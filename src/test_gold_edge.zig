// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("common/tests.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const CameraInput = @import("zraster/zig/camera.zig").CameraInput;
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");
const zraster = @import("zraster/zig/zraster.zig");

const SHADER_FILTER: common.ShaderFilter = .both; // .nodal, .tex, or .both

fn buildUvField(
    allocator: std.mem.Allocator,
    uvs: @import("zraster/zig/ndarray.zig").NDArray(f64),
    time_steps: usize,
) !meshio.Field {
    const node_num = uvs.dims[0];
    var field = try meshio.Field.initAlloc(allocator, time_steps, node_num, 2);

    for (0..time_steps) |tt| {
        for (0..node_num) |nn| {
            field.array.set(&[_]usize{ tt, nn, 0 }, uvs.get(&[_]usize{ nn, 0 }));
            field.array.set(&[_]usize{ tt, nn, 1 }, uvs.get(&[_]usize{ nn, 1 }));
        }
    }

    return field;
}

fn runDistortMidsideTexFuncTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    pixel_num: [2]u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const prepared = try orch.prepareSingleMeshCase(
        aa,
        io,
        "distort-midside",
        mesh_type,
        pixel_num,
        1.1,
        data_dir_root,
    );

    const case_dir_name = try std.fmt.allocPrint(
        aa,
        "distort-midside_{s}_texfunc_constant",
        .{@tagName(mesh_type)},
    );
    const gold_dir = try std.fmt.allocPrint(
        aa,
        "{s}/{s}",
        .{ gold_dir_root, case_dir_name },
    );

    const mesh_input = mo.MeshInput{
        .mesh_type = mesh_type,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shader = .{
            .tex_func = .{
                .uvs = null,
                .builtin = .constant,
                .normal_type = .none,
            },
        },
    };

    const config = zraster.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = tcfg.TOTAL_THREADS,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = tcfg.MAX_GEOM_THREADS_PER_FRAME,
        .max_raster_threads_per_frame = tcfg.MAX_RASTER_THREADS_PER_FRAME,
        .save_strategy = .memory,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    const prepared_camera_input = prepared.camera.toInput();
    std.debug.print("Testing {s} ... ", .{case_dir_name});
    const start_time = std.Io.Clock.Timestamp.now(io, .awake);
    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{prepared_camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer aa.free(result.slice);
    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;

    const frames_num = if (result.dims.len == 5) result.dims[1] else result.dims[0];
    for (0..frames_num) |frame_idx| {
        const gold_path = try common.findGoldPath(
            aa,
            io,
            gold_dir,
            0,
            frame_idx,
            0,
            false,
        );

        common.compareNDArrayToGold(
            aa,
            io,
            &result,
            0,
            frame_idx,
            0,
            1,
            gold_path,
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
        ) catch |err| {
            if (err == error.PixelMismatch) {
                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
            } else {
                std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
            }
            const fail_dir_name = try std.fmt.allocPrint(
                aa,
                "all_{s}_{s}",
                .{
                    case_dir_name,
                    if (buildconfig.config.simd == .on) "simd" else "scalar",
                },
            );
            try common.saveComparisonArtifactsFromResult(
                aa,
                io,
                "fails",
                fail_dir_name,
                &result,
                0,
                frame_idx,
                0,
                gold_path,
                1,
            );
            return err;
        };
    }
    std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
}

fn runDistortMidsideNodalUvTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    pixel_num: [2]u32,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const prepared = try orch.prepareSingleMeshCase(
        aa,
        io,
        "distort-midside",
        mesh_type,
        pixel_num,
        1.1,
        data_dir_root,
    );
    const uv_field = try buildUvField(
        aa,
        prepared.uvs.array,
        prepared.sim_data.field.?.getTimeN(),
    );

    const case_dir_name = try std.fmt.allocPrint(
        aa,
        "distort-midside_{s}_nodal_uv",
        .{@tagName(mesh_type)},
    );
    const gold_dir = try std.fmt.allocPrint(aa, "{s}/{s}", .{ gold_dir_root, case_dir_name });

    const mesh_input = mo.MeshInput{
        .mesh_type = mesh_type,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shader = .{
            .nodal = .{
                .field = uv_field,
                .bits = null,
                .scaling = .none,
            },
        },
    };

    const config = zraster.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = tcfg.TOTAL_THREADS,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = tcfg.MAX_GEOM_THREADS_PER_FRAME,
        .max_raster_threads_per_frame = tcfg.MAX_RASTER_THREADS_PER_FRAME,
        .save_strategy = .memory,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    const prepared_camera_input = prepared.camera.toInput();
    std.debug.print("Testing {s} ... ", .{case_dir_name});
    const start_time = std.Io.Clock.Timestamp.now(io, .awake);
    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{prepared_camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer aa.free(result.slice);
    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;

    const frames_num = if (result.dims.len == 5) result.dims[1] else result.dims[0];
    for (0..frames_num) |frame_idx| {
        for (0..2) |field_idx| {
            const gold_path = try common.findGoldPath(
                aa,
                io,
                gold_dir,
                0,
                frame_idx,
                field_idx,
                false,
            );

            common.compareNDArrayToGold(
                aa,
                io,
                &result,
                0,
                frame_idx,
                field_idx,
                1,
                gold_path,
                tcfg.REL_TOL,
                tcfg.ABS_TOL,
            ) catch |err| {
                if (err == error.PixelMismatch) {
                    std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
                } else {
                    std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
                }
                return err;
            };
        }
    }
    std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
}

fn runDistortMidsideTexShaderTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    pixel_num: [2]u32,
    texture: iio.Texture(1),
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const prepared = try orch.prepareSingleMeshCase(
        aa,
        io,
        "distort-midside",
        mesh_type,
        pixel_num,
        1.1,
        data_dir_root,
    );
    const sample_config = texops.TextureSampleConfig{
        .sample = .cubic_catmull_rom,
        .mode = .lut_lerp,
    };

    const case_dir_name = try std.fmt.allocPrint(
        aa,
        "distort-midside_{s}_tex_{s}_{s}",
        .{
            @tagName(mesh_type),
            @tagName(sample_config.sample),
            @tagName(sample_config.mode),
        },
    );
    const gold_dir = try std.fmt.allocPrint(aa, "{s}/{s}", .{ gold_dir_root, case_dir_name });

    const mesh_input = mo.MeshInput{
        .mesh_type = mesh_type,
        .coords = prepared.sim_data.coords,
        .connect = prepared.sim_data.connect,
        .disp = prepared.sim_data.field,
        .shader = .{
            .tex = .{
                .uvs = prepared.uvs.array,
                .texture = texture,
                .sample_config = sample_config,
            },
        },
    };

    const config = zraster.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = tcfg.TOTAL_THREADS,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = tcfg.MAX_GEOM_THREADS_PER_FRAME,
        .max_raster_threads_per_frame = tcfg.MAX_RASTER_THREADS_PER_FRAME,
        .save_strategy = .memory,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    const prepared_camera_input = prepared.camera.toInput();
    std.debug.print("Testing {s} ... ", .{case_dir_name});
    const start_time = std.Io.Clock.Timestamp.now(io, .awake);
    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{prepared_camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer aa.free(result.slice);
    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;

    const frames_num = if (result.dims.len == 5) result.dims[1] else result.dims[0];
    for (0..frames_num) |frame_idx| {
        const gold_path = try common.findGoldPath(
            aa,
            io,
            gold_dir,
            0,
            frame_idx,
            0,
            false,
        );

        common.compareNDArrayToGold(
            aa,
            io,
            &result,
            0,
            frame_idx,
            0,
            1,
            gold_path,
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
        ) catch |err| {
            if (err == error.PixelMismatch) {
                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
            } else {
                std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
            }
            return err;
        };
    }
    std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
}

test "Gold Edge Suite" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const io = std.testing.io;

    const texture = blk: {
        break :blk try iio.loadImage(
            u8,
            1,
            allocator,
            io,
            "texture/speckle-simple.tiff",
            .tiff,
        );
    };
    defer texture.deinit(allocator);

    const mesh_types = [_]gk.MeshType{ .tri6, .quad8, .quad9 };
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 320, 200 };
    const pixel_num_distort_midside = [_]u32{ 800, 500 };

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    const simd_on = @import("zraster/zig/buildconfig.zig").config.simd == .on;
    std.debug.print("Running Gold Edge Tests with .simd = .{s}...\n", .{
        if (simd_on) "on" else "off",
    });

    for (mesh_types) |mt| {
        try common.runTestInternal(
            allocator,
            io,
            "bulgein_rot",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );

        try common.runTestInternal(
            allocator,
            io,
            "bulgeout_rot",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );

        try common.runTestInternal(
            allocator,
            io,
            "vertbulge",
            mt,
            1.1,
            texture,
            pixel_num,
            &sample_configs,
            "gold-edge",
            "data-edge",
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
            SHADER_FILTER,
            false,
        );

        try runDistortMidsideTexFuncTest(
            allocator,
            io,
            mt,
            "gold-edge",
            "data-edge",
            pixel_num_distort_midside,
        );

        try runDistortMidsideNodalUvTest(
            allocator,
            io,
            mt,
            "gold-edge",
            "data-edge",
            pixel_num_distort_midside,
        );

        try runDistortMidsideTexShaderTest(
            allocator,
            io,
            mt,
            "gold-edge",
            "data-edge",
            pixel_num_distort_midside,
            texture,
        );
    }

    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;
    std.debug.print("Gold Edge Test Suite took {d:.3} ms\n", .{duration_ms});
}
