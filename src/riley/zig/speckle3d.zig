// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Allocation-free procedural speckles in reference-mesh XYZ.
const std = @import("std");
const F = @import("buildconfig.zig").F;
const speckleconfig = @import("speckleconfig.zig");
const speckleops = @import("speckleops.zig");

pub const Perlin3DParams = struct {
    /// Lattice spacing in reference-mesh units. Must resolve at the mesh's distance from the origin.
    cell_size: F,
    seed: u32 = speckleconfig.default_seed,
    threshold: F = 0,
    transition_width: F = speckleconfig.default_perlin_transition_width,
    foreground: F = 0,
    background: F = 1,
};

pub const Speckle3DParams = union(enum) {
    perlin: Perlin3DParams,

    pub fn validate(self: Speckle3DParams) !void {
        const params = self.perlin;
        if (!std.math.isFinite(params.cell_size) or params.cell_size <= 0)
            return error.InvalidSpeckleCellSize;
        try speckleops.validatePerlinControls(params.threshold, params.transition_width);
        try speckleops.validateColors(params.foreground, params.background);
        try speckleops.validateColorContrast(params.foreground, params.background);
    }

    /// The caller validates parameters before preparing them.
    pub fn prepare(self: Speckle3DParams) Prepared {
        const params = self.perlin;
        return .{
            .cell_size = params.cell_size,
            .seed = params.seed,
            .threshold = params.threshold,
            .transition_width = params.transition_width,
            .background = params.background,
            .color_delta = params.foreground - params.background,
        };
    }
};

pub fn validateReferenceRange(params: Speckle3DParams, max_abs_coord: f64) !void {
    const cell_size = params.perlin.cell_size;
    if (!std.math.isFinite(cell_size) or cell_size <= 0) return error.InvalidSpeckleCellSize;

    // Leave at least two fractional bits in cell units at the renderer's coordinate precision.
    const max_abs_cell = 0.25 / std.math.floatEps(F);
    if (max_abs_coord > std.math.floatMax(F) or max_abs_coord / cell_size > max_abs_cell)
        return error.Speckle3DCoordinateRange;
}

pub const Prepared = struct {
    cell_size: F,
    seed: u32,
    threshold: F,
    transition_width: F,
    background: F,
    color_delta: F,

    /// Coordinates are in undeformed mesh units, relative to the XYZ origin.
    /// The reference-coordinate range must have passed `validateReferenceRange`.
    pub fn sample(self: *const Prepared, coords: [3]F) F {
        const x = splitAxis(coords[0], self.cell_size, 0x9e3779b185ebca87);
        const y = splitAxis(coords[1], self.cell_size, 0xc2b2ae3d27d4eb4f);
        const z = splitAxis(coords[2], self.cell_size, 0x165667b19e3779f9);
        const seed: u64 = self.seed;
        const dx = x.frac - 1;
        const dy = y.frac - 1;
        const dz = z.frac - 1;
        const fx = fade(x.frac);
        const fy = fade(y.frac);
        const fz = fade(z.frac);

        const n000 = gradientDot(seed ^ x.lo ^ y.lo ^ z.lo, x.frac, y.frac, z.frac);
        const n100 = gradientDot(seed ^ x.hi ^ y.lo ^ z.lo, dx, y.frac, z.frac);
        const n010 = gradientDot(seed ^ x.lo ^ y.hi ^ z.lo, x.frac, dy, z.frac);
        const n110 = gradientDot(seed ^ x.hi ^ y.hi ^ z.lo, dx, dy, z.frac);
        const n001 = gradientDot(seed ^ x.lo ^ y.lo ^ z.hi, x.frac, y.frac, dz);
        const n101 = gradientDot(seed ^ x.hi ^ y.lo ^ z.hi, dx, y.frac, dz);
        const n011 = gradientDot(seed ^ x.lo ^ y.hi ^ z.hi, x.frac, dy, dz);
        const n111 = gradientDot(seed ^ x.hi ^ y.hi ^ z.hi, dx, dy, dz);
        const nz0 = lerp(lerp(n000, n100, fx), lerp(n010, n110, fx), fy);
        const nz1 = lerp(lerp(n001, n101, fx), lerp(n011, n111, fx), fy);
        const noise = lerp(nz0, nz1, fz) * @sqrt(@as(F, 0.5));

        const coverage: F = if (self.transition_width == 0)
            @floatFromInt(@intFromBool(noise >= self.threshold))
        else blk: {
            const t = @min(1, @max(0, (noise - self.threshold) / self.transition_width + 0.5));
            break :blk t * t * (3 - 2 * t);
        };
        return self.background + coverage * self.color_delta;
    }
};

const Axis = struct { frac: F, lo: u64, hi: u64 };

fn splitAxis(coord: F, cell_size: F, prime: u64) Axis {
    const scaled = @as(f64, coord) / @as(f64, cell_size);
    std.debug.assert(std.math.isFinite(scaled));
    const cell = @floor(scaled);
    return .{
        .frac = @floatCast(scaled - cell),
        .lo = latticeKey(cell) *% prime,
        .hi = latticeKey(cell + 1) *% prime,
    };
}

fn latticeKey(cell: f64) u64 {
    const bits: u64 = @bitCast(if (cell == 0) @as(f64, 0) else cell);
    // Move the sign into the low bit so two negative axes do not cancel under XOR.
    return std.math.rotl(u64, bits, 1);
}

fn gradientDot(key: u64, x: F, y: F, z: F) F {
    // SplitMix64 finalizer; choose among the twelve signed cube-edge directions.
    var bits = (key ^ (key >> 30)) *% 0xbf58476d1ce4e5b9;
    bits = (bits ^ (bits >> 27)) *% 0x94d049bb133111eb;
    const id = (bits ^ (bits >> 31)) % 12;
    const u = if (id < 8) x else y;
    const v = if (id < 4) y else z;
    return (if (id & 1 == 0) u else -u) + (if (id & 2 == 0) v else -v);
}

fn fade(t: F) F {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

fn lerp(a: F, b: F, t: F) F {
    return a + t * (b - a);
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "3D Perlin matches signed cell midpoint references for different Z and seeds" {
    const cases = [_]struct { seed: u32, z: F, twice_dot_sum: F }{
        .{ .seed = 7, .z = -1, .twice_dot_sum = -6 },
        .{ .seed = 7, .z = 1, .twice_dot_sum = 2 },
        .{ .seed = 8, .z = -1, .twice_dot_sum = 2 },
    };
    for (cases) |case| {
        var params = Speckle3DParams{ .perlin = .{
            .cell_size = 2,
            .seed = case.seed,
            .transition_width = 1,
            .foreground = 1,
            .background = 0,
        } };
        const prepared = params.prepare();
        const coords = [3]F{ -1, 1, case.z };
        // Independently summed signed gradient dots. At a midpoint every corner
        // has weight 1/8, with displacements +/-1/2 and unit-diagonal gradients.
        const noise = case.twice_dot_sum / (16 * @sqrt(@as(F, 2)));
        // Smoothstep on [noise + 1/2] in terms of centered noise.
        const expected = 0.5 + 1.5 * noise - 2 * noise * noise * noise;
        const actual = prepared.sample(coords);
        try std.testing.expectApproxEqAbs(expected, actual, 4 * std.math.floatEps(F));
        _ = prepared.sample(.{ 0, 0, 0 });
        try std.testing.expectEqual(actual, prepared.sample(coords));
        params.perlin.cell_size = 1;
        try std.testing.expectEqual(actual, params.prepare().sample(.{ -0.5, 0.5, case.z * 0.5 }));
    }
}

test "3D Perlin is continuous with a continuous slope across negative and zero faces" {
    const prepared = (Speckle3DParams{ .perlin = .{
        .cell_size = 1,
        .transition_width = 2,
    } }).prepare();
    const step: F = 0x1p-10;
    for (0..3) |axis| {
        for ([_]F{ -2, 0, 2 }) |face| {
            var coords = [3]F{ -0.375, 0.25, -0.625 };
            coords[axis] = face;
            const center = prepared.sample(coords);
            if (face == 0) {
                coords[axis] = -0.0;
                try std.testing.expectEqual(center, prepared.sample(coords));
            }
            coords[axis] = face - step;
            const left = prepared.sample(coords);
            coords[axis] = face + step;
            const right = prepared.sample(coords);
            try std.testing.expectApproxEqAbs(center, left, step);
            try std.testing.expectApproxEqAbs(center, right, step);
            try std.testing.expectApproxEqAbs(center - left, right - center, 2 * step * step);
        }
    }
}

test "3D Perlin transition and colors at analytic zero-noise vertices" {
    var params = Speckle3DParams{ .perlin = .{
        .cell_size = 0.5,
        .foreground = 0.875,
        .background = 0.125,
        .transition_width = 1,
    } };
    // Gradient noise is zero at every vertex, including beyond signed integer range.
    const corner = [3]F{ -1.5, 1, 0x1p70 };
    try std.testing.expectEqual(@as(F, 0.5), params.prepare().sample(corner));
    params.perlin.threshold = 0.25;
    try std.testing.expectEqual(@as(F, 0.2421875), params.prepare().sample(corner));
    params.perlin.threshold = 0.5;
    try std.testing.expectEqual(params.perlin.background, params.prepare().sample(corner));
    params.perlin.threshold = -0.5;
    try std.testing.expectEqual(params.perlin.foreground, params.prepare().sample(corner));
    params.perlin.transition_width = 0;
    params.perlin.threshold = 0;
    try std.testing.expectEqual(params.perlin.foreground, params.prepare().sample(corner));
    params.perlin.threshold = 0.25;
    try std.testing.expectEqual(params.perlin.background, params.prepare().sample(corner));
}

test "3D Perlin validates every control error" {
    const valid = Speckle3DParams{ .perlin = .{ .cell_size = 1 } };
    try valid.validate();
    const cases = .{
        .{ "cell_size", 0, error.InvalidSpeckleCellSize },
        .{ "cell_size", std.math.inf(F), error.InvalidSpeckleCellSize },
        .{ "threshold", std.math.nan(F), error.InvalidSpecklePerlinThreshold },
        .{ "transition_width", -0.1, error.InvalidSpecklePerlinTransitionWidth },
        .{ "transition_width", std.math.inf(F), error.InvalidSpecklePerlinTransitionWidth },
        .{ "foreground", -1, error.InvalidSpeckleForeground },
        .{ "background", 2, error.InvalidSpeckleBackground },
        .{ "foreground", 1, error.SpeckleColorsMustDiffer },
    };
    inline for (cases) |case| {
        var params = valid;
        @field(params.perlin, case[0]) = case[1];
        try std.testing.expectError(case[2], params.validate());
    }
}
