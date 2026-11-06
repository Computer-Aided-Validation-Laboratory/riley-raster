// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const oneelem = @import("../tests/test_basic_oneelem.zig");
const hull = @import("../tests/test_full_hull.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    std.debug.print(
        "Running warning-only invalid-Jacobian diagnostic renders.\n",
        .{},
    );
    oneelem.runBadJac(allocator, io);
    hull.runBadJac(allocator, io);
    std.debug.print(
        "Invalid-Jacobian diagnostic renders complete.\n",
        .{},
    );
}
