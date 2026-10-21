// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
//! Resolved speckle policy and compile-time specialization catalogues.
const std = @import("std");

pub const Pattern = enum(u8) { disk = 0, gaussian = 1, perlin = 2 };
pub const Evaluator = enum(u8) {
    cell_hash,
    gradient_lattice,
    list_naive,
    list_indexed,
    classified_indexed, // Owner-aligned classification with exact masked hard-disk fallback.
    direct_fixed,
    mask_1bit,
    mask_u8,
    mock,
};
pub const Neighborhood = enum(u8) { one = 1, four = 4, nine = 9 };
pub const MaskResolution = enum(u8) { eight = 8, twelve = 12, sixteen = 16 };
pub const Edges = enum { hard, soft };
pub const default_pattern: Pattern = .disk;
pub const default_neighborhood: Neighborhood = .nine;
pub const default_mask_resolution: MaskResolution = .twelve;

pub const DiskConfig = struct { neighborhood: Neighborhood, edges: Edges };
pub const Shape = union(enum) { disk: DiskConfig, gaussian: Neighborhood };
pub const Field = union(Pattern) { disk: DiskConfig, gaussian: Neighborhood, perlin: void };
pub const Config = union(Evaluator) {
    cell_hash: Field,
    gradient_lattice: void,
    list_naive: Shape,
    list_indexed: Shape,
    classified_indexed: void,
    direct_fixed: void,
    mask_1bit: Neighborhood,
    mask_u8: Field,
    mock: void,

    pub fn pattern(self: Config) ?Pattern {
        return switch (self) {
            .cell_hash, .mask_u8 => |field| std.meta.activeTag(field),
            .list_naive, .list_indexed => |shape| switch (shape) {
                .disk => .disk,
                .gaussian => .gaussian,
            },
            .gradient_lattice => .perlin,
            .classified_indexed, .direct_fixed, .mask_1bit => .disk,
            .mock => null,
        };
    }

    pub fn neighborhood(self: Config) ?Neighborhood {
        return switch (self) {
            .cell_hash, .mask_u8 => |field| switch (field) {
                .disk => |disk| disk.neighborhood,
                .gaussian => |neighbors| neighbors,
                .perlin => null,
            },
            .list_naive, .list_indexed => |shape| switch (shape) {
                .disk => |disk| disk.neighborhood,
                .gaussian => |neighbors| neighbors,
            },
            .classified_indexed => .nine,
            .direct_fixed => .one,
            .mask_1bit => |neighbors| neighbors,
            .gradient_lattice, .mock => null,
        };
    }

    pub fn edges(self: Config) ?Edges {
        return switch (self) {
            .cell_hash, .mask_u8 => |field| switch (field) {
                .disk => |disk| disk.edges,
                .gaussian, .perlin => null,
            },
            .list_naive, .list_indexed => |shape| switch (shape) {
                .disk => |disk| disk.edges,
                .gaussian => null,
            },
            .classified_indexed, .direct_fixed, .mask_1bit => .hard,
            .gradient_lattice => null,
            .mock => null,
        };
    }

    /// Capability, not the current edge setting. Mock's raw pattern is checked at the boundary.
    pub fn supportsSoftEdges(self: Config) bool {
        return switch (self) {
            .cell_hash, .mask_u8 => |field| field == .disk,
            .list_naive, .list_indexed => |shape| shape == .disk,
            .mock => true,
            else => false,
        };
    }
};

pub const ResolveError = error{
    SpeckleOverridesDisabled,
    SpecklePerlinDoesNotUseNeighbors,
    PerlinRequiresSupportedEvaluator,
    GradientLatticeRequiresPerlin,
    Mask1BitRequiresDisk,
    ClassifiedIndexedRequiresDiskAndNineNeighbors,
    DirectFixedRequiresDiskAndOneNeighbor,
    SpeckleEdgeSoftnessRequiresDisk,
    SpeckleEvaluatorRequiresHardEdges,
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
        .gradient_lattice => "gradient-lattice",
        .list_naive => "list-naive",
        .list_indexed => "list-indexed",
        .classified_indexed => "classified-indexed",
        .direct_fixed => "direct-fixed",
        .mask_1bit => "mask-1bit",
        .mask_u8 => "mask-u8",
        .mock => "mock",
    };
}

/// Validate external controls once, before constructing a policy containing only valid states.
/// Overrides require an experimental build, even when they name a default value.
pub fn resolve(
    comptime enable_all_evaluators: bool,
    pattern: Pattern,
    evaluator: ?Evaluator,
    neighbor_count: ?Neighborhood,
    edges: Edges,
) ResolveError!Config {
    if (!enable_all_evaluators and (evaluator != null or neighbor_count != null))
        return error.SpeckleOverridesDisabled;
    if (pattern == .perlin and evaluator != .mock and neighbor_count != null)
        return error.SpecklePerlinDoesNotUseNeighbors;
    const neighbors = neighbor_count orelse
        if (evaluator == .direct_fixed) .one else default_neighborhood;
    const selected = evaluator orelse switch (pattern) {
        .disk => if (edges == .hard and neighbors == .nine)
            Evaluator.classified_indexed
        else
            Evaluator.list_indexed,
        .gaussian => Evaluator.list_indexed,
        .perlin => Evaluator.gradient_lattice,
    };
    if (pattern == .perlin and selected != .gradient_lattice and selected != .cell_hash and
        selected != .mask_u8 and selected != .mock) return error.PerlinRequiresSupportedEvaluator;
    switch (selected) {
        .gradient_lattice => if (pattern != .perlin) return error.GradientLatticeRequiresPerlin,
        .mask_1bit => if (pattern != .disk) return error.Mask1BitRequiresDisk,
        .classified_indexed => if (pattern != .disk or neighbors != .nine)
            return error.ClassifiedIndexedRequiresDiskAndNineNeighbors,
        .direct_fixed => if (pattern != .disk or neighbors != .one)
            return error.DirectFixedRequiresDiskAndOneNeighbor,
        else => {},
    }
    if (edges == .soft) {
        if (pattern != .disk) return error.SpeckleEdgeSoftnessRequiresDisk;
        switch (selected) {
            .classified_indexed, .direct_fixed, .mask_1bit, .gradient_lattice => return error.SpeckleEvaluatorRequiresHardEdges,
            else => {},
        }
    }
    // In particular, mock erases controls only after their external errors have been checked.
    return switch (selected) {
        .cell_hash, .mask_u8 => blk: {
            const field: Field = switch (pattern) {
                .disk => .{ .disk = .{ .neighborhood = neighbors, .edges = edges } },
                .gaussian => .{ .gaussian = neighbors },
                .perlin => .perlin,
            };
            break :blk if (selected == .cell_hash) .{ .cell_hash = field } else .{ .mask_u8 = field };
        },
        .list_naive, .list_indexed => blk: {
            const shape: Shape = switch (pattern) {
                .disk => .{ .disk = .{ .neighborhood = neighbors, .edges = edges } },
                .gaussian => .{ .gaussian = neighbors },
                .perlin => unreachable,
            };
            break :blk if (selected == .list_naive) .{ .list_naive = shape } else .{ .list_indexed = shape };
        },
        .gradient_lattice => .gradient_lattice,
        .classified_indexed => .classified_indexed,
        .direct_fixed => .direct_fixed,
        .mask_1bit => .{ .mask_1bit = neighbors },
        .mock => .mock,
    };
}

/// Masks ignore generation policy; naive lists retain centers/radii rather than a neighborhood.
pub fn canonicalizeSampleConfig(config: Config) Config {
    return switch (config) {
        .mask_1bit => .{ .mask_1bit = .nine },
        .mask_u8 => .{ .mask_u8 = .{ .disk = .{ .neighborhood = .nine, .edges = .hard } } },
        .list_naive => |shape| .{ .list_naive = switch (shape) {
            .disk => |disk| .{ .disk = .{ .neighborhood = .nine, .edges = disk.edges } },
            .gaussian => .{ .gaussian = .nine },
        } },
        else => config,
    };
}

const default_configs = [_]Config{
    .classified_indexed,
    .{ .list_indexed = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
    .{ .list_indexed = .{ .gaussian = .nine } },
    .gradient_lattice,
};
const Catalogue = struct {
    configs: [45]Config = undefined,
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
const all_sample_configs = enumerateSampleConfigs(all_generation_configs.configs[0..all_generation_configs.len]);

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
    result.appendUnique(.direct_fixed);
    result.appendUnique(.mock);
    inline for (.{ Evaluator.cell_hash, Evaluator.mask_u8 }) |evaluator|
        result.appendUnique(@unionInit(Config, @tagName(evaluator), Field.perlin));
    for (std.enums.values(Neighborhood)) |neighbors| {
        result.appendUnique(.{ .mask_1bit = neighbors });
        inline for (.{ Evaluator.cell_hash, Evaluator.mask_u8, Evaluator.list_naive, Evaluator.list_indexed }) |evaluator| {
            const Payload = if (evaluator == .cell_hash or evaluator == .mask_u8) Field else Shape;
            result.appendUnique(@unionInit(Config, @tagName(evaluator), Payload{ .gaussian = neighbors }));
            for (std.enums.values(Edges)) |edges| {
                const payload: Payload = .{ .disk = .{ .neighborhood = neighbors, .edges = edges } };
                result.appendUnique(@unionInit(Config, @tagName(evaluator), payload));
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

test "enum boundary conversions and pattern/evaluator spellings" {
    for (0..256) |raw| {
        const value: u8 = @intCast(raw);
        const neighbors = std.enums.fromInt(Neighborhood, value);
        const resolution = std.enums.fromInt(MaskResolution, value);
        try std.testing.expectEqual(raw == 1 or raw == 4 or raw == 9, neighbors != null);
        try std.testing.expectEqual(raw == 8 or raw == 12 or raw == 16, resolution != null);
        if (neighbors) |n| try std.testing.expectEqual(value, @intFromEnum(n));
        if (resolution) |r| try std.testing.expectEqual(value, @intFromEnum(r));
    }
    try std.testing.expectEqual(Neighborhood.nine, default_neighborhood);
    try std.testing.expectEqual(MaskResolution.twelve, default_mask_resolution);
    for (std.enums.values(Pattern)) |pattern|
        try std.testing.expectEqual(pattern, parsePattern(@tagName(pattern)).?);
    for ([_][]const u8{ "", "Disk", "hard", "soft", " perlin" }) |name|
        try std.testing.expectEqual(null, parsePattern(name));
    for (std.enums.values(Evaluator)) |evaluator| {
        try std.testing.expectEqual(evaluator, parseEvaluator(evaluatorName(evaluator)).?);
        if (evaluator != .mock) try std.testing.expectEqual(null, parseEvaluator(@tagName(evaluator)));
    }
    for ([_][]const u8{ "", "Cell-hash", " mask-u8", "mask", "MASK-U8", "list-indexed-2", "classified-indexed-99" }) |name|
        try std.testing.expectEqual(null, parseEvaluator(name));
}

test "exhaustive external controls preserve acceptance errors and resolved semantics" {
    inline for (.{ false, true }) |enabled| {
        for (std.enums.values(Pattern)) |pattern| {
            for (0..10) |choice| {
                const evaluator: ?Evaluator = if (choice == 9) null else @enumFromInt(choice);
                for ([_]?Neighborhood{ null, .one, .four, .nine }) |neighbors| {
                    for (std.enums.values(Edges)) |edges| {
                        // Independent raw-tuple oracle: original validation order, before erasure.
                        const n: u8 = if (neighbors) |value| @intFromEnum(value) else if (evaluator == .direct_fixed) 1 else 9;
                        const selected = evaluator orelse switch (pattern) {
                            .disk => if (edges == .hard and n == 9) Evaluator.classified_indexed else Evaluator.list_indexed,
                            .gaussian => Evaluator.list_indexed,
                            .perlin => Evaluator.gradient_lattice,
                        };
                        const err: ?ResolveError = blk: {
                            if (!enabled and (evaluator != null or neighbors != null)) break :blk error.SpeckleOverridesDisabled;
                            if (pattern == .perlin and evaluator != .mock and neighbors != null) break :blk error.SpecklePerlinDoesNotUseNeighbors;
                            if (pattern == .perlin and selected != .cell_hash and selected != .gradient_lattice and selected != .mask_u8 and selected != .mock) break :blk error.PerlinRequiresSupportedEvaluator;
                            if (selected == .gradient_lattice and pattern != .perlin) break :blk error.GradientLatticeRequiresPerlin;
                            if (selected == .mask_1bit and pattern != .disk) break :blk error.Mask1BitRequiresDisk;
                            if (selected == .classified_indexed and (pattern != .disk or n != 9)) break :blk error.ClassifiedIndexedRequiresDiskAndNineNeighbors;
                            if (selected == .direct_fixed and (pattern != .disk or n != 1)) break :blk error.DirectFixedRequiresDiskAndOneNeighbor;
                            if (edges == .soft and pattern != .disk) break :blk error.SpeckleEdgeSoftnessRequiresDisk;
                            if (edges == .soft and (selected == .classified_indexed or selected == .direct_fixed or selected == .mask_1bit or selected == .gradient_lattice)) break :blk error.SpeckleEvaluatorRequiresHardEdges;
                            break :blk null;
                        };
                        const actual = resolve(enabled, pattern, evaluator, neighbors, edges);
                        if (err) |expected| {
                            try std.testing.expectError(expected, actual);
                            continue;
                        }
                        const config = try actual;
                        try std.testing.expectEqual(selected, std.meta.activeTag(config));
                        try std.testing.expectEqual(if (selected == .mock) null else pattern, config.pattern());
                        try std.testing.expectEqual(if (selected == .mock or pattern == .perlin) null else std.enums.fromInt(Neighborhood, n), config.neighborhood());
                        try std.testing.expectEqual(if (selected == .mock or pattern != .disk) null else edges, config.edges());
                        const capable = selected == .mock or (pattern == .disk and (selected == .cell_hash or selected == .list_naive or selected == .list_indexed or selected == .mask_u8));
                        try std.testing.expectEqual(capable, config.supportsSoftEdges());
                        var matches: usize = 0;
                        for (generationConfigs(enabled)) |candidate| matches += @intFromBool(std.meta.eql(config, candidate));
                        try std.testing.expectEqual(@as(usize, 1), matches);
                    }
                }
            }
        }
    }
}

test "catalogues contain exactly the valid policies and canonical sampler behaviors" {
    try std.testing.expectEqual(45, generationConfigs(true).len);
    try std.testing.expectEqual(28, sampleConfigs(true).len);
    try std.testing.expectEqual(4, generationConfigs(false).len);
    try std.testing.expectEqual(4, sampleConfigs(false).len);
    inline for (.{ false, true }) |enabled| {
        for (generationConfigs(enabled), 0..) |config, index| {
            for (generationConfigs(enabled)[index + 1 ..]) |other| try std.testing.expect(!std.meta.eql(config, other));
            const resolved = try resolve(true, config.pattern() orelse .disk, std.meta.activeTag(config), config.neighborhood(), config.edges() orelse .hard);
            try std.testing.expectEqualDeep(config, resolved);
            const canonical = canonicalizeSampleConfig(config);
            try std.testing.expectEqualDeep(canonical, canonicalizeSampleConfig(canonical));
            var matches: usize = 0;
            for (sampleConfigs(enabled)) |sample| matches += @intFromBool(std.meta.eql(sample, canonical));
            try std.testing.expectEqual(@as(usize, 1), matches);
        }
        for (sampleConfigs(enabled), 0..) |config, index| {
            for (sampleConfigs(enabled)[index + 1 ..]) |other| try std.testing.expect(!std.meta.eql(config, other));
        }
    }
}
