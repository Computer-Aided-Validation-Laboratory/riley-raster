// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const testsuites = @import("dev_support/testsuites.zig");
const demo_common = @import("demo_common.zig");

const oneelem = @import("tests/test_gold_oneelem.zig");
const twoshapes = @import("tests/test_gold_twoshapes.zig");
const featurezoo = @import("tests/test_gold_featurezoo.zig");

test "output reset demo helpers" {
    _ = demo_common;
}

test "basic test suite" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    testsuites.beginSuiteRun();

    try testsuites.printStatus(io, "\nRunning basic test suite.\n\n", .{});
    try testsuites.runSuite("oneelem", allocator, io, oneelem.run);
    try testsuites.runSuite("twoshapes", allocator, io, twoshapes.run);
    try testsuites.runSuite("featurezoo", allocator, io, featurezoo.run);

    const end = std.Io.Clock.Timestamp.now(io, .awake);
    const elapsed_s = testsuites.durationToSeconds(start, end);
    try testsuites.printStatus(
        io,
        "\nBasic test suite complete. Took {d:.3} seconds.\n\n",
        .{elapsed_s},
    );
    try testsuites.finishSuiteRun(io);
}
