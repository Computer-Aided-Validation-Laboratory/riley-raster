const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const mr = @import("meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster;
const MeshTransform = mr.MeshTransform;
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;
const Shader = mr.Shader;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;
const imageops = @import("imageops.zig");

const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

const perf = @import("perf.zig");
const Report = perf.Report;
const Perf = perf.Perf;
const PerfOpts = perf.PerfOpts;

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
        .{ .format = .tiff, .bits = 8, .scaling = .none },
    },
    tile_size: u16 = 16,
    report: Report = .off,
    perf_opts: PerfOpts = .{},
};

fn applyDispToMesh(
    outer_alloc: std.mem.Allocator,
    tt: usize,
    coords: *const MatSlice(f64),
    disp: *const NDArray(f64),
) !MatSlice(f64) {

    var coords_disp = try MatSlice(f64).initAlloc(
        outer_alloc, coords.rows_num, coords.cols_num
    );
    @memcpy(coords_disp.elems, coords.elems);

    const disp_frame_mem = disp.getSlice(&[_]usize{ tt, 0, 0 }, 0);
    var disp_frame = MatSlice(f64).init(disp_frame_mem, 
                                        disp.dims[1],
                                        disp.dims[2]);

    coords_disp.addInPlace(&disp_frame);

    return coords_disp;
}

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    meshes: []const MeshRaster,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const dim_time_pre: usize = 0;
    const dim_field_pre: usize = 2;

    // Work out max time across all meshes
    var num_time: usize = 1;
    for (meshes) |mesh| {
        if (mesh.disp) |field| {
            num_time = @max(num_time, field.array.dims[dim_time_pre]);
        } else if (mesh.shader == .flat) {
            num_time = @max(num_time, mesh.shader.flat.field.array.dims[dim_time_pre]);
        }
    }

    // For now we assume all meshes in scene have SAME number of fields
    var num_fields: usize = 0;
    for (meshes) |mesh| {
        const mesh_fields = switch (mesh.shader) {
            .flat => |f| f.field.array.dims[dim_field_pre],
            .tex_u8, .tex_u16 => 1,
        };
        num_fields = @max(num_fields, mesh_fields);
    }

    // Allocate NDArray if we are returning everything to the user in memory
    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time, num_fields, camera.pixels_num[1], camera.pixels_num[0]
        };
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    var flat_global_scaling = try outer_alloc.alloc(?imageops.ScalingParams, meshes.len);
    defer outer_alloc.free(flat_global_scaling);
    for (meshes, 0..) |mesh, ii| {
        flat_global_scaling[ii] = null;
        if (mesh.shader == .flat) {
            if (mesh.shader.flat.scale_over == .over_frames) {
                flat_global_scaling[ii] = imageops.getScalingParamsNDArray(
                    &mesh.shader.flat.field.array, null, mesh.shader.flat.scaling
                );
            }
        }
    }

    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        // Transform all meshes for this frame
        var transformed_meshes = try arena_alloc.alloc(MeshTransform, meshes.len);
        for (meshes, 0..) |mesh, ii| {
            var coords_to_trans: MatSlice(f64) = undefined;
            if (mesh.disp) |disp| {
                const frame_idx = @min(tt, disp.array.dims[dim_time_pre] - 1);
                coords_to_trans = try applyDispToMesh(
                    arena_alloc, frame_idx, &mesh.coords.mat, &disp.array
                );
            } else {
                coords_to_trans = MatSlice(f64).init(mesh.coords.mat.elems, 
                                                     mesh.coords.mat.rows_num,
                                                     mesh.coords.mat.cols_num);
            }

            var flat_frame_scaling: ?imageops.ScalingParams = null;
            if (mesh.shader == .flat) {
                if (mesh.shader.flat.scale_over == .over_frames) {
                    flat_frame_scaling = flat_global_scaling[ii];
                } else {
                    flat_frame_scaling = imageops.getScalingParamsNDArray(
                        &mesh.shader.flat.field.array, tt, mesh.shader.flat.scaling
                    );
                }
            }
            transformed_meshes[ii] = try mr.transformMesh(
                arena_alloc, &mesh, &coords_to_trans, flat_frame_scaling
            );
        }
        
        var frame_arr: NDArray(f64) = undefined;
        if (images_arr) |*ima| {
            const stride = ima.strides[0];
            const mem = ima.elems[tt * stride .. (tt + 1) * stride];
            frame_arr = try NDArray(f64).init(arena_alloc, mem, ima.dims[1..]);
        } else {
            const dims = [_]usize{ num_fields, camera.pixels_num[1], camera.pixels_num[0] };
            frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
        }
        @memset(frame_arr.elems, 0.0);

        var frame_perf: ?perf.Perf = null;
        if (config.report == .perf) {
            frame_perf = try perf.initFramePerf(
                outer_alloc,
                camera.pixels_num,
                config.tile_size,
                camera.sub_sample,
                config.perf_opts,
            );
        }
        defer if (frame_perf) |*fp| fp.deinit(outer_alloc);

        switch (config.report) {
            .off => try rasterSceneInternal(
                arena_alloc, io, camera, tt, transformed_meshes, &frame_arr, 
                config.tile_size, .off, null,
            ),
            .perf => try rasterSceneInternal(
                arena_alloc, io, camera, tt, transformed_meshes, &frame_arr, 
                config.tile_size, .perf, &frame_perf.?,
            ),
        }

        if (frame_perf) |*fp| {
            try fp.saveFrameReport(
                io, outer_alloc, out_dir, tt, camera, config.tile_size, config.perf_opts,
            );
        }

        if (config.save_opt == .disk or config.save_opt == .both) {
            try iio.saveImages(
                io, out_dir, tt, num_fields, camera.pixels_num, &frame_arr, 
                config.save_opts,
            );
        }
    }
    return images_arr;
}

fn rasterSceneInternal(
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_ind: usize,
    meshes: []MeshTransform,
    image_out_arr: *NDArray(f64),
    tile_size: u16,
    comptime report: Report,
    perf_data: ?*Perf,
) !void {
    const raster_start = Timestamp.now(io, .awake);
    const pctx = perf.PerfContext(report){ .perf = if (report == .perf) perf_data.? else {} };
    var pipe_times = perf.PipeTimes{};

    const tiles_num_x: usize = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const time_start_geo = Timestamp.now(io, .awake);

    const elem_bboxes_by_mesh = try arena_alloc.alloc([]ElemBBox, meshes.len);
    const elems_in_image_by_mesh = try arena_alloc.alloc(usize, meshes.len);
    var total_elems_in_image: usize = 0;
    var total_elems_num: usize = 0;
    const raster_hulls = try arena_alloc.alloc(?NDArray(f64), meshes.len);

    try rops.prepareSceneGeometry(
        report,
        pctx,
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
        time_start_geo.durationTo(time_end_geo).raw.nanoseconds
    );

    const time_start_overlap = Timestamp.now(io, .awake);

    const tiling = try rops.sceneTileElemOverlap(
        arena_alloc,
        tile_size,
        tiles_num_x,
        tiles_num_y,
        @intCast(camera.pixels_num[0]),
        @intCast(camera.pixels_num[1]),
        meshes.len,
        elems_in_image_by_mesh,
        elem_bboxes_by_mesh,
    );

    const time_end_overlap = Timestamp.now(io, .awake);
    pipe_times.tile_overlap = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds
    );

    const time_start_loop = Timestamp.now(io, .awake);

    const ctx = rops.RasterContext(report){
        .perf_ctx = pctx,
        .camera = camera,
        .frame_ind = frame_ind,
        .tile_size = tile_size,
    };

    try rasterengine.rasterScene(
        report,
        ctx,
        arena_alloc,
        io,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );
    
    const time_end_loop = Timestamp.now(io, .awake);
    pipe_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds
    );

    const raster_end = Timestamp.now(io, .awake);
    pipe_times.total_time = @floatFromInt(
        raster_start.durationTo(raster_end).raw.nanoseconds
    );

    if (comptime report == .perf) {
        perf_data.?.pipe_times = pipe_times;
    } else {
        try perf.standardReport(io, camera, pipe_times, total_elems_num);
    }
}
