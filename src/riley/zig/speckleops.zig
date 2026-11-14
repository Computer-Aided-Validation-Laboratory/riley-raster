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
const matslice = @import("matslice.zig");
const speckleconfig = @import("speckleconfig.zig");

const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSI = buildconfig.VecSI;
const VecSF = buildconfig.VecSF;
const speckle_mask_samples_per_cell: F =
    @floatFromInt(buildconfig.speckle_mask_samples_per_cell);

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

/// Per-mesh runtime settings, immutable for the lifetime of prepared resources.
/// Except for mock, UVs are clamped to [0, 1], then mapped to cells as uv * cells_per_uv.
/// UVs must be finite (full input validation scans them); the clamp still keeps nonfinite
/// UVs in bounds (NaN clamps to 1), so samplers never recheck finiteness.
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
    /// Active-cell probability in [0, 1], not image coverage; ignored by Perlin/mock.
    /// User-facing disk/Gaussian requests require a strictly positive value.
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
    /// User-facing requests must use a value different from background.
    foreground: F = 0.0,
    /// Background intensity in [0, 1], before renderer output scaling.
    background: F = 1.0,

    /// Resolve a generation configuration and validate numerical constraints before allocating.
    /// Equal colors and zero occupancy are supported here; validate() adds user-facing policy.
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

    /// Validate user input, including nonzero contrast and positive disk/Gaussian occupancy.
    /// Low-level preparation uses resolve() and allows constant/empty reference patterns.
    pub fn validate(self: Speckle2DParams) !void {
        const config = try self.resolve();
        if (self.foreground == self.background) return error.SpeckleColorsMustDiffer;
        if (config.pattern()) |pattern| {
            if (pattern != .perlin and self.occupancy == 0.0) return error.InvalidSpeckleOccupancy;
        }
    }

    // Per-configuration numeric checks, run by resolve() after its softness check.
    // Prepared generators rely on this single validation and never repeat it.
    fn validateResolved(self: Speckle2DParams, config: speckleconfig.Config) !void {
        const evaluator = std.meta.activeTag(config);
        for (self.cells_per_uv) |cell_count| {
            if (!std.math.isFinite(cell_count) or cell_count <= 0.0) {
                return error.InvalidSpeckleCellsPerUV;
            }
        }
        if (config.pattern() == .perlin) {
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

pub const DirectFixedSpeckle2D = struct {
    params: Speckle2DParams,
    /// Packed descriptors in zero-origin row-major cells; zero denotes an inactive cell.
    cells: []const u64,
    cell_dims: [2]usize,
    radius2: F,
};

/// Exact gradient IDs, shared by adjacent cells; preparation requires a representable cache.
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
    // Only counts[cell] entries in each nine-slot cell are initialized.
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

/// R8 x R4 certificates, FG32 / AMB32, with ordinary full-bin record indexing.
/// Fixed radii use nine-slot X/Y planes; only counts[cell] slots are initialized.
/// Variable radii use CSR X/Y/radius² planes with u32 offsets.
pub const ClassifiedBinnedSpeckle2D = struct {
    params: Speckle2DParams,
    dims: [2]usize,
    cell_dims: [2]usize,
    coordinates: []const F = &.{},
    /// Capacity of each coordinate plane, including unused fixed-layout slots.
    slots: usize = 0,

    headers: []const u64,
    counts: []const u8,
    offsets: []const u32,

    pub fn byteSize(self: @This()) usize {
        return self.headers.len * @sizeOf(u64) + self.coordinates.len * @sizeOf(F) + self.counts.len + self.offsets.len * @sizeOf(u32);
    }

    fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.headers);
        allocator.free(self.coordinates);
        allocator.free(self.counts);
        allocator.free(self.offsets);
    }
};

pub const Backing = union(enum) {
    none,
    list: SpeckleList2D,
    strip_list: StripSpeckleList2D,
    cell_binned: CellBinnedSpeckle2D,
    classified: ClassifiedIndexedSpeckle2D,
    classified_binned: ClassifiedBinnedSpeckle2D,
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
            .classified_binned => |binned| binned.deinit(allocator),
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
            return Impl.samplePreparedScal(u, v, params, resources);
        }

        pub inline fn sampleSIMD(
            u: VecSF,
            v: VecSF,
            active: VecSB,
            params: Speckle2DParams,
            resources: *const Resources,
        ) VecSF {
            std.debug.assert(resources.kernel_index == @as(?u8, index_tag));
            return Impl.samplePreparedSIMD(u, v, active, params, resources);
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
            return Implementation(config).evalSpeckle2DImpl(u, v, params);
        }
    }
    unreachable;
}

/// Prepared Perlin (gradient-lattice or cell-hash) and classified/direct/mask kernels
/// background inactive lanes. Other prepared kernels and all unprepared calls evaluate
/// every lane. Callers discard inactive lanes either way.
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
            if (comptime std.meta.activeTag(config) == .mock) return Impl.samplePreparedSIMD(u, v, active, params, resources);
            return Impl.evalSpeckleSIMDImpl(Impl.evalSpeckle2DImpl, u, v, params);
        }
    }
    unreachable;
}

/// Fill a borrowed row-major image with final speckle intensities at pixel centers.
/// Row zero is the top row; u increases rightward and v downward over [0, 1]².
/// Cell counts control aspect independently of image dimensions: equal counts on a
/// square image preserve round disks; rectangular images need proportional counts.
/// Resources must be prepared from exactly params and remain immutable while borrowed.
/// SIMD builds use numerically identical prepared kernels; zero signs may differ.
/// Performs no allocation, I/O, supersampling, or additional intensity mapping.
pub fn fillImage(image: matslice.MatSlice(F), params: Speckle2DParams, resources: *const Resources) void {
    std.debug.assert(image.slice.len == image.rows_num * image.cols_num);
    const index = resources.kernel_index.?;
    const rows: F = @floatFromInt(image.rows_num);
    const cols: F = @floatFromInt(image.cols_num);
    inline for (kernel_configs, 0..) |_, ii| {
        if (index == ii) {
            const K = Kernel(ii);
            for (0..image.rows_num) |rr| {
                const v = (@as(F, @floatFromInt(rr)) + 0.5) / rows;
                const row = image.slice[rr * image.cols_num ..][0..image.cols_num];
                var cc: usize = 0;
                if (comptime buildconfig.config.simd == .on) {
                    // Convert integer columns exactly as the scalar tail does.
                    const lane_cols = std.simd.iota(usize, S);
                    while (cc + S <= row.len) : (cc += S) {
                        const col: VecSF = @floatFromInt(@as(@Vector(S, usize), @splat(cc)) + lane_cols);
                        const u = (col + @as(VecSF, @splat(0.5))) / @as(VecSF, @splat(cols));
                        row[cc..][0..S].* = K.sampleSIMD(u, @splat(v), @splat(true), params, resources);
                    }
                }
                for (row[cc..], cc..) |*value, col| {
                    const u = (@as(F, @floatFromInt(col)) + 0.5) / cols;
                    value.* = K.sampleScal(u, v, params, resources);
                }
            }
            return;
        }
    }
    unreachable;
}

// These helpers do not depend on a generation or sampling configuration.

/// Element count if both axes, their product, and the allocation's byte size fit usize.
/// Coordinate validation makes each axis representable in u64, but not their product.
fn gridCount(comptime T: type, dims: [2]u64) ?usize {
    const width = std.math.cast(usize, dims[0]) orelse return null;
    const height = std.math.cast(usize, dims[1]) orelse return null;
    const count = std.math.mul(usize, width, height) catch return null;
    _ = std.math.mul(usize, count, @sizeOf(T)) catch return null;
    return count;
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

// First representable p with RN(p*R) >= index; integer indices are exact under
// the validated coordinate ceilings. Rounded multiplication is monotone, so
// adjusting the quotient until its predecessor maps below index locates the
// inverse boundary without assuming division and multiplication round symmetrically.
fn directMicrocellBoundary(comptime T: type, comptime r: u8, index: u64) T {
    if (index == 0) return 0;
    const target: T = @floatFromInt(index);
    var p = target / @as(T, r);
    if (comptime std.math.isPowerOfTwo(r)) return p;
    while (p * @as(T, r) < target) p = std.math.nextAfter(T, p, std.math.inf(T));
    while (true) {
        const previous = std.math.nextAfter(T, p, 0);
        if (previous * @as(T, r) < target) return p;
        p = previous;
    }
}

fn generatePerlinLattice(allocator: std.mem.Allocator, params: Speckle2DParams) !PerlinLattice2D {
    // Owners 0..floor(C) plus their shared upper corners.
    const corners = [2]u64{
        @as(u64, @intFromFloat(@floor(params.cells_per_uv[0]))) + 2,
        @as(u64, @intFromFloat(@floor(params.cells_per_uv[1]))) + 2,
    };
    const count = gridCount(u8, corners) orelse return error.SpecklePerlinLatticeTooLarge;
    const dims = [2]usize{ @intCast(corners[0]), @intCast(corners[1]) };
    const gradients = try allocator.alloc(u8, count);
    for (0..dims[1]) |y| {
        for (0..dims[0]) |x| {
            gradients[y * dims[0] + x] = @as(u8, @truncate(hashSpeckleCell(@intCast(x), @intCast(y), params.seed))) & 7;
        }
    }
    return .{ .params = params, .gradients = gradients, .dims = dims };
}

fn perlinCornerIDs(lattice: PerlinLattice2D, x: i64, y: i64) [4]u8 {
    const xx: usize = @intCast(x);
    const yy: usize = @intCast(y);
    std.debug.assert(xx + 1 < lattice.dims[0]);
    std.debug.assert(yy + 1 < lattice.dims[1]);
    const i = yy * lattice.dims[0] + xx;
    return .{ lattice.gradients[i], lattice.gradients[i + 1], lattice.gradients[i + lattice.dims[0]], lattice.gradients[i + lattice.dims[0] + 1] };
}

fn perlinSplat(comptime T: type, value: F) T {
    return if (T == F) value else @splat(value);
}

fn perlinSelect(comptime T: type, condition: anytype, yes: T, no: T) T {
    return if (T == F) (if (condition) yes else no) else @select(F, condition, yes, no);
}

// Select complete expressions, not gradient coefficients: rearranging diagonal
// products changes rounding and cancellation relative to the oracle.
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
    const x = @max(0.0, @min(1.0, u)) * lattice.params.cells_per_uv[0];
    const y = @max(0.0, @min(1.0, v)) * lattice.params.cells_per_uv[1];
    return perlinAnalytic(F, x - @floor(x), y - @floor(y), perlinCornerIDs(lattice, @intFromFloat(@floor(x)), @intFromFloat(@floor(y))), lattice.params);
}

fn samplePerlinSIMD(u: VecSF, v: VecSF, active: VecSB, lattice: PerlinLattice2D) VecSF {
    const zero: VecSF = @splat(0);
    const one: VecSF = @splat(1);
    const x = @max(zero, @min(one, u)) * @as(VecSF, @splat(lattice.params.cells_per_uv[0]));
    const y = @max(zero, @min(one, v)) * @as(VecSF, @splat(lattice.params.cells_per_uv[1]));
    const cx = @floor(x);
    const cy = @floor(y);
    var ids: [4]@Vector(S, u8) = .{ @splat(0), @splat(0), @splat(0), @splat(0) };
    inline for (0..S) |lane| {
        if (active[lane]) {
            const corners = perlinCornerIDs(lattice, @intFromFloat(cx[lane]), @intFromFloat(cy[lane]));
            inline for (0..4) |i| ids[i][lane] = corners[i];
        }
    }
    const value = perlinAnalytic(VecSF, x - cx, y - cy, ids, lattice.params);
    return @select(F, active, value, @as(VecSF, @splat(lattice.params.background)));
}

const speckle_classification_boundary_cache_capacity = 8192;

fn ClassificationAxis(comptime r: u8) type {
    return struct {
        dim: usize,
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

/// Microcells 0..floor(C * r), exact in u64 for validated cell counts. Include the
/// actual upper endpoint, including its own cell at integral C.
fn classifiedAxisCount(comptime r: u8, cells_per_uv: F) u64 {
    return @as(u64, @intFromFloat(@floor(cells_per_uv * @as(F, r)))) + 1;
}

fn classifiedAxisDim(comptime r: u8, cells_per_uv: F) ?usize {
    // SIMD axis indices must also fit VecSI.
    const count = classifiedAxisCount(r, cells_per_uv);
    if (count > std.math.maxInt(isize)) return null;
    return @intCast(count);
}

// Bin certificates clip the terminal inverse subcells to the reachable UV domain.
// Classification is local R8 x R4, independent of the build-wide mask resolution.
const ClassifiedBinned = struct {
    const Rx: u8 = 8;
    const Ry: u8 = 4;
    const Data = ClassifiedBinnedSpeckle2D;
    const Ops = Implementation(.classified_binned);

    fn generate(allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        return if (params.radius_jitter == 0) generateImpl(true, allocator, params) else generateImpl(false, allocator, params);
    }

    fn generateImpl(comptime fixed: bool, allocator: std.mem.Allocator, params: Speckle2DParams) !Data {
        const dims: [2]usize = .{
            classifiedAxisDim(Rx, params.cells_per_uv[0]) orelse return error.SpeckleClassificationTooLarge,
            classifiedAxisDim(Ry, params.cells_per_uv[1]) orelse return error.SpeckleClassificationTooLarge,
        };
        const bounds = Ops.speckleProceduralCellBounds(params, 0) orelse return error.SpeckleClassificationTooLarge;
        const owners = Ops.speckleProceduralCellBounds(params, 1) orelse return error.SpeckleClassificationTooLarge;
        const planes: usize = if (fixed) 2 else 3;
        const fixed_slots: usize = if (fixed) std.math.mul(usize, bounds.count, 9) catch return error.SpeckleClassificationTooLarge else 0;
        // Check all known allocation sizes before asking the allocator for storage.
        _ = gridCount(u64, .{ bounds.count, 1 }) orelse return error.SpeckleClassificationTooLarge;
        const fixed_coordinate_count = if (fixed) gridCount(F, .{ fixed_slots, planes }) orelse return error.SpeckleClassificationTooLarge else 0;
        const offsets_len: usize = if (fixed) 0 else std.math.add(usize, bounds.count, 1) catch return error.SpeckleClassificationTooLarge;
        _ = gridCount(u32, .{ offsets_len, 1 }) orelse return error.SpeckleClassificationTooLarge;
        const headers = try allocator.alloc(u64, bounds.count);
        errdefer allocator.free(headers);
        @memset(headers, 0);
        const counts = try allocator.alloc(u8, bounds.count);
        errdefer allocator.free(counts);
        @memset(counts, 0);
        const offsets: []u32 = if (fixed) &.{} else try allocator.alloc(u32, offsets_len);
        errdefer allocator.free(offsets);
        const layout: Ops.CellBinnedAssignment = if (fixed) .classified_fixed else .classified_csr;
        var slots: usize = fixed_slots;
        if (!fixed) {
            Ops.assignCellBinnedDisks(false, layout, params, owners, bounds, counts, offsets, .{ .coordinates = &.{}, .slots = 0 });
            offsets[0] = 0;
            for (counts, 0..) |amount, cell| offsets[cell + 1] = std.math.add(u32, offsets[cell], amount) catch return error.SpeckleClassificationTooLarge;
            slots = offsets[bounds.count];
            @memset(counts, 0);
        }
        const coordinate_count = if (fixed) fixed_coordinate_count else gridCount(F, .{ slots, planes }) orelse return error.SpeckleClassificationTooLarge;
        const coordinates = try allocator.alloc(F, coordinate_count);
        errdefer allocator.free(coordinates);
        Ops.assignCellBinnedDisks(true, layout, params, owners, bounds, counts, offsets, .{ .coordinates = coordinates, .slots = slots });
        const result: Data = .{ .params = params, .dims = dims, .cell_dims = bounds.dims, .coordinates = coordinates, .slots = slots, .headers = headers, .counts = counts, .offsets = offsets };
        classifyBins(fixed, &result, headers);
        return result;
    }

    fn classifyBins(comptime fixed: bool, data: *const Data, headers: []u64) void {
        const V = @Vector(8, F);
        const B = @Vector(8, bool);
        const p = data.params;
        // Rx/Ry are powers of two, so x/R is the exact inverse boundary.
        comptime std.debug.assert(std.math.isPowerOfTwo(Rx) and std.math.isPowerOfTwo(Ry));
        for (data.counts, 0..) |amount, cell| {
            if (amount == 0) continue;
            const base_x = (cell % data.cell_dims[0]) * Rx;
            const base_y = (cell / data.cell_dims[0]) * Ry;
            var lower_x: [8]F = @splat(0);
            var upper_x: [8]F = @splat(0);
            var valid_x: [8]bool = @splat(false);
            var lower_y: [4]F = @splat(0);
            var upper_y: [4]F = @splat(0);
            var valid_y: [4]bool = @splat(false);
            for (0..8) |lane| {
                const x = base_x + lane;
                if (x < data.dims[0]) {
                    lower_x[lane] = @as(F, @floatFromInt(x)) / Rx;
                    upper_x[lane] = @min(std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / Rx, -std.math.inf(F)), p.cells_per_uv[0]);
                    valid_x[lane] = true;
                    std.debug.assert(lower_x[lane] <= upper_x[lane]);
                }
            }
            for (0..4) |row| {
                const y = base_y + row;
                if (y < data.dims[1]) {
                    lower_y[row] = @as(F, @floatFromInt(y)) / Ry;
                    upper_y[row] = @min(std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / Ry, -std.math.inf(F)), p.cells_per_uv[1]);
                    valid_y[row] = true;
                    std.debug.assert(lower_y[row] <= upper_y[row]);
                }
            }
            const start = if (fixed) cell * 9 else data.offsets[cell];
            var fg: u32 = 0;
            var amb: u32 = 0;
            for (0..amount) |j| {
                const r = record(fixed, data, start + j);
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
    inline fn record(comptime fixed: bool, data: *const Data, index: usize) [3]F {
        return .{ data.coordinates[index], data.coordinates[data.slots + index], if (fixed) data.params.radius_mean * data.params.radius_mean else data.coordinates[2 * data.slots + index] };
    }

    fn sampleScal(u: F, v: F, data: *const Data) F {
        return if (data.params.radius_jitter == 0) sampleScalarImpl(true, u, v, data) else sampleScalarImpl(false, u, v, data);
    }

    fn sampleScalarImpl(comptime fixed: bool, u: F, v: F, data: *const Data) F {
        const p = data.params;
        const px = @max(0.0, @min(1.0, u)) * p.cells_per_uv[0];
        const py = @max(0.0, @min(1.0, v)) * p.cells_per_uv[1];
        const x: usize = @intFromFloat(px * @as(F, Rx));
        const y: usize = @intFromFloat(py * @as(F, Ry));
        const cell = (y / Ry) * data.cell_dims[0] + x / Rx;
        const word = data.headers[cell];
        const shift: u6 = @intCast((y % Ry) * Rx + x % Rx);
        const flags = word >> shift;
        var covered = flags & 1 != 0;
        if (flags & 0x1_0000_0000 != 0) {
            const start = (if (fixed) cell * 9 else data.offsets[cell]);
            for (0..data.counts[cell]) |j| {
                const r = record(fixed, data, start + j);
                const dx = px - r[0];
                const dy = py - r[1];
                if (dx * dx + dy * dy < r[2]) {
                    covered = true;
                    break;
                }
            }
        }
        return Ops.speckleCoverageEndpointValue(p, if (covered) 1 else 0);
    }

    inline fn sampleSIMD(u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        return if (data.params.radius_jitter == 0) sampleSIMDImpl(true, u, v, active, data) else sampleSIMDImpl(false, u, v, active, data);
    }

    fn sampleSIMDImpl(comptime fixed: bool, u: VecSF, v: VecSF, active: VecSB, data: *const Data) VecSF {
        const p = data.params;
        const bg: VecSF = @splat(p.background);
        const zero: VecSF = @splat(0);
        const one: VecSF = @splat(1);
        const px = @max(zero, @min(one, u)) * @as(VecSF, @splat(p.cells_per_uv[0]));
        const py = @max(zero, @min(one, v)) * @as(VecSF, @splat(p.cells_per_uv[1]));
        const xs: [S]isize = @as(VecSI, @intFromFloat(px * @as(VecSF, @splat(@as(F, Rx)))));
        const ys: [S]isize = @as(VecSI, @intFromFloat(py * @as(VecSF, @splat(@as(F, Ry)))));
        var cells: [S]usize = undefined;
        var flag_values: [S]u64 = undefined;
        inline for (0..S) |lane| {
            const x: usize = @intCast(xs[lane]);
            const y: usize = @intCast(ys[lane]);
            cells[lane] = (y / Ry) * data.cell_dims[0] + x / Rx;
            const shift: u6 = @intCast((y % Ry) * Rx + x % Rx);
            flag_values[lane] = data.headers[cells[lane]] >> shift;
        }
        const Flags = @Vector(S, u64);
        const flags: Flags = flag_values;
        var covered = active & ((flags & @as(Flags, @splat(1))) != @as(Flags, @splat(0)));
        const ambiguous = active & ((flags & @as(Flags, @splat(0x1_0000_0000))) != @as(Flags, @splat(0)));
        if (@reduce(.Or, ambiguous)) {
            const Bits = std.meta.Int(.unsigned, S);
            const first: usize = @ctz(@as(Bits, @bitCast(ambiguous)));
            const cell = cells[first];
            var coherent = true;
            inline for (0..S) |lane| coherent = coherent and (!ambiguous[lane] or cells[lane] == cell);
            if (coherent) {
                const start = if (fixed) cell * 9 else data.offsets[cell];
                for (0..data.counts[cell]) |j| {
                    const r = record(fixed, data, start + j);
                    const dx = px - @as(VecSF, @splat(r[0]));
                    const dy = py - @as(VecSF, @splat(r[1]));
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, @splat(r[2])));
                }
            } else if (fixed) {
                var starts: [S]usize = undefined;
                var counts: [S]u8 = undefined;
                var max_count: u8 = 0;
                inline for (0..S) |lane| {
                    starts[lane] = cells[lane] * 9;
                    counts[lane] = data.counts[cells[lane]];
                    if (ambiguous[lane]) max_count = @max(max_count, counts[lane]);
                }
                for (0..max_count) |j| {
                    var rx: [S]F = @splat(std.math.inf(F));
                    var ry: [S]F = @splat(0);
                    const rr: [S]F = @splat(p.radius_mean * p.radius_mean);
                    inline for (0..S) |lane| {
                        if (ambiguous[lane] and j < counts[lane]) {
                            const r = record(true, data, starts[lane] + j);
                            rx[lane] = r[0];
                            ry[lane] = r[1];
                        }
                    }
                    const dx = px - @as(VecSF, rx);
                    const dy = py - @as(VecSF, ry);
                    covered |= ambiguous & (dx * dx + dy * dy < @as(VecSF, rr));
                }
            } else {
                covered |= groupHits(px, py, cells, ambiguous, data);
            }
        }
        const coverage = @select(F, covered, one, zero);
        return @select(F, active, bg + coverage * @as(VecSF, @splat(p.foreground - p.background)), bg);
    }

    inline fn groupHits(px: VecSF, py: VecSF, cells: [S]usize, ambiguous: VecSB, data: *const Data) VecSB {
        const V = VecSF;
        const Bits = std.meta.Int(.unsigned, S);
        var remaining: Bits = @bitCast(ambiguous);
        var hits: @Vector(S, bool) = @splat(false);
        while (remaining != 0) {
            const first: usize = @ctz(remaining);
            const cell = cells[first];
            const same = @as(@Vector(S, usize), cells) == @as(@Vector(S, usize), @splat(cell));
            const group = remaining & @as(Bits, @bitCast(same));
            const members: @Vector(S, bool) = @bitCast(group);
            const start = data.offsets[cell];
            for (0..data.counts[cell]) |j| {
                const r = record(false, data, start + j);
                const dx = px - @as(V, @splat(r[0]));
                const dy = py - @as(V, @splat(r[1]));
                hits |= members & (dx * dx + dy * dy < @as(V, @splat(r[2])));
            }
            remaining &= ~group;
        }
        return hits;
    }
};

fn Implementation(comptime config: speckleconfig.Config) type {
    return struct {
        const speckle_shape = config.pattern() orelse .disk;
        const speckle_neighbor_count = @intFromEnum(config.neighborhood() orelse speckleconfig.Neighborhood.nine);
        const evaluator = std.meta.activeTag(config);
        const configured_soft_edges = config.edges() == .soft;

        /// Prepare the configured evaluator once for reuse across frames and samples.
        /// Params must already resolve to this config; Resources.init is the only validator.
        /// Returned allocations belong to outer_alloc; release them through Resources.deinit
        /// or their owning static arena. Procedural cell hashing needs no allocation.
        fn generateConfiguredResources(
            outer_alloc: std.mem.Allocator,
            params: Speckle2DParams,
        ) !Resources {
            return .{ .data = switch (comptime evaluator) {
                .cell_hash, .mock => .none,
                .gradient_lattice => .{ .perlin = try generatePerlinLattice(outer_alloc, params) },
                .list_naive => .{ .list = try generateSpeckleList2D(outer_alloc, params) },
                .list_indexed => .{ .strip_list = try generateStripSpeckleList2D(outer_alloc, params) },
                .cell_binned => .{ .cell_binned = try generateCellBinnedSpeckle2D(outer_alloc, params) },
                .classified_indexed => .{
                    .classified = try generateClassifiedSpeckle2D(outer_alloc, params),
                },
                .classified_binned => .{ .classified_binned = try ClassifiedBinned.generate(outer_alloc, params) },
                .direct_fixed => .{
                    .direct_fixed = try generateDirectFixedSpeckle2D(outer_alloc, params),
                },
                .mask_1bit, .mask_u8 => .{
                    .mask = try generateSpeckleMask2D(outer_alloc, params),
                },
            } };
        }

        /// Prepared resources are required and supply their own parameters;
        /// only cell hashing uses params.
        inline fn samplePreparedScal(
            u: F,
            v: F,
            params: Speckle2DParams,
            resources: *const Resources,
        ) F {
            return switch (comptime evaluator) {
                .gradient_lattice => samplePerlinScal(u, v, resources.data.perlin),
                .mock => 0.5 * (u + v),
                .cell_hash => evalSpeckle2DImpl(u, v, params),
                .list_naive => evalSpeckleList2DNaiveImpl(u, v, resources.data.list),
                .list_indexed => evalStripSpeckleList2DImpl(u, v, resources.data.strip_list),
                .cell_binned => evalCellBinnedSpeckle2D(u, v, resources.data.cell_binned),
                .classified_indexed => evalClassifiedIndexedSpeckle2D(.{ u, v }, resources.data.classified),
                .classified_binned => ClassifiedBinned.sampleScal(u, v, &resources.data.classified_binned),
                .direct_fixed => evalDirectFixedSpeckle2D(.{ u, v }, resources.data.direct_fixed),
                .mask_1bit, .mask_u8 => evalSpeckleMask2D(.{ u, v }, resources.data.mask),
            };
        }

        inline fn samplePreparedSIMD(
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
                    const values = evalSpeckleSIMDImpl(evalSpeckle2DImpl, u, v, params);
                    break :blk if (comptime speckle_shape == .perlin)
                        @select(F, active, values, @as(VecSF, @splat(params.background)))
                    else
                        values;
                },
                .list_naive => evalSpeckleListNaiveSIMDImpl(u, v, resources.data.list),
                .list_indexed => blk: {
                    const strip = resources.data.strip_list;
                    if (strip.centers.len != 0) break :blk evalSpeckleSIMDImpl(evalFixedStripSpeckleList2DImpl, u, v, strip);
                    break :blk evalSpeckleSIMDImpl(evalGeneralStripSpeckleList2DImpl, u, v, strip);
                },
                .cell_binned => blk: {
                    const binned = resources.data.cell_binned;
                    break :blk switch (binned.records) {
                        .disks => evalCellBinnedSpeckleSIMDImpl(.disks, u, v, binned),
                        .strided => evalCellBinnedSpeckleSIMDImpl(.strided, u, v, binned),
                        .gaussian => evalCellBinnedSpeckleSIMDImpl(.gaussian, u, v, binned),
                    };
                },
                .classified_indexed => evalClassifiedIndexedSpeckleSIMDImpl(u, v, active, &resources.data.classified),
                .classified_binned => ClassifiedBinned.sampleSIMD(u, v, active, &resources.data.classified_binned),
                .direct_fixed => evalDirectFixedSpeckleSIMDImpl(u, v, active, &resources.data.direct_fixed),
                .mask_1bit, .mask_u8 => evalSpeckleMaskSIMDImpl(u, v, active, &resources.data.mask),
            };
        }

        // --------------------------------------------------------------------------------------
        // Speckle Generation & Scalar Evaluation
        // --------------------------------------------------------------------------------------

        const SpeckleCellBounds = struct {
            min: [2]i64,
            max: [2]i64,
            dims: [2]usize,
            count: usize,
        };

        /// Owner cells 0..floor(C) plus padding, or null if dimensions/count cannot fit usize.
        fn speckleProceduralCellBounds(
            params: Speckle2DParams,
            comptime padding: i64,
        ) ?SpeckleCellBounds {
            const min = [2]i64{ -padding, -padding };
            const max = [2]i64{
                @as(i64, @intFromFloat(@floor(params.cells_per_uv[0]))) + padding,
                @as(i64, @intFromFloat(@floor(params.cells_per_uv[1]))) + padding,
            };
            const dims = [2]u64{ @intCast(max[0] - min[0] + 1), @intCast(max[1] - min[1] + 1) };
            const count = gridCount(u8, dims) orelse return null;
            return .{ .min = min, .max = max, .dims = .{ @intCast(dims[0]), @intCast(dims[1]) }, .count = count };
        }

        fn classifiedDims(params: Speckle2DParams) [2]u64 {
            const r = buildconfig.speckle_mask_samples_per_cell;
            return .{ classifiedAxisCount(r, params.cells_per_uv[0]), classifiedAxisCount(r, params.cells_per_uv[1]) };
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
            cell_x: i64,
            cell_y: i64,
            hash: u64,
            params: Speckle2DParams,
        ) SpeckleDisk2D {
            const radius_variation = 2.0 * randomUnitFromHash(hash, 48) - 1.0;
            const edge_softness = if (configured_soft_edges) params.edge_softness else 0.0;
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
            cell_x: i64,
            cell_y: i64,
            params: Speckle2DParams,
        ) ?SpeckleDisk2D {
            const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
            if (randomUnitFromHash(hash, 0) >= params.occupancy) return null;
            return speckleDiskFromHash(cell_x, cell_y, hash, params);
        }

        fn generateSpeckleList2D(
            allocator: std.mem.Allocator,
            params: Speckle2DParams,
        ) !SpeckleList2D {
            const cell_bounds = speckleProceduralCellBounds(params, 1) orelse
                return error.SpeckleListTooLarge;

            var active_count: usize = 0;
            var cell_y = cell_bounds.min[1];
            while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
                var cell_x = cell_bounds.min[0];
                while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
                    if (speckleDiskForCell(cell_x, cell_y, params) != null) {
                        active_count += 1;
                    }
                }
            }

            _ = std.math.mul(usize, active_count, @sizeOf(SpeckleDisk2D)) catch return error.SpeckleListTooLarge;
            const disks = try allocator.alloc(SpeckleDisk2D, active_count);
            var disk_index: usize = 0;
            cell_y = cell_bounds.min[1];
            while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
                var cell_x = cell_bounds.min[0];
                while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
                    if (speckleDiskForCell(cell_x, cell_y, params)) |disk| {
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
            const Record = CellBinnedRecord(layout);
            const bounds = speckleProceduralCellBounds(params, 0) orelse return error.SpeckleCellBinsTooLarge;
            const owners = speckleProceduralCellBounds(params, 1) orelse return error.SpeckleCellBinsTooLarge;
            if (layout == .strided) {
                const coordinate_count = gridCount(F, .{ bounds.count, 18 }) orelse return error.SpeckleCellBinsTooLarge;
                const slots = coordinate_count / 2;
                const counts = try outer_alloc.alloc(u8, bounds.count);
                errdefer outer_alloc.free(counts);
                const coordinates = try outer_alloc.alloc(F, coordinate_count);
                const xs = coordinates[0..slots];
                const ys = coordinates[slots..];
                @memset(counts, 0);
                assignCellBinnedDisks(true, .strided, params, owners, bounds, counts, &.{}, .{ .xs = xs, .ys = ys });
                return .{ .params = params, .offsets = &.{}, .records = .{ .strided = .{ .coordinates = coordinates, .counts = counts } }, .dims = bounds.dims };
            }
            const offsets_len = std.math.add(usize, bounds.count, 1) catch return error.SpeckleCellBinsTooLarge;
            _ = std.math.mul(usize, offsets_len, @sizeOf(usize)) catch return error.SpeckleCellBinsTooLarge;
            const offsets = try outer_alloc.alloc(usize, offsets_len);
            errdefer outer_alloc.free(offsets);
            const cursors = try outer_alloc.alloc(usize, bounds.count);
            defer outer_alloc.free(cursors);
            @memset(cursors, 0);
            const assignment = @field(CellBinnedAssignment, @tagName(layout));
            assignCellBinnedDisks(false, assignment, params, owners, bounds, cursors, offsets, &.{});
            offsets[0] = 0;
            for (cursors, 0..) |count, ii| {
                offsets[ii + 1] = std.math.add(usize, offsets[ii], count) catch return error.SpeckleCellBinsTooLarge;
            }
            _ = std.math.mul(usize, offsets[bounds.count], @sizeOf(Record)) catch return error.SpeckleCellBinsTooLarge;
            const records = try outer_alloc.alloc(Record, offsets[bounds.count]);
            errdefer outer_alloc.free(records);
            @memset(cursors, 0);
            assignCellBinnedDisks(true, assignment, params, owners, bounds, cursors, offsets, records);
            for (cursors, 0..) |count, cell| std.debug.assert(count == offsets[cell + 1] - offsets[cell]);
            return .{ .params = params, .offsets = offsets, .records = @unionInit(CellBinnedRecords, @tagName(layout), records), .dims = bounds.dims };
        }

        /// Cell-binned record layouts plus the classified-binned fixed and CSR layouts.
        const CellBinnedAssignment = enum { classified_fixed, classified_csr, strided, disks, gaussian };

        // Share generation, stencil eligibility and support/bin intersection across both
        // binned evaluators; only the final record layout differs at compile time.
        fn assignCellBinnedDisks(
            comptime assign: bool,
            comptime layout: CellBinnedAssignment,
            params: Speckle2DParams,
            owners: SpeckleCellBounds,
            bounds: SpeckleCellBounds,
            cursors: switch (layout) {
                .classified_fixed, .classified_csr, .strided => []u8,
                .disks, .gaussian => []usize,
            },
            offsets: if (layout == .classified_fixed or layout == .classified_csr) []const u32 else []const usize,
            records: switch (layout) {
                .classified_fixed, .classified_csr => struct { coordinates: []F, slots: usize },
                .strided => struct { xs: []F, ys: []F },
                .disks, .gaussian => []CellBinnedRecord(@field(CellBinnedLayout, @tagName(layout))),
            },
        ) void {
            const first: i64 = if (speckle_neighbor_count == 1) 0 else -1;
            const last: i64 = if (speckle_neighbor_count == 9) 1 else 0;
            var owner_y = owners.min[1];
            while (owner_y <= owners.max[1]) : (owner_y += 1) {
                var owner_x = owners.min[0];
                while (owner_x <= owners.max[0]) : (owner_x += 1) {
                    const disk = speckleDiskForCell(owner_x, owner_y, params) orelse continue;
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
                            std.debug.assert(cursors[cell] < 9);
                            if (assign) {
                                if (layout == .classified_fixed or layout == .classified_csr) {
                                    const target = (if (layout == .classified_fixed) cell * 9 else offsets[cell]) + cursors[cell];
                                    records.coordinates[target] = disk.center[0];
                                    records.coordinates[records.slots + target] = disk.center[1];
                                    if (layout == .classified_csr) records.coordinates[2 * records.slots + target] = disk.radius * disk.radius;
                                } else if (layout == .strided) {
                                    const target = cell * 9 + cursors[cell];
                                    records.xs[target] = disk.center[0];
                                    records.ys[target] = disk.center[1];
                                } else {
                                    std.debug.assert(cursors[cell] < offsets[cell + 1] - offsets[cell]);
                                    const target = offsets[cell] + cursors[cell];
                                    records[target] = if (layout == .gaussian) blk: {
                                        const sigma = disk.radius / 3.0;
                                        break :blk .{ .center = disk.center, .outer2 = disk.radius * disk.radius, .sigma2 = sigma * sigma };
                                    } else disk;
                                }
                            }
                            cursors[cell] += 1; // At most nine eligible owners per cell.
                        }
                    }
                }
            }
        }

        fn evalCellBinnedSpeckle2D(u: F, v: F, binned: CellBinnedSpeckle2D) F {
            return switch (binned.records) {
                .disks => evalCellBinnedRecords(.disks, u, v, binned),
                .strided => evalCellBinnedRecords(.strided, u, v, binned),
                .gaussian => evalCellBinnedRecords(.gaussian, u, v, binned),
            };
        }

        fn evalCellBinnedRecords(comptime layout: CellBinnedLayout, u: F, v: F, binned: CellBinnedSpeckle2D) F {
            const params = binned.params;
            const proc_x = @max(0.0, @min(1.0, u)) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, v)) * params.cells_per_uv[1];
            const xx: usize = @intFromFloat(@floor(proc_x));
            const yy: usize = @intFromFloat(@floor(proc_y));
            std.debug.assert(xx < binned.dims[0]);
            std.debug.assert(yy < binned.dims[1]);
            const cell = yy * binned.dims[0] + xx;
            const range: [2]usize = if (layout == .strided) .{ cell * 9, cell * 9 + binned.records.strided.counts[cell] } else .{ binned.offsets[cell], binned.offsets[cell + 1] };
            std.debug.assert(range[0] <= range[1] and range[1] - range[0] <= 9);
            const edge = if (configured_soft_edges) params.edge_softness else 0.0;
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
                    } else speckleDiskMask(distance2, disk.radius, edge);
                    coverage = @max(coverage, mask);
                    if (coverage == 1.0) break;
                }
            }
            if (comptime layout == .strided and speckle_shape == .gaussian) {
                // Tiny supported radii can underflow sigma² to zero. Preserve the
                // original max reduction's NaN handling rather than returning that mask.
                coverage = @max(@as(F, 0), speckleDiskMask(nearest2, params.radius_mean, edge));
            }

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
            const bounds = speckleProceduralCellBounds(params, 1) orelse return error.SpeckleListTooLarge;
            const Record = if (fixed_radius) [2]F else SpeckleDisk2D;
            const count = gridCount(Record, .{ bounds.count, strip_length }) orelse return error.SpeckleListTooLarge;
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
                        } else speckleDiskForCell(cell_x, cell_y, params) orelse .{ .center = .{ std.math.inf(F), 0.0 }, .radius = params.radius_mean };
                    }
                }
            }
            const inner = @max(0.0, params.radius_mean - edge);
            const sigma = params.radius_mean / 3.0;
            const max_outer = params.radius_mean + params.radius_jitter + edge;
            return .{
                .params = params,
                .disks = if (fixed_radius) &.{} else records,
                .centers = if (fixed_radius) records else &.{},
                .cell_origin = bounds.min,
                .cell_dims = bounds.dims,
                .outer2 = if (fixed_radius) support2 else 0.0,
                .inner2 = if (fixed_radius) inner * inner else 0.0,
                .sigma2 = if (fixed_radius) sigma * sigma else 0.0,
                .max_outer_radius2 = max_outer * max_outer,
            };
        }

        fn evalStripSpeckleList2DImpl(
            u: F,
            v: F,
            speckles: StripSpeckleList2D,
        ) F {
            if (speckles.centers.len != 0) return evalFixedStripSpeckleList2DImpl(u, v, speckles);
            return evalGeneralStripSpeckleList2DImpl(u, v, speckles);
        }

        fn evalFixedStripSpeckleList2DImpl(u: F, v: F, speckles: StripSpeckleList2D) F {
            // Infinity absence is already rejected by the mask; full and partial fixed storage share this kernel.
            return evalStripSpeckleList2DSpecialized(true, u, v, speckles);
        }

        fn evalGeneralStripSpeckleList2DImpl(u: F, v: F, speckles: StripSpeckleList2D) F {
            return evalStripSpeckleList2DSpecialized(false, u, v, speckles);
        }

        fn evalStripSpeckleList2DSpecialized(comptime fixed_radius: bool, u: F, v: F, speckles: StripSpeckleList2D) F {
            const uv = [2]F{ u, v };
            const params = speckles.params;
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
            const edge_softness = if (configured_soft_edges) params.edge_softness else 0.0;
            const max_outer_radius2 = speckles.max_outer_radius2;

            var coverage: F = 0.0;
            const row: usize = @intCast(cell_y - speckles.cell_origin[1]);
            std.debug.assert(row < speckles.cell_dims[1]);
            neighbor_loop: for (offsets, min_delta_x) |offset_x, min_dx| {
                const column: usize = @intCast(cell_x + offset_x - speckles.cell_origin[0]);
                std.debug.assert(column < speckles.cell_dims[0]);
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
                        if (fixed_radius) fixedStripDiskMask(distance2, speckles) else speckleDiskMask(distance2, disk.radius, edge_softness),
                    );
                    if (coverage == 1.0) break :neighbor_loop;
                }
            }
            return params.background + coverage * (params.foreground - params.background);
        }

        fn fixedStripDiskMask(distance2: F, speckles: StripSpeckleList2D) F {
            if (!(distance2 < speckles.outer2)) return 0.0;
            if (comptime speckle_shape == .gaussian) return @exp(-0.5 * distance2 / speckles.sigma2);
            if (comptime !configured_soft_edges) return 1.0;
            if (distance2 <= speckles.inner2) return 1.0;
            const transition = (distance2 - speckles.inner2) / (speckles.outer2 - speckles.inner2);
            return 1.0 - cubicSmoothStep(transition);
        }

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
            const cell_bounds = speckleProceduralCellBounds(params, 0) orelse return error.DirectFixedSpeckleTooLarge;
            _ = std.math.mul(usize, cell_bounds.count, @sizeOf(u64)) catch
                return error.DirectFixedSpeckleTooLarge;

            const cells = try allocator.alloc(u64, cell_bounds.count);
            errdefer allocator.free(cells);
            @memset(cells, 0);
            if (params.occupancy != 0.0) {
                for (0..cell_bounds.dims[1]) |yy| {
                    const cell_y: i64 = @intCast(yy);
                    for (0..cell_bounds.dims[0]) |xx| {
                        const cell_x: i64 = @intCast(xx);
                        const hash = hashSpeckleCell(cell_x, cell_y, params.seed);
                        if (params.occupancy == 1.0 or
                            randomUnitFromHash(hash, 0) < params.occupancy)
                        {
                            cells[yy * cell_bounds.dims[0] + xx] =
                                directFixedSpeckleDescriptor(cell_x, cell_y, hash, params.radius_mean);
                        }
                    }
                }
            }

            return .{
                .params = params,
                .cells = cells,
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

        const SpeckleClassificationIndexRange = struct {
            min: usize,
            max: usize,
        };

        const SpeckleClassificationAxis = ClassificationAxis(buildconfig.speckle_mask_samples_per_cell);

        fn speckleClassificationAxes(dims: [2]usize) [2]SpeckleClassificationAxis {
            return .{
                .{ .dim = dims[0] },
                .{ .dim = dims[1] },
            };
        }

        fn speckleClassificationAxisRange(
            proc_min: F,
            proc_max: F,
            axis: SpeckleClassificationAxis,
        ) ?SpeckleClassificationIndexRange {
            const dim = axis.dim;
            // Disjoint representable inverse bins: each endpoint selects its own bin.
            if (proc_max < 0.0) return null;
            const first: usize = @intFromFloat(@max(0.0, proc_min) * speckle_mask_samples_per_cell);
            if (first >= dim) return null;
            const last: usize = @intFromFloat(@max(0.0, proc_max) * speckle_mask_samples_per_cell);
            return .{ .min = first, .max = @min(dim - 1, last) };
        }

        fn stampSpeckleDiskClassification(
            states: []u16,
            dims: [2]usize,
            proc_axes: [2]SpeckleClassificationAxis,
            domain_scale: F,
            disk_cell: [2]i64,
            disk: SpeckleDisk2D,
        ) void {
            const center_scale = @max(@abs(disk.center[0]), @abs(disk.center[1]));
            const max_margin = 16.0 * std.math.floatEps(F) * @max(domain_scale, center_scale);
            // Inflate only the candidate scan to cover rounded subtraction and products;
            // the exact endpoint predicate below decides every state transition.
            const stamp_radius = disk.radius + 4.0 * max_margin;
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

            for (y_range.min..y_range.max + 1) |yy| {
                const proc_min_y = proc_axes[1].boundary(yy);
                const proc_max_y = proc_axes[1].upperBound(yy + 1);

                const y_mask = classificationAxisMask(yy, disk_cell[1], 1);
                if (y_mask == 0) continue;
                for (x_range.min..x_range.max + 1) |xx| {
                    const state_index = yy * dims[0] + xx;
                    if (states[state_index] == 512) continue;

                    const proc_min_x = proc_axes[0].boundary(xx);
                    const proc_max_x = proc_axes[0].upperBound(xx + 1);

                    const x_mask = classificationAxisMask(xx, disk_cell[0], 3);
                    if (x_mask == 0) continue;
                    const disk_state = classifySpeckleDiskMicrocell(
                        disk,
                        .{ proc_min_x, proc_min_y },
                        .{ proc_max_x, proc_max_y },
                    );
                    if (disk_state == .foreground) {
                        // A covering disk dominates intersections and clears the mask.
                        states[state_index] = 512;
                    } else if (disk_state == .ambiguous) {
                        states[state_index] |= x_mask * y_mask;
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
            var proc_axes = speckleClassificationAxes(dims);
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
            const microcells = classifiedDims(params);
            const state_count = gridCount(u16, microcells) orelse
                return error.SpeckleClassificationTooLarge;
            const dims = [2]usize{ @intCast(microcells[0]), @intCast(microcells[1]) };
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
            const relative = owner - @as(i64, @intCast(index / buildconfig.speckle_mask_samples_per_cell));
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
            std.debug.assert(column + 2 < speckles.cell_dims[0]);
            std.debug.assert(row < speckles.cell_dims[1]);
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

        fn speckleDiskMask(
            distance2: F,
            radius: F,
            edge_softness: F,
        ) F {
            const outer_radius = if (configured_soft_edges)
                radius + edge_softness
            else
                radius;
            const outer2 = outer_radius * outer_radius;
            if (!(distance2 < outer2)) return 0.0;
            if (comptime speckle_shape == .gaussian) {
                const sigma = radius / 3.0;
                return @exp(-0.5 * distance2 / (sigma * sigma));
            }
            if (comptime !configured_soft_edges) return 1.0;

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

        inline fn rasterizeSpeckleMaskDisk(
            bits: []u8,
            row_stride: usize,
            uv_to_texel: [2]F,
            params: Speckle2DParams,
            disk: SpeckleDisk2D,
        ) void {
            const edge_softness = if (configured_soft_edges) params.edge_softness else 0.0;
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
            const cell_bounds = speckleProceduralCellBounds(params, 1) orelse
                return error.SpeckleMaskTooLarge;

            // Texels 0..intervals sample both UV endpoints.
            const intervals = [2]u64{
                @intFromFloat(@ceil(params.cells_per_uv[0] * speckle_mask_samples_per_cell)),
                @intFromFloat(@ceil(params.cells_per_uv[1] * speckle_mask_samples_per_cell)),
            };
            const stride: u64 = if (comptime evaluator == .mask_u8) intervals[0] + 1 else intervals[0] / 8 + 1;
            // Packed bytes can fit even when the unpacked SIMD texel indices cannot.
            const max_index: u64 = std.math.maxInt(isize);
            if (intervals[0] > max_index or intervals[1] > max_index) return error.SpeckleMaskTooLarge;
            const byte_count = gridCount(u8, .{ stride, intervals[1] + 1 }) orelse
                return error.SpeckleMaskTooLarge;
            const dims = [2]usize{ @intCast(intervals[0] + 1), @intCast(intervals[1] + 1) };
            const row_stride: usize = @intCast(stride);
            const uv_to_texel = [2]F{
                @floatFromInt(intervals[0]),
                @floatFromInt(intervals[1]),
            };

            const empty_pattern = speckle_shape != .perlin and params.occupancy == 0.0;
            if (empty_pattern) {
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
                            bits,
                            row_stride,
                            uv_to_texel,
                            params,
                            speckleDiskFromHash(cell_x, cell_y, hash, params),
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
            // Empty patterns have no payload to index.
            if (mask.bits.len == 0) return params.background;
            const texel_x: usize = @intFromFloat(
                @max(0.0, @min(1.0, uv[0])) * mask.uv_to_texel[0] + 0.5,
            );
            const texel_y: usize = @intFromFloat(
                @max(0.0, @min(1.0, uv[1])) * mask.uv_to_texel[1] + 0.5,
            );
            std.debug.assert(texel_x < mask.dims[0]);
            std.debug.assert(texel_y < mask.dims[1]);
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

        // Clamped UVs give owners 0..floor(C), exactly the generated grid.
        inline fn directFixedSpeckleCellIndex(
            direct: DirectFixedSpeckle2D,
            cell_x: i64,
            cell_y: i64,
        ) usize {
            const column: usize = @intCast(cell_x);
            const row: usize = @intCast(cell_y);
            std.debug.assert(column < direct.cell_dims[0]);
            std.debug.assert(row < direct.cell_dims[1]);
            return row * direct.cell_dims[0] + column;
        }

        inline fn evalDirectFixedSpeckle2D(
            uv: [2]F,
            direct: DirectFixedSpeckle2D,
        ) F {
            const params = direct.params;
            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const cell_x: i64 = @intFromFloat(@floor(proc_x));
            const cell_y: i64 = @intFromFloat(@floor(proc_y));
            const descriptor = direct.cells[directFixedSpeckleCellIndex(direct, cell_x, cell_y)];
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
            u: F,
            v: F,
            speckles: SpeckleList2D,
        ) F {
            const uv = [2]F{ u, v };
            const params = speckles.params;
            const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0];
            const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1];
            const edge_softness = if (configured_soft_edges) params.edge_softness else 0.0;
            var coverage: F = 0.0;
            for (speckles.disks) |disk| {
                const delta_x = proc_x - disk.center[0];
                const delta_y = proc_y - disk.center[1];
                const distance2 = delta_x * delta_x + delta_y * delta_y;
                coverage = @max(
                    coverage,
                    speckleDiskMask(distance2, disk.radius, edge_softness),
                );
                if (coverage == 1.0) break;
            }
            return params.background + coverage * (params.foreground - params.background);
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
            const proc: [2]F = .{
                @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0],
                @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1],
            };
            const x: usize = @intFromFloat(proc[0] * speckle_mask_samples_per_cell);
            const y: usize = @intFromFloat(proc[1] * speckle_mask_samples_per_cell);
            std.debug.assert(x < classified.dims[0]);
            std.debug.assert(y < classified.dims[1]);
            const state = classified.states[y * classified.dims[0] + x];
            if ((state & 511) == 0) return speckleCoverageEndpointValue(params, if (state == 512) 1.0 else 0.0);
            if (classified.speckles.centers.len != 0) return evalMaskedNeighborsAtProc(true, proc, state, classified.speckles);
            return evalMaskedNeighborsAtProc(false, proc, state, classified.speckles);
        }

        fn evalSpeckle2DImpl(
            u: F,
            v: F,
            params: Speckle2DParams,
        ) F {
            if (comptime evaluator == .mock) return 0.5 * (u + v);
            const uv = [2]F{ u, v };
            if (comptime speckle_shape == .perlin) return evalPerlinSpeckle2D(uv, params);

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
            const edge_softness = if (configured_soft_edges) params.edge_softness else 0.0;
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
                        speckleDiskMask(distance2, disk.radius, edge_softness),
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

        fn speckleDiskMaskSIMD(distance2: VecSF, radius: VecSF, edge: F) VecSF {
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const outer = if (speckle_shape == .disk and configured_soft_edges) radius + @as(VecSF, @splat(edge)) else radius;
            const outer2 = outer * outer;
            const mask = if (comptime speckle_shape == .gaussian) blk: {
                if (!@reduce(.Or, distance2 < outer2)) return zero;
                const sigma = radius / @as(VecSF, @splat(3));
                break :blk @exp(@as(VecSF, @splat(-0.5)) * distance2 / (sigma * sigma));
            } else if (comptime !configured_soft_edges) one else blk: {
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
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, u)) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, v)) * @as(VecSF, @splat(p.cells_per_uv[1]));
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
            return background + coverage * @as(VecSF, @splat(p.foreground - p.background));
        }

        fn evalSpeckleListNaiveSIMDImpl(u: VecSF, v: VecSF, speckles: SpeckleList2D) VecSF {
            const p = speckles.params;
            if (comptime speckle_shape == .gaussian) {
                if (p.radius_jitter != 0) return evalSpeckleListNaiveVariableGaussianSIMDImpl(u, v, speckles);
            }
            const background: VecSF = @splat(p.background);
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, u)) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, v)) * @as(VecSF, @splat(p.cells_per_uv[1]));
            var coverage = zero;
            var nearest: VecSF = @splat(std.math.inf(F));
            for (speckles.disks) |disk| {
                const dx = px - @as(VecSF, @splat(disk.center[0]));
                const dy = py - @as(VecSF, @splat(disk.center[1]));
                if (comptime speckle_shape == .gaussian) {
                    nearest = @min(nearest, dx * dx + dy * dy);
                } else {
                    coverage = @max(coverage, speckleDiskMaskSIMD(dx * dx + dy * dy, @splat(disk.radius), if (configured_soft_edges) p.edge_softness else 0));
                    if (@reduce(.And, coverage == one)) break;
                }
            }
            if (comptime speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(nearest, @splat(p.radius_mean), 0));
            return background + coverage * @as(VecSF, @splat(p.foreground - p.background));
        }

        fn evalCellBinnedSpeckleSIMDImpl(comptime layout: CellBinnedLayout, u: VecSF, v: VecSF, binned: CellBinnedSpeckle2D) VecSF {
            const p = binned.params;
            const background: VecSF = @splat(p.background);
            const zero: VecSF = @splat(0);
            const one: VecSF = @splat(1);
            const px = @max(zero, @min(one, u)) * @as(VecSF, @splat(p.cells_per_uv[0]));
            const py = @max(zero, @min(one, v)) * @as(VecSF, @splat(p.cells_per_uv[1]));
            // Clamped procedural coordinates are nonnegative; truncation is floor.
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
                        coverage = @max(coverage, speckleDiskMaskSIMD(dx * dx + dy * dy, @splat(disk.radius), if (configured_soft_edges) p.edge_softness else 0));
                    }
                }
                if (comptime layout == .strided and speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(nearest, @splat(p.radius_mean), 0));
                return background + coverage * @as(VecSF, @splat(p.foreground - p.background));
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
                    // Only live records are initialized, including in fixed-stride cells.
                    if (ii >= counts[lane]) continue;
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
                    } else speckleDiskMaskSIMD(d2, rs, if (configured_soft_edges) p.edge_softness else 0);
                    coverage = @max(coverage, mask);
                }
            }
            if (comptime layout == .strided and speckle_shape == .gaussian) coverage = @max(zero, speckleDiskMaskSIMD(nearest, @splat(p.radius_mean), 0));
            return background + coverage * @as(VecSF, @splat(p.foreground - p.background));
        }

        inline fn evalSpeckleSIMDImpl(
            comptime eval: anytype,
            u: VecSF,
            v: VecSF,
            input: anytype,
        ) VecSF {
            const coord_0: [S]F = u;
            const coord_1: [S]F = v;
            var values: [S]F = undefined;
            for (0..S) |lane| values[lane] = eval(coord_0[lane], coord_1[lane], input);
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

            const v_zero: VecSF = @splat(0.0);
            const v_proc_x = @max(v_zero, @min(@as(VecSF, @splat(1.0)), u)) * @as(VecSF, @splat(params.cells_per_uv[0]));
            const v_proc_y = @max(v_zero, @min(@as(VecSF, @splat(1.0)), v)) * @as(VecSF, @splat(params.cells_per_uv[1]));
            const v_cell_x: VecSI = @intFromFloat(v_proc_x * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
            const v_cell_y: VecSI = @intFromFloat(v_proc_y * @as(VecSF, @splat(speckle_mask_samples_per_cell)));
            const sample: [S]bool = v_mask_active;
            const cell_x: [S]isize = v_cell_x;
            const cell_y: [S]isize = v_cell_y;
            var state_values = [_]u16{0} ** S;
            // Clamping keeps every lane's load in bounds; inactive lanes never evaluate candidates.
            inline for (0..S) |lane| {
                const x: usize = @intCast(cell_x[lane]);
                const y: usize = @intCast(cell_y[lane]);
                std.debug.assert(x < classified.dims[0]);
                std.debug.assert(y < classified.dims[1]);
                state_values[lane] = classified.states[y * classified.dims[0] + x];
            }

            const v_states: @Vector(S, u16) = state_values;
            const v_foreground = v_mask_active & (v_states == @as(
                @Vector(S, u16),
                @splat(foreground),
            ));
            const v_certified_background: VecSF = @splat(
                speckleCoverageEndpointValue(params, 0.0),
            );
            const v_full_coverage: VecSF = @splat(
                speckleCoverageEndpointValue(params, 1.0),
            );
            var v_values = @select(F, v_mask_active, v_certified_background, v_background);
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

            const v_zero: VecSF = @splat(0.0);
            const v_one: VecSF = @splat(1.0);
            const v_proc_x = @max(v_zero, @min(v_one, u)) *
                @as(VecSF, @splat(params.cells_per_uv[0]));
            const v_proc_y = @max(v_zero, @min(v_one, v)) *
                @as(VecSF, @splat(params.cells_per_uv[1]));
            const v_cell_x: VecSI = @intFromFloat(@floor(v_proc_x));
            const v_cell_y: VecSI = @intFromFloat(@floor(v_proc_y));
            const sample: [S]bool = v_mask_active;
            const cell_x: [S]isize = v_cell_x;
            const cell_y: [S]isize = v_cell_y;
            var descriptors = [_]u64{0} ** S;
            inline for (0..S) |lane| {
                if (sample[lane]) {
                    descriptors[lane] = direct.cells[directFixedSpeckleCellIndex(direct.*, cell_x[lane], cell_y[lane])];
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
            const v_inside = v_mask_active &
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
            if (mask.bits.len == 0) return v_background;

            const v_zero: VecSF = @splat(0.0);
            const v_one: VecSF = @splat(1.0);
            const v_half: VecSF = @splat(0.5);
            const v_texel_x: VecSI = @intFromFloat(
                @max(v_zero, @min(v_one, u)) *
                    @as(VecSF, @splat(mask.uv_to_texel[0])) + v_half,
            );
            const v_texel_y: VecSI = @intFromFloat(
                @max(v_zero, @min(v_one, v)) *
                    @as(VecSF, @splat(mask.uv_to_texel[1])) + v_half,
            );
            const sample: [S]bool = v_mask_active;
            const texel_x: [S]isize = v_texel_x;
            const texel_y: [S]isize = v_texel_y;

            const Sample = if (evaluator == .mask_u8) u8 else bool;
            var samples: [S]Sample = @splat(std.mem.zeroes(Sample));
            inline for (0..S) |lane| {
                if (sample[lane]) {
                    const x: usize = @intCast(texel_x[lane]);
                    const y: usize = @intCast(texel_y[lane]);
                    std.debug.assert(x < mask.dims[0]);
                    std.debug.assert(y < mask.dims[1]);
                    if (comptime evaluator == .mask_u8) {
                        samples[lane] = mask.bits[y * mask.row_stride + x];
                    } else {
                        const shift: u3 = @intCast(x & 7);
                        samples[lane] = mask.bits[y * mask.row_stride + x / 8] &
                            (@as(u8, 1) << shift) != 0;
                    }
                }
            }

            if (comptime evaluator == .mask_u8) {
                const v_coverage_u8: @Vector(S, u8) = samples;
                const v_coverage: VecSF = @as(
                    VecSF,
                    @floatFromInt(v_coverage_u8),
                ) / @as(VecSF, @splat(255.0));
                const v_value = v_background + v_coverage *
                    @as(VecSF, @splat(params.foreground - params.background));
                return v_value;
            }

            const v_value = @select(
                F,
                v_mask_active & @as(VecSB, samples),
                @as(VecSF, @splat(params.foreground)),
                v_background,
            );
            return v_value;
        }
    };
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "grid sizing checks axes element counts and byte sizes without a fixed budget" {
    const max = std.math.maxInt(usize);
    try std.testing.expectEqual(@as(?usize, 1 << 29), gridCount(u8, .{ 1 << 20, 1 << 9 }));
    try std.testing.expectEqual(@as(?usize, max), gridCount(u8, .{ max, 1 }));
    try std.testing.expectEqual(@as(?usize, null), gridCount(u8, .{ max, 2 }));
    try std.testing.expectEqual(@as(?usize, max / 8), gridCount(u64, .{ max / 8, 1 }));
    try std.testing.expectEqual(@as(?usize, null), gridCount(u64, .{ max / 8 + 1, 1 }));
    try std.testing.expectEqual(@as(?usize, null), gridCount(u8, .{ 1 << 40, 1 << 40 }));
    if (@bitSizeOf(usize) == 32) {
        try std.testing.expectEqual(@as(?usize, null), gridCount(u8, .{ 1 << 32, 1 }));
        try std.testing.expectEqual(@as(?usize, null), gridCount(u8, .{ 1, 1 << 32 }));
    }
}
fn expectDirectMicrocell(comptime T: type, comptime r: u8, p: T) !void {
    const j: u64 = @intFromFloat(@floor(p * @as(T, r)));
    try std.testing.expectEqual(@as(u64, @intFromFloat(@floor(p))), j / r);
    const lo = directMicrocellBoundary(T, r, j);
    const next = directMicrocellBoundary(T, r, j + 1);
    try std.testing.expect(p >= lo and p < next);
    // Both representable endpoints of an inverse bin belong to procedural owner j/R,
    // so its candidate disks are confined to that owner's stencil.
    try std.testing.expectEqual(j / r, @as(u64, @intFromFloat(@floor(lo))));
    try std.testing.expectEqual(j / r, @as(u64, @intFromFloat(@floor(std.math.nextAfter(T, next, -std.math.inf(T))))));
    try std.testing.expect(lo * @as(T, r) >= @as(T, @floatFromInt(j)));
    if (j != 0) try std.testing.expect(std.math.nextAfter(T, lo, 0) * @as(T, r) < @as(T, @floatFromInt(j)));
    const v: @Vector(S, T) = @floor(@as(@Vector(S, T), @splat(p)) * @as(@Vector(S, T), @splat(r)));
    const vector: [S]T = v;
    for (vector) |value| try std.testing.expectEqual(@as(T, @floatFromInt(j)), value);
}

test "direct procedural microcells exhaust f32 faces and inverse subcells and probe f64 ceilings" {
    // R4/R8 cover the default classified-binned axes; R12/R16 the experimental mask resolutions.
    const resolutions = if (buildconfig.enable_all_evaluators) .{ 4, 8, 12, 16 } else .{ 4, 8 };
    inline for (.{ f32, f64 }) |T| {
        inline for (resolutions) |r| {
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
                    const n: u64 = @as(u64, 1) << @intCast(exponent);
                    for ([_]u64{ n - 1, n, n + 1, n + n / 2 }) |owner| {
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
const PerlinReference = Implementation(.gradient_lattice);

test "exact Perlin gradients preserve all signed expressions scalar and SIMD" {
    const values = [_]F{ 0, -0.0, 0.25, -0.25, 1, -1, std.math.nextAfter(F, 0, 1) };
    for (0..8) |id| {
        for (values) |x| {
            for (values) |y| {
                const expected = PerlinReference.perlinGradientDot(@intCast(id), x, y);
                try std.testing.expectEqual(expected, perlinDot(F, @as(u8, @intCast(id)), x, y));
                const actual: [S]F = perlinDot(VecSF, @as(@Vector(S, u8), @splat(@intCast(id))), @as(VecSF, @splat(x)), @as(VecSF, @splat(y)));
                for (actual) |value| try std.testing.expectEqual(expected, value);
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
                    try std.testing.expectEqual(expected, perlinAnalytic(F, p[0], p[1], ids, params));
                    const vector_ids = [4]@Vector(S, u8){ @splat(ids[0]), @splat(ids[1]), @splat(ids[2]), @splat(ids[3]) };
                    const actual: [S]F = perlinAnalytic(VecSF, @splat(p[0]), @splat(p[1]), vector_ids, params);
                    for (actual) |value| try std.testing.expectEqual(expected, value);
                }
            }
        }
    }
}

test "exact Perlin cache agrees with independent hashes across parameters and mixed lanes" {
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
                    for (0..2) |dy| {
                        for (0..2) |dx| {
                            const expected: u8 = @as(u8, @truncate(hashSpeckleCell(@intCast(x + dx), @intCast(y + dy), seed))) & 7;
                            try std.testing.expectEqual(expected, got[dy * 2 + dx]);
                        }
                    }
                }
            }
            for ([_]F{ 0, tiny, std.math.floatMin(F), 0.12, 2, std.math.floatMax(F) }) |width| {
                for ([_]F{ -std.math.floatMax(F), -0.2, -tiny, 0, tiny, 0.2, std.math.floatMax(F) }) |threshold| {
                    for ([_][2]F{ .{ 1, 0 }, .{ 0, 1 }, .{ 0.23, 0.23 }, .{ 0.0, 0.0 } }) |colours| {
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
                                try std.testing.expectEqual(expected, samplePerlinScal(us[lane], vs[lane], lattice));
                            }
                            const actual: [S]F = samplePerlinSIMD(us, vs, active, lattice);
                            inline for (0..S) |lane| {
                                const expected = if (active[lane]) PerlinReference.evalPerlinSpeckle2D(.{ us[lane], vs[lane] }, lattice.params) else lattice.params.background;
                                try std.testing.expectEqual(expected, actual[lane]);
                            }
                        }
                    }
                }
            }
        }
    }
}

test "exact Perlin cache owns parameters and preserves endpoint samples" {
    for ([_][2]F{ .{ 2.17, 1.31 }, .{ 1, 1 }, .{ 0.03125, 0.0625 } }) |scale| {
        var resources = try Resources.init(std.testing.allocator, .{ .pattern = .perlin, .cells_per_uv = scale });
        defer resources.deinit(std.testing.allocator);
        try std.testing.expect(resources.data.perlin.gradients.len > 0);
        const params = resources.data.perlin.params;
        for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ 1, 0.61 }, .{ 0.37, 1 }, .{ std.math.nextAfter(F, 1, 0), 0.37 }, .{ 0.37, std.math.nextAfter(F, 1, 0) } }) |uv| {
            const expected = PerlinReference.evalPerlinSpeckle2D(uv, params);
            try std.testing.expectEqual(expected, sampleScal(uv[0], uv[1], .{}, &resources));
            const actual: [S]F = sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), .{}, &resources);
            for (actual) |value| try std.testing.expectEqual(expected, value);
        }
    }
}

test "resource backings clean up partial allocations and repeated deinit resets" {
    // Classified and cell-binned layouts have their own instrumented allocation matrices.
    inline for (.{
        @as(speckleconfig.Config, .gradient_lattice),
        @as(speckleconfig.Config, .direct_fixed),
        speckleconfig.Config{ .list_naive = .{ .disk = .{ .neighborhood = .nine, .edges = .hard } } },
        speckleconfig.Config{ .list_indexed = .{ .disk = .{ .neighborhood = .nine, .edges = .hard } } },
        speckleconfig.Config{ .list_indexed = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
        speckleconfig.Config{ .list_indexed = .{ .gaussian = .nine } },
        speckleconfig.Config{ .mask_1bit = .nine },
        speckleconfig.Config{ .mask_u8 = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
        speckleconfig.Config{ .mask_u8 = .{ .gaussian = .nine } },
        speckleconfig.Config{ .mask_u8 = .perlin },
    }) |config| {
        if (comptime !buildconfig.enable_all_evaluators and std.meta.activeTag(config) != .gradient_lattice) continue;
        const Probe = struct {
            fn run(allocator: std.mem.Allocator, jitter: F, occupancy: F) !void {
                const params = Speckle2DParams{
                    .pattern = config.pattern().?,
                    .evaluator = if (buildconfig.enable_all_evaluators) std.meta.activeTag(config) else null,
                    .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
                    .cells_per_uv = .{ 2.17, 1.31 },
                    .radius_mean = 0.35,
                    .radius_jitter = jitter,
                    .occupancy = occupancy,
                    .edge_softness = if (config.edges() == .soft) 0.04 else 0,
                };
                var resources = try Resources.init(allocator, params);
                defer resources.deinit(allocator);
                resources.deinit(allocator);
                try std.testing.expectEqualDeep(Resources{}, resources);
                resources.deinit(allocator);
            }
        };
        // Perlin has no occupancy/radius branches; direct-fixed has no variable-radius path.
        const jitters: []const F = if (config.pattern() == .perlin or std.meta.activeTag(config) == .direct_fixed) &.{0} else &.{ 0, 0.08 };
        const occupancies: []const F = if (config.pattern() == .perlin) &.{1} else &.{ 0, 1 };
        for (jitters) |jitter| {
            for (occupancies) |occupancy| {
                std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{ jitter, occupancy }) catch |err| {
                    std.debug.print("allocation cleanup evaluator={s} pattern={any} edges={any} jitter={d} occupancy={d}\n", .{ @tagName(std.meta.activeTag(config)), config.pattern(), config.edges(), jitter, occupancy });
                    return err;
                };
            }
        }
    }
}

test "procedural speckle hash has stable known vectors" {
    try std.testing.expectEqual(@as(u64, 0x42cc592e95069169), hashSpeckleCell(0, 0, 0));
    try std.testing.expectEqual(@as(u64, 0xe4214bce0919ce5d), hashSpeckleCell(17, 29, 12345));
    try std.testing.expectEqual(
        @as(u64, 0xcbba3e407b1fa232),
        hashSpeckleCell(-7, -11, 0xa511e9b3),
    );
    try std.testing.expectEqual(
        @as(u64, 0x833cd6c57d01169f),
        hashSpeckleCell(-1, 5, std.math.maxInt(u32)),
    );
}

test "speckle coverage quantization clamps and rounds boundaries" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    try std.testing.expectEqual(@as(u8, 0), PerlinReference.quantizeSpeckleCoverage(-1.0));
    try std.testing.expectEqual(@as(u8, 0), PerlinReference.quantizeSpeckleCoverage(0.0));
    try std.testing.expectEqual(@as(u8, 1), PerlinReference.quantizeSpeckleCoverage(1.0 / 255.0));
    try std.testing.expectEqual(@as(u8, 128), PerlinReference.quantizeSpeckleCoverage(0.5));
    try std.testing.expectEqual(@as(u8, 254), PerlinReference.quantizeSpeckleCoverage(254.0 / 255.0));
    try std.testing.expectEqual(@as(u8, 255), PerlinReference.quantizeSpeckleCoverage(1.0));
    try std.testing.expectEqual(@as(u8, 255), PerlinReference.quantizeSpeckleCoverage(2.0));
}

// Default tests cover production configs; experimental tests add all ten analytic fields.
const analytic_test_configs = if (!buildconfig.enable_all_evaluators) generation_configs else blk: {
    var configs: [10]speckleconfig.Config = undefined;
    var count: usize = 0;
    for (std.enums.values(speckleconfig.Neighborhood)) |neighbors| {
        for (std.enums.values(speckleconfig.Edges)) |edges| {
            configs[count] = .{ .cell_hash = .{ .disk = .{ .neighborhood = neighbors, .edges = edges } } };
            count += 1;
        }
        configs[count] = .{ .cell_hash = .{ .gaussian = neighbors } };
        count += 1;
    }
    configs[count] = .{ .cell_hash = .perlin };
    break :blk configs;
};

fn printSpeckleTestConfig(config: speckleconfig.Config) void {
    std.debug.print("speckle config: evaluator={s} pattern={any} neighbors={any} edges={any}\n", .{
        @tagName(std.meta.activeTag(config)), config.pattern(), config.neighborhood(), config.edges(),
    });
}

test "exact rounded extrema certify inverse bins through coordinate ceilings" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const ceiling: u64 = if (F == f32) 65_536 else 35_184_372_088_832;
    const r = buildconfig.speckle_mask_samples_per_cell;
    for ([_]u64{ 0, 1, r - 1, r, 17 * r + 3, (ceiling - 1) * r }) |j| {
        const lo = directMicrocellBoundary(F, r, j);
        const hi = std.math.nextAfter(F, directMicrocellBoundary(F, r, j + 1), -std.math.inf(F));
        const mid = lo + (hi - lo) * 0.5;
        for ([_]F{ lo, mid, hi, std.math.nextAfter(F, lo, -std.math.inf(F)), std.math.nextAfter(F, hi, std.math.inf(F)) }) |center| {
            for ([_]F{ 0.0, std.math.nextAfter(F, 0.0, 1.0), 0.35, 1.0 }) |radius| {
                const disk = SpeckleDisk2D{ .center = .{ center, mid }, .radius = radius };
                const state = Classified.classifySpeckleDiskMicrocell(disk, .{ lo, lo }, .{ hi, hi });
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

test "classified dimensions include default integral and fractional endpoints" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const r = buildconfig.speckle_mask_samples_per_cell;
    try testing.expectEqual([2]u64{ 192 * r + 1, 160 * r + 1 }, Classified.classifiedDims(.{}));
    try testing.expectEqual([2]u64{ 3 * r + 1, 2 * r + 1 }, Classified.classifiedDims(.{
        .cells_per_uv = .{ 3.0 + 0.25 / speckle_mask_samples_per_cell, 2.0 + 0.75 / speckle_mask_samples_per_cell },
    }));
}

test "direct stamp ranges match exhaustive representable bin overlap" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    for ([_]F{ 3.25, 0.03125, std.math.nextAfter(F, 0.0, 1.0) }) |cells| {
        const params = Speckle2DParams{ .cells_per_uv = .{ cells, cells } };
        const dims = testClassifiedDims(params);
        const axis = Classified.speckleClassificationAxes(dims)[0];
        for (0..axis.dim + 2) |boundary_index| {
            const boundary = axis.boundary(boundary_index);
            for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |p| {
                for ([_][2]F{ .{ p, p }, .{ -1.0, p }, .{ p, cells + 2.0 } }) |interval| {
                    var expected: ?Classified.SpeckleClassificationIndexRange = null;
                    for (0..axis.dim) |i| {
                        if (axis.upperBound(i + 1) < interval[0] or axis.boundary(i) > interval[1]) continue;
                        if (expected) |*range| range.max = i else expected = .{ .min = i, .max = i };
                    }
                    try testing.expectEqualDeep(expected, Classified.speckleClassificationAxisRange(interval[0], interval[1], axis));
                }
            }
        }
    }
}

test "neighbor masks preserve exact scalar SIMD boundaries" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    for ([_]F{ 0.0, 0.08, 0.35 }) |jitter| {
        for ([_]F{ 0.0, 0.7, 1.0 }) |occupancy| {
            const params: Speckle2DParams = .{
                .evaluator = .classified_indexed,
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
            const axes = Classified.speckleClassificationAxes(masked.dims);
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
}

test "aligned lookup keeps procedural owners and stamps one bit across faces and corners" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
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
    const dims = testClassifiedDims(params);
    const axes = Classified.speckleClassificationAxes(dims);
    const states = try testing.allocator.alloc(u16, dims[0] * dims[1]);
    defer testing.allocator.free(states);
    for ([_][2]F{ .{ 1, 0.5 }, .{ 0.5, 1 }, .{ 1, 1 } }) |center| {
        @memset(states, 0);
        Classified.stampSpeckleDiskClassification(states, dims, axes, 2, .{ 0, 0 }, .{ .center = center, .radius = 0.02 });
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
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const axes = Classified.speckleClassificationAxes(.{ 1, 1 });
    const covering: SpeckleDisk2D = .{ .center = .{ 0.04, 0.04 }, .radius = 0.2 };
    const intersecting: SpeckleDisk2D = .{ .center = .{ 0.0, 0.04 }, .radius = 0.04 };
    var states = [_]u16{0};
    Classified.stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
    try testing.expectEqual(@as(u16, 16), states[0]);
    Classified.stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, covering);
    try testing.expectEqual(@as(u16, 512), states[0]);
    Classified.stampSpeckleDiskClassification(&states, .{ 1, 1 }, axes, 1.0, .{ 0, 0 }, intersecting);
    try testing.expectEqual(@as(u16, 512), states[0]);
}

test "unconditional classified loads keep inactive lanes backgrounded" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    var resources = try Resources.init(testing.allocator, .{ .evaluator = .classified_indexed, .cells_per_uv = .{ 0.031, 1.17 }, .foreground = -0.0, .background = 0.23 });
    defer resources.deinit(testing.allocator);
    const params = resources.data.classified.speckles.params;
    const probes = [_]F{ -2, -1, -0.0, 0, 0.37, 1, 2, 3 };
    for (0..probes.len) |batch| {
        var us: [S]F = undefined;
        var vs: [S]F = undefined;
        var active: [S]bool = undefined;
        for (0..S) |lane| {
            us[lane] = probes[(batch + lane) % probes.len];
            vs[lane] = probes[(batch * 3 + lane) % probes.len];
            active[lane] = (batch + lane) % 3 == 0;
        }
        const actual: [S]F = Kernel(kernelIndex(.classified_indexed)).sampleSIMD(us, vs, active, params, &resources);
        for (0..S) |lane| {
            const expected = if (active[lane]) evalSpeckle2D(.classified_indexed, .{ us[lane], vs[lane] }, params) else params.background;
            try testing.expectEqual(expected, actual[lane]);
        }
    }
}

test "direct procedural endpoints include fractional tiny and ceiling scales" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const limit: F = if (F == f32) 65_536 else 35_184_372_088_832;
    const accepted_tie: F = limit - 1 + 0x1p-8;
    const rejected = std.math.nextAfter(F, accepted_tie, std.math.inf(F));
    try testing.expectEqual(limit, accepted_tie + 1);
    try testing.expect(rejected + 1 > limit);
    inline for (.{ 8, 12, 16 }) |r| try expectDirectMicrocell(F, r, accepted_tie);
    for (0..2) |axis| {
        var params: Speckle2DParams = .{};
        params.cells_per_uv[axis] = accepted_tie;
        try params.validateResolved(.classified_indexed);
        params.cells_per_uv[axis] = rejected;
        try testing.expectError(error.SpeckleCellCoordinateOutOfRange, params.validateResolved(.classified_indexed));
    }
    for ([_]F{ std.math.nextAfter(F, 0, 1), std.math.floatMin(F), 0.031, 0.5, 1, 1.17, limit - 1, accepted_tie }) |cells| {
        const params: Speckle2DParams = .{ .evaluator = .classified_indexed, .cells_per_uv = .{ cells, cells } };
        try params.validateResolved(.classified_indexed);
        // Ceiling-scale geometry stays in u64; these probes require no allocation.
        const dims = Classified.classifiedDims(params);
        const r = buildconfig.speckle_mask_samples_per_cell;
        for ([_]F{ -1, -0.0, 0, 0.5, std.math.nextAfter(F, 1, 0), 1, 2 }) |uv| {
            const p = @max(0.0, @min(1.0, uv)) * cells;
            const j: u64 = @intFromFloat(classificationCoordinate(uv, cells));
            try testing.expect(j < dims[0]);
            try testing.expect(p >= directMicrocellBoundary(F, r, j) and p < directMicrocellBoundary(F, r, j + 1));
            try testing.expectEqual(@as(u64, @intFromFloat(@floor(p))), j / r);
        }
        try testing.expectEqual(@as(u64, @intFromFloat(cells * speckle_mask_samples_per_cell)) + 1, dims[0]);
        if (cells > 2) continue; // Mathematical ceiling probes need no huge allocation.
        for ([_]F{ 0, 0.08 }) |jitter| {
            var resources = try Resources.init(testing.allocator, .{ .evaluator = .classified_indexed, .cells_per_uv = params.cells_per_uv, .radius_jitter = jitter, .foreground = -0.0, .background = 0.23 });
            defer resources.deinit(testing.allocator);
            try expectNeighborMaskCandidates(resources.data.classified);
            for ([_][2]F{ .{ 0, 0 }, .{ -0.0, 1 }, .{ 1, 1 }, .{ 0.5, 0.5 }, .{ -1, 2 } }) |uv| try expectClassifiedSample(&resources, uv);
        }
    }
}

test "neighbor masks preserve tiny zero radii and endpoint arithmetic" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const tiny = @sqrt(std.math.floatMin(F)) * 0.25;
    for ([_]F{ tiny, 0.35 }) |radius| {
        for ([_][2]F{ .{ 0.23, -0.0 }, .{ 0.0, 0.0 }, .{ 1.0, 0.0 } }) |colours| {
            var resources = try Resources.init(testing.allocator, .{ .evaluator = .classified_indexed, .cells_per_uv = .{ 2.17, 1.31 }, .radius_mean = radius, .radius_jitter = 0, .occupancy = 1, .background = colours[0], .foreground = colours[1] });
            defer resources.deinit(testing.allocator);
            for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 3 }, .{ 0.5, 0.5 } }) |uv| try expectClassifiedSample(&resources, uv);
            const strip = resources.data.classified.speckles;
            for (0..strip.recordCount() / 3) |index| {
                const disk = strip.record(index * 3 + 1);
                if (!std.math.isFinite(disk.center[0])) continue;
                try expectClassifiedSample(&resources, .{ disk.center[0] / strip.params.cells_per_uv[0], disk.center[1] / strip.params.cells_per_uv[1] });
            }
        }
    }
}

test "procedural speckle shape has bounded support" {
    inline for (analytic_test_configs) |config| {
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        if (comptime Impl.speckle_shape == .gaussian) {
            try testing.expectEqual(@as(F, 1.0), Impl.speckleDiskMask(0.0, 0.5, 0.0));
            const transition = Impl.speckleDiskMask(0.0625, 0.5, 0.0);
            try testing.expect(transition > 0.0);
            try testing.expect(transition < 1.0);
            try testing.expectEqual(@as(F, 0.0), Impl.speckleDiskMask(0.25, 0.5, 0.0));
        } else if (comptime Impl.speckle_shape == .disk) {
            const inside = std.math.nextAfter(F, 0.25, 0.0);
            try testing.expectEqual(@as(F, 1.0), Impl.speckleDiskMask(inside, 0.5, 0.0));
            try testing.expectEqual(@as(F, 0.0), Impl.speckleDiskMask(0.25, 0.5, 0.0));
            try testing.expectEqual(@as(F, 0.0), Impl.speckleDiskMask(0.0, 0.0, 0.0));
            try testing.expectEqual(@as(F, 0.0), Impl.speckleDiskMask(0.251, 0.5, 0.0));

            if (comptime Impl.configured_soft_edges) {
                const transition = Impl.speckleDiskMask(0.25, 0.5, 0.1);
                try testing.expect(transition > 0.0 and transition < 1.0);
            }
        } else {
            const params = Speckle2DParams{};
            try testing.expectEqual(@as(F, 0.0), Impl.perlinCoverage(-1.0, params));
            try testing.expectEqual(@as(F, 1.0), Impl.perlinCoverage(1.0, params));
            const transition = Impl.perlinCoverage(params.perlin_coverage_threshold, params);
            try testing.expect(transition > 0.0 and transition < 1.0);
        }
    }
}

test "procedural speckle is bounded seed-sensitive and UV clamped" {
    inline for (analytic_test_configs) |config| {
        errdefer printSpeckleTestConfig(config);
        const params: Speckle2DParams = .{ .cells_per_uv = .{ 12.0, 10.0 }, .edge_softness = if (config.edges() == .soft) 0.035 else 0 };

        try testing.expectEqual(
            evalSpeckle2D(config, .{ 0.0, 1.0 }, params),
            evalSpeckle2D(config, .{ -2.0, 3.0 }, params),
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
                const sample = evalSpeckle2D(config, uv, params);
                try testing.expect(sample >= @min(params.foreground, params.background));
                try testing.expect(sample <= @max(params.foreground, params.background));
                if (sample != evalSpeckle2D(config, uv, seed_changed)) {
                    found_seed_difference = true;
                }
            }
        }
        try testing.expect(found_seed_difference);
    }
}

test "procedural speckle SIMD fallback matches scalar evaluation" {
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) == .mock) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        var speckle_params: Speckle2DParams = .{
            .cells_per_uv = .{ 11.0, 9.0 },
            .seed = 42,
            .edge_softness = if (Impl.configured_soft_edges) 0.035 else 0.0,
            .pattern = Impl.speckle_shape,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            speckle_params.evaluator = Impl.evaluator;
            speckle_params.neighbor_count = if (Impl.speckle_shape == .perlin) null else config.neighborhood();
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
            const expected = evalSpeckle2D(config, .{ coords_0[lane], coords_1[lane] }, speckle_params);
            try testing.expectEqual(expected, values_simd[lane]);
            try testing.expectEqual(expected, inactive[lane]);
        }
    }
}

test "procedural speckle occupancy endpoints behave exactly" {
    inline for (analytic_test_configs) |config| {
        if (comptime config.pattern() == .perlin) continue;
        errdefer printSpeckleTestConfig(config);
        var params: Speckle2DParams = .{ .cells_per_uv = .{ 8.0, 8.0 }, .occupancy = 0.0, .edge_softness = if (config.edges() == .soft) 0.035 else 0 };
        for (0..8) |yy| {
            for (0..8) |xx| {
                const uv = [2]F{
                    @as(F, @floatFromInt(xx)) / 7.0,
                    @as(F, @floatFromInt(yy)) / 7.0,
                };
                try testing.expectEqual(params.background, evalSpeckle2D(config, uv, params));
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
                if (evalSpeckle2D(config, uv, params) < params.background) {
                    found_speckle = true;
                }
            }
        }
        try testing.expect(found_speckle);
    }
}

test "generated speckle list matches hard and soft cell hash evaluation" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (analytic_test_configs) |config| {
        if (comptime config.pattern() == .perlin) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const softnesses: []const F = if (!Impl.configured_soft_edges)
            &.{0.0}
        else if (Impl.speckle_neighbor_count == 4)
            &.{ 0.035, 0.2 }
        else
            &.{0.035};
        for (softnesses) |softness| {
            const params: Speckle2DParams = .{
                .pattern = Impl.speckle_shape,
                .cells_per_uv = .{ 4.25, 3.17 },
                .occupancy = 0.7,
                .radius_mean = if (softness == 0.2) 0.8 else 0.45,
                .edge_softness = softness,
            };
            const speckles = try Impl.generateSpeckleList2D(testing.allocator, params);
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
                    const value = evalSpeckle2D(config, uv, params);
                    try testing.expectEqual(value, Impl.evalSpeckleList2DNaiveImpl(uv[0], uv[1], speckles));
                    found_intermediate = found_intermediate or (value > 0.0 and value < 1.0);
                }
            }
            if (Impl.speckle_shape == .disk) {
                try testing.expectEqual(softness > 0.0, found_intermediate);
            }
        }
    }
}

test "rounded speckle support excludes omitted cells" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (analytic_test_configs) |config| {
        if (comptime config.pattern() != .disk or config.edges() == .soft or config.neighborhood() == .nine) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const support_radius_limit: F = if (Impl.speckle_neighbor_count == 1) 0.5 else 1.0;
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
            const min = if (Impl.speckle_neighbor_count == 1) case.support else 0.0;
            const extent = if (Impl.speckle_neighbor_count == 1) 1.0 - 2.0 * min else 1.0 - case.support;
            const center = Impl.speckleCenter(case.cell, case.unit, min, extent, case.support * case.support);
            const cell: F = @floatFromInt(case.cell);
            const lower_face = cell - @as(F, if (Impl.speckle_neighbor_count == 1) 0.0 else 1.0);
            const lower_gap = center.coordinate - std.math.nextAfter(F, lower_face, -std.math.inf(F));
            const upper_gap = cell + 1.0 - center.coordinate;
            try testing.expect(lower_gap * lower_gap >= case.support * case.support);
            try testing.expect(upper_gap * upper_gap >= case.support * case.support);
            try testing.expect(center.unit <= case.unit);
        }
    }
}

test "direct fixed generation is contained and exact" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    const config: speckleconfig.Config = .direct_fixed;
    const Impl = Implementation(config);
    errdefer printSpeckleTestConfig(config);
    const params: Speckle2DParams = .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 3.25, 1.75 },
        .occupancy = 0.72,
        .radius_mean = 0.38,
        .radius_jitter = 0.0,
        .foreground = 0.15,
        .background = 0.85,
    };
    const first = try Impl.generateDirectFixedSpeckle2D(testing.allocator, params);
    defer deinitTestResources(.{ .data = .{ .direct_fixed = first } });
    var inactive_params = params;
    inactive_params.occupancy = 0.0;
    const inactive = try Impl.generateDirectFixedSpeckle2D(testing.allocator, inactive_params);
    defer deinitTestResources(.{ .data = .{ .direct_fixed = inactive } });
    for (inactive.cells) |descriptor| try testing.expectEqual(@as(u64, 0), descriptor);
    try testing.expect(first.cell_dims[0] != first.cell_dims[1]);
    try testing.expectEqual(params.radius_mean * params.radius_mean, first.radius2);
    for (first.cells, 0..) |descriptor, index| {
        const xx = index % first.cell_dims[0];
        const yy = index / first.cell_dims[0];
        const cell_x: i64 = @intCast(xx);
        const cell_y: i64 = @intCast(yy);
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
            evalSpeckle2D(config, uv, params),
            Impl.evalDirectFixedSpeckle2D(uv, first),
            unit_tol,
        );
    }
    for (0..41) |ii| {
        const uv = [2]F{
            @as(F, @floatFromInt((ii * 17 + 3) % 43)) / 42.0,
            @as(F, @floatFromInt((ii * 29 + 7) % 47)) / 46.0,
        };
        try testing.expectApproxEqAbs(
            evalSpeckle2D(config, uv, params),
            Impl.evalDirectFixedSpeckle2D(uv, first),
            unit_tol,
        );
    }
    try testing.expectEqual(
        Impl.evalDirectFixedSpeckle2D(.{ 0.0, 1.0 }, first),
        Impl.evalDirectFixedSpeckle2D(.{ -2.0, 3.0 }, first),
    );
}

test "classified evaluators preserve independent states and exact samples" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
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
            for ([_][2]F{ .{ 0.0, 0.0 }, .{ 0.91, -0.0 }, .{ 0.23, 0.23 } }) |colors| {
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
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const cases = [_]Speckle2DParams{
        .{ .cells_per_uv = .{ 192.0, 160.0 } },
        .{ .cells_per_uv = .{ 3.25, 2.5 } },
        .{ .cells_per_uv = .{ 0.03125, 0.0625 } },
    };
    for (cases) |params| {
        try params.validateResolved(.classified_indexed);
        const dims = testClassifiedDims(params);
        const axes = Classified.speckleClassificationAxes(dims);
        for (axes, params.cells_per_uv) |axis, cells_per_uv| {
            for (0..axis.dim + 1) |ii| {
                const uv = axis.boundary(ii) / cells_per_uv;
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
                    const cell: usize = @intFromFloat(classificationCoordinate(sample, cells_per_uv));
                    const proc = bounded_uv * cells_per_uv;
                    try testing.expectEqual(@as(usize, @intFromFloat(@floor(proc))), cell / buildconfig.speckle_mask_samples_per_cell);
                    try testing.expect(proc >= axis.boundary(cell));
                    try testing.expect(proc <= axis.upperBound(cell + 1));
                }
            }
        }
    }
}

test "direct 1-bit speckle mask preserves list-derived bytes and lattice values" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_1bit) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const params = speckleMaskTestParams(config);
        const speckles = try Impl.generateSpeckleList2D(testing.allocator, params);
        defer deinitTestResources(.{ .data = .{ .list = speckles } });

        var mask_storage: [1200]u8 = undefined;
        var fixed = std.heap.FixedBufferAllocator.init(&mask_storage);
        const mask = try Impl.generateSpeckleMask2D(fixed.allocator(), params);
        const expected_byte_count = mask.row_stride * mask.dims[1];
        try testing.expectEqual(expected_byte_count, mask.bits.len);
        if (comptime buildconfig.speckle_mask_samples_per_cell == 12) {
            try testing.expectEqual(@as(usize, 155), mask.bits.len);
        }

        const list_bits = try testing.allocator.alloc(u8, mask.bits.len);
        defer testing.allocator.free(list_bits);
        @memset(list_bits, 0);
        for (speckles.disks) |disk| {
            Impl.rasterizeSpeckleMaskDisk(
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
                const value = Impl.evalSpeckleMask2D(uv, mask);
                try testing.expectApproxEqAbs(
                    Impl.evalSpeckleList2DNaiveImpl(uv[0], uv[1], speckles),
                    value,
                    unit_tol,
                );
                found_foreground = found_foreground or value == mask.params.foreground;
                found_background = found_background or value == mask.params.background;
            }
        }
        try testing.expect(found_foreground and found_background);
    }
}

test "speckle mask handles empty patterns and equal colors" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_1bit and std.meta.activeTag(config) != .mask_u8) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        for ([_]bool{ false, true }) |equal_colour| {
            var params = speckleMaskTestParams(config);
            params.occupancy = if (equal_colour) 1.0 else 0.0;
            if (equal_colour) params.foreground = params.background;
            const mask = try Impl.generateSpeckleMask2D(testing.allocator, params);
            defer deinitTestResources(.{ .data = .{ .mask = mask } });
            if (Impl.speckle_shape == .perlin or equal_colour) {
                try testing.expect(mask.bits.len > 0);
            } else {
                try testing.expectEqual(@as(usize, 0), mask.bits.len);
            }
            if (equal_colour or Impl.speckle_shape != .perlin) {
                try testing.expectEqual(params.background, Impl.evalSpeckleMask2D(.{ 0.37, 0.61 }, mask));
            }
        }
    }
}

test "speckle mask clamps UV endpoints" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_1bit and std.meta.activeTag(config) != .mask_u8) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const mask = try Impl.generateSpeckleMask2D(testing.allocator, speckleMaskTestParams(config));
        defer deinitTestResources(.{ .data = .{ .mask = mask } });

        try testing.expectEqual(
            Impl.evalSpeckleMask2D(.{ 0.0, 1.0 }, mask),
            Impl.evalSpeckleMask2D(.{ -2.0, 3.0 }, mask),
        );
        try testing.expectEqual(
            Impl.evalSpeckleMask2D(.{ 1.0, 0.0 }, mask),
            Impl.evalSpeckleMask2D(.{ 3.0, -2.0 }, mask),
        );
    }
}

test "Perlin u8 mask quantizes analytic lattice coverage and samples nearest texels" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    const config: speckleconfig.Config = .{ .mask_u8 = .perlin };
    const Impl = Implementation(config);
    errdefer printSpeckleTestConfig(config);
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
            var mask = try Impl.generateSpeckleMask2D(testing.allocator, params);
            std.mem.doNotOptimizeAway(&mask);
            defer deinitTestResources(.{ .data = .{ .mask = mask } });
            try testing.expectEqual(mask.dims[0], mask.row_stride);
            try testing.expectEqual(mask.dims[0] * mask.dims[1], mask.bits.len);
            try testing.expectEqualDeep(params, mask.params);
            const resources: Resources = .{ .kernel_index = comptime kernelIndex(config), .data = .{ .mask = mask } };
            const K = Kernel(kernelIndex(config));
            const expected = Impl.evalSpeckleMask2D(.{ 0.37, 0.61 }, mask);
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
                    testing.expectEqual(Impl.quantizeSpeckleCoverage(analytic), byte) catch |err| {
                        std.debug.print("Perlin mask byte mismatch cells={any} width={d} texel=({d},{d}) analytic={d} byte={d}\n", .{ cells, width, xx, yy, analytic, byte });
                        return err;
                    };
                    const sampled = Impl.evalSpeckleMask2D(uv, mask);
                    try testing.expectApproxEqAbs(analytic, sampled, 0.5 / 255.0 + unit_tol);
                    found_intermediate = found_intermediate or (byte != 0 and byte != 255);
                    if (xx + 1 < mask.dims[0]) {
                        const nearby = [2]F{ uv[0] + 0.24 / mask.uv_to_texel[0], uv[1] };
                        try testing.expectApproxEqAbs(sampled, Impl.evalSpeckleMask2D(nearby, mask), unit_tol);
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
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_u8 or config.pattern() == .perlin) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const params = speckleMaskTestParams(config);
        const speckles = try Impl.generateSpeckleList2D(testing.allocator, params);
        defer deinitTestResources(.{ .data = .{ .list = speckles } });
        const mask = try Impl.generateSpeckleMask2D(testing.allocator, params);
        defer deinitTestResources(.{ .data = .{ .mask = mask } });

        try testing.expectEqual(mask.dims[0], mask.row_stride);
        try testing.expectEqual(mask.dims[0] * mask.dims[1], mask.bits.len);
        var found_intermediate = false;
        for (0..mask.dims[1]) |yy| {
            for (0..mask.dims[0]) |xx| {
                const uv = [2]F{
                    @as(F, @floatFromInt(xx)) / mask.uv_to_texel[0],
                    @as(F, @floatFromInt(yy)) / mask.uv_to_texel[1],
                };
                const analytic = Impl.evalSpeckleList2DNaiveImpl(uv[0], uv[1], speckles);
                const analytic_coverage = (analytic - params.background) /
                    (params.foreground - params.background);
                const expected_byte = Impl.quantizeSpeckleCoverage(analytic_coverage);
                const actual_byte = mask.bits[yy * mask.row_stride + xx];
                if (Impl.speckle_shape == .disk and config.edges() == .hard) {
                    try testing.expect(actual_byte == 0 or actual_byte == 255);
                }
                const byte_diff = if (actual_byte > expected_byte)
                    actual_byte - expected_byte
                else
                    expected_byte - actual_byte;
                try testing.expect(byte_diff <= 1);

                const coverage = @as(F, @floatFromInt(actual_byte)) / 255.0;
                const expected = params.background +
                    coverage * (params.foreground - params.background);
                try testing.expectEqual(expected, Impl.evalSpeckleMask2D(uv, mask));
                found_intermediate = found_intermediate or
                    (actual_byte != 0 and actual_byte != 255);
            }
        }
        if (Impl.speckle_shape == .gaussian or config.edges() == .soft) {
            try testing.expect(found_intermediate);
        }
    }
}

test "direct fixed prepared SIMD handles active and inactive lanes" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    const config: speckleconfig.Config = .direct_fixed;
    errdefer printSpeckleTestConfig(config);
    const cells = [_]u64{
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
        .cell_dims = .{ 3, 2 },
        .radius2 = 0.25 * 0.25,
    };
    const resources: Resources = .{ .data = .{ .direct_fixed = direct } };
    try expectPreparedSpeckleSIMD(config, params, &resources, &.{
        .{ .uv = .{ 0.25, 0.5 }, .expected = params.foreground },
        .{ .uv = .{ 0.375, 0.5 }, .expected = params.background },
        .{ .uv = .{ 0.1, 0.5 }, .expected = params.background },
        .{ .uv = .{ 0.75, 0.5 }, .expected = params.background },
        .{ .uv = .{ 0.25, 0.5 }, .active = false },
    });
}

test "classified indexed prepared SIMD matches scalar for every state" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    errdefer printSpeckleTestConfig(.classified_indexed);
    const params: Speckle2DParams = .{
        .evaluator = .classified_indexed,
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 5.25, 4.4 },
        .occupancy = 1.0,
        .radius_mean = 0.2,
        .radius_jitter = 0.0,
        .foreground = 0.17,
        .background = 0.83,
    };
    const classified = try Classified.generateClassifiedSpeckle2D(testing.allocator, params);
    defer deinitTestResources(.{ .data = .{ .classified = classified } });

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

    const resources: Resources = .{ .data = .{ .classified = classified } };
    try expectPreparedSpeckleSIMD(.classified_indexed, params, &resources, &.{
        .{ .uv = state_uv[0] },
        .{ .uv = state_uv[1] },
        .{ .uv = state_uv[2] },
        .{ .uv = state_uv[1], .active = false },
        .{ .uv = .{ std.math.nan(F), std.math.inf(F) } },
    });
}

test "all certified foreground cells return foreground without candidate records" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    const side: usize = buildconfig.speckle_mask_samples_per_cell + 1;
    const states: [side * side]u16 = @splat(512);
    const params = Speckle2DParams{ .cells_per_uv = .{ 1, 1 }, .foreground = 0.25, .background = 0.75 };
    // A certified foreground table must never touch these deliberately empty owner records.
    const resources = Resources{
        .kernel_index = kernelIndex(.classified_indexed),
        .data = .{ .classified = .{
            .speckles = .{ .params = params, .cell_origin = .{ 0, 0 }, .cell_dims = .{ 0, 0 } },
            .states = &states,
            .dims = .{ side, side },
        } },
    };
    for ([_]F{ -1, 0, 0.5, 1, 2, std.math.nan(F) }) |u| {
        try std.testing.expectEqual(params.foreground, sampleScal(u, 0.5, params, &resources));
        var active: [S]bool = undefined;
        for (&active, 0..) |*on, lane| on.* = lane % 2 == 0;
        const lanes: [S]F = sampleSIMD(@splat(u), @splat(0.5), active, params, &resources);
        for (lanes, active) |value, on| try std.testing.expectEqual(if (on) params.foreground else params.background, value);
    }
}

test "1-bit speckle mask SIMD matches scalar and backgrounds inactive lanes" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_1bit) continue;
        errdefer printSpeckleTestConfig(config);
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
        try expectPreparedSpeckleSIMD(config, params, &resources, &.{
            .{ .uv = .{ -2.0, 0.0 } },
            .{ .uv = .{ 0.0, 1.0 } },
            .{ .uv = .{ 0.0624, 0.0 } },
            .{ .uv = .{ 0.0625, 1.0 } },
            .{ .uv = .{ 0.99, 0.0 } },
            .{ .uv = .{ 1.0, 1.0 } },
            .{ .uv = .{ 3.0, 0.0 } },
            .{ .uv = .{ 0.5, 1.0 } },
            .{ .uv = .{ 0.0, 0.0 }, .active = false },
        });
    }
}

test "u8 speckle mask SIMD matches scalar for active lanes" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .mask_u8) continue;
        errdefer printSpeckleTestConfig(config);
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
            try expectPreparedSpeckleSIMD(config, params, &resources, &cases);
        }

        var no_gather_mask = mask;
        no_gather_mask.bits = &.{};
        const no_gather: Resources = .{ .data = .{ .mask = no_gather_mask } };
        try expectPreparedSpeckleSIMD(config, params, &no_gather, &.{
            .{ .uv = .{ 0.5, 0.5 }, .expected = params.background },
            .{ .uv = .{ 0.0, 0.0 }, .active = false },
        });
    }
}

test "speckle resources prepare sample open boundaries and release owned allocations" {
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) == .mock or config.edges() == .soft) continue;
        const Impl = Implementation(config);
        errdefer printSpeckleTestConfig(config);
        const single = Impl.speckle_neighbor_count == 1;
        const params: Speckle2DParams = .{
            .seed = 6,
            .cells_per_uv = if (single) .{ 1.0, 1.0 } else .{ 2.0, 1.0 },
            .occupancy = if (Impl.speckle_shape == .perlin) 0.0 else if (single) 1.0 else 0.1,
            .radius_mean = if (single) 0.5 else 1.0,
            .foreground = 0.25,
            .background = 0.75,
        };
        var resources = try Impl.generateConfiguredResources(testing.allocator, params);
        defer resources.deinit(testing.allocator);
        var fallback_params = params;
        if (comptime Impl.evaluator != .cell_hash) {
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
            const expected = if (Impl.speckle_shape == .disk and single)
                (if (index == 0) params.foreground else params.background)
            else if (Impl.speckle_shape == .disk and Impl.speckle_neighbor_count == 4 and index == 3)
                params.background
            else switch (comptime Impl.evaluator) {
                .mock => unreachable,
                .cell_hash, .gradient_lattice => evalSpeckle2D(config, uv, params),
                .list_naive => Impl.evalSpeckleList2DNaiveImpl(uv[0], uv[1], resources.data.list),
                .list_indexed => Impl.evalStripSpeckleList2DImpl(uv[0], uv[1], resources.data.strip_list),
                .cell_binned => Impl.evalCellBinnedSpeckle2D(uv[0], uv[1], resources.data.cell_binned),
                .classified_indexed => Impl.evalClassifiedIndexedSpeckle2D(
                    uv,
                    resources.data.classified,
                ),
                .classified_binned => ClassifiedBinned.sampleScal(uv[0], uv[1], &resources.data.classified_binned),
                .direct_fixed => Impl.evalDirectFixedSpeckle2D(uv, resources.data.direct_fixed),
                .mask_1bit, .mask_u8 => Impl.evalSpeckleMask2D(uv, resources.data.mask),
            };
            try testing.expectEqual(expected, Impl.samplePreparedScal(uv[0], uv[1], fallback_params, &resources));
            const actual: [S]F = Impl.samplePreparedSIMD(
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
}

test "speckle numeric parameters validate common and shape-specific contracts" {
    const coord_limit: F = if (F == f32) 65_536.0 else 35_184_372_088_832.0;
    const common = [_]struct { params: Speckle2DParams, err: anyerror }{
        .{ .params = .{ .cells_per_uv = .{ 0.0, 1.0 } }, .err = error.InvalidSpeckleCellsPerUV },
        .{ .params = .{ .cells_per_uv = .{ 1.0, std.math.nan(F) } }, .err = error.InvalidSpeckleCellsPerUV },
        .{ .params = .{ .cells_per_uv = .{ coord_limit, 1.0 } }, .err = error.SpeckleCellCoordinateOutOfRange },
        .{ .params = .{ .foreground = 1.1 }, .err = error.InvalidSpeckleForeground },
        .{ .params = .{ .background = -0.1 }, .err = error.InvalidSpeckleBackground },
        .{ .params = .{ .background = std.math.nan(F) }, .err = error.InvalidSpeckleBackground },
    };
    for (common) |case| try std.testing.expectError(case.err, case.params.resolve());

    // Numeric field rules depend on pattern and neighborhood, not storage layout.
    for (analytic_test_configs) |config| {
        errdefer std.debug.print("numeric validation pattern={any} neighbors={any} edges={any}\n", .{ config.pattern(), config.neighborhood(), config.edges() });
        var params = Speckle2DParams{ .pattern = config.pattern().? };
        try std.testing.expectEqual(@as(F, 0), params.edge_softness);
        try params.validateResolved(config);
        if (config.pattern() == .perlin) {
            params.perlin_coverage_threshold = std.math.nan(F);
            try std.testing.expectError(error.InvalidSpecklePerlinCoverageThreshold, params.validateResolved(config));
            params.perlin_coverage_threshold = 0;
            for ([_]F{ -0.01, std.math.nan(F), std.math.inf(F) }) |width| {
                params.perlin_coverage_transition_width = width;
                try std.testing.expectError(error.InvalidSpecklePerlinCoverageTransitionWidth, params.validateResolved(config));
            }
            params.perlin_coverage_transition_width = 0;
            params.occupancy = -1;
            params.radius_mean = -1;
            params.radius_jitter = -1;
            try params.validateResolved(config);
        } else {
            const cases = [_]struct { params: Speckle2DParams, err: anyerror }{
                .{ .params = .{ .occupancy = -0.1 }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .occupancy = 1.1 }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .occupancy = std.math.nan(F) }, .err = error.InvalidSpeckleOccupancy },
                .{ .params = .{ .radius_mean = 0.0 }, .err = error.InvalidSpeckleRadiusMean },
                .{ .params = .{ .radius_mean = std.math.inf(F) }, .err = error.InvalidSpeckleRadiusMean },
                .{ .params = .{ .radius_jitter = -0.1 }, .err = error.InvalidSpeckleRadiusJitter },
                .{ .params = .{ .radius_jitter = std.math.nan(F) }, .err = error.InvalidSpeckleRadiusJitter },
            };
            for (cases) |case| try std.testing.expectError(case.err, case.params.validateResolved(config));
            params.perlin_coverage_threshold = std.math.nan(F);
            params.perlin_coverage_transition_width = -1;
            try params.validateResolved(config);
            params.radius_jitter = params.radius_mean + 0.01;
            try std.testing.expectError(error.InvalidSpeckleRadiusRange, params.validateResolved(config));
            params.radius_jitter = 0;
            params.radius_mean = if (config.neighborhood() == .one) 0.5 else 1.0;
            try params.validateResolved(config);
            params.radius_mean = std.math.nextAfter(F, params.radius_mean, std.math.inf(F));
            try std.testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validateResolved(config));
            if (config.edges() == .soft) {
                params.radius_mean = (if (config.neighborhood() == .one) @as(F, 0.5) else 1.0) - 0.125;
                params.edge_softness = 0.125;
                try params.validateResolved(config);
                params.edge_softness = 0.25;
                try std.testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validateResolved(config));
                params.edge_softness = 0;
                params.radius_jitter = 0.125;
                try params.validateResolved(config);
                params.edge_softness = 0.125;
                try std.testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validateResolved(config));
            }
        }
    }
    if (comptime buildconfig.enable_all_evaluators) {
        var direct = Speckle2DParams{};
        direct.radius_jitter = 0.01;
        try std.testing.expectError(error.InvalidDirectFixedSpeckleRadiusJitter, direct.validateResolved(.direct_fixed));
        direct.radius_jitter = 0;
        direct.radius_mean = 0.5;
        try direct.validateResolved(.direct_fixed);
        direct.radius_mean = std.math.nextAfter(F, direct.radius_mean, std.math.inf(F));
        try std.testing.expectError(error.InvalidDirectFixedSpeckleRadius, direct.validateResolved(.direct_fixed));
    }
}

test "Perlin accepts negative zero settings and preserves exact uniform foreground samples" {
    const params = Speckle2DParams{ .pattern = .perlin, .cells_per_uv = .{ 2.17, 1.31 }, .perlin_coverage_threshold = -0.0, .perlin_coverage_transition_width = -0.0 };
    _ = try params.resolve();
    var lattice = try generatePerlinLattice(std.testing.allocator, params);
    defer std.testing.allocator.free(lattice.gradients);
    for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ 0.37, 0.61 }, .{ -1, 2 } }) |uv| {
        const expected = PerlinReference.evalPerlinSpeckle2D(uv, params);
        try std.testing.expectEqual(expected, samplePerlinScal(uv[0], uv[1], lattice));
        const lanes: [S]F = samplePerlinSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), lattice);
        for (lanes) |value| try std.testing.expectEqual(expected, value);
    }
    lattice.params.perlin_coverage_threshold = -std.math.floatMax(F);
    for ([_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ 0.37, 0.61 } }) |uv| {
        try std.testing.expectEqual(params.foreground, samplePerlinScal(uv[0], uv[1], lattice));
        const lanes: [S]F = samplePerlinSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), lattice);
        for (lanes) |value| try std.testing.expectEqual(params.foreground, value);
    }
}

const testing = std.testing;
const unit_tol: F = if (F == f32) 1e-5 else 1e-12;
const Classified = Implementation(.classified_indexed);

const SpeckleSIMDCase = struct {
    uv: [2]F,
    active: bool = true,
    expected: ?F = null,
};

inline fn classificationCoordinate(uv: F, cells: F) F {
    return (@max(0.0, @min(1.0, uv)) * cells) * speckle_mask_samples_per_cell;
}

fn evalSpeckle2D(comptime config: speckleconfig.Config, uv: [2]F, params: Speckle2DParams) F {
    const Impl = Implementation(config);
    return Impl.evalSpeckle2DImpl(uv[0], uv[1], params);
}

fn expectNeighborMaskCandidates(masked: ClassifiedIndexedSpeckle2D) !void {
    const params = masked.speckles.params;
    const Owner = struct { cell: [2]i64, disk: SpeckleDisk2D };
    const bounds = Classified.speckleProceduralCellBounds(params, 1).?;
    const owners = try testing.allocator.alloc(Owner, bounds.count);
    defer testing.allocator.free(owners);
    var owner_count: usize = 0;
    // Regenerate owners independently of strip records, stamp ranges,
    // and the separable mask multiplication being tested.
    for (0..bounds.dims[1]) |yy| {
        for (0..bounds.dims[0]) |xx| {
            const cell: [2]i64 = .{ bounds.min[0] + @as(i64, @intCast(xx)), bounds.min[1] + @as(i64, @intCast(yy)) };
            if (Classified.speckleDiskForCell(cell[0], cell[1], params)) |disk| {
                owners[owner_count] = .{ .cell = cell, .disk = disk };
                owner_count += 1;
            }
        }
    }
    const axes = Classified.speckleClassificationAxes(masked.dims);
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
            switch (Classified.classifySpeckleDiskMicrocell(owner.disk, lo, hi)) {
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

fn testClassifiedDims(params: Speckle2DParams) [2]usize {
    const dims = Classified.classifiedDims(params);
    return .{ @intCast(dims[0]), @intCast(dims[1]) };
}

fn deinitTestResources(resources: Resources) void {
    var owned = resources;
    owned.deinit(testing.allocator);
}

fn expectClassifiedSample(resources: *const Resources, uv: [2]F) !void {
    const strip = resources.data.classified.speckles;
    const params = strip.params;
    const expected = if (strip.recordCount() == 0) params.background else evalSpeckle2D(.classified_indexed, uv, params);
    const K = Kernel(kernelIndex(.classified_indexed));
    try testing.expectEqual(expected, K.sampleScal(uv[0], uv[1], params, resources));
    const values: [S]F = K.sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(true), params, resources);
    for (values) |value| try testing.expectEqual(expected, value);
    if (strip.recordCount() != 0) {
        const indexed = Classified.evalStripSpeckleList2DImpl(uv[0], uv[1], strip);
        try testing.expectEqual(expected, indexed);
    }
}

fn expectClassifiedExact(params: Speckle2DParams) !bool {
    var prepared_params = params;
    prepared_params.evaluator = .classified_indexed;
    var resources = try Resources.init(testing.allocator, prepared_params);
    defer resources.deinit(testing.allocator);
    try testing.expectEqual(@as(?u8, kernelIndex(.classified_indexed)), resources.kernel_index);
    const classified = resources.data.classified;
    const strip = classified.speckles;
    try expectNeighborMaskCandidates(classified);
    const bounds = Classified.speckleProceduralCellBounds(params, 1).?;
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
        if (Classified.speckleDiskForCell(owner_x, owner_y, params)) |expected| {
            try testing.expectEqualDeep(expected, record);
            try testing.expect(record.radius * record.radius <= strip.max_outer_radius2);
            for (record.center, [2]i64{ owner_x, owner_y }) |coordinate, owner| {
                try testing.expect(coordinate >= @as(F, @floatFromInt(owner)) and coordinate <= @as(F, @floatFromInt(owner + 1)));
            }
        } else {
            try testing.expectEqual(std.math.inf(F), record.center[0]);
            try testing.expectEqual(@as(F, 0), record.center[1]);
            try testing.expectEqual(params.radius_mean, record.radius);
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
            const boundary = Classified.speckleClassificationAxes(classified.dims)[axis].boundary(index) / params.cells_per_uv[axis];
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
    const K = Kernel(kernelIndex(.classified_indexed));
    for (0..8) |batch| {
        var us: [S]F = undefined;
        var vs: [S]F = undefined;
        var active: [S]bool = undefined;
        for (0..S) |lane| {
            us[lane] = @as(F, @floatFromInt((batch * S + lane) % 17)) / 16.0;
            vs[lane] = if (batch == 0 and lane % 2 == 0) -2 else if (batch == 1 and lane % 2 == 0) 2 else 1.0 - us[lane];
            active[lane] = (batch + lane) % 3 != 0;
        }
        const actual: [S]F = K.sampleSIMD(us, vs, active, params, &resources);
        for (0..S) |lane| {
            const expected = if (strip.recordCount() != 0 and active[lane]) evalSpeckle2D(.classified_indexed, .{ us[lane], vs[lane] }, params) else params.background;
            try testing.expectEqual(expected, actual[lane]);
        }
    }
    return has_zero_radius;
}

fn speckleMaskTestParams(comptime config: speckleconfig.Config) Speckle2DParams {
    return .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 3.25, 2.5 },
        .occupancy = 0.72,
        .radius_mean = 0.38,
        .radius_jitter = 0.07,
        .edge_softness = if (std.meta.activeTag(config) == .mask_u8 and
            config.edges() == .soft) 0.035 else 0.0,
        .foreground = 0.15,
        .background = 0.85,
    };
}

fn expectPreparedSpeckleSIMD(
    comptime config: speckleconfig.Config,
    params: Speckle2DParams,
    resources: *const Resources,
    cases: []const SpeckleSIMDCase,
) !void {
    const Impl = Implementation(config);
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
        const actual: [S]F = Impl.samplePreparedSIMD(coord_0, coord_1, active, params, resources);
        for (0..S) |lane| {
            const case = cases[(batch * S + lane) % cases.len];
            const expected = if (case.active)
                Impl.samplePreparedScal(case.uv[0], case.uv[1], params, resources)
            else
                params.background;
            if (case.expected) |value| try testing.expectEqual(value, expected);
            try testing.expectEqual(expected, actual[lane]);
        }
    }
}

test "user validation requires positive occupancy only for disk and Gaussian" {
    for ([_]speckleconfig.Pattern{ .disk, .gaussian }) |pattern| {
        for ([_]F{ 0.0, -0.0 }) |occupancy| {
            var params: Speckle2DParams = .{
                .pattern = pattern,
                .occupancy = occupancy,
            };
            try std.testing.expectError(error.InvalidSpeckleOccupancy, params.validate());
            _ = try params.resolve();

            params.occupancy = std.math.floatMin(F);
            try params.validate();
        }
    }
    const equal_colors = Speckle2DParams{ .foreground = 0.23, .background = 0.23 };
    _ = try equal_colors.resolve();
    try std.testing.expectError(error.SpeckleColorsMustDiffer, equal_colors.validate());
    try (Speckle2DParams{ .pattern = .perlin, .occupancy = 0 }).validate();
    if (comptime buildconfig.enable_all_evaluators) {
        try (Speckle2DParams{ .evaluator = .mock, .occupancy = 0 }).validate();
    }
}

test "runtime override policy and invalid settings fail before allocation" {
    for ([_]F{ -0.01, std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |softness| {
        for (std.enums.values(speckleconfig.Pattern)) |pattern| {
            try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, Resources.init(std.testing.failing_allocator, .{ .pattern = pattern, .edge_softness = softness }));
        }
    }
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
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
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
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    const Probe = struct {
        fn generate(allocator: std.mem.Allocator, jitter: F, occupancy: F) !void {
            var tracking = std.testing.FailingAllocator.init(allocator, .{});
            const tracked_allocator = tracking.allocator();
            var resources = try Resources.init(tracked_allocator, .{
                .evaluator = .classified_indexed,
                .cells_per_uv = .{ 2, 1 },
                .occupancy = occupancy,
                .radius_mean = 0.35,
                .radius_jitter = jitter,
            });
            defer resources.deinit(tracked_allocator);
            try std.testing.expectEqual(@as(usize, 2), tracking.allocations);
            const strip = resources.data.classified.speckles;
            try std.testing.expectEqual(occupancy == 0.0, strip.recordCount() == 0);
            if (occupancy == 0.0) {
                for (resources.data.classified.states) |state| try std.testing.expectEqual(@as(u16, 0), state);
            }
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

test "positive-occupancy empty owner strips return the background regardless of zero sign" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    for ([_]F{ 0.0, 0.08 }) |jitter| {
        const params: Speckle2DParams = .{ .evaluator = .classified_indexed, .seed = 0, .cells_per_uv = .{ 0.03125, 0.0625 }, .occupancy = 0.001, .radius_mean = 0.35, .radius_jitter = jitter, .foreground = 0.91, .background = -0.0 };
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        const strip = resources.data.classified.speckles;
        try std.testing.expectEqual(@as(usize, 0), strip.centers.len);
        try std.testing.expectEqual(@as(usize, 0), strip.disks.len);
        for (resources.data.classified.states) |state| try std.testing.expectEqual(@as(u16, 0), state);
        for ([_]F{ 0.0, 0.5, 1.0, std.math.nan(F) }) |u| {
            try std.testing.expectEqual(params.background, sampleScal(u, 0.5, params, &resources));
            inline for (.{ false, true }) |active| {
                const lanes: [S]F = sampleSIMD(@splat(u), @splat(0.5), @splat(active), params, &resources);
                for (lanes) |value| try std.testing.expectEqual(params.background, value);
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
        const raw = Implementation(config).evalSpeckle2DImpl(0.37, 0.61, params);
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
            .classified_binned => .classified_binned,
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
        const points = [_][2]F{ .{ 0, 0 }, .{ 1, 1 }, .{ -2, 0.37 }, .{ 0.35, 0.61 }, .{ 0.67, 0.41 }, .{ 0.37, 2 } };
        for (points) |uv| {
            const Impl = Implementation(config);
            const reference = switch (comptime evaluator) {
                .mock => 0.5 * (uv[0] + uv[1]),
                .cell_hash, .gradient_lattice, .list_indexed, .cell_binned => evalSpeckle2D(config, uv, params),
                // Direct-fixed returns stored endpoints, not the hash reference's arithmetic mapping.
                .direct_fixed => if (evalSpeckle2D(config, uv, params) == params.background)
                    params.background
                else
                    params.foreground,
                .list_naive => Impl.evalSpeckleList2DNaiveImpl(uv[0], uv[1], resources.data.list),
                .classified_indexed, .classified_binned => evalSpeckle2D(config, uv, params),
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
        // The UV clamp alone keeps out-of-contract UVs in bounds, so samplers need no
        // per-sample finiteness checks. Mock is raw arithmetic.
        if (comptime evaluator != .mock) {
            const nan = std.math.nan(F);
            const inf = std.math.inf(F);
            const extremes = [_][2]F{ .{ nan, 1 }, .{ -inf, 0 }, .{ inf, 1 }, .{ -std.math.floatMax(F), 0 }, .{ std.math.floatMax(F), 1 }, .{ -0.5, 0 }, .{ 1.5, 1 }, .{ 0.37, 0.37 } };
            const junk = [_]F{ nan, inf, -inf };
            for (extremes) |eu| {
                for (extremes) |ev| {
                    const expected = Kernel(index).sampleScal(eu[1], ev[1], params, &resources);
                    try std.testing.expectEqual(expected, Kernel(index).sampleScal(eu[0], ev[0], params, &resources));
                    // Active samples alternate with rotating nonfinite inactive lanes.
                    for (0..2) |parity| {
                        var us: [S]F = undefined;
                        var vs: [S]F = undefined;
                        var active: [S]bool = undefined;
                        for (0..S) |lane| {
                            active[lane] = (lane + parity) % 2 == 0;
                            us[lane] = if (active[lane]) eu[0] else junk[lane % 3];
                            vs[lane] = if (active[lane]) ev[0] else junk[(lane + 1) % 3];
                        }
                        const lanes: [S]F = Kernel(index).sampleSIMD(us, vs, active, params, &resources);
                        for (lanes, active) |value, on| {
                            if (on) try std.testing.expectEqual(expected, value);
                        }
                    }
                }
            }
        }
        resources.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(?u8, null), resources.kernel_index);
        try std.testing.expectEqualDeep(Resources{}, resources);
    }
}

test "representable resource allocations reach the allocator" {
    inline for (generation_configs) |config| {
        const evaluator = comptime std.meta.activeTag(config);
        const cells: [2]F = switch (evaluator) {
            .cell_hash, .mock => continue,
            .gradient_lattice => .{ 16_383, 16_383 },
            // Naive lists must count owners before allocating: keep that work small.
            .list_naive => .{ 2, 1 },
            .list_indexed => .{ 9_997, 998 },
            .cell_binned, .classified_indexed, .classified_binned => .{ 2000, 2000 },
            .direct_fixed => .{ 65_535, 512 },
            .mask_u8 => .{ 2200, 2200 },
            .mask_1bit => .{ 4000, 4000 },
        };
        var params: Speckle2DParams = .{
            .pattern = config.pattern() orelse .disk,
            .cells_per_uv = cells,
            .edge_softness = if (config.edges() == .soft) 0.035 else 0,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            params.evaluator = evaluator;
            params.neighbor_count = config.neighborhood();
        }
        // No large allocations: reaching the failing allocator proves size acceptance.
        try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, params));
    }
}

test "unrepresentable resource grids fail before allocation without fallback" {
    if (comptime F == f32 and @bitSizeOf(usize) == 64) return error.SkipZigTest;
    const cells: F = if (F == f32) 65_535 else 35_184_372_088_831;
    inline for (generation_configs) |config| {
        const evaluator = comptime std.meta.activeTag(config);
        const expected = switch (evaluator) {
            .cell_hash, .mock => continue,
            .gradient_lattice => error.SpecklePerlinLatticeTooLarge,
            .list_naive, .list_indexed => error.SpeckleListTooLarge,
            .cell_binned => error.SpeckleCellBinsTooLarge,
            .classified_indexed, .classified_binned => error.SpeckleClassificationTooLarge,
            .direct_fixed => error.DirectFixedSpeckleTooLarge,
            .mask_1bit, .mask_u8 => error.SpeckleMaskTooLarge,
        };
        var params: Speckle2DParams = .{
            .pattern = config.pattern() orelse .disk,
            .cells_per_uv = .{ cells, cells },
            .edge_softness = if (config.edges() == .soft) 0.035 else 0,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            params.evaluator = evaluator;
            params.neighbor_count = config.neighborhood();
        }
        try params.validate();
        try std.testing.expectError(expected, Resources.init(std.testing.failing_allocator, params));
    }
}

test "32 bit preparation rejects byte and record expansion overflow before allocation" {
    if (comptime @bitSizeOf(usize) != 32) return error.SkipZigTest;
    try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 40_000, 40_000 } }));
    try std.testing.expectError(error.SpeckleCellBinsTooLarge, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 40_000, 40_000 }, .edge_softness = 0.04 }));
    if (comptime buildconfig.enable_all_evaluators) {
        // The state count fits u32, but its two-byte elements do not. Owners still fit.
        const classification: Speckle2DParams = .{
            .evaluator = .classified_indexed,
            .cells_per_uv = .{ 65_535.5 / speckle_mask_samples_per_cell, 32_768.5 / speckle_mask_samples_per_cell },
        };
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, classification));
        for ([_]struct { evaluator: speckleconfig.Evaluator, err: anyerror }{
            .{ .evaluator = .list_indexed, .err = error.SpeckleListTooLarge },
            .{ .evaluator = .cell_binned, .err = error.SpeckleCellBinsTooLarge },
            .{ .evaluator = .classified_binned, .err = error.SpeckleClassificationTooLarge },
            .{ .evaluator = .direct_fixed, .err = error.DirectFixedSpeckleTooLarge },
        }) |case| {
            for ([_]F{ 0, 0.08 }) |jitter| {
                if (case.evaluator == .direct_fixed and jitter != 0) continue;
                const params: Speckle2DParams = .{
                    .evaluator = case.evaluator,
                    .cells_per_uv = .{ 40_000, 40_000 },
                    .radius_jitter = jitter,
                };
                try params.validate();
                try std.testing.expectError(case.err, Resources.init(std.testing.failing_allocator, params));
            }
        }
    }
}

test "classified bins 32 bit packed headers do not require a flattened microcell array" {
    if (comptime @bitSizeOf(usize) != 32) return error.SkipZigTest;
    const params: Speckle2DParams = .{
        .cells_per_uv = .{ 12_000, 12_000 },
        .radius_jitter = 0.08,
        .occupancy = 0,
    };
    const dim_x = classifiedAxisDim(ClassifiedBinned.Rx, params.cells_per_uv[0]).?;
    const dim_y = classifiedAxisDim(ClassifiedBinned.Ry, params.cells_per_uv[1]).?;
    try std.testing.expectEqual(@as(usize, 96_001), dim_x);
    try std.testing.expectEqual(@as(usize, 48_001), dim_y);
    try std.testing.expect(@as(u64, dim_x) * dim_y > std.math.maxInt(usize));
    // Packed bin headers/counts/CSR offsets fit in about 1.87 GB; no flat grid is stored.
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, params));
    if (F == f64) {
        var signed_overflow = params;
        signed_overflow.cells_per_uv = .{ 268_435_456, 0.01 };
        _ = try signed_overflow.resolve();
        try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, signed_overflow));
    }
}

test "packed mask rejects unrepresentable SIMD indices even when its bytes fit" {
    if (comptime !buildconfig.enable_all_evaluators or F != f64 or @bitSizeOf(usize) != 32)
        return error.SkipZigTest;
    const intervals: u64 = 1 << 31;
    const params: Speckle2DParams = .{
        .evaluator = .mask_1bit,
        .cells_per_uv = .{ @as(F, @floatFromInt(intervals)) / speckle_mask_samples_per_cell, 0.5 / speckle_mask_samples_per_cell },
    };
    try params.validate();
    try std.testing.expect(gridCount(u8, .{ intervals / 8 + 1, 2 }) != null);
    try std.testing.expectError(error.SpeckleMaskTooLarge, Resources.init(std.testing.failing_allocator, params));
}

test "strip indexed records and samples match exhaustive lists exactly across occupancy and neighborhoods" {
    @setEvalBranchQuota(10_000);
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
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
                            try std.testing.expectEqual(@as(F, 0), Impl.fixedStripDiskMask(distance2, strip));
                        }
                    }
                }
                for (0..strip.cell_dims[1]) |yy| {
                    for (0..strip.cell_dims[0]) |xx| {
                        for (0..length) |ii| {
                            const disk: SpeckleDisk2D = Impl.speckleDiskForCell(strip.cell_origin[0] + @as(i64, @intCast(xx)), strip.cell_origin[1] + @as(i64, @intCast(yy)) + @as(i64, @intCast(ii)) - (if (speckle_neighbor_count == 9) @as(i64, 1) else 0), params) orelse .{ .center = .{ 0.0, 0.0 }, .radius = -1.0 };
                            const stored = strip.record((yy * strip.cell_dims[0] + xx) * length + ii);
                            if (disk.radius < 0.0) {
                                try std.testing.expectEqual(std.math.inf(F), stored.center[0]);
                                try std.testing.expectEqual(@as(F, 0.0), stored.center[1]);
                                try std.testing.expectEqual(params.radius_mean, stored.radius);
                                const mask = if (params.radius_jitter == 0.0)
                                    Impl.fixedStripDiskMask(std.math.inf(F), strip)
                                else
                                    Impl.speckleDiskMask(std.math.inf(F), stored.radius, params.edge_softness);
                                try std.testing.expectEqual(@as(F, 0.0), mask);
                            } else {
                                try std.testing.expectEqualDeep(disk, stored);
                            }
                        }
                    }
                }
                for (table.disks) |disk| {
                    const u = disk.center[0] / table.params.cells_per_uv[0];
                    const v = disk.center[1] / table.params.cells_per_uv[1];
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(Impl.evalSpeckleList2DNaiveImpl, @splat(u), @splat(v), table);
                    const after: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(false), params, &indexed);
                    for (before, after) |reference, actual| try std.testing.expectEqual(reference, actual);
                    if (params.radius_jitter == 0.0) {
                        const support = disk.radius + params.edge_softness;
                        for (0..2) |axis| {
                            for ([_]F{ -support, support }) |edge| {
                                const point = (disk.center[axis] + edge) / params.cells_per_uv[axis];
                                for ([_]F{ point, std.math.nextAfter(F, point, -std.math.inf(F)), std.math.nextAfter(F, point, std.math.inf(F)) }) |coordinate| {
                                    const edge_u = if (axis == 0) coordinate else u;
                                    const edge_v = if (axis == 1) coordinate else v;
                                    const expected = sampleScal(edge_u, edge_v, table.params, &reference_resources);
                                    try std.testing.expectEqual(expected, sampleScal(edge_u, edge_v, params, &indexed));
                                    const lanes: [S]F = sampleSIMD(@splat(edge_u), @splat(edge_v), @splat(false), params, &indexed);
                                    for (lanes) |actual| try std.testing.expectEqual(expected, actual);
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
                    const before: [S]F = Impl.evalSpeckleSIMDImpl(Impl.evalSpeckleList2DNaiveImpl, us, vs, table);
                    const after: [S]F = sampleSIMD(us, vs, @splat(false), params, &indexed);
                    for (before, after) |reference, actual| try std.testing.expectEqual(reference, actual);
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
                    const expected: [S]F = Impl.evalSpeckleSIMDImpl(Impl.evalSpeckleList2DNaiveImpl, us, vs, table);
                    const actual: [S]F = sampleSIMD(us, vs, active, params, &indexed);
                    for (us, vs) |u, v| {
                        if (!std.math.isFinite(u) or !std.math.isFinite(v)) continue;
                        try std.testing.expectEqual(sampleScal(u, v, table.params, &reference_resources), sampleScal(u, v, params, &indexed));
                    }
                    for (expected, actual) |before, after| {
                        try std.testing.expectEqual(before, after);
                    }
                }
                for (0..2) |axis| {
                    for (0..strip.cell_dims[axis]) |ii| {
                        const boundary = (@as(F, @floatFromInt(strip.cell_origin[axis] + @as(i64, @intCast(ii))))) / params.cells_per_uv[axis];
                        for ([_]F{ boundary, std.math.nextAfter(F, boundary, -std.math.inf(F)), std.math.nextAfter(F, boundary, std.math.inf(F)) }) |coordinate| {
                            const u = if (axis == 0) coordinate else 0.5;
                            const v = if (axis == 1) coordinate else 0.5;
                            try std.testing.expectEqual(sampleScal(u, v, table.params, &reference_resources), sampleScal(u, v, params, &indexed));
                        }
                    }
                }
                for (0..23) |yy| {
                    for (0..23) |xx| {
                        const u = @as(F, @floatFromInt(xx)) / 20.0 - 0.05;
                        const v = @as(F, @floatFromInt(yy)) / 20.0 - 0.05;
                        const expected = sampleScal(u, v, table.params, &reference_resources);
                        try std.testing.expectEqual(expected, sampleScal(u, v, params, &indexed));
                        const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(true), params, &indexed);
                        for (lanes) |value| try std.testing.expectEqual(expected, value);
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
        const n = @intFromEnum(p.neighbor_count orelse .nine);
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
        const px = @max(0, @min(1, u)) * p.cells_per_uv[0];
        const py = @max(0, @min(1, v)) * p.cells_per_uv[1];
        const sx: i64 = @intFromFloat(@floor(px));
        const sy: i64 = @intFromFloat(@floor(py));
        const n = @intFromEnum(p.neighbor_count orelse .nine);
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

test "cell binned independent exhaustive field reference" {
    @setEvalBranchQuota(100_000);
    inline for (generation_configs) |config| {
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const soft = comptime config.edges() == .soft;
        const limit: F = if (config.neighborhood() == .one) 0.5 else 1;
        for (0..8) |variation| {
            const p: Speckle2DParams = .{
                .evaluator = if (buildconfig.enable_all_evaluators) std.meta.activeTag(config) else null,
                .pattern = config.pattern().?,
                .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
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
                if (variation == 0 or variation == 5) try std.testing.expectEqual(@as(F, 0), expected);
                if (variation == 6) try std.testing.expectEqual(p.background, expected);
                try std.testing.expectEqual(expected, sampleScal(uv[0], uv[1], p, &resources));
                const lanes: [S]F = sampleSIMD(@splat(uv[0]), @splat(uv[1]), @splat(false), p, &resources);
                for (lanes) |actual| try std.testing.expectEqual(expected, actual);
            }
        }
    }
}

// Borrowed, stack-backed fixtures share the original per-disk reduction as their reference.
fn expectGaussianStrided(radius: F, points: []const [2]F, colors: [2]F) !void {
    const Impl = Implementation(.{ .cell_binned = .{ .gaussian = .nine } });
    std.debug.assert(points.len <= 9);
    // Poison every unused slot with a hit at the sample point.
    var coordinates: [18]F = @splat(0);
    var coverage: F = 0;
    for (points, 0..) |point, ii| {
        coordinates[ii] = point[0];
        coordinates[9 + ii] = point[1];
        const d2 = point[0] * point[0] + point[1] * point[1];
        coverage = @max(coverage, Impl.speckleDiskMask(d2, radius, 0));
    }
    if (radius == 0.75) try std.testing.expect(coverage < 1);
    const counts = [_]u8{@intCast(points.len)};
    const params: Speckle2DParams = .{
        .pattern = .gaussian,
        .radius_mean = radius,
        .cells_per_uv = .{ 0.5, 0.5 },
        .foreground = colors[0],
        .background = colors[1],
    };
    const binned = CellBinnedSpeckle2D{
        .params = params,
        .dims = .{ 1, 1 },
        .offsets = &.{},
        .records = .{ .strided = .{ .coordinates = &coordinates, .counts = &counts } },
    };
    const resources = Resources{ .kernel_index = kernelIndex(try params.resolve()), .data = .{ .cell_binned = binned } };
    const expected = params.background + coverage * (params.foreground - params.background);
    try std.testing.expect(std.math.isFinite(expected));
    try std.testing.expectEqual(expected, Impl.evalCellBinnedSpeckle2D(0, 0, binned));
    const prepared: [S]F = Impl.samplePreparedSIMD(@splat(0), @splat(0), @splat(false), params, &resources);
    for (prepared) |value| try std.testing.expectEqual(expected, value);
    var borrowed = params;
    borrowed.foreground = 0.37;
    borrowed.background = 0.63;
    borrowed.radius_mean = 0.2;
    try std.testing.expectEqual(expected, sampleScal(0, 0, borrowed, &resources));
    const lanes: [S]F = sampleSIMD(@splat(0), @splat(0), @splat(false), borrowed, &resources);
    for (lanes) |value| try std.testing.expectEqual(expected, value);
    const invalid: [S]F = sampleSIMD(@splat(std.math.nan(F)), @splat(0), @splat(true), borrowed, &resources);
    for (invalid) |value| try std.testing.expectEqual(sampleScal(1, 0, borrowed, &resources), value);
}

test "cell binned overlapping Gaussian adjacent scores and exp plateaus" {
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
        if (@exp(ea) == @exp(eb)) plateaus += 1;
        for (0..2) |order| {
            const points = [_][2]F{ .{ 0.125, if (order == 0) y0 else y1 }, .{ 0.125, if (order == 0) y1 else y0 } };
            try expectGaussianStrided(0.75, &points, .{ 0.91, -0.0 });
        }
    }
    try std.testing.expect(plateaus > 0);
}

test "cell binned records preserve exact samples at supports faces colors and SIMD lanes" {
    @setEvalBranchQuota(100_000);
    // Default builds cover only the default cell-binned configurations.
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
                    .evaluator = if (buildconfig.enable_all_evaluators) std.meta.activeTag(config) else null,
                    .pattern = config.pattern().?,
                    .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
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
                const Reference = CellBinnedIndependentReference;
                const binned = owned.data.cell_binned;
                const count = switch (binned.records) {
                    .disks => |records| records.len,
                    .gaussian => |records| records.len,
                    .strided => binned.recordCount(),
                };
                try std.testing.expectEqual(count, binned.recordCount());
                for (0..binned.dims[0] * binned.dims[1]) |cell| {
                    if (binned.records == .strided) {
                        try std.testing.expect(binned.records.strided.counts[cell] <= 9);
                    } else {
                        const start = binned.offsets[cell];
                        const end = binned.offsets[cell + 1];
                        try std.testing.expect(start <= end and end - start <= 9);
                    }
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
                    const actual: [S]F = sampleSIMD(us, vs, active, params, &owned);
                    for (actual, us, vs) |after, u, v| {
                        // Cell-binned lanes all evaluate; NaN clamps to the upper endpoint.
                        try std.testing.expectEqual(Reference.sample(params, @max(0.0, @min(1.0, u)), @max(0.0, @min(1.0, v))), after);
                        if (std.math.isFinite(u) and std.math.isFinite(v)) {
                            const value = sampleScal(u, v, params, &owned);
                            try std.testing.expectEqual(after, value);
                            // Compare the analytic path even for empty patterns.
                            try std.testing.expectEqual(Impl.evalSpeckle2DImpl(u, v, params), value);
                        }
                    }
                }
                // Independently generate owners, including zero-radius records and halo disks.
                var owner_y: i64 = -1;
                while (owner_y <= @as(i64, @intFromFloat(@floor(params.cells_per_uv[1]))) + 1) : (owner_y += 1) {
                    var owner_x: i64 = -1;
                    while (owner_x <= @as(i64, @intFromFloat(@floor(params.cells_per_uv[0]))) + 1) : (owner_x += 1) {
                        const disk = Reference.disk(params, owner_x, owner_y) orelse continue;
                        const support = disk.radius + params.edge_softness;
                        for (0..2) |axis| {
                            for ([_]F{ -support, 0, support }) |delta| {
                                const edge = (disk.xy[axis] + delta) / params.cells_per_uv[axis];
                                for ([_]F{ edge, std.math.nextAfter(F, edge, -std.math.inf(F)), std.math.nextAfter(F, edge, std.math.inf(F)) }) |coordinate| {
                                    const u = if (axis == 0) coordinate else disk.xy[0] / params.cells_per_uv[0];
                                    const v = if (axis == 1) coordinate else disk.xy[1] / params.cells_per_uv[1];
                                    try std.testing.expectEqual(Reference.sample(params, u, v), sampleScal(u, v, params, &owned));
                                }
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
                            try std.testing.expectEqual(Reference.sample(params, u, v), sampleScal(u, v, params, &owned));
                        }
                    }
                }
            }
        }
    }
}

test "cell binned allocation failures clean up every layout" {
    inline for (.{
        speckleconfig.Config{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .hard } } },
        speckleconfig.Config{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
        speckleconfig.Config{ .cell_binned = .{ .gaussian = .nine } },
    }) |config| {
        if (comptime !buildconfig.enable_all_evaluators and config.pattern() == .disk and config.edges() == .hard) continue;
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                try std.testing.checkAllAllocationFailures(std.testing.allocator, struct {
                    fn run(allocator: std.mem.Allocator, radius_jitter: F, owner_occupancy: F) !void {
                        var resources = try Resources.init(allocator, .{
                            .evaluator = if (buildconfig.enable_all_evaluators) .cell_binned else null,
                            .pattern = config.pattern().?,
                            .edge_softness = if (config.edges() == .soft) 0.04 else 0,
                            .radius_jitter = radius_jitter,
                            .occupancy = owner_occupancy,
                            .cells_per_uv = .{ 3.25, 2.5 },
                        });
                        defer resources.deinit(allocator);
                        const expected: std.meta.Tag(CellBinnedRecords) = if (radius_jitter == 0) .strided else if (config.pattern() == .gaussian) .gaussian else .disks;
                        try std.testing.expectEqual(expected, std.meta.activeTag(resources.data.cell_binned.records));
                        resources.deinit(allocator);
                        try std.testing.expectEqualDeep(Resources{}, resources);
                        resources.deinit(allocator);
                    }
                }.run, .{ jitter, occupancy });
            }
        }
    }
}

test "cell binned Gaussian nearest reductions preserve underflowed sigma squared" {
    @setEvalBranchQuota(100_000);
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    inline for (generation_configs) |config| {
        if (comptime config.pattern() != .gaussian) continue;
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const Impl = Implementation(config);
        for ([_]F{ @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
            const params: Speckle2DParams = .{ .evaluator = if (buildconfig.enable_all_evaluators) std.meta.activeTag(config) else null, .pattern = .gaussian, .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null, .cells_per_uv = .{ 1, 1 }, .occupancy = 1, .radius_mean = radius, .foreground = 0.91, .background = 0.23 };
            var resources = try Resources.init(std.testing.allocator, params);
            defer resources.deinit(std.testing.allocator);
            const disk = Impl.speckleDiskForCell(0, 0, params).?;
            const expected = Impl.evalSpeckle2DImpl(disk.center[0], disk.center[1], params);
            try std.testing.expect(std.math.isFinite(expected));
            try std.testing.expectEqual(expected, sampleScal(disk.center[0], disk.center[1], params, &resources));
            const lanes: [S]F = sampleSIMD(@splat(disk.center[0]), @splat(disk.center[1]), @splat(true), params, &resources);
            for (lanes) |value| try std.testing.expectEqual(expected, value);
        }
    }
}

test "cell binned wide procedural grids retain rounded face and endpoint membership" {
    @setEvalBranchQuota(100_000);
    inline for (generation_configs) |config| {
        switch (comptime std.meta.activeTag(config)) {
            .cell_binned => {},
            else => continue,
        }
        const Impl = Implementation(config);
        const soft = comptime config.edges() == .soft;
        const params: Speckle2DParams = .{
            .evaluator = if (buildconfig.enable_all_evaluators) std.meta.activeTag(config) else null,
            .pattern = config.pattern().?,
            .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
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
                    const expected = Impl.evalSpeckle2DImpl(u, v, params);
                    try std.testing.expectEqual(expected, sampleScal(u, v, params, &resources));
                    const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(false), params, &resources);
                    for (lanes) |value| try std.testing.expectEqual(expected, value);
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

test "cell binned canonical layouts and rounded coefficients" {
    var checked: usize = 0;
    inline for (generation_configs) |config| {
        if (comptime std.meta.activeTag(config) != .cell_binned) continue;
        checked += 1;
        for ([_]F{ 0, 0.08 }) |jitter| {
            const p: Speckle2DParams = .{ .evaluator = if (buildconfig.enable_all_evaluators) .cell_binned else null, .pattern = config.pattern().?, .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null, .edge_softness = if (config.edges() == .soft) 0.04 else 0, .cells_per_uv = .{ 3.25, 2.75 }, .radius_mean = 0.3, .radius_jitter = jitter, .occupancy = 0.7 };
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
                for (strided.counts) |count| try std.testing.expect(count <= 9);
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
    try std.testing.expectEqual(@as(usize, if (buildconfig.enable_all_evaluators) 9 else 2), checked);
}

test "cell binned fixed stride scans only populated Gaussian records" {
    // Well-separated populated scores complement adjacent-score/plateau fixtures.
    const points = [_][2]F{ .{ 0.125, 0 }, .{ 0.25, 0 } };
    for (0..3) |count| try expectGaussianStrided(0.75, points[0..count], .{ 0.91, -0.0 });
}

test "binned defaults preserve independent analytic samples without overrides" {
    for ([_]struct { pattern: speckleconfig.Pattern, softness: F, radius: F = 0.3 }{
        .{ .pattern = .disk, .softness = 0 },
        .{ .pattern = .disk, .softness = 0, .radius = 0.425 },
        .{ .pattern = .disk, .softness = 0.04 },
        .{ .pattern = .gaussian, .softness = 0 },
    }) |case| {
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                const params: Speckle2DParams = .{
                    .pattern = case.pattern,
                    .edge_softness = case.softness,
                    .radius_mean = case.radius,
                    .radius_jitter = jitter,
                    .occupancy = occupancy,
                    .cells_per_uv = .{ 3.25, 2.75 },
                    .foreground = 0.91,
                    .background = -0.0,
                };
                const resolved = try params.resolve();
                const classified = case.pattern == .disk and case.softness == 0;
                const evaluator: speckleconfig.Evaluator = if (classified) .classified_binned else .cell_binned;
                try std.testing.expectEqual(evaluator, std.meta.activeTag(resolved));
                var resources = try Resources.init(std.testing.allocator, params);
                defer resources.deinit(std.testing.allocator);
                const backing: std.meta.Tag(Backing) = if (classified) .classified_binned else .cell_binned;
                try std.testing.expectEqual(backing, std.meta.activeTag(resources.data));
                for ([_]F{ -1, 0, 1.0 / 3.25, 0.5, 1, 2 }) |u| {
                    for ([_]F{ -1, 0, 1.0 / 2.75, 0.5, 1, 2 }) |v| {
                        const expected = CellBinnedIndependentReference.sample(params, u, v);
                        try std.testing.expectEqual(expected, sampleScal(u, v, params, &resources));
                        inline for (.{ false, true }) |active| {
                            const lanes: [S]F = sampleSIMD(@splat(u), @splat(v), @splat(active), params, &resources);
                            const masked_expected = if (classified and !active) params.background else expected;
                            for (lanes) |actual| try std.testing.expectEqual(masked_expected, actual);
                        }
                    }
                }
            }
        }
    }
}

test "cell binned paired vectors preserve count tails plateaus colors and borrowed params" {
    const smallest = std.math.floatMin(F) * std.math.floatEps(F);
    const base: F = 0.015625;
    const ulp = std.math.nextAfter(F, base, std.math.inf(F)) - base;
    for ([_]F{ 0.75, @sqrt(smallest), @sqrt(smallest) * 1.5 }) |radius| {
        if (radius != 0.75) {
            const sigma = radius / 3;
            try std.testing.expect(radius * radius > 0);
            try std.testing.expectEqual(@as(F, 0), sigma * sigma);
        }
        for (0..10) |count| {
            for (0..2) |order| {
                var points: [9][2]F = undefined;
                for (points[0..count], 0..) |*point, ii| {
                    const k = if (order == 0) ii else count - ii - 1;
                    point.* = .{
                        if (radius == 0.75) 0.125 else if (k % 2 == 0) 0 else @sqrt(smallest),
                        if (radius == 0.75) @sqrt(@as(F, @floatFromInt(k)) * ulp) else 0,
                    };
                }
                for ([_][2]F{ .{ 0.91, -0.0 }, .{ -0.0, 0.83 }, .{ -0.0, -0.0 }, .{ 0.0, -0.0 }, .{ 0.17, 0.83 } }) |colors| {
                    expectGaussianStrided(radius, points[0..count], colors) catch |err| {
                        std.debug.print("Gaussian strided radius={d} count={d} order={d} colors={any}\n", .{ radius, count, order, colors });
                        return err;
                    };
                }
            }
        }
    }
}

test "speckle image fill matches scalar pixel-center samples for every generation config" {
    inline for (generation_configs) |config| {
        var params: Speckle2DParams = .{
            .pattern = config.pattern() orelse .disk,
            .cells_per_uv = .{ 2.17, 1.31 },
            .radius_mean = 0.35,
            .edge_softness = if (config.edges() == .soft) 0.035 else 0,
            .foreground = 0.83,
            .background = 0.17,
        };
        if (comptime buildconfig.enable_all_evaluators) {
            params.evaluator = comptime std.meta.activeTag(config);
            params.neighbor_count = config.neighborhood();
        }
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        // Widths cover scalar-only rows, whole SIMD lane groups, and scalar tails.
        for ([_]usize{ 1, S - 1, S, S + 1, 2 * S + 3 }) |cols| {
            var pixels: [3 * (2 * S + 3)]F = undefined;
            fillImage(matslice.MatSlice(F).init(pixels[0 .. 3 * cols], 3, cols), params, &resources);
            for (0..3) |rr| {
                for (0..cols) |cc| {
                    const u = (@as(F, @floatFromInt(cc)) + 0.5) / @as(F, @floatFromInt(cols));
                    const v = (@as(F, @floatFromInt(rr)) + 0.5) / 3;
                    const want = sampleScal(u, v, params, &resources);
                    try std.testing.expectEqual(want, pixels[rr * cols + cc]);
                }
            }
        }
    }
}

test "speckle image fill gives independent empty and equal color intensities" {
    const cases = [_]struct { params: Speckle2DParams, expected: F }{
        .{ .params = .{ .occupancy = 0, .background = 0.83 }, .expected = 0.83 },
        .{ .params = .{ .occupancy = 0, .edge_softness = 0.035, .background = 0.17 }, .expected = 0.17 },
        .{ .params = .{ .pattern = .gaussian, .occupancy = 0, .background = 0.37 }, .expected = 0.37 },
        .{ .params = .{ .foreground = 0.17, .background = 0.17 }, .expected = 0.17 },
        .{ .params = .{ .pattern = .gaussian, .foreground = 0.83, .background = 0.83 }, .expected = 0.83 },
        .{ .params = .{ .pattern = .perlin, .foreground = 0.37, .background = 0.37 }, .expected = 0.37 },
    };
    for (cases) |case| {
        var params = case.params;
        params.cells_per_uv = .{ 3.25, 2.5 };
        var resources = try Resources.init(std.testing.allocator, params);
        defer resources.deinit(std.testing.allocator);
        var pixels: [15]F = undefined;
        fillImage(matslice.MatSlice(F).init(&pixels, 3, 5), params, &resources);
        for (pixels) |value| try std.testing.expectEqual(case.expected, value);
    }
}

fn expectSpeckleSlicesEqual(comptime T: type, a: []const T, b: []const T) !void {
    if (T == F) {
        try std.testing.expectEqual(a.len, b.len);
        for (a, b) |expected, actual| try std.testing.expect(expected == actual);
    } else {
        try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));
    }
}

fn expectIndependentClassifiedField(resources: *const Resources, p: Speckle2DParams) !void {
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
            const expected = CellBinnedIndependentReference.sample(p, @max(0.0, @min(1.0, us[lane])), @max(0.0, @min(1.0, vs[lane])));
            try std.testing.expectEqual(expected, sampleScal(us[lane], vs[lane], borrowed, resources));
        }
        const actual: [S]F = sampleSIMD(us, vs, active, borrowed, resources);
        for (0..S) |lane| {
            const expected = if (!active[lane]) p.background else CellBinnedIndependentReference.sample(p, @max(0.0, @min(1.0, us[lane])), @max(0.0, @min(1.0, vs[lane])));
            try std.testing.expectEqual(expected, actual[lane]);
        }
    }
}

fn independentBinHit(data: ClassifiedBinnedSpeckle2D, cell: usize, px: F, py: F) bool {
    const p = data;
    const first = if (p.params.radius_jitter == 0) cell * 9 else data.offsets[cell];
    for (0..data.counts[cell]) |j| {
        const index = first + j;
        const dx = px - p.coordinates[index];
        const dy = py - p.coordinates[p.slots + index];
        const rr = if (p.params.radius_jitter == 0) (p.params.radius_mean * p.params.radius_mean) else p.coordinates[2 * p.slots + index];
        if (dx * dx + dy * dy < rr) return true;
    }
    return false;
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

test "classified bins clipped owner certificates singleton classes and exact fields" {
    var singleton_cells: usize = 0;
    var regular_cells: usize = 0;
    for (0..28) |variation| {
        const p: Speckle2DParams = .{
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
        var actual = try Resources.init(std.testing.allocator, p);
        defer actual.deinit(std.testing.allocator);
        const b = actual.data.classified_binned;
        try std.testing.expectEqual(@as(?speckleconfig.Evaluator, null), b.params.evaluator);
        try std.testing.expectEqual(@as(?speckleconfig.Neighborhood, null), b.params.neighbor_count);
        try std.testing.expectEqual(speckleconfig.Config.classified_binned, kernel_configs[actual.kernel_index.?]);
        try std.testing.expectEqualDeep(p, b.params);
        for (b.headers, b.counts, 0..) |word, count, cell| {
            try std.testing.expect(count <= 9);
            const start = if (b.params.radius_jitter == 0) cell * 9 else b.offsets[cell];
            try std.testing.expect(start + count <= b.slots);
            if (count == 0) try std.testing.expectEqual(@as(u64, 0), word);
            try std.testing.expectEqual(@as(u32, 0), @as(u32, @truncate(word)) & @as(u32, @truncate(word >> 32)));
            for (0..32) |bit| {
                const x = (cell % b.cell_dims[0]) * 8 + bit % 8;
                const y = (cell / b.cell_dims[0]) * 4 + bit / 8;
                const state = rectangularHeaderClass(word, @intCast(bit));
                if (x >= b.dims[0] or y >= b.dims[1]) {
                    try std.testing.expectEqual(@as(u2, 0), state);
                    continue;
                }
                if (count == 1) singleton_cells += 1;
                regular_cells += 1;
                try std.testing.expectEqual(independentClippedOwnerClass(p, x, y), state);
            }
        }
        if (variation < 11 or variation >= 14) try expectIndependentClassifiedField(&actual, p);
        // Large asymmetric domains also check selected packets against independent hashes.
        for (0..32) |batch| {
            var us: [S]F = undefined;
            var vs: [S]F = undefined;
            for (0..S) |lane| {
                us[lane] = if (batch == 0) 1 else @as(F, @floatFromInt((batch * 73 + lane * 37) % 257)) / 256;
                vs[lane] = if (batch == 1) 1 else @as(F, @floatFromInt((batch * 17 + lane * 53) % 259)) / 256;
            }
            var expected: [S]F = undefined;
            for (0..S) |lane| expected[lane] = CellBinnedIndependentReference.sample(p, @max(0.0, @min(1.0, us[lane])), @max(0.0, @min(1.0, vs[lane])));
            const result: [S]F = sampleSIMD(us, vs, @splat(true), p, &actual);
            try expectSpeckleSlicesEqual(F, &expected, &result);
        }
    }
    try std.testing.expect(singleton_cells != 0 and regular_cells != 0);
}

test "classified bins fallback counts0 through9 all hit positions groups masks and final CSR tails" {
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
                    const p: Speckle2DParams = .{ .cells_per_uv = .{ @as(F, @floatFromInt(cells_num)) - 0.01, 0.99 }, .radius_mean = 0.25, .radius_jitter = if (fixed) 0 else 0.08, .foreground = 0.91, .background = -0.0 };
                    @memset(&headers, 0xffff_ffff_0000_0000);
                    const data: ClassifiedBinnedSpeckle2D = .{ .params = p, .dims = .{ cells_num * 8, 4 }, .cell_dims = .{ cells_num, 1 }, .coordinates = coordinates, .slots = slots, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
                    ClassifiedBinned.classifyBins(fixed, &data, &headers);
                    const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .classified_binned = data } };
                    for (0..@as(usize, 1) << @min(S, 8)) |mask| {
                        var active: [S]bool = undefined;
                        for (&active, 0..) |*value, lane| value.* = mask & (@as(usize, 1) << @intCast(lane)) != 0;
                        const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
                        for (0..S) |lane| {
                            const hit = independentBinHit(data, chosen[lane], us[lane] * p.cells_per_uv[0], vs[lane] * p.cells_per_uv[1]);
                            const expected = if (active[lane]) p.background + @as(F, if (hit) 1 else 0) * (p.foreground - p.background) else p.background;
                            try std.testing.expectEqual(expected, actual[lane]);
                        }
                        packets += 1;
                    }
                }
            }
        }
    }
    try std.testing.expectEqual(@as(usize, 2 * 55 * 3 * (@as(usize, 1) << @min(S, 8))), packets);
}

test "classified bins mixed certified clamped lanes and nonempty zero radii retain numerical background values" {
    const p: Speckle2DParams = .{ .cells_per_uv = .{ 3.17, 2.31 }, .seed = 43498, .radius_mean = 0.4, .radius_jitter = 0.4, .occupancy = 1, .foreground = 0.91, .background = -0.0 };
    var resources = try Resources.init(std.testing.allocator, p);
    defer resources.deinit(std.testing.allocator);
    const data = resources.data.classified_binned;
    const slots = data.slots;
    var zeros: usize = 0;
    for (data.coordinates[2 * slots ..], 0..) |r2, index| {
        if (r2 != 0) continue;
        zeros += 1;
        const us: [S]F = @splat(data.coordinates[index] / p.cells_per_uv[0]);
        const vs: [S]F = @splat(data.coordinates[slots + index] / p.cells_per_uv[1]);
        const actual: [S]F = sampleSIMD(us, vs, @splat(true), p, &resources);
        var expected: [S]F = undefined;
        for (0..S) |lane| expected[lane] = sampleScal(us[lane], vs[lane], p, &resources);
        try expectSpeckleSlicesEqual(F, &expected, &actual);
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
            if (!active[lane]) continue;
            const expected = CellBinnedIndependentReference.sample(p, @max(0.0, @min(1.0, us[lane])), @max(0.0, @min(1.0, vs[lane])));
            try std.testing.expectEqual(expected, sampleScal(us[lane], vs[lane], p, &resources));
        }
        const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
        var expected: [S]F = undefined;
        for (0..S) |lane| expected[lane] = if (active[lane]) sampleScal(us[lane], vs[lane], p, &resources) else p.background;
        try expectSpeckleSlicesEqual(F, &expected, &actual);
    }
}

test "classified bins builders initialize poisoned storage own true params and reset" {
    for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 0.7, 1 }) |occupancy| {
        const p: Speckle2DParams = .{ .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy };
        var expected = try Resources.init(std.testing.allocator, p);
        defer expected.deinit(std.testing.allocator);
        var buffer: [32769]u8 = @splat(0xa5);
        var fba = std.heap.FixedBufferAllocator.init(buffer[1..]);
        var actual = try Resources.init(fba.allocator(), p);
        defer actual.deinit(fba.allocator());
        const a = expected.data.classified_binned;
        const b = actual.data.classified_binned;
        try expectSpeckleSlicesEqual(u64, a.headers, b.headers);
        for (b.counts, 0..) |count, cell| {
            const start = if (jitter == 0) cell * 9 else b.offsets[cell];
            const planes: usize = if (jitter == 0) 2 else 3;
            for (0..planes) |plane| {
                const first = plane * b.slots + start;
                try expectSpeckleSlicesEqual(F, a.coordinates[first..][0..count], b.coordinates[first..][0..count]);
            }
        }
        try expectSpeckleSlicesEqual(u8, a.counts, b.counts);
        try expectSpeckleSlicesEqual(u32, a.offsets, b.offsets);
        try std.testing.expectEqual(@as(usize, 0), @intFromPtr(b.headers.ptr) % @alignOf(u64));
        try std.testing.expectEqual(@as(?speckleconfig.Evaluator, null), b.params.evaluator);
        actual.deinit(fba.allocator());
        try std.testing.expectEqualDeep(Resources{}, actual);
    };
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 3.17, 2.31 } }));
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 1500, 3000 }, .occupancy = 0, .radius_jitter = 0.08 }));
}

test "classified bins explicit mixed FG BG AMB packets preserve inactive clamped and zero-count groups" {
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
        for (0..4) |phase| for ([_]usize{ 1, 2, S }) |groups| for ([_]bool{ false, true }) |invalid| {
            var us: [S]F = undefined;
            const vs: [S]F = @splat(0.5 / 0.99);
            for (&us, 0..) |*u, lane| {
                const local = (@as(F, @floatFromInt((lane + phase) % 4)) + 0.5) / 8;
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
                const p: Speckle2DParams = .{ .cells_per_uv = .{ @as(F, @floatFromInt(S)) - 0.01, 0.99 }, .radius_mean = 0.25, .radius_jitter = if (fixed) 0 else 0.08, .foreground = 0.91, .background = -0.0 };
                const data: ClassifiedBinnedSpeckle2D = .{ .params = p, .dims = .{ S * 8, 4 }, .cell_dims = .{ S, 1 }, .coordinates = coordinates, .slots = slots, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
                const resources: Resources = .{ .kernel_index = kernelIndex(try p.resolve()), .data = .{ .classified_binned = data } };
                const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
                for (0..S) |lane| {
                    var expected = p.background;
                    if (active[lane]) {
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
                    try std.testing.expectEqual(expected, actual[lane]);
                }
            }
        };
    }
    try std.testing.expectEqual(@as(u8, 7), seen);
}

test "classified bins check representability before allocation and clean up every allocation failure" {
    // The header fits, but fixed-slot coordinate bytes do not. Reject before allocation.
    if (F == f64) try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 35_184_372_088_831, 8192 } }));
    if (F == f64) try std.testing.expectError(error.SpeckleClassificationTooLarge, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 35_184_372_088_831, 35_184_372_088_831 } }));
    const Probe = struct {
        fn run(allocator: std.mem.Allocator, jitter: F, occupancy: F) !void {
            var resources = try Resources.init(allocator, .{ .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy });
            defer resources.deinit(allocator);
            try std.testing.expect(resources.data == .classified_binned);
        }
    };
    for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 1 }) |occupancy| try std.testing.checkAllAllocationFailures(std.testing.allocator, Probe.run, .{ jitter, occupancy });
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 1500, 3000 }, .occupancy = 0 }));
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 60_000, 70 }, .occupancy = 0 }));
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 4000, 3000 }, .occupancy = 0, .radius_jitter = 0.08 }));
    try std.testing.expectError(error.OutOfMemory, Resources.init(std.testing.failing_allocator, .{ .cells_per_uv = .{ 2000, 2000 }, .occupancy = 0 }));
}

fn independentClippedRecordClass(data: ClassifiedBinnedSpeckle2D, x: usize, y: usize) u2 {
    const p = data.params;
    const lo: [2]F = .{ @as(F, @floatFromInt(x)) / 8, @as(F, @floatFromInt(y)) / 4 };
    const hi: [2]F = .{ @min(std.math.nextAfter(F, @as(F, @floatFromInt(x + 1)) / 8, -std.math.inf(F)), p.cells_per_uv[0]), @min(std.math.nextAfter(F, @as(F, @floatFromInt(y + 1)) / 4, -std.math.inf(F)), p.cells_per_uv[1]) };
    const cell = (y / 4) * data.cell_dims[0] + x / 8;
    const first = if (data.params.radius_jitter == 0) cell * 9 else data.offsets[cell];
    var intersects = false;
    for (0..data.counts[cell]) |j| {
        const index = first + j;
        const center: [2]F = .{ data.coordinates[index], data.coordinates[data.slots + index] };
        const rr = if (data.params.radius_jitter == 0) (data.params.radius_mean * data.params.radius_mean) else data.coordinates[2 * data.slots + index];
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

test "classified bins vector classifier all counts0 through9 partial singleton zero squared radius and final CSR" {
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
            const p: Speckle2DParams = .{ .cells_per_uv = .{ 1.17, 0.31 }, .radius_mean = if (zero_radius) std.math.floatMin(F) else 0.25, .radius_jitter = if (fixed) 0 else if (zero_radius) std.math.floatMin(F) else 0.08 };
            for (0..2) |cell| for (0..amount) |j| {
                const index = (if (fixed) cell * 9 else offsets[cell]) + j;
                coordinates[index] = @as(F, @floatFromInt(cell)) + @as(F, @floatFromInt(j + 1)) / 32;
                coordinates[slots + index] = 0.125;
                if (!fixed) coordinates[2 * slots + index] = if (zero_radius) 0 else 0.0625;
            };
            var headers: [2]u64 = @splat(std.math.maxInt(u64));
            const data: ClassifiedBinnedSpeckle2D = .{ .params = p, .dims = .{ 10, 2 }, .cell_dims = .{ 2, 1 }, .coordinates = coordinates, .slots = slots, .headers = &headers, .counts = &counts, .offsets = if (fixed) &.{} else &offsets };
            // Real constructors zero headers before count0 is skipped.
            @memset(&headers, 0);
            ClassifiedBinned.classifyBins(fixed, &data, &headers);
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

test "classified bins unprepared raw inactive dispatch preserve separate contracts" {
    try std.testing.expectEqual(speckleconfig.Config.classified_binned, speckleconfig.canonicalizeSampleConfig(.classified_binned));
    for ([_]F{ 0, 0.08 }) |jitter| for ([_]F{ 0, 0.7, 1 }) |occupancy| {
        const p: Speckle2DParams = .{ .cells_per_uv = .{ 3.17, 2.31 }, .radius_mean = 0.6, .radius_jitter = jitter, .occupancy = occupancy, .foreground = 0.91, .background = -0.0 };
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        try std.testing.expectEqual(kernelIndex(.classified_binned), resources.kernel_index.?);
        try std.testing.expectEqual(@as(?speckleconfig.Evaluator, null), resources.data.classified_binned.params.evaluator);
        const empty: Resources = .{};
        for (0..48) |batch| {
            var us: [S]F = undefined;
            var vs: [S]F = undefined;
            var active: [S]bool = undefined;
            for (0..S) |lane| {
                us[lane] = if (batch == 0) std.math.nan(F) else if (batch == 1) std.math.inf(F) else @as(F, @floatFromInt((batch * 73 + lane * 37) % 257)) / 256;
                vs[lane] = if (batch == 2) -std.math.inf(F) else @as(F, @floatFromInt((batch * 17 + lane * 53) % 259)) / 256;
                active[lane] = (batch + lane) % 3 != 0;
                const expected = CellBinnedIndependentReference.sample(p, @max(0.0, @min(1.0, us[lane])), @max(0.0, @min(1.0, vs[lane])));
                try std.testing.expectEqual(expected, sampleScal(us[lane], vs[lane], p, &empty));
            }
            const raw: [S]F = sampleSIMD(us, vs, active, p, &empty);
            for (0..S) |lane| {
                // The raw adapter samples every lane; prepared kernels background inactive lanes.
                const expected = sampleScal(us[lane], vs[lane], p, &empty);
                try std.testing.expectEqual(expected, raw[lane]);
            }
            const prepared: [S]F = sampleSIMD(us, vs, active, p, &resources);
            const selected: [S]F = Kernel(kernelIndex(.classified_binned)).sampleSIMD(us, vs, active, p, &resources);
            try expectSpeckleSlicesEqual(F, &selected, &prepared);
        }
    };
}

test "classified bins resource census exhaustive clipped owner reference all logical cells" {
    const Case = struct { cells: [2]F, radius: F, jitter: F, occupancy: F };
    const cases = [_]Case{
        .{ .cells = .{ 16, 12 }, .radius = 0.425, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 16.17, 12.31 }, .radius = 0.425, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 16, 12 }, .radius = 0.4, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 16, 12 }, .radius = 0.4, .jitter = 0.08, .occupancy = 1 },
        .{ .cells = .{ 16, 12 }, .radius = 0.6, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 16, 12 }, .radius = 0.6, .jitter = 0.08, .occupancy = 1 },
        .{ .cells = .{ 16, 12 }, .radius = 0.6, .jitter = 0, .occupancy = 0.7 },
        .{ .cells = .{ 16, 12 }, .radius = 0.6, .jitter = 0.08, .occupancy = 0.7 },
        .{ .cells = .{ 13, 10 }, .radius = 0.4, .jitter = 0, .occupancy = 1 },
        .{ .cells = .{ 13, 10 }, .radius = 0.6, .jitter = 0, .occupancy = 1 },
    };
    for (cases) |c| {
        const p: Speckle2DParams = .{ .cells_per_uv = c.cells, .radius_mean = c.radius, .radius_jitter = c.jitter, .occupancy = c.occupancy, .seed = 0xa511e9b3 };
        var resources = try Resources.init(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        const data = resources.data.classified_binned;
        var histogram: [10]usize = @splat(0);
        var classes: [3]usize = @splat(0);
        var live: usize = 0;
        var singleton_logical: usize = 0;
        for (data.counts, data.headers, 0..) |count, word, cell| {
            try std.testing.expect(count <= 9);
            histogram[count] += 1;
            live += count;
            try std.testing.expectEqual(@as(u32, 0), @as(u32, @truncate(word)) & @as(u32, @truncate(word >> 32)));
            if (count == 0) try std.testing.expectEqual(@as(u64, 0), word);
            for (0..32) |bit| {
                const x = (cell % data.cell_dims[0]) * 8 + bit % 8;
                const y = (cell / data.cell_dims[0]) * 4 + bit / 8;
                const state = rectangularHeaderClass(word, @intCast(bit));
                if (x >= data.dims[0] or y >= data.dims[1]) {
                    try std.testing.expectEqual(@as(u2, 0), state);
                    continue;
                }
                try std.testing.expectEqual(independentClippedOwnerClass(p, x, y), state);
                classes[state] += 1;
                if (count == 1) singleton_logical += 1;
            }
        }
        const logical = data.dims[0] * data.dims[1];
        try std.testing.expectEqual(logical, classes[0] + classes[1] + classes[2]);
        try std.testing.expectEqual(data.headers.len, @reduce(.Add, @as(@Vector(10, usize), histogram)));
        try std.testing.expectEqual(if (data.params.radius_jitter == 0) data.headers.len * 9 else live, data.slots);
        try std.testing.expect(singleton_logical != 0);
        try expectIndependentClassifiedField(&resources, p);
    }
}

test "classified bins active owners with no bin records preserve arithmetic backgrounds including signed zero" {
    for ([_]F{ std.math.nextAfter(F, 0, 1), std.math.floatMin(F) }) |radius| {
        for ([_]bool{ false, true }) |variable| {
            const p: Speckle2DParams = .{ .cells_per_uv = .{ 0.01, 0.01 }, .radius_mean = radius, .radius_jitter = if (variable) radius else 0, .occupancy = 1, .foreground = 0.91, .background = -0.0, .seed = 43498 };
            var resources = try Resources.init(std.testing.allocator, p);
            defer resources.deinit(std.testing.allocator);
            const data = resources.data.classified_binned;
            for (data.counts) |count| try std.testing.expectEqual(@as(u8, 0), count);
            for (data.headers) |word| try std.testing.expectEqual(@as(u64, 0), word);
            const arithmetic = p.background + @as(F, 0) * (p.foreground - p.background);
            try std.testing.expectEqual(arithmetic, sampleScal(0.5, 0.5, p, &resources));
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
                const expected = arithmetic;
                try std.testing.expectEqual(expected, sampleScal(us[lane], vs[lane], p, &resources));
            }
            const actual: [S]F = sampleSIMD(us, vs, active, p, &resources);
            for (actual, 0..) |value, lane| {
                const expected = if (active[lane]) arithmetic else p.background;
                try std.testing.expectEqual(expected, value);
            }
        }
    }
}

test "Gaussian packets match independent fields at centers overlaps and underflowed sigma squared" {
    @setEvalBranchQuota(100_000);
    inline for (generation_configs) |config| {
        const tag = comptime std.meta.activeTag(config);
        if (comptime (tag != .list_naive and tag != .cell_binned) or config.pattern() != .gaussian) continue;
        for (0..6) |variation| {
            const tiny = @sqrt(std.math.floatMin(F) * std.math.floatEps(F)) * 1.5;
            const radius: F = if (variation == 2 or variation == 3) tiny else if (config.neighborhood() == .one) 0.4 else 0.6;
            const p: Speckle2DParams = .{
                .evaluator = if (buildconfig.enable_all_evaluators) tag else null,
                .pattern = .gaussian,
                .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
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
                    const expected = CellBinnedIndependentReference.sample(p, u, v);
                    try std.testing.expectEqual(expected, value);
                }
            }
        }
    }
}

test "packet adapters preserve inactive and clamped lane contracts numerically" {
    @setEvalBranchQuota(100_000);
    inline for (kernel_configs, 0..) |config, index| {
        const tag = comptime std.meta.activeTag(config);
        if (comptime tag != .cell_hash and tag != .list_naive and tag != .list_indexed and tag != .cell_binned) continue;
        for ([_]F{ 0, 0.08 }) |jitter| {
            for ([_]F{ 0, 0.7, 1 }) |occupancy| {
                const params: Speckle2DParams = .{
                    .evaluator = if (buildconfig.enable_all_evaluators) tag else null,
                    .pattern = config.pattern().?,
                    .neighbor_count = if (buildconfig.enable_all_evaluators) config.neighborhood() else null,
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
                        const expected = if (config.pattern() != .perlin or enabled) Kernel(index).sampleScal(u, v, params, &resources) else params.background;
                        try std.testing.expectEqual(expected, value);
                    }
                }
            }
        }
    }
}

test "cell binned mixed-count packets never read poisoned unused strided records" {
    inline for (.{
        speckleconfig.Config{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .hard } } },
        speckleconfig.Config{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } },
        speckleconfig.Config{ .cell_binned = .{ .gaussian = .nine } },
    }) |config| {
        if (comptime !buildconfig.enable_all_evaluators and config.pattern() == .disk and config.edges() == .hard) continue;
        const p: Speckle2DParams = .{
            .evaluator = if (buildconfig.enable_all_evaluators) .cell_binned else null,
            .pattern = config.pattern().?,
            .neighbor_count = if (buildconfig.enable_all_evaluators) .nine else null,
            .cells_per_uv = .{ 9.99, 0.99 },
            .radius_mean = 0.3,
            .edge_softness = if (config.edges() == .soft) 0.04 else 0,
            .foreground = 0.17,
            .background = 0.83,
        };
        for ([_]bool{ false, true }) |hit| {
            var coordinates: [180]F = undefined;
            var counts: [10]u8 = undefined;
            for (&counts, 0..) |*count, cell| {
                count.* = @intCast(cell);
                for (0..9) |slot| {
                    // An accidental padding load produces full coverage, not a harmless miss.
                    coordinates[cell * 9 + slot] = @as(F, @floatFromInt(cell)) + 0.5;
                    coordinates[90 + cell * 9 + slot] = 0.5;
                }
                for (0..count.*) |slot| {
                    coordinates[cell * 9 + slot] = @as(F, @floatFromInt(cell)) +
                        (if (hit and slot + 1 == count.*) @as(F, 0.6) else 3.5);
                }
            }
            const resources: Resources = .{
                .kernel_index = kernelIndex(try p.resolve()),
                .data = .{ .cell_binned = .{
                    .params = p,
                    .offsets = &.{},
                    .records = .{ .strided = .{ .coordinates = &coordinates, .counts = &counts } },
                    .dims = .{ 10, 1 },
                } },
            };
            for (0..10) |first| for ([_]bool{ false, true }) |coherent| {
                var us: [S]F = undefined;
                const vs: [S]F = @splat(0.5 / p.cells_per_uv[1]);
                var active: [S]bool = undefined;
                for (0..S) |lane| {
                    const cell = if (coherent) first else (first + lane) % 10;
                    us[lane] = (@as(F, @floatFromInt(cell)) + 0.5) / p.cells_per_uv[0];
                    active[lane] = lane % 2 == 0;
                }
                const values: [S]F = sampleSIMD(us, vs, active, p, &resources);
                for (values, us, vs) |value, u, v| {
                    try std.testing.expectEqual(sampleScal(u, v, p, &resources), value);
                }
            };
        }
    }
}

test "classified bins count guards ignore finite infinite and NaN unused fixed records" {
    const p: Speckle2DParams = .{
        .cells_per_uv = .{ 9.99, 0.99 },
        .radius_mean = 0.3,
        .foreground = 0.17,
        .background = 0.83,
    };
    for ([_]bool{ false, true }) |hit| {
        var coordinates: [180]F = undefined;
        var counts: [10]u8 = undefined;
        var headers: [10]u64 = undefined;
        var reference_headers: [10]u64 = undefined;
        for (0..4) |poison| {
            for (&counts, 0..) |*count, cell| {
                count.* = @intCast(cell);
                for (0..9) |slot| {
                    // Finite padding sits at the probe: an accidental load is a false hit.
                    coordinates[cell * 9 + slot] = switch (poison) {
                        0 => @as(F, @floatFromInt(cell)) + 0.5,
                        1 => std.math.inf(F),
                        2 => -std.math.inf(F),
                        else => std.math.nan(F),
                    };
                    coordinates[90 + cell * 9 + slot] = if (poison == 2) std.math.inf(F) else 0.5;
                }
                for (0..count.*) |slot| {
                    coordinates[cell * 9 + slot] = @as(F, @floatFromInt(cell)) +
                        (if (hit and slot + 1 == count.*) @as(F, 0.6) else 3.5);
                    coordinates[90 + cell * 9 + slot] = 0.5;
                }
            }
            const data: ClassifiedBinnedSpeckle2D = .{
                .params = p,
                .dims = .{ 80, 4 },
                .cell_dims = .{ 10, 1 },
                .coordinates = &coordinates,
                .slots = 90,
                .headers = &headers,
                .counts = &counts,
                .offsets = &.{},
            };
            @memset(&headers, 0);
            ClassifiedBinned.classifyBins(true, &data, &headers);
            if (poison == 0) {
                reference_headers = headers;
            } else {
                try std.testing.expectEqualSlices(u64, &reference_headers, &headers);
            }
            const resources: Resources = .{
                .kernel_index = kernelIndex(.classified_binned),
                .data = .{ .classified_binned = data },
            };
            // Check both real certificates and forced exact fallback, including count-zero bins.
            for ([_]bool{ false, true }) |force_fallback| {
                if (force_fallback) @memset(&headers, 0xffff_ffff_0000_0000);
                for (0..10) |first| for ([_]bool{ false, true }) |coherent| {
                    var us: [S]F = undefined;
                    const vs: [S]F = @splat(0.5 / p.cells_per_uv[1]);
                    for (&us, 0..) |*u, lane| {
                        const cell = if (coherent) first else (first + lane) % 10;
                        u.* = (@as(F, @floatFromInt(cell)) + 0.5) / p.cells_per_uv[0];
                        const expected = p.background + @as(F, if (hit and cell != 0) 1 else 0) * (p.foreground - p.background);
                        try std.testing.expectEqual(expected, sampleScal(u.*, vs[lane], p, &resources));
                    }
                    for (0..@as(usize, 1) << @min(S, 8)) |mask| {
                        var active: [S]bool = undefined;
                        for (&active, 0..) |*enabled, lane| enabled.* = mask & (@as(usize, 1) << @intCast(lane)) != 0;
                        const values: [S]F = sampleSIMD(us, vs, active, p, &resources);
                        for (values, active, 0..) |value, enabled, lane| {
                            const cell = if (coherent) first else (first + lane) % 10;
                            const expected = if (enabled) p.background + @as(F, if (hit and cell != 0) 1 else 0) * (p.foreground - p.background) else p.background;
                            try std.testing.expectEqual(expected, value);
                        }
                    }
                };
            }
        }
    }
}
