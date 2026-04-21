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

pub const SaveOption = enum {
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
    save_opt: SaveOption = .disk,
    save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
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

const FramePipelineContext = struct {
    arena: std.heap.ArenaAllocator,
    camera_idx: usize = 0,
    frame_idx: usize = 0,
    frame_meshes: []FrameMeshPrepared = &.{},
    prep_meshes: []MeshPrepared = &.{},
    elem_bboxes_by_mesh: [][]ElemBBox = &.{},
    elems_in_image_by_mesh: []usize = &.{},
    raster_hulls: []?NDArray(f64) = &.{},
    total_elems_num: usize = 0,
    total_elems_in_image: usize = 0,
    frame_arr: NDArray(f64) = undefined,
    pipe_times: report.PipeTimes = .{},
    report_storage: FrameReportStorage = .{ .off = .{} },
    io: std.Io = undefined,
    camera: *const Camera = undefined,
    out_dir: ?std.Io.Dir = null,
    outer_alloc: std.mem.Allocator = undefined,
    tile_size: u16 = 0,
    report_mode: ReportMode = .off,
    save_opt: SaveOption = .none,
    save_opts: []const iio.ImageSaveOpts = &.{},
    full_stats_opts: FullStatsOpts = .{},

    fn deinit(
        self: *FramePipelineContext,
        outer_alloc: std.mem.Allocator,
    ) void {
        if (self.report_mode == .full_stats) {
            self.report_storage.full_stats.deinit(outer_alloc);
        }
        self.arena.deinit();
    }
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
    slot: *FramePipelineContext,
) FrameReportPtr(report_mode) {
    return switch (report_mode) {
        .off => &slot.report_storage.off,
        .bench => &slot.report_storage.bench,
        .full_stats => &slot.report_storage.full_stats,
    };
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
    if (config.save_opt == .memory or config.save_opt == .both) {
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

fn initFrameContext(
    outer_alloc: std.mem.Allocator,
) FramePipelineContext {
    return .{
        .arena = std.heap.ArenaAllocator.init(outer_alloc),
    };
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

fn admitFrameSlot(
    slot: *FramePipelineContext,
    camera: *const Camera,
    camera_idx: usize,
    config: RasterConfig,
    frame_idx: usize,
    num_fields: u8,
    images_arr: ?*NDArray(f64),
    out_dir: ?std.Io.Dir,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
) !void {
    const arena_alloc = slot.arena.allocator();
    slot.camera_idx = camera_idx;
    slot.frame_idx = frame_idx;
    slot.io = io;
    slot.camera = camera;
    slot.out_dir = out_dir;
    slot.outer_alloc = outer_alloc;
    slot.tile_size = config.tile_size;
    slot.report_mode = config.report;
    slot.save_opt = config.save_opt;
    slot.save_opts = config.save_opts;
    slot.full_stats_opts = config.full_stats_opts;
    slot.report_storage = try initFrameReportStorage(
        slot.outer_alloc,
        camera,
        config,
    );

    if (images_arr) |images| {
        const start_idx = camera_idx * images.strides[0] + frame_idx * images.strides[1];
        const mem = images.slice[start_idx .. start_idx + images.strides[1]];
        slot.frame_arr = try NDArray(f64).init(arena_alloc, mem, images.dims[2..]);
    } else {
        const dims = [_]usize{
            @as(usize, num_fields),
            camera.pixels_num[1],
            camera.pixels_num[0],
        };
        slot.frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
    }
    @memset(slot.frame_arr.slice, 0.0);
}

fn prepareFrameGeometry(
    slot: *FramePipelineContext,
    camera: *const Camera,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_pool: ?*geomthread.GeometryWorkerPool,
) !void {
    const arena_alloc = slot.arena.allocator();
    const time_start_geo = Timestamp.now(slot.io, .awake);

    slot.frame_meshes = try arena_alloc.alloc(FrameMeshPrepared, mesh_static_prepared.len);
    slot.prep_meshes = try arena_alloc.alloc(MeshPrepared, mesh_static_prepared.len);
    slot.elem_bboxes_by_mesh = try arena_alloc.alloc([]ElemBBox, mesh_static_prepared.len);
    slot.elems_in_image_by_mesh = try arena_alloc.alloc(usize, mesh_static_prepared.len);
    slot.raster_hulls = try arena_alloc.alloc(?NDArray(f64), mesh_static_prepared.len);
    slot.total_elems_in_image = 0;
    slot.total_elems_num = 0;

    for (mesh_static_prepared, 0..) |*mesh_static, ii| {
        var nodal_frame_scaling: ?imageops.ScalingParams = null;
        switch (mesh_static.shader) {
            .nodal => |s| {
                if (s.scale_over == .over_frames) {
                    nodal_frame_scaling = nodal_global_scaling[ii];
                } else {
                    nodal_frame_scaling = imageops.getScalingParamsNDArray(
                        &s.field.array,
                        slot.frame_idx,
                        s.scaling,
                    );
                }
            },
            else => {},
        }

        slot.frame_meshes[ii] = try mr.prepareVisibleFrameMesh(
            arena_alloc,
            camera,
            mesh_static,
            slot.frame_idx,
            nodal_frame_scaling,
            geom_pool,
        );
        slot.prep_meshes[ii] = slot.frame_meshes[ii].mesh;
        slot.elem_bboxes_by_mesh[ii] = slot.frame_meshes[ii].elem_bboxes;
        slot.elems_in_image_by_mesh[ii] = slot.frame_meshes[ii].elems_in_image;
        slot.raster_hulls[ii] = slot.frame_meshes[ii].raster_hull;
        slot.total_elems_num += slot.frame_meshes[ii].total_elems_num;
        slot.total_elems_in_image += slot.frame_meshes[ii].elems_in_image;
    }

    const time_end_geo = Timestamp.now(slot.io, .awake);
    slot.pipe_times = .{};
    slot.pipe_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );
}

fn prepareFrameGeometryLinear(
    slot: *FramePipelineContext,
    camera: *const Camera,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_threads: u16,
) !void {
    if (geom_threads <= 1) {
        try prepareFrameGeometry(
            slot,
            camera,
            mesh_static_prepared,
            nodal_global_scaling,
            null,
        );
        return;
    }

    var geom_pool: geomthread.GeometryWorkerPool = undefined;
    try geom_pool.init(slot.outer_alloc, slot.io, geom_threads);
    defer geom_pool.deinit(slot.outer_alloc);

    try prepareFrameGeometry(
        slot,
        camera,
        mesh_static_prepared,
        nodal_global_scaling,
        &geom_pool,
    );
}

fn runFrameRasterMode(
    comptime report_mode: ReportMode,
    slot: *FramePipelineContext,
    raster_threads: u16,
) !void {
    try rasterPreparedVisibleInternal(
        slot.arena.allocator(),
        slot.io,
        slot.camera,
        slot.frame_idx,
        slot.prep_meshes,
        slot.elem_bboxes_by_mesh,
        slot.elems_in_image_by_mesh,
        slot.raster_hulls,
        slot.total_elems_num,
        slot.total_elems_in_image,
        &slot.frame_arr,
        slot.tile_size,
        raster_threads,
        report_mode,
        getFrameReportPtr(report_mode, slot),
        slot.outer_alloc,
        Timestamp.now(slot.io, .awake),
        slot.pipe_times,
    );
}

fn runFrameRaster(
    slot: *FramePipelineContext,
    raster_threads: u16,
) !void {
    switch (slot.report_mode) {
        .off => try runFrameRasterMode(.off, slot, raster_threads),
        .bench => try runFrameRasterMode(.bench, slot, raster_threads),
        .full_stats => try runFrameRasterMode(.full_stats, slot, raster_threads),
    }
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

fn finalizeFrameSlot(
    slot: *FramePipelineContext,
) !void {
    const nodes_per_elem = calcNodesPerElem(slot.prep_meshes);

    switch (slot.report_mode) {
        .off => {},
        .bench => {},
        .full_stats => try slot.report_storage.full_stats.saveFrameReport(
            slot.io,
            slot.outer_alloc,
            slot.out_dir,
            slot.camera_idx,
            slot.frame_idx,
            slot.camera,
            slot.tile_size,
            slot.full_stats_opts,
            nodes_per_elem,
        ),
    }

    if (slot.save_opt == .disk or slot.save_opt == .both) {
        std.debug.assert(slot.frame_arr.dims[0] <= std.math.maxInt(u8));
        try iio.saveImages(
            slot.io,
            slot.out_dir,
            slot.camera_idx,
            slot.frame_idx,
            @intCast(slot.frame_arr.dims[0]),
            slot.camera.pixels_num,
            &slot.frame_arr,
            slot.save_opts,
        );
    }
}

const FrameJobParams = struct {
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    images_arr: ?*NDArray(f64),
    out_dir: ?std.Io.Dir,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_threads: u16,
    raster_threads: u16,
    err_state: *FrameJobErrorState,
};

fn processFrameJob(
    job: FrameJobParams,
) std.Io.Cancelable!void {
    var slot = initFrameContext(job.outer_alloc);
    defer slot.deinit(job.outer_alloc);

    admitFrameSlot(
        &slot,
        job.camera,
        job.camera_idx,
        job.config,
        job.frame_idx,
        job.num_fields,
        job.images_arr,
        job.out_dir,
        job.outer_alloc,
        job.io,
    ) catch |err| switch (err) {
        else => {
            job.err_state.setFirst(err);
            return;
        },
    };
    prepareFrameGeometryLinear(
        &slot,
        job.camera,
        job.mesh_static_prepared,
        job.nodal_global_scaling,
        job.geom_threads,
    ) catch |err| switch (err) {
        else => {
            job.err_state.setFirst(err);
            return;
        },
    };
    runFrameRaster(&slot, job.raster_threads) catch |err| switch (err) {
        else => {
            job.err_state.setFirst(err);
            return;
        },
    };
    finalizeFrameSlot(&slot) catch |err| switch (err) {
        else => {
            job.err_state.setFirst(err);
            return;
        },
    };
}

fn runFrameJobLinear(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    camera_idx: usize,
    frame_idx: usize,
    num_fields: u8,
    config: RasterConfig,
    images_arr: ?*NDArray(f64),
    out_dir: ?std.Io.Dir,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    geom_threads: u16,
    raster_threads: u16,
) !void {
    var slot = initFrameContext(outer_alloc);
    defer slot.deinit(outer_alloc);

    try admitFrameSlot(
        &slot,
        camera,
        camera_idx,
        config,
        frame_idx,
        num_fields,
        images_arr,
        out_dir,
        outer_alloc,
        io,
    );
    try prepareFrameGeometryLinear(
        &slot,
        camera,
        mesh_static_prepared,
        nodal_global_scaling,
        geom_threads,
    );
    try runFrameRaster(&slot, raster_threads);
    try finalizeFrameSlot(&slot);
}

fn dispatchSerialFrameJobs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    images_arr: ?*NDArray(f64),
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
) !?NDArray(f64) {
    const geom_threads: u16 = 1;
    const raster_threads: u16 = 1;

    for (0..num_time) |frame_idx| {
        for (cameras, 0..) |*camera, camera_idx| {
            try runFrameJobLinear(
                outer_alloc,
                io,
                camera,
                camera_idx,
                frame_idx,
                num_fields,
                config,
                images_arr,
                out_dir,
                mesh_static_prepared,
                nodal_global_scaling,
                geom_threads,
                raster_threads,
            );
        }
    }

    return if (images_arr) |ima| ima.* else null;
}

fn dispatchOfflineFrameJobs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
    num_time: usize,
    num_fields: u8,
    images_arr: ?*NDArray(f64),
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
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
                processFrameJob,
                .{FrameJobParams{
                    .outer_alloc = outer_alloc,
                    .io = io,
                    .camera = camera,
                    .camera_idx = camera_idx,
                    .frame_idx = frame_idx,
                    .num_fields = num_fields,
                    .config = config,
                    .images_arr = images_arr,
                    .out_dir = out_dir,
                    .mesh_static_prepared = mesh_static_prepared,
                    .nodal_global_scaling = nodal_global_scaling,
                    .geom_threads = geom_threads,
                    .raster_threads = raster_threads,
                    .err_state = &err_state,
                }},
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
    images_arr: ?*NDArray(f64),
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
) !?NDArray(f64) {
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
                processFrameJob,
                .{FrameJobParams{
                    .outer_alloc = outer_alloc,
                    .io = io,
                    .camera = camera,
                    .camera_idx = camera_idx,
                    .frame_idx = frame_idx,
                    .num_fields = num_fields,
                    .config = config,
                    .images_arr = images_arr,
                    .out_dir = out_dir,
                    .mesh_static_prepared = mesh_static_prepared,
                    .nodal_global_scaling = nodal_global_scaling,
                    .geom_threads = geom_threads,
                    .raster_threads = raster_threads,
                    .err_state = &err_state,
                }},
            );
        }

        try group.await(io);
        if (err_state.first_err) |err| {
            return err;
        }
    }

    return if (images_arr) |ima| ima.* else null;
}

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    cameras: []const Camera,
    meshes: []const MeshInput,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {
    var static_arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer static_arena.deinit();
    const static_alloc = static_arena.allocator();
    std.debug.assert(cameras.len > 0);
    const num_time = countFrames(meshes);
    const num_fields = countOutputFields(meshes);
    var images_arr_opt = try initImagesArray(
        outer_alloc,
        config,
        cameras,
        num_time,
        num_fields,
    );
    const nodal_global_scaling = try initNodalGlobalScaling(outer_alloc, meshes);
    defer outer_alloc.free(nodal_global_scaling);
    const mesh_static_prepared = try prepareMeshStatics(static_alloc, meshes);

    if (config.total_threads == 0) {
        return dispatchSerialFrameJobs(
            outer_alloc,
            io,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            if (images_arr_opt) |*ima| ima else null,
            mesh_static_prepared,
            nodal_global_scaling,
        );
    }

    if (config.render_mode == .in_order) {
        return dispatchInOrderFrameJobs(
            outer_alloc,
            io,
            cameras,
            config,
            out_dir,
            num_time,
            num_fields,
            if (images_arr_opt) |*ima| ima else null,
            mesh_static_prepared,
            nodal_global_scaling,
        );
    }

    try dispatchOfflineFrameJobs(
        outer_alloc,
        io,
        cameras,
        config,
        out_dir,
        num_time,
        num_fields,
        if (images_arr_opt) |*ima| ima else null,
        mesh_static_prepared,
        nodal_global_scaling,
    );

    return images_arr_opt;
}

pub fn rasterSceneInternal(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_idx: usize,
    meshes: []MeshPrepared,
    image_out_arr: *NDArray(f64),
    tile_size: u16,
    threads_within_image: u16,
    comptime report_mode: ReportMode,
    report_log: *report.LogType(report_mode),
) !void {
    const raster_start = Timestamp.now(io, .awake);
    const ctx_report = report.ReportContext(report_mode){ .log = report_log };
    var pipe_times = report.PipeTimes{};

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const time_start_geo = Timestamp.now(io, .awake);

    const elem_bboxes_by_mesh = try arena_alloc.alloc([]ElemBBox, meshes.len);
    const elems_in_image_by_mesh = try arena_alloc.alloc(usize, meshes.len);
    var total_elems_in_image: usize = 0;
    var total_elems_num: usize = 0;
    const raster_hulls = try arena_alloc.alloc(?NDArray(f64), meshes.len);

    try rops.prepareSceneGeometry(
        report_mode,
        ctx_report,
        arena_alloc,
        camera,
        meshes,
        raster_hulls,
        elem_bboxes_by_mesh,
        elems_in_image_by_mesh,
        &total_elems_num,
        &total_elems_in_image,
    );

    const time_end_geo = Timestamp.now(io, .awake);
    pipe_times.geometry_prep = @floatFromInt(
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
    );

    try rasterPreparedVisibleInternal(
        arena_alloc,
        io,
        camera,
        frame_idx,
        meshes,
        elem_bboxes_by_mesh,
        elems_in_image_by_mesh,
        raster_hulls,
        total_elems_num,
        total_elems_in_image,
        image_out_arr,
        tile_size,
        threads_within_image,
        report_mode,
        report_log,
        outer_alloc,
        raster_start,
        pipe_times,
    );
}

fn rasterPreparedVisibleInternal(
    arena_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_idx: usize,
    meshes: []MeshPrepared,
    elem_bboxes_by_mesh: [][]ElemBBox,
    elems_in_image_by_mesh: []usize,
    raster_hulls: []?NDArray(f64),
    total_elems_num: usize,
    total_elems_in_image: usize,
    image_out_arr: *NDArray(f64),
    tile_size: u16,
    threads_within_image: u16,
    comptime report_mode: ReportMode,
    report_log: *report.LogType(report_mode),
    outer_alloc: std.mem.Allocator,
    raster_start: Timestamp,
    pipe_times_in: report.PipeTimes,
) !void {
    const ctx_report = report.ReportContext(report_mode){ .log = report_log };
    var pipe_times = pipe_times_in;
    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        camera.pixels_num[0],
        tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        camera.pixels_num[1],
        tile_size,
    );

    const time_start_overlap = Timestamp.now(io, .awake);

    const tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(camera.pixels_num[0]),
        @intCast(camera.pixels_num[1]),
        elems_in_image_by_mesh,
        elem_bboxes_by_mesh,
    );

    const time_end_overlap = Timestamp.now(io, .awake);
    pipe_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds,
    );

    const time_start_loop = Timestamp.now(io, .awake);

    const ctx_rast = rops.RasterContext{
        .camera = camera,
        .frame_idx = frame_idx,
        .tile_size = tile_size,
    };

    try rasterengine.rasterScene(
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        threads_within_image,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );

    const time_end_loop = Timestamp.now(io, .awake);
    pipe_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds,
    );

    const raster_end = Timestamp.now(io, .awake);
    pipe_times.total_time = @floatFromInt(
        raster_start.durationTo(raster_end).raw.nanoseconds,
    );

    if (report.getBenchLog(report_mode, report_log)) |bench_log| {
        bench_log.pipe_times = pipe_times;
    }

    var nodes_sum: usize = 0;
    for (meshes) |mesh| {
        nodes_sum += mesh.mesh_type.getNodesNum();
    }
    const nodes_per_elem: f64 = @as(f64, @floatFromInt(nodes_sum)) /
        @as(f64, @floatFromInt(meshes.len));

    switch (report_mode) {
        .off => {},
        .bench => {
            const bench_log = report.getBenchLog(report_mode, report_log).?;
            try report.standardReport(
                io,
                camera,
                pipe_times,
                total_elems_num,
                total_elems_in_image,
                nodes_per_elem,
                bench_log,
            );
        },
        .full_stats => try report_log.fullReport(
            io,
            frame_idx,
            camera,
            nodes_per_elem,
        ),
    }
}
