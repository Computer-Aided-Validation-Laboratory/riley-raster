// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const print = std.debug.print;
const time = std.time;
const Timestamp = std.Io.Clock.Timestamp;

const Vec3f = @import("vecstack.zig").Vec3f;
const Vec3SliceOps = @import("vecstack.zig").Vec3SliceOps;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

const Camera = @import("camera.zig").Camera;

const iio = @import("imageio.zig");

fn edgeFun(vert_0: Vec3f, vert_1: Vec3f, vert_2: Vec3f) f64 {
    return ((vert_2.get(0) - vert_0.get(0)) *
        (vert_1.get(1) - vert_0.get(1)) -
        (vert_2.get(1) - vert_0.get(1)) *
            (vert_1.get(0) - vert_0.get(0)));
}

fn boundIndexMin(min_val: f64) usize {
    const min_idx = @as(isize, @intFromFloat(@floor(min_val)));
    return @as(usize, @intCast(@max(0, min_idx)));
}

fn boundIndexMax(max_val: f64, pixels_num: usize) usize {
    const max_idx = @as(isize, @intFromFloat(@ceil(max_val)));
    const px = @as(isize, @intCast(pixels_num - 1));
    return @as(usize, @intCast(@max(0, @min(max_idx, px))));
}

fn worldToRasterCoords(coord_world: Vec3f, camera: *const Camera) Vec3f {
    var coord_raster = Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);

    coord_raster.slice[0] = camera.image_dist * coord_raster.slice[0] /
        (-coord_raster.slice[2]);
    coord_raster.slice[1] = camera.image_dist * coord_raster.slice[1] /
        (-coord_raster.slice[2]);

    coord_raster.slice[0] = 2.0 * coord_raster.slice[0] / camera.image_dims[0];
    coord_raster.slice[1] = 2.0 * coord_raster.slice[1] / camera.image_dims[1];

    coord_raster.slice[0] = (coord_raster.slice[0] + 1.0) / 2.0 *
        @as(f64, @floatFromInt(camera.pixels_num[0]));
    coord_raster.slice[1] = (1.0 - coord_raster.slice[1]) / 2.0 *
        @as(f64, @floatFromInt(camera.pixels_num[1]));
    coord_raster.slice[2] = -coord_raster.slice[2];

    return coord_raster;
}

pub fn rasterOneFrame(
    allocator: std.mem.Allocator,
    io: std.Io,
    frame_idx: usize,
    coords: *const Coords,
    connect: *const Connect,
    field: *const Field,
    camera: *const Camera,
    image_out_arr: *NDArray(f64),
) !void {

    // We allocate all temporary buffers on our arena so no need to defer
    // free any temporary buffers in this function
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const tol = cfg.tolerance.legacy.oldraster_area;
    var elems_in_image: usize = 0;
    const num_fields: usize = field.getFieldsN();

    var nodes_raster_buff: []Vec3f = try arena_alloc.alloc(Vec3f, connect.nodes_per_elem);

    // Stores N weights, one for each node in the element
    var weights_buff: []f64 = try arena_alloc.alloc(f64, connect.nodes_per_elem);

    // Stores all F field values at the N nodes per element
    var field_idxs = [_]usize{ frame_idx, 0, 0 };
    const field_buff: []f64 = try arena_alloc.alloc(
        f64,
        num_fields * connect.nodes_per_elem,
    );

    var field_raster_mat = MatSlice(f64).init(
        field_buff,
        connect.nodes_per_elem,
        num_fields,
    );

    // Stores field value at the pixel
    var px_field: f64 = 0.0;

    // Sub-pixel image buffers
    const subpx_x: usize = @as(usize, camera.pixels_num[0]) *
        @as(usize, camera.sub_sample);
    const subpx_y: usize = @as(usize, camera.pixels_num[1]) *
        @as(usize, camera.sub_sample);

    var depth_subpx_inds = [_]usize{ 0, 0 };
    var image_subpx_inds = [_]usize{ 0, 0, 0 };

    // Sub-pixel image buffer
    var image_subpx_dims = [_]usize{ num_fields, subpx_y, subpx_x };
    const image_subpx_mem = try arena_alloc.alloc(f64, subpx_y * subpx_x * num_fields);
    var image_subpx = try NDArray(f64).init(
        arena_alloc,
        image_subpx_mem,
        image_subpx_dims[0..],
    );

    // Sub-pixel depth buffer
    var depth_subpx_dims = [_]usize{ subpx_y, subpx_x };
    const depth_subpx_mem = try arena_alloc.alloc(f64, subpx_y * subpx_x);
    var depth_subpx = try NDArray(f64).init(
        arena_alloc,
        depth_subpx_mem,
        depth_subpx_dims[0..],
    );

    // Set image background to 0.0 and depth buffer to large value.
    image_subpx.fill(0.0);
    depth_subpx.fill(1e6);

    const raster_start = Timestamp.now(io, .awake);

    var px_coord_buff: Vec3f = Vec3f.initZeros();

    // Lifted constants out of loop
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const coord_step: f64 = 1.0 / sub_samp_f;
    const coord_offset: f64 = 1.0 / (2.0 * sub_samp_f);

    //----------------------------------------------------------------------
    // Raster Loop
    for (0..connect.elem_n) |ee| {
        const coord_inds: []usize = connect.getElem(ee);

        for (0..connect.nodes_per_elem) |nn| {
            nodes_raster_buff[nn] = worldToRasterCoords(coords.getVec3(coord_inds[nn]), camera);
        }

        const elem_area: f64 = edgeFun(nodes_raster_buff[0], nodes_raster_buff[1], nodes_raster_buff[2]);

        // print("Element: {d}\n",.{ee});
        // print("Node 0:",.{});
        // nodes_raster_buff[0].vecPrint();
        // print("Node 1:",.{});
        // nodes_raster_buff[1].vecPrint();
        // print("Node 2:", .{});
        // nodes_raster_buff[2].vecPrint();
        // print("{} ELEM AREA : {d:.4}\n",.{ee,elem_area});

        if (elem_area < -tol) {
            continue;
        }

        const x_min: f64 = Vec3SliceOps.min(f64, nodes_raster_buff, 0);
        const x_max: f64 = Vec3SliceOps.max(f64, nodes_raster_buff, 0);

        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        const y_min: f64 = Vec3SliceOps.min(f64, nodes_raster_buff, 1);
        const y_max: f64 = Vec3SliceOps.max(f64, nodes_raster_buff, 1);

        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }

        elems_in_image += 1;

        // print("Elem {}: x, min {}\n", .{ ee, x_min });
        // print("Elem {}: x, max {}\n", .{ ee, x_max });
        // print("Elem {}: x, min {}\n", .{ ee, y_min });
        // print("Elem {}: x, max {}\n\n", .{ ee, y_max });

        const xi_min: usize = boundIndexMin(x_min);
        const xi_max: usize = boundIndexMax(x_max, @as(usize, camera.pixels_num[0]));
        const yi_min: usize = boundIndexMin(y_min);
        const yi_max: usize = boundIndexMax(y_max, @as(usize, camera.pixels_num[1]));

        // print("Elem {}: xi, min {}\n", .{ ee, xi_min });
        // print("Elem {}: xi, max {}\n", .{ ee, xi_max });
        // print("Elem {}: yi, min {}\n", .{ ee, yi_min });
        // print("Elem {}: yi, max {}\n", .{ ee, yi_max });
        // print("\n",.{});

        const xi_min_f: f64 = @as(f64, @floatFromInt(xi_min));
        const xi_max_f: f64 = @as(f64, @floatFromInt(xi_max));
        const yi_min_f: f64 = @as(f64, @floatFromInt(yi_min));
        const yi_max_f: f64 = @as(f64, @floatFromInt(yi_max));

        var bound_coord_x: f64 = xi_min_f + 1.0 / (2.0 * sub_samp_f);
        var bound_coord_y: f64 = yi_min_f + 1.0 / (2.0 * sub_samp_f);
        var bound_ind_x: usize = @as(usize, camera.sub_sample) * xi_min;
        var bound_ind_y: usize = @as(usize, camera.sub_sample) * yi_min;

        const num_bound_x: usize = sliceops.rangeLen(xi_min_f, xi_max_f, coord_step);
        const num_bound_y: usize = sliceops.rangeLen(yi_min_f, yi_max_f, coord_step);

        // NOTE: only need inverse of node z coords
        var inv_buff: f64 = 0.0;
        for (0..connect.nodes_per_elem) |nn| {
            inv_buff = 1.0 / nodes_raster_buff[nn].z();
            nodes_raster_buff[nn].set(2, inv_buff);
        }

        // print("Elem {}: bound_coord_x={d}\n",.{ee,bound_coord_x});
        // print("Elem {}: bound_coord_y={d}\n",.{ee,bound_coord_y});
        // print("Elem {}: bound_ind_x={}\n",.{ee,bound_ind_x});
        // print("Elem {}: bound_ind_y={}\n",.{ee,bound_ind_y});
        // print("Elem {}: coord_step={d}\n",.{ee,coord_step});
        // print("Elem {}: num_bound_x={}\n",.{ee,num_bound_x});
        // print("Elem {}: num_bound_y={}\n\n",.{ee,num_bound_y});

        for (0..num_bound_y) |jj| {
            _ = jj;

            bound_coord_x = xi_min_f + coord_offset;
            bound_ind_x = camera.sub_sample * xi_min;

            for (0..num_bound_x) |ii| {
                _ = ii;

                px_coord_buff.set(0, bound_coord_x);
                px_coord_buff.set(1, bound_coord_y);

                weights_buff[0] = edgeFun(nodes_raster_buff[1], nodes_raster_buff[2], px_coord_buff);
                if (weights_buff[0] < -tol) {
                    bound_coord_x += coord_step;
                    bound_ind_x += 1;
                    continue;
                }

                weights_buff[1] = edgeFun(nodes_raster_buff[2], nodes_raster_buff[0], px_coord_buff);
                if (weights_buff[1] < -tol) {
                    bound_coord_x += coord_step;
                    bound_ind_x += 1;
                    continue;
                }

                weights_buff[2] = edgeFun(nodes_raster_buff[0], nodes_raster_buff[1], px_coord_buff);
                if (weights_buff[2] < -tol) {
                    bound_coord_x += coord_step;
                    bound_ind_x += 1;
                    continue;
                }

                // if ((ee % 10) == 0){
                //     print("Elem: {}\n",.{ee});
                //     print("x bound ind={}, coord={d}\n",
                //         .{bound_ind_x,bound_coord_x});
                //     print("y bound ind={}, coord={d}\n",
                //         .{bound_ind_y,bound_coord_y});
                //     print("weights=[{d},{d},{d}]\n",
                //         .{weights_buff[0],weights_buff[1],weights_buff[2]});
                //     print("\n",.{});
                // }

                var weight_dot_nodes: f64 = 0.0;
                for (0..connect.nodes_per_elem) |nn| {
                    weights_buff[nn] = weights_buff[nn] / elem_area;
                    weight_dot_nodes += weights_buff[nn] * nodes_raster_buff[nn].z();
                }

                // Calculate the depth for this sub-pixel
                const px_coord_z: f64 = 1.0 / weight_dot_nodes;

                // If this pixel is behind another we move on
                depth_subpx_inds[0] = bound_ind_y;
                depth_subpx_inds[1] = bound_ind_x;

                const depth_arr_z: f64 = depth_subpx.get(depth_subpx_inds[0..]);

                if (px_coord_z >= depth_arr_z) {
                    bound_coord_x += coord_step;
                    bound_ind_x += 1;
                    continue;
                }

                depth_subpx.set(depth_subpx_inds[0..], px_coord_z);

                // if ((ee % 10) == 0) {
                //     print("Elem: {}\n", .{ee});
                //     print("x bound ind={}, coord={d}\n",
                //     .{ bound_ind_x, bound_coord_x });
                //     print("y bound ind={}, coord={d}\n",
                //     .{ bound_ind_y, bound_coord_y });
                //     print("weight_dot_nodes={d}\n", .{weight_dot_nodes});
                //     print("depth_arr_z={d}\n",. {depth_arr_z});
                //     print("px_coord_z={d}\n", .{px_coord_z});
                //     print("\n", .{});
                // }

                var field_val: f64 = 0.0;
                for (0..connect.nodes_per_elem) |nn| {
                    // NOTE:
                    // field.array, shape=(time_n,coord_n,field_n)
                    // field_raster_mat, shape=(field_n,nodes_per_elem)
                    for (0..num_fields) |ff| {
                        field_idxs[1] = coord_inds[nn]; // This is scattered
                        field_idxs[2] = ff;

                        field_val = field.array.get(field_idxs[0..]);

                        //NOTE: need to multiple by inv z (see previous where inv z is put into
                        //nodes_raster_buff) for perspective correct interp!
                        field_val = field_val * nodes_raster_buff[nn].z();

                        field_raster_mat.set(ff, nn, field_val);
                    }
                }

                image_subpx_inds[1] = bound_ind_y;
                image_subpx_inds[2] = bound_ind_x;

                for (0..num_fields) |ff| {
                    const field_slice = field_raster_mat.getSlice(ff);
                    px_field = sliceops.dot(f64, field_slice, weights_buff);
                    px_field = px_field * px_coord_z;

                    // print("\nind_y={} , ind_x={}, px_field={}\n",
                    //      .{bound_ind_y,bound_ind_x,px_field});

                    image_subpx_inds[0] = ff;
                    image_subpx.set(image_subpx_inds[0..], px_field);
                }

                // DEBUG
                // Write depth buffer to first field for testing
                // image_subpx_inds[0] = 0;
                // image_subpx.set(image_subpx_inds[0..], px_coord_z);

                //----------------------------------------------------------
                // End for(x) - increment the x coords
                bound_coord_x += coord_step;
                bound_ind_x += 1;
            }
            //--------------------------------------------------------------
            // End for(y) - increment the y coords
            bound_coord_y += coord_step;
            bound_ind_y += 1;
        }
    }

    const raster_end = Timestamp.now(io, .awake);
    const time_raster_all: f64 = @floatFromInt(raster_start.durationTo(raster_end).raw.nanoseconds);

    var total_px: f64 = @as(f64, @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
    const sub_samp_f_total: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    total_px = total_px * sub_samp_f_total * sub_samp_f_total;
    // conv ns->s *1e9, conv to million ops-> /1e6 = *1e3
    const mega_ops_per_sec: f64 = 1.0e3 * total_px / time_raster_all; // time in ns
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(connect.elem_n)) / time_raster_all;

    const conv_units: f64 = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\nSoftware Raster Times\n{s}\n", .{ print_break, print_break });
    print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n", .{ print_break, time_raster_all * conv_units });
    print("{s}\n", .{print_break});
    print("Total Ops   = {d}\n", .{total_px});
    print("MOps/second = {d:.2}\n", .{mega_ops_per_sec});
    print("MTri/second = {d:.2}\n", .{mega_tris_per_sec});
    print("{s}\n", .{print_break});

    const image_subpx_max = std.mem.max(f64, image_subpx.slice);
    const image_subpx_min = std.mem.min(f64, image_subpx.slice);
    const depth_subpx_max = std.mem.max(f64, depth_subpx.slice);
    const depth_subpx_min = std.mem.min(f64, depth_subpx.slice);
    print("\nimage_subpx_max,min=[{d:.6},{d:.6}]\n", .{ image_subpx_max, image_subpx_min });
    print("depth_subpx_max,min=[{d:.6},{d:.6}]\n", .{ depth_subpx_max, depth_subpx_min });

    var out_slice_inds = [_]usize{ 0, 0, 0 };
    for (0..num_fields) |ff| {
        out_slice_inds[0] = ff;

        // 1) Create MatSlice for sub-pixel image for given field ff
        const image_subpx_slice = image_subpx.getSlice(out_slice_inds[0..], 0);
        const image_subpx_mat = MatSlice(f64).init(image_subpx_slice, subpx_y, subpx_x);

        // 2) Create wrapper MatSlice for actual images dims from last
        // two dims of the image_out_arr using getSlice()
        // Need to get it from image_out_arr
        const image_out_slice = image_out_arr.getSlice(out_slice_inds[0..], 0);
        var image_out_mat = MatSlice(f64).init(image_out_slice, camera.pixels_num[1], camera.pixels_num[0]);

        rops.averageImage(&image_subpx_mat, camera.sub_sample, &image_out_mat);
    }

    //----------------------------------------------------------------------
    // DEBUG: SAVE SUB-PIXEL IMAGES TO DISK
    //     var single_thread_io: std.Io.Threaded = .init_single_threaded;
    //     const io = single_thread_io.io();
    //
    //     const cwd: std.Io.Dir = std.Io.Dir.cwd();
    //
    //     const dir_name = "raster-test";
    //     var name_buff: [1024]u8 = undefined;
    //
    //     cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
    //         error.PathAlreadyExists => {}, // Path exists do nothing
    //         else => return err, // Propagate any other error
    //     };
    //
    //     var out_dir: std.Io.Dir = try cwd.openDir(io, dir_name, .{});
    //     defer out_dir.close(io);
    //
    //     var file_name = try std.fmt.bufPrint(name_buff[0..],
    //                                        "rn_depthsp_frame{d}",
    //                                        .{ frame_ind });
    //     const depth_mat = MatSlice(f64).init(depth_subpx.slice[0..],
    //                                          subpx_y,
    //                                          subpx_x);
    //     try rops.saveImage(io,out_dir,file_name,&depth_mat,.ppm);
    //     try rops.saveImage(io,out_dir,file_name,&depth_mat,.csv);
    //
    //     for (0..num_fields) |ff| {
    //         out_slice_inds[0] = ff;
    //
    //         file_name = try std.fmt.bufPrint(name_buff[0..],
    //                                          "rn_imagesp_field{d}_frame{d}",
    //                                          .{ ff,frame_ind });
    //         const imagesp_slice = image_subpx.getSlice(out_slice_inds[0..],0);
    //         const imagesp_mat = MatSlice(f64).init(imagesp_slice,subpx_y,subpx_x);
    //         try rops.saveImage(io,out_dir,file_name,&imagesp_mat,.ppm);
    //         try rops.saveImage(io,out_dir,file_name,&imagesp_mat,.csv);
    //     }

}

pub fn rasterAllFrames(
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    coords: *const Coords,
    connect: *const Connect,
    field: *const Field,
    camera: *const Camera,
) !NDArray(f64) {

    // We allocate all temporary buffers on our arena so no need to defer
    // free any temporary buffers in this function
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const num_fields: usize = field.getFieldsN();
    const num_time: usize = field.getTimeN();

    const frame_arr_size: usize = num_time * num_fields * camera.pixels_num[0] * camera.pixels_num[1];

    // We are going to return this so we use the input allocator instead of
    // the arena.
    const frame_arr_mem = try allocator.alloc(f64, frame_arr_size);

    // This is duped and heap allocated inside the NDArray.init so NDArray
    // is safe to return from this function
    var frame_arr_dims = [_]usize{
        num_time,
        num_fields,
        camera.pixels_num[1],
        camera.pixels_num[0],
    };

    // We are going to return this so we use the input allocator instead of
    // the arena. It also owns the memory slice we just allocated.
    var frame_arr = try NDArray(f64).init(allocator, frame_arr_mem, frame_arr_dims[0..]);

    const image_stride: usize = frame_arr.strides[0];
    var image_idxs = [_]usize{ 0, 0, 0, 0 }; // frame,field,px_y,px_x
    var field_idxs = [_]usize{ 0, 0, 0 }; // field,px_y_px_x

    var time_start = Timestamp.now(io, .awake);
    var time_end = Timestamp.now(io, .awake);
    var time_raster: f64 = 0.0;

    var name_buff: [1024]u8 = undefined;

    print("Starting rastering frames.\n", .{});

    for (0..num_time) |tt| {
        time_start = Timestamp.now(io, .awake);

        image_idxs[0] = tt;
        const start_idx = frame_arr.getFlatIdx(image_idxs[0..]);
        const end_idx = start_idx + image_stride;

        const images_mem = frame_arr.slice[start_idx..end_idx];
        // This is only temporary so we use our arena - the slice belongs to
        // the larger NDArray we will return which is on the input allocator
        var images_arr = try NDArray(f64).init(arena_alloc, images_mem, frame_arr_dims[1..]);

        // This will create it's own arena for temporary storage so we pass
        // through the input allocator for this.
        try rasterOneFrame(allocator, io, tt, coords, connect, field, camera, &images_arr);

        for (0..num_fields) |ff| {
            const file_name = try std.fmt.bufPrint(name_buff[0..], "raster_all_field{d}_frame{d}", .{ ff, tt });

            field_idxs[0] = ff;
            const field_slice = images_arr.getSlice(field_idxs[0..], 0);

            const image_mat = MatSlice(f64).init(field_slice, camera.pixels_num[1], camera.pixels_num[0]);

            try iio.saveImage(io, out_dir, file_name, &image_mat, .csv, 8);
            try iio.saveImage(io, out_dir, file_name, &image_mat, .ppm, 8);
        }

        time_end = Timestamp.now(io, .awake);
        time_raster = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

        print("Frame {}, raster time = {d:.3}ms\n", .{ tt, time_raster / time.ns_per_ms });
    }

    print("Rastering complete.\n\n", .{});

    return frame_arr;
}
