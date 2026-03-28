const std = @import("std");
const gen_small = @import("gen_gold_small.zig");
const gen_simple = @import("gen_gold_simple.zig");
const gen_edge = @import("gen_gold_edge.zig");
const gen_multimesh = @import("gen_gold_multimesh.zig");
const gen_fullscreen = @import("gen_gold_bench_fullscreen.zig");
const gen_sphere = @import("gen_gold_sphere.zig");

pub fn main() !void {
    std.debug.print("Generating ALL Gold Data...\n\n", .{});

    std.debug.print("--- Small ---\n", .{});
    try gen_small.main();
    
    std.debug.print("\n--- Simple ---\n", .{});
    try gen_simple.main();

    std.debug.print("\n--- Edge ---\n", .{});
    try gen_edge.main();

    std.debug.print("\n--- Multimesh ---\n", .{});
    try gen_multimesh.main();

    std.debug.print("\n--- Fullscreen ---\n", .{});
    try gen_fullscreen.main();

    std.debug.print("\n--- Sphere ---\n", .{});
    try gen_sphere.main();

    std.debug.print("\nALL Gold Data generation complete.\n", .{});
}
