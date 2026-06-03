// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rastcfg = @import("rasterconfig.zig");
const report = @import("report.zig");
const GeometrySchedulingMode = rastcfg.GeometrySchedulingMode;

pub const DispatchScaling = struct {
    dispatch_threads: u16,
    frames_in_flight: u16,
    geom_workers: u16,
    raster_workers: u16,
};

const l2_cache_size_bytes = 1024 * 1024;
const l2_safety_margin = 0.8;
const bytes_per_subpixel = 154; // Based on F=8, S=8, precision=f64
const target_subpx_per_tile: usize = @intFromFloat(@as(f64, l2_cache_size_bytes) * l2_safety_margin / bytes_per_subpixel);
pub const GEOMETRY_CHUNKS_PER_WORKER: usize = 1;
pub const RASTER_CHUNKS_PER_WORKER: usize = 4;
pub const AUTO_GEOMETRY_SPREAD_ELEMS_THRESHOLD: usize = 100_000;

pub fn dispatchScaling(
    render_mode: rastcfg.RenderMode,
    config: rastcfg.RasterConfig,
    cameras_num: usize,
) DispatchScaling {
    return .{
        .dispatch_threads = config.total_threads,
        .frames_in_flight = framesInFlight(
            render_mode,
            config.total_threads,
            config.max_frames_in_flight,
            cameras_num,
        ),
        .geom_workers = phaseWorkers(
            config.total_threads,
            config.max_geom_workers_per_frame,
        ),
        .raster_workers = phaseWorkers(
            config.total_threads,
            config.max_raster_workers_per_frame,
        ),
    };
}

pub fn phaseWorkers(
    total_threads: u16,
    phase_workers_requested: u16,
) u16 {
    const total_thr = @max(@as(u16, 1), total_threads);

    // A value of 0 means use everything (Auto)
    if (phase_workers_requested == 0) {
        return total_thr;
    }

    // Otherwise cap at the total threads available
    return @min(total_thr, phase_workers_requested);
}

pub fn resolveGeometrySchedulingMode(
    requested_mode: GeometrySchedulingMode,
    total_scene_elems: usize,
) GeometrySchedulingMode {
    return switch (requested_mode) {
        .spread, .pack => requested_mode,
        .auto => if (total_scene_elems < AUTO_GEOMETRY_SPREAD_ELEMS_THRESHOLD)
            .spread
        else
            .pack,
    };
}

pub fn framesInFlight(
    render_mode: rastcfg.RenderMode,
    total_threads: u16,
    max_frames_in_flight: u16,
    cameras_num: usize,
) u16 {
    _ = total_threads;
    const requested_frames = @max(@as(u16, 1), max_frames_in_flight);

    if (render_mode == .in_order) {
        // In order processing is constrained to one time step at a time
        // but can process multiple cameras for that time step in parallel.
        const camera_cap = @max(@as(usize, 1), cameras_num);
        return @min(requested_frames, @as(u16, @intCast(camera_cap)));
    } else {
        // Offline processing can process multiple time steps and cameras
        // in parallel in any order.
        return requested_frames;
    }
}

pub fn frameBatchSize(
    frames_in_flight: u16,
    jobs_num: usize,
) usize {
    return @min(@as(usize, frames_in_flight), jobs_num);
}

pub fn tileSize(
    tile_size_override: u16,
    tile_size_min: u16,
    tile_size_max: u16,
    pixels_num: [2]u32,
    sub_sample: u8,
    halo_px: u16,
) u16 {
    if (tile_size_override > 0) {
        return tile_size_override;
    }

    const min_sensor_dim = @max(
        @as(u32, 1),
        @min(pixels_num[0], pixels_num[1]),
    );
    var tile_size = @max(@as(u16, 1), tile_size_max);
    tile_size = @min(
        tile_size,
        @as(u16, @intCast(@min(min_sensor_dim, std.math.maxInt(u16)))),
    );

    const sub_samp: usize = @max(
        @as(usize, 1),
        @as(usize, @intCast(sub_sample)),
    );

    const min_tile_size = @max(@as(u16, 1), tile_size_min);

    while (tile_size > min_tile_size) {
        const tile_size_u: usize = @intCast(tile_size);
        const eff_tile_size_u = tile_size_u + 2 * @as(usize, halo_px);
        const subpx_per_tile = eff_tile_size_u * eff_tile_size_u * sub_samp * sub_samp;
        if (subpx_per_tile <= target_subpx_per_tile) {
            break;
        }
        tile_size = @max(min_tile_size, tile_size / 2);
    }

    return tile_size;
}

pub fn geometryWorkers(
    geom_workers: u16,
) usize {
    return @as(usize, @max(@as(u16, 1), geom_workers));
}

pub fn geometryNodeChunkSize(
    nodes_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(nodes_num, workers_num, GEOMETRY_CHUNKS_PER_WORKER);
}

pub fn geometryElemChunkSize(
    elems_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(elems_num, workers_num, GEOMETRY_CHUNKS_PER_WORKER);
}

pub fn geometryVisibleChunkSize(
    elems_in_image: usize,
    workers_num: usize,
) usize {
    return chunkSize(
        elems_in_image,
        workers_num,
        GEOMETRY_CHUNKS_PER_WORKER,
    );
}

pub fn tilingChunkSize(
    elems_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(elems_num, workers_num, GEOMETRY_CHUNKS_PER_WORKER);
}

pub fn rasterWorkers(
    requested_workers: u16,
    active_tiles_num: usize,
) usize {
    if (active_tiles_num == 0) {
        return 1;
    }

    const requested_workers_u16 = @max(@as(u16, 1), requested_workers);
    const tile_cap = @as(
        u16,
        @intCast(@min(active_tiles_num, std.math.maxInt(u16))),
    );
    return @as(usize, @min(requested_workers_u16, tile_cap));
}

pub fn rasterGrainSize(
    active_tiles_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(
        active_tiles_num,
        workers_num,
        RASTER_CHUNKS_PER_WORKER,
    );
}

fn chunkSize(
    domain_len: usize,
    workers_num: usize,
    chunks_per_worker: usize,
) usize {
    if (domain_len == 0) {
        return 1;
    }

    const actual_workers = @max(@as(usize, 1), workers_num);
    const chunk_count = @max(
        @as(usize, 1),
        actual_workers * chunks_per_worker,
    );
    return @max(@as(usize, 1), (domain_len + chunk_count - 1) / chunk_count);
}

test "resolveGeometrySchedulingMode uses explicit modes unchanged" {
    try std.testing.expectEqual(
        GeometrySchedulingMode.spread,
        resolveGeometrySchedulingMode(.spread, 1),
    );
    try std.testing.expectEqual(
        GeometrySchedulingMode.pack,
        resolveGeometrySchedulingMode(.pack, 1),
    );
}

test "resolveGeometrySchedulingMode auto prefers spread for smaller scenes" {
    try std.testing.expectEqual(
        GeometrySchedulingMode.spread,
        resolveGeometrySchedulingMode(
            .auto,
            AUTO_GEOMETRY_SPREAD_ELEMS_THRESHOLD - 1,
        ),
    );
}

test "resolveGeometrySchedulingMode auto prefers pack for larger scenes" {
    try std.testing.expectEqual(
        GeometrySchedulingMode.pack,
        resolveGeometrySchedulingMode(
            .auto,
            AUTO_GEOMETRY_SPREAD_ELEMS_THRESHOLD,
        ),
    );
}
