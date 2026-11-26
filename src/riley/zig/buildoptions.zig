// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const speckleconfig = @import("speckleconfig.zig");

pub const Precision = enum {
    f32,
    f64,

    pub fn defaultSimdVectorWidth(precision: Precision) u32 {
        return switch (precision) {
            .f32 => 16,
            .f64 => 8,
        };
    }
};

pub const SimdMode = enum { off, on };
pub const NewtonSolverMode = enum { fast, robust };

pub const Options = struct {
    precision: Precision = .f64,
    simd: SimdMode = .on,
    newton_solver: NewtonSolverMode = .fast,
    simd_vector_width: u32 = 0,
    enable_all_evaluators: bool = false,
    speckle_mask_resolution: speckleconfig.MaskResolution = speckleconfig.default_mask_resolution,
};
