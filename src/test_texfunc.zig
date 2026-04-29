// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("common/tests.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const shaderops = @import("zraster/zig/shaderops.zig");
const uvio = @import("zraster/zig/uvio.zig");
const CameraInput = @import("zraster/zig/camera.zig").CameraInput;
const iio = @import("zraster/zig/imageio.zig");
const zraster = @import("zraster/zig/zraster.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const rastcfg = @import("zraster/zig/rasterconfig.zig");

const gold_root = "gold-texfunc";
const data_root = "data-min";
const test_type = "sphere200";
const CoordMode = enum { uv, param };

const SphereCasePrepared = struct {
    coords: meshio.Coords,
    connect: meshio.Connect,
    uvs: uvio.UVMap,
    camera_input: CameraInput,
};

fn loadSphereCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
) !SphereCasePrepared {
    const data_dir = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}_{s}",
        .{ data_root, @tagName(mesh_type), test_type },
    );
    const coord_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "coords.csv" },
    );
    const connect_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "connect.csv" },
    );
    const uv_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ data_dir, "uvs.csv" },
    );

    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        coord_path,
        connect_path,
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(allocator, io, uv_path);
    const camera = try orch.initCameraForCoords(
        allocator,
        &sim_data.coords,
        .{ 640, 400 },
        1.0,
    );

    return .{
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .uvs = uvs,
        .camera_input = camera.toInput(),
    };
}

fn runTexFuncCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh_type: gk.MeshType,
    builtin: shaderops.TexFuncBuiltin,
    coord_mode: CoordMode,
    is_rgb: bool,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const prepared = try loadSphereCase(
        aa,
        io,
        mesh_type,
    );

    const coord_name = if (coord_mode == .uv) "uv" else "param";
    const uvs = if (coord_mode == .uv) prepared.uvs.array else null;
    const normal_type: shaderops.NormalType =
        if (builtin == .lambertian_normal_z) .averaged else .none;

    const case_dir_name = if (is_rgb)
        try std.fmt.allocPrint(
            aa,
            "{s}_{s}_texfunc_rgb_{s}_{s}",
            .{
                test_type,
                @tagName(mesh_type),
                coord_name,
                @tagName(builtin),
            },
        )
    else
        try std.fmt.allocPrint(
            aa,
            "{s}_{s}_texfunc_{s}_{s}",
            .{
                test_type,
                @tagName(mesh_type),
                coord_name,
                @tagName(builtin),
            },
        );
    const gold_dir = try std.fmt.allocPrint(aa, "{s}/{s}", .{ gold_root, case_dir_name });

    const mesh_input = mo.MeshInput{
        .mesh_type = mesh_type,
        .coords = prepared.coords,
        .connect = prepared.connect,
        .disp = null,
        .shader = if (is_rgb)
            .{
                .tex_func_rgb = .{
                    .uvs = uvs,
                    .builtin = builtin,
                    .normal_type = normal_type,
                },
            }
        else
            .{
                .tex_func = .{
                    .uvs = uvs,
                    .builtin = builtin,
                    .normal_type = normal_type,
                },
            },
    };

    std.debug.print("Testing {s} ... ", .{case_dir_name});

    const config = rastcfg.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = tcfg.TOTAL_THREADS,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = tcfg.MAX_GEOM_THREADS_PER_FRAME,
        .max_raster_threads_per_frame = tcfg.MAX_RASTER_THREADS_PER_FRAME,
        .hull_mode = tcfg.HULL_MODE,
        .save_strategy = .memory,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    const camera_input: CameraInput = prepared.camera_input;
    const time_start = Timestamp.now(io, .awake);
    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &[_]CameraInput{camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer aa.free(result.slice);
    const time_end = Timestamp.now(io, .awake);
    const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;

    const frames_num = if (result.dims.len == 5) result.dims[1] else result.dims[0];
    for (0..frames_num) |frame_idx| {
        if (is_rgb) {
            for (0..3) |channel_idx| {
                const gold_path = try common.findGoldPath(
                    aa,
                    io,
                    gold_dir,
                    0,
                    frame_idx,
                    channel_idx,
                    false,
                );

                try common.compareNDArrayToGold(
                    aa,
                    io,
                    &result,
                    0,
                    frame_idx,
                    channel_idx,
                    1,
                    gold_path,
                    tcfg.REL_TOL,
                    tcfg.ABS_TOL,
                );
            }
        } else {
            const gold_path = try common.findGoldPath(
                aa,
                io,
                gold_dir,
                0,
                frame_idx,
                0,
                false,
            );

            try common.compareNDArrayToGold(
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
            );
        }
    }
    std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
}

test "TexFunc Suite" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const simd_on = buildconfig.config.simd == .on;
    std.debug.print("Running TexFunc Gold Tests with .simd = .{s}...\n", .{
        if (simd_on) "on" else "off",
    });

    const io = std.testing.io;
    const mesh_types = [_]gk.MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad4newton,
        .quad8,
        .quad9,
    };
    const builtins = [_]shaderops.TexFuncBuiltin{
        .constant,
        .linear,
        .quadratic,
        .sinusoidal,
        .checker_smooth,
        .lambertian_normal_z,
    };
    const coord_modes = [_]CoordMode{ .uv, .param };
    const rgb_modes = [_]bool{ false, true };

    for (mesh_types) |mesh_type| {
        for (builtins) |builtin| {
            for (coord_modes) |coord_mode| {
                for (rgb_modes) |is_rgb| {
                    try runTexFuncCase(
                        allocator,
                        io,
                        mesh_type,
                        builtin,
                        coord_mode,
                        is_rgb,
                    );
                }
            }
        }
    }
}
