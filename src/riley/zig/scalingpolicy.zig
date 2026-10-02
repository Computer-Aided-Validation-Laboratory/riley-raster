// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const rastcfg = @import("rasterconfig.zig");
const report = @import("report.zig");
const GeometrySchedulingMode = rastcfg.GeometrySchedulingMode;

// --------------------------------------------------------------------------------------
// Module Constants
// --------------------------------------------------------------------------------------

const l2_cache_size_bytes = 1024 * 1024;
const l2_safety_margin = 0.8;
const F = buildconfig.F;

fn bytesPerSubpixelForF64() comptime_int {
    return 154;
}

fn bytesPerSubpixelForF32() comptime_int {
    return 86;
}

const bytes_per_subpixel = switch (F) {
    f32 => bytesPerSubpixelForF32(),
    f64 => bytesPerSubpixelForF64(),
    else => @compileError("Only f32 and f64 precision are supped."),
};
const targ_subpx_per_tile: usize = @intFromFloat(
    @as(f64, l2_cache_size_bytes) * l2_safety_margin / bytes_per_subpixel,
);
pub const GEOMETRY_CHUNKS_PER_WORKER: usize = 1;
pub const RASTER_CHUNKS_PER_WORKER: usize = 4;
pub const AUTO_GEOMETRY_SPREAD_ELEMS_THRESHOLD: usize = 100_000;
pub const GEOM_THREADING_ELEMENT_THRESHOLD: usize = 1_000_000;

// --------------------------------------------------------------------------------------
// Public Types
// --------------------------------------------------------------------------------------

pub const ParallelWorkload = struct {
    camera_count: usize,
    frame_count: usize,
    element_count: usize,
    render_mode: rastcfg.RenderMode,
};

pub const ResolvedParallelConfig = struct {
    total_threads: u16,
    render_group_count: u16,
    frame_batch_size_per_group: u16,
    max_geom_jobs_in_flight_per_group: u16,
    max_geom_workers_per_job: u16,
    geom_scheduling_mode: GeometrySchedulingMode,
    max_raster_workers_per_job: u16,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

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

pub fn maxIndependentRenderJobs(workload: ParallelWorkload) usize {
    return switch (workload.render_mode) {
        .offline => @max(
            @as(usize, 1),
            workload.camera_count *| workload.frame_count,
        ),
        .in_order => @max(
            @as(usize, 1),
            workload.camera_count,
        ),
    };
}

pub fn availableThreadBudget(config: rastcfg.ParallelConfig) u16 {
    return switch (config) {
        .auto => blk: {
            const cpu_count = std.Thread.getCpuCount() catch 1;
            const clamped = @min(cpu_count, std.math.maxInt(u16));
            break :blk @as(u16, @intCast(@max(1, clamped)));
        },
        .serial => 1,
        .threads => |thread_count| @max(@as(u16, 1), thread_count),
    };
}

pub fn resolveParallelConfig(
    workload: ParallelWorkload,
    parallel_config: rastcfg.ParallelConfig,
    report_mode: rastcfg.ReportMode,
) ResolvedParallelConfig {
    const thread_budget = if (report_mode == .full_stats)
        1
    else
        availableThreadBudget(parallel_config);
    const independent_jobs = maxIndependentRenderJobs(workload);
    const jobs_cap = @as(
        u16,
        @intCast(@min(independent_jobs, std.math.maxInt(u16))),
    );
    const render_group_count = @max(
        @as(u16, 1),
        @min(thread_budget, jobs_cap),
    );
    const workers_per_group = @max(
        @as(u16, 1),
        thread_budget / render_group_count,
    );

    const max_geom_workers_per_job = if (workload.element_count >=
        GEOM_THREADING_ELEMENT_THRESHOLD and workers_per_group > 1)
        workers_per_group
    else
        1;

    const max_raster_workers_per_job = if (report_mode == .full_stats)
        1
    else
        workers_per_group;

    return .{
        .total_threads = thread_budget,
        .render_group_count = render_group_count,
        .frame_batch_size_per_group = 1,
        .max_geom_jobs_in_flight_per_group = 1,
        .max_geom_workers_per_job = max_geom_workers_per_job,
        .geom_scheduling_mode = resolveGeometrySchedulingMode(
            .auto,
            workload.element_count,
        ),
        .max_raster_workers_per_job = max_raster_workers_per_job,
    };
}

pub fn frameBatchSize(
    frames_in_flight: u16,
    jobs_num: usize,
) usize {
    return @min(@as(usize, frames_in_flight), jobs_num);
}

pub fn tileSize(
    tile_size_override: ?u16,
    tile_size_min: u16,
    tile_size_max: u16,
    pixels_num: [2]u32,
    sub_sample: u32,
    halo_px: u16,
) u16 {
    if (tile_size_override) |tile_size| {
        return tile_size;
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
        if (subpx_per_tile <= targ_subpx_per_tile) {
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
    dom_len: usize,
    workers_num: usize,
    chunks_per_worker: usize,
) usize {
    if (dom_len == 0) {
        return 1;
    }

    const actual_workers = @max(@as(usize, 1), workers_num);
    const chunk_count = @max(
        @as(usize, 1),
        actual_workers * chunks_per_worker,
    );
    return @max(@as(usize, 1), (dom_len + chunk_count - 1) / chunk_count);
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

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

test "resolveParallelConfig single job serial" {
    const workload = ParallelWorkload{
        .camera_count = 1,
        .frame_count = 1,
        .element_count = 100,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .serial, .off);
    try std.testing.expectEqual(@as(u16, 1), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 1), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_geom_workers_per_job);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig single job 16 threads" {
    const workload = ParallelWorkload{
        .camera_count = 1,
        .frame_count = 1,
        .element_count = 100,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 16 }, .off);
    try std.testing.expectEqual(@as(u16, 16), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 1), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_geom_workers_per_job);
    try std.testing.expectEqual(@as(u16, 16), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig 8 jobs 16 threads offline" {
    const workload = ParallelWorkload{
        .camera_count = 2,
        .frame_count = 4,
        .element_count = 100,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 16 }, .off);
    try std.testing.expectEqual(@as(u16, 16), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 8), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_geom_workers_per_job);
    try std.testing.expectEqual(@as(u16, 2), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig 20 jobs 16 threads offline" {
    const workload = ParallelWorkload{
        .camera_count = 2,
        .frame_count = 10,
        .element_count = 100,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 16 }, .off);
    try std.testing.expectEqual(@as(u16, 16), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 16), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_geom_workers_per_job);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig in_order limits concurrency to cameras" {
    const workload = ParallelWorkload{
        .camera_count = 2,
        .frame_count = 10,
        .element_count = 100,
        .render_mode = .in_order,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 16 }, .off);
    try std.testing.expectEqual(@as(u16, 16), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 2), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 8), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig large geometry enables geom workers" {
    const workload = ParallelWorkload{
        .camera_count = 1,
        .frame_count = 1,
        .element_count = 1_500_000,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 8 }, .off);
    try std.testing.expectEqual(@as(u16, 8), resolved.max_geom_workers_per_job);
    try std.testing.expectEqual(@as(u16, 8), resolved.max_raster_workers_per_job);
}

test "resolveParallelConfig full_stats forces single raster worker" {
    const workload = ParallelWorkload{
        .camera_count = 1,
        .frame_count = 1,
        .element_count = 100,
        .render_mode = .offline,
    };
    const resolved = resolveParallelConfig(workload, .{ .threads = 8 }, .full_stats);
    try std.testing.expectEqual(@as(u16, 1), resolved.total_threads);
    try std.testing.expectEqual(@as(u16, 1), resolved.render_group_count);
    try std.testing.expectEqual(@as(u16, 1), resolved.max_raster_workers_per_job);
}
