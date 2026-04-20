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
const common = @import("common/benchcommon.zig");
const tests = @import("common/tests.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub const REL_TOL: f64 = 2.0e-10;
pub const ABS_TOL: f64 = 1.0e-11;
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

    const mesh_types = comptime std.enums.values(mr.MeshType);
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

    if (simd_on) {
        std.debug.print("\nRunning MIN Suite sphere200 tests...\n", .{});
        for (mesh_types) |mt| {
            for (shader_types) |st| {
                for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        allocator,
                        "data-min/{s}_sphere200",
                        .{@tagName(mt)},
                    );
                    defer allocator.free(data_dir);

                    // Filter for Min Suite:
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
                            .{
                                .return_image = true,
                                .save_opts = &[_]iio.ImageSaveOpts{},
                            },
                        );
                        defer result.deinit(allocator);

                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}_{s}_{s}",
                                .{
                                    @tagName(mt),
                                    @tagName(st),
                                    @tagName(sc.sample),
                                    @tagName(sc.mode),
                                },
                            )
                        else
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );
                        defer allocator.free(case_name);

                        const gold_case_dir = try std.fs.path.join(
                            allocator,
                            &[_][]const u8{ gold_dir, case_name },
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
                            REL_TOL,
                            ABS_TOL,
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
                            return err;
                        };
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

    try tests.runMultimeshTestExt(
        allocator,
        io,
        gold_dir,
        &multi_dir_paths,
        pixel_num_multi,
        REL_TOL,
        ABS_TOL,
    );
    try tests.runMultimeshMixedTestExt(
        allocator,
        io,
        gold_dir ++ "/allelem_allshade",
        &multi_dir_paths,
        pixel_num_multi,
        REL_TOL,
        ABS_TOL,
    );
    try tests.runMultimeshMixedRGBTestExt(
        allocator,
        io,
        gold_dir ++ "/allelem_allshade_rgb",
        &multi_dir_paths,
        pixel_num_multi,
        REL_TOL,
        ABS_TOL,
    );

    std.debug.print("MIN Suite tests passed.\n", .{});
}
