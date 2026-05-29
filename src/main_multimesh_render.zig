// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const gengold = @import("common/gengold.zig");
const tcfg = @import("common/testconfig.zig");
const riley = @import("riley/zig/riley.zig");
const iio = @import("riley/zig/imageio.zig");

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var config = tcfg.getRasterConfig(.preview);
    config.save_strategy = .disk;
    config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
        .{ .format = .csv, .bits = null, .scaling = .none },
    };
    config.report = .full_stats;
    config.full_stats_opts = .{
        .formats = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .save_iteration_map = true,
        .save_depth_map = true,
    };
    const dir_paths = [_][]const u8{
        "data/simple/tri3_twoelems/",
        "data/simple/tri6_twoelems/",
        "data/simple/quad4_twoelems/",
        "data/simple/quad8_twoelems/",
        "data/simple/quad9_twoelems/",
    };

    const out_dir_root = "out/multimesh";
    std.debug.print("Rendering Multimesh Data to {s}/...\n", .{out_dir_root});

    try gengold.runMultimeshGenerationExt(
        outer_alloc,
        io,
        config,
        out_dir_root,
        &dir_paths,
        .{ 1200, 800 },
    );
    try gengold.runMultimeshMixedGenerationExt(
        outer_alloc,
        io,
        config,
        out_dir_root ++ "/allelem_allshade",
        &dir_paths,
        .{ 1600, 800 },
    );
    try gengold.runMultimeshMixedRGBGenerationExt(
        outer_alloc,
        io,
        config,
        out_dir_root ++ "/allelem_allshade_rgb",
        &dir_paths,
        .{ 1200, 800 },
    );

    std.debug.print("Done.\n", .{});
}
