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
const buildconfig = @import("zraster/zig/buildconfig.zig");
const common = @import("common/benchcommon.zig");
const minsuite = @import("common/minsuite.zig");
const tests = @import("common/tests.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");
const tcfg = @import("common/testconfig.zig");

const simd_on = buildconfig.config.simd == .on;

test "MIN Suite: sphere200 and multimesh" {
    const allocator = std.testing.allocator;
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

    const gold_dir = "gold-min";
    const pixel_num_sphere = [_]u32{ 160, 100 };
    const pixel_num_multi = [_]u32{ 640, 400 };

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    var total_fails: usize = 0;

    if (simd_on) {
        std.debug.print("\nRunning MIN Suite sphere200/base tests...\n", .{});
        for (mesh_types) |mt| {
            for (shader_types) |st| {
                for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        allocator,
                        "data-min/{s}_sphere200",
                        .{@tagName(mt)},
                    );
                    defer allocator.free(data_dir);

                    const is_rgb = (st == .tex8_rgb or st == .nodal_rgb);
                    const is_allowed_rgb = (st == .nodal_rgb) or
                        (st == .tex8_rgb and
                            sc.sample == .cubic_catmull_rom and
                            sc.mode == .lut_lerp);

                    if (is_rgb and !is_allowed_rgb) continue;

                    if (common.shouldRun(
                        .{ .run = .all, .skip_quad4ibi_sphere = true },
                        mt,
                        st,
                        sc,
                        data_dir,
                    )) {
                        const options = common.BenchOptions{
                            .return_image = true,
                            .save_opts = &[_]iio.ImageSaveOpts{},
                            .fov_scale = 1.0,
                            .hull_mode = .on_convex_fallback,
                        };

                        const case_name = try minsuite.calcMinCaseName(
                            allocator,
                            mt,
                            st,
                            sc,
                        );
                        defer allocator.free(case_name);
                        std.debug.print("Testing sphere200/base/{s} ... ", .{case_name});

                        const time_start = Timestamp.now(io, .awake);
                        var result = try common.runBenchmarkQuiet(
                            allocator,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            pixel_num_sphere,
                            texture_grey,
                            texture_rgb,
                            options,
                        );
                        defer result.deinit(allocator);
                        const time_end = Timestamp.now(io, .awake);
                        const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;

                        const gold_case_dir = try std.fs.path.join(
                            allocator,
                            &[_][]const u8{
                                gold_dir,
                                "sphere200",
                                "base",
                                case_name,
                            },
                        );
                        defer allocator.free(gold_case_dir);
                        const gold_fname = try tests.findGoldPath(
                            allocator,
                            io,
                            gold_case_dir,
                            0,
                            0,
                            0,
                            is_rgb,
                        );
                        defer allocator.free(gold_fname);

                        const channels: usize = if (is_rgb) 3 else 1;
                        tests.compareNDArrayToGold(
                            allocator,
                            io,
                            &result.image.?,
                            0,
                            0,
                            0,
                            channels,
                            gold_fname,
                            tcfg.REL_TOL,
                            tcfg.ABS_TOL,
                        ) catch |err| {
                            try tests.saveComparisonArtifactsFromResult(
                                allocator,
                                io,
                                "fails",
                                case_name,
                                &result.image.?,
                                0,
                                0,
                                0,
                                gold_fname,
                                channels,
                            );
                            if (err == error.PixelMismatch) {
                                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
                                total_fails += 1;
                                continue;
                            }
                            return err;
                        };
                        std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
                    }
                }
            }
        }

        std.debug.print("Running MIN Suite sphere200multicull tests...\n", .{});
        for (mesh_types) |mt| {
            for (shader_types) |st| {
                for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        allocator,
                        "data-min/{s}_sphere200",
                        .{@tagName(mt)},
                    );
                    defer allocator.free(data_dir);

                    const is_rgb = (st == .tex8_rgb or st == .nodal_rgb);
                    const is_allowed_rgb = (st == .nodal_rgb) or
                        (st == .tex8_rgb and
                            sc.sample == .cubic_catmull_rom and
                            sc.mode == .lut_lerp);

                    if (is_rgb and !is_allowed_rgb) continue;

                    if (common.shouldRun(
                        .{ .run = .all, .skip_quad4ibi_sphere = true },
                        mt,
                        st,
                        sc,
                        data_dir,
                    )) {
                        const options = common.BenchOptions{
                            .return_image = true,
                            .save_opts = &[_]iio.ImageSaveOpts{},
                            .fov_scale = 0.75,
                            .hull_mode = .on_convex_fallback,
                        };

                        const case_name = try minsuite.calcMinCaseName(
                            allocator,
                            mt,
                            st,
                            sc,
                        );
                        defer allocator.free(case_name);
                        std.debug.print("Testing sphere200/multicull/{s} ... ", .{case_name});

                        const time_start = Timestamp.now(io, .awake);
                        var result = try minsuite.runSphere200MultiCullQuiet(
                            allocator,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            pixel_num_sphere,
                            texture_grey,
                            texture_rgb,
                            options,
                        );
                        defer result.deinit(allocator);
                        const time_end = Timestamp.now(io, .awake);
                        const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;

                        const gold_case_dir = try std.fs.path.join(
                            allocator,
                            &[_][]const u8{
                                gold_dir,
                                "sphere200multicull",
                                case_name,
                            },
                        );
                        defer allocator.free(gold_case_dir);
                        const gold_fname = try tests.findGoldPath(
                            allocator,
                            io,
                            gold_case_dir,
                            0,
                            0,
                            0,
                            is_rgb,
                        );
                        defer allocator.free(gold_fname);

                        const channels: usize = if (is_rgb) 3 else 1;
                        tests.compareNDArrayToGold(
                            allocator,
                            io,
                            &result.image.?,
                            0,
                            0,
                            0,
                            channels,
                            gold_fname,
                            tcfg.REL_TOL,
                            tcfg.ABS_TOL,
                        ) catch |err| {
                            try tests.saveComparisonArtifactsFromResult(
                                allocator,
                                io,
                                "fails",
                                case_name,
                                &result.image.?,
                                0,
                                0,
                                0,
                                gold_fname,
                                channels,
                            );
                            if (err == error.PixelMismatch) {
                                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
                                total_fails += 1;
                                continue;
                            }
                            return err;
                        };
                        std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
                    }
                }
            }
        }
    } else {
        std.debug.print(
            "\nSkipping MIN Suite sphere200 tests with .simd = .off...\n",
            .{},
        );
    }

    std.debug.print("Running MIN Suite multimesh tests...\n", .{});
    const multi_dir_paths = [_][]const u8{
        "data-min/tri3_twoelems/",
        "data-min/tri6_twoelems/",
        "data-min/quad4_twoelems/",
        "data-min/quad8_twoelems/",
        "data-min/quad9_twoelems/",
    };

    {
        std.debug.print("Testing multimesh/base ... ", .{});
        const time_start = Timestamp.now(io, .awake);
        tests.runMultimeshTestExt(
            allocator,
            io,
            gold_dir ++ "/multimesh/base",
            &multi_dir_paths,
            pixel_num_multi,
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
        ) catch |err| {
            const time_end = Timestamp.now(io, .awake);
            const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
            if (err == error.PixelMismatch) {
                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
            } else {
                std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
            }
            total_fails += 1;
            if (err != error.PixelMismatch) {
                return err;
            }
        };
        const time_end = Timestamp.now(io, .awake);
        const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
        std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
    }

    {
        std.debug.print("Testing multimesh/allelem_allshade ... ", .{});
        const time_start = Timestamp.now(io, .awake);
        tests.runMultimeshMixedTestExt(
            allocator,
            io,
            gold_dir ++ "/multimesh/allelem_allshade",
            &multi_dir_paths,
            pixel_num_multi,
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
        ) catch |err| {
            const time_end = Timestamp.now(io, .awake);
            const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
            if (err == error.PixelMismatch) {
                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
            } else {
                std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
            }
            total_fails += 1;
            if (err != error.PixelMismatch) {
                return err;
            }
        };
        const time_end = Timestamp.now(io, .awake);
        const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
        std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
    }

    {
        std.debug.print("Testing multimesh/allelem_allshade_rgb ... ", .{});
        const time_start = Timestamp.now(io, .awake);
        tests.runMultimeshMixedRGBTestExt(
            allocator,
            io,
            gold_dir ++ "/multimesh/allelem_allshade_rgb",
            &multi_dir_paths,
            pixel_num_multi,
            tcfg.REL_TOL,
            tcfg.ABS_TOL,
        ) catch |err| {
            const time_end = Timestamp.now(io, .awake);
            const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
            if (err == error.PixelMismatch) {
                std.debug.print("MISMATCH! ({d:.2} ms)\n", .{duration_ms});
            } else {
                std.debug.print("ERROR! ({d:.2} ms)\n", .{duration_ms});
            }
            total_fails += 1;
            if (err != error.PixelMismatch) {
                return err;
            }
        };
        const time_end = Timestamp.now(io, .awake);
        const duration_ms = @as(f64, @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds)) / 1e6;
        std.debug.print("MATCHED ({d:.2} ms)\n", .{duration_ms});
    }

    if (total_fails != 0) {
        std.debug.print(
            "MIN Suite found {d} failing cases.\n",
            .{total_fails},
        );
        return error.TestUnexpectedResult;
    }

    std.debug.print("MIN Suite tests passed.\n", .{});
}
