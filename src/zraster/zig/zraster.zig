// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;

const matslice = @import("matslice.zig");
const ndarray = @import("ndarray.zig");

const sliceops = @import("sliceops.zig");

const cam = @import("camera.zig");
const rops = @import("rasterops.zig");
const mo = @import("meshops.zig");
const shaderops = @import("shaderops.zig");

const iio = @import("imageio.zig");
const imageops = @import("imageops.zig");
const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");

const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

const rastcfg = @import("rasterconfig.zig");
pub const RasterConfig = rastcfg.RasterConfig;
pub const SaveStrategy = rastcfg.SaveStrategy;
pub const RenderMode = rastcfg.RenderMode;
pub const ReportMode = rastcfg.ReportMode;
pub const FullStatsOpts = rastcfg.FullStatsOpts;

const saveStrategyReturnsImages = rastcfg.saveStrategyReturnsImages;
const saveStrategyWritesDisk = rastcfg.saveStrategyWritesDisk;
const saveStrategyUsesDirectWrite = rastcfg.saveStrategyUsesDirectWrite;
const saveStrategyUsesPerFrameCopy = rastcfg.saveStrategyUsesPerFrameCopy;

pub const ManagedIo = struct {
    threaded: std.Io.Threaded,

    pub fn io(self: *ManagedIo) std.Io {
        return self.threaded.io();
    }

    pub fn deinit(self: *ManagedIo) void {
        self.threaded.deinit();
    }
};

pub fn getManagedIo(
    gpa: std.mem.Allocator,
    minimal: std.process.Init.Minimal,
    num_threads: u16,
) ManagedIo {
    // User-facing thread counts in zraster always include the caller thread.
    // Zig's std.Io.Threaded limits count only spawned worker threads, excluding
    // the caller. Translate here so:
    //   threads=1  -> caller only
    //   threads=N  -> caller + (N - 1) worker threads
    const limit: std.Io.Limit =
        if (num_threads <= 1) .nothing else .limited(num_threads - 1);

    return .{ .threaded = std.Io.Threaded.init(gpa, .{
        .argv0 = .init(minimal.args),
        .environ = minimal.environ,
        .async_limit = limit,
        .concurrent_limit = limit,
    }) };
}

const report = @import("report.zig");
const FrameReportStorage = report.FrameReportStorage;

const FrameJobErrorState = struct {
    mutex: std.atomic.Mutex = .unlocked,
    first_err: ?anyerror = null,

    fn setFirst(
        self: *FrameJobErrorState,
        err: anyerror,
    ) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        if (self.first_err == null) {
            self.first_err = err;
        }
    }
};

fn FrameReportPtr(comptime report_mode: ReportMode) type {
    return *report.LogType(report_mode);
}

fn getFrameReportPtr(
    comptime report_mode: ReportMode,
    ctx: *FrameContext,
) FrameReportPtr(report_mode) {
    return switch (report_mode) {
        .off => &ctx.report_storage.off,
        .bench => &ctx.report_storage.bench,
        .full_stats => &ctx.report_storage.full_stats,
    };
}

fn calcNodesPerElem(
    meshes: []const mo.MeshPrepared,
) f64 {
    var nodes_sum: usize = 0;
    for (meshes) |mesh| {
        nodes_sum += mesh.mesh_type.getNodesNum();
    }
    return @as(f64, @floatFromInt(nodes_sum)) /
        @as(f64, @floatFromInt(meshes.len));
}

fn countFrames(
    meshes: []const mo.MeshInput,
) usize {
    const dim_time_pre: usize = 0;
    var num_time: usize = 1;
    for (meshes) |mesh| {
        if (mesh.disp) |field| {
            num_time = @max(num_time, field.array.dims[dim_time_pre]);
        } else switch (mesh.shader) {
            .nodal => |s| {
                num_time = @max(num_time, s.field.array.dims[dim_time_pre]);
            },
            else => {},
        }
    }
    return num_time;
}

fn countOutputFields(
    meshes: []const mo.MeshInput,
) u8 {
    var num_fields: u8 = 0;
    for (meshes) |mesh| {
        const mesh_fields: u8 = switch (mesh.shader) {
            .nodal => |s| s.field.getFieldsN(),
            .tex => 1,
            .tex_rgb => 3,
            .tex_func => 1,
            .tex_func_rgb => 3,
        };
        num_fields = @max(num_fields, mesh_fields);
    }
    return num_fields;
}

fn initNodalGlobalScaling(
    outer_alloc: std.mem.Allocator,
    meshes: []const mo.MeshInput,
) ![]?imageops.ScalingParams {
    var nodal_global_scaling = try outer_alloc.alloc(?imageops.ScalingParams, meshes.len);

    for (meshes, 0..) |mesh, ii| {
        nodal_global_scaling[ii] = null;
        switch (mesh.shader) {
            .nodal => |s| {
                if (s.scale_over == .over_frames) {
                    nodal_global_scaling[ii] = imageops.getScalingParamsNDArray(
                        &s.field.array,
                        null,
                        s.scaling,
                    );
                }
            },
            else => {},
        }
    }

    return nodal_global_scaling;
}

fn initMeshStaticSlice(
    allocator: std.mem.Allocator,
    meshes: []const mo.MeshInput,
) ![]mo.MeshStatic {
    const mesh_static = try allocator.alloc(mo.MeshStatic, meshes.len);

    for (meshes, 0..) |mesh, ii| {
        mesh_static[ii] = try mo.initMeshStatic(allocator, &mesh);
    }

    return mesh_static;
}

fn initAllFramesBuffer(
    outer_alloc: std.mem.Allocator,
    config: RasterConfig,
    cameras: []const cam.CameraPrepared,
    num_time: usize,
    num_fields: u8,
) !?ndarray.NDArray(f64) {
    if (saveStrategyReturnsImages(config.save_strategy)) {
        std.debug.assert(cameras.len > 0);
        var max_pixels_num = cameras[0].pixels_num;
        for (cameras[1..]) |camera| {
            max_pixels_num[0] = @max(max_pixels_num[0], camera.pixels_num[0]);
            max_pixels_num[1] = @max(max_pixels_num[1], camera.pixels_num[1]);
        }
        const dims = [_]usize{
            cameras.len,
            num_time,
            @as(usize, num_fields),
            max_pixels_num[1],
            max_pixels_num[0],
        };
        const images_arr = try ndarray.NDArray(f64).initFlat(outer_alloc, dims[0..]);
        @memset(images_arr.slice, 0.0);
        return images_arr;
    }

    return null;
}

fn getFrameImageView(
    allocator: std.mem.Allocator,
    images_arr: *ndarray.NDArray(f64),
    camera_idx: usize,
    frame_idx: usize,
    camera_pixels_num: [2]u32,
) !ndarray.NDArray(f64) {
    std.debug.assert(images_arr.dims.len == 5);
    if (images_arr.dims[3] != camera_pixels_num[1] or
        images_arr.dims[4] != camera_pixels_num[0])
    {
        return error.DirectWriteRequiresUniformCameraPixels;
    }
    return try images_arr.fixedPrefixView(
        allocator,
        &[_]usize{ camera_idx, frame_idx },
    );
}

fn initFrameReportStorage(
    outer_alloc: std.mem.Allocator,
    camera: *const cam.CameraPrepared,
    actual_tile_size: u16,
    config: RasterConfig,
) !report.FrameReportStorage {
    return switch (config.report) {
        .off => .{ .off = .{} },
        .bench => .{ .bench = .{} },
        .full_stats => .{ .full_stats = try report.initFullStatsLog(
            outer_alloc,
            camera.pixels_num,
            actual_tile_size,
            camera.sub_sample,
            config.full_stats_opts,
        ) },
    };
}

fn calcBenchCaptureIdx(
    cameras_num: usize,
    camera_idx: usize,
    frame_idx: usize,
) usize {
    return frame_idx * cameras_num + camera_idx;
}

//------------------------------------------------------------------------------------------
// 4. Pipeline Stages

const FrameContext = struct {
    arena: std.heap.ArenaAllocator,

    frame_meshes: []mo.MeshFrame = &.{},
    prep_meshes: []mo.MeshPrepared = &.{},
    elem_bboxes_by_mesh: [][]rops.ElemBBox = &.{},
    elems_in_image_by_mesh: []usize = &.{},
    raster_hulls: []?ndarray.NDArray(f64) = &.{},
    tiling: ?rops.TilingOverlaps = null,
    total_elems_num: usize = 0,
    total_elems_in_image: usize = 0,
    actual_tile_size: u16 = 1,

    frame_arr: ndarray.NDArray(f64) = undefined,

    report_storage: report.FrameReportStorage = .{ .off = .{} },
    frame_times: report.FrameTimes = .{},

    fn init(
        outer_alloc: std.mem.Allocator,
    ) FrameContext {
        return .{
            .arena = std.heap.ArenaAllocator.init(outer_alloc),
        };
    }

    fn deinit(
        self: *FrameContext,
        outer_alloc: std.mem.Allocator,
        config: RasterConfig,
    ) void {
        if (config.report == .full_stats) {
            self.report_storage.full_stats.deinit(outer_alloc);
        }
        self.arena.deinit();
    }
};

fn prepareFrameContext(
    outer_alloc: std.mem.Allocator,
    ctx: *FrameContext,
    input: *const FrameJobDesc,
) !void {
    const arena_alloc = ctx.arena.allocator();
    ctx.actual_tile_size = scalingpolicy.tileSize(
        input.config.tile_size_min,
        input.config.tile_size_max,
        input.camera.pixels_num,
        input.camera.sub_sample,
    );

    ctx.report_storage = try initFrameReportStorage(
        outer_alloc,
        input.camera,
        ctx.actual_tile_size,
        input.config,
    );

    const mesh_n = input.mesh_static.len;
    ctx.frame_meshes = try arena_alloc.alloc(mo.MeshFrame, mesh_n);
    ctx.prep_meshes = try arena_alloc.alloc(mo.MeshPrepared, mesh_n);
    ctx.elem_bboxes_by_mesh = try arena_alloc.alloc([]rops.ElemBBox, mesh_n);
    ctx.elems_in_image_by_mesh = try arena_alloc.alloc(usize, mesh_n);
    ctx.raster_hulls = try arena_alloc.alloc(?ndarray.NDArray(f64), mesh_n);

    const dims = [_]usize{
        @as(usize, input.num_fields),
        input.camera.pixels_num[1],
        input.camera.pixels_num[0],
    };
    if (saveStrategyUsesDirectWrite(input.config.save_strategy)) {
        const images_arr = input.images_arr orelse return error.NoResult;
        ctx.frame_arr = try getFrameImageView(
            arena_alloc,
            images_arr,
            input.camera_idx,
            input.frame_idx,
            input.camera.pixels_num,
        );
    } else {
        ctx.frame_arr = try ndarray.NDArray(f64).initFlat(arena_alloc, dims[0..]);
    }
    std.debug.assert(ctx.frame_arr.dims.len == dims.len);
    for (dims, 0..) |dim, ii| std.debug.assert(ctx.frame_arr.dims[ii] == dim);
    @memset(ctx.frame_arr.slice, input.config.background_value);
}

fn copyFrameToImageBatch(
    images_arr: *ndarray.NDArray(f64),
    camera_idx: usize,
    frame_idx: usize,
    frame_arr: *const ndarray.NDArray(f64),
) void {
    std.debug.assert(images_arr.dims.len == 5);
    std.debug.assert(frame_arr.dims.len == 3);
    std.debug.assert(frame_arr.dims[0] == images_arr.dims[2]);
    std.debug.assert(frame_arr.dims[1] <= images_arr.dims[3]);
    std.debug.assert(frame_arr.dims[2] <= images_arr.dims[4]);

    const dst_base = camera_idx * images_arr.strides[0] + frame_idx * images_arr.strides[1];
    const dst_field_stride = images_arr.strides[2];
    const dst_row_stride = images_arr.strides[3];
    const src_field_stride = frame_arr.strides[0];
    const src_row_stride = frame_arr.strides[1];
    const row_len = frame_arr.dims[2];

    for (0..frame_arr.dims[0]) |ff| {
        const dst_field_base = dst_base + ff * dst_field_stride;
        const src_field_base = ff * src_field_stride;
        for (0..frame_arr.dims[1]) |rr| {
            const dst_row_base = dst_field_base + rr * dst_row_stride;
            const src_row_base = src_field_base + rr * src_row_stride;
            @memcpy(
                images_arr.slice[dst_row_base .. dst_row_base + row_len],
                frame_arr.slice[src_row_base .. src_row_base + row_len],
            );
        }
    }
}

fn rasterFrame(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: *const FrameJobDesc,
    raster_workers: u16,
    ctx: *FrameContext,
) !void {
    const report_ptr = getFrameReportPtr(report_mode, ctx);
    const ctx_report = report.ReportContext(report_mode){ .log = report_ptr };
    const time_start_loop = Timestamp.now(io, .awake);

    const ctx_rast = rops.RasterContext{
        .camera = input.camera,
        .config = input.config,
        .frame_idx = input.frame_idx,
        .tile_size = ctx.actual_tile_size,
    };

    try rasterengine.rasterScene(
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        raster_workers,
        ctx.tiling.?,
        ctx.prep_meshes,
        ctx.raster_hulls,
        &ctx.frame_arr,
    );

    const time_end_loop = Timestamp.now(io, .awake);
    ctx.frame_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds,
    );
}

fn runRasterFrame(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: *const FrameJobDesc,
    raster_workers: u16,
    ctx: *FrameContext,
) !void {
    switch (input.config.report) {
        .off => try rasterFrame(
            .off,
            outer_alloc,
            io,
            input,
            raster_workers,
            ctx,
        ),
        .bench => try rasterFrame(
            .bench,
            outer_alloc,
            io,
            input,
            raster_workers,
            ctx,
        ),
        .full_stats => try rasterFrame(
            .full_stats,
            outer_alloc,
            io,
            input,
            raster_workers,
            ctx,
        ),
    }
}

fn saveFrame(
    io: std.Io,
    input: *const FrameJobDesc,
    ctx: *FrameContext,
) !void {
    if (saveStrategyWritesDisk(input.config.save_strategy)) {
        std.debug.assert(ctx.frame_arr.dims[0] <= std.math.maxInt(u8));
        try iio.saveImages(
            io,
            input.out_dir,
            input.camera_idx,
            input.frame_idx,
            @intCast(ctx.frame_arr.dims[0]),
            input.camera.pixels_num,
            &ctx.frame_arr,
            input.config.image_save_opts,
        );
    }
    if (saveStrategyUsesPerFrameCopy(input.config.save_strategy)) {
        const images_arr = input.images_arr orelse return error.NoResult;
        copyFrameToImageBatch(
            images_arr,
            input.camera_idx,
            input.frame_idx,
            &ctx.frame_arr,
        );
    }
}

fn sceneTileOverlapBinning(
    io: std.Io,
    job: *const FrameJobDesc,
    chunk_exec: *pce.ParaChunkExecutor,
    geom_workers: u16,
    ctx: *FrameContext,
) !void {
    const arena_alloc = ctx.arena.allocator();
    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        job.camera.pixels_num[0],
        ctx.actual_tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        job.camera.pixels_num[1],
        ctx.actual_tile_size,
    );

    const time_start_overlap = Timestamp.now(io, .awake);
    ctx.tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        chunk_exec,
        scalingpolicy.geometryWorkers(geom_workers),
        ctx.actual_tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(job.camera.pixels_num[0]),
        @intCast(job.camera.pixels_num[1]),
        ctx.elems_in_image_by_mesh,
        ctx.elem_bboxes_by_mesh,
    );
    const time_end_overlap = Timestamp.now(io, .awake);
    ctx.frame_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds,
    );
}

pub const RenderGroupSpec = struct {
    io: std.Io,
    workers: u16,
};

const FrameJobDesc = struct {
    camera: *const cam.CameraPrepared,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
    cameras_num: usize,
};

const PreparedFrameJob = struct {
    desc: FrameJobDesc,
    ctx: FrameContext,
    time_start_frame: ?Timestamp = null,

    fn init(
        group_alloc: std.mem.Allocator,
        desc: FrameJobDesc,
    ) PreparedFrameJob {
        return .{
            .desc = desc,
            .ctx = FrameContext.init(group_alloc),
            .time_start_frame = null,
        };
    }

    fn deinit(
        self: *PreparedFrameJob,
        group_alloc: std.mem.Allocator,
    ) void {
        self.ctx.deinit(group_alloc, self.desc.config);
    }
};

const RenderGroupErrorState = FrameJobErrorState;

fn runGeometryStage(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    geom_workers: u16,
) !void {
    if (job.time_start_frame == null) {
        job.time_start_frame = Timestamp.now(io, .awake);
    }

    try prepareFrameContext(
        group_alloc,
        &job.ctx,
        &job.desc,
    );

    var chunk_exec = pce.ParaChunkExecutor.init(io, geom_workers);

    const time_start_geo = Timestamp.now(io, .awake);
    const arena_alloc = job.ctx.arena.allocator();

    const geo_res = try mo.prepareMeshFrames(
        arena_alloc,
        &chunk_exec,
        scalingpolicy.geometryWorkers(geom_workers),
        job.desc.camera,
        job.desc.config,
        job.desc.frame_idx,
        job.desc.mesh_static,
        job.desc.nodal_global_scaling,
        job.ctx.frame_meshes,
    );
    for (job.ctx.frame_meshes, 0..) |*fm, ii| {
        job.ctx.prep_meshes[ii] = fm.mesh;
        job.ctx.elem_bboxes_by_mesh[ii] = fm.elem_bboxes;
        job.ctx.elems_in_image_by_mesh[ii] = fm.elems_in_image;
        job.ctx.raster_hulls[ii] = fm.raster_hull;
    }
    job.ctx.total_elems_num = geo_res.total_elems_num;
    job.ctx.total_elems_in_image = geo_res.total_elems_in_image;

    const time_end_geo = Timestamp.now(io, .awake);
    job.ctx.frame_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );

    try sceneTileOverlapBinning(
        io,
        &job.desc,
        &chunk_exec,
        geom_workers,
        &job.ctx,
    );
}

fn runRasterAndFinalizeStage(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    raster_workers: u16,
) !void {
    try runRasterFrame(
        outer_alloc,
        io,
        &job.desc,
        raster_workers,
        &job.ctx,
    );

    const time_start_save = Timestamp.now(io, .awake);
    try saveFrame(io, &job.desc, &job.ctx);
    const time_end_save = Timestamp.now(io, .awake);
    job.ctx.frame_times.save_frame = @floatFromInt(
        time_start_save.durationTo(time_end_save).raw.nanoseconds,
    );

    const time_end_frame = Timestamp.now(io, .awake);
    job.ctx.frame_times.total_time = @floatFromInt(
        job.time_start_frame.?.durationTo(time_end_frame).raw.nanoseconds,
    );

    try report.publishFrameResults(
        outer_alloc,
        io,
        job.desc.config,
        job.ctx.actual_tile_size,
        job.desc.camera,
        job.desc.camera_idx,
        job.desc.frame_idx,
        job.desc.cameras_num,
        job.desc.out_dir,
        job.desc.bench_capture,
        &job.ctx.report_storage,
        job.ctx.frame_times,
        job.ctx.total_elems_num,
        job.ctx.total_elems_in_image,
        job.ctx.prep_meshes,
    );
}

fn runGeometryJobAsync(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    geom_workers: u16,
    err_state: *RenderGroupErrorState,
) std.Io.Cancelable!void {
    runGeometryStage(group_alloc, io, job, geom_workers) catch |err| {
        err_state.setFirst(err);
    };
}

fn countStaticMeshElements(
    mesh_static: []const mo.MeshStatic,
) usize {
    var total: usize = 0;
    for (mesh_static) |mesh| {
        total += mesh.connect.table.rows_num;
    }
    return total;
}

fn buildPreparedBatch(
    group_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
    job_indices: []const usize,
) ![]PreparedFrameJob {
    const jobs = try group_alloc.alloc(PreparedFrameJob, job_indices.len);
    for (job_indices, 0..) |job_idx, ii| {
        const frame_idx = @divFloor(job_idx, cameras.len);
        const camera_idx = @mod(job_idx, cameras.len);
        jobs[ii] = PreparedFrameJob.init(
            group_alloc,
            .{
                .camera = &cameras[camera_idx],
                .camera_idx = camera_idx,
                .frame_idx = frame_idx,
                .num_fields = num_fields,
                .config = config,
                .out_dir = out_dir,
                .mesh_static = mesh_static,
                .nodal_global_scaling = nodal_global_scaling,
                .images_arr = images_arr,
                .bench_capture = bench_capture,
                .cameras_num = cameras.len,
            },
        );
    }
    return jobs;
}

fn assignSpreadGeometryWorkers(
    allocator: std.mem.Allocator,
    group_workers: u16,
    jobs_in_wave: usize,
    max_geom_workers_per_job: u16,
) ![]u16 {
    const assigned = try allocator.alloc(u16, jobs_in_wave);
    @memset(assigned, 0);

    const max_jobs = @min(jobs_in_wave, @as(usize, @max(@as(u16, 1), group_workers)));
    for (0..max_jobs) |ii| {
        assigned[ii] = 1;
    }

    var remaining_workers = @as(usize, @max(@as(u16, 1), group_workers)) - max_jobs;
    while (remaining_workers > 0) {
        var added_any = false;
        for (assigned) |*workers| {
            if (remaining_workers == 0) break;
            if (workers.* < @max(@as(u16, 1), max_geom_workers_per_job)) {
                workers.* += 1;
                remaining_workers -= 1;
                added_any = true;
            }
        }
        if (!added_any) break;
    }

    for (assigned) |*workers| {
        if (workers.* == 0) workers.* = 1;
    }
    return assigned;
}

fn geometryJobsPerWave(
    config: RasterConfig,
    group_workers: u16,
    jobs_remaining: usize,
) usize {
    const requested_jobs = @max(@as(u16, 1), config.max_geom_jobs_in_flight_per_group);
    const worker_cap = @max(@as(u16, 1), group_workers);
    return @min(
        jobs_remaining,
        @as(usize, @intCast(@min(requested_jobs, worker_cap))),
    );
}

fn processGeometryWave(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    jobs: []PreparedFrameJob,
    workers_per_job: []const u16,
) !void {
    var err_state = RenderGroupErrorState{};
    var group: std.Io.Group = .init;
    errdefer group.cancel(io);

    const caller_idx = jobs.len - 1;
    for (jobs[0..caller_idx], workers_per_job[0..caller_idx]) |*job, geom_workers| {
        group.async(
            io,
            runGeometryJobAsync,
            .{ group_alloc, io, job, geom_workers, &err_state },
        );
    }
    try runGeometryStage(
        group_alloc,
        io,
        &jobs[caller_idx],
        workers_per_job[caller_idx],
    );
    try group.await(io);
    if (err_state.first_err) |err| return err;
}

fn processGeometryBatch(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    group_workers: u16,
    config: RasterConfig,
    total_scene_elems: usize,
    jobs: []PreparedFrameJob,
) !void {
    const geom_mode = scalingpolicy.resolveGeometrySchedulingMode(
        config.geom_scheduling_mode,
        total_scene_elems,
    );
    var wave_start: usize = 0;
    while (wave_start < jobs.len) {
        const jobs_remaining = jobs.len - wave_start;
        const wave_jobs = switch (geom_mode) {
            .spread => geometryJobsPerWave(config, group_workers, jobs_remaining),
            .pack => @min(@as(usize, 1), jobs_remaining),
            .auto => unreachable,
        };
        const wave_end = wave_start + wave_jobs;
        const wave = jobs[wave_start..wave_end];
        const workers_per_job = switch (geom_mode) {
            .spread => try assignSpreadGeometryWorkers(
                group_alloc,
                group_workers,
                wave.len,
                config.max_geom_workers_per_job,
            ),
            .pack => blk: {
                const assigned = try group_alloc.alloc(u16, 1);
                assigned[0] = @min(
                    @max(@as(u16, 1), group_workers),
                    @max(@as(u16, 1), config.max_geom_workers_per_job),
                );
                break :blk assigned;
            },
            .auto => unreachable,
        };
        defer group_alloc.free(workers_per_job);
        try processGeometryWave(group_alloc, io, wave, workers_per_job);
        wave_start = wave_end;
    }
}

fn processRasterBatch(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    group_alloc: std.mem.Allocator,
    group_workers: u16,
    config: RasterConfig,
    jobs: []PreparedFrameJob,
) !void {
    const raster_workers = @min(
        @max(@as(u16, 1), group_workers),
        @max(@as(u16, 1), config.max_raster_workers_per_job),
    );
    for (jobs) |*job| {
        defer job.deinit(group_alloc);
        try runRasterAndFinalizeStage(outer_alloc, io, job, raster_workers);
    }
}

fn processOfflineBatch(
    outer_alloc: std.mem.Allocator,
    group_alloc: std.mem.Allocator,
    render_group: RenderGroupSpec,
    config: RasterConfig,
    total_scene_elems: usize,
    jobs: []PreparedFrameJob,
) !void {
    try processGeometryBatch(
        group_alloc,
        render_group.io,
        render_group.workers,
        config,
        total_scene_elems,
        jobs,
    );
    try processRasterBatch(
        outer_alloc,
        render_group.io,
        group_alloc,
        render_group.workers,
        config,
        jobs,
    );
}

const OfflineDispatchShared = struct {
    outer_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
    total_scene_elems: usize,
    batch_size: usize,
    next_job: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    err_state: *RenderGroupErrorState,
};

const InOrderDispatchShared = struct {
    outer_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    frame_idx: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
    total_scene_elems: usize,
    batch_size: usize,
    next_camera: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    err_state: *RenderGroupErrorState,
};

fn processOfflineRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *OfflineDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();
    const jobs_num = shared.cameras.len * shared.num_time;

    while (true) {
        const batch_start = shared.next_job.fetchAdd(shared.batch_size, .monotonic);
        if (batch_start >= jobs_num) break;
        const batch_end = @min(jobs_num, batch_start + shared.batch_size);
        const batch_len = batch_end - batch_start;
        const job_indices = try group_alloc.alloc(usize, batch_len);
        for (0..batch_len) |ii| {
            job_indices[ii] = batch_start + ii;
        }
        const jobs = try buildPreparedBatch(
            group_alloc,
            shared.cameras,
            shared.config,
            shared.out_dir,
            shared.num_fields,
            shared.mesh_static,
            shared.nodal_global_scaling,
            shared.images_arr,
            shared.bench_capture,
            job_indices,
        );
        try processOfflineBatch(
            shared.outer_alloc,
            group_alloc,
            render_group,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );
        _ = group_arena.reset(.retain_capacity);
    }
}

fn processOfflineRenderGroupThread(
    render_group: RenderGroupSpec,
    shared: *OfflineDispatchShared,
) void {
    processOfflineRenderGroupLoop(render_group, shared) catch |err| {
        shared.err_state.setFirst(err);
    };
}

fn dispatchGeometryJobsOffline(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    var err_state = RenderGroupErrorState{};
    var shared = OfflineDispatchShared{
        .outer_alloc = outer_alloc,
        .cameras = cameras,
        .config = config,
        .out_dir = out_dir,
        .num_time = num_time,
        .num_fields = num_fields,
        .mesh_static = mesh_static,
        .nodal_global_scaling = nodal_global_scaling,
        .images_arr = images_arr,
        .bench_capture = bench_capture,
        .total_scene_elems = countStaticMeshElements(mesh_static),
        .batch_size = @max(@as(usize, 1), config.frame_batch_size_per_group),
        .err_state = &err_state,
    };

    var threads = try outer_alloc.alloc(std.Thread, render_groups.len -| 1);
    defer outer_alloc.free(threads);

    for (render_groups[1..], 0..) |render_group, ii| {
        threads[ii] = try std.Thread.spawn(
            .{},
            processOfflineRenderGroupThread,
            .{ render_group, &shared },
        );
    }
    processOfflineRenderGroupLoop(render_groups[0], &shared) catch |err| {
        err_state.setFirst(err);
    };
    for (threads) |thread| thread.join();
    if (err_state.first_err) |err| return err;
}

fn processInOrderRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *InOrderDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();

    while (true) {
        const batch_start_camera = shared.next_camera.fetchAdd(
            shared.batch_size,
            .monotonic,
        );
        if (batch_start_camera >= shared.cameras.len) break;
        const batch_end_camera = @min(
            shared.cameras.len,
            batch_start_camera + shared.batch_size,
        );
        const batch_len = batch_end_camera - batch_start_camera;
        const job_indices = try group_alloc.alloc(usize, batch_len);
        for (0..batch_len) |ii| {
            job_indices[ii] =
                shared.frame_idx * shared.cameras.len + batch_start_camera + ii;
        }
        const jobs = try buildPreparedBatch(
            group_alloc,
            shared.cameras,
            shared.config,
            shared.out_dir,
            shared.num_fields,
            shared.mesh_static,
            shared.nodal_global_scaling,
            shared.images_arr,
            shared.bench_capture,
            job_indices,
        );
        try processOfflineBatch(
            shared.outer_alloc,
            group_alloc,
            render_group,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );
        _ = group_arena.reset(.retain_capacity);
    }
}

fn processInOrderRenderGroupThread(
    render_group: RenderGroupSpec,
    shared: *InOrderDispatchShared,
) void {
    processInOrderRenderGroupLoop(render_group, shared) catch |err| {
        shared.err_state.setFirst(err);
    };
}

fn dispatchGeometryJobsInOrder(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    cameras: []const cam.CameraPrepared,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    const total_scene_elems = countStaticMeshElements(mesh_static);
    const batch_size = @max(@as(usize, 1), config.frame_batch_size_per_group);

    for (0..num_time) |frame_idx| {
        var err_state = RenderGroupErrorState{};
        var shared = InOrderDispatchShared{
            .outer_alloc = outer_alloc,
            .cameras = cameras,
            .config = config,
            .out_dir = out_dir,
            .frame_idx = frame_idx,
            .num_fields = num_fields,
            .mesh_static = mesh_static,
            .nodal_global_scaling = nodal_global_scaling,
            .images_arr = images_arr,
            .bench_capture = bench_capture,
            .total_scene_elems = total_scene_elems,
            .batch_size = batch_size,
            .err_state = &err_state,
        };

        var threads = try outer_alloc.alloc(std.Thread, render_groups.len -| 1);
        defer outer_alloc.free(threads);
        for (render_groups[1..], 0..) |render_group, ii| {
            threads[ii] = try std.Thread.spawn(
                .{},
                processInOrderRenderGroupThread,
                .{ render_group, &shared },
            );
        }
        processInOrderRenderGroupLoop(render_groups[0], &shared) catch |err| {
            err_state.setFirst(err);
        };
        for (threads) |thread| thread.join();
        if (err_state.first_err) |err| return err;
    }
}

fn prepareCameras(
    outer_alloc: std.mem.Allocator,
    camera_inputs: []const cam.CameraInput,
    config: RasterConfig,
) ![]cam.CameraPrepared {
    const cameras = try outer_alloc.alloc(cam.CameraPrepared, camera_inputs.len);
    for (camera_inputs, 0..) |camera_input, cc| {
        cameras[cc] = cam.CameraPrepared.initForSubPixelCenterMap(
            outer_alloc,
            camera_input,
            config.subpixel_center_map,
        ) catch |err| {
            for (0..cc) |pp| cameras[pp].deinit(outer_alloc);
            outer_alloc.free(cameras);
            return err;
        };
    }

    return cameras;
}

pub fn rasterAllFramesGrouped(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]report.FrameBenchCapture,
) !?ndarray.NDArray(f64) {
    std.debug.assert(render_groups.len > 0);
    const summary_io = render_groups[0].io;
    const time_start_render = Timestamp.now(summary_io, .awake);

    var out_dir: ?std.Io.Dir = null;
    if (out_dir_path) |path| {
        const cwd = std.Io.Dir.cwd();
        cwd.createDir(summary_io, path, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        out_dir = try cwd.openDir(summary_io, path, .{});
    }
    defer if (out_dir) |*od| od.close(summary_io);

    var static_arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer static_arena.deinit();
    const static_alloc = static_arena.allocator();

    const cameras = try prepareCameras(outer_alloc, camera_inputs, config);
    defer {
        for (cameras) |camera| camera.deinit(outer_alloc);
        outer_alloc.free(cameras);
    }

    const num_time = countFrames(meshes);
    const num_fields = countOutputFields(meshes);

    std.debug.assert(cameras.len > 0);
    std.debug.assert(meshes.len > 0);
    std.debug.assert(num_time > 0);
    std.debug.assert(num_fields > 0);
    if (bench_capture) |capture| {
        std.debug.assert(capture.len == cameras.len * num_time);
    }

    // Init. static data across all frames - here we reshape uv's once if we have them so
    // we don't need to do this every frames
    const mesh_static = try initMeshStaticSlice(static_alloc, meshes);
    const nodal_global_scaling = try initNodalGlobalScaling(outer_alloc, meshes);
    defer outer_alloc.free(nodal_global_scaling);

    var images_arr_opt: ?ndarray.NDArray(f64) = try initAllFramesBuffer(
        outer_alloc,
        config,
        cameras,
        num_time,
        num_fields,
    );
    const time_end_setup = Timestamp.now(summary_io, .awake);
    var end_to_end_times = report.EndToEndTimes{
        .setup_time = @floatFromInt(
            time_start_render.durationTo(time_end_setup).raw.nanoseconds,
        ),
    };
    const time_start_dispatch = Timestamp.now(summary_io, .awake);

    if (config.render_mode == .in_order) {
        try dispatchGeometryJobsInOrder(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            if (images_arr_opt) |*ima| ima else null,
            bench_capture,
        );
    } else {
        try dispatchGeometryJobsOffline(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            if (images_arr_opt) |*ima| ima else null,
            bench_capture,
        );
    }

    const time_end_render = Timestamp.now(summary_io, .awake);
    end_to_end_times.dispatch_time = @floatFromInt(
        time_start_dispatch.durationTo(time_end_render).raw.nanoseconds,
    );
    end_to_end_times.total_time = @floatFromInt(
        time_start_render.durationTo(time_end_render).raw.nanoseconds,
    );

    const actual_tile_size = scalingpolicy.tileSize(
        config.tile_size_min,
        config.tile_size_max,
        cameras[0].pixels_num,
        cameras[0].sub_sample,
    );
    try report.printRenderSummary(
        summary_io,
        cameras,
        actual_tile_size,
        num_time,
        config.report,
        end_to_end_times,
        if (bench_capture) |capture| capture else null,
    );
    return images_arr_opt;
}

//==========================================================================================
// 1. Compatibility wrapper using a single render group
pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]report.FrameBenchCapture,
) !?ndarray.NDArray(f64) {
    const total_workers = @max(@as(u16, 1), config.total_threads);
    const render_groups = [_]RenderGroupSpec{
        .{ .io = io, .workers = total_workers },
    };
    return rasterAllFramesGrouped(
        outer_alloc,
        render_groups[0..],
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        bench_capture,
    );
}
