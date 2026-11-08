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
const max_perlin_lattice_bytes = 256 * 1024 * 1024;
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
    neighbor_count: ?speckleconfig.Neighborhood = null,
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
            if (self.edge_softness > 0.0) .soft else .hard,
        );
        try self.validateResolved(config);
        return config;
    }

    pub fn validate(self: Speckle2DParams) !void {
        _ = try self.resolve();
    }

    // Separate numeric checks let configured generators validate without resolving again.
    fn validateResolved(self: Speckle2DParams, config: speckleconfig.Config) !void {
        const evaluator = std.meta.activeTag(config);
        // Only mock erases its pattern; softness still obeys the raw pattern contract.
        const pattern = config.pattern() orelse self.pattern;
        for (self.cells_per_uv) |cell_count| {
            if (!std.math.isFinite(cell_count) or cell_count <= 0.0) {
                return error.InvalidSpeckleCellsPerUV;
            }
        }
        if (!std.math.isFinite(self.edge_softness) or self.edge_softness < 0.0) {
            return error.InvalidSpeckleEdgeSoftness;
        }
        if (self.edge_softness != 0.0) {
            if (pattern != .disk) {
                return error.SpeckleEdgeSoftnessRequiresDisk;
            }
            if (!config.supportsSoftEdges()) return error.SpeckleEvaluatorRequiresHardEdges;
        }
        if (evaluator != .mock and pattern == .perlin) {
            if (!std.math.isFinite(self.perlin_coverage_threshold)) {
                return error.InvalidSpecklePerlinCoverageThreshold;
            }
            if (!std.math.isFinite(self.perlin_coverage_transition_width) or
                self.perlin_coverage_transition_width < 0.0)
            {
                return error.InvalidSpecklePerlinCoverageTransitionWidth;
            }
        } else if (evaluator != .mock) {
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
            if (evaluator == .direct_fixed and self.radius_jitter != 0.0) {
                return error.InvalidDirectFixedSpeckleRadiusJitter;
            }
            if (self.radius_jitter > self.radius_mean) return error.InvalidSpeckleRadiusRange;

            const max_radius = self.radius_mean + self.radius_jitter + self.edge_softness;
            if (max_radius > (if (config.neighborhood() == .one) @as(F, 0.5) else @as(F, 1.0))) {
                return if (evaluator == .direct_fixed)
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
};

pub const ClassifiedIndexedSpeckle2D = struct {
    speckles: StripSpeckleList2D,
    /// Bits 0..8 select x-major (-1..1, -1..1) neighbours; bit 9 is the base colour.
    /// Foreground certification is exactly 512 (no candidates); otherwise the base is background.
    states: []const u16,
    dims: [2]usize,
};

pub const DirectFixedSpeckleCell2D = u64;

pub const DirectFixedSpeckle2D = struct {
    params: Speckle2DParams,
    cells: []const DirectFixedSpeckleCell2D,
    cell_origin: [2]i64,
    cell_dims: [2]usize,
    radius2: F,
};

/// Exact gradient IDs, shared by adjacent cells; an empty lattice hashes on demand.
pub const PerlinLattice2D = struct {
    params: Speckle2DParams,
    gradients: []const u8,
    dims: [2]usize,
};

pub const SpeckleMask2D = struct {
    bits: []const u8,
    dims: [2]usize,
    row_stride: usize,
    uv_to_texel: [2]F,
    params: Speckle2DParams,
};

pub const GaussianDiskCoefficients = struct { center: [2]F, outer2: F, sigma2: F };

pub const CellBinnedRecords = union(enum) {
    disks: []const SpeckleDisk2D,
    gaussian: []const GaussianDiskCoefficients,
    // One allocation contains X then Y planes; two slices keep the tagged value compact.
    strided: struct { coordinates: []const F, counts: []const u8 },
};

/// Bins over existing procedural cells, including the UV upper endpoint cell.
/// Fixed-stride records omit CSR offsets; all other layouts retain them.
/// Records are duplicated into intersected, stencil-eligible cells during setup;
/// immutable sampling traverses only one contiguous cell list, never neighbours.
pub const CellBinnedSpeckle2D = struct {
    params: Speckle2DParams,
    offsets: []const usize,
    records: CellBinnedRecords,
    dims: [2]usize,

    fn range(self: @This(), cell: usize) [2]usize {
        if (self.records == .strided) return .{ cell * 9, cell * 9 + self.records.strided.counts[cell] };
        return .{ self.offsets[cell], self.offsets[cell + 1] };
    }

    pub fn recordCount(self: @This()) usize {
        if (self.records == .strided) {
            var count: usize = 0;
            for (self.records.strided.counts) |n| count += n;
            return count;
        }
        return self.offsets[self.offsets.len - 1];
    }

    pub fn byteSize(self: @This()) usize {
        return self.offsets.len * @sizeOf(usize) + switch (self.records) {
            .disks => |records| records.len * @sizeOf(SpeckleDisk2D),
            .gaussian => |records| records.len * @sizeOf(GaussianDiskCoefficients),
            .strided => |records| records.coordinates.len * @sizeOf(F) + records.counts.len,
        };
    }

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        switch (self.records) {
            .strided => |records| {
                allocator.free(records.coordinates);
                allocator.free(records.counts);
            },
            inline else => |records| allocator.free(records),
        }
        allocator.free(self.offsets);
    }
};

const max_cell_binned_bytes = 256 * 1024 * 1024;

fn checkCellBinnedPreparationBudget(index_bytes: usize, record_bytes: usize, budget: usize) !void {
    const total = std.math.add(usize, index_bytes, record_bytes) catch return error.SpeckleCellBinsTooLarge;
    if (total > budget) return error.SpeckleCellBinsTooLarge;
}

pub const Backing = union(enum) {
    none,
    list: SpeckleList2D,
    strip_list: StripSpeckleList2D,
    cell_binned: CellBinnedSpeckle2D,
    classified: ClassifiedIndexedSpeckle2D,
    direct_classified: DirectClassifiedSpeckle2D,
    rect_bin_classified: RectBinClassifiedSpeckle2D,
    direct_fixed: DirectFixedSpeckle2D,
    mask: SpeckleMask2D,
    perlin: PerlinLattice2D,
};

/// Static feature owner. Only the owner calls deinit with its original allocator;
/// frames and workers borrow *const Resources and cannot free the backing.
/// Arena-backed resources may instead be released with their owning static arena.
pub const Resources = struct {
    /// Index into kernel_configs, set even when cell hashing needs no allocation.
    kernel_index: ?u8 = null,
    data: Backing = .none,

    /// Prepare only the resolved backing; keep parameters/configuration immutable thereafter.
    // Classification setup is alignment-sensitive; 64-byte alignment avoids a measured regression.
    pub fn init(
        outer_alloc: std.mem.Allocator,
        params: Speckle2DParams,
    ) align(64) !Resources {
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

    pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .none => {},
            .list => |speckles| allocator.free(speckles.disks),
            .strip_list => |speckles| {
                allocator.free(speckles.centers);
                allocator.free(speckles.disks);
            },
            .classified => |classified| {
                allocator.free(classified.states);
                allocator.free(classified.speckles.centers);
                allocator.free(classified.speckles.disks);
            },
            .cell_binned => |binned| binned.deinit(allocator),
            .direct_classified => |direct| direct.deinit(allocator),
            .rect_bin_classified => |data| data.deinit(allocator),
            .direct_fixed => |direct| allocator.free(direct.cells),
            .mask => |mask| allocator.free(mask.bits),
            .perlin => |perlin| allocator.free(perlin.gradients),
        }
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
    return speckleconfig.sampleConfigIndex(buildconfig.enable_all_evaluators, config);
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
            return Impl.samplePreparedScal(config.edges() == .soft, u, v, params, resources);
        }

        pub inline fn sampleSIMD(
            u: VecSF,
            v: VecSF,
            active: VecSB,
            params: Speckle2DParams,
            resources: *const Resources,
        ) VecSF {
            std.debug.assert(resources.kernel_index == @as(?u8, index_tag));
            return Impl.samplePreparedSIMD(config.edges() == .soft, u, v, active, params, resources);
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
            return Implementation(config).evalSpeckle2DImpl(config.edges() == .soft, u, v, params);
        }
    }
    unreachable;
}

/// Prepared Perlin and classified/direct/mask kernels background inactive lanes.
/// Other procedural/list kernels retain the existing finite-lane behavior.
/// Except for mock's raw arithmetic, every SIMD kernel backgrounds nonfinite lanes.
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
            if (comptime std.meta.activeTag(config) == .mock) return Impl.samplePreparedSIMD(config.edges() == .soft, u, v, active, params, resources);
            return Impl.evalSpeckleSIMDImpl(
                config.edges() == .soft,
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
    // Exact inverse bins stay in one procedural owner, so the stencil alone
    // implies the former floor(box endpoints) +/- 1 owner-search guard.
    try std.testing.expectEqual(j / r, @as(usize, @intFromFloat(@floor(lo))));
    try std.testing.expectEqual(j / r, @as(usize, @intFromFloat(@floor(std.math.nextAfter(T, next, -std.math.inf(T))))));
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

fn generatePerlinLattice(allocator: std.mem.Allocator, params: Speckle2DParams) !PerlinLattice2D {
    var lattice = PerlinLattice2D{ .params = params, .gradients = &.{}, .dims = .{ 0, 0 } };
    var dims: [2]usize = undefined;
    for (params.cells_per_uv, 0..) |cells, axis| {
        const owners = std.math.cast(usize, @as(u64, @intFromFloat(@floor(cells)))) orelse return lattice;
        dims[axis] = std.math.add(usize, owners, 2) catch return lattice;
    }
    const count = std.math.mul(usize, dims[0], dims[1]) catch return lattice;
    if (count > max_perlin_lattice_bytes) return lattice;
    const gradients = try allocator.alloc(u8, count);
    for (0..dims[1]) |y| {
        for (0..dims[0]) |x| {
            gradients[y * dims[0] + x] = @as(u8, @truncate(hashSpeckleCell(@intCast(x), @intCast(y), params.seed))) & 7;
        }
    }
    lattice.gradients = gradients;
    lattice.dims = dims;
    return lattice;
}

fn perlinCornerIDs(lattice: PerlinLattice2D, x: i64, y: i64) [4]u8 {
    if (lattice.gradients.len == 0) {
        return .{
            @truncate(hashSpeckleCell(x, y, lattice.params.seed)),
            @truncate(hashSpeckleCell(x + 1, y, lattice.params.seed)),
            @truncate(hashSpeckleCell(x, y + 1, lattice.params.seed)),
            @truncate(hashSpeckleCell(x + 1, y + 1, lattice.params.seed)),
        };
    }
    // Only cached owners are bounded by allocated, pointer-sized dimensions.
    const i = @as(usize, @intCast(y)) * lattice.dims[0] + @as(usize, @intCast(x));
    return .{ lattice.gradients[i], lattice.gradients[i + 1], lattice.gradients[i + lattice.dims[0]], lattice.gradients[i + lattice.dims[0] + 1] };
}

fn perlinSplat(comptime T: type, value: F) T {
    return if (T == F) value else @splat(value);
}

fn perlinSelect(comptime T: type, condition: anytype, yes: T, no: T) T {
    return if (T == F) (if (condition) yes else no) else @select(F, condition, yes, no);
}

// Select complete expressions, not gradient coefficients: rearranging diagonal
// products changes rounding, cancellation and signed zero relative to the oracle.
fn perlinDot(comptime T: type, id: anytype, x: T, y: T) T {
    const d = perlinSplat(T, @sqrt(@as(F, 0.5)));
    const g = id & perlinIDConstant(@TypeOf(id), 7);
    var result = d * (x - y);
    inline for (0..7) |i| {
        const value = switch (i) {
            0 => x,
            1 => d * (x + y),
            2 => y,
            3 => d * (-x + y),
            4 => -x,
            5 => -d * (x + y),
            6 => -y,
            else => unreachable,
        };
        result = perlinSelect(T, g == perlinIDConstant(@TypeOf(id), i), value, result);
    }
    return result;
}

fn perlinIDConstant(comptime T: type, comptime value: u8) T {
    return if (T == u8) value else @splat(value);
}

fn perlinAnalytic(comptime T: type, x: T, y: T, ids: anytype, params: Speckle2DParams) T {
    const one = perlinSplat(T, 1);
    const fx = x * x * x * (x * (x * perlinSplat(T, 6) - perlinSplat(T, 15)) + perlinSplat(T, 10));
    const fy = y * y * y * (y * (y * perlinSplat(T, 6) - perlinSplat(T, 15)) + perlinSplat(T, 10));
    const n00 = perlinDot(T, ids[0], x, y);
    const n10 = perlinDot(T, ids[1], x - one, y);
    const n01 = perlinDot(T, ids[2], x, y - one);
    const n11 = perlinDot(T, ids[3], x - one, y - one);
    const nx0 = n00 + fx * (n10 - n00);
    const nx1 = n01 + fx * (n11 - n01);
    const noise = nx0 + fy * (nx1 - nx0);
    const threshold = perlinSplat(T, params.perlin_coverage_threshold);
    const coverage = if (params.perlin_coverage_transition_width == 0)
        perlinSelect(T, noise >= threshold, one, perlinSplat(T, 0))
    else blk: {
        const t = @max(perlinSplat(T, 0), @min(one, (noise - threshold) / perlinSplat(T, params.perlin_coverage_transition_width) + perlinSplat(T, 0.5)));
        break :blk t * t * (perlinSplat(T, 3) - perlinSplat(T, 2) * t);
    };
    return perlinSplat(T, params.background) + coverage * perlinSplat(T, params.foreground - params.background);
}

fn samplePerlinScal(u: F, v: F, lattice: PerlinLattice2D) F {
    if (!std.math.isFinite(u) or !std.math.isFinite(v)) return lattice.params.background;
    const x = @max(0.0, @min(1.0, u)) * lattice.params.cells_per_uv[0];
    const y = @max(0.0, @min(1.0, v)) * lattice.params.cells_per_uv[1];
    return perlinAnalytic(F, x - @floor(x), y - @floor(y), perlinCornerIDs(lattice, @intFromFloat(@floor(x)), @intFromFloat(@floor(y))), lattice.params);
}

fn samplePerlinSIMD(u: VecSF, v: VecSF, active: VecSB, lattice: PerlinLattice2D) VecSF {
    const valid = active & (@abs(u) <= @as(VecSF, @splat(std.math.floatMax(F)))) & (@abs(v) <= @as(VecSF, @splat(std.math.floatMax(F))));
    const zero: VecSF = @splat(0);
    const one: VecSF = @splat(1);
    const x = @max(zero, @min(one, @select(F, valid, u, zero))) * @as(VecSF, @splat(lattice.params.cells_per_uv[0]));
    const y = @max(zero, @min(one, @select(F, valid, v, zero))) * @as(VecSF, @splat(lattice.params.cells_per_uv[1]));
    const cx = @floor(x);
    const cy = @floor(y);
    var ids: [4]@Vector(S, u8) = .{ @splat(0), @splat(0), @splat(0), @splat(0) };
    inline for (0..S) |lane| {
        if (valid[lane]) {
            const corners = perlinCornerIDs(lattice, @intFromFloat(cx[lane]), @intFromFloat(cy[lane]));
            inline for (0..4) |i| ids[i][lane] = corners[i];
        }
    }
    const value = perlinAnalytic(VecSF, x - cx, y - cy, ids, lattice.params);
    return @select(F, valid, value, @as(VecSF, @splat(lattice.params.background)));
}

const PerlinReference = Implementation(.{ .cell_hash = .perlin });

fn expectPerlinBits(expected: F, actual: F) !void {
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
}

test "exact Perlin gradients preserve all signed expressions scalar and SIMD" {
    const values = [_]F{ 0, -0.0, 0.25, -0.25, 1, -1, std.math.nextAfter(F, 0, 1) };
    for (0..8) |id| {
        for (values) |x| {
            for (values) |y| {
                const expected = PerlinReference.perlinGradientDot(@intCast(id), x, y);
                try expectPerlinBits(expected, perlinDot(F, @as(u8, @intCast(id)), x, y));
                const actual: [S]F = perlinDot(VecSF, @as(@Vector(S, u8), @splat(@intCast(id))), @as(VecSF, @splat(x)), @as(VecSF, @splat(y)));
                for (actual) |value| try expectPerlinBits(expected, value);
            }
        }
    }
}

test "exact Perlin all 4096 corner combinations preserve analytic arithmetic" {
    var params = Speckle2DParams{ .pattern = .perlin, .foreground = 0.17, .background = 0.83 };
    for (0..4096) |code| {
        const ids = [4]u8{ @intCast(code & 7), @intCast((code >> 3) & 7), @intCast((code >> 6) & 7), @intCast((code >> 9) & 7) };
        for ([_][2]F{ .{ 0, 0 }, .{ 0.25, 0.75 }, .{ 0.5, 0.5 }, .{ std.math.nextAfter(F, 1, 0), 0.37 } }) |p| {
            const a = PerlinReference.perlinGradientDot(ids[0], p[0], p[1]);
            const b = PerlinReference.perlinGradientDot(ids[1], p[0] - 1, p[1]);
            const c = PerlinReference.perlinGradientDot(ids[2], p[0], p[1] - 1);
            const d = PerlinReference.perlinGradientDot(ids[3], p[0] - 1, p[1] - 1);
            const fx = PerlinReference.quinticPerlinFade(p[0]);
            const fy = PerlinReference.quinticPerlinFade(p[1]);
            const lo = a + fx * (b - a);
            const hi = c + fx * (d - c);
            const noise = lo + fy * (hi - lo);
            for ([_]F{ noise, std.math.nextAfter(F, noise, -std.math.inf(F)), std.math.nextAfter(F, noise, std.math.inf(F)) }) |threshold| {
                for ([_]F{ 0, std.math.nextAfter(F, 0, 1), 0.12 }) |width| {
                    params.perlin_coverage_threshold = threshold;
                    params.perlin_coverage_transition_width = width;
                    const coverage = PerlinReference.perlinCoverage(noise, params);
                    const expected = params.background + coverage * (params.foreground - params.background);
                    try expectPerlinBits(expected, perlinAnalytic(F, p[0], p[1], ids, params));
                    const vector_ids = [4]@Vector(S, u8){ @splat(ids[0]), @splat(ids[1]), @splat(ids[2]), @splat(ids[3]) };
                    const actual: [S]F = perlinAnalytic(VecSF, @splat(p[0]), @splat(p[1]), vector_ids, params);
                    for (actual) |value| try expectPerlinBits(expected, value);
                }
            }
        }
    }
}

test "exact Perlin cache agrees bitwise with independent hashes across parameters and mixed lanes" {
    const tiny = std.math.nextAfter(F, 0, 1);
    const scales = [_][2]F{ .{ 7.25, 5.5 }, .{ 2, 1 }, .{ 0.031, 1.17 }, .{ tiny, tiny }, .{ 192, 160 } };
    for (scales) |scale| {
        for ([_]u32{ 0, 0xa511e9b3, 0xffffffff }) |seed| {
            var lattice = try generatePerlinLattice(std.testing.allocator, .{ .pattern = .perlin, .seed = seed, .cells_per_uv = scale, .occupancy = std.math.nan(F), .radius_mean = -1 });
            defer std.testing.allocator.free(lattice.gradients);
            // Each cached corner is checked against the independently addressed hash.
            for (0..@as(usize, @intFromFloat(@floor(scale[1]))) + 1) |y| {
                for (0..@as(usize, @intFromFloat(@floor(scale[0]))) + 1) |x| {
                    const got = perlinCornerIDs(lattice, @intCast(x), @intCast(y));
                    var direct = lattice;
                    direct.gradients = &.{};
                    const expected = perlinCornerIDs(direct, @intCast(x), @intCast(y));
                    for (got, expected) |a, b| try std.testing.expectEqual(b & 7, a & 7);
                }
            }
            for ([_]F{ 0, -0.0, tiny, std.math.floatMin(F), 0.12, 2, std.math.floatMax(F) }) |width| {
                for ([_]F{ -std.math.floatMax(F), -0.2, -tiny, -0.0, 0, tiny, 0.2, std.math.floatMax(F) }) |threshold| {
                    for ([_][2]F{ .{ 1, 0 }, .{ 0, 1 }, .{ 0.23, 0.23 }, .{ -0.0, 0 }, .{ 0, -0.0 }, .{ -0.0, -0.0 } }) |colours| {
                        lattice.params.perlin_coverage_transition_width = width;
                        lattice.params.perlin_coverage_threshold = threshold;
                        lattice.params.background = colours[0];
                        lattice.params.foreground = colours[1];
                        var i: usize = 0;
                        while (i < 96) : (i += S) {
                            var us: VecSF = undefined;
                            var vs: VecSF = undefined;
                            var active: VecSB = undefined;
                            inline for (0..S) |lane| {
                                const k = i + lane;
                                const boundary = @min(@as(F, 2), @as(F, @floatFromInt(k % 8)) / scale[0]);
                                us[lane] = switch (k % 12) {
                                    0 => 0,
                                    1 => 1,
                                    2 => -2,
                                    3 => 2,
                                    4 => boundary,
                                    5 => std.math.nextAfter(F, boundary, 0),
                                    6 => std.math.nextAfter(F, boundary, std.math.inf(F)),
                                    else => @as(F, @floatFromInt((k * 3571) % 65521)) / 65521,
                                };
                                vs[lane] = @as(F, @floatFromInt((k * 7919) % 65521)) / 65521;
                                active[lane] = k % 7 != 0;
                                const expected = PerlinReference.evalPerlinSpeckle2D(.{ us[lane], vs[lane] }, lattice.params);
                                try expectPerlinBits(expected, samplePerlinScal(us[lane], vs[lane], lattice));
                            }
                            const actual: [S]F = samplePerlinSIMD(us, vs, active, lattice);
                            inline for (0..S) |lane| {
                                const expected = if (active[lane]) PerlinReference.evalPerlinSpeckle2D(.{ us[lane], vs[lane] }, lattice.params) else lattice.params.background;
                                try expectPerlinBits(expected, actual[lane]);
                            }
                        }
                    }
                }
            }
            for ([_]F{ std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |invalid| {
                try expectPerlinBits(lattice.params.background, samplePerlinScal(invalid, 0.5, lattice));
                const actual: [S]F = samplePerlinSIMD(@splat(invalid), @splat(0.5), @splat(true), lattice);
                for (actual) |value| try expectPerlinBits(lattice.params.background, value);
            }
        }
    }
}

test "exact Perlin budget fallback owns parameters without narrowing coordinates" {
    const scales: []const [2]F = if (F == f64)
        &.{ .{ 4_294_967_296, 1.17 }, .{ 1.17, 4_294_967_296 }, .{ 35_184_372_088_831, 1.17 }, .{ 1.17, 35_184_372_088_831 }, .{ 35_184_372_088_831, 35_184_372_088_831 } }
    else
        &.{.{ 65_535, 65_535 }};
    for (scales) |scale| {
        var resources = try Resources.init(std.testing.failing_allocator, .{ .pattern = .perlin, .cells_per_uv = scale });
        defer resources.deinit(std.testing.failing_allocator);
        try std.testing.expectEqual(@as(usize, 0), resources.data.perlin.gradients.len);
        const params = resources.data.perlin.params;
        for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ 1, 0.61 }, .{ 0.37, 1 }, .{ std.math.nextAfter(F, 1, 0), 0.37 }, .{ 0.37, std.math.nextAfter(F, 1, 0) } }) |uv| {
            const expected = PerlinReference.evalPerlinSpeckle2D(uv, params);
            try expectPerlinBits(expected, sampleScal(uv[0], uv[1], .{}, &resources));
            const actual: [S]F = sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), .{}, &resources);
            for (actual) |value| try expectPerlinBits(expected, value);
        }
    }
}

test "exact Perlin propagates allocation failure and releases owned storage" {
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .pattern = .perlin }));
    const Allocation = struct {
        fn run(allocator: std.mem.Allocator) !void {
            var owned = try Resources.init(allocator, .{ .pattern = .perlin, .cells_per_uv = .{ 2.17, 1.31 } });
            defer owned.deinit(allocator);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Allocation.run, .{});
}

/// Experimental direct builders own only their selected backing. No canonical
/// strip resources are constructed. The 512 MiB cap includes all live scratch.
pub const DirectClassifiedSpeckle2D = struct {
    params: Speckle2DParams,
    dims: [2]usize,
    cell_dims: [2]usize,
    owner_origin: [2]i64,
    owner_dims: [2]usize,
    states: []const u16 = &.{},
    descriptors: []const u32 = &.{},
    coordinates: []const F = &.{},
    indexes: []const u32 = &.{},
    offsets: []const u32 = &.{},
    counts: []const u8 = &.{},
    record_count: usize = 0,
    radius2: F,
    fixed_radius: bool,
    empty: bool = true,
    width: usize = 0,
    owner_visits: usize = 0,
    active_owners: usize = 0,
    ambiguous_cells: usize = 0,
    singleton_cells: usize = 0,
    candidate_entries: usize = 0,
    peak_bytes: usize = 0,

    pub fn byteSize(self: @This()) usize {
        return self.states.len * 2 + self.descriptors.len * 4 + self.coordinates.len * @sizeOf(F) +
            self.indexes.len * 4 + self.offsets.len * 4 + self.counts.len;
    }

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.states);
        allocator.free(self.descriptors);
        allocator.free(self.coordinates);
        allocator.free(self.indexes);
        allocator.free(self.offsets);
        allocator.free(self.counts);
    }
};

const max_direct_classified_preparation_bytes = 512 * 1024 * 1024;

fn directClassifiedCharge(live: *usize, count: usize, size: usize) !void {
    const bytes = std.math.mul(usize, count, size) catch return error.SpeckleClassificationTooLarge;
    live.* = std.math.add(usize, live.*, bytes) catch return error.SpeckleClassificationTooLarge;
    if (live.* > max_direct_classified_preparation_bytes) return error.SpeckleClassificationTooLarge;
}

// Candidate 22 is the frozen candidate-19 specialization. Dead 20/21
// branches are removed; in-budget generation/initialization and slot mapping
// remain unchanged. Only float-to-integer coordinates change in its sampler.
const Classified22 = struct {
    const Original = Implementation(.classified_indexed);
    const R = buildconfig.speckle_mask_samples_per_cell;
    fn generate(allocator: std.mem.Allocator, params: Speckle2DParams) !DirectClassifiedSpeckle2D {
        try params.validateResolved(.classified_indexed);
        return if (params.radius_jitter == 0) generateImpl(true, allocator, params) else generateImpl(false, allocator, params);
    }

    fn generateImpl(comptime fixed: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !DirectClassifiedSpeckle2D {
        const dims = Original.classifiedDims(params) orelse return error.SpeckleClassificationTooLarge;
        const n = std.math.mul(usize, dims[0], dims[1]) catch return error.SpeckleClassificationTooLarge;
        if (n > max_speckle_classification_bytes / 2) return error.SpeckleClassificationTooLarge;
        const bounds = Original.speckleProceduralCellBounds(params, 0) orelse return error.SpeckleClassificationTooLarge;
        const owners = Original.speckleProceduralCellBounds(params, 1) orelse return error.SpeckleClassificationTooLarge;
        if (owners.count > max_speckle_cells) return error.SpeckleClassificationTooLarge;
        var live: usize = 0;
        try directClassifiedCharge(&live, n, 2);
        const states = try allocator.alloc(u16, n);
        errdefer allocator.free(states);
        @memset(states, 0);
        var result: DirectClassifiedSpeckle2D = .{
            .params = params,
            .dims = dims,
            .cell_dims = bounds.dims,
            .owner_origin = owners.min,
            .owner_dims = owners.dims,
            .radius2 = params.radius_mean * params.radius_mean,
            .fixed_radius = fixed,
        };
        var boundary_cache: [Original.speckle_classification_boundary_cache_capacity]F = undefined;
        var cached: usize = 0;
        var axes = Original.speckleClassificationAxes(dims, params);
        var domain_scale: F = 1;
        for (0..2) |axis| {
            domain_scale = @max(domain_scale, @max(@abs(axes[axis].boundary(0)), @abs(axes[axis].upperBound(dims[axis]))));
            const len = dims[axis] + 1;
            if (len <= boundary_cache.len - cached) {
                const cache = boundary_cache[cached..][0..len];
                for (cache, 0..) |*b, i| b.* = axes[axis].boundary(i);
                axes[axis].cached_boundaries = cache;
                cached += len;
            }
        }
        // Account for bounded stack boundary scratch as well as heap arrays.
        try directClassifiedCharge(&live, boundary_cache.len, @sizeOf(F));

        try directClassifiedCharge(&live, bounds.count, 1);
        const counts = try allocator.alloc(u8, bounds.count);
        errdefer allocator.free(counts);
        @memset(counts, 0);
        const offsets_len: usize = if (fixed) 0 else bounds.count + 1;
        try directClassifiedCharge(&live, offsets_len, 4);
        const offsets = try allocator.alloc(u32, offsets_len);
        errdefer allocator.free(offsets);
        if (!fixed) {
            visitBinnedOwners(false, fixed, params, owners, bounds, counts, offsets, &.{}, 0, states, dims, axes, domain_scale, &result);
            offsets[0] = 0;
            for (counts, 0..) |count, i| offsets[i + 1] = std.math.add(u32, offsets[i], count) catch return error.SpeckleClassificationTooLarge;
            @memset(counts, 0);
        }
        const slots = if (fixed) std.math.mul(usize, bounds.count, 9) catch return error.SpeckleClassificationTooLarge else offsets[bounds.count];
        try directClassifiedCharge(&live, slots, (if (fixed) @as(usize, 2) else 3) * @sizeOf(F));
        const coordinates = try allocator.alloc(F, slots * (if (fixed) @as(usize, 2) else 3));
        errdefer allocator.free(coordinates);
        @memset(coordinates, 0);
        @memset(coordinates[0..slots], std.math.inf(F));
        visitBinnedOwners(true, fixed, params, owners, bounds, counts, offsets, coordinates, slots, states, dims, axes, domain_scale, &result);
        result.states = states;
        result.coordinates = coordinates;
        result.record_count = slots;
        result.counts = counts;
        result.offsets = offsets;

        result.empty = result.active_owners == 0;
        result.peak_bytes = live;
        return result;
    }

    fn visitBinnedOwners(comptime assign: bool, comptime fixed: bool, params: Speckle2DParams, owners: Original.SpeckleCellBounds, bounds: Original.SpeckleCellBounds, counts: []u8, offsets: []const u32, coordinates: []F, slots: usize, states: []u16, dims: [2]usize, axes: [2]Original.SpeckleClassificationAxis, domain_scale: F, result: *DirectClassifiedSpeckle2D) void {
        for (0..owners.dims[1]) |oy| {
            for (0..owners.dims[0]) |ox| {
                result.owner_visits += 1;
                const owner: [2]i64 = .{ owners.min[0] + @as(i64, @intCast(ox)), owners.min[1] + @as(i64, @intCast(oy)) };
                const disk = Original.speckleDiskForCell(false, owner[0], owner[1], params) orelse continue;
                if (assign) result.active_owners += 1;
                var local_slots: [9]i8 = @splat(-1);
                var yy = @max(0, owner[1] - 1);
                while (yy <= @min(bounds.max[1], owner[1] + 1)) : (yy += 1) {
                    var xx = @max(0, owner[0] - 1);
                    while (xx <= @min(bounds.max[0], owner[0] + 1)) : (xx += 1) {
                        const lo: [2]F = .{ @floatFromInt(xx), @floatFromInt(yy) };
                        const hi: [2]F = .{ @min(lo[0] + 1, params.cells_per_uv[0]), @min(lo[1] + 1, params.cells_per_uv[1]) };
                        const dx = @max(lo[0], @min(hi[0], disk.center[0])) - disk.center[0];
                        const dy = @max(lo[1], @min(hi[1], disk.center[1])) - disk.center[1];
                        if (dx * dx + dy * dy > disk.radius * disk.radius) continue;
                        const cell = @as(usize, @intCast(yy)) * bounds.dims[0] + @as(usize, @intCast(xx));
                        std.debug.assert(counts[cell] < 9);
                        if (assign) {
                            local_slots[@as(usize, @intCast((yy - owner[1] + 1) * 3 + xx - owner[0] + 1))] = @intCast(counts[cell]);
                            const target = (if (fixed) cell * 9 else offsets[cell]) + counts[cell];
                            coordinates[target] = disk.center[0];
                            coordinates[slots + target] = disk.center[1];
                            if (!fixed) coordinates[2 * slots + target] = disk.radius * disk.radius;
                        }
                        counts[cell] += 1;
                    }
                }
                if (assign) Original.stampSpeckleDiskClassificationMapped(true, states, dims, axes, domain_scale, owner, disk, local_slots);
            }
        }
    }

    inline fn record(comptime fixed: bool, data: *const DirectClassifiedSpeckle2D, index: usize) [3]F {
        return .{ data.coordinates[index], data.coordinates[data.record_count + index], if (fixed) data.radius2 else data.coordinates[2 * data.record_count + index] };
    }

    inline fn hit(r: [3]F, px: F, py: F) bool {
        const dx = px - r[0];
        const dy = py - r[1];
        return dx * dx + dy * dy < r[2];
    }

    fn scalarFallback(comptime fixed: bool, px: F, py: F, state: u32, micro_x: usize, micro_y: usize, data: *const DirectClassifiedSpeckle2D) bool {
        const cell = (micro_y / R) * data.cell_dims[0] + micro_x / R;
        const start: usize = if (fixed) cell * 9 else data.offsets[cell];
        var mask: u16 = @intCast(state);
        while (mask != 0) {
            const bit = @ctz(mask);
            mask &= mask - 1;
            if (hit(record(fixed, data, start + bit), px, py)) return true;
        }
        return false;
    }

    fn sampleScal(u: F, v: F, data: *const DirectClassifiedSpeckle2D) F {
        const p = data.params;
        if (data.empty or p.foreground == p.background or !std.math.isFinite(u) or !std.math.isFinite(v)) return p.background;
        const px = @max(0.0, @min(1.0, u)) * p.cells_per_uv[0];
        const py = @max(0.0, @min(1.0, v)) * p.cells_per_uv[1];
        const x: usize = @intFromFloat(px * speckle_mask_samples_per_cell);
        const y: usize = @intFromFloat(py * speckle_mask_samples_per_cell);
        const state: u32 = data.states[y * data.dims[0] + x];
        const foreground: u32 = 512;
        const covered = if (state == foreground) true else if (state == 0) false else if (data.fixed_radius) scalarFallback(true, px, py, state, x, y, data) else scalarFallback(false, px, py, state, x, y, data);
        return Original.speckleCoverageEndpointValue(p, if (covered) 1 else 0);
    }

    inline fn sampleSIMD(u: VecSF, v: VecSF, active: VecSB, data: *const DirectClassifiedSpeckle2D) VecSF {
        if (data.fixed_radius) return sampleSIMDImpl(true, u, v, active, data);
        return sampleSIMDImpl(false, u, v, active, data);
    }

    fn sampleSIMDImpl(comptime fixed: bool, u: VecSF, v: VecSF, active: VecSB, data: *const DirectClassifiedSpeckle2D) VecSF {
        const p = data.params;
        const bg: VecSF = @splat(p.background);
        if (data.empty or p.foreground == p.background) return bg;
        const zero: VecSF = @splat(0);
        const one: VecSF = @splat(1);
        const inf: VecSF = @splat(std.math.inf(F));
        const valid = active & (@abs(u) < inf) & (@abs(v) < inf);
        const px = @max(zero, @min(one, @select(F, valid, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
        const py = @max(zero, @min(one, @select(F, valid, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
        // Preparation bounds each microcell axis by 134,217,728. Preserve
        // the p*R rounding, convert to signed i32, then widen before products.
        const xs32: @Vector(S, i32) = @intFromFloat(px * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
        const ys32: @Vector(S, i32) = @intFromFloat(py * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
        const xs: [S]usize = @as(@Vector(S, usize), @intCast(xs32));
        const ys: [S]usize = @as(@Vector(S, usize), @intCast(ys32));
        const State = u16;
        const foreground: State = 512;
        var states: [S]State = undefined;
        inline for (0..S) |lane| {
            const micro = ys[lane] * data.dims[0] + xs[lane];
            states[lane] = data.states[micro];
        }
        const state_vec: @Vector(S, State) = states;
        var covered = valid & (state_vec == @as(@Vector(S, State), @splat(foreground)));
        const ambiguous = valid & (state_vec != @as(@Vector(S, State), @splat(0))) & (state_vec != @as(@Vector(S, State), @splat(foreground)));
        const amb: [S]bool = ambiguous;
        if (@reduce(.Or, ambiguous)) {
            var first: usize = 0;
            while (!amb[first]) first += 1;
            const first_cell = (ys[first] / R) * data.cell_dims[0] + xs[first] / R;
            var coherent = true;
            var union_mask: u16 = 0;
            inline for (0..S) |lane| {
                if (amb[lane]) {
                    coherent = coherent and (ys[lane] / R) * data.cell_dims[0] + xs[lane] / R == first_cell;
                    union_mask |= states[lane];
                }
            }
            if (coherent) {
                const base: usize = if (fixed) first_cell * 9 else data.offsets[first_cell];
                while (union_mask != 0) {
                    const bit = @ctz(union_mask);
                    union_mask &= union_mask - 1;
                    const r = record(fixed, data, base + bit);
                    const dx = px - @as(VecSF, @splat(r[0]));
                    const dy = py - @as(VecSF, @splat(r[1]));
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, @splat(r[2])));
                }
            } else {
                var hits: [S]bool = covered;
                inline for (0..S) |lane| if (amb[lane]) {
                    hits[lane] = scalarFallback(fixed, px[lane], py[lane], states[lane], xs[lane], ys[lane], data);
                };
                covered = hits;
            }
        }
        const coverage = @select(F, covered, one, zero);
        return @select(F, valid, bg + coverage * @as(VecSF, @splat(p.foreground - p.background)), bg);
    }
};

/// Coefficient ownership for bin-local rectangular classification.
pub const ClassifiedBinPayload = struct {
    params: Speckle2DParams,
    dims: [2]usize,
    cell_dims: [2]usize,
    owner_dims: [2]usize,
    coordinates: []const F = &.{},
    record_count: usize = 0,
    radius2: F,
    fixed_radius: bool,
    empty: bool = true,
    owner_visits: usize = 0,
    active_owners: usize = 0,
    peak_bytes: usize = 0,
};

/// R8 x R4 certificates, FG32 / AMB32, with ordinary full-bin record indexing.
pub const RectBinClassifiedSpeckle2D = struct {
    payload: ClassifiedBinPayload,
    headers: []const u64,
    counts: []const u8,
    offsets: []const u32,

    pub fn byteSize(self: @This()) usize {
        return self.headers.len * @sizeOf(u64) + self.payload.coordinates.len * @sizeOf(F) + self.counts.len + self.offsets.len * @sizeOf(u32);
    }

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.payload.coordinates);
        allocator.free(self.counts);
        allocator.free(self.offsets);
    }
};

// The accepted scalar classifier is frozen. The rectangular writer uses this predicate,
// with the same arithmetic but a radius squared computed once per owner visit.
fn classifyBinMicrocell(disk: SpeckleDisk2D, radius2: F, box_min: [2]F, box_max: [2]F) SpeckleClassificationState {
    const far_x = @max(@abs(box_min[0] - disk.center[0]), @abs(box_max[0] - disk.center[0]));
    const far_y = @max(@abs(box_min[1] - disk.center[1]), @abs(box_max[1] - disk.center[1]));
    if (disk.radius > 0.0 and far_x * far_x + far_y * far_y < radius2) return .foreground;
    const min_x = @max(@as(F, 0.0), @max(box_min[0] - disk.center[0], disk.center[0] - box_max[0]));
    const min_y = @max(@as(F, 0.0), @max(box_min[1] - disk.center[1], disk.center[1] - box_max[1]));
    return if (min_x * min_x + min_y * min_y <= radius2) .ambiguous else .background;
}

const Classified42 = struct {
    const Rx: u8 = 8;
    const Ry: u8 = 4;
    const Mask = u32;
    const Shift = std.math.Log2Int(Mask);
    const Data = RectBinClassifiedSpeckle2D;
    const Original = Implementation(.classified_indexed);
    const Axes = struct { x: Original.ClassificationAxis(Rx), y: Original.ClassificationAxis(Ry) };
    const scratch_bytes: usize = Original.speckle_classification_boundary_cache_capacity * @sizeOf(F) + 64;

    fn generate(allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        try params.validateResolved(.classified_binned_42);
        return if (params.radius_jitter == 0) generateImpl(true, allocator, params) else generateImpl(false, allocator, params);
    }

    fn generateImpl(comptime fixed: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        const dims_x = Original.classifiedDimsAtResolution(Rx, params) orelse return error.SpeckleClassificationTooLarge;
        const dims_y = Original.classifiedDimsAtResolution(Ry, params) orelse return error.SpeckleClassificationTooLarge;
        const dims = [2]usize{ dims_x[0], dims_y[1] };
        const n = std.math.mul(usize, dims[0], dims[1]) catch return error.SpeckleClassificationTooLarge;
        if (n > max_speckle_classification_bytes / @sizeOf(u16)) return error.SpeckleClassificationTooLarge;
        const bounds = Original.speckleProceduralCellBounds(params, 0) orelse return error.SpeckleClassificationTooLarge;
        const owners = Original.speckleProceduralCellBounds(params, 1) orelse return error.SpeckleClassificationTooLarge;
        if (owners.count > max_speckle_cells) return error.SpeckleClassificationTooLarge;
        const planes: usize = if (fixed) 2 else 3;
        var live: usize = 0;
        try directClassifiedCharge(&live, bounds.count, @sizeOf(u64));
        try directClassifiedCharge(&live, 1, scratch_bytes);
        const fixed_slots: usize = if (fixed) std.math.mul(usize, bounds.count, 9) catch return error.SpeckleClassificationTooLarge else 0;
        if (fixed) try directClassifiedCharge(&live, fixed_slots, planes * @sizeOf(F));
        const counts_len: usize = bounds.count;
        const offsets_len: usize = if (fixed) 0 else std.math.add(usize, bounds.count, 1) catch return error.SpeckleClassificationTooLarge;
        try directClassifiedCharge(&live, counts_len, @sizeOf(u8));
        try directClassifiedCharge(&live, offsets_len, @sizeOf(u32));
        const headers = try allocator.alloc(u64, bounds.count);
        errdefer allocator.free(headers);
        @memset(headers, 0);
        const counts: []u8 = try allocator.alloc(u8, counts_len);
        errdefer allocator.free(counts);
        @memset(counts, 0);
        const offsets: []u32 = if (fixed) &.{} else try allocator.alloc(u32, offsets_len);
        errdefer allocator.free(offsets);
        var data: ClassifiedBinPayload = .{ .params = params, .dims = dims, .cell_dims = bounds.dims, .owner_dims = owners.dims, .radius2 = params.radius_mean * params.radius_mean, .fixed_radius = fixed };
        var axes: Axes = .{ .x = .{ .dim = dims[0], .cells_per_uv = params.cells_per_uv[0] }, .y = .{ .dim = dims[1], .cells_per_uv = params.cells_per_uv[1] } };
        var cache: [Original.speckle_classification_boundary_cache_capacity]F = undefined;
        var cached: usize = 0;
        var domain_scale: F = 1;
        inline for (.{ "x", "y" }) |axis_name| {
            const axis = &@field(axes, axis_name);
            domain_scale = @max(domain_scale, @max(@abs(axis.boundary(0)), @abs(axis.upperBound(axis.dim))));
            const len = axis.dim + 1;
            if (len <= cache.len - cached) {
                const boundaries = cache[cached..][0..len];
                for (boundaries, 0..) |*boundary, i| boundary.* = axis.boundary(i);
                axis.cached_boundaries = boundaries;
                cached += len;
            }
        }
        var slots: usize = fixed_slots;
        if (!fixed) {
            visitBinned(false, fixed, params, owners, bounds, headers, counts, offsets, &.{}, 0, axes, domain_scale, &data);

            offsets[0] = 0;
            for (counts, 0..) |amount, cell| offsets[cell + 1] = std.math.add(u32, offsets[cell], amount) catch return error.SpeckleClassificationTooLarge;
            slots = offsets[bounds.count];
            @memset(counts, 0);

            try directClassifiedCharge(&live, slots, planes * @sizeOf(F));
        }
        const coordinates = try allocator.alloc(F, slots * planes);
        errdefer allocator.free(coordinates);
        if (fixed) {
            @memset(coordinates[0..slots], std.math.inf(F));
            @memset(coordinates[slots..], 0);
        }
        visitBinned(true, fixed, params, owners, bounds, headers, counts, offsets, coordinates, slots, axes, domain_scale, &data);
        data.coordinates = coordinates;
        data.record_count = slots;
        data.empty = data.active_owners == 0;
        data.peak_bytes = live;
        return .{ .payload = data, .headers = headers, .counts = counts, .offsets = offsets };
    }

    fn visitBinned(comptime assign: bool, comptime fixed: bool, params: Speckle2DParams, owners: Original.SpeckleCellBounds, bounds: Original.SpeckleCellBounds, headers: []u64, counts: []u8, offsets: []const u32, coordinates: []F, slots: usize, axes: Axes, domain_scale: F, data: *ClassifiedBinPayload) void {
        for (0..owners.dims[1]) |oy| {
            for (0..owners.dims[0]) |ox| {
                data.owner_visits += 1;
                const owner: [2]i64 = .{ owners.min[0] + @as(i64, @intCast(ox)), owners.min[1] + @as(i64, @intCast(oy)) };
                const disk = Original.speckleDiskForCell(false, owner[0], owner[1], params) orelse continue;
                const radius2 = disk.radius * disk.radius;
                if (assign) data.active_owners += 1;
                var yy = @max(0, owner[1] - 1);
                while (yy <= @min(bounds.max[1], owner[1] + 1)) : (yy += 1) {
                    var xx = @max(0, owner[0] - 1);
                    while (xx <= @min(bounds.max[0], owner[0] + 1)) : (xx += 1) {
                        const lo: [2]F = .{ @floatFromInt(xx), @floatFromInt(yy) };
                        const hi: [2]F = .{ @min(lo[0] + 1, params.cells_per_uv[0]), @min(lo[1] + 1, params.cells_per_uv[1]) };
                        const dx = @max(lo[0], @min(hi[0], disk.center[0])) - disk.center[0];
                        const dy = @max(lo[1], @min(hi[1], disk.center[1])) - disk.center[1];
                        if (dx * dx + dy * dy > radius2) continue;
                        const cell = @as(usize, @intCast(yy)) * bounds.dims[0] + @as(usize, @intCast(xx));
                        const amount = counts[cell];
                        std.debug.assert(amount < 9);
                        if (assign) {
                            const target = (if (fixed) cell * 9 else offsets[cell]) + amount;
                            coordinates[target] = disk.center[0];
                            coordinates[slots + target] = disk.center[1];
                            if (!fixed) coordinates[2 * slots + target] = radius2;
                        }
                        counts[cell] = amount + 1;
                    }
                }
                if (assign) stamp(headers, bounds.dims[0], axes, domain_scale, owner, disk, radius2);
            }
        }
    }

    fn stamp(headers: []u64, stride: usize, axes: Axes, domain_scale: F, owner: [2]i64, disk: SpeckleDisk2D, radius2: F) void {
        const center_scale = @max(@abs(disk.center[0]), @abs(disk.center[1]));
        const max_margin = 16.0 * std.math.floatEps(F) * @max(domain_scale, center_scale);
        const stamp_radius = disk.radius + 4.0 * max_margin;
        const yr = Original.speckleClassificationAxisRangeAtResolution(Ry, disk.center[1] - stamp_radius, disk.center[1] + stamp_radius, axes.y) orelse return;
        const xr = Original.speckleClassificationAxisRangeAtResolution(Rx, disk.center[0] - stamp_radius, disk.center[0] + stamp_radius, axes.x) orelse return;
        for (yr.min..yr.max + 1) |yy| {
            if (Original.classificationAxisMaskAtResolution(Ry, yy, owner[1], 1) == 0) continue;
            const min_y = axes.y.boundary(yy);
            const max_y = axes.y.upperBound(yy + 1);
            var xx = xr.min;
            while (xx <= xr.max) {
                const column = xx / Rx;
                const stop = @min(xr.max + 1, (column + 1) * Rx);
                if (Original.classificationAxisMaskAtResolution(Rx, xx, owner[0], 3) == 0) {
                    xx = stop;
                    continue;
                }
                const cell = (yy / Ry) * stride + column;
                const word = headers[cell];
                const old_fg: Mask = @truncate(word);
                const old_amb: Mask = @truncate(word >> @bitSizeOf(Mask));
                var fragment_fg: Mask = 0;
                var fragment_amb: Mask = 0;
                while (xx < stop) : (xx += 1) {
                    const shift: Shift = @intCast((yy % Ry) * Rx + xx % Rx);
                    const bit = @as(Mask, 1) << shift;
                    if (old_fg & bit != 0) continue;
                    const state = classifyBinMicrocell(disk, radius2, .{ axes.x.boundary(xx), min_y }, .{ axes.x.upperBound(xx + 1), max_y });
                    if (state == .foreground) fragment_fg |= bit else if (state == .ambiguous) fragment_amb |= bit;
                }
                const next_fg = old_fg | fragment_fg;
                const next_amb = (old_amb | fragment_amb) & ~next_fg;
                const class_word = @as(u64, next_fg) | (@as(u64, next_amb) << @bitSizeOf(Mask));
                headers[cell] = class_word;
            }
        }
    }

    inline fn record(comptime fixed: bool, data: *const ClassifiedBinPayload, index: usize) [3]F {
        return .{ data.coordinates[index], data.coordinates[data.record_count + index], if (fixed) data.radius2 else data.coordinates[2 * data.record_count + index] };
    }

    fn sampleScal(u: F, v: F, data: *const Data) F {
        return if (data.payload.fixed_radius) sampleScalarImpl(true, u, v, data) else sampleScalarImpl(false, u, v, data);
    }

    fn sampleScalarImpl(comptime fixed: bool, u: F, v: F, data: *const Data) F {
        const bins = &data.payload;
        const p = bins.params;
        if (bins.empty or p.foreground == p.background or !std.math.isFinite(u) or !std.math.isFinite(v)) return p.background;
        const px = @max(0.0, @min(1.0, u)) * p.cells_per_uv[0];
        const py = @max(0.0, @min(1.0, v)) * p.cells_per_uv[1];
        const x: usize = @intFromFloat(px * @as(F, Rx));
        const y: usize = @intFromFloat(py * @as(F, Ry));
        const cell = (y / Ry) * bins.cell_dims[0] + x / Rx;
        const word = data.headers[cell];
        const Class = u64;
        const shift: std.math.Log2Int(Class) = @intCast((y % Ry) * Rx + x % Rx);
        const flags = @as(Class, @truncate(word)) >> shift;
        var covered = flags & 1 != 0;
        if (flags & (@as(Class, 1) << @bitSizeOf(Mask)) != 0) {
            const start = (if (fixed) cell * 9 else data.offsets[cell]);
            for (0..data.counts[cell]) |j| {
                const r = record(fixed, bins, start + j);
                const dx = px - r[0];
                const dy = py - r[1];
                if (dx * dx + dy * dy < r[2]) {
                    covered = true;
                    break;
                }
            }
        }
        return Original.speckleCoverageEndpointValue(p, if (covered) 1 else 0);
    }

    inline fn sampleSIMD(u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        return if (data.payload.fixed_radius) sampleSIMDImpl(true, u, v, active, data) else sampleSIMDImpl(false, u, v, active, data);
    }

    fn sampleSIMDImpl(comptime fixed: bool, u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        const bins = &data.payload;
        const p = bins.params;
        const bg: VecSF = @splat(p.background);
        if (bins.empty or p.foreground == p.background) return bg;
        const zero: VecSF = @splat(0);
        const one: VecSF = @splat(1);
        const inf: VecSF = @splat(std.math.inf(F));
        const valid = active & (@abs(u) < inf) & (@abs(v) < inf);
        const px = @max(zero, @min(one, @select(F, valid, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
        const py = @max(zero, @min(one, @select(F, valid, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
        const xs32: @Vector(S, i32) = @intFromFloat(px * @as(VecSF, @splat(@as(F, Rx))));
        const ys32: @Vector(S, i32) = @intFromFloat(py * @as(VecSF, @splat(@as(F, Ry))));
        const xs: [S]usize = @as(@Vector(S, usize), @intCast(xs32));
        const ys: [S]usize = @as(@Vector(S, usize), @intCast(ys32));
        const Class = u64;
        var cells: [S]usize = undefined;
        var words: [S]u64 = undefined;
        var classes: [S]Class = undefined;
        var shifts: [S]Class = undefined;
        inline for (0..S) |lane| {
            cells[lane] = (ys[lane] / Ry) * bins.cell_dims[0] + xs[lane] / Rx;
            words[lane] = data.headers[cells[lane]];
            classes[lane] = @truncate(words[lane]);
            shifts[lane] = @intCast((ys[lane] % Ry) * Rx + xs[lane] % Rx);
        }
        const flags = @as(@Vector(S, Class), classes) >> @as(@Vector(S, std.math.Log2Int(Class)), @intCast(@as(@Vector(S, Class), shifts)));
        var covered = valid & ((flags & @as(@Vector(S, Class), @splat(1))) != @as(@Vector(S, Class), @splat(0)));
        const ambiguous = valid & ((flags & @as(@Vector(S, Class), @splat(@as(Class, 1) << @bitSizeOf(Mask)))) != @as(@Vector(S, Class), @splat(0)));
        if (@reduce(.Or, ambiguous)) {
            var coherent = true;
            for (1..S) |lane| coherent = coherent and cells[lane] == cells[0];
            if (coherent) {
                const start = (if (fixed) cells[0] * 9 else data.offsets[cells[0]]);
                for (0..data.counts[cells[0]]) |j| {
                    const r = record(fixed, bins, start + j);
                    const dx = px - @as(VecSF, @splat(r[0]));
                    const dy = py - @as(VecSF, @splat(r[1]));
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, @splat(r[2])));
                }
            } else {
                var starts: [S]usize = undefined;
                var counts: [S]u8 = undefined;
                var max_count: u8 = 0;
                inline for (0..S) |lane| {
                    starts[lane] = (if (fixed) cells[lane] * 9 else data.offsets[cells[lane]]);
                    counts[lane] = data.counts[cells[lane]];
                    max_count = @max(max_count, counts[lane]);
                }
                for (0..max_count) |j| {
                    var rx: [S]F = @splat(std.math.inf(F));
                    var ry: [S]F = @splat(0);
                    var rr: [S]F = @splat(if (fixed) bins.radius2 else 0);
                    inline for (0..S) |lane| {
                        if (fixed or j < counts[lane]) {
                            const r = record(fixed, bins, starts[lane] + j);
                            rx[lane] = r[0];
                            ry[lane] = r[1];
                            if (!fixed) rr[lane] = r[2];
                        }
                    }
                    const dx = px - @as(VecSF, rx);
                    const dy = py - @as(VecSF, ry);
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, rr));
                }
            }
        }
        const coverage = @select(F, covered, one, zero);
        return @select(F, valid, bg + coverage * @as(VecSF, @splat(p.foreground - p.background)), bg);
    }
};

// Fixed resources call retained42 before any variable grouped-classification work.
const Classified46 = struct {
    const Data = RectBinClassifiedSpeckle2D;
    const Rx = Classified42.Rx;
    const Ry = Classified42.Ry;
    const Mask = Classified42.Mask;
    const record = Classified42.record;
    inline fn sampleSIMD(u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        if (data.payload.fixed_radius) return Classified42.sampleSIMD(u, v, active, data);
        return sampleVariable(u, v, active, data);
    }
    fn sampleVariable(u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        const fixed = false;
        const bins = &data.payload;
        const p = bins.params;
        const bg: VecSF = @splat(p.background);
        if (bins.empty or p.foreground == p.background) return bg;
        const zero: VecSF = @splat(0);
        const one: VecSF = @splat(1);
        const inf: VecSF = @splat(std.math.inf(F));
        const valid = active & (@abs(u) < inf) & (@abs(v) < inf);
        const px = @max(zero, @min(one, @select(F, valid, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
        const py = @max(zero, @min(one, @select(F, valid, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
        const xs32: @Vector(S, i32) = @intFromFloat(px * @as(VecSF, @splat(@as(F, Rx))));
        const ys32: @Vector(S, i32) = @intFromFloat(py * @as(VecSF, @splat(@as(F, Ry))));
        const xs: [S]usize = @as(@Vector(S, usize), @intCast(xs32));
        const ys: [S]usize = @as(@Vector(S, usize), @intCast(ys32));
        const Class = u64;
        var cells: [S]usize = undefined;
        var words: [S]u64 = undefined;
        var classes: [S]Class = undefined;
        var shifts: [S]Class = undefined;
        inline for (0..S) |lane| {
            cells[lane] = (ys[lane] / Ry) * bins.cell_dims[0] + xs[lane] / Rx;
            words[lane] = data.headers[cells[lane]];
            classes[lane] = @truncate(words[lane]);
            shifts[lane] = @intCast((ys[lane] % Ry) * Rx + xs[lane] % Rx);
        }
        const flags = @as(@Vector(S, Class), classes) >> @as(@Vector(S, std.math.Log2Int(Class)), @intCast(@as(@Vector(S, Class), shifts)));
        var covered = valid & ((flags & @as(@Vector(S, Class), @splat(1))) != @as(@Vector(S, Class), @splat(0)));
        const ambiguous = valid & ((flags & @as(@Vector(S, Class), @splat(@as(Class, 1) << @bitSizeOf(Mask)))) != @as(@Vector(S, Class), @splat(0)));
        if (@reduce(.Or, ambiguous)) {
            var coherent = true;
            for (1..S) |lane| coherent = coherent and cells[lane] == cells[0];
            if (coherent) {
                const start = (if (fixed) cells[0] * 9 else data.offsets[cells[0]]);
                for (0..data.counts[cells[0]]) |j| {
                    const r = record(fixed, bins, start + j);
                    const dx = px - @as(VecSF, @splat(r[0]));
                    const dy = py - @as(VecSF, @splat(r[1]));
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, @splat(r[2])));
                }
            } else {
                covered |= groupHits(S, px, py, cells, ambiguous, bins, data);
            }
        }
        const coverage = @select(F, covered, one, zero);
        return @select(F, valid, bg + coverage * @as(VecSF, @splat(p.foreground - p.background)), bg);
    }
    inline fn groupHits(comptime W: usize, px: @Vector(W, F), py: @Vector(W, F), cells: [W]usize, ambiguous: @Vector(W, bool), bins: *const ClassifiedBinPayload, data: *const RectBinClassifiedSpeckle2D) @Vector(W, bool) {
        const V = @Vector(W, F);
        const Bits = std.meta.Int(.unsigned, W);
        var remaining: Bits = @bitCast(ambiguous);
        var hits: @Vector(W, bool) = @splat(false);
        while (remaining != 0) {
            const first: usize = @ctz(remaining);
            const cell = cells[first];
            const same = @as(@Vector(W, usize), cells) == @as(@Vector(W, usize), @splat(cell));
            const group = remaining & @as(Bits, @bitCast(same));
            const members: @Vector(W, bool) = @bitCast(group);
            const start = data.offsets[cell];
            for (0..data.counts[cell]) |j| {
                const r = Classified42.record(false, bins, start + j);
                const dx = px - @as(V, @splat(r[0]));
                const dy = py - @as(V, @splat(r[1]));
                hits |= members & (dx * dx + dy * dy < @as(V, @splat(r[2])));
            }
            remaining &= ~group;
        }
        return hits;
    }
};

// Generation-only bins-first preparation. Sampling canonicalizes to retained46.
// Reachable-domain clipping changes terminal certificates, never the analytic field.
const Classified49 = struct {
    const Rx = Classified42.Rx;
    const Ry = Classified42.Ry;
    const Data = RectBinClassifiedSpeckle2D;
    const Original = Implementation(.classified_indexed);
    const record = Classified42.record;
    const scratch_bytes: usize = Original.speckle_classification_boundary_cache_capacity * @sizeOf(F) + 1024;

    fn generate(allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        try params.validateResolved(.classified_binned_49);
        return if (params.radius_jitter == 0) generateImpl(true, allocator, params) else generateImpl(false, allocator, params);
    }

    fn generateImpl(comptime fixed: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        const dims_x = Original.classifiedDimsAtResolution(Rx, params) orelse return error.SpeckleClassificationTooLarge;
        const dims_y = Original.classifiedDimsAtResolution(Ry, params) orelse return error.SpeckleClassificationTooLarge;
        const dims = [2]usize{ dims_x[0], dims_y[1] };
        const n = std.math.mul(usize, dims[0], dims[1]) catch return error.SpeckleClassificationTooLarge;
        if (n > max_speckle_classification_bytes / @sizeOf(u16)) return error.SpeckleClassificationTooLarge;
        const bounds = Original.speckleProceduralCellBounds(params, 0) orelse return error.SpeckleClassificationTooLarge;
        const owners = Original.speckleProceduralCellBounds(params, 1) orelse return error.SpeckleClassificationTooLarge;
        if (owners.count > max_speckle_cells) return error.SpeckleClassificationTooLarge;
        const planes: usize = if (fixed) 2 else 3;
        var live: usize = 0;
        try directClassifiedCharge(&live, bounds.count, @sizeOf(u64));
        try directClassifiedCharge(&live, 1, scratch_bytes);
        const fixed_slots: usize = if (fixed) std.math.mul(usize, bounds.count, 9) catch return error.SpeckleClassificationTooLarge else 0;
        if (fixed) try directClassifiedCharge(&live, fixed_slots, planes * @sizeOf(F));
        const counts_len: usize = bounds.count;
        const offsets_len: usize = if (fixed) 0 else std.math.add(usize, bounds.count, 1) catch return error.SpeckleClassificationTooLarge;
        try directClassifiedCharge(&live, counts_len, @sizeOf(u8));
        try directClassifiedCharge(&live, offsets_len, @sizeOf(u32));
        const headers = try allocator.alloc(u64, bounds.count);
        errdefer allocator.free(headers);
        @memset(headers, 0);
        const counts: []u8 = try allocator.alloc(u8, counts_len);
        errdefer allocator.free(counts);
        @memset(counts, 0);
        const offsets: []u32 = if (fixed) &.{} else try allocator.alloc(u32, offsets_len);
        errdefer allocator.free(offsets);
        var data: ClassifiedBinPayload = .{ .params = params, .dims = dims, .cell_dims = bounds.dims, .owner_dims = owners.dims, .radius2 = params.radius_mean * params.radius_mean, .fixed_radius = fixed };
        var slots: usize = fixed_slots;
        if (!fixed) {
            visitBinned(false, fixed, params, owners, bounds, counts, offsets, &.{}, 0, &data);

            offsets[0] = 0;
            for (counts, 0..) |amount, cell| offsets[cell + 1] = std.math.add(u32, offsets[cell], amount) catch return error.SpeckleClassificationTooLarge;
            slots = offsets[bounds.count];
            @memset(counts, 0);

            try directClassifiedCharge(&live, slots, planes * @sizeOf(F));
        }
        const coordinates = try allocator.alloc(F, slots * planes);
        errdefer allocator.free(coordinates);
        if (fixed) {
            @memset(coordinates[0..slots], std.math.inf(F));
            @memset(coordinates[slots..], 0);
        }
        visitBinned(true, fixed, params, owners, bounds, counts, offsets, coordinates, slots, &data);
        data.coordinates = coordinates;
        data.record_count = slots;
        data.empty = data.active_owners == 0;
        data.peak_bytes = live;
        const result: Data = .{ .payload = data, .headers = headers, .counts = counts, .offsets = offsets };
        classifyBins(fixed, &result, headers);
        return result;
    }

    fn visitBinned(comptime assign: bool, comptime fixed: bool, params: Speckle2DParams, owners: Original.SpeckleCellBounds, bounds: Original.SpeckleCellBounds, counts: []u8, offsets: []const u32, coordinates: []F, slots: usize, data: *ClassifiedBinPayload) void {
        for (0..owners.dims[1]) |oy| {
            for (0..owners.dims[0]) |ox| {
                data.owner_visits += 1;
                const owner: [2]i64 = .{ owners.min[0] + @as(i64, @intCast(ox)), owners.min[1] + @as(i64, @intCast(oy)) };
                const disk = Original.speckleDiskForCell(false, owner[0], owner[1], params) orelse continue;
                const radius2 = disk.radius * disk.radius;
                if (assign) data.active_owners += 1;
                var yy = @max(0, owner[1] - 1);
                while (yy <= @min(bounds.max[1], owner[1] + 1)) : (yy += 1) {
                    var xx = @max(0, owner[0] - 1);
                    while (xx <= @min(bounds.max[0], owner[0] + 1)) : (xx += 1) {
                        const lo: [2]F = .{ @floatFromInt(xx), @floatFromInt(yy) };
                        const hi: [2]F = .{ @min(lo[0] + 1, params.cells_per_uv[0]), @min(lo[1] + 1, params.cells_per_uv[1]) };
                        const dx = @max(lo[0], @min(hi[0], disk.center[0])) - disk.center[0];
                        const dy = @max(lo[1], @min(hi[1], disk.center[1])) - disk.center[1];
                        if (dx * dx + dy * dy > radius2) continue;
                        const cell = @as(usize, @intCast(yy)) * bounds.dims[0] + @as(usize, @intCast(xx));
                        const amount = counts[cell];
                        std.debug.assert(amount < 9);
                        if (assign) {
                            const target = (if (fixed) cell * 9 else offsets[cell]) + amount;
                            coordinates[target] = disk.center[0];
                            coordinates[slots + target] = disk.center[1];
                            if (!fixed) coordinates[2 * slots + target] = radius2;
                        }
                        counts[cell] = amount + 1;
                    }
                }
            }
        }
    }

    fn classifyBins(comptime fixed: bool, data: *const Data, headers: []u64) void {
        const V = @Vector(8, F);
        const B = @Vector(8, bool);
        const bins = &data.payload;
        const p = bins.params;
        var axes: Classified42.Axes = .{ .x = .{ .dim = bins.dims[0], .cells_per_uv = p.cells_per_uv[0] }, .y = .{ .dim = bins.dims[1], .cells_per_uv = p.cells_per_uv[1] } };
        var cache: [Original.speckle_classification_boundary_cache_capacity]F = undefined;
        var cached: usize = 0;
        inline for (.{ "x", "y" }) |name| {
            const axis = &@field(axes, name);
            const len = axis.dim + 1;
            if (len <= cache.len - cached) {
                const values = cache[cached..][0..len];
                for (values, 0..) |*value, i| value.* = axis.boundary(i);
                axis.cached_boundaries = values;
                cached += len;
            }
        }
        for (data.counts, 0..) |amount, cell| {
            if (amount == 0) continue;
            const base_x = (cell % bins.cell_dims[0]) * Rx;
            const base_y = (cell / bins.cell_dims[0]) * Ry;
            var lower_x: [8]F = @splat(0);
            var upper_x: [8]F = @splat(0);
            var valid_x: [8]bool = @splat(false);
            var lower_y: [4]F = @splat(0);
            var upper_y: [4]F = @splat(0);
            var valid_y: [4]bool = @splat(false);
            for (0..8) |lane| {
                const x = base_x + lane;
                if (x < bins.dims[0]) {
                    lower_x[lane] = axes.x.boundary(x);
                    upper_x[lane] = @min(axes.x.upperBound(x + 1), p.cells_per_uv[0]);
                    valid_x[lane] = true;
                    std.debug.assert(lower_x[lane] <= upper_x[lane]);
                }
            }
            for (0..4) |row| {
                const y = base_y + row;
                if (y < bins.dims[1]) {
                    lower_y[row] = axes.y.boundary(y);
                    upper_y[row] = @min(axes.y.upperBound(y + 1), p.cells_per_uv[1]);
                    valid_y[row] = true;
                    std.debug.assert(lower_y[row] <= upper_y[row]);
                }
            }
            const start = if (fixed) cell * 9 else data.offsets[cell];
            var fg: u32 = 0;
            var amb: u32 = 0;
            for (0..amount) |j| {
                const r = record(fixed, bins, start + j);
                const center_x: V = @splat(r[0]);
                const far_x = @max(@abs(@as(V, lower_x) - center_x), @abs(@as(V, upper_x) - center_x));
                const near_x = @max(@as(V, @splat(0)), @max(@as(V, lower_x) - center_x, center_x - @as(V, upper_x)));
                const far_x2 = far_x * far_x;
                const near_x2 = near_x * near_x;
                for (0..4) |row| {
                    if (!valid_y[row]) continue;
                    const far_y = @max(@abs(lower_y[row] - r[1]), @abs(upper_y[row] - r[1]));
                    const near_y = @max(@as(F, 0), @max(lower_y[row] - r[1], r[1] - upper_y[row]));
                    // For nonnegative supported radii, r²==0 cannot pass the strict FG test.
                    const foreground: B = @as(B, valid_x) & (far_x2 + @as(V, @splat(far_y * far_y)) < @as(V, @splat(r[2])));
                    const intersect: B = @as(B, valid_x) & (near_x2 + @as(V, @splat(near_y * near_y)) <= @as(V, @splat(r[2])));
                    const shift: u5 = @intCast(row * 8);
                    fg |= @as(u32, @as(u8, @bitCast(foreground))) << shift;
                    amb = (amb | (@as(u32, @as(u8, @bitCast(intersect))) << shift)) & ~fg;
                }
            }
            headers[cell] = @as(u64, fg) | (@as(u64, amb) << 32);
        }
    }
};

/// Full-binned variants specialize classification resolution at compile time.
/// They never construct canonical resources or strips.
fn ClassifiedNext(comptime id: u8) type {
    std.debug.assert(id == 23 or id == 34);
    return struct {
        const Original = Implementation(.classified_indexed);
        const R = if (id == 34) 8 else buildconfig.speckle_mask_samples_per_cell;
        const samples: F = @floatFromInt(R);
        const foreground: u32 = 512;

        fn generate(allocator: std.mem.Allocator, params: Speckle2DParams) !DirectClassifiedSpeckle2D {
            try params.validateResolved(.classified_indexed);
            return if (params.radius_jitter == 0) generateImpl(true, allocator, params) else generateImpl(false, allocator, params);
        }

        fn generateImpl(comptime fixed: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !DirectClassifiedSpeckle2D {
            const dims = Original.classifiedDimsAtResolution(R, params) orelse return error.SpeckleClassificationTooLarge;
            const n = std.math.mul(usize, dims[0], dims[1]) catch return error.SpeckleClassificationTooLarge;
            // This also bounds each axis and its runtime microcell index to i32.
            if (n > max_speckle_classification_bytes / @sizeOf(u16)) return error.SpeckleClassificationTooLarge;
            const bounds = Original.speckleProceduralCellBounds(params, 0) orelse return error.SpeckleClassificationTooLarge;
            const owners = Original.speckleProceduralCellBounds(params, 1) orelse return error.SpeckleClassificationTooLarge;
            if (owners.count > max_speckle_cells) return error.SpeckleClassificationTooLarge;
            var live: usize = 0;
            try directClassifiedCharge(&live, n, @sizeOf(u16));
            try directClassifiedCharge(&live, Original.speckle_classification_boundary_cache_capacity, @sizeOf(F));
            const states = try allocator.alloc(u16, n);
            errdefer allocator.free(states);
            @memset(states, 0);
            var data: DirectClassifiedSpeckle2D = .{
                .params = params,
                .dims = dims,
                .cell_dims = bounds.dims,
                .owner_origin = owners.min,
                .owner_dims = owners.dims,
                .radius2 = params.radius_mean * params.radius_mean,
                .fixed_radius = fixed,
            };
            var cache: [Original.speckle_classification_boundary_cache_capacity]F = undefined;
            var cached: usize = 0;
            var axes = Original.speckleClassificationAxesAtResolution(R, dims, params);
            var domain_scale: F = 1;
            for (0..2) |axis| {
                domain_scale = @max(domain_scale, @max(@abs(axes[axis].boundary(0)), @abs(axes[axis].upperBound(dims[axis]))));
                const len = dims[axis] + 1;
                if (len <= cache.len - cached) {
                    const boundaries = cache[cached..][0..len];
                    for (boundaries, 0..) |*boundary, i| boundary.* = axes[axis].boundary(i);
                    axes[axis].cached_boundaries = boundaries;
                    cached += len;
                }
            }
            const planes: usize = if (fixed) 2 else 3;

            try directClassifiedCharge(&live, bounds.count, @sizeOf(u8));
            const counts = try allocator.alloc(u8, bounds.count);
            errdefer allocator.free(counts);
            @memset(counts, 0);
            const offsets_len: usize = if (fixed) 0 else std.math.add(usize, bounds.count, 1) catch return error.SpeckleClassificationTooLarge;
            try directClassifiedCharge(&live, offsets_len, @sizeOf(u32));
            const offsets: []u32 = if (fixed) &.{} else try allocator.alloc(u32, offsets_len);
            errdefer allocator.free(offsets);
            if (!fixed) {
                visitBinned(false, fixed, params, owners, bounds, counts, offsets, &.{}, 0, states, dims, axes, domain_scale, &data);
                offsets[0] = 0;
                for (counts, 0..) |count, i| offsets[i + 1] = std.math.add(u32, offsets[i], count) catch return error.SpeckleClassificationTooLarge;
                @memset(counts, 0);
            }
            const slots: usize = if (fixed) std.math.mul(usize, bounds.count, 9) catch return error.SpeckleClassificationTooLarge else offsets[bounds.count];
            try directClassifiedCharge(&live, slots, planes * @sizeOf(F));
            const coordinates = try allocator.alloc(F, slots * planes);
            errdefer allocator.free(coordinates);
            if (fixed) {
                // Incoherent fixed-bin SIMD intentionally loads padded slots.
                @memset(coordinates[0..slots], std.math.inf(F));
                @memset(coordinates[slots..], 0);
            }
            visitBinned(true, fixed, params, owners, bounds, counts, offsets, coordinates, slots, states, dims, axes, domain_scale, &data);
            data.states = states;
            data.counts = counts;
            data.offsets = offsets;
            data.coordinates = coordinates;
            data.record_count = slots;

            data.empty = data.active_owners == 0;
            data.peak_bytes = live;
            return data;
        }

        fn visitBinned(comptime assign: bool, comptime fixed: bool, params: Speckle2DParams, owners: Original.SpeckleCellBounds, bounds: Original.SpeckleCellBounds, counts: []u8, offsets: []const u32, coordinates: []F, slots: usize, states: []u16, dims: [2]usize, axes: [2]Original.ClassificationAxis(R), domain_scale: F, data: *DirectClassifiedSpeckle2D) void {
            // No local-slot map or map emission exists in this full-list builder.
            for (0..owners.dims[1]) |oy| {
                for (0..owners.dims[0]) |ox| {
                    data.owner_visits += 1;
                    const owner: [2]i64 = .{ owners.min[0] + @as(i64, @intCast(ox)), owners.min[1] + @as(i64, @intCast(oy)) };
                    const disk = Original.speckleDiskForCell(false, owner[0], owner[1], params) orelse continue;
                    if (assign) data.active_owners += 1;
                    var yy = @max(0, owner[1] - 1);
                    while (yy <= @min(bounds.max[1], owner[1] + 1)) : (yy += 1) {
                        var xx = @max(0, owner[0] - 1);
                        while (xx <= @min(bounds.max[0], owner[0] + 1)) : (xx += 1) {
                            const lo: [2]F = .{ @floatFromInt(xx), @floatFromInt(yy) };
                            const hi: [2]F = .{ @min(lo[0] + 1, params.cells_per_uv[0]), @min(lo[1] + 1, params.cells_per_uv[1]) };
                            const dx = @max(lo[0], @min(hi[0], disk.center[0])) - disk.center[0];
                            const dy = @max(lo[1], @min(hi[1], disk.center[1])) - disk.center[1];
                            if (dx * dx + dy * dy > disk.radius * disk.radius) continue;
                            const cell = @as(usize, @intCast(yy)) * bounds.dims[0] + @as(usize, @intCast(xx));
                            std.debug.assert(counts[cell] < 9);
                            if (assign) {
                                const target = (if (fixed) cell * 9 else @as(usize, offsets[cell])) + counts[cell];
                                coordinates[target] = disk.center[0];
                                coordinates[slots + target] = disk.center[1];
                                if (!fixed) coordinates[2 * slots + target] = disk.radius * disk.radius;
                            }
                            counts[cell] += 1;
                        }
                    }
                    if (assign) Original.stampSpeckleDiskClassificationImpl(R, false, states, dims, axes, domain_scale, owner, disk, undefined);
                }
            }
        }

        inline fn record(comptime fixed: bool, data: *const DirectClassifiedSpeckle2D, index: usize) [3]F {
            return .{ data.coordinates[index], data.coordinates[data.record_count + index], if (fixed) data.radius2 else data.coordinates[2 * data.record_count + index] };
        }

        inline fn hit(r: [3]F, px: F, py: F) bool {
            const dx = px - r[0];
            const dy = py - r[1];
            return dx * dx + dy * dy < r[2];
        }

        fn sampleScal(u: F, v: F, data: *const DirectClassifiedSpeckle2D) F {
            if (data.fixed_radius) return sampleScalarImpl(true, u, v, data);
            return sampleScalarImpl(false, u, v, data);
        }

        fn sampleScalarImpl(comptime fixed: bool, u: F, v: F, data: *const DirectClassifiedSpeckle2D) F {
            const p = data.params;
            if (data.empty or p.foreground == p.background or !std.math.isFinite(u) or !std.math.isFinite(v)) return p.background;
            const px = @max(0.0, @min(1.0, u)) * p.cells_per_uv[0];
            const py = @max(0.0, @min(1.0, v)) * p.cells_per_uv[1];
            const x: usize = @intFromFloat(px * samples);
            const y: usize = @intFromFloat(py * samples);
            const state: u32 = data.states[y * data.dims[0] + x];
            var covered = state == foreground;
            if (state != 0 and !covered) {
                const cell = (y / R) * data.cell_dims[0] + x / R;
                const base: usize = if (fixed) cell * 9 else data.offsets[cell];
                const count: usize = data.counts[cell];
                for (0..count) |j| {
                    if (hit(record(fixed, data, base + j), px, py)) {
                        covered = true;
                        break;
                    }
                }
            }
            return Original.speckleCoverageEndpointValue(p, if (covered) 1 else 0);
        }

        inline fn sampleSIMD(u: VecSF, v: VecSF, active: VecSB, data: *const DirectClassifiedSpeckle2D) VecSF {
            // One immutable layout choice precedes all lane/record work.
            if (data.fixed_radius) return sampleSIMDImpl(true, u, v, active, data);
            return sampleSIMDImpl(false, u, v, active, data);
        }

        fn sampleSIMDImpl(comptime fixed: bool, u: VecSF, v: VecSF, active: VecSB, data: *const DirectClassifiedSpeckle2D) VecSF {
            const p = data.params;
            const bg: VecSF = @splat(p.background);
            if (data.empty or p.foreground == p.background) return bg;
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const inf: VecSF = @splat(std.math.inf(F));
            const valid = active & (@abs(u) < inf) & (@abs(v) < inf);
            const px = @max(zero, @min(one, @select(F, valid, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, @select(F, valid, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
            const xs32: @Vector(S, i32) = @intFromFloat(px * @as(VecSF, @splat(samples)));
            const ys32: @Vector(S, i32) = @intFromFloat(py * @as(VecSF, @splat(samples)));
            const xs: [S]usize = @as(@Vector(S, usize), @intCast(xs32));
            const ys: [S]usize = @as(@Vector(S, usize), @intCast(ys32));
            const State = u16;
            var states: [S]State = undefined;
            inline for (0..S) |lane| {
                const micro = ys[lane] * data.dims[0] + xs[lane];
                states[lane] = data.states[micro];
            }
            const state_vec: @Vector(S, State) = states;
            var covered = valid & (state_vec == @as(@Vector(S, State), @splat(foreground)));
            const ambiguous = valid & (state_vec != @as(@Vector(S, State), @splat(0))) & (state_vec != @as(@Vector(S, State), @splat(foreground)));
            if (@reduce(.Or, ambiguous)) {
                var cells: [S]usize = undefined;
                inline for (0..S) |lane| cells[lane] = (ys[lane] / R) * data.cell_dims[0] + xs[lane] / R;
                var coherent = true;
                for (1..S) |lane| coherent = coherent and cells[lane] == cells[0];
                if (coherent) {
                    const base: usize = if (fixed) cells[0] * 9 else data.offsets[cells[0]];
                    for (0..data.counts[cells[0]]) |j| {
                        const r = record(fixed, data, base + j);
                        const dx = px - @as(VecSF, @splat(r[0]));
                        const dy = py - @as(VecSF, @splat(r[1]));
                        covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, @splat(r[2])));
                    }
                } else {
                    var starts: [S]usize = undefined;
                    var counts: [S]u8 = undefined;
                    var max_count: u8 = 0;
                    inline for (0..S) |lane| {
                        starts[lane] = if (fixed) cells[lane] * 9 else data.offsets[cells[lane]];
                        counts[lane] = data.counts[cells[lane]];
                        max_count = @max(max_count, counts[lane]);
                    }
                    for (0..max_count) |j| {
                        var rx: [S]F = @splat(std.math.inf(F));
                        var ry: [S]F = @splat(0);
                        var rr: [S]F = @splat(if (fixed) data.radius2 else 0);
                        inline for (0..S) |lane| {
                            if (fixed or j < counts[lane]) {
                                const r = record(fixed, data, starts[lane] + j);
                                rx[lane] = r[0];
                                ry[lane] = r[1];
                                if (!fixed) rr[lane] = r[2];
                            }
                        }
                        const dx = px - @as(VecSF, rx);
                        const dy = py - @as(VecSF, ry);
                        covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, rr));
                    }
                }
            }
            const coverage = @select(F, covered, one, zero);
            return @select(F, valid, bg + coverage * @as(VecSF, @splat(p.foreground - p.background)), bg);
        }
    };
}

fn Implementation(comptime config: speckleconfig.Config) type {
    return struct {
        const speckle_shape = config.pattern() orelse .disk;
        const speckle_neighbor_count = @intFromEnum(config.neighborhood() orelse speckleconfig.Neighborhood.nine);
        const evaluator = std.meta.activeTag(config);
        const configured_soft_edges = config.edges() == .soft;
        const supports_soft_edges = config.supportsSoftEdges();
        const support_radius_limit: F = if (speckle_neighbor_count == 1) 0.5 else 1.0;
        /// Prepare the configured evaluator once for reuse across frames and samples.
        /// Returned allocations belong to outer_alloc; release them through Resources.deinit
        /// or their owning static arena. Procedural cell hashing needs no allocation.
        fn generateConfiguredResources(
            outer_alloc: std.mem.Allocator,
            params: Speckle2DParams,
        ) !Resources {
            return .{ .data = switch (comptime evaluator) {
                .cell_hash, .mock => blk: {
                    try params.validateResolved(config);
                    break :blk .none;
                },
                .gradient_lattice => blk: {
                    try params.validateResolved(config);
                    break :blk .{ .perlin = try generatePerlinLattice(outer_alloc, params) };
                },
                .list_naive => .{ .list = try generateSpeckleList2D(outer_alloc, params) },
                .list_indexed => .{ .strip_list = try generateStripSpeckleList2D(outer_alloc, params) },
                .cell_binned => .{ .cell_binned = try generateCellBinnedSpeckle2D(outer_alloc, params) },
                .classified_indexed => .{
                    .classified = try generateClassifiedSpeckle2D(outer_alloc, params),
                },
                .classified_binned_22 => .{ .direct_classified = try Classified22.generate(outer_alloc, params) },
                .classified_binned_23 => .{ .direct_classified = try ClassifiedNext(23).generate(outer_alloc, params) },
                .classified_binned_34 => .{ .direct_classified = try ClassifiedNext(34).generate(outer_alloc, params) },
                .classified_binned_42 => .{ .rect_bin_classified = try Classified42.generate(outer_alloc, params) },
                .classified_binned_46 => blk: {
                    try params.validateResolved(config);
                    break :blk .{ .rect_bin_classified = if (params.radius_jitter == 0) try Classified42.generateImpl(true, outer_alloc, params) else try Classified42.generateImpl(false, outer_alloc, params) };
                },

                .classified_binned_49 => .{ .rect_bin_classified = try Classified49.generate(outer_alloc, params) },

                .direct_fixed => .{
                    .direct_fixed = try generateDirectFixedSpeckle2D(outer_alloc, params),
                },
                .mask_1bit, .mask_u8 => .{
                    .mask = try generateSpeckleMask2D(outer_alloc, params),
                },
            } };
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
            return switch (comptime evaluator) {
                .gradient_lattice => samplePerlinScal(u, v, resources.data.perlin),
                .mock => 0.5 * (u + v),
                .cell_hash => evalSpeckle2DImpl(soft_edges, u, v, params),
                .list_naive => evalSpeckleList2DNaiveImpl(soft_edges, u, v, resources.data.list),
                .list_indexed => evalStripSpeckleList2DImpl(soft_edges, u, v, resources.data.strip_list),
                .cell_binned => evalCellBinnedSpeckle2D(soft_edges, u, v, resources.data.cell_binned),
                .classified_indexed => evalClassifiedIndexedSpeckle2D(.{ u, v }, resources.data.classified),
                .classified_binned_22 => Classified22.sampleScal(u, v, &resources.data.direct_classified),
                .classified_binned_23 => ClassifiedNext(23).sampleScal(u, v, &resources.data.direct_classified),
                .classified_binned_34 => ClassifiedNext(34).sampleScal(u, v, &resources.data.direct_classified),
                .classified_binned_42 => Classified42.sampleScal(u, v, &resources.data.rect_bin_classified),
                .classified_binned_46 => Classified42.sampleScal(u, v, &resources.data.rect_bin_classified),
                .classified_binned_49 => @compileError("generation-only49 must sample through canonical Kernel46"),

                .direct_fixed => evalDirectFixedSpeckle2D(.{ u, v }, resources.data.direct_fixed),
                .mask_1bit, .mask_u8 => evalSpeckleMask2D(.{ u, v }, resources.data.mask),
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
            return switch (comptime evaluator) {
                .gradient_lattice => samplePerlinSIMD(u, v, active, resources.data.perlin),
                .mock => @as(VecSF, @splat(0.5)) * (u + v),
                .cell_hash => blk: {
                    const values = evalSpeckleSIMDImpl(soft_edges, evalSpeckle2DImpl, u, v, params, params.background);
                    break :blk if (comptime speckle_shape == .perlin)
                        @select(F, active, values, @as(VecSF, @splat(params.background)))
                    else
                        values;
                },
                .list_naive => evalSpeckleListNaiveSIMDImpl(soft_edges, u, v, resources.data.list),
                .list_indexed => blk: {
                    const strip = resources.data.strip_list;
                    if (strip.centers.len != 0) break :blk evalSpeckleSIMDImpl(soft_edges, evalFixedStripSpeckleList2DImpl, u, v, strip, strip.params.background);
                    break :blk evalSpeckleSIMDImpl(soft_edges, evalGeneralStripSpeckleList2DImpl, u, v, strip, strip.params.background);
                },
                .cell_binned => blk: {
                    const binned = resources.data.cell_binned;
                    break :blk switch (binned.records) {
                        .disks => evalCellBinnedSpeckleSIMDImpl(soft_edges, .disks, u, v, binned),
                        .strided => evalCellBinnedSpeckleSIMDImpl(soft_edges, .strided, u, v, binned),
                        .gaussian => evalCellBinnedSpeckleSIMDImpl(soft_edges, .gaussian, u, v, binned),
                    };
                },
                .classified_indexed => evalClassifiedIndexedSpeckleSIMDImpl(u, v, active, &resources.data.classified),
                .classified_binned_22 => Classified22.sampleSIMD(u, v, active, &resources.data.direct_classified),
                .classified_binned_23 => ClassifiedNext(23).sampleSIMD(u, v, active, &resources.data.direct_classified),
                .classified_binned_34 => ClassifiedNext(34).sampleSIMD(u, v, active, &resources.data.direct_classified),
                .classified_binned_42 => Classified42.sampleSIMD(u, v, active, &resources.data.rect_bin_classified),
                .classified_binned_46 => Classified46.sampleSIMD(u, v, active, &resources.data.rect_bin_classified),
                .classified_binned_49 => @compileError("generation-only49 must sample through canonical Kernel46"),

                .direct_fixed => evalDirectFixedSpeckleSIMDImpl(u, v, active, &resources.data.direct_fixed),
                .mask_1bit, .mask_u8 => evalSpeckleMaskSIMDImpl(u, v, active, &resources.data.mask),
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

        fn classifiedDims(params: Speckle2DParams) ?[2]usize {
            return classifiedDimsAtResolution(buildconfig.speckle_mask_samples_per_cell, params);
        }

        fn classifiedDimsAtResolution(comptime r: u8, params: Speckle2DParams) ?[2]usize {
            const samples: F = @floatFromInt(r);
            var dims: [2]usize = undefined;
            for (params.cells_per_uv, 0..) |cells, axis| {
                // Include the actual upper endpoint, including its own cell at integral C.
                const last = @floor(cells * samples);
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

        fn generateCellBinnedSpeckle2D(outer_alloc: std.mem.Allocator, params: Speckle2DParams) !CellBinnedSpeckle2D {
            if (params.radius_jitter == 0) return generateCellBinnedRecords(.strided, outer_alloc, params);
            if (speckle_shape == .gaussian) return generateCellBinnedRecords(.gaussian, outer_alloc, params);
            return generateCellBinnedRecords(.disks, outer_alloc, params);
        }

        const CellBinnedLayout = std.meta.Tag(CellBinnedRecords);

        fn CellBinnedRecord(comptime layout: CellBinnedLayout) type {
            return switch (layout) {
                .disks => SpeckleDisk2D,
                .strided => [2]F,
                .gaussian => GaussianDiskCoefficients,
            };
        }

        fn generateCellBinnedRecords(comptime layout: CellBinnedLayout, outer_alloc: std.mem.Allocator, params: Speckle2DParams) !CellBinnedSpeckle2D {
            try params.validateResolved(config);
            const Record = CellBinnedRecord(layout);
            const bounds = speckleProceduralCellBounds(params, 0) orelse return error.SpeckleCellBinsTooLarge;
            const owners = speckleProceduralCellBounds(params, 1) orelse return error.SpeckleCellBinsTooLarge;
            if (owners.count > max_speckle_cells) return error.SpeckleCellBinsTooLarge;
            if (layout == .strided) {
                const slots = std.math.mul(usize, bounds.count, 9) catch return error.SpeckleCellBinsTooLarge;
                const center_bytes = std.math.mul(usize, slots, 2 * @sizeOf(F)) catch return error.SpeckleCellBinsTooLarge;
                try checkCellBinnedPreparationBudget(bounds.count, center_bytes, max_cell_binned_bytes);
                const counts = try outer_alloc.alloc(u8, bounds.count);
                errdefer outer_alloc.free(counts);
                const coordinates = try outer_alloc.alloc(F, slots * 2);
                const xs = coordinates[0..slots];
                const ys = coordinates[slots..];
                @memset(counts, 0);
                @memset(xs, std.math.inf(F));
                @memset(ys, 0);
                assignCellBinnedDisks(true, layout, params, owners, bounds, counts, &.{}, .{ .xs = xs, .ys = ys });
                return .{ .params = params, .offsets = &.{}, .records = .{ .strided = .{ .coordinates = coordinates, .counts = counts } }, .dims = bounds.dims };
            }
            const offsets_len = std.math.add(usize, bounds.count, 1) catch return error.SpeckleCellBinsTooLarge;
            const offsets_bytes = std.math.mul(usize, offsets_len, @sizeOf(usize)) catch return error.SpeckleCellBinsTooLarge;
            // Include the temporary counting/cursor array in the preparation budget.
            const index_bytes = std.math.mul(usize, offsets_bytes, 2) catch return error.SpeckleCellBinsTooLarge;
            if (index_bytes > max_cell_binned_bytes) return error.SpeckleCellBinsTooLarge;
            const offsets = try outer_alloc.alloc(usize, offsets_len);
            errdefer outer_alloc.free(offsets);
            const cursors = try outer_alloc.alloc(usize, bounds.count);
            defer outer_alloc.free(cursors);
            @memset(cursors, 0);
            assignCellBinnedDisks(false, layout, params, owners, bounds, cursors, offsets, &.{});
            offsets[0] = 0;
            for (cursors, 0..) |count, ii| {
                offsets[ii + 1] = std.math.add(usize, offsets[ii], count) catch return error.SpeckleCellBinsTooLarge;
            }
            const record_bytes = std.math.mul(usize, offsets[bounds.count], @sizeOf(Record)) catch return error.SpeckleCellBinsTooLarge;
            try checkCellBinnedPreparationBudget(index_bytes, record_bytes, max_cell_binned_bytes);
            const records = try outer_alloc.alloc(Record, offsets[bounds.count]);
            errdefer outer_alloc.free(records);
            @memset(cursors, 0);
            assignCellBinnedDisks(true, layout, params, owners, bounds, cursors, offsets, records);
            return .{ .params = params, .offsets = offsets, .records = @unionInit(CellBinnedRecords, @tagName(layout), records), .dims = bounds.dims };
        }

        fn assignCellBinnedDisks(comptime assign: bool, comptime layout: CellBinnedLayout, params: Speckle2DParams, owners: SpeckleCellBounds, bounds: SpeckleCellBounds, cursors: if (layout == .strided) []u8 else []usize, offsets: []const usize, records: if (layout == .strided) struct { xs: []F, ys: []F } else []CellBinnedRecord(layout)) void {
            const first: i64 = if (speckle_neighbor_count == 1) 0 else -1;
            const last: i64 = if (speckle_neighbor_count == 9) 1 else 0;
            var owner_y = owners.min[1];
            while (owner_y <= owners.max[1]) : (owner_y += 1) {
                var owner_x = owners.min[0];
                while (owner_x <= owners.max[0]) : (owner_x += 1) {
                    const disk = speckleDiskForCell(configured_soft_edges, owner_x, owner_y, params) orelse continue;
                    const support = disk.radius + (if (configured_soft_edges) params.edge_softness else @as(F, 0));
                    const support2 = support * support;
                    var yy = @max(0, owner_y + first);
                    while (yy <= @min(bounds.max[1], owner_y + last)) : (yy += 1) {
                        var xx = @max(0, owner_x + first);
                        while (xx <= @min(bounds.max[0], owner_x + last)) : (xx += 1) {
                            const lo: [2]F = .{ @floatFromInt(xx), @floatFromInt(yy) };
                            const hi: [2]F = .{ @min(lo[0] + 1, params.cells_per_uv[0]), @min(lo[1] + 1, params.cells_per_uv[1]) };
                            // Closed cells include touching faces. The nearest rounded subtraction
                            // and squared sum conservatively bound the identical runtime predicate.
                            // Owner eligibility also preserves the exact 1/4/9-neighbour stencil.
                            const dx = @max(lo[0], @min(hi[0], disk.center[0])) - disk.center[0];
                            const dy = @max(lo[1], @min(hi[1], disk.center[1])) - disk.center[1];
                            if (dx * dx + dy * dy > support2) continue;
                            const cell = @as(usize, @intCast(yy)) * bounds.dims[0] + @as(usize, @intCast(xx));
                            if (assign) {
                                if (layout == .strided) {
                                    std.debug.assert(cursors[cell] < 9);
                                    const target = cell * 9 + cursors[cell];
                                    records.xs[target] = disk.center[0];
                                    records.ys[target] = disk.center[1];
                                } else {
                                    const target = offsets[cell] + cursors[cell];
                                    records[target] = switch (layout) {
                                        .disks => disk,
                                        .strided => disk.center,
                                        .gaussian => blk: {
                                            const sigma = disk.radius / 3.0;
                                            break :blk .{ .center = disk.center, .outer2 = disk.radius * disk.radius, .sigma2 = sigma * sigma };
                                        },
                                    };
                                }
                            }
                            cursors[cell] += 1; // At most nine eligible owners per cell.
                        }
                    }
                }
            }
        }

        fn evalCellBinnedSpeckle2D(comptime soft_edges: bool, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            return switch (binned.records) {
                .disks => evalFullCellBinnedSpeckle2D(soft_edges, u, v, binned),
                .strided => evalStridedCellBinnedSpeckle2D(soft_edges, u, v, binned),
                .gaussian => evalGaussianCellBinnedSpeckle2D(soft_edges, u, v, binned),
            };
        }

        // Wrappers resolve layout before entering the shared finite-lane SIMD adapter.
        fn evalFullCellBinnedSpeckle2D(comptime soft_edges: bool, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            return evalCellBinnedRecords(soft_edges, .disks, u, v, binned);
        }

        fn evalStridedCellBinnedSpeckle2D(comptime soft_edges: bool, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            return evalCellBinnedRecords(soft_edges, .strided, u, v, binned);
        }

        fn evalGaussianCellBinnedSpeckle2D(comptime soft_edges: bool, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            return evalCellBinnedRecords(soft_edges, .gaussian, u, v, binned);
        }

        fn evalCellBinnedRecords(comptime soft_edges: bool, comptime layout: CellBinnedLayout, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            const params = binned.params;
            if (params.foreground == params.background) return params.background;
            const proc_x = @max(0.0, @min(1.0, u)) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, v)) * params.cells_per_uv[1];
            const xx: usize = @intFromFloat(@floor(proc_x));
            const yy: usize = @intFromFloat(@floor(proc_y));
            const cell = yy * binned.dims[0] + xx;
            const range: [2]usize = if (layout == .strided) .{ cell * 9, cell * 9 + binned.records.strided.counts[cell] } else .{ binned.offsets[cell], binned.offsets[cell + 1] };
            const edge = if (soft_edges) params.edge_softness else 0.0;
            var coverage: F = 0.0;
            var nearest2: F = std.math.inf(F);
            var index = range[0];
            if (comptime layout == .strided and speckle_shape == .gaussian) {
                const coordinates = binned.records.strided.coordinates;
                const half = coordinates.len / 2;
                var alternate: F = std.math.inf(F);
                while (index + 1 < range[1]) : (index += 2) {
                    const V = @Vector(2, F);
                    const xs: V = coordinates[index..][0..2].*;
                    const ys: V = coordinates[half + index ..][0..2].*;
                    const dx = @as(V, @splat(proc_x)) - xs;
                    const dy = @as(V, @splat(proc_y)) - ys;
                    const squared = dx * dx + dy * dy;
                    nearest2 = @min(nearest2, squared[0]);
                    alternate = @min(alternate, squared[1]);
                }
                nearest2 = @min(nearest2, alternate);
            }
            while (index < range[1]) : (index += 1) {
                const disk = switch (layout) {
                    .disks => binned.records.disks[index],
                    .strided => SpeckleDisk2D{ .center = .{ binned.records.strided.coordinates[index], binned.records.strided.coordinates[binned.records.strided.coordinates.len / 2 + index] }, .radius = params.radius_mean },
                    .gaussian => SpeckleDisk2D{ .center = binned.records.gaussian[index].center, .radius = 0 },
                };
                const dx = proc_x - disk.center[0];
                const dy = proc_y - disk.center[1];
                const distance2 = dx * dx + dy * dy;
                if (comptime layout == .strided and speckle_shape == .gaussian) {
                    nearest2 = @min(nearest2, distance2);
                } else {
                    const mask = if (layout == .gaussian) blk: {
                        const coefficients = binned.records.gaussian[index];
                        break :blk if (distance2 < coefficients.outer2) @exp(-0.5 * distance2 / coefficients.sigma2) else 0.0;
                    } else speckleDiskMask(soft_edges, distance2, disk.radius, edge);
                    coverage = @max(coverage, mask);
                    if (coverage == 1.0) break;
                }
            }
            if (comptime layout == .strided and speckle_shape == .gaussian) {
                // Tiny supported radii can underflow sigma² to zero. Preserve the
                // original max reduction's NaN handling rather than returning that mask.
                coverage = @max(@as(F, 0), speckleDiskMask(soft_edges, nearest2, params.radius_mean, edge));
            }
            // Do not return stored background for empty cells: signed-zero arithmetic
            // must remain identical to the existing analytic list evaluator.
            return params.background + coverage * (params.foreground - params.background);
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
            const edge = if (configured_soft_edges) params.edge_softness else 0.0;
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
                        } else speckleDiskForCell(configured_soft_edges, cell_x, cell_y, params) orelse .{ .center = .{ std.math.inf(F), 0.0 }, .radius = params.radius_mean };
                    }
                }
            }
            const outer = if (speckle_shape == .disk and configured_soft_edges) params.radius_mean + edge else params.radius_mean;
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
            // Rounded subtraction, squaring and addition are monotone on these
            // exact inverse-bin endpoints; no geometry epsilon is needed. Strict
            // coverage and non-strict intersection preserve hard-disk edges.
            const far_x = @max(
                @abs(box_min[0] - disk.center[0]),
                @abs(box_max[0] - disk.center[0]),
            );
            const far_y = @max(
                @abs(box_min[1] - disk.center[1]),
                @abs(box_max[1] - disk.center[1]),
            );
            const radius2 = disk.radius * disk.radius;
            if (disk.radius > 0.0 and
                far_x * far_x + far_y * far_y < radius2)
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
            return if (min_x * min_x + min_y * min_y <= radius2)
                .ambiguous
            else
                .background;
        }

        test "exact rounded extrema certify inverse bins through coordinate ceilings" {
            if (comptime evaluator != .classified_indexed) return;
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

        const speckle_classification_boundary_cache_capacity = 8192;

        const SpeckleClassificationIndexRange = struct {
            min: usize,
            max: usize,
        };

        const SpeckleClassificationAxis = ClassificationAxis(buildconfig.speckle_mask_samples_per_cell);

        fn ClassificationAxis(comptime r: u8) type {
            return struct {
                dim: usize,
                cells_per_uv: F,
                cached_boundaries: ?[]const F = null,

                inline fn upperBound(self: @This(), index: usize) F {
                    return std.math.nextAfter(F, self.boundary(index), -std.math.inf(F));
                }

                inline fn boundary(self: @This(), index: usize) F {
                    if (self.cached_boundaries) |boundaries| return boundaries[index];
                    return directMicrocellBoundary(F, r, index);
                }
            };
        }

        fn speckleClassificationAxes(
            dims: [2]usize,
            params: Speckle2DParams,
        ) [2]SpeckleClassificationAxis {
            return speckleClassificationAxesAtResolution(buildconfig.speckle_mask_samples_per_cell, dims, params);
        }

        fn speckleClassificationAxesAtResolution(comptime r: u8, dims: [2]usize, params: Speckle2DParams) [2]ClassificationAxis(r) {
            return .{
                .{ .dim = dims[0], .cells_per_uv = params.cells_per_uv[0] },
                .{ .dim = dims[1], .cells_per_uv = params.cells_per_uv[1] },
            };
        }

        fn speckleClassificationAxisRange(
            proc_min: F,
            proc_max: F,
            axis: SpeckleClassificationAxis,
        ) ?SpeckleClassificationIndexRange {
            return speckleClassificationAxisRangeAtResolution(buildconfig.speckle_mask_samples_per_cell, proc_min, proc_max, axis);
        }

        fn speckleClassificationAxisRangeAtResolution(comptime r: u8, proc_min: F, proc_max: F, axis: ClassificationAxis(r)) ?SpeckleClassificationIndexRange {
            const samples: F = @floatFromInt(r);
            const dim = axis.dim;
            // Disjoint representable inverse bins: each endpoint selects its own bin.
            if (proc_max < 0.0) return null;
            const first: usize = @intFromFloat(@max(0.0, proc_min) * samples);
            if (first >= dim) return null;
            const last: usize = @intFromFloat(@max(0.0, proc_max) * samples);
            return .{ .min = first, .max = @min(dim - 1, last) };
        }

        test "classified dimensions include default integral and fractional endpoints" {
            if (comptime evaluator != .classified_indexed) return;
            const r = buildconfig.speckle_mask_samples_per_cell;
            try testing.expectEqual([2]usize{ 192 * @as(usize, r) + 1, 160 * @as(usize, r) + 1 }, classifiedDims(.{}).?);
            try testing.expectEqual([2]usize{ 3 * @as(usize, r) + 1, 2 * @as(usize, r) + 1 }, classifiedDims(.{
                .cells_per_uv = .{ 3.0 + 0.25 / speckle_mask_samples_per_cell, 2.0 + 0.75 / speckle_mask_samples_per_cell },
            }).?);
        }

        test "direct stamp ranges match exhaustive representable bin overlap" {
            if (comptime evaluator != .classified_indexed) return;
            for ([_]F{ 3.25, 0.03125, std.math.nextAfter(F, 0.0, 1.0) }) |cells| {
                const params = Speckle2DParams{ .cells_per_uv = .{ cells, cells } };
                const dims = classifiedDims(params).?;
                const axis = speckleClassificationAxes(dims, params)[0];
                for (0..axis.dim + 2) |boundary_index| {
                    const boundary = axis.boundary(boundary_index);
                    for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |p| {
                        for ([_][2]F{ .{ p, p }, .{ -1.0, p }, .{ p, cells + 2.0 } }) |interval| {
                            var expected: ?SpeckleClassificationIndexRange = null;
                            for (0..axis.dim) |i| {
                                if (axis.upperBound(i + 1) < interval[0] or axis.boundary(i) > interval[1]) continue;
                                if (expected) |*range| range.max = i else expected = .{ .min = i, .max = i };
                            }
                            try testing.expectEqualDeep(expected, speckleClassificationAxisRange(interval[0], interval[1], axis));
                        }
                    }
                }
            }
        }

        fn stampSpeckleDiskClassification(
            states: []u16,
            dims: [2]usize,
            proc_axes: [2]SpeckleClassificationAxis,
            domain_scale: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
        ) void {
            stampSpeckleDiskClassificationMapped(false, states, dims, proc_axes, domain_scale, disk_cell, disk, undefined);
        }

        fn stampSpeckleDiskClassificationMapped(
            comptime local_slots: bool,
            states: []u16,
            dims: [2]usize,
            proc_axes: [2]SpeckleClassificationAxis,
            domain_scale: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
            slots: [9]i8,
        ) void {
            stampSpeckleDiskClassificationImpl(buildconfig.speckle_mask_samples_per_cell, local_slots, states, dims, proc_axes, domain_scale, disk_cell, disk, slots);
        }

        fn stampSpeckleDiskClassificationImpl(
            comptime r: u8,
            comptime local_slots: bool,
            states: []u16,
            dims: [2]usize,
            proc_axes: [2]ClassificationAxis(r),
            domain_scale: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
            slots: [9]i8,
        ) void {
            const center_scale = @max(@abs(disk.center[0]), @abs(disk.center[1]));
            const max_margin = 16.0 * std.math.floatEps(F) * @max(domain_scale, center_scale);
            // Inflate only the candidate scan to cover rounded subtraction and products;
            // the exact endpoint predicate below decides every state transition.
            const stamp_radius = disk.radius + 4.0 * max_margin;
            const y_range = speckleClassificationAxisRangeAtResolution(
                r,
                disk.center[1] - stamp_radius,
                disk.center[1] + stamp_radius,
                proc_axes[1],
            ) orelse return;
            const x_range = speckleClassificationAxisRangeAtResolution(
                r,
                disk.center[0] - stamp_radius,
                disk.center[0] + stamp_radius,
                proc_axes[0],
            ) orelse return;

            for (y_range.min..y_range.max + 1) |yy| {
                const proc_min_y = proc_axes[1].boundary(yy);
                const proc_max_y = proc_axes[1].upperBound(yy + 1);

                const y_mask = classificationAxisMaskAtResolution(r, yy, disk_cell[1], 1);
                if (y_mask == 0) continue;
                for (x_range.min..x_range.max + 1) |xx| {
                    const state_index = yy * dims[0] + xx;
                    if (states[state_index] == 512) continue;

                    const proc_min_x = proc_axes[0].boundary(xx);
                    const proc_max_x = proc_axes[0].upperBound(xx + 1);

                    const x_mask = classificationAxisMaskAtResolution(r, xx, disk_cell[0], 3);
                    if (x_mask == 0) continue;
                    const candidate_bit = if (local_slots) blk: {
                        const local_x = @as(i64, @intCast(xx / r)) - disk_cell[0] + 1;
                        const local_y = @as(i64, @intCast(yy / r)) - disk_cell[1] + 1;
                        const slot = slots[@as(usize, @intCast(local_y * 3 + local_x))];
                        if (slot < 0) continue;
                        break :blk @as(u16, 1) << @as(u4, @intCast(slot));
                    } else x_mask * y_mask;
                    const disk_state = classifySpeckleDiskMicrocell(
                        disk,
                        .{ proc_min_x, proc_min_y },
                        .{ proc_max_x, proc_max_y },
                    );
                    if (disk_state == .foreground) {
                        // A covering disk dominates intersections and clears the mask.
                        states[state_index] = 512;
                    } else if (disk_state == .ambiguous) {
                        states[state_index] |= candidate_bit;
                    }
                }
            }
        }

        fn buildSpeckleClassificationsFromOwnerRecords(
            states: []u16,
            dims: [2]usize,
            speckles: StripSpeckleList2D,
        ) void {
            if (speckles.recordCount() == 0) return;

            // Covers the default 2305 + 1921 boundaries without arena scratch storage.
            var boundary_cache: [speckle_classification_boundary_cache_capacity]F = undefined;
            var cached_boundary_count: usize = 0;
            var proc_axes = speckleClassificationAxes(dims, speckles.params);
            var domain_scale: F = 1.0;
            for (0..2) |axis| {
                const domain_min = proc_axes[axis].boundary(0);
                const domain_max = proc_axes[axis].upperBound(dims[axis]);
                const axis_scale = @max(@abs(domain_min), @abs(domain_max));
                domain_scale = @max(domain_scale, axis_scale);

                const boundary_count = dims[axis] + 1;
                if (boundary_count <= boundary_cache.len - cached_boundary_count) {
                    const cache_end = cached_boundary_count + boundary_count;
                    const cached_boundaries = boundary_cache[cached_boundary_count..cache_end];
                    // Cache exact inverse-bin boundaries without changing their rounding.
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
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !ClassifiedIndexedSpeckle2D {
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
            if (state_count > max_speckle_classification_bytes / @sizeOf(u16)) {
                return error.SpeckleClassificationTooLarge;
            }
            const states = try allocator.alloc(u16, state_count);
            errdefer allocator.free(states);
            @memset(states, 0);
            buildSpeckleClassificationsFromOwnerRecords(states, dims, speckles);
            return .{
                .speckles = speckles,
                .states = states,
                .dims = dims,
            };
        }

        fn classificationAxisMask(index: usize, owner: i64, stride: u4) u16 {
            return classificationAxisMaskAtResolution(buildconfig.speckle_mask_samples_per_cell, index, owner, stride);
        }

        fn classificationAxisMaskAtResolution(comptime r: u8, index: usize, owner: i64, stride: u4) u16 {
            const relative = owner - @as(i64, @intCast(index / r));
            return if (relative >= -1 and relative <= 1) @as(u16, 1) << @as(u4, @intCast((relative + 1) * stride)) else 0;
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
            if (comptime evaluator != .classified_indexed) return;
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
                    var resources = try Resources.init(testing.allocator, params);
                    defer resources.deinit(testing.allocator);
                    const masked = resources.data.classified;
                    const axes = speckleClassificationAxes(masked.dims, params);
                    // Dense two-axis microcell crossings supplement nextAfter edge samples.
                    for (0..masked.dims[1] + 1) |yy| {
                        for (0..masked.dims[0] + 1) |xx| {
                            for ([_]F{ -std.math.floatEps(F), 0.0, std.math.floatEps(F), 0.5 / (params.cells_per_uv[0] * speckle_mask_samples_per_cell) }) |delta| {
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
                            const masked = resources.data.classified;
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

        fn expectNeighborMaskCandidates(masked: ClassifiedIndexedSpeckle2D) !void {
            const params = masked.speckles.params;
            const Owner = struct { cell: [2]i64, disk: SpeckleDisk2D };
            const bounds = speckleProceduralCellBounds(params, 1).?;
            const owners = try testing.allocator.alloc(Owner, bounds.count);
            defer testing.allocator.free(owners);
            var owner_count: usize = 0;
            // Regenerate owners independently of strip records, stamp ranges,
            // and the separable mask multiplication being tested.
            for (0..bounds.dims[1]) |yy| {
                for (0..bounds.dims[0]) |xx| {
                    const cell: [2]i64 = .{ bounds.min[0] + @as(i64, @intCast(xx)), bounds.min[1] + @as(i64, @intCast(yy)) };
                    if (speckleDiskForCell(false, cell[0], cell[1], params)) |disk| {
                        owners[owner_count] = .{ .cell = cell, .disk = disk };
                        owner_count += 1;
                    }
                }
            }
            const axes = speckleClassificationAxes(masked.dims, params);
            for (masked.states, 0..) |state, index| {
                const xx = index % masked.dims[0];
                const yy = index / masked.dims[0];
                const lo: [2]F = .{ axes[0].boundary(xx), axes[1].boundary(yy) };
                const hi: [2]F = .{ axes[0].upperBound(xx + 1), axes[1].upperBound(yy + 1) };
                const cell: [2]i64 = .{ @intCast(xx / buildconfig.speckle_mask_samples_per_cell), @intCast(yy / buildconfig.speckle_mask_samples_per_cell) };
                var covered = false;
                var expected_candidates: u16 = 0;
                for (owners[0..owner_count]) |owner| {
                    if (owner.cell[0] < cell[0] - 1 or owner.cell[0] > cell[0] + 1 or
                        owner.cell[1] < cell[1] - 1 or owner.cell[1] > cell[1] + 1) continue;
                    switch (classifySpeckleDiskMicrocell(owner.disk, lo, hi)) {
                        .foreground => covered = true,
                        .ambiguous => {
                            // Test all nine relative positions independently of mask stamping.
                            for (0..9) |bit| {
                                const sample_cell: [2]i64 = .{
                                    owner.cell[0] - (@as(i64, @intCast(bit / 3)) - 1),
                                    owner.cell[1] - (@as(i64, @intCast(bit % 3)) - 1),
                                };
                                if (sample_cell[0] == cell[0] and sample_cell[1] == cell[1]) {
                                    expected_candidates |= @as(u16, 1) << @as(u4, @intCast(bit));
                                }
                            }
                        },
                        .background => {},
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
            if (comptime evaluator != .classified_indexed) return;
            const r = buildconfig.speckle_mask_samples_per_cell;
            // Probe the actual rounded procedural coordinate, not a real-number UV model.
            for ([_]F{ 0, 1, 2, 17, 4095, 65534 }) |face| {
                for ([_]F{ face, std.math.nextAfter(F, face, 0), std.math.nextAfter(F, face, std.math.inf(F)) }) |p| {
                    const index: usize = @intFromFloat(@floor(p * speckle_mask_samples_per_cell));
                    try testing.expectEqual(@as(usize, @intFromFloat(@floor(p))), index / r);
                    const mapped: VecSF = @floor(@as(VecSF, @splat(p)) * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
                    const vector: [S]F = mapped;
                    for (vector) |value| try testing.expectEqual(@floor(p * speckle_mask_samples_per_cell), value);
                }
            }
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 2, 2 } };
            const dims = classifiedDims(params).?;
            const axes = speckleClassificationAxes(dims, params);
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

        test "covering owner clears candidates in either stamping order" {
            if (comptime evaluator != .classified_indexed) return;
            const params: Speckle2DParams = .{ .cells_per_uv = .{ 0.01, 0.01 } };
            const axes = speckleClassificationAxes(.{ 1, 1 }, params);
            const covering: SpeckleDisk2D = .{ .center = .{ 0.04, 0.04 }, .radius = 0.2 };
            const intersecting: SpeckleDisk2D = .{ .center = .{ 0.0, 0.04 }, .radius = 0.04 };
            var states = [_]u16{0};
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
            try testing.expectEqual(@as(u16, 16), states[0]);
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, covering);
            try testing.expectEqual(@as(u16, 512), states[0]);
            stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
            try testing.expectEqual(@as(u16, 512), states[0]);
        }

        test "unconditional classified loads keep inactive and nonfinite lanes backgrounded" {
            if (comptime evaluator != .classified_indexed) return;
            var resources = try Resources.init(testing.allocator, .{ .cells_per_uv = .{ 0.031, 1.17 }, .foreground = -0.0, .background = 0.23 });
            defer resources.deinit(testing.allocator);
            const params = resources.data.classified.speckles.params;
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
            if (comptime evaluator != .classified_indexed) return;
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
                const axes = speckleClassificationAxes(dims, params);
                for ([_]F{ -1, -0.0, 0, 0.5, std.math.nextAfter(F, 1, 0), 1, 2 }) |uv| {
                    const p = @max(0.0, @min(1.0, uv)) * cells;
                    const j: usize = @intFromFloat(classificationCoordinate(uv, cells));
                    try testing.expect(j < dims[0]);
                    try testing.expect(p >= axes[0].boundary(j) and p <= axes[0].upperBound(j + 1));
                    try testing.expectEqual(@as(usize, @intFromFloat(@floor(p))), j / buildconfig.speckle_mask_samples_per_cell);
                }
                try testing.expectEqual(@as(usize, @intFromFloat(cells * speckle_mask_samples_per_cell)) + 1, dims[0]);
                if (cells > 2) continue; // Mathematical ceiling probes need no huge allocation.
                for ([_]F{ 0, 0.08 }) |jitter| {
                    var resources = try Resources.init(testing.allocator, .{ .cells_per_uv = params.cells_per_uv, .radius_jitter = jitter, .foreground = -0.0, .background = 0.23 });
                    defer resources.deinit(testing.allocator);
                    try expectNeighborMaskCandidates(resources.data.classified);
                    for ([_][2]F{ .{ 0, 0 }, .{ -0.0, 1 }, .{ 1, 1 }, .{ 0.5, 0.5 }, .{ -1, 2 } }) |uv| try expectClassifiedSample(&resources, uv);
                }
            }
        }

        test "neighbor masks preserve tiny zero radii and endpoint arithmetic" {
            if (comptime evaluator != .classified_indexed) return;
            const tiny = @sqrt(std.math.floatMin(F)) * 0.25;
            for ([_]F{ tiny, 0.35 }) |radius| {
                for ([_][2]F{ .{ 0.23, -0.0 }, .{ -0.0, 0.0 }, .{ 0.0, -0.0 }, .{ 1.0, 0.0 } }) |colours| {
                    var resources = try Resources.init(testing.allocator, .{ .cells_per_uv = .{ 2.17, 1.31 }, .radius_mean = radius, .radius_jitter = 0, .occupancy = 1, .background = colours[0], .foreground = colours[1] });
                    defer resources.deinit(testing.allocator);
                    for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 3 }, .{ 0.5, 0.5 }, .{ std.math.nan(F), 0 }, .{ 0, -std.math.inf(F) } }) |uv| try expectClassifiedSample(&resources, uv);
                    const strip = resources.data.classified.speckles;
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
            if (!std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1])) return params.background;
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
                    if (comptime evaluator == .mask_u8) {
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
            const row_stride = if (comptime evaluator == .mask_u8)
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

            const empty_pattern = speckle_shape != .perlin and params.occupancy == 0.0;
            if (empty_pattern or params.foreground == params.background) {
                return .{
                    .bits = try allocator.alloc(u8, 0),
                    .dims = dims,
                    .row_stride = row_stride,
                    .uv_to_texel = uv_to_texel,
                    .params = params,
                };
            }

            const bits = try allocator.alloc(u8, byte_count);
            errdefer allocator.free(bits);
            if (comptime speckle_shape == .perlin) {
                // Store coverage, not intensity; the mask sampler applies the original colors.
                var coverage_params = params;
                coverage_params.background = 0;
                coverage_params.foreground = 1;
                const lattice = try generatePerlinLattice(allocator, coverage_params);
                defer allocator.free(lattice.gradients);
                for (0..dims[1]) |y| {
                    for (0..dims[0]) |x| {
                        bits[y * row_stride + x] = quantizeSpeckleCoverage(samplePerlinScal(
                            @as(F, @floatFromInt(x)) / uv_to_texel[0],
                            @as(F, @floatFromInt(y)) / uv_to_texel[1],
                            lattice,
                        ));
                    }
                }
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
                .params = params,
            };
        }

        inline fn evalSpeckleMask2D(uv: [2]F, mask: SpeckleMask2D) F {
            const params = mask.params;
            // Generation encodes empty patterns in the payload; Perlin ignores occupancy.
            if (mask.bits.len == 0 or params.foreground == params.background or
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
            if (comptime evaluator == .mask_u8) {
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

        inline fn classificationCoordinate(uv: F, cells: F) F {
            return (@max(0.0, @min(1.0, uv)) * cells) * speckle_mask_samples_per_cell;
        }

        inline fn speckleCoverageEndpointValue(
            params: Speckle2DParams,
            coverage: F,
        ) F {
            return params.background + coverage * (params.foreground - params.background);
        }

        fn evalClassifiedIndexedSpeckle2D(
            uv: [2]F,
            classified: ClassifiedIndexedSpeckle2D,
        ) F {
            const params = classified.speckles.params;
            const empty = classified.speckles.recordCount() == 0;
            if (empty or
                params.foreground == params.background or
                !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
            {
                return params.background;
            }
            const proc: [2]F = .{
                @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0],
                @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1],
            };
            const x: usize = @intFromFloat(proc[0] * speckle_mask_samples_per_cell);
            const y: usize = @intFromFloat(proc[1] * speckle_mask_samples_per_cell);
            const state = classified.states[y * classified.dims[0] + x];
            if ((state & 511) == 0) return speckleCoverageEndpointValue(params, if (state == 512) 1.0 else 0.0);
            if (classified.speckles.centers.len != 0) return evalMaskedNeighborsAtProc(true, proc, state, classified.speckles);
            return evalMaskedNeighborsAtProc(false, proc, state, classified.speckles);
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
            if (comptime evaluator == .mock) return 0.5 * (u + v);
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

        fn speckleDiskMaskSIMD(comptime soft_edges: bool, distance2: VecSF, radius: VecSF, edge: F) VecSF {
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const outer = if (speckle_shape == .disk and soft_edges) radius + @as(VecSF, @splat(edge)) else radius;
            const outer2 = outer * outer;
            const mask = if (comptime speckle_shape == .gaussian) blk: {
                if (!@reduce(.Or, distance2 < outer2)) return zero;
                const sigma = radius / @as(VecSF, @splat(3));
                break :blk @exp(@as(VecSF, @splat(-0.5)) * distance2 / (sigma * sigma));
            } else if (comptime !soft_edges) one else blk: {
                const inner = @max(zero, radius - @as(VecSF, @splat(edge)));
                const inner2 = inner * inner;
                const t = @max(zero, @min(one, (distance2 - inner2) / (outer2 - inner2)));
                const smooth = one - t * t * (@as(VecSF, @splat(3)) - @as(VecSF, @splat(2)) * t);
                break :blk @select(F, distance2 <= inner2, one, smooth);
            };
            return @select(F, distance2 < outer2, mask, zero);
        }

        fn evalSpeckleListNaiveVariableGaussianSIMDImpl(u: VecSF, v: VecSF, speckles: SpeckleList2D) VecSF {
            const p = speckles.params;
            const background: VecSF = @splat(p.background);
            if (speckles.disks.len == 0 or p.foreground == p.background) return background;
            const finite = (@abs(u) < @as(VecSF, @splat(std.math.inf(F)))) & (@abs(v) < @as(VecSF, @splat(std.math.inf(F))));
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, @select(F, finite, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, @select(F, finite, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
            // Exp is monotone on supported nonpositive exponents, so only the
            // strongest one needs evaluating. Min ignores NaNs from underflowed
            // sigma² just as the scalar coverage max ignores their NaN masks.
            var nearest: VecSF = @splat(std.math.inf(F));
            for (speckles.disks) |disk| {
                const dx = px - @as(VecSF, @splat(disk.center[0]));
                const dy = py - @as(VecSF, @splat(disk.center[1]));
                const d2 = dx * dx + dy * dy;
                const sigma = disk.radius / 3;
                const exponent = @as(VecSF, @splat(-0.5)) * d2 / @as(VecSF, @splat(sigma * sigma));
                nearest = @min(nearest, -@select(F, d2 < @as(VecSF, @splat(disk.radius * disk.radius)), exponent, @as(VecSF, @splat(-std.math.inf(F)))));
            }
            const coverage = @exp(-nearest);
            return @select(F, finite, background + coverage * @as(VecSF, @splat(p.foreground - p.background)), background);
        }

        fn evalSpeckleListNaiveSIMDImpl(comptime soft_edges: bool, u: VecSF, v: VecSF, speckles: SpeckleList2D) VecSF {
            const p = speckles.params;
            if (comptime speckle_shape == .gaussian) {
                if (p.radius_jitter != 0) return evalSpeckleListNaiveVariableGaussianSIMDImpl(u, v, speckles);
            }
            const background: VecSF = @splat(p.background);
            if (speckles.disks.len == 0 or p.foreground == p.background) return background;
            const finite = (@abs(u) < @as(VecSF, @splat(std.math.inf(F)))) & (@abs(v) < @as(VecSF, @splat(std.math.inf(F))));
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, @select(F, finite, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, @select(F, finite, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
            var coverage = zero;
            var nearest: VecSF = @splat(std.math.inf(F));
            for (speckles.disks) |disk| {
                const dx = px - @as(VecSF, @splat(disk.center[0]));
                const dy = py - @as(VecSF, @splat(disk.center[1]));
                if (comptime speckle_shape == .gaussian) {
                    nearest = @min(nearest, dx * dx + dy * dy);
                } else {
                    coverage = @max(coverage, speckleDiskMaskSIMD(soft_edges, dx * dx + dy * dy, @splat(disk.radius), if (soft_edges) p.edge_softness else 0));
                    if (@reduce(.And, coverage == one)) break;
                }
            }
            if (comptime speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(soft_edges, nearest, @splat(p.radius_mean), 0));
            return @select(F, finite, background + coverage * @as(VecSF, @splat(p.foreground - p.background)), background);
        }

        fn evalCellBinnedSpeckleSIMDImpl(comptime soft_edges: bool, comptime layout: CellBinnedLayout, u: VecSF, v: VecSF, binned: CellBinnedSpeckle2D) VecSF {
            const p = binned.params;
            const background: VecSF = @splat(p.background);
            if (p.foreground == p.background) return background;
            const finite = (@abs(u) < @as(VecSF, @splat(std.math.inf(F)))) & (@abs(v) < @as(VecSF, @splat(std.math.inf(F))));
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, @select(F, finite, u, zero))) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, @select(F, finite, v, zero))) * @as(VecSF, @splat(p.cells_per_uv[1]));
            // Sanitized, clamped procedural coordinates are nonnegative; truncation is floor.
            const cx: [S]usize = @as(@Vector(S, usize), @intFromFloat(px));
            const cy: [S]usize = @as(@Vector(S, usize), @intFromFloat(py));
            const first_cell = cy[0] * binned.dims[0] + cx[0];
            var coherent = true;
            for (1..S) |lane| coherent = coherent and cy[lane] * binned.dims[0] + cx[lane] == first_cell;
            if (layout != .gaussian and coherent) {
                const range: [2]usize = if (layout == .strided) .{ first_cell * 9, first_cell * 9 + binned.records.strided.counts[first_cell] } else .{ binned.offsets[first_cell], binned.offsets[first_cell + 1] };
                var coverage = zero;
                var nearest: VecSF = @splat(std.math.inf(F));
                for (range[0]..range[1]) |index| {
                    const disk = if (layout == .strided) SpeckleDisk2D{ .center = .{ binned.records.strided.coordinates[index], binned.records.strided.coordinates[binned.records.strided.coordinates.len / 2 + index] }, .radius = p.radius_mean } else binned.records.disks[index];
                    const dx = px - @as(VecSF, @splat(disk.center[0]));
                    const dy = py - @as(VecSF, @splat(disk.center[1]));
                    if (comptime layout == .strided and speckle_shape == .gaussian) {
                        nearest = @min(nearest, dx * dx + dy * dy);
                    } else {
                        coverage = @max(coverage, speckleDiskMaskSIMD(soft_edges, dx * dx + dy * dy, @splat(disk.radius), if (soft_edges) p.edge_softness else 0));
                    }
                }
                if (comptime layout == .strided and speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(soft_edges, nearest, @splat(p.radius_mean), 0));
                return @select(F, finite, background + coverage * @as(VecSF, @splat(p.foreground - p.background)), background);
            }
            var starts: [S]usize = undefined;
            var counts: [S]usize = undefined;
            var max_count: usize = 0;
            for (0..S) |lane| {
                const cell = cy[lane] * binned.dims[0] + cx[lane];
                const range: [2]usize = if (layout == .strided) .{ cell * 9, cell * 9 + binned.records.strided.counts[cell] } else .{ binned.offsets[cell], binned.offsets[cell + 1] };
                starts[lane] = range[0];
                counts[lane] = range[1] - range[0];
                max_count = @max(max_count, counts[lane]);
            }
            var coverage = zero;
            var nearest: VecSF = @splat(std.math.inf(F));
            for (0..max_count) |ii| {
                var xs: [S]F = @splat(std.math.inf(F));
                var ys: [S]F = @splat(0);
                var rs: [S]F = @splat(p.radius_mean);
                var outer: [S]F = @splat(0);
                var sigma: [S]F = @splat(1);
                for (0..S) |lane| {
                    // Strided cells have nine slots with infinity-padded absent records.
                    if (layout != .strided and ii >= counts[lane]) continue;
                    const index = starts[lane] + ii;
                    switch (layout) {
                        .strided => {
                            xs[lane] = binned.records.strided.coordinates[index];
                            ys[lane] = binned.records.strided.coordinates[binned.records.strided.coordinates.len / 2 + index];
                        },
                        .disks => {
                            const disk = binned.records.disks[index];
                            xs[lane] = disk.center[0];
                            ys[lane] = disk.center[1];
                            rs[lane] = disk.radius;
                        },
                        .gaussian => {
                            const disk = binned.records.gaussian[index];
                            xs[lane] = disk.center[0];
                            ys[lane] = disk.center[1];
                            outer[lane] = disk.outer2;
                            sigma[lane] = disk.sigma2;
                        },
                    }
                }
                const dx = px - @as(VecSF, xs);
                const dy = py - @as(VecSF, ys);
                const d2 = dx * dx + dy * dy;
                if (comptime layout == .strided and speckle_shape == .gaussian) {
                    nearest = @min(nearest, d2);
                } else {
                    const mask = if (layout == .gaussian) blk: {
                        const distances: [S]F = d2;
                        var masks: [S]F = @splat(0);
                        for (0..S) |lane| {
                            if (distances[lane] < outer[lane]) masks[lane] = @exp(-0.5 * distances[lane] / sigma[lane]);
                        }
                        break :blk @as(VecSF, masks);
                    } else speckleDiskMaskSIMD(soft_edges, d2, rs, if (soft_edges) p.edge_softness else 0);
                    coverage = @max(coverage, mask);
                }
            }
            if (comptime layout == .strided and speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(soft_edges, nearest, @splat(p.radius_mean), 0));
            return @select(F, finite, background + coverage * @as(VecSF, @splat(p.foreground - p.background)), background);
        }

        // Finite inactive lanes still sample normally in the raw packet API.
        // Check the packet once, then keep the common scalar lane loop unchecked.
        inline fn evalSpeckleSIMDImpl(
            comptime soft_edges: bool,
            comptime eval: anytype,
            u: VecSF,
            v: VecSF,
            input: anytype,
            background: F,
        ) VecSF {
            const finite = (@abs(u) < @as(VecSF, @splat(std.math.inf(F)))) &
                (@abs(v) < @as(VecSF, @splat(std.math.inf(F))));
            const coord_0: [S]F = u;
            const coord_1: [S]F = v;
            var values: [S]F = undefined;
            if (@reduce(.And, finite)) {
                for (0..S) |lane| values[lane] = eval(soft_edges, coord_0[lane], coord_1[lane], input);
            } else {
                const valid: [S]bool = finite;
                for (0..S) |lane| values[lane] = if (valid[lane]) eval(soft_edges, coord_0[lane], coord_1[lane], input) else background;
            }
            return values;
        }

        inline fn evalClassifiedIndexedSpeckleSIMDImpl(
            u: VecSF,
            v: VecSF,
            v_mask_active: VecSB,
            classified: *const ClassifiedIndexedSpeckle2D,
        ) VecSF {
            const foreground = 512;
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
            const v_proc_x = @max(v_zero, @min(@as(VecSF, @splat(1.0)), v_u)) * @as(VecSF, @splat(params.cells_per_uv[0]));
            const v_proc_y = @max(v_zero, @min(@as(VecSF, @splat(1.0)), v_v)) * @as(VecSF, @splat(params.cells_per_uv[1]));
            const v_cell_x: VecSI = @intFromFloat(v_proc_x * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
            const v_cell_y: VecSI = @intFromFloat(v_proc_y * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
            const sample: [S]bool = v_sample;
            const cell_x: [S]isize = v_cell_x;
            const cell_y: [S]isize = v_cell_y;
            var state_values = [_]u16{0} ** S;
            // Sanitized inactive/nonfinite lanes load a valid state but never evaluate candidates.
            inline for (0..S) |lane| {
                const x: usize = @intCast(cell_x[lane]);
                const y: usize = @intCast(cell_y[lane]);
                state_values[lane] = classified.states[y * classified.dims[0] + x];
            }

            const v_states: @Vector(S, u16) = state_values;
            const v_foreground = v_sample & (v_states == @as(
                @Vector(S, u16),
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
                const ambiguous = state_values[lane] != 0 and state_values[lane] != foreground;
                if (sample[lane] and ambiguous) {
                    values[lane] = if (classified.speckles.centers.len != 0)
                        evalMaskedNeighborsAtProc(true, .{ v_proc_x[lane], v_proc_y[lane] }, state_values[lane], classified.speckles)
                    else
                        evalMaskedNeighborsAtProc(false, .{ v_proc_x[lane], v_proc_y[lane] }, state_values[lane], classified.speckles);
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
            if (mask.bits.len == 0 or params.foreground == params.background) {
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

            if (comptime evaluator == .mask_u8) {
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
            if (comptime evaluator == .mock or speckle_shape == .perlin) return;
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
            if (comptime evaluator == .mock) return;
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
                if (comptime evaluator == .direct_fixed) {
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
                    if (evaluator == .direct_fixed)
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
            switch (comptime evaluator) {
                .gradient_lattice => unreachable,
                .classified_indexed, .classified_binned_22, .classified_binned_23, .classified_binned_34, .classified_binned_42, .classified_binned_46, .classified_binned_49, .direct_fixed, .mask_1bit => {
                    try testing.expectError(
                        error.SpeckleEvaluatorRequiresHardEdges,
                        params.validateResolved(config),
                    );
                },
                .cell_hash, .list_naive, .list_indexed, .cell_binned, .mask_u8, .mock => try params.validateResolved(config),
            }
        }

        test "procedural speckle softness expands support bounds" {
            if (comptime evaluator == .mock or !supports_soft_edges) return;
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
            try testing.expectError(error.InvalidSpeckleEdgeSoftness, generateClassifiedSpeckle2D(testing.failing_allocator, params));
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
            if (comptime evaluator == .mock) return;
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
            if (comptime evaluator == .mock) return;
            var speckle_params: Speckle2DParams = .{
                .cells_per_uv = .{ 11.0, 9.0 },
                .seed = 42,
                .edge_softness = if (supports_soft_edges) 0.035 else 0.0,
                .pattern = speckle_shape,
            };
            if (comptime buildconfig.enable_all_evaluators) {
                speckle_params.evaluator = evaluator;
                speckle_params.neighbor_count = if (speckle_shape == .perlin) null else config.neighborhood();
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
            if (comptime evaluator == .mock or speckle_shape == .perlin) return;
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
            if (comptime evaluator == .mock or speckle_shape == .perlin) return;
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
                defer deinitTestResources(.{ .data = .{ .list = speckles } });
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
                        if (comptime evaluator == .cell_hash or evaluator == .list_naive) {
                            const prepared = if (softness > 0.0)
                                samplePreparedScal(true, uv[0], uv[1], params, &.{ .data = .{ .list = speckles } })
                            else
                                samplePreparedScal(false, uv[0], uv[1], params, &.{ .data = .{ .list = speckles } });
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
            if (comptime evaluator != .direct_fixed) return;

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
            defer deinitTestResources(.{ .data = .{ .direct_fixed = first } });
            var inactive_params = params;
            inactive_params.occupancy = 0.0;
            const inactive = try generateDirectFixedSpeckle2D(testing.allocator, inactive_params);
            defer deinitTestResources(.{ .data = .{ .direct_fixed = inactive } });
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

        fn classifiedStateSamples(classified: ClassifiedIndexedSpeckle2D) ![3][2]F {
            var state_uv: [3][2]F = undefined;
            var found_state = [_]bool{false} ** 3;
            for (0..classified.dims[0] * classified.dims[1]) |index| {
                const state = classified.states[index];
                const state_value: usize = if (state == 0) 0 else if (state == 512) 1 else 2;
                if (!found_state[state_value]) {
                    const x = index % classified.dims[0];
                    const y = index / classified.dims[0];
                    state_uv[state_value] = .{
                        (@as(F, @floatFromInt(x)) + 0.5) / (classified.speckles.params.cells_per_uv[0] * speckle_mask_samples_per_cell),
                        (@as(F, @floatFromInt(y)) + 0.5) / (classified.speckles.params.cells_per_uv[1] * speckle_mask_samples_per_cell),
                    };
                    found_state[state_value] = true;
                }
            }
            for (found_state) |found| try testing.expect(found);
            return state_uv;
        }

        fn expectClassifiedSample(resources: *const Resources, uv: [2]F) !void {
            const strip = resources.data.classified.speckles;
            const params = strip.params;
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            const expected = if (strip.recordCount() == 0 or !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1])) params.background else evalSpeckle2D(uv, params);
            const K = Kernel(kernelIndex(config));
            try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(K.sampleScal(uv[0], uv[1], params, resources))));
            const values: [S]F = K.sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), params, resources);
            for (values) |value| try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
            if (strip.recordCount() != 0 and std.math.isFinite(uv[0]) and std.math.isFinite(uv[1])) {
                const indexed = evalStripSpeckleList2DImpl(false, uv[0], uv[1], strip);
                try testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(indexed)));
            }
        }

        fn expectClassifiedExact(params: Speckle2DParams) !bool {
            const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
            var resources = try Resources.init(testing.allocator, params);
            defer resources.deinit(testing.allocator);
            try testing.expectEqual(@as(?u8, kernelIndex(config)), resources.kernel_index);
            const classified = resources.data.classified;
            const strip = classified.speckles;
            try expectNeighborMaskCandidates(classified);
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
                    const boundary = speckleClassificationAxes(classified.dims, params)[axis].boundary(index) / params.cells_per_uv[axis];
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

        test "classified evaluators preserve independent states and bitwise samples" {
            if (comptime evaluator != .classified_indexed) return;
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
            if (comptime evaluator != .classified_indexed) return;

            const cases = [_]Speckle2DParams{
                .{ .cells_per_uv = .{ 192.0, 160.0 } },
                .{ .cells_per_uv = .{ 3.25, 2.5 } },
                .{ .cells_per_uv = .{ 0.03125, 0.0625 } },
            };
            for (cases) |params| {
                try params.validateResolved(config);
                const dims = classifiedDims(params) orelse return error.TestUnexpectedResult;
                const axes = speckleClassificationAxes(dims, params);
                for (axes) |axis| {
                    for (0..axis.dim + 1) |ii| {
                        const uv = axis.boundary(ii) / axis.cells_per_uv;
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
                            const cell: usize = @intFromFloat(classificationCoordinate(sample, axis.cells_per_uv));
                            const proc = bounded_uv * axis.cells_per_uv;
                            try testing.expectEqual(@as(usize, @intFromFloat(@floor(proc))), cell / buildconfig.speckle_mask_samples_per_cell);
                            try testing.expect(proc >= axis.boundary(cell));
                            try testing.expect(proc <= axis.upperBound(cell + 1));
                        }
                    }
                }
            }
        }

        test "procedural speckle equal-colour fast path is exact" {
            if (comptime evaluator == .mock) return;
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
                    evaluator == .mask_u8) 0.035 else 0.0,
                .foreground = 0.15,
                .background = 0.85,
            };
        }

        test "direct 1-bit speckle mask preserves list-derived bytes and lattice values" {
            if (comptime evaluator != .mask_1bit) return;

            const params = speckleMaskTestParams();
            const speckles = try generateSpeckleList2D(testing.allocator, params);
            defer deinitTestResources(.{ .data = .{ .list = speckles } });

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
            if (comptime evaluator != .mask_1bit and
                evaluator != .mask_u8) return;

            for ([_]bool{ false, true }) |equal_colour| {
                var params = speckleMaskTestParams();
                params.occupancy = if (equal_colour) 1.0 else 0.0;
                if (equal_colour) params.foreground = params.background;
                const mask = try generateSpeckleMask2D(testing.allocator, params);
                defer deinitTestResources(.{ .data = .{ .mask = mask } });
                if (speckle_shape == .perlin and !equal_colour) {
                    try testing.expect(mask.bits.len > 0);
                } else {
                    try testing.expectEqual(@as(usize, 0), mask.bits.len);
                    try testing.expectEqual(params.background, evalSpeckleMask2D(.{ 0.37, 0.61 }, mask));
                }
            }

            var params = speckleMaskTestParams();
            const sizes: []const F = if (evaluator == .mask_u8) &.{ 3000.0, 4000.0 } else &.{4000.0};
            for (sizes) |cells| {
                params.cells_per_uv = .{ cells, cells };
                try testing.expectError(
                    error.SpeckleMaskTooLarge,
                    generateSpeckleMask2D(testing.allocator, params),
                );
            }
        }

        test "speckle mask clamps UV endpoints" {
            if (comptime evaluator != .mask_1bit and
                evaluator != .mask_u8) return;

            const mask = try generateSpeckleMask2D(testing.allocator, speckleMaskTestParams());
            defer deinitTestResources(.{ .data = .{ .mask = mask } });

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

        test "Perlin u8 mask quantizes analytic lattice coverage and samples nearest texels" {
            if (comptime speckle_shape != .perlin or evaluator != .mask_u8) return;

            var found_spatial_difference = false;
            for ([_][2]F{ .{ 3.25, 2.5 }, .{ 0.25, 0.75 }, .{ 2, 1 } }) |cells| {
                for ([_]F{ 0.0, 0.12 }) |width| {
                    var params: Speckle2DParams = .{
                        .pattern = .perlin,
                        .cells_per_uv = cells,
                        .perlin_coverage_threshold = 0.03,
                        .perlin_coverage_transition_width = width,
                        .foreground = 1,
                        .background = 0,
                        .occupancy = 0,
                        .radius_mean = 0.9,
                        .radius_jitter = 0.8,
                    };
                    std.mem.doNotOptimizeAway(&params);
                    var mask = try generateSpeckleMask2D(testing.allocator, params);
                    std.mem.doNotOptimizeAway(&mask);
                    defer deinitTestResources(.{ .data = .{ .mask = mask } });
                    try testing.expectEqual(mask.dims[0], mask.row_stride);
                    try testing.expectEqual(mask.dims[0] * mask.dims[1], mask.bits.len);
                    try testing.expectEqualDeep(params, mask.params);
                    const resources: Resources = .{ .kernel_index = comptime kernelIndex(config), .data = .{ .mask = mask } };
                    const K = Kernel(kernelIndex(config));
                    const expected = evalSpeckleMask2D(.{ 0.37, 0.61 }, mask);
                    try testing.expectApproxEqAbs(expected, K.sampleScal(0.37, 0.61, params, &resources), unit_tol);
                    const lanes: [S]F = K.sampleSIMD(@splat(0.37), @splat(0.61), @splat(true), params, &resources);
                    for (lanes) |value| try testing.expectApproxEqAbs(expected, value, unit_tol);
                    var found_intermediate = false;
                    for (0..mask.dims[1]) |yy| {
                        for (0..mask.dims[0]) |xx| {
                            const uv = [2]F{
                                @as(F, @floatFromInt(xx)) / mask.uv_to_texel[0],
                                @as(F, @floatFromInt(yy)) / mask.uv_to_texel[1],
                            };
                            const analytic = PerlinReference.evalPerlinSpeckle2D(uv, params);
                            const byte = mask.bits[yy * mask.row_stride + xx];
                            testing.expectEqual(quantizeSpeckleCoverage(analytic), byte) catch |err| {
                                std.debug.print("Perlin mask byte mismatch cells={any} width={d} texel=({d},{d}) analytic={d} byte={d}\n", .{ cells, width, xx, yy, analytic, byte });
                                return err;
                            };
                            const sampled = evalSpeckleMask2D(uv, mask);
                            try testing.expectApproxEqAbs(analytic, sampled, 0.5 / 255.0 + unit_tol);
                            found_intermediate = found_intermediate or (byte != 0 and byte != 255);
                            if (xx + 1 < mask.dims[0]) {
                                const nearby = [2]F{ uv[0] + 0.24 / mask.uv_to_texel[0], uv[1] };
                                try testing.expectApproxEqAbs(sampled, evalSpeckleMask2D(nearby, mask), unit_tol);
                                found_spatial_difference = found_spatial_difference or
                                    @abs(sampled - PerlinReference.evalPerlinSpeckle2D(nearby, params)) > 1.0 / 255.0;
                            }
                        }
                    }
                    testing.expectEqual(width > 0, found_intermediate) catch |err| {
                        std.debug.print("Perlin mask intermediate coverage cells={any} width={d} found={}\n", .{ cells, width, found_intermediate });
                        return err;
                    };
                }
            }
            try testing.expect(found_spatial_difference);
        }

        test "u8 speckle mask agrees with quantized indexed lattice evaluation" {
            if (comptime evaluator != .mask_u8 or speckle_shape == .perlin) return;

            const params = speckleMaskTestParams();
            const speckles = try generateSpeckleList2D(testing.allocator, params);
            defer deinitTestResources(.{ .data = .{ .list = speckles } });
            const mask = try generateSpeckleMask2D(testing.allocator, params);
            defer deinitTestResources(.{ .data = .{ .mask = mask } });

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
                    const analytic = if (speckleSoftness(params) > 0.0)
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
            if (comptime evaluator != .direct_fixed) return;

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
            const resources: Resources = .{ .data = .{ .direct_fixed = direct } };
            try expectPreparedSpeckleSIMD(params, &resources, &.{
                .{ .uv = .{ 0.25, 0.5 }, .expected = params.foreground },
                .{ .uv = .{ 0.375, 0.5 }, .expected = params.background },
                .{ .uv = .{ 0.1, 0.5 }, .expected = params.background },
                .{ .uv = .{ 0.75, 0.5 }, .expected = params.background },
                .{ .uv = .{ std.math.nan(F), std.math.inf(F) }, .expected = params.background },
                .{ .uv = .{ 0.25, 0.5 }, .active = false },
            });
        }

        test "classified binned prepared SIMD matches scalar for every state" {
            if (comptime evaluator != .classified_indexed) return;

            const params: Speckle2DParams = .{
                .seed = 0x85ebca6b,
                .cells_per_uv = .{ 5.25, 4.4 },
                .occupancy = 1.0,
                .radius_mean = 0.2,
                .radius_jitter = 0.0,
                .foreground = 0.17,
                .background = 0.83,
            };
            const classified = try generateClassifiedSpeckle2D(testing.allocator, params);
            defer deinitTestResources(.{ .data = .{ .classified = classified } });

            const state_uv = try classifiedStateSamples(classified);

            const resources: Resources = .{ .data = .{ .classified = classified } };
            try expectPreparedSpeckleSIMD(params, &resources, &.{
                .{ .uv = state_uv[0] },
                .{ .uv = state_uv[1] },
                .{ .uv = state_uv[2] },
                .{ .uv = state_uv[1], .active = false },
                .{ .uv = .{ std.math.nan(F), std.math.inf(F) } },
            });
        }

        test "1-bit speckle mask SIMD matches scalar and backgrounds invalid lanes" {
            if (comptime evaluator != .mask_1bit) return;

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
            const resources: Resources = .{ .data = .{ .mask = mask } };
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
            if (comptime evaluator != .mask_u8) return;

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
            const resources: Resources = .{ .data = .{ .mask = mask } };
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
            const no_gather: Resources = .{ .data = .{ .mask = no_gather_mask } };
            try expectPreparedSpeckleSIMDBackground(params, &no_gather);
        }

        test "speckle resources prepare sample open boundaries and release owned allocations" {
            if (comptime evaluator == .mock) return;
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
            var fallback_params = params;
            if (comptime evaluator != .cell_hash) {
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
                else switch (comptime evaluator) {
                    .mock => unreachable,
                    .cell_hash, .gradient_lattice => evalSpeckle2D(uv, params),
                    .list_naive => evalSpeckleList2DNaiveImpl(configured_soft_edges, uv[0], uv[1], resources.data.list),
                    .list_indexed => evalStripSpeckleList2DImpl(configured_soft_edges, uv[0], uv[1], resources.data.strip_list),
                    .cell_binned => evalCellBinnedSpeckle2D(configured_soft_edges, uv[0], uv[1], resources.data.cell_binned),
                    .classified_indexed => evalClassifiedIndexedSpeckle2D(
                        uv,
                        resources.data.classified,
                    ),
                    .classified_binned_22, .classified_binned_23, .classified_binned_34, .classified_binned_42, .classified_binned_46, .classified_binned_49 => evalSpeckle2D(uv, params),
                    .direct_fixed => evalDirectFixedSpeckle2D(uv, resources.data.direct_fixed),
                    .mask_1bit, .mask_u8 => evalSpeckleMask2D(uv, resources.data.mask),
                };
                try testing.expectEqual(expected, Implementation(speckleconfig.canonicalizeSampleConfig(config)).samplePreparedScal(false, uv[0], uv[1], fallback_params, &resources));
                const actual: [S]F = Implementation(speckleconfig.canonicalizeSampleConfig(config)).samplePreparedSIMD(
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
            try testing.expectEqualDeep(Resources{}, resources);
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
    try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, Resources.init(std.testing.failing_allocator, bad_softness));
    for ([_]speckleconfig.Pattern{ .gaussian, .perlin }) |pattern| {
        try std.testing.expectError(error.SpeckleEdgeSoftnessRequiresDisk, Resources.init(std.testing.failing_allocator, .{ .pattern = pattern, .edge_softness = 0.1 }));
    }
    if (comptime !buildconfig.enable_all_evaluators) {
        for (std.enums.values(speckleconfig.Evaluator)) |evaluator| {
            try std.testing.expectError(error.SpeckleOverridesDisabled, Resources.init(std.testing.failing_allocator, .{ .evaluator = evaluator }));
        }
        for (std.enums.values(speckleconfig.Neighborhood)) |neighbors| {
            try std.testing.expectError(error.SpeckleOverridesDisabled, Resources.init(std.testing.failing_allocator, .{ .neighbor_count = neighbors }));
        }
    } else {
        const cases = [_]struct { params: Speckle2DParams, err: anyerror }{
            .{ .params = .{ .pattern = .perlin, .neighbor_count = .nine }, .err = error.SpecklePerlinDoesNotUseNeighbors },
            .{ .params = .{ .pattern = .perlin, .evaluator = .list_indexed }, .err = error.PerlinRequiresSupportedEvaluator },
            .{ .params = .{ .pattern = .gaussian, .evaluator = .mask_1bit }, .err = error.Mask1BitRequiresDisk },
            .{ .params = .{ .evaluator = .classified_indexed, .neighbor_count = .four }, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
            .{ .params = .{ .evaluator = .classified_indexed, .pattern = .gaussian }, .err = error.ClassifiedIndexedRequiresDiskAndNineNeighbors },
            .{ .params = .{ .evaluator = .classified_indexed, .edge_softness = 0.01 }, .err = error.SpeckleEvaluatorRequiresHardEdges },
            .{ .params = .{ .evaluator = .classified_indexed, .radius_mean = 0.95, .radius_jitter = 0.08 }, .err = error.InvalidSpeckleNeighborhoodRadius },
            .{ .params = .{ .evaluator = .direct_fixed, .neighbor_count = .nine }, .err = error.DirectFixedRequiresDiskAndOneNeighbor },
            .{ .params = .{ .evaluator = .direct_fixed, .radius_jitter = 0.01 }, .err = error.InvalidDirectFixedSpeckleRadiusJitter },
            .{ .params = .{ .evaluator = .direct_fixed, .radius_mean = 0.6 }, .err = error.InvalidDirectFixedSpeckleRadius },
            .{ .params = .{ .neighbor_count = .one, .radius_jitter = 0.1 }, .err = error.InvalidSpeckleNeighborhoodRadius },
        };
        for (cases) |case| try std.testing.expectError(case.err, Resources.init(std.testing.failing_allocator, case.params));
        const direct = try (Speckle2DParams{ .evaluator = .direct_fixed }).resolve();
        try std.testing.expectEqual(speckleconfig.Neighborhood.one, direct.neighborhood().?);
        for ([_]speckleconfig.Evaluator{ .cell_hash, .mock }) |evaluator| {
            var resources = try Resources.init(std.testing.failing_allocator, .{ .evaluator = evaluator });
            defer resources.deinit(std.testing.failing_allocator);
            try std.testing.expect(resources.kernel_index != null);
            try std.testing.expectEqualDeep(Resources{ .kernel_index = resources.kernel_index }, resources);
        }
    }
    // Perlin ignores disk-only fields but never silently repairs its own settings.
    try (Speckle2DParams{ .pattern = .perlin, .occupancy = std.math.nan(F), .radius_mean = -1, .radius_jitter = std.math.inf(F) }).validate();
    try std.testing.expectError(error.InvalidSpecklePerlinCoverageTransitionWidth, (Speckle2DParams{ .pattern = .perlin, .perlin_coverage_transition_width = -1 }).resolve());
}

test "mock erases ignored settings but retains raw common and softness validation" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    for (std.enums.values(speckleconfig.Pattern)) |pattern| {
        for (std.enums.values(speckleconfig.Neighborhood)) |neighbors| {
            var params: Speckle2DParams = .{
                .pattern = pattern,
                .evaluator = .mock,
                .neighbor_count = neighbors,
                .occupancy = std.math.nan(F),
                .radius_mean = -1,
                .radius_jitter = std.math.inf(F),
                .perlin_coverage_threshold = std.math.nan(F),
                .perlin_coverage_transition_width = -1,
            };
            try std.testing.expectEqualDeep(speckleconfig.Config{ .mock = {} }, try params.resolve());
            var resources = try Resources.init(std.testing.failing_allocator, params);
            defer resources.deinit(std.testing.failing_allocator);
            try std.testing.expectEqual(@as(F, 0.75), sampleScal(-0.5, 2, params, &resources));
            const lanes: [S]F = sampleSIMD(@splat(-0.5), @splat(2), @splat(false), params, &resources);
            for (lanes) |value| try std.testing.expectEqual(@as(F, 0.75), value);
            for ([_]F{ -1, std.math.nan(F), std.math.inf(F) }) |softness| {
                params.edge_softness = softness;
                try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, params.resolve());
            }
            params.edge_softness = 0.1;
            if (pattern == .disk) {
                try std.testing.expectEqualDeep(speckleconfig.Config{ .mock = {} }, try params.resolve());
            } else {
                try std.testing.expectError(error.SpeckleEdgeSoftnessRequiresDisk, params.resolve());
            }
            params.edge_softness = 0;
            params.cells_per_uv[0] = std.math.nan(F);
            try std.testing.expectError(error.InvalidSpeckleCellsPerUV, params.resolve());
            params.cells_per_uv[0] = 1;
            params.foreground = std.math.nan(F);
            try std.testing.expectError(error.InvalidSpeckleForeground, params.resolve());
            params.foreground = 0;
            params.background = std.math.inf(F);
            try std.testing.expectError(error.InvalidSpeckleBackground, params.resolve());
        }
    }
}

test "classified owner strips clean up every allocation failure" {
    const Probe = struct {
        fn generate(allocator: std.mem.Allocator, jitter: F, occupancy: F) !void {
            var tracking = std.testing.FailingAllocator.init(allocator, .{});
            const tracked_allocator = tracking.allocator();
            var resources = try Resources.init(tracked_allocator, .{
                .cells_per_uv = .{ 2, 1 },
                .occupancy = occupancy,
                .radius_mean = 0.35,
                .radius_jitter = jitter,
            });
            defer resources.deinit(tracked_allocator);
            try std.testing.expectEqual(@as(usize, 2), tracking.allocations);
            const strip = resources.data.classified.speckles;
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
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        const strip = resources.data.classified.speckles;
        try std.testing.expectEqual(@as(usize, 0), strip.centers.len);
        try std.testing.expectEqual(@as(usize, 0), strip.disks.len);
        for (resources.data.classified.states) |state| try std.testing.expectEqual(@as(u16, 0), state);
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
    var empty: Resources = .{};
    empty.deinit(std.testing.failing_allocator);
    try std.testing.expectEqualDeep(Resources{}, empty);
    inline for (generation_configs) |config| {
        const evaluator = comptime std.meta.activeTag(config);
        const speckle_shape = comptime config.pattern() orelse .disk;
        const speckle_neighbor_count = comptime @intFromEnum(config.neighborhood() orelse speckleconfig.Neighborhood.nine);
        const soft_edges = comptime config.edges() == .soft;
        var params: Speckle2DParams = .{
            .pattern = speckle_shape,
            .cells_per_uv = .{ 3.25, 2.5 },
            .radius_mean = if (evaluator == .mock) 100 else if (speckle_neighbor_count == 1) 0.25 else 0.38,
            .radius_jitter = if (evaluator == .direct_fixed) 0.0 else 0.07,
            .occupancy = if (evaluator == .mock) 0 else (Speckle2DParams{}).occupancy,
            .edge_softness = if (soft_edges) 0.035 else 0.0,
            .foreground = 0.17,
            .background = 0.83,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            params.evaluator = evaluator;
            params.neighbor_count = config.neighborhood();
        }
        try std.testing.expectEqual(config, try params.resolve());
        const raw = Implementation(config).evalSpeckle2DImpl(soft_edges, 0.37, 0.61, params);
        try std.testing.expectEqual(raw, sampleScal(0.37, 0.61, params, &.{}));
        const raw_simd: [S]F = sampleSIMD(@splat(0.37), @splat(0.61), @splat(false), params, &.{});
        for (raw_simd) |value| try std.testing.expectEqual(raw, value);
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        const index = comptime kernelIndex(config);
        try std.testing.expectEqual(@as(?u8, index), resources.kernel_index);
        const backing_tag: std.meta.Tag(Backing) = switch (evaluator) {
            .cell_hash, .mock => .none,
            .list_naive => .list,
            .list_indexed => .strip_list,
            .cell_binned => .cell_binned,
            .classified_indexed => .classified,
            .classified_binned_22, .classified_binned_23, .classified_binned_34 => .direct_classified,
            .classified_binned_42, .classified_binned_46, .classified_binned_49 => .rect_bin_classified,
            .direct_fixed => .direct_fixed,
            .mask_1bit, .mask_u8 => .mask,
            .gradient_lattice => .perlin,
        };
        try std.testing.expectEqual(backing_tag, @as(std.meta.Tag(Backing), resources.data));
        if (comptime evaluator == .cell_hash or evaluator == .mock) {
            var allocation_free = try Resources.init(std.testing.failing_allocator, params);
            allocation_free.deinit(std.testing.failing_allocator);
            try std.testing.expectEqualDeep(Resources{}, allocation_free);
        }
        try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
            fn run(allocator: std.mem.Allocator, input: Speckle2DParams) !void {
                var owned = try Resources.init(allocator, input);
                defer owned.deinit(allocator);
                owned.deinit(allocator);
                try std.testing.expectEqualDeep(Resources{}, owned);
            }
        }.run, .{params});
        const points = [_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 0.37 }, .{ 0.35, 0.61 }, .{ 0.67, 0.41 }, .{ 0.37, 2 } };
        for (points) |uv| {
            const Impl = Implementation(config);
            const reference = switch (comptime evaluator) {
                .mock => 0.5 * (uv[0] + uv[1]),
                .cell_hash, .gradient_lattice, .list_indexed, .cell_binned => Impl.evalSpeckle2D(uv, params),
                // Direct-fixed returns stored endpoints, not the hash reference's arithmetic mapping.
                .direct_fixed => if (Impl.evalSpeckle2D(uv, params) == params.background)
                    params.background
                else
                    params.foreground,
                .list_naive => Impl.evalSpeckleList2DNaiveImpl(soft_edges, uv[0], uv[1], resources.data.list),
                .classified_indexed, .classified_binned_22, .classified_binned_23, .classified_binned_34, .classified_binned_42, .classified_binned_46, .classified_binned_49 => Impl.evalSpeckle2D(uv, params),
                .mask_1bit, .mask_u8 => Impl.evalSpeckleMask2D(uv, resources.data.mask),
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
            const inactive_expected = switch (evaluator) {
                .cell_hash => if (speckle_shape == .perlin) params.background else reference,
                .list_naive, .list_indexed, .cell_binned, .mock => reference,
                else => params.background,
            };
            for (inactive) |value| try std.testing.expectEqual(inactive_expected, value);
        }
        const nonfinite: [S]F = Kernel(index).sampleSIMD(@splat(std.math.nan(F)), @splat(std.math.inf(F)), @splat(true), params, &resources);
        for (nonfinite) |value| {
            if (comptime evaluator == .mock) {
                try std.testing.expect(std.math.isNan(value));
            } else try std.testing.expectEqual(params.background, value);
        }
        resources.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(?u8, null), resources.kernel_index);
        try std.testing.expectEqualDeep(Resources{}, resources);
    }
}

test "strip indexed records and samples match exhaustive lists bitwise across occupancy and neighborhoods" {
    @setEvalBranchQuota(10_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (generation_configs) |config| {
        const evaluator = comptime std.meta.activeTag(config);
        const speckle_shape = comptime config.pattern() orelse .disk;
        const speckle_neighbor_count = comptime @intFromEnum(config.neighborhood() orelse speckleconfig.Neighborhood.nine);
        const soft_edges = comptime config.edges() == .soft;
        if (comptime evaluator != .list_indexed) continue;
        for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
            for (0..9) |variation| {
                const params: Speckle2DParams = .{
                    .pattern = speckle_shape,
                    .evaluator = .list_indexed,
                    .neighbor_count = config.neighborhood(),
                    .cells_per_uv = .{ 3.25, 2.75 },
                    .occupancy = occupancy,
                    .seed = if (variation == 1) 43498 else 0,
                    .radius_mean = if (variation >= 7) (if (speckle_neighbor_count == 1) @as(F, 0.5) else @as(F, 1.0)) - (if (soft_edges) @as(F, 0.05) else 0.0) else if (variation == 1) 0.2 else 0.3,
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
                    .edge_softness = if (soft_edges) 0.05 else 0.0,
                };
                var reference_params = params;
                reference_params.evaluator = .list_naive;
                var reference_resources = try Resources.init(std.testing.allocator, reference_params);
                defer reference_resources.deinit(std.testing.allocator);
                var tracking = std.testing.FailingAllocator.init(std.testing.allocator, .{});
                var indexed = try Resources.init(tracking.allocator(), params);
                defer indexed.deinit(tracking.allocator());
                try std.testing.expectEqual(@as(usize, 1), tracking.allocations);
                const table = reference_resources.data.list;
                const strip = indexed.data.strip_list;
                const length: usize = switch (speckle_neighbor_count) {
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
                            try std.testing.expectEqual(@as(SentinelBits, 0), @as(SentinelBits, @bitCast(Impl.fixedStripDiskMask(soft_edges, distance2, strip))));
                        }
                    }
                }
                for (0..strip.cell_dims[1]) |yy| {
                    for (0..strip.cell_dims[0]) |xx| {
                        for (0..length) |ii| {
                            const disk: SpeckleDisk2D = Impl.speckleDiskForCell(soft_edges, strip.cell_origin[0] + @as(i64, @intCast(xx)), strip.cell_origin[1] + @as(i64, @intCast(yy)) + @as(i64, @intCast(ii)) - (if (speckle_neighbor_count == 9) @as(i64, 1) else 0), params) orelse .{ .center = .{ 0.0, 0.0 }, .radius = -1.0 };
                            const stored = strip.record((yy * strip.cell_dims[0] + xx) * length + ii);
                            if (disk.radius < 0.0) {
                                try std.testing.expectEqual(std.math.inf(F), stored.center[0]);
                                try std.testing.expectEqual(@as(F, 0.0), stored.center[1]);
                                try std.testing.expectEqual(params.radius_mean, stored.radius);
                                const mask = if (params.radius_jitter == 0.0)
                                    Impl.fixedStripDiskMask(soft_edges, std.math.inf(F), strip)
                                else
                                    Impl.speckleDiskMask(soft_edges, std.math.inf(F), stored.radius, params.edge_softness);
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
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(soft_edges, Impl.evalSpeckleList2DNaiveImpl, @splat(u), @splat(v), table, table.params.background);
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
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(soft_edges, Impl.evalSpeckleList2DNaiveImpl, us, vs, table, table.params.background);
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
                    const expected: [S]F = Impl.evalSpeckleSIMDImpl(soft_edges, Impl.evalSpeckleList2DNaiveImpl, us, vs, table, table.params.background);
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

// Test-only oracle: shares the deterministic cell hash, not production placement,
// neighbor culling, mask, color, or list-generation helpers.
const CellBinnedIndependentReference = struct {
    const Disk = struct { xy: [2]F, radius: F };

    fn disk(p: Speckle2DParams, x: i64, y: i64) ?Disk {
        const hash = hashSpeckleCell(x, y, p.seed);
        const occupied: F = @as(F, @floatFromInt(hash & 0xffff)) / 65536;
        if (occupied >= p.occupancy) return null;
        const radius = p.radius_mean + p.radius_jitter * (@as(F, @floatFromInt(hash >> 48)) / 32768 - 1);
        const support = radius + p.edge_softness;
        const n = @intFromEnum(p.neighbor_count.?);
        const margin = if (n == 1) support else @as(F, 0);
        const span = 1 - (if (n == 1) 2 * support else if (n == 4) support else @as(F, 0));
        var result: Disk = .{ .xy = undefined, .radius = radius };
        for ([_]i64{ x, y }, [_]u16{ @truncate(hash >> 16), @truncate(hash >> 32) }, 0..) |cell, raw, axis| {
            const origin: F = @floatFromInt(cell);
            var unit = raw;
            var center = (origin + margin) + (@as(F, @floatFromInt(unit)) / 65536) * span;
            // Exhaustive descending repair, independent of the production binary search.
            if (n != 9) while (unit > 0) {
                const gap = origin + 1 - center;
                if (gap * gap >= support * support) break;
                unit -= 1;
                center = (origin + margin) + (@as(F, @floatFromInt(unit)) / 65536) * span;
            };
            result.xy[axis] = center;
        }
        return result;
    }

    fn sample(p: Speckle2DParams, u: F, v: F) F {
        if (p.foreground == p.background) return p.background;
        const px = @min(@max(u, 0), 1) * p.cells_per_uv[0];
        const py = @min(@max(v, 0), 1) * p.cells_per_uv[1];
        const sx: i64 = @intFromFloat(@floor(px));
        const sy: i64 = @intFromFloat(@floor(py));
        const n = @intFromEnum(p.neighbor_count.?);
        var coverage: F = 0;
        var y: i64 = -1;
        while (y <= @as(i64, @intFromFloat(@floor(p.cells_per_uv[1]))) + 1) : (y += 1) {
            var x: i64 = -1;
            while (x <= @as(i64, @intFromFloat(@floor(p.cells_per_uv[0]))) + 1) : (x += 1) {
                const eligible = switch (n) {
                    1 => x == sx and y == sy,
                    4 => x >= sx and x <= sx + 1 and y >= sy and y <= sy + 1,
                    9 => @abs(x - sx) <= 1 and @abs(y - sy) <= 1,
                    else => unreachable,
                };
                if (!eligible) continue;
                const d = disk(p, x, y) orelse continue;
                const dx = px - d.xy[0];
                const dy = py - d.xy[1];
                const squared = dx * dx + dy * dy;
                const outer = d.radius + p.edge_softness;
                if (!(squared < outer * outer)) continue;
                var strength: F = 1;
                if (p.pattern == .gaussian) {
                    const sigma = d.radius / 3;
                    strength = @exp((-0.5 * squared) / (sigma * sigma));
                } else if (p.edge_softness > 0) {
                    const inner = @max(d.radius - p.edge_softness, 0);
                    if (squared > inner * inner) {
                        const t = (squared - inner * inner) / (outer * outer - inner * inner);
                        strength = 1 - t * t * (3 - 2 * t);
                    }
                }
                if (strength > coverage) coverage = strength; // NaN masks do not replace zero.
            }
        }
        // Deliberately no occupancy-zero fast return: this is the list contract.
        return p.background + coverage * (p.foreground - p.background);
    }
};

test "cell binned review independent exhaustive field reference" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (generation_configs) |config| {
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const soft = comptime config.edges() == .soft;
        const limit: F = if (config.neighborhood() == .one) 0.5 else 1;
        for (0..8) |variation| {
            const p: Speckle2DParams = .{
                .evaluator = std.meta.activeTag(config),
                .pattern = config.pattern().?,
                .neighbor_count = config.neighborhood(),
                .seed = if (variation == 2) 43498 else 0,
                .cells_per_uv = if (variation == 5) .{ 0.03125, 0.0625 } else if (variation == 7) .{ 1, 1 } else .{ 3.25, 2.75 },
                .radius_mean = if (variation == 1) limit - (if (soft) @as(F, 0.04) else 0) else if (variation == 4) std.math.floatMin(F) else if (variation == 7) @sqrt(std.math.floatMin(F) * std.math.floatEps(F)) * 1.5 else 0.2,
                .radius_jitter = if (variation == 2) 0.2 else if (variation == 3) 0.08 else 0,
                .edge_softness = if (soft) 0.04 else 0,
                .occupancy = if (variation == 0) 0 else if (variation == 3) 0.7 else if (variation == 5) 0.001 else 1,
                .foreground = if (variation == 6) 0 else if (variation == 3) 0.17 else 0.91,
                .background = if (variation == 0 or variation == 5 or variation == 6) -0.0 else if (variation == 3) 0.83 else 0.23,
            };
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            var points: [52][2]F = undefined;
            var count: usize = 0;
            const ux = 1 / p.cells_per_uv[0];
            const vy = 1 / p.cells_per_uv[1];
            for ([_]F{ -1, 0, ux, std.math.nextAfter(F, ux, std.math.inf(F)), 0.5, 1, 2 }) |u| {
                for ([_]F{ -1, 0, vy, std.math.nextAfter(F, vy, std.math.inf(F)), 0.5, 1, 2 }) |v| {
                    points[count] = .{ u, v };
                    count += 1;
                }
            }
            if (CellBinnedIndependentReference.disk(p, 0, 0)) |d| {
                for ([_]F{ -1, 0, 1 }) |sign| {
                    points[count] = .{ (d.xy[0] + sign * (d.radius + p.edge_softness)) / p.cells_per_uv[0], d.xy[1] / p.cells_per_uv[1] };
                    count += 1;
                }
            }
            for (points[0..count]) |uv| {
                const expected = CellBinnedIndependentReference.sample(p, uv[0], uv[1]);
                if (variation == 0 or variation == 5) try std.testing.expectEqual(@as(Bits, 0), @as(Bits, @bitCast(expected)));
                if (variation == 6) try std.testing.expectEqual(@as(Bits, @bitCast(p.background)), @as(Bits, @bitCast(expected)));
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(uv[0], uv[1], p, &resources))));
                const lanes: [S]F = sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(false), p, &resources);
                for (lanes) |actual| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
            }
        }
    }
}

test "Gaussian packets match independent fields at centers overlaps and underflowed sigma squared" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (generation_configs) |config| {
        const tag = comptime std.meta.activeTag(config);
        if (comptime (tag != .list_naive and tag != .cell_binned) or config.pattern() != .gaussian) continue;
        for (0..6) |variation| {
            const tiny = @sqrt(std.math.floatMin(F) * std.math.floatEps(F)) * 1.5;
            const radius: F = if (variation == 2 or variation == 3) tiny else if (config.neighborhood() == .one) 0.4 else 0.6;
            const p: Speckle2DParams = .{
                .evaluator = tag,
                .pattern = .gaussian,
                .neighbor_count = config.neighborhood(),
                .cells_per_uv = .{ 1, 1 },
                .radius_mean = radius,
                .radius_jitter = if (variation == 3) tiny * 0.25 else if (variation == 1 or variation == 5) 0.08 else 0,
                .occupancy = if (variation == 4) 0 else if (variation == 5) 0.7 else 1,
                .foreground = if (variation == 5) -0.0 else 0.91,
                .background = if (variation == 5) 0.83 else -0.0,
            };
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            var points: [80][2]F = undefined;
            var count: usize = 0;
            for (0..5) |yy| {
                for (0..5) |xx| {
                    points[count] = .{ @as(F, @floatFromInt(xx)) / 4, @as(F, @floatFromInt(yy)) / 4 };
                    count += 1;
                }
            }
            for (0..2) |yy| {
                for (0..2) |xx| {
                    const disk = CellBinnedIndependentReference.disk(p, @intCast(xx), @intCast(yy)) orelse continue;
                    for ([_]F{ -disk.radius, 0, disk.radius }) |offset| {
                        const x = disk.xy[0] + offset;
                        points[count] = .{ std.math.nextAfter(F, x, -std.math.inf(F)), disk.xy[1] };
                        points[count + 1] = .{ x, disk.xy[1] };
                        points[count + 2] = .{ std.math.nextAfter(F, x, std.math.inf(F)), disk.xy[1] };
                        count += 3;
                    }
                }
            }
            var first: usize = 0;
            while (first < count) : (first += S) {
                var us: [S]F = undefined;
                var vs: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    const point = points[@min(first + lane, count - 1)];
                    us[lane] = point[0];
                    vs[lane] = point[1];
                    active[lane] = lane % 2 == 0;
                }
                const values: [S]F = sampleSIMD(us, vs, active, p, &resources);
                for (values, us, vs) |value, u, v| {
                    const expected = if (comptime tag == .list_naive) blk: {
                        if (resources.data.list.disks.len == 0) break :blk p.background;
                        break :blk CellBinnedIndependentReference.sample(p, u, v);
                    } else CellBinnedIndependentReference.sample(p, u, v);
                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
                }
            }
        }
    }
}

test "packet adapters preserve finite inactive and nonfinite lane contracts bitwise" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (kernel_configs, 0..) |config, index| {
        const tag = comptime std.meta.activeTag(config);
        if (comptime tag != .cell_hash and tag != .list_naive and tag != .list_indexed and tag != .cell_binned) continue;
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                const params: Speckle2DParams = .{
                    .evaluator = tag,
                    .pattern = config.pattern().?,
                    .neighbor_count = config.neighborhood(),
                    .edge_softness = if (config.edges() == .soft) 0.04 else 0,
                    .cells_per_uv = .{ 3.17, 2.31 },
                    .radius_mean = 0.35,
                    .radius_jitter = jitter,
                    .occupancy = occupancy,
                    .background = -0.0,
                    .foreground = 0.9,
                };
                var resources = try Resources.init(std.testing.allocator, params);
                defer resources.deinit(std.testing.allocator);
                const coords = [_]F{ -1, -0.0, 0, 0.17, 0.5, 1, 2, std.math.nan(F), std.math.inf(F), -std.math.inf(F) };
                for (0..coords.len * coords.len) |batch| {
                    var us: [S]F = undefined;
                    var vs: [S]F = undefined;
                    var active: [S]bool = undefined;
                    for (0..S) |lane| {
                        us[lane] = coords[(batch + lane) % coords.len];
                        vs[lane] = coords[(batch / coords.len + lane * 3) % coords.len];
                        active[lane] = (batch + lane) % 3 == 0;
                    }
                    const values: [S]F = Kernel(index).sampleSIMD(us, vs, active, params, &resources);
                    for (values, us, vs, active) |value, u, v, enabled| {
                        const finite = std.math.isFinite(u) and std.math.isFinite(v);
                        const expected = if (finite and (config.pattern() != .perlin or enabled)) Kernel(index).sampleScal(u, v, params, &resources) else params.background;
                        try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
                    }
                }
            }
        }
    }
}

test "cell binned preparation budget includes temporary indices and checked addition" {
    try checkCellBinnedPreparationBudget(32, 48, 80);
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, checkCellBinnedPreparationBudget(32, 48, 79));
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, checkCellBinnedPreparationBudget(std.math.maxInt(usize), 1, std.math.maxInt(usize)));
}

test "cell binned review overlapping Gaussian adjacent scores and exp plateaus" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const Check = struct {
        fn pair(radius: F, centers: [2][2]F) !void {
            const Impl = Implementation(.{ .cell_binned = .{ .gaussian = .nine } });
            for (0..2) |order| {
                const points = [_][2]F{ centers[order], centers[1 - order] };
                var original: F = 0;
                // Compare to the original per-disk mask reduction, not the nearest helper.
                for (points) |point| {
                    const d2 = point[0] * point[0] + point[1] * point[1];
                    original = @max(original, Impl.speckleDiskMask(false, d2, radius, 0));
                }
                const xs = [_]F{ points[0][0], points[1][0] };
                const ys = [_]F{ points[0][1], points[1][1] };
                var coordinates: [18]F = @splat(0);
                @memset(coordinates[0..9], std.math.inf(F));
                @memcpy(coordinates[0..2], &xs);
                @memcpy(coordinates[9..11], &ys);
                const counts = [_]u8{2};
                const p: Speckle2DParams = .{ .pattern = .gaussian, .evaluator = .cell_binned, .neighbor_count = .nine, .radius_mean = radius, .cells_per_uv = .{ 1, 1 }, .foreground = 0.91, .background = -0.0 };
                const binned: CellBinnedSpeckle2D = .{ .params = p, .offsets = &.{}, .dims = .{ 1, 1 }, .records = .{ .strided = .{ .coordinates = &coordinates, .counts = &counts } } };
                // Borrowed stack fixtures: no owning-resource deinit is appropriate.
                const resources: Resources = .{ .data = .{ .cell_binned = binned } };
                const expected = p.background + original * (p.foreground - p.background);
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(Impl.evalCellBinnedSpeckle2D(false, 0, 0, binned))));
                const lanes: [S]F = Impl.samplePreparedSIMD(false, @splat(0), @splat(0), @splat(false), p, &resources);
                for (lanes) |value| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
            }
        }
    };
    const base: F = 0.015625;
    const ulp = std.math.nextAfter(F, base, std.math.inf(F)) - base;
    var plateaus: usize = 0;
    for (0..16) |ii| {
        const y0 = @sqrt(@as(F, @floatFromInt(ii)) * ulp);
        const y1 = @sqrt(@as(F, @floatFromInt(ii + 1)) * ulp);
        const a = base + y0 * y0;
        const b = base + y1 * y1;
        try std.testing.expectEqual(std.math.nextAfter(F, a, std.math.inf(F)), b);
        const ea = -0.5 * a / 0.0625; // radius .75 gives exactly sigma² = .0625.
        const eb = -0.5 * b / 0.0625;
        try std.testing.expectEqual(std.math.nextAfter(F, ea, -std.math.inf(F)), eb);
        if (@as(Bits, @bitCast(@exp(ea))) == @as(Bits, @bitCast(@exp(eb)))) plateaus += 1;
        try Check.pair(0.75, .{ .{ 0.125, y0 }, .{ 0.125, y1 } });
    }
    try std.testing.expect(plateaus > 0);
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    for ([_]F{ @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
        const sigma = radius / 3;
        try std.testing.expect(radius * radius > 0);
        try std.testing.expectEqual(@as(F, 0), sigma * sigma);
        try Check.pair(radius, .{ .{ 0, 0 }, .{ @sqrt(smallest), 0 } });
    }
}

test "cell binned records preserve original bits at supports faces colors and SIMD lanes" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (generation_configs) |config| {
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const Impl = Implementation(config);
        const soft = comptime config.edges() == .soft;
        const single = comptime config.neighborhood() == .one;
        for ([_]F{ 0, 0.7, 1 }) |occupancy| {
            for (0..10) |variation| {
                const radius: F = switch (variation) {
                    0 => 0.2,
                    1 => std.math.floatMin(F),
                    2 => if (single) 0.45 else 0.95,
                    else => 0.3,
                };
                const params: Speckle2DParams = .{
                    .evaluator = std.meta.activeTag(config),
                    .pattern = config.pattern().?,
                    .neighbor_count = config.neighborhood(),
                    .seed = if (variation == 0) 43498 else 0,
                    .cells_per_uv = if (variation == 9) .{ 0.03125, 0.0625 } else if (variation == 8) .{ 4, 3 } else .{ 3.25, 2.75 },
                    .occupancy = occupancy,
                    .radius_mean = radius,
                    .radius_jitter = if (variation == 0) radius else if (variation > 2 and variation < 7) 0.1 else 0,
                    .edge_softness = if (soft) 0.05 else 0,
                    .foreground = if (variation == 4 or variation == 6) -0.0 else if (variation == 5) 0.0 else 0.91,
                    .background = if (variation == 3 or variation == 5 or variation == 6 or variation == 9) -0.0 else 0.23,
                };
                var owned = try Resources.init(std.testing.allocator, params);
                defer owned.deinit(std.testing.allocator);
                var ref_params = params;
                ref_params.evaluator = .list_indexed;
                var reference = try Resources.init(std.testing.allocator, ref_params);
                defer reference.deinit(std.testing.allocator);
                const binned = owned.data.cell_binned;
                const count = switch (binned.records) {
                    .disks => |records| records.len,
                    .gaussian => |records| records.len,
                    .strided => binned.recordCount(),
                };
                try std.testing.expectEqual(count, binned.recordCount());
                for (0..binned.dims[0] * binned.dims[1]) |cell| {
                    const range = binned.range(cell);
                    try std.testing.expect(range[0] <= range[1] and range[1] - range[0] <= 9);
                }
                for (0..128) |batch| {
                    var us: [S]F = undefined;
                    var vs: [S]F = undefined;
                    var active: [S]bool = undefined;
                    for (0..S) |lane| {
                        const index = batch * S + lane;
                        us[lane] = @as(F, @floatFromInt((index * 7919 + 17) % 65521)) / 60000.0 - 0.05;
                        vs[lane] = @as(F, @floatFromInt((index * 104729 + 31) % 65521)) / 60000.0 - 0.05;
                        active[lane] = lane % 2 == 0 and batch % 3 != 0;
                        if (batch < 8) us[lane] = switch ((batch + lane) % 8) {
                            0 => 0,
                            1 => 1,
                            2 => -0.0,
                            3 => std.math.nan(F),
                            4 => std.math.inf(F),
                            5 => -std.math.inf(F),
                            else => 0.5,
                        };
                    }
                    const expected: [S]F = sampleSIMD(us, vs, active, ref_params, &reference);
                    const actual: [S]F = sampleSIMD(us, vs, active, params, &owned);
                    for (expected, actual, us, vs) |before, after, u, v| {
                        try std.testing.expectEqual(@as(Bits, @bitCast(before)), @as(Bits, @bitCast(after)));
                        if (std.math.isFinite(u) and std.math.isFinite(v)) {
                            const value = sampleScal(u, v, params, &owned);
                            try std.testing.expectEqual(@as(Bits, @bitCast(sampleScal(u, v, ref_params, &reference))), @as(Bits, @bitCast(value)));
                            // At zero occupancy, preserve the existing list's arithmetic
                            // background mapping, including its signed-zero behavior.
                            if (occupancy > 0) try std.testing.expectEqual(@as(Bits, @bitCast(Impl.evalSpeckle2DImpl(soft, u, v, params))), @as(Bits, @bitCast(value)));
                        }
                    }
                }
                // Independently generate owners, including zero-radius records and halo disks.
                const list = try Impl.generateSpeckleList2D(std.testing.allocator, params);
                defer std.testing.allocator.free(list.disks);
                for (list.disks) |disk| {
                    const support = disk.radius + params.edge_softness;
                    for (0..2) |axis| {
                        for ([_]F{ -support, 0, support }) |delta| {
                            const edge = (disk.center[axis] + delta) / params.cells_per_uv[axis];
                            for ([_]F{ edge, std.math.nextAfter(F, edge, -std.math.inf(F)), std.math.nextAfter(F, edge, std.math.inf(F)) }) |coordinate| {
                                const u = if (axis == 0) coordinate else disk.center[0] / params.cells_per_uv[0];
                                const v = if (axis == 1) coordinate else disk.center[1] / params.cells_per_uv[1];
                                const expected = sampleScal(u, v, ref_params, &reference);
                                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(u, v, params, &owned))));
                            }
                        }
                    }
                }
                for (0..2) |axis| {
                    for (0..binned.dims[axis]) |ii| {
                        const edge = @as(F, @floatFromInt(ii)) / params.cells_per_uv[axis];
                        for ([_]F{ edge, std.math.nextAfter(F, edge, 0), std.math.nextAfter(F, edge, std.math.inf(F)) }) |coordinate| {
                            const u = if (axis == 0) coordinate else 0.5;
                            const v = if (axis == 1) coordinate else 0.5;
                            const expected = sampleScal(u, v, ref_params, &reference);
                            try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(u, v, params, &owned))));
                        }
                    }
                }
            }
        }
    }
}

test "cell binned preparation budget and allocation failures are checked" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const params: Speckle2DParams = .{ .evaluator = .cell_binned, .cells_per_uv = .{ 65534, 65534 } };
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, Resources.init(std.testing.failing_allocator, params));
    var wide = params;
    wide.cells_per_uv = .{ 100, 100 };
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, wide));
    // Counts fit the cell limit, but full-support duplication exceeds the byte budget.
    wide.cells_per_uv = .{ 1800, 1800 };
    wide.radius_mean = 0.99;
    wide.radius_jitter = 0.01;
    wide.occupancy = 1;
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, Resources.init(std.testing.allocator, wide));
    if (F == f64) {
        wide.cells_per_uv = .{ 35_184_372_088_831, 35_184_372_088_831 };
        try std.testing.expectError(error.SpeckleCellBinsTooLarge, Resources.init(std.testing.failing_allocator, wide));
    }
    for ([_]F{ 0, 0.08 }) |jitter| {
        for ([_]struct { pattern: speckleconfig.Pattern, softness: F }{
            .{ .pattern = .disk, .softness = 0 },
            .{ .pattern = .disk, .softness = 0.04 },
            .{ .pattern = .gaussian, .softness = 0 },
        }) |shape| {
            try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
                fn run(allocator: std.mem.Allocator, pattern: speckleconfig.Pattern, softness: F, radius_jitter: F) !void {
                    var resources = try Resources.init(allocator, .{ .evaluator = .cell_binned, .pattern = pattern, .edge_softness = softness, .radius_jitter = radius_jitter, .cells_per_uv = .{ 3.25, 2.5 } });
                    defer resources.deinit(allocator);
                }
            }.run, .{ shape.pattern, shape.softness, jitter });
        }
    }
}

test "cell binned Gaussian nearest reductions preserve underflowed sigma squared" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    inline for (generation_configs) |config| {
        if (comptime config.pattern() != .gaussian) continue;
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const Impl = Implementation(config);
        for ([_]F{ @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
            const params: Speckle2DParams = .{ .evaluator = std.meta.activeTag(config), .pattern = .gaussian, .neighbor_count = config.neighborhood(), .cells_per_uv = .{ 1, 1 }, .occupancy = 1, .radius_mean = radius, .foreground = 0.91, .background = 0.23 };
            var resources = try Resources.init(std.testing.allocator, params);
            defer resources.deinit(std.testing.allocator);
            const disk = Impl.speckleDiskForCell(false, 0, 0, params).?;
            const expected = Impl.evalSpeckle2DImpl(false, disk.center[0], disk.center[1], params);
            try std.testing.expect(std.math.isFinite(expected));
            try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(disk.center[0], disk.center[1], params, &resources))));
            const lanes: [S]F = sampleSIMD(@splat(disk.center[0]), @splat(disk.center[1]), @splat(true), params, &resources);
            for (lanes) |value| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
        }
    }
}

test "cell binned wide procedural grids retain rounded face and endpoint membership" {
    @setEvalBranchQuota(100_000);
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (generation_configs) |config| {
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const Impl = Implementation(config);
        const soft = comptime config.edges() == .soft;
        const params: Speckle2DParams = .{
            .evaluator = std.meta.activeTag(config),
            .pattern = config.pattern().?,
            .neighbor_count = config.neighborhood(),
            .cells_per_uv = .{ 65534, 0.03125 },
            .radius_mean = 0.35,
            .radius_jitter = 0,
            .edge_softness = if (soft) 0.04 else 0,
            .occupancy = 0.7,
            .foreground = 0.91,
            .background = -0.0,
        };
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        for ([_]F{ 0, 0.5, 1, 65533.0 / 65534.0, 1.0 / 65534.0 }) |face| {
            for ([_]F{ face, std.math.nextAfter(F, face, -std.math.inf(F)), std.math.nextAfter(F, face, std.math.inf(F)) }) |u| {
                for ([_]F{ 0, 0.5, 1 }) |v| {
                    const expected = Impl.evalSpeckle2DImpl(soft, u, v, params);
                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(u, v, params, &resources))));
                    const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(false), params, &resources);
                    for (lanes) |value| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
                }
            }
        }
    }
}

test "strip indexed zero radius soft disk coverage and default gate" {
    const params: Speckle2DParams = .{ .evaluator = .list_indexed, .neighbor_count = .one, .seed = 43498, .cells_per_uv = .{ 1, 1 }, .occupancy = 1, .radius_mean = 0.2, .radius_jitter = 0.2, .edge_softness = 0.05 };
    if (comptime !buildconfig.enable_all_evaluators) {
        try std.testing.expectError(error.SpeckleOverridesDisabled, params.resolve());
        return;
    }
    var strip = try Resources.init(std.testing.allocator, params);
    defer strip.deinit(std.testing.allocator);
    var reference_params = params;
    reference_params.evaluator = .list_naive;
    var reference = try Resources.init(std.testing.allocator, reference_params);
    defer reference.deinit(std.testing.allocator);
    const table = strip.data.strip_list;
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

test "cell binned canonical layouts padding and rounded coefficients" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    var checked: usize = 0;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .cell_binned) continue;
        checked += 1;
        for ([_]F{ 0, 0.08 }) |jitter| {
            const p: Speckle2DParams = .{ .evaluator = .cell_binned, .pattern = config.pattern().?, .neighbor_count = config.neighborhood(), .edge_softness = if (config.edges() == .soft) 0.04 else 0, .cells_per_uv = .{ 3.25, 2.75 }, .radius_mean = 0.3, .radius_jitter = jitter, .occupancy = 0.7 };
            var owned = try Resources.init(std.testing.allocator, p);
            defer owned.deinit(std.testing.allocator);
            const binned = owned.data.cell_binned;
            const expected: std.meta.Tag(CellBinnedRecords) = if (jitter == 0) .strided else if (p.pattern == .gaussian) .gaussian else .disks;
            try std.testing.expectEqual(expected, std.meta.activeTag(binned.records));
            if (jitter == 0) {
                const strided = binned.records.strided;
                const cells = binned.dims[0] * binned.dims[1];
                try std.testing.expectEqual(@as(usize, 0), binned.offsets.len);
                try std.testing.expectEqual(cells * 18, strided.coordinates.len);
                try std.testing.expectEqual(cells, strided.counts.len);
                const xs = strided.coordinates[0 .. cells * 9];
                const ys = strided.coordinates[cells * 9 ..];
                for (strided.counts, 0..) |count, cell| {
                    try std.testing.expect(count <= 9);
                    for (count..9) |ii| {
                        try std.testing.expectEqual(std.math.inf(F), xs[cell * 9 + ii]);
                        try std.testing.expectEqual(@as(F, 0), ys[cell * 9 + ii]);
                    }
                }
                try std.testing.expectEqual(cells * (18 * @sizeOf(F) + 1), binned.byteSize());
            } else if (p.pattern == .gaussian) {
                // Independent owner generation checks the cached rounding, not another layout.
                for (binned.records.gaussian) |record| {
                    var found = false;
                    var y: i64 = -1;
                    while (y <= 3) : (y += 1) {
                        var x: i64 = -1;
                        while (x <= 4) : (x += 1) {
                            const disk = CellBinnedIndependentReference.disk(p, x, y) orelse continue;
                            if (!std.meta.eql(record.center, disk.xy)) continue;
                            const sigma = disk.radius / 3;
                            try std.testing.expectEqual(disk.radius * disk.radius, record.outer2);
                            try std.testing.expectEqual(sigma * sigma, record.sigma2);
                            found = true;
                        }
                    }
                    try std.testing.expect(found);
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 9), checked);
}

test "cell binned fixed stride padded independent Gaussian masks and direct budget" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const Impl = Implementation(.{ .cell_binned = .{ .gaussian = .nine } });
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    for ([_]F{ 0.75, @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
        for (0..3) |count| {
            var xs: [9]F = @splat(std.math.inf(F));
            const ys: [9]F = @splat(0);
            xs[0] = if (count == 0) std.math.inf(F) else 0;
            xs[1] = if (count < 2) std.math.inf(F) else @sqrt(smallest);
            const offsets = [_]usize{ 0, count };
            const counts = [_]u8{@intCast(count)};
            const p: Speckle2DParams = .{ .evaluator = .cell_binned, .pattern = .gaussian, .radius_mean = radius, .cells_per_uv = .{ 1, 1 }, .foreground = 0.91, .background = -0.0 };
            const binned: CellBinnedSpeckle2D = .{ .params = p, .offsets = &offsets, .dims = .{ 1, 1 }, .records = .{ .strided = .{ .coordinates = &(xs ++ ys), .counts = &counts } } };
            const resources: Resources = .{ .data = .{ .cell_binned = binned } };
            var coverage: F = 0;
            for (xs, ys) |x, y| coverage = @max(coverage, Impl.speckleDiskMask(false, x * x + y * y, radius, 0));
            const expected = p.background + coverage * (p.foreground - p.background);
            try std.testing.expect(std.math.isFinite(expected));
            try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(Impl.evalCellBinnedSpeckle2D(false, 0, 0, binned))));
            const lanes: [S]F = Impl.samplePreparedSIMD(false, @splat(0), @splat(0), @splat(false), p, &resources);
            for (lanes) |actual| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
        }
    }
    // Direct preparation owns only the final padded centers and byte counts.
    const centers = 9 * 2 * @sizeOf(F);
    try checkCellBinnedPreparationBudget(1, centers, centers + 1);
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, checkCellBinnedPreparationBudget(1, centers, centers));

    const params: Speckle2DParams = .{ .evaluator = .cell_binned, .pattern = .gaussian, .neighbor_count = .nine, .cells_per_uv = .{ 2000, 2000 }, .radius_jitter = 0 };
    const bounds = Impl.speckleProceduralCellBounds(params, 0).?;
    const owners = Impl.speckleProceduralCellBounds(params, 1).?;
    try std.testing.expect(owners.count < max_speckle_cells);
    try std.testing.expect(bounds.count * (18 * @sizeOf(F) + @sizeOf(u8)) > max_cell_binned_bytes);
    // A missing or late budget check would hit this allocator and return OutOfMemory.
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, Resources.init(std.testing.failing_allocator, params));
}

test "cell binned defaults preserve independent analytic bits without overrides" {
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    for ([_]speckleconfig.Pattern{ .disk, .gaussian }) |pattern| {
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                const params: Speckle2DParams = .{
                    .pattern = pattern,
                    .edge_softness = if (pattern == .disk) 0.04 else 0,
                    .radius_mean = 0.3,
                    .radius_jitter = jitter,
                    .occupancy = occupancy,
                    .cells_per_uv = .{ 3.25, 2.75 },
                    .foreground = 0.91,
                    .background = -0.0,
                };
                const resolved = try params.resolve();
                try std.testing.expectEqual(speckleconfig.Evaluator.cell_binned, std.meta.activeTag(resolved));
                var resources = try Resources.init(std.testing.allocator, params);
                defer resources.deinit(std.testing.allocator);
                var reference_params = params;
                reference_params.neighbor_count = .nine;
                for ([_]F{ -1, 0, 1.0 / 3.25, 0.5, 1, 2 }) |u| {
                    for ([_]F{ -1, 0, 1.0 / 2.75, 0.5, 1, 2 }) |v| {
                        const expected: Bits = @bitCast(CellBinnedIndependentReference.sample(reference_params, u, v));
                        try std.testing.expectEqual(expected, @as(Bits, @bitCast(sampleScal(u, v, params, &resources))));
                        const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(false), params, &resources);
                        for (lanes) |actual| try std.testing.expectEqual(expected, @as(Bits, @bitCast(actual)));
                    }
                }
            }
        }
    }
}

test "cell binned paired vectors preserve count tails plateaus colors and borrowed params" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const Ref = Implementation(.{ .cell_binned = .{ .gaussian = .nine } });
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    const base: F = 0.015625;
    const ulp = std.math.nextAfter(F, base, std.math.inf(F)) - base;
    for ([_]F{ 0.75, @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
        for (0..10) |count| {
            for (0..2) |order| {
                var coordinates: [18]F = @splat(0);
                @memset(coordinates[0..9], std.math.inf(F));
                for (0..count) |ii| {
                    const k = if (order == 0) ii else count - ii - 1;
                    coordinates[ii] = if (radius == 0.75) 0.125 else if (k % 2 == 0) 0 else @sqrt(smallest);
                    coordinates[9 + ii] = if (radius == 0.75) @sqrt(@as(F, @floatFromInt(k)) * ulp) else 0;
                }
                for ([_][2]F{ .{ 0.91, -0.0 }, .{ -0.0, 0.83 }, .{ -0.0, -0.0 }, .{ 0.0, -0.0 }, .{ 0.17, 0.83 } }) |colors| {
                    const p: Speckle2DParams = .{ .evaluator = .cell_binned, .pattern = .gaussian, .neighbor_count = .nine, .radius_mean = radius, .cells_per_uv = .{ 1, 1 }, .foreground = colors[0], .background = colors[1] };
                    const counts = [_]u8{@intCast(count)};
                    const binned: CellBinnedSpeckle2D = .{ .params = p, .dims = .{ 1, 1 }, .offsets = &.{}, .records = .{ .strided = .{ .coordinates = &coordinates, .counts = &counts } } };
                    const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .cell_binned = binned } };
                    var coverage: F = 0;
                    for (0..count) |ii| {
                        const d2 = coordinates[ii] * coordinates[ii] + coordinates[9 + ii] * coordinates[9 + ii];
                        coverage = @max(coverage, Ref.speckleDiskMask(false, d2, radius, 0));
                    }
                    const expected = if (p.foreground == p.background) p.background else p.background + coverage * (p.foreground - p.background);
                    var borrowed = p;
                    borrowed.foreground = 0.37;
                    borrowed.background = 0.63;
                    borrowed.radius_mean = 0.2;
                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(0, 0, borrowed, &resources))));
                    const lanes: [S]F = sampleSIMD(@splat(0), @splat(0), @splat(false), borrowed, &resources);
                    for (lanes) |actual| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
                    const invalid: [S]F = sampleSIMD(@splat(std.math.nan(F)), @splat(0), @splat(true), borrowed, &resources);
                    for (invalid) |actual| try std.testing.expectEqual(@as(Bits, @bitCast(p.background)), @as(Bits, @bitCast(actual)));
                }
            }
        }
    }
}

fn directClassifiedTestImpl(comptime id: u8) type {
    return if (id == 22) Classified22 else ClassifiedNext(id);
}

fn expectDirectClassifiedPoint(comptime id: u8, resources: *const Resources, canonical: *const Resources, uv: [2]F) !void {
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const data = &resources.data.direct_classified;
    const p = data.params;
    const expected = if (data.empty or p.foreground == p.background or !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1])) p.background else CellBinnedIndependentReference.sample(p, uv[0], uv[1]);
    const actual = directClassifiedTestImpl(id).sampleScal(uv[0], uv[1], data);
    const reference = Implementation(.classified_indexed).evalClassifiedIndexedSpeckle2D(uv, canonical.data.classified);
    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual)));
    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(reference)));
    const values: [S]F = directClassifiedTestImpl(id).sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), data);
    for (values) |value| try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
}

test "direct classified independent fields boundaries and packet contracts" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    @setEvalBranchQuota(500_000);
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const Original = Implementation(.classified_indexed);
    inline for (.{ 22, 23, 34 }) |id| {
        const evaluator: speckleconfig.Evaluator = switch (id) {
            22 => .classified_binned_22,
            23 => .classified_binned_23,
            34 => .classified_binned_34,
            else => unreachable,
        };
        const config: speckleconfig.Config = @unionInit(speckleconfig.Config, @tagName(evaluator), {});
        const K = Kernel(kernelIndex(config));
        for (0..16) |variation| {
            const p: Speckle2DParams = .{
                .evaluator = evaluator,
                .neighbor_count = .nine,
                .seed = if (variation == 5) 43498 else if (variation == 9) 2636 else 0xa511e9b3,
                .cells_per_uv = if (variation == 7) .{ 0.03125, 0.0625 } else if (variation == 8) .{ std.math.nextAfter(F, 0, 1), std.math.nextAfter(F, 0, 1) } else if (variation == 9) .{ 0.01, 0.01 } else if (variation == 10) .{ 1, 1 } else .{ 3.17, 2.31 },
                .radius_mean = if (variation == 6 or variation == 8) std.math.floatMin(F) else if (variation == 11) @sqrt(std.math.floatMin(F) * std.math.floatEps(F)) * 1.5 else if (variation == 12) 1 else 0.4,
                .radius_jitter = if (variation == 5) 0.4 else if (variation == 2 or variation == 4 or variation == 13) 0.08 else 0,
                .occupancy = if (variation == 0) 0 else if (variation == 3 or variation == 4) 0.7 else if (variation == 9) 0.0001 else 1,
                .foreground = if (variation == 10 or variation == 13) -0.0 else if (variation == 7) 0.23 else 0.17,
                .background = if (variation == 0 or variation == 6 or variation == 9 or variation == 10 or variation == 14) -0.0 else if (variation == 7) 0.23 else 0.83,
            };
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            var original_params = p;
            original_params.evaluator = .classified_indexed;
            var canonical = try Resources.init(std.testing.allocator, original_params);
            defer canonical.deinit(std.testing.allocator);
            const data = &resources.data.direct_classified;
            try std.testing.expectEqual(@as(?u8, kernelIndex(config)), resources.kernel_index);
            try std.testing.expectEqual(config, kernel_configs[resources.kernel_index.?]);
            try std.testing.expectEqual(p.radius_jitter == 0, data.fixed_radius);
            try std.testing.expectEqual(canonical.data.classified.speckles.recordCount() == 0, data.empty);
            const owners = Original.speckleProceduralCellBounds(p, 1).?;
            try std.testing.expectEqual(owners.count * (if (p.radius_jitter != 0) @as(usize, 2) else 1), data.owner_visits);
            try std.testing.expect(data.peak_bytes >= data.byteSize());
            try expectDirectClassifiedLayout(id, &resources, &canonical);
            try std.testing.expectEqual(data.record_count * (if (data.fixed_radius) @as(usize, 2) else 3), data.coordinates.len);
            const scalar = K.sampleScal(0.37, 0.61, p, &resources);
            if (variation == 9) try std.testing.expect(data.empty);
            if (variation == 6) {
                try std.testing.expect(data.active_owners > 0 and !data.empty);
                try std.testing.expectEqual(@as(Bits, 0), @as(Bits, @bitCast(scalar)));
            }
            try std.testing.expectEqual(@as(Bits, @bitCast(directClassifiedTestImpl(id).sampleScal(0.37, 0.61, data))), @as(Bits, @bitCast(scalar)));
            const dispatched: [S]F = K.sampleSIMD(@splat(0.37), @splat(0.61), @splat(true), p, &resources);
            for (dispatched) |value| try std.testing.expectEqual(@as(Bits, @bitCast(scalar)), @as(Bits, @bitCast(value)));
            for ([_][2]F{ .{ -1, -1 }, .{ 0, 0 }, .{ 1, 1 }, .{ 2, 2 }, .{ std.math.nan(F), 0.5 }, .{ 0.5, std.math.inf(F) }, .{ -std.math.inf(F), 0 } }) |uv| try expectDirectClassifiedPoint(id, &resources, &canonical, uv);
            const axes = Original.speckleClassificationAxesAtResolution(if (id == 34) 8 else buildconfig.speckle_mask_samples_per_cell, data.dims, p);
            for (0..2) |axis| {
                for (0..data.dims[axis] + 1) |j| {
                    const boundary = axes[axis].boundary(j) / p.cells_per_uv[axis];
                    for ([_]F{ std.math.nextAfter(F, boundary, -std.math.inf(F)), boundary, std.math.nextAfter(F, boundary, std.math.inf(F)) }) |point| {
                        var uv = [2]F{ 0.587, 0.413 };
                        uv[axis] = point;
                        try expectDirectClassifiedPoint(id, &resources, &canonical, uv);
                    }
                }
            }
            // All microcell centers/corners exercise every emitted descriptor, not
            // merely random samples that may miss narrow ambiguous boundaries.
            for (0..data.dims[1]) |yy| {
                for (0..data.dims[0]) |xx| {
                    const lo: [2]F = .{ axes[0].boundary(xx), axes[1].boundary(yy) };
                    const hi: [2]F = .{ axes[0].upperBound(xx + 1), axes[1].upperBound(yy + 1) };
                    for ([_][2]F{ lo, hi, .{ lo[0] + (hi[0] - lo[0]) * 0.5, lo[1] + (hi[1] - lo[1]) * 0.5 } }) |point| try expectDirectClassifiedPoint(id, &resources, &canonical, .{ point[0] / p.cells_per_uv[0], point[1] / p.cells_per_uv[1] });
                }
            }
            for (0..owners.dims[1]) |yy| {
                for (0..owners.dims[0]) |xx| {
                    const x = owners.min[0] + @as(i64, @intCast(xx));
                    const y = owners.min[1] + @as(i64, @intCast(yy));
                    const disk = CellBinnedIndependentReference.disk(p, x, y) orelse continue;
                    for (0..2) |axis| {
                        for ([_]F{ -disk.radius, 0, disk.radius }) |delta| {
                            var uv: [2]F = .{ disk.xy[0] / p.cells_per_uv[0], disk.xy[1] / p.cells_per_uv[1] };
                            const boundary = (disk.xy[axis] + delta) / p.cells_per_uv[axis];
                            for ([_]F{ std.math.nextAfter(F, boundary, -std.math.inf(F)), boundary, std.math.nextAfter(F, boundary, std.math.inf(F)) }) |point| {
                                uv[axis] = point;
                                try expectDirectClassifiedPoint(id, &resources, &canonical, uv);
                            }
                        }
                    }
                }
            }
            for (0..40) |batch| {
                var us: [S]F = undefined;
                var vs: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    us[lane] = if (batch < 4) 0.37 + @as(F, @floatFromInt(lane)) * 0.0001 else @as(F, @floatFromInt((batch * 37 + lane * 113) % 271)) / 250 - 0.03;
                    vs[lane] = if (batch == 0 and lane % 2 == 0) std.math.nan(F) else if (batch == 1 and lane % 2 == 0) std.math.inf(F) else if (batch == 2 and lane % 2 == 0) -std.math.inf(F) else if (batch < 4) 0.61 else @as(F, @floatFromInt((batch * 73 + lane * 47) % 263)) / 245;
                    active[lane] = (batch + lane) % 3 != 0;
                }
                const actual: [S]F = K.sampleSIMD(us, vs, active, p, &resources);
                for (0..S) |lane| {
                    const expected = if (data.empty or p.foreground == p.background or !active[lane] or !std.math.isFinite(us[lane]) or !std.math.isFinite(vs[lane])) p.background else CellBinnedIndependentReference.sample(p, us[lane], vs[lane]);
                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
                }
            }
        }
    }
}

test "direct classified checked capacities ownership and allocation failures" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{ 22, 23, 34 }) |id| {
        const evaluator: speckleconfig.Evaluator = switch (id) {
            22 => .classified_binned_22,
            23 => .classified_binned_23,
            34 => .classified_binned_34,
            else => unreachable,
        };
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
                    fn run(allocator: std.mem.Allocator, p: Speckle2DParams) !void {
                        var resources = try Resources.init(allocator, p);
                        defer resources.deinit(allocator);
                        resources.deinit(allocator);
                        try std.testing.expectEqualDeep(Resources{}, resources);
                    }
                }.run, .{Speckle2DParams{ .evaluator = evaluator, .neighbor_count = .nine, .cells_per_uv = .{ 2.25, 1.75 }, .radius_jitter = jitter, .occupancy = occupancy }});
            }
        }
        try std.testing.expectError(error.SpeckleClassificationTooLarge, directClassifiedTestImpl(id).generate(std.testing.failing_allocator, .{ .cells_per_uv = .{ 65535, 65535 } }));
    }
    var bytes: usize = 0;
    try std.testing.expectError(error.SpeckleClassificationTooLarge, directClassifiedCharge(&bytes, std.math.maxInt(usize), 2));
    bytes = std.math.maxInt(usize);
    try std.testing.expectError(error.SpeckleClassificationTooLarge, directClassifiedCharge(&bytes, 1, 1));
    bytes = max_direct_classified_preparation_bytes;
    try std.testing.expectError(error.SpeckleClassificationTooLarge, directClassifiedCharge(&bytes, 1, 1));
}

fn expectDirectClassifiedLayout(comptime id: u8, resources: *const Resources, canonical: *const Resources) !void {
    const data = &resources.data.direct_classified;
    const params = data.params;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const original = canonical.data.classified;
    try std.testing.expectEqual(@as(usize, 0), data.indexes.len);
    try std.testing.expectEqual(@as(usize, 0), data.width);
    try std.testing.expectEqual(@as(usize, 0), data.singleton_cells);

    const logical_count = data.dims[0] * data.dims[1];
    try std.testing.expectEqual(logical_count, data.states.len);
    if (id == 34) try std.testing.expectEqual(Implementation(.classified_indexed).classifiedDimsAtResolution(8, params).?, data.dims);
    try std.testing.expectEqual(@as(usize, 0), data.descriptors.len);
    try std.testing.expectEqual(data.cell_dims[0] * data.cell_dims[1], data.counts.len);
    try std.testing.expectEqual(if (data.fixed_radius) @as(usize, 0) else data.counts.len + 1, data.offsets.len);

    if (id != 22) {
        if (id != 34) try std.testing.expectEqualSlices(u16, original.states, data.states);
        var bin_params = params;
        bin_params.evaluator = .cell_binned;
        var bins = try Resources.init(std.testing.allocator, bin_params);
        defer bins.deinit(std.testing.allocator);
        const binned = bins.data.cell_binned;
        if (data.fixed_radius) {
            try std.testing.expectEqualSlices(u8, binned.records.strided.counts, data.counts);
            try std.testing.expectEqualSlices(F, binned.records.strided.coordinates, data.coordinates);
        } else {
            for (binned.offsets, data.offsets) |expected, actual| try std.testing.expectEqual(expected, actual);
            try std.testing.expectEqual(binned.records.disks.len, data.record_count);
            for (data.counts, 0..) |count, cell| try std.testing.expectEqual(data.offsets[cell + 1] - data.offsets[cell], count);
            for (binned.records.disks, 0..) |disk, record| {
                try std.testing.expectEqual(@as(Bits, @bitCast(disk.center[0])), @as(Bits, @bitCast(data.coordinates[record])));
                try std.testing.expectEqual(@as(Bits, @bitCast(disk.center[1])), @as(Bits, @bitCast(data.coordinates[data.record_count + record])));
                try std.testing.expectEqual(@as(Bits, @bitCast(disk.radius * disk.radius)), @as(Bits, @bitCast(data.coordinates[2 * data.record_count + record])));
            }
        }
    }
}

test "direct classified poisoned storage fully assigns live payload and owner names" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const memory = try std.testing.allocator.alloc(u8, 1024 * 1024);
    defer std.testing.allocator.free(memory);
    inline for (.{ 22, 23, 34 }) |id| {
        const evaluator: speckleconfig.Evaluator = switch (id) {
            22 => .classified_binned_22,
            23 => .classified_binned_23,
            34 => .classified_binned_34,
            else => unreachable,
        };
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.17, 0.7, 1 }) |occupancy| {
                @memset(memory, 0xa5);
                var backing = std.heap.FixedBufferAllocator.init(memory);
                const p: Speckle2DParams = .{ .evaluator = evaluator, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy };
                var resources = try Resources.init(backing.allocator(), p);
                defer resources.deinit(backing.allocator());
                var original_params = p;
                original_params.evaluator = .classified_indexed;
                var canonical = try Resources.init(std.testing.allocator, original_params);
                defer canonical.deinit(std.testing.allocator);
                try expectDirectClassifiedLayout(id, &resources, &canonical);
            }
        }
    }
}

test "direct classified signed microcell conversion bounds preserve rounded grouping" {
    const Original = Implementation(.classified_indexed);
    const R = buildconfig.speckle_mask_samples_per_cell;
    const max_states = max_speckle_classification_bytes / @sizeOf(u16);
    try std.testing.expect(max_states < std.math.maxInt(i32));
    for ([_]usize{ 0, 1, R - 1, R, 65_535 * R, max_states - 1 }) |index| {
        if (F == f32 and index > 65_535 * R) continue;
        const p = directMicrocellBoundary(F, R, index);
        for ([_]F{ p, std.math.nextAfter(F, p, 0), std.math.nextAfter(F, p, std.math.inf(F)) }) |coordinate| {
            const scaled = @as(VecSF, @splat(coordinate)) * @as(VecSF, @splat(speckle_mask_samples_per_cell));
            const narrow: @Vector(S, i32) = @intFromFloat(scaled);
            const widened: [S]usize = @as(@Vector(S, usize), @intCast(narrow));
            const native: [S]usize = @as(@Vector(S, usize), @intFromFloat(scaled));
            try std.testing.expectEqualSlices(usize, &native, &widened);
        }
    }
    const dims = Original.classifiedDims(.{ .cells_per_uv = .{ 65_535, 0.000001 } }).?;
    try std.testing.expect(dims[0] * dims[1] <= max_states);
    try std.testing.expect(dims[0] <= max_states and dims[1] <= max_states);
}

test "representation local R8 exact inverse bins match exhaustive owner stamping" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Original = Implementation(.classified_indexed);
    for ([_][2]F{ .{ 3.17, 2.31 }, .{ 4, 3 }, .{ 0.03125, 0.0625 }, .{ std.math.nextAfter(F, 0, 1), std.math.nextAfter(F, 0, 1) } }) |cells| {
        for ([_]F{ 0, 0.08 }) |jitter| {
            const p: Speckle2DParams = .{ .cells_per_uv = cells, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = 0.7 };
            const data = try ClassifiedNext(34).generate(std.testing.allocator, p);
            defer data.deinit(std.testing.allocator);
            const axes = Original.speckleClassificationAxesAtResolution(8, data.dims, p);
            const owners = Original.speckleProceduralCellBounds(p, 1).?;
            for (0..data.dims[1]) |y| {
                for (0..data.dims[0]) |x| {
                    var expected: u16 = 0;
                    for (0..owners.dims[1]) |oy| {
                        for (0..owners.dims[0]) |ox| {
                            const owner: [2]i64 = .{ owners.min[0] + @as(i64, @intCast(ox)), owners.min[1] + @as(i64, @intCast(oy)) };
                            const disk = Original.speckleDiskForCell(false, owner[0], owner[1], p) orelse continue;
                            const relative_x = owner[0] - @as(i64, @intCast(x / 8));
                            const relative_y = owner[1] - @as(i64, @intCast(y / 8));
                            if (relative_x < -1 or relative_x > 1 or relative_y < -1 or relative_y > 1 or expected == 512) continue;
                            const state = Original.classifySpeckleDiskMicrocell(disk, .{ axes[0].boundary(x), axes[1].boundary(y) }, .{ axes[0].upperBound(x + 1), axes[1].upperBound(y + 1) });
                            if (state == .foreground) expected = 512 else if (state == .ambiguous) expected |= @as(u16, 1) << @as(u4, @intCast((relative_x + 1) * 3 + relative_y + 1));
                        }
                    }
                    try std.testing.expectEqual(expected, data.states[y * data.dims[0] + x]);
                }
            }
        }
    }
}

test "representation logical cap includes local R8" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{34}) |id| {
        const r: F = if (id == 34) 8 else @floatFromInt(buildconfig.speckle_mask_samples_per_cell);
        // Exceed the logical grid cap without first exceeding the owner-cell limit.
        const p: Speckle2DParams = .{ .cells_per_uv = .{ 12000 / r, 12000 / r } };
        try std.testing.expectError(error.SpeckleClassificationTooLarge, ClassifiedNext(id).generate(std.testing.failing_allocator, p));
        if (F == f64) try std.testing.expectError(error.SpeckleClassificationTooLarge, ClassifiedNext(id).generate(std.testing.failing_allocator, .{ .cells_per_uv = .{ 35_184_372_088_831, 35_184_372_088_831 } }));
    }
}

fn expectBitwiseSlice(comptime T: type, a: []const T, b: []const T) !void {
    try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));
}

fn expectIndependentClassifiedField(resources: *const Resources, p: Speckle2DParams, empty: bool) !void {
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    var borrowed = p;
    borrowed.foreground = 0.39;
    borrowed.background = 0.61;
    for (0..80) |batch| {
        var us: [S]F = undefined;
        var vs: [S]F = undefined;
        var active: [S]bool = undefined;
        for (0..S) |lane| {
            us[lane] = switch (batch % 20) {
                0 => 0,
                1 => 1,
                2 => -1,
                3 => 2,
                4 => std.math.nan(F),
                5 => std.math.inf(F),
                6 => -std.math.inf(F),
                else => @as(F, @floatFromInt((batch * 113 + lane * 37) % 521)) / 500,
            };
            vs[lane] = switch (batch % 19) {
                0 => 1,
                1 => 0,
                2 => std.math.inf(F),
                else => @as(F, @floatFromInt((batch * 17 + lane * 73) % 523)) / 500,
            };
            active[lane] = (batch + lane) % 3 != 0;
            const expected = if (empty or p.foreground == p.background or !std.math.isFinite(us[lane]) or !std.math.isFinite(vs[lane])) p.background else CellBinnedIndependentReference.sample(p, us[lane], vs[lane]);
            try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(us[lane], vs[lane], borrowed, resources))));
        }
        const actual: [S]F = sampleSIMD(us, vs, active, borrowed, resources);
        for (0..S) |lane| {
            const expected = if (!active[lane] or empty or p.foreground == p.background or !std.math.isFinite(us[lane]) or !std.math.isFinite(vs[lane])) p.background else CellBinnedIndependentReference.sample(p, us[lane], vs[lane]);
            try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
        }
    }
}

// Power-of-two endpoints and corner/nearest-point distances are an independent
// small-grid oracle; no production axis, range, stamp or certificate helper is used.
fn independentRectangularClass(comptime rx: u8, comptime ry: u8, p: Speckle2DParams, x: usize, y: usize) u2 {
    const lo: [2]F = .{ @as(F, @floatFromInt(x)) / rx, @as(F, @floatFromInt(y)) / ry };
    const hi: [2]F = .{ std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / rx, -std.math.inf(F)), std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / ry, -std.math.inf(F)) };
    const cx: i64 = @intCast(x / rx);
    const cy: i64 = @intCast(y / ry);
    var ambiguous = false;
    var oy = cy - 1;
    while (oy <= cy + 1) : (oy += 1) {
        var ox = cx - 1;
        while (ox <= cx + 1) : (ox += 1) {
            const disk = CellBinnedIndependentReference.disk(p, ox, oy) orelse continue;
            const radius2 = disk.radius * disk.radius;
            var far2: F = 0;
            for ([_]F{ lo[0], hi[0] }) |px| for ([_]F{ lo[1], hi[1] }) |py| {
                const dx = px - disk.xy[0];
                const dy = py - disk.xy[1];
                far2 = @max(far2, dx * dx + dy * dy);
            };
            if (disk.radius > 0 and far2 < radius2) return 2;
            const dx = @max(lo[0], @min(hi[0], disk.xy[0])) - disk.xy[0];
            const dy = @max(lo[1], @min(hi[1], disk.xy[1])) - disk.xy[1];
            if (dx * dx + dy * dy <= radius2) ambiguous = true;
        }
    }
    return if (ambiguous) 1 else 0;
}

fn expectRectangularBins(data: *const Classified42.Data, baseline: *const DirectClassifiedSpeckle2D, exhaustive: bool) !void {
    const K = Classified42;
    const p = data.payload.params;
    const bins = &data.payload;
    try expectBitwiseSlice(F, baseline.coordinates, bins.coordinates);
    inline for (.{ "cell_dims", "owner_dims", "record_count", "radius2", "fixed_radius", "empty", "owner_visits", "active_owners" }) |field| try std.testing.expectEqualDeep(@field(baseline, field), @field(bins, field));
    try std.testing.expectEqual(data.headers.len * 8 + bins.coordinates.len * @sizeOf(F) + (data.counts.len + data.offsets.len * 4), data.byteSize());
    try std.testing.expectEqual(data.byteSize() + K.scratch_bytes, bins.peak_bytes);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(data.headers.ptr) % @alignOf(u64));
    for (data.headers, 0..) |word, cell| {
        try std.testing.expectEqual(baseline.counts[cell], data.counts[cell]);
        const start = if (baseline.fixed_radius) cell * 9 else baseline.offsets[cell];
        if (baseline.fixed_radius) {
            try std.testing.expectEqual(start, cell * 9);
            for (baseline.counts[cell]..9) |slot| {
                try std.testing.expectEqual(std.math.inf(F), bins.coordinates[start + slot]);
                try std.testing.expectEqual(@as(F, 0), bins.coordinates[bins.record_count + start + slot]);
            }
        } else try std.testing.expectEqual(start, data.offsets[cell]);
        const fg: K.Mask = @truncate(word);
        const amb: K.Mask = @truncate(word >> @bitSizeOf(K.Mask));
        try std.testing.expectEqual(@as(K.Mask, 0), fg & amb);
        for (0..K.Rx * K.Ry) |bit| {
            const x = (cell % bins.cell_dims[0]) * K.Rx + bit % K.Rx;
            const y = (cell / bins.cell_dims[0]) * K.Ry + bit / K.Rx;
            const shift: K.Shift = @intCast(bit);
            const actual: u2 = if ((fg >> shift) & 1 != 0) 2 else if ((amb >> shift) & 1 != 0) 1 else 0;
            if (x >= bins.dims[0] or y >= bins.dims[1]) try std.testing.expectEqual(@as(u2, 0), actual) else if (exhaustive) try std.testing.expectEqual(independentRectangularClass(K.Rx, K.Ry, p, x, y), actual);
        }
    }
    {
        try expectBitwiseSlice(u8, baseline.counts, data.counts);
        try expectBitwiseSlice(u32, baseline.offsets, data.offsets);
    }
}

test "rectangular classified42 direct headers exhaustive rectangular classes and exact fields" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    {
        for (0..14) |variation| {
            const p: Speckle2DParams = .{
                .evaluator = .classified_binned_42,
                .neighbor_count = .nine,
                .seed = if (variation % 2 == 0) 43498 else 0xa511e9b3,
                .cells_per_uv = if (variation == 8) .{ 4, 3 } else if (variation == 9) .{ 0.01, 0.01 } else if (variation == 10) .{ std.math.nextAfter(F, 0, 1), 0.01 } else if (variation == 11) .{ 1023.75, 0.125 } else if (variation == 12) .{ 2047.75, 0.125 } else if (variation == 13) .{ 2047.875, 0.125 } else .{ 3.17, 2.31 },
                .radius_mean = if (variation == 4) std.math.floatMin(F) else if (variation % 2 == 0) 0.4 else 0.6,
                .radius_jitter = if (variation == 4) 0 else if (variation == 3) 0.4 else if (variation % 3 == 1) 0.08 else 0,
                .occupancy = if (variation == 0) 0 else if (variation == 9) 0.0001 else if (variation % 3 == 2) 0.7 else 1,
                .foreground = if (variation == 5 or variation == 6) -0.0 else 0.17,
                .background = if (variation == 6 or variation == 7) -0.0 else 0.83,
            };
            var bp = p;
            bp.evaluator = .classified_binned_34;
            var baseline = try Resources.init(std.testing.allocator, bp);
            defer baseline.deinit(std.testing.allocator);
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            const data = &resources.data.rect_bin_classified;
            try expectRectangularBins(data, &baseline.data.direct_classified, variation < 11);
            const expected_dims = [2]usize{ @as(usize, @intFromFloat(@floor(p.cells_per_uv[0] * @as(F, Classified42.Rx)))) + 1, @as(usize, @intFromFloat(@floor(p.cells_per_uv[1] * 4))) + 1 };
            try std.testing.expectEqual(expected_dims, data.payload.dims);
            if (variation < 10) try expectIndependentClassifiedField(&resources, p, data.payload.empty);
            // Exercise both axes' cell faces and representable neighbors independently.
            for (0..2) |axis| {
                const r: F = if (axis == 0) Classified42.Rx else 4;
                for (0..@min(data.payload.dims[axis], 24)) |j| {
                    const boundary = @as(F, @floatFromInt(j)) / r / p.cells_per_uv[axis];
                    for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |v| {
                        const u = if (axis == 0) v else @as(F, 0.37);
                        const w = if (axis == 1) v else @as(F, 0.61);
                        const expected = if (data.payload.empty or p.foreground == p.background or !std.math.isFinite(u) or !std.math.isFinite(w)) p.background else CellBinnedIndependentReference.sample(p, u, w);
                        try std.testing.expectEqual(@as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(expected)), @as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(sampleScal(u, w, p, &resources))));
                    }
                }
            }
        }
    }
}

test "rectangular classified row fragments dominance bit31 and partial physical padding" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    {
        const K = Classified42;
        const axes: K.Axes = .{ .x = .{ .dim = K.Rx, .cells_per_uv = 1 }, .y = .{ .dim = 4, .cells_per_uv = 1 } };
        const metadata: u64 = 0;
        var a = [_]u64{metadata};
        var b = [_]u64{metadata};
        const cover: SpeckleDisk2D = .{ .center = .{ 0.5, 0.5 }, .radius = 1 };
        const edge: SpeckleDisk2D = .{ .center = .{ 0.5, 0.5 }, .radius = 0.3 };
        K.stamp(&a, 1, axes, 1, .{ 0, 0 }, cover, 1);
        K.stamp(&a, 1, axes, 1, .{ 0, 0 }, edge, 0.3 * 0.3);
        K.stamp(&b, 1, axes, 1, .{ 0, 0 }, edge, 0.3 * 0.3);
        K.stamp(&b, 1, axes, 1, .{ 0, 0 }, cover, 1);
        try std.testing.expectEqualSlices(u64, &a, &b);
        try std.testing.expectEqual(std.math.maxInt(K.Mask), @as(K.Mask, @truncate(a[0])));
        try std.testing.expectEqual(@as(K.Mask, 0), @as(K.Mask, @truncate(a[0] >> @bitSizeOf(K.Mask))));
    }
}

test "rectangular classified checked logical budgets prefix ranges and allocation cleanup" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{speckleconfig.Evaluator.classified_binned_42}) |e| {
        for ([_]F{ 0, 0.08 }) |jitter| {
            const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .radius_jitter = jitter };
            try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, p));
            try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
                fn run(allocator: std.mem.Allocator, params: Speckle2DParams) !void {
                    var resources = try Resources.init(allocator, params);
                    defer resources.deinit(allocator);
                    resources.deinit(allocator);
                    try std.testing.expectEqualDeep(Resources{}, resources);
                }
            }.run, .{p});
        }
        const rx: F = 8;
        const ry: F = 4;
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 12000 / rx, 12000 / ry }, .occupancy = 0, .radius_jitter = 0.08 }));
    }

    // The same fixed payload exceeds the f64 budget but fits at f32.
    try std.testing.expectError(if (F == f64) error.SpeckleClassificationTooLarge else error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .evaluator = .classified_binned_42, .cells_per_uv = .{ 2500, 1500 } }));
}

test "rectangular classified generated zero radius nonempty underflow and empty active owner contracts" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{speckleconfig.Evaluator.classified_binned_42}) |e| {
        const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .seed = 43498, .cells_per_uv = .{ 3.17, 2.31 }, .occupancy = 1, .radius_mean = 0.4, .radius_jitter = 0.4, .foreground = 0.91, .background = -0.0 };
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        const coordinates = switch (e) {
            .classified_binned_42 => resources.data.rect_bin_classified.payload.coordinates,
            else => unreachable,
        };
        const slots = coordinates.len / 3;
        var zeros: usize = 0;
        for (coordinates[2 * slots ..], 0..) |radius2, i| {
            if (radius2 != 0) continue;
            zeros += 1;
            const u = coordinates[i] / p.cells_per_uv[0];
            const v = coordinates[slots + i] / p.cells_per_uv[1];
            const expected = CellBinnedIndependentReference.sample(p, u, v);
            try std.testing.expectEqual(@as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(expected)), @as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(sampleScal(u, v, p, &resources))));
        }
        std.debug.print("GENERATED_ZERO evaluator={s} slots={} zero_records={}\n", .{ speckleconfig.evaluatorName(e), slots, zeros });
        try std.testing.expectEqual(false, zeros == 0);
        try expectIndependentClassifiedField(&resources, p, false);
        for ([_]bool{ false, true }) |underflow| {
            const q: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .seed = if (underflow) 0 else 2636, .cells_per_uv = if (underflow) .{ 0.03125, 0.0625 } else .{ 0.01, 0.01 }, .radius_mean = if (underflow) std.math.floatMin(F) else 0.35, .occupancy = if (underflow) 1 else 0.0001, .foreground = 0.91, .background = -0.0 };
            var owned = try Resources.init(std.testing.allocator, q);
            defer owned.deinit(std.testing.allocator);
            const active = switch (e) {
                .classified_binned_42 => owned.data.rect_bin_classified.payload.active_owners,
                else => unreachable,
            };
            std.debug.print("ACTIVE_CONTRACT evaluator={s} underflow={} owners={}\n", .{ speckleconfig.evaluatorName(e), underflow, active });
            if (underflow) try std.testing.expectEqual(false, active == 0) else try std.testing.expectEqual(@as(usize, 0), active);
            try expectIndependentClassifiedField(&owned, q, active == 0);
        }
    }
}

test "rectangular classified nine live records fixed and variable fallback preserve counts and offsets" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    {
        const K = Classified42;
        for ([_]bool{ false, true }) |fixed| {
            var coordinates: [27]F = @splat(0.5);
            for (0..9) |j| {
                const radius = @as(F, @floatFromInt(j + 1)) / 32;
                coordinates[18 + j] = radius * radius;
            }
            const p: Speckle2DParams = .{ .evaluator = .classified_binned_42, .neighbor_count = .nine, .cells_per_uv = .{ 0.99, 0.99 }, .radius_mean = 0.25, .radius_jitter = if (fixed) 0 else 0.08, .foreground = 0.91, .background = -0.0 };
            const payload: ClassifiedBinPayload = .{ .params = p, .dims = .{ K.Rx, 4 }, .cell_dims = .{ 1, 1 }, .owner_dims = .{ 3, 3 }, .coordinates = coordinates[0..if (fixed) 18 else 27], .record_count = 9, .radius2 = 0.25 * 0.25, .fixed_radius = fixed, .empty = false, .active_owners = 9 };
            const word: u64 = 0xffff_ffff_0000_0000;
            const data: K.Data = .{ .payload = payload, .headers = &.{word}, .counts = &.{9}, .offsets = if (fixed) &.{} else &.{ 0, 9 } };
            const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .rect_bin_classified = data } };
            for (0..12) |batch| {
                var us: [S]F = undefined;
                var vs: [S]F = undefined;
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    us[lane] = @as(F, @floatFromInt(batch + lane)) / 20;
                    vs[lane] = 0.5;
                    active[lane] = lane % 3 != 0;
                }
                const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
                for (0..S) |lane| {
                    var covered = false;
                    for (0..9) |j| {
                        const dx = us[lane] * 0.99 - coordinates[j];
                        const dy = vs[lane] * 0.99 - coordinates[9 + j];
                        covered = covered or dx * dx + dy * dy < (if (fixed) payload.radius2 else coordinates[18 + j]);
                    }
                    const expected = p.background + @as(F, if (covered) 1 else 0) * (p.foreground - p.background);
                    try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(us[lane], vs[lane], p, &resources))));
                    try std.testing.expectEqual(@as(Bits, @bitCast(if (active[lane]) expected else p.background)), @as(Bits, @bitCast(actual[lane])));
                }
            }
        }
    }
}

test "grouped classified46 actual generation payloads stay42 bitwise with independent field samples" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{speckleconfig.Evaluator.classified_binned_46}) |e| {
        for (0..18) |variation| {
            const p: Speckle2DParams = .{
                .evaluator = e,
                .neighbor_count = .nine,
                .seed = if (variation % 2 == 0) 43498 else 0xa511e9b3,
                .cells_per_uv = if (variation == 8) .{ 4, 3 } else if (variation == 9) .{ 0.01, 0.01 } else if (variation == 10) .{ std.math.nextAfter(F, 0, 1), 0.01 } else if (variation == 11) .{ 1023.75, 0.125 } else if (variation == 12) .{ 2047.75, 0.125 } else if (variation == 13) .{ 2047.875, 0.125 } else .{ 3.17, 2.31 },
                .radius_mean = if (variation == 4 or variation == 17) std.math.floatMin(F) else if (variation % 2 == 0) 0.4 else 0.6,
                .radius_jitter = if (variation == 4 or variation == 17) 0 else if (variation == 3 or variation == 14) 0.4 else if (variation % 3 == 1) 0.08 else 0,
                .occupancy = if (variation == 0) 0 else if (variation == 9 or variation == 16) 0.0001 else if (variation % 3 == 2) 0.7 else 1,
                .foreground = if (variation == 5 or variation == 6) -0.0 else 0.17,
                .background = if (variation == 6 or variation == 7 or variation >= 16) -0.0 else 0.83,
            };
            var bp = p;
            bp.evaluator = .classified_binned_42;
            var baseline = try Resources.init(std.testing.allocator, bp);
            defer baseline.deinit(std.testing.allocator);
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            const a = baseline.data.rect_bin_classified;
            const b = resources.data.rect_bin_classified;
            try std.testing.expectEqual(@as(?speckleconfig.Evaluator, e), b.payload.params.evaluator);
            try std.testing.expectEqual(try p.resolve(), kernel_configs[resources.kernel_index.?]);
            try std.testing.expect(resources.kernel_index != baseline.kernel_index);
            try expectBitwiseSlice(u64, a.headers, b.headers);
            try expectBitwiseSlice(F, a.payload.coordinates, b.payload.coordinates);
            try expectBitwiseSlice(u8, a.counts, b.counts);
            try expectBitwiseSlice(u32, a.offsets, b.offsets);
            inline for (.{ "dims", "cell_dims", "owner_dims", "record_count", "radius2", "fixed_radius", "empty", "owner_visits", "active_owners", "peak_bytes" }) |field| try std.testing.expectEqualDeep(@field(a.payload, field), @field(b.payload, field));
            var normalized = b.payload.params;
            normalized.evaluator = .classified_binned_42;
            try std.testing.expectEqualDeep(a.payload.params, normalized);
            try std.testing.expectEqual(a.byteSize(), b.byteSize());
            try std.testing.expect(b.payload.cell_dims[0] * b.payload.cell_dims[1] <= b.payload.owner_dims[0] * b.payload.owner_dims[1]);
            if (variation < 10 or variation >= 14) try expectIndependentClassifiedField(&resources, p, b.payload.empty);
        }
    }
}

// Synthetic full-bin lists deliberately isolate count-bounded fallback, including
// a final CSR allocation with no extra next-bin/dummy/padded record available.
fn independentBinHit(data: RectBinClassifiedSpeckle2D, cell: usize, px: F, py: F) bool {
    const p = &data.payload;
    const first = if (p.fixed_radius) cell * 9 else data.offsets[cell];
    for (0..data.counts[cell]) |j| {
        const index = first + j;
        const dx = px - p.coordinates[index];
        const dy = py - p.coordinates[p.record_count + index];
        const rr = if (p.fixed_radius) p.radius2 else p.coordinates[2 * p.record_count + index];
        if (dx * dx + dy * dy < rr) return true;
    }
    return false;
}

test "grouped classified46 representative plate sphere grids preserve full prepared payload and field bits" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{speckleconfig.Evaluator.classified_binned_46}) |e| {
        for ([_][2]F{ .{ 320, 192 }, .{ 256, 160 } }) |cells| for ([_]F{ 0, 0.08 }) |jitter| {
            const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = cells, .seed = 0xa511e9b3, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = 0.7, .foreground = 0.91, .background = -0.0 };
            var bp = p;
            bp.evaluator = .classified_binned_42;
            var baseline = try Resources.init(std.testing.allocator, bp);
            defer baseline.deinit(std.testing.allocator);
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            const a = baseline.data.rect_bin_classified;
            const b = resources.data.rect_bin_classified;
            try expectBitwiseSlice(u64, a.headers, b.headers);
            try expectBitwiseSlice(F, a.payload.coordinates, b.payload.coordinates);
            try expectBitwiseSlice(u8, a.counts, b.counts);
            try expectBitwiseSlice(u32, a.offsets, b.offsets);
            try std.testing.expectEqual(a.payload.peak_bytes, b.payload.peak_bytes);
            try expectIndependentClassifiedField(&resources, p, b.payload.empty);
        };
    }
}

test "grouped classified46 group width masks2 4 8 progress and exact subgroup broadcasts" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{ 2, 4, 8 }) |W| {
        const Bits = std.meta.Int(.unsigned, W);
        for ([_]usize{ 1, 2, W }) |groups| {
            var cells: [W]usize = undefined;
            for (&cells, 0..) |*cell, lane| cell.* = lane % groups;
            for (0..@as(usize, 1) << W) |pattern| {
                const original: Bits = @intCast(pattern);
                const lanes: [W]bool = @as(@Vector(W, bool), @bitCast(original));
                for (lanes, 0..) |lane, i| try std.testing.expectEqual(pattern & (@as(usize, 1) << @intCast(i)) != 0, lane);
                var left = original;
                var visited: Bits = 0;
                var iterations: usize = 0;
                while (left != 0) {
                    const first: usize = @ctz(left);
                    const same = @as(@Vector(W, usize), cells) == @as(@Vector(W, usize), @splat(cells[first]));
                    const group = left & @as(Bits, @bitCast(same));
                    var expected: Bits = 0;
                    for (0..W) |lane| if (left & (@as(Bits, 1) << @intCast(lane)) != 0 and cells[lane] == cells[first]) {
                        expected |= @as(Bits, 1) << @intCast(lane);
                    };
                    try std.testing.expectEqual(expected, group);
                    try std.testing.expect(group != 0 and visited & group == 0);
                    visited |= group;
                    left &= ~group;
                    iterations += 1;
                    try std.testing.expect(iterations <= W);
                }
                try std.testing.expectEqual(original, visited);
            }
        }
    }
    // Instantiate the actual helper for the small width as well as native-width roots.
    inline for (.{ 2, 4, 8 }) |W| {
        const counts: [2]u8 = .{ 1, 0 };
        const offsets: [3]u32 = .{ 0, 1, 1 };
        const coordinates = [_]F{ 0.5, 0.5, 0.25 };
        const bins: ClassifiedBinPayload = .{ .params = .{}, .dims = .{ 16, 4 }, .cell_dims = .{ 2, 1 }, .owner_dims = .{ 4, 3 }, .coordinates = &coordinates, .record_count = 1, .radius2 = 0.25, .fixed_radius = false, .empty = false };
        var headers: [2]u64 = @splat(0);
        const data: RectBinClassifiedSpeckle2D = .{ .payload = bins, .headers = &headers, .counts = &counts, .offsets = &offsets };
        var cells: [W]usize = undefined;
        for (&cells, 0..) |*cell, lane| cell.* = lane % 2;
        for (0..@as(usize, 1) << W) |mask| {
            const active: @Vector(W, bool) = @bitCast(@as(std.meta.Int(.unsigned, W), @intCast(mask)));
            const hits: [W]bool = Classified46.groupHits(W, @splat(0.5), @splat(0.5), cells, active, &bins, &data);
            for (hits, 0..) |hit, lane| try std.testing.expectEqual(mask & (@as(usize, 1) << @intCast(lane)) != 0 and cells[lane] == 0, hit);
        }
    }
}

fn independentClippedOwnerClass(p: Speckle2DParams, x: usize, y: usize) u2 {
    const lo: [2]F = .{ @as(F, @floatFromInt(x)) / 8, @as(F, @floatFromInt(y)) / 4 };
    const hi: [2]F = .{ @min(std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / 8, -std.math.inf(F)), p.cells_per_uv[0]), @min(std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / 4, -std.math.inf(F)), p.cells_per_uv[1]) };
    const cx: i64 = @intCast(x / 8);
    const cy: i64 = @intCast(y / 4);
    var intersects = false;
    var oy = cy - 1;
    while (oy <= cy + 1) : (oy += 1) {
        var ox = cx - 1;
        while (ox <= cx + 1) : (ox += 1) {
            const disk = CellBinnedIndependentReference.disk(p, ox, oy) orelse continue;
            const r2 = disk.radius * disk.radius;
            var far2: F = 0;
            for ([_]F{ lo[0], hi[0] }) |px| for ([_]F{ lo[1], hi[1] }) |py| {
                const dx = px - disk.xy[0];
                const dy = py - disk.xy[1];
                far2 = @max(far2, dx * dx + dy * dy);
            };
            if (disk.radius > 0 and far2 < r2) return 2;
            const dx = @max(lo[0], @min(hi[0], disk.xy[0])) - disk.xy[0];
            const dy = @max(lo[1], @min(hi[1], disk.xy[1])) - disk.xy[1];
            if (dx * dx + dy * dy <= r2) intersects = true;
        }
    }
    return if (intersects) 1 else 0;
}

fn rectangularHeaderClass(word: u64, bit: u5) u2 {
    const fg = (word >> bit) & 1 != 0;
    const amb = (word >> (@as(u6, bit) + 32)) & 1 != 0;
    return if (fg and amb) 3 else if (fg) 2 else if (amb) 1 else 0;
}

test "bins-first classified49 bins first clipped owner certificates ordinary singleton classes exact payload and reachable field" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    var terminal_differences: usize = 0;
    var interior_checked: usize = 0;
    var singleton_cells: usize = 0;
    var regular_cells: usize = 0;
    for (0..28) |variation| {
        const p: Speckle2DParams = .{
            .evaluator = .classified_binned_49,
            .neighbor_count = .nine,
            .seed = if (variation % 2 == 0) 43498 else 0xa511e9b3,
            .cells_per_uv = switch (variation) {
                8 => .{ 4, 3 },
                9 => .{ 0.01, 0.01 },
                10 => .{ std.math.nextAfter(F, 0, 1), 0.01 },
                11 => .{ 1023.75, 0.125 },
                12 => .{ 2047.75, 0.125 },
                13 => .{ 2047.875, 0.125 },
                18 => .{ 3.125, 2.25 },
                19 => .{ 3.17, 2.375 },
                20 => .{ 0.125, 0.25 },
                21 => .{ 0.125, std.math.nextAfter(F, 0, 1) },
                else => .{ 3.17, 2.31 },
            },
            .radius_mean = if (variation == 4 or variation == 17) std.math.floatMin(F) else if (variation % 2 == 0) 0.4 else 0.6,
            .radius_jitter = if (variation == 4 or variation == 17) 0 else if (variation == 3 or variation == 14) 0.4 else if (variation % 3 == 1) 0.08 else 0,
            .occupancy = if (variation == 0) 0 else if (variation == 9 or variation == 16) 0.0001 else if (variation % 3 == 2) 0.7 else 1,
            .foreground = if (variation == 5 or variation == 6) -0.0 else 0.17,
            .background = if (variation == 6 or variation == 7 or variation >= 16) -0.0 else 0.83,
        };
        var bp = p;
        bp.evaluator = .classified_binned_46;
        var baseline = try Resources.init(std.testing.allocator, bp);
        defer baseline.deinit(std.testing.allocator);
        var actual = try Resources.init(std.testing.allocator, p);
        defer actual.deinit(std.testing.allocator);
        const a = baseline.data.rect_bin_classified;
        const b = actual.data.rect_bin_classified;
        try std.testing.expectEqual(.classified_binned_49, b.payload.params.evaluator.?);
        try std.testing.expectEqual(speckleconfig.Config.classified_binned_46, kernel_configs[actual.kernel_index.?]);
        try std.testing.expectEqual(baseline.kernel_index, actual.kernel_index);
        try expectBitwiseSlice(F, a.payload.coordinates, b.payload.coordinates);
        try expectBitwiseSlice(u8, a.counts, b.counts);
        try expectBitwiseSlice(u32, a.offsets, b.offsets);
        inline for (.{ "dims", "cell_dims", "owner_dims", "record_count", "radius2", "fixed_radius", "empty", "owner_visits", "active_owners" }) |field| try std.testing.expectEqualDeep(@field(a.payload, field), @field(b.payload, field));
        try std.testing.expectEqual(a.byteSize(), b.byteSize());
        try std.testing.expectEqual(a.payload.peak_bytes + 960, b.payload.peak_bytes);
        var normalized = b.payload.params;
        normalized.evaluator = .classified_binned_46;
        try std.testing.expectEqualDeep(a.payload.params, normalized);
        try std.testing.expectEqual(b.byteSize() + Classified49.scratch_bytes, b.payload.peak_bytes);
        for (b.headers, b.counts, 0..) |word, count, cell| {
            try std.testing.expect(count <= 9);
            const start = if (b.payload.fixed_radius) cell * 9 else b.offsets[cell];
            try std.testing.expect(start + count <= b.payload.record_count);
            if (count == 0) try std.testing.expectEqual(@as(u64, 0), word);
            try std.testing.expectEqual(@as(u32, 0), @as(u32, @truncate(word)) & @as(u32, @truncate(word >> 32)));
            for (0..32) |bit| {
                const x = (cell % b.payload.cell_dims[0]) * 8 + bit % 8;
                const y = (cell / b.payload.cell_dims[0]) * 4 + bit / 8;
                const state = rectangularHeaderClass(word, @intCast(bit));
                if (x >= b.payload.dims[0] or y >= b.payload.dims[1]) {
                    try std.testing.expectEqual(@as(u2, 0), state);
                    continue;
                }
                if (count == 1) singleton_cells += 1;
                regular_cells += 1;
                try std.testing.expectEqual(independentClippedOwnerClass(p, x, y), state);
                const old = rectangularHeaderClass(a.headers[cell], @intCast(bit));
                const terminal = std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / 8, -std.math.inf(F)) > p.cells_per_uv[0] or std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / 4, -std.math.inf(F)) > p.cells_per_uv[1];
                if (old != state) {
                    try std.testing.expect(terminal);
                    terminal_differences += 1;
                } else if (!terminal) interior_checked += 1;
            }
        }
        if (variation < 11 or variation >= 14) try expectIndependentClassifiedField(&actual, p, b.payload.empty);
        // Large cached/uncached domains still check exact selected packets against42.
        for (0..32) |batch| {
            var us: [S]F = undefined;
            var vs: [S]F = undefined;
            for (0..S) |lane| {
                us[lane] = if (batch == 0) 1 else @as(F, @floatFromInt((batch * 73 + lane * 37) % 257)) / 256;
                vs[lane] = if (batch == 1) 1 else @as(F, @floatFromInt((batch * 17 + lane * 53) % 259)) / 256;
            }
            const expected: [S]F = sampleSIMD(us, vs, @splat(true), bp, &baseline);
            const result: [S]F = sampleSIMD(us, vs, @splat(true), p, &actual);
            try expectBitwiseSlice(F, &expected, &result);
        }
    }
    try std.testing.expect(singleton_cells != 0 and regular_cells != 0 and interior_checked != 0);
    std.debug.print("CLIPPED49 interior_checked={d} terminal_differences={d} singleton_cells={d} regular_cells={d}\n", .{ interior_checked, terminal_differences, singleton_cells, regular_cells });
}

test "classified bins fallback counts0 through9 all hit positions groups masks and final CSR tails" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    const cells_num = S;
    var packets: usize = 0;
    inline for ([_]bool{ false, true }) |fixed| {
        for (0..10) |amount| {
            const slots = cells_num * (if (fixed) @as(usize, 9) else amount);
            const planes: usize = if (fixed) 2 else 3;
            const coordinates = try std.testing.allocator.alloc(F, slots * planes);
            defer std.testing.allocator.free(coordinates);
            var headers: [cells_num]u64 = @splat(0xffff_ffff_0000_0000);
            var counts: [cells_num]u8 = @splat(@intCast(amount));
            var offsets: [cells_num + 1]u32 = undefined;
            for (&offsets, 0..) |*offset, cell| offset.* = @intCast(cell * amount);
            for (0..amount + 1) |hit_index| {
                if (slots != 0) {
                    @memset(coordinates[0..slots], std.math.inf(F));
                    @memset(coordinates[slots..], 0);
                }
                for (0..cells_num) |cell| {
                    const start = if (fixed) cell * 9 else offsets[cell];
                    for (0..amount) |j| {
                        coordinates[start + j] = @as(F, @floatFromInt(cell)) + (if (j == hit_index) @as(F, 0.5) else 4);
                        coordinates[slots + start + j] = 0.5;
                        if (!fixed) coordinates[2 * slots + start + j] = 0.25 * 0.25;
                    }
                }
                for ([_]usize{ 1, 2, S }) |groups| {
                    var us: [S]F = undefined;
                    const vs: [S]F = @splat(0.5 / 0.99);
                    var chosen: [S]usize = undefined;
                    for (&us, 0..) |*u, lane| {
                        // Include the final bin in every mixed-bin pattern.
                        chosen[lane] = cells_num - 1 - lane % groups;
                        u.* = (@as(F, @floatFromInt(chosen[lane])) + 0.5) / (@as(F, @floatFromInt(cells_num)) - 0.01);
                    }
                    for (0..@as(usize, 1) << @min(S, 8)) |mask| {
                        var active: [S]bool = undefined;
                        for (&active, 0..) |*value, lane| value.* = mask & (@as(usize, 1) << @intCast(lane)) != 0;
                        inline for (.{ speckleconfig.Evaluator.classified_binned_46, speckleconfig.Evaluator.classified_binned_49 }) |e| {
                            const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = .{ @as(F, @floatFromInt(cells_num)) - 0.01, 0.99 }, .radius_mean = 0.25, .radius_jitter = if (fixed) 0 else 0.08, .foreground = 0.91, .background = -0.0 };
                            @memset(&headers, 0xffff_ffff_0000_0000);
                            const data: RectBinClassifiedSpeckle2D = .{ .payload = .{ .params = p, .dims = .{ cells_num * 8, 4 }, .cell_dims = .{ cells_num, 1 }, .owner_dims = .{ cells_num + 2, 3 }, .coordinates = coordinates, .record_count = slots, .radius2 = 0.25 * 0.25, .fixed_radius = fixed, .empty = false, .active_owners = 1 }, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
                            if (comptime e == .classified_binned_49) Classified49.classifyBins(fixed, &data, &headers);
                            const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .rect_bin_classified = data } };
                            const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
                            const reference: [S]F = Classified42.sampleSIMD(us, vs, active, &data);
                            try expectBitwiseSlice(F, &reference, &actual);
                            for (0..S) |lane| {
                                const hit = independentBinHit(data, chosen[lane], us[lane] * p.cells_per_uv[0], vs[lane] * p.cells_per_uv[1]);
                                const expected = if (active[lane]) p.background + @as(F, if (hit) 1 else 0) * (p.foreground - p.background) else p.background;
                                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
                            }
                            packets += 1;
                        }
                    }
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2 * 2 * 55 * 3 * (@as(usize, 1) << @min(S, 8))), packets);
}

test "classified bins mixed certified invalid lanes and nonempty zero radii retain raw background bits" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    inline for (.{ speckleconfig.Evaluator.classified_binned_46, speckleconfig.Evaluator.classified_binned_49 }) |e| {
        const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .seed = 43498, .radius_mean = 0.4, .radius_jitter = 0.4, .occupancy = 1, .foreground = 0.91, .background = -0.0 };
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        const data = resources.data.rect_bin_classified;
        const slots = data.payload.record_count;
        var zeros: usize = 0;
        for (data.payload.coordinates[2 * slots ..], 0..) |r2, index| {
            if (r2 != 0) continue;
            zeros += 1;
            const us: [S]F = @splat(data.payload.coordinates[index] / p.cells_per_uv[0]);
            const vs: [S]F = @splat(data.payload.coordinates[slots + index] / p.cells_per_uv[1]);
            const actual: [S]F = sampleSIMD(us, vs, @splat(true), p, &resources);
            const expected: [S]F = Classified42.sampleSIMD(us, vs, @splat(true), &data);
            try expectBitwiseSlice(F, &expected, &actual);
        }
        try std.testing.expect(zeros != 0);
        for (0..96) |batch| {
            var us: [S]F = undefined;
            var vs: [S]F = undefined;
            var active: [S]bool = undefined;
            for (0..S) |lane| {
                us[lane] = switch ((batch + lane) % 12) {
                    0 => std.math.nan(F),
                    1 => std.math.inf(F),
                    2 => -std.math.inf(F),
                    3 => -1,
                    4 => 2,
                    else => @as(F, @floatFromInt((batch * 17 + lane * 37) % 257)) / 256,
                };
                vs[lane] = if ((batch + lane) % 11 == 0) std.math.nan(F) else @as(F, @floatFromInt((batch * 7 + lane * 53) % 259)) / 256;
                active[lane] = (batch + lane) % 3 != 0;
                if (!active[lane] or !std.math.isFinite(us[lane]) or !std.math.isFinite(vs[lane])) continue;
                const expected = CellBinnedIndependentReference.sample(p, us[lane], vs[lane]);
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(us[lane], vs[lane], p, &resources))));
            }
            const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
            const expected: [S]F = Classified42.sampleSIMD(us, vs, active, &data);
            try expectBitwiseSlice(F, &expected, &actual);
        }
    }
}

test "classified bins builders initialize poisoned storage own true params and reset" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    inline for (.{ speckleconfig.Evaluator.classified_binned_42, speckleconfig.Evaluator.classified_binned_46, speckleconfig.Evaluator.classified_binned_49 }) |e| {
        for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 0.7, 1 }) |occupancy| {
            const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy };
            var expected = try Resources.init(std.testing.allocator, p);
            defer expected.deinit(std.testing.allocator);
            var buffer: [32769]u8 = @splat(0xa5);
            var fba = std.heap.FixedBufferAllocator.init(buffer[1..]);
            var actual = try Resources.init(fba.allocator(), p);
            defer actual.deinit(fba.allocator());
            const a = expected.data.rect_bin_classified;
            const b = actual.data.rect_bin_classified;
            try expectBitwiseSlice(u64, a.headers, b.headers);
            try expectBitwiseSlice(F, a.payload.coordinates, b.payload.coordinates);
            try expectBitwiseSlice(u8, a.counts, b.counts);
            try expectBitwiseSlice(u32, a.offsets, b.offsets);
            try std.testing.expectEqual(@as(usize, 0), @intFromPtr(b.headers.ptr) % @alignOf(u64));
            try std.testing.expectEqual(@as(?speckleconfig.Evaluator, e), b.payload.params.evaluator);
            actual.deinit(fba.allocator());
            try std.testing.expectEqualDeep(Resources{}, actual);
        };
        try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 3.17, 2.31 } }));
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 1500, 3000 }, .occupancy = 0, .radius_jitter = 0.08 }));
    }
}

test "classified bins explicit mixed FG BG AMB packets preserve inactive invalid and zero-count groups" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    var seen: u8 = 0;
    inline for ([_]bool{ false, true }) |fixed| {
        var headers: [S]u64 = @splat(0xaaaa_aaaa_1111_1111);
        var counts: [S]u8 = undefined;
        var offsets: [S + 1]u32 = undefined;
        offsets[0] = 0;
        for (&counts, 0..) |*n, cell| {
            n.* = @intCast(cell % 4);
            offsets[cell + 1] = offsets[cell] + n.*;
        }
        const slots = if (fixed) S * 9 else offsets[S];
        const coordinates = try std.testing.allocator.alloc(F, slots * (if (fixed) @as(usize, 2) else 3));
        defer std.testing.allocator.free(coordinates);
        @memset(coordinates[0..slots], std.math.inf(F));
        @memset(coordinates[slots..], 0);
        for (counts, 0..) |n, cell| {
            const start = if (fixed) cell * 9 else offsets[cell];
            for (0..n) |j| {
                coordinates[start + j] = @as(F, @floatFromInt(cell)) + (if (j + 1 == n) @as(F, 0.5) else 4);
                coordinates[slots + start + j] = 0.5;
                if (!fixed) coordinates[2 * slots + start + j] = 0.25 * 0.25;
            }
        }
        for ([_]usize{ 1, 2, S }) |groups| for ([_]bool{ false, true }) |invalid| {
            var us: [S]F = undefined;
            const vs: [S]F = @splat(0.5 / 0.99);
            for (&us, 0..) |*u, lane| {
                const local = (@as(F, @floatFromInt(lane % 4)) + 0.5) / 8;
                u.* = (@as(F, @floatFromInt(S - 1 - lane % groups)) + local) / (@as(F, @floatFromInt(S)) - 0.01);
                if (invalid) u.* = switch (lane) {
                    0 => std.math.nan(F),
                    1 => std.math.inf(F),
                    2 => -std.math.inf(F),
                    3 => -1,
                    4 => 2,
                    else => u.*,
                };
            }
            for (0..@as(usize, 1) << @min(S, 8)) |pattern| {
                var active: [S]bool = undefined;
                for (&active, 0..) |*value, lane| value.* = pattern & (@as(usize, 1) << @intCast(lane)) != 0;
                inline for (.{ speckleconfig.Evaluator.classified_binned_46, speckleconfig.Evaluator.classified_binned_49 }) |e| {
                    const p: Speckle2DParams = .{ .evaluator = e, .neighbor_count = .nine, .cells_per_uv = .{ @as(F, @floatFromInt(S)) - 0.01, 0.99 }, .radius_mean = 0.25, .radius_jitter = if (fixed) 0 else 0.08, .foreground = 0.91, .background = -0.0 };
                    const data: RectBinClassifiedSpeckle2D = .{ .payload = .{ .params = p, .dims = .{ S * 8, 4 }, .cell_dims = .{ S, 1 }, .owner_dims = .{ S + 2, 3 }, .coordinates = coordinates, .record_count = slots, .radius2 = 0.25 * 0.25, .fixed_radius = fixed, .empty = false }, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
                    const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .rect_bin_classified = data } };
                    const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
                    for (0..S) |lane| {
                        var expected = p.background;
                        if (active[lane] and std.math.isFinite(us[lane])) {
                            const px = @max(0.0, @min(1.0, us[lane])) * p.cells_per_uv[0];
                            const py = vs[lane] * p.cells_per_uv[1];
                            const cell: usize = @intFromFloat(@floor(px));
                            const x: usize = @intFromFloat(px * 8);
                            const y: usize = @intFromFloat(py * 4);
                            const bit: u6 = @intCast((y % 4) * 8 + x % 8);
                            const flags = headers[cell] >> bit;
                            const fg = flags & 1 != 0;
                            const amb = flags & 0x1_0000_0000 != 0;
                            seen |= if (fg) @as(u8, 1) else if (amb) 2 else 4;
                            const hit = fg or (amb and independentBinHit(data, cell, px, py));
                            expected = p.background + @as(F, if (hit) 1 else 0) * (p.foreground - p.background);
                        }
                        try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(actual[lane])));
                    }
                }
            }
        };
    }
    try std.testing.expectEqual(@as(u8, 7), seen);
}

test "classified bins every allocation failure and upstream logical owner preparation budgets" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Probe = struct {
        fn run(allocator: std.mem.Allocator, evaluator: speckleconfig.Evaluator, jitter: F, occupancy: F) !void {
            var resources = try Resources.init(allocator, .{ .evaluator = evaluator, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy });
            defer resources.deinit(allocator);
        }
    };
    inline for (.{ speckleconfig.Evaluator.classified_binned_46, speckleconfig.Evaluator.classified_binned_49 }) |e| {
        for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 1 }) |occupancy| try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{ e, jitter, occupancy });
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 1500, 3000 }, .occupancy = 0 }));
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 60_000, 70 }, .occupancy = 0 }));
        try std.testing.expectError(if (F == f64) error.SpeckleClassificationTooLarge else error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .evaluator = e, .cells_per_uv = .{ 2000, 2000 }, .occupancy = 0 }));
    }
}

fn independentClippedRecordClass(data: RectBinClassifiedSpeckle2D, x: usize, y: usize) u2 {
    const p = data.payload.params;
    const lo: [2]F = .{ @as(F, @floatFromInt(x)) / 8, @as(F, @floatFromInt(y)) / 4 };
    const hi: [2]F = .{ @min(std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / 8, -std.math.inf(F)), p.cells_per_uv[0]), @min(std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / 4, -std.math.inf(F)), p.cells_per_uv[1]) };
    const cell = (y / 4) * data.payload.cell_dims[0] + x / 8;
    const first = if (data.payload.fixed_radius) cell * 9 else data.offsets[cell];
    var intersects = false;
    for (0..data.counts[cell]) |j| {
        const index = first + j;
        const center: [2]F = .{ data.payload.coordinates[index], data.payload.coordinates[data.payload.record_count + index] };
        const rr = if (data.payload.fixed_radius) data.payload.radius2 else data.payload.coordinates[2 * data.payload.record_count + index];
        var far2: F = 0;
        for ([_]F{ lo[0], hi[0] }) |px| for ([_]F{ lo[1], hi[1] }) |py| {
            const dx = px - center[0];
            const dy = py - center[1];
            far2 = @max(far2, dx * dx + dy * dy);
        };
        if (far2 < rr) return 2;
        const dx = @max(lo[0], @min(hi[0], center[0])) - center[0];
        const dy = @max(lo[1], @min(hi[1], center[1])) - center[1];
        if (dx * dx + dy * dy <= rr) intersects = true;
    }
    return if (intersects) 1 else 0;
}

test "bins-first classified49 vector classifier all counts0 through9 partial singleton zero squared radius and final CSR" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    var checked: usize = 0;
    inline for ([_]bool{ false, true }) |fixed| for ([_]bool{ false, true }) |zero_radius| {
        for (0..10) |amount| {
            const slots = if (fixed) 18 else 2 * amount;
            const planes: usize = if (fixed) 2 else 3;
            const coordinates = try std.testing.allocator.alloc(F, slots * planes);
            defer std.testing.allocator.free(coordinates);
            @memset(coordinates[0..slots], std.math.inf(F));
            @memset(coordinates[slots..], 0);
            const counts = [_]u8{ @intCast(amount), @intCast(amount) };
            const offsets = [_]u32{ 0, @intCast(amount), @intCast(2 * amount) };
            const p: Speckle2DParams = .{ .evaluator = .classified_binned_49, .neighbor_count = .nine, .cells_per_uv = .{ 1.17, 0.31 }, .radius_mean = if (zero_radius) std.math.floatMin(F) else 0.25, .radius_jitter = if (fixed) 0 else if (zero_radius) std.math.floatMin(F) else 0.08 };
            for (0..2) |cell| for (0..amount) |j| {
                const index = (if (fixed) cell * 9 else offsets[cell]) + j;
                coordinates[index] = @as(F, @floatFromInt(cell)) + @as(F, @floatFromInt(j + 1)) / 32;
                coordinates[slots + index] = 0.125;
                if (!fixed) coordinates[2 * slots + index] = if (zero_radius) 0 else 0.0625;
            };
            var headers: [2]u64 = @splat(std.math.maxInt(u64));
            const data: RectBinClassifiedSpeckle2D = .{ .payload = .{ .params = p, .dims = .{ 10, 2 }, .cell_dims = .{ 2, 1 }, .owner_dims = .{ 4, 3 }, .coordinates = coordinates, .record_count = slots, .radius2 = if (zero_radius) 0 else 0.0625, .fixed_radius = fixed, .empty = false, .active_owners = 1 }, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
            // Real constructors zero headers before count0 is skipped.
            @memset(&headers, 0);
            Classified49.classifyBins(fixed, &data, &headers);
            for (headers, 0..) |word, cell| {
                try std.testing.expectEqual(@as(u32, 0), @as(u32, @truncate(word)) & @as(u32, @truncate(word >> 32)));
                for (0..32) |bit| {
                    const x = cell * 8 + bit % 8;
                    const y = bit / 8;
                    const expected = if (x < 10 and y < 2) independentClippedRecordClass(data, x, y) else 0;
                    try std.testing.expectEqual(expected, rectangularHeaderClass(word, @intCast(bit)));
                    checked += 1;
                }
            }
        }
    };
    try std.testing.expectEqual(@as(usize, 2560), checked);
}

test "bins-first classified49 alias Kernel46 and unprepared raw finite inactive dispatch preserve separate contracts" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    try std.testing.expectEqual(kernelIndex(.classified_binned_46), kernelIndex(.classified_binned_49));
    try std.testing.expect(Kernel(kernelIndex(.classified_binned_49)) == Kernel(kernelIndex(.classified_binned_46)));
    try std.testing.expectEqual(speckleconfig.Config.classified_binned_46, speckleconfig.canonicalizeSampleConfig(.classified_binned_49));
    for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 0.7, 1 }) |occupancy| {
        const p: Speckle2DParams = .{ .evaluator = .classified_binned_49, .neighbor_count = .nine, .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy, .foreground = 0.91, .background = -0.0 };
        var bp = p;
        bp.evaluator = .classified_binned_46;
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        try std.testing.expectEqual(kernelIndex(.classified_binned_46), resources.kernel_index.?);
        try std.testing.expectEqual(.classified_binned_49, resources.data.rect_bin_classified.payload.params.evaluator.?);
        const empty: Resources = .{};
        for (0..48) |batch| {
            var us: [S]F = undefined;
            var vs: [S]F = undefined;
            var active: [S]bool = undefined;
            for (0..S) |lane| {
                us[lane] = if (batch == 0) std.math.nan(F) else if (batch == 1) std.math.inf(F) else @as(F, @floatFromInt((batch * 73 + lane * 37) % 257)) / 256;
                vs[lane] = if (batch == 2) -std.math.inf(F) else @as(F, @floatFromInt((batch * 17 + lane * 53) % 259)) / 256;
                active[lane] = (batch + lane) % 3 != 0;
                if (std.math.isFinite(us[lane]) and std.math.isFinite(vs[lane])) {
                    try std.testing.expectEqual(@as(Bits, @bitCast(sampleScal(us[lane], vs[lane], bp, &empty))), @as(Bits, @bitCast(sampleScal(us[lane], vs[lane], p, &empty))));
                }
            }
            const raw: [S]F = sampleSIMD(us, vs, active, p, &empty);
            const reference: [S]F = sampleSIMD(us, vs, active, bp, &empty);
            try expectBitwiseSlice(F, &reference, &raw);
            for (0..S) |lane| {
                // The raw adapter samples finite inactive lanes; prepared Kernel46 backgrounds them.
                const expected = if (std.math.isFinite(us[lane]) and std.math.isFinite(vs[lane])) sampleScal(us[lane], vs[lane], p, &empty) else p.background;
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(raw[lane])));
            }
            const prepared: [S]F = sampleSIMD(us, vs, active, p, &resources);
            const selected: [S]F = Kernel(kernelIndex(.classified_binned_46)).sampleSIMD(us, vs, active, p, &resources);
            try expectBitwiseSlice(F, &selected, &prepared);
        }
    };
}

test "bins-first classified49 representative normal resource census exhaustive clipped owner reference all logical cells" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Case = struct { cells: [2]F, radius: F, jitter: F, occupancy: F };
    const cases = [_]Case{
        .{ .cells = .{ 320, 192 }, .radius = 0.4, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 320, 192 }, .radius = 0.4, .jitter = 0.08, .occupancy = 1 },
        .{ .cells = .{ 320, 192 }, .radius = 0.6, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 320, 192 }, .radius = 0.6, .jitter = 0.08, .occupancy = 1 },
        .{ .cells = .{ 320, 192 }, .radius = 0.6, .jitter = 0, .occupancy = 0.7 },
        .{ .cells = .{ 320, 192 }, .radius = 0.6, .jitter = 0.08, .occupancy = 0.7 },
        .{ .cells = .{ 256, 160 }, .radius = 0.4, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 256, 160 }, .radius = 0.6, .jitter = 0, .occupancy = 1 },
    };
    for (cases, 0..) |c, case_id| {
        const p: Speckle2DParams = .{ .evaluator = .classified_binned_49, .neighbor_count = .nine, .cells_per_uv = c.cells, .radius_mean = c.radius, .radius_jitter = c.jitter, .occupancy = c.occupancy, .seed = 0xa511e9b3 };
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        var bp = p;
        bp.evaluator = .classified_binned_46;
        var baseline = try Resources.init(std.testing.allocator, bp);
        defer baseline.deinit(std.testing.allocator);
        const data = resources.data.rect_bin_classified;
        const before = baseline.data.rect_bin_classified;
        try expectBitwiseSlice(F, before.payload.coordinates, data.payload.coordinates);
        try expectBitwiseSlice(u8, before.counts, data.counts);
        try expectBitwiseSlice(u32, before.offsets, data.offsets);
        var histogram: [10]usize = @splat(0);
        var classes: [3]usize = @splat(0);
        var live: usize = 0;
        var terminal_differences: usize = 0;
        var singleton_logical: usize = 0;
        for (data.counts, data.headers, 0..) |count, word, cell| {
            try std.testing.expect(count <= 9);
            histogram[count] += 1;
            live += count;
            try std.testing.expectEqual(@as(u32, 0), @as(u32, @truncate(word)) & @as(u32, @truncate(word >> 32)));
            if (count == 0) try std.testing.expectEqual(@as(u64, 0), word);
            for (0..32) |bit| {
                const x = (cell % data.payload.cell_dims[0]) * 8 + bit % 8;
                const y = (cell / data.payload.cell_dims[0]) * 4 + bit / 8;
                const state = rectangularHeaderClass(word, @intCast(bit));
                if (x >= data.payload.dims[0] or y >= data.payload.dims[1]) {
                    try std.testing.expectEqual(@as(u2, 0), state);
                    continue;
                }
                try std.testing.expectEqual(independentClippedOwnerClass(p, x, y), state);
                classes[state] += 1;
                if (count == 1) singleton_logical += 1;
                if (rectangularHeaderClass(before.headers[cell], @intCast(bit)) != state) {
                    const terminal = std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / 8, -std.math.inf(F)) > p.cells_per_uv[0] or std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / 4, -std.math.inf(F)) > p.cells_per_uv[1];
                    try std.testing.expect(terminal);
                    terminal_differences += 1;
                }
            }
        }
        const logical = data.payload.dims[0] * data.payload.dims[1];
        try std.testing.expectEqual(logical, classes[0] + classes[1] + classes[2]);
        try std.testing.expectEqual(before.byteSize(), data.byteSize());
        try std.testing.expectEqual(before.payload.peak_bytes + 960, data.payload.peak_bytes);
        const json = try std.json.Stringify.valueAlloc(std.testing.allocator, .{ .case_id = case_id, .bin_weighted_not_sample_weighted = true, .bins_by_count = histogram, .logical_classes_bg_amb_fg = classes, .logical_cells = logical, .physical_class_capacity = data.headers.len * 32, .header_words = data.headers.len, .live_records = live, .allocated_slots = data.payload.record_count, .coordinate_bytes = data.payload.coordinates.len * @sizeOf(F), .offset_entries = data.offsets.len, .count_entries = data.counts.len, .retained_bytes = data.byteSize(), .accounted_peak_bytes = data.payload.peak_bytes, .scratch_bytes = Classified49.scratch_bytes, .terminal_differences = terminal_differences, .singleton_logical_cells = singleton_logical, .generation = speckleconfig.evaluatorName(data.payload.params.evaluator.?), .sampling = speckleconfig.evaluatorName(std.meta.activeTag(kernel_configs[resources.kernel_index.?])), .sampling_index = resources.kernel_index.? }, .{});
        defer std.testing.allocator.free(json);
        std.debug.print("RESOURCE49 {s}\n", .{json});
        try expectIndependentClassifiedField(&resources, p, data.payload.empty);
    }
}

test "bins-first classified49 active owners with no bin records preserve arithmetic versus raw signed zero backgrounds" {
    if (comptime !buildconfig.enable_all_evaluators) return;
    const Bits = std.meta.Int(.unsigned, @bitSizeOf(F));
    for ([_]F{ std.math.nextAfter(F, 0, 1), std.math.floatMin(F) }) |radius| {
        for ([_]bool{ false, true }) |variable| {
            const p: Speckle2DParams = .{ .evaluator = .classified_binned_49, .neighbor_count = .nine, .cells_per_uv = .{ 0.01, 0.01 }, .radius_mean = radius, .radius_jitter = if (variable) radius else 0, .occupancy = 1, .foreground = 0.91, .background = -0.0, .seed = 43498 };
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            const data = resources.data.rect_bin_classified;
            try std.testing.expect(data.payload.active_owners != 0);
            try std.testing.expect(!data.payload.empty);
            for (data.counts) |count| try std.testing.expectEqual(@as(u8, 0), count);
            for (data.headers) |word| try std.testing.expectEqual(@as(u64, 0), word);
            const arithmetic = p.background + @as(F, 0) * (p.foreground - p.background);
            try std.testing.expectEqual(@as(Bits, @bitCast(arithmetic)), @as(Bits, @bitCast(sampleScal(0.5, 0.5, p, &resources))));
            var us: [S]F = undefined;
            const vs: [S]F = @splat(0.5);
            var active: [S]bool = undefined;
            for (0..S) |lane| {
                us[lane] = switch (lane % 5) {
                    0 => std.math.nan(F),
                    1 => std.math.inf(F),
                    2 => -std.math.inf(F),
                    3 => -1,
                    else => 2,
                };
                active[lane] = lane % 3 != 0;
                const expected = if (std.math.isFinite(us[lane])) arithmetic else p.background;
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(sampleScal(us[lane], vs[lane], p, &resources))));
            }
            const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
            for (actual, 0..) |value, lane| {
                const expected = if (active[lane] and std.math.isFinite(us[lane])) arithmetic else p.background;
                try std.testing.expectEqual(@as(Bits, @bitCast(expected)), @as(Bits, @bitCast(value)));
            }
        }
    }
}
