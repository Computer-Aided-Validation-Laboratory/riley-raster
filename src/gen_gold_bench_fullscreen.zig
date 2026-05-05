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
const tcfg = @import("common/testconfig.zig");
const mo = @import("zraster/zig/meshops.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
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

    const out_dir_base = "gold/bench-fullscreen";
    const pixel_num = [_]u32{ 800, 500 };

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

    std.debug.print(
        "Generating Unified Fullscreen Gold data to {s}/...\n",
        .{out_dir_base},
    );

    inline for (mesh_types) |mt| {
        inline for (shader_types) |st| {
            inline for (sample_configs) |sc| {
                const data_dir = comptime "data/bench/" ++ @tagName(mt) ++ "_fullraster";
                if (common.shouldRun(.{ .run = .all }, mt, st, sc, data_dir)) {
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
                    std.debug.print("Rendering reference: {s}\n", .{case_name});

                    // We generate gold from the minimal 'fullraster' dataset
                    var r_config = tcfg.getRasterConfig(.bench);
                    r_config.save_strategy = .disk;
                    _ = try common.runBenchmarkQuiet(
                        aa,
                        io,
                        mt,
                        st,
                        sc,
                        data_dir,
                        pixel_num,
                        2,
                        texture_grey,
                        texture_rgb,
                        r_config,
                        out_dir_base,
                        1.0,
                    );
                }
            }
        }
    }

    std.debug.print("\nDone. Unified gold references established.\n", .{});
}
