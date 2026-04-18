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
    threads_over_images: u16 = 0,
    save_opt: SaveOption = .disk,
    save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .none },
    },
    tile_size: u16 = 32,
    report: ReportMode = .bench,
    full_stats_opts: FullStatsOpts = .{},
};

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

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const dim_time_pre: usize = 0; // Array dimension for time pre-format prep

    // Work out max time across all meshes
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

    // Work out the number of fields/channels we are rendering to the final image
    var num_fields: u8 = 0;
    for (meshes) |mesh| {
        const mesh_fields: u8 = switch (mesh.shader) {
            .nodal => |s| s.field.getFieldsN(),
            .tex => 1,
            .tex_rgb => 3,
        };

        num_fields = @max(num_fields, mesh_fields);
    }

    // Allocate NDArray if we are returning everything to the user in memory
    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time,
            @as(usize, num_fields),
            camera.pixels_num[1],
            camera.pixels_num[0],
        };
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    // Work out field scaling for on-the-fly scaled rendering
    var nodal_global_scaling = try outer_alloc.alloc(?imageops.ScalingParams, meshes.len);
    defer outer_alloc.free(nodal_global_scaling);
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

    const mesh_static_prepared = try static_alloc.alloc(MeshStaticPrepared, meshes.len);
    for (meshes, 0..) |mesh, ii| {
        mesh_static_prepared[ii] = try mr.prepareMeshStatic(static_alloc, &mesh);
    }

    var geom_pool_storage: geomthread.GeometryWorkerPool = undefined;
    var geom_pool: ?*geomthread.GeometryWorkerPool = null;
    defer if (geom_pool) |pool| {
        pool.deinit(outer_alloc);
    };

    if (config.threads_geom_preproc > 1) {
        try geom_pool_storage.init(
            outer_alloc,
            io,
            config.threads_geom_preproc,
        );
        geom_pool = &geom_pool_storage;
    }

    // Main render loop, frame by frame
    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        const time_start_geo = Timestamp.now(io, .awake);
        var frame_meshes = try arena_alloc.alloc(FrameMeshPrepared, meshes.len);
        var prep_meshes = try arena_alloc.alloc(MeshPrepared, meshes.len);
        const elem_bboxes_by_mesh = try arena_alloc.alloc([]ElemBBox, meshes.len);
        const elems_in_image_by_mesh = try arena_alloc.alloc(usize, meshes.len);
        const raster_hulls = try arena_alloc.alloc(?NDArray(f64), meshes.len);
        var total_elems_in_image: usize = 0;
        var total_elems_num: usize = 0;

        for (mesh_static_prepared, 0..) |*mesh_static, ii| {
            var nodal_frame_scaling: ?imageops.ScalingParams = null;
            switch (mesh_static.shader) {
                .nodal => |s| {
                    if (s.scale_over == .over_frames) {
                        nodal_frame_scaling = nodal_global_scaling[ii];
                    } else {
                        nodal_frame_scaling = imageops.getScalingParamsNDArray(
                            &s.field.array,
                            tt,
                            s.scaling,
                        );
                    }
                },
                else => {},
            }

            frame_meshes[ii] = try mr.prepareVisibleFrameMesh(
                arena_alloc,
                camera,
                mesh_static,
                tt,
                nodal_frame_scaling,
                geom_pool,
            );
            prep_meshes[ii] = frame_meshes[ii].mesh;
            elem_bboxes_by_mesh[ii] = frame_meshes[ii].elem_bboxes;
            elems_in_image_by_mesh[ii] = frame_meshes[ii].elems_in_image;
            raster_hulls[ii] = frame_meshes[ii].raster_hull;
            total_elems_num += frame_meshes[ii].total_elems_num;
            total_elems_in_image += frame_meshes[ii].elems_in_image;
        }
        const time_end_geo = Timestamp.now(io, .awake);
        var pipe_times = report.PipeTimes{};
        pipe_times.geometry_prep = @floatFromInt(
            time_start_geo.durationTo(time_end_geo).raw.nanoseconds,
        );

        // Allocate frame buffer to render the image into or wrap the NDArray of frames to
        // return to the user
        var frame_arr: NDArray(f64) = undefined;
        if (images_arr) |*ima| {
            const stride = ima.strides[0];
            const mem = ima.slice[tt * stride .. (tt + 1) * stride];
            frame_arr = try NDArray(f64).init(arena_alloc, mem, ima.dims[1..]);
        } else {
            const dims = [_]usize{
                @as(usize, num_fields),
                camera.pixels_num[1],
                camera.pixels_num[0],
            };
            frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
        }
        @memset(frame_arr.slice, 0.0);

        switch (config.report) {
            .off => {
                var off_log = report.OffLog{};
                try rasterPreparedVisibleInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    elem_bboxes_by_mesh,
                    elems_in_image_by_mesh,
                    raster_hulls,
                    total_elems_num,
                    total_elems_in_image,
                    &frame_arr,
                    config.tile_size,
                    config.threads_within_image,
                    .off,
                    &off_log,
                    outer_alloc,
                    time_start_geo,
                    pipe_times,
                );
            },
            .bench => {
                var bench_log = BenchLog{};
                try rasterPreparedVisibleInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    elem_bboxes_by_mesh,
                    elems_in_image_by_mesh,
                    raster_hulls,
                    total_elems_num,
                    total_elems_in_image,
                    &frame_arr,
                    config.tile_size,
                    config.threads_within_image,
                    .bench,
                    &bench_log,
                    outer_alloc,
                    time_start_geo,
                    pipe_times,
                );
            },
            .full_stats => {
                var full_stats_log = try report.initFullStatsLog(
                    outer_alloc,
                    camera.pixels_num,
                    config.tile_size,
                    camera.sub_sample,
                    config.full_stats_opts,
                );
                defer full_stats_log.deinit(outer_alloc);

                try rasterPreparedVisibleInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    elem_bboxes_by_mesh,
                    elems_in_image_by_mesh,
                    raster_hulls,
                    total_elems_num,
                    total_elems_in_image,
                    &frame_arr,
                    config.tile_size,
                    config.threads_within_image,
                    .full_stats,
                    &full_stats_log,
                    outer_alloc,
                    time_start_geo,
                    pipe_times,
                );

                var nodes_sum: usize = 0;
                for (prep_meshes) |mesh| {
                    nodes_sum += mesh.mesh_type.getNodesNum();
                }
                const nodes_per_elem: f64 = @as(f64, @floatFromInt(nodes_sum)) /
                    @as(f64, @floatFromInt(prep_meshes.len));

                try full_stats_log.saveFrameReport(
                    io,
                    outer_alloc,
                    out_dir,
                    tt,
                    camera,
                    config.tile_size,
                    config.full_stats_opts,
                    nodes_per_elem,
                );
            },
        }

        if (config.save_opt == .disk or config.save_opt == .both) {
            try iio.saveImages(
                io,
                out_dir,
                tt,
                num_fields,
                camera.pixels_num,
                &frame_arr,
                config.save_opts,
            );
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
