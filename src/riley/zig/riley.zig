// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
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

const report = @import("report.zig");
const FrameReportStorage = report.FrameReportStorage;

pub fn getThreadedIo(
    gpa: std.mem.Allocator,
    minimal: std.process.Init.Minimal,
    num_threads: u16,
) std.Io.Threaded {
    // User-facing thread counts in riley always include the caller thread.
    // Zig's std.Io.Threaded limits count only spawned worker threads, excluding
    // the caller. Translate here so:
    //   threads=1  -> caller only
    //   threads=N  -> caller + (N - 1) worker threads
    const limit: std.Io.Limit =
        if (num_threads <= 1) .nothing else .limited(num_threads - 1);

    return std.Io.Threaded.init(gpa, .{
        .argv0 = .init(minimal.args),
        .environ = minimal.environ,
        .async_limit = limit,
        .concurrent_limit = limit,
    });
}

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

const SaveSlotState = enum {
    free,
    rendering,
    ready_to_save,
    saving,
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
    dims: [5]usize,
) !ndarray.NDArray(f64) {
    return try ndarray.NDArray(f64).initFlat(
        outer_alloc,
        dims[0..],
    );
}

fn calcAllFramesDimsFromPixels(
    camera_pixels_num: []const [2]u32,
    num_time: usize,
    num_fields: u8,
) [5]usize {
    std.debug.assert(camera_pixels_num.len > 0);

    var max_pixels_num = camera_pixels_num[0];
    for (camera_pixels_num[1..]) |pixels_num| {
        max_pixels_num[0] = @max(max_pixels_num[0], pixels_num[0]);
        max_pixels_num[1] = @max(max_pixels_num[1], pixels_num[1]);
    }

    return .{
        camera_pixels_num.len,
        num_time,
        @as(usize, num_fields),
        max_pixels_num[1],
        max_pixels_num[0],
    };
}

fn validateAllFramesBuffer(
    images_arr: *const ndarray.NDArray(f64),
    expected_dims: [5]usize,
) !void {
    if (images_arr.dims.len != expected_dims.len) {
        return error.InvalidOutputBuffer;
    }
    for (expected_dims, 0..) |expected_dim, dd| {
        if (images_arr.dims[dd] != expected_dim) {
            return error.InvalidOutputBuffer;
        }
    }
}

pub fn calcAllFramesImageDims(
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
) [5]usize {
    std.debug.assert(camera_inputs.len > 0);
    std.debug.assert(meshes.len > 0);

    const num_time = mo.countFrames(meshes);
    const num_fields = mo.countOutputFields(meshes);
    var max_pixels_num = camera_inputs[0].pixels_num;
    for (camera_inputs[1..]) |camera_input| {
        max_pixels_num[0] = @max(max_pixels_num[0], camera_input.pixels_num[0]);
        max_pixels_num[1] = @max(max_pixels_num[1], camera_input.pixels_num[1]);
    }

    return .{
        camera_inputs.len,
        num_time,
        @as(usize, num_fields),
        max_pixels_num[1],
        max_pixels_num[0],
    };
}

fn getFrameImageView(
    allocator: std.mem.Allocator,
    images_arr: *ndarray.NDArray(f64),
    camera_idx: usize,
    frame_idx: usize,
) !ndarray.NDArray(f64) {
    std.debug.assert(images_arr.dims.len == 5);
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
        report.deinitFrameReportStorage(
            outer_alloc,
            config,
            &self.report_storage,
        );
        self.arena.deinit();
    }
};

const SaveSlot = struct {
    state: SaveSlotState = .free,
    frame_arr: ndarray.NDArray(f64),
    camera: ?*const cam.CameraPrepared = null,
    camera_idx: usize = 0,
    frame_idx: usize = 0,
    cameras_num: usize = 0,
    num_fields: u8 = 0,
    pixels_num: [2]u32 = .{ 0, 0 },
    out_dir: ?std.Io.Dir = null,
    bench_capture: ?[]report.FrameBenchCapture = null,
    report_storage: FrameReportStorage = .{ .off = .{} },
    frame_times: report.FrameTimes = .{},
    total_elems_num: usize = 0,
    total_elems_in_image: usize = 0,
    nodes_per_elem: f64 = 0.0,
    actual_tile_size: u16 = 1,
    time_start_frame: ?Timestamp = null,

    fn resetReportStorage(
        self: *SaveSlot,
        outer_alloc: std.mem.Allocator,
        config: RasterConfig,
    ) void {
        report.deinitFrameReportStorage(
            outer_alloc,
            config,
            &self.report_storage,
        );
    }
};

const SaveCoordinator = struct {
    mutex: std.Io.Mutex = .init,
    ready_cond: std.Io.Condition = .init,
    free_cond: std.Io.Condition = .init,
    done_submitting: bool = false,
    first_err: ?anyerror = null,
    slots: []SaveSlot,

    fn setFirstError(
        self: *SaveCoordinator,
        io: std.Io,
        err: anyerror,
    ) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        if (self.first_err == null) {
            self.first_err = err;
        }
        self.done_submitting = true;
        self.ready_cond.broadcast(io);
        self.free_cond.broadcast(io);
    }
};

const SaveSlotBuffer = struct {
    slots: []SaveSlot,
    frame_pool: ndarray.NDArray(f64),
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
    if (input.save_slot) |save_slot| {
        ctx.frame_arr = save_slot.frame_arr;
        std.debug.assert(ctx.frame_arr.dims.len == dims.len);
        for (dims, 0..) |dim, ii| std.debug.assert(ctx.frame_arr.dims[ii] == dim);
        @memset(ctx.frame_arr.slice, input.config.background_value);
        return;
    }
    if (input.can_write_result_direct) {
        const images_arr = input.images_arr orelse return error.NoResult;
        ctx.frame_arr = try getFrameImageView(
            arena_alloc,
            images_arr,
            input.camera_idx,
            input.frame_idx,
        );
    } else {
        ctx.frame_arr = try ndarray.NDArray(f64).initFlat(
            arena_alloc,
            dims[0..],
        );
    }
    std.debug.assert(ctx.frame_arr.dims.len == dims.len);
    for (dims, 0..) |dim, ii| std.debug.assert(ctx.frame_arr.dims[ii] == dim);
    @memset(ctx.frame_arr.slice, input.config.background_value);
}

fn copyFrameToImageBatch(
    background_val: f64,
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
    const dst_rows = images_arr.dims[3];
    const dst_cols = images_arr.dims[4];
    const src_rows = frame_arr.dims[1];
    const src_cols = frame_arr.dims[2];
    for (0..frame_arr.dims[0]) |ff| {
        const dst_field_base = dst_base + ff * dst_field_stride;
        const src_field_base = ff * src_field_stride;

        for (0..dst_rows) |rr| {
            const dst_row_base = dst_field_base + rr * dst_row_stride;
            @memset(
                images_arr.slice[dst_row_base .. dst_row_base + dst_cols],
                background_val,
            );
        }

        for (0..src_rows) |rr| {
            const dst_row_base = dst_field_base + rr * dst_row_stride;
            const src_row_base = src_field_base + rr * src_row_stride;
            @memcpy(
                images_arr.slice[dst_row_base .. dst_row_base + src_cols],
                frame_arr.slice[src_row_base .. src_row_base + src_cols],
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

fn saveFrame(
    io: std.Io,
    input: *const FrameJobDesc,
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
    if ((input.config.save_strategy == .memory or input.config.save_strategy == .both) and !input.can_write_result_direct) {
        const images_arr = input.images_arr orelse return error.NoResult;
        copyFrameToImageBatch(
            input.config.background_value,
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
    save_frame_io: ?std.Io = null,
    workers: u16,
};

fn renderGroupSaveIo(render_group: RenderGroupSpec) std.Io {
    return render_group.save_frame_io orelse render_group.io;
}

fn saveOverlapEnabled(config: RasterConfig) bool {
    return config.save_strategy == .disk and config.disk_save_overlap;
}

fn initSaveSlots(
    save_alloc: std.mem.Allocator,
    cameras: []const cam.CameraPrepared,
    num_fields: u8,
    slot_count: usize,
) !SaveSlotBuffer {
    std.debug.assert(cameras.len > 0);
    var max_pixels_num = cameras[0].pixels_num;
    for (cameras[1..]) |camera| {
        max_pixels_num[0] = @max(max_pixels_num[0], camera.pixels_num[0]);
        max_pixels_num[1] = @max(max_pixels_num[1], camera.pixels_num[1]);
    }
    const frame_pool = try ndarray.NDArray(f64).initFlat(
        save_alloc,
        &[_]usize{
            slot_count,
            @as(usize, num_fields),
            max_pixels_num[1],
            max_pixels_num[0],
        },
    );
    const slots = try save_alloc.alloc(SaveSlot, slot_count);
    for (0..slot_count) |ss| {
        slots[ss] = .{
            .frame_arr = try frame_pool.fixedPrefixView(
                save_alloc,
                &[_]usize{ss},
            ),
        };
    }
    return SaveSlotBuffer{
        .slots = slots,
        .frame_pool = frame_pool,
    };
}

fn acquireSaveSlot(
    io: std.Io,
    coordinator: *SaveCoordinator,
) !usize {
    try coordinator.mutex.lock(io);
    defer coordinator.mutex.unlock(io);

    while (true) {
        if (coordinator.first_err) |err| return err;
        for (coordinator.slots, 0..) |*slot, ss| {
            if (slot.state == .free) {
                slot.state = .rendering;
                return ss;
            }
        }
        try coordinator.free_cond.wait(io, &coordinator.mutex);
    }
}

fn completeSaveSlot(
    outer_alloc: std.mem.Allocator,
    save_io: std.Io,
    coordinator: *SaveCoordinator,
    slot_idx: usize,
    config: RasterConfig,
) !void {
    var slot = &coordinator.slots[slot_idx];
    const time_start_save = Timestamp.now(save_io, .awake);
    std.debug.assert(slot.camera != null);
    std.debug.assert(slot.pixels_num[0] > 0);
    std.debug.assert(slot.pixels_num[1] > 0);
    try iio.saveImages(
        save_io,
        slot.out_dir,
        slot.camera_idx,
        slot.frame_idx,
        slot.num_fields,
        slot.pixels_num,
        &slot.frame_arr,
        config.image_save_opts,
    );
    const time_end_save = Timestamp.now(save_io, .awake);

    slot.frame_times.save_frame = @floatFromInt(
        time_start_save.durationTo(time_end_save).raw.nanoseconds,
    );
    slot.frame_times.active_time =
        slot.frame_times.geometry_prep +
        slot.frame_times.tile_overlap +
        slot.frame_times.raster_loop +
        slot.frame_times.save_frame;
    slot.frame_times.latency_time = @floatFromInt(
        slot.time_start_frame.?.durationTo(time_end_save).raw.nanoseconds,
    );

    try report.publishFrameResultsWithNodesPerElem(
        outer_alloc,
        save_io,
        config,
        slot.actual_tile_size,
        slot.camera.?,
        slot.camera_idx,
        slot.frame_idx,
        slot.cameras_num,
        slot.out_dir,
        slot.bench_capture,
        &slot.report_storage,
        slot.frame_times,
        slot.total_elems_num,
        slot.total_elems_in_image,
        slot.nodes_per_elem,
    );

    try coordinator.mutex.lock(save_io);
    defer coordinator.mutex.unlock(save_io);
    slot.resetReportStorage(outer_alloc, config);
    slot.state = .free;
    coordinator.free_cond.signal(save_io);
}

fn saveWorkerLoop(
    outer_alloc: std.mem.Allocator,
    save_io: std.Io,
    coordinator: *SaveCoordinator,
    config: RasterConfig,
) void {
    while (true) {
        coordinator.mutex.lockUncancelable(save_io);
        while (true) {
            if (coordinator.first_err != null) {
                coordinator.mutex.unlock(save_io);
                return;
            }
            var ready_idx: ?usize = null;
            for (coordinator.slots, 0..) |slot, ss| {
                if (slot.state == .ready_to_save) {
                    ready_idx = ss;
                    break;
                }
            }
            if (ready_idx) |slot_idx| {
                coordinator.slots[slot_idx].state = .saving;
                coordinator.mutex.unlock(save_io);
                completeSaveSlot(
                    outer_alloc,
                    save_io,
                    coordinator,
                    slot_idx,
                    config,
                ) catch |err| {
                    coordinator.setFirstError(save_io, err);
                    return;
                };
                break;
            }
            if (coordinator.done_submitting) {
                coordinator.mutex.unlock(save_io);
                return;
            }
            coordinator.ready_cond.waitUncancelable(save_io, &coordinator.mutex);
        }
    }
}

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
    can_write_result_direct: bool,
    save_slot: ?*SaveSlot = null,
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

fn runGeometryStage(
    group_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    geom_workers: u16,
) !void {
    if (job.time_start_frame == null) {
        job.time_start_frame = Timestamp.now(io, .awake);
    }

    const time_start_geo = Timestamp.now(io, .awake);
    try prepareFrameContext(
        group_alloc,
        &job.ctx,
        &job.desc,
    );

    var chunk_exec = pce.ParaChunkExecutor.init(io, geom_workers);
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

fn runRasterStage(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    raster_workers: u16,
) !void {
    switch (job.desc.config.report) {
        .off => try rasterFrame(
            .off,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
        .bench => try rasterFrame(
            .bench,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
        .full_stats => try rasterFrame(
            .full_stats,
            outer_alloc,
            io,
            &job.desc,
            raster_workers,
            &job.ctx,
        ),
    }
}

fn runRasterAndSaveFrame(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    job: *PreparedFrameJob,
    raster_workers: u16,
) !void {
    try runRasterStage(
        outer_alloc,
        io,
        job,
        raster_workers,
    );
    const time_start_save = Timestamp.now(io, .awake);
    try saveFrame(io, &job.desc, &job.ctx);
    const time_end_save = Timestamp.now(io, .awake);

    job.ctx.frame_times.save_frame = @floatFromInt(
        time_start_save.durationTo(time_end_save).raw.nanoseconds,
    );
    job.ctx.frame_times.active_time =
        job.ctx.frame_times.geometry_prep +
        job.ctx.frame_times.tile_overlap +
        job.ctx.frame_times.raster_loop +
        job.ctx.frame_times.save_frame;

    const time_end_frame = Timestamp.now(io, .awake);

    job.ctx.frame_times.latency_time = @floatFromInt(
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

fn prepareJobBatch(
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
                .can_write_result_direct = images_arr != null and
                    cam.allCamerasSharePixels(cameras),
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
    const AsyncGeometryJob = struct {
        fn run(
            local_group_alloc: std.mem.Allocator,
            local_io: std.Io,
            job: *PreparedFrameJob,
            geom_workers: u16,
            err_state: *FrameJobErrorState,
        ) std.Io.Cancelable!void {
            runGeometryStage(
                local_group_alloc,
                local_io,
                job,
                geom_workers,
            ) catch |err| {
                err_state.setFirst(err);
            };
        }
    };

    var err_state = FrameJobErrorState{};
    var group: std.Io.Group = .init;
    errdefer group.cancel(io);

    const caller_idx = jobs.len - 1;
    for (jobs[0..caller_idx], workers_per_job[0..caller_idx]) |*job, geom_workers| {
        group.async(
            io,
            AsyncGeometryJob.run,
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
    group_io: std.Io,
    group_alloc: std.mem.Allocator,
    group_workers: u16,
    config: RasterConfig,
    save_coordinator: ?*SaveCoordinator,
    jobs: []PreparedFrameJob,
) !void {
    const raster_workers = @min(
        @max(@as(u16, 1), group_workers),
        @max(@as(u16, 1), config.max_raster_workers_per_job),
    );
    for (jobs) |*job| {
        defer job.deinit(group_alloc);
        if (save_coordinator) |coordinator| {
            const slot_idx = try acquireSaveSlot(group_io, coordinator);
            const slot = &coordinator.slots[slot_idx];
            job.desc.save_slot = slot;
            try runRasterStage(
                outer_alloc,
                group_io,
                job,
                raster_workers,
            );
            slot.camera = job.desc.camera;
            slot.camera_idx = job.desc.camera_idx;
            slot.frame_idx = job.desc.frame_idx;
            slot.cameras_num = job.desc.cameras_num;
            slot.num_fields = @intCast(job.ctx.frame_arr.dims[0]);
            slot.pixels_num = .{
                job.desc.camera.pixels_num[0],
                job.desc.camera.pixels_num[1],
            };
            slot.out_dir = job.desc.out_dir;
            slot.bench_capture = job.desc.bench_capture;
            slot.report_storage = job.ctx.report_storage;
            job.ctx.report_storage = .{ .off = .{} };
            slot.frame_times = job.ctx.frame_times;
            slot.total_elems_num = job.ctx.total_elems_num;
            slot.total_elems_in_image = job.ctx.total_elems_in_image;
            slot.nodes_per_elem = mo.calcNodesPerElem(job.ctx.prep_meshes);
            slot.actual_tile_size = job.ctx.actual_tile_size;
            slot.time_start_frame = job.time_start_frame;

            try coordinator.mutex.lock(group_io);
            slot.state = .ready_to_save;
            coordinator.ready_cond.signal(group_io);
            coordinator.mutex.unlock(group_io);
            continue;
        }
        try runRasterAndSaveFrame(
            outer_alloc,
            group_io,
            job,
            raster_workers,
        );
    }
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
    next_job: std.atomic.Value(usize) =
        std.atomic.Value(usize).init(0),
    err_state: *FrameJobErrorState,
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
    next_camera: std.atomic.Value(usize) =
        std.atomic.Value(usize).init(0),
    err_state: *FrameJobErrorState,
};

fn processOfflineRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *OfflineDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();
    const jobs_num = shared.cameras.len * shared.num_time;
    const overlap_save = saveOverlapEnabled(shared.config);
    var save_frame_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer save_frame_arena.deinit();
    const save_frame_alloc = save_frame_arena.allocator();
    var save_slots_buf: ?SaveSlotBuffer = null;
    var save_coordinator: ?SaveCoordinator = null;
    var save_thread: ?std.Thread = null;
    if (overlap_save) {
        save_slots_buf = try initSaveSlots(
            save_frame_alloc,
            shared.cameras,
            shared.num_fields,
            @max(@as(usize, 1), shared.config.save_frame_buffer_count),
        );
        save_coordinator = .{ .slots = save_slots_buf.?.slots };
        save_thread = try std.Thread.spawn(
            .{},
            saveWorkerLoop,
            .{
                shared.outer_alloc,
                renderGroupSaveIo(render_group),
                &save_coordinator.?,
                shared.config,
            },
        );
    }
    defer {
        if (save_coordinator) |*coordinator| {
            coordinator.mutex.lockUncancelable(renderGroupSaveIo(render_group));
            coordinator.done_submitting = true;
            coordinator.ready_cond.broadcast(renderGroupSaveIo(render_group));
            coordinator.free_cond.broadcast(renderGroupSaveIo(render_group));
            coordinator.mutex.unlock(renderGroupSaveIo(render_group));
        }
        if (save_thread) |thread| {
            thread.join();
        }
        if (save_coordinator) |*coordinator| {
            for (coordinator.slots) |*slot| {
                slot.resetReportStorage(shared.outer_alloc, shared.config);
            }
        }
    }

    while (true) {
        const batch_start = shared.next_job.fetchAdd(shared.batch_size, .monotonic);
        if (batch_start >= jobs_num) break;
        const batch_end = @min(jobs_num, batch_start + shared.batch_size);
        const batch_len = batch_end - batch_start;
        const job_indices = try group_alloc.alloc(usize, batch_len);
        for (0..batch_len) |ii| {
            job_indices[ii] = batch_start + ii;
        }
        const jobs = try prepareJobBatch(
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
        try processGeometryBatch(
            group_alloc,
            render_group.io,
            render_group.workers,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );
        try processRasterBatch(
            shared.outer_alloc,
            render_group.io,
            group_alloc,
            render_group.workers,
            shared.config,
            if (save_coordinator) |*coordinator| coordinator else null,
            jobs,
        );
        _ = group_arena.reset(.retain_capacity);
    }

    if (save_coordinator) |*coordinator| {
        try coordinator.mutex.lock(render_group.io);
        coordinator.done_submitting = true;
        coordinator.ready_cond.broadcast(render_group.io);
        coordinator.free_cond.broadcast(render_group.io);
        coordinator.mutex.unlock(render_group.io);
    }
    if (save_coordinator) |*coordinator| {
        if (coordinator.first_err) |err| return err;
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

fn dispatchFrameJobsOffline(
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
    var err_state = FrameJobErrorState{};
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
        .total_scene_elems = mo.countStaticMeshElements(mesh_static),
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
    for (threads) |thread| {
        thread.join();
    }
    if (err_state.first_err) |err| return err;
}

fn processInOrderRenderGroupLoop(
    render_group: RenderGroupSpec,
    shared: *InOrderDispatchShared,
) !void {
    var group_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer group_arena.deinit();
    const group_alloc = group_arena.allocator();
    const overlap_save = saveOverlapEnabled(shared.config);
    var save_frame_arena = std.heap.ArenaAllocator.init(shared.outer_alloc);
    defer save_frame_arena.deinit();
    const save_frame_alloc = save_frame_arena.allocator();
    var save_slots_buf: ?SaveSlotBuffer = null;
    var save_coordinator: ?SaveCoordinator = null;
    var save_thread: ?std.Thread = null;
    if (overlap_save) {
        save_slots_buf = try initSaveSlots(
            save_frame_alloc,
            shared.cameras,
            shared.num_fields,
            @max(@as(usize, 1), shared.config.save_frame_buffer_count),
        );
        save_coordinator = .{ .slots = save_slots_buf.?.slots };
        save_thread = try std.Thread.spawn(
            .{},
            saveWorkerLoop,
            .{
                shared.outer_alloc,
                renderGroupSaveIo(render_group),
                &save_coordinator.?,
                shared.config,
            },
        );
    }
    defer {
        if (save_coordinator) |*coordinator| {
            coordinator.mutex.lockUncancelable(renderGroupSaveIo(render_group));
            coordinator.done_submitting = true;
            coordinator.ready_cond.broadcast(renderGroupSaveIo(render_group));
            coordinator.free_cond.broadcast(renderGroupSaveIo(render_group));
            coordinator.mutex.unlock(renderGroupSaveIo(render_group));
        }
        if (save_thread) |thread| {
            thread.join();
        }
        if (save_coordinator) |*coordinator| {
            for (coordinator.slots) |*slot| {
                slot.resetReportStorage(shared.outer_alloc, shared.config);
            }
        }
    }

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
        const jobs = try prepareJobBatch(
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
        try processGeometryBatch(
            group_alloc,
            render_group.io,
            render_group.workers,
            shared.config,
            shared.total_scene_elems,
            jobs,
        );
        try processRasterBatch(
            shared.outer_alloc,
            render_group.io,
            group_alloc,
            render_group.workers,
            shared.config,
            if (save_coordinator) |*coordinator| coordinator else null,
            jobs,
        );
        _ = group_arena.reset(.retain_capacity);
    }

    if (save_coordinator) |*coordinator| {
        try coordinator.mutex.lock(render_group.io);
        coordinator.done_submitting = true;
        coordinator.ready_cond.broadcast(render_group.io);
        coordinator.free_cond.broadcast(render_group.io);
        coordinator.mutex.unlock(render_group.io);
    }
    if (save_coordinator) |*coordinator| {
        if (coordinator.first_err) |err| return err;
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

fn dispatchFrameJobsInOrder(
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
    const total_scene_elems = mo.countStaticMeshElements(mesh_static);
    const batch_size = @max(@as(usize, 1), config.frame_batch_size_per_group);

    for (0..num_time) |frame_idx| {
        var err_state = FrameJobErrorState{};
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

        var threads = try outer_alloc.alloc(
            std.Thread,
            render_groups.len -| 1,
        );
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
        for (threads) |thread| {
            thread.join();
        }
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

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
) !?ndarray.NDArray(f64) {
    return rasterAllFramesReport(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        null,
    );
}

pub fn rasterAllFramesInto(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    images_arr: ?*ndarray.NDArray(f64),
) !void {
    try rasterAllFramesReportInto(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        images_arr,
        null,
    );
}

pub fn rasterAllFramesReport(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]report.FrameBenchCapture,
) !?ndarray.NDArray(f64) {
    const needs_images_arr = config.save_strategy == .memory or
        config.save_strategy == .both;
    var images_arr_opt: ?ndarray.NDArray(f64) = null;
    if (needs_images_arr) {
        const dims = calcAllFramesImageDims(camera_inputs, meshes);
        images_arr_opt = try initAllFramesBuffer(
            outer_alloc,
            dims,
        );
    }
    errdefer if (images_arr_opt) |*images_arr| {
        outer_alloc.free(images_arr.slice);
        images_arr.deinit(outer_alloc);
    };

    try rasterAllFramesReportInto(
        outer_alloc,
        render_groups,
        camera_inputs,
        meshes,
        config,
        out_dir_path,
        if (images_arr_opt) |*images_arr| images_arr else null,
        bench_capture,
    );
    return images_arr_opt;
}

pub fn rasterAllFramesReportInto(
    outer_alloc: std.mem.Allocator,
    render_groups: []const RenderGroupSpec,
    camera_inputs: []const cam.CameraInput,
    meshes: []const mo.MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    images_arr: ?*ndarray.NDArray(f64),
    bench_capture: ?[]report.FrameBenchCapture,
) !void {
    std.debug.assert(render_groups.len > 0);
    const summary_io = render_groups[0].io;
    const time_start_render = Timestamp.now(summary_io, .awake);

    var out_dir: ?std.Io.Dir = null;
    if (out_dir_path) |path| {
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(summary_io, path) catch |err| {
            if (err != error.PathAlreadyExists) {
                return err;
            }
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

    const num_time = mo.countFrames(meshes);
    const num_fields = mo.countOutputFields(meshes);

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

    const time_start_frame_buffer = Timestamp.now(summary_io, .awake);
    if (config.save_strategy == .memory or config.save_strategy == .both) {
        const expected_image_dims = calcAllFramesImageDims(camera_inputs, meshes);
        const images_arr_req = images_arr orelse return error.InvalidOutputBuffer;
        try validateAllFramesBuffer(images_arr_req, expected_image_dims);
    } else if (images_arr != null) {
        return error.InvalidOutputBuffer;
    }
    const time_end_setup = Timestamp.now(summary_io, .awake);
    var end_to_end_times = report.EndToEndTimes{
        .setup_time = @floatFromInt(
            time_start_render.durationTo(time_end_setup).raw.nanoseconds,
        ),
        .setup_other_time = @floatFromInt(
            time_start_render.durationTo(
                time_start_frame_buffer,
            ).raw.nanoseconds,
        ),
        .setup_frame_buffer_time = @floatFromInt(
            time_start_frame_buffer.durationTo(
                time_end_setup,
            ).raw.nanoseconds,
        ),
    };
    const time_start_dispatch = Timestamp.now(summary_io, .awake);

    if (config.render_mode == .in_order) {
        try dispatchFrameJobsInOrder(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            images_arr,
            bench_capture,
        );
    } else {
        try dispatchFrameJobsOffline(
            outer_alloc,
            render_groups,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static,
            nodal_global_scaling,
            images_arr,
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
}
