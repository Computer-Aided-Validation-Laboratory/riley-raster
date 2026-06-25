// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const buildconfig = @import("../riley/zig/buildconfig.zig");
const gk = @import("../riley/zig/geometrykernels.zig");

const cfg = buildconfig.config;
const F = buildconfig.F;

pub const GoldModePolicy = enum {
    shared_by_precision,
    split_by_precision_and_simd,
};

pub const GoldSuite = enum {
    min,
    small,
    simple,
    edge,
    multimesh,
    hull,
    fullscreen,
    texfunc,
    ssaa,
    psf,
    sphere2000,
    sphere2000zoom,
    sphere200multicam,
};

pub const MeshNameContext = enum {
    fixture_case,
    benchmark_data,
    gold_case,
    sphere_gold_case,
};

pub fn goldModePolicy(comptime suite: GoldSuite) GoldModePolicy {
    return switch (suite) {
        .sphere2000, .sphere2000zoom, .sphere200multicam => .split_by_precision_and_simd,
        else => .shared_by_precision,
    };
}

pub fn suiteDirName(comptime suite: GoldSuite) []const u8 {
    return switch (suite) {
        .min => "min",
        .small => "small",
        .simple => "simple",
        .edge => "edge",
        .multimesh => "multimesh",
        .hull => "hull",
        .fullscreen => "fullscreen",
        .texfunc => "texfunc",
        .ssaa => "ssaa",
        .psf => "psf",
        .sphere2000 => "sphere2000",
        .sphere2000zoom => "sphere2000zoom",
        .sphere200multicam => "sphere200multicam",
    };
}

pub fn goldRoot(comptime suite: GoldSuite) []const u8 {
    return switch (suite) {
        .min => if (F == f64) "gold/min" else "gold/min_f32",
        .small => if (F == f64) "gold/small" else "gold/small_f32",
        .simple => if (F == f64) "gold/simple" else "gold/simple_f32",
        .edge => if (F == f64) "gold/edge" else "gold/edge_f32",
        .multimesh => if (F == f64) "gold/multimesh" else "gold/multimesh_f32",
        .hull => if (F == f64) "gold/hull" else "gold/hull_f32",
        .fullscreen => if (F == f64) "gold/fullscreen" else "gold/fullscreen_f32",
        .texfunc => if (F == f64) "gold/texfunc" else "gold/texfunc_f32",
        .ssaa => if (F == f64) "gold/ssaa" else "gold/ssaa_f32",
        .psf => if (F == f64) "gold/psf" else "gold/psf_f32",
        .sphere2000 => if (F == f64)
            (if (cfg.simd == .on) "gold/sphere2000-simd" else "gold/sphere2000")
        else
            (if (cfg.simd == .on)
                "gold/sphere2000_f32_simd"
            else
                "gold/sphere2000_f32_scalar"),
        .sphere2000zoom => if (F == f64)
            (if (cfg.simd == .on)
                "gold/sphere2000zoom-simd"
            else
                "gold/sphere2000zoom")
        else
            (if (cfg.simd == .on)
                "gold/sphere2000zoom_f32_simd"
            else
                "gold/sphere2000zoom_f32_scalar"),
        .sphere200multicam => if (F == f64)
            (if (cfg.simd == .on)
                "gold/sphere200multicam-simd"
            else
                "gold/sphere200multicam")
        else
            (if (cfg.simd == .on)
                "gold/sphere200multicam_f32_simd"
            else
                "gold/sphere200multicam_f32_scalar"),
    };
}

pub fn canonicalCaseMeshType(mesh_type: gk.MeshType) gk.MeshType {
    return switch (mesh_type) {
        .tri3opt => .tri3,
        else => mesh_type,
    };
}

pub fn sphereGoldCaseMeshType(mesh_type: gk.MeshType) gk.MeshType {
    return switch (mesh_type) {
        .quad4ibi => .quad4newton,
        else => canonicalCaseMeshType(mesh_type),
    };
}

pub fn meshName(
    comptime context: MeshNameContext,
    mesh_type: gk.MeshType,
) []const u8 {
    return switch (context) {
        .fixture_case => switch (mesh_type) {
            .tri3opt => "tri3",
            .quad4ibi, .quad4newton => "quad4",
            else => @tagName(mesh_type),
        },
        .benchmark_data, .gold_case => @tagName(canonicalCaseMeshType(mesh_type)),
        .sphere_gold_case => @tagName(sphereGoldCaseMeshType(mesh_type)),
    };
}
