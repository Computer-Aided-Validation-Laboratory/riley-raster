// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const root = @import("root");

const build_options = if (@hasDecl(root, "build_options"))
    root.build_options
else
    struct {
        pub const precision = "f64";
        pub const simd = "on";
        pub const newton_solver = "fast";
        pub const simd_vector_width: comptime_int = 0;
    };

pub const comptime_eval_branch_quota: comptime_int = 50000;

// --------------------------------------------------------------------------------------
// Main Config
// --------------------------------------------------------------------------------------

pub const Config = struct {
    simd: SimdMode = default_simd,
    newton_solver_mode: NewtonSolverMode = default_newton_solver_mode,
    simd_vector_width: comptime_int = defaultSimdVectorWidthForPrecision(F),
    max_nodal_fields: comptime_int = 8,
    max_image_channels: comptime_int = 8,
    raster_newton_iter_max: comptime_int = 10,
    distortion_newton_iter_max: comptime_int = 15,
    interp_lut_size: comptime_int = 1024,
    save_frame_buffer_count: comptime_int = 3,
    precision: type = F,
    tolerance: Tolerance = defaultToleranceForPrecision(F),
};

pub const default_precision = parsePrecision(build_options.precision);
pub const F = default_precision;
pub const Scalar = F;

pub const default_simd = parseSimd(build_options.simd);
pub const default_newton_solver_mode =
    parseNewtonSolverMode(build_options.newton_solver);

pub const config = configForPrecision(F);

pub const SimdWidth = config.simd_vector_width;
pub const SaveFrameBufferCount = config.save_frame_buffer_count;
pub const NewtonMode = config.newton_solver_mode;
pub const UseHullNewtonSeed = defaultNewtonSeedModeUsesHull(F);
pub const UseLastConvergedNewtonSeedReuse =
    defaultNewtonSeedReuseLastConverged(F);

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const SimdMode = enum {
    off,
    on,
};

pub const SimdTextureInterpMode = enum {
    inner,
    over_pixels,
};

pub const NewtonSolverMode = enum {
    fast,
    robust,
};

pub const TextureSIMDPolicy = struct {
    pub fn resolve(
        comptime channels: comptime_int,
        comptime is_linear: bool,
        comptime uses_lut: bool,
    ) SimdTextureInterpMode {
        if (is_linear) {
            return .over_pixels;
        }
        if (channels == 1) {
            if (uses_lut) {
                return .inner;
            }
            return .over_pixels;
        }
        return .inner;
    }
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn defaultNewtonSeedModeUsesHull(comptime precision: type) bool {
    return switch (precision) {
        f32 => true,
        f64 => false,
        else => @compileError("Only f32 and f64 precision are supported."),
    };
}

pub fn defaultNewtonSeedReuseLastConverged(comptime precision: type) bool {
    _ = precision;
    return false;
}

pub fn defaultSimdVectorWidthForPrecision(comptime precision: type) comptime_int {
    if (build_options.simd_vector_width > 0) {
        return build_options.simd_vector_width;
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
        .newton_solver_mode = default_newton_solver_mode,
        .simd_vector_width = defaultSimdVectorWidthForPrecision(precision),
        .tolerance = defaultToleranceForPrecision(precision),
    };
}

fn parsePrecision(comptime precision: []const u8) type {
    if (std.mem.eql(u8, precision, "f32")) {
        return f32;
    }
    if (std.mem.eql(u8, precision, "f64")) {
        return f64;
    }
    @compileError("build_options.precision must be \"f32\" or \"f64\".");
}

fn parseSimd(comptime simd: []const u8) SimdMode {
    if (std.mem.eql(u8, simd, "on")) {
        return .on;
    }
    if (std.mem.eql(u8, simd, "off")) {
        return .off;
    }
    @compileError("build_options.simd must be \"on\" or \"off\".");
}

fn parseNewtonSolverMode(comptime newton_solver: []const u8) NewtonSolverMode {
    if (std.mem.eql(u8, newton_solver, "fast")) {
        return .fast;
    }
    if (std.mem.eql(u8, newton_solver, "robust")) {
        return .robust;
    }
    @compileError(
        "build_options.newton_solver must be \"fast\" or \"robust\".",
    );
}

// --------------------------------------------------------------------------------------
// Major Internal Types Shared Across The File
// --------------------------------------------------------------------------------------

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
    normalized_residual: Scalar = 3e-11,
    stagnation_normalized_residual: Scalar = 1e-10,
    relative_determinant: Scalar = 1e-12,
    parametric_domain: Scalar = 1e-7,
    parametric_step_abs: Scalar = 1e-12,
    parametric_step_rel: Scalar = 1e-12,
    max_parametric_step: Scalar = 0.5,
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

pub const PSFTolerance = struct {
    support_radius_inclusion: Scalar = 1e-12,
    pixel_box_identity_support_radius: Scalar = 1e-12,
    anisotropic_axis_alignment: Scalar = 1e-12,
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
    psf: PSFTolerance = .{},
    image: ImageTolerance = .{},
    legacy: LegacyTolerance = .{},
};

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
        .residual = 1e-4,
        .normalized_residual = 1.5e-5,
        .stagnation_normalized_residual = 7.5e-5,
        .relative_determinant = 1e-6,
        .parametric_domain = 5e-5,
        .parametric_step_abs = 2e-6,
        .parametric_step_rel = 2e-6,
        .max_parametric_step = 0.5,
    },
    .distortion = .{
        .residual = 1e-5,
        .delta = 1e-5,
        .determinant = 1e-7,
    },
    .newton_seed = .{
        .determinant = 1e-7,
        .parametric_domain = 2e-4,
        .residual_sq = 5e-3,
    },
    .geometry = .{
        .bilinear_parametric_domain = 5e-5,
        .bilinear_denom = 1e-7,
        .quadratic_area = 1e-8,
        .depth_buffer_inv_z_cmp = 1e-8,
    },
    .texture = .{
        .lancsoz_centre_snap = 1e-6,
        .samp_coeff_sum = 1e-6,
    },
    .psf = .{
        .support_radius_inclusion = 1e-6,
        .pixel_box_identity_support_radius = 1e-6,
        .anisotropic_axis_alignment = 1e-6,
    },
    .image = .{
        .auto_scale_range = 1e-8,
    },
    .legacy = .{
        .oldraster_area = 1e-8,
    },
};

// --------------------------------------------------------------------------------------
// Generic Low-Level Helpers
// --------------------------------------------------------------------------------------

pub const VecSF = @Vector(SimdWidth, F);
pub const VecSU = @Vector(SimdWidth, usize);
pub const VecSI = @Vector(SimdWidth, isize);
pub const VecSB = @Vector(SimdWidth, bool);
pub const VecSU8 = @Vector(SimdWidth, u8);

pub const Tri3FixedConfig = switch (F) {
    f32 => struct {
        pub const Coord = i32;
        pub const Setup = i64;
        pub const Edge = i64;
        pub const frac_bits: comptime_int = 12;
    },
    f64 => struct {
        pub const Coord = i64;
        pub const Setup = i128;
        pub const Edge = i64;
        pub const frac_bits: comptime_int = 16;
    },
    else => @compileError("Unsupported Riley floating-point type."),
};

pub const Tri3FixedCoord = Tri3FixedConfig.Coord;
pub const Tri3FixedSetup = Tri3FixedConfig.Setup;
pub const Tri3FixedEdge = Tri3FixedConfig.Edge;
pub const Tri3FixedFracBits = Tri3FixedConfig.frac_bits;
pub const Tri3FixedOne: Tri3FixedEdge =
    @as(Tri3FixedEdge, 1) << Tri3FixedFracBits;
pub const VecSTri3FixedEdge = @Vector(SimdWidth, Tri3FixedEdge);

comptime {
    if (Tri3FixedFracBits <= 0) {
        @compileError("tri3 fixed-point precision must be positive.");
    }
    if (@bitSizeOf(Tri3FixedEdge) < @bitSizeOf(Tri3FixedCoord)) {
        @compileError(
            "tri3 edge type must not be narrower than coordinate type.",
        );
    }
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "TextureSIMDPolicy resolves texture cases" {
    const expectEqual = std.testing.expectEqual;

    try expectEqual(
        SimdTextureInterpMode.over_pixels,
        TextureSIMDPolicy.resolve(1, true, false),
    );
    try expectEqual(
        SimdTextureInterpMode.inner,
        TextureSIMDPolicy.resolve(1, false, true),
    );
    try expectEqual(
        SimdTextureInterpMode.inner,
        TextureSIMDPolicy.resolve(1, false, true),
    );
    try expectEqual(
        SimdTextureInterpMode.over_pixels,
        TextureSIMDPolicy.resolve(1, false, false),
    );
    try expectEqual(
        SimdTextureInterpMode.over_pixels,
        TextureSIMDPolicy.resolve(3, true, false),
    );
    try expectEqual(
        SimdTextureInterpMode.inner,
        TextureSIMDPolicy.resolve(3, false, true),
    );
    try expectEqual(
        SimdTextureInterpMode.inner,
        TextureSIMDPolicy.resolve(3, false, false),
    );
}
