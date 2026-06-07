// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const common = @import("camera_common.zig");
const camera_scalar = @import("camera_scalar.zig");
const camera_simd = @import("camera_simd.zig");

const cfg = buildconfig.config;
const camera_impl = if (cfg.simd == .on) camera_simd else camera_scalar;

pub const DistortionModel = common.DistortionModel;
pub const BrownConrady = common.BrownConrady;
pub const BrownConradyExt = common.BrownConradyExt;
pub const DistortionInverseResult = common.DistortionInverseResult;
pub const DistortionForwardJacResult = common.DistortionForwardJacResult;
pub const SeparablePSF = common.SeparablePSF;
pub const PixelBoxPSF = common.PixelBoxPSF;
pub const GaussianPSF = common.GaussianPSF;
pub const AnisotropicGaussianPSF = common.AnisotropicGaussianPSF;
pub const PointSpreadFunc = common.PointSpreadFunc;
pub const PreparedPSFMode = common.PreparedPSFMode;
pub const PreparedPSF = common.PreparedPSF;

pub const CameraCoordSys = common.CameraCoordSys;
pub const SubPixelCenterMap = common.SubPixelCenterMap;
pub const CameraInput = common.CameraInput;
pub const StereoPairInput = common.StereoPairInput;
pub const FOVScaling = common.FOVScaling;

pub const CameraPrepared = camera_impl.CameraPrepared;
pub const allCamerasSharePixels = common.allCamerasSharePixels;

pub fn fillTileIdealCentersPerTile(
    camera: *const CameraPrepared,
    scratch_x_px_min: usize,
    scratch_x_px_max: usize,
    scratch_y_px_min: usize,
    scratch_y_px_max: usize,
    subpx_tile_size: usize,
    ideal_pixel_centers: []f64,
) !void {
    return camera_impl.fillTileIdealCentersPerTile(
        camera,
        scratch_x_px_min,
        scratch_x_px_max,
        scratch_y_px_min,
        scratch_y_px_max,
        subpx_tile_size,
        ideal_pixel_centers,
    );
}

pub fn fillTileIdealCentersAffineJac(
    camera: *const CameraPrepared,
    scratch_x_px_min: usize,
    scratch_x_px_max: usize,
    scratch_y_px_min: usize,
    scratch_y_px_max: usize,
    subpx_tile_size: usize,
    ideal_pixel_centers: []f64,
) void {
    camera_impl.fillTileIdealCentersAffineJac(
        camera,
        scratch_x_px_min,
        scratch_x_px_max,
        scratch_y_px_min,
        scratch_y_px_max,
        subpx_tile_size,
        ideal_pixel_centers,
    );
}
