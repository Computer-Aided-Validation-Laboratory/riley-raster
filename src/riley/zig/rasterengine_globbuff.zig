// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const impl = if (cfg.simd == .on)
    @import("rasterengine_globbuff_simd.zig")
else
    @import("rasterengine_globbuff_scalar.zig");

pub const rasterSceneGlobBuff = impl.rasterSceneGlobBuff;
