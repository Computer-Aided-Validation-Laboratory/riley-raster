// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const meshtypes = @import("meshtypes.zig");
const std = @import("std");
const F = @import("buildconfig.zig").F;
const frontend = @import("rasterfrontend.zig");
const elemtilebin = @import("elemtilebinning.zig");
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const scalingpolicy = @import("scalingpolicy.zig");
const pce = @import("parachunkexec.zig");
const meshpipe = @import("meshpipeline.zig");
const MeshPrepared = meshtypes.MeshPrepared;
const NDArray = @import("ndarray.zig").NDArray;
const Timestamp = std.Io.Clock.Timestamp;
const rasterreport = @import("rasterreport.zig");
const common = @import("rasterengine_common.zig");
const cfg = @import("buildconfig.zig").config;
const S = @import("buildconfig.zig").SimdWidth;
const MatSlice = @import("matslice.zig").MatSlice;
const scalar_kernel = @import("rasterengine_scalar.zig");
const simd_kernel = @import("rasterengine_simd.zig");
const SelectedRasterBackend = if (cfg.simd == .on)
    GlobalBackendSIMD
else
    GlobalBackendScalar;
const subpxframe = @import("subpxframe_globbuff.zig");

pub fn rasterSceneGlobBuff(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: elemtilebin.TileElemOverlaps,
    meshes: []const MeshPrepared,
    mesh_hulls: meshtypes.MeshHulls,
    target: *subpxframe.SubpxTarget,
    image_out_arr: *NDArray(F),
) !usize {
    return rasterSceneGlobBuffImpl(
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
        target,
        image_out_arr,
    );
}

fn rasterSceneGlobBuffImpl(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: elemtilebin.TileElemOverlaps,
    meshes: []const MeshPrepared,
    mesh_hulls: meshtypes.MeshHulls,
    target: *subpxframe.SubpxTarget,
    image_out_arr: *NDArray(F),
) !usize {
    if (tiling.active_tiles.len == 0) return 0;

    const WorkerState = comptime ThreadState(RasterBackend, report_mode);
    const GlobalTileRangeCtx = struct {
        io: std.Io,
        ctx_rast: frontend.RasterContext,
        shared_log: *report.LogType(report_mode),
        tiling: elemtilebin.TileElemOverlaps,
        meshes: []const MeshPrepared,
        mesh_hulls: meshtypes.MeshHulls,
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
                .log = &worker_state.log,
            };

            const sub_samp: i32 = @intCast(tile_rng_ctx.ctx_rast.camera.sub_sample);
            for (range_start..range_end) |tile_idx| {
                const tile = tile_rng_ctx.tiling.active_tiles[tile_idx];
                RasterBackend.configureTarget(
                    tile_rng_ctx.target,
                    tile,
                    sub_samp,
                    &worker_state.subpx_scratch,
                );
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
                    tile_rng_ctx.mesh_hulls,
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.subpx_tile_size,
                );
                rasterreport.finishTile(
                    ctx_report_task,
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
            common.tileScratchSubpxSize(ctx_rast),
        );
        initialized_num += 1;
    }

    var tile_range_ctx = GlobalTileRangeCtx{
        .io = io,
        .ctx_rast = ctx_rast,
        .shared_log = ctx_report.log,
        .tiling = tiling,
        .meshes = meshes,
        .mesh_hulls = mesh_hulls,
        .target = target,
        .worker_states = worker_states,
        .subpx_tile_size = common.tileScratchSubpxSize(ctx_rast),
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

// --------------------------------------------------------------------------------------
// Scalar global-buffer scratch and kernel binding
// --------------------------------------------------------------------------------------
const GlobalSubpxBuffsScalar = struct {
    pub const exclusive_subpx_target = true;

    stride_subpx: usize,
    inv_z: []F,
    image: MatSlice(F),
    filter_tmp: MatSlice(F),
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pix_cent: []F,
    target_stride_subpx: usize = 0,
    target_subx_min: i32 = 0,
    target_suby_min: i32 = 0,
    tile_subx_min: i32 = 0,
    tile_suby_min: i32 = 0,
    tile_origin_idx: usize = 0,

    pub inline fn resolveImageIdx(
        self: *const GlobalSubpxBuffsScalar,
        local_subx: usize,
        local_suby: usize,
        _: usize,
    ) usize {
        return self.tile_origin_idx +
            local_suby * self.target_stride_subpx + local_subx;
    }
};

pub const GlobalBackendScalar = struct {
    pub const SubpxScratchBuffs = GlobalSubpxBuffsScalar;

    pub fn initSubpxScratch(
        arena_alloc: std.mem.Allocator,
        fields_num: u8,
        subpx_tile_size: usize,
    ) !GlobalSubpxBuffsScalar {
        const total = subpx_tile_size * subpx_tile_size;
        const image_mem = try arena_alloc.alloc(F, 0);
        return .{
            .stride_subpx = subpx_tile_size,
            .inv_z = try arena_alloc.alloc(F, total),
            .image = MatSlice(F).init(image_mem, fields_num, 0),
            .filter_tmp = MatSlice(F).init(
                image_mem,
                fields_num,
                0,
            ),
            .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
            .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
            .ideal_pix_cent = try arena_alloc.alloc(F, total * 2),
        };
    }

    // Polymorphic interface matching tile-local backends. In global-buffer mode,
    // target image memory is cleared once at frame scope, so the background value
    // parameter is unused.
    pub fn resetSubpxScratch(
        scratch: *GlobalSubpxBuffsScalar,
        subpx_tile_size: usize,
        _: F,
    ) void {
        @memset(scratch.inv_z, -std.math.inf(F));
        @memset(scratch.touched_min_x, subpx_tile_size);
        @memset(scratch.touched_max_x, 0);
    }

    pub fn configureTarget(
        target: *subpxframe.SubpxTarget,
        tile: elemtilebin.ActiveTile,
        sub_samp: i32,
        scratch: *GlobalSubpxBuffsScalar,
    ) void {
        const subpx = tile.calcSubpxBounds(sub_samp);
        scratch.image = target.image;
        scratch.target_stride_subpx = target.domain.storage_w_subpx;
        scratch.target_subx_min = target.global_subx_min;
        scratch.target_suby_min = target.global_suby_min;
        scratch.tile_subx_min = subpx.scratch.x_min;
        scratch.tile_suby_min = subpx.scratch.y_min;

        const origin_x = subpx.scratch.x_min - target.global_subx_min;
        const origin_y = subpx.scratch.y_min - target.global_suby_min;
        scratch.tile_origin_idx = @as(usize, @intCast(origin_y)) *
            scratch.target_stride_subpx + @as(usize, @intCast(origin_x));
    }

    pub fn RasterEngine(
        comptime GeomKern: type,
        comptime ShaderKern: type,
        comptime ShaderData: type,
        comptime root_class: frontend.ElemRootClass,
    ) type {
        return scalar_kernel.RasterEngine(
            GlobalSubpxBuffsScalar,
            GeomKern,
            ShaderKern,
            ShaderData,
            root_class,
        );
    }
};

// --------------------------------------------------------------------------------------
// Simd global-buffer scratch and kernel binding
// --------------------------------------------------------------------------------------
pub const GlobalSubpxBuffsSIMD = struct {
    pub const exclusive_subpx_target = true;

    stride_subpx: usize,
    inv_z: []align(64) F,
    image: MatSlice(F),
    filter_tmp: MatSlice(F),
    simd_chunks: []simd_kernel.SubpxSimdChunk,
    multi_root_candidate_indices: []u32,
    multi_root_child_masks: []u8,
    mask: []align(64) bool,
    xi: []align(64) F,
    eta: []align(64) F,
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pix_cent: []align(64) F,
    target_stride_subpx: usize = 0,
    target_subx_min: i32 = 0,
    target_suby_min: i32 = 0,
    tile_subx_min: i32 = 0,
    tile_suby_min: i32 = 0,
    tile_origin_idx: usize = 0,

    pub inline fn resolveImageIdx(
        self: *const GlobalSubpxBuffsSIMD,
        local_subx: usize,
        local_suby: usize,
        _: usize,
    ) usize {
        return self.tile_origin_idx +
            local_suby * self.target_stride_subpx + local_subx;
    }
};

pub const GlobalSubPxBuffsSIMD = GlobalSubpxBuffsSIMD;

pub const GlobalBackendSIMD = struct {
    pub const SubpxScratchBuffs = GlobalSubpxBuffsSIMD;

    pub fn initSubpxScratch(
        arena_alloc: std.mem.Allocator,
        fields_num: u8,
        subpx_tile_size: usize,
    ) !GlobalSubpxBuffsSIMD {
        const subpx_tile_total = subpx_tile_size * subpx_tile_size;
        const subpx_tile_total_padded = std.mem.alignForward(
            usize,
            subpx_tile_total,
            S,
        );
        const mem_align = std.mem.Alignment.@"64";

        const subpx_inv_z_scratch = try arena_alloc.alignedAlloc(
            F,
            mem_align,
            subpx_tile_total_padded + S,
        );
        const subpx_mask_scratch = try arena_alloc.alignedAlloc(
            bool,
            mem_align,
            subpx_tile_total_padded + S,
        );
        const subpx_xi_scratch = try arena_alloc.alignedAlloc(
            F,
            mem_align,
            subpx_tile_total_padded + S,
        );
        const subpx_eta_scratch = try arena_alloc.alignedAlloc(
            F,
            mem_align,
            subpx_tile_total_padded + S,
        );

        const empty_image_mem = try arena_alloc.alloc(F, 0);
        const empty_image = MatSlice(F).init(
            empty_image_mem,
            @as(usize, fields_num),
            0,
        );

        const subpx_simd_chunk_count =
            @divFloor(subpx_tile_total_padded + (S - 1), S) + 1;
        const subpx_simd_chunks = try arena_alloc.alloc(
            simd_kernel.SubpxSimdChunk,
            subpx_simd_chunk_count,
        );

        const ideal_pix_cent = try arena_alloc.alignedAlloc(
            F,
            mem_align,
            (subpx_tile_total_padded + S) * 2,
        );

        return .{
            .stride_subpx = subpx_tile_size,
            .inv_z = subpx_inv_z_scratch,
            .image = empty_image,
            .filter_tmp = empty_image,
            .simd_chunks = subpx_simd_chunks,
            .multi_root_candidate_indices = try arena_alloc.alloc(
                u32,
                subpx_tile_total_padded,
            ),
            .multi_root_child_masks = try arena_alloc.alloc(
                u8,
                subpx_tile_total_padded,
            ),
            .mask = subpx_mask_scratch,
            .xi = subpx_xi_scratch,
            .eta = subpx_eta_scratch,
            .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
            .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
            .ideal_pix_cent = ideal_pix_cent,
        };
    }

    // Polymorphic interface matching tile-local backends. In global-buffer mode,
    // target image memory is cleared once at frame scope, so the background value
    // parameter is unused.
    pub fn resetSubpxScratch(
        scratch: *GlobalSubpxBuffsSIMD,
        subpx_tile_size: usize,
        _: F,
    ) void {
        @memset(scratch.inv_z, -std.math.inf(F));
        @memset(scratch.touched_min_x, subpx_tile_size);
        @memset(scratch.touched_max_x, 0);
    }

    pub fn configureTarget(
        target: *subpxframe.SubpxTarget,
        tile: elemtilebin.ActiveTile,
        sub_samp: i32,
        scratch: *GlobalSubpxBuffsSIMD,
    ) void {
        const subpx = tile.calcSubpxBounds(sub_samp);
        scratch.image = target.image;
        scratch.target_stride_subpx = target.domain.storage_w_subpx;
        scratch.target_subx_min = target.global_subx_min;
        scratch.target_suby_min = target.global_suby_min;
        scratch.tile_subx_min = subpx.scratch.x_min;
        scratch.tile_suby_min = subpx.scratch.y_min;

        const origin_x = subpx.scratch.x_min - target.global_subx_min;
        const origin_y = subpx.scratch.y_min - target.global_suby_min;
        scratch.tile_origin_idx = @as(usize, @intCast(origin_y)) *
            scratch.target_stride_subpx + @as(usize, @intCast(origin_x));
    }

    pub fn RasterEngine(
        comptime GeomKern: type,
        comptime ShaderKern: type,
        comptime ShaderData: type,
        comptime root_class: frontend.ElemRootClass,
    ) type {
        return simd_kernel.RasterEngine(
            GlobalSubpxBuffsSIMD,
            GeomKern,
            ShaderKern,
            ShaderData,
            root_class,
        );
    }
};

// --------------------------------------------------------------------------------------
// Global raster workers
// --------------------------------------------------------------------------------------
fn initThreadReportLog(
    comptime report_mode: ReportMode,
) report.LogType(report_mode) {
    return switch (report_mode) {
        .off => .{},
        .bench => .{},
    };
}

fn ThreadState(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
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
