// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const common = @import("cameramodels_common.zig");
const simd = @import("cameramodels_simd.zig");

pub const DistortionModel = common.DistortionModel;
pub const BrownConrady = common.BrownConrady;
pub const BrownConradyExt = common.BrownConradyExt;
pub const PolynomialOrder = common.PolynomialOrder;
pub const PolynomialMap = common.PolynomialMap;
pub const BidirectionalPolynomial = common.BidirectionalPolynomial;
pub const BrownConradyPolynomial = common.BrownConradyPolynomial;
pub const BrownConradyExtPolynomial = common.BrownConradyExtPolynomial;
pub const DistortionInverseResult = common.DistortionInverseResult;
pub const DistortionForwardJacResult = common.DistortionForwardJacResult;

pub const SeparablePSF = common.SeparablePSF;
pub const PixelBoxPSF = common.PixelBoxPSF;
pub const GaussianPSF = common.GaussianPSF;
pub const AnisotropicGaussianPSF = common.AnisotropicGaussianPSF;
pub const PointSpreadFunc = common.PointSpreadFunc;
pub const PreparedPSFMode = common.PreparedPSFMode;
pub const PreparedPSF = common.PreparedPSF;
pub const preparePSF = common.preparePSF;
pub const forwardDistortionScalar = common.forwardDistortionScalar;
pub const forwardDistortionWithJacScalar = common.forwardDistortionWithJacScalar;
pub const inverseDistortionScalar = common.inverseDistortionScalar;
pub const forwardDistortionModelScalar = common.forwardDistortionModelScalar;
pub const inverseDistortionModelScalar = common.inverseDistortionModelScalar;

pub const DistortionForwardJacSIMDResult = simd.DistortionForwardJacSIMDResult;
pub const forwardDistortionSIMD = simd.forwardDistortionSIMD;
pub const forwardDistortionWithJacSIMD = simd.forwardDistortionWithJacSIMD;
pub const inverseDistortionSIMD = simd.inverseDistortionSIMD;
pub const inverseDistortionModelSIMD = simd.inverseDistortionModelSIMD;
