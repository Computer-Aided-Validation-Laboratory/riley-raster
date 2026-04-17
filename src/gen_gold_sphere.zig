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
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");

const cfg = buildconfig.config;

const simd_on = cfg.simd == .on;

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

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

    const cases = [_]struct { ds: []const u8, out: []const u8 }{
        .{
            .ds = "sphere2000",
            .out = if (simd_on) "gold-simd-sphere2000" else "gold-sphere2000",
        },
    };

    std.debug.print("Generating Sphere Gold data with .simd = .{s}...\n", .{
        if (simd_on) "on" else "off",
    });

    for (cases) |case| {
        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        aa,
                        "data-bench/{s}_{s}",
                        .{ @tagName(mt), case.ds },
                    );

                    if (common.shouldRun(
                        .{ .run = .all, .skip_quad4ibi_sphere = true },
                        mt,
                        st,
                        sc,
                        data_dir,
                    )) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}_{s}_{s}",
                                .{ @tagName(mt), @tagName(st), @tagName(sc.sample), @tagName(sc.mode) },
                            )
                        else
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );

                        std.debug.print(
                            "Rendering reference: {s}/{s}\n",
                            .{ case.out, case_name },
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
                            .{ .out_dir_base = case.out },
                        );
                    }
                }
            }
        }
    }

    std.debug.print("\nDone. Sphere gold references established.\n", .{});
}
