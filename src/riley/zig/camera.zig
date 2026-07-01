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

pub const DistortionModel = cm.DistortionModel;
pub const BrownConrady = cm.BrownConrady;
pub const BrownConradyExt = cm.BrownConradyExt;
pub const PolynomialOrder = cm.PolynomialOrder;
pub const PolynomialMap = cm.PolynomialMap;
pub const BidirectionalPolynomial = cm.BidirectionalPolynomial;
pub const BrownConradyPolynomial = cm.BrownConradyPolynomial;
pub const BrownConradyExtPolynomial = cm.BrownConradyExtPolynomial;
pub const DistortionInverseResult = cm.DistortionInverseResult;
pub const DistortionForwardJacResult = cm.DistortionForwardJacResult;
pub const forwardDistortionModelScalar = cm.forwardDistortionModelScalar;
pub const inverseDistortionModelScalar = cm.inverseDistortionModelScalar;
pub const forwardDistortionSIMD = cm.forwardDistortionSIMD;
pub const forwardDistortionWithJacSIMD = cm.forwardDistortionWithJacSIMD;
pub const inverseDistortionSIMD = cm.inverseDistortionSIMD;
pub const inverseDistortionModelSIMD = cm.inverseDistortionModelSIMD;
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
pub const isNoDistortion = common.isNoDistortion;
