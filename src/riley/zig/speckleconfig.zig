// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
//! Procedural speckle build policy, independent of root/build_options and runtime code.
//! Validate option domains even when the selected evaluator or shape does not use them.
const std = @import("std");

pub const Shape = enum { disk, gaussian, perlin };
pub const Evaluator = enum {
    cell_hash,
    list_naive,
    list_indexed,
    classified_indexed,
    direct_fixed,
    mask_1bit,
    mask_u8,
};

pub const default_neighbor_count: u8 = 9;
pub const default_mask_samples_per_cell: u8 = 12;
pub const default_evaluator = "classified-indexed";
pub const default_shape = "disk";

pub const CompatibilityError = error{
    PerlinRequiresMaskU8,
    Mask1BitRequiresDisk,
    ClassifiedIndexedRequiresDiskAndNineNeighbors,
    DirectFixedRequiresDiskAndOneNeighbor,
};

/// Exact, case-sensitive build option spelling; null means an unsupported name.
pub fn parseShape(name: []const u8) ?Shape {
    return std.meta.stringToEnum(Shape, name);
}

/// Hyphenated build option names, not the underscore-separated Zig enum tags.
pub fn parseEvaluator(name: []const u8) ?Evaluator {
    if (std.mem.eql(u8, name, "cell-hash")) return .cell_hash;
    if (std.mem.eql(u8, name, "list-naive")) return .list_naive;
    if (std.mem.eql(u8, name, "list-indexed")) return .list_indexed;
    if (std.mem.eql(u8, name, "classified-indexed")) return .classified_indexed;
    if (std.mem.eql(u8, name, "direct-fixed")) return .direct_fixed;
    if (std.mem.eql(u8, name, "mask-1bit")) return .mask_1bit;
    if (std.mem.eql(u8, name, "mask-u8")) return .mask_u8;
    return null;
}

// Accept integer types without narrowing: direct build_options may use comptime_int.
pub fn isValidNeighborCount(count: anytype) bool {
    return count == 9 or count == 4 or count == 1;
}

pub fn isValidMaskSamplesPerCell(samples: anytype) bool {
    return samples == 8 or samples == 12 or samples == 16;
}

/// Check compatibility after validating the option domains. Perlin requires mask-u8;
/// mask-1bit requires disk; classified-indexed/direct-fixed require disk and 9/1 neighbors.
/// Perlin is checked first so both build entry points report the same incompatibility.
pub fn validateCompatibility(
    evaluator: Evaluator,
    shape: Shape,
    neighbor_count: anytype,
) CompatibilityError!void {
    if (shape == .perlin and evaluator != .mask_u8) return error.PerlinRequiresMaskU8;
    switch (evaluator) {
        .mask_1bit => if (shape != .disk) return error.Mask1BitRequiresDisk,
        .classified_indexed => if (shape != .disk or neighbor_count != 9)
            return error.ClassifiedIndexedRequiresDiskAndNineNeighbors,
        .direct_fixed => if (shape != .disk or neighbor_count != 1)
            return error.DirectFixedRequiresDiskAndOneNeighbor,
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => {},
    }
}

pub fn describeCompatibilityError(err: CompatibilityError) []const u8 {
    return switch (err) {
        error.PerlinRequiresMaskU8 => "speckle shape perlin requires evaluator mask-u8.",
        error.Mask1BitRequiresDisk => "speckle evaluator mask-1bit requires disk shape.",
        error.ClassifiedIndexedRequiresDiskAndNineNeighbors => "speckle evaluator classified-indexed requires disk shape and neighbor count 9.",
        error.DirectFixedRequiresDiskAndOneNeighbor => "speckle evaluator direct-fixed requires disk shape and neighbor count 1.",
    };
}

test "speckle option names are exact and preserve enum tags" {
    for (std.enums.values(Shape)) |shape| {
        try std.testing.expectEqual(shape, parseShape(@tagName(shape)).?);
    }
    const names = [_][]const u8{
        "cell-hash",    "list-naive", "list-indexed", "classified-indexed",
        "direct-fixed", "mask-1bit",  "mask-u8",
    };
    for (names, std.enums.values(Evaluator)) |name, evaluator| {
        try std.testing.expectEqual(evaluator, parseEvaluator(name).?);
        try std.testing.expectEqual(null, parseEvaluator(@tagName(evaluator)));
    }
    for ([_][]const u8{ "", "Disk", "DISK", "disk ", " gaussian", "perlin\n", "sphere" }) |name| {
        try std.testing.expectEqual(null, parseShape(name));
    }
    for ([_][]const u8{ "", "Cell-hash", "MASK-U8", "cell-hash ", " mask-u8", "mask-u8\n", "mask" }) |name| {
        try std.testing.expectEqual(null, parseEvaluator(name));
    }
}

test "speckle numeric domains include only the supported counts and resolutions" {
    for (0..256) |value| {
        const count: u8 = @intCast(value);
        try std.testing.expectEqual(
            std.mem.indexOfScalar(u8, &.{ 9, 4, 1 }, count) != null,
            isValidNeighborCount(count),
        );
        try std.testing.expectEqual(
            std.mem.indexOfScalar(u8, &.{ 8, 12, 16 }, count) != null,
            isValidMaskSamplesPerCell(count),
        );
    }
    inline for (.{ -1, 256, 1 << 100 }) |value| {
        try std.testing.expect(!isValidNeighborCount(value));
        try std.testing.expect(!isValidMaskSamplesPerCell(value));
    }
}

test "speckle compatibility covers every evaluator shape and neighbor count" {
    const cases = [_]struct {
        evaluator: Evaluator,
        // Independently specified valid counts for disk, gaussian, and perlin.
        valid_counts: [3][]const u8,
    }{
        .{ .evaluator = .cell_hash, .valid_counts = .{ &.{ 9, 4, 1 }, &.{ 9, 4, 1 }, &.{} } },
        .{ .evaluator = .list_naive, .valid_counts = .{ &.{ 9, 4, 1 }, &.{ 9, 4, 1 }, &.{} } },
        .{ .evaluator = .list_indexed, .valid_counts = .{ &.{ 9, 4, 1 }, &.{ 9, 4, 1 }, &.{} } },
        .{ .evaluator = .classified_indexed, .valid_counts = .{ &.{9}, &.{}, &.{} } },
        .{ .evaluator = .direct_fixed, .valid_counts = .{ &.{1}, &.{}, &.{} } },
        .{ .evaluator = .mask_1bit, .valid_counts = .{ &.{ 9, 4, 1 }, &.{}, &.{} } },
        .{ .evaluator = .mask_u8, .valid_counts = .{ &.{ 9, 4, 1 }, &.{ 9, 4, 1 }, &.{ 9, 4, 1 } } },
    };
    for (cases) |case| {
        for ([_]Shape{ .disk, .gaussian, .perlin }, case.valid_counts) |shape, valid_counts| {
            for ([_]u8{ 9, 4, 1 }) |count| {
                const expected = std.mem.indexOfScalar(u8, valid_counts, count) != null;
                const result = validateCompatibility(case.evaluator, shape, count);
                if (result) |_| {
                    try std.testing.expect(expected);
                } else |_| {
                    try std.testing.expect(!expected);
                }
            }
        }
    }
}

test "speckle compatibility errors identify the violated requirement" {
    const cases = [_]struct {
        evaluator: Evaluator,
        shape: Shape,
        count: u8,
        err: CompatibilityError,
        message: []const u8,
    }{
        .{
            .evaluator = .cell_hash,
            .shape = .perlin,
            .count = 9,
            .err = error.PerlinRequiresMaskU8,
            .message = "speckle shape perlin requires evaluator mask-u8.",
        },
        .{
            .evaluator = .mask_1bit,
            .shape = .gaussian,
            .count = 9,
            .err = error.Mask1BitRequiresDisk,
            .message = "speckle evaluator mask-1bit requires disk shape.",
        },
        .{
            .evaluator = .classified_indexed,
            .shape = .disk,
            .count = 4,
            .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors,
            .message = "speckle evaluator classified-indexed requires disk shape and neighbor count 9.",
        },
        .{
            .evaluator = .direct_fixed,
            .shape = .disk,
            .count = 9,
            .err = error.DirectFixedRequiresDiskAndOneNeighbor,
            .message = "speckle evaluator direct-fixed requires disk shape and neighbor count 1.",
        },
    };
    for (cases) |case| {
        try std.testing.expectError(case.err, validateCompatibility(case.evaluator, case.shape, case.count));
        try std.testing.expectEqualStrings(case.message, describeCompatibilityError(case.err));
    }
    for (std.enums.values(Evaluator)) |evaluator| {
        if (evaluator == .mask_u8) continue;
        try std.testing.expectError(error.PerlinRequiresMaskU8, validateCompatibility(evaluator, .perlin, 9));
    }
}

test "speckle defaults retain classified disk with nine neighbors and twelve samples" {
    try std.testing.expectEqual(Evaluator.classified_indexed, parseEvaluator(default_evaluator).?);
    try std.testing.expectEqual(Shape.disk, parseShape(default_shape).?);
    try std.testing.expectEqual(9, default_neighbor_count);
    try std.testing.expectEqual(12, default_mask_samples_per_cell);
    try validateCompatibility(parseEvaluator(default_evaluator).?, parseShape(default_shape).?, default_neighbor_count);
    try std.testing.expect(isValidNeighborCount(default_neighbor_count));
    try std.testing.expect(isValidMaskSamplesPerCell(default_mask_samples_per_cell));
}
