// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");

const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSI = buildconfig.VecSI;
const VecSF = buildconfig.VecSF;
const speckle_neighbor_count = buildconfig.speckle_neighbor_count;
const speckle_shape = buildconfig.speckle_shape;
const speckle_mask_samples_per_cell: F =
    @floatFromInt(buildconfig.speckle_mask_samples_per_cell);
const max_speckle_cells = 10_000_000;
const max_speckle_mask_bytes = 256 * 1024 * 1024;
const max_speckle_classification_bytes = 256 * 1024 * 1024;
const max_direct_fixed_speckle_bytes = 256 * 1024 * 1024;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const Speckle2DParams = struct {
    seed: u32 = 0xa511e9b3,
    cells_per_uv: [2]F = .{ 192.0, 160.0 },
    uv_offset: [2]F = .{ 0.0, 0.0 },
    occupancy: F = 0.9,
    radius_mean: F = 0.45,
    radius_jitter: F = 0.0,
    /// Disk boundary half-width in cell units; requires a compatible evaluator.
    /// Zero selects hard boundaries; positive values select smooth boundaries.
    edge_softness: F = 0.0,
    perlin_coverage_threshold: F = 0.0,
    perlin_coverage_transition_width: F = 0.12,
    foreground: F = 0.0,
    background: F = 1.0,

    pub fn validate(self: Speckle2DParams) !void {
        for (self.cells_per_uv) |cell_count| {
            if (!std.math.isFinite(cell_count) or cell_count <= 0.0) {
                return error.InvalidSpeckleCellsPerUV;
            }
        }
        for (self.uv_offset) |offset| {
            if (!std.math.isFinite(offset)) {
                return error.InvalidSpeckleUVOffset;
            }
        }
        if (!std.math.isFinite(self.edge_softness) or self.edge_softness < 0.0) {
            return error.InvalidSpeckleEdgeSoftness;
        }
        if (self.edge_softness != 0.0) {
            if (comptime speckle_shape != .disk) {
                return error.SpeckleEdgeSoftnessRequiresDisk;
            }
            switch (comptime buildconfig.speckle_evaluator) {
                .classified_indexed, .direct_fixed, .mask_1bit => {
                    return error.SpeckleEvaluatorRequiresHardEdges;
                },
                .cell_hash, .list_naive, .list_indexed, .mask_u8 => {},
            }
        }
        if (comptime speckle_shape == .perlin) {
            if (!std.math.isFinite(self.perlin_coverage_threshold)) {
                return error.InvalidSpecklePerlinCoverageThreshold;
            }
            if (!std.math.isFinite(self.perlin_coverage_transition_width) or
                self.perlin_coverage_transition_width < 0.0)
            {
                return error.InvalidSpecklePerlinCoverageTransitionWidth;
            }
        } else {
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
            switch (comptime buildconfig.speckle_evaluator) {
                .direct_fixed => {
                    if (self.radius_jitter != 0.0) {
                        return error.InvalidDirectFixedSpeckleRadiusJitter;
                    }
                    if (self.radius_mean >= 0.5) {
                        return error.InvalidDirectFixedSpeckleRadius;
                    }
                },
                .cell_hash,
                .list_naive,
                .list_indexed,
                .classified_indexed,
                .mask_1bit,
                .mask_u8,
                => {
                    if (self.radius_jitter > self.radius_mean) {
                        return error.InvalidSpeckleRadiusRange;
                    }
                },
            }
            const edge_softness = speckleSoftness(self);
            if (comptime buildconfig.speckle_evaluator != .direct_fixed) {
                if (self.radius_mean + self.radius_jitter + edge_softness > 1.0) {
                    return error.InvalidSpeckleNeighborhoodRadius;
                }
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
        for (0..2) |axis| {
            const coord_min = self.uv_offset[axis] - 1.0;
            const coord_max = self.uv_offset[axis] + self.cells_per_uv[axis] + 1.0;
            if (!std.math.isFinite(coord_max) or
                coord_min < -cell_coord_lim or coord_max > cell_coord_lim)
            {
                return error.SpeckleCellCoordinateOutOfRange;
            }
        }
    }
};

pub const SpeckleDisk2D = struct {
    center: [2]F,
    radius: F,
};

pub const SpeckleList2D = struct {
    pub const no_disk = std.math.maxInt(u32);

    params: Speckle2DParams,
    disks: []const SpeckleDisk2D,
    cell_origin: [2]i64,
    cell_dims: [2]usize,
    disk_by_cell: []const u32,
};

pub const SpeckleClassificationState = enum(u8) {
    background = 0,
    foreground = 1,
    ambiguous = 2,
    reserve3 = 3,
};

pub const ClassifiedIndexedSpeckle2D = struct {
    speckles: SpeckleList2D,
    states: []const u8,
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
    list: ?SpeckleList2D = null,
    classified: ?ClassifiedIndexedSpeckle2D = null,
    direct_fixed: ?DirectFixedSpeckle2D = null,
    mask: ?SpeckleMask2D = null,

    pub fn deinit(self: *Resources, allocator: std.mem.Allocator) void {
        if (self.list) |speckles| {
            allocator.free(speckles.disk_by_cell);
            allocator.free(speckles.disks);
        }
        if (self.classified) |classified| {
            allocator.free(classified.states);
            allocator.free(classified.speckles.disk_by_cell);
            allocator.free(classified.speckles.disks);
        }
        if (self.direct_fixed) |direct| allocator.free(direct.cells);
        if (self.mask) |mask| allocator.free(mask.bits);
        self.* = .{};
    }
};

// --------------------------------------------------------------------------------------
// Resource Preparation & Sampling
// --------------------------------------------------------------------------------------

/// Prepare the configured evaluator once for reuse across frames and samples.
/// Returned allocations belong to outer_alloc; release them through Resources.deinit
/// or their owning static arena. Procedural cell hashing needs no allocation.
pub fn generateResources(
    outer_alloc: std.mem.Allocator,
    params: Speckle2DParams,
) !Resources {
    return switch (comptime buildconfig.speckle_evaluator) {
        .cell_hash => blk: {
            try params.validate();
            break :blk .{};
        },
        .list_naive, .list_indexed => .{
            .list = try generateSpeckleList2D(outer_alloc, params),
        },
        .classified_indexed => .{
            .classified = try generateClassifiedIndexedSpeckle2D(outer_alloc, params),
        },
        .direct_fixed => .{
            .direct_fixed = try generateDirectFixedSpeckle2D(outer_alloc, params),
        },
        .mask_1bit, .mask_u8 => .{
            .mask = try generateSpeckleMask2D(outer_alloc, params),
        },
    };
}

/// Return foreground/background-mapped intensity without renderer output scaling.
/// Prepared resources supply their own parameters; missing resources use params for
/// procedural hash/Perlin evaluation. Sampling never allocates or frees memory.
pub inline fn sampleScal(
    u: F,
    v: F,
    params: Speckle2DParams,
    resources: *const Resources,
) F {
    switch (comptime buildconfig.speckle_evaluator) {
        .cell_hash => {},
        .list_naive, .list_indexed => {
            if (resources.list) |speckles| {
                return if (speckleSoftness(speckles.params) > 0.0)
                    evalSpeckleList2DImpl(true, u, v, speckles)
                else
                    evalSpeckleList2DImpl(false, u, v, speckles);
            }
        },
        .classified_indexed => {
            if (resources.classified) |classified| {
                return evalClassifiedIndexedSpeckle2D(.{ u, v }, classified);
            }
        },
        .direct_fixed => {
            if (resources.direct_fixed) |direct| {
                return evalDirectFixedSpeckle2D(.{ u, v }, direct);
            }
        },
        .mask_1bit, .mask_u8 => {
            if (resources.mask) |mask| return evalSpeckleMask2D(.{ u, v }, mask);
        },
    }
    return if (speckleSoftness(params) > 0.0)
        evalSpeckle2DImpl(true, u, v, params)
    else
        evalSpeckle2DImpl(false, u, v, params);
}

/// Vector sampling with the same raw intensity mapping and resource selection.
/// Classified/direct/mask samplers background inactive lanes; the procedural/list
/// fallback evaluates every finite lane. All SIMD paths background nonfinite lanes.
pub inline fn sampleSIMD(
    u: VecSF,
    v: VecSF,
    active: VecSB,
    params: Speckle2DParams,
    resources: *const Resources,
) VecSF {
    switch (comptime buildconfig.speckle_evaluator) {
        .cell_hash => {},
        .list_naive, .list_indexed => {
            if (resources.list) |speckles| {
                const p = speckles.params;
                const eval = evalSpeckleList2DImpl;
                return if (speckleSoftness(p) > 0.0)
                    evalSpeckleSIMDImpl(true, eval, u, v, speckles, p.background)
                else
                    evalSpeckleSIMDImpl(false, eval, u, v, speckles, p.background);
            }
        },
        .classified_indexed => {
            if (resources.classified) |*classified| {
                return evalClassifiedIndexedSpeckleSIMDImpl(u, v, active, classified);
            }
        },
        .direct_fixed => {
            if (resources.direct_fixed) |*direct| {
                return evalDirectFixedSpeckleSIMDImpl(u, v, active, direct);
            }
        },
        .mask_1bit, .mask_u8 => {
            if (resources.mask) |*mask| {
                return evalSpeckleMaskSIMDImpl(u, v, active, mask);
            }
        },
    }
    const eval = evalSpeckle2DImpl;
    return if (speckleSoftness(params) > 0.0)
        evalSpeckleSIMDImpl(true, eval, u, v, params, params.background)
    else
        evalSpeckleSIMDImpl(false, eval, u, v, params, params.background);
}

// --------------------------------------------------------------------------------------
// Speckle Generation & Scalar Evaluation
// --------------------------------------------------------------------------------------

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

inline fn speckleSoftness(params: Speckle2DParams) F {
    if (comptime speckle_shape != .disk) return 0.0;
    return switch (comptime buildconfig.speckle_evaluator) {
        .classified_indexed, .direct_fixed, .mask_1bit => 0.0,
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => params.edge_softness,
    };
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
    const min = [2]i64{
        @as(i64, @intFromFloat(@floor(params.uv_offset[0]))) - padding,
        @as(i64, @intFromFloat(@floor(params.uv_offset[1]))) - padding,
    };
    const max = [2]i64{
        @as(i64, @intFromFloat(@floor(
            params.uv_offset[0] + params.cells_per_uv[0],
        ))) + padding,
        @as(i64, @intFromFloat(@floor(
            params.uv_offset[1] + params.cells_per_uv[1],
        ))) + padding,
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

fn speckleDiskFromHash(
    comptime soft_edges: bool,
    cell_x: i64,
    cell_y: i64,
    hash: u64,
    params: Speckle2DParams,
) SpeckleDisk2D {
    const radius_variation = 2.0 * randomUnitFromHash(hash, 48) - 1.0;
    const edge_softness = if (soft_edges) params.edge_softness else 0.0;
    var radius = params.radius_mean + params.radius_jitter * radius_variation;
    if (comptime speckle_neighbor_count == 1) {
        radius = @min(radius, 0.5 - edge_softness);
    }
    const center_min = if (comptime speckle_neighbor_count == 1)
        radius + edge_softness
    else
        0.0;
    const center_extent = switch (comptime speckle_neighbor_count) {
        1 => 1.0 - 2.0 * center_min,
        4 => 1.0 - radius - edge_softness,
        9 => 1.0,
        else => unreachable,
    };
    return .{
        .center = .{
            @as(F, @floatFromInt(cell_x)) + center_min +
                randomUnitFromHash(hash, 16) * center_extent,
            @as(F, @floatFromInt(cell_y)) + center_min +
                randomUnitFromHash(hash, 32) * center_extent,
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

pub fn generateSpeckleList2D(
    allocator: std.mem.Allocator,
    params: Speckle2DParams,
) !SpeckleList2D {
    try params.validate();
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
    errdefer allocator.free(disks);
    const disk_by_cell_count = if (comptime buildconfig.speckle_evaluator == .list_naive)
        0
    else
        cell_bounds.count;
    const disk_by_cell = try allocator.alloc(u32, disk_by_cell_count);
    errdefer allocator.free(disk_by_cell);
    if (comptime buildconfig.speckle_evaluator != .list_naive) {
        @memset(disk_by_cell, SpeckleList2D.no_disk);
    }
    var disk_index: usize = 0;
    var cell_index: usize = 0;
    cell_y = cell_bounds.min[1];
    while (cell_y <= cell_bounds.max[1]) : (cell_y += 1) {
        var cell_x = cell_bounds.min[0];
        while (cell_x <= cell_bounds.max[0]) : (cell_x += 1) {
            if (speckleDiskForCell(soft_edges, cell_x, cell_y, params)) |disk| {
                disks[disk_index] = disk;
                if (comptime buildconfig.speckle_evaluator != .list_naive) {
                    disk_by_cell[cell_index] = @intCast(disk_index);
                }
                disk_index += 1;
            }
            cell_index += 1;
        }
    }
    return .{
        .params = params,
        .disks = disks,
        .cell_origin = cell_bounds.min,
        .cell_dims = cell_bounds.dims,
        .disk_by_cell = disk_by_cell,
    };
}

const direct_fixed_center_bits: u64 = 0x0000_ffff_ffff_0000;
const direct_fixed_active_bit: u64 = 1;

inline fn directFixedSpeckleDescriptor(hash: u64) u64 {
    return (hash & direct_fixed_center_bits) | direct_fixed_active_bit;
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

pub fn generateDirectFixedSpeckle2D(
    allocator: std.mem.Allocator,
    params: Speckle2DParams,
) !DirectFixedSpeckle2D {
    try params.validate();

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
                        directFixedSpeckleDescriptor(hash);
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

fn speckleClassificationByteCount(state_count: usize) !usize {
    const rounded_state_count = std.math.add(usize, state_count, 3) catch
        return error.SpeckleClassificationTooLarge;
    return rounded_state_count / 4;
}

fn speckleClassificationDims(params: Speckle2DParams) ![2]usize {
    const dims = speckleSampleIntervalDims(params) orelse
        return error.SpeckleClassificationTooLarge;
    const state_count = std.math.mul(usize, dims[0], dims[1]) catch
        return error.SpeckleClassificationTooLarge;
    const state_byte_count = try speckleClassificationByteCount(state_count);
    if (state_byte_count > max_speckle_classification_bytes) {
        return error.SpeckleClassificationTooLarge;
    }
    return dims;
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
    const margin = 16.0 * std.math.floatEps(F) * scale;
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

fn classifySpeckleMicrocell(
    speckles: SpeckleList2D,
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
    var state: SpeckleClassificationState = .background;
    var cell_y = min_cell[1];
    while (cell_y <= max_cell[1]) : (cell_y += 1) {
        var cell_x = min_cell[0];
        while (cell_x <= max_cell[0]) : (cell_x += 1) {
            const disk = speckleListDiskAt(speckles, cell_x, cell_y) orelse continue;
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
    speckles: SpeckleList2D,
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

inline fn speckleClassificationBoundary(
    index: usize,
    uv_to_cell: F,
    cells_per_uv: F,
    uv_offset: F,
) F {
    const uv = @as(F, @floatFromInt(index)) / uv_to_cell;
    return uv * cells_per_uv + uv_offset;
}

const SpeckleClassificationAxis = struct {
    dim: usize,
    uv_to_cell: F,
    cells_per_uv: F,
    uv_offset: F,
    transform_margin: F,
    cached_boundaries: ?[]const F = null,

    inline fn lowerBound(self: @This(), index: usize) F {
        return self.boundary(index) - self.transform_margin;
    }

    inline fn upperBound(self: @This(), index: usize) F {
        return self.boundary(index) + self.transform_margin;
    }

    inline fn boundary(self: @This(), index: usize) F {
        if (self.cached_boundaries) |boundaries| return boundaries[index];
        return speckleClassificationBoundary(
            index,
            self.uv_to_cell,
            self.cells_per_uv,
            self.uv_offset,
        );
    }
};

fn speckleClassificationAxes(
    dims: [2]usize,
    uv_to_cell: [2]F,
    params: Speckle2DParams,
) [2]SpeckleClassificationAxis {
    var axes: [2]SpeckleClassificationAxis = undefined;
    for (0..2) |axis| {
        const scale = @max(1.0, params.cells_per_uv[axis] + @abs(params.uv_offset[axis]));
        // Lookup multiplication, boundary division and both affine evaluations cost
        // less than 4*eps*scale; 8 also covers rounding the expanded endpoints.
        // Coordinate and allocation limits keep indices exactly representable in F.
        axes[axis] = .{
            .dim = dims[axis],
            .uv_to_cell = uv_to_cell[axis],
            .cells_per_uv = params.cells_per_uv[axis],
            .uv_offset = params.uv_offset[axis],
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

inline fn speckleClassificationSearchIncludesCell(
    box_min: F,
    box_max: F,
    cell: i64,
) bool {
    const min_cell = @as(i64, @intFromFloat(@floor(box_min))) - 1;
    const max_cell = @as(i64, @intFromFloat(@floor(box_max))) + 1;
    return cell >= min_cell and cell <= max_cell;
}

fn stampFixedSpeckleDiskClassification(
    states: []u8,
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
    const owner_search_is_implicit = stamp_radius < 1.0;
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
        const proc_min_y = proc_axes[1].lowerBound(yy);
        const proc_max_y = proc_axes[1].upperBound(yy + 1);
        if (!owner_search_is_implicit and
            !speckleClassificationSearchIncludesCell(
                proc_min_y,
                proc_max_y,
                disk_cell[1],
            )) continue;

        for (x_range.min..x_range.max + 1) |xx| {
            const state_index = yy * dims[0] + xx;
            const packed_byte = states[state_index / 4];
            const old_state = decodeSpeckleClassificationState(
                packed_byte,
                state_index,
            );
            if (old_state == .foreground) continue;

            const proc_min_x = proc_axes[0].lowerBound(xx);
            const proc_max_x = proc_axes[0].upperBound(xx + 1);
            if (!owner_search_is_implicit and
                !speckleClassificationSearchIncludesCell(
                    proc_min_x,
                    proc_max_x,
                    disk_cell[0],
                )) continue;

            const disk_state = classifySpeckleDiskMicrocell(
                disk,
                .{ proc_min_x, proc_min_y },
                .{ proc_max_x, proc_max_y },
            );
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

fn buildFixedSpeckleClassificationsByStamping(
    states: []u8,
    dims: [2]usize,
    uv_to_cell: [2]F,
    speckles: SpeckleList2D,
) void {
    std.debug.assert(speckles.params.radius_jitter == 0.0);
    if (speckles.disks.len == 0) return;

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
            const encoded = speckles.disk_by_cell[cell_index];
            if (encoded == SpeckleList2D.no_disk) continue;
            const disk_cell_x = speckles.cell_origin[0] + @as(i64, @intCast(xx));
            stampFixedSpeckleDiskClassification(
                states,
                dims,
                proc_axes,
                domain_scale,
                .{ disk_cell_x, disk_cell_y },
                speckles.disks[encoded],
            );
        }
    }
}

pub fn generateClassifiedIndexedSpeckle2D(
    allocator: std.mem.Allocator,
    params: Speckle2DParams,
) !ClassifiedIndexedSpeckle2D {
    const speckles = try generateSpeckleList2D(allocator, params);
    errdefer allocator.free(speckles.disk_by_cell);
    errdefer allocator.free(speckles.disks);

    const dims = try speckleClassificationDims(params);
    const state_count = std.math.mul(usize, dims[0], dims[1]) catch
        return error.SpeckleClassificationTooLarge;
    const state_byte_count = try speckleClassificationByteCount(state_count);
    const states = try allocator.alloc(u8, state_byte_count);
    errdefer allocator.free(states);
    @memset(states, 0);
    const uv_to_cell = [2]F{
        @floatFromInt(dims[0]),
        @floatFromInt(dims[1]),
    };
    if (params.radius_jitter == 0.0) {
        buildFixedSpeckleClassificationsByStamping(
            states,
            dims,
            uv_to_cell,
            speckles,
        );
    } else {
        buildSpeckleClassificationsExhaustive(
            states,
            dims,
            uv_to_cell,
            speckles,
        );
    }
    return .{
        .speckles = speckles,
        .states = states,
        .dims = dims,
        .uv_to_cell = uv_to_cell,
    };
}

fn speckleDiskMask(
    comptime soft_edges: bool,
    distance2: F,
    radius: F,
    edge_softness: F,
) F {
    if (comptime speckle_shape == .gaussian) {
        const radius2 = radius * radius;
        if (distance2 >= radius2) return 0.0;
        const sigma = radius / 3.0;
        return @exp(-0.5 * distance2 / (sigma * sigma));
    }
    if (comptime !soft_edges) {
        return if (distance2 <= radius * radius) 1.0 else 0.0;
    }
    if (edge_softness == 0.0) return if (distance2 <= radius * radius) 1.0 else 0.0;

    const inner_radius = @max(0.0, radius - edge_softness);
    const outer_radius = radius + edge_softness;
    const inner2 = inner_radius * inner_radius;
    const outer2 = outer_radius * outer_radius;

    if (distance2 <= inner2) return 1.0;
    if (distance2 >= outer2) return 0.0;

    const transition = (distance2 - inner2) / (outer2 - inner2);
    return 1.0 - cubicSmoothStep(transition);
}

fn speckleListDiskAt(
    speckles: SpeckleList2D,
    cell_x: i64,
    cell_y: i64,
) ?SpeckleDisk2D {
    if (cell_x < speckles.cell_origin[0] or cell_y < speckles.cell_origin[1]) {
        return null;
    }
    const rel_x = std.math.cast(usize, cell_x - speckles.cell_origin[0]) orelse
        return null;
    const rel_y = std.math.cast(usize, cell_y - speckles.cell_origin[1]) orelse
        return null;
    if (rel_x >= speckles.cell_dims[0] or rel_y >= speckles.cell_dims[1]) return null;
    const encoded = speckles.disk_by_cell[rel_y * speckles.cell_dims[0] + rel_x];
    if (encoded == SpeckleList2D.no_disk) return null;
    return speckles.disks[encoded];
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
    const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0] +
        params.uv_offset[0];
    const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1] +
        params.uv_offset[1];
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
        const proc_y = uv_y * params.cells_per_uv[1] + params.uv_offset[1];
        const cell_y = @as(i64, @intFromFloat(@floor(proc_y)));
        const rel_y = std.math.cast(usize, cell_y - cell_bounds.min[1]) orelse
            return error.SpeckleMaskTooLarge;
        if (rel_y + 1 >= cell_bounds.dims[1]) return error.SpeckleMaskTooLarge;
        const frac_y = proc_y - @as(F, @floatFromInt(cell_y));
        const fade_y = quinticPerlinFade(frac_y);

        for (0..dims[0]) |xx| {
            const uv_x = @as(F, @floatFromInt(xx)) / uv_to_texel[0];
            const proc_x = uv_x * params.cells_per_uv[0] + params.uv_offset[0];
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
        (disk.center[0] - outer_radius - params.uv_offset[0]) * proc_to_texel[0],
        (disk.center[1] - outer_radius - params.uv_offset[1]) * proc_to_texel[1],
    };
    const box_max = [2]F{
        (disk.center[0] + outer_radius - params.uv_offset[0]) * proc_to_texel[0],
        (disk.center[1] + outer_radius - params.uv_offset[1]) * proc_to_texel[1],
    };
    if (box_max[0] < 0.0 or box_max[1] < 0.0 or
        box_min[0] > uv_to_texel[0] or box_min[1] > uv_to_texel[1]) return;
    const min_x: usize = @intFromFloat(@max(0.0, @floor(box_min[0])));
    const min_y: usize = @intFromFloat(@max(0.0, @floor(box_min[1])));
    const max_x: usize = @intFromFloat(@min(uv_to_texel[0], @ceil(box_max[0])));
    const max_y: usize = @intFromFloat(@min(uv_to_texel[1], @ceil(box_max[1])));

    for (min_y..max_y + 1) |yy| {
        const proc_y = @as(F, @floatFromInt(yy)) * texel_to_proc[1] +
            params.uv_offset[1];
        const delta_y = proc_y - disk.center[1];
        for (min_x..max_x + 1) |xx| {
            const proc_x = @as(F, @floatFromInt(xx)) * texel_to_proc[0] +
                params.uv_offset[0];
            const delta_x = proc_x - disk.center[0];
            const coverage = speckleDiskMask(
                soft_edges,
                delta_x * delta_x + delta_y * delta_y,
                disk.radius,
                edge_softness,
            );
            if (comptime buildconfig.speckle_evaluator == .mask_u8) {
                const idx = yy * row_stride + xx;
                bits[idx] = @max(bits[idx], quantizeSpeckleCoverage(coverage));
            } else if (coverage != 0.0) {
                const shift: u3 = @intCast(xx & 7);
                bits[yy * row_stride + xx / 8] |= @as(u8, 1) << shift;
            }
        }
    }
}

pub fn generateSpeckleMask2D(
    allocator: std.mem.Allocator,
    params: Speckle2DParams,
) !SpeckleMask2D {
    try params.validate();
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
    const row_stride = if (comptime buildconfig.speckle_evaluator == .mask_u8)
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

pub inline fn evalSpeckleMask2D(uv: [2]F, mask: SpeckleMask2D) F {
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
    if (comptime buildconfig.speckle_evaluator == .mask_u8) {
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

pub inline fn evalDirectFixedSpeckle2D(
    uv: [2]F,
    direct: DirectFixedSpeckle2D,
) F {
    const params = direct.params;
    if (params.foreground == params.background or
        !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
    {
        return params.background;
    }

    const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0] +
        params.uv_offset[0];
    const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1] +
        params.uv_offset[1];
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
    return if (dx * dx + dy * dy <= direct.radius2)
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
    const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0] +
        params.uv_offset[0];
    const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1] +
        params.uv_offset[1];
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

fn evalSpeckleList2DIndexedImpl(
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
    const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0] +
        params.uv_offset[0];
    const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1] +
        params.uv_offset[1];
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
    const min_delta_x = if (comptime speckle_neighbor_count == 1)
        [_]F{0.0}
    else if (comptime speckle_neighbor_count == 4)
        [_]F{ 0.0, 1.0 - frac_x }
    else
        [_]F{ frac_x, 0.0, 1.0 - frac_x };
    const min_delta_y = if (comptime speckle_neighbor_count == 1)
        [_]F{0.0}
    else if (comptime speckle_neighbor_count == 4)
        [_]F{ 0.0, 1.0 - frac_y }
    else
        [_]F{ frac_y, 0.0, 1.0 - frac_y };
    const edge_softness = if (soft_edges) params.edge_softness else 0.0;
    const max_outer_radius = params.radius_mean + params.radius_jitter +
        edge_softness;
    const max_outer_radius2 = max_outer_radius * max_outer_radius;

    var coverage: F = 0.0;
    neighbor_loop: for (offsets, min_delta_y) |offset_y, min_dy| {
        for (offsets, min_delta_x) |offset_x, min_dx| {
            if (min_dx * min_dx + min_dy * min_dy > max_outer_radius2) continue;
            const disk = speckleListDiskAt(
                speckles,
                cell_x + offset_x,
                cell_y + offset_y,
            ) orelse continue;
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

inline fn classifiedSpeckleState(
    uv: [2]F,
    classified: ClassifiedIndexedSpeckle2D,
) SpeckleClassificationState {
    const cell_x = @min(
        classified.dims[0] - 1,
        @as(usize, @intFromFloat(
            @max(0.0, @min(1.0, uv[0])) * classified.uv_to_cell[0],
        )),
    );
    const cell_y = @min(
        classified.dims[1] - 1,
        @as(usize, @intFromFloat(
            @max(0.0, @min(1.0, uv[1])) * classified.uv_to_cell[1],
        )),
    );
    const state_index = cell_y * classified.dims[0] + cell_x;
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

pub fn evalClassifiedIndexedSpeckle2D(
    uv: [2]F,
    classified: ClassifiedIndexedSpeckle2D,
) F {
    const params = classified.speckles.params;
    if (classified.speckles.disks.len == 0 or
        params.foreground == params.background or
        !std.math.isFinite(uv[0]) or !std.math.isFinite(uv[1]))
    {
        return params.background;
    }
    return switch (classifiedSpeckleState(uv, classified)) {
        .background => speckleCoverageEndpointValue(params, 0.0),
        .foreground => speckleCoverageEndpointValue(params, 1.0),
        .ambiguous => evalSpeckleList2DIndexedImpl(
            false,
            uv[0],
            uv[1],
            classified.speckles,
        ),
        .reserve3 => unreachable,
    };
}

pub fn evalSpeckleList2D(uv: [2]F, speckles: SpeckleList2D) F {
    return if (speckleSoftness(speckles.params) > 0.0)
        evalSpeckleList2DImpl(true, uv[0], uv[1], speckles)
    else
        evalSpeckleList2DImpl(false, uv[0], uv[1], speckles);
}

// Scalar coordinates avoid a per-sample array spill at this kernel boundary.
fn evalSpeckleList2DImpl(
    comptime soft_edges: bool,
    u: F,
    v: F,
    speckles: SpeckleList2D,
) F {
    return switch (comptime buildconfig.speckle_evaluator) {
        .list_indexed,
        .classified_indexed,
        .direct_fixed,
        .mask_1bit,
        .mask_u8,
        => evalSpeckleList2DIndexedImpl(soft_edges, u, v, speckles),
        .cell_hash, .list_naive => evalSpeckleList2DNaiveImpl(soft_edges, u, v, speckles),
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
    const uv = [2]F{ u, v };
    if (comptime speckle_shape == .perlin) return evalPerlinSpeckle2D(uv, params);
    if (params.occupancy == 0.0 or params.foreground == params.background) {
        return params.background;
    }

    const proc_x = @max(0.0, @min(1.0, uv[0])) * params.cells_per_uv[0] +
        params.uv_offset[0];
    const proc_y = @max(0.0, @min(1.0, uv[1])) * params.cells_per_uv[1] +
        params.uv_offset[1];
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
    const min_delta_x = if (comptime speckle_neighbor_count == 1)
        [_]F{0.0}
    else if (comptime speckle_neighbor_count == 4)
        [_]F{ 0.0, 1.0 - frac_x }
    else
        [_]F{ frac_x, 0.0, 1.0 - frac_x };
    const min_delta_y = if (comptime speckle_neighbor_count == 1)
        [_]F{0.0}
    else if (comptime speckle_neighbor_count == 4)
        [_]F{ 0.0, 1.0 - frac_y }
    else
        [_]F{ frac_y, 0.0, 1.0 - frac_y };
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
    classified: *const ClassifiedIndexedSpeckle2D,
) VecSF {
    const params = classified.speckles.params;
    const v_background: VecSF = @splat(params.background);
    if (classified.speckles.disks.len == 0 or
        params.foreground == params.background)
    {
        return v_background;
    }

    const v_zero: VecSF = @splat(0.0);
    const v_one: VecSF = @splat(1.0);
    const v_inf: VecSF = @splat(std.math.inf(F));
    const v_sample = v_mask_active & (@abs(u) < v_inf) &
        (@abs(v) < v_inf);
    const v_u = @select(F, v_sample, u, v_zero);
    const v_v = @select(F, v_sample, v, v_zero);
    const v_cell_x: VecSI = @intFromFloat(@min(
        @as(VecSF, @splat(@as(F, @floatFromInt(classified.dims[0] - 1)))),
        @max(v_zero, @min(v_one, v_u)) *
            @as(VecSF, @splat(classified.uv_to_cell[0])),
    ));
    const v_cell_y: VecSI = @intFromFloat(@min(
        @as(VecSF, @splat(@as(F, @floatFromInt(classified.dims[1] - 1)))),
        @max(v_zero, @min(v_one, v_v)) *
            @as(VecSF, @splat(classified.uv_to_cell[1])),
    ));
    const sample: [S]bool = v_sample;
    const cell_x: [S]isize = v_cell_x;
    const cell_y: [S]isize = v_cell_y;
    var state_values = [_]u8{@intFromEnum(SpeckleClassificationState.background)} ** S;
    inline for (0..S) |lane| {
        if (sample[lane]) {
            const x: usize = @intCast(cell_x[lane]);
            const y: usize = @intCast(cell_y[lane]);
            const state_index = y * classified.dims[0] + x;
            const packed_byte = classified.states[state_index / 4];
            state_values[lane] = @intFromEnum(decodeSpeckleClassificationState(
                packed_byte,
                state_index,
            ));
        }
    }

    const v_states: @Vector(S, u8) = state_values;
    const v_foreground = v_sample & (v_states == @as(
        @Vector(S, u8),
        @splat(@intFromEnum(SpeckleClassificationState.foreground)),
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
        if (sample[lane] and
            state_values[lane] == @intFromEnum(SpeckleClassificationState.ambiguous))
        {
            values[lane] = evalSpeckleList2DIndexedImpl(
                false,
                u[lane],
                v[lane],
                classified.speckles,
            );
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
        @as(VecSF, @splat(params.cells_per_uv[0])) +
        @as(VecSF, @splat(params.uv_offset[0]));
    const v_proc_y = @max(v_zero, @min(v_one, v_v)) *
        @as(VecSF, @splat(params.cells_per_uv[1])) +
        @as(VecSF, @splat(params.uv_offset[1]));
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
        (v_dx * v_dx + v_dy * v_dy <= @as(VecSF, @splat(direct.radius2)));
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

    if (comptime buildconfig.speckle_evaluator == .mask_u8) {
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

test "procedural speckle parameters validate shape-specific settings" {
    var invalid = Speckle2DParams{};
    if (comptime buildconfig.speckle_evaluator == .direct_fixed) {
        invalid.radius_jitter = 0.0;
    }
    try testing.expectEqual(@as(F, 0.0), invalid.edge_softness);
    try invalid.validate();
    if (comptime speckle_shape == .perlin) {
        invalid.perlin_coverage_transition_width = -0.01;
        try testing.expectError(
            error.InvalidSpecklePerlinCoverageTransitionWidth,
            invalid.validate(),
        );
        invalid = Speckle2DParams{};
        invalid.occupancy = -1.0;
        invalid.radius_mean = -1.0;
        invalid.radius_jitter = -1.0;
        try invalid.validate();
    } else {
        if (comptime buildconfig.speckle_evaluator == .direct_fixed) {
            invalid.radius_jitter = 0.01;
            try testing.expectError(
                error.InvalidDirectFixedSpeckleRadiusJitter,
                invalid.validate(),
            );
        } else {
            invalid.radius_jitter = invalid.radius_mean + 0.01;
            try testing.expectError(error.InvalidSpeckleRadiusRange, invalid.validate());
        }

        invalid = Speckle2DParams{};
        if (comptime buildconfig.speckle_evaluator == .direct_fixed) {
            invalid.radius_mean = 0.5;
            invalid.radius_jitter = 0.0;
            try testing.expectError(
                error.InvalidDirectFixedSpeckleRadius,
                invalid.validate(),
            );
        } else {
            invalid.radius_mean = 0.9;
            invalid.radius_jitter = 0.15;
            try testing.expectError(
                error.InvalidSpeckleNeighborhoodRadius,
                invalid.validate(),
            );
        }
    }
}

test "procedural speckle rejects negative and nonfinite softness for every shape" {
    const invalid_values = [_]F{
        -0.01,
        std.math.nan(F),
        std.math.inf(F),
        -std.math.inf(F),
    };
    for (invalid_values) |softness| {
        const params: Speckle2DParams = .{ .edge_softness = softness };
        try testing.expectError(error.InvalidSpeckleEdgeSoftness, params.validate());
    }
}

test "procedural speckle softness requires compatible disk evaluators" {
    const params: Speckle2DParams = .{ .edge_softness = 0.05 };
    if (comptime speckle_shape != .disk) {
        try testing.expectError(error.SpeckleEdgeSoftnessRequiresDisk, params.validate());
        return;
    }
    switch (comptime buildconfig.speckle_evaluator) {
        .classified_indexed, .direct_fixed, .mask_1bit => {
            try testing.expectError(
                error.SpeckleEvaluatorRequiresHardEdges,
                params.validate(),
            );
        },
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => try params.validate(),
    }
}

test "procedural speckle softness expands support bounds" {
    if (comptime speckle_shape != .disk) return;
    switch (comptime buildconfig.speckle_evaluator) {
        .classified_indexed, .direct_fixed, .mask_1bit => return,
        .cell_hash, .list_naive, .list_indexed, .mask_u8 => {},
    }
    var params: Speckle2DParams = .{ .radius_mean = 0.9, .edge_softness = 0.2 };
    try testing.expectError(error.InvalidSpeckleNeighborhoodRadius, params.validate());
    params.edge_softness = 0.0;
    try params.validate();
}

test "speckle generators reject invalid softness before allocating" {
    const params: Speckle2DParams = .{ .edge_softness = std.math.nan(F) };
    inline for (.{
        generateSpeckleList2D,
        generateClassifiedIndexedSpeckle2D,
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
        try testing.expectEqual(@as(F, 1.0), speckleDiskMask(false, 0.25, 0.5, 0.0));
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
    var params = Speckle2DParams{};
    params.cells_per_uv = .{ 12.0, 10.0 };

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
    var speckle_params = Speckle2DParams{};
    speckle_params.cells_per_uv = .{ 11.0, 9.0 };
    speckle_params.seed = 42;
    speckle_params.edge_softness = if (speckle_shape == .disk)
        switch (buildconfig.speckle_evaluator) {
            .classified_indexed, .direct_fixed, .mask_1bit => 0.0,
            .cell_hash, .list_naive, .list_indexed, .mask_u8 => 0.035,
        }
    else
        0.0;

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
        const expected = sampleScal(coords_0[lane], coords_1[lane], speckle_params, &.{});
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
    if (comptime speckle_shape == .perlin) return;
    var params = Speckle2DParams{};
    params.cells_per_uv = .{ 8.0, 8.0 };
    params.occupancy = 0.0;
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
    var params = Speckle2DParams{};
    params.uv_offset[0] = std.math.nan(F);
    try testing.expectError(
        error.InvalidSpeckleUVOffset,
        generateSpeckleList2D(testing.allocator, params),
    );
}

test "generated speckle list matches hard and soft cell hash evaluation" {
    if (comptime speckle_shape == .perlin) return;
    const softnesses: []const F = if (speckle_shape == .disk)
        switch (buildconfig.speckle_evaluator) {
            .cell_hash, .list_naive, .list_indexed, .mask_u8 => &.{ 0.0, 0.035 },
            else => &.{0.0},
        }
    else
        &.{0.0};
    for (softnesses) |softness| {
        const params: Speckle2DParams = .{
            .cells_per_uv = .{ 4.0, 3.0 },
            .uv_offset = .{ -0.25, 0.4 },
            .occupancy = 0.7,
            .edge_softness = softness,
        };
        try testing.expectEqual(softness, speckleSoftness(params));
        const speckles = try generateSpeckleList2D(testing.allocator, params);
        defer testing.allocator.free(speckles.disk_by_cell);
        defer testing.allocator.free(speckles.disks);
        var found_intermediate = false;
        for (0..9) |yy| {
            for (0..9) |xx| {
                const uv = [2]F{
                    @as(F, @floatFromInt(xx)) / 8.0,
                    @as(F, @floatFromInt(yy)) / 8.0,
                };
                const value = evalSpeckle2D(uv, params);
                try testing.expectEqual(value, evalSpeckleList2D(uv, speckles));
                found_intermediate = found_intermediate or (value > 0.0 and value < 1.0);
            }
        }
        if (speckle_shape == .disk) {
            try testing.expectEqual(softness > 0.0, found_intermediate);
        }
    }
}

test "direct fixed generation is contained and exact" {
    if (comptime buildconfig.speckle_evaluator != .direct_fixed) return;

    const params: Speckle2DParams = .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 3.25, 1.75 },
        .uv_offset = .{ 0.37, -0.42 },
        .occupancy = 0.72,
        .radius_mean = 0.38,
        .radius_jitter = 0.0,
        .foreground = 0.15,
        .background = 0.85,
    };
    const first = try generateDirectFixedSpeckle2D(testing.allocator, params);
    defer testing.allocator.free(first.cells);
    var inactive_params = params;
    inactive_params.occupancy = 0.0;
    const inactive = try generateDirectFixedSpeckle2D(testing.allocator, inactive_params);
    defer testing.allocator.free(inactive.cells);
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

fn expectClassifiedSpeckleExact(
    classified: ClassifiedIndexedSpeckle2D,
    uv: [2]F,
) !void {
    try testing.expectEqual(
        evalSpeckle2D(uv, classified.speckles.params),
        evalClassifiedIndexedSpeckle2D(uv, classified),
    );
}

fn expectClassifiedSpeckleDifferential(
    stamped: ClassifiedIndexedSpeckle2D,
    exhaustive: ClassifiedIndexedSpeckle2D,
    uv: [2]F,
) !void {
    const actual = evalClassifiedIndexedSpeckle2D(uv, stamped);
    try testing.expectEqual(
        evalClassifiedIndexedSpeckle2D(uv, exhaustive),
        actual,
    );
    try testing.expectEqual(evalSpeckle2D(uv, stamped.speckles.params), actual);
}

fn expectFixedSpeckleStampMatchesExhaustive(params: Speckle2DParams) !void {
    const stamped = try generateClassifiedIndexedSpeckle2D(testing.allocator, params);
    defer testing.allocator.free(stamped.states);
    defer testing.allocator.free(stamped.speckles.disk_by_cell);
    defer testing.allocator.free(stamped.speckles.disks);

    const exhaustive_states = try testing.allocator.alloc(u8, stamped.states.len);
    defer testing.allocator.free(exhaustive_states);
    @memset(exhaustive_states, 0);
    buildSpeckleClassificationsExhaustive(
        exhaustive_states,
        stamped.dims,
        stamped.uv_to_cell,
        stamped.speckles,
    );
    try testing.expectEqualSlices(u8, exhaustive_states, stamped.states);

    var exhaustive = stamped;
    exhaustive.states = exhaustive_states;
    const fixed_points = [_][2]F{
        .{ 0.0, 0.0 },
        .{ 1.0, 1.0 },
        .{ 0.0, 1.0 },
        .{ 1.0, 0.0 },
        .{ -2.0, 0.37 },
        .{ 3.0, 0.61 },
        .{ -1.0, 2.0 },
    };
    for (fixed_points) |uv| {
        try expectClassifiedSpeckleDifferential(stamped, exhaustive, uv);
    }

    for (0..97) |ii| {
        const uv = [2]F{
            @as(F, @floatFromInt((ii * 73 + 19) % 257)) / 256.0,
            @as(F, @floatFromInt((ii * 151 + 43) % 263)) / 262.0,
        };
        try expectClassifiedSpeckleDifferential(stamped, exhaustive, uv);
    }
    for (0..stamped.dims[0] + 1) |xx| {
        if (xx % 5 != 0 and xx != stamped.dims[0]) continue;
        const u = @as(F, @floatFromInt(xx)) / stamped.uv_to_cell[0];
        try expectClassifiedSpeckleDifferential(
            stamped,
            exhaustive,
            .{ u, 0.413 },
        );
    }
    for (0..stamped.dims[1] + 1) |yy| {
        if (yy % 5 != 0 and yy != stamped.dims[1]) continue;
        const v = @as(F, @floatFromInt(yy)) / stamped.uv_to_cell[1];
        try expectClassifiedSpeckleDifferential(
            stamped,
            exhaustive,
            .{ 0.587, v },
        );
    }

    const adjacent = 8.0 * std.math.floatEps(F);
    for (stamped.speckles.disks) |disk| {
        const boundary_proc_x = disk.center[0] + disk.radius;
        const boundary_u = (boundary_proc_x - params.uv_offset[0]) /
            params.cells_per_uv[0];
        const center_v = (disk.center[1] - params.uv_offset[1]) /
            params.cells_per_uv[1];
        if (boundary_u >= 0.0 and boundary_u <= 1.0 and
            center_v >= 0.0 and center_v <= 1.0)
        {
            try expectClassifiedSpeckleDifferential(
                stamped,
                exhaustive,
                .{ boundary_u, center_v },
            );
            try expectClassifiedSpeckleDifferential(
                stamped,
                exhaustive,
                .{ boundary_u - adjacent, center_v },
            );
            try expectClassifiedSpeckleDifferential(
                stamped,
                exhaustive,
                .{ boundary_u + adjacent, center_v },
            );
        }
    }
}

test "fixed-radius stamped speckle classification matches exhaustive construction" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const cases = [_]Speckle2DParams{
        .{
            .seed = 0x85ebca6b,
            .cells_per_uv = .{ 5.25, 4.4 },
            .uv_offset = .{ -1.375, -0.625 },
            .occupancy = 0.72,
            .radius_mean = 0.2,
            .radius_jitter = 0.0,
            .foreground = 0.17,
            .background = 0.83,
        },
        .{
            .seed = 0x9e3779b9,
            .cells_per_uv = .{ 3.125, 2.75 },
            .uv_offset = .{ 0.9375, -1.0625 },
            .occupancy = 1.0,
            .radius_mean = 0.82,
            .radius_jitter = 0.0,
            .foreground = 0.91,
            .background = 0.09,
        },
        .{
            .seed = 0x27d4eb2d,
            .cells_per_uv = .{ 2.25, 1.75 },
            .uv_offset = if (F == f32)
                .{ 65_530.0, -65_535.0 }
            else
                .{ 35_184_372_088_828.0, -35_184_372_088_831.0 },
            .occupancy = 0.85,
            .radius_mean = 0.45,
            .radius_jitter = 0.0,
            .foreground = 0.0,
            .background = 1.0,
        },
        .{
            .seed = 0x165667b1,
            .cells_per_uv = .{ 0.03125, 0.0625 },
            .uv_offset = .{ 0.999, -2.001 },
            .occupancy = 1.0,
            .radius_mean = 0.95,
            .radius_jitter = 0.0,
            .foreground = 0.25,
            .background = 0.75,
        },
        .{
            .cells_per_uv = .{ 3.0, 2.0 },
            .uv_offset = .{ -0.25, 0.75 },
            .occupancy = 0.0,
            .radius_mean = 0.35,
            .radius_jitter = 0.0,
        },
    };
    for (cases) |params| try expectFixedSpeckleStampMatchesExhaustive(params);

    for ([_]usize{ 1, 2 }) |case_index| {
        var unit_radius_params = cases[case_index];
        for ([_]F{ std.math.floatEps(F), 1.0 - std.math.floatEps(F), 1.0 }) |radius| {
            unit_radius_params.radius_mean = radius;
            try expectFixedSpeckleStampMatchesExhaustive(unit_radius_params);
        }
    }
}

test "fixed-radius stamping handles boundary cache overflow exactly" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const overflowing_interval_count: F =
        @as(F, @floatFromInt(speckle_classification_boundary_cache_capacity + 1)) + 0.5;
    const params: Speckle2DParams = .{
        .seed = 0x7f4a7c15,
        .cells_per_uv = .{
            overflowing_interval_count / speckle_mask_samples_per_cell,
            0.5 / speckle_mask_samples_per_cell,
        },
        .uv_offset = .{ -0.375, 0.25 },
        .occupancy = 0.5,
        .radius_mean = 0.35,
        .radius_jitter = 0.0,
    };
    const dims = try speckleClassificationDims(params);
    try testing.expect(
        dims[0] + 1 > speckle_classification_boundary_cache_capacity,
    );
    try testing.expectEqual(@as(usize, 1), dims[1]);
    try expectFixedSpeckleStampMatchesExhaustive(params);
}

test "speckle classification bounds contain rounded UV lookups" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const cases = [_]Speckle2DParams{
        .{ .cells_per_uv = .{ 192.0, 160.0 }, .uv_offset = .{ -191.0, -159.0 } },
        .{ .cells_per_uv = .{ 3.25, 2.5 }, .uv_offset = .{ -2.0, 0.4 } },
        .{ .cells_per_uv = .{ 0.03125, 0.0625 }, .uv_offset = .{ 0.999, -2.001 } },
        .{
            .cells_per_uv = .{ 2.25, 1.75 },
            .uv_offset = if (F == f32)
                .{ 65_530.0, -65_535.0 }
            else
                .{ 35_184_372_088_828.0, -35_184_372_088_831.0 },
        },
    };
    for (cases) |params| {
        try params.validate();
        const dims = try speckleClassificationDims(params);
        const uv_to_cell = [2]F{ @floatFromInt(dims[0]), @floatFromInt(dims[1]) };
        const axes = speckleClassificationAxes(dims, uv_to_cell, params);
        for (axes) |axis| {
            for (0..axis.dim + 1) |ii| {
                const uv = @as(F, @floatFromInt(ii)) / axis.uv_to_cell;
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
                    const index: usize = @intFromFloat(bounded_uv * axis.uv_to_cell);
                    const cell = @min(axis.dim - 1, index);
                    const proc = bounded_uv * axis.cells_per_uv + axis.uv_offset;
                    try testing.expect(proc >= axis.lowerBound(cell));
                    try testing.expect(proc <= axis.upperBound(cell + 1));
                }
            }
        }
    }
}

test "classified indexed speckle preserves foreground after UV cancellation" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const params: Speckle2DParams = .{
        .seed = 63,
        .cells_per_uv = .{ 192.0, 1.0 },
        .uv_offset = .{ -191.0, 0.0 },
        .occupancy = 0.01,
        .radius_mean = if (F == f32) 0.06400136 else 0.4806722005208286,
        .radius_jitter = 0.0,
        .foreground = 0.0,
        .background = 1.0,
    };
    // Both precision-specific samples lie inside the disk centred at
    // (-0.8973388671875, 0.73699951171875). At 12 samples/cell, cancellation places
    // them outside their nominal microcells, beyond the local-coordinate margin.
    const uv = [2]F{
        if (F == f32) 0.9904513359069824 else 0.9926215277777777,
        0.73699951171875,
    };
    const classified = try generateClassifiedIndexedSpeckle2D(testing.allocator, params);
    defer testing.allocator.free(classified.states);
    defer testing.allocator.free(classified.speckles.disk_by_cell);
    defer testing.allocator.free(classified.speckles.disks);

    try testing.expectEqual(
        params.foreground,
        evalSpeckleList2DIndexedImpl(false, uv[0], uv[1], classified.speckles),
    );
    try testing.expectEqual(
        params.foreground,
        evalClassifiedIndexedSpeckle2D(uv, classified),
    );
    try expectFixedSpeckleStampMatchesExhaustive(params);
}

test "classified indexed speckle is exact on boundaries and varied points" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const params: Speckle2DParams = .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 5.25, 4.4 },
        .uv_offset = .{ -1.375, -0.625 },
        .occupancy = 0.72,
        .radius_mean = 0.2,
        .radius_jitter = 0.07,
        .foreground = 0.17,
        .background = 0.83,
    };
    const classified = try generateClassifiedIndexedSpeckle2D(testing.allocator, params);
    defer testing.allocator.free(classified.states);
    defer testing.allocator.free(classified.speckles.disk_by_cell);
    defer testing.allocator.free(classified.speckles.disks);

    var found_state = [_]bool{false} ** 3;
    const state_count = classified.dims[0] * classified.dims[1];
    for (0..state_count) |index| {
        const state = decodeSpeckleClassificationState(
            classified.states[index / 4],
            index,
        );
        try testing.expect(state != .reserve3);
        found_state[@intFromEnum(state)] = true;
    }
    for (found_state) |found| try testing.expect(found);

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

    for (0..classified.dims[0] + 1) |xx| {
        if (xx % 7 != 0 and xx != classified.dims[0]) continue;
        const u = @as(F, @floatFromInt(xx)) / classified.uv_to_cell[0];
        try expectClassifiedSpeckleExact(classified, .{ u, 0.413 });
    }
    for (0..classified.dims[1] + 1) |yy| {
        if (yy % 5 != 0 and yy != classified.dims[1]) continue;
        const v = @as(F, @floatFromInt(yy)) / classified.uv_to_cell[1];
        try expectClassifiedSpeckleExact(classified, .{ 0.587, v });
    }

    var cell_x = @as(i64, @intFromFloat(@ceil(params.uv_offset[0])));
    const cell_x_end = @as(i64, @intFromFloat(@floor(
        params.uv_offset[0] + params.cells_per_uv[0],
    )));
    while (cell_x <= cell_x_end) : (cell_x += 1) {
        const u = (@as(F, @floatFromInt(cell_x)) - params.uv_offset[0]) /
            params.cells_per_uv[0];
        try expectClassifiedSpeckleExact(classified, .{ u, 0.319 });
    }
    var cell_y = @as(i64, @intFromFloat(@ceil(params.uv_offset[1])));
    const cell_y_end = @as(i64, @intFromFloat(@floor(
        params.uv_offset[1] + params.cells_per_uv[1],
    )));
    while (cell_y <= cell_y_end) : (cell_y += 1) {
        const v = (@as(F, @floatFromInt(cell_y)) - params.uv_offset[1]) /
            params.cells_per_uv[1];
        try expectClassifiedSpeckleExact(classified, .{ 0.681, v });
    }

    const adjacent = 8.0 * std.math.floatEps(F);
    for (classified.speckles.disks) |disk| {
        const boundary_proc_x = disk.center[0] + disk.radius;
        const boundary_u = (boundary_proc_x - params.uv_offset[0]) /
            params.cells_per_uv[0];
        const center_v = (disk.center[1] - params.uv_offset[1]) /
            params.cells_per_uv[1];
        if (boundary_u >= 0.0 and boundary_u <= 1.0 and
            center_v >= 0.0 and center_v <= 1.0)
        {
            try expectClassifiedSpeckleExact(classified, .{ boundary_u, center_v });
            try expectClassifiedSpeckleExact(
                classified,
                .{ boundary_u - adjacent, center_v },
            );
            try expectClassifiedSpeckleExact(
                classified,
                .{ boundary_u + adjacent, center_v },
            );
        }
    }
}

test "procedural speckle equal-colour fast path is exact" {
    var params = Speckle2DParams{};
    params.foreground = 0.375;
    params.background = params.foreground;
    try testing.expectEqual(params.background, evalSpeckle2D(.{ 0.37, 0.61 }, params));
}

fn speckleMaskTestParams() Speckle2DParams {
    return .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 3.25, 2.5 },
        .uv_offset = .{ 0.37, -0.42 },
        .occupancy = 0.72,
        .radius_mean = 0.38,
        .radius_jitter = 0.07,
        .edge_softness = if (speckle_shape == .disk and
            buildconfig.speckle_evaluator == .mask_u8) 0.035 else 0.0,
        .foreground = 0.15,
        .background = 0.85,
    };
}

test "Perlin mask is varied seed-sensitive bounded and balanced" {
    if (comptime speckle_shape != .perlin) return;

    var params = Speckle2DParams{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 7.25, 5.5 },
        .uv_offset = .{ -2.375, -0.625 },
        .foreground = 0.15,
        .background = 0.85,
    };
    params.occupancy = -1.0;
    params.radius_mean = -1.0;
    params.radius_jitter = -1.0;

    const first = try generateSpeckleMask2D(testing.allocator, params);
    defer testing.allocator.free(first.bits);

    params.seed +%= 1;
    const changed = try generateSpeckleMask2D(testing.allocator, params);
    defer testing.allocator.free(changed.bits);
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
    endpoint_params.uv_offset = .{ 0.0, 0.0 };
    const endpoint = try generateSpeckleMask2D(testing.allocator, endpoint_params);
    defer testing.allocator.free(endpoint.bits);
    try testing.expect(std.math.isFinite(evalSpeckleMask2D(.{ 1.0, 1.0 }, endpoint)));
}

test "direct 1-bit speckle mask preserves list-derived bytes and lattice values" {
    if (comptime buildconfig.speckle_evaluator != .mask_1bit) return;

    const params = speckleMaskTestParams();
    const speckles = try generateSpeckleList2D(testing.allocator, params);
    defer testing.allocator.free(speckles.disk_by_cell);
    defer testing.allocator.free(speckles.disks);

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
                evalSpeckleList2DIndexedImpl(false, uv[0], uv[1], speckles),
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
    if (comptime buildconfig.speckle_evaluator != .mask_1bit and
        buildconfig.speckle_evaluator != .mask_u8) return;

    var params = speckleMaskTestParams();
    if (comptime speckle_shape != .perlin) {
        params.occupancy = 0.0;
        const empty = try generateSpeckleMask2D(testing.allocator, params);
        defer testing.allocator.free(empty.bits);
        try testing.expectEqual(@as(usize, 0), empty.bits.len);
        try testing.expectEqual(
            params.background,
            evalSpeckleMask2D(.{ 0.37, 0.61 }, empty),
        );
    }

    params.occupancy = 1.0;
    params.foreground = params.background;
    const equal_colour = try generateSpeckleMask2D(testing.allocator, params);
    defer testing.allocator.free(equal_colour.bits);
    try testing.expectEqual(@as(usize, 0), equal_colour.bits.len);
    try testing.expectEqual(
        params.background,
        evalSpeckleMask2D(.{ 0.37, 0.61 }, equal_colour),
    );

    params = speckleMaskTestParams();
    if (comptime buildconfig.speckle_evaluator == .mask_u8) {
        params.cells_per_uv = .{ 3000.0, 3000.0 };
        try testing.expectError(
            error.SpeckleMaskTooLarge,
            generateSpeckleMask2D(testing.allocator, params),
        );
    }
    params.cells_per_uv = .{ 4000.0, 4000.0 };
    try testing.expectError(
        error.SpeckleMaskTooLarge,
        generateSpeckleMask2D(testing.allocator, params),
    );
}

test "speckle mask clamps UV endpoints" {
    if (comptime buildconfig.speckle_evaluator != .mask_1bit and
        buildconfig.speckle_evaluator != .mask_u8) return;

    const mask = try generateSpeckleMask2D(testing.allocator, speckleMaskTestParams());
    defer testing.allocator.free(mask.bits);

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
    if (comptime buildconfig.speckle_evaluator != .mask_u8) return;

    const params = speckleMaskTestParams();
    const speckles = try generateSpeckleList2D(testing.allocator, params);
    defer testing.allocator.free(speckles.disk_by_cell);
    defer testing.allocator.free(speckles.disks);
    const mask = try generateSpeckleMask2D(testing.allocator, params);
    defer testing.allocator.free(mask.bits);

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
            else
                evalSpeckleList2D(uv, speckles);
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

test "direct fixed prepared SIMD handles active inactive and nonfinite lanes" {
    if (comptime buildconfig.speckle_evaluator != .direct_fixed) return;

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
    const cases = [_]struct { uv: [2]F, active: bool = true, value: F }{
        .{ .uv = .{ 0.25, 0.5 }, .value = params.foreground },
        .{ .uv = .{ 0.1, 0.5 }, .value = params.background },
        .{ .uv = .{ 0.75, 0.5 }, .value = params.background },
        .{ .uv = .{ std.math.nan(F), std.math.inf(F) }, .value = params.background },
        .{ .uv = .{ 0.25, 0.5 }, .active = false, .value = params.background },
    };
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
        const actual: [S]F = sampleSIMD(coord_0, coord_1, active, params, &resources);
        for (0..S) |lane| {
            const case = cases[(batch * S + lane) % cases.len];
            const expected = if (case.active)
                sampleScal(case.uv[0], case.uv[1], params, &resources)
            else
                params.background;
            try testing.expectEqual(case.value, expected);
            try testing.expectEqual(expected, actual[lane]);
        }
    }
}

test "classified indexed prepared SIMD matches scalar for every state" {
    if (comptime buildconfig.speckle_evaluator != .classified_indexed) return;

    const params: Speckle2DParams = .{
        .seed = 0x85ebca6b,
        .cells_per_uv = .{ 5.25, 4.4 },
        .uv_offset = .{ -1.375, -0.625 },
        .occupancy = 1.0,
        .radius_mean = 0.2,
        .radius_jitter = 0.0,
        .foreground = 0.17,
        .background = 0.83,
    };
    const classified = try generateClassifiedIndexedSpeckle2D(testing.allocator, params);
    defer testing.allocator.free(classified.states);
    defer testing.allocator.free(classified.speckles.disk_by_cell);
    defer testing.allocator.free(classified.speckles.disks);

    var state_uv: [3][2]F = undefined;
    var found_state = [_]bool{false} ** 3;
    const state_count = classified.dims[0] * classified.dims[1];
    for (0..state_count) |index| {
        const state = decodeSpeckleClassificationState(
            classified.states[index / 4],
            index,
        );
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

    const resources: Resources = .{ .classified = classified };
    const uv_cases = [_][2]F{
        state_uv[0],
        state_uv[1],
        state_uv[2],
        state_uv[1],
        .{ std.math.nan(F), std.math.inf(F) },
    };
    for (0..(uv_cases.len + S - 1) / S) |batch| {
        var coord_0: [S]F = undefined;
        var coord_1: [S]F = undefined;
        var active: [S]bool = undefined;
        for (0..S) |lane| {
            const index = (batch * S + lane) % uv_cases.len;
            coord_0[lane] = uv_cases[index][0];
            coord_1[lane] = uv_cases[index][1];
            active[lane] = index != 3;
        }
        const actual: [S]F = sampleSIMD(coord_0, coord_1, active, params, &resources);
        for (0..S) |lane| {
            const expected = if (active[lane])
                sampleScal(coord_0[lane], coord_1[lane], params, &resources)
            else
                params.background;
            try testing.expectEqual(expected, actual[lane]);
        }
    }
}

test "1-bit speckle mask SIMD matches scalar and backgrounds invalid lanes" {
    if (comptime buildconfig.speckle_evaluator != .mask_1bit) return;

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
    const u_cases = [_]F{ -2.0, 0.0, 0.0624, 0.0625, 0.99, 1.0, 3.0, 0.5 };
    var coord_0: [S]F = undefined;
    var coord_1: [S]F = undefined;
    for (0..(u_cases.len + S - 1) / S) |batch| {
        for (0..S) |lane| {
            const index = (batch * S + lane) % u_cases.len;
            coord_0[lane] = u_cases[index];
            coord_1[lane] = @as(F, @floatFromInt(index & 1));
        }
        const finite: [S]F = sampleSIMD(
            coord_0,
            coord_1,
            @splat(true),
            params,
            &resources,
        );
        for (0..S) |lane| {
            const expected = sampleScal(coord_0[lane], coord_1[lane], params, &resources);
            try testing.expectEqual(expected, finite[lane]);
        }
    }

    for (0..S) |lane| {
        coord_0[lane] = if (lane & 1 == 0) std.math.nan(F) else 0.0;
        coord_1[lane] = if (lane & 1 == 0) 0.0 else std.math.inf(F);
    }
    const nonfinite: [S]F = sampleSIMD(coord_0, coord_1, @splat(true), params, &resources);
    const inactive: [S]F = sampleSIMD(
        @splat(0.0),
        @splat(0.0),
        @splat(false),
        params,
        &resources,
    );
    for (nonfinite, inactive) |nonfinite_value, inactive_value| {
        try testing.expectEqual(params.background, nonfinite_value);
        try testing.expectEqual(params.background, inactive_value);
    }
}

test "u8 speckle mask SIMD matches scalar for active finite lanes" {
    if (comptime buildconfig.speckle_evaluator != .mask_u8) return;

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
    const uv_cases = [_][2]F{
        .{ -1.0, 0.0 },
        .{ 1.0, 0.0 },
        .{ 0.0, 1.0 },
        .{ 1.0, 1.0 },
    };
    var coord_0: [S]F = undefined;
    var coord_1: [S]F = undefined;
    var active: [S]bool = undefined;
    for ([_]bool{ false, true }) |all_active| {
        for (0..(uv_cases.len + S - 1) / S) |batch| {
            for (0..S) |lane| {
                const index = (batch * S + lane) % uv_cases.len;
                coord_0[lane] = uv_cases[index][0];
                coord_1[lane] = uv_cases[index][1];
                active[lane] = all_active or index & 1 == 0;
            }
            const actual: [S]F = sampleSIMD(coord_0, coord_1, active, params, &resources);
            for (0..S) |lane| {
                const expected = if (active[lane])
                    sampleScal(coord_0[lane], coord_1[lane], params, &resources)
                else
                    params.background;
                try testing.expectEqual(expected, actual[lane]);
            }
        }
    }

    for (0..S) |lane| {
        coord_0[lane] = if (lane & 1 == 0) std.math.nan(F) else 0.0;
        coord_1[lane] = if (lane & 1 == 0) 0.0 else std.math.inf(F);
    }
    var no_gather_mask = mask;
    no_gather_mask.bits = &.{};
    const no_gather: Resources = .{ .mask = no_gather_mask };
    const nonfinite: [S]F = sampleSIMD(coord_0, coord_1, @splat(true), params, &no_gather);
    const inactive: [S]F = sampleSIMD(
        @splat(0.0),
        @splat(0.0),
        @splat(false),
        params,
        &no_gather,
    );
    for (nonfinite, inactive) |nonfinite_value, inactive_value| {
        try testing.expectEqual(params.background, nonfinite_value);
        try testing.expectEqual(params.background, inactive_value);
    }
}

test "speckle resources validate prepare sample and release owned allocations" {
    try testing.expectError(
        error.InvalidSpeckleEdgeSoftness,
        generateResources(testing.failing_allocator, .{ .edge_softness = std.math.nan(F) }),
    );
    const params: Speckle2DParams = .{
        .cells_per_uv = .{ 2.0, 1.5 },
        .occupancy = if (speckle_shape == .perlin) 0.0 else 0.75,
        .radius_mean = 0.35,
        .foreground = 0.17,
        .background = 0.83,
    };
    var resources = try generateResources(testing.allocator, params);
    defer resources.deinit(testing.allocator);
    if (comptime speckle_shape == .perlin) {
        try testing.expectEqual(@as(F, 1.0), resources.mask.?.params.occupancy);
    }
    var fallback_params = params;
    if (comptime buildconfig.speckle_evaluator != .cell_hash) {
        fallback_params.foreground = 0.95;
        fallback_params.background = 0.05;
        fallback_params.occupancy = 0.0;
    }
    for (0..8) |ii| {
        const u = @as(F, @floatFromInt(ii)) / 7.0;
        const v = 1.0 - u;
        const uv = [2]F{ u, v };
        const expected = switch (comptime buildconfig.speckle_evaluator) {
            .cell_hash => evalSpeckle2D(uv, params),
            .list_naive, .list_indexed => evalSpeckleList2D(uv, resources.list.?),
            .classified_indexed => evalClassifiedIndexedSpeckle2D(
                uv,
                resources.classified.?,
            ),
            .direct_fixed => evalDirectFixedSpeckle2D(uv, resources.direct_fixed.?),
            .mask_1bit, .mask_u8 => evalSpeckleMask2D(uv, resources.mask.?),
        };
        try testing.expectEqual(expected, sampleScal(u, v, fallback_params, &resources));
        const actual: [S]F = sampleSIMD(
            @splat(u),
            @splat(v),
            @splat(true),
            fallback_params,
            &resources,
        );
        for (actual) |value| try testing.expectEqual(expected, value);
    }
    resources.deinit(testing.allocator);
    try testing.expect(resources.list == null and resources.classified == null and
        resources.direct_fixed == null and resources.mask == null);
}
