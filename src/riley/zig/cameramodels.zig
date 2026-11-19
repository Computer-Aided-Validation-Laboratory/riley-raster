// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cameramodels_common = @import("cameramodels_common.zig");
const cameramodels_scalar = @import("cameramodels_scalar.zig");
const cameramodels_simd = @import("cameramodels_simd.zig");

// --------------------------------------------------------------------------------------
// Brown Conrady
// --------------------------------------------------------------------------------------

pub const BrownCon = cameramodels_common.BrownCon;
pub const BrownConParams = cameramodels_common.BrownConParams;
pub const BrownConExt = cameramodels_common.BrownConExt;
pub const BrownConExtParams = cameramodels_common.BrownConExtParams;
pub const DistortCoords = cameramodels_common.DistortCoords;
pub const DistortFordJacResult = cameramodels_common.DistortFordJacResult;

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

pub const PolyMode = cameramodels_common.PolyMode;
pub const polyTermCount = cameramodels_common.polyTermCount;
pub const POLY_MAX_DEGREE = cameramodels_common.POLY_MAX_DEGREE;
pub const PolyMap = cameramodels_common.PolyMap;
pub const BrownConPoly = cameramodels_common.BrownConPoly;
pub const BrownConExtPoly = cameramodels_common.BrownConExtPoly;
pub const BrownConExtPolyParams = cameramodels_common.BrownConExtPolyParams;

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortModel = cameramodels_common.DistortModel;
pub const DistortParams = cameramodels_common.DistortParams;
pub const fordDistortModelScal = cameramodels_scalar.fordDistortModel;
pub const invDistortModelScal = cameramodels_scalar.invDistortModel;
pub const DistortFordJacSIMDResult = cameramodels_simd.DistortFordJacSIMDResult;
pub const DistortCoordsSIMD = cameramodels_simd.DistortCoordsSIMD;
pub const BrownConSIMD = cameramodels_simd.BrownConSIMD;
pub const BrownConExtSIMD = cameramodels_simd.BrownConExtSIMD;
pub const PolyMapSIMD = cameramodels_simd.PolyMapSIMD;
pub const fordDistortSIMD = cameramodels_simd.fordDistortSIMD;
pub const fordDistortWithJacSIMD = cameramodels_simd.fordDistortWithJacSIMD;
pub const invDistortSIMD = cameramodels_simd.invDistortSIMD;
pub const fordDistortModelSIMD = cameramodels_simd.fordDistortModelSIMD;
pub const invDistortModelSIMD = cameramodels_simd.invDistortModelSIMD;

// --------------------------------------------------------------------------------------
// Point Spread Func
// --------------------------------------------------------------------------------------

pub const SeparablePSF = cameramodels_common.SeparablePSF;
pub const PixelBoxPSF = cameramodels_common.PixelBoxPSF;
pub const GaussianPSF = cameramodels_common.GaussianPSF;
pub const AnisotropicGaussianPSF = cameramodels_common.AnisotropicGaussianPSF;
pub const PointSpreadFunc = cameramodels_common.PointSpreadFunc;
pub const PreparedPSFMode = cameramodels_common.PreparedPSFMode;
pub const PreparedPSF = cameramodels_common.PreparedPSF;
pub const preparePSF = cameramodels_common.preparePSF;
