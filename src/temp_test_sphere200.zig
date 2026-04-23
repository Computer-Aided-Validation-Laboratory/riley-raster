// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const tcfg = @import("common/testconfig.zig");
const testcommon = @import("common/tests.zig");
const zraster = @import("zraster/zig/zraster.zig");
const csvio = @import("zraster/zig/csvio.zig");
const iio = @import("zraster/zig/imageio.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const texops = @import("zraster/zig/textureops.zig");
const uvio = @import("zraster/zig/uvio.zig");
const CameraPrepared = @import("zraster/zig/camera.zig").CameraPrepared;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;
const Rotation = @import("zraster/zig/camera.zig").Rotation;
const NDArray = @import("zraster/zig/ndarray.zig").NDArray;

const simd_on = buildconfig.config.simd == .on;
const impl_suffix = if (simd_on) "_simd" else "_scalar";
const gold_dir = if (simd_on) "gold-simd-sphere2000" else "gold-sphere2000";

const ShaderType = enum {
    nodal_grey,
    nodal_rgb,
    tex8_grey,
    tex8_rgb,
};

fn shouldRun(
    shader_type: ShaderType,
    sample_config: texops.TextureSampleConfig,
) bool {
    const is_tex = switch (shader_type) {
        .tex8_grey, .tex8_rgb => true,
        else => false,
    };

    if (!is_tex) {
        return sample_config.sample == .linear and sample_config.mode == .direct;
    }

    return true;
}

fn loadFieldTimeSeries(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    requested_channels: usize,
) !meshio.Field {
    var field_2d = try csvio.loadScalarCsv2D(allocator, io, path);
    defer {
        allocator.free(field_2d.slice);
        field_2d.deinit(allocator);
    }

    if (field_2d.dims[1] < requested_channels) {
        return error.ChannelMismatch;
    }

    var field = try meshio.Field.initAlloc(
        allocator,
        1,
        field_2d.dims[0],
        @intCast(requested_channels),
    );

    for (0..field_2d.dims[0]) |rr| {
        for (0..requested_channels) |cc| {
            field.array.set(
                &[_]usize{ 0, rr, cc },
                field_2d.get(&[_]usize{ rr, cc }),
            );
        }
    }

    return field;
}

fn initCameraForCoords(
    allocator: std.mem.Allocator,
    coords: *const meshio.Coords,
    pixel_num: [2]u32,
) !CameraPrepared {
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_length: f64 = 50.0e-3;
    const rot = Rotation.init(0.0, 0.0, 0.0);
    const cam_pos = CameraOps.posFillFrameFromRot(
        coords,
        pixel_num,
        pixel_size,
        focal_length,
        rot,
        1.0,
    );

    return try CameraPrepared.init(
        allocator,
        .{
            .pixels_num = pixel_num,
            .pixels_size = pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = CameraOps.roiCentFromCoords(coords),
            .focal_length = focal_length,
            .sub_sample = 2,
        },
    );
}

fn goldDirExists(io: std.Io, path: []const u8) bool {
    const cwd = std.Io.Dir.cwd();
    var gold_handle = cwd.openDir(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    gold_handle.close(io);
    return true;
}

fn runSphereCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: mo.MeshType,
    shader_type: ShaderType,
    sample_config: texops.TextureSampleConfig,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) !bool {
    const pixel_num = [_]u32{ 800, 500 };
    const data_dir = try std.fmt.allocPrint(
        allocator,
        "data-bench/{s}_sphere2000",
        .{@tagName(mesh_type)},
    );
    defer allocator.free(data_dir);

    const coord_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "coords.csv" },
    );
    defer allocator.free(coord_path);
    const conn_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "connect.csv" },
    );
    defer allocator.free(conn_path);
    const field_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "field.csv" },
    );
    defer allocator.free(field_path);
    const uv_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "uvs.csv" },
    );
    defer allocator.free(uv_path);

    var sim_data = try meshio.loadSimData(
        allocator,
        io,
        coord_path,
        conn_path,
        null,
        null,
    );
    defer sim_data.deinit(allocator);

    const field_channels: usize = switch (shader_type) {
        .nodal_rgb => 3,
        else => 1,
    };
    var field = try loadFieldTimeSeries(allocator, io, field_path, field_channels);
    defer field.deinit(allocator);

    var uvs = try uvio.loadUVMap(allocator, io, uv_path);
    defer uvs.deinit(allocator);

    var camera = try initCameraForCoords(allocator, &sim_data.coords, pixel_num);
    defer camera.deinit(allocator);

    const shader: mo.ShaderInput = switch (shader_type) {
        .nodal_grey, .nodal_rgb => .{ .nodal = .{
            .field = field,
            .scaling = .none,
        } },
        .tex8_grey => .{ .tex = .{
            .uvs = uvs.array,
            .texture = texture_grey,
            .sample_config = sample_config,
        } },
        .tex8_rgb => .{ .tex_rgb = .{
            .uvs = uvs.array,
            .texture = texture_rgb,
            .sample_config = sample_config,
        } },
    };

    const mesh_input = mo.MeshInput{
        .mesh_type = mesh_type,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = shader,
    };

    const config = zraster.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = tcfg.TOTAL_THREADS,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = tcfg.MAX_GEOM_THREADS_PER_FRAME,
        .max_raster_threads_per_frame = tcfg.MAX_RASTER_THREADS_PER_FRAME,
        .save_strategy = .memory,
        .report = .off,
    };

    const camera_input = camera.toInput();
    const result = (try zraster.rasterAllFrames(
        allocator,
        io,
        &[_]@TypeOf(camera_input){camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer {
        allocator.free(result.slice);
        var result_mut = result;
        result_mut.deinit(allocator);
    }

    const is_rgb = switch (shader_type) {
        .nodal_rgb, .tex8_rgb => true,
        else => false,
    };
    const channels: usize = if (is_rgb) 3 else 1;

    const gold_mesh_name = if (mesh_type == .quad4ibi)
        "quad4newton"
    else
        @tagName(mesh_type);
    const gold_case_name = if (shader_type == .tex8_grey or
        shader_type == .tex8_rgb)
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}_{s}",
            .{
                gold_mesh_name,
                @tagName(shader_type),
                @tagName(sample_config.sample),
                @tagName(sample_config.mode),
            },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ gold_mesh_name, @tagName(shader_type) },
        );
    defer allocator.free(gold_case_name);

    const gold_case_dir = try std.fs.path.join(
        allocator,
        &[_][]const u8{ gold_dir, gold_case_name },
    );
    defer allocator.free(gold_case_dir);

    const gold_path = try testcommon.findGoldPath(
        allocator,
        io,
        gold_case_dir,
        0,
        0,
        0,
        is_rgb,
    );
    defer allocator.free(gold_path);

    testcommon.compareNDArrayToGold(
        allocator,
        io,
        &result,
        0,
        0,
        0,
        channels,
        gold_path,
        tcfg.REL_TOL,
        tcfg.ABS_TOL,
    ) catch |err| {
        const fail_dir_name = if (shader_type == .tex8_grey or
            shader_type == .tex8_rgb)
            try std.fmt.allocPrint(
                allocator,
                "temp_sphere2000_{s}_{s}_{s}_{s}_thr{d}{s}",
                .{
                    @tagName(mesh_type),
                    @tagName(shader_type),
                    @tagName(sample_config.sample),
                    @tagName(sample_config.mode),
                    tcfg.TOTAL_THREADS,
                    impl_suffix,
                },
            )
        else
            try std.fmt.allocPrint(
                allocator,
                "temp_sphere2000_{s}_{s}_thr{d}{s}",
                .{
                    @tagName(mesh_type),
                    @tagName(shader_type),
                    tcfg.TOTAL_THREADS,
                    impl_suffix,
                },
            );
        defer allocator.free(fail_dir_name);

        try testcommon.saveComparisonArtifactsFromResult(
            allocator,
            io,
            "fails",
            fail_dir_name,
            &result,
            0,
            0,
            0,
            gold_path,
            channels,
        );
        if (err == error.PixelMismatch) {
            return false;
        }
        return err;
    };

    return true;
}

test "Temp sphere2000 public API path" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const io = std.testing.io;

    const texture_grey = try iio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    defer texture_grey.deinit(allocator);

    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const mesh_types = std.enums.values(mo.MeshType);
    const shader_types = std.enums.values(ShaderType);
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    std.debug.print(
        "Running temp sphere2000 public API test " ++
            "with .simd = .{s}, total_threads = {d}\n",
        .{
            if (simd_on) "on" else "off",
            tcfg.TOTAL_THREADS,
        },
    );

    if (!simd_on and !goldDirExists(io, gold_dir)) {
        std.debug.print(
            "Skipping scalar temp sphere2000 public API test: " ++
                "missing {s}\n",
            .{gold_dir},
        );
        return;
    }

    var total_fails: usize = 0;

    for (mesh_types) |mesh_type| {
        for (shader_types) |shader_type| {
            for (sample_configs) |sample_config| {
                if (!shouldRun(shader_type, sample_config)) {
                    continue;
                }

                const passed = try runSphereCase(
                    allocator,
                    io,
                    mesh_type,
                    shader_type,
                    sample_config,
                    texture_grey,
                    texture_rgb,
                );

                if (!passed) {
                    total_fails += 1;
                }
            }
        }
    }

    if (total_fails != 0) {
        std.debug.print(
            "Temp sphere2000 public API test found {d} failing cases.\n",
            .{total_fails},
        );
        return error.TestUnexpectedResult;
    }
}
