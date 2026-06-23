// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const root = @import("root");
const local_build_options = @import("build_options.zig");

const build_options = if (@hasDecl(root, "build_options"))
    root.build_options
else
    local_build_options;

pub const default_precision = blk: {
    if (std.mem.eql(u8, build_options.precision, "f32")) {
        break :blk f32;
    }
    if (std.mem.eql(u8, build_options.precision, "f64")) {
        break :blk f64;
    }
    @compileError("build_options.precision must be \"f32\" or \"f64\".");
};
pub const Scalar = default_precision;

pub const SimdMode = enum {
    off,
    on,
};

pub const default_simd = blk: {
    if (std.mem.eql(u8, build_options.simd, "on")) {
        break :blk SimdMode.on;
    }
    if (std.mem.eql(u8, build_options.simd, "off")) {
        break :blk SimdMode.off;
    }
    @compileError("build_options.simd must be \"on\" or \"off\".");
};

pub const SimdTextureInterpMode = enum {
    inner,
    over_pixels,
};

const simd_texture_interp_str = if (@hasDecl(build_options, "simd_texture_interp"))
    build_options.simd_texture_interp
else
    "inner";

pub const default_simd_texture_interp = blk: {
    if (std.mem.eql(u8, simd_texture_interp_str, "inner")) {
        break :blk SimdTextureInterpMode.inner;
    }
    if (std.mem.eql(u8, simd_texture_interp_str, "over_pixels")) {
        break :blk SimdTextureInterpMode.over_pixels;
    }
    @compileError(
        "build_options.simd_texture_interp must be \"inner\" or " ++
            "\"over_pixels\".",
    );
};

const build_simd_vector_width = if (@hasDecl(build_options, "simd_vector_width"))
    build_options.simd_vector_width
else
    0;

pub const EdgeTolerance = struct {
    tri_weight_inclusion: Scalar = 1e-9,
    simd_raster_weight_inclusion: Scalar = 1e-9,
};

pub const HullTolerance = struct {
    scalar_inclusion: Scalar = 1.0e-6,
    simd_inclusion: Scalar = 1.0e-6,
    corner_midside_ang_lower_deg: Scalar = 20.0,
    corner_midside_ang_upper_deg: Scalar = 180.0,
    // Node-only front-end AABB pad used when RasterConfig.hull_mode == .off.
    // Set from a hull-suite ablation study against the 0.3 baseline:
    // 0.25/0.20/0.15/0.10 passed and 0.05 failed, so we keep 0.15 as a
    // conservative default with margin.
    no_hull_bbox_rel_pad: Scalar = 0.15,
};

pub const CullingTolerance = struct {
    higher_order_backface_nz: Scalar = 1e-3,
    tri3_signed_area: Scalar = 1e-6,
    projective_z_min: Scalar = 1e-12,
};

pub const NormalTolerance = struct {
    normalise_magnitude: Scalar = 1e-12,
};

pub const NewtonTolerance = struct {
    residual: Scalar = 1e-8,
    determinant: Scalar = 1e-12,
    parametric_domain: Scalar = 1e-7,
};

pub const DistortionTolerance = struct {
    residual: Scalar = 1e-10,
    delta: Scalar = 1e-10,
    determinant: Scalar = 1e-12,
};

pub const NewtonSeedTolerance = struct {
    determinant: Scalar = 1e-10,
    parametric_domain: Scalar = 1e-5,
    residual_sq: Scalar = 1e-4,
};

pub const GeometryTolerance = struct {
    bilinear_parametric_domain: Scalar = 1e-8,
    bilinear_denom: Scalar = 1e-12,
    quadratic_area: Scalar = 1e-12,
    depth_buffer_inv_z_cmp: Scalar = 1e-12,
};

pub const TextureTolerance = struct {
    lancsoz_centre_snap: Scalar = 1e-6,
    samp_coeff_sum: Scalar = 1e-9,
};

pub const ImageTolerance = struct {
    auto_scale_range: Scalar = 1e-9,
};

pub const LegacyTolerance = struct {
    oldraster_area: Scalar = 1e-12,
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
    simd: SimdMode = default_simd,
    simd_texture_interp: SimdTextureInterpMode = default_simd_texture_interp,
    simd_vector_width: comptime_int = defaultSimdVectorWidthForPrecision(Scalar),
    max_nodal_fields: comptime_int = 8,
    max_image_channels: comptime_int = 8,
    raster_newton_iter_max: comptime_int = 10,
    distortion_newton_iter_max: comptime_int = 15,
    interp_lut_size: comptime_int = 1024,
    save_frame_buffer_count: comptime_int = 3,
    precision: type = Scalar,
    tolerance: Tolerance = defaultToleranceForPrecision(Scalar),
};

pub fn defaultSimdVectorWidthForPrecision(comptime precision: type) comptime_int {
    if (build_simd_vector_width > 0) {
        return build_simd_vector_width;
    }
    return switch (precision) {
        f32 => 16,
        f64 => 8,
        else => @compileError("Only f32 and f64 precision are supported."),
    };
}

pub fn defaultToleranceForPrecision(comptime precision: type) Tolerance {
    return switch (precision) {
        f32 => tolerance_f32,
        f64 => tolerance_f64,
        else => @compileError("Only f32 and f64 precision are supported."),
    };
}

pub fn configForPrecision(comptime precision: type) Config {
    _ = defaultSimdVectorWidthForPrecision(precision);
    return .{
        .precision = precision,
        .simd_vector_width = defaultSimdVectorWidthForPrecision(precision),
        .tolerance = defaultToleranceForPrecision(precision),
    };
}

pub const tolerance_f64 = Tolerance{};

pub const tolerance_f32 = Tolerance{
    .edge = .{
        .tri_weight_inclusion = 1e-6,
        .simd_raster_weight_inclusion = 1e-6,
    },
    .hull = .{
        .scalar_inclusion = 1.0e-5,
        .simd_inclusion = 1.0e-5,
        .corner_midside_ang_lower_deg = 20.0,
        .corner_midside_ang_upper_deg = 180.0,
        .no_hull_bbox_rel_pad = 0.15,
    },
    .culling = .{
        .higher_order_backface_nz = 1e-3,
        .tri3_signed_area = 1e-5,
        .projective_z_min = 1e-9,
    },
    .normals = .{
        .normalise_magnitude = 1e-8,
    },
    .newton = .{
        .residual = 1e-5,
        .determinant = 1e-8,
        .parametric_domain = 1e-5,
    },
    .distortion = .{
        .residual = 1e-6,
        .delta = 1e-6,
        .determinant = 1e-8,
    },
    .newton_seed = .{
        .determinant = 1e-8,
        .parametric_domain = 1e-4,
        .residual_sq = 1e-3,
    },
    .geometry = .{
        .bilinear_parametric_domain = 1e-5,
        .bilinear_denom = 1e-8,
        .quadratic_area = 1e-8,
        .depth_buffer_inv_z_cmp = 1e-8,
    },
    .texture = .{
        .lancsoz_centre_snap = 1e-6,
        .samp_coeff_sum = 1e-6,
    },
    .image = .{
        .auto_scale_range = 1e-8,
    },
    .legacy = .{
        .oldraster_area = 1e-8,
    },
};

pub const config = configForPrecision(default_precision);

pub const F = config.precision;
pub const SimdWidth = config.simd_vector_width;
pub const SaveFrameBufferCount = config.save_frame_buffer_count;

pub const VecSF = @Vector(SimdWidth, F);
pub const VecSU = @Vector(SimdWidth, usize);
pub const VecSI = @Vector(SimdWidth, isize);
pub const VecSB = @Vector(SimdWidth, bool);
pub const VecSU8 = @Vector(SimdWidth, u8);
