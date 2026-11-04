// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const newton_common = @import("newton_common.zig");
const newton_scalar = @import("newton_scalar.zig");
const newton_simd = @import("newton_simd.zig");

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn solveScal(
    comptime N: usize,
    targ_x: buildconfig.F,
    targ_y: buildconfig.F,
    elem_node_x: []const buildconfig.F,
    elem_node_y: []const buildconfig.F,
    elem_node_w: []const buildconfig.F,
    xi_seed: buildconfig.F,
    eta_seed: buildconfig.F,
    node_vals: *[N]buildconfig.F,
) if (buildconfig.config.newton_solver_mode == .robust)
    newton_common.NewtonResRobustScal
else
    newton_common.NewtonResFastScal {
    if (comptime buildconfig.config.newton_solver_mode == .robust) {
        return newton_scalar.solveRobustScal(
            N,
            targ_x,
            targ_y,
            elem_node_x,
            elem_node_y,
            elem_node_w,
            xi_seed,
            eta_seed,
            node_vals,
        );
    }

    return newton_scalar.solveFastScal(
        N,
        targ_x,
        targ_y,
        elem_node_x,
        elem_node_y,
        elem_node_w,
        xi_seed,
        eta_seed,
        node_vals,
    );
}

pub fn solveSIMD(
    comptime N: usize,
    v_targ_x: buildconfig.VecSF,
    v_targ_y: buildconfig.VecSF,
    elem_node_x: []const buildconfig.F,
    elem_node_y: []const buildconfig.F,
    elem_node_w: []const buildconfig.F,
    v_xi_seed: buildconfig.VecSF,
    v_eta_seed: buildconfig.VecSF,
    v_node_vals: *[N]buildconfig.VecSF,
) if (buildconfig.config.newton_solver_mode == .robust)
    newton_common.NewtonResRobustSIMD
else
    newton_common.NewtonResFastSIMD {
    if (comptime buildconfig.config.newton_solver_mode == .robust) {
        return newton_simd.solveRobustSIMD(
            N,
            v_targ_x,
            v_targ_y,
            elem_node_x,
            elem_node_y,
            elem_node_w,
            v_xi_seed,
            v_eta_seed,
            v_node_vals,
        );
    }

    return newton_simd.solveFastSIMD(
        N,
        v_targ_x,
        v_targ_y,
        elem_node_x,
        elem_node_y,
        elem_node_w,
        v_xi_seed,
        v_eta_seed,
        v_node_vals,
    );
}

pub const reportSolve = newton_scalar.reportSolve;
pub const selectSeed = newton_common.selectSeed;
pub const isSeedFinite = newton_common.isSeedFinite;
pub const updateSeedState = newton_common.updateSeedState;
pub const applySeedReuseInPlace = newton_common.applySeedReuseInPlace;
pub const updateSeedStateFromSIMDResult = newton_common.updateSeedStateFromSIMDResult;
pub const evaluateSeedQuality = newton_common.evaluateSeedQuality;
pub const evaluateSolveState = newton_common.evaluateSolveState;
pub const calcJacDet2D = newton_common.calcJacDet2D;
pub const isConvStatus = newton_common.isConvStatus;
pub const isPreDomConvStatus = newton_common.isPreDomConvStatus;
pub const hitIterLimitStatus = newton_common.hitIterLimitStatus;
pub const statusLabel = newton_common.statusLabel;
pub const refineSeedFrozenScal = newton_scalar.refineSeedFrozenScal;
pub const FrozenJacConfig = newton_scalar.FrozenJacConfig;
pub const FrozenJacResult = newton_scalar.FrozenJacResult;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const NewtonSeed = newton_common.NewtonSeed;
pub const NewtonSeedSIMD = newton_common.NewtonSeedSIMD;
pub const NewtonSeedState = newton_common.NewtonSeedState;
pub const NewtonSeedQuality = newton_common.NewtonSeedQuality;
pub const NewtonEvalState = newton_common.NewtonEvalState;
pub const NewtonStatus = newton_common.NewtonStatus;
pub const NewtonResFastScal = newton_common.NewtonResFastScal;
pub const NewtonResRobustScal = newton_common.NewtonResRobustScal;
pub const NewtonResFastSIMD = newton_common.NewtonResFastSIMD;
pub const NewtonResRobustSIMD = newton_common.NewtonResRobustSIMD;
