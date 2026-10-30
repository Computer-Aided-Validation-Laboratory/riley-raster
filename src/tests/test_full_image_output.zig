// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const meshtypes = @import("../riley/zig/meshtypes.zig");
const cameratypes = @import("../riley/zig/cameratypes.zig");
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/cameraprojops.zig");
const common = @import("../dev_support/tests.zig");
const common_full = @import("../dev_support/fullfixtures.zig");
const gengold_io = @import("../gengold/gen_gold_full_image_output.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const iio = @import("../riley/zig/imageio.zig");
const imageops = @import("../riley/zig/imageops.zig");
const mo = @import("../riley/zig/meshpipeline.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const orch = @import("../dev_support/orchestration.zig");
const policy = @import("../dev_support/testpolicy.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const report = @import("../riley/zig/report.zig");
const riley = @import("../riley/zig/riley.zig");
const tcfg = @import("../dev_support/testconfig.zig");

const F = buildconfig.F;
const CameraInput = cameratypes.CameraInput;
const MeshInput = meshtypes.MeshInput;
const NDArray = ndarray.NDArray(F);
const Timestamp = std.Io.Clock.Timestamp;

const save_strategies = [_]rastcfg.SaveStrategy{
    .memory,
    .disk,
    .both,
    .none,
};

const test_formats = [_]iio.ImageFormat{
    .fimg,
    .csv,
    .bmp,
    .tiff,
};

const report_modes = [_]rastcfg.ReportMode{
    .off,
    .bench,
};

const scale_strategies = [_]enum {
    none,
    auto,
    fixed,
    frac,
}{
    .none,
    .auto,
    .fixed,
    .frac,
};

fn runBaseComparison(
    allocator: std.mem.Allocator,
    io: std.Io,
    bc: gengold_io.ImageOutputBaseCase,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    gold_dir_root: []const u8,
    config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const meshes = try common_full.buildScene2ImageOutputMeshes(
        aa,
        prep,
        textures,
        bc.is_rgb,
        bc.is_u16,
    );
    const cam_inp = common_full.createScene2ImageOutputCamera(&meshes);

    var run_config = config;
    run_config.save_strategy = .memory;

    const start_time = Timestamp.now(io, .awake);
    const result = try riley.raster(
        aa,
        io,
        &[_]CameraInput{cam_inp},
        &meshes,
        run_config,
        null,
    );

    var render_result = result orelse return error.NoResult;
    defer aa.free(render_result.slice);

    const end_time = Timestamp.now(io, .awake);
    const duration_ms = @as(
        F,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1.0e6;

    const gold_dir = try std.fmt.allocPrint(
        aa,
        "{s}/{s}",
        .{ gold_dir_root, bc.tag },
    );

    const expected_channels: usize = if (bc.is_rgb) 3 else 1;
    try std.testing.expectEqual(@as(usize, 1), render_result.dims[0]);
    try std.testing.expectEqual(@as(usize, 1), render_result.dims[1]);
    try std.testing.expectEqual(expected_channels, render_result.dims[2]);
    try std.testing.expectEqual(@as(usize, 100), render_result.dims[3]);
    try std.testing.expectEqual(@as(usize, 160), render_result.dims[4]);

    const gold_path = try common.findGoldPath(
        aa,
        io,
        gold_dir,
        0,
        0,
        0,
        false,
    );

    common.compareNDArrayToGold(
        aa,
        io,
        &render_result,
        0,
        0,
        0,
        expected_channels,
        gold_path,
        tcfg.FULL_GOLD_REL_TOL,
        tcfg.FULL_GOLD_ABS_TOL,
    ) catch |err| {
        const fail_dir_name = try std.fmt.allocPrint(
            aa,
            "full_image_output/{s}",
            .{bc.tag},
        );
        try common.saveComparisonArtifactsFromResult(
            aa,
            io,
            common.default_fails_root,
            fail_dir_name,
            &render_result,
            0,
            0,
            0,
            gold_path,
            expected_channels,
        );
        if (tcfg.TEST_CASE_VERBOSE) {
            std.debug.print("FAIL base {s} ({d:.2} ms)\n", .{ bc.tag, duration_ms });
        }
        try common.recordGoldFailure(err);
    };

    if (tcfg.TEST_CASE_VERBOSE) {
        std.debug.print("PASS base {s} ({d:.2} ms)\n", .{ bc.tag, duration_ms });
    }
}

fn runFactorialSaveStrategy(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    config: rastcfg.RasterConfig,
) !void {
    const temp_dir_base = "temp-tests/image_output_strategy";
    var dir = try orch.openDirEnsured(io, temp_dir_base);
    dir.close(io);

    const meshes = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        false,
        false,
    );
    const cam_inp = common_full.createScene2ImageOutputCamera(&meshes);

    for (save_strategies) |strat| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const out_subdir = try std.fmt.allocPrint(
            aa,
            "{s}/{s}",
            .{ temp_dir_base, @tagName(strat) },
        );
        var sub_dir = try orch.openDirEnsured(io, out_subdir);
        sub_dir.close(io);

        var run_config = config;
        run_config.save_strategy = strat;

        const result = try riley.raster(
            aa,
            io,
            &[_]CameraInput{cam_inp},
            &meshes,
            run_config,
            out_subdir,
        );

        switch (strat) {
            .memory => {
                try std.testing.expect(result != null);
                if (result) |arr| aa.free(arr.slice);
            },
            .disk => {
                try std.testing.expect(result == null);
            },
            .both => {
                try std.testing.expect(result != null);
                if (result) |arr| aa.free(arr.slice);
            },
            .none => {
                try std.testing.expect(result == null);
            },
        }
    }
}

fn runFactorialFormatsAndModes(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    config: rastcfg.RasterConfig,
) !void {
    const temp_dir_base = "temp-tests/image_output_formats";
    var dir = try orch.openDirEnsured(io, temp_dir_base);
    dir.close(io);

    const meshes_mono = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        false,
        false,
    );
    const meshes_rgb = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        true,
        false,
    );
    defer {
        allocator.free(meshes_rgb[0].shaders.rgb_pipe.?.stages);
        allocator.free(meshes_rgb[1].shaders.rgb_pipe.?.stages);
    }

    for ([_]bool{ false, true }) |is_rgb| {
        for (test_formats) |fmt| {
            if (is_rgb and fmt == .tiff) continue;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();
            const out_subdir = try std.fmt.allocPrint(
                aa,
                "{s}/{s}_{s}",
                .{ temp_dir_base, if (is_rgb) @as([]const u8, "rgb") else "mono", @tagName(fmt) },
            );
            var sub_dir = try orch.openDirEnsured(io, out_subdir);
            sub_dir.close(io);

            var run_config = config;
            run_config.save_strategy = .both;
            const bits: ?u8 = switch (fmt) {
                .bmp, .tiff, .ppm => 8,
                .fimg, .csv => null,
            };
            const meshes = if (is_rgb) &meshes_rgb else &meshes_mono;
            var selected_camera = common_full.createScene2ImageOutputCamera(meshes);
            const file_options = [_]iio.ImageSaveOpts{.{
                .format = fmt,
                .file_bits = bits,
                .scaling = .none,
            }};
            selected_camera.output_files = &file_options;
            const result = try riley.raster(
                aa,
                io,
                &.{selected_camera},
                meshes,
                run_config,
                out_subdir,
            );
            try std.testing.expect(result != null);
            if (result) |arr| aa.free(arr.slice);
        }
    }
}

fn runFactorialScalingAndReports(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    config: rastcfg.RasterConfig,
) !void {
    const meshes = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        false,
        false,
    );
    const cam_inp = common_full.createScene2ImageOutputCamera(&meshes);

    for (scale_strategies) |scale_strat| {
        for (report_modes) |rep_mode| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            var run_config = config;
            run_config.save_strategy = .memory;
            run_config.report_perf = rep_mode;
            const scaling: imageops.ScaleStrategy = switch (scale_strat) {
                .none => .none,
                .auto => .auto,
                .fixed => .{ .fixed = .{ 0.0, 255.0 } },
                .frac => .{ .frac = .{ 0.05, 0.95 } },
            };

            var camera_with_scaling = cam_inp;
            camera_with_scaling.output_files = &.{.{ .format = .bmp, .scaling = scaling }};
            const result = try riley.raster(
                aa,
                io,
                &[_]CameraInput{camera_with_scaling},
                &meshes,
                run_config,
                null,
            );

            try std.testing.expect(result != null);
            if (result) |arr| aa.free(arr.slice);
        }
    }
}

fn runEntryPointEquivalence(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const meshes = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        false,
        false,
    );
    const cam_inp = common_full.createScene2ImageOutputCamera(&meshes);
    const cam_inps = [_]CameraInput{cam_inp};

    var run_config = config;
    run_config.save_strategy = .memory;
    run_config.report_console = true;

    // 1. raster (allocates output array)
    const result_raster = try riley.raster(
        aa,
        io,
        &cam_inps,
        &meshes,
        run_config,
        null,
    );
    const img_raster = result_raster orelse return error.NoResult;

    run_config.report_console = false;

    // Capture requires timing, even when console output is disabled.
    var off_capture = [_]report.FrameBenchCapture{
        std.mem.zeroes(report.FrameBenchCapture),
    };
    try std.testing.expectError(
        error.InvalidBenchCaptureBuff,
        riley.rasterAdvanced(
            aa,
            io,
            &cam_inps,
            &meshes,
            run_config,
            null,
            .{ .bench_capture = off_capture[0..] },
        ),
    );
    run_config.report_perf = .bench;
    run_config.report_console = false;

    // 2. rasterAdvanced (allocates output array, captures bench)
    var bench_capt = [_]report.FrameBenchCapture{
        std.mem.zeroes(report.FrameBenchCapture),
    };
    const result_report = try riley.rasterAdvanced(
        aa,
        io,
        &cam_inps,
        &meshes,
        run_config,
        null,
        .{ .bench_capture = bench_capt[0..] },
    );
    const img_report = result_report orelse return error.NoResult;

    // 3. rasterInto (renders into pre-allocated output array)
    const dims = try riley.calcAllFramesImageDims(
        &cam_inps,
        &meshes,
        run_config,
    );
    var img_into = try NDArray.initFlat(aa, dims[0..]);
    try riley.rasterInto(
        aa,
        io,
        &cam_inps,
        &meshes,
        run_config,
        null,
        &img_into,
    );

    run_config.report_console = true;

    // 4. rasterAdvancedInto (renders into pre-allocated array, captures bench)
    var bench_capt_into = [_]report.FrameBenchCapture{
        std.mem.zeroes(report.FrameBenchCapture),
    };
    var img_report_into = try NDArray.initFlat(aa, dims[0..]);
    try riley.rasterAdvancedInto(
        aa,
        io,
        &cam_inps,
        &meshes,
        run_config,
        null,
        &img_report_into,
        .{ .bench_capture = bench_capt_into[0..] },
    );

    // Assert exact identical outputs across all four entry points
    try std.testing.expectEqualSlices(usize, img_raster.dims, img_report.dims);
    try std.testing.expectEqualSlices(usize, img_raster.dims, img_into.dims);
    try std.testing.expectEqualSlices(
        usize,
        img_raster.dims,
        img_report_into.dims,
    );

    try std.testing.expectEqualSlices(F, img_raster.slice, img_report.slice);
    try std.testing.expectEqualSlices(F, img_raster.slice, img_into.slice);
    try std.testing.expectEqualSlices(
        F,
        img_raster.slice,
        img_report_into.slice,
    );

    // The caller I/O opens the directory, while this supplied threaded group
    // renders and saves the frame through its own I/O context.
    var groups = try riley.ManagedRenderGroups.init(allocator, null, 2, 1);
    defer groups.deinit(allocator);

    var disk_config = run_config;
    disk_config.save_strategy = .both;
    const out_dir_path = "temp-tests/image_output_user_io";
    const result_supplied = try riley.rasterAdvanced(
        allocator,
        io,
        &cam_inps,
        &meshes,
        disk_config,
        out_dir_path,
        .{ .render_groups = .{ .supplied = groups.groups } },
    );
    var img_supplied = result_supplied orelse return error.NoResult;
    defer {
        allocator.free(img_supplied.slice);
        img_supplied.deinit(allocator);
    }
    try std.testing.expectEqualSlices(F, img_raster.slice, img_supplied.slice);

    var saved_file = try std.Io.Dir.cwd().openFile(
        io,
        "temp-tests/image_output_user_io/cam0_frame0_field0.bmp",
        .{},
    );
    saved_file.close(io);
}

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    var config = tcfg.getRasterConfig(.testing);
    config.background_value = 127.5;
    const gold_dir_root = policy.goldRoot(.full_image_output);

    var textures = try common_full.FullTextures.init(allocator, io);
    defer textures.deinit(allocator);

    var prep = try common_full.prepareScene2(allocator, io, .tri3);
    defer prep.deinit(allocator);

    for (gengold_io.base_cases) |bc| {
        try runBaseComparison(
            allocator,
            io,
            bc,
            &prep,
            &textures,
            gold_dir_root,
            config,
        );
    }

    try runFactorialSaveStrategy(allocator, io, &prep, &textures, config);
    try runFactorialFormatsAndModes(allocator, io, &prep, &textures, config);
    try runFactorialScalingAndReports(allocator, io, &prep, &textures, config);
    try runEntryPointEquivalence(allocator, io, &prep, &textures, config);
    try runAdditionalImageOutputTests(allocator, io, &prep, &textures, config);
    try runMixedCameraOutput(allocator, io, &prep, &textures, config);
    try runPerFileAdcOutput(allocator, io, &prep, &textures, config);
}

fn runPerFileAdcOutput(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    base_config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const meshes = try common_full.buildScene2ImageOutputMeshes(aa, prep, textures, false, false);
    var camera_input = common_full.createScene2ImageOutputCamera(&meshes);
    var config = base_config;
    config.save_strategy = .both;

    for ([_]iio.CodePacking{ .lower, .upper, .spread }, 0..) |packing, index| {
        const out_dir = try std.fmt.allocPrint(aa, "temp-tests/image_output_adc_{d}", .{index});
        var dir = try orch.openDirEnsured(io, out_dir);
        dir.close(io);
        const file_options = [_]iio.ImageSaveOpts{
            .{ .format = .csv, .file_bits = null },
            .{ .format = .tiff, .file_bits = 16, .adc_bits = 12, .scaling = .{ .fixed = .{ 0, 255 } }, .packing = packing },
        };
        camera_input.output_files = &file_options;
        const rendered = (try riley.raster(aa, io, &.{camera_input}, &meshes, config, out_dir)) orelse
            return error.NoResult;
        const csv_path = try std.fmt.allocPrint(aa, "{s}/cam0_frame0_field0.csv", .{out_dir});
        const tiff_path = try std.fmt.allocPrint(aa, "{s}/cam0_frame0_field0.tiff", .{out_dir});
        var csv = try iio.loadImage(F, 1, aa, io, csv_path, .csv);
        defer csv.deinit(aa);
        var tiff = try iio.loadImage(u16, 1, aa, io, tiff_path, .tiff);
        defer tiff.deinit(aa);
        for (0..camera_input.pixels_num[1]) |row| {
            for (0..camera_input.pixels_num[0]) |col| {
                const raw = rendered.get(&.{ 0, 0, 0, row, col });
                try std.testing.expectApproxEqAbs(raw, csv.getVal(0, row, col), @as(F, 0.0001));
                const norm = std.math.clamp(raw / 255.0, 0, 1);
                const code: u16 = @intFromFloat(@round(norm * 4095.0));
                const expected: u16 = switch (packing) {
                    .lower => code,
                    .upper => code << 4,
                    .spread => @intFromFloat(@round(@as(F, @floatFromInt(code)) * 65535.0 / 4095.0)),
                };
                try std.testing.expectEqual(expected, tiff.getVal(0, row, col));
            }
        }
    }
}

fn runMixedCameraOutput(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    base_config: rastcfg.RasterConfig,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();
    const mono_meshes = try common_full.buildScene2ImageOutputMeshes(
        aa,
        prep,
        textures,
        false,
        false,
    );
    const rgb_meshes = try common_full.buildScene2ImageOutputMeshes(
        aa,
        prep,
        textures,
        true,
        false,
    );
    const meshes = [_]MeshInput{
        mono_meshes[0], mono_meshes[1], rgb_meshes[0], rgb_meshes[1],
    };
    var mono_camera = common_full.createScene2ImageOutputCamera(&mono_meshes);
    mono_camera.output_files = &.{.{ .format = .bmp, .file_bits = 8 }};
    var rgb_camera = common_full.createScene2ImageOutputCamera(&rgb_meshes);
    rgb_camera.output_files = &.{.{ .format = .fimg, .file_bits = null }};
    const cameras = [_]CameraInput{ mono_camera, rgb_camera };
    const out_dir = "temp-tests/image_output_mixed_cameras";
    var config = base_config;
    config.save_strategy = .both;
    const saved = (try riley.raster(
        aa,
        io,
        &cameras,
        &meshes,
        config,
        out_dir,
    )) orelse return error.NoResult;
    try std.testing.expectEqual(@as(usize, 2), saved.dims[0]);
    try std.testing.expectEqual(@as(usize, 3), saved.dims[2]);
    for (1..3) |ch| {
        for (0..saved.dims[3]) |row| {
            for (0..saved.dims[4]) |col| {
                try std.testing.expectEqual(
                    base_config.background_value,
                    saved.get(&.{ 0, 0, ch, row, col }),
                );
            }
        }
    }
    var bmp = try std.Io.Dir.cwd().openFile(
        io,
        out_dir ++ "/cam0_frame0_field0.bmp",
        .{},
    );
    bmp.close(io);
    var rgb_file = try std.Io.Dir.cwd().openFile(
        io,
        out_dir ++ "/cam1_frame0_field0.fimg",
        .{},
    );
    rgb_file.close(io);

    var memory_config = config;
    memory_config.save_strategy = .memory;
    const unsaved = (try riley.raster(
        aa,
        io,
        &cameras,
        &meshes,
        memory_config,
        null,
    )) orelse return error.NoResult;
    try std.testing.expectEqualSlices(F, unsaved.slice, saved.slice);

    var ir_meshes = mono_meshes;
    for (&ir_meshes, 0..) |*mesh, ii| {
        mesh.shaders = .{ .ir_direct = mono_meshes[ii].shaders.mono_direct };
    }
    var ir_camera = mono_camera;
    ir_camera.render_format = .ir;
    ir_camera.output_files = &.{.{ .format = .tiff, .file_bits = 16, .scaling = .{ .fixed = .{ 0, 255 } } }};
    const ir_dir = "temp-tests/image_output_ir_camera";
    const ir_saved = (try riley.raster(
        aa,
        io,
        &.{ir_camera},
        &ir_meshes,
        config,
        ir_dir,
    )) orelse return error.NoResult;
    const ir_raw = (try riley.raster(
        aa,
        io,
        &.{ir_camera},
        &ir_meshes,
        memory_config,
        null,
    )) orelse return error.NoResult;
    try std.testing.expectEqualSlices(F, ir_raw.slice, ir_saved.slice);
    var ir_file = try std.Io.Dir.cwd().openFile(
        io,
        ir_dir ++ "/cam0_frame0_field0.tiff",
        .{},
    );
    ir_file.close(io);

    var invalid_camera = mono_camera;
    invalid_camera.output_files = &.{ .{ .format = .bmp }, .{ .format = .bmp } };
    try std.testing.expectError(
        error.InvalidImageSaveOpts,
        riley.raster(aa, io, &.{invalid_camera}, &mono_meshes, config, out_dir),
    );
}

fn runAdditionalImageOutputTests(
    allocator: std.mem.Allocator,
    io: std.Io,
    prep: *const common_full.Scene2Prepared,
    textures: *const common_full.FullTextures,
    config: rastcfg.RasterConfig,
) !void {
    const temp_dir_base = "temp-tests/image_output_additional";
    var dir = try orch.openDirEnsured(io, temp_dir_base);
    dir.close(io);

    const meshes_mono = try common_full.buildScene2ImageOutputMeshes(
        allocator,
        prep,
        textures,
        false,
        false,
    );
    const cam_inp = common_full.createScene2ImageOutputCamera(&meshes_mono);

    // 1. Disk vs Memory output reload round-trip
    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const out_subdir = try std.fmt.allocPrint(
            aa,
            "{s}/reload_roundtrip",
            .{temp_dir_base},
        );
        var sub_dir = try orch.openDirEnsured(io, out_subdir);
        sub_dir.close(io);

        var run_config = config;
        run_config.save_strategy = .both;

        var fimg_camera = cam_inp;
        fimg_camera.output_files = &.{.{ .format = .fimg, .file_bits = null }};
        const result = try riley.raster(
            aa,
            io,
            &[_]CameraInput{fimg_camera},
            &meshes_mono,
            run_config,
            out_subdir,
        );
        const mem_img = result orelse return error.NoResult;

        const fimg_path = try std.fmt.allocPrint(
            aa,
            "{s}/cam0_frame0_field0.fimg",
            .{out_subdir},
        );
        var disk_img = try iio.loadFIMG(aa, io, fimg_path);
        defer {
            aa.free(disk_img.slice);
            disk_img.deinit(aa);
        }

        const rows_n = mem_img.dims[3];
        const cols_n = mem_img.dims[4];
        for (0..rows_n) |rr| {
            for (0..cols_n) |cc| {
                const mem_val = mem_img.get(&[_]usize{ 0, 0, 0, rr, cc });
                const disk_val = disk_img.get(&[_]usize{ 0, rr, cc });
                try std.testing.expectEqual(mem_val, disk_val);
            }
        }
    }

    // 2. save_frame_buff_count sweep
    const buff_counts = [_]usize{ 1, 2, 4 };
    for (buff_counts) |bc_val| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        var run_config = config;
        run_config.save_strategy = .memory;
        run_config.output.save_frame_buff_count = bc_val;

        const result = try riley.raster(
            aa,
            io,
            &[_]CameraInput{cam_inp},
            &meshes_mono,
            run_config,
            null,
        );
        const img = result orelse return error.NoResult;
        try std.testing.expect(img.slice.len > 0);
    }

    // Source channel conversion is tested through shader pipes in test_basic_shaderpipe.

}
