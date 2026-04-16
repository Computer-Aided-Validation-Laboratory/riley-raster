// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .fimg, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    std.debug.print("Generating Multimesh Gold Data...\n", .{});
    try gengold.runMultimeshGeneration(allocator, io, config);
    try gengold.runMultimeshMixedGeneration(allocator, io, config);
    try gengold.runMultimeshMixedRGBGeneration(allocator, io, config);
    std.debug.print("Done.\n", .{});
}
