// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const speckleconfig = @import("speckleconfig.zig");

const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSI = buildconfig.VecSI;
const VecSF = buildconfig.VecSF;
const speckle_mask_samples_per_cell: F =
    @floatFromInt(buildconfig.speckle_mask_samples_per_cell);
const max_speckle_cells = 10_000_000;
const max_speckle_mask_bytes = 256 * 1024 * 1024;
const max_speckle_classification_bytes = 256 * 1024 * 1024;
const max_direct_fixed_speckle_bytes = 256 * 1024 * 1024;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

/// Per-mesh runtime settings, immutable for the lifetime of prepared resources.
/// Except for mock, UVs are clamped to [0, 1], then mapped to cells as uv * cells_per_uv.
/// Mock is an experimental ablation: raw 0.5 * (u + v), without speckle resources or mapping.
/// For non-mock disk/Gaussian shapes, radius_mean + radius_jitter + edge_softness must not
/// exceed 0.5 for one neighbor, or 1.0 otherwise.
/// Hard disks exclude their circumference (distance² < radius²).
/// Ignored shape-specific fields are not validated; all other floating values must be finite.
/// On each axis, [-1, cells_per_uv + 1] must fit within
/// [-2^16, 2^16] for f32 or [-2^45, 2^45] for f64 to retain sub-cell precision.
pub const Speckle2DParams = struct {
    pattern: speckleconfig.Pattern = .disk,
    /// Experimental overrides; defaults-only builds reject every explicit value.
    evaluator: ?speckleconfig.Evaluator = null,
    neighbor_count: ?u8 = null,
    /// Deterministic seed; no automatic random seeding.
    seed: u32 = 0xa511e9b3,
    /// Positive cell counts per UV unit along each axis; noninteger values are supported.
    cells_per_uv: [2]F = .{ 192.0, 160.0 },
    /// Active-cell probability in [0, 1], not image coverage; ignored by Perlin.
    occupancy: F = 0.9,
    /// Positive disk radius or Gaussian three-sigma support, in cell units; ignored by Perlin.
    radius_mean: F = 0.45,
    /// Radius variation half-range in [0, radius_mean]; zero for direct-fixed; ignored by Perlin.
    radius_jitter: F = 0.0,
    /// Nonnegative disk boundary half-width in cell units; zero selects hard boundaries.
    /// Must be zero unless the selected disk evaluator supports soft edges.
    /// Unlike radii, this is checked for every pattern.
    edge_softness: F = 0.0,
    /// Perlin noise threshold; ignored by disk/Gaussian shapes.
    perlin_coverage_threshold: F = 0.0,
    /// Nonnegative Perlin transition width; zero selects a hard threshold.
    /// Ignored by disk/Gaussian shapes.
    perlin_coverage_transition_width: F = 0.12,
    /// Foreground intensity in [0, 1], before renderer output scaling.
    foreground: F = 0.0,
    /// Background intensity in [0, 1], before renderer output scaling.
    background: F = 1.0,

    /// Resolve one immutable generation configuration and validate before allocating.
    pub fn resolve(self: Speckle2DParams) !speckleconfig.Config {
        if (!std.math.isFinite(self.edge_softness) or self.edge_softness < 0.0) {
            return error.InvalidSpeckleEdgeSoftness;
        }
        const config = try speckleconfig.resolve(
            buildconfig.enable_all_evaluators,
            self.pattern,
            self.evaluator,
            self.neighbor_count,
            self.edge_softness > 0.0,
        );
        try self.validateResolved(config);
        return config;
    }

    pub fn validate(self: Speckle2DParams) !void {
        _ = try self.resolve();
    }

    // Separate numeric checks let configured generators validate without resolving again.
    fn validateResolved(self: Speckle2DParams, config: speckleconfig.Config) !void {
        for (self.cells_per_uv) |cell_count| {
            if (!std.math.isFinite(cell_count) or cell_count <= 0.0) {
                return error.InvalidSpeckleCellsPerUV;
            }
        }
        if (!std.math.isFinite(self.edge_softness) or self.edge_softness < 0.0) {
            return error.InvalidSpeckleEdgeSoftness;
        }
        if (self.edge_softness != 0.0) {
            if (config.pattern != .disk) {
                return error.SpeckleEdgeSoftnessRequiresDisk;
            }
            if (!speckleconfig.supportsSoftEdges(config)) return error.SpeckleEvaluatorRequiresHardEdges;
        }
        if (config.evaluator != .mock and config.pattern == .perlin) {
            if (!std.math.isFinite(self.perlin_coverage_threshold)) {
                return error.InvalidSpecklePerlinCoverageThreshold;
            }
            if (!std.math.isFinite(self.perlin_coverage_transition_width) or
                self.perlin_coverage_transition_width < 0.0)
            {
                return error.InvalidSpecklePerlinCoverageTransitionWidth;
            }
        } else if (config.evaluator != .mock) {
            if (!std.math.isFinite(self.occupancy) or
                self.occupancy < 0.0 or self.occupancy > 1.0)
            {
                return error.InvalidSpeckleOccupancy;
            }
            if (!std.math.isFinite(self.radius_mean) or self.radius_mean <= 0.0) {
                return error.InvalidSpeckleRadiusMean;
            }
            if (!std.math.isFinite(self.radius_jitter) or self.radius_jitter < 0.0) {
                return error.InvalidSpeckleRadiusJitter;
            }
            if (config.evaluator == .direct_fixed and self.radius_jitter != 0.0) {
                return error.InvalidDirectFixedSpeckleRadiusJitter;
            }
            if (self.radius_jitter > self.radius_mean) return error.InvalidSpeckleRadiusRange;

            const max_radius = self.radius_mean + self.radius_jitter + self.edge_softness;
            if (max_radius > (if (config.neighbor_count == 1) @as(F, 0.5) else @as(F, 1.0))) {
                return if (config.evaluator == .direct_fixed)
                    error.InvalidDirectFixedSpeckleRadius
                else
                    error.InvalidSpeckleNeighborhoodRadius;
            }
        }
        if (!std.math.isFinite(self.foreground) or
            self.foreground < 0.0 or self.foreground > 1.0)
        {
            return error.InvalidSpeckleForeground;
        }
        if (!std.math.isFinite(self.background) or
            self.background < 0.0 or self.background > 1.0)
        {
            return error.InvalidSpeckleBackground;
        }

        // Preserve at least eight bits of sub-cell precision in procedural coordinates.
        const cell_coord_lim: F = if (F == f32)
            65_536.0
        else
            35_184_372_088_832.0;
        for (self.cells_per_uv) |cells| {
            if (cells + 1.0 > cell_coord_lim) return error.SpeckleCellCoordinateOutOfRange;
        }
    }
};

pub const SpeckleDisk2D = struct {
    center: [2]F,
    radius: F,
};

pub const SpeckleList2D = struct {
    params: Speckle2DParams,
    disks: []const SpeckleDisk2D,
};

/// Row-major cells, each containing a vertical strip of 3/2/1 disk records.
/// Owns one record allocation, or center-only allocation for fixed radii, without a cell index.
pub const StripSpeckleList2D = struct {
    params: Speckle2DParams,
    disks: []const SpeckleDisk2D = &.{},
    centers: []const [2]F = &.{},
    cell_origin: [2]i64,
    cell_dims: [2]usize,
    outer2: F = 0,
    inner2: F = 0,
    sigma2: F = 0,
    max_outer_radius2: F = 0,

    fn recordCount(self: @This()) usize {
        return if (self.centers.len != 0) self.centers.len else self.disks.len;
    }

    fn record(self: @This(), index: usize) SpeckleDisk2D {
        return if (self.centers.len == 0) self.disks[index] else .{ .center = self.centers[index], .radius = self.params.radius_mean };
    }
};

pub const SpeckleClassificationState = enum(u8) {
    background = 0,
    foreground = 1,
    ambiguous = 2,
    reserve3 = 3,
};

pub const ClassifiedIndexedSpeckle2D = struct {
    speckles: StripSpeckleList2D,
    states: []const u8,
    dims: [2]usize,
    uv_to_cell: [2]F,
};

pub const NeighborMaskedSpeckle2D = struct {
    speckles: StripSpeckleList2D,
    /// Bits 0..8 select x-major (-1..1, -1..1) neighbours; bit 9 is the base colour.
    /// Foreground certification is exactly 512 (no candidates); otherwise the base is background.
    states: []const u16,
    dims: [2]usize,
    uv_to_cell: [2]F,
};

pub const DirectFixedSpeckleCell2D = u64;

pub const DirectFixedSpeckle2D = struct {
    params: Speckle2DParams,
    cells: []const DirectFixedSpeckleCell2D,
    cell_origin: [2]i64,
    cell_dims: [2]usize,
    radius2: F,
};

pub const SpeckleMask2D = struct {
    bits: []const u8,
    dims: [2]usize,
    row_stride: usize,
    uv_to_texel: [2]F,
    params: Speckle2DParams,
};

/// Static feature data returned by generateResources. Copies borrow the allocations;
/// only the original owner may deinit them with the allocator used for generation.
/// Arena-backed resources may instead be released with their static arena. Do not
/// free borrowed resources or per-frame copies, or alias owned slices across fields.
pub const Resources = struct {
    /// Index into kernel_configs, set even when cell hashing needs no allocation.
    kernel_index: ?u8 = null,
    list: ?SpeckleList2D = null,
    strip_list: ?StripSpeckleList2D = null,
    classified: ?ClassifiedIndexedSpeckle2D = null,
    neighbor_masked: ?NeighborMaskedSpeckle2D = null,
    direct_fixed: ?DirectFixedSpeckle2D = null,
    mask: ?SpeckleMask2D = null,

    pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
        if (self.list) |speckles| {
            allocator.free(speckles.disks);
        }
        if (self.strip_list) |speckles| {
            if (speckles.centers.len != 0) allocator.free(speckles.centers) else allocator.free(speckles.disks);
        }
        inline for (.{ self.neighbor_masked, self.classified }) |resource| {
            if (resource) |classified| {
                allocator.free(classified.states);
                allocator.free(classified.speckles.centers);
                allocator.free(classified.speckles.disks);
            }
        }
        if (self.direct_fixed) |direct| allocator.free(direct.cells);
        if (self.mask) |mask| allocator.free(mask.bits);
        self.* = .{};
    }
};

// --------------------------------------------------------------------------------------
// Preparation and statically specialized sampling
// --------------------------------------------------------------------------------------

/// Only distinct sample kernels are exposed to whole-raster specialization.
pub const kernel_configs = speckleconfig.sampleConfigs(buildconfig.enable_all_evaluators);
const generation_configs = speckleconfig.generationConfigs(buildconfig.enable_all_evaluators);

fn kernelIndex(config: speckleconfig.Config) u8 {
    @setEvalBranchQuota(100_000);
    const canonical = speckleconfig.canonicalizeSampleConfig(config);
    for (kernel_configs, 0..) |sample, index| {
        if (std.meta.eql(sample, canonical)) return @intCast(index);
    }
    unreachable; // Resolution and the catalogue share the same availability policy.
}

/// Prepare only the resolved resource. Copies borrow it; the owner calls deinit.
/// Keep the parameters/configuration immutable across frames using these resources.
pub fn generateResources(
    outer_alloc: std.mem.Allocator,
    params: Speckle2DParams,
) !Resources {
    const resolved = try params.resolve();
    inline for (generation_configs) |config| {
        if (std.meta.eql(resolved, config)) {
            var resources = try Implementation(config).generateConfiguredResources(outer_alloc, params);
            resources.kernel_index = comptime kernelIndex(config);
            return resources;
        }
    }
    unreachable;
}

/// The renderer selects this type outside sample loops using Resources.kernel_index.
/// Pattern, evaluator, neighborhood and hard/soft branches are all compile-time choices.
/// Parameters must match the prepared configuration; prepared resources must be present.
pub fn Kernel(comptime kernel_index: usize) type {
    const config = kernel_configs[kernel_index];
    const index_tag: u8 = @intCast(kernel_index);
    const Impl = Implementation(config);
    return struct {
        pub inline fn sampleScal(
            u: F,
            v: F,
            params: Speckle2DParams,
            resources: *const Resources,
        ) F {
            std.debug.assert(resources.kernel_index == @as(?u8, index_tag));
            return Impl.samplePreparedScal(config.soft_edges, u, v, params, resources);
        }

        pub inline fn sampleSIMD(
            u: VecSF,
            v: VecSF,
            active: VecSB,
            params: Speckle2DParams,
            resources: *const Resources,
        ) VecSF {
            std.debug.assert(resources.kernel_index == @as(?u8, index_tag));
            return Impl.samplePreparedSIMD(config.soft_edges, u, v, active, params, resources);
        }
    };
}

/// Convenience dispatch for raw callers/tests. Production uses Kernel(index) instead.
/// Unprepared calls require valid parameters and use the procedural reference without allocation.
pub fn sampleScal(u: F, v: F, params: Speckle2DParams, resources: *const Resources) F {
    @setEvalBranchQuota(100_000);
    if (resources.kernel_index) |index| {
        inline for (kernel_configs, 0..) |_, ii| {
            if (index == ii) return Kernel(ii).sampleScal(u, v, params, resources);
        }
        @panic("Invalid speckle kernel index");
    }
    const resolved = params.resolve() catch @panic("Speckle sampling requires validated parameters");
    inline for (generation_configs) |config| {
        if (std.meta.eql(resolved, config)) {
            return Implementation(config).evalSpeckle2DImpl(config.soft_edges, u, v, params);
        }
    }
    unreachable;
}

/// Classified/direct/mask kernels background inactive lanes. Procedural/list kernels
/// retain the existing finite-lane behavior. Except for mock's raw arithmetic,
/// every SIMD kernel backgrounds nonfinite lanes.
pub fn sampleSIMD(
    u: VecSF,
    v: VecSF,
    active: VecSB,
    params: Speckle2DParams,
    resources: *const Resources,
) VecSF {
    // The opt-in raw dispatcher expands all available kernels, including their SIMD lanes.
    @setEvalBranchQuota(100_000);
    if (resources.kernel_index) |index| {
        inline for (kernel_configs, 0..) |_, ii| {
            if (index == ii) return Kernel(ii).sampleSIMD(u, v, active, params, resources);
        }
        @panic("Invalid speckle kernel index");
    }
    const resolved = params.resolve() catch @panic("Speckle sampling requires validated parameters");
    inline for (generation_configs) |config| {
        if (std.meta.eql(resolved, config)) {
            const Impl = Implementation(config);
            if (comptime config.evaluator == .mock) return Impl.samplePreparedSIMD(config.soft_edges, u, v, active, params, resources);
            return Impl.evalSpeckleSIMDImpl(
                config.soft_edges,
                Impl.evalSpeckle2DImpl,
                u,
                v,
                params,
                params.background,
            );
        }
    }
    unreachable;
}

// These helpers do not depend on a generation or sampling configuration.
inline fn encodeSpeckleClassificationState(
    packed_byte: u8,
    state_index: usize,
    state: SpeckleClassificationState,
) u8 {
    const shift: u3 = @intCast((state_index & 3) * 2);
    const mask = @as(u8, 0b11) << shift;
    return (packed_byte & ~mask) | (@as(u8, @intFromEnum(state)) << shift);
}

inline fn decodeSpeckleClassificationState(
    packed_byte: u8,
    state_index: usize,
) SpeckleClassificationState {
    const shift: u3 = @intCast((state_index & 3) * 2);
    return @enumFromInt((packed_byte >> shift) & 0b11);
}

fn hashSpeckleCell(cell_x: i64, cell_y: i64, seed: u32) u64 {
    var key: [16]u8 = undefined;
    std.mem.writeInt(u64, key[0..8], @bitCast(cell_x), .little);
    std.mem.writeInt(u64, key[8..16], @bitCast(cell_y), .little);
    return std.hash.Wyhash.hash(seed, &key);
}

// Split one cell hash into four variates to avoid additional hash evaluations.
fn randomUnitFromHash(hash: u64, comptime shift: u6) F {
    const bits: u16 = @truncate(hash >> shift);
    return @as(F, @floatFromInt(bits)) / 65_536.0;
}

// Shared algorithms remain together so generation and the numerical reference tests
// use precisely the same placement, rounding and culling rules for each configuration.
// First representable p with RN(p*R) >= index. Integer indices are exact under
// the validated coordinate ceilings. See perf/direct-aligned-5-20261024-sol/MATH.md.
fn directMicrocellBoundary(comptime T: type, comptime r: u8, index: usize) T {
    if (index == 0) return 0;
    const target: T = @floatFromInt(index);
    var p = target / @as(T, r);
    while (p * @as(T, r) < target) p = std.math.nextAfter(T, p, std.math.inf(T));
    while (true) {
        const previous = std.math.nextAfter(T, p, 0);
        if (previous * @as(T, r) < target) return p;
        p = previous;
    }
}

fn expectDirectMicrocell(comptime T: type, comptime r: u8, p: T) !void {
    const j: usize = @intFromFloat(@floor(p * @as(T, r)));
    try std.testing.expectEqual(@as(usize, @intFromFloat(@floor(p))), j / r);
    const lo = directMicrocellBoundary(T, r, j);
    const next = directMicrocellBoundary(T, r, j + 1);
    try std.testing.expect(p >= lo and p < next);
    try std.testing.expect(lo * @as(T, r) >= @as(T, @floatFromInt(j)));
    if (j != 0) try std.testing.expect(std.math.nextAfter(T, lo, 0) * @as(T, r) < @as(T, @floatFromInt(j)));
    const v: @Vector(S, T) = @floor(@as(@Vector(S, T), @splat(p)) * @as(@Vector(S, T), @splat(r)));
    const vector: [S]T = v;
    for (vector) |value| try std.testing.expectEqual(@as(T, @floatFromInt(j)), value);
}

test "direct procedural microcells exhaust f32 faces and inverse subcells and probe f64 ceilings" {
    inline for (.{ f32, f64 }) |T| {
        inline for (.{ 8, 12, 16 }) |r| {
            if (T == f32) {
                for (0..65_537) |n| {
                    const face: T = @floatFromInt(n);
                    for ([_]T{ face, std.math.nextAfter(T, face, 0), std.math.nextAfter(T, face, std.math.inf(T)) }) |p| try expectDirectMicrocell(T, r, p);
                }
                // Every subcell through the mathematical ceiling, not only owner faces.
                for (0..65_536 * r + 1) |i| {
                    const p = @as(T, @floatFromInt(i)) / r;
                    for ([_]T{ p, std.math.nextAfter(T, p, 0), std.math.nextAfter(T, p, std.math.inf(T)) }) |q| try expectDirectMicrocell(T, r, q);
                }
            } else {
                for (0..46) |exponent| {
                    const n: usize = @as(usize, 1) << @intCast(exponent);
                    for ([_]usize{ n - 1, n, n + 1, n + n / 2 }) |owner| {
                        for (0..r + 1) |sub| {
                            const p = @as(T, @floatFromInt(owner * r + sub)) / r;
                            for ([_]T{ p, std.math.nextAfter(T, p, 0), std.math.nextAfter(T, p, std.math.inf(T)) }) |q| try expectDirectMicrocell(T, r, q);
                        }
                    }
                }
            }
            for ([_]T{ 0, std.math.nextAfter(T, 0, 1), std.math.floatMin(T), std.math.nextAfter(T, std.math.floatMin(T), 0) }) |p| try expectDirectMicrocell(T, r, p);
        }
    }
}

fn Implementation(comptime config: speckleconfig.Config) type {
    return struct {
        const direct_classification = config.evaluator == .classified_indexed_5 or config.evaluator == .classified_indexed_6 or config.evaluator == .classified_indexed_7 or config.evaluator == .classified_indexed_8;
        const aligned_classification = config.evaluator == .classified_indexed_3 or direct_classification;
        const speckle_shape = config.pattern;
        const speckle_neighbor_count = config.neighbor_count;
        const supports_soft_edges = speckleconfig.supportsSoftEdges(config);
        const support_radius_limit: F = if (speckle_neighbor_count == 1) 0.5 else 1.0;
        /// Prepare the configured evaluator once for reuse across frames and samples.
        /// Returned allocations belong to outer_alloc; release them through Resources.deinit
        /// or their owning static arena. Procedural cell hashing needs no allocation.
        fn generateConfiguredResources(
            outer_alloc: std.mem.Allocator,
            params: Speckle2DParams,
        ) !Resources {
            return switch (comptime config.evaluator) {
                .cell_hash, .mock => blk: {
                    try params.validateResolved(config);
                    break :blk .{};
                },
                .list_naive => .{ .list = try generateSpeckleList2D(outer_alloc, params) },
                .list_indexed => .{ .strip_list = try generateStripSpeckleList2D(outer_alloc, params) },
                .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8 => .{ .neighbor_masked = try generateClassifiedSpeckle2D(NeighborMaskedSpeckle2D, outer_alloc, params) },
                .classified_indexed => .{
                    .classified = try generateClassifiedSpeckle2D(ClassifiedIndexedSpeckle2D, outer_alloc, params),
                },
                .direct_fixed => .{
                    .direct_fixed = try generateDirectFixedSpeckle2D(outer_alloc, params),
                },
                .mask_1bit, .mask_u8 => .{
                    .mask = try generateSpeckleMask2D(outer_alloc, params),
                },
            };
        }

        /// Prepared resources are required and supply their own parameters; only cell hashing
        /// uses params. Explicit comptime softness also lets fixtures exercise hard/soft variants.
        inline fn samplePreparedScal(
            comptime soft_edges: bool,
            u: F,
            v: F,
            params: Speckle2DParams,
            resources: *const Resources,
        ) F {
            return switch (comptime config.evaluator) {
                .mock => 0.5 * (u + v),
                .cell_hash => evalSpeckle2DImpl(soft_edges, u, v, params),
                .list_naive => evalSpeckleList2DNaiveImpl(soft_edges, u, v, resources.list.?),
                .list_indexed => evalStripSpeckleList2DImpl(soft_edges, u, v, resources.strip_list.?),
                .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8 => evalClassifiedIndexedSpeckle2D(.{ u, v }, resources.neighbor_masked.?),
                .classified_indexed => evalClassifiedIndexedSpeckle2D(.{ u, v }, resources.classified.?),
                .direct_fixed => evalDirectFixedSpeckle2D(.{ u, v }, resources.direct_fixed.?),
                .mask_1bit, .mask_u8 => evalSpeckleMask2D(.{ u, v }, resources.mask.?),
            };
        }

        inline fn samplePreparedSIMD(
            comptime soft_edges: bool,
            u: VecSF,
            v: VecSF,
            active: VecSB,
            params: Speckle2DParams,
            resources: *const Resources,
        ) VecSF {
            return switch (comptime config.evaluator) {
                .mock => @as(VecSF, @splat(0.5)) * (u + v),
                .cell_hash => evalSpeckleSIMDImpl(soft_edges, evalSpeckle2DImpl, u, v, params, params.background),
                .list_naive => evalSpeckleSIMDImpl(
                    soft_edges,
                    evalSpeckleList2DNaiveImpl,
                    u,
                    v,
                    resources.list.?,
                    resources.list.?.params.background,
                ),
                .list_indexed => blk: {
                    const strip = resources.strip_list.?;
                    if (strip.centers.len != 0) break :blk evalSpeckleSIMDImpl(soft_edges, evalFixedStripSpeckleList2DImpl, u, v, strip, strip.params.background);
                    break :blk evalSpeckleSIMDImpl(soft_edges, evalGeneralStripSpeckleList2DImpl, u, v, strip, strip.params.background);
                },
                .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8 => evalClassifiedIndexedSpeckleSIMDImpl(u, v, active, &resources.neighbor_masked.?),
                .classified_indexed => evalClassifiedIndexedSpeckleSIMDImpl(u, v, active, &resources.classified.?),
                .direct_fixed => evalDirectFixedSpeckleSIMDImpl(u, v, active, &resources.direct_fixed.?),
                .mask_1bit, .mask_u8 => evalSpeckleMaskSIMDImpl(u, v, active, &resources.mask.?),
            };
        }

        // --------------------------------------------------------------------------------------
        // Speckle Generation & Scalar Evaluation
        // --------------------------------------------------------------------------------------

        inline fn speckleSoftness(params: Speckle2DParams) F {
            return if (supports_soft_edges) params.edge_softness else 0.0;
        }

        const SpeckleCellBounds = struct {
            min: [2]i64,
            max: [2]i64,
            dims: [2]usize,
            count: usize,
        };

        fn speckleProceduralCellBounds(
            params: Speckle2DParams,
            comptime padding: i64,
        ) ?SpeckleCellBounds {
            const min = [2]i64{ -padding, -padding };
            const max = [2]i64{
                @as(i64, @intFromFloat(@floor(params.cells_per_uv[0]))) + padding,
                @as(i64, @intFromFloat(@floor(params.cells_per_uv[1]))) + padding,
            };
            const dims = [2]usize{
                std.math.cast(usize, max[0] - min[0] + 1) orelse return null,
                std.math.cast(usize, max[1] - min[1] + 1) orelse return null,
            };
            const count = std.math.mul(usize, dims[0], dims[1]) catch return null;
            return .{ .min = min, .max = max, .dims = dims, .count = count };
        }

        fn speckleSampleIntervalDims(params: Speckle2DParams) ?[2]usize {
            var intervals: [2]usize = undefined;
            for (params.cells_per_uv, 0..) |cells, axis| {
                const interval_f = @ceil(cells * speckle_mask_samples_per_cell);
                const max_interval: F = @floatFromInt(std.math.maxInt(usize) - 1);
                if (!std.math.isFinite(interval_f) or interval_f > max_interval) return null;
                intervals[axis] = @intFromFloat(interval_f);
            }
            return intervals;
        }

        // -3 splits ownership before scaling; -5 uses the proven direct product.
        inline fn alignedMicrocell(proc: anytype) @TypeOf(proc) {
            const T = @TypeOf(proc);
            const r: T = if (@typeInfo(T) == .vector) @splat(speckle_mask_samples_per_cell) else speckle_mask_samples_per_cell;
            const last: T = if (@typeInfo(T) == .vector) @splat(speckle_mask_samples_per_cell - 1.0) else speckle_mask_samples_per_cell - 1.0;
            if (comptime direct_classification) return @floor(proc * r);
            const cell = @floor(proc);
            return cell * r + @min(last, @floor((proc - cell) * r));
        }

        fn classifiedDims(params: Speckle2DParams) ?[2]usize {
            if (comptime !aligned_classification) return speckleSampleIntervalDims(params);
            var dims: [2]usize = undefined;
            for (params.cells_per_uv, 0..) |cells, axis| {
                // Include the actual upper endpoint, including its own cell at integral C.
                const last = alignedMicrocell(cells);
                if (!std.math.isFinite(last) or last >= @as(F, @floatFromInt(std.math.maxInt(usize) - 1))) return null;
                dims[axis] = @as(usize, @intFromFloat(last)) + 1;
            }
            return dims;
        }

        const SpeckleCenter = struct { coordinate: F, unit: u16 };

        inline fn speckleCenter(
            cell: i64,
            unit: u16,
            center_min: F,
            extent: F,
            support2: F,
        ) SpeckleCenter {
            const cell_f: F = @floatFromInt(cell);
            const base = cell_f + center_min;
            const raw: SpeckleCenter = .{
                .coordinate = base + (@as(F, @floatFromInt(unit)) / 65_536.0) * extent,
                .unit = unit,
            };
            if (comptime speckle_neighbor_count == 9) return raw;
            const upper = cell_f + 1.0;
            const gap = upper - raw.coordinate;
            if (gap * gap >= support2) return raw;
            return @call(.never_inline, repairSpeckleCenter, .{ base, extent, upper, support2, unit });
        }

        // Upper excluded samples start at cell + 1; equality is safe for open support.
        // Below the lower face, the preceding float stays excluded at validated integer origins.
        // Decoding is monotone; find the nearest safe unit in at most 16 iterations.
        fn repairSpeckleCenter(base: F, extent: F, upper: F, support2: F, unit: u16) SpeckleCenter {
            @branchHint(.cold);
            var low: u16 = 0;
            var high = unit;
            while (low < high) {
                const mid = high - (high - low) / 2;
                const coordinate = base + (@as(F, @floatFromInt(mid)) / 65_536.0) * extent;
                const gap = upper - coordinate;
                if (gap * gap >= support2) {
                    low = mid;
                } else {
                    high = mid - 1;
                }
            }
            return .{
                .coordinate = base + (@as(F, @floatFromInt(low)) / 65_536.0) * extent,
                .unit = low,
            };
        }

        fn speckleDiskFromHash(
            comptime soft_edges: bool,
            cell_x: i64,
            cell_y: i64,
            hash: u64,
            params: Speckle2DParams,
        ) SpeckleDisk2D {
            const radius_variation = 2.0 * randomUnitFromHash(hash, 48) - 1.0;
            const edge_softness = if (soft_edges) params.edge_softness else 0.0;
            const radius = params.radius_mean + params.radius_jitter * radius_variation;
            const support = radius + edge_softness;
            const center_min = if (comptime speckle_neighbor_count == 1)
                support
            else
                0.0;
            const center_extent = switch (comptime speckle_neighbor_count) {
                1 => 1.0 - 2.0 * center_min,
                4 => 1.0 - support,
                9 => 1.0,
                else => unreachable,
            };
            return .{
                .center = .{
                    speckleCenter(
                        cell_x,
                        @truncate(hash >> 16),
                        center_min,
                        center_extent,
                        support * support,
                    ).coordinate,
                    speckleCenter(
                        cell_y,
                        @truncate(hash >> 32),
                        center_min,
                        center_extent,
                        support * support,
                    ).coordinate,
                },
                .radius = radius,
            };
        }

        fn speckleDiskForCell(
            comptime soft_edges: bool,
            cell_x: i64,
            cell_y: i64,
            params: Speckle2DParams,
        ) ?SpeckleDisk2D {
            const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
            if (randomUnitFromHash(hash, 0) >= params.occupancy) return null;
            return speckleDiskFromHash(soft_edges, cell_x, cell_y, hash, params);
        }

        fn generateSpeckleList2D(
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !SpeckleList2D {
            try params.validateResolved(config);
            return if (speckleSoftness(params) > 0.0)
                generateSpeckleList2DImpl(true, allocator, params)
            else
                generateSpeckleList2DImpl(false, allocator, params);
        }

        fn generateSpeckleList2DImpl(
            comptime soft_edges: bool,
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !SpeckleList2D {
            const cell_bounds = speckleProceduralCellBounds(params, 1) orelse
                return error.SpeckleListTooLarge;
            if (cell_bounds.count > max_speckle_cells) return error.SpeckleListTooLarge;

            var active_count: usize = 0;
            var cell_y = cell_bounds.min[1];
            while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
                var cell_x = cell_bounds.min[0];
                while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
                    if (speckleDiskForCell(soft_edges, cell_x, cell_y, params) != null) {
                        active_count += 1;
                    }
                }
            }

            const disks = try allocator.alloc(SpeckleDisk2D, active_count);
            var disk_index: usize = 0;
            cell_y = cell_bounds.min[1];
            while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
                var cell_x = cell_bounds.min[0];
                while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
                    if (speckleDiskForCell(soft_edges, cell_x, cell_y, params)) |disk| {
                        disks[disk_index] = disk;
                        disk_index += 1;
                    }
                }
            }
            return .{
                .params = params,
                .disks = disks,
            };
        }

        const strip_length: usize = switch (speckle_neighbor_count) {
            9 => 3,
            4 => 2,
            1 => 1,
            else => unreachable,
        };

        fn generateStripSpeckleList2D(allocator: std.mem.Allocator, params: Speckle2DParams) !StripSpeckleList2D {
            if (params.radius_jitter == 0.0) return generateStripSpeckleRecords(true, allocator, params);
            return generateStripSpeckleRecords(false, allocator, params);
        }

        fn generateStripSpeckleRecords(comptime fixed_radius: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !StripSpeckleList2D {
            try params.validateResolved(config);
            const bounds = speckleProceduralCellBounds(params, 1) orelse return error.SpeckleListTooLarge;
            if (bounds.count > max_speckle_cells) return error.SpeckleListTooLarge;
            const Record = if (fixed_radius) [2]F else SpeckleDisk2D;
            const count = std.math.mul(usize, bounds.count, strip_length) catch return error.SpeckleListTooLarge;
            _ = std.math.mul(usize, count, @sizeOf(Record)) catch return error.SpeckleListTooLarge;
            const records = try allocator.alloc(Record, count);
            const edge = if (config.soft_edges) params.edge_softness else 0.0;
            const support = params.radius_mean + edge;
            const center_min = if (speckle_neighbor_count == 1) support else 0.0;
            const extent = switch (speckle_neighbor_count) {
                1 => 1.0 - 2.0 * center_min,
                4 => 1.0 - support,
                9 => 1.0,
                else => unreachable,
            };
            const support2 = support * support;
            for (0..bounds.dims[1]) |yy| {
                for (0..bounds.dims[0]) |xx| {
                    const base = (yy * bounds.dims[0] + xx) * strip_length;
                    // Disjoint output rows cache retained owners, including the real outer halo.
                    if (yy != 0) {
                        const previous = base - bounds.dims[0] * strip_length;
                        @memcpy(records[base..][0 .. strip_length - 1], records[previous + 1 ..][0 .. strip_length - 1]);
                    }
                    const first: usize = if (yy == 0) 0 else strip_length - 1;
                    for (first..strip_length) |ii| {
                        const cell_x = bounds.min[0] + @as(i64, @intCast(xx));
                        const cell_y = bounds.min[1] + @as(i64, @intCast(yy)) + @as(i64, @intCast(ii)) - (if (speckle_neighbor_count == 9) @as(i64, 1) else 0);
                        records[base + ii] = if (fixed_radius) blk: {
                            const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
                            break :blk if (randomUnitFromHash(hash, 0) < params.occupancy) .{
                                speckleCenter(cell_x, @truncate(hash >> 16), center_min, extent, support2).coordinate,
                                speckleCenter(cell_y, @truncate(hash >> 32), center_min, extent, support2).coordinate,
                            } else .{ std.math.inf(F), 0.0 };
                        } else speckleDiskForCell(config.soft_edges, cell_x, cell_y, params) orelse .{ .center = .{ std.math.inf(F), 0.0 }, .radius = params.radius_mean };
                    }
                }
            }
            const outer = if (speckle_shape == .disk and config.soft_edges) params.radius_mean + edge else params.radius_mean;
            const inner = @max(0.0, params.radius_mean - edge);
            const sigma = params.radius_mean / 3.0;
            const max_outer = params.radius_mean + params.radius_jitter + edge;
            return .{
                .params = params,
                .disks = if (fixed_radius) &.{} else records,
                .centers = if (fixed_radius) records else &.{},
                .cell_origin = bounds.min,
                .cell_dims = bounds.dims,
                .outer2 = if (fixed_radius) outer * outer else 0.0,
                .inner2 = if (fixed_radius) inner * inner else 0.0,
                .sigma2 = if (fixed_radius) sigma * sigma else 0.0,
                .max_outer_radius2 = max_outer * max_outer,
            };
        }

        fn evalStripSpeckleList2DImpl(
            comptime soft_edges: bool,
            u: F,
            v: F,
            speckles: StripSpeckleList2D,
        ) F {
            if (speckles.centers.len != 0) return evalFixedStripSpeckleList2DImpl(soft_edges, u, v, speckles);
            return evalGeneralStripSpeckleList2DImpl(soft_edges, u, v, speckles);
        }

        fn evalFixedStripSpeckleList2DImpl(comptime soft_edges: bool, u: F, v: F, speckles: StripSpeckleList2D) F {
            // Infinity absence is already rejected by the mask; full and partial fixed storage share this kernel.
            return evalStripSpeckleList2DSpecialized(soft_edges, true, u, v, speckles);
        }

        fn evalGeneralStripSpeckleList2DImpl(comptime soft_edges: bool, u: F, v: F, speckles: StripSpeckleList2D) F {
            return evalStripSpeckleList2DSpecialized(soft_edges, false, u, v, speckles);
        }

        fn evalStripSpeckleList2DSpecialized(comptime soft_edges: bool, comptime fixed_radius: bool, u: F, v: F, speckles: StripSpeckleList2D) F {
            const uv = [2]F{ u, v };
            const params = speckles.params;
            if ((if (fixed_radius) speckles.centers.len else speckles.disks.len) == 0 or params.foreground == params.background) {
                return params.background;
            }
            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const cell_x_f = @floor(proc_x);
            const cell_y_f = @floor(proc_y);
            const cell_x: i64 = @intFromFloat(cell_x_f);
            const cell_y: i64 = @intFromFloat(cell_y_f);
            const frac_x = proc_x - cell_x_f;
            const frac_y = proc_y - cell_y_f;
            const offsets = if (comptime speckle_neighbor_count == 1)
                [_]i64{0}
            else if (comptime speckle_neighbor_count == 4)
                [_]i64{ 0, 1 }
            else
                [_]i64{ -1, 0, 1 };
            // Subtract the face directly: 1 - frac can round a genuinely inside point out.
            const min_delta_x = if (comptime speckle_neighbor_count == 1)
                [_]F{0.0}
            else if (comptime speckle_neighbor_count == 4)
                [_]F{ 0.0, cell_x_f + 1.0 - proc_x }
            else
                [_]F{ frac_x, 0.0, cell_x_f + 1.0 - proc_x };
            const min_delta_y = if (comptime speckle_neighbor_count == 1)
                [_]F{0.0}
            else if (comptime speckle_neighbor_count == 4)
                [_]F{ 0.0, cell_y_f + 1.0 - proc_y }
            else
                [_]F{ frac_y, 0.0, cell_y_f + 1.0 - proc_y };
            const edge_softness = if (soft_edges) params.edge_softness else 0.0;
            const max_outer_radius2 = speckles.max_outer_radius2;

            var coverage: F = 0.0;
            const row: usize = @intCast(cell_y - speckles.cell_origin[1]);
            neighbor_loop: for (offsets, min_delta_x) |offset_x, min_dx| {
                const column: usize = @intCast(cell_x + offset_x - speckles.cell_origin[0]);
                const base = (row * speckles.cell_dims[0] + column) * strip_length;
                for (min_delta_y, 0..) |min_dy, ii| {
                    if (min_dx * min_dx + min_dy * min_dy > max_outer_radius2) continue;
                    const disk = if (fixed_radius)
                        SpeckleDisk2D{ .center = speckles.centers[base + ii], .radius = params.radius_mean }
                    else
                        speckles.disks[base + ii];
                    // Infinity centers reject absent records at the mask bound, before sqrt/exp.
                    const delta_x = proc_x - disk.center[0];
                    const delta_y = proc_y - disk.center[1];
                    const distance2 = delta_x * delta_x + delta_y * delta_y;
                    coverage = @max(
                        coverage,
                        if (fixed_radius) fixedStripDiskMask(soft_edges, distance2, speckles) else speckleDiskMask(soft_edges, distance2, disk.radius, edge_softness),
                    );
                    if (coverage == 1.0) break :neighbor_loop;
                }
            }
            return params.background + coverage * (params.foreground - params.background);
        }

        inline fn evalClassifiedStripFallback(u: F, v: F, speckles: StripSpeckleList2D) F {
            if (comptime buildconfig.default_simd == .on) {
                if (speckles.centers.len != 0) return evalNeighborVectorStrip(true, u, v, speckles);
                return evalNeighborVectorStrip(false, u, v, speckles);
            }
            return evalStripSpeckleList2DImpl(false, u, v, speckles);
        }

        fn evalNeighborVectorStrip(comptime fixed_radius: bool, u: F, v: F, speckles: StripSpeckleList2D) F {
            comptime std.debug.assert(speckle_shape == .disk and !config.soft_edges and speckle_neighbor_count == 9);
            const params = speckles.params;
            const count = if (fixed_radius) speckles.centers.len else speckles.disks.len;
            if (count == 0 or params.foreground == params.background) return params.background;
            const proc_x = @max(0.0, @min(1.0, u)) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, v)) * params.cells_per_uv[1];
            const cell_x: i64 = @intFromFloat(@floor(proc_x));
            const cell_y: i64 = @intFromFloat(@floor(proc_y));
            const column: usize = @intCast(cell_x - 1 - speckles.cell_origin[0]);
            const row: usize = @intCast(cell_y - speckles.cell_origin[1]);
            const width = speckles.cell_dims[0];
            const base = (row * width + column) * 3;
            // The padded grid guarantees a complete row-local window, never a wrapped row.
            std.debug.assert(width >= 3 and column <= width - 3 and row < speckles.cell_dims[1] and count >= 9 and base <= count - 9);
            const NeighborVec = @Vector(9, F);
            var centers_x: NeighborVec = undefined;
            var centers_y: NeighborVec = undefined;
            var radius2: NeighborVec = @splat(speckles.outer2);
            inline for (0..9) |lane| {
                const disk = if (fixed_radius)
                    SpeckleDisk2D{ .center = speckles.centers[base + lane], .radius = params.radius_mean }
                else
                    speckles.disks[base + lane];
                centers_x[lane] = disk.center[0];
                centers_y[lane] = disk.center[1];
                if (!fixed_radius) radius2[lane] = disk.radius * disk.radius;
            }
            const delta_x = @as(NeighborVec, @splat(proc_x)) - centers_x;
            const delta_y = @as(NeighborVec, @splat(proc_y)) - centers_y;
            // Closed owner-cell centers bound actual distance below by the old cell-face bound;
            // radius² <= max support², so dropping that pruning cannot introduce a hit.
            const hit = @reduce(.Or, delta_x * delta_x + delta_y * delta_y < radius2);
            const coverage: F = @floatFromInt(@intFromBool(hit));
            return params.background + coverage * (params.foreground - params.background);
        }

        fn fixedStripDiskMask(comptime soft_edges: bool, distance2: F, speckles: StripSpeckleList2D) F {
            if (!(distance2 < speckles.outer2)) return 0.0;
            if (comptime speckle_shape == .gaussian) return @exp(-0.5 * distance2 / speckles.sigma2);
            if (comptime !soft_edges) return 1.0;
            if (distance2 <= speckles.inner2) return 1.0;
            const transition = (distance2 - speckles.inner2) / (speckles.outer2 - speckles.inner2);
            return 1.0 - cubicSmoothStep(transition);
        }

        const direct_fixed_center_bits: u64 = 0x0000_ffff_ffff_0000;
        const direct_fixed_active_bit: u64 = 1;

        fn directFixedSpeckleDescriptor(cell_x: i64, cell_y: i64, hash: u64, radius: F) u64 {
            var descriptor: u64 = direct_fixed_active_bit;
            for ([2]i64{ cell_x, cell_y }, [_]u6{ 16, 32 }) |cell, shift| {
                const center = speckleCenter(
                    cell,
                    @truncate(hash >> shift),
                    radius,
                    1.0 - 2.0 * radius,
                    radius * radius,
                );
                descriptor |= @as(u64, center.unit) << shift;
            }
            return descriptor;
        }

        fn directFixedSpeckleCenter(
            cell_x: i64,
            cell_y: i64,
            descriptor: u64,
            radius: F,
        ) [2]F {
            const center_extent = 1.0 - 2.0 * radius;
            return .{
                @as(F, @floatFromInt(cell_x)) + radius +
                    randomUnitFromHash(descriptor, 16) * center_extent,
                @as(F, @floatFromInt(cell_y)) + radius +
                    randomUnitFromHash(descriptor, 32) * center_extent,
            };
        }

        fn generateDirectFixedSpeckle2D(
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !DirectFixedSpeckle2D {
            try params.validateResolved(config);

            const cell_bounds = speckleProceduralCellBounds(params, 0) orelse
                return error.DirectFixedSpeckleTooLarge;
            const byte_count = std.math.mul(
                usize,
                cell_bounds.count,
                @sizeOf(DirectFixedSpeckleCell2D),
            ) catch return error.DirectFixedSpeckleTooLarge;
            if (byte_count > max_direct_fixed_speckle_bytes) {
                return error.DirectFixedSpeckleTooLarge;
            }

            const cells = try allocator.alloc(DirectFixedSpeckleCell2D, cell_bounds.count);
            errdefer allocator.free(cells);
            @memset(cells, 0);
            if (params.occupancy != 0.0) {
                var cell_y = cell_bounds.min[1];
                for (0..cell_bounds.dims[1]) |yy| {
                    var cell_x = cell_bounds.min[0];
                    for (0..cell_bounds.dims[0]) |xx| {
                        const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
                        if (params.occupancy == 1.0 or
                            randomUnitFromHash(hash, 0) < params.occupancy)
                        {
                            cells[yy * cell_bounds.dims[0] + xx] =
                                directFixedSpeckleDescriptor(cell_x, cell_y, hash, params.radius_mean);
                        }
                        cell_x += 1;
                    }
                    cell_y += 1;
                }
            }

            return .{
                .params = params,
                .cells = cells,
                .cell_origin = cell_bounds.min,
                .cell_dims = cell_bounds.dims,
                .radius2 = params.radius_mean * params.radius_mean,
            };
        }

        fn classifySpeckleDiskMicrocell(
            disk: SpeckleDisk2D,
            box_min: [2]F,
            box_max: [2]F,
        ) SpeckleClassificationState {
            const scale = @max(
                @as(F, 1.0),
                @max(
                    @max(@abs(box_min[0]), @abs(box_max[0])),
                    @max(
                        @max(@abs(box_min[1]), @abs(box_max[1])),
                        @max(@abs(disk.center[0]), @abs(disk.center[1])),
                    ),
                ),
            );
            // Exact inverse bins need only monotone rounded endpoint extrema (-8).
            const margin = if (comptime config.evaluator == .classified_indexed_8) 0.0 else 16.0 * std.math.floatEps(F) * scale;
            const far_x = @max(
                @abs(box_min[0] - disk.center[0]),
                @abs(box_max[0] - disk.center[0]),
            ) + margin;
            const far_y = @max(
                @abs(box_min[1] - disk.center[1]),
                @abs(box_max[1] - disk.center[1]),
            ) + margin;
            const inner_radius = disk.radius - margin;
            if (inner_radius > 0.0 and
                far_x * far_x + far_y * far_y < inner_radius * inner_radius)
            {
                return .foreground;
            }

            const min_x = @max(
                @as(F, 0.0),
                @max(
                    box_min[0] - disk.center[0],
                    disk.center[0] - box_max[0],
                ),
            );
            const min_y = @max(
                @as(F, 0.0),
                @max(
                    box_min[1] - disk.center[1],
                    disk.center[1] - box_max[1],
                ),
            );
            const safe_x = @max(@as(F, 0.0), min_x - margin);
            const safe_y = @max(@as(F, 0.0), min_y - margin);
            const outer_radius = disk.radius + margin;
            return if (safe_x * safe_x + safe_y * safe_y <= outer_radius * outer_radius)
                .ambiguous
            else
                .background;
        }

        test "exact rounded extrema certify inverse bins through coordinate ceilings" {
            if (comptime config.evaluator != .classified_indexed_8) return;
            const ceiling: usize = if (F == f32) 65_536 else 35_184_372_088_832;
            const r = buildconfig.speckle_mask_samples_per_cell;
            for ([_]usize{ 0, 1, r - 1, r, 17 * r + 3, (ceiling - 1) * r }) |j| {
                const lo = directMicrocellBoundary(F, r, j);
                const hi = std.math.nextAfter(F, directMicrocellBoundary(F, r, j + 1), -std.math.inf(F));
                const mid = lo + (hi - lo) * 0.5;
                for ([_]F{ lo, mid, hi, std.math.nextAfter(F, lo, -std.math.inf(F)), std.math.nextAfter(F, hi, std.math.inf(F)) }) |center| {
                    for ([_]F{ 0.0, std.math.nextAfter(F, 0.0, 1.0), 0.35, 1.0 }) |radius| {
                        const disk = SpeckleDisk2D{ .center = .{ center, mid }, .radius = radius };
                        const state = classifySpeckleDiskMicrocell(disk, .{ lo, lo }, .{ hi, hi });
                        const nearest = @max(lo, @min(hi, center));
                        for ([_]F{ lo, mid, hi, nearest }) |x| {
                            for ([_]F{ lo, mid, hi }) |y| {
                                const dx = x - center;
                                const dy = y - mid;
                                const hit = dx * dx + dy * dy < radius * radius;
                                if (state == .foreground) try testing.expect(hit);
                                if (state == .background) try testing.expect(!hit);
                            }
                        }
                    }
                }
            }
        }

        fn classifySpeckleMicrocell(
            speckles: StripSpeckleList2D,
            box_min: [2]F,
            box_max: [2]F,
        ) SpeckleClassificationState {
            const min_cell = [2]i64{
                @as(i64, @intFromFloat(@floor(box_min[0]))) - 1,
                @as(i64, @intFromFloat(@floor(box_min[1]))) - 1,
            };
            const max_cell = [2]i64{
                @as(i64, @intFromFloat(@floor(box_max[0]))) + 1,
                @as(i64, @intFromFloat(@floor(box_max[1]))) + 1,
            };
            const bounds = speckleProceduralCellBounds(speckles.params, 1).?;
            var state: SpeckleClassificationState = .background;
            var cell_y = min_cell[1];
            while (cell_y <= max_cell[1]) : (cell_y += 1) {
                var cell_x = min_cell[0];
                while (cell_x <= max_cell[0]) : (cell_x += 1) {
                    if (cell_x < bounds.min[0] or cell_x > bounds.max[0] or cell_y < bounds.min[1] or cell_y > bounds.max[1]) continue;
                    const disk = speckleDiskForCell(false, cell_x, cell_y, speckles.params) orelse continue;
                    switch (classifySpeckleDiskMicrocell(disk, box_min, box_max)) {
                        .foreground => return .foreground,
                        .ambiguous => state = .ambiguous,
                        .background => {},
                        .reserve3 => unreachable,
                    }
                }
            }
            return state;
        }

        fn buildSpeckleClassificationsExhaustive(
            states: []u8,
            dims: [2]usize,
            uv_to_cell: [2]F,
            speckles: StripSpeckleList2D,
        ) void {
            const proc_axes = speckleClassificationAxes(dims, uv_to_cell, speckles.params);
            for (0..dims[1]) |yy| {
                const proc_min_y = proc_axes[1].lowerBound(yy);
                const proc_max_y = proc_axes[1].upperBound(yy + 1);
                for (0..dims[0]) |xx| {
                    const proc_min_x = proc_axes[0].lowerBound(xx);
                    const proc_max_x = proc_axes[0].upperBound(xx + 1);
                    const state_index = yy * dims[0] + xx;
                    states[state_index / 4] = encodeSpeckleClassificationState(
                        states[state_index / 4],
                        state_index,
                        classifySpeckleMicrocell(
                            speckles,
                            .{ proc_min_x, proc_min_y },
                            .{ proc_max_x, proc_max_y },
                        ),
                    );
                }
            }
        }

        const speckle_classification_boundary_cache_capacity = 8192;

        const SpeckleClassificationIndexRange = struct {
            min: usize,
            max: usize,
        };

        const SpeckleClassificationAxis = struct {
            dim: usize,
            uv_to_cell: F,
            cells_per_uv: F,
            transform_margin: F,
            cached_boundaries: ?[]const F = null,

            inline fn lowerBound(self: @This(), index: usize) F {
                if (comptime direct_classification) return self.boundary(index);
                return self.boundary(index) - self.transform_margin;
            }

            inline fn upperBound(self: @This(), index: usize) F {
                if (comptime direct_classification) return std.math.nextAfter(F, self.boundary(index), -std.math.inf(F));
                return self.boundary(index) + self.transform_margin;
            }

            inline fn boundary(self: @This(), index: usize) F {
                if (self.cached_boundaries) |boundaries| return boundaries[index];
                if (comptime direct_classification) return directMicrocellBoundary(F, buildconfig.speckle_mask_samples_per_cell, index);
                if (comptime aligned_classification) {
                    const r = buildconfig.speckle_mask_samples_per_cell;
                    return @as(F, @floatFromInt(index / r)) + @as(F, @floatFromInt(index % r)) / speckle_mask_samples_per_cell;
                }
                const uv = @as(F, @floatFromInt(index)) / self.uv_to_cell;
                return uv * self.cells_per_uv;
            }
        };

        fn speckleClassificationAxes(
            dims: [2]usize,
            uv_to_cell: [2]F,
            params: Speckle2DParams,
        ) [2]SpeckleClassificationAxis {
            var axes: [2]SpeckleClassificationAxis = undefined;
            for (0..2) |axis| {
                const scale = @max(1.0, params.cells_per_uv[axis]);
                // Lookup multiplication, boundary division and procedural scaling cost
                // less than 4*eps*scale; 8 also covers rounding the expanded endpoints.
                // Coordinate and allocation limits keep indices exactly representable in F.
                axes[axis] = .{
                    .dim = dims[axis],
                    .uv_to_cell = uv_to_cell[axis],
                    .cells_per_uv = params.cells_per_uv[axis],
                    .transform_margin = 8.0 * std.math.floatEps(F) * scale,
                };
            }
            return axes;
        }

        fn speckleClassificationAxisRange(
            proc_min: F,
            proc_max: F,
            axis: SpeckleClassificationAxis,
        ) ?SpeckleClassificationIndexRange {
            const dim = axis.dim;
            if (comptime config.evaluator == .classified_indexed_6 or config.evaluator == .classified_indexed_7 or config.evaluator == .classified_indexed_8) {
                // Disjoint representable inverse bins: each endpoint selects its own bin.
                if (proc_max < 0.0) return null;
                const first: usize = @intFromFloat(@max(0.0, proc_min) * speckle_mask_samples_per_cell);
                if (first >= dim) return null;
                const last: usize = @intFromFloat(@max(0.0, proc_max) * speckle_mask_samples_per_cell);
                return .{ .min = first, .max = @min(dim - 1, last) };
            }
            var low: usize = 0;
            var high = dim;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const box_max = axis.upperBound(mid + 1);
                if (box_max >= proc_min) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
            const first = low;
            if (first == dim) return null;

            low = first;
            high = dim;
            while (low < high) {
                const mid = low + (high - low) / 2;
                const box_min = axis.lowerBound(mid);
                if (box_min > proc_max) {
                    high = mid;
                } else {
                    low = mid + 1;
                }
            }
            if (low == first) return null;
            return .{ .min = first, .max = low - 1 };
        }

        test "direct stamp ranges match exhaustive representable bin overlap" {
            if (comptime !direct_classification) return;
            for ([_]F{ 3.25, 0.03125, std.math.nextAfter(F, 0.0, 1.0) }) |cells| {
                const params = Speckle2DParams{ .cells_per_uv = .{ cells, cells } };
                const dims = classifiedDims(params).?;
                const axis = speckleClassificationAxes(dims, .{ cells * speckle_mask_samples_per_cell, cells * speckle_mask_samples_per_cell }, params)[0];
                for (0..axis.dim + 2) |boundary_index| {
                    const boundary = axis.boundary(boundary_index);
                    for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |p| {
                        for ([_][2]F{ .{ p, p }, .{ -1.0, p }, .{ p, cells + 2.0 } }) |interval| {
                            var expected: ?SpeckleClassificationIndexRange = null;
                            for (0..axis.dim) |i| {
                                if (axis.upperBound(i + 1) < interval[0] or axis.lowerBound(i) > interval[1]) continue;
                                if (expected) |*range| range.max = i else expected = .{ .min = i, .max = i };
                            }
                            try testing.expectEqualDeep(expected, speckleClassificationAxisRange(interval[0], interval[1], axis));
                        }
                    }
                }
            }
        }

        inline fn speckleClassificationSearchIncludesCell(
            box_min: F,
            box_max: F,
            cell: i64,
        ) bool {
            const min_cell = @as(i64, @intFromFloat(@floor(box_min))) - 1;
            const max_cell = @as(i64, @intFromFloat(@floor(box_max))) + 1;
            return cell >= min_cell and cell <= max_cell;
        }

        fn stampSpeckleDiskClassification(
            states: anytype,
            dims: [2]usize,
            proc_axes: [2]SpeckleClassificationAxis,
            domain_scale: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
        ) void {
            const center_scale = @max(@abs(disk.center[0]), @abs(disk.center[1]));
            const max_margin = 16.0 * std.math.floatEps(F) * @max(domain_scale, center_scale);
            // The exhaustive intersection test can reach two local margins beyond the disk.
            // Four domain-wide margins keep this candidate scan conservative under rounding;
            // the shared exact predicate below still decides every state transition.
            const stamp_radius = disk.radius + 4.0 * max_margin;
            // A margin-expanded disk with support below one cell cannot reach a
            // microcell whose exhaustive floor(box)-1..+1 search excludes that owner.
            // Specialize once per disk, not inside the microcell loops.
            if (stamp_radius < 1.0) {
                stampSpeckleDiskClassificationImpl(
                    true,
                    states,
                    dims,
                    proc_axes,
                    stamp_radius,
                    disk_cell,
                    disk,
                );
            } else {
                stampSpeckleDiskClassificationImpl(
                    false,
                    states,
                    dims,
                    proc_axes,
                    stamp_radius,
                    disk_cell,
                    disk,
                );
            }
        }

        fn stampSpeckleDiskClassificationImpl(
            comptime owner_search_is_implicit: bool,
            states: anytype,
            dims: [2]usize,
            proc_axes: [2]SpeckleClassificationAxis,
            stamp_radius: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
        ) void {
            const neighbor_masks = @TypeOf(states[0]) == u16;
            const y_range = speckleClassificationAxisRange(
                disk.center[1] - stamp_radius,
                disk.center[1] + stamp_radius,
                proc_axes[1],
            ) orelse return;
            const x_range = speckleClassificationAxisRange(
                disk.center[0] - stamp_radius,
                disk.center[0] + stamp_radius,
                proc_axes[0],
            ) orelse return;

            var x_masks: [64]u16 = undefined;
            const cache_x = neighbor_masks and !aligned_classification and x_range.max - x_range.min < x_masks.len;
            if (cache_x) {
                for (x_range.min..x_range.max + 1) |xx| x_masks[xx - x_range.min] = classificationAxisMask(proc_axes[0], xx, disk_cell[0], 3);
            }
            for (y_range.min..y_range.max + 1) |yy| {
                const proc_min_y = proc_axes[1].lowerBound(yy);
                const proc_max_y = proc_axes[1].upperBound(yy + 1);
                if (!owner_search_is_implicit and
                    !speckleClassificationSearchIncludesCell(
                        proc_min_y,
                        proc_max_y,
                        disk_cell[1],
                    )) continue;

                const y_mask = if (neighbor_masks) classificationAxisMask(proc_axes[1], yy, disk_cell[1], 1) else 0;
                if (neighbor_masks and aligned_classification and y_mask == 0) continue;
                for (x_range.min..x_range.max + 1) |xx| {
                    const state_index = yy * dims[0] + xx;
                    const packed_byte = if (neighbor_masks) 0 else states[state_index / 4];
                    const old_state = if (neighbor_masks)
                        (if (states[state_index] == 512) SpeckleClassificationState.foreground else .background)
                    else
                        decodeSpeckleClassificationState(packed_byte, state_index);
                    if (old_state == .foreground) continue;

                    const proc_min_x = proc_axes[0].lowerBound(xx);
                    const proc_max_x = proc_axes[0].upperBound(xx + 1);
                    if (!owner_search_is_implicit and
                        !speckleClassificationSearchIncludesCell(
                            proc_min_x,
                            proc_max_x,
                            disk_cell[0],
                        )) continue;

                    const x_mask = if (!neighbor_masks) 0 else if (cache_x) x_masks[xx - x_range.min] else classificationAxisMask(proc_axes[0], xx, disk_cell[0], 3);
                    if (neighbor_masks and aligned_classification and x_mask == 0) continue;
                    const disk_state = classifySpeckleDiskMicrocell(
                        disk,
                        .{ proc_min_x, proc_min_y },
                        .{ proc_max_x, proc_max_y },
                    );
                    if (neighbor_masks) {
                        if (disk_state == .foreground) {
                            // A covering disk dominates intersections and clears the mask.
                            states[state_index] = 512;
                        } else if (disk_state == .ambiguous) {
                            states[state_index] |= x_mask * y_mask;
                        }
                        continue;
                    }
                    const new_state: SpeckleClassificationState = switch (disk_state) {
                        .foreground => .foreground,
                        .ambiguous => if (old_state == .background) .ambiguous else old_state,
                        .background => old_state,
                        .reserve3 => unreachable,
                    };
                    if (new_state != old_state) {
                        states[state_index / 4] = encodeSpeckleClassificationState(
                            packed_byte,
                            state_index,
                            new_state,
                        );
                    }
                }
            }
        }

        fn buildSpeckleClassificationsFromOwnerRecords(
            states: anytype,
            dims: [2]usize,
            uv_to_cell: [2]F,
            speckles: StripSpeckleList2D,
        ) void {
            if (speckles.recordCount() == 0) return;

            // Covers the default 2305 + 1921 boundaries without arena scratch storage.
            var boundary_cache: [speckle_classification_boundary_cache_capacity]F = undefined;
            var cached_boundary_count: usize = 0;
            var proc_axes = speckleClassificationAxes(dims, uv_to_cell, speckles.params);
            var domain_scale: F = 1.0;
            for (0..2) |axis| {
                const domain_min = proc_axes[axis].lowerBound(0);
                const domain_max = proc_axes[axis].upperBound(dims[axis]);
                const axis_scale = @max(@abs(domain_min), @abs(domain_max));
                domain_scale = @max(domain_scale, axis_scale);

                const boundary_count = dims[axis] + 1;
                if (boundary_count <= boundary_cache.len - cached_boundary_count) {
                    const cache_end = cached_boundary_count + boundary_count;
                    const cached_boundaries = boundary_cache[cached_boundary_count..cache_end];
                    // Keep the exhaustive operation order; edge classifications are bit-sensitive.
                    for (cached_boundaries, 0..) |*boundary, index| {
                        boundary.* = proc_axes[axis].boundary(index);
                    }
                    proc_axes[axis].cached_boundaries = cached_boundaries;
                    cached_boundary_count = cache_end;
                }
            }

            for (0..speckles.cell_dims[1]) |yy| {
                const disk_cell_y = speckles.cell_origin[1] + @as(i64, @intCast(yy));
                for (0..speckles.cell_dims[0]) |xx| {
                    const cell_index = yy * speckles.cell_dims[0] + xx;
                    // Only the middle record owns this cell; outer records are halo replicas.
                    const disk = speckles.record(cell_index * strip_length + 1);
                    if (!std.math.isFinite(disk.center[0])) continue;
                    const disk_cell_x = speckles.cell_origin[0] + @as(i64, @intCast(xx));
                    stampSpeckleDiskClassification(
                        states,
                        dims,
                        proc_axes,
                        domain_scale,
                        .{ disk_cell_x, disk_cell_y },
                        disk,
                    );
                }
            }
        }

        fn generateClassifiedSpeckle2D(
            comptime Classified: type,
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !Classified {
            const State = if (Classified == NeighborMaskedSpeckle2D) u16 else u8;
            var speckles = try generateStripSpeckleList2D(allocator, params);
            errdefer allocator.free(speckles.centers);
            errdefer allocator.free(speckles.disks);
            var has_active_owner = false;
            for (0..speckles.cell_dims[0] * speckles.cell_dims[1]) |cell_index| {
                if (std.math.isFinite(speckles.record(cell_index * strip_length + 1).center[0])) {
                    has_active_owner = true;
                    break;
                }
            }
            // Zero-radius owners are active; halo-only realizations are genuinely empty.
            if (!has_active_owner) {
                allocator.free(speckles.centers);
                allocator.free(speckles.disks);
                speckles.centers = &.{};
                speckles.disks = &.{};
            }

            const dims = classifiedDims(params) orelse
                return error.SpeckleClassificationTooLarge;
            const state_count = std.math.mul(usize, dims[0], dims[1]) catch
                return error.SpeckleClassificationTooLarge;
            const stored_count = if (State == u16) state_count else blk: {
                const rounded = std.math.add(usize, state_count, 3) catch
                    return error.SpeckleClassificationTooLarge;
                break :blk rounded / 4;
            };
            if (stored_count > max_speckle_classification_bytes / @sizeOf(State)) {
                return error.SpeckleClassificationTooLarge;
            }
            const states = try allocator.alloc(State, stored_count);
            errdefer allocator.free(states);
            @memset(states, 0);
            const uv_to_cell = if (aligned_classification) [2]F{
                params.cells_per_uv[0] * speckle_mask_samples_per_cell,
                params.cells_per_uv[1] * speckle_mask_samples_per_cell,
            } else [2]F{ @floatFromInt(dims[0]), @floatFromInt(dims[1]) };
            buildSpeckleClassificationsFromOwnerRecords(states, dims, uv_to_cell, speckles);
            return .{
                .speckles = speckles,
                .states = states,
                .dims = dims,
                .uv_to_cell = uv_to_cell,
            };
        }

        fn classificationAxisMask(axis: SpeckleClassificationAxis, index: usize, owner: i64, stride: u4) u16 {
            if (comptime aligned_classification) {
                // Expanded geometry boxes do not expand the lookup's procedural owner.
                const relative = owner - @as(i64, @intCast(index / buildconfig.speckle_mask_samples_per_cell));
                return if (relative >= -1 and relative <= 1) @as(u16, 1) << @as(u4, @intCast((relative + 1) * stride)) else 0;
            }
            return neighborAxisMask(axis.lowerBound(index), axis.upperBound(index + 1), owner, stride);
        }

        fn neighborAxisMask(lo: F, hi: F, owner: i64, stride: u4) u16 {
            const low = @max(@as(i64, @intFromFloat(@floor(lo))), owner - 1);
            const high = @min(@as(i64, @intFromFloat(@floor(hi))), owner + 1);
            var mask: u16 = 0;
            var cell = low;
            while (cell <= high) : (cell += 1) {
                const bit: u4 = @intCast((owner - cell + 1) * stride);
                mask |= @as(u16, 1) << bit;
            }
            return mask;
        }

        fn evalMaskedNeighbors(comptime fixed_radius: bool, uv: [2]F, state: u16, speckles: StripSpeckleList2D) F {
            const params = speckles.params;
            return evalMaskedNeighborsAtProc(fixed_radius, .{
                @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0],
                @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1],
            }, state, speckles);
        }

        fn evalMaskedNeighborsAtProc(comptime fixed_radius: bool, proc: [2]F, state: u16, speckles: StripSpeckleList2D) F {
            const params = speckles.params;
            const proc_x = proc[0];
            const proc_y = proc[1];
            const cell_x: i64 = @intFromFloat(@floor(proc_x));
            const cell_y: i64 = @intFromFloat(@floor(proc_y));
            const column: usize = @intCast(cell_x - 1 - speckles.cell_origin[0]);
            const row: usize = @intCast(cell_y - speckles.cell_origin[1]);
            var remaining = state & 511;
            var hit = false;
            while (remaining != 0) {
                const bit = @ctz(remaining);
                remaining &= remaining - 1;
                const index = (row * speckles.cell_dims[0] + column + bit / 3) * 3 + bit % 3;
                const disk = if (fixed_radius) SpeckleDisk2D{ .center = speckles.centers[index], .radius = params.radius_mean } else speckles.disks[index];
                const dx = proc_x - disk.center[0];
                const dy = proc_y - disk.center[1];
                const distance2 = dx * dx + dy * dy;
                if (distance2 < (if (fixed_radius) speckles.outer2 else disk.radius * disk.radius)) {
                    hit = true;
                    break;
                }
            }
            return speckleCoverageEndpointValue(params, if (hit) 1.0 else 0.0);
        }

        test "neighbor masks preserve exact scalar SIMD boundaries and allocation cleanup" {
            if (comptime config.evaluator != .classified_indexed_2 and !aligned_classification and config.evaluator != .classified_indexed_4 and !direct_classification) return;
            for ([_]F{ 0.0, 0.08, 0.35 }) |jitter| {
                for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
                    const params: Speckle2DParams = .{
                        .cells_per_uv = .{ 3.17, 2.31 },
                        .radius_mean = 0.35,
                        .radius_jitter = jitter,
                        .occupancy = occupancy,
                        .foreground = -0.0,
                        .background = 0.23,
                    };
                    _ = try expectClassifiedExact(params);
                    var resources = try generateConfiguredResources(testing.allocator, params);
                    defer resources.deinit(testing.allocator);
                    const masked = resources.neighbor_masked.?;
                    const axes = speckleClassificationAxes(masked.dims, masked.uv_to_cell, params);
                    // Dense two-axis microcell crossings supplement nextAfter edge samples.
                    for (0..masked.dims[1] + 1) |yy| {
                        for (0..masked.dims[0] + 1) |xx| {
                            for ([_]F{ -std.math.floatEps(F), 0.0, std.math.floatEps(F), 0.5 / masked.uv_to_cell[0] }) |delta| {
                                try expectClassifiedSample(&resources, .{
                                    axes[0].boundary(xx) / params.cells_per_uv[0] + delta,
                                    axes[1].boundary(yy) / params.cells_per_uv[1] + delta,
                                });
                            }
                        }
                    }
                }
            }
            for ([_]F{ 0.0, 0.08 }) |jitter| {
                for ([_]F{ 0.0, 0.7 }) |occupancy| {
                    try testing.checkAllAllocationFailures(testing.allocator, struct {
                        fn run(allocator: std.mem.Allocator, radius_jitter: F, owner_occupancy: F) !void {
                            var resources = try generateConfiguredResources(allocator, .{ .cells_per_uv = .{ 2, 2 }, .radius_jitter = radius_jitter, .occupancy = owner_occupancy });
                            defer resources.deinit(allocator);
                            const masked = resources.neighbor_masked.?;
                            if (owner_occupancy == 0.0) {
                                try testing.expectEqual(@as(usize, 0), masked.speckles.recordCount());
                                for (masked.states) |state| try testing.expectEqual(@as(u16, 0), state);
                            } else {
                                try testing.expectEqual(radius_jitter == 0.0, masked.speckles.centers.len != 0);
                            }
                        }
                    }.run, .{ jitter, occupancy });
                }
            }
        }

        fn expectNeighborMaskCandidates(masked: NeighborMaskedSpeckle2D) !void {
            const params = masked.speckles.params;
            const Owner = struct { cell: [2]i64, disk: SpeckleDisk2D };
            const bounds = speckleProceduralCellBounds(params, 1).?;
            const owners = try testing.allocator.alloc(Owner, bounds.count);
            defer testing.allocator.free(owners);
            var owner_count: usize = 0;
            // Regenerate owners independently: do not use strip records, stamp ranges,
            // neighborAxisMask, or the separable mask multiplication being tested.
            for (0..bounds.dims[1]) |yy| {
                for (0..bounds.dims[0]) |xx| {
                    const cell: [2]i64 = .{ bounds.min[0] + @as(i64, @intCast(xx)), bounds.min[1] + @as(i64, @intCast(yy)) };
                    if (speckleDiskForCell(false, cell[0], cell[1], params)) |disk| {
                        owners[owner_count] = .{ .cell = cell, .disk = disk };
                        owner_count += 1;
                    }
                }
            }
            const axes = speckleClassificationAxes(masked.dims, masked.uv_to_cell, params);
            for (masked.states, 0..) |state, index| {
                const xx = index % masked.dims[0];
                const yy = index / masked.dims[0];
                const lo: [2]F = .{ axes[0].lowerBound(xx), axes[1].lowerBound(yy) };
                const hi: [2]F = .{ axes[0].upperBound(xx + 1), axes[1].upperBound(yy + 1) };
                const cell_lo: [2]i64 = if (aligned_classification)
                    .{ @intCast(xx / buildconfig.speckle_mask_samples_per_cell), @intCast(yy / buildconfig.speckle_mask_samples_per_cell) }
                else
                    .{ @intFromFloat(@floor(lo[0])), @intFromFloat(@floor(lo[1])) };
                const cell_hi: [2]i64 = if (aligned_classification) cell_lo else .{ @intFromFloat(@floor(hi[0])), @intFromFloat(@floor(hi[1])) };
                var covered = false;
                var expected_candidates: u16 = 0;
                for (owners[0..owner_count]) |owner| {
                    if (owner.cell[0] < cell_lo[0] - 1 or owner.cell[0] > cell_hi[0] + 1 or
                        owner.cell[1] < cell_lo[1] - 1 or owner.cell[1] > cell_hi[1] + 1) continue;
                    switch (classifySpeckleDiskMicrocell(owner.disk, lo, hi)) {
                        .foreground => covered = true,
                        .ambiguous => {
                            // Test all nine relative positions independently. A straddling
                            // microcell can require several bits for this single owner.
                            for (0..9) |bit| {
                                const sample_cell: [2]i64 = .{
                                    owner.cell[0] - (@as(i64, @intCast(bit / 3)) - 1),
                                    owner.cell[1] - (@as(i64, @intCast(bit % 3)) - 1),
                                };
                                if (sample_cell[0] >= cell_lo[0] and sample_cell[0] <= cell_hi[0] and
                                    sample_cell[1] >= cell_lo[1] and sample_cell[1] <= cell_hi[1])
                                {
                                    expected_candidates |= @as(u16, 1) << @as(u4, @intCast(bit));
                                }
                            }
                        },
                        .background => {},
                        .reserve3 => unreachable,
                    }
                }
                if (covered) {
                    try testing.expectEqual(@as(u16, 512), state);
                } else {
                    try testing.expectEqual(@as(u16, 0), state & 512);
                    // Supersets are intentional at procedural faces and conservative margins.
                    // Missing a potentially hitting owner/relative position is never allowed.
                    try testing.expectEqual(expected_candidates, state & expected_candidates);
                }
            }
        }

        test "aligned lookup keeps procedural owners and stamps one bit across faces and corners" {
            if (comptime !aligned_classification) return;
            const r = buildconfig.speckle_mask_samples_per_cell;
            // Probe the actual rounded procedural coordinate, not a real-number UV model.
            for ([_]F{ 0, 1, 2, 17, 4095, 65534 }) |face| {
                for ([_]F{ face, std.math.nextAfter(F, face, 0), std.math.nextAfter(F, face, std.math.inf(F)) }) |p| {
                    const index: usize = @intFromFloat(alignedMicrocell(p));
                    try testing.expectEqual(@as(usize, @intFromFloat(@floor(p))), index / r);
                    const vector: [S]F = alignedMicrocell(@as(VecSF, @splat(p)));
                    for (vector) |value| try testing.expectEqual(alignedMicrocell(p), value);
                }
            }
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 2, 2 } };
            const dims = classifiedDims(params).?;
            const axes = speckleClassificationAxes(dims, .{ 2 * speckle_mask_samples_per_cell, 2 * speckle_mask_samples_per_cell }, params);
            const states = try testing.allocator.alloc(u16, dims[0] * dims[1]);
            defer testing.allocator.free(states);
            for ([_][2]F{ .{ 1, 0.5 }, .{ 0.5, 1 }, .{ 1, 1 } }) |center| {
                @memset(states, 0);
                stampSpeckleDiskClassification(states, dims, axes, 2, .{ 0, 0 }, .{ .center = center, .radius = 0.02 });
                var found: usize = 0;
                for (states, 0..) |state, index| {
                    if (state == 0) continue;
                    found += 1;
                    const x = (index % dims[0]) / r;
                    const y = (index / dims[0]) / r;
                    try testing.expect(x <= 1 and y <= 1);
                    const bit: u4 = @intCast((1 - x) * 3 + 1 - y);
                    try testing.expectEqual(@as(u16, 1) << bit, state);
                }
                try testing.expect(found >= 4);
            }
        }

        test "neighbor mask face and corner crossings include every owner-relative candidate" {
            if (comptime config.evaluator != .classified_indexed_2) return;
            const cases = [_]struct { center: [2]F, index: usize, expected: u16 }{
                .{ .center = .{ 1.0, 0.5 }, .index = 1, .expected = 18 },
                .{ .center = .{ 0.5, 1.0 }, .index = 3, .expected = 24 },
                .{ .center = .{ 1.0, 1.0 }, .index = 4, .expected = 27 },
            };
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 2.0, 2.0 } };
            const axes = speckleClassificationAxes(.{ 3, 3 }, .{ 3, 3 }, params);
            for (cases) |case| {
                var states = [_]u16{0} ** 9;
                stampSpeckleDiskClassification(&states, .{ 3, 3 }, axes, 1.0, .{ 0, 0 }, .{ .center = case.center, .radius = 0.02 });
                try testing.expectEqual(@as(u16, 0), states[case.index] & 512);
                try testing.expectEqual(case.expected, states[case.index] & case.expected);
            }
        }

        test "neighbor mask stamp caches and direct boundaries agree on long ranges" {
            if (comptime config.evaluator != .classified_indexed_2) return;
            const dims: [2]usize = .{ 128, 1 };
            const uv_to_cell: [2]F = .{ 128, 1 };
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 0.5, 0.5 }, .radius_mean = 0.2 };
            const axes = speckleClassificationAxes(dims, uv_to_cell, params);
            const disk: SpeckleDisk2D = .{ .center = .{ 0.25, 0.25 }, .radius = 0.2 };
            const range = speckleClassificationAxisRange(disk.center[0] - disk.radius, disk.center[0] + disk.radius, axes[0]).?;
            try testing.expect(range.max - range.min >= 64); // Uncached x-mask path.
            var boundaries: [129]F = undefined;
            for (&boundaries, 0..) |*boundary, index| boundary.* = axes[0].boundary(index);
            var cached_axes = axes;
            cached_axes[0].cached_boundaries = &boundaries;
            var direct = [_]u16{0} ** 128;
            var cached = direct;
            stampSpeckleDiskClassification(&direct, dims, axes, 1.0, .{ 0, 0 }, disk);
            stampSpeckleDiskClassification(&cached, dims, cached_axes, 1.0, .{ 0, 0 }, disk);
            try testing.expectEqualSlices(u16, &direct, &cached);
            var found_candidate = false;
            for (direct) |state| found_candidate = found_candidate or state != 0;
            try testing.expect(found_candidate);
        }

        test "neighbor mask covering owner dominates intersections in either stamping order" {
            if (comptime config.evaluator != .classified_indexed_2) return;
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 0.1, 0.1 } };
            const axes = speckleClassificationAxes(.{ 1, 1 }, .{ 1, 1 }, params);
            const covering: SpeckleDisk2D = .{ .center = .{ 0.05, 0.05 }, .radius = 0.2 };
            const intersecting: SpeckleDisk2D = .{ .center = .{ -0.05, 0.05 }, .radius = 0.1 };
            var states = [_]u16{0};
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
            try testing.expectEqual(@as(u16, 432), states[0]);
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, covering);
            try testing.expectEqual(@as(u16, 512), states[0]);
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
            try testing.expectEqual(@as(u16, 512), states[0]);
        }

        test "unconditional classified loads keep inactive and nonfinite lanes backgrounded" {
            if (comptime config.evaluator != .classified_indexed_4 and !direct_classification) return;
            var resources = try generateConfiguredResources(testing.allocator, .{ .cells_per_uv = .{ 0.031, 1.17 }, .foreground = -0.0, .background = 0.23 });
            defer resources.deinit(testing.allocator);
            const params = resources.neighbor_masked.?.speckles.params;
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            const probes = [_]F{ -std.math.inf(F), std.math.nan(F), std.math.inf(F), -1, -0.0, 0, 1, 2 };
            for (0..probes.len) |batch| {
                var us: [S]F = undefined;
                var vs: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    us[lane] = probes[(batch + lane) % probes.len];
                    vs[lane] = probes[(batch * 3 + lane) % probes.len];
                    active[lane] = (batch + lane) % 3 == 0;
                }
                const actual: [S]F = Kernel(kernelIndex(config)).sampleSIMD(us, vs, active, params, &resources);
                for (0..S) |lane| {
                    const expected = if (active[lane] and std.math.isFinite(us[lane]) and std.math.isFinite(vs[lane])) evalSpeckle2D(.{ us[lane], vs[lane] }, params) else params.background;
                    try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
                }
            }
        }

        test "direct procedural endpoints include fractional tiny and ceiling scales" {
            if (comptime !direct_classification) return;
            const limit: F = if (F == f32) 65_536 else 35_184_372_088_832;
            const accepted_tie: F = limit - 1 + 0x1p-8;
            const rejected = std.math.nextAfter(F, accepted_tie, std.math.inf(F));
            try testing.expectEqual(limit, accepted_tie + 1);
            try testing.expect(rejected + 1 > limit);
            inline for (.{ 8, 12, 16 }) |r| try expectDirectMicrocell(F, r, accepted_tie);
            for (0..2) |axis| {
                var params: Speckle2DParams = .{};
                params.cells_per_uv[axis] = accepted_tie;
                try params.validateResolved(config);
                params.cells_per_uv[axis] = rejected;
                try testing.expectError(error.SpeckleCellCoordinateOutOfRange, params.validateResolved(config));
            }
            for ([_]F{ std.math.nextAfter(F, 0, 1), std.math.floatMin(F), 0.031, 0.5, 1, 1.17, limit - 1, accepted_tie }) |cells| {
                const params: Speckle2DParams = .{ .cells_per_uv = .{ cells, cells } };
                try params.validateResolved(config);
                const dims = classifiedDims(params).?;
                const axes = speckleClassificationAxes(dims, .{ 0, 0 }, params);
                for ([_]F{ -1, -0.0, 0, 0.5, std.math.nextAfter(F, 1, 0), 1, 2 }) |uv| {
                    const p = @max(0.0, @min(1.0, uv)) * cells;
                    const j: usize = @intFromFloat(classificationCoordinate(uv, cells, 0, dims[0]));
                    try testing.expect(j < dims[0]);
                    try testing.expect(p >= axes[0].lowerBound(j) and p <= axes[0].upperBound(j + 1));
                    try testing.expectEqual(@as(usize, @intFromFloat(@floor(p))), j / buildconfig.speckle_mask_samples_per_cell);
                }
                try testing.expectEqual(@as(usize, @intFromFloat(cells * speckle_mask_samples_per_cell)) + 1, dims[0]);
                if (cells > 2) continue; // Mathematical ceiling probes need no huge allocation.
                for ([_]F{ 0, 0.08 }) |jitter| {
                    var resources = try generateConfiguredResources(testing.allocator, .{ .cells_per_uv = params.cells_per_uv, .radius_jitter = jitter, .foreground = -0.0, .background = 0.23 });
                    defer resources.deinit(testing.allocator);
                    try expectNeighborMaskCandidates(resources.neighbor_masked.?);
                    for ([_][2]F{ .{ 0, 0 }, .{ -0.0, 1 }, .{ 1, 1 }, .{ 0.5, 0.5 }, .{ -1, 2 } }) |uv| try expectClassifiedSample(&resources, uv);
                }
            }
        }

        test "neighbor masks preserve tiny zero radii and endpoint arithmetic" {
            if (comptime config.evaluator != .classified_indexed_2 and !aligned_classification and config.evaluator != .classified_indexed_4 and !direct_classification) return;
            const tiny = @sqrt(std.math.floatMin(F)) * 0.25;
            for ([_]F{ tiny, 0.35 }) |radius| {
                for ([_][2]F{ .{ 0.23, -0.0 }, .{ -0.0, 0.0 }, .{ 0.0, -0.0 }, .{ 1.0, 0.0 } }) |colours| {
                    var resources = try generateConfiguredResources(testing.allocator, .{ .cells_per_uv = .{ 2.17, 1.31 }, .radius_mean = radius, .radius_jitter = 0, .occupancy = 1, .background = colours[0], .foreground = colours[1] });
                    defer resources.deinit(testing.allocator);
                    for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 3 }, .{ 0.5, 0.5 }, .{ std.math.nan(F), 0 }, .{ 0, -std.math.inf(F) } }) |uv| try expectClassifiedSample(&resources, uv);
                    const strip = resources.neighbor_masked.?.speckles;
                    for (0..strip.recordCount() / 3) |index| {
                        const disk = strip.record(index * 3 + 1);
                        if (!std.math.isFinite(disk.center[0])) continue;
                        try expectClassifiedSample(&resources, .{ disk.center[0] / strip.params.cells_per_uv[0], disk.center[1] / strip.params.cells_per_uv[1] });
                    }
                }
            }
        }

        fn speckleDiskMask(
            comptime soft_edges: bool,
            distance2: F,
            radius: F,
            edge_softness: F,
        ) F {
            const outer_radius = if (speckle_shape == .disk and soft_edges)
                radius + edge_softness
            else
                radius;
            const outer2 = outer_radius * outer_radius;
            if (!(distance2 < outer2)) return 0.0;
            if (comptime speckle_shape == .gaussian) {
                const sigma = radius / 3.0;
                return @exp(-0.5 * distance2 / (sigma * sigma));
            }
            if (comptime !soft_edges) return 1.0;

            const inner_radius = @max(0.0, radius - edge_softness);
            const inner2 = inner_radius * inner_radius;
            if (distance2 <= inner2) return 1.0;

            const transition = (distance2 - inner2) / (outer2 - inner2);
            return 1.0 - cubicSmoothStep(transition);
        }

        inline fn quantizeSpeckleCoverage(coverage: F) u8 {
            return @intFromFloat(@round(@max(0.0, @min(1.0, coverage)) * 255.0));
        }

        inline fn quinticPerlinFade(value: F) F {
            return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
        }

        inline fn perlinGradientDot(gradient_index: u8, delta_x: F, delta_y: F) F {
            const diagonal = @sqrt(@as(F, 0.5));
            return switch (gradient_index & 7) {
                0 => delta_x,
                1 => diagonal * (delta_x + delta_y),
                2 => delta_y,
                3 => diagonal * (-delta_x + delta_y),
                4 => -delta_x,
                5 => -diagonal * (delta_x + delta_y),
                6 => -delta_y,
                7 => diagonal * (delta_x - delta_y),
                else => unreachable,
            };
        }

        inline fn perlinCoverage(noise: F, params: Speckle2DParams) F {
            const width = params.perlin_coverage_transition_width;
            if (width == 0.0) {
                return if (noise >= params.perlin_coverage_threshold) 1.0 else 0.0;
            }
            const transition = (noise - params.perlin_coverage_threshold) / width + 0.5;
            return cubicSmoothStep(transition);
        }

        fn evalPerlinSpeckle2D(uv: [2]F, params: Speckle2DParams) F {
            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const cell_x = @as(i64, @intFromFloat(@floor(proc_x)));
            const cell_y = @as(i64, @intFromFloat(@floor(proc_y)));
            const frac_x = proc_x - @as(F, @floatFromInt(cell_x));
            const frac_y = proc_y - @as(F, @floatFromInt(cell_y));
            const fade_x = quinticPerlinFade(frac_x);
            const fade_y = quinticPerlinFade(frac_y);
            const noise_00 = perlinGradientDot(
                @truncate(hashSpeckleCell(cell_x, cell_y, params.seed)),
                frac_x,
                frac_y,
            );
            const noise_10 = perlinGradientDot(
                @truncate(hashSpeckleCell(cell_x + 1, cell_y, params.seed)),
                frac_x - 1.0,
                frac_y,
            );
            const noise_01 = perlinGradientDot(
                @truncate(hashSpeckleCell(cell_x, cell_y + 1, params.seed)),
                frac_x,
                frac_y - 1.0,
            );
            const noise_11 = perlinGradientDot(
                @truncate(hashSpeckleCell(cell_x + 1, cell_y + 1, params.seed)),
                frac_x - 1.0,
                frac_y - 1.0,
            );
            const noise_x0 = noise_00 + fade_x * (noise_10 - noise_00);
            const noise_x1 = noise_01 + fade_x * (noise_11 - noise_01);
            const noise = noise_x0 + fade_y * (noise_x1 - noise_x0);
            const coverage = perlinCoverage(noise, params);
            return params.background + coverage * (params.foreground - params.background);
        }

        fn rasterizePerlinSpeckleMask(
            allocator: std.mem.Allocator,
            bits: []u8,
            dims: [2]usize,
            row_stride: usize,
            uv_to_texel: [2]F,
            cell_bounds: SpeckleCellBounds,
            params: Speckle2DParams,
        ) !void {
            const gradient_count = std.math.mul(
                usize,
                cell_bounds.dims[0],
                cell_bounds.dims[1],
            ) catch return error.SpeckleMaskTooLarge;
            const gradient_indices = try allocator.alloc(u8, gradient_count);
            defer allocator.free(gradient_indices);

            for (0..cell_bounds.dims[1]) |yy| {
                const cell_y = cell_bounds.min[1] + @as(i64, @intCast(yy));
                for (0..cell_bounds.dims[0]) |xx| {
                    const cell_x = cell_bounds.min[0] + @as(i64, @intCast(xx));
                    gradient_indices[yy * cell_bounds.dims[0] + xx] =
                        @as(u8, @truncate(hashSpeckleCell(cell_x, cell_y, params.seed))) & 7;
                }
            }

            for (0..dims[1]) |yy| {
                const uv_y = @as(F, @floatFromInt(yy)) / uv_to_texel[1];
                const proc_y = uv_y * params.cells_per_uv[1];
                const cell_y = @as(i64, @intFromFloat(@floor(proc_y)));
                const rel_y = std.math.cast(usize, cell_y - cell_bounds.min[1]) orelse
                    return error.SpeckleMaskTooLarge;
                if (rel_y + 1 >= cell_bounds.dims[1]) return error.SpeckleMaskTooLarge;
                const frac_y = proc_y - @as(F, @floatFromInt(cell_y));
                const fade_y = quinticPerlinFade(frac_y);

                for (0..dims[0]) |xx| {
                    const uv_x = @as(F, @floatFromInt(xx)) / uv_to_texel[0];
                    const proc_x = uv_x * params.cells_per_uv[0];
                    const cell_x = @as(i64, @intFromFloat(@floor(proc_x)));
                    const rel_x = std.math.cast(usize, cell_x - cell_bounds.min[0]) orelse
                        return error.SpeckleMaskTooLarge;
                    if (rel_x + 1 >= cell_bounds.dims[0]) return error.SpeckleMaskTooLarge;
                    const frac_x = proc_x - @as(F, @floatFromInt(cell_x));
                    const fade_x = quinticPerlinFade(frac_x);
                    const gradient_row_0 = rel_y * cell_bounds.dims[0];
                    const gradient_row_1 = (rel_y + 1) * cell_bounds.dims[0];

                    const noise_00 = perlinGradientDot(
                        gradient_indices[gradient_row_0 + rel_x],
                        frac_x,
                        frac_y,
                    );
                    const noise_10 = perlinGradientDot(
                        gradient_indices[gradient_row_0 + rel_x + 1],
                        frac_x - 1.0,
                        frac_y,
                    );
                    const noise_01 = perlinGradientDot(
                        gradient_indices[gradient_row_1 + rel_x],
                        frac_x,
                        frac_y - 1.0,
                    );
                    const noise_11 = perlinGradientDot(
                        gradient_indices[gradient_row_1 + rel_x + 1],
                        frac_x - 1.0,
                        frac_y - 1.0,
                    );
                    const noise_x0 = noise_00 + fade_x * (noise_10 - noise_00);
                    const noise_x1 = noise_01 + fade_x * (noise_11 - noise_01);
                    const noise = noise_x0 + fade_y * (noise_x1 - noise_x0);
                    bits[yy * row_stride + xx] = quantizeSpeckleCoverage(
                        perlinCoverage(noise, params),
                    );
                }
            }
        }

        inline fn rasterizeSpeckleMaskDisk(
            comptime soft_edges: bool,
            bits: []u8,
            row_stride: usize,
            uv_to_texel: [2]F,
            params: Speckle2DParams,
            disk: SpeckleDisk2D,
        ) void {
            const edge_softness = if (soft_edges) params.edge_softness else 0.0;
            const outer_radius = disk.radius + edge_softness;
            const proc_to_texel = [2]F{
                uv_to_texel[0] / params.cells_per_uv[0],
                uv_to_texel[1] / params.cells_per_uv[1],
            };
            const texel_to_proc = [2]F{
                params.cells_per_uv[0] / uv_to_texel[0],
                params.cells_per_uv[1] / uv_to_texel[1],
            };
            const box_min = [2]F{
                (disk.center[0] - outer_radius) * proc_to_texel[0],
                (disk.center[1] - outer_radius) * proc_to_texel[1],
            };
            const box_max = [2]F{
                (disk.center[0] + outer_radius) * proc_to_texel[0],
                (disk.center[1] + outer_radius) * proc_to_texel[1],
            };
            if (box_max[0] < 0.0 or box_max[1] < 0.0 or
                box_min[0] > uv_to_texel[0] or box_min[1] > uv_to_texel[1]) return;
            const min_x: usize = @intFromFloat(@max(0.0, @floor(box_min[0])));
            const min_y: usize = @intFromFloat(@max(0.0, @floor(box_min[1])));
            const max_x: usize = @intFromFloat(@min(uv_to_texel[0], @ceil(box_max[0])));
            const max_y: usize = @intFromFloat(@min(uv_to_texel[1], @ceil(box_max[1])));

            for (min_y..max_y + 1) |yy| {
                const proc_y = @as(F, @floatFromInt(yy)) * texel_to_proc[1];
                const delta_y = proc_y - disk.center[1];
                for (min_x..max_x + 1) |xx| {
                    const proc_x = @as(F, @floatFromInt(xx)) * texel_to_proc[0];
                    const delta_x = proc_x - disk.center[0];
                    const coverage = speckleDiskMask(
                        soft_edges,
                        delta_x * delta_x + delta_y * delta_y,
                        disk.radius,
                        edge_softness,
                    );
                    if (comptime config.evaluator == .mask_u8) {
                        const idx = yy * row_stride + xx;
                        bits[idx] = @max(bits[idx], quantizeSpeckleCoverage(coverage));
                    } else if (coverage != 0.0) {
                        const shift: u3 = @intCast(xx & 7);
                        bits[yy * row_stride + xx / 8] |= @as(u8, 1) << shift;
                    }
                }
            }
        }

        fn generateSpeckleMask2D(
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !SpeckleMask2D {
            try params.validateResolved(config);
            return if (speckleSoftness(params) > 0.0)
                generateSpeckleMask2DImpl(true, allocator, params)
            else
                generateSpeckleMask2DImpl(false, allocator, params);
        }

        fn generateSpeckleMask2DImpl(
            comptime soft_edges: bool,
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !SpeckleMask2D {
            const cell_bounds = speckleProceduralCellBounds(params, 1) orelse
                return error.SpeckleMaskTooLarge;
            if (cell_bounds.count > max_speckle_cells) return error.SpeckleMaskTooLarge;

            const intervals = speckleSampleIntervalDims(params) orelse
                return error.SpeckleMaskTooLarge;
            const dims = [2]usize{
                std.math.add(usize, intervals[0], 1) catch return error.SpeckleMaskTooLarge,
                std.math.add(usize, intervals[1], 1) catch return error.SpeckleMaskTooLarge,
            };
            const row_stride = if (comptime config.evaluator == .mask_u8)
                dims[0]
            else
                std.math.divCeil(usize, dims[0], 8) catch
                    return error.SpeckleMaskTooLarge;
            const byte_count = std.math.mul(usize, row_stride, dims[1]) catch
                return error.SpeckleMaskTooLarge;
            if (byte_count > max_speckle_mask_bytes) return error.SpeckleMaskTooLarge;
            const uv_to_texel = [2]F{
                @floatFromInt(intervals[0]),
                @floatFromInt(intervals[1]),
            };
            var mask_params = params;
            if (comptime speckle_shape == .perlin) mask_params.occupancy = 1.0;
            const empty_pattern = if (comptime speckle_shape == .perlin)
                false
            else
                params.occupancy == 0.0;
            if (empty_pattern or params.foreground == params.background) {
                return .{
                    .bits = try allocator.alloc(u8, 0),
                    .dims = dims,
                    .row_stride = row_stride,
                    .uv_to_texel = uv_to_texel,
                    .params = mask_params,
                };
            }

            const bits = try allocator.alloc(u8, byte_count);
            errdefer allocator.free(bits);
            if (comptime speckle_shape == .perlin) {
                try rasterizePerlinSpeckleMask(
                    allocator,
                    bits,
                    dims,
                    row_stride,
                    uv_to_texel,
                    cell_bounds,
                    params,
                );
            } else {
                @memset(bits, 0);
                var cell_y = cell_bounds.min[1];
                while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
                    var cell_x = cell_bounds.min[0];
                    while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
                        const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
                        if (params.occupancy < 1.0 and
                            randomUnitFromHash(hash, 0) >= params.occupancy)
                        {
                            continue;
                        }
                        rasterizeSpeckleMaskDisk(
                            soft_edges,
                            bits,
                            row_stride,
                            uv_to_texel,
                            params,
                            speckleDiskFromHash(soft_edges, cell_x, cell_y, hash, params),
                        );
                    }
                }
            }

            return .{
                .bits = bits,
                .dims = dims,
                .row_stride = row_stride,
                .uv_to_texel = uv_to_texel,
                .params = mask_params,
            };
        }

        inline fn evalSpeckleMask2D(uv: [2]F, mask: SpeckleMask2D) F {
            const params = mask.params;
            if (params.occupancy == 0.0 or params.foreground == params.background or
                !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
            {
                return params.background;
            }
            const texel_x: usize = @intFromFloat(
                @max(0.0, @min(1.0, uv[0])) * mask.uv_to_texel[0] + 0.5,
            );
            const texel_y: usize = @intFromFloat(
                @max(0.0, @min(1.0, uv[1])) * mask.uv_to_texel[1] + 0.5,
            );
            if (comptime config.evaluator == .mask_u8) {
                const coverage = @as(F, @floatFromInt(
                    mask.bits[texel_y * mask.row_stride + texel_x],
                )) / 255.0;
                return params.background + coverage * (params.foreground - params.background);
            }
            const shift: u3 = @intCast(texel_x & 7);
            const is_foreground = mask.bits[texel_y * mask.row_stride + texel_x / 8] &
                (@as(u8, 1) << shift) != 0;
            return if (is_foreground) params.foreground else params.background;
        }

        inline fn directFixedSpeckleCellIndex(
            direct: DirectFixedSpeckle2D,
            cell_x: i64,
            cell_y: i64,
        ) ?usize {
            const delta_x = std.math.sub(i64, cell_x, direct.cell_origin[0]) catch return null;
            const delta_y = std.math.sub(i64, cell_y, direct.cell_origin[1]) catch return null;
            const rel_x = std.math.cast(usize, delta_x) orelse return null;
            const rel_y = std.math.cast(usize, delta_y) orelse return null;
            if (rel_x >= direct.cell_dims[0] or rel_y >= direct.cell_dims[1]) return null;
            return rel_y * direct.cell_dims[0] + rel_x;
        }

        inline fn evalDirectFixedSpeckle2D(
            uv: [2]F,
            direct: DirectFixedSpeckle2D,
        ) F {
            const params = direct.params;
            if (params.foreground == params.background or
                !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
            {
                return params.background;
            }

            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const cell_x: i64 = @intFromFloat(@floor(proc_x));
            const cell_y: i64 = @intFromFloat(@floor(proc_y));
            const cell_index = directFixedSpeckleCellIndex(direct, cell_x, cell_y) orelse
                return params.background;
            const descriptor = direct.cells[cell_index];
            if (descriptor == 0) return params.background;

            const center = directFixedSpeckleCenter(
                cell_x,
                cell_y,
                descriptor,
                params.radius_mean,
            );
            const dx = proc_x - center[0];
            const dy = proc_y - center[1];
            return if (dx * dx + dy * dy < direct.radius2)
                params.foreground
            else
                params.background;
        }

        fn evalSpeckleList2DNaiveImpl(
            comptime soft_edges: bool,
            u: F,
            v: F,
            speckles: SpeckleList2D,
        ) F {
            const uv = [2]F{ u, v };
            const params = speckles.params;
            if (speckles.disks.len == 0 or params.foreground == params.background) {
                return params.background;
            }
            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const edge_softness = if (soft_edges) params.edge_softness else 0.0;
            var coverage: F = 0.0;
            for (speckles.disks) |disk| {
                const delta_x = proc_x - disk.center[0];
                const delta_y = proc_y - disk.center[1];
                const distance2 = delta_x * delta_x + delta_y * delta_y;
                coverage = @max(
                    coverage,
                    speckleDiskMask(soft_edges, distance2, disk.radius, edge_softness),
                );
                if (coverage == 1.0) break;
            }
            return params.background + coverage * (params.foreground - params.background);
        }

        inline fn classificationCoordinate(uv: anytype, cells: F, scale: F, dim: usize) @TypeOf(uv) {
            const T = @TypeOf(uv);
            const vector = @typeInfo(T) == .vector;
            const zero: T = if (vector) @splat(0.0) else 0.0;
            const one: T = if (vector) @splat(1.0) else 1.0;
            const factor: T = if (vector) @splat(if (aligned_classification) cells else scale) else if (aligned_classification) cells else scale;
            const mapped = @max(zero, @min(one, uv)) * factor;
            const last: T = if (vector) @splat(@floatFromInt(dim - 1)) else @floatFromInt(dim - 1);
            if (comptime direct_classification) return mapped * (if (vector) @as(T, @splat(speckle_mask_samples_per_cell)) else speckle_mask_samples_per_cell);
            return @min(last, if (aligned_classification) alignedMicrocell(mapped) else mapped);
        }

        // Classified ambiguous samples retain compact indexed lookup; tests also use it as a reference.
        inline fn classifiedSpeckleState(
            uv: [2]F,
            classified: anytype,
        ) if (@TypeOf(classified) == NeighborMaskedSpeckle2D) u16 else SpeckleClassificationState {
            const cell_x: usize = @intFromFloat(classificationCoordinate(uv[0], classified.speckles.params.cells_per_uv[0], classified.uv_to_cell[0], classified.dims[0]));
            const cell_y: usize = @intFromFloat(classificationCoordinate(uv[1], classified.speckles.params.cells_per_uv[1], classified.uv_to_cell[1], classified.dims[1]));
            const state_index = cell_y * classified.dims[0] + cell_x;
            if (@TypeOf(classified) == NeighborMaskedSpeckle2D) return classified.states[state_index];
            return decodeSpeckleClassificationState(
                classified.states[state_index / 4],
                state_index,
            );
        }

        inline fn speckleCoverageEndpointValue(
            params: Speckle2DParams,
            coverage: F,
        ) F {
            return params.background + coverage * (params.foreground - params.background);
        }

        fn evalClassifiedIndexedSpeckle2D(
            uv: [2]F,
            classified: anytype,
        ) F {
            const params = classified.speckles.params;
            const empty = classified.speckles.recordCount() == 0;
            if (empty or
                params.foreground == params.background or
                !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
            {
                return params.background;
            }
            const state = classifiedSpeckleState(uv, classified);
            if (@TypeOf(classified) == NeighborMaskedSpeckle2D) {
                if ((state & 511) == 0) return speckleCoverageEndpointValue(params, if (state == 512) 1.0 else 0.0);
                if (classified.speckles.centers.len != 0) return evalMaskedNeighbors(true, uv, state, classified.speckles);
                return evalMaskedNeighbors(false, uv, state, classified.speckles);
            }
            return switch (state) {
                .background => speckleCoverageEndpointValue(params, 0.0),
                .foreground => speckleCoverageEndpointValue(params, 1.0),
                .ambiguous => evalClassifiedStripFallback(uv[0], uv[1], classified.speckles),
                .reserve3 => unreachable,
            };
        }

        fn evalSpeckle2D(uv: [2]F, params: Speckle2DParams) F {
            return if (speckleSoftness(params) > 0.0)
                evalSpeckle2DImpl(true, uv[0], uv[1], params)
            else
                evalSpeckle2DImpl(false, uv[0], uv[1], params);
        }

        fn evalSpeckle2DImpl(
            comptime soft_edges: bool,
            u: F,
            v: F,
            params: Speckle2DParams,
        ) F {
            if (comptime config.evaluator == .mock) return 0.5 * (u + v);
            const uv = [2]F{ u, v };
            if (comptime speckle_shape == .perlin) return evalPerlinSpeckle2D(uv, params);
            if (params.occupancy == 0.0 or params.foreground == params.background) {
                return params.background;
            }

            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const cell_x_f = @floor(proc_x);
            const cell_y_f = @floor(proc_y);
            const cell_x: i64 = @intFromFloat(cell_x_f);
            const cell_y: i64 = @intFromFloat(cell_y_f);
            const frac_x = proc_x - cell_x_f;
            const frac_y = proc_y - cell_y_f;
            const neighbor_offsets = if (comptime speckle_neighbor_count == 1)
                [_]i64{0}
            else if (comptime speckle_neighbor_count == 4)
                [_]i64{ 0, 1 }
            else
                [_]i64{ -1, 0, 1 };
            // Match indexed culling without the cancelling 1 - frac subtraction.
            const min_delta_x = if (comptime speckle_neighbor_count == 1)
                [_]F{0.0}
            else if (comptime speckle_neighbor_count == 4)
                [_]F{ 0.0, cell_x_f + 1.0 - proc_x }
            else
                [_]F{ frac_x, 0.0, cell_x_f + 1.0 - proc_x };
            const min_delta_y = if (comptime speckle_neighbor_count == 1)
                [_]F{0.0}
            else if (comptime speckle_neighbor_count == 4)
                [_]F{ 0.0, cell_y_f + 1.0 - proc_y }
            else
                [_]F{ frac_y, 0.0, cell_y_f + 1.0 - proc_y };
            const edge_softness = if (soft_edges) params.edge_softness else 0.0;
            const max_outer_radius = params.radius_mean + params.radius_jitter +
                edge_softness;
            const max_outer_radius2 = max_outer_radius * max_outer_radius;

            var coverage: F = 0.0;
            neighbor_loop: for (neighbor_offsets, min_delta_y) |offset_y, min_dy| {
                for (neighbor_offsets, min_delta_x) |offset_x, min_dx| {
                    const min_distance2 = min_dx * min_dx + min_dy * min_dy;
                    if (min_distance2 > max_outer_radius2) continue;

                    const candidate_x = cell_x + offset_x;
                    const candidate_y = cell_y + offset_y;
                    const hash = hashSpeckleCell(candidate_x, candidate_y, params.seed);
                    if (params.occupancy < 1.0 and
                        randomUnitFromHash(hash, 0) >= params.occupancy)
                    {
                        continue;
                    }

                    const disk = speckleDiskFromHash(
                        soft_edges,
                        candidate_x,
                        candidate_y,
                        hash,
                        params,
                    );
                    const delta_x = proc_x - disk.center[0];
                    const delta_y = proc_y - disk.center[1];
                    const distance2 = delta_x * delta_x + delta_y * delta_y;
                    coverage = @max(
                        coverage,
                        speckleDiskMask(soft_edges, distance2, disk.radius, edge_softness),
                    );
                    if (coverage == 1.0) break :neighbor_loop;
                }
            }

            return params.background + coverage * (params.foreground - params.background);
        }

        inline fn cubicSmoothStep(val: F) F {
            const clamped = @max(0.0, @min(1.0, val));
            return clamped * clamped * (3.0 - 2.0 * clamped);
        }

        // --------------------------------------------------------------------------------------
        // SIMD Evaluation
        // --------------------------------------------------------------------------------------

        inline fn evalSpeckleSIMDImpl(
            comptime soft_edges: bool,
            comptime eval: anytype,
            u: VecSF,
            v: VecSF,
            input: anytype,
            background: F,
        ) VecSF {
            const coord_0: [S]F = u;
            const coord_1: [S]F = v;
            var values: [S]F = undefined;
            for (0..S) |lane| {
                values[lane] = if (std.math.isFinite(coord_0[lane]) and
                    std.math.isFinite(coord_1[lane]))
                    eval(soft_edges, coord_0[lane], coord_1[lane], input)
                else
                    background;
            }
            return values;
        }

        inline fn evalClassifiedIndexedSpeckleSIMDImpl(
            u: VecSF,
            v: VecSF,
            v_mask_active: VecSB,
            classified: anytype,
        ) VecSF {
            const neighbor_masks = @TypeOf(classified.*) == NeighborMaskedSpeckle2D;
            const State = if (neighbor_masks) u16 else u8;
            const foreground = if (neighbor_masks) 512 else @intFromEnum(SpeckleClassificationState.foreground);
            const params = classified.speckles.params;
            const v_background: VecSF = @splat(params.background);
            const empty = classified.speckles.recordCount() == 0;
            if (empty or
                params.foreground == params.background)
            {
                return v_background;
            }

            const v_zero: VecSF = @splat(0.0);
            const v_inf: VecSF = @splat(std.math.inf(F));
            const v_sample = v_mask_active & (@abs(u) < v_inf) &
                (@abs(v) < v_inf);
            const v_u = @select(F, v_sample, u, v_zero);
            const v_v = @select(F, v_sample, v, v_zero);
            const carry_proc = config.evaluator == .classified_indexed_7 or config.evaluator == .classified_indexed_8;
            const v_proc_x = @max(v_zero, @min(@as(VecSF, @splat(1.0)), v_u)) * @as(VecSF, @splat(params.cells_per_uv[0]));
            const v_proc_y = @max(v_zero, @min(@as(VecSF, @splat(1.0)), v_v)) * @as(VecSF, @splat(params.cells_per_uv[1]));
            const v_cell_x: VecSI = @intFromFloat(if (carry_proc) v_proc_x * @as(VecSF, @splat(speckle_mask_samples_per_cell)) else classificationCoordinate(v_u, params.cells_per_uv[0], classified.uv_to_cell[0], classified.dims[0]));
            const v_cell_y: VecSI = @intFromFloat(if (carry_proc) v_proc_y * @as(VecSF, @splat(speckle_mask_samples_per_cell)) else classificationCoordinate(v_v, params.cells_per_uv[1], classified.uv_to_cell[1], classified.dims[1]));
            const sample: [S]bool = v_sample;
            const cell_x: [S]isize = v_cell_x;
            const cell_y: [S]isize = v_cell_y;
            var state_values = [_]State{0} ** S;
            // Inactive/nonfinite coordinates were sanitized to zero; -4/-5 may load
            // their valid states unconditionally, but never evaluates their candidates.
            inline for (0..S) |lane| {
                if (sample[lane] or (config.evaluator == .classified_indexed_4 or direct_classification)) {
                    const x: usize = @intCast(cell_x[lane]);
                    const y: usize = @intCast(cell_y[lane]);
                    const state_index = y * classified.dims[0] + x;
                    state_values[lane] = if (neighbor_masks) classified.states[state_index] else @intFromEnum(decodeSpeckleClassificationState(classified.states[state_index / 4], state_index));
                }
            }

            const v_states: @Vector(S, State) = state_values;
            const v_foreground = v_sample & (v_states == @as(
                @Vector(S, State),
                @splat(foreground),
            ));
            const v_certified_background: VecSF = @splat(
                speckleCoverageEndpointValue(params, 0.0),
            );
            const v_full_coverage: VecSF = @splat(
                speckleCoverageEndpointValue(params, 1.0),
            );
            var v_values = @select(F, v_sample, v_certified_background, v_background);
            v_values = @select(F, v_foreground, v_full_coverage, v_values);
            var values: [S]F = v_values;
            inline for (0..S) |lane| {
                const ambiguous = if (neighbor_masks)
                    state_values[lane] != 0 and state_values[lane] != foreground
                else
                    state_values[lane] == @intFromEnum(SpeckleClassificationState.ambiguous);
                if (sample[lane] and ambiguous) {
                    values[lane] = if (!neighbor_masks)
                        evalClassifiedStripFallback(u[lane], v[lane], classified.speckles)
                    else if (classified.speckles.centers.len != 0)
                        (if (carry_proc) evalMaskedNeighborsAtProc(true, .{ v_proc_x[lane], v_proc_y[lane] }, state_values[lane], classified.speckles) else evalMaskedNeighbors(true, .{ u[lane], v[lane] }, state_values[lane], classified.speckles))
                    else
                        (if (carry_proc) evalMaskedNeighborsAtProc(false, .{ v_proc_x[lane], v_proc_y[lane] }, state_values[lane], classified.speckles) else evalMaskedNeighbors(false, .{ u[lane], v[lane] }, state_values[lane], classified.speckles));
                }
            }
            return values;
        }

        inline fn evalDirectFixedSpeckleSIMDImpl(
            u: VecSF,
            v: VecSF,
            v_mask_active: VecSB,
            direct: *const DirectFixedSpeckle2D,
        ) VecSF {
            const params = direct.params;
            const v_background: VecSF = @splat(params.background);
            if (params.foreground == params.background) {
                return v_background;
            }

            const v_zero: VecSF = @splat(0.0);
            const v_one: VecSF = @splat(1.0);
            const v_inf: VecSF = @splat(std.math.inf(F));
            const v_sample = v_mask_active & (@abs(u) < v_inf) &
                (@abs(v) < v_inf);
            const v_u = @select(F, v_sample, u, v_zero);
            const v_v = @select(F, v_sample, v, v_zero);
            const v_proc_x = @max(v_zero, @min(v_one, v_u)) *
                @as(VecSF, @splat(params.cells_per_uv[0]));
            const v_proc_y = @max(v_zero, @min(v_one, v_v)) *
                @as(VecSF, @splat(params.cells_per_uv[1]));
            const v_cell_x: VecSI = @intFromFloat(@floor(v_proc_x));
            const v_cell_y: VecSI = @intFromFloat(@floor(v_proc_y));
            const sample: [S]bool = v_sample;
            const cell_x: [S]isize = v_cell_x;
            const cell_y: [S]isize = v_cell_y;
            var descriptors = [_]u64{0} ** S;
            inline for (0..S) |lane| {
                if (sample[lane]) {
                    if (directFixedSpeckleCellIndex(
                        direct.*,
                        @intCast(cell_x[lane]),
                        @intCast(cell_y[lane]),
                    )) |cell_index| {
                        descriptors[lane] = direct.cells[cell_index];
                    }
                }
            }

            const VecSU64 = @Vector(S, u64);
            const VecSU16 = @Vector(S, u16);
            const VecSU6 = @Vector(S, u6);
            const v_descriptors: VecSU64 = descriptors;
            const v_center_x_bits: VecSU16 = @truncate(
                v_descriptors >> @as(VecSU6, @splat(16)),
            );
            const v_center_y_bits: VecSU16 = @truncate(
                v_descriptors >> @as(VecSU6, @splat(32)),
            );
            const v_radius: VecSF = @splat(params.radius_mean);
            const v_center_extent: VecSF = @splat(1.0 - 2.0 * params.radius_mean);
            const v_random_scale: VecSF = @splat(1.0 / 65_536.0);
            const v_center_x = @as(VecSF, @floatFromInt(v_cell_x)) + v_radius +
                @as(VecSF, @floatFromInt(v_center_x_bits)) * v_random_scale * v_center_extent;
            const v_center_y = @as(VecSF, @floatFromInt(v_cell_y)) + v_radius +
                @as(VecSF, @floatFromInt(v_center_y_bits)) * v_random_scale * v_center_extent;
            const v_dx = v_proc_x - v_center_x;
            const v_dy = v_proc_y - v_center_y;
            const v_inside = v_sample &
                (v_descriptors != @as(VecSU64, @splat(0))) &
                (v_dx * v_dx + v_dy * v_dy < @as(VecSF, @splat(direct.radius2)));
            const v_value = @select(
                F,
                v_inside,
                @as(VecSF, @splat(params.foreground)),
                v_background,
            );
            return v_value;
        }

        inline fn evalSpeckleMaskSIMDImpl(
            u: VecSF,
            v: VecSF,
            v_mask_active: VecSB,
            mask: *const SpeckleMask2D,
        ) VecSF {
            const params = mask.params;
            const v_background: VecSF = @splat(params.background);
            if (params.occupancy == 0.0 or params.foreground == params.background) {
                return v_background;
            }

            const v_zero: VecSF = @splat(0.0);
            const v_one: VecSF = @splat(1.0);
            const v_half: VecSF = @splat(0.5);
            const v_inf: VecSF = @splat(std.math.inf(F));
            const v_sample = v_mask_active & (@abs(u) < v_inf) &
                (@abs(v) < v_inf);
            const v_u = @select(F, v_sample, u, v_zero);
            const v_v = @select(F, v_sample, v, v_zero);
            const v_texel_x: VecSI = @intFromFloat(
                @max(v_zero, @min(v_one, v_u)) *
                    @as(VecSF, @splat(mask.uv_to_texel[0])) + v_half,
            );
            const v_texel_y: VecSI = @intFromFloat(
                @max(v_zero, @min(v_one, v_v)) *
                    @as(VecSF, @splat(mask.uv_to_texel[1])) + v_half,
            );
            const sample: [S]bool = v_sample;
            const texel_x: [S]isize = v_texel_x;
            const texel_y: [S]isize = v_texel_y;

            if (comptime config.evaluator == .mask_u8) {
                var coverage_bytes = [_]u8{0} ** S;
                inline for (0..S) |lane| {
                    if (sample[lane]) {
                        const x: usize = @intCast(texel_x[lane]);
                        const y: usize = @intCast(texel_y[lane]);
                        coverage_bytes[lane] = mask.bits[y * mask.row_stride + x];
                    }
                }
                const v_coverage_u8: @Vector(S, u8) = coverage_bytes;
                const v_coverage: VecSF = @as(
                    VecSF,
                    @floatFromInt(v_coverage_u8),
                ) / @as(VecSF, @splat(255.0));
                const v_value = v_background + v_coverage *
                    @as(VecSF, @splat(params.foreground - params.background));
                return v_value;
            }

            var is_foreground = [_]bool{false} ** S;
            inline for (0..S) |lane| {
                if (sample[lane]) {
                    const x: usize = @intCast(texel_x[lane]);
                    const y: usize = @intCast(texel_y[lane]);
                    const shift: u3 = @intCast(x & 7);
                    is_foreground[lane] = mask.bits[y * mask.row_stride + x / 8] &
                        (@as(u8, 1) << shift) != 0;
                }
            }
            const v_value = @select(
                F,
                v_sample & @as(VecSB, is_foreground),
                @as(VecSF, @splat(params.foreground)),
                v_background,
            );
            return v_value;
        }

        // --------------------------------------------------------------------------------------
        // Tests
        // --------------------------------------------------------------------------------------

        const testing = std.testing;
        const unit_tol: F = if (F == f32) 1e-5 else 1e-12;

        // Generated fixtures own their allocations; stack-backed SIMD fixtures do not.
        fn deinitTestResources(resources: Resources) void {
            var owned = resources;
            owned.deinit(testing.allocator);
        }

        test "procedural speckle hash has stable known vectors" {
            try testing.expectEqual(@as(u64, 0x42cc592e95069169), hashSpeckleCell(0, 0, 0));
            try testing.expectEqual(@as(u64, 0xe4214bce0919ce5d), hashSpeckleCell(17, 29, 12345));
            try testing.expectEqual(
                @as(u64, 0xcbba3e407b1fa232),
                hashSpeckleCell(-7, -11, 0xa511e9b3),
            );
            try testing.expectEqual(
                @as(u64, 0x833cd6c57d01169f),
                hashSpeckleCell(-1, 5, std.math.maxInt(u32)),
            );
        }

        test "procedural speckle validates common parameter ranges" {
            const coord_limit: F = if (F == f32) 65_536.0 else 35_184_372_088_832.0;
            const cases = [_]struct { params: Speckle2DParams, err: anyerror }{
                .{ .params = .{ .cells_per_uv = .{ 0.0, 1.0 } }, .err = error.InvalidSpeckleCellsPerUV },
                .{ .params = .{ .cells_per_uv = .{ 1.0, std.math.nan(F) } }, .err = error.InvalidSpeckleCellsPerUV },
                .{ .params = .{ .cells_per_uv = .{ coord_limit, 1.0 } }, .err = error.SpeckleCellCoordinateOutOfRange },
                .{ .params = .{ .foreground = 1.1 }, .err = error.InvalidSpeckleForeground },
                .{ .params = .{ .background = -0.1 }, .err = error.InvalidSpeckleBackground },
                .{ .params = .{ .background = std.math.nan(F) }, .err = error.InvalidSpeckleBackground },
            };
            for (cases) |case| try testing.expectError(case.err, case.params.validateResolved(config));
        }

        test "disk and Gaussian speckles validate probability and radius ranges" {
            if (comptime config.evaluator == .mock or speckle_shape == .perlin) return;
            const cases = [_]struct { params: Speckle2DParams, err: anyerror }{
                .{ .params = .{ .occupancy = -0.1 }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .occupancy = 1.1 }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .occupancy = std.math.nan(F) }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .radius_mean = 0.0 }, .err = error.InvalidSpeckleRadiusMean },
                .{ .params = .{ .radius_mean = std.math.inf(F) }, .err = error.InvalidSpeckleRadiusMean },
                .{ .params = .{ .radius_jitter = -0.1 }, .err = error.InvalidSpeckleRadiusJitter },
                .{ .params = .{ .radius_jitter = std.math.nan(F) }, .err = error.InvalidSpeckleRadiusJitter },
            };
            for (cases) |case| try testing.expectError(case.err, case.params.validateResolved(config));
        }

        test "procedural speckle parameters validate shape-specific settings" {
            if (comptime config.evaluator == .mock) return;
            var invalid = Speckle2DParams{};
            try testing.expectEqual(@as(F, 0.0), invalid.edge_softness);
            try invalid.validateResolved(config);
            if (comptime speckle_shape == .perlin) {
                invalid.perlin_coverage_threshold = std.math.nan(F);
                try testing.expectError(error.InvalidSpecklePerlinCoverageThreshold, invalid.validateResolved(config));
                invalid.perlin_coverage_threshold = 0.0;
                for ([_]F{ -0.01, std.math.nan(F), std.math.inf(F) }) |width| {
                    invalid.perlin_coverage_transition_width = width;
                    try testing.expectError(
                        error.InvalidSpecklePerlinCoverageTransitionWidth,
                        invalid.validateResolved(config),
                    );
                }
                invalid.perlin_coverage_transition_width = 0.0;
                try invalid.validateResolved(config);
                invalid = Speckle2DParams{};
                invalid.occupancy = -1.0;
                invalid.radius_mean = -1.0;
                invalid.radius_jitter = -1.0;
                try invalid.validateResolved(config);
            } else {
                invalid.perlin_coverage_threshold = std.math.nan(F);
                invalid.perlin_coverage_transition_width = -1.0;
                try invalid.validateResolved(config);
                if (comptime config.evaluator == .direct_fixed) {
                    invalid.radius_jitter = 0.01;
                    try testing.expectError(
                        error.InvalidDirectFixedSpeckleRadiusJitter,
                        invalid.validateResolved(config),
                    );
                } else {
                    invalid.radius_jitter = invalid.radius_mean + 0.01;
                    try testing.expectError(error.InvalidSpeckleRadiusRange, invalid.validateResolved(config));
                }

                invalid = Speckle2DParams{};
                invalid.radius_mean = if (speckle_neighbor_count == 1) 0.5 else 1.0;
                try invalid.validateResolved(config);
                invalid.radius_mean = std.math.nextAfter(F, invalid.radius_mean, std.math.inf(F));
                try testing.expectError(
                    if (config.evaluator == .direct_fixed)
                        error.InvalidDirectFixedSpeckleRadius
                    else
                        error.InvalidSpeckleNeighborhoodRadius,
                    invalid.validateResolved(config),
                );
            }
        }

        test "procedural speckle rejects negative and nonfinite softness for every shape" {
            for ([_]F{ -0.01, std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |softness| {
                const params: Speckle2DParams = .{ .edge_softness = softness };
                try testing.expectError(error.InvalidSpeckleEdgeSoftness, params.validateResolved(config));
            }
        }

        test "procedural speckle softness requires compatible disk evaluators" {
            const params: Speckle2DParams = .{ .edge_softness = 0.05 };
            if (comptime speckle_shape != .disk) {
                try testing.expectError(error.SpeckleEdgeSoftnessRequiresDisk, params.validateResolved(config));
                return;
            }
            switch (comptime config.evaluator) {
                .classified_indexed, .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8, .direct_fixed, .mask_1bit => {
                    try testing.expectError(
                        error.SpeckleEvaluatorRequiresHardEdges,
                        params.validateResolved(config),
                    );
                },
                .cell_hash, .list_naive, .list_indexed, .mask_u8, .mock => try params.validateResolved(config),
            }
        }

        test "procedural speckle softness expands support bounds" {
            if (comptime config.evaluator == .mock or !supports_soft_edges) return;
            const radius_limit: F = if (speckle_neighbor_count == 1) 0.5 else 1.0;
            var params: Speckle2DParams = .{
                .radius_mean = radius_limit - 0.125,
                .edge_softness = 0.125,
            };
            try params.validateResolved(config);
            params.edge_softness = 0.25;
            try testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validateResolved(config));
            params.edge_softness = 0.0;
            params.radius_jitter = 0.125;
            try params.validateResolved(config);
            params.edge_softness = 0.125;
            try testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validateResolved(config));
        }

        test "speckle generators reject invalid softness before allocating" {
            const params: Speckle2DParams = .{ .edge_softness = std.math.nan(F) };
            inline for (.{ ClassifiedIndexedSpeckle2D, NeighborMaskedSpeckle2D }) |Classified| {
                try testing.expectError(error.InvalidSpeckleEdgeSoftness, generateClassifiedSpeckle2D(Classified, testing.failing_allocator, params));
            }
            inline for (.{
                generateConfiguredResources,
                generateSpeckleList2D,
                generateDirectFixedSpeckle2D,
                generateSpeckleMask2D,
            }) |generate| {
                try testing.expectError(
                    error.InvalidSpeckleEdgeSoftness,
                    generate(testing.failing_allocator, params),
                );
            }
        }

        test "procedural speckle shape has bounded support" {
            if (comptime speckle_shape == .gaussian) {
                try testing.expectEqual(@as(F, 1.0), speckleDiskMask(false, 0.0, 0.5, 0.0));
                const transition = speckleDiskMask(false, 0.0625, 0.5, 0.0);
                try testing.expect(transition > 0.0);
                try testing.expect(transition < 1.0);
                try testing.expectEqual(@as(F, 0.0), speckleDiskMask(false, 0.25, 0.5, 0.0));
            } else if (comptime speckle_shape == .disk) {
                inline for (.{ false, true }) |soft_edges| {
                    const inside = std.math.nextAfter(F, 0.25, 0.0);
                    try testing.expectEqual(@as(F, 1.0), speckleDiskMask(soft_edges, inside, 0.5, 0.0));
                    try testing.expectEqual(@as(F, 0.0), speckleDiskMask(soft_edges, 0.25, 0.5, 0.0));
                    try testing.expectEqual(@as(F, 0.0), speckleDiskMask(soft_edges, 0.0, 0.0, 0.0));
                }
                try testing.expectEqual(@as(F, 0.0), speckleDiskMask(false, 0.251, 0.5, 0.0));

                const transition = speckleDiskMask(true, 0.25, 0.5, 0.1);
                try testing.expect(transition > 0.0 and transition < 1.0);
            } else {
                const params = Speckle2DParams{};
                try testing.expectEqual(@as(F, 0.0), perlinCoverage(-1.0, params));
                try testing.expectEqual(@as(F, 1.0), perlinCoverage(1.0, params));
                const transition = perlinCoverage(params.perlin_coverage_threshold, params);
                try testing.expect(transition > 0.0 and transition < 1.0);
            }
        }

        test "procedural speckle is bounded seed-sensitive and UV clamped" {
            if (comptime config.evaluator == .mock) return;
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 12.0, 10.0 } };

            try testing.expectEqual(
                evalSpeckle2D(.{ 0.0, 1.0 }, params),
                evalSpeckle2D(.{ -2.0, 3.0 }, params),
            );

            var seed_changed = params;
            seed_changed.seed +%= 1;
            var found_seed_difference = false;
            for (0..16) |yy| {
                for (0..16) |xx| {
                    const uv = [2]F{
                        @as(F, @floatFromInt(xx)) / 15.0,
                        @as(F, @floatFromInt(yy)) / 15.0,
                    };
                    const sample = evalSpeckle2D(uv, params);
                    try testing.expect(sample >= @min(params.foreground, params.background));
                    try testing.expect(sample <= @max(params.foreground, params.background));
                    if (sample != evalSpeckle2D(uv, seed_changed)) {
                        found_seed_difference = true;
                    }
                }
            }
            try testing.expect(found_seed_difference);
        }

        test "procedural speckle SIMD fallback matches scalar evaluation" {
            if (comptime config.evaluator == .mock) return;
            var speckle_params: Speckle2DParams = .{
                .cells_per_uv = .{ 11.0, 9.0 },
                .seed = 42,
                .edge_softness = if (supports_soft_edges) 0.035 else 0.0,
                .pattern = config.pattern,
            };
            if (comptime buildconfig.enable_all_evaluators) {
                speckle_params.evaluator = config.evaluator;
                speckle_params.neighbor_count = if (speckle_shape == .perlin) null else speckle_neighbor_count;
            }

            var coords_0: [S]F = undefined;
            var coords_1: [S]F = undefined;
            for (0..S) |lane| {
                coords_0[lane] = @as(F, @floatFromInt(lane)) / @as(F, @floatFromInt(S));
                coords_1[lane] = 1.0 - coords_0[lane];
            }
            const values_simd: [S]F = sampleSIMD(
                coords_0,
                coords_1,
                @splat(true),
                speckle_params,
                &.{},
            );
            const inactive: [S]F = sampleSIMD(
                coords_0,
                coords_1,
                @splat(false),
                speckle_params,
                &.{},
            );
            for (0..S) |lane| {
                const expected = evalSpeckle2D(.{ coords_0[lane], coords_1[lane] }, speckle_params);
                try testing.expectEqual(expected, values_simd[lane]);
                try testing.expectEqual(expected, inactive[lane]);
                coords_0[lane] = if (lane & 1 == 0) std.math.nan(F) else 0.0;
                coords_1[lane] = if (lane & 1 == 0) 0.0 else std.math.inf(F);
            }
            const nonfinite: [S]F = sampleSIMD(
                coords_0,
                coords_1,
                @splat(true),
                speckle_params,
                &.{},
            );
            for (nonfinite) |value| try testing.expectEqual(speckle_params.background, value);
        }

        test "procedural speckle occupancy endpoints behave exactly" {
            if (comptime config.evaluator == .mock or speckle_shape == .perlin) return;
            var params: Speckle2DParams = .{ .cells_per_uv = .{ 8.0, 8.0 }, .occupancy = 0.0 };
            for (0..8) |yy| {
                for (0..8) |xx| {
                    const uv = [2]F{
                        @as(F, @floatFromInt(xx)) / 7.0,
                        @as(F, @floatFromInt(yy)) / 7.0,
                    };
                    try testing.expectEqual(params.background, evalSpeckle2D(uv, params));
                }
            }

            params.occupancy = 1.0;
            var found_speckle = false;
            for (0..16) |yy| {
                for (0..16) |xx| {
                    const uv = [2]F{
                        @as(F, @floatFromInt(xx)) / 15.0,
                        @as(F, @floatFromInt(yy)) / 15.0,
                    };
                    if (evalSpeckle2D(uv, params) < params.background) {
                        found_speckle = true;
                    }
                }
            }
            try testing.expect(found_speckle);
        }

        test "generated speckle list validates before coordinate conversion" {
            const params: Speckle2DParams = .{ .cells_per_uv = .{ std.math.nan(F), 1.0 } };
            try testing.expectError(
                error.InvalidSpeckleCellsPerUV,
                generateSpeckleList2D(testing.allocator, params),
            );
        }

        test "generated speckle list matches hard and soft cell hash evaluation" {
            if (comptime config.evaluator == .mock or speckle_shape == .perlin) return;
            const softnesses: []const F = if (!supports_soft_edges)
                &.{0.0}
            else if (speckle_neighbor_count == 4)
                &.{ 0.0, 0.035, 0.2 }
            else
                &.{ 0.0, 0.035 };
            for (softnesses) |softness| {
                const params: Speckle2DParams = .{
                    .cells_per_uv = .{ 4.25, 3.17 },
                    .occupancy = 0.7,
                    .radius_mean = if (softness == 0.2) 0.8 else 0.45,
                    .edge_softness = softness,
                };
                try testing.expectEqual(softness, speckleSoftness(params));
                const speckles = try generateSpeckleList2D(testing.allocator, params);
                defer deinitTestResources(.{ .list = speckles });
                if (softness == 0.2) {
                    for (speckles.disks) |disk| {
                        for (disk.center) |coordinate| try testing.expectEqual(@floor(coordinate), coordinate);
                    }
                }
                var found_intermediate = false;
                for (0..9) |yy| {
                    for (0..9) |xx| {
                        const uv = [2]F{
                            @as(F, @floatFromInt(xx)) / 8.0,
                            @as(F, @floatFromInt(yy)) / 8.0,
                        };
                        const value = evalSpeckle2D(uv, params);
                        try testing.expectEqual(value, if (softness > 0.0) evalSpeckleList2DNaiveImpl(true, uv[0], uv[1], speckles) else evalSpeckleList2DNaiveImpl(false, uv[0], uv[1], speckles));
                        if (comptime config.evaluator == .cell_hash or config.evaluator == .list_naive) {
                            const prepared = if (softness > 0.0)
                                samplePreparedScal(true, uv[0], uv[1], params, &.{ .list = speckles })
                            else
                                samplePreparedScal(false, uv[0], uv[1], params, &.{ .list = speckles });
                            try testing.expectEqual(value, prepared);
                        }
                        found_intermediate = found_intermediate or (value > 0.0 and value < 1.0);
                    }
                }
                if (speckle_shape == .disk) {
                    try testing.expectEqual(softness > 0.0, found_intermediate);
                }
            }
        }

        test "rounded speckle support excludes omitted cells" {
            if (comptime speckle_neighbor_count == 9 or speckle_shape == .perlin) return;
            const large: i64 = if (F == f32) 65_528 else 35_184_372_088_824;
            const cases = [_]struct { cell: i64, unit: u16, support: F }{
                .{ .cell = 1000, .unit = 65535, .support = 0.3 },
                .{ .cell = large, .unit = 65535, .support = 0.499 },
                .{ .cell = -large, .unit = 0, .support = 0.499 },
                .{ .cell = -1, .unit = 0, .support = std.math.floatMin(F) },
                .{ .cell = 0, .unit = 65535, .support = std.math.floatEps(F) },
                .{ .cell = large, .unit = 0, .support = support_radius_limit },
                .{ .cell = -large, .unit = 65535, .support = support_radius_limit },
            };
            for (cases) |case| {
                const min = if (speckle_neighbor_count == 1) case.support else 0.0;
                const extent = if (speckle_neighbor_count == 1) 1.0 - 2.0 * min else 1.0 - case.support;
                const center = speckleCenter(case.cell, case.unit, min, extent, case.support * case.support);
                const cell: F = @floatFromInt(case.cell);
                const lower_face = cell - @as(F, if (speckle_neighbor_count == 1) 0.0 else 1.0);
                const lower_gap = center.coordinate - std.math.nextAfter(F, lower_face, -std.math.inf(F));
                const upper_gap = cell + 1.0 - center.coordinate;
                try testing.expect(lower_gap * lower_gap >= case.support * case.support);
                try testing.expect(upper_gap * upper_gap >= case.support * case.support);
                try testing.expect(center.unit <= case.unit);
            }
        }

        test "direct fixed generation is contained and exact" {
            if (comptime config.evaluator != .direct_fixed) return;

            const params: Speckle2DParams = .{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 3.25, 1.75 },
                .occupancy = 0.72,
                .radius_mean = 0.38,
                .radius_jitter = 0.0,
                .foreground = 0.15,
                .background = 0.85,
            };
            const first = try generateDirectFixedSpeckle2D(testing.allocator, params);
            defer deinitTestResources(.{ .direct_fixed = first });
            var inactive_params = params;
            inactive_params.occupancy = 0.0;
            const inactive = try generateDirectFixedSpeckle2D(testing.allocator, inactive_params);
            defer deinitTestResources(.{ .direct_fixed = inactive });
            for (inactive.cells) |descriptor| try testing.expectEqual(@as(u64, 0), descriptor);

            try testing.expectEqual(@as(usize, 8), @sizeOf(DirectFixedSpeckleCell2D));
            try testing.expect(first.cell_dims[0] != first.cell_dims[1]);
            try testing.expectEqual(params.radius_mean * params.radius_mean, first.radius2);
            for (first.cells, 0..) |descriptor, index| {
                const xx = index % first.cell_dims[0];
                const yy = index / first.cell_dims[0];
                const cell_x = first.cell_origin[0] + @as(i64, @intCast(xx));
                const cell_y = first.cell_origin[1] + @as(i64, @intCast(yy));
                const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
                const expected_active = randomUnitFromHash(hash, 0) < params.occupancy;
                try testing.expectEqual(expected_active, descriptor != 0);
                if (expected_active) {
                    try testing.expectEqual(
                        (hash & @as(u64, 0x0000_ffff_ffff_0000)) | 1,
                        descriptor,
                    );
                    const extent = 1.0 - 2.0 * params.radius_mean;
                    const center = [2]F{
                        @as(F, @floatFromInt(cell_x)) + params.radius_mean +
                            @as(F, @floatFromInt(@as(u16, @truncate(descriptor >> 16)))) /
                                65_536.0 * extent,
                        @as(F, @floatFromInt(cell_y)) + params.radius_mean +
                            @as(F, @floatFromInt(@as(u16, @truncate(descriptor >> 32)))) /
                                65_536.0 * extent,
                    };
                    try testing.expect(center[0] >=
                        @as(F, @floatFromInt(cell_x)) + params.radius_mean);
                    try testing.expect(center[0] <=
                        @as(F, @floatFromInt(cell_x + 1)) - params.radius_mean);
                    try testing.expect(center[1] >=
                        @as(F, @floatFromInt(cell_y)) + params.radius_mean);
                    try testing.expect(center[1] <=
                        @as(F, @floatFromInt(cell_y + 1)) - params.radius_mean);
                }
            }

            const fixed_points = [_][2]F{
                .{ 0.0, 0.0 },
                .{ 1.0, 1.0 },
                .{ -2.0, 0.41 },
                .{ 3.0, 0.41 },
                .{ 0.37, -4.0 },
                .{ 0.37, 5.0 },
            };
            for (fixed_points) |uv| {
                try testing.expectApproxEqAbs(
                    evalSpeckle2D(uv, params),
                    evalDirectFixedSpeckle2D(uv, first),
                    unit_tol,
                );
            }
            for (0..41) |ii| {
                const uv = [2]F{
                    @as(F, @floatFromInt((ii * 17 + 3) % 43)) / 42.0,
                    @as(F, @floatFromInt((ii * 29 + 7) % 47)) / 46.0,
                };
                try testing.expectApproxEqAbs(
                    evalSpeckle2D(uv, params),
                    evalDirectFixedSpeckle2D(uv, first),
                    unit_tol,
                );
            }
            try testing.expectEqual(
                evalDirectFixedSpeckle2D(.{ 0.0, 1.0 }, first),
                evalDirectFixedSpeckle2D(.{ -2.0, 3.0 }, first),
            );
        }

        test "packed speckle classification helpers round trip" {
            const expected = [_]SpeckleClassificationState{
                .background,
                .foreground,
                .ambiguous,
                .foreground,
                .ambiguous,
                .background,
                .foreground,
                .ambiguous,
            };
            var packed_bytes = [_]u8{0xff} ** 2;
            for (expected, 0..) |state, index| {
                packed_bytes[index / 4] = encodeSpeckleClassificationState(
                    packed_bytes[index / 4],
                    index,
                    state,
                );
            }
            for (expected, 0..) |state, index| {
                try testing.expectEqual(
                    state,
                    decodeSpeckleClassificationState(packed_bytes[index / 4], index),
                );
            }
        }

        fn classifiedStateSamples(classified: ClassifiedIndexedSpeckle2D) ![3][2]F {
            var state_uv: [3][2]F = undefined;
            var found_state = [_]bool{false} ** 3;
            for (0..classified.dims[0] * classified.dims[1]) |index| {
                const state = decodeSpeckleClassificationState(classified.states[index / 4], index);
                try testing.expect(state != .reserve3);
                const state_value = @intFromEnum(state);
                if (!found_state[state_value]) {
                    const x = index % classified.dims[0];
                    const y = index / classified.dims[0];
                    state_uv[state_value] = .{
                        (@as(F, @floatFromInt(x)) + 0.5) / classified.uv_to_cell[0],
                        (@as(F, @floatFromInt(y)) + 0.5) / classified.uv_to_cell[1],
                    };
                    found_state[state_value] = true;
                }
            }
            for (found_state) |found| try testing.expect(found);
            return state_uv;
        }

        fn expectClassifiedSpeckleExact(
            classified: ClassifiedIndexedSpeckle2D,
            uv: [2]F,
        ) !void {
            try testing.expectEqual(
                evalSpeckle2D(uv, classified.speckles.params),
                evalClassifiedIndexedSpeckle2D(uv, classified),
            );
        }

        fn expectClassifiedSpeckleSamples(
            classified: ClassifiedIndexedSpeckle2D,
            grid_strides: [2]usize,
        ) !void {
            const params = classified.speckles.params;
            const fixed_points = [_][2]F{
                .{ 0.0, 0.0 },
                .{ 1.0, 1.0 },
                .{ 0.0, 1.0 },
                .{ 1.0, 0.0 },
                .{ -2.0, 0.37 },
                .{ 3.0, 0.61 },
                .{ -1.0, 2.0 },
            };
            for (fixed_points) |uv| try expectClassifiedSpeckleExact(classified, uv);

            for (0..97) |ii| {
                const uv = [2]F{
                    @as(F, @floatFromInt((ii * 73 + 19) % 257)) / 256.0,
                    @as(F, @floatFromInt((ii * 151 + 43) % 263)) / 262.0,
                };
                try expectClassifiedSpeckleExact(classified, uv);
            }
            for (grid_strides, 0..) |stride, axis| {
                for (0..classified.dims[axis] + 1) |index| {
                    if (index % stride != 0 and index != classified.dims[axis]) continue;
                    var uv = [2]F{ 0.587, 0.413 };
                    uv[axis] = @as(F, @floatFromInt(index)) / classified.uv_to_cell[axis];
                    try expectClassifiedSpeckleExact(classified, uv);
                }
            }

            const adjacent = 8.0 * std.math.floatEps(F);
            if (classified.speckles.recordCount() == 0) return;
            for (0..classified.speckles.cell_dims[0] * classified.speckles.cell_dims[1]) |cell_index| {
                const disk = classified.speckles.record(cell_index * strip_length + 1);
                if (!std.math.isFinite(disk.center[0])) continue;
                const boundary_proc_x = disk.center[0] + disk.radius;
                const boundary_u = boundary_proc_x / params.cells_per_uv[0];
                const center_v = disk.center[1] / params.cells_per_uv[1];
                if (boundary_u >= 0.0 and boundary_u <= 1.0 and
                    center_v >= 0.0 and center_v <= 1.0)
                {
                    for ([_]F{ boundary_u, boundary_u - adjacent, boundary_u + adjacent }) |u| {
                        try expectClassifiedSpeckleExact(classified, .{ u, center_v });
                    }
                }
            }
        }

        fn expectClassifiedSample(resources: *const Resources, uv: [2]F) !void {
            const strip = if ((config.evaluator == .classified_indexed_2 or aligned_classification or (config.evaluator == .classified_indexed_4 or direct_classification))) resources.neighbor_masked.?.speckles else resources.classified.?.speckles;
            const params = strip.params;
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            const expected = if (strip.recordCount() == 0 or !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1])) params.background else evalSpeckle2D(uv, params);
            const K = Kernel(kernelIndex(config));
            try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(K.sampleScal(uv[0], uv[1], params, resources))));
            const values: [S]F = K.sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), params, resources);
            for (values) |value| try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
            if (direct_classification and strip.recordCount() != 0 and std.math.isFinite(uv[0]) and std.math.isFinite(uv[1])) {
                const indexed = evalStripSpeckleList2DImpl(false, uv[0], uv[1], strip);
                try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(indexed)));
            }
            if (config.evaluator == .classified_indexed and strip.recordCount() != 0 and std.math.isFinite(uv[0]) and std.math.isFinite(uv[1])) {
                const actual = if (strip.centers.len != 0) evalNeighborVectorStrip(true, uv[0], uv[1], strip) else evalNeighborVectorStrip(false, uv[0], uv[1], strip);
                try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
            }
        }

        fn expectClassifiedExact(params: Speckle2DParams) !bool {
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            var resources = try generateConfiguredResources(testing.allocator, params);
            defer resources.deinit(testing.allocator);
            const neighbor_masks = (config.evaluator == .classified_indexed_2 or aligned_classification or (config.evaluator == .classified_indexed_4 or direct_classification));
            const classified = if (neighbor_masks) resources.neighbor_masked.? else resources.classified.?;
            const strip = classified.speckles;
            if (neighbor_masks) {
                try expectNeighborMaskCandidates(classified);
            } else {
                const exhaustive = try testing.allocator.alloc(u8, classified.states.len);
                defer testing.allocator.free(exhaustive);
                @memset(exhaustive, 0);
                buildSpeckleClassificationsExhaustive(exhaustive, classified.dims, classified.uv_to_cell, strip);
                try testing.expectEqualSlices(u8, exhaustive, classified.states);
            }
            const bounds = speckleProceduralCellBounds(params, 1).?;
            try testing.expectEqual(bounds.min, strip.cell_origin);
            try testing.expectEqual(bounds.dims, strip.cell_dims);
            if (strip.recordCount() != 0) {
                try testing.expectEqual(3 * bounds.count, strip.recordCount());
                try testing.expectEqual(params.radius_jitter == 0.0, strip.centers.len != 0);
            }
            var has_zero_radius = false;
            for (0..strip.recordCount()) |index| {
                const cell_index = index / 3;
                const owner_x = strip.cell_origin[0] + @as(i64, @intCast(cell_index % strip.cell_dims[0]));
                const owner_y = strip.cell_origin[1] + @as(i64, @intCast(cell_index / strip.cell_dims[0])) + @as(i64, @intCast(index % 3)) - 1;
                const record = strip.record(index);
                if (speckleDiskForCell(false, owner_x, owner_y, params)) |expected| {
                    try testing.expectEqualSlices(u8, std.mem.asBytes(&expected), std.mem.asBytes(&record));
                    try testing.expect(record.radius * record.radius <= strip.max_outer_radius2);
                    for (record.center, [2]i64{ owner_x, owner_y }) |coordinate, owner| {
                        try testing.expect(coordinate >= @as(F, @floatFromInt(owner)) and coordinate <= @as(F, @floatFromInt(owner + 1)));
                    }
                } else {
                    try testing.expectEqual(std.math.inf(F), record.center[0]);
                    try testing.expectEqual(@as(Bits, 0), @as(Bits, @bitCast(record.center[1])));
                    try testing.expectEqual(@as(Bits, @bitCast(params.radius_mean)), @as(Bits, @bitCast(record.radius)));
                }
                if (index % 3 != 1 or !std.math.isFinite(record.center[0])) continue;
                has_zero_radius = has_zero_radius or record.radius == 0.0;
                var uv: [2]F = undefined;
                for (0..2) |axis| uv[axis] = record.center[axis] / params.cells_per_uv[axis];
                try expectClassifiedSample(&resources, uv);
                // Cartesian nextAfter samples cross both procedural faces at once.
                const face_u = @as(F, @floatFromInt(owner_x)) / params.cells_per_uv[0];
                const face_v = @as(F, @floatFromInt(owner_y)) / params.cells_per_uv[1];
                for ([_]F{ face_u, std.math.nextAfter(F, face_u, -std.math.inf(F)), std.math.nextAfter(F, face_u, std.math.inf(F)) }) |u| {
                    for ([_]F{ face_v, std.math.nextAfter(F, face_v, -std.math.inf(F)), std.math.nextAfter(F, face_v, std.math.inf(F)) }) |v| {
                        try expectClassifiedSample(&resources, .{ u, v });
                    }
                }
                for (0..2) |axis| {
                    for ([_]F{ -record.radius, record.radius }) |edge| {
                        const boundary = (record.center[axis] + edge) / params.cells_per_uv[axis];
                        for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |point| {
                            var sample = uv;
                            sample[axis] = point;
                            try expectClassifiedSample(&resources, sample);
                        }
                    }
                }
            }
            for (0..97) |ii| try expectClassifiedSample(&resources, .{
                @as(F, @floatFromInt((ii * 73 + 19) % 257)) / 240.0 - 0.03,
                @as(F, @floatFromInt((ii * 151 + 43) % 263)) / 245.0 - 0.03,
            });
            for (0..2) |axis| {
                for (0..classified.dims[axis] + 1) |index| {
                    const boundary = if (aligned_classification)
                        speckleClassificationAxes(classified.dims, classified.uv_to_cell, params)[axis].boundary(index) / params.cells_per_uv[axis]
                    else
                        @as(F, @floatFromInt(index)) / classified.uv_to_cell[axis];
                    for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |point| {
                        var uv = [2]F{ 0.587, 0.413 };
                        uv[axis] = point;
                        try expectClassifiedSample(&resources, uv);
                    }
                }
            }
            for (0..2) |axis| {
                const face = 1.0 / params.cells_per_uv[axis];
                for ([_]F{ face, std.math.nextAfter(F, face, -std.math.inf(F)), std.math.nextAfter(F, face, std.math.inf(F)) }) |point| {
                    var uv = [2]F{ 0.5, 0.5 };
                    uv[axis] = point;
                    try expectClassifiedSample(&resources, uv);
                }
            }
            const K = Kernel(kernelIndex(config));
            for (0..8) |batch| {
                var us: [S]F = undefined;
                var vs: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    us[lane] = @as(F, @floatFromInt((batch * S + lane) % 17)) / 16.0;
                    vs[lane] = if (batch == 0 and lane % 2 == 0) std.math.nan(F) else if (batch == 1 and lane % 2 == 0) std.math.inf(F) else if (batch == 2 and lane % 2 == 0) -std.math.inf(F) else 1.0 - us[lane];
                    active[lane] = (batch + lane) % 3 != 0;
                }
                const actual: [S]F = K.sampleSIMD(us, vs, active, params, &resources);
                for (0..S) |lane| {
                    const expected = if (strip.recordCount() != 0 and active[lane] and std.math.isFinite(vs[lane])) evalSpeckle2D(.{ us[lane], vs[lane] }, params) else params.background;
                    try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
                }
            }
            return has_zero_radius;
        }

        test "neighbor vector hard strip covers all nine lanes strict edges and tiny radii" {
            if (comptime config.evaluator != .classified_indexed) return;
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            var centers: [27][2]F = undefined;
            var disks: [27]SpeckleDisk2D = undefined;
            inline for (.{ false, true }) |fixed_radius| {
                var strip: StripSpeckleList2D = .{
                    .params = .{ .cells_per_uv = .{ 0.5, 0.5 }, .radius_mean = 1.0, .foreground = -0.0, .background = 0.23 },
                    .centers = if (fixed_radius) &centers else &.{},
                    .disks = if (fixed_radius) &.{} else &disks,
                    .cell_origin = .{ -1, -1 },
                    .cell_dims = .{ 3, 3 },
                    .outer2 = 1.0,
                    .max_outer_radius2 = 1.0,
                };
                for (0..9) |lane| {
                    @memset(&centers, .{ std.math.inf(F), 0.0 });
                    @memset(&disks, .{ .center = .{ std.math.inf(F), 0.0 }, .radius = 1.0 });
                    const center: [2]F = .{ @as(F, @floatFromInt(lane / 3)) * 0.5, @as(F, @floatFromInt(lane % 3)) * 0.5 };
                    centers[9 + lane] = center;
                    disks[9 + lane] = .{ .center = center, .radius = 1.0 };
                    const actual = evalNeighborVectorStrip(fixed_radius, 1.0, 1.0, strip);
                    try testing.expectEqual(@as(Bits, 0), @as(Bits, @bitCast(actual)));
                    try testing.expectEqual(@as(Bits, @bitCast(evalStripSpeckleList2DSpecialized(false, fixed_radius, 1.0, 1.0, strip))), @as(Bits, @bitCast(actual)));
                }
                for ([_]F{ 0.0, std.math.floatMin(F), std.math.floatEps(F), 0.125 }) |radius| {
                    @memset(&centers, .{ std.math.inf(F), 0.0 });
                    @memset(&disks, .{ .center = .{ std.math.inf(F), 0.0 }, .radius = 0.0 });
                    centers[13] = .{ 0.25, 0.25 };
                    disks[13] = .{ .center = centers[13], .radius = radius };
                    strip.params.radius_mean = if (fixed_radius) @max(radius, std.math.floatMin(F)) else 0.5;
                    strip.params.radius_jitter = if (fixed_radius) 0.0 else 0.5;
                    strip.outer2 = strip.params.radius_mean * strip.params.radius_mean;
                    strip.max_outer_radius2 = if (fixed_radius) strip.outer2 else 1.0;
                    const edge = (0.25 + radius) / 0.5;
                    for ([_]F{ 0.5, edge, std.math.nextAfter(F, edge, -std.math.inf(F)), std.math.nextAfter(F, edge, std.math.inf(F)) }) |u| {
                        const expected = evalStripSpeckleList2DSpecialized(false, fixed_radius, u, 0.5, strip);
                        const actual = evalNeighborVectorStrip(fixed_radius, u, 0.5, strip);
                        try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
                        if (radius * radius == 0.0) try testing.expectEqual(@as(Bits, @bitCast(strip.params.background)), @as(Bits, @bitCast(actual)));
                    }
                }
            }
        }

        test "classified evaluators preserve independent states and bitwise samples" {
            if (comptime config.evaluator != .classified_indexed and config.evaluator != .classified_indexed_2 and !aligned_classification and config.evaluator != .classified_indexed_4 and !direct_classification) return;
            const densities = [_][2]F{ .{ 3.25, 2.75 }, .{ 0.25, 0.75 }, .{ 2.17, 1.31 } };
            var has_zero_radius = false;
            for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
                for ([_]F{ 0.0, 0.08, 0.5 }) |jitter| {
                    for (densities) |density| {
                        has_zero_radius = try expectClassifiedExact(.{
                            .seed = 43498,
                            .cells_per_uv = density,
                            .occupancy = occupancy,
                            .radius_mean = 0.5,
                            .radius_jitter = jitter,
                            .foreground = 0.17,
                            .background = 0.83,
                        }) or has_zero_radius;
                    }
                }
            }
            try testing.expect(has_zero_radius);
            for ([_]F{ 0.0, 0.08 }) |jitter| {
                _ = try expectClassifiedExact(.{
                    .seed = 0,
                    .cells_per_uv = .{ 0.03125, 0.0625 },
                    .occupancy = 0.001,
                    .radius_mean = 0.35,
                    .radius_jitter = jitter,
                });
            }
            for ([_]F{ 0.0, 0.08 }) |jitter| {
                for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
                    for ([_][2]F{ .{ 0.0, -0.0 }, .{ 0.91, -0.0 }, .{ -0.0, 0.0 }, .{ 0.23, 0.23 } }) |colors| {
                        _ = try expectClassifiedExact(.{
                            .cells_per_uv = .{ 2.25, 1.75 },
                            .occupancy = occupancy,
                            .radius_mean = 0.35,
                            .radius_jitter = jitter,
                            .foreground = colors[0],
                            .background = colors[1],
                        });
                    }
                }
            }
            for ([_]F{ std.math.floatMin(F), std.math.floatEps(F), 1.0 - std.math.floatEps(F), 1.0 }) |radius| {
                _ = try expectClassifiedExact(.{
                    .cells_per_uv = .{ 0.03125, 0.0625 },
                    .occupancy = 1.0,
                    .radius_mean = radius,
                    .radius_jitter = -0.0,
                    .foreground = -0.0,
                    .background = 0.23,
                });
            }
            for ([_]usize{ speckle_classification_boundary_cache_capacity - 8, speckle_classification_boundary_cache_capacity + 1 }) |interval_count| {
                _ = try expectClassifiedExact(.{
                    .cells_per_uv = .{ @as(F, @floatFromInt(interval_count)) / speckle_mask_samples_per_cell, 0.5 / speckle_mask_samples_per_cell },
                    .occupancy = 0.7,
                    .radius_mean = 0.92,
                    .radius_jitter = 0.08,
                });
            }
        }

        test "speckle classification bounds contain rounded UV lookups" {
            if (comptime config.evaluator != .classified_indexed and config.evaluator != .classified_indexed_2 and !aligned_classification and config.evaluator != .classified_indexed_4 and !direct_classification) return;

            const cases = [_]Speckle2DParams{
                .{ .cells_per_uv = .{ 192.0, 160.0 } },
                .{ .cells_per_uv = .{ 3.25, 2.5 } },
                .{ .cells_per_uv = .{ 0.03125, 0.0625 } },
            };
            for (cases) |params| {
                try params.validateResolved(config);
                const dims = classifiedDims(params) orelse return error.TestUnexpectedResult;
                const uv_to_cell = [2]F{ @floatFromInt(dims[0]), @floatFromInt(dims[1]) };
                const axes = speckleClassificationAxes(dims, uv_to_cell, params);
                for (axes) |axis| {
                    for (0..axis.dim + 1) |ii| {
                        const uv = if (aligned_classification) axis.boundary(ii) / axis.cells_per_uv else @as(F, @floatFromInt(ii)) / axis.uv_to_cell;
                        const below = std.math.nextAfter(F, uv, -std.math.inf(F));
                        const above = std.math.nextAfter(F, uv, std.math.inf(F));
                        const samples = [_]F{
                            std.math.nextAfter(F, below, -std.math.inf(F)),
                            below,
                            uv,
                            above,
                            std.math.nextAfter(F, above, std.math.inf(F)),
                        };
                        for (samples) |sample| {
                            const bounded_uv = @max(0.0, @min(1.0, sample));
                            const cell: usize = @intFromFloat(classificationCoordinate(sample, axis.cells_per_uv, axis.uv_to_cell, axis.dim));
                            const proc = bounded_uv * axis.cells_per_uv;
                            if (aligned_classification) try testing.expectEqual(@as(usize, @intFromFloat(@floor(proc))), cell / buildconfig.speckle_mask_samples_per_cell);
                            try testing.expect(proc >= axis.lowerBound(cell));
                            try testing.expect(proc <= axis.upperBound(cell + 1));
                        }
                    }
                }
            }
        }

        test "classified indexed speckle is exact on boundaries and varied points" {
            if (comptime config.evaluator != .classified_indexed) return;

            const params: Speckle2DParams = .{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 5.25, 4.4 },
                .occupancy = 0.72,
                .radius_mean = 0.2,
                .radius_jitter = 0.07,
                .foreground = 0.17,
                .background = 0.83,
            };
            const classified = try generateClassifiedSpeckle2D(ClassifiedIndexedSpeckle2D, testing.allocator, params);
            defer deinitTestResources(.{ .classified = classified });

            _ = try classifiedStateSamples(classified);

            try expectClassifiedSpeckleSamples(classified, .{ 7, 5 });

            var cell_x: i64 = 0;
            const cell_x_end = @as(i64, @intFromFloat(@floor(params.cells_per_uv[0])));
            while (cell_x <= cell_x_end) : (cell_x += 1) {
                const u = @as(F, @floatFromInt(cell_x)) / params.cells_per_uv[0];
                try expectClassifiedSpeckleExact(classified, .{ u, 0.319 });
            }
            var cell_y: i64 = 0;
            const cell_y_end = @as(i64, @intFromFloat(@floor(params.cells_per_uv[1])));
            while (cell_y <= cell_y_end) : (cell_y += 1) {
                const v = @as(F, @floatFromInt(cell_y)) / params.cells_per_uv[1];
                try expectClassifiedSpeckleExact(classified, .{ 0.681, v });
            }
        }

        test "procedural speckle equal-colour fast path is exact" {
            if (comptime config.evaluator == .mock) return;
            const params: Speckle2DParams = .{ .foreground = 0.375, .background = 0.375 };
            try testing.expectEqual(params.background, evalSpeckle2D(.{ 0.37, 0.61 }, params));
        }

        fn speckleMaskTestParams() Speckle2DParams {
            return .{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 3.25, 2.5 },
                .occupancy = 0.72,
                .radius_mean = 0.38,
                .radius_jitter = 0.07,
                .edge_softness = if (speckle_shape == .disk and
                    config.evaluator == .mask_u8) 0.035 else 0.0,
                .foreground = 0.15,
                .background = 0.85,
            };
        }

        test "Perlin mask is varied seed-sensitive bounded and balanced" {
            if (comptime config.evaluator == .mock or speckle_shape != .perlin) return;

            var params = Speckle2DParams{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 7.25, 5.5 },
                .occupancy = -1.0,
                .radius_mean = -1.0,
                .radius_jitter = -1.0,
                .foreground = 0.15,
                .background = 0.85,
            };

            const first = try generateSpeckleMask2D(testing.allocator, params);
            defer deinitTestResources(.{ .mask = first });

            params.seed +%= 1;
            const changed = try generateSpeckleMask2D(testing.allocator, params);
            defer deinitTestResources(.{ .mask = changed });
            try testing.expect(!std.mem.eql(u8, first.bits, changed.bits));

            var min_value: u8 = std.math.maxInt(u8);
            var max_value: u8 = 0;
            var has_intermediate = false;
            var sum: u64 = 0;
            for (first.bits) |value| {
                min_value = @min(min_value, value);
                max_value = @max(max_value, value);
                has_intermediate = has_intermediate or (value > 0 and value < 255);
                sum += value;
            }
            const mean_coverage = @as(F, @floatFromInt(sum)) /
                (@as(F, @floatFromInt(first.bits.len)) * 255.0);
            try testing.expect(min_value < 32 and max_value > 223);
            try testing.expect(has_intermediate);
            try testing.expect(mean_coverage > 0.3 and mean_coverage < 0.7);

            for ([_][2]F{ .{ 0.0, 0.0 }, .{ 0.37, 0.61 }, .{ 1.0, 1.0 } }) |uv| {
                const value = evalSpeckleMask2D(uv, first);
                try testing.expect(value >= @min(params.foreground, params.background));
                try testing.expect(value <= @max(params.foreground, params.background));
            }
            try testing.expectEqual(
                evalSpeckleMask2D(.{ 0.0, 1.0 }, first),
                evalSpeckleMask2D(.{ -2.0, 3.0 }, first),
            );

            var endpoint_params = params;
            endpoint_params.cells_per_uv = .{ 1.0 - std.math.floatEps(F), 1.0 };
            const endpoint = try generateSpeckleMask2D(testing.allocator, endpoint_params);
            defer deinitTestResources(.{ .mask = endpoint });
            try testing.expect(std.math.isFinite(evalSpeckleMask2D(.{ 1.0, 1.0 }, endpoint)));
        }

        test "direct 1-bit speckle mask preserves list-derived bytes and lattice values" {
            if (comptime config.evaluator != .mask_1bit) return;

            const params = speckleMaskTestParams();
            const speckles = try generateSpeckleList2D(testing.allocator, params);
            defer deinitTestResources(.{ .list = speckles });

            var mask_storage: [1200]u8 = undefined;
            var fixed = std.heap.FixedBufferAllocator.init(&mask_storage);
            const mask = try generateSpeckleMask2D(fixed.allocator(), params);
            const expected_byte_count = mask.row_stride * mask.dims[1];
            try testing.expectEqual(expected_byte_count, mask.bits.len);
            if (comptime buildconfig.speckle_mask_samples_per_cell == 12) {
                try testing.expectEqual(@as(usize, 155), mask.bits.len);
            }

            const list_bits = try testing.allocator.alloc(u8, mask.bits.len);
            defer testing.allocator.free(list_bits);
            @memset(list_bits, 0);
            for (speckles.disks) |disk| {
                rasterizeSpeckleMaskDisk(
                    false,
                    list_bits,
                    mask.row_stride,
                    mask.uv_to_texel,
                    params,
                    disk,
                );
            }
            try testing.expectEqualSlices(u8, list_bits, mask.bits);

            var found_foreground = false;
            var found_background = false;
            for (0..mask.dims[1]) |yy| {
                for (0..mask.dims[0]) |xx| {
                    const uv = [2]F{
                        @as(F, @floatFromInt(xx)) / mask.uv_to_texel[0],
                        @as(F, @floatFromInt(yy)) / mask.uv_to_texel[1],
                    };
                    const value = evalSpeckleMask2D(uv, mask);
                    try testing.expectApproxEqAbs(
                        evalSpeckleList2DNaiveImpl(false, uv[0], uv[1], speckles),
                        value,
                        unit_tol,
                    );
                    found_foreground = found_foreground or value == mask.params.foreground;
                    found_background = found_background or value == mask.params.background;
                }
            }
            try testing.expect(found_foreground and found_background);
        }

        test "speckle mask handles degenerate and oversized inputs" {
            if (comptime config.evaluator != .mask_1bit and
                config.evaluator != .mask_u8) return;

            for ([_]bool{ false, true }) |equal_colour| {
                if (!equal_colour and speckle_shape == .perlin) continue;
                var params = speckleMaskTestParams();
                params.occupancy = if (equal_colour) 1.0 else 0.0;
                if (equal_colour) params.foreground = params.background;
                const mask = try generateSpeckleMask2D(testing.allocator, params);
                defer deinitTestResources(.{ .mask = mask });
                try testing.expectEqual(@as(usize, 0), mask.bits.len);
                try testing.expectEqual(params.background, evalSpeckleMask2D(.{ 0.37, 0.61 }, mask));
            }

            var params = speckleMaskTestParams();
            const sizes: []const F = if (config.evaluator == .mask_u8) &.{ 3000.0, 4000.0 } else &.{4000.0};
            for (sizes) |cells| {
                params.cells_per_uv = .{ cells, cells };
                try testing.expectError(
                    error.SpeckleMaskTooLarge,
                    generateSpeckleMask2D(testing.allocator, params),
                );
            }
        }

        test "speckle mask clamps UV endpoints" {
            if (comptime config.evaluator != .mask_1bit and
                config.evaluator != .mask_u8) return;

            const mask = try generateSpeckleMask2D(testing.allocator, speckleMaskTestParams());
            defer deinitTestResources(.{ .mask = mask });

            try testing.expectEqual(
                evalSpeckleMask2D(.{ 0.0, 1.0 }, mask),
                evalSpeckleMask2D(.{ -2.0, 3.0 }, mask),
            );
            try testing.expectEqual(
                evalSpeckleMask2D(.{ 1.0, 0.0 }, mask),
                evalSpeckleMask2D(.{ 3.0, -2.0 }, mask),
            );
            try testing.expectEqual(
                mask.params.background,
                evalSpeckleMask2D(.{ std.math.nan(F), 0.5 }, mask),
            );
            try testing.expectEqual(
                mask.params.background,
                evalSpeckleMask2D(.{ 0.5, std.math.inf(F) }, mask),
            );
        }

        test "u8 speckle mask agrees with quantized indexed lattice evaluation" {
            if (comptime config.evaluator != .mask_u8) return;

            const params = speckleMaskTestParams();
            const speckles = try generateSpeckleList2D(testing.allocator, params);
            defer deinitTestResources(.{ .list = speckles });
            const mask = try generateSpeckleMask2D(testing.allocator, params);
            defer deinitTestResources(.{ .mask = mask });

            try testing.expectEqual(@as(u8, 0), quantizeSpeckleCoverage(-1.0));
            try testing.expectEqual(@as(u8, 0), quantizeSpeckleCoverage(0.0));
            try testing.expectEqual(@as(u8, 1), quantizeSpeckleCoverage(1.0 / 255.0));
            try testing.expectEqual(@as(u8, 128), quantizeSpeckleCoverage(0.5));
            try testing.expectEqual(@as(u8, 254), quantizeSpeckleCoverage(254.0 / 255.0));
            try testing.expectEqual(@as(u8, 255), quantizeSpeckleCoverage(1.0));
            try testing.expectEqual(@as(u8, 255), quantizeSpeckleCoverage(2.0));
            try testing.expectEqual(mask.dims[0], mask.row_stride);
            try testing.expectEqual(mask.dims[0] * mask.dims[1], mask.bits.len);
            var found_intermediate = false;
            for (0..mask.dims[1]) |yy| {
                for (0..mask.dims[0]) |xx| {
                    const uv = [2]F{
                        @as(F, @floatFromInt(xx)) / mask.uv_to_texel[0],
                        @as(F, @floatFromInt(yy)) / mask.uv_to_texel[1],
                    };
                    const analytic = if (comptime speckle_shape == .perlin)
                        evalPerlinSpeckle2D(uv, params)
                    else if (speckleSoftness(params) > 0.0)
                        evalSpeckleList2DNaiveImpl(true, uv[0], uv[1], speckles)
                    else
                        evalSpeckleList2DNaiveImpl(false, uv[0], uv[1], speckles);
                    const analytic_coverage = (analytic - params.background) /
                        (params.foreground - params.background);
                    const expected_byte = quantizeSpeckleCoverage(analytic_coverage);
                    const actual_byte = mask.bits[yy * mask.row_stride + xx];
                    const byte_diff = if (actual_byte > expected_byte)
                        actual_byte - expected_byte
                    else
                        expected_byte - actual_byte;
                    try testing.expect(byte_diff <= 1);

                    const coverage = @as(F, @floatFromInt(actual_byte)) / 255.0;
                    const expected = params.background +
                        coverage * (params.foreground - params.background);
                    try testing.expectEqual(expected, evalSpeckleMask2D(uv, mask));
                    found_intermediate = found_intermediate or
                        (actual_byte != 0 and actual_byte != 255);
                }
            }
            if (speckle_shape == .gaussian or params.edge_softness > 0.0) {
                try testing.expect(found_intermediate);
            }
        }

        const SpeckleSIMDCase = struct {
            uv: [2]F,
            active: bool = true,
            expected: ?F = null,
        };

        fn expectPreparedSpeckleSIMD(
            params: Speckle2DParams,
            resources: *const Resources,
            cases: []const SpeckleSIMDCase,
        ) !void {
            for (0..(cases.len + S - 1) / S) |batch| {
                var coord_0: [S]F = undefined;
                var coord_1: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    const case = cases[(batch * S + lane) % cases.len];
                    coord_0[lane] = case.uv[0];
                    coord_1[lane] = case.uv[1];
                    active[lane] = case.active;
                }
                const actual: [S]F = samplePreparedSIMD(false, coord_0, coord_1, active, params, resources);
                for (0..S) |lane| {
                    const case = cases[(batch * S + lane) % cases.len];
                    const expected = if (case.active)
                        samplePreparedScal(false, case.uv[0], case.uv[1], params, resources)
                    else
                        params.background;
                    if (case.expected) |value| try testing.expectEqual(value, expected);
                    try testing.expectEqual(expected, actual[lane]);
                }
            }
        }

        fn expectPreparedSpeckleSIMDBackground(
            params: Speckle2DParams,
            resources: *const Resources,
        ) !void {
            try expectPreparedSpeckleSIMD(params, resources, &.{
                .{ .uv = .{ std.math.nan(F), 0.0 }, .expected = params.background },
                .{ .uv = .{ 0.0, std.math.inf(F) }, .expected = params.background },
            });
            try expectPreparedSpeckleSIMD(params, resources, &.{
                .{ .uv = .{ 0.0, 0.0 }, .active = false },
            });
        }

        test "direct fixed prepared SIMD handles active inactive and nonfinite lanes" {
            if (comptime config.evaluator != .direct_fixed) return;

            const cells = [_]DirectFixedSpeckleCell2D{
                0x0000_8000_8000_0001,
                0,
                0,
                0,
                0,
                0,
            };
            const params: Speckle2DParams = .{
                .cells_per_uv = .{ 2.0, 1.0 },
                .occupancy = 0.5,
                .radius_mean = 0.25,
                .foreground = 0.2,
                .background = 0.8,
            };
            const direct: DirectFixedSpeckle2D = .{
                .params = params,
                .cells = &cells,
                .cell_origin = .{ 0, 0 },
                .cell_dims = .{ 3, 2 },
                .radius2 = 0.25 * 0.25,
            };
            const resources: Resources = .{ .direct_fixed = direct };
            try expectPreparedSpeckleSIMD(params, &resources, &.{
                .{ .uv = .{ 0.25, 0.5 }, .expected = params.foreground },
                .{ .uv = .{ 0.375, 0.5 }, .expected = params.background },
                .{ .uv = .{ 0.1, 0.5 }, .expected = params.background },
                .{ .uv = .{ 0.75, 0.5 }, .expected = params.background },
                .{ .uv = .{ std.math.nan(F), std.math.inf(F) }, .expected = params.background },
                .{ .uv = .{ 0.25, 0.5 }, .active = false },
            });
        }

        test "classified indexed prepared SIMD matches scalar for every state" {
            if (comptime config.evaluator != .classified_indexed) return;

            const params: Speckle2DParams = .{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 5.25, 4.4 },
                .occupancy = 1.0,
                .radius_mean = 0.2,
                .radius_jitter = 0.0,
                .foreground = 0.17,
                .background = 0.83,
            };
            const classified = try generateClassifiedSpeckle2D(ClassifiedIndexedSpeckle2D, testing.allocator, params);
            defer deinitTestResources(.{ .classified = classified });

            const state_uv = try classifiedStateSamples(classified);

            const resources: Resources = .{ .classified = classified };
            try expectPreparedSpeckleSIMD(params, &resources, &.{
                .{ .uv = state_uv[0] },
                .{ .uv = state_uv[1] },
                .{ .uv = state_uv[2] },
                .{ .uv = state_uv[1], .active = false },
                .{ .uv = .{ std.math.nan(F), std.math.inf(F) } },
            });
        }

        test "1-bit speckle mask SIMD matches scalar and backgrounds invalid lanes" {
            if (comptime config.evaluator != .mask_1bit) return;

            const bits = [_]u8{ 0b10000011, 0b00000001, 0b01010101, 0b00000000 };
            const params: Speckle2DParams = .{
                .foreground = 0.75,
                .background = 0.25,
            };
            const mask: SpeckleMask2D = .{
                .bits = &bits,
                .dims = .{ 9, 2 },
                .row_stride = 2,
                .uv_to_texel = .{ 8.0, 1.0 },
                .params = params,
            };
            const resources: Resources = .{ .mask = mask };
            try expectPreparedSpeckleSIMD(params, &resources, &.{
                .{ .uv = .{ -2.0, 0.0 } },
                .{ .uv = .{ 0.0, 1.0 } },
                .{ .uv = .{ 0.0624, 0.0 } },
                .{ .uv = .{ 0.0625, 1.0 } },
                .{ .uv = .{ 0.99, 0.0 } },
                .{ .uv = .{ 1.0, 1.0 } },
                .{ .uv = .{ 3.0, 0.0 } },
                .{ .uv = .{ 0.5, 1.0 } },
            });
            try expectPreparedSpeckleSIMDBackground(params, &resources);
        }

        test "u8 speckle mask SIMD matches scalar for active finite lanes" {
            if (comptime config.evaluator != .mask_u8) return;

            const bits = [_]u8{ 0, 64, 128, 255 };
            const params: Speckle2DParams = .{
                .foreground = 0.8,
                .background = 0.2,
            };
            const mask: SpeckleMask2D = .{
                .bits = &bits,
                .dims = .{ 2, 2 },
                .row_stride = 2,
                .uv_to_texel = .{ 1.0, 1.0 },
                .params = params,
            };
            const resources: Resources = .{ .mask = mask };
            var cases = [_]SpeckleSIMDCase{
                .{ .uv = .{ -1.0, 0.0 } },
                .{ .uv = .{ 1.0, 0.0 } },
                .{ .uv = .{ 0.0, 1.0 } },
                .{ .uv = .{ 1.0, 1.0 } },
            };
            for ([_]bool{ false, true }) |all_active| {
                for (&cases, 0..) |*case, index| case.active = all_active or index & 1 == 0;
                try expectPreparedSpeckleSIMD(params, &resources, &cases);
            }

            var no_gather_mask = mask;
            no_gather_mask.bits = &.{};
            const no_gather: Resources = .{ .mask = no_gather_mask };
            try expectPreparedSpeckleSIMDBackground(params, &no_gather);
        }

        test "speckle resources prepare sample open boundaries and release owned allocations" {
            if (comptime config.evaluator == .mock) return;
            const single = speckle_neighbor_count == 1;
            const params: Speckle2DParams = .{
                .seed = 6,
                .cells_per_uv = if (single) .{ 1.0, 1.0 } else .{ 2.0, 1.0 },
                .occupancy = if (speckle_shape == .perlin) 0.0 else if (single) 1.0 else 0.1,
                .radius_mean = if (single) 0.5 else 1.0,
                .foreground = 0.25,
                .background = 0.75,
            };
            var resources = try generateConfiguredResources(testing.allocator, params);
            defer resources.deinit(testing.allocator);
            if (comptime speckle_shape == .perlin) {
                try testing.expectEqual(@as(F, 1.0), resources.mask.?.params.occupancy);
            }
            var fallback_params = params;
            if (comptime config.evaluator != .cell_hash) {
                fallback_params.foreground = 0.95;
                fallback_params.background = 0.05;
                fallback_params.occupancy = 0.0;
            }
            const points = [_][2]F{
                .{ 0.5, 0.5 }, .{ 0.0, 0.5 }, .{ 1.0, 0.5 }, .{ 0.5, 0.0 }, .{ 0.5, 1.0 },
            };
            for (points, 0..) |uv, index| {
                // One-neighbor disks touch all four cell edges; seed 6 leaves cell (1, 0)
                // inactive, exposing the four-neighbor disk at (0, 0)'s circumference.
                const expected = if (speckle_shape == .disk and single)
                    (if (index == 0) params.foreground else params.background)
                else if (speckle_shape == .disk and speckle_neighbor_count == 4 and index == 3)
                    params.background
                else switch (comptime config.evaluator) {
                    .mock => unreachable,
                    .cell_hash => evalSpeckle2D(uv, params),
                    .list_naive => evalSpeckleList2DNaiveImpl(config.soft_edges, uv[0], uv[1], resources.list.?),
                    .list_indexed => evalStripSpeckleList2DImpl(config.soft_edges, uv[0], uv[1], resources.strip_list.?),
                    .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8 => evalClassifiedIndexedSpeckle2D(uv, resources.neighbor_masked.?),
                    .classified_indexed => evalClassifiedIndexedSpeckle2D(
                        uv,
                        resources.classified.?,
                    ),
                    .direct_fixed => evalDirectFixedSpeckle2D(uv, resources.direct_fixed.?),
                    .mask_1bit, .mask_u8 => evalSpeckleMask2D(uv, resources.mask.?),
                };
                try testing.expectEqual(expected, samplePreparedScal(false, uv[0], uv[1], fallback_params, &resources));
                const actual: [S]F = samplePreparedSIMD(
                    false,
                    @splat(uv[0]),
                    @splat(uv[1]),
                    @splat(true),
                    fallback_params,
                    &resources,
                );
                for (actual) |value| try testing.expectEqual(expected, value);
            }
            resources.deinit(testing.allocator);
            try testing.expect(resources.list == null and resources.strip_list == null and resources.classified == null and
                resources.direct_fixed == null and resources.mask == null);
        }
    };
}

// --------------------------------------------------------------------------------------
// Runtime policy and retained specialized numerical regressions
// --------------------------------------------------------------------------------------

// Comptime discovery keeps individual regression names available to --test-filter.
comptime {
    if (@import("builtin").is_test) {
        for (generation_configs) |config| std.testing.refAllDecls(Implementation(config));
    }
}

test "runtime override policy and invalid settings fail before allocation" {
    const bad_softness: Speckle2DParams = .{ .edge_softness = std.math.nan(F) };
    try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, generateResources(std.testing.failing_allocator, bad_softness));
    for ([_]speckleconfig.Pattern{ .gaussian, .perlin }) |pattern| {
        try std.testing.expectError(error.SpeckleEdgeSoftnessRequiresDisk, generateResources(std.testing.failing_allocator, .{ .pattern = pattern, .edge_softness = 0.1 }));
    }
    if (comptime !buildconfig.enable_all_evaluators) {
        for (std.enums.values(speckleconfig.Evaluator)) |evaluator| {
            try std.testing.expectError(error.SpeckleOverridesDisabled, generateResources(std.testing.failing_allocator, .{ .evaluator = evaluator }));
        }
        for ([_]u8{ 0, 1, 4, 9, 255 }) |neighbors| {
            try std.testing.expectError(error.SpeckleOverridesDisabled, generateResources(std.testing.failing_allocator, .{ .neighbor_count = neighbors }));
        }
    } else {
        const cases = [_]struct { params: Speckle2DParams, err: anyerror }{
            .{ .params = .{ .neighbor_count = 2 }, .err = error.InvalidSpeckleNeighborCount },
            .{ .params = .{ .pattern = .perlin, .neighbor_count = 9 }, .err = error.SpecklePerlinDoesNotUseNeighbors },
            .{ .params = .{ .pattern = .perlin, .evaluator = .cell_hash }, .err = error.PerlinRequiresMaskU8 },
            .{ .params = .{ .pattern = .gaussian, .evaluator = .mask_1bit }, .err = error.Mask1BitRequiresDisk },
            .{ .params = .{ .evaluator = .classified_indexed, .neighbor_count = 4 }, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
            .{ .params = .{ .evaluator = .classified_indexed, .neighbor_count = 4 }, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
            .{ .params = .{ .evaluator = .classified_indexed, .pattern = .gaussian }, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
            .{ .params = .{ .evaluator = .classified_indexed, .edge_softness = 0.01 }, .err = error.SpeckleEvaluatorRequiresHardEdges },
            .{ .params = .{ .evaluator = .classified_indexed, .radius_mean = 0.95, .radius_jitter = 0.08 }, .err = error.InvalidSpeckleNeighborhoodRadius },
            .{ .params = .{ .evaluator = .direct_fixed, .neighbor_count = 9 }, .err = error.DirectFixedRequiresDiskAndOneNeighbor },
            .{ .params = .{ .evaluator = .classified_indexed, .edge_softness = 0.01 }, .err = error.SpeckleEvaluatorRequiresHardEdges },
            .{ .params = .{ .evaluator = .direct_fixed, .radius_jitter = 0.01 }, .err = error.InvalidDirectFixedSpeckleRadiusJitter },
            .{ .params = .{ .evaluator = .direct_fixed, .radius_mean = 0.6 }, .err = error.InvalidDirectFixedSpeckleRadius },
            .{ .params = .{ .neighbor_count = 1, .radius_jitter = 0.1 }, .err = error.InvalidSpeckleNeighborhoodRadius },
        };
        for (cases) |case| try std.testing.expectError(case.err, generateResources(std.testing.failing_allocator, case.params));
        const direct = try (Speckle2DParams{ .evaluator = .direct_fixed }).resolve();
        try std.testing.expectEqual(@as(u8, 1), direct.neighbor_count);
        for ([_]speckleconfig.Evaluator{ .cell_hash, .mock }) |evaluator| {
            var resources = try generateResources(std.testing.failing_allocator, .{ .evaluator = evaluator });
            defer resources.deinit(std.testing.failing_allocator);
            try std.testing.expect(resources.kernel_index != null);
            try std.testing.expectEqualDeep(Resources{ .kernel_index = resources.kernel_index }, resources);
        }
    }
    // Perlin ignores disk-only fields but never silently repairs its own settings.
    try (Speckle2DParams{ .pattern = .perlin, .occupancy = std.math.nan(F), .radius_mean = -1, .radius_jitter = std.math.inf(F) }).validate();
    try std.testing.expectError(error.InvalidSpecklePerlinCoverageTransitionWidth, (Speckle2DParams{ .pattern = .perlin, .perlin_coverage_transition_width = -1 }).resolve());
}

test "classified owner strips clean up every allocation failure" {
    const Probe = struct {
        fn generate(allocator: std.mem.Allocator, jitter: F, occupancy: F) !void {
            var tracking = std.testing.FailingAllocator.init(allocator, .{});
            const tracked_allocator = tracking.allocator();
            var resources = try generateResources(tracked_allocator, .{
                .cells_per_uv = .{ 2, 1 },
                .occupancy = occupancy,
                .radius_mean = 0.35,
                .radius_jitter = jitter,
            });
            defer resources.deinit(tracked_allocator);
            try std.testing.expectEqual(@as(usize, 2), tracking.allocations);
            const strip = resources.classified.?.speckles;
            try std.testing.expectEqual(occupancy == 0.0, strip.recordCount() == 0);
            if (strip.recordCount() != 0) {
                try std.testing.expectEqual(3 * strip.cell_dims[0] * strip.cell_dims[1], strip.recordCount());
                try std.testing.expectEqual(jitter == 0.0, strip.centers.len != 0);
            }
            resources.deinit(tracked_allocator);
            try std.testing.expectEqual(tracking.allocations, tracking.deallocations);
            try std.testing.expectEqual(tracking.allocated_bytes, tracking.freed_bytes);
        }
    };
    for ([_]F{ 0.0, 0.08 }) |jitter| {
        for ([_]F{ 0.0, 1.0 }) |occupancy| try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.generate, .{ jitter, occupancy });
    }
}

test "positive-occupancy empty owner strips preserve stored negative-zero background" {
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    for ([_]F{ 0.0, 0.08 }) |jitter| {
        const params: Speckle2DParams = .{ .seed = 0, .cells_per_uv = .{ 0.03125, 0.0625 }, .occupancy = 0.001, .radius_mean = 0.35, .radius_jitter = jitter, .foreground = 0.91, .background = -0.0 };
        var resources = try generateResources(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        const strip = resources.classified.?.speckles;
        try std.testing.expectEqual(@as(usize, 0), strip.centers.len);
        try std.testing.expectEqual(@as(usize, 0), strip.disks.len);
        for (resources.classified.?.states) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
        const expected: Bits = @bitCast(params.background);
        for ([_]F{ 0.0, 0.5, 1.0, std.math.nan(F) }) |u| {
            try std.testing.expectEqual(expected, @as(Bits, @bitCast(sampleScal(u, 0.5, params, &resources))));
            inline for (.{ false, true }) |active| {
                const lanes: [S]F = sampleSIMD(@splat(u), @splat(0.5), @splat(active), params, &resources);
                for (lanes) |value| try std.testing.expectEqual(expected, @as(Bits, @bitCast(value)));
            }
        }
    }
}

test "runtime resources select only one resource and canonical scalar SIMD kernels" {
    inline for (generation_configs) |config| {
        var params: Speckle2DParams = .{
            .pattern = config.pattern,
            .cells_per_uv = .{ 3.25, 2.5 },
            .radius_mean = if (config.evaluator == .mock) 100 else if (config.neighbor_count == 1) 0.25 else 0.38,
            .radius_jitter = if (config.evaluator == .direct_fixed) 0.0 else 0.07,
            .occupancy = if (config.evaluator == .mock) 0 else (Speckle2DParams{}).occupancy,
            .edge_softness = if (config.soft_edges) 0.035 else 0.0,
            .foreground = 0.17,
            .background = 0.83,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            params.evaluator = config.evaluator;
            params.neighbor_count = if (config.pattern == .perlin and config.evaluator != .mock) null else config.neighbor_count;
        }
        try std.testing.expectEqual(config, try params.resolve());
        const raw = Implementation(config).evalSpeckle2DImpl(config.soft_edges, 0.37, 0.61, params);
        try std.testing.expectEqual(raw, sampleScal(0.37, 0.61, params, &.{}));
        const raw_simd: [S]F = sampleSIMD(@splat(0.37), @splat(0.61), @splat(false), params, &.{});
        for (raw_simd) |value| try std.testing.expectEqual(raw, value);
        var resources = try generateResources(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        const index = comptime kernelIndex(config);
        try std.testing.expectEqual(@as(?u8, index), resources.kernel_index);
        const allocated = @as(usize, @intFromBool(resources.list != null)) +
            @intFromBool(resources.classified != null) + @intFromBool(resources.neighbor_masked != null) + @intFromBool(resources.direct_fixed != null) +
            @intFromBool(resources.mask != null) + @intFromBool(resources.strip_list != null);
        try std.testing.expectEqual(@as(usize, if (config.evaluator == .cell_hash or config.evaluator == .mock) 0 else 1), allocated);
        try std.testing.expectEqual(config.evaluator == .list_naive, resources.list != null);
        try std.testing.expectEqual(config.evaluator == .list_indexed, resources.strip_list != null);
        try std.testing.expectEqual(config.evaluator == .classified_indexed, resources.classified != null);
        const points = [_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 0.37 }, .{ 0.35, 0.61 }, .{ 0.67, 0.41 }, .{ 0.37, 2 } };
        for (points) |uv| {
            const Impl = Implementation(config);
            const reference = switch (comptime config.evaluator) {
                .mock => 0.5 * (uv[0] + uv[1]),
                .cell_hash, .list_indexed => Impl.evalSpeckle2D(uv, params),
                // Direct-fixed returns stored endpoints, not the hash reference's arithmetic mapping.
                .direct_fixed => if (Impl.evalSpeckle2D(uv, params) == params.background)
                    params.background
                else
                    params.foreground,
                .list_naive => Impl.evalSpeckleList2DNaiveImpl(config.soft_edges, uv[0], uv[1], resources.list.?),
                .classified_indexed, .classified_indexed_2, .classified_indexed_3, .classified_indexed_4, .classified_indexed_5, .classified_indexed_6, .classified_indexed_7, .classified_indexed_8 => Impl.evalSpeckle2D(uv, params),
                .mask_1bit, .mask_u8 => Impl.evalSpeckleMask2D(uv, resources.mask.?),
            };
            try std.testing.expectEqual(reference, Kernel(index).sampleScal(uv[0], uv[1], params, &resources));
            try std.testing.expectEqual(reference, sampleScal(uv[0], uv[1], params, &resources));
            const actual: [S]F = Kernel(index).sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), params, &resources);
            const dispatched: [S]F = sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), params, &resources);
            for (actual, dispatched) |value, generic| {
                try std.testing.expectEqual(reference, value);
                try std.testing.expectEqual(value, generic);
            }
            const inactive: [S]F = Kernel(index).sampleSIMD(
                @splat(uv[0]),
                @splat(uv[1]),
                @splat(false),
                params,
                &resources,
            );
            const inactive_expected = switch (config.evaluator) {
                .cell_hash, .list_naive, .list_indexed, .mock => reference,
                else => params.background,
            };
            for (inactive) |value| try std.testing.expectEqual(inactive_expected, value);
        }
        const nonfinite: [S]F = Kernel(index).sampleSIMD(@splat(std.math.nan(F)), @splat(std.math.inf(F)), @splat(true), params, &resources);
        for (nonfinite) |value| {
            if (comptime config.evaluator == .mock) {
                try std.testing.expect(std.math.isNan(value));
            } else try std.testing.expectEqual(params.background, value);
        }
        resources.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(?u8, null), resources.kernel_index);
        try std.testing.expect(resources.list == null and resources.strip_list == null and resources.classified == null and
            resources.direct_fixed == null and resources.mask == null);
    }
}

test "strip indexed records and samples match exhaustive lists bitwise across occupancy and neighborhoods" {
    @setEvalBranchQuota(10_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (generation_configs) |config| {
        if (comptime config.evaluator != .list_indexed) continue;
        for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
            for (0..9) |variation| {
                const params: Speckle2DParams = .{
                    .pattern = config.pattern,
                    .evaluator = .list_indexed,
                    .neighbor_count = config.neighbor_count,
                    .cells_per_uv = .{ 3.25, 2.75 },
                    .occupancy = occupancy,
                    .seed = if (variation == 1) 43498 else 0,
                    .radius_mean = if (variation >= 7) (if (config.neighbor_count == 1) @as(F, 0.5) else @as(F, 1.0)) - (if (config.soft_edges) @as(F, 0.05) else 0.0) else if (variation == 1) 0.2 else 0.3,
                    .radius_jitter = if (variation == 1) 0.2 else if (variation == 8) -0.0 else if (variation == 3 or variation >= 7) 0.0 else 0.1,
                    .background = switch (variation) {
                        2, 5 => -0.0,
                        6 => 0.0,
                        4 => 0.91,
                        else => 0.23,
                    },
                    .foreground = switch (variation) {
                        2, 6 => -0.0,
                        5 => 0.0,
                        4 => 0.23,
                        else => 0.91,
                    },
                    .edge_softness = if (config.soft_edges) 0.05 else 0.0,
                };
                var reference_params = params;
                reference_params.evaluator = .list_naive;
                var reference_resources = try generateResources(std.testing.allocator, reference_params);
                defer reference_resources.deinit(std.testing.allocator);
                var tracking = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                var indexed = try generateResources(tracking.allocator(), params);
                defer indexed.deinit(tracking.allocator());
                try std.testing.expectEqual(@as(usize, 1), tracking.allocations);
                const table = reference_resources.list.?;
                const strip = indexed.strip_list.?;
                const length: usize = switch (config.neighbor_count) {
                    9 => 3,
                    4 => 2,
                    1 => 1,
                    else => unreachable,
                };
                const bounds = Implementation(config).speckleProceduralCellBounds(params, 1).?;
                try std.testing.expectEqual(bounds.min, strip.cell_origin);
                try std.testing.expectEqual(bounds.dims, strip.cell_dims);
                const record_count = bounds.count * length;
                try std.testing.expectEqual(record_count, strip.recordCount());
                if (params.radius_jitter == 0.0) {
                    try std.testing.expectEqual(@as(usize, 0), strip.disks.len);
                    try std.testing.expectEqual(@as(usize, 2 * @sizeOf(F)), @sizeOf([2]F));
                } else {
                    try std.testing.expectEqual(@as(usize, 0), strip.centers.len);
                    try std.testing.expectEqual(record_count, strip.disks.len);
                }
                if (params.radius_jitter == 0.0 and occupancy == 1.0) {
                    for (strip.centers) |center| try std.testing.expect(std.math.isFinite(center[0]) and std.math.isFinite(center[1]));
                }
                const Impl = Implementation(config);
                if (params.radius_jitter == 0.0) {
                    for (strip.centers) |center| {
                        if (!std.math.isInf(center[0])) continue;
                        try std.testing.expectEqual(@as(F, 0.0), center[1]);
                        for ([_]F{ -1.0, -0.0, 0.0, 1.0 }) |coordinate| {
                            const delta_x = coordinate - center[0];
                            const delta_y = coordinate - center[1];
                            const distance2 = delta_x * delta_x + delta_y * delta_y;
                            try std.testing.expectEqual(std.math.inf(F), distance2);
                            const SentinelBits = std.meta.Int(.unsigned, @bitSizeOf(F));
                            try std.testing.expectEqual(@as(SentinelBits, 0), @as(SentinelBits, @bitCast(Impl.fixedStripDiskMask(config.soft_edges, distance2, strip))));
                        }
                    }
                }
                for (0..strip.cell_dims[1]) |yy| {
                    for (0..strip.cell_dims[0]) |xx| {
                        for (0..length) |ii| {
                            const disk: SpeckleDisk2D = Impl.speckleDiskForCell(config.soft_edges, strip.cell_origin[0] + @as(i64, @intCast(xx)), strip.cell_origin[1] + @as(i64, @intCast(yy)) + @as(i64, @intCast(ii)) - (if (config.neighbor_count == 9) @as(i64, 1) else 0), params) orelse .{ .center = .{ 0.0, 0.0 }, .radius = -1.0 };
                            const stored = strip.record((yy * strip.cell_dims[0] + xx) * length + ii);
                            if (disk.radius < 0.0) {
                                try std.testing.expectEqual(std.math.inf(F), stored.center[0]);
                                try std.testing.expectEqual(@as(F, 0.0), stored.center[1]);
                                try std.testing.expectEqual(params.radius_mean, stored.radius);
                                const mask = if (params.radius_jitter == 0.0)
                                    Impl.fixedStripDiskMask(config.soft_edges, std.math.inf(F), strip)
                                else
                                    Impl.speckleDiskMask(config.soft_edges, std.math.inf(F), stored.radius, params.edge_softness);
                                try std.testing.expectEqual(@as(F, 0.0), mask);
                            } else {
                                try std.testing.expectEqualDeep(disk, stored);
                                try std.testing.expectEqualSlices(u8, std.mem.asBytes(&disk), std.mem.asBytes(&stored));
                            }
                        }
                    }
                }
                const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
                for (table.disks) |disk| {
                    const u = disk.center[0] / table.params.cells_per_uv[0];
                    const v = disk.center[1] / table.params.cells_per_uv[1];
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(config.soft_edges, Impl.evalSpeckleList2DNaiveImpl, @splat(u), @splat(v), table, table.params.background);
                    const after: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(false), params, &indexed);
                    for (before, after) |reference, actual| try std.testing.expectEqual(@as(Bits, @bitCast(reference)), @as(Bits, @bitCast(actual)));
                    if (params.radius_jitter == 0.0) {
                        const support = disk.radius + params.edge_softness;
                        for (0..2) |axis| {
                            for ([_]F{ -support, support }) |edge| {
                                const point = (disk.center[axis] + edge) / params.cells_per_uv[axis];
                                for ([_]F{ point, std.math.nextAfter(F, point, -std.math.inf(F)), std.math.nextAfter(F, point, std.math.inf(F)) }) |coordinate| {
                                    const edge_u = if (axis == 0) coordinate else u;
                                    const edge_v = if (axis == 1) coordinate else v;
                                    const expected = sampleScal(edge_u, edge_v, table.params, &reference_resources);
                                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(edge_u, edge_v, params, &indexed))));
                                    const lanes: [S]F = sampleSIMD(@splat(edge_u), @splat(edge_v), @splat(false), params, &indexed);
                                    for (lanes) |actual| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
                                }
                            }
                        }
                    }
                }
                for (0..64) |batch| {
                    var us: [S]F = undefined;
                    var vs: [S]F = undefined;
                    for (0..S) |lane| {
                        const shift = @as(F, @floatFromInt(lane)) * 0.00001;
                        us[lane] = @as(F, @floatFromInt(batch % 8)) / 8.0 + shift;
                        vs[lane] = @as(F, @floatFromInt(batch / 8)) / 8.0 - shift;
                    }
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(config.soft_edges, Impl.evalSpeckleList2DNaiveImpl, us, vs, table, table.params.background);
                    const after: [S]F = sampleSIMD(us, vs, @splat(false), params, &indexed);
                    for (before, after) |reference, actual| try std.testing.expectEqual(@as(Bits, @bitCast(reference)), @as(Bits, @bitCast(actual)));
                }
                for (0..128) |batch| {
                    var us: [S]F = undefined;
                    var vs: [S]F = undefined;
                    var active: [S]bool = undefined;
                    for (0..S) |lane| {
                        const index = batch * S + lane;
                        us[lane] = @as(F, @floatFromInt((index * 7919 + 17) % 65521)) / 60000.0 - 0.05;
                        vs[lane] = @as(F, @floatFromInt((index * 104729 + 31) % 65521)) / 60000.0 - 0.05;
                        active[lane] = batch % 3 != 0 and lane % 2 == 0;
                        if (batch >= 8 and batch < 16) {
                            vs[lane] = switch ((batch + lane) % 4) {
                                0 => std.math.nan(F),
                                1 => std.math.inf(F),
                                2 => -std.math.inf(F),
                                else => 0.5,
                            };
                        }
                        if (batch < 8) {
                            us[lane] = switch ((batch + lane) % 8) {
                                0 => 0.0,
                                1 => 1.0,
                                2 => std.math.nan(F),
                                3 => std.math.inf(F),
                                4 => -std.math.inf(F),
                                5 => -0.0,
                                6 => 0.5,
                                else => 1.0 + std.math.floatEps(F),
                            };
                        }
                    }
                    const expected: [S]F = Impl.evalSpeckleSIMDImpl(config.soft_edges, Impl.evalSpeckleList2DNaiveImpl, us, vs, table, table.params.background);
                    const actual: [S]F = sampleSIMD(us, vs, active, params, &indexed);
                    for (us, vs) |u, v| {
                        if (!std.math.isFinite(u) or !std.math.isFinite(v)) continue;
                        try std.testing.expectEqual(@as(Bits, @bitCast(sampleScal(u, v, table.params, &reference_resources))), @as(Bits, @bitCast(sampleScal(u, v, params, &indexed))));
                    }
                    for (expected, actual) |before, after| {
                        try std.testing.expectEqual(@as(Bits, @bitCast(before)), @as(Bits, @bitCast(after)));
                    }
                }
                for (0..2) |axis| {
                    for (0..strip.cell_dims[axis]) |ii| {
                        const boundary = (@as(F, @floatFromInt(strip.cell_origin[axis] + @as(i64, @intCast(ii))))) / params.cells_per_uv[axis];
                        for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |coordinate| {
                            const u = if (axis == 0) coordinate else 0.5;
                            const v = if (axis == 1) coordinate else 0.5;
                            try std.testing.expectEqual(@as(Bits, @bitCast(sampleScal(u, v, table.params, &reference_resources))), @as(Bits, @bitCast(sampleScal(u, v, params, &indexed))));
                        }
                    }
                }
                for (0..23) |yy| {
                    for (0..23) |xx| {
                        const u = @as(F, @floatFromInt(xx)) / 20.0 - 0.05;
                        const v = @as(F, @floatFromInt(yy)) / 20.0 - 0.05;
                        const expected = sampleScal(u, v, table.params, &reference_resources);
                        try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(u, v, params, &indexed))));
                        const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(true), params, &indexed);
                        for (lanes) |value| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
                    }
                }
            }
        }
    }
}

test "strip indexed zero radius soft disk coverage and default gate" {
    const params: Speckle2DParams = .{ .evaluator = .list_indexed, .neighbor_count = 1, .seed = 43498, .cells_per_uv = .{ 1, 1 }, .occupancy = 1, .radius_mean = 0.2, .radius_jitter = 0.2, .edge_softness = 0.05 };
    if (comptime !buildconfig.enable_all_evaluators) {
        try std.testing.expectError(error.SpeckleOverridesDisabled, params.resolve());
        return;
    }
    var strip = try generateResources(std.testing.allocator, params);
    defer strip.deinit(std.testing.allocator);
    var reference_params = params;
    reference_params.evaluator = .list_naive;
    var reference = try generateResources(std.testing.allocator, reference_params);
    defer reference.deinit(std.testing.allocator);
    const table = strip.strip_list.?;
    const disk = table.disks[@as(usize, @intCast(-table.cell_origin[1])) * table.cell_dims[0] + @as(usize, @intCast(-table.cell_origin[0]))];
    try std.testing.expectEqual(@as(F, 0), disk.radius);
    try std.testing.expectApproxEqAbs(@as(F, 0.1723602294921875), disk.center[0], 0.000001);
    try std.testing.expectApproxEqAbs(@as(F, 0.6010055541992189), disk.center[1], 0.000001);
    const expected = sampleScal(disk.center[0], disk.center[1], reference_params, &reference);
    try std.testing.expect(expected != params.background);
    try std.testing.expectEqual(expected, sampleScal(disk.center[0], disk.center[1], params, &strip));
    const lanes: [S]F = sampleSIMD(@splat(disk.center[0]), @splat(disk.center[1]), @splat(true), params, &strip);
    for (lanes) |value| try std.testing.expectEqual(expected, value);
}
