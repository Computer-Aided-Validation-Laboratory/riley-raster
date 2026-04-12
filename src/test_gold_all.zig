const std = @import("std");

pub const small = @import("test_gold_small.zig");
pub const simple = @import("test_gold_simple.zig");
pub const edge = @import("test_gold_edge.zig");
pub const multimesh = @import("test_gold_multimesh.zig");
pub const nodal_normals = @import("test_nodal_normals.zig");

pub fn main() !void {
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
