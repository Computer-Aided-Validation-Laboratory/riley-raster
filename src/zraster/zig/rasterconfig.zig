// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const iio = @import("imageio.zig");

pub const RasterConfig = struct {
    render_mode: RenderMode = .in_order,
    total_threads: u16 = 0,
    max_frames_in_flight: u16 = 1,
    max_geom_threads_per_frame: u16 = 0,
    max_raster_threads_per_frame: u16 = 0,
    save_strategy: SaveStrategy = .disk,
    image_save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .none },
    },
    tile_size_max: u16 = 32,
    hull_mode: HullMode = .on_no_fallback,
    newton_seed_mode: NewtonSeedMode = .centroid,
    newton_seed_reuse: NewtonSeedReuse = .off,
    report: ReportMode = .bench,
    full_stats_opts: FullStatsOpts = .{},
    subpixel_center_map: SubPixelCenterMap = .per_tile,
};

pub const SubPixelCenterMap = enum {
    full_in_mem,
    per_tile,
    affine_jac,
};

pub const RenderMode = enum {
    in_order,
    offline,
};

pub const SaveStrategy = enum {
    disk,
    memory,
    both,
    none,
};

pub const ReportMode = enum {
    off,
    bench,
    full_stats,
};

pub const HullMode = enum {
    off,
    on_no_fallback,
    on_convex_fallback,
};

pub const NewtonSeedMode = enum {
    centroid,
    hull,
};

pub const NewtonSeedReuse = enum {
    off,
    last_converged,
};

pub const FullStatsOpts = struct {
    formats: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
        .{ .format = .csv, .bits = null, .scaling = .none },
    },
    save_iteration_map: bool = true,
    save_tile_timing_map: bool = true,
    save_tile_density_map: bool = true,
    save_tile_occupancy_map: bool = true,
    save_depth_map: bool = true,
    save_earlyout_map: bool = true,
    save_pixel_occupancy_map: bool = true,
    save_normals_map: bool = false,
};
