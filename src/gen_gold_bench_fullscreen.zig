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
const Rotation = @import("zraster/zig/rotation.zig").Rotation;

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
    const render_defaults = common.BenchRenderDefaults{
        .pixels_num = pixel_num,
        .sub_sample = 2,
        .focal_leng = 50.0e-3,
        .pixels_size = .{ 5.3e-6, 5.3e-6 },
        .fov_scale = 1.0,
        .rot = Rotation.init(0, 0, 0),
    };

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = [_]common.ShaderType{
        .nodal_grey,
        .nodal_rgb,
        .tex8_grey,
        .tex8_rgb,
    };
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
                    const is_rgb = (st == .nodal_rgb or st == .tex8_rgb);
                    r_config.image_save_opts = if (is_rgb)
                        &[_]iio.ImageSaveOpts{
                            .{ .format = .fimg, .bits = null, .scaling = .none, .channels = 3 },
                            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
                        }
                    else
                        &[_]iio.ImageSaveOpts{
                            .{ .format = .fimg, .bits = null, .scaling = .none },
                            .{ .format = .bmp, .bits = 8, .scaling = .auto },
                        };
                    _ = try common.runBenchmarkQuiet(
                        aa,
                        io,
                        mt,
                        st,
                        sc,
                        null,
                        data_dir,
                        render_defaults,
                        texture_grey,
                        texture_rgb,
                        r_config,
                        out_dir_base,
                    );
                }
            }
        }
    }

    std.debug.print("\nDone. Unified gold references established.\n", .{});
}
