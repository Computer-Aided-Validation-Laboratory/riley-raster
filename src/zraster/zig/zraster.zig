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
const shaderops = @import("shaderops.zig");
const ShaderInput = shaderops.ShaderInput;
const ShaderPrepared = shaderops.ShaderPrepared;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;
const imageops = @import("imageops.zig");

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

    // Main render loop, frame by frame
    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        // Prepare and reshape data for all meshes in this frame
        var prep_meshes = try arena_alloc.alloc(MeshPrepared, meshes.len);
        for (meshes, 0..) |mesh, ii| {
            // Apply displacements to coords to deform mesh
            var coords_to_prep: MatSlice(f64) = undefined;
            if (mesh.disp) |disp| {
                const frame_idx = @min(tt, disp.array.dims[dim_time_pre] - 1);
                coords_to_prep = try applyDispToMesh(
                    arena_alloc,
                    frame_idx,
                    &mesh.coords.mat,
                    &disp.array,
                );
            } else {
                coords_to_prep = MatSlice(f64).init(
                    mesh.coords.mat.slice,
                    mesh.coords.mat.rows_num,
                    mesh.coords.mat.cols_num,
                );
            }

            // Apply on-the-fly field scaling for rendering in bits, if required
            var nodal_frame_scaling: ?imageops.ScalingParams = null;
            switch (mesh.shader) {
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

            // Final prepared meshes in NDArray format: [elems_num,field,nodes_per_elem]
            prep_meshes[ii] = try mr.prepareMesh(
                arena_alloc,
                &mesh,
                &coords_to_prep,
                nodal_frame_scaling,
            );
        }

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
                try rasterSceneInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    &frame_arr,
                    config.tile_size,
                    .off,
                    &off_log,
                );
            },
            .bench => {
                var bench_log = BenchLog{};
                try rasterSceneInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    &frame_arr,
                    config.tile_size,
                    .bench,
                    &bench_log,
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

                try rasterSceneInternal(
                    arena_alloc,
                    io,
                    camera,
                    tt,
                    prep_meshes,
                    &frame_arr,
                    config.tile_size,
                    .full_stats,
                    &full_stats_log,
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
    comptime report_mode: ReportMode,
    report_log: *report.LogType(report_mode),
) !void {
    const raster_start = Timestamp.now(io, .awake);
    const ctx_report = report.ReportContext(report_mode){ .log = report_log };
    var pipe_times = report.PipeTimes{};

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
