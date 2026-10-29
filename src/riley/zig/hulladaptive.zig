// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("hulladaptive_common.zig");
const impl = if (cfg.simd == .on)
    @import("hulladaptive_simd.zig")
else
    @import("hulladaptive_scalar.zig");
const simd_impl = @import("hulladaptive_simd.zig");

pub const HullAdaptive = struct {
    pub const Points = common.Points;
    pub const buildPointsFromClip = common.buildPointsFromClip;
    pub const Tessellation = impl.Tessellation;
    pub const makeTessellation = impl.makeTessellation;
    pub const CandidateSeedSIMD = simd_impl.CandidateSeedSIMD;
};
