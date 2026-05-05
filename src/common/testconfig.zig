// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const rastcfg = @import("../zraster/zig/rasterconfig.zig");
const RenderMode = rastcfg.RenderMode;
const HullMode = rastcfg.HullMode;

pub const REL_TOL: f64 = 1e-6;
pub const ABS_TOL: f64 = 1e-6;
pub const RENDER_MODE: RenderMode = .in_order;
pub const HULL_MODE: HullMode = .on_no_fallback;
pub const TOTAL_THREADS: u16 = 2;
pub const MAX_FRAMES_IN_FLIGHT: u16 = 1;
pub const MAX_GEOM_THREADS_PER_FRAME: u16 = 2;
pub const MAX_RASTER_THREADS_PER_FRAME: u16 = 2;
pub const TEST_CASE_VERBOSE: bool = false;

pub const RasterConfigMode = enum {
    gold,
    preview,
    testing,
    bench,
};

// What is going on here?
pub fn getRasterConfig(mode: RasterConfigMode) rastcfg.RasterConfig {
    var config = rastcfg.RasterConfig{
        .render_mode = RENDER_MODE,
        .max_frames_in_flight = MAX_FRAMES_IN_FLIGHT,
        .hull_mode = HULL_MODE,
    };

    switch (mode) {
        .gold, .preview => {
            config.total_threads = 0;
            config.max_geom_threads_per_frame = 0;
            config.max_raster_threads_per_frame = 0;
            config.report = .off;
        },
        .testing => {
            config.total_threads = TOTAL_THREADS;
            config.max_geom_threads_per_frame = MAX_GEOM_THREADS_PER_FRAME;
            config.max_raster_threads_per_frame = MAX_RASTER_THREADS_PER_FRAME;
            config.report = .off;
        },
        .bench => {
            config.total_threads = TOTAL_THREADS;
            config.max_geom_threads_per_frame = MAX_GEOM_THREADS_PER_FRAME;
            config.max_raster_threads_per_frame = MAX_RASTER_THREADS_PER_FRAME;
            config.report = .bench;
        },
    }

    return config;
}
