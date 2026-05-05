// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rastcfg = @import("rasterconfig.zig");
const report = @import("report.zig");

pub const DispatchScaling = struct {
    dispatch_threads: u16,
    frames_in_flight: u16,
    geom_threads: u16,
    raster_threads: u16,
};

const l2_cache_size_bytes = 1024 * 1024;
const l2_safety_margin = 0.75;
const bytes_per_subpixel = 154; // Based on F=8, S=8, precision=f64
const target_subpx_per_tile: usize = @intFromFloat(
    @as(f64, l2_cache_size_bytes) * l2_safety_margin / bytes_per_subpixel
);
const default_chunk_count_per_worker: usize = 4;

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
        .geom_threads = phaseThreads(
            config.total_threads,
            config.max_geom_threads_per_frame,
        ),
        .raster_threads = phaseThreads(
            config.total_threads,
            config.max_raster_threads_per_frame,
        ),
    };
}

pub fn phaseThreads(
    total_threads: u16,
    phase_threads_max: u16,
) u16 {
    if (total_threads == 0) {
        return 1;
    }

    const phase_threads = @max(@as(u16, 1), phase_threads_max);
    return @min(total_threads, phase_threads);
}

pub fn framesInFlight(
    render_mode: rastcfg.RenderMode,
    total_threads: u16,
    max_frames_in_flight: u16,
    cameras_num: usize,
) u16 {
    if (total_threads == 0) {
        return 1;
    }

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
    tile_size_min: u16,
    tile_size_max: u16,
    pixels_num: [2]u32,
    sub_sample: u8,
) u16 {
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
        const subpx_per_tile = tile_size_u * tile_size_u * sub_samp * sub_samp;
        if (subpx_per_tile <= target_subpx_per_tile) {
            break;
        }
        tile_size = @max(min_tile_size, tile_size / 2);
    }

    return tile_size;
}

pub fn geometryWorkers(
    geom_threads: u16,
) usize {
    return @as(usize, @max(@as(u16, 1), geom_threads));
}

pub fn geometryNodeChunkSize(
    nodes_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(nodes_num, workers_num, default_chunk_count_per_worker);
}

pub fn geometryElemChunkSize(
    elems_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(elems_num, workers_num, default_chunk_count_per_worker);
}

pub fn geometryVisibleChunkSize(
    elems_in_image: usize,
    workers_num: usize,
) usize {
    return chunkSize(
        elems_in_image,
        workers_num,
        default_chunk_count_per_worker,
    );
}

pub fn tilingChunkSize(
    elems_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(elems_num, workers_num, default_chunk_count_per_worker);
}

pub fn rasterWorkers(
    requested_threads: u16,
    active_tiles_num: usize,
) usize {
    if (active_tiles_num == 0) {
        return 1;
    }

    const requested_workers = @max(@as(u16, 1), requested_threads);
    const tile_cap = @as(
        u16,
        @intCast(@min(active_tiles_num, std.math.maxInt(u16))),
    );
    return @as(usize, @min(requested_workers, tile_cap));
}

pub fn rasterGrainSize(
    active_tiles_num: usize,
    workers_num: usize,
) usize {
    return chunkSize(
        active_tiles_num,
        workers_num,
        default_chunk_count_per_worker,
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
