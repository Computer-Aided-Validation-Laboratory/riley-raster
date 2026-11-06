// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cameratypes = @import("cameratypes.zig");
const buildconfig = @import("buildconfig.zig");
const cameraprojops_common = @import("cameraprojops_common.zig");
const cameraprojops_scalar = @import("cameraprojops_scalar.zig");
const cameraprojops_simd = @import("cameraprojops_simd.zig");

const cfg = buildconfig.config;
const F = cfg.precision;
const camera_impl = if (cfg.simd == .on) cameraprojops_simd else cameraprojops_scalar;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const CameraPrepared = camera_impl.CameraPrepared;
pub const allCamerasSharePixels = cameraprojops_common.allCamerasSharePixels;
pub const isNoDistort = cameratypes.isNoDistort;
pub const calcPixelCenterCoord = cameraprojops_common.calcPixelCenterCoord;
pub const storeIdealPairScratch = cameraprojops_common.storeIdealPairScratch;
pub const getIdealXPlaneScratch = cameraprojops_common.getIdealXPlaneScratch;
pub const getIdealYPlaneScratch = cameraprojops_common.getIdealYPlaneScratch;
