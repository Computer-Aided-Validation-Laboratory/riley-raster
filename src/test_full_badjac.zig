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
const oneelem = @import("tests/test_gold_oneelem.zig");
const hull = @import("tests/test_full_hull.zig");

test "invalid-Jacobian diagnostic renders" {
    const io = std.testing.io;
    try testsuites.printStatus(
        io,
        "Running warning-only invalid-Jacobian diagnostic suite.\n",
        .{},
    );
    oneelem.runBadJac(std.testing.allocator, io);
    hull.runBadJac(std.testing.allocator, io);
    try testsuites.printStatus(
        io,
        "Invalid-Jacobian diagnostic suite complete.\n",
        .{},
    );
}
