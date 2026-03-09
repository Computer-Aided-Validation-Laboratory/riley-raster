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
const FlatShader = meshraster.FlatShader;
const TexShader = meshraster.TexShader;
const FieldShader = meshraster.FieldShader;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;

const geometrykernels = @import("geometrykernels.zig");
const shaderkernels = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

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
    tile_size: u16 = 32,
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
    mesh_raster: *const MeshRaster,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var num_time: usize = 1;
    if (mesh_raster.disp) |d| {
        num_time = d.dims[0];
    } else if (mesh_raster.shader == .flat) {
        num_time = mesh_raster.shader.flat.field.dims[0];
    }

    const num_fields = switch (mesh_raster.shader) {
        .flat => |f| f.field.dims[2],
        .texture => 1,
    };

    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time, num_fields, camera.pixels_num[1], camera.pixels_num[0]
        };
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        var coords_transform: NDArray(f64) = undefined;
        if (mesh_raster.disp) |disp| {
            coords_transform = try applyDispToMesh(arena_alloc, tt, &mesh_raster.coords, 
                                                   &disp);
        } else {
            coords_transform = try NDArray(f64).initFlat(arena_alloc, 
                                                        mesh_raster.coords.dims);
            @memcpy(coords_transform.elems, mesh_raster.coords.elems);
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

        try rasterOneFrame(
            mesh_raster.mesh_type,
            arena_alloc,
            io,
            camera,
            tt,
            config.tile_size,
            config.threads_within_image,
            &mesh_raster.shader,
            &coords_transform,
            &frame_arr,
        );

        if (config.save_opt == .disk or config.save_opt == .both) {
            if (out_dir) |save_dir| {
                var name_buff: [1024]u8 = undefined;
                for (0..num_fields) |ff| {
                    const file_name = try std.fmt.bufPrint(name_buff[0..], 
                                                           "frame_{d}_field_{d}", 
                                                           .{ tt, ff });
                    const save_slice = frame_arr.getSlice(&[_]usize{ ff, 0, 0 }, 0);
                    const save_mat = MatSlice(f64).init(save_slice, 
                                                        camera.pixels_num[1], 
                                                        camera.pixels_num[0]);
                    const bits: u8 = switch (mesh_raster.shader) {
                        .flat => |f| @intCast(f.bits orelse 8),
                        .texture => 8,
                    };
                    for (config.save_formats) |format| {
                        try iio.saveImage(io, save_dir, file_name, &save_mat, format, bits);
                    }
                }
            }
        }
    }
    return images_arr;
}

pub fn rasterOneFrame(
    mesh_type: MeshType,
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_ind: usize,
    tile_size: u16,
    threads: u16,
    shader: *const FieldShader,
    coords: *NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    _ = threads;
    const raster_start = Timestamp.now(io, .awake);

    switch (mesh_type) {
        inline else => |m_tag| {
            const GK = switch (m_tag) {
                .tri3, .tri3opt => geometrykernels.Tri3Kernel(),
                .tri6 => geometrykernels.Tri6Kernel(),
                .quad4ibi => geometrykernels.Quad4IBIKernel(),
                .quad4newton => geometrykernels.Quad4NewtonKernel(),
                .quad8 => geometrykernels.HigherOrderKernel(8),
                .quad9 => geometrykernels.HigherOrderKernel(9),
            };
            const N = GK.node_n;

            switch (shader.*) {
                .flat => |*sh| {
                    const SK = shaderkernels.FlatKernel(N);
                    try rasterInternalMono(
                        GK, SK, FlatShader, allocator, io, camera, frame_ind, 
                        tile_size, sh, coords, image_out_arr, raster_start
                    );
                },
                .texture => |*sh| {
                    switch (sh.interp_type) {
                        inline else => |it| {
                            const SK = shaderkernels.TexKernel(N, it);
                            try rasterInternalMono(
                                GK, SK, TexShader, allocator, io, camera, frame_ind, 
                                tile_size, sh, coords, image_out_arr, raster_start
                            );
                        }
                    }
                },
            }
        }
    }
}

fn rasterInternalMono(
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
    raster_start: Timestamp,
) !void {
    const N = GK.node_n;
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

    const time_start_internal = Timestamp.now(io, .awake);
    if (comptime GK.coord_space == geometrykernels.CoordSpace.raster) {
        try rops.transformElemsRasterSIMD(N, f64, camera, dim_elem, coords);
    } else {
        try rops.transformElemsCamSIMD(N, f64, camera, dim_elem, coords);
    }
    const time_end_internal = Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(
        time_start_internal.durationTo(time_end_internal).raw.nanoseconds
    );

    const time_start_bbox = Timestamp.now(io, .awake);
    const element_bboxes: []BBox = try arena_alloc.alloc(BBox, elems_num);
    const elements_in_image = if (comptime GK.coord_space == geometrykernels.CoordSpace.raster)
        try rops.countElemsCalcBBoxesTri3(camera, dim_elem, coords, element_bboxes)
    else
        try rops.countElemsCalcBBoxes(N, camera, dim_elem, coords, element_bboxes);
    const time_end_bbox = Timestamp.now(io, .awake);
    const time2_elem_bboxes_crop: f64 = @floatFromInt(
        time_start_bbox.durationTo(time_end_bbox).raw.nanoseconds
    );

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
    const time3_elem_tile_overlap_count: f64 = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds
    );

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
    const time4_elem_tile_overlap_store: f64 = @floatFromInt(
        time_start_store.durationTo(time_end_store).raw.nanoseconds
    );

    const time_start_loop = Timestamp.now(io, .awake);
    try rasterengine.RasterEngine(GK, SK, SD).raster(
        arena_alloc,
        camera,
        frame_ind,
        tile_size,
        active_tiles,
        overlap_bboxes,
        coords,
        shader,
        image_out_arr,
    );
    const time_end_loop = Timestamp.now(io, .awake);
    const time5_raster_loop: f64 = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds
    );

    const raster_end = Timestamp.now(io, .awake);
    const time_raster_all: f64 = @floatFromInt(
        raster_start.durationTo(raster_end).raw.nanoseconds
    );

    var total_px: f64 = @as(f64, @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    total_px = total_px * sub_samp_f * sub_samp_f;
    const mega_ops_per_sec: f64 = 1.0e3 * total_px / time_raster_all;
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(elems_num)) / 
                                   time_raster_all;

    const conv_units: f64 = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\nSoftware Raster Times\n{s}\n", .{ print_break, print_break });
    print("World to raster         = {d:.6} ms\n", .{ time1_world_to_raster * conv_units });
    print("Elem bbox crop          = {d:.6} ms\n", .{ time2_elem_bboxes_crop * conv_units });
    print("Elem tile overlap count = {d:.6} ms\n", 
          .{ time3_elem_tile_overlap_count * conv_units });
    print("Elem tile overlap store = {d:.6} ms\n", 
          .{ time4_elem_tile_overlap_store * conv_units });
    print("Raster loop time        = {d:.6} ms\n", .{ time5_raster_loop * conv_units });
    print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n", 
          .{ print_break, time_raster_all * conv_units });
    print("{s}\n", .{print_break});
    print("Total Ops   = {d}\n", .{total_px});
    print("MOps/second = {d:.2}\n", .{mega_ops_per_sec});
    print("MTri/second = {d:.2}\n", .{mega_tris_per_sec});
    print("{s}\n", .{print_break});
}
