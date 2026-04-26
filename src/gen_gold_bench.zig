// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("common/benchcommon.zig");
const mo = @import("zraster/zig/meshops.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const zraster = @import("zraster/zig/zraster.zig");

const cfg = buildconfig.config;
const simd_on = cfg.simd == .on;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture_grey = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    const texture_rgb = try iio.loadImage(
        u8,
        3,
        aa,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );

    const pixel_num = [_]u32{ 800, 500 };

    const cases = [_]struct {
        name: []const u8,
        data_name: []const u8,
        gold_dir: []const u8,
        is_sphere: bool = false,
        fov_scale: f64 = 1.0,
    }{
        .{
            .name = "fullraster",
            .data_name = "fullraster",
            .gold_dir = "gold-bench-fullscreen",
        },
        .{
            .name = "geom",
            .data_name = "geom",
            .gold_dir = "gold-bench-fullscreen",
        },
        .{
            .name = "sphere2000",
            .data_name = "sphere2000",
            .gold_dir = if (simd_on) "gold-simd-sphere2000" else "gold-sphere2000",
            .is_sphere = true,
        },
        .{
            .name = "sphere2000zoom",
            .data_name = "sphere2000",
            .gold_dir = if (simd_on)
                "gold-simd-sphere2000zoom"
            else
                "gold-sphere2000zoom",
            .is_sphere = true,
            .fov_scale = 0.5,
        },
    };

    const mesh_types = std.enums.values(mo.MeshType);
    const shader_types = std.enums.values(common.ShaderType);
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

    std.debug.print("Generating Gold Data for Bench Suite...\n", .{});
    std.debug.print("SIMD is {s}\n", .{if (simd_on) "ON" else "OFF"});

    for (cases) |cc| {
        std.debug.print("\n--- Case: {s} ---\n", .{cc.name});

        if (!simd_on and cc.is_sphere) {
            std.debug.print(
                "Skipping scalar sphere gold generation.\n",
                .{},
            );
            continue;
        }

        for (mesh_types) |mt| {
            for (shader_types) |st| {
                for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        aa,
                        "data-bench/{s}_{s}",
                        .{ @tagName(mt), cc.data_name },
                    );

                    const run_config = if (cc.is_sphere)
                        common.BenchConfig{
                            .run = .all,
                            .skip_quad4ibi_sphere = true,
                        }
                    else
                        common.BenchConfig{ .run = .all };

                    if (common.shouldRun(run_config, mt, st, sc, data_dir)) {
                        const is_rgb = (st == .nodal_rgb or st == .tex8_rgb);
                        const channels: u8 = if (is_rgb) 3 else 1;

                        const save_opts = [_]iio.ImageSaveOpts{
                            .{ .format = .fimg, .bits = null, .scaling = .none, .channels = channels },
                            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = channels },
                        };

                        const options = common.BenchOptions{
                            .out_dir_base = cc.gold_dir,
                            .save_opts = &save_opts,
                            .fov_scale = cc.fov_scale,
                        };

                        const case_name = try common.calcCaseName(
                            aa,
                            mt,
                            st,
                            sc,
                            options,
                        );

                        std.debug.print(
                            "Rendering reference: {s}/{s}\n",
                            .{ cc.gold_dir, case_name },
                        );

                        _ = try common.runBenchmarkQuiet(
                            aa,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
                            options,
                        );
                    }
                }
            }
        }
    }

    std.debug.print("\nDone. Benchmark gold references established.\n", .{});
}
