// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

pub const SimdMode = enum {
    off,
    on,
};

pub const ResolveScratchSimdMode = enum {
    off,
    on,
};

pub const SimdTextureInterpMode = enum {
    inner,
    over_pixels,
};

pub const EdgeTolerance = struct {
    tri_weight_inclusion: f64 = 1e-9,
    simd_raster_weight_inclusion: f64 = 1e-9,
};

pub const HullTolerance = struct {
    scalar_inclusion: f64 = 1.0e-6,
    simd_inclusion: f64 = 1.0e-6,
    corner_midside_ang_lower_deg: f64 = 20.0,
    corner_midside_ang_upper_deg: f64 = 180.0,
    // Node-only front-end AABB pad used when RasterConfig.hull_mode == .off.
    // Set from a hull-suite ablation study against the 0.3 baseline:
    // 0.25/0.20/0.15/0.10 passed and 0.05 failed, so we keep 0.15 as a
    // conservative default with margin.
    no_hull_bbox_rel_pad: f64 = 0.15,
};

pub const CullingTolerance = struct {
    higher_order_backface_nz: f64 = 1e-3,
    tri3_signed_area: f64 = 1e-6,
    projective_z_min: f64 = 1e-12,
};

pub const NormalTolerance = struct {
    normalise_magnitude: f64 = 1e-12,
};

pub const NewtonTolerance = struct {
    residual: f64 = 1e-8,
    determinant: f64 = 1e-12,
    parametric_domain: f64 = 1e-7,
};

pub const DistortionTolerance = struct {
    residual: f64 = 1e-10,
    delta: f64 = 1e-10,
    determinant: f64 = 1e-12,
};

pub const NewtonSeedTolerance = struct {
    determinant: f64 = 1e-10,
    parametric_domain: f64 = 1e-5,
    residual_sq: f64 = 1e-4,
};

pub const GeometryTolerance = struct {
    bilinear_parametric_domain: f64 = 1e-8,
    bilinear_denom: f64 = 1e-12,
    quadratic_area: f64 = 1e-12,
    depth_buffer_inv_z_cmp: f64 = 1e-12,
};

pub const TextureTolerance = struct {
    lancsoz_centre_snap: f64 = 1e-6,
    samp_coeff_sum: f64 = 1e-9,
};

pub const ImageTolerance = struct {
    auto_scale_range: f64 = 1e-9,
};

pub const LegacyTolerance = struct {
    oldraster_area: f64 = 1e-12,
};

pub const Tolerance = struct {
    edge: EdgeTolerance = .{},
    hull: HullTolerance = .{},
    culling: CullingTolerance = .{},
    normals: NormalTolerance = .{},
    newton: NewtonTolerance = .{},
    distortion: DistortionTolerance = .{},
    newton_seed: NewtonSeedTolerance = .{},
    geometry: GeometryTolerance = .{},
    texture: TextureTolerance = .{},
    image: ImageTolerance = .{},
    legacy: LegacyTolerance = .{},
};

pub const Config = struct {
    simd: SimdMode = .on,
    resolve_scratch_simd: ResolveScratchSimdMode = .off,
    simd_texture_interp: SimdTextureInterpMode = .inner,
    simd_vector_width: comptime_int = 8,
    max_nodal_fields: comptime_int = 8,
    max_image_channels: comptime_int = 8,
    raster_newton_iter_max: comptime_int = 10,
    distortion_newton_iter_max: comptime_int = 15,
    interp_lut_size: comptime_int = 1024,
    save_frame_buffer_count: comptime_int = 3,
    precision: type = f64,
    tolerance: Tolerance = .{},
};

pub const config = Config{};

pub const SimdWidth = config.simd_vector_width;
pub const SaveFrameBufferCount = config.save_frame_buffer_count;

pub const VecSF = @Vector(SimdWidth, f64);
pub const VecSU = @Vector(SimdWidth, usize);
pub const VecSI = @Vector(SimdWidth, isize);
pub const VecSB = @Vector(SimdWidth, bool);
pub const VecSU8 = @Vector(SimdWidth, u8);
