const std = @import("std");
const print = std.debug.print;
const Timestamp = std.Io.Clock.Timestamp;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const meshraster = @import("meshraster.zig");
const MeshType = meshraster.MeshType;
const MeshRaster = meshraster.MeshRaster;
const MeshTransform = meshraster.MeshTransform;
const FlatShader = meshraster.FlatShader;
const TexShader = meshraster.TexShader;
const Shader = meshraster.Shader;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;

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
    save_formats: []const ImageFormat = &[_]ImageFormat{.tiff},
    tile_size: u16 = 16,
    report: Report = .off,
    perf_opts: PerfOpts = .{},
};

fn applyDispToMesh(
    outer_alloc: std.mem.Allocator,
    tt: usize,
    coords: *const NDArray(f64),
    disp: *const NDArray(f64),
) !NDArray(f64) {
    var coords_disp = try NDArray(f64).initFlat(outer_alloc, coords.dims);
    @memcpy(coords_disp.elems, coords.elems);

    const disp_frame_mem = disp.getSlice(&[_]usize{ tt, 0, 0, 0 }, 0);
    var disp_frame = try NDArray(f64).init(outer_alloc, disp_frame_mem, disp.dims[1..]);
    coords_disp.addInPlace(&disp_frame);

    return coords_disp;
}

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    mesh_in: *const MeshRaster,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    // TODO: time the data transformation step!
    const mesh_trans = try mr.transformMesh(arena_alloc, mesh_in);

    var num_time: usize = 1;
    if (mesh_trans.disp) |d| {
        num_time = d.dims[0];
    } else if (mesh_trans.shader == .flat) {
        num_time = mesh_trans.shader.flat.field.dims[0];
    }

    const num_fields = switch (mesh_trans.shader) {
        .flat => |f| f.field.dims[2],
        .texture => 1,
    };

    // Allocate NDArray if we are returning everything to the user in memory
    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time, num_fields, camera.pixels_num[1], camera.pixels_num[0]
        };
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        // Add displacements to nodal coordinates if mesh is deforming
        var coords_transform: NDArray(f64) = undefined;
        if (mesh_trans.disp) |disp| {
            coords_transform = try applyDispToMesh(arena_alloc, tt, &mesh_trans.coords, 
                                                   &disp);
        } else {
            coords_transform = try NDArray(f64).initFlat(arena_alloc, 
                                                         mesh_trans.coords.dims);
            @memcpy(coords_transform.elems, mesh_trans.coords.elems);
        }
        
        // Allocate frame buffer or wrap images NDArray slice to return to user
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

        // Performance allocs for rendering diagnostic images
        var frame_perf: ?Perf = null;
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
            .off => try rasterOneFrame(
                mesh_trans.mesh_type,
                arena_alloc,
                io,
                camera,
                tt,
                config.tile_size,
                config.threads_within_image,
                &mesh_trans.shader,
                &coords_transform,
                &frame_arr,
                .off,
                null,
            ),
            .perf => try rasterOneFrame(
                mesh_trans.mesh_type,
                arena_alloc,
                io,
                camera,
                tt,
                config.tile_size,
                config.threads_within_image,
                &mesh_trans.shader,
                &coords_transform,
                &frame_arr,
                .perf,
                &frame_perf.?,
            ),
        }

        if (frame_perf) |*fp| {
            try fp.saveFrameReport(
                io, outer_alloc, out_dir, tt, camera, config.tile_size, config.perf_opts,
            );
        }

        if (config.save_opt == .disk or config.save_opt == .both) {
            const bits: u8 = switch (mesh_trans.shader) {
                .flat => |f| @intCast(f.bits orelse 8),
                .texture => 8,
            };
            try iio.saveImages(
                io, out_dir, tt, num_fields, camera.pixels_num, &frame_arr, 
                config.save_formats, bits,
            );
        }
    }
    return images_arr;
}

pub fn rasterOneFrame(
    mesh_type: MeshType,
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    mesh: *const MeshTransform,
    frame_ind: usize,
    tile_size: u16,
    threads: u16,
    shader: *const FieldShader,
    coords: *NDArray(f64),
    image_out_arr: *NDArray(f64),
    comptime report: Report,
    perf_data: ?*Perf,
) !void {

    _ = threads;

    switch (mesh_type) {
        inline else => |m_tag| {
            const GK = switch (m_tag) {
                .tri3 => geomkerns.Tri3Kernel(),
                .tri3opt => geomkerns.Tri3OptKernel(),
                .tri6 => geomkerns.Tri6Kernel(),
                .quad4ibi => geomkerns.Quad4IBIKernel(),
                .quad4newton => geomkerns.Quad4NewtonKernel(),
                .quad8 => geomkerns.Quad89Kernel(8),
                .quad9 => geomkerns.Quad89Kernel(9),
            };
            const N = GK.nodes_num;

            switch (shader.*) {
                .flat => |*sh| {
                    const SK = shadekerns.FlatKernel(N);
                    try rasterInternal(GK, SK, FlatShader, allocator, io, camera, frame_ind, 
                        tile_size, sh, coords, image_out_arr, report, perf_data);
                },
                .texture => |*sh| {
                    switch (sh.interp_type) {
                        inline else => |it| {
                            const SK = shadekerns.TexKernel(N, it);
                            try rasterInternal(GK, SK, TexShader, allocator, io, camera, 
                                frame_ind, tile_size, sh, coords, image_out_arr, report, 
                                perf_data
                            );
                        }
                    }
                },
            }
        }
    }
}

fn rasterInternal(
    comptime GK: type, // geometry kernel
    comptime SK: type, // shader kernel
    comptime SD: type, // shader data
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_ind: usize,
    tile_size: u16,
    shader: *const SD,
    coords: *NDArray(f64),
    image_out_arr: *NDArray(f64),
    comptime report: Report,
    perf_data: ?*Perf,
) !void {

    const raster_start = Timestamp.now(io, .awake);
    const pctx = perf.PerfContext(report){ .perf = if (report == .perf) perf_data.? else {} };
    var pipe_times = perf.PipeTimes{};

    const N = GK.nodes_num;
    const dim_elem: usize = 0;
    const elems_num: usize = coords.dims[dim_elem];

    const screen_px_x = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16, @intCast(camera.pixels_num[1]));

    const tiles_num_x: usize = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);
    const tiles_num: usize = tiles_num_x * tiles_num_y;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 1: Coordinate transformation
    const time_start_internal = Timestamp.now(io, .awake);
    
    if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
        try rops.transformElemsRasterSIMD(N, f64, camera, dim_elem, coords);
    } else {
        try rops.transformElemsClipPxLengSIMD(N, f64, camera, dim_elem, coords);
    }

    // TODO: Transform to NDArray here?

    // Need to handle quad9 - has a hull of 8 points
    const NH = if (comptime GK.has_hull) GK.hull_nodes_num else 0;
    var raster_hull: ?NDArray(f64) = null;
    if (comptime GK.has_hull) {
        raster_hull = try NDArray(f64).initFlat(
            arena_alloc,
            &[_]usize{ elems_num, 2, NH },
        );
        try rops.buildAdaptiveHulls(N, camera, dim_elem, coords, &raster_hull.?);
    }

    const time_end_internal = Timestamp.now(io, .awake);
    pipe_times.coord_transform = @floatFromInt(
        time_start_internal.durationTo(time_end_internal).raw.nanoseconds
    );

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 2: Count elements in image and calculate element bounding boxes
    const time_start_bbox = Timestamp.now(io, .awake);

    const element_bboxes: []BBox = try arena_alloc.alloc(BBox, elems_num);

    var elements_in_image: usize = 0;
    if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
        elements_in_image = try rops.countElemsCalcBBoxesTri3(
            camera,
            dim_elem,
            coords,
            element_bboxes,
        );
    } else {
        const rh_ptr = if (raster_hull) |*rh| rh else null;
        elements_in_image = try rops.countElemsCalcBBoxes(
            N,
            NH,
            camera,
            dim_elem,
            coords,
            rh_ptr,
            element_bboxes,
        );
    }

    const time_end_bbox = Timestamp.now(io, .awake);
    pipe_times.bbox_calc = @floatFromInt(
        time_start_bbox.durationTo(time_end_bbox).raw.nanoseconds
    );

    if (comptime report == .perf) {
        pctx.recordGeometry(elems_num, elements_in_image);
    }

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 3: Count number of elements overlapping each tile
    const time_start_overlap = Timestamp.now(io, .awake);

    const tile_elem_counts = try arena_alloc.alloc(usize, tiles_num);
    @memset(tile_elem_counts, 0);
    const tile_write_inds = try arena_alloc.alloc(usize, tiles_num);

    const num_active_tiles = try rops.elemTileOverlapCount(
        tile_size,
        tiles_num_x,
        elements_in_image,
        element_bboxes,
        tile_elem_counts,
        tile_write_inds,
    );
    
    const time_end_overlap = Timestamp.now(io, .awake);
    pipe_times.tile_count = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds
    );

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 4: Store overlap bounding boxes for the active tiles
    const time_start_store = Timestamp.now(io, .awake);

    const overlap_total: usize = sliceops.sum(usize, tile_elem_counts);
    const overlap_bboxes = try arena_alloc.alloc(BBox, overlap_total);
    const active_tiles = try arena_alloc.alloc(ActiveTile, num_active_tiles);

    rops.storeActiveTiles(
        tile_size,
        tiles_num_x,
        tiles_num_y,
        screen_px_x,
        screen_px_y,
        elements_in_image,
        element_bboxes,
        tile_elem_counts,
        tile_write_inds,
        overlap_bboxes,
        active_tiles,
    );

    const time_end_store = Timestamp.now(io, .awake);
    pipe_times.tile_store = @floatFromInt(
        time_start_store.durationTo(time_end_store).raw.nanoseconds
    );

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 5: Main raster loop
    const time_start_loop = Timestamp.now(io, .awake);

    try rasterengine.RasterEngine(GK, SK, SD).raster(
        report,
        pctx,
        arena_alloc,
        io,
        camera,
        frame_ind,
        tile_size,
        active_tiles,
        overlap_bboxes,
        coords,
        shader,
        if (raster_hull) |*rh| rh else null,
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

    if (report == .perf) {
        perf_data.?.pipe_times = pipe_times;
    }

    if (comptime report == .off) {
        try perf.standardReport(io, camera, pipe_times, elems_num);
    }
}
