// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const common = @import("shaderops_common.zig");

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub const fillNodalClip = common.fillNodalClip;
pub const fillNodalPersp = common.fillNodalPersp;
pub const fillTexClip = common.fillTexClip;
pub const fillTexPersp = common.fillTexPersp;
pub const fillFuncClip = common.fillFuncClip;
pub const fillFuncPersp = common.fillFuncPersp;
