// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
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
const gen_multicamera = @import("gen_gold_multicamera.zig");
const gen_hull = @import("gen_gold_hull.zig");
const gen_fullscreen = @import("gen_gold_bench_fullscreen.zig");
const gen_sphere = @import("gen_gold_sphere.zig");
const gen_texfunc = @import("gen_gold_texfunc.zig");
const gen_ssaa = @import("gen_gold_ssaa.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();

    // Intentionally excludes the committed `min` suite, which is
    // generated separately by `gen_gold_min.zig`.
    std.debug.print("Generating ALL SIMD Gold Data...\n\n", .{});

    std.debug.print("--- Small ---\n", .{});
    try gen_small.main(init);

    std.debug.print("\n--- Simple ---\n", .{});
    try gen_simple.main(init);

    std.debug.print("\n--- Edge ---\n", .{});
    try gen_edge.main(init);

    std.debug.print("\n--- Multimesh ---\n", .{});
    try gen_multimesh.main(init);

    std.debug.print("\n--- Multicamera ---\n", .{});
    try gen_multicamera.main(init);

    std.debug.print("\n--- Hull ---\n", .{});
    try gen_hull.main(init);

    std.debug.print("\n--- Fullscreen ---\n", .{});
    try gen_fullscreen.main(init);

    std.debug.print("\n--- Sphere ---\n", .{});
    try gen_sphere.main(init);

    std.debug.print("\n--- TexFunc ---\n", .{});
    try gen_texfunc.main(init);

    std.debug.print("\n--- SSAA ---\n", .{});
    try gen_ssaa.main(init);

    std.debug.print("\nALL SIMD Gold Data generation complete.\n", .{});
}
