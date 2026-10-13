// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const F = @import("buildconfig.zig").F;
const rops = @import("rasterfrontend.zig");
const bin = @import("elemtilebinning.zig");
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const scalingpolicy = @import("scalingpolicy.zig");
const pce = @import("parachunkexec.zig");
const mo = @import("meshpipeline.zig");
const MeshPrepared = mo.MeshPrepared;
const NDArray = @import("ndarray.zig").NDArray;
const Timestamp = std.Io.Clock.Timestamp;
const rasterreport = @import("rasterreport.zig");
const common = @import("rasterengine_common.zig");
const exec = @import("rasterengine_exec_common.zig");
const cfg = @import("buildconfig.zig").config;
const SelectedBackend = if (cfg.simd == .on)
    @import("rasterengine_globbuff_simd.zig").GlobalBackend
else
    @import("rasterengine_globbuff_scalar.zig").GlobalBackend;
const subpxframe = @import("subpxframe_globbuff.zig");

pub fn rasterSceneGlobBuff(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: bin.TilingOverlaps,
    meshes: []const MeshPrepared,
    root_inputs: mo.MeshRootInputs,
    target: *subpxframe.SubpxTarget,
    image_out_arr: *NDArray(F),
) !usize {
    return rasterSceneGlobBuffImpl(
        SelectedBackend,
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        requested_workers,
        tiling,
        meshes,
        root_inputs,
        target,
        image_out_arr,
    );
}

fn rasterSceneGlobBuffImpl(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: bin.TilingOverlaps,
    meshes: []const MeshPrepared,
    root_inputs: mo.MeshRootInputs,
    target: *subpxframe.SubpxTarget,
    image_out_arr: *NDArray(F),
) !usize {
    if (tiling.active_tiles.len == 0) return 0;

    const WorkerState = comptime exec.ThreadState(RasterBackend, report_mode);
    const GlobalTileRangeCtx = struct {
        io: std.Io,
        ctx_rast: rops.RasterContext,
        shared_log: *report.LogType(report_mode),
        tiling: bin.TilingOverlaps,
        meshes: []const MeshPrepared,
        root_inputs: mo.MeshRootInputs,
        target: *subpxframe.SubpxTarget,
        worker_states: []WorkerState,
        subpx_tile_size: usize,
    };
    const TileRangeWorkerAdapter = struct {
        fn run(
            ctx_ptr: *anyopaque,
            worker_idx: usize,
            range_start: usize,
            range_end: usize,
        ) anyerror!void {
            const tile_rng_ctx: *GlobalTileRangeCtx = @ptrCast(@alignCast(ctx_ptr));
            const worker_state = &tile_rng_ctx.worker_states[worker_idx];
            const ctx_report_task = report.ReportContext(report_mode){
                .log = if (comptime report_mode == .full_stats)
                    tile_rng_ctx.shared_log
                else
                    &worker_state.log,
            };

            for (range_start..range_end) |tile_idx| {
                const tile = tile_rng_ctx.tiling.active_tiles[tile_idx];
                RasterBackend.configureTarget(
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.target,
                    tile,
                );
                const tile_scope: ?rasterreport.TileScope =
                    if (comptime report_mode == .full_stats)
                        rasterreport.beginTile(tile_rng_ctx.io)
                    else
                        null;
                RasterBackend.resetSubpxScratch(
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.subpx_tile_size,
                    tile_rng_ctx.ctx_rast.config.background_value,
                );
                const result = try common.rasterTileCore(
                    RasterBackend,
                    report_mode,
                    tile_rng_ctx.io,
                    tile_rng_ctx.ctx_rast,
                    ctx_report_task,
                    tile,
                    tile_rng_ctx.tiling.overlaps,
                    tile_rng_ctx.meshes,
                    tile_rng_ctx.root_inputs,
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.subpx_tile_size,
                );
                const tile_duration_ns: u64 = if (comptime report_mode == .full_stats)
                    @intCast(tile_scope.?.start.durationTo(
                        Timestamp.now(tile_rng_ctx.io, .awake),
                    ).raw.nanoseconds)
                else
                    0;
                rasterreport.finishTile(
                    ctx_report_task,
                    tile_rng_ctx.ctx_rast,
                    tile,
                    tile_duration_ns,
                    result.shaded_px,
                    tile.overlap_count,
                    result.cam_duration_ns,
                    result.elem_duration_ns,
                    0,
                );
                worker_state.rasterized_tiles += 1;
            }
        }
    };

    const workers_num = scalingpolicy.rasterWorkers(
        requested_workers,
        tiling.active_tiles.len,
    );
    var chunk_exec = pce.ParaChunkExecutor.init(io, @intCast(workers_num));
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const worker_states = try arena_alloc.alloc(WorkerState, workers_num);
    var initialized_num: usize = 0;
    defer for (worker_states[0..initialized_num]) |*worker_state| {
        worker_state.deinit();
    };
    for (worker_states) |*worker_state| {
        worker_state.* = try WorkerState.init(
            arena_alloc,
            image_out_arr.dims[0],
            exec.tileScratchSubpxSize(ctx_rast),
        );
        initialized_num += 1;
    }

    var tile_range_ctx = GlobalTileRangeCtx{
        .io = io,
        .ctx_rast = ctx_rast,
        .shared_log = ctx_report.log,
        .tiling = tiling,
        .meshes = meshes,
        .root_inputs = root_inputs,
        .target = target,
        .worker_states = worker_states,
        .subpx_tile_size = exec.tileScratchSubpxSize(ctx_rast),
    };
    try chunk_exec.runDynRangeWithWorkerErr(
        &tile_range_ctx,
        TileRangeWorkerAdapter.run,
        tiling.active_tiles.len,
        scalingpolicy.rasterGrainSize(tiling.active_tiles.len, workers_num),
    );

    if (comptime report_mode == .bench) {
        if (report.getBenchLog(report_mode, ctx_report.log)) |bench_log| {
            for (worker_states) |*worker_state| {
                report.reduceBenchLog(bench_log, &worker_state.log);
            }
        }
    }
    var workers_used: usize = 0;
    for (worker_states) |worker_state| {
        if (worker_state.rasterized_tiles > 0) workers_used += 1;
    }
    return workers_used;
}
