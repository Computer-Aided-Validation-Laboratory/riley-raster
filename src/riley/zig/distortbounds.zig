// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const camera = @import("camera.zig");
const common = @import("distortbounds_common.zig");
const distortbounds_scalar = @import("distortbounds_scalar.zig");
const distortbounds_simd = @import("distortbounds_simd.zig");

const cfg = buildconfig.config;
const F = buildconfig.F;
const impl = if (cfg.simd == .on) distortbounds_simd else distortbounds_scalar;

pub const DistortBounds = common.DistortBounds;
pub const Bounds = common.DistortBounds;
pub const validateSpacing = common.validateSpacing;
pub const edgeIntervalCount = common.edgeIntervalCount;
pub const idealSensorBounds = common.idealSensorBounds;
pub const sampleRectScalar = distortbounds_scalar.sampleRect;
pub const sampleRectSIMD = distortbounds_simd.sampleRect;

pub fn sampleRect(
    cam: *const camera.CameraPrepared,
    rect: DistortBounds,
    spacing_px: F,
) !DistortBounds {
    return impl.sampleRect(cam, rect, spacing_px);
}

