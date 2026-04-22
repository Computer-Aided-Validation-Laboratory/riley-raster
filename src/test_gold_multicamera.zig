// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const benchcommon = @import("common/benchcommon.zig");
const orch = @import("common/orchestration.zig");
const testcommon = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const cfg = buildconfig.config;
const camera_mod = @import("zraster/zig/camera.zig");
const Camera = camera_mod.Camera;
const iio = @import("zraster/zig/imageio.zig");
const mr = @import("zraster/zig/meshraster.zig");
const meshio = @import("zraster/zig/meshio.zig");
const NDArray = @import("zraster/zig/ndarray.zig").NDArray;
const texops = @import("zraster/zig/textureops.zig");
const uvio = @import("zraster/zig/uvio.zig");
const zraster = @import("zraster/zig/zraster.zig");

const simd_on = cfg.simd == .on;

const duplicate_rel_tol: f64 = 1.0e-7;
const duplicate_abs_tol: f64 = 1.0e-11;
const fails_root = "fails";

const RenderCase = struct {
    case_name: []const u8,
    data_dir: []const u8,
    mesh_type: mr.MeshType,
    channels: usize,
    shader: union(enum) {
        nodal_grey,
        tex8_rgb: texops.TextureSampleConfig,
    },
};

fn expectCamerasEqual(
    array: *const NDArray(f64),
    camera_a: usize,
    camera_b: usize,
    channels: usize,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    const rows_num = array.dims[3];
    const cols_num = array.dims[4];

    for (0..channels) |cc| {
        for (0..rows_num) |rr| {
            for (0..cols_num) |pp| {
                const value_a = array.get(
                    &[_]usize{ camera_a, 0, cc, rr, pp },
                );
                const value_b = array.get(
                    &[_]usize{ camera_b, 0, cc, rr, pp },
                );
                if (!testcommon.isApproxEqual(
                    value_a,
                    value_b,
                    rel_tol,
                    abs_tol,
                )) {
                    return error.CameraOutputsDiffer;
                }
            }
        }
    }
}

fn expectCamerasDifferent(
    array: *const NDArray(f64),
    camera_a: usize,
    camera_b: usize,
    channels: usize,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    const rows_num = array.dims[3];
    const cols_num = array.dims[4];

    for (0..channels) |cc| {
        for (0..rows_num) |rr| {
            for (0..cols_num) |pp| {
                const value_a = array.get(
                    &[_]usize{ camera_a, 0, cc, rr, pp },
                );
                const value_b = array.get(
                    &[_]usize{ camera_b, 0, cc, rr, pp },
                );
                if (!testcommon.isApproxEqual(
                    value_a,
                    value_b,
                    rel_tol,
                    abs_tol,
                )) {
                    return;
                }
            }
        }
    }

    return error.CameraOutputsIdentical;
}

test "Multicamera duplicate sphere200 cameras match each other" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const io = std.testing.io;
    const pixel_num = [_]u32{ 800, 500 };
    const render_case = RenderCase{
        .case_name = "tri3_nodal_grey",
        .data_dir = "data-bench/tri3_sphere200",
        .mesh_type = .tri3,
        .channels = 1,
        .shader = .nodal_grey,
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const coord_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ render_case.data_dir, "coords.csv" },
    );
    const connect_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ render_case.data_dir, "connect.csv" },
    );
    const field_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ render_case.data_dir, "field.csv" },
    );

    const sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        connect_path,
        null,
        null,
    );
    const field_raw = try benchcommon.loadNDArrayFromCSV(
        aa,
        io,
        field_path,
        1,
        true,
    );
    const camera = try orch.initCameraForCoords(aa, &sim_data.coords, pixel_num, 1.0);
    defer camera.deinit(aa);
    const cameras = [_]Camera{ camera, camera };

    const mesh_input = mr.MeshInput{
        .mesh_type = render_case.mesh_type,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{
            .nodal = .{
                .field = .{
                    .array = field_raw,
                    .array_mem = field_raw.slice,
                },
                .scaling = .auto,
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

    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &cameras,
        &[_]mr.MeshInput{mesh_input},
        config,
        null,
        null,
    )) orelse return error.NoResult;
    defer aa.free(result.slice);

    try std.testing.expectEqual(@as(usize, 2), result.dims[0]);
    try expectCamerasEqual(
        &result,
        0,
        1,
        render_case.channels,
        duplicate_rel_tol,
        duplicate_abs_tol,
    );
}

test "Sphere200 multicamera gold tests" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const io = std.testing.io;
    const gold_root = if (simd_on)
        "gold-simd-sphere200multicam"
    else
        "gold-sphere200multicam";
    const pixel_num = [_]u32{ 800, 500 };

    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const render_cases = [_]RenderCase{
        .{
            .case_name = "tri3_nodal_grey",
            .data_dir = "data-bench/tri3_sphere200",
            .mesh_type = .tri3,
            .channels = 1,
            .shader = .nodal_grey,
        },
        .{
            .case_name = "tri6_tex8_rgb_cubic_catmull_rom_lut_lerp",
            .data_dir = "data-bench/tri6_sphere200",
            .mesh_type = .tri6,
            .channels = 3,
            .shader = .{
                .tex8_rgb = .{
                    .sample = .cubic_catmull_rom,
                    .mode = .lut_lerp,
                },
            },
        },
    };

    for (render_cases) |render_case| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const coord_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "coords.csv" },
        );
        const connect_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "connect.csv" },
        );
        const field_path = try std.fs.path.join(
            aa,
            &[_][]const u8{ render_case.data_dir, "field.csv" },
        );
        const sim_data = try meshio.loadSimData(
            aa,
            io,
            coord_path,
            connect_path,
            null,
            null,
        );
        const field_raw = try benchcommon.loadNDArrayFromCSV(
            aa,
            io,
            field_path,
            if (render_case.channels == 3) 3 else 1,
            true,
        );
        const cameras = try orch.initStereoCamerasForCoords(
            aa,
            &sim_data.coords,
            pixel_num,
            1.0,
            10.0,
        );
        defer for (cameras) |cam| cam.deinit(aa);

        const mesh_input = switch (render_case.shader) {
            .nodal_grey => mr.MeshInput{
                .mesh_type = render_case.mesh_type,
                .coords = sim_data.coords,
                .connect = sim_data.connect,
                .disp = null,
                .shader = .{
                    .nodal = .{
                        .field = .{
                            .array = field_raw,
                            .array_mem = field_raw.slice,
                        },
                        .scaling = .auto,
                    },
                },
            },
            .tex8_rgb => |sample_config| blk: {
                const uv_path = try std.fmt.allocPrint(
                    aa,
                    "{s}/uvs.csv",
                    .{render_case.data_dir},
                );
                const uv_map = try uvio.loadUVMap(
                    aa,
                    io,
                    uv_path,
                );
                break :blk mr.MeshInput{
                    .mesh_type = render_case.mesh_type,
                    .coords = sim_data.coords,
                    .connect = sim_data.connect,
                    .disp = null,
                    .shader = .{
                        .tex_rgb = .{
                            .uvs = uv_map.array,
                            .texture = texture_rgb,
                            .sample_config = sample_config,
                        },
                    },
                };
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
                .{
                    .format = .csv,
                    .bits = null,
                    .scaling = .none,
                    .channels = render_case.channels,
                },
            },
            .report = .off,
        };

        const result = (try zraster.rasterAllFrames(
            aa,
            io,
            &cameras,
            &[_]mr.MeshInput{mesh_input},
            config,
            null,
            null,
        )) orelse return error.NoResult;
        defer aa.free(result.slice);

        try std.testing.expectEqual(@as(usize, 2), result.dims[0]);
        try expectCamerasDifferent(
            &result,
            0,
            1,
            render_case.channels,
            duplicate_rel_tol,
            duplicate_abs_tol,
        );

        const gold_dir = try std.fs.path.join(
            aa,
            &[_][]const u8{ gold_root, render_case.case_name },
        );

        for (0..2) |camera_idx| {
            const gold_path = try testcommon.findGoldPath(
                aa,
                io,
                gold_dir,
                camera_idx,
                0,
                0,
                render_case.channels == 3,
            );

            testcommon.compareNDArrayToGold(
                aa,
                io,
                &result,
                camera_idx,
                0,
                0,
                render_case.channels,
                gold_path,
                duplicate_rel_tol,
                duplicate_abs_tol,
            ) catch |err| {
                const fail_dir_name = try std.fmt.allocPrint(
                    aa,
                    "multicam_{s}_cam{d}",
                    .{ render_case.case_name, camera_idx },
                );
                try testcommon.saveComparisonArtifactsFromResult(
                    aa,
                    io,
                    fails_root,
                    fail_dir_name,
                    &result,
                    camera_idx,
                    0,
                    0,
                    gold_path,
                    render_case.channels,
                );
                return err;
            };
        }
    }
}
