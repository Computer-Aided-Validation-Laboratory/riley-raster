// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const rasterconfig = @import("rasterconfig.zig");
const ndarray = @import("ndarray.zig");
const scratchresolve_common = @import("scratchresolve_common.zig");
const meshtypes = @import("meshtypes.zig");
const std = @import("std");
const F = @import("buildconfig.zig").F;
const rasterfrontend = @import("rasterfrontend.zig");
const elemtilebinning = @import("elemtilebinning.zig");
const report = @import("report.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const parachunkexec = @import("parachunkexec.zig");
const rasterreport = @import("rasterreport.zig");
const rasterengine_common = @import("rasterengine_common.zig");
const cfg = @import("buildconfig.zig").config;
const scratchresolve = @import("scratchresolve.zig");

const kernel = if (cfg.simd == .on)
    @import("rasterengine_simd.zig")
else
    @import("rasterengine_scalar.zig");

const SelectedRasterBackend = struct {
    pub const SubpxScratchBuffs = kernel.SubpxScratchBuffs;
    pub const initSubpxScratch = kernel.initSubpxScratch;
    pub const resetSubpxScratch = kernel.resetSubpxScratch;

    pub fn RasterEngine(
        comptime GeomKern: type,
        comptime ShaderKern: type,
        comptime ShaderData: type,
        comptime root_class: rasterfrontend.ElemRootClass,
    ) type {
        return kernel.RasterEngine(
            kernel.SubpxScratchBuffs,
            GeomKern,
            ShaderKern,
            ShaderData,
            root_class,
        );
    }
};

pub fn rasterSceneTileLoc(
    comptime report_mode: rasterconfig.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rasterfrontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: elemtilebinning.TileElemOverlaps,
    meshes: []const meshtypes.MeshPrepared,
    mesh_hulls: meshtypes.MeshHulls,
    image_out_arr: *ndarray.NDArray(F),
) !void {
    try rasterSceneTileLocImpl(
        SelectedRasterBackend,
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        requested_workers,
        tiling,
        meshes,
        mesh_hulls,
        image_out_arr,
    );
}

fn rasterSceneTileLocImpl(
    comptime RasterBackend: type,
    comptime report_mode: rasterconfig.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rasterfrontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: elemtilebinning.TileElemOverlaps,
    meshes: []const meshtypes.MeshPrepared,
    mesh_hulls: meshtypes.MeshHulls,
    image_out_arr: *ndarray.NDArray(F),
) !void {
    const WorkerState = comptime ThreadState(RasterBackend, report_mode);

    const TileRangeCtx = TileRangeContext(RasterBackend, report_mode);

    const TileRangeWorkerAdapter = struct {
        fn run(
            ctx_ptr: *anyopaque,
            worker_idx: usize,
            range_start: usize,
            range_end: usize,
        ) anyerror!void {
            const tile_rng_ctx: *TileRangeCtx = @ptrCast(@alignCast(ctx_ptr));
            const worker_state = &tile_rng_ctx.worker_states[worker_idx];

            const ctx_report_task = report.ReportContext(report_mode){
                .log = &worker_state.log,
            };

            for (range_start..range_end) |tile_idx| {
                const tile = tile_rng_ctx.tiling.active_tiles[tile_idx];

                try rasterTileLoc(
                    RasterBackend,
                    report_mode,
                    tile_rng_ctx.io,
                    tile_rng_ctx.ctx_rast,
                    ctx_report_task,
                    tile,
                    tile_rng_ctx.tiling.overlaps,
                    tile_rng_ctx.meshes,
                    tile_rng_ctx.mesh_hulls,
                    tile_rng_ctx.image_out_arr,
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.fields_num,
                    tile_rng_ctx.subpx_tile_size,
                );
            }
        }
    };

    const workers_num = scalingpolicy.rasterWorkers(
        requested_workers,
        tiling.active_tiles.len,
    );
    const workers_num_u16: u16 = @intCast(workers_num);
    var chunk_exec = parachunkexec.ParaChunkExecutor.init(io, workers_num_u16);

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const worker_states = try arena_alloc.alloc(WorkerState, workers_num);
    var worker_states_initialized: usize = 0;
    defer for (worker_states[0..worker_states_initialized]) |*worker_state| {
        worker_state.deinit();
    };

    for (worker_states) |*worker_state| {
        worker_state.* = try WorkerState.init(
            arena_alloc,
            image_out_arr.dims[0],
            rasterengine_common.tileScratchSubpxSize(ctx_rast),
        );
        worker_states_initialized += 1;
    }

    var tile_range_ctx = TileRangeCtx{
        .io = io,
        .ctx_rast = ctx_rast,
        .tiling = tiling,
        .meshes = meshes,
        .mesh_hulls = mesh_hulls,
        .image_out_arr = image_out_arr,
        .worker_states = worker_states,
        .shared_log = ctx_report.log,
        .fields_num = @intCast(image_out_arr.dims[0]),
        .subpx_tile_size = rasterengine_common.tileScratchSubpxSize(ctx_rast),
    };

    try chunk_exec.runDynRangeWithWorkerErr(
        &tile_range_ctx,
        TileRangeWorkerAdapter.run,
        tiling.active_tiles.len,
        scalingpolicy.rasterGrainSize(
            tiling.active_tiles.len,
            workers_num,
        ),
    );

    if (comptime report_mode == .bench) {
        if (report.getBenchLog(report_mode, ctx_report.log)) |bench_log| {
            for (worker_states) |*worker_state| {
                report.reduceBenchLog(bench_log, &worker_state.log);
            }
        }
    }
}

fn rasterTileLoc(
    comptime RasterBackend: type,
    comptime report_mode: rasterconfig.ReportMode,
    io: std.Io,
    ctx_rast: rasterfrontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebinning.ActiveTile,
    overlaps_all: []const elemtilebinning.OverlapBBox,
    meshes: []const meshtypes.MeshPrepared,
    mesh_hulls: meshtypes.MeshHulls,
    image_out_arr: *ndarray.NDArray(F),
    subpx_scratch: *RasterBackend.SubpxScratchBuffs,
    fields_num: u8,
    subpx_tile_size: usize,
) !void {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const scratch_geom = scratchresolve_common.ScratchTileGeometry.init(tile, sub_samp);

    RasterBackend.resetSubpxScratch(
        subpx_scratch,
        subpx_tile_size,
        ctx_rast.camera.background_value,
    );

    const result = try rasterengine_common.rasterTileCore(
        RasterBackend,
        report_mode,
        io,
        ctx_rast,
        ctx_report,
        tile,
        overlaps_all,
        meshes,
        mesh_hulls,
        subpx_scratch,
        subpx_tile_size,
    );

    const time_resolve_start: ?std.Io.Clock.Timestamp =
        if (comptime report_mode != .off) std.Io.Clock.Timestamp.now(io, .awake) else null;

    if (ctx_rast.camera.prep_psf.hasFilter()) {
        scratchresolve.resolveTileWithPSF(
            tile,
            sub_samp,
            subpx_tile_size,
            fields_num,
            ctx_rast.camera.background_value,
            ctx_rast.camera.prep_psf,
            scratch_geom,
            &subpx_scratch.image,
            &subpx_scratch.filter_tmp,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    } else if (sub_samp > 1) {
        scratchresolve.avgScratch(
            tile,
            scratch_geom,
            @intCast(sub_samp),
            subpx_tile_size,
            fields_num,
            &subpx_scratch.image,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    } else {
        scratchresolve.resolveScratchDirect(
            tile,
            scratch_geom,
            subpx_tile_size,
            fields_num,
            &subpx_scratch.image,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    }

    const resolve_duration_ns: u64 = if (comptime report_mode != .off)
        @intCast(time_resolve_start.?.durationTo(std.Io.Clock.Timestamp.now(io, .awake)).raw.nanoseconds)
    else
        0;

    rasterreport.finishTile(
        ctx_report,
        result.shaded_px,
        tile.overlap_count,
        result.cam_duration_ns,
        result.elem_duration_ns,
        resolve_duration_ns,
    );
}

fn TileRangeContext(
    comptime RasterBackend: type,
    comptime report_mode: rasterconfig.ReportMode,
) type {
    const WorkerState = ThreadState(RasterBackend, report_mode);

    return struct {
        io: std.Io,
        ctx_rast: rasterfrontend.RasterContext,
        shared_log: *report.LogType(report_mode),
        tiling: elemtilebinning.TileElemOverlaps,
        meshes: []const meshtypes.MeshPrepared,
        mesh_hulls: meshtypes.MeshHulls,
        image_out_arr: *ndarray.NDArray(F),
        worker_states: []WorkerState,
        fields_num: u8,
        subpx_tile_size: usize,
    };
}

// --------------------------------------------------------------------------------------
// Tile-local raster workers
// --------------------------------------------------------------------------------------
fn initThreadReportLog(
    comptime report_mode: rasterconfig.ReportMode,
) report.LogType(report_mode) {
    return switch (report_mode) {
        .off => .{},
        .bench => .{},
    };
}

fn ThreadState(
    comptime RasterBackend: type,
    comptime report_mode: rasterconfig.ReportMode,
) type {
    return struct {
        const Self = @This();

        arena: std.heap.ArenaAllocator,
        subpx_scratch: RasterBackend.SubpxScratchBuffs,
        log: report.LogType(report_mode),
        rasterized_tiles: usize = 0,

        fn init(
            outer_alloc: std.mem.Allocator,
            fields_num: usize,
            subpx_tile_size: usize,
        ) !Self {
            var arena = std.heap.ArenaAllocator.init(outer_alloc);
            errdefer arena.deinit();
            const arena_alloc = arena.allocator();

            return .{
                .arena = arena,
                .subpx_scratch = try RasterBackend.initSubpxScratch(
                    arena_alloc,
                    @intCast(fields_num),
                    subpx_tile_size,
                ),
                .log = initThreadReportLog(report_mode),
            };
        }

        fn deinit(self: *Self) void {
            self.arena.deinit();
        }
    };
}
