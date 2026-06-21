// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const common = @import("newton_common.zig");
const scalar = @import("newton_scalar.zig");
const simd = @import("newton_simd.zig");

pub const NewtonSeed = common.NewtonSeed;
pub const NewtonSeedSIMD = common.NewtonSeedSIMD;
pub const NewtonSeedState = common.NewtonSeedState;
pub const NewtonSeedQuality = common.NewtonSeedQuality;
pub const NewtonResult = common.NewtonResult;
pub const NewtonResultSIMD = common.NewtonResultSIMD;

pub const selectSeed = common.selectSeed;
pub const isSeedFinite = common.isSeedFinite;
pub const updateSeedState = common.updateSeedState;
pub const applySeedReuseInPlace = common.applySeedReuseInPlace;
pub const updateSeedStateFromSIMDResult = common.updateSeedStateFromSIMDResult;
pub const evaluateSeedQuality = common.evaluateSeedQuality;
pub const calcJacobianDet2D = common.calcJacobianDet2D;

pub const solveInverse = scalar.solveInverse;
pub const solveInverseSIMD = simd.solveInverseSIMD;

test "calcJacobianDet2D regular elements" {
    const testing = std.testing;
    const det_tol: F = if (F == f32) 1e-4 else 1e-9;
    const quad_det_tol: F = if (F == f32) 1e-4 else 1e-12;

    const tri_x = [_]F{ 0.0, 10.0, 5.0 };
    const tri_y = [_]F{ 0.0, 0.0, 8.660254037844386 };
    const tri_det = calcJacobianDet2D(3, 0.2, 0.3, &tri_x, &tri_y);
    try testing.expectApproxEqAbs(86.60254037844386, tri_det, det_tol);

    const quad_x = [_]F{ 0.0, 10.0, 10.0, 0.0 };
    const quad_y = [_]F{ 0.0, 0.0, 10.0, 10.0 };
    const quad_det = calcJacobianDet2D(4, 0.0, 0.0, &quad_x, &quad_y);
    try testing.expectApproxEqAbs(25.0, quad_det, quad_det_tol);
}
