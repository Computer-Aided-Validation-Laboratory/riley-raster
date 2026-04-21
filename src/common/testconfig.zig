// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const RenderMode = @import("../zraster/zig/zraster.zig").RenderMode;

pub const REL_TOL: f64 = 1e-6;
pub const ABS_TOL: f64 = 1e-6;
pub const RENDER_MODE: RenderMode = .in_order;
pub const TOTAL_THREADS: u16 = 2;
pub const MAX_FRAMES_IN_FLIGHT: u16 = 1;
pub const MAX_GEOM_THREADS_PER_FRAME: u16 = 2;
pub const MAX_RASTER_THREADS_PER_FRAME: u16 = 2;
