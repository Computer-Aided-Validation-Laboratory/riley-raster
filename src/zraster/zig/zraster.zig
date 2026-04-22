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

const MatSlice = @import("matslice.zig").MatSlice;
pub const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const ActiveTile = rops.ActiveTile;
const Vec3Slices = rops.Vec3Slices;

const mr = @import("meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const MeshPrepared = mr.MeshPrepared;
const MeshStaticPrepared = mr.MeshStaticPrepared;
const FrameMeshPrepared = mr.FrameMeshPrepared;
const shaderops = @import("shaderops.zig");
const ShaderInput = shaderops.ShaderInput;
const ShaderPrepared = shaderops.ShaderPrepared;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;
const imageops = @import("imageops.zig");
const geomthread = @import("geomthread.zig");

const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

const report = @import("report.zig");
const ReportMode = report.ReportMode;
const BenchLog = report.BenchLog;
const FullStatsOpts = report.FullStatsOpts;

pub const SaveStrategy = enum {
    disk,
    memory,
    both,
    none,
};

pub const RenderMode = enum {
    in_order,
    offline,
};

pub const RasterConfig = struct {
    render_mode: RenderMode = .in_order,
    total_threads: u16 = 0,
    max_frames_in_flight: u16 = 1,
    max_geom_threads_per_frame: u16 = 0,
    max_raster_threads_per_frame: u16 = 0,
    save_strategy: SaveStrategy = .disk,
    image_save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .none },
    },
    tile_size: u16 = 32,
    report: ReportMode = .bench,
    full_stats_opts: FullStatsOpts = .{},
};

const FrameReportStorage = union(ReportMode) {
    off: report.OffLog,
    bench: BenchLog,
    full_stats: report.FullStatsLog,
};

pub const FrameBenchCapture = struct {
    camera_idx: usize,
    frame_idx: usize,
    bench_log: BenchLog,
};

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
    meshes: []const MeshPrepared,
) f64 {
    var nodes_sum: usize = 0;
    for (meshes) |mesh| {
        nodes_sum += mesh.mesh_type.getNodesNum();
    }
    return @as(f64, @floatFromInt(nodes_sum)) /
        @as(f64, @floatFromInt(meshes.len));
}

fn countFrames(
    meshes: []const MeshInput,
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
    meshes: []const MeshInput,
) u8 {
    var num_fields: u8 = 0;
    for (meshes) |mesh| {
        const mesh_fields: u8 = switch (mesh.shader) {
            .nodal => |s| s.field.getFieldsN(),
            .tex => 1,
            .tex_rgb => 3,
        };
        num_fields = @max(num_fields, mesh_fields);
    }
    return num_fields;
}

fn initNodalGlobalScaling(
    outer_alloc: std.mem.Allocator,
    meshes: []const MeshInput,
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

fn prepareMeshStatics(
    allocator: std.mem.Allocator,
    meshes: []const MeshInput,
) ![]MeshStaticPrepared {
    const mesh_static_prepared = try allocator.alloc(MeshStaticPrepared, meshes.len);

    for (meshes, 0..) |mesh, ii| {
        mesh_static_prepared[ii] = try mr.prepareMeshStatic(allocator, &mesh);
    }

    return mesh_static_prepared;
}

fn initImagesArray(
    outer_alloc: std.mem.Allocator,
    config: RasterConfig,
    cameras: []const Camera,
    num_time: usize,
    num_fields: u8,
) !?NDArray(f64) {
    if (config.save_strategy == .memory or config.save_strategy == .both) {
        std.debug.assert(cameras.len > 0);
        const camera = &cameras[0];
        for (cameras[1..]) |camera_check| {
            std.debug.assert(std.meta.eql(camera_check.pixels_num, camera.pixels_num));
        }
        const dims = [_]usize{
            cameras.len,
            num_time,
            @as(usize, num_fields),
            camera.pixels_num[1],
            camera.pixels_num[0],
        };
        return try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    return null;
}

fn normalizePhaseThreadCap(
    phase_cap: u16,
) u16 {
    if (phase_cap == 0) {
        return 1;
    }
    return phase_cap;
}

fn calcPhaseThreadCap(
    total_threads: u16,
    phase_cap: u16,
) u16 {
    if (total_threads == 0) {
        return 1;
    }
    return @min(total_threads, normalizePhaseThreadCap(phase_cap));
}

fn calcFramesInFlight(
    render_mode: RenderMode,
    config: RasterConfig,
    cameras_num: usize,
) u16 {
    if (config.total_threads == 0) {
        return 1;
    }
    const requested_frames = if (render_mode == .in_order)
        @as(u16, 1)
    else
        @max(@as(u16, 1), config.max_frames_in_flight);
    return @min(requested_frames, @as(u16, @intCast(@max(@as(usize, 1), cameras_num))));
}

fn initFrameReportStorage(
    outer_alloc: std.mem.Allocator,
    camera: *const Camera,
    config: RasterConfig,
) !FrameReportStorage {
    return switch (config.report) {
        .off => .{ .off = .{} },
        .bench => .{ .bench = .{} },
        .full_stats => .{ .full_stats = try report.initFullStatsLog(
            outer_alloc,
            camera.pixels_num,
            config.tile_size,
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

fn finaliseFrame(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: *const FrameInput,
    ctx: *FrameContext,
) !void {
    const nodes_per_elem = calcNodesPerElem(ctx.prep_meshes);

    switch (input.config.report) {
        .off => {},
        .bench => {
            if (input.bench_capture) |capture| {
                const capture_idx = calcBenchCaptureIdx(
                    input.cameras_num,
                    input.camera_idx,
                    input.frame_idx,
                );
                capture[capture_idx] = .{
                    .camera_idx = input.camera_idx,
                    .frame_idx = input.frame_idx,
                    .bench_log = ctx.report_storage.bench,
                };
            }
        },
        .full_stats => try ctx.report_storage.full_stats.saveFrameReport(
            io,
            outer_alloc,
            input.out_dir,
            input.camera_idx,
            input.frame_idx,
            input.camera,
            input.config.tile_size,
            input.config.full_stats_opts,
            nodes_per_elem,
        ),
    }

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
    const arena_alloc = ctx.arena.allocator();

    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        input.camera.pixels_num[0],
        input.config.tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        input.camera.pixels_num[1],
        input.config.tile_size,
    );

    const time_start_overlap = Timestamp.now(io, .awake);

    const tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        input.config.tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(input.camera.pixels_num[0]),
        @intCast(input.camera.pixels_num[1]),
        ctx.elems_in_image_by_mesh,
        ctx.elem_bboxes_by_mesh,
    );

    const time_end_overlap = Timestamp.now(io, .awake);
    ctx.pipe_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds,
    );

    const time_start_loop = Timestamp.now(io, .awake);

    const ctx_rast = rops.RasterContext{
        .camera = input.camera,
        .frame_idx = input.frame_idx,
        .tile_size = input.config.tile_size,
    };

    try rasterengine.rasterScene(
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        input.raster_threads,
        tiling,
        ctx.prep_meshes,
        ctx.raster_hulls,
        &ctx.frame_arr,
    );

    const time_end_loop = Timestamp.now(io, .awake);
    ctx.pipe_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds,
    );

    const raster_end = Timestamp.now(io, .awake);
    ctx.pipe_times.total_time = @floatFromInt(
        time_start_overlap.durationTo(raster_end).raw.nanoseconds,
    );

    if (report.getBenchLog(report_mode, report_ptr)) |bench_log| {
        bench_log.pipe_times = ctx.pipe_times;
    }

    const nodes_per_elem = calcNodesPerElem(ctx.prep_meshes);

    switch (report_mode) {
        .off => {},
        .bench => {
            const bench_log = report.getBenchLog(report_mode, report_ptr).?;
            try report.standardReport(
                io,
                input.camera,
                ctx.pipe_times,
                ctx.total_elems_num,
                ctx.total_elems_in_image,
                nodes_per_elem,
                bench_log,
            );
        },
        .full_stats => try report_ptr.fullReport(
            io,
            input.frame_idx,
            input.camera,
            nodes_per_elem,
        ),
    }
}

fn runFrameRaster(
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

//------------------------------------------------------------------------------------------
// 4. Pipeline Stages

const FrameContext = struct {
    arena: std.heap.ArenaAllocator,

    frame_meshes: []FrameMeshPrepared = &.{},
    prep_meshes: []MeshPrepared = &.{},
    elem_bboxes_by_mesh: [][]ElemBBox = &.{},
    elems_in_image_by_mesh: []usize = &.{},
    raster_hulls: []?NDArray(f64) = &.{},
    total_elems_num: usize = 0,
    total_elems_in_image: usize = 0,

    frame_arr: NDArray(f64) = undefined,

    report_storage: FrameReportStorage = .{ .off = .{} },
    pipe_times: report.PipeTimes = .{},

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

    ctx.report_storage = try initFrameReportStorage(
        outer_alloc,
        input.camera,
        input.config,
    );

    const mesh_n = input.mesh_static_prepared.len;
    ctx.frame_meshes = try arena_alloc.alloc(FrameMeshPrepared, mesh_n);
    ctx.prep_meshes = try arena_alloc.alloc(MeshPrepared, mesh_n);
    ctx.elem_bboxes_by_mesh = try arena_alloc.alloc([]ElemBBox, mesh_n);
    ctx.elems_in_image_by_mesh = try arena_alloc.alloc(usize, mesh_n);
    ctx.raster_hulls = try arena_alloc.alloc(?NDArray(f64), mesh_n);

    if (input.images_arr) |images| {
        const start_idx = input.camera_idx * images.strides[0] +
            input.frame_idx * images.strides[1];
        const mem = images.slice[start_idx .. start_idx + images.strides[1]];
        ctx.frame_arr = try NDArray(f64).init(arena_alloc, mem, images.dims[2..]);
    } else {
        const dims = [_]usize{
            @as(usize, input.num_fields),
            input.camera.pixels_num[1],
            input.camera.pixels_num[0],
        };
        ctx.frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
    }
    @memset(ctx.frame_arr.slice, 0.0);
}



//------------------------------------------------------------------------------------------
// 3. Process: frame jobs for a given camera and frame
const FrameInput = struct {
    camera: *const Camera,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_threads: u16,
    raster_threads: u16,
    images_arr: ?*NDArray(f64),
    bench_capture: ?[]FrameBenchCapture,
    cameras_num: usize,
    err_state: *FrameJobErrorState,
};

fn processFrameJobInternal(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    input: FrameInput,
) !void {
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

    const geo_res = try mr.prepareFrameMeshes(
        arena_alloc,
        outer_alloc,
        io,
        input.camera,
        input.frame_idx,
        input.mesh_static_prepared,
        input.nodal_global_scaling,
        input.geom_threads,
        ctx.frame_meshes,
        ctx.prep_meshes,
        ctx.elem_bboxes_by_mesh,
        ctx.elems_in_image_by_mesh,
        ctx.raster_hulls,
    );
    ctx.total_elems_num = geo_res.total_elems_num;
    ctx.total_elems_in_image = geo_res.total_elems_in_image;

    const time_end_geo = Timestamp.now(io, .awake);
    ctx.pipe_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );

    // Stage 3: Render the frame by rasterisation
    try runFrameRaster(
        outer_alloc,
        io,
        &input,
        &ctx,
    );

    // Stage 4: Finalise frame
    try finaliseFrame(outer_alloc, io, &input, &ctx);
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
fn dispatchSerialFrameJobs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*NDArray(f64),
    bench_capture: ?[]FrameBenchCapture,
) !void {
    const geom_threads: u16 = 1;
    const raster_threads: u16 = 1;

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
                    .mesh_static_prepared = mesh_static_prepared,
                    .nodal_global_scaling = nodal_global_scaling,
                    .geom_threads = geom_threads,
                    .raster_threads = raster_threads,
                    .images_arr = images_arr,
                    .bench_capture = bench_capture,
                    .cameras_num = cameras.len,
                    .err_state = undefined,
                },
            );
        }
    }
}

fn dispatchOfflineFrameJobs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*NDArray(f64),
    bench_capture: ?[]FrameBenchCapture,
) !void {
    const jobs_num = cameras.len * num_time;
    const frames_in_flight = calcFramesInFlight(.offline, config, cameras.len);

    const geom_threads = calcPhaseThreadCap(
        config.total_threads,
        config.max_geom_threads_per_frame,
    );
    const raster_threads = calcPhaseThreadCap(
        config.total_threads,
        config.max_raster_threads_per_frame,
    );

    const batch_size = @min(@as(usize, frames_in_flight), jobs_num);
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
                        .mesh_static_prepared = mesh_static_prepared,
                        .nodal_global_scaling = nodal_global_scaling,
                        .geom_threads = geom_threads,
                        .raster_threads = raster_threads,
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

fn dispatchInOrderFrameJobs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    images_arr: ?*NDArray(f64),
    bench_capture: ?[]FrameBenchCapture,
) !void {
    const geom_threads = calcPhaseThreadCap(
        config.total_threads,
        config.max_geom_threads_per_frame,
    );
    const raster_threads = calcPhaseThreadCap(
        config.total_threads,
        config.max_raster_threads_per_frame,
    );

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
                        .mesh_static_prepared = mesh_static_prepared,
                        .nodal_global_scaling = nodal_global_scaling,
                        .geom_threads = geom_threads,
                        .raster_threads = raster_threads,
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

//==========================================================================================
// 1. Main entry point function to the rasteriser
pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    meshes: []const MeshInput,
    config: RasterConfig,
    out_dir_path: ?[]const u8,
    bench_capture: ?[]FrameBenchCapture,
) !?NDArray(f64) {
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

    const num_time = countFrames(meshes);
    const num_fields = countOutputFields(meshes);

    std.debug.assert(cameras.len > 0);
    std.debug.assert(meshes.len > 0);
    std.debug.assert(num_time > 0);
    std.debug.assert(num_fields > 0);
    if (bench_capture) |capture| {
        std.debug.assert(capture.len == cameras.len * num_time);
    }

    const nodal_global_scaling = try initNodalGlobalScaling(outer_alloc, meshes);
    defer outer_alloc.free(nodal_global_scaling);
    const mesh_static_prepared = try prepareMeshStatics(static_alloc, meshes);

    var images_arr_opt: ?NDArray(f64) = try initImagesArray(
        outer_alloc,
        config,
        cameras,
        num_time,
        num_fields,
    );

    if (config.total_threads == 0) {
        try dispatchSerialFrameJobs(
            outer_alloc,
            io,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static_prepared,
            nodal_global_scaling,
            if (images_arr_opt) |*ima| ima else null,
            bench_capture,
        );

        return images_arr_opt;
    }

    if (config.render_mode == .in_order) {
        try dispatchInOrderFrameJobs(
            outer_alloc,
            io,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            mesh_static_prepared,
            nodal_global_scaling,
            if (images_arr_opt) |*ima| ima else null,
            bench_capture,
        );

        return images_arr_opt;
    }

    try dispatchOfflineFrameJobs(
        outer_alloc,
        io,
        cameras,
        config,
        out_dir,
        num_time,
        num_fields,
        mesh_static_prepared,
        nodal_global_scaling,
        if (images_arr_opt) |*ima| ima else null,
        bench_capture,
    );

    return images_arr_opt;
}
