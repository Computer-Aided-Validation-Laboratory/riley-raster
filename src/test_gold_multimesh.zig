// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");

test "Gold Multimesh Suite" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const start_time = std.Io.Clock.Timestamp.now(io, .awake);

    try common.runMultimeshTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);
    try common.runMultimeshMixedTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);
    try common.runMultimeshMixedRGBTest(allocator, io, tcfg.REL_TOL, tcfg.ABS_TOL);

    const end_time = std.Io.Clock.Timestamp.now(io, .awake);
    const duration_ms = @as(
        f64,
        @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
    ) / 1e6;
    std.debug.print("Multi-Mesh Test Suite took {d:.3} ms\n", .{duration_ms});
}
