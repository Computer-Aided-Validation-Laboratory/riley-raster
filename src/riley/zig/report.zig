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
const F = buildconfig.F;
const cam = @import("camera.zig");
const meshpipe = @import("meshpipeline.zig");
const rastcfg = @import("rasterconfig.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const elemtilebin = @import("elemtilebinning.zig");
pub const ReportMode = rastcfg.ReportMode;

/// A zero timestamp keeps existing duration arithmetic inert when reporting is off.
pub inline fn timestamp(io: std.Io, mode: ReportMode) std.Io.Clock.Timestamp {
    return if (mode == .bench)
        std.Io.Clock.Timestamp.now(io, .awake)
    else
        .{ .raw = .zero, .clock = .awake };
}

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const OffLog = struct {};

pub const GlobalSubpxStats = struct {
    mode: rastcfg.BufferMode = .tile_local,
    output_w_subpx: usize = 0,
    output_h_subpx: usize = 0,
    outer_halo_subpx: usize = 0,
    tile_core_subpx: usize = 0,
    tile_scratch_subpx: usize = 0,
    tile_grid_count: usize = 0,
    active_tile_count: usize = 0,
    overlap_refs_total: usize = 0,
    overlap_refs_max: usize = 0,
    stripe_core_subpx: usize = 0,
    stripe_count: usize = 0,
    final_stripe_core_subpx: usize = 0,
    stripe_storage_w_subpx: usize = 0,
    stripe_storage_h_subpx: usize = 0,
    stripe_storage_samples_cleared: u64 = 0,
};

pub const GlobalSubpxTimes = struct {
    buffer_setup: F = 0,
    tile_raster: F = 0,
    resolve: F = 0,
};

pub const FrameTimes = struct {
    setup_frame_buff: F = 0,
    prepare_frame_context: F = 0,
    geometry_prep: F = 0,
    geom_coord_ops: F = 0,
    geom_cull_ops: F = 0,
    geom_prep_hulls_shaders: F = 0,
    geom_remap_inds: F = 0,
    tile_overlap: F = 0,
    raster_loop: F = 0,
    raster_workers_requested: u16 = 0,
    raster_workers_used: u16 = 0,
    resolve_workers_requested: u16 = 0,
    resolve_workers_used: u16 = 0,
    cam_invert: F = 0,
    elem_loop: F = 0,
    scratch_resolve: F = 0,
    global_subpx_times: GlobalSubpxTimes = .{},
    global_subpx_stats: ?GlobalSubpxStats = null,
    save_frame: F = 0,
    active_time: F = 0,
    latency_time: F = 0,
};

pub fn rasterStageTime(frame_times: FrameTimes) F {
    if (frame_times.global_subpx_stats != null) {
        return frame_times.tile_overlap +
            frame_times.global_subpx_times.buffer_setup +
            frame_times.global_subpx_times.tile_raster +
            frame_times.global_subpx_times.resolve;
    }
    return frame_times.raster_loop;
}

pub fn initGlobalSubpxStats(
    buffer_mode: rastcfg.BufferMode,
    pixels_num: [2]u32,
    sub_sample: u32,
    halo_px: u16,
    actual_tile_size: u16,
    frame_times: *FrameTimes,
) void {
    const sub_samp: usize = @intCast(sub_sample);
    frame_times.global_subpx_stats = .{
        .mode = buffer_mode,
        .output_w_subpx = @as(usize, pixels_num[0]) * sub_samp,
        .output_h_subpx = @as(usize, pixels_num[1]) * sub_samp,
        .outer_halo_subpx = @as(usize, halo_px) * sub_samp,
        .tile_core_subpx = @as(usize, actual_tile_size) * sub_samp,
        .tile_scratch_subpx = (@as(usize, actual_tile_size) +
            2 * @as(usize, halo_px)) * sub_samp,
    };
}

pub fn recordTilingStatsGlobBuff(
    tiling: elemtilebin.TileElemOverlaps,
    tile_grid_count: usize,
    stats: *GlobalSubpxStats,
) void {
    stats.tile_grid_count += tile_grid_count;
    stats.active_tile_count += tiling.active_tiles.len;
    stats.overlap_refs_total += tiling.overlaps.len;
    for (tiling.active_tiles) |tile| {
        stats.overlap_refs_max = @max(stats.overlap_refs_max, tile.overlap_count);
    }
}

pub fn recordGlobalSubpxStats(
    pixels_num: [2]u32,
    actual_tile_size: u16,
    tiling: elemtilebin.TileElemOverlaps,
    frame_times: *FrameTimes,
) void {
    if (frame_times.global_subpx_stats) |*stats| {
        const tiles_x = std.math.divCeil(
            usize,
            pixels_num[0],
            actual_tile_size,
        ) catch unreachable;
        const tiles_y = std.math.divCeil(
            usize,
            pixels_num[1],
            actual_tile_size,
        ) catch unreachable;
        recordTilingStatsGlobBuff(tiling, tiles_x * tiles_y, stats);
    }
}

pub fn recordGlobalSubpxStripeStats(
    cam_w_px: u32,
    actual_tile_size: u16,
    core_suby_min: usize,
    core_suby_max: usize,
    sub_samp: usize,
    stripe_subpx: usize,
    storage_w_subpx: usize,
    storage_h_subpx: usize,
    stripe_tiling: elemtilebin.TileElemOverlaps,
    frame_times: *FrameTimes,
) void {
    if (frame_times.global_subpx_stats) |*stats| {
        const tiles_x = std.math.divCeil(
            usize,
            cam_w_px,
            actual_tile_size,
        ) catch unreachable;
        const stripe_h_px = (core_suby_max - core_suby_min) / sub_samp;
        const tiles_y = std.math.divCeil(
            usize,
            stripe_h_px,
            actual_tile_size,
        ) catch unreachable;
        recordTilingStatsGlobBuff(stripe_tiling, tiles_x * tiles_y, stats);

        stats.stripe_core_subpx = stripe_subpx;
        stats.stripe_count += 1;
        stats.final_stripe_core_subpx = core_suby_max - core_suby_min;
        stats.stripe_storage_w_subpx = storage_w_subpx;
        stats.stripe_storage_h_subpx = storage_h_subpx;
        stats.stripe_storage_samples_cleared += @intCast(
            storage_w_subpx * storage_h_subpx,
        );
    }
}

pub const EndToEndTimes = struct {
    setup_time: F = 0,
    setup_other_time: F = 0,
    setup_frame_buff_time: F = 0,
    dispatch_time: F = 0,
    total_time: F = 0,
};

pub const BenchLog = struct {
    frame_times: FrameTimes = .{},
    total_nodes: usize = 0,
    total_elems: usize = 0,
    vis_elems: usize = 0,
    solver_calls: u64 = 0,
    total_solver_iters: u64 = 0,
    solver_diverged: u64 = 0,
    coherent: CoherentStats = .{},
    tess_checks: u64 = 0,
    tess_passes: u64 = 0,
    total_shaded_px: u64 = 0,
    total_depth_test: u64 = 0,
    depth_tests_fail: u64 = 0,
    max_tile_elems: usize = 0,
    cam_time_ns: F = 0,
    elem_time_ns: F = 0,
    resolve_time_ns: F = 0,
};

pub const CoherentStats = struct {
    candidate_children: u64 = 0,
    cache_eligible: u64 = 0,
    cache_attempts: u64 = 0,
    cache_successes: u64 = 0,
    cache_failures: u64 = 0,
    extrap_attempts: u64 = 0,
    extrap_successes: u64 = 0,
    center_attempts: u64 = 0,
    center_successes: u64 = 0,
    center_failures: u64 = 0,
    reuse_recoveries: u64 = 0,
    bank_fallbacks: u64 = 0,
    bank_fallback_successes: u64 = 0,
    bank_improved: u64 = 0,
    bank_recovered: u64 = 0,
    bank_numerical_ties: u64 = 0,
    cross_child: u64 = 0,
};

pub const FrameBenchCapture = struct {
    camera_idx: usize,
    frame_idx: usize,
    bench_log: BenchLog,
};

pub const FrameReportStorage = union(ReportMode) {
    off: OffLog,
    bench: BenchLog,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn FrameReportPtr(comptime report_mode: ReportMode) type {
    return *LogType(report_mode);
}

pub fn calcBenchCaptureIdx(
    cameras_num: usize,
    camera_idx: usize,
    frame_idx: usize,
) usize {
    return frame_idx * cameras_num + camera_idx;
}

// --------------------------------------------------------------------------------------
// Publish Pipeline
// --------------------------------------------------------------------------------------

pub fn publishFrameResults(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    config: rastcfg.RasterConfig,
    actual_tile_size: u16,
    camera: *const cam.CameraPrepared,
    camera_idx: usize,
    frame_idx: usize,
    cameras_num: usize,
    out_dir: ?std.Io.Dir,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]FrameBenchCapture,
    report_storage: *FrameReportStorage,
    frame_times: FrameTimes,
    total_nodes_num: usize,
    total_elems_num: usize,
    total_elems_in_image: usize,
    prep_meshes: []const meshpipe.MeshPrepared,
) !void {
    const nodes_per_elem = meshpipe.calcNodesPerElem(prep_meshes);
    try publishFrameResultsWithNodesPerElem(
        outer_alloc,
        io,
        config,
        actual_tile_size,
        camera,
        camera_idx,
        frame_idx,
        cameras_num,
        out_dir,
        out_dir_path,
        bench_capture,
        report_storage,
        frame_times,
        total_nodes_num,
        total_elems_num,
        total_elems_in_image,
        nodes_per_elem,
    );
}

pub fn publishFrameResultsWithNodesPerElem(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    config: rastcfg.RasterConfig,
    actual_tile_size: u16,
    camera: *const cam.CameraPrepared,
    camera_idx: usize,
    frame_idx: usize,
    cameras_num: usize,
    out_dir: ?std.Io.Dir,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]FrameBenchCapture,
    report_storage: *FrameReportStorage,
    frame_times: FrameTimes,
    total_nodes_num: usize,
    total_elems_num: usize,
    total_elems_in_image: usize,
    nodes_per_elem: F,
) !void {
    _ = outer_alloc;
    _ = out_dir;
    switch (config.report_perf) {
        .off => {},
        .bench => {
            report_storage.bench.frame_times = frame_times;
            report_storage.bench.total_nodes = total_nodes_num;
            report_storage.bench.total_elems = total_elems_num;
            report_storage.bench.vis_elems = total_elems_in_image;
            if (bench_capture) |capture| {
                const capture_idx = calcBenchCaptureIdx(
                    cameras_num,
                    camera_idx,
                    frame_idx,
                );
                capture[capture_idx] = .{
                    .camera_idx = camera_idx,
                    .frame_idx = frame_idx,
                    .bench_log = report_storage.bench,
                };
            }
            if (config.report_console) try standardReport(
                io,
                camera,
                actual_tile_size,
                frame_idx,
                camera_idx,
                frame_times,
                camera.prep_psf.halo_px,
                out_dir_path,
                total_elems_num,
                total_elems_in_image,
                nodes_per_elem,
                &report_storage.bench,
            );
        },
    }
}

pub fn reduceBenchLog(dst: *BenchLog, src: *const BenchLog) void {
    dst.total_nodes += src.total_nodes;
    dst.solver_calls += src.solver_calls;
    dst.total_solver_iters += src.total_solver_iters;
    dst.solver_diverged += src.solver_diverged;
    inline for (std.meta.fields(CoherentStats)) |field| {
        @field(dst.coherent, field.name) += @field(src.coherent, field.name);
    }
    dst.tess_checks += src.tess_checks;
    dst.tess_passes += src.tess_passes;
    dst.total_shaded_px += src.total_shaded_px;
    dst.total_depth_test += src.total_depth_test;
    dst.depth_tests_fail += src.depth_tests_fail;
    dst.max_tile_elems = @max(
        dst.max_tile_elems,
        src.max_tile_elems,
    );
    dst.cam_time_ns += src.cam_time_ns;
    dst.elem_time_ns += src.elem_time_ns;
    dst.resolve_time_ns += src.resolve_time_ns;
}

pub const ReportLog = union(ReportMode) {
    off: OffLog,
    bench: BenchLog,
};

pub fn LogType(comptime mode: ReportMode) type {
    return switch (mode) {
        .off => OffLog,
        .bench => BenchLog,
    };
}

pub fn getBenchLog(comptime mode: ReportMode, log: *LogType(mode)) ?*BenchLog {
    return switch (mode) {
        .off => null,
        .bench => log,
    };
}

pub fn ReportContext(comptime mode: ReportMode) type {
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
    return struct {
        log: *LogType(mode),

        inline fn bench(self: @This()) ?*BenchLog {
            return getBenchLog(mode, self.log);
        }

        pub const mode_tag = mode;

        pub inline fn recordGeometry(self: @This(), total: usize, vis: usize) void {
            if (self.bench()) |bench_log| {
                bench_log.total_elems = total;
                bench_log.vis_elems = vis;
            }
        }

        pub inline fn recordTile(
            self: @This(),
            shaded_px: u64,
            elem_count: usize,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.total_shaded_px += shaded_px;
                if (elem_count > bench_log.max_tile_elems) {
                    bench_log.max_tile_elems = elem_count;
                }
            }
        }

        pub inline fn recordSolverCalls(self: @This(), solver_calls: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_calls += solver_calls;
            }
        }

        pub inline fn recordCoherentStats(
            self: @This(),
            counts: CoherentStats,
        ) void {
            if (self.bench()) |bench_log| {
                inline for (std.meta.fields(CoherentStats)) |field| {
                    @field(bench_log.coherent, field.name) +=
                        @field(counts, field.name);
                }
            }
        }

        pub inline fn recordSolverIters(self: @This(), solver_iters: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.total_solver_iters += solver_iters;
            }
        }

        pub inline fn recordSolverStats(
            self: @This(),
            solver_calls: u64,
            solver_iters: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_calls += solver_calls;
                bench_log.total_solver_iters += solver_iters;
            }
        }

        pub inline fn recordTessChecks(self: @This(), tess_checks: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.tess_checks += tess_checks;
            }
        }

        pub inline fn recordTessPasses(self: @This(), tess_passes: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.tess_passes += tess_passes;
            }
        }

        pub inline fn recordDepthTest(self: @This(), fail: bool) void {
            if (self.bench()) |bench_log| {
                bench_log.total_depth_test += 1;
                if (fail) {
                    bench_log.depth_tests_fail += 1;
                }
            }
        }

        pub inline fn recordSolverDiverged(self: @This()) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_diverged += 1;
            }
        }

        pub inline fn recordSolverDivergedCount(
            self: @This(),
            diverged_count: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_diverged += diverged_count;
            }
        }

        pub inline fn recordCamTime(
            self: @This(),
            cam_duration_ns: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.cam_time_ns +=
                    @floatFromInt(cam_duration_ns);
            }
        }

        pub inline fn recordElemTime(
            self: @This(),
            elem_duration_ns: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.elem_time_ns +=
                    @floatFromInt(elem_duration_ns);
            }
        }

        pub inline fn recordResolveTime(
            self: @This(),
            resolve_duration_ns: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.resolve_time_ns +=
                    @floatFromInt(resolve_duration_ns);
            }
        }
    };
}

pub fn standardReport(
    io: std.Io,
    camera: *const cam.CameraPrepared,
    actual_tile_size: u16,
    frame_idx: usize,
    camera_idx: usize,
    frame_times: FrameTimes,
    tile_halo_px: u16,
    out_dir_path: ?[]const u8,
    total_elems: usize,
    vis_elems: usize,
    nodes_per_elem: F,
    bench_log: *const BenchLog,
) !void {
    if (frame_times.global_subpx_stats) |stats| {
        return globalSubpxStandardReport(
            io,
            camera,
            frame_idx,
            camera_idx,
            frame_times,
            stats,
            out_dir_path,
            bench_log,
        );
    }
    var buff: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buff);
    const writer = &stdout_writer.interface;

    const px_x = @as(F, @floatFromInt(camera.pixels_num[0]));
    const px_y = @as(F, @floatFromInt(camera.pixels_num[1]));
    const sub_samp_f: F = @as(F, @floatFromInt(camera.sub_sample));

    const total_subpx = px_x * px_y * sub_samp_f * sub_samp_f;
    const total_px = px_x * px_y;

    const raster_sec = frame_times.raster_loop / 1e9;
    const active_sec = frame_times.active_time / 1e9;
    const geom_tiling_sec = (frame_times.geometry_prep + frame_times.tile_overlap) / 1e9;

    const melems_sec = if (geom_tiling_sec > 0)
        (@as(F, @floatFromInt(total_elems)) / (geom_tiling_sec * 1e6))
    else
        0;
    const mnodes_sec = if (geom_tiling_sec > 0)
        (@as(F, @floatFromInt(bench_log.total_nodes)) /
            (geom_tiling_sec * 1e6))
    else
        0;
    const mpx_sec = if (raster_sec > 0) (total_px / (raster_sec * 1e6)) else 0;
    const msubpx_sec = if (raster_sec > 0) (total_subpx / (raster_sec * 1e6)) else 0;
    _ = nodes_per_elem;
    const frame_mpx_sec = if (active_sec > 0)
        (total_px / (active_sec * 1e6))
    else
        0;

    const conv_units: F = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;
    const print_break_inner = [_]u8{'-'} ** 80;

    try writer.print("{s}\nRILEY TILE LOCAL RASTER: Frame {d}, Camera {d}\n{s}\n", .{
        print_break,
        frame_idx,
        camera_idx,
        print_break,
    });

    const shaded_subpx = @as(F, @floatFromInt(bench_log.total_shaded_px));
    const shaded_pct = if (total_subpx > 0)
        (shaded_subpx * 100.0 / total_subpx)
    else
        0;
    const vis_elems_f = @as(F, @floatFromInt(vis_elems));
    const total_elems_f = @as(F, @floatFromInt(total_elems));
    const vis_pct = if (total_elems > 0) (vis_elems_f * 100.0 / total_elems_f) else 0;

    const tile_subpx = @as(usize, actual_tile_size) * camera.sub_sample;

    try writer.print("Camera Pixels              = {d}x{d}\n", .{
        camera.pixels_num[0],
        camera.pixels_num[1],
    });
    try writer.print("Camera Distortion          = {s}\n", .{
        @tagName(camera.distort),
    });
    try writer.print("Camera PSF                 = {s}\n", .{@tagName(camera.psf)});
    try writer.print("Camera Subsamples          = {d}x{d}\n", .{
        camera.sub_sample,
        camera.sub_sample,
    });
    try writer.print("Tile Size Pixels           = {d}x{d}\n", .{
        actual_tile_size,
        actual_tile_size,
    });
    try writer.print("Tile Size Subpixels        = {d}x{d}\n", .{ tile_subpx, tile_subpx });
    try writer.print("Tile Halo Pixels           = {d}\n", .{tile_halo_px});
    try writer.print("{s}\n", .{print_break_inner});

    try writer.print("Vis Elems                  = {d}\n", .{vis_elems});
    try writer.print("Total Elems                = {d}\n", .{total_elems});
    try writer.print("Vis %                      = {d:.2}%\n", .{vis_pct});
    try writer.print("Total SubPx                = {d:.0}\n", .{total_subpx});
    try writer.print("Shaded SubPx               = {d:.0}\n", .{shaded_subpx});
    try writer.print("Shaded %                   = {d:.2}%\n", .{shaded_pct});
    try writer.print("{s}\n", .{print_break_inner});

    try writer.print("Setup Frame Buff           = {d:.6} ms\n", .{
        frame_times.setup_frame_buff * conv_units,
    });
    try writer.print("Prep Frame                 = {d:.6} ms\n", .{
        frame_times.prepare_frame_context * conv_units,
    });
    try writer.print("Geometry Preparation       = {d:.6} ms\n", .{
        frame_times.geometry_prep * conv_units,
    });
    try writer.print("  Coord Ops                = {d:.6} ms\n", .{
        frame_times.geom_coord_ops * conv_units,
    });
    try writer.print("  Cull Ops                 = {d:.6} ms\n", .{
        frame_times.geom_cull_ops * conv_units,
    });
    try writer.print("  Prep Hulls Shaders       = {d:.6} ms\n", .{
        frame_times.geom_prep_hulls_shaders * conv_units,
    });
    try writer.print("  Remap Inds               = {d:.6} ms\n", .{
        frame_times.geom_remap_inds * conv_units,
    });
    try writer.print("Elem/Tile Overlap          = {d:.6} ms\n", .{
        frame_times.tile_overlap * conv_units,
    });
    const cam_inv_print_ms =
        frame_times.cam_invert * conv_units;
    const resolve_print_ms =
        frame_times.scratch_resolve * conv_units;
    const elem_loop_print_ms = frame_times.elem_loop * conv_units;
    try writer.print("Cam Invert Time            = {d:.6} ms\n", .{
        cam_inv_print_ms,
    });
    try writer.print("Elem Loop Time             = {d:.6} ms\n", .{
        elem_loop_print_ms,
    });
    try writer.print("Scratch Resolve Time       = {d:.6} ms\n", .{
        resolve_print_ms,
    });
    try writer.print("Raster Loop                = {d:.6} ms\n", .{
        frame_times.raster_loop * conv_units,
    });
    try writer.print("Save Frame                 = {d:.6} ms\n", .{
        frame_times.save_frame * conv_units,
    });

    try writer.print("{s}\n", .{print_break_inner});
    try writer.print("ACTIVE FRAME TIME          = {d:.3} ms\n", .{
        frame_times.active_time * conv_units,
    });
    try writer.print("FRAME LATENCY              = {d:.3} ms\n", .{
        frame_times.latency_time * conv_units,
    });
    try writer.print("{s}\n", .{print_break_inner});

    try writer.print("Geom. Node Throughput      = {d:.2} MNodes/s\n", .{mnodes_sec});
    try writer.print("Geom. Elem. Throughput     = {d:.2} MElem/s\n", .{melems_sec});
    try writer.print("Subpx Raster Throughput    = {d:.2} MSubPx/s\n", .{msubpx_sec});
    try writer.print("Raster Throughput          = {d:.2} MPx/s\n", .{mpx_sec});
    try writer.print("Active Frame Throughput    = {d:.2} MPx/s\n", .{frame_mpx_sec});

    if (out_dir_path) |path| {
        try writer.print("Output Frame Path          = {s}\n", .{path});
    } else {
        try writer.print("Output Frame Path          = not written (memory output)\n", .{});
    }
    try writer.print("{s}\n", .{print_break});
    try writer.flush();
}

fn globalSubpxStandardReport(
    io: std.Io,
    camera: *const cam.CameraPrepared,
    frame_idx: usize,
    camera_idx: usize,
    frame_times: FrameTimes,
    stats: GlobalSubpxStats,
    out_dir_path: ?[]const u8,
    bench_log: *const BenchLog,
) !void {
    var buff: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buff);
    const writer = &stdout_writer.interface;
    const stats_break = [_]u8{'='} ** 80;
    const section_break = [_]u8{'-'} ** 80;
    const conv: F = 1.0 / 1.0e6;
    const output_samples = @as(F, @floatFromInt(
        stats.output_w_subpx * stats.output_h_subpx,
    ));
    const output_px = output_samples / @as(F, @floatFromInt(
        camera.sub_sample * camera.sub_sample,
    ));
    const active_tiles = @as(F, @floatFromInt(stats.active_tile_count));
    const mean_refs = if (stats.active_tile_count > 0)
        @as(F, @floatFromInt(stats.overlap_refs_total)) / active_tiles
    else
        0.0;
    const empty_tiles = stats.tile_grid_count -| stats.active_tile_count;
    const buffer_planning = frame_times.tile_overlap +
        frame_times.global_subpx_times.buffer_setup;
    const raster_sec = frame_times.global_subpx_times.tile_raster / 1e9;
    const resolve_sec = frame_times.global_subpx_times.resolve / 1e9;
    const active_sec = frame_times.active_time / 1e9;
    const shaded = @as(F, @floatFromInt(bench_log.total_shaded_px));
    const shade_rate = if (raster_sec > 0)
        shaded / (raster_sec * 1e6)
    else
        0.0;
    const sample_rate = if (raster_sec > 0)
        output_samples / (raster_sec * 1e6)
    else
        0.0;
    const resolve_rate = if (resolve_sec > 0)
        output_px / (resolve_sec * 1e6)
    else
        0.0;
    const active_rate = if (active_sec > 0)
        output_px / (active_sec * 1e6)
    else
        0.0;

    try writer.print("{s}\nRILEY GLOBAL SUBPIXEL RASTER: Frame {d}, Camera {d}\n{s}\n", .{
        stats_break,
        frame_idx,
        camera_idx,
        stats_break,
    });
    try writer.print("Mode                         = {s}\n", .{@tagName(stats.mode)});
    try writer.print("Output Core                  = {d} x {d} px | {d} x {d} subpx\n", .{
        camera.pixels_num[0],
        camera.pixels_num[1],
        stats.output_w_subpx,
        stats.output_h_subpx,
    });
    try writer.print("Subsample                    = {d} x {d}\n", .{
        camera.sub_sample,
        camera.sub_sample,
    });
    try writer.print("PSF / Support                = {s} | {d} px\n", .{
        @tagName(camera.psf),
        camera.prep_psf.halo_px,
    });
    try writer.print("{s}\nTILE DOMAIN\n", .{section_break});
    try writer.print("Tile Core                    = {d} x {d} subpx\n", .{
        stats.tile_core_subpx,
        stats.tile_core_subpx,
    });
    try writer.print("Interior Tile Halo           = 0 x 0 px\n", .{});
    try writer.print("Outer Frame Halo             = {d} x {d} subpx\n", .{
        stats.outer_halo_subpx,
        stats.outer_halo_subpx,
    });
    try writer.print("Scratch Capacity             = {d} x {d} subpx\n", .{
        stats.tile_scratch_subpx,
        stats.tile_scratch_subpx,
    });
    try writer.print("Raster Workers (Req / Used)  = {d} / {d}\n", .{
        frame_times.raster_workers_requested,
        frame_times.raster_workers_used,
    });
    try writer.print("Resolve Workers (Req / Used) = {d} / {d}\n", .{
        frame_times.resolve_workers_requested,
        frame_times.resolve_workers_used,
    });
    try writer.print("Tile Grid / Active / Empty   = {d} / {d} / {d}\n", .{
        stats.tile_grid_count,
        stats.active_tile_count,
        empty_tiles,
    });
    try writer.print("Overlap Refs / Active Tile   = mean {d:.2} | max {d}\n", .{
        mean_refs,
        stats.overlap_refs_max,
    });
    if (stats.mode == .global_subpx_stripe) {
        const repeated_storage = stats.stripe_storage_samples_cleared -|
            stats.output_w_subpx * stats.output_h_subpx;
        try writer.print("{s}\nSTRIPE DOMAIN\n", .{section_break});
        try writer.print(
            "Core Height                  = {d} subpx\n",
            .{stats.stripe_core_subpx},
        );
        try writer.print("Stripe Count / Final Height  = {d} / {d} subpx\n", .{
            stats.stripe_count,
            stats.final_stripe_core_subpx,
        });
        try writer.print("Stripe Edge Halo             = x: {d} | y: {d} subpx\n", .{
            stats.outer_halo_subpx,
            stats.outer_halo_subpx,
        });
        try writer.print("Peak Stripe Storage          = {d} x {d} subpx\n", .{
            stats.stripe_storage_w_subpx,
            stats.stripe_storage_h_subpx,
        });
        try writer.print("Repeated Halo Storage        = {d} samples\n", .{repeated_storage});
    }
    try writer.print("{s}\nWALL-CLOCK TIMINGS\n", .{section_break});
    try writer.print("Global Buffer + Planning     = {d:.3} ms\n", .{buffer_planning * conv});
    try writer.print("Global Tile Raster           = {d:.3} ms\n", .{
        frame_times.global_subpx_times.tile_raster * conv,
    });
    try writer.print("Global Resolve               = {d:.3} ms\n", .{
        frame_times.global_subpx_times.resolve * conv,
    });
    try writer.print(
        "Save Frame                   = {d:.3} ms\n",
        .{frame_times.save_frame * conv},
    );
    try writer.print(
        "Active Frame                 = {d:.3} ms\n",
        .{frame_times.active_time * conv},
    );
    try writer.print(
        "Frame Latency                = {d:.3} ms\n",
        .{frame_times.latency_time * conv},
    );
    try writer.print("{s}\nRATES\n", .{section_break});
    try writer.print("Executed Shade Rate          = {d:.3} Msubpx/s\n", .{shade_rate});
    try writer.print("Output Sample Rate           = {d:.3} Msubpx/s\n", .{sample_rate});
    try writer.print("Global Resolve Rate          = {d:.3} MPx/s\n", .{resolve_rate});
    try writer.print("Active Frame Rate            = {d:.3} MPx/s\n", .{active_rate});
    try writer.print("{s}\n", .{section_break});
    if (out_dir_path) |path| {
        try writer.print("Output Frame Path            = {s}\n", .{path});
    } else {
        try writer.print("Output Frame Path            = not written (memory output)\n", .{});
    }
    try writer.print("{s}\n", .{stats_break});
    try writer.flush();
}

pub fn printRenderSummary(
    io: std.Io,
    cameras: []const cam.CameraPrepared,
    config: rastcfg.RasterConfig,
    num_time: usize,
    report_mode: ReportMode,
    end_to_end_times: EndToEndTimes,
    bench_capture: ?[]const FrameBenchCapture,
) !void {
    if (!config.report_console) return;
    if (report_mode == .off) {
        var brief_buff: [256]u8 = undefined;
        var brief_writer = std.Io.File.stdout().writer(io, &brief_buff);
        try brief_writer.interface.print(
            "Riley render complete: {d} camera(s), {d} frame(s).\n",
            .{ cameras.len, num_time },
        );
        try brief_writer.interface.flush();
        return;
    }

    var total_pixels: usize = 0;
    for (cameras) |camera| {
        total_pixels += camera.pixels_num[0] * camera.pixels_num[1];
    }
    total_pixels *= num_time;

    const actual_tile_size = switch (config.advanced.raster.buffer_mode) {
        .tile_local => scalingpolicy.tileSize(
            config.advanced.raster.tile_size_override,
            config.advanced.raster.tile_size_min,
            config.advanced.raster.tile_size_max,
            cameras[0].pixels_num,
            cameras[0].sub_sample,
            cameras[0].prep_psf.halo_px,
        ),
        .global_subpx_full, .global_subpx_stripe => @divExact(
            config.advanced.raster.global_subpx_tile_size_override orelse
                config.advanced.raster.global_subpx_tile_size_min,
            @as(u16, @intCast(cameras[0].sub_sample)),
        ),
    };

    const total_frames = cameras.len * num_time;
    const total_render_ms = end_to_end_times.total_time / 1e6;
    const total_render_sec = end_to_end_times.total_time / 1e9;
    const setup_ms = end_to_end_times.setup_time / 1e6;
    // const setup_other_ms = end_to_end_times.setup_other_time / 1e6;
    // const setup_frame_buff_ms =
    //     end_to_end_times.setup_frame_buff_time / 1e6;
    const dispatch_ms = end_to_end_times.dispatch_time / 1e6;
    const avg_frame_ms = total_render_ms / @as(
        F,
        @floatFromInt(total_frames),
    );
    const avg_frame_mpx_sec = if (total_render_sec > 0)
        @as(F, @floatFromInt(total_pixels)) / (total_render_sec * 1e6)
    else
        0.0;
    var total_raster_ns: F = 0.0;
    if (bench_capture) |capture| {
        for (capture) |frame_capture| {
            total_raster_ns += rasterStageTime(frame_capture.bench_log.frame_times);
        }
    }
    const total_raster_sec = total_raster_ns / 1e9;
    const avg_raster_mpx_sec = if (total_raster_sec > 0)
        @as(F, @floatFromInt(total_pixels)) / (total_raster_sec * 1e6)
    else
        0.0;

    var buff: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buff);
    const writer = &stdout_writer.interface;
    const print_break = [_]u8{'='} ** 80;

    try writer.print("{s}\nRILEY RASTER RENDER SUMMARY\n{s}\n", .{
        print_break,
        print_break,
    });
    try writer.print("Buffer Mode             = {s}\n", .{
        @tagName(config.advanced.raster.buffer_mode),
    });
    if (config.advanced.raster.buffer_mode != .tile_local) {
        const global_tile_subpx = @as(usize, actual_tile_size) *
            @as(usize, cameras[0].sub_sample);
        try writer.print("Global Raster Tile      = {d} subpx\n", .{global_tile_subpx});
        if (config.advanced.raster.buffer_mode == .global_subpx_stripe) {
            const stripe_subpx =
                config.advanced.raster.global_subpx_stripe_size_override orelse
                config.advanced.raster.global_subpx_stripe_size_min;
            try writer.print("Global Stripe Height    = {d} subpx\n", .{stripe_subpx});
        }
    }
    try writer.print("Setup Time              = {d:.3} ms\n", .{setup_ms});
    // try writer.print("Setup other             = {d:.3} ms\n", .{
    //     setup_other_ms,
    // });
    // try writer.print("Setup frame buff      = {d:.3} ms\n", .{
    //     setup_frame_buff_ms,
    // });
    try writer.print("Dispatch Time           = {d:.3} ms\n", .{dispatch_ms});
    try writer.print("Total Render Time       = {d:.3} ms\n", .{total_render_ms});
    try writer.print("Avg. Frame Time         = {d:.3} ms\n", .{avg_frame_ms});
    if (bench_capture != null) {
        try writer.print(
            "Avg. Raster Throughput = {d:.3} MPx/s\n",
            .{avg_raster_mpx_sec},
        );
    }
    try writer.print(
        "Avg. Frame Throughput   = {d:.3} MPx/s\n",
        .{avg_frame_mpx_sec},
    );
    try writer.print("{s}\n", .{print_break});
    try writer.flush();
}
