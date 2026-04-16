// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const gen_small = @import("gen_gold_small.zig");
const gen_simple = @import("gen_gold_simple.zig");
const gen_edge = @import("gen_gold_edge.zig");
const gen_multimesh = @import("gen_gold_multimesh.zig");
const gen_fullscreen = @import("gen_gold_bench_fullscreen.zig");
const gen_sphere = @import("gen_gold_sphere.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    // const aa = arena.allocator();

    // Intentionally excludes the committed `min` suite, which is
    // generated separately by `gen_gold_min.zig`.
    std.debug.print("Generating ALL SIMD Gold Data...\n\n", .{});

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

    std.debug.print("\nALL SIMD Gold Data generation complete.\n", .{});
}
