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
const zraster = @import("zraster/zig/zraster.zig");
const iio = @import("zraster/zig/imageio.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const config = zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .fimg, .bits = null, .scaling = .none },
        },
        .report = .off,
    };

    std.debug.print("Generating Multimesh Gold Data...\n", .{});

    try gengold.runMultimeshGeneration(aa, io, config);
    try gengold.runMultimeshMixedGeneration(aa, io, config);
    try gengold.runMultimeshMixedRGBGeneration(aa, io, config);

    std.debug.print("Done.\n", .{});
}
