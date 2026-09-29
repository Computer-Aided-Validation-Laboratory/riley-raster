// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const common = @import("camera_common.zig");
const cm = @import("cameramodels.zig");
const camera_scalar = @import("camera_scalar.zig");
const camera_simd = @import("camera_simd.zig");

const cfg = buildconfig.config;
const F = cfg.precision;
const camera_impl = if (cfg.simd == .on) camera_simd else camera_scalar;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const DistortModel = cm.DistortModel;
pub const DistortParams = cm.DistortParams;
pub const BrownCon = cm.BrownCon;
pub const BrownConExt = cm.BrownConExt;
pub const BrownConParams = cm.BrownConParams;
pub const BrownConExtParams = cm.BrownConExtParams;
pub const DistortCoords = cm.DistortCoords;
pub const PolyMode = cm.PolyMode;
pub const polyTermCount = cm.polyTermCount;
pub const POLY_MAX_DEGREE = cm.POLY_MAX_DEGREE;
pub const PolyMap = cm.PolyMap;
pub const BrownConPoly = cm.BrownConPoly;
pub const BrownConExtPoly = cm.BrownConExtPoly;
pub const BrownConExtPolyParams = cm.BrownConExtPolyParams;
pub const DistortFordJacResult = cm.DistortFordJacResult;
pub const fordDistortModelScal = cm.fordDistortModelScal;
pub const invDistortModelScal = cm.invDistortModelScal;
pub const fordDistortSIMD = cm.fordDistortSIMD;
pub const fordDistortWithJacSIMD = cm.fordDistortWithJacSIMD;
pub const invDistortSIMD = cm.invDistortSIMD;
pub const fordDistortModelSIMD = cm.fordDistortModelSIMD;
pub const invDistortModelSIMD = cm.invDistortModelSIMD;
pub const SeparablePSF = cm.SeparablePSF;
pub const PixelBoxPSF = cm.PixelBoxPSF;
pub const GaussianPSF = cm.GaussianPSF;
pub const AnisotropicGaussianPSF = cm.AnisotropicGaussianPSF;
pub const PointSpreadFunc = cm.PointSpreadFunc;
pub const PreparedPSFMode = cm.PreparedPSFMode;
pub const PreparedPSF = cm.PreparedPSF;

pub const CameraCoordSys = common.CameraCoordSys;
pub const SubPixelCenterMap = common.SubPixelCenterMap;
pub const CameraInput = common.CameraInput;
pub const StereoPairInput = common.StereoPairInput;
pub const FOVScaling = common.FOVScaling;

pub const CameraPrepared = camera_impl.CameraPrepared;
pub const allCamerasSharePixels = common.allCamerasSharePixels;
pub const isNoDistort = common.isNoDistort;
pub const calcPixelCenterCoord = common.calcPixelCenterCoord;
pub const storeIdealPairScratch = common.storeIdealPairScratch;
pub const getIdealXPlaneScratch = common.getIdealXPlaneScratch;
pub const getIdealYPlaneScratch = common.getIdealYPlaneScratch;
