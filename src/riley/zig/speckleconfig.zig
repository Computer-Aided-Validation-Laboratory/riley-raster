// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Resolved speckle policy and compile-time specialization catalogues.
const std = @import("std");
const buildconfig = @import("buildconfig.zig");

pub const Pattern = enum(u8) { disk = 0, gaussian = 1, perlin = 2 };
pub const Evaluator = enum(u8) {
    cell_hash,
    gradient_lattice,
    list_naive,
    list_indexed,
    cell_binned,
    classified_indexed, // Owner-aligned classification with exact masked hard-disk fallback.
    classified_binned,
    direct_fixed,
    mask_1bit,
    mask_u8,
    mock,
};

pub const Neighborhood = enum(u8) { one = 1, four = 4, nine = 9 };
pub const MaskResolution = enum(u8) { eight = 8, twelve = 12, sixteen = 16 };
pub const Edges = enum { hard, soft };
pub const default_seed: u32 = 0xa511e9b3;
pub const default_perlin_transition_width: buildconfig.F = 0.12;
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
    cell_binned: Shape,
    classified_indexed: void,
    classified_binned: void,
    direct_fixed: void,
    mask_1bit: Neighborhood,
    mask_u8: Field,
    mock: void,

    pub fn pattern(self: Config) ?Pattern {
        return switch (self) {
            .cell_hash, .mask_u8 => |field| std.meta.activeTag(field),
            .list_naive, .list_indexed, .cell_binned => |shape| switch (shape) {
                .disk => .disk,
                .gaussian => .gaussian,
            },
            .gradient_lattice => .perlin,
            .classified_indexed, .classified_binned, .direct_fixed, .mask_1bit => .disk,
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
            .list_naive, .list_indexed, .cell_binned => |shape| switch (shape) {
                .disk => |disk| disk.neighborhood,
                .gaussian => |neighbors| neighbors,
            },
            .classified_indexed, .classified_binned => .nine,
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
            .list_naive, .list_indexed, .cell_binned => |shape| switch (shape) {
                .disk => |disk| disk.edges,
                .gaussian => null,
            },
            .classified_indexed, .classified_binned, .direct_fixed, .mask_1bit => .hard,
            .gradient_lattice => null,
            .mock => null,
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
    ClassifiedBinnedRequiresDiskAndNineNeighbors,
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
        .cell_binned => "cell-binned",
        .classified_indexed => "classified-indexed",
        .classified_binned => "classified-binned",
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
        .disk => if (neighbors != .nine) Evaluator.list_indexed else if (edges == .hard) Evaluator.classified_binned else Evaluator.cell_binned,
        .gaussian => if (neighbors == .nine) Evaluator.cell_binned else Evaluator.list_indexed,
        .perlin => Evaluator.gradient_lattice,
    };
    if (pattern == .perlin and selected != .gradient_lattice and selected != .cell_hash and
        selected != .mask_u8 and selected != .mock) return error.PerlinRequiresSupportedEvaluator;
    switch (selected) {
        .gradient_lattice => if (pattern != .perlin) return error.GradientLatticeRequiresPerlin,
        .mask_1bit => if (pattern != .disk) return error.Mask1BitRequiresDisk,
        .classified_indexed => if (pattern != .disk or neighbors != .nine)
            return error.ClassifiedIndexedRequiresDiskAndNineNeighbors,
        .classified_binned => if (pattern != .disk or neighbors != .nine)
            return error.ClassifiedBinnedRequiresDiskAndNineNeighbors,
        .direct_fixed => if (pattern != .disk or neighbors != .one)
            return error.DirectFixedRequiresDiskAndOneNeighbor,
        else => {},
    }
    if (edges == .soft) {
        if (pattern != .disk) return error.SpeckleEdgeSoftnessRequiresDisk;
        switch (selected) {
            .classified_indexed, .classified_binned, .direct_fixed, .mask_1bit, .gradient_lattice => return error.SpeckleEvaluatorRequiresHardEdges,
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
        .list_naive, .list_indexed, .cell_binned => blk: {
            const shape: Shape = switch (pattern) {
                .disk => .{ .disk = .{ .neighborhood = neighbors, .edges = edges } },
                .gaussian => .{ .gaussian = neighbors },
                .perlin => unreachable,
            };
            break :blk switch (selected) {
                .list_naive => .{ .list_naive = shape },
                .list_indexed => .{ .list_indexed = shape },
                .cell_binned => .{ .cell_binned = shape },
                else => unreachable,
            };
        },
        .gradient_lattice => .gradient_lattice,
        .classified_indexed => .classified_indexed,
        .classified_binned => .classified_binned,
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
        .cell_binned => |shape| .{ .cell_binned = switch (shape) {
            .disk => |disk| .{ .disk = .{ .neighborhood = .nine, .edges = disk.edges } },
            .gaussian => .{ .gaussian = .nine },
        } },
        else => config,
    };
}

const default_configs = [_]Config{
    .classified_binned,
    .{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
    .{ .cell_binned = .{ .gaussian = .nine } },
    .gradient_lattice,
};
const Catalogue = struct {
    configs: [55]Config = undefined,
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

/// Resolve a generation policy to its actual, deduplicated sampling kernel.
pub fn sampleConfigIndex(comptime enabled: bool, config: Config) u8 {
    @setEvalBranchQuota(100_000);
    const canonical = canonicalizeSampleConfig(config);
    for (sampleConfigs(enabled), 0..) |sample, index| {
        if (std.meta.eql(sample, canonical)) return @intCast(index);
    }
    unreachable; // Resolved policies and the catalogue share availability rules.
}

fn enumerateGenerationConfigs() Catalogue {
    @setEvalBranchQuota(100_000);
    var result: Catalogue = .{};
    for (default_configs) |config| result.appendUnique(config);
    result.appendUnique(.direct_fixed);
    result.appendUnique(.mock);
    result.appendUnique(.classified_indexed);
    result.appendUnique(.classified_binned);

    inline for (.{ Evaluator.cell_hash, Evaluator.mask_u8 }) |evaluator|
        result.appendUnique(@unionInit(Config, @tagName(evaluator), Field.perlin));
    for (std.enums.values(Neighborhood)) |neighbors| {
        result.appendUnique(.{ .mask_1bit = neighbors });
        inline for (.{ Evaluator.cell_hash, Evaluator.mask_u8, Evaluator.list_naive, Evaluator.list_indexed, Evaluator.cell_binned }) |evaluator| {
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
        if (neighbors) |n| try std.testing.expectEqual(value, @backingInt(n));
        if (resolution) |r| try std.testing.expectEqual(value, @backingInt(r));
    }
    try std.testing.expectEqual(Neighborhood.nine, default_neighborhood);
    try std.testing.expectEqual(MaskResolution.twelve, default_mask_resolution);
    for (std.enums.values(Pattern)) |pattern|
        try std.testing.expectEqual(pattern, parsePattern(@tagName(pattern)).?);
    for ([_][]const u8{ "", "Disk", "hard", "soft", " perlin" }) |name|
        try std.testing.expectEqual(null, parsePattern(name));
    const evaluator_names = [_][]const u8{
        "cell-hash",          "gradient-lattice",  "list-naive",   "list-indexed", "cell-binned",
        "classified-indexed", "classified-binned", "direct-fixed", "mask-1bit",    "mask-u8",
        "mock",
    };
    for (std.enums.values(Evaluator), evaluator_names) |evaluator, name| {
        try std.testing.expectEqualStrings(name, evaluatorName(evaluator));
        try std.testing.expectEqual(evaluator, parseEvaluator(name).?);
        if (evaluator != .mock) try std.testing.expectEqual(null, parseEvaluator(@tagName(evaluator)));
    }
    for ([_][]const u8{ "", "Cell-hash", " mask-u8", "mask", "MASK-U8", "unknown-evaluator" }) |name|
        try std.testing.expectEqual(null, parseEvaluator(name));
}

test "resolve selects the documented policies and rejects incompatible controls" {
    const Case = struct {
        pattern: Pattern = .disk,
        evaluator: ?Evaluator = null,
        neighbors: ?Neighborhood = null,
        edges: Edges = .hard,
        expected: ResolveError!Config,
    };
    const automatic = [_]Case{
        .{ .expected = .classified_binned },
        .{ .edges = .soft, .expected = .{ .cell_binned = .{ .disk = .{
            .neighborhood = .nine,
            .edges = .soft,
        } } } },
        .{ .pattern = .gaussian, .expected = .{ .cell_binned = .{ .gaussian = .nine } } },
        .{ .pattern = .perlin, .expected = .gradient_lattice },
        .{ .pattern = .gaussian, .edges = .soft, .expected = error.SpeckleEdgeSoftnessRequiresDisk },
        .{ .pattern = .perlin, .edges = .soft, .expected = error.SpeckleEdgeSoftnessRequiresDisk },
    };
    const overrides_disabled = [_]Case{
        .{ .evaluator = .classified_binned, .expected = error.SpeckleOverridesDisabled },
        .{ .neighbors = .nine, .expected = error.SpeckleOverridesDisabled },
        .{ .pattern = .perlin, .neighbors = .one, .expected = error.SpeckleOverridesDisabled },
    };
    const overrides_enabled = [_]Case{
        .{ .neighbors = .one, .expected = .{ .list_indexed = .{ .disk = .{
            .neighborhood = .one,
            .edges = .hard,
        } } } },
        .{ .neighbors = .four, .edges = .soft, .expected = .{ .list_indexed = .{ .disk = .{
            .neighborhood = .four,
            .edges = .soft,
        } } } },
        .{ .pattern = .gaussian, .neighbors = .one, .expected = .{ .list_indexed = .{ .gaussian = .one } } },
        .{ .pattern = .gaussian, .neighbors = .four, .expected = .{ .list_indexed = .{ .gaussian = .four } } },
        .{ .evaluator = .classified_indexed, .expected = .classified_indexed },
        .{ .evaluator = .direct_fixed, .expected = .direct_fixed },
        .{ .pattern = .perlin, .evaluator = .cell_hash, .expected = .{ .cell_hash = .perlin } },
        .{ .pattern = .perlin, .evaluator = .mask_u8, .expected = .{ .mask_u8 = .perlin } },
        .{ .pattern = .perlin, .evaluator = .mock, .neighbors = .four, .expected = .mock },
        .{ .pattern = .perlin, .evaluator = .mock, .edges = .soft, .expected = error.SpeckleEdgeSoftnessRequiresDisk },
        .{ .pattern = .perlin, .neighbors = .nine, .expected = error.SpecklePerlinDoesNotUseNeighbors },
        .{ .pattern = .perlin, .evaluator = .list_indexed, .expected = error.PerlinRequiresSupportedEvaluator },
        .{ .evaluator = .gradient_lattice, .expected = error.GradientLatticeRequiresPerlin },
        .{ .pattern = .gaussian, .evaluator = .mask_1bit, .expected = error.Mask1BitRequiresDisk },
        .{ .pattern = .gaussian, .evaluator = .classified_indexed, .expected = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
        .{ .evaluator = .classified_indexed, .neighbors = .four, .expected = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
        .{ .pattern = .gaussian, .evaluator = .classified_binned, .expected = error.ClassifiedBinnedRequiresDiskAndNineNeighbors },
        .{ .evaluator = .classified_binned, .neighbors = .four, .expected = error.ClassifiedBinnedRequiresDiskAndNineNeighbors },
        .{ .pattern = .gaussian, .evaluator = .direct_fixed, .expected = error.DirectFixedRequiresDiskAndOneNeighbor },
        .{ .evaluator = .direct_fixed, .neighbors = .nine, .expected = error.DirectFixedRequiresDiskAndOneNeighbor },
        .{ .evaluator = .classified_indexed, .edges = .soft, .expected = error.SpeckleEvaluatorRequiresHardEdges },
        .{ .evaluator = .classified_binned, .edges = .soft, .expected = error.SpeckleEvaluatorRequiresHardEdges },
        .{ .evaluator = .direct_fixed, .edges = .soft, .expected = error.SpeckleEvaluatorRequiresHardEdges },
        .{ .evaluator = .mask_1bit, .edges = .soft, .expected = error.SpeckleEvaluatorRequiresHardEdges },
    };
    inline for (.{ false, true }) |enabled| {
        const cases = if (enabled) automatic ++ overrides_enabled else automatic ++ overrides_disabled;
        for (cases, 0..) |case, index| {
            errdefer std.debug.print("resolve case {d}, experimental={}: {any}\n", .{ index, enabled, case });
            const actual = resolve(enabled, case.pattern, case.evaluator, case.neighbors, case.edges);
            if (case.expected) |expected| {
                try std.testing.expectEqualDeep(expected, try actual);
            } else |err| {
                try std.testing.expectError(err, actual);
            }
        }
    }
}

test "catalogues contain exactly the valid policies and canonical sampler behaviors" {
    if (comptime buildconfig.enable_all_evaluators) {
        try std.testing.expectEqual(55, generationConfigs(true).len);
        try std.testing.expectEqual(32, sampleConfigs(true).len);
    }
    const expected_defaults = [_]Config{
        .classified_binned,
        .{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
        .{ .cell_binned = .{ .gaussian = .nine } },
        .gradient_lattice,
    };
    try std.testing.expectEqualDeep(&expected_defaults, generationConfigs(false));
    try std.testing.expectEqualDeep(&expected_defaults, sampleConfigs(false));
    const enabled = buildconfig.enable_all_evaluators;
    for (generationConfigs(enabled), 0..) |config, index| {
        for (generationConfigs(enabled)[index + 1 ..]) |other| try std.testing.expect(!std.meta.eql(config, other));
        const resolved = try resolve(enabled, config.pattern() orelse .disk, if (enabled) std.meta.activeTag(config) else null, if (enabled) config.neighborhood() else null, config.edges() orelse .hard);
        try std.testing.expectEqualDeep(config, resolved);
        const canonical = canonicalizeSampleConfig(config);
        try std.testing.expectEqualDeep(canonical, canonicalizeSampleConfig(canonical));
        try std.testing.expectEqualDeep(canonical, sampleConfigs(enabled)[sampleConfigIndex(enabled, config)]);
        var matches: usize = 0;
        for (sampleConfigs(enabled)) |sample| matches += @intFromBool(std.meta.eql(sample, canonical));
        try std.testing.expectEqual(@as(usize, 1), matches);
    }
    for (sampleConfigs(enabled), 0..) |config, index| {
        for (sampleConfigs(enabled)[index + 1 ..]) |other| try std.testing.expect(!std.meta.eql(config, other));
    }
}
