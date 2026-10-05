// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
//! Runtime speckle policy and compile-time specialization catalogues.
const std = @import("std");

pub const Pattern = enum(u8) { disk = 0, gaussian = 1, perlin = 2 };
pub const Evaluator = enum(u8) {
    cell_hash,
    list_naive,
    list_indexed,
    classified_indexed,
    direct_fixed,
    mask_1bit,
    mask_u8,
};

pub const Config = struct {
    pattern: Pattern,
    evaluator: Evaluator,
    /// Nine is the internal placeholder for Perlin, which has no neighborhood setting.
    neighbor_count: u8,
    soft_edges: bool,
};

pub const default_pattern: Pattern = .disk;
pub const default_neighbor_count: u8 = 9;
pub const default_mask_samples_per_cell: u8 = 12;

pub const CompatibilityError = error{
    InvalidSpeckleNeighborCount,
    PerlinRequiresMaskU8,
    Mask1BitRequiresDisk,
    ClassifiedIndexedRequiresDiskAndNineNeighbors,
    DirectFixedRequiresDiskAndOneNeighbor,
    SpeckleEdgeSoftnessRequiresDisk,
    SpeckleEvaluatorRequiresHardEdges,
};

pub const ResolveError = CompatibilityError || error{
    SpeckleOverridesDisabled,
    SpecklePerlinDoesNotUseNeighbors,
};

pub fn parsePattern(name: []const u8) ?Pattern {
    return std.meta.stringToEnum(Pattern, name);
}

pub fn parseEvaluator(name: []const u8) ?Evaluator {
    inline for (std.enums.values(Evaluator)) |evaluator| {
        if (std.mem.eql(u8, name, evaluatorName(evaluator))) return evaluator;
    }
    return null;
}

pub fn evaluatorName(evaluator: Evaluator) []const u8 {
    return switch (evaluator) {
        .cell_hash => "cell-hash",
        .list_naive => "list-naive",
        .list_indexed => "list-indexed",
        .classified_indexed => "classified-indexed",
        .direct_fixed => "direct-fixed",
        .mask_1bit => "mask-1bit",
        .mask_u8 => "mask-u8",
    };
}

pub fn isValidNeighborCount(count: anytype) bool {
    return count == 1 or count == 4 or count == 9;
}

pub fn isValidMaskSamplesPerCell(samples: anytype) bool {
    return samples == 8 or samples == 12 or samples == 16;
}

pub fn supportsSoftEdges(config: Config) bool {
    return config.pattern == .disk and switch (config.evaluator) {
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => true,
        .classified_indexed, .direct_fixed, .mask_1bit => false,
    };
}

/// Numerical parameter ranges are checked by Speckle2DParams after policy resolution.
pub fn validateCompatibility(config: Config) CompatibilityError!void {
    if (!isValidNeighborCount(config.neighbor_count)) return error.InvalidSpeckleNeighborCount;
    if (config.pattern == .perlin and config.evaluator != .mask_u8) {
        return error.PerlinRequiresMaskU8;
    }
    switch (config.evaluator) {
        .mask_1bit => if (config.pattern != .disk) return error.Mask1BitRequiresDisk,
        .classified_indexed => if (config.pattern != .disk or config.neighbor_count != 9)
            return error.ClassifiedIndexedRequiresDiskAndNineNeighbors,
        .direct_fixed => if (config.pattern != .disk or config.neighbor_count != 1)
            return error.DirectFixedRequiresDiskAndOneNeighbor,
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => {},
    }
    if (config.soft_edges) {
        if (config.pattern != .disk) return error.SpeckleEdgeSoftnessRequiresDisk;
        if (!supportsSoftEdges(config)) return error.SpeckleEvaluatorRequiresHardEdges;
    }
}

/// Overrides are an experimental-build feature, even when they name a default value.
/// An omitted direct-fixed neighborhood selects one; explicit incompatible values fail.
pub fn resolve(
    comptime enable_all_evaluators: bool,
    pattern: Pattern,
    evaluator: ?Evaluator,
    neighbor_count: ?u8,
    soft_edges: bool,
) ResolveError!Config {
    if (!enable_all_evaluators and (evaluator != null or neighbor_count != null)) {
        return error.SpeckleOverridesDisabled;
    }
    if (pattern == .perlin and neighbor_count != null) {
        return error.SpecklePerlinDoesNotUseNeighbors;
    }
    const neighbors = neighbor_count orelse
        if (evaluator == .direct_fixed) @as(u8, 1) else default_neighbor_count;
    const selected = evaluator orelse switch (pattern) {
        .disk => if (!soft_edges and neighbors == 9)
            Evaluator.classified_indexed
        else
            Evaluator.list_indexed,
        .gaussian => Evaluator.list_indexed,
        .perlin => Evaluator.mask_u8,
    };
    const config: Config = .{
        .pattern = pattern,
        .evaluator = selected,
        .neighbor_count = neighbors,
        .soft_edges = soft_edges,
    };
    try validateCompatibility(config);
    return config;
}

/// Prepared masks no longer depend on how they were generated. Naive lists retain
/// the stored centers/radii, so their sampler does not depend on the placement neighborhood.
pub fn canonicalizeSampleConfig(config: Config) Config {
    var result = config;
    switch (config.evaluator) {
        .mask_1bit, .mask_u8 => {
            result.pattern = .disk;
            result.neighbor_count = 9;
            result.soft_edges = false;
        },
        .list_naive => result.neighbor_count = 9,
        else => {},
    }
    return result;
}

const default_configs = [_]Config{
    .{ .pattern = .disk, .evaluator = .classified_indexed, .neighbor_count = 9, .soft_edges = false },
    .{ .pattern = .disk, .evaluator = .list_indexed, .neighbor_count = 9, .soft_edges = true },
    .{ .pattern = .gaussian, .evaluator = .list_indexed, .neighbor_count = 9, .soft_edges = false },
    .{ .pattern = .perlin, .evaluator = .mask_u8, .neighbor_count = 9, .soft_edges = false },
};

const Catalogue = struct {
    configs: [3 * 7 * 3 * 2]Config = undefined,
    len: usize = 0,

    fn appendUnique(self: *Catalogue, config: Config) void {
        for (self.configs[0..self.len]) |existing| {
            if (std.meta.eql(existing, config)) return;
        }
        self.configs[self.len] = config;
        self.len += 1;
    }
};

const all_generation_configs = enumerateGenerationConfigs();
const default_sample_configs = enumerateSampleConfigs(&default_configs);
const all_sample_configs = enumerateSampleConfigs(
    all_generation_configs.configs[0..all_generation_configs.len],
);

pub fn generationConfigs(comptime enable_all_evaluators: bool) []const Config {
    return if (enable_all_evaluators)
        all_generation_configs.configs[0..all_generation_configs.len]
    else
        &default_configs;
}

pub fn sampleConfigs(comptime enable_all_evaluators: bool) []const Config {
    const catalogue = if (enable_all_evaluators) &all_sample_configs else &default_sample_configs;
    return catalogue.configs[0..catalogue.len];
}

fn enumerateGenerationConfigs() Catalogue {
    @setEvalBranchQuota(100_000);
    var result: Catalogue = .{};
    for (default_configs) |config| result.appendUnique(config);
    for (std.enums.values(Pattern)) |pattern| {
        for (std.enums.values(Evaluator)) |evaluator| {
            for ([_]u8{ 1, 4, 9 }) |neighbors| {
                if (pattern == .perlin and neighbors != 9) continue;
                for ([_]bool{ false, true }) |soft| {
                    const config: Config = .{
                        .pattern = pattern,
                        .evaluator = evaluator,
                        .neighbor_count = neighbors,
                        .soft_edges = soft,
                    };
                    validateCompatibility(config) catch continue;
                    result.appendUnique(config);
                }
            }
        }
    }
    return result;
}

fn enumerateSampleConfigs(configs: []const Config) Catalogue {
    @setEvalBranchQuota(100_000);
    var result: Catalogue = .{};
    for (configs) |config| result.appendUnique(canonicalizeSampleConfig(config));
    return result;
}

test "runtime evaluator names round trip and reject invalid spellings" {
    for (std.enums.values(Evaluator)) |evaluator| {
        try std.testing.expectEqual(evaluator, parseEvaluator(evaluatorName(evaluator)).?);
        try std.testing.expectEqual(null, parseEvaluator(@tagName(evaluator)));
    }
    for ([_][]const u8{ "", "Cell-hash", " mask-u8", "mask", "MASK-U8" }) |name| {
        try std.testing.expectEqual(null, parseEvaluator(name));
    }
}

test "experimental resolution selects defaults and rejects incompatible overrides" {
    for ([_]u8{ 1, 4, 9 }) |neighbors| {
        const hard = try resolve(true, .disk, null, neighbors, false);
        try std.testing.expectEqual(if (neighbors == 9) Evaluator.classified_indexed else Evaluator.list_indexed, hard.evaluator);
        try std.testing.expectEqual(Evaluator.list_indexed, (try resolve(true, .disk, null, neighbors, true)).evaluator);
        try std.testing.expectEqual(Evaluator.list_indexed, (try resolve(true, .gaussian, null, neighbors, false)).evaluator);
    }
    try std.testing.expectEqual(@as(u8, 1), (try resolve(true, .disk, .direct_fixed, null, false)).neighbor_count);
    const cases = [_]struct {
        pattern: Pattern = .disk,
        evaluator: ?Evaluator = null,
        neighbors: ?u8 = null,
        soft: bool = false,
        err: ResolveError,
    }{
        .{ .neighbors = 0, .err = error.InvalidSpeckleNeighborCount },
        .{ .pattern = .perlin, .neighbors = 9, .err = error.SpecklePerlinDoesNotUseNeighbors },
        .{ .pattern = .perlin, .evaluator = .cell_hash, .err = error.PerlinRequiresMaskU8 },
        .{ .pattern = .gaussian, .evaluator = .mask_1bit, .err = error.Mask1BitRequiresDisk },
        .{ .evaluator = .classified_indexed, .neighbors = 4, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
        .{ .evaluator = .direct_fixed, .neighbors = 9, .err = error.DirectFixedRequiresDiskAndOneNeighbor },
        .{ .pattern = .gaussian, .soft = true, .err = error.SpeckleEdgeSoftnessRequiresDisk },
        .{ .evaluator = .classified_indexed, .soft = true, .err = error.SpeckleEvaluatorRequiresHardEdges },
        .{ .evaluator = .direct_fixed, .soft = true, .err = error.SpeckleEvaluatorRequiresHardEdges },
        .{ .evaluator = .mask_1bit, .soft = true, .err = error.SpeckleEvaluatorRequiresHardEdges },
    };
    for (cases) |case| try std.testing.expectError(case.err, resolve(true, case.pattern, case.evaluator, case.neighbors, case.soft));
}

test "specialization catalogues are unique and cover every resolved generation config" {
    inline for (.{ false, true }) |enable_all| {
        const generators = generationConfigs(enable_all);
        const samplers = sampleConfigs(enable_all);
        for (generators) |config| {
            try validateCompatibility(config);
            const canonical = canonicalizeSampleConfig(config);
            var matches: usize = 0;
            for (samplers) |sample| matches += @intFromBool(std.meta.eql(sample, canonical));
            try std.testing.expectEqual(@as(usize, 1), matches);
        }
        for (samplers, 0..) |config, index| {
            for (samplers[index + 1 ..]) |other| try std.testing.expect(!std.meta.eql(config, other));
        }
    }
}
