// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

pub const small = @import("test_gold_small.zig");
pub const simple = @import("test_gold_simple.zig");
pub const edge = @import("test_gold_edge.zig");
pub const multimesh = @import("test_gold_multimesh.zig");
pub const multicamera = @import("test_gold_multicamera.zig");
pub const nodal_normals = @import("test_nodal_normals.zig");
pub const texfunc = @import("test_texfunc.zig");

pub fn main(init: std.process.Init) !void {
    _ = init;
    std.debug.print("Running ALL Gold Test Suites...\n", .{});

    std.debug.print(
        "Please use 'zig test -lc -O ReleaseSafe src/test_gold_all.zig' " ++
            "to run all tests.\n",
        .{},
    );
}

test {
    std.testing.refAllDecls(@This());
}
