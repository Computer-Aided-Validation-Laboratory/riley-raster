// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("adaptivehull_common.zig");
const impl = if (cfg.simd == .on)
    @import("adaptivehull_simd.zig")
else
    @import("adaptivehull_scalar.zig");
const simd_impl = @import("adaptivehull_simd.zig");

pub const AdaptiveHull = struct {
    pub const Points = common.Points;
    pub const buildPointsFromClip = common.AdaptiveHull.buildPointsFromClip;
    pub const Tessellation = impl.Tessellation;
    pub const makeTessellation = impl.makeTessellation;
    pub const CandidateSIMD = simd_impl.CandidateSIMD;
};
