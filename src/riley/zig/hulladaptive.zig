// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const hulladaptive_common = @import("hulladaptive_common.zig");
const impl = if (cfg.simd == .on)
    @import("hulladaptive_simd.zig")
else
    @import("hulladaptive_scalar.zig");
const hulladaptive_simd = @import("hulladaptive_simd.zig");

pub const HullAdaptive = struct {
    pub const Points = hulladaptive_common.Points;
    pub const buildPointsFromClip = hulladaptive_common.buildPointsFromClip;
    pub const Tessellation = impl.Tessellation;
    pub const makeTessellation = impl.makeTessellation;
    pub const CandidateSeedSIMD = hulladaptive_simd.CandidateSeedSIMD;
};
