// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const orch = @import("orchestration.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const mo = @import("../zraster/zig/meshops.zig");
const MeshType = mo.MeshType;
const MeshInput = mo.MeshInput;
const Camera = @import("../zraster/zig/camera.zig").Camera;
const CameraInput = @import("../zraster/zig/camera.zig").CameraInput;
const zraster = @import("../zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;
const iio = @import("../zraster/zig/imageio.zig");
const texops = @import("../zraster/zig/textureops.zig");

pub fn renderAndSave(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    mt: MeshType,
    coords: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    sh: mo.ShaderInput,
    dir: []const u8,
    add_disp: bool,
    config: RasterConfig,
) !void {
    const mesh_input = MeshInput{
        .mesh_type = mt,
        .coords = coords,
        .connect = connect,
        .disp = if (add_disp) disp else null,
        .shader = sh,
    };

    const meshes = &[_]MeshInput{mesh_input};
    const camera_input = camera.toInput();
    const images = try zraster.rasterAllFrames(
        outer_alloc,
        io,
        &[_]CameraInput{camera_input},
        meshes,
        config,
        dir,
        null,
    );
    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }
}

pub fn runGenerationExt(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    test_type: []const u8,
    mesh_types: []const MeshType,
    fov_scale: f64,
    texture: iio.Texture(1),
    pixel_num: [2]u32,
    sample_configs: []const texops.TextureSampleConfig,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    config: RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    for (mesh_types) |mt| {
        _ = arena.reset(.free_all);
        const prepared = try orch.prepareSingleMeshCase(
            aa,
            io,
            test_type,
            mt,
            pixel_num,
            fov_scale,
            data_dir_root,
        );

        const disps = [_]bool{ true, false };
        for (disps) |add_disp| {
            const d_str = if (add_disp) "dispon" else "dispoff";

            // Nodal ShaderInput
            const nodal_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_nodal", .{
                gold_dir_root,
                test_type,
                @tagName(mt),
                d_str,
            });
            try renderAndSave(
                aa,
                io,
                &prepared.camera,
                mt,
                prepared.sim_data.coords,
                prepared.sim_data.connect,
                prepared.sim_data.field,
                .{
                    .nodal = .{
                        .field = prepared.sim_data.field.?,
                        .bits = 8,
                    },
                },
                nodal_dir,
                add_disp,
                config,
            );

            // Tex ShaderInput
            for (sample_configs) |sc| {
                const tex_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_tex_{s}_{s}", .{
                    gold_dir_root,
                    test_type,
                    @tagName(mt),
                    d_str,
                    @tagName(sc.sample),
                    @tagName(sc.mode),
                });
                try renderAndSave(
                    aa,
                    io,
                    &prepared.camera,
                    mt,
                    prepared.sim_data.coords,
                    prepared.sim_data.connect,
                    prepared.sim_data.field,
                    .{
                        .tex = .{
                            .uvs = prepared.uvs.array,
                            .texture = texture,
                            .sample_config = sc,
                        },
                    },
                    tex_dir,
                    add_disp,
                    config,
                );
            }
        }
    }
}

pub fn runMultimeshGeneration(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    try runMultimeshGenerationExt(
        outer_alloc,
        io,
        config,
        "gold-multimesh",
        &orch.default_multimesh_dir_paths,
        .{ 1200, 800 },
    );
}

pub fn runMultimeshGenerationExt(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
    out_dir_root: []const u8,
    dir_paths: []const []const u8,
    pixel_num: [2]u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const shader_modes = [_]enum { nodal, texture }{ .nodal, .texture };

    for (shader_modes) |mode| {
        _ = arena.reset(.free_all);
        const gold_dir = if (mode == .nodal)
            try std.fmt.allocPrint(aa, "{s}/allelem_nodal", .{out_dir_root})
        else
            try std.fmt.allocPrint(aa, "{s}/allelem_tex_cubic_lut_lerp", .{out_dir_root});

        const mesh_inputs = try orch.buildMultimeshInputs(
            aa,
            io,
            dir_paths,
            if (mode == .nodal) .nodal else .texture,
        );

        const fov_scale_factor: f64 = 1.1;
        const camera = try orch.initCameraForMeshes(
            aa,
            mesh_inputs,
            pixel_num,
            fov_scale_factor,
        );
        defer camera.deinit(aa);

        std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
        const camera_input = camera.toInput();
        const images = try zraster.rasterAllFrames(
            aa,
            io,
            &[_]CameraInput{camera_input},
            mesh_inputs,
            config,
            gold_dir,
            null,
        );
        if (images) |img| {
            aa.free(img.slice);
            img.deinit(aa);
        }
    }
}

pub fn runMultimeshMixedGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    try runMultimeshMixedGenerationExt(
        allocator,
        io,
        config,
        "gold-multimesh/allelem_allshade",
        &orch.default_multimesh_dir_paths,
        .{ 1600, 800 },
    );
}

pub fn runMultimeshMixedGenerationExt(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
    gold_dir: []const u8,
    dir_paths: []const []const u8,
    pixel_num: [2]u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    const mesh_inputs = try orch.buildMixedMeshInputs(
        aa,
        io,
        dir_paths,
        texture,
    );

    const fov_scale_factor: f64 = 1.2;
    const camera = try orch.initCameraForMeshes(
        aa,
        mesh_inputs,
        pixel_num,
        fov_scale_factor,
    );
    defer camera.deinit(aa);

    std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
    const camera_input = camera.toInput();
    const images = try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{camera_input},
        mesh_inputs,
        config,
        gold_dir,
        null,
    );
    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }
}

pub fn runMultimeshMixedRGBGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    try runMultimeshMixedRGBGenerationExt(
        allocator,
        io,
        config,
        "gold-multimesh/allelem_allshade_rgb",
        &orch.default_multimesh_dir_paths,
        .{ 1200, 800 },
    );
}

pub fn runMultimeshMixedRGBGenerationExt(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
    gold_dir: []const u8,
    dir_paths: []const []const u8,
    pixel_num: [2]u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture = try iio.loadImage(
        u8,
        3,
        aa,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );

    const mesh_inputs = try orch.buildMixedRgbMeshInputs(
        aa,
        io,
        dir_paths,
        texture,
    );

    const fov_scale_factor: f64 = 1.1;
    const camera_rgb = try orch.initCameraForMeshes(
        aa,
        mesh_inputs,
        pixel_num,
        fov_scale_factor,
    );
    defer camera_rgb.deinit(aa);

    var config_rgb = config;
    if (config_rgb.image_save_opts.len == 0) {
        config_rgb.image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
            .{ .format = .fimg, .bits = null, .scaling = .none, .channels = 3 },
        };
    } else {
        // If save_opts are provided, ensure they use 3 channels for RGB
        const opts_rgb = try aa.alloc(iio.ImageSaveOpts, config_rgb.image_save_opts.len);
        for (config_rgb.image_save_opts, 0..) |opt, ii| {
            opts_rgb[ii] = opt;
            opts_rgb[ii].channels = 3;
        }
        config_rgb.image_save_opts = opts_rgb;
    }

    std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
    const camera_input = camera_rgb.toInput();
    _ = try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{camera_input},
        mesh_inputs,
        config_rgb,
        gold_dir,
        null,
    );
}
