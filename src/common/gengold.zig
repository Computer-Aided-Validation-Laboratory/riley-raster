const std = @import("std");

pub const MatSlice = @import("../zraster/zig/matslice.zig").MatSlice;
pub const NDArray = @import("../zraster/zig/ndarray.zig").NDArray;
pub const meshio = @import("../zraster/zig/meshio.zig");
pub const SimData = meshio.SimData;
pub const mr = @import("../zraster/zig/meshraster.zig");
pub const MeshType = mr.MeshType;
pub const MeshInput = mr.MeshInput;
pub const Rotation = @import("../zraster/zig/camera.zig").Rotation;
pub const Camera = @import("../zraster/zig/camera.zig").Camera;
pub const CameraOps = @import("../zraster/zig/camera.zig").CameraOps;
pub const zraster = @import("../zraster/zig/zraster.zig");
pub const RasterConfig = zraster.RasterConfig;
pub const iio = @import("../zraster/zig/imageio.zig");
pub const texops = @import("../zraster/zig/textureops.zig");
pub const uvio = @import("../zraster/zig/uvio.zig");

pub fn loadData(outer_alloc: std.mem.Allocator, io: std.Io, path: []const u8) !SimData {
    const pc = try std.fmt.allocPrint(outer_alloc, "{s}/coords.csv", .{path});
    const pn = try std.fmt.allocPrint(outer_alloc, "{s}/connectivity.csv", .{path});
    const pf = [_][]const u8{
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_x.csv", .{path}),
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_y.csv", .{path}),
        try std.fmt.allocPrint(outer_alloc, "{s}/field_disp_z.csv", .{path}),
    };
    return try meshio.loadSimData(outer_alloc, io, pc, pn, pf[0..], null);
}

pub fn renderAndSave(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    mt: MeshType,
    coords: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    sh: mr.ShaderInput,
    dir: []const u8,
    add_disp: bool,
    config: RasterConfig,
) !void {
    const cwd = std.Io.Dir.cwd();
    // Manual recursive directory creation since makePath isn't in std.Io.Dir
    var iter = std.mem.splitScalar(u8, dir, '/');
    var path_buf: [256]u8 = undefined;
    var path_len: usize = 0;
    while (iter.next()) |part| {
        if (path_len > 0) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        std.mem.copyForwards(u8, path_buf[path_len..], part);
        path_len += part.len;
        cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
    var out_dir = try cwd.openDir(io, dir, .{});
    defer out_dir.close(io);

    const mesh_input = MeshInput{
        .mesh_type = mt,
        .coords = coords,
        .connect = connect,
        .disp = if (add_disp) disp else null,
        .shader = sh,
    };

    const meshes = &[_]MeshInput{mesh_input};
    _ = try zraster.rasterAllFrames(outer_alloc, io, camera, meshes, config, out_dir);
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
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const suffix = if (std.mem.eql(u8, test_type, "full"))
        "fullscreen"
    else if (std.mem.eql(u8, test_type, "single"))
        "single"
    else
        test_type;
    for (mesh_types) |mt| {
        _ = arena.reset(.free_all);
        const data_name = switch (mt) {
            .quad4ibi, .quad4newton => "quad4",
            else => @tagName(mt),
        };
        const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
        const data_path = try std.fmt.allocPrint(
            aa,
            "{s}/{s}",
            .{ data_dir_root, case_name },
        );

        var sim_data = loadData(aa, io, data_path) catch |err| {
            std.debug.print("Failed to load data for {s}: {any}\n", .{ case_name, err });
            continue;
        };
        const uv_p = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
        var uvs = try uvio.loadUVMap(aa, io, uv_p);

        const cam_pos = CameraOps.posFillFrameFromRot(
            &sim_data.coords,
            pixel_num,
            pixel_size,
            focal_leng,
            rot,
            fov_scale,
        );
        const camera = Camera.init(
            pixel_num,
            pixel_size,
            cam_pos,
            rot,
            CameraOps.roiCentFromCoords(&sim_data.coords),
            focal_leng,
            2,
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
            try renderAndSave(aa, io, &camera, mt, sim_data.coords, sim_data.connect, sim_data.field, .{
                .nodal = .{ .field = sim_data.field.?, .bits = 8 },
            }, nodal_dir, add_disp, config);

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
                try renderAndSave(aa, io, &camera, mt, sim_data.coords, sim_data.connect, sim_data.field, .{
                    .tex = .{
                        .uvs = uvs.array,
                        .texture = texture,
                        .sample_config = sc,
                    },
                }, tex_dir, add_disp, config);
            }
        }
    }
}

pub fn runMultimeshGeneration(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };
    try runMultimeshGenerationExt(
        outer_alloc,
        io,
        config,
        "gold-multimesh",
        &dir_paths,
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

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const shader_modes = [_]enum { nodal, texture }{ .nodal, .texture };

    for (shader_modes) |mode| {
        _ = arena.reset(.free_all);
        const sim_datas = try meshio.loadMultiSimData(aa, io, dir_paths, .{});


        const gold_dir = if (mode == .nodal)
            try std.fmt.allocPrint(aa, "{s}/allelem_nodal", .{out_dir_root})
        else
            try std.fmt.allocPrint(aa, "{s}/allelem_tex_cubic_lut_lerp", .{out_dir_root});

        const mesh_inputs = if (mode == .nodal)
            try mr.meshInputFromSimDataSlice(
                aa,
                io,
                sim_datas,
                &mesh_types,
                .nodal,
                null,
                null,
                null,
            )
        else
            try mr.meshInputFromSimDataSlice(
                aa,
                io,
                sim_datas,
                &mesh_types,
                .texture,
                dir_paths,
                "texture/speckle-simple.tiff",
                null,
            );

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.1, 0.1, 0.0 }, .{ 3, 2, 1 });

        const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
        const focal_leng: f64 = 50.0e-3;
        const rot = Rotation.init(0, 0, 0);
        const fov_scale_factor: f64 = 1.1;

        const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
        const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
            mesh_inputs,
            pixel_num,
            pixel_size,
            focal_leng,
            rot,
            fov_scale_factor,
        );
        const camera = Camera.init(
            pixel_num,
            pixel_size,
            cam_pos,
            rot,
            roi_pos,
            focal_leng,
            2,
        );

        const cwd = std.Io.Dir.cwd();
        var iter = std.mem.splitScalar(u8, gold_dir, '/');
        var path_buf: [256]u8 = undefined;
        var path_len: usize = 0;
        while (iter.next()) |part| {
            if (path_len > 0) {
                path_buf[path_len] = '/';
                path_len += 1;
            }
            std.mem.copyForwards(u8, path_buf[path_len..], part);
            path_len += part.len;
            cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };
        }
        var out_dir = try cwd.openDir(io, gold_dir, .{});
        defer out_dir.close(io);

        std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
        _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_inputs, config, out_dir);
    }
}

pub fn runMultimeshMixedGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };
    try runMultimeshMixedGenerationExt(
        allocator,
        io,
        config,
        "gold-multimesh/allelem_allshade",
        &dir_paths,
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

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const sim_datas = try meshio.loadMultiSimData(aa, io, dir_paths, .{});

    const texture = try iio.loadImage(
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
        u8,
        1,
    );

    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Nodal Shading
    for (0..5) |ii| {
        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = sim_datas[ii].field.?,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    // Bottom Row (5-9): Texture Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex = .{
                .uvs = uvs.array,
                .texture = texture,
                .sample_config = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );
    const cwd = std.Io.Dir.cwd();
    var iter = std.mem.splitScalar(u8, gold_dir, '/');
    var path_buf: [256]u8 = undefined;
    var path_len: usize = 0;
    while (iter.next()) |part| {
        if (path_len > 0) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        std.mem.copyForwards(u8, path_buf[path_len..], part);
        path_len += part.len;
        cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
    var out_dir = try cwd.openDir(io, gold_dir, .{});
    defer out_dir.close(io);

    std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
    _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_inputs, config, out_dir);
}

pub fn runMultimeshMixedRGBGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    config: RasterConfig,
) !void {
    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };
    try runMultimeshMixedRGBGenerationExt(
        allocator,
        io,
        config,
        "gold-multimesh/allelem_allshade_rgb",
        &dir_paths,
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

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const sim_datas = try meshio.loadMultiSimData(aa, io, dir_paths, .{});

    const texture = try iio.loadImage(
        aa,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
        u8,
        3,
    );

    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Texture RGB Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_rgb = .{
                .uvs = uvs.array,
                .texture = texture,
                .sample_config = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    // Bottom Row (5-9): Nodal RGB Shading with Gradient
    for (0..5) |ii| {
        const field = sim_datas[ii].field.?;
        const num_coords = sim_datas[ii].coords.mat.rows_num;
        var rgb_field_arr = try NDArray(f64).initFlat(
            aa,
            &[_]usize{ field.array.dims[0], num_coords, 3 },
        );

        const coords = sim_datas[ii].coords;
        var min_x: f64 = std.math.inf(f64);
        var max_x: f64 = -std.math.inf(f64);
        for (0..num_coords) |nn| {
            const x_val = coords.x(nn);
            if (x_val < min_x) min_x = x_val;
            if (x_val > max_x) max_x = x_val;
        }
        const range_x = max_x - min_x;

        for (0..field.array.dims[0]) |tt| {
            for (0..num_coords) |nn| {
                const x_val = coords.x(nn);
                const t = if (range_x > 0) (x_val - min_x) / range_x else 0.5;

                var rr: f64 = 0;
                var gg: f64 = 0;
                var bb: f64 = 0;

                if (t < 0.5) {
                    const t_scaled = t * 2.0;
                    rr = 1.0 - t_scaled;
                    gg = t_scaled;
                    bb = 0.0;
                } else {
                    const t_scaled = (t - 0.5) * 2.0;
                    rr = 0.0;
                    gg = 1.0 - t_scaled;
                    bb = t_scaled;
                }

                rgb_field_arr.set(&[_]usize{ tt, nn, 0 }, rr);
                rgb_field_arr.set(&[_]usize{ tt, nn, 1 }, gg);
                rgb_field_arr.set(&[_]usize{ tt, nn, 2 }, bb);
            }
        }

        const rgb_field = meshio.Field{
            .array = rgb_field_arr,
            .array_mem = rgb_field_arr.slice,
        };

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.1;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera_rgb = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );

    var config_rgb = config;
    if (config_rgb.save_opts.len == 0) {
        config_rgb.save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
            .{ .format = .fimg, .bits = null, .scaling = .none, .channels = 3 },
        };
    } else {
        // If save_opts are provided, ensure they use 3 channels for RGB
        const opts_rgb = try aa.alloc(iio.ImageSaveOpts, config_rgb.save_opts.len);
        for (config_rgb.save_opts, 0..) |opt, ii| {
            opts_rgb[ii] = opt;
            opts_rgb[ii].channels = 3;
        }
        config_rgb.save_opts = opts_rgb;
    }

    const cwd = std.Io.Dir.cwd();
    var iter = std.mem.splitScalar(u8, gold_dir, '/');
    var path_buf: [256]u8 = undefined;
    var path_len: usize = 0;
    while (iter.next()) |part| {
        if (path_len > 0) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        std.mem.copyForwards(u8, path_buf[path_len..], part);
        path_len += part.len;
        cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
    var out_dir = try cwd.openDir(io, gold_dir, .{});
    defer out_dir.close(io);

    std.debug.print("Generating Multimesh Gold Data for {s}...\n", .{gold_dir});
    _ = try zraster.rasterAllFrames(
        aa,
        io,
        &camera_rgb,
        mesh_inputs,
        config_rgb,
        out_dir,
    );
}
