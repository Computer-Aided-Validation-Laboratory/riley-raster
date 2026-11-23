// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Nominal Bernoulli-grid support coverage; see dev/THEORY.md for the model.
//! Independent reference checks use a 1e-6 absolute coverage tolerance.
//! Ordinary builds import constants; scripts/generate_speckle_coverage.py is offline.
const std = @import("std");
const table = @import("specklecoveragecoeffs.zig").coefficients;
const pi = std.math.pi;
const intervals = table.len - 1;

/// Lower an already validated nominal request, without a second feasibility check.
/// Returns a normalized radius in (0, 1]; the nominal cap maps to exactly 1.
pub fn radiusForValidatedCoverage(target: f64, occupancy: f64) f64 {
    std.debug.assert(target > 0 and target < 1 and occupancy > 0 and occupancy <= 1);

    // Scale the initial bracket with the dilute estimate so even very thin coverage
    // retains relative radius accuracy. Since F >= 1-exp(-p*pi*r*r), four times the
    // dilute radius is a conservative upper bracket (capped by the feasible r = 1).
    var lo: f64 = 0;
    var hi = @min(1.0, 4 * @sqrt(target / occupancy) / @sqrt(pi));
    for (0..64) |_| {
        const mid = lo + (hi - lo) * 0.5;
        if (mid == lo or mid == hi) break;
        if (coverage(occupancy, mid) <= target) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo + (hi - lo) * 0.5;
}

/// Validate nominal range and attainability without inversion.
pub fn validateRequest(target: f64, occupancy: f64) Error!void {
    if (!std.math.isFinite(target) or target <= 0 or target >= 1)
        return error.InvalidSpeckleCoverage;
    if (!std.math.isFinite(occupancy) or occupancy <= 0 or occupancy > 1)
        return error.InvalidSpeckleOccupancy;
    const maximum = coverage(occupancy, 1);
    if (target > maximum) return error.UnattainableSpeckleCoverage;
}

/// Expected fraction covered; no allocation or I/O. Low-level checked-by-caller API:
/// occupancy and radius must be finite and in [0, 1] (asserted in safe builds).
/// Zero occupancy/radius are allowed here for references and metrics, not inversion.
pub fn coverage(occupancy: f64, radius: f64) f64 {
    std.debug.assert(occupancy >= 0 and occupancy <= 1);
    std.debug.assert(radius >= 0 and radius <= 1);

    if (occupancy == 0 or radius == 0) return 0;
    if (radius <= 0.5) {
        const r2 = radius * radius;
        const r3 = r2 * radius;
        const r6 = r3 * r3;
        const c3 = 68.0 / 27.0 + pi * pi / 192.0;
        const c4 = -(3.0 * pi * pi * pi / 256.0 - 421.0 * pi / 17280.0);
        // Factoring p*r*r preserves dilute coverage without subtracting from one.
        const normalized = pi + occupancy * r3 * (-256.0 / 45.0 + pi / 2.0 * radius) +
            occupancy * occupancy * r6 * (c3 + occupancy * r2 * c4);
        return (occupancy * radius) * radius * normalized;
    }

    const u = (radius - 0.5) * (2 * intervals);
    const ii: usize = @min(@as(usize, @intFromFloat(u)), intervals - 1);
    const t = u - @as(f64, @floatFromInt(ii));
    const left_value = nodeValue(occupancy, ii);
    const right_value = nodeValue(occupancy, ii + 1);
    const delta = right_value - left_value;
    const before = if (ii > 0) left_value - nodeValue(occupancy, ii - 1) else 0;
    const after = if (ii < intervals - 1) nodeValue(occupancy, ii + 2) - right_value else 0;
    const left_slope = if (ii == 0)
        @max(0, @min(3 * delta, (3 * delta - after) * 0.5))
    else
        slope(before, delta);
    const right_slope = if (ii == intervals - 1)
        @max(0, @min(3 * delta, (3 * delta - before) * 0.5))
    else
        slope(delta, after);

    // PCHIP of F/p, not coefficients; slopes use unit table-index spacing.
    const value = left_value + t * (left_slope + t *
        (3 * delta - 2 * left_slope - right_slope +
            t * (left_slope + right_slope - 2 * delta)));
    return occupancy * value;
}

pub const Error = error{
    InvalidSpeckleCoverage,
    InvalidSpeckleOccupancy,
    UnattainableSpeckleCoverage,
};

/// F/p at a table node; removing the outer occupancy factor also keeps interpolation
/// slopes well-scaled for tiny occupancies. The exact first coefficient is not stored.
fn nodeValue(occupancy: f64, index: usize) f64 {
    const row = table[index];
    var value = row[7];
    var kk: usize = 7;
    while (kk > 0) {
        kk -= 1;
        value = value * occupancy + row[kk];
    }
    const radius = 0.5 + @as(f64, @floatFromInt(index)) / (2 * intervals);
    return pi * radius * radius + occupancy * value;
}

fn slope(before: f64, after: f64) f64 {
    std.debug.assert(before > 0 and after > 0);
    return 2 * before * after / (before + after);
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------
test "coverage request excludes zero and one and accepts exactly the attainable maximum" {
    for ([_]f64{ -0.1, 0, 1, 1.1, std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64) }) |invalid| {
        try std.testing.expectError(error.InvalidSpeckleCoverage, validateRequest(invalid, 1));
    }
    for ([_]f64{ -0.1, 0, 1.1, std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64) }) |invalid| {
        try std.testing.expectError(error.InvalidSpeckleOccupancy, validateRequest(0.5, invalid));
    }
    for ([_]f64{ 1e-8, 0.1, 0.5, 1 }) |occupancy| {
        const maximum = coverage(occupancy, 1);
        try validateRequest(maximum, occupancy);
        try std.testing.expectEqual(@as(f64, 1), radiusForValidatedCoverage(maximum, occupancy));
        try std.testing.expectError(error.UnattainableSpeckleCoverage, validateRequest(
            std.math.nextAfter(f64, maximum, std.math.inf(f64)),
            occupancy,
        ));
    }
}

test "analytic low radius and independently integrated maximum" {
    try std.testing.expectEqual(@as(f64, 0), coverage(0, 1));
    try std.testing.expectEqual(@as(f64, 0), coverage(1, 0));
    try std.testing.expectApproxEqAbs(@as(f64, 0.641922746182372), coverage(1, 0.5), 2e-15);
    // Higher-order direct-probability quadrature with independent vertical-slice areas.
    try std.testing.expectApproxEqAbs(@as(f64, 0.999498286229077), coverage(1, 1), 2e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4247368), radiusForValidatedCoverage(0.5, 1), 1e-7);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6175762), radiusForValidatedCoverage(0.5, 0.5), 1e-7);
    try std.testing.expect(@abs(coverage(1, 0.5) - (1 - @exp(-pi * 0.25))) > 0.09);
}

test "eight independent coverage and inverse references with f32 and f64 input quantization" {
    // Vertical-slice circle/rectangle areas (atan2 primitive), direct probabilities,
    // 1536 Gauss nodes per axis; 1024/1536 convergence differs by at most 5.9e-10.
    // Reproduce with reference_coverages in scripts/tests/test_speckle_coverage.py;
    // these values never evaluate the coefficient table or occupancy polynomial.
    const Reference = struct { occupancy: f64, radius: f64, expected: f64 };
    const references = [_]Reference{
        .{ .occupancy = 1, .radius = 0.5009765625, .expected = 0.64369224042378459 },
        .{ .occupancy = 1, .radius = 0.501953125, .expected = 0.64545898675764135 },
        .{ .occupancy = 1, .radius = 0.5029296875, .expected = 0.64722295153685372 },
        .{ .occupancy = 0.5, .radius = 0.7060546875, .expected = 0.60340423642153784 },
        .{ .occupancy = 1, .radius = 0.70703125, .expected = 0.91995749570045049 },
        .{ .occupancy = 1, .radius = 0.70710678118654746, .expected = 0.92001709394488895 },
        .{ .occupancy = 1, .radius = 0.7080078125, .expected = 0.9207257362154011 },
        .{ .occupancy = 0.5, .radius = 0.998046875, .expected = 0.85535305682530061 },
    };
    inline for (.{ f32, f64 }) |CallerFloat| {
        for (references) |reference| {
            const occupancy: CallerFloat = @floatCast(reference.occupancy);
            const radius: CallerFloat = @floatCast(reference.radius);
            const target: CallerFloat = @floatCast(reference.expected);
            const actual = coverage(occupancy, radius);
            const solved = radiusForValidatedCoverage(target, occupancy);
            try std.testing.expectApproxEqAbs(reference.expected, actual, 1e-6);
            try std.testing.expectApproxEqAbs(reference.radius, solved, 1e-6);
            try std.testing.expectApproxEqAbs(@as(f64, target), coverage(occupancy, solved), 2e-15);
        }
    }
}

test "coverage stays monotone across nodes and geometry breaks" {
    for ([_]f64{ 1e-12, 1e-8, 0.001, 0.01, 0.1, 0.25, 0.5, 0.75, 1 }) |occupancy| {
        var previous: f64 = 0;
        for (0..16385) |ii| {
            const radius = @as(f64, @floatFromInt(ii)) / 16384;
            const value = coverage(occupancy, radius);
            try std.testing.expect(value >= previous and value >= 0 and value <= 1);
            previous = value;
        }
        for ([_]f64{ 0.5, 1 / @sqrt(@as(f64, 2)), 1 }) |radius| {
            const below = std.math.nextAfter(f64, radius, 0);
            try std.testing.expect(coverage(occupancy, below) <= coverage(occupancy, radius) + 2e-15);
            try std.testing.expectApproxEqAbs(coverage(occupancy, below), coverage(occupancy, radius), 3e-15);
            if (radius < 1) {
                const above = std.math.nextAfter(f64, radius, std.math.inf(f64));
                try std.testing.expectApproxEqAbs(coverage(occupancy, radius), coverage(occupancy, above), 3e-15);
            }
        }
    }
}

test "inverse round trips including thin coverage and near maximum" {
    for ([_]f64{ 1e-12, 1e-8, 0.001, 0.1, 0.5, 1 }) |occupancy| {
        for ([_]f64{ 1e-140, 1e-8, 0.01, 0.25, 0.5, 0.50000001, 0.7071067811865475, 0.9, 0.99999, 1 }) |radius| {
            const target = coverage(occupancy, radius);
            const actual = radiusForValidatedCoverage(target, occupancy);
            try std.testing.expectApproxEqRel(radius, actual, 1e-10);
            try std.testing.expectApproxEqRel(target, coverage(occupancy, actual), 1e-13);
        }
    }
    const thin_target: f64 = 1e-300;
    const radius = radiusForValidatedCoverage(thin_target, 1);
    try std.testing.expectApproxEqRel(thin_target, coverage(1, radius), 2e-15);
}
