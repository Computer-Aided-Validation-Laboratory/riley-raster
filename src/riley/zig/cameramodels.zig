// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const common = @import("cameramodels_common.zig");
const scal = @import("cameramodels_scalar.zig");
const simd = @import("cameramodels_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------
// Brown Conrady
// --------------------------------------------------------------------------------------

pub const BrownCon = common.BrownCon;
pub const BrownConParams = common.BrownConParams;
pub const BrownConExt = common.BrownConExt;
pub const BrownConExtParams = common.BrownConExtParams;
pub const DistortCoords = common.DistortCoords;
pub const DistortFordJacResult = common.DistortFordJacResult;

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

pub const PolyOrder = common.PolyOrder;
pub const PolyMap = common.PolyMap;
pub const BrownConPoly = common.BrownConPoly;
pub const BrownConExtPoly = common.BrownConExtPoly;
pub const BrownConExtPolyParams = common.BrownConExtPolyParams;

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortModel = common.DistortModel;
pub const DistortParams = common.DistortParams;
pub const fordDistortModelScal = scal.fordDistortModel;
pub const invDistortModelScal = scal.invDistortModel;
pub const DistortFordJacSIMDResult = simd.DistortFordJacSIMDResult;
pub const DistortCoordsSIMD = simd.DistortCoordsSIMD;
pub const BrownConSIMD = simd.BrownConSIMD;
pub const BrownConExtSIMD = simd.BrownConExtSIMD;
pub const PolyMapSIMD = simd.PolyMapSIMD;
pub const fordDistortSIMD = simd.fordDistortSIMD;
pub const fordDistortWithJacSIMD = simd.fordDistortWithJacSIMD;
pub const invDistortSIMD = simd.invDistortSIMD;
pub const fordDistortModelSIMD = simd.fordDistortModelSIMD;
pub const invDistortModelSIMD = simd.invDistortModelSIMD;

// --------------------------------------------------------------------------------------
// Point Spread Func
// --------------------------------------------------------------------------------------

pub const SeparablePSF = common.SeparablePSF;
pub const PixelBoxPSF = common.PixelBoxPSF;
pub const GaussianPSF = common.GaussianPSF;
pub const AnisotropicGaussianPSF = common.AnisotropicGaussianPSF;
pub const PointSpreadFunc = common.PointSpreadFunc;
pub const PreparedPSFMode = common.PreparedPSFMode;
pub const PreparedPSF = common.PreparedPSF;
pub const preparePSF = common.preparePSF;
