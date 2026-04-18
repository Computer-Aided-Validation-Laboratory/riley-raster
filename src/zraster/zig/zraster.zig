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

pub const RasterConfig = struct {
    threads_geom_preproc: u16 = 0,
    threads_within_image: u16 = 0,
    threads_over_images: u16 = 1,
    save_opt: SaveOption = .disk,
    save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .none },
    },
    tile_size: u16 = 32,
    report: ReportMode = .bench,
    full_stats_opts: FullStatsOpts = .{},
};

const FramePipelineState = enum {
    free,
    queued,
    in_geometry,
    geom_ready,
    in_raster,
    raster_ready,
    done,
    failed,
};

const FrameReportStorage = union(ReportMode) {
    off: report.OffLog,
    bench: BenchLog,
    full_stats: report.FullStatsLog,
};

const FramePipelineContext = struct {
    arena: std.heap.ArenaAllocator,
    state: FramePipelineState = .free,
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
    geom_thread: ?std.Thread = null,
    geom_done: std.atomic.Value(bool) = .init(false),
    geom_failed: bool = false,
    geom_error: ?anyerror = null,
    geom_pool_storage: geomthread.GeometryWorkerPool = undefined,
    geom_pool_active: bool = false,
    raster_thread: ?std.Thread = null,
    raster_done: std.atomic.Value(bool) = .init(false),
    raster_failed: bool = false,
    raster_error: ?anyerror = null,
    io: std.Io = undefined,
    camera: *const Camera = undefined,
    out_dir: ?std.Io.Dir = null,
    outer_alloc: std.mem.Allocator = undefined,
    tile_size: u16 = 0,
    slot_geom_threads: u16 = 0,
    slot_raster_threads: u16 = 0,
    report_mode: ReportMode = .off,
    save_opt: SaveOption = .none,
    save_opts: []const iio.ImageSaveOpts = &.{},
    full_stats_opts: FullStatsOpts = .{},

    fn reset(
        self: *FramePipelineContext,
        outer_alloc: std.mem.Allocator,
    ) void {
        if (self.geom_thread) |thread| {
            thread.join();
        }
        if (self.raster_thread) |thread| {
            thread.join();
        }
        if (self.geom_pool_active) {
            self.geom_pool_storage.deinit(outer_alloc);
        }
        if (self.report_mode == .full_stats) {
            self.report_storage.full_stats.deinit(outer_alloc);
        }
        if (self.state != .free) {
            _ = self.arena.reset(.free_all);
        }
        self.state = .free;
        self.frame_idx = 0;
        self.frame_meshes = &.{};
        self.prep_meshes = &.{};
        self.elem_bboxes_by_mesh = &.{};
        self.elems_in_image_by_mesh = &.{};
        self.raster_hulls = &.{};
        self.total_elems_num = 0;
        self.total_elems_in_image = 0;
        self.pipe_times = .{};
        self.report_storage = .{ .off = .{} };
        self.geom_thread = null;
        self.geom_done.store(false, .monotonic);
        self.geom_failed = false;
        self.geom_error = null;
        self.geom_pool_active = false;
        self.raster_thread = null;
        self.raster_done.store(false, .monotonic);
        self.raster_failed = false;
        self.raster_error = null;
        self.io = undefined;
        self.camera = undefined;
        self.out_dir = null;
        self.outer_alloc = undefined;
        self.tile_size = 0;
        self.slot_geom_threads = 0;
        self.slot_raster_threads = 0;
        self.report_mode = .off;
        self.save_opt = .none;
        self.save_opts = &.{};
        self.full_stats_opts = .{};
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
    num_time: usize,
    num_fields: u8,
    camera: *const Camera,
) !?NDArray(f64) {
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time,
            @as(usize, num_fields),
            camera.pixels_num[1],
            camera.pixels_num[0],
        };
        return try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    return null;
}

fn initFrameSlots(
    outer_alloc: std.mem.Allocator,
    slots_num: usize,
) ![]FramePipelineContext {
    const slots = try outer_alloc.alloc(FramePipelineContext, slots_num);
    errdefer outer_alloc.free(slots);

    for (slots) |*slot| {
        slot.* = .{
            .arena = std.heap.ArenaAllocator.init(outer_alloc),
        };
    }

    return slots;
}

fn deinitFrameSlots(
    outer_alloc: std.mem.Allocator,
    slots: []FramePipelineContext,
) void {
    for (slots) |*slot| {
        if (slot.raster_thread) |thread| {
            thread.join();
        }
        slot.reset(outer_alloc);
        slot.arena.deinit();
    }
    outer_alloc.free(slots);
}

fn findFreeFrameSlot(
    slots: []FramePipelineContext,
) ?*FramePipelineContext {
    for (slots) |*slot| {
        if (slot.state == .free) {
            return slot;
        }
    }
    return null;
}

fn findGeomReadyFrameSlot(
    slots: []FramePipelineContext,
) ?*FramePipelineContext {
    var selected_slot: ?*FramePipelineContext = null;
    for (slots) |*slot| {
        if (slot.state != .geom_ready) {
            continue;
        }
        if (selected_slot == null or slot.frame_idx < selected_slot.?.frame_idx) {
            selected_slot = slot;
        }
    }
    return selected_slot;
}

fn findInGeometryFrameSlot(
    slots: []FramePipelineContext,
) ?*FramePipelineContext {
    var selected_slot: ?*FramePipelineContext = null;
    for (slots) |*slot| {
        if (slot.state != .in_geometry) {
            continue;
        }
        if (selected_slot == null or slot.frame_idx < selected_slot.?.frame_idx) {
            selected_slot = slot;
        }
    }
    return selected_slot;
}

fn countActiveFrameSlots(
    slots: []FramePipelineContext,
) usize {
    var active_slots: usize = 0;
    for (slots) |slot| {
        if (slot.state != .free) {
            active_slots += 1;
        }
    }
    return active_slots;
}

fn countSlotsInState(
    slots: []const FramePipelineContext,
    target_state: FramePipelineState,
) usize {
    var slots_num: usize = 0;
    for (slots) |slot| {
        if (slot.state == target_state) {
            slots_num += 1;
        }
    }
    return slots_num;
}

fn calcPerSlotThreads(
    total_threads: u16,
    active_slots: usize,
) u16 {
    if (active_slots == 0) {
        return total_threads;
    }
    if (total_threads == 0) {
        return 0;
    }
    const total_threads_num: usize = @intCast(total_threads);
    const slot_threads = @max(
        @as(usize, 1),
        total_threads_num / active_slots,
    );
    return @intCast(slot_threads);
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
    outer_alloc: std.mem.Allocator,
    camera: *const Camera,
    config: RasterConfig,
    slot_geom_threads: u16,
    slot_raster_threads: u16,
    frame_idx: usize,
    num_fields: u8,
    images_arr: ?*NDArray(f64),
    out_dir: ?std.Io.Dir,
    io: std.Io,
) !void {
    slot.reset(outer_alloc);

    const arena_alloc = slot.arena.allocator();
    slot.state = .queued;
    slot.frame_idx = frame_idx;
    slot.io = io;
    slot.camera = camera;
    slot.out_dir = out_dir;
    slot.outer_alloc = outer_alloc;
    slot.tile_size = config.tile_size;
    slot.slot_geom_threads = slot_geom_threads;
    slot.slot_raster_threads = slot_raster_threads;
    slot.report_mode = config.report;
    slot.save_opt = config.save_opt;
    slot.save_opts = config.save_opts;
    slot.full_stats_opts = config.full_stats_opts;
    slot.report_storage = try initFrameReportStorage(outer_alloc, camera, config);
    slot.geom_done.store(false, .monotonic);
    slot.geom_failed = false;
    slot.geom_error = null;
    slot.raster_done.store(false, .monotonic);
    slot.raster_failed = false;
    slot.raster_error = null;

    if (slot.slot_geom_threads > 1) {
        try slot.geom_pool_storage.init(
            outer_alloc,
            io,
            slot.slot_geom_threads - 1,
        );
        slot.geom_pool_active = true;
    }

    if (images_arr) |images| {
        const stride = images.strides[0];
        const mem = images.slice[frame_idx * stride .. (frame_idx + 1) * stride];
        slot.frame_arr = try NDArray(f64).init(arena_alloc, mem, images.dims[1..]);
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
) !void {
    const arena_alloc = slot.arena.allocator();
    const time_start_geo = Timestamp.now(slot.io, .awake);
    const geom_pool = if (slot.geom_pool_active)
        &slot.geom_pool_storage
    else
        null;

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

fn runFrameRasterMode(
    comptime report_mode: ReportMode,
    slot: *FramePipelineContext,
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
        slot.slot_raster_threads,
        report_mode,
        getFrameReportPtr(report_mode, slot),
        slot.outer_alloc,
        Timestamp.now(slot.io, .awake),
        slot.pipe_times,
    );
}

fn runFrameRaster(
    slot: *FramePipelineContext,
) !void {
    switch (slot.report_mode) {
        .off => try runFrameRasterMode(.off, slot),
        .bench => try runFrameRasterMode(.bench, slot),
        .full_stats => try runFrameRasterMode(.full_stats, slot),
    }
}

fn frameGeometryWorker(
    slot: *FramePipelineContext,
    camera: *const Camera,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
) void {
    prepareFrameGeometry(
        slot,
        camera,
        mesh_static_prepared,
        nodal_global_scaling,
    ) catch |err| {
        slot.geom_failed = true;
        slot.geom_error = err;
        slot.geom_done.store(true, .release);
        return;
    };

    slot.geom_done.store(true, .release);
}

fn spawnFrameGeometry(
    slot: *FramePipelineContext,
    camera: *const Camera,
    mesh_static_prepared: []const MeshStaticPrepared,
    nodal_global_scaling: []const ?imageops.ScalingParams,
) !void {
    slot.state = .in_geometry;
    slot.geom_done.store(false, .monotonic);
    slot.geom_failed = false;
    slot.geom_error = null;
    slot.geom_thread = try std.Thread.spawn(
        .{},
        frameGeometryWorker,
        .{
            slot,
            camera,
            mesh_static_prepared,
            nodal_global_scaling,
        },
    );
}

fn finishFrameGeometry(
    slot: *FramePipelineContext,
) !void {
    const thread = slot.geom_thread orelse return;
    thread.join();
    slot.geom_thread = null;

    if (slot.geom_pool_active) {
        slot.geom_pool_storage.deinit(slot.outer_alloc);
        slot.geom_pool_active = false;
    }

    if (slot.geom_failed) {
        slot.state = .failed;
        return slot.geom_error orelse error.GeometryFailed;
    }

    slot.state = .geom_ready;
}

fn frameRasterWorker(
    slot: *FramePipelineContext,
) void {
    runFrameRaster(slot) catch |err| {
        slot.raster_failed = true;
        slot.raster_error = err;
        slot.raster_done.store(true, .release);
        return;
    };

    slot.raster_done.store(true, .release);
}

fn spawnFrameRaster(
    slot: *FramePipelineContext,
) !void {
    slot.state = .in_raster;
    slot.raster_done.store(false, .monotonic);
    slot.raster_failed = false;
    slot.raster_error = null;
    slot.raster_thread = try std.Thread.spawn(.{}, frameRasterWorker, .{slot});
}

fn finishFrameRaster(
    slot: *FramePipelineContext,
) !void {
    const thread = slot.raster_thread orelse return;
    thread.join();
    slot.raster_thread = null;

    if (slot.raster_failed) {
        slot.state = .failed;
        return slot.raster_error orelse error.RasterFailed;
    }

    slot.state = .raster_ready;
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
            slot.frame_idx,
            @intCast(slot.frame_arr.dims[0]),
            slot.camera.pixels_num,
            &slot.frame_arr,
            slot.save_opts,
        );
    }

    slot.state = .done;
}

fn applyDispToMesh(
    outer_alloc: std.mem.Allocator,
    tt: usize,
    coords: *const MatSlice(f64),
    disp: *const NDArray(f64),
) !MatSlice(f64) {
    var coords_disp = try MatSlice(f64).initAlloc(
        outer_alloc,
        coords.rows_num,
        coords.cols_num,
    );
    @memcpy(coords_disp.slice, coords.slice);

    const disp_frame_mem = disp.getSlice(&[_]usize{ tt, 0, 0 }, 0);
    var disp_frame = MatSlice(f64).init(disp_frame_mem, disp.dims[1], disp.dims[2]);

    coords_disp.addInPlace(&disp_frame);

    return coords_disp;
}

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    meshes: []const MeshInput,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {
    var static_arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer static_arena.deinit();
    const static_alloc = static_arena.allocator();
    const num_time = countFrames(meshes);
    const num_fields = countOutputFields(meshes);
    var images_arr = try initImagesArray(
        outer_alloc,
        config,
        num_time,
        num_fields,
        camera,
    );
    const nodal_global_scaling = try initNodalGlobalScaling(outer_alloc, meshes);
    defer outer_alloc.free(nodal_global_scaling);
    const mesh_static_prepared = try prepareMeshStatics(static_alloc, meshes);

    const frames_in_flight = @max(@as(u16, 1), config.threads_over_images);
    const slots_num = @min(@as(usize, @intCast(frames_in_flight)), num_time);
    const frame_slots = try initFrameSlots(outer_alloc, slots_num);
    defer deinitFrameSlots(outer_alloc, frame_slots);

    var next_frame_idx: usize = 0;
    var completed_frames: usize = 0;
    var raster_slot: ?*FramePipelineContext = null;

    while (completed_frames < num_time) {
        var progressed = false;

        for (frame_slots) |*slot| {
            if (slot.state != .in_geometry) {
                continue;
            }
            if (!slot.geom_done.load(.acquire)) {
                continue;
            }
            try finishFrameGeometry(slot);
            progressed = true;
        }

        if (raster_slot) |slot| {
            if (slot.raster_done.load(.acquire)) {
                try finishFrameRaster(slot);
                try finalizeFrameSlot(slot);
                slot.reset(outer_alloc);
                completed_frames += 1;
                raster_slot = null;
                progressed = true;
            }
        }

        if (raster_slot == null) {
            if (findGeomReadyFrameSlot(frame_slots)) |slot| {
                try spawnFrameRaster(slot);
                raster_slot = slot;
                progressed = true;
            }
        }

        if (next_frame_idx < num_time and countActiveFrameSlots(frame_slots) < slots_num) {
            const slot = findFreeFrameSlot(frame_slots).?;
            const slot_geom_threads = calcPerSlotThreads(
                config.threads_geom_preproc,
                countSlotsInState(frame_slots, .in_geometry) + 1,
            );
            const slot_raster_threads = calcPerSlotThreads(
                config.threads_within_image,
                1,
            );
            try admitFrameSlot(
                slot,
                outer_alloc,
                camera,
                config,
                slot_geom_threads,
                slot_raster_threads,
                next_frame_idx,
                num_fields,
                if (images_arr) |*ima| ima else null,
                out_dir,
                io,
            );
            try spawnFrameGeometry(
                slot,
                camera,
                mesh_static_prepared,
                nodal_global_scaling,
            );
            next_frame_idx += 1;
            progressed = true;
        }

        if (!progressed) {
            if (raster_slot) |slot| {
                try finishFrameRaster(slot);
                try finalizeFrameSlot(slot);
                slot.reset(outer_alloc);
                completed_frames += 1;
                raster_slot = null;
                continue;
            }
            if (findInGeometryFrameSlot(frame_slots)) |slot| {
                try finishFrameGeometry(slot);
                continue;
            }
            return error.FramePipelineStalled;
        }
    }

    return images_arr;
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
