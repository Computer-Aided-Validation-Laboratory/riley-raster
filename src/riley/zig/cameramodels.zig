// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const common = @import("cameramodels_common.zig");
const scalar = @import("cameramodels_scalar.zig");
const simd = @import("cameramodels_simd.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------
// Brown Conrady
// --------------------------------------------------------------------------------------

pub const BrownConrady = common.BrownConrady;
pub const BrownConradyExt = common.BrownConradyExt;
pub const DistortionInverseResult = common.DistortionInverseResult;
pub const DistortionForwardJacResult = common.DistortionForwardJacResult;

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

pub const PolynomialOrder = common.PolynomialOrder;
pub const PolynomialMap = common.PolynomialMap;
pub const BidirectionalPolynomial = common.BidirectionalPolynomial;
pub const BrownConradyPolynomial = common.BrownConradyPolynomial;
pub const BrownConradyExtPolynomial = common.BrownConradyExtPolynomial;

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortionModel = common.DistortionModel;
pub const forwardDistortionModelScalar = scalar.forwardDistortionModel;
pub const inverseDistortionModelScalar = scalar.inverseDistortionModel;
pub const DistortionForwardJacSIMDResult = simd.DistortionForwardJacSIMDResult;
pub const forwardDistortionSIMD = simd.forwardDistortionSIMD;
pub const forwardDistortionWithJacSIMD = simd.forwardDistortionWithJacSIMD;
pub const inverseDistortionSIMD = simd.inverseDistortionSIMD;
pub const inverseDistortionModelSIMD = simd.inverseDistortionModelSIMD;

// --------------------------------------------------------------------------------------
// Point Spread Functions
// --------------------------------------------------------------------------------------

pub const SeparablePSF = common.SeparablePSF;
pub const PixelBoxPSF = common.PixelBoxPSF;
pub const GaussianPSF = common.GaussianPSF;
pub const AnisotropicGaussianPSF = common.AnisotropicGaussianPSF;
pub const PointSpreadFunc = common.PointSpreadFunc;
pub const PreparedPSFMode = common.PreparedPSFMode;
pub const PreparedPSF = common.PreparedPSF;
pub const preparePSF = common.preparePSF;
