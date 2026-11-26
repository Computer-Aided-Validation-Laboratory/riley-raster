// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Friendly procedural inputs, lowered once to internal cell-space sampling parameters.
const std = @import("std");
const F = @import("buildconfig.zig").F;
const MeshType = @import("geometrykernels.zig").MeshType;
const meshtypes = @import("meshtypes.zig");
const NDArray = @import("ndarray.zig").NDArray;
const geom = @import("specklegeom.zig");
const coverage = @import("specklecoverage.zig");
const speckle = @import("speckleops.zig");
const config = @import("speckleconfig.zig");

pub const ValidationError = coverage.Error || speckle.PerlinControlError || speckle.ColorError || error{
    InvalidSpeckleCellSize,
    SpeckleColorsMustDiffer,
    InvalidSpeckleRadius,
    InvalidSpeckleJitter,
    InvalidSpeckleEdgeSoftness,
    UnsupportedSpeckleSupport,
};

/// Nominal footprints: coverage in (0, 1), radius > 0, occupancy in (0, 1],
/// jitter in [0, radius/2], and edge_softness >= 0, subject to support feasibility.
/// Units, calibration, and coverage semantics: dev/PROCEDURAL.md.
pub const Disk2DParams = struct {
    coverage: F,
    radius: F,
    occupancy: F = 1,
    jitter: F = 0,
    edge_softness: F = 0,
    seed: u32 = config.default_seed,
    foreground: F = 0,
    background: F = 1,
};

/// Truncated Gaussian spots with nominal coverage and the same radius, occupancy,
/// and jitter conventions as disks. The Gaussian profile has no edge-softness control.
pub const Gaussian2DParams = struct {
    coverage: F,
    radius: F,
    occupancy: F = 1,
    jitter: F = 0,
    seed: u32 = config.default_seed,
    foreground: F = 0,
    background: F = 1,
};

/// Thresholded gradient noise. Cell size is positive and in reference-mesh length units;
/// threshold and transition are in noise units. No nominal footprint coverage is implied.
pub const Perlin2DParams = struct {
    cell_size: F,
    threshold: F = 0,
    transition_width: F = config.default_perlin_transition_width,
    seed: u32 = config.default_seed,
    foreground: F = 0,
    background: F = 1,
};

pub const SpeckleParams = union(enum) {
    disk: Disk2DParams,
    gaussian: Gaussian2DParams,
    perlin: Perlin2DParams,

    /// Cheap input/support checks; does not scan geometry or invert coverage.
    /// Invalid scalar inputs retain their specific errors; unattainable nominal coverage
    /// and unsupported jitter/softness support are rejected, never clamped.
    pub fn validate(self: SpeckleParams) ValidationError!void {
        switch (self) {
            inline else => |params, pattern| {
                if (pattern == .perlin) {
                    if (!std.math.isFinite(params.cell_size) or params.cell_size <= 0)
                        return error.InvalidSpeckleCellSize;
                    try speckle.validatePerlinControls(params.threshold, params.transition_width);
                } else {
                    try coverage.validateRequest(params.coverage, params.occupancy);
                    if (!std.math.isFinite(params.radius) or params.radius <= 0)
                        return error.InvalidSpeckleRadius;
                    if (!std.math.isFinite(params.jitter) or params.jitter < 0)
                        return error.InvalidSpeckleJitter;
                    if (params.jitter > 0.5 * params.radius) return error.InvalidSpeckleJitter;
                    if (pattern == .disk and (!std.math.isFinite(params.edge_softness) or params.edge_softness < 0))
                        return error.InvalidSpeckleEdgeSoftness;
                }
                try speckle.validateColors(params.foreground, params.background);
                try speckle.validateColorContrast(params.foreground, params.background);

                if (pattern != .perlin) {
                    // Feasibility only: actual density remains the nominal C,p inverse,
                    // independent of jitter/softness. The nominal cap was already checked.
                    const softness_ratio = if (pattern == .disk) @as(f64, params.edge_softness) / params.radius else 0;
                    const limit = 1 / (1 + @as(f64, params.jitter) / params.radius + softness_ratio);
                    if (limit < 1 and params.coverage > coverage.coverage(params.occupancy, limit))
                        return error.UnsupportedSpeckleSupport;
                }
            },
        }
    }
};

/// Lower friendly inputs against the reference mesh, once for every pattern, before frames.
/// Callers must validate scalar parameters and array metadata/connectivity beforehand, or
/// assume their validity with render validation disabled. The referenced UV domain and
/// calibration geometry are checked here; resource preparation checks converted grid limits.
pub fn resolveForMesh(
    params: SpeckleParams,
    mesh_type: MeshType,
    coords: *const meshtypes.Coords,
    connect: *const meshtypes.Connect,
    uvs: *const NDArray(F),
) !speckle.GridParams {
    const lengths = try geom.calibrateReferenceUv(mesh_type, coords, connect, uvs);
    return resolveCalibrated(params, lengths);
}

/// Prepare backing for a lowered friendly grid, mapping internal size/support errors.
pub fn initResources(outer_alloc: std.mem.Allocator, grid: speckle.GridParams) !speckle.Resources {
    return speckle.Resources.init(outer_alloc, grid) catch |err| return switch (err) {
        error.InvalidSpeckleCellsPerUV,
        error.SpeckleCellCoordinateOutOfRange,
        error.SpeckleClassificationTooLarge,
        error.SpeckleCellBinsTooLarge,
        error.SpecklePerlinLatticeTooLarge,
        error.SpeckleListTooLarge,
        error.DirectFixedSpeckleTooLarge,
        error.SpeckleMaskTooLarge,
        => error.SpeckleDensityOutOfRange,
        error.InvalidSpeckleNeighborhoodRadius => error.UnsupportedSpeckleSupport,
        else => err,
    };
}

fn resolveCalibrated(params: SpeckleParams, length_per_uv: [2]F) speckle.GridParams {
    return switch (params) {
        .perlin => |p| .{
            .pattern = .perlin,
            .cells_per_uv = .{ length_per_uv[0] / p.cell_size, length_per_uv[1] / p.cell_size },
            .perlin_coverage_threshold = p.threshold,
            .perlin_coverage_transition_width = p.transition_width,
            .seed = p.seed,
            .foreground = p.foreground,
            .background = p.background,
        },
        inline .disk, .gaussian => |p, pattern| blk: {
            // Only this lowering step inverts; jitter and softness never affect nominal density.
            const radius: F = @floatCast(coverage.radiusForValidatedCoverage(p.coverage, p.occupancy));
            const inverse_length = radius / p.radius;
            break :blk .{
                .pattern = if (pattern == .disk) .disk else .gaussian,
                .cells_per_uv = .{
                    length_per_uv[0] * inverse_length,
                    length_per_uv[1] * inverse_length,
                },
                .radius_mean = radius,
                .radius_jitter = radius * (p.jitter / p.radius),
                .edge_softness = if (pattern == .disk) radius * (p.edge_softness / p.radius) else 0,
                .occupancy = p.occupancy,
                .seed = p.seed,
                .foreground = p.foreground,
                .background = p.background,
            };
        },
    };
}

const test_calibration = [2]F{ 8, 12 };

test "friendly validation error contract excludes internal grid controls" {
    try std.testing.expect(ValidationError == error{
        InvalidSpeckleCoverage,
        InvalidSpeckleOccupancy,
        UnattainableSpeckleCoverage,
        InvalidSpeckleRadius,
        InvalidSpeckleJitter,
        InvalidSpeckleEdgeSoftness,
        UnsupportedSpeckleSupport,
        InvalidSpeckleCellSize,
        InvalidSpecklePerlinThreshold,
        InvalidSpecklePerlinTransitionWidth,
        InvalidSpeckleForeground,
        InvalidSpeckleBackground,
        SpeckleColorsMustDiffer,
    });
}

test "physical defaults and nominal density ignore jitter and visual softness" {
    const physical = Disk2DParams{ .coverage = 0.5, .radius = 0.02 };
    try std.testing.expectEqual(@as(F, 1), physical.occupancy);
    try std.testing.expectEqual(@as(F, 0), physical.jitter);
    const hard = resolveCalibrated(.{ .disk = physical }, test_calibration);
    const gaussian = resolveCalibrated(.{ .gaussian = .{ .coverage = physical.coverage, .radius = physical.radius } }, test_calibration);
    try std.testing.expectEqual(@as(F, 0), gaussian.edge_softness);
    var varied = physical;
    varied.jitter = 0.003;
    varied.edge_softness = 0.002;
    const soft = resolveCalibrated(.{ .disk = varied }, test_calibration);
    try std.testing.expectEqual(hard.cells_per_uv, soft.cells_per_uv);
    try std.testing.expectEqual(hard.cells_per_uv, gaussian.cells_per_uv);
    try std.testing.expectEqual(hard.radius_mean, soft.radius_mean);
    try std.testing.expectEqual(hard.radius_mean, gaussian.radius_mean);
    const tol: F = if (F == f32) 2e-6 else 2e-14;
    try std.testing.expectApproxEqRel(physical.radius, hard.radius_mean / hard.cells_per_uv[0] * 8, tol);
    try std.testing.expectApproxEqRel(physical.radius, hard.radius_mean / hard.cells_per_uv[1] * 12, tol);
    try std.testing.expectApproxEqRel(varied.jitter / physical.radius, soft.radius_jitter / soft.radius_mean, tol);
    try std.testing.expectApproxEqRel(varied.edge_softness / physical.radius, soft.edge_softness / soft.radius_mean, tol);
    try std.testing.expectEqual(@as(?config.Evaluator, null), hard.evaluator);
}

test "physical parameters reject unattainable coverage, unsupported support and excessive density" {
    var physical = Disk2DParams{ .coverage = 0.99, .radius = 2, .occupancy = 0.1 };
    try std.testing.expectError(error.UnattainableSpeckleCoverage, (SpeckleParams{ .disk = physical }).validate());
    physical.coverage = 0.5;
    physical.occupancy = 1;
    physical.jitter = 1;
    physical.edge_softness = 2;
    try std.testing.expectError(error.UnsupportedSpeckleSupport, (SpeckleParams{ .disk = physical }).validate());
    const grid = resolveCalibrated(.{ .disk = .{ .coverage = 0.5, .radius = 1e-20 } }, test_calibration);
    try std.testing.expectError(error.SpeckleDensityOutOfRange, initResources(std.testing.failing_allocator, grid));
}

test "friendly input scalar errors and colors are strict for both physical shapes" {
    const disk_base: Disk2DParams = .{ .coverage = 0.5, .radius = 2 };
    const gaussian_base: Gaussian2DParams = .{ .coverage = 0.5, .radius = 2 };
    try std.testing.expect(!@hasField(Gaussian2DParams, "edge_softness"));
    const nan = std.math.nan(F);
    const inf = std.math.inf(F);
    const Case = struct { field: []const u8, values: []const F, err: anyerror };
    const cases = [_]Case{
        .{ .field = "coverage", .values = &.{ 0, 1, nan }, .err = error.InvalidSpeckleCoverage },
        .{ .field = "radius", .values = &.{ 0, -1, nan, inf }, .err = error.InvalidSpeckleRadius },
        .{ .field = "occupancy", .values = &.{ 0, 1.1, nan }, .err = error.InvalidSpeckleOccupancy },
        .{ .field = "jitter", .values = &.{ -1, nan, inf }, .err = error.InvalidSpeckleJitter },

        .{ .field = "foreground", .values = &.{ -1, 2, nan, inf, -inf }, .err = error.InvalidSpeckleForeground },
        .{ .field = "background", .values = &.{ -1, 2, nan, inf, -inf }, .err = error.InvalidSpeckleBackground },
        .{ .field = "foreground", .values = &.{1}, .err = error.SpeckleColorsMustDiffer },
    };
    inline for (cases) |case| {
        for (case.values) |value| {
            var disk = disk_base;
            var gaussian = gaussian_base;
            @field(disk, case.field) = value;
            @field(gaussian, case.field) = value;
            try std.testing.expectError(case.err, (SpeckleParams{ .disk = disk }).validate());
            try std.testing.expectError(case.err, (SpeckleParams{ .gaussian = gaussian }).validate());
        }
    }
    for ([_]F{ -1, nan, inf }) |softness| {
        var disk = disk_base;
        disk.edge_softness = softness;
        try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, (SpeckleParams{ .disk = disk }).validate());
    }
}

test "friendly validation reports colors after pattern controls but before support feasibility" {
    var physical = Disk2DParams{
        .coverage = 0.5,
        .radius = 2,
        .jitter = 1,
        .edge_softness = 2,
        .foreground = 1,
    };
    try std.testing.expectError(error.SpeckleColorsMustDiffer, (SpeckleParams{ .disk = physical }).validate());
    physical.edge_softness = -1;
    try std.testing.expectError(error.InvalidSpeckleEdgeSoftness, (SpeckleParams{ .disk = physical }).validate());
    physical.edge_softness = 2;
    physical.background = -1;
    try std.testing.expectError(error.InvalidSpeckleBackground, (SpeckleParams{ .disk = physical }).validate());
}

test "Perlin validates physical cell size and noise controls" {
    const base = Perlin2DParams{ .cell_size = 2 };
    const Case = struct { field: []const u8, values: []const F, err: anyerror };
    const cases = [_]Case{
        .{ .field = "cell_size", .values = &.{ 0, -1, std.math.nan(F), std.math.inf(F) }, .err = error.InvalidSpeckleCellSize },
        .{ .field = "threshold", .values = &.{std.math.nan(F)}, .err = error.InvalidSpecklePerlinThreshold },
        .{ .field = "transition_width", .values = &.{ -1, std.math.inf(F) }, .err = error.InvalidSpecklePerlinTransitionWidth },
        .{ .field = "background", .values = &.{std.math.nan(F)}, .err = error.InvalidSpeckleBackground },
        .{ .field = "foreground", .values = &.{1}, .err = error.SpeckleColorsMustDiffer },
    };
    inline for (cases) |case| for (case.values) |value| {
        var invalid = base;
        @field(invalid, case.field) = value;
        try std.testing.expectError(case.err, (SpeckleParams{ .perlin = invalid }).validate());
    };

    const dense = resolveCalibrated(.{ .perlin = .{ .cell_size = 1e-20 } }, test_calibration);
    try std.testing.expectError(error.SpeckleDensityOutOfRange, initResources(std.testing.failing_allocator, dense));
    if (F == f64) {
        // Both axes fit the coordinate-precision limit, but the lattice count overflows.
        const oversized = resolveCalibrated(.{ .perlin = .{ .cell_size = 1 } }, .{ 0x1p32, 0x1p32 });
        try std.testing.expectError(error.SpeckleDensityOutOfRange, initResources(std.testing.failing_allocator, oversized));
    }
    const small = resolveCalibrated(.{ .perlin = base }, test_calibration);
    try std.testing.expectError(error.OutOfMemory, initResources(std.testing.failing_allocator, small));
}

test "dilute physical coverage uses continuous occupancy without density compensation" {
    const unit_plane = [2]F{ 1, 1 };
    for ([_]F{ 1e-6, 1e-4 }) |p| {
        const physical = Disk2DParams{ .coverage = p, .radius = 0.001, .occupancy = p };
        const grid = resolveCalibrated(.{ .disk = physical }, unit_plane);
        try std.testing.expectEqual(p, grid.occupancy);
        try std.testing.expectEqual(grid.radius_mean / physical.radius, grid.cells_per_uv[0]);
        try std.testing.expectEqual(grid.cells_per_uv[0], grid.cells_per_uv[1]);
        // The generator's uniform 53-bit integer variate has this exact marginal.
        // Its <=2^-53 absolute probability granularity must not materially bias C,
        // and is not fed back into the nominal radius or cell-density solve.
        const actual_occupancy = @ceil(@as(f64, p) * 0x1.0p53) * 0x1.0p-53;
        const actual_coverage = coverage.coverage(actual_occupancy, grid.radius_mean);
        try std.testing.expectApproxEqRel(@as(f64, physical.coverage), actual_coverage, if (F == f32) 2e-6 else 1e-9);
        try std.testing.expectApproxEqRel(@as(f64, physical.coverage), coverage.coverage(p, grid.radius_mean), if (F == f32) 2e-6 else 2e-12);
    }
}

test "mesh resolution calibrates reference geometry rather than UV bounding-box extent" {
    var positions = [_]F{ 0, 0, 0, 4, 0, 0, 0, 3, 0 };
    var texcoords = [_]F{ 0.2, 0.1, 0.7, 0.1, 0.2, 0.35 };
    var indices = [_]usize{ 0, 1, 2 };
    const coords = meshtypes.Coords.init(&positions, 3);
    const connect = meshtypes.Connect.init(&indices, 1, 3);
    const uvs = try NDArray(F).init(std.testing.allocator, &texcoords, &.{ 3, 2 });
    defer uvs.deinit(std.testing.allocator);
    const physical = Disk2DParams{ .coverage = 0.5, .radius = 0.1 };
    const grid = try resolveForMesh(.{ .disk = physical }, .tri3, &coords, &connect, &uvs);
    const tol: F = if (F == f32) 2e-6 else 2e-14;
    try std.testing.expectApproxEqRel(physical.radius, grid.radius_mean / grid.cells_per_uv[0] * 8, tol);
    try std.testing.expectApproxEqRel(physical.radius, grid.radius_mean / grid.cells_per_uv[1] * 12, tol);
    for (&positions) |*value| value.* *= 1000;
    var scaled = physical;
    scaled.radius *= 1000;
    const rescaled = try resolveForMesh(.{ .disk = scaled }, .tri3, &coords, &connect, &uvs);
    for (grid.cells_per_uv, rescaled.cells_per_uv) |before, after|
        try std.testing.expectApproxEqRel(before, after, tol);
    try std.testing.expectEqual(grid.radius_mean, rescaled.radius_mean);

    // An 8x12 reference extent, with physical cells of side 2, has 4x6 cells
    // per full unit UV, including when the reference coordinates use different units.
    const perlin = Perlin2DParams{
        .cell_size = 2000,
        .threshold = 0.1,
        .transition_width = 0.2,
        .seed = 7,
        .foreground = 0.17,
        .background = 0.83,
    };
    const perlin_grid = try resolveForMesh(.{ .perlin = perlin }, .tri3, &coords, &connect, &uvs);
    try std.testing.expectEqual(config.Pattern.perlin, perlin_grid.pattern);
    for ([_]F{ 4, 6 }, perlin_grid.cells_per_uv) |expected, actual|
        try std.testing.expectApproxEqRel(expected, actual, tol);
    try std.testing.expectEqual(perlin.threshold, perlin_grid.perlin_coverage_threshold);
    try std.testing.expectEqual(perlin.transition_width, perlin_grid.perlin_coverage_transition_width);
    try std.testing.expectEqual(perlin.foreground, perlin_grid.foreground);
    try std.testing.expectEqual(perlin.background, perlin_grid.background);
    try std.testing.expectEqual(perlin.seed, perlin_grid.seed);
}

test "half-radius jitter boundary preserves ratio-first jitter and softness" {
    // At R=0.3, (r*J)/R differs from r*(J/R) in both f32 and f64 for C=0.5.
    const boundary = Disk2DParams{ .coverage = 0.5, .radius = 0.3, .jitter = 0.15, .edge_softness = 0.15 };
    const disk_params = SpeckleParams{ .disk = boundary };
    try disk_params.validate();
    const disk = resolveCalibrated(disk_params, test_calibration);
    try std.testing.expectEqual(0.5 * disk.radius_mean, disk.radius_jitter);
    try std.testing.expectEqual(0.5 * disk.radius_mean, disk.edge_softness);
    const gaussian_params = SpeckleParams{ .gaussian = .{
        .coverage = boundary.coverage,
        .radius = boundary.radius,
        .jitter = boundary.jitter,
    } };
    try gaussian_params.validate();
    const blob = resolveCalibrated(gaussian_params, test_calibration);
    try std.testing.expectEqual(disk.radius_mean, blob.radius_mean);
    try std.testing.expectEqual(disk.radius_jitter, blob.radius_jitter);
    const excessive_jitter = std.math.nextAfter(F, boundary.jitter, std.math.inf(F));
    var invalid_disk = disk_params;
    var invalid_gaussian = gaussian_params;
    invalid_disk.disk.jitter = excessive_jitter;
    invalid_gaussian.gaussian.jitter = excessive_jitter;
    try std.testing.expectError(error.InvalidSpeckleJitter, invalid_disk.validate());
    try std.testing.expectError(error.InvalidSpeckleJitter, invalid_gaussian.validate());
}

test "physical support boundary checks converted rounding without clamping" {
    var rounded_over: usize = 0;
    for (0..128) |ii| {
        const radius: F = @as(F, @floatFromInt(ii + 1)) / 37;
        const softness: F = radius * (3 * @as(F, @floatFromInt(ii)) / 127);
        const limit = 1 / (1.5 + @as(f64, softness) / radius);
        const maximum = coverage.coverage(1, limit);
        var target: F = @floatCast(maximum);
        if (target > maximum) target = std.math.nextAfter(F, target, 0);
        const params = SpeckleParams{ .disk = .{
            .coverage = target,
            .radius = radius,
            .jitter = 0.5 * radius,
            .edge_softness = softness,
        } };
        try params.validate();
        const grid = resolveCalibrated(params, .{ 1, 1 });
        if (grid.radius_mean + grid.radius_jitter + grid.edge_softness > 1) {
            rounded_over += 1;
            try std.testing.expectError(error.UnsupportedSpeckleSupport, initResources(std.testing.failing_allocator, grid));
        }
        var excessive = params;
        excessive.disk.coverage = std.math.nextAfter(F, @as(F, @floatCast(maximum)), 1);
        try std.testing.expectError(error.UnsupportedSpeckleSupport, excessive.validate());
    }
    // f32 target quantization can put this entire sample set below the boundary.
    if (F == f64) try std.testing.expect(rounded_over > 0);
}
