// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const buildconfig = @import("../riley/zig/buildconfig.zig");
const F = buildconfig.F;
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const RenderMode = rastcfg.RenderMode;
const HullMode = rastcfg.HullMode;

pub const REL_TOL: F = if (F == f32) 1.0e-3 else 1e-6;
pub const ABS_TOL: F = if (F == f32) 1.0e-3 else 1e-6;

// Full-suite gold comparison tolerances
pub const FULL_GOLD_REL_TOL: F = if (F == f32) 1.0e-3 else 1.0e-5;
pub const FULL_GOLD_ABS_TOL: F = if (F == f32) 1.0e-3 else 1.0e-5;

// tri3opt parity tolerances against baseline tri3
pub const TRI3OPT_PARITY_REL_TOL: F = 1.0e-3;
pub const TRI3OPT_PARITY_ABS_TOL: F = 1.0e-3;

// Equivalence comparison tolerances (multi-threading / multi-camera / buffer modes)
pub const EQUIV_REL_TOL: F = if (F == f32) 1.0e-4 else 1.0e-6;
pub const EQUIV_ABS_TOL: F = if (F == f32) 1.0e-4 else 1.0e-6;

pub const RENDER_MODE: RenderMode = .in_order;
pub const HULL_MODE: HullMode = .on_no_fallback;
// Includes the caller thread. TOTAL_THREADS = 3 means caller + 2 helpers.
pub const TOTAL_THREADS: u16 = 3;
pub const TEST_CASE_VERBOSE: bool = false;

pub const VerifTol = struct {
    para_abs: F,
    reproj_abs_px: F,
    distort_abs_px: F,
    silhouette_area_abs_px2: F,
    silhouette_cent_abs_px: F,
    silhouette_mask_diff_pct: F,
    depth_value_abs: F,
    depth_gap_rel: F,
};

pub const VERIF_TOL = VerifTol{
    .para_abs = 1.0e-7,
    .reproj_abs_px = 1.0e-6,
    .distort_abs_px = 1.0e-6,
    .silhouette_area_abs_px2 = 16.0,
    .silhouette_cent_abs_px = 5.0e-2,
    .silhouette_mask_diff_pct = 1.0e-3,
    .depth_value_abs = 1.0e-12,
    .depth_gap_rel = 1.0e-5,
};

pub const DistortOracleTol = struct {
    ford_abs_norm: F,
    inv_abs_norm: F,
    jac_abs: F,
    jac_rel: F,
    backend_abs_norm: F,
    compatibility_abs_norm: F,
};

pub const DISTORT_ORACLE_TOL = DistortOracleTol{
    .ford_abs_norm = 5.0e-12,
    .inv_abs_norm = 2.0e-5,
    .jac_abs = 2.0e-8,
    .jac_rel = 2.0e-8,
    .backend_abs_norm = 2.0e-5,
    .compatibility_abs_norm = 1.0e-14,
};

pub const DISTORT_ROUNDTRIP_ABS_PX: F = 1.0e-6;
pub const RasterConfigMode = enum {
    gold_gen,
    preview,
    testing,
    bench,
};

pub fn getRasterConfig(mode: RasterConfigMode) rastcfg.RasterConfig {
    var config = rastcfg.RasterConfig{
        .advanced = .{
            .solver = .{
                .hull_mode = HULL_MODE,
                // Existing gold was generated with camera-depth seed order.
                // The public default is front-facing order; retain this
                // explicit policy for historical render regression coverage.
                .multi_root = .{ .method = .legacy_depth },
            },
        },
    };

    switch (mode) {
        .gold_gen, .preview => {
            config.parallel = .serial;
            config.report = .{ .mode = .off };
        },
        .testing => {
            config.parallel = .{ .threads = TOTAL_THREADS };
            config.report = .{ .mode = .off };
        },
        .bench => {
            config.parallel = .serial;
            config.report = .{ .mode = .bench };
        },
    }

    return config;
}
