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

pub const BrownConrady = common.BrownConrady;
pub const BrownConradyParams = common.BrownConradyParams;
pub const BrownConradyExt = common.BrownConradyExt;
pub const BrownConradyExtParams = common.BrownConradyExtParams;
pub const DistortionCoords = common.DistortionCoords;
pub const DistortionForwardJacResult = common.DistortionForwardJacResult;

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

pub const PolynomialOrder = common.PolynomialOrder;
pub const PolynomialMap = common.PolynomialMap;
pub const BidirectionalPolynomial = common.BidirectionalPolynomial;
pub const BrownConradyPolynomial = common.BrownConradyPolynomial;
pub const BrownConradyExtPolynomial = common.BrownConradyExtPolynomial;
pub const BrownConradyExtPolynomialParams = common.BrownConradyExtPolynomialParams;

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortionModel = common.DistortionModel;
pub const DistortionParams = common.DistortionParams;
pub const initDistortionModel = common.initDistortionModel;
pub const distortionParamsFromModel = common.distortionParamsFromModel;
pub const forwardDistortionModelScal = scal.forwardDistortionModel;
pub const invDistortionModelScal = scal.invDistortionModel;
pub const DistortionForwardJacSIMDResult = simd.DistortionForwardJacSIMDResult;
pub const DistortionCoordsSIMD = simd.DistortionCoordsSIMD;
pub const BrownConradySIMD = simd.BrownConradySIMD;
pub const BrownConradyExtSIMD = simd.BrownConradyExtSIMD;
pub const PolynomialMapSIMD = simd.PolynomialMapSIMD;
pub const BidirectionalPolynomialSIMD = simd.BidirectionalPolynomialSIMD;
pub const forwardDistortionSIMD = simd.forwardDistortionSIMD;
pub const forwardDistortionWithJacSIMD = simd.forwardDistortionWithJacSIMD;
pub const invDistortionSIMD = simd.invDistortionSIMD;
pub const forwardDistortionModelSIMD = simd.forwardDistortionModelSIMD;
pub const invDistortionModelSIMD = simd.invDistortionModelSIMD;

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
