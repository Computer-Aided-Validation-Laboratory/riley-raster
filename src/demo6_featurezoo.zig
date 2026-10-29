// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const demo_common = @import("demo_common.zig");

const buildconfig = @import("riley/zig/buildconfig.zig");
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const riley = @import("riley/zig/riley.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const sceneops = @import("riley/zig/sceneops.zig");
const shaderops = @import("riley/zig/shaderops_common.zig");
const texops = @import("riley/zig/textureops.zig");
const uvio = @import("riley/zig/uvio.zig");

const F = buildconfig.F;
const MeshInput = meshpipe.MeshInput;

const MeshShape = struct {
    shape: []const u8,
    elem: []const u8,
    mesh_type: gk.MeshType,
};

const DemoOptions = struct {
    out_dir_root: []const u8,
    pixel_size: [2]F,
    focal_length: F,
    mesh_shapes: []const MeshShape,
    mesh_centers: []const [3]F,
};

fn buildRgbField(
    allocator: std.mem.Allocator,
    temp: meshio.Field,
    disp: meshio.Field,
) !meshio.Field {
    const time_n = temp.getTimeN();
    const node_n = temp.getCoordN();
    var field = try meshio.Field.initAlloc(allocator, time_n, node_n, 3);
    for (0..time_n) |tt| {
        for (0..node_n) |nn| {
            field.array.set(&.{ tt, nn, 0 }, temp.array.get(&.{ tt, nn, 0 }));
            field.array.set(&.{ tt, nn, 1 }, disp.array.get(&.{ tt, nn, 0 }));
            field.array.set(&.{ tt, nn, 2 }, disp.array.get(&.{ tt, nn, 1 }));
        }
    }
    return field;
}

fn textureShader(
    comptime T: type,
    comptime C: usize,
    texture: texops.Tex(T, C),
    uvs: uvio.UVMap,
    comptime bits: u8,
    linear: bool,
    normal_type: shaderops.NormalType,
) shaderops.ShaderInput {
    const samp_cfg = texops.TexSampConfig{
        .sample = if (linear) .linear else .cubic_catmull_rom,
        .mode = if (linear) .direct else .lut_lerp,
    };
    const input = shaderops.TexInput(T, C){
        .uvs = uvs.array,
        .tex = texture,
        .samp_cfg = samp_cfg,
        .bits = bits,
        .scaling = .auto,
        .normal_type = normal_type,
    };
    if (C == 1 and T == u8) return .{ .tex_u8 = input };
    if (C == 1 and T == u16) return .{ .tex_u16 = input };
    if (C == 3 and T == u8) return .{ .tex_rgb_u8 = input };
    if (C == 3 and T == u16) return .{ .tex_rgb_u16 = input };
    unreachable;
}

fn loadMesh(
    comptime T: type,
    comptime C: usize,
    comptime bits: u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_shape: MeshShape,
    mesh_index: usize,
    texture: texops.Tex(T, C),
) !MeshInput {
    const dir = try std.fmt.allocPrint(
        allocator,
        "data/shapes/{s}/{s}/",
        .{ mesh_shape.shape, mesh_shape.elem },
    );

    const temp_files = &[_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}temperature.csv", .{dir}),
    };

    const disp_files = &[_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}disp_x.csv", .{dir}),
        try std.fmt.allocPrint(allocator, "{s}disp_y.csv", .{dir}),
        try std.fmt.allocPrint(allocator, "{s}disp_z.csv", .{dir}),
    };

    const sim = try meshio.loadSimData(
        allocator,
        io,
        try std.fmt.allocPrint(allocator, "{s}coords.csv", .{dir}),
        try std.fmt.allocPrint(allocator, "{s}connect.csv", .{dir}),
        temp_files,
        disp_files,
    );
    const uvs = try uvio.loadUVMap(
        allocator,
        io,
        try std.fmt.allocPrint(allocator, "{s}uvs.csv", .{dir}),
    );

    const temp = sim.field orelse return error.MissingTemperature;
    const disp = sim.disp orelse return error.MissingDisplacement;
    const normal_type: shaderops.NormalType = switch (mesh_index % 3) {
        0 => .none,
        1 => .exact,
        else => .avg,
    };

    const shader: shaderops.ShaderInput = switch (mesh_index) {
        0, 2 => textureShader(
            T,
            C,
            texture,
            uvs,
            bits,
            mesh_index != 0,
            normal_type,
        ),
        1, 5 => blk: {
            const field = if (C == 1)
                temp
            else
                try buildRgbField(allocator, temp, disp);
            break :blk .{ .nodal = .{
                .field = field,
                .bits = bits,
                .scaling = .auto,
                .scale_over = if (mesh_index == 1)
                    .over_frames
                else
                    .within_frames,
                .normal_type = normal_type,
            } };
        },
        3, 4 => blk: {
            const params = if (mesh_index == 3)
                shaderops.FuncShaderParams{
                    .coord_scale = .{ 1000.0, 1000.0 },
                    .settings = .{ .checker = .{} },
                }
            else
                shaderops.FuncShaderParams{
                    .coord_scale = .{ 1.0, 1.0 },
                    .settings = .{ .eggbox = .{
                        .pitch = .{ 0.005, 0.005 },
                    } },
                };
            const input = shaderops.FuncInput{
                .coord_mode = if (mesh_index == 3)
                    .world_reference
                else
                    .world_deformed,
                .builtin = if (mesh_index == 3) .checker else .eggbox,
                .params = params,
                .bits = bits,
                .scaling = .auto,
                .normal_type = normal_type,
            };
            break :blk if (C == 1)
                .{ .func = input }
            else
                .{ .func_rgb = input };
        },
        else => unreachable,
    };
    return .{
        .mesh_type = mesh_shape.mesh_type,
        .coords = sim.coords,
        .connect = sim.connect,
        .disp = if (mesh_index % 2 == 1) disp else null,
        .shader = shader,
    };
}

fn buildScene(
    comptime T: type,
    comptime C: usize,
    comptime bits: u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    texture: texops.Tex(T, C),
    options: DemoOptions,
) ![]MeshInput {
    var meshes = std.ArrayList(MeshInput).empty;
    var groups = std.ArrayList(sceneops.MeshGroup).empty;
    for (options.mesh_shapes, 0..) |mesh_shape, mesh_index| {
        try meshes.append(
            allocator,
            try loadMesh(T, C, bits, allocator, io, mesh_shape, mesh_index, texture),
        );
        try groups.append(allocator, sceneops.meshGroupSingle(mesh_index));
    }
    const plate = &meshes.items[5];
    for (0..plate.coords.mat.rows_num) |node| {
        const x = plate.coords.mat.get(node, 0);
        const y = plate.coords.mat.get(node, 1);
        plate.coords.mat.set(node, 0, -y);
        plate.coords.mat.set(node, 1, x);
    }
    for (groups.items, options.mesh_centers) |group, center| {
        sceneops.centerMeshGroupAt(meshes.items, group, center);
    }
    return try meshes.toOwnedSlice(allocator);
}

fn makeCamera(
    meshes: []MeshInput,
    options: DemoOptions,
    pixels_num: [2]u32,
    rot: Rotation,
    sub_sample: u32,
    distort: camera.DistortParams,
    psf: camera.PointSpreadFunc,
) camera.CameraInput {
    const target = sceneops.boundsCenterOverMeshes(meshes);
    return .{
        .pixels_num = pixels_num,
        .pixels_size = options.pixel_size,
        .pos_world = cameraops.posFillFrameFromRotOverMeshesAndTarg(
            meshes,
            target,
            pixels_num,
            options.pixel_size,
            options.focal_length,
            rot,
            1.1,
        ),
        .rot_world = rot,
        .roi_cent_world = target,
        .focal_length = options.focal_length,
        .sub_sample = sub_sample,
        .distort = distort,
        .psf = psf,
    };
}

fn buildCameras(meshes: []MeshInput, options: DemoOptions) [6]camera.CameraInput {
    const deg = std.math.degreesToRadians;
    const brown: camera.DistortParams = .{ .brown_con = .{
        .k1 = -0.12,
        .k2 = 0.035,
        .p1 = 0.0002,
        .p2 = -0.0001,
    } };
    const gaussian: camera.PointSpreadFunc = .{ .gaussian = .{
        .sigma_px = 0.65,
        .supp_rad_px = 2.0,
    } };
    return .{
        makeCamera(
            meshes,
            options,
            .{ 1024, 1024 },
            Rotation.init(0, 0, 0),
            1,
            .none,
            .{ .pixel_box = .{} },
        ),
        makeCamera(
            meshes,
            options,
            .{ 1024, 1024 },
            Rotation.init(0, deg(25.0), 0),
            4,
            brown,
            .{ .pixel_box = .{} },
        ),
        makeCamera(
            meshes,
            options,
            .{ 1024, 1229 },
            Rotation.init(0, deg(-28.0), 0),
            4,
            .none,
            gaussian,
        ),
        makeCamera(
            meshes,
            options,
            .{ 1229, 1024 },
            Rotation.init(deg(90.0), deg(25.0), 0),
            4,
            brown,
            gaussian,
        ),
        makeCamera(
            meshes,
            options,
            .{ 1024, 1024 },
            Rotation.init(deg(18.0), deg(38.0), deg(26.0)),
            4,
            .none,
            .{ .anisotropic_gaussian = .{
                .sigma_x_px = 0.55,
                .sigma_y_px = 0.9,
                .theta_rad = deg(25.0),
                .supp_rad_px = 2.5,
            } },
        ),
        makeCamera(
            meshes,
            options,
            .{ 1229, 1024 },
            Rotation.init(deg(-90.0), deg(-20.0), deg(5.0)),
            4,
            brown,
            .{ .pixel_box = .{} },
        ),
    };
}

fn renderCase(
    comptime T: type,
    comptime C: usize,
    comptime bits: u8,
    local_alloc: std.mem.Allocator,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    texture_path: []const u8,
    case_name: []const u8,
    options: DemoOptions,
) !void {
    // -------------------------------------------------------------------------
    // 1. Build scene meshes and cameras
    // -------------------------------------------------------------------------
    const texture: texops.Tex(T, C) = if (T == u16 and C == 3) blk: {
        const tex_u8 = try iio.loadImage(
            u8,
            3,
            local_alloc,
            io,
            "texture/speck128_rgb_u8.bmp",
            .bmp,
        );
        defer tex_u8.deinit(local_alloc);

        var tex_u16 = try texops.Tex(u16, 3).init(
            local_alloc,
            tex_u8.rows_num,
            tex_u8.cols_num,
        );
        for (0..tex_u8.array.slice.len) |ii| {
            tex_u16.array.slice[ii] = @as(u16, tex_u8.array.slice[ii]) * 257;
        }
        break :blk tex_u16;
    } else blk: {
        break :blk try iio.loadImage(
            T,
            C,
            local_alloc,
            io,
            texture_path,
            if (T == u8) .bmp else .tiff,
        );
    };
    defer texture.deinit(local_alloc);

    const meshes = try buildScene(T, C, bits, local_alloc, io, texture, options);

    const cameras = buildCameras(meshes, options);

    // -------------------------------------------------------------------------
    // 2. Configure raster settings and output directory
    // -------------------------------------------------------------------------
    const out_dir = try std.fs.path.join(
        local_alloc,
        &.{ options.out_dir_root, case_name },
    );

    const config = riley.RasterConfig{
        .render_mode = .offline,
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .background_value = 0.5 * (@as(F, @floatFromInt((@as(u32, 1) << bits) - 1))),
        .output = .{
            .image_save_mode = if (C == 1) .grey else .rgb,
            .image_save_opts = &.{
                .{
                    .format = if (bits == 8) .bmp else .tiff,
                    .bits = bits,
                    .scaling = .none,
                },
            },
        },
    };

    // -------------------------------------------------------------------------
    // 3. Render the multi-mesh multi-camera case
    // -------------------------------------------------------------------------
    const images = try riley.raster(
        outer_alloc,
        io,
        &cameras,
        meshes,
        config,
        out_dir,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        var img_mut = img;
        img_mut.deinit(outer_alloc);
    }
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();
    const io = init.io;

    const out_dir_root = "./out/demo6_featurezoo";

    const pixel_size = [2]F{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50.0e-3;

    const mesh_shapes = [_]MeshShape{
        .{ .shape = "cube_surf", .elem = "quad9", .mesh_type = .quad9 },
        .{ .shape = "cube_surf", .elem = "tri6", .mesh_type = .tri6 },
        .{ .shape = "cylinder_surf", .elem = "quad8", .mesh_type = .quad8 },
        .{ .shape = "cylinder_surf", .elem = "tri6", .mesh_type = .tri6 },
        .{ .shape = "platewithhole_surf", .elem = "quad4", .mesh_type = .quad4 },
        .{ .shape = "platewithhole_surf", .elem = "tri3", .mesh_type = .tri3 },
    };

    const mesh_centers = [mesh_shapes.len][3]F{
        .{ -0.015, 0.0075, 0.0 },
        .{ 0.0, 0.0075, 0.0 },
        .{ 0.015, 0.0075, 0.0 },
        .{ -0.015, -0.0075, 0.0 },
        .{ 0.0, -0.0075, 0.0 },
        .{ 0.015, -0.0075, 0.0 },
    };

    const options = DemoOptions{
        .out_dir_root = out_dir_root,
        .pixel_size = pixel_size,
        .focal_length = focal_length,
        .mesh_shapes = &mesh_shapes,
        .mesh_centers = &mesh_centers,
    };
    
    // -------------------------------------------------------------------------
    // Clean output root and render all combinations
    // -------------------------------------------------------------------------
    var output_root = try demo_common.resetOutputDir(io, out_dir_root);
    defer output_root.close(io);

    try renderCase(
        u8,
        1,
        8,
        local_alloc,
        init.gpa,
        io,
        "texture/speck128_mono_u8.bmp",
        "mono-u8",
        options,
    );

    try renderCase(
        u16,
        1,
        16,
        local_alloc,
        init.gpa,
        io,
        "texture/speck128_mono_u16.tiff",
        "mono-u16",
        options,
    );

    try renderCase(
        u8,
        3,
        8,
        local_alloc,
        init.gpa,
        io,
        "texture/speck128_rgb_u8.bmp",
        "rgb-u8",
        options,
    );

    try renderCase(
        u16,
        3,
        16,
        local_alloc,
        init.gpa,
        io,
        "texture/speck128_rgb_u8.bmp",
        "rgb-u16",
        options,
    );
}
