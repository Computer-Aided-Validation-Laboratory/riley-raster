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

pub const IoMode = enum {
    direct,
    async_single,
    threaded,
};

pub const ManagedIo = union(enum) {
    direct: std.Io,
    threaded: std.Io.Threaded,

    pub fn io(self: *ManagedIo) std.Io {
        return switch (self.*) {
            .direct => |direct_io| direct_io,
            .threaded => |*threaded| threaded.io(),
        };
    }

    pub fn deinit(self: *ManagedIo) void {
        switch (self.*) {
            .direct => {},
            .threaded => |*threaded| threaded.deinit(),
        }
    }
};

pub fn getThreadedIo(
    gpa: std.mem.Allocator,
    default_io: std.Io,
    minimal: std.process.Init.Minimal,
    num_threads: u16,
    io_mode: IoMode,
) ManagedIo {
    if (io_mode == .direct) {
        return .{ .direct = default_io };
    }

    // std.Io.Threaded limits count worker threads in addition to the caller.
    // Our raster/bench configs use total execution-thread semantics, so:
    //   1 => caller only
    //   2 => caller + 1 worker
    // and clamp 0/1 to single-threaded execution.
    const limit: std.Io.Limit = switch (io_mode) {
        .direct => unreachable,
        .async_single => .nothing,
        .threaded => blk: {
            const io_workers: u16 = if (num_threads <= 1) 0 else num_threads - 1;
            break :blk if (io_workers == 0) .nothing else .limited(io_workers);
        },
    };

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
    if (config.save_strategy == .memory or config.save_strategy == .both) {
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
        input: *const FrameInput,
    ) void {
        if (input.config.report == .full_stats) {
            self.report_storage.full_stats.deinit(outer_alloc);
        }
        self.arena.deinit();
    }
};

fn prepareFrameContext(
    outer_alloc: std.mem.Allocator,
    ctx: *FrameContext,
    input: *const FrameInput,
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
    ctx.frame_arr = try ndarray.NDArray(f64).initFlat(arena_alloc, dims[0..]);
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

    for (0..frame_arr.dims[0]) |ff| {
        for (0..frame_arr.dims[1]) |rr| {
            for (0..frame_arr.dims[2]) |cc| {
                images_arr.set(
                    &[_]usize{ camera_idx, frame_idx, ff, rr, cc },
                    frame_arr.get(&[_]usize{ ff, rr, cc }),
                );
            }
        }
    }
}

fn rasterFrame(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: *const FrameInput,
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
        input.raster_workers,
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
    input: *const FrameInput,
    ctx: *FrameContext,
) !void {
    switch (input.config.report) {
        .off => try rasterFrame(
            .off,
            outer_alloc,
            io,
            input,
            ctx,
        ),
        .bench => try rasterFrame(
            .bench,
            outer_alloc,
            io,
            input,
            ctx,
        ),
        .full_stats => try rasterFrame(
            .full_stats,
            outer_alloc,
            io,
            input,
            ctx,
        ),
    }
}

fn saveFrame(
    io: std.Io,
    input: *const FrameInput,
    ctx: *FrameContext,
) !void {
    if (input.config.save_strategy == .disk or input.config.save_strategy == .both) {
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
    if (input.images_arr) |images_arr| {
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
    input: *const FrameInput,
    ctx: *FrameContext,
) !void {
    const arena_alloc = ctx.arena.allocator();
    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        input.camera.pixels_num[0],
        ctx.actual_tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        input.camera.pixels_num[1],
        ctx.actual_tile_size,
    );

    const time_start_overlap = Timestamp.now(io, .awake);
    ctx.tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        input.chunk_exec,
        scalingpolicy.geometryWorkers(input.geom_workers),
        ctx.actual_tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(input.camera.pixels_num[0]),
        @intCast(input.camera.pixels_num[1]),
        ctx.elems_in_image_by_mesh,
        ctx.elem_bboxes_by_mesh,
    );
    const time_end_overlap = Timestamp.now(io, .awake);
    ctx.frame_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds,
    );
}

//------------------------------------------------------------------------------------------
// 3. Process: frame jobs for a given camera and frame
const FrameInput = struct {
    camera: *const cam.CameraPrepared,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    mesh_static: []const mo.MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_workers: u16,
    raster_workers: u16,
    chunk_exec: ?*pce.ParaChunkExecutor,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
    cameras_num: usize,
    err_state: *FrameJobErrorState,
};

fn processFrameJobInternal(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: FrameInput,
) !void {
    const time_start_frame = Timestamp.now(io, .awake);

    // Stage 1: Allocate and Prepare Frame Context
    var ctx = FrameContext.init(outer_alloc);
    defer ctx.deinit(outer_alloc, &input);

    try prepareFrameContext(
        outer_alloc,
        &ctx,
        &input,
    );

    // Stage 2: Geometry Preparation
    const time_start_geo = Timestamp.now(io, .awake);
    const arena_alloc = ctx.arena.allocator();

    const geo_res = try mo.prepareMeshFrames(
        arena_alloc,
        input.chunk_exec,
        scalingpolicy.geometryWorkers(input.geom_workers),
        input.camera,
        input.config,
        input.frame_idx,
        input.mesh_static,
        input.nodal_global_scaling,
        ctx.frame_meshes,
    );
    for (ctx.frame_meshes, 0..) |*fm, ii| {
        ctx.prep_meshes[ii] = fm.mesh;
        ctx.elem_bboxes_by_mesh[ii] = fm.elem_bboxes;
        ctx.elems_in_image_by_mesh[ii] = fm.elems_in_image;
        ctx.raster_hulls[ii] = fm.raster_hull;
    }
    ctx.total_elems_num = geo_res.total_elems_num;
    ctx.total_elems_in_image = geo_res.total_elems_in_image;

    const time_end_geo = Timestamp.now(io, .awake);
    ctx.frame_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );

    // Stage 3: Scene-tile overlap
    try sceneTileOverlapBinning(
        io,
        &input,
        &ctx,
    );

    // Stage 4: Render the frame by rasterisation
    try runRasterFrame(
        outer_alloc,
        io,
        &input,
        &ctx,
    );

    // Stage 5: Finalise frame
    const time_start_save = Timestamp.now(io, .awake);
    try saveFrame(io, &input, &ctx);
    const time_end_save = Timestamp.now(io, .awake);
    ctx.frame_times.save_frame = @floatFromInt(
        time_start_save.durationTo(time_end_save).raw.nanoseconds,
    );

    const time_end_frame = Timestamp.now(io, .awake);
    ctx.frame_times.total_time = @floatFromInt(
        time_start_frame.durationTo(time_end_frame).raw.nanoseconds,
    );

    try report.publishFrameResults(
        outer_alloc,
        io,
        input.config,
        ctx.actual_tile_size,
        input.camera,
        input.camera_idx,
        input.frame_idx,
        input.cameras_num,
        input.out_dir,
        input.bench_capture,
        &ctx.report_storage,
        ctx.frame_times,
        ctx.total_elems_num,
        ctx.total_elems_in_image,
        ctx.prep_meshes,
    );
}

// Async/parallel processing function
fn processFrameJobAsync(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: FrameInput,
) std.Io.Cancelable!void {
    processFrameJobInternal(outer_alloc, io, input) catch |err| {
        input.err_state.setFirst(err);
    };
}

// Serial processing function
fn processFrameJobSerial(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: FrameInput,
) !void {
    try processFrameJobInternal(outer_alloc, io, input);
}

//------------------------------------------------------------------------------------------
// 2. Dispatch: Frame jobs over cameras and frames frames to render
fn dispatchFrameJobsSerial(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
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
    const dispatch_scale = scalingpolicy.dispatchScaling(
        .in_order,
        config,
        cameras.len,
    );

    const chunk_exec: ?*pce.ParaChunkExecutor = null;

    for (0..num_time) |frame_idx| {
        for (cameras, 0..) |*camera, camera_idx| {
            try processFrameJobSerial(
                outer_alloc,
                io,
                FrameInput{
                    .camera = camera,
                    .camera_idx = camera_idx,
                    .frame_idx = frame_idx,
                    .num_fields = num_fields,
                    .config = config,
                    .out_dir = out_dir,
                    .mesh_static = mesh_static,
                    .nodal_global_scaling = nodal_global_scaling,
                    .geom_workers = dispatch_scale.geom_workers,
                    .raster_workers = dispatch_scale.raster_workers,
                    .chunk_exec = chunk_exec,
                    .images_arr = images_arr,
                    .bench_capture = bench_capture,
                    .cameras_num = cameras.len,
                    .err_state = undefined,
                },
            );
        }
    }
}

fn dispatchFrameJobsOffline(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
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
    const jobs_num = cameras.len * num_time;
    const dispatch_scale = scalingpolicy.dispatchScaling(
        .offline,
        config,
        cameras.len,
    );

    var pool = pce.ParaChunkExecutor.init(io, dispatch_scale.geom_workers);
    var chunk_exec: ?*pce.ParaChunkExecutor = null;
    if (dispatch_scale.geom_workers > 1) {
        chunk_exec = &pool;
    }

    const batch_size = scalingpolicy.frameBatchSize(
        dispatch_scale.frames_in_flight,
        jobs_num,
    );
    var batch_start: usize = 0;
    while (batch_start < jobs_num) : (batch_start += batch_size) {
        var err_state = FrameJobErrorState{};

        var group: std.Io.Group = .init;
        errdefer group.cancel(io);

        const batch_end = @min(jobs_num, batch_start + batch_size);

        for (batch_start..batch_end) |job_idx| {
            const frame_idx = @divFloor(job_idx, cameras.len);
            const camera_idx = @mod(job_idx, cameras.len);
            const camera = &cameras[camera_idx];

            group.async(
                io,
                processFrameJobAsync,
                .{
                    outer_alloc,
                    io,
                    FrameInput{
                        .camera = camera,
                        .camera_idx = camera_idx,
                        .frame_idx = frame_idx,
                        .num_fields = num_fields,
                        .config = config,
                        .out_dir = out_dir,
                        .mesh_static = mesh_static,
                        .nodal_global_scaling = nodal_global_scaling,
                        .geom_workers = dispatch_scale.geom_workers,
                        .raster_workers = dispatch_scale.raster_workers,
                        .chunk_exec = chunk_exec,
                        .images_arr = images_arr,
                        .bench_capture = bench_capture,
                        .cameras_num = cameras.len,
                        .err_state = &err_state,
                    },
                },
            );
        }

        try group.await(io);
        if (err_state.first_err) |err| {
            return err;
        }
    }
}

fn dispatchFrameJobsInOrder(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
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
    const dispatch_scale = scalingpolicy.dispatchScaling(
        .in_order,
        config,
        cameras.len,
    );

    var pool = pce.ParaChunkExecutor.init(io, dispatch_scale.geom_workers);
    var chunk_exec: ?*pce.ParaChunkExecutor = null;
    if (dispatch_scale.geom_workers > 1) {
        chunk_exec = &pool;
    }

    for (0..num_time) |frame_idx| {
        var err_state = FrameJobErrorState{};

        var group: std.Io.Group = .init;
        errdefer group.cancel(io);

        for (cameras, 0..) |*camera, camera_idx| {
            group.async(
                io,
                processFrameJobAsync,
                .{
                    outer_alloc,
                    io,
                    FrameInput{
                        .camera = camera,
                        .camera_idx = camera_idx,
                        .frame_idx = frame_idx,
                        .num_fields = num_fields,
                        .config = config,
                        .out_dir = out_dir,
                        .mesh_static = mesh_static,
                        .nodal_global_scaling = nodal_global_scaling,
                        .geom_workers = dispatch_scale.geom_workers,
                        .raster_workers = dispatch_scale.raster_workers,
                        .chunk_exec = chunk_exec,
                        .images_arr = images_arr,
                        .bench_capture = bench_capture,
                        .cameras_num = cameras.len,
                        .err_state = &err_state,
                    },
                },
            );
        }

        try group.await(io);
        if (err_state.first_err) |err| {
            return err;
        }
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

//==========================================================================================
// 1. Main entry point function to the rasteriser
pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]report.FrameBenchCapture,
) !?ndarray.NDArray(f64) {
    const time_start_render = Timestamp.now(io, .awake);

    var out_dir: ?std.Io.Dir = null;
    if (out_dir_path) |path| {
        const cwd = std.Io.Dir.cwd();
        cwd.createDir(io, path, .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
        out_dir = try cwd.openDir(io, path, .{});
    }
    defer if (out_dir) |*od| od.close(io);

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
    const time_end_setup = Timestamp.now(io, .awake);
    var end_to_end_times = report.EndToEndTimes{
        .setup_time = @floatFromInt(
            time_start_render.durationTo(time_end_setup).raw.nanoseconds,
        ),
    };
    const time_start_dispatch = Timestamp.now(io, .awake);

    if (config.total_threads == 0) {
        try dispatchFrameJobsSerial(
            outer_alloc,
            io,
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

        const time_end_render = Timestamp.now(io, .awake);
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
            io,
            cameras,
            actual_tile_size,
            num_time,
            config.report,
            end_to_end_times,
        );
        return images_arr_opt;
    }

    if (config.render_mode == .in_order) {
        try dispatchFrameJobsInOrder(
            outer_alloc,
            io,
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

        const time_end_render = Timestamp.now(io, .awake);
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
            io,
            cameras,
            actual_tile_size,
            num_time,
            config.report,
            end_to_end_times,
        );
        return images_arr_opt;
    }

    try dispatchFrameJobsOffline(
        outer_alloc,
        io,
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

    const time_end_render = Timestamp.now(io, .awake);
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
        io,
        cameras,
        actual_tile_size,
        num_time,
        config.report,
        end_to_end_times,
    );
    return images_arr_opt;
}
