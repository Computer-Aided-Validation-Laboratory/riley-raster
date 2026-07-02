// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const common = @import("newton_common.zig");
const scal = @import("newton_scalar.zig");
const simd = @import("newton_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const NewtonSeed = common.NewtonSeed;
pub const NewtonSeedSIMD = common.NewtonSeedSIMD;
pub const NewtonSeedState = common.NewtonSeedState;
pub const NewtonSeedQuality = common.NewtonSeedQuality;
pub const NewtonEvalState = common.NewtonEvalState;
pub const NewtonStatus = common.NewtonStatus;
pub const NewtonResult = common.NewtonResult;
pub const NewtonResultSIMD = common.NewtonResultSIMD;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const selectSeed = common.selectSeed;
pub const isSeedFinite = common.isSeedFinite;
pub const updateSeedState = common.updateSeedState;
pub const applySeedReuseInPlace = common.applySeedReuseInPlace;
pub const updateSeedStateFromSIMDResult = common.updateSeedStateFromSIMDResult;
pub const evaluateSeedQuality = common.evaluateSeedQuality;
pub const evaluateSolveState = common.evaluateSolveState;
pub const calcJacDet2D = common.calcJacDet2D;
pub const isConvStatus = common.isConvStatus;
pub const isPreDomConvStatus = common.isPreDomConvStatus;
pub const hitIterLimitStatus = common.hitIterLimitStatus;
pub const statusLabel = common.statusLabel;

pub const solveInv = scal.solveInv;
pub const solveInvSIMD = simd.solveInvSIMD;
pub const traceSolveInv = scal.traceSolveInv;
