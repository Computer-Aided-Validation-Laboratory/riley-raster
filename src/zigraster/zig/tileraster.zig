const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Instant = time.Instant;

const vecstack = @import("vecstack.zig");
const Vec3T = @import("vecstack.zig").Vec3T;
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

const rops = @import("rasterops.zig");
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;


pub fn BBoxSIMD(comptime L: usize) type {
    return struct {
        elem_ind: @Vector(L,usize),
        x_min: @Vector(L,u16),
        x_max: @Vector(L,u16),
        y_min: @Vector(L,u16),
        y_max: @Vector(L,u16),    
    };
} 

const BBox = struct {
    elem_ind: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub fn initElemArray(comptime T: type,
                     allocator: std.mem.Allocator,
                     dim0: usize, 
                     dim1: usize, 
                     dim2: usize) !NDArray(T) {
    var elem_arr_dims = [_]usize{dim0,dim1,dim2};
    const elem_arr_size: usize = dim0*dim1*dim2;
    const elem_arr_mem = try allocator.alloc(T, elem_arr_size);
    @memset(elem_arr_mem,0.0);
    const elem_arr = try NDArray(T).init(allocator, 
                                             elem_arr_mem, 
                                             elem_arr_dims[0..]);
    return elem_arr;
}

pub fn fillElemCoords(coords: *const Coords, 
                      connect: *const Connect,
                      dim_elem: usize,
                      dim_node: usize,
                      dim_field: usize,
                      elem_array: *NDArray(f64),
                      ) !void {
    var elem_inds = [_]usize{0,0,0};

    for (0..elem_array.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_array.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;
                                
            elem_inds[dim_field] = 0;            
            try elem_array.set(elem_inds[0..],coords.x[coord_inds[nn]]);
            elem_inds[dim_field] = 1;            
            try elem_array.set(elem_inds[0..],coords.y[coord_inds[nn]]);
            elem_inds[dim_field] = 2;            
            try elem_array.set(elem_inds[0..],coords.z[coord_inds[nn]]);
            
        } 
    }    
}

pub fn rasterOneFrame(allocator: std.mem.Allocator, 
                      frame_ind: usize, 
                      coords: *const Coords, 
                      connect: *const Connect, 
                      field: *const Field, 
                      camera: *const Camera, 
                      image_out_arr: *NDArray(f64),
                      ) !void {
    _ = frame_ind;
    _ = field;
    _ = image_out_arr;

    const N: usize = 3; // Set to nodes per elem 
    // SIMD lanes for batching bounding boxes of u16 - should be 32 for AVX-512
    const L: usize = 16; 

    print("DEBUG\n",.{});

    var time_start = try Instant.now();
    var time_end = try Instant.now();
    
    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // **ELEMENT WISE PRE-TRANSFORM**
    
    const elems_num: usize = connect.elem_n;
    const nodes_per_elem: usize = connect.nodes_per_elem;
    const coords_num: usize = 3;
    //const fields_num: usize = field.getFieldsN();

    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    const dim_elem: usize = 0; 
    const dim_field: usize = 1;
    const dim_node: usize = 2;
    var elem_coord_arr = try initElemArray(f64,
                                                arena_alloc,
                                                elems_num,
                                                coords_num,
                                                nodes_per_elem);
    try fillElemCoords(coords,connect,dim_elem,dim_node,dim_field,&elem_coord_arr);
    var elem_inds = [_]usize{0,0,0};
    
 
    print("\n",.{});
    print("elem_coord_arr:\n",.{});
    print("    dims=[{d},{d},{d}]\n",
          .{elem_coord_arr.dims[0],elem_coord_arr.dims[1],elem_coord_arr.dims[2]});
    print("    strides=[{d},{d},{d}]\n",
          .{elem_coord_arr.strides[0],elem_coord_arr.strides[1],elem_coord_arr.strides[2]});
    print("\n",.{});

    //-----------------------------------------------------------------------------------------
    // World to Raster Coords - SIMD
        
    time_start = try Instant.now();
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N,f64) = try vsd.loadVec3FromElemArray(
            N,f64,&elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,f64) = rops.worldToRasterSIMD(
            N,f64,coords_world,camera); 

        try vsd.saveVec3ToElemArray(N,f64,&elem_coord_arr,ee,coords_raster);
    }
    time_end = try Instant.now();
    const time_simd: f64 = @floatFromInt(time_end.since(time_start));
    print("\nTIME SIMD WORLD TO RASTER = {d}ns\n",.{time_simd});

    // DEBUG: print element raster coords in screen space for debugging
    // elem_inds = .{0,0,0};
    // for (0..elems_num) |ee| {
    //     elem_inds[dim_elem] = ee;
    //     print("Element: {d}\n",.{ee});
    //     for (0..nodes_per_elem) |nn| {
    //         elem_inds[dim_node] = nn;
    //         print("Node={d}, [",.{nn});
    //         for (0..coords_num) |cc| {
    //             elem_inds[dim_field] = cc;
    //             const val = try elem_coord_arr.get(elem_inds[0..]);
    //              print("{d},",.{val});
    //         }
    //         print("]\n",.{});
    //     }
    //     print("\n",.{});
    // }
    // print("\nTIME SIMD WORLD TO RASTER = {d}ns\n",.{time_simd}); 
    
    //-----------------------------------------------------------------------------------------
    // Element Bounding Boxes
    elem_inds = .{0,0,0}; 

    const num_bbox_simd: usize = try std.math.divCeil(usize,elem_coord_arr.dims[0],L);
    const elem_boxes_simd: []BBoxSIMD(L) = try arena_alloc.alloc(BBoxSIMD(L),num_bbox_simd);
    
    var elem_ind_buff = [_]usize{0} ** L;
    var x_max_buff = [_]u16{0} ** L;
    var x_min_buff = [_]u16{0} ** L;
    var y_max_buff = [_]u16{0} ** L;
    var y_min_buff = [_]u16{0} ** L;

    var simd_lane_count: u8 = 0;
    var simd_elem_box_count: usize = 0;
    var elems_in_image: usize = 0;
                
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3SIMD(N,f64) = try vsd.loadVec3FromElemArray(
            N,f64,&elem_coord_arr,ee);

        const x_max: f64 = @reduce(.Max,coords_raster.x);
        const x_min: f64 = @reduce(.Min,coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        const y_max: f64 = @reduce(.Max,coords_raster.y);
        const y_min: f64 = @reduce(.Min,coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }
        
        const x_min_i: u16 = rops.boundIndMin(u16,x_min);
        const x_max_i: u16 = rops.boundIndMax(u16,
                                              x_max, 
                                              @intCast(camera.pixels_num[0]));
        const y_min_i: u16 = rops.boundIndMin(u16,y_min);
        const y_max_i: u16 = rops.boundIndMax(u16,
                                              y_max, 
                                              @intCast(camera.pixels_num[1]));

        elem_ind_buff[simd_lane_count] = ee;
        x_min_buff[simd_lane_count] = x_min_i;
        x_max_buff[simd_lane_count] = x_max_i;
        y_min_buff[simd_lane_count] = y_min_i;
        y_max_buff[simd_lane_count] = y_max_i;
        simd_lane_count += 1;
        
        if (simd_lane_count == L) {
            elem_boxes_simd[simd_elem_box_count] = BBoxSIMD(L){
                .elem_ind = elem_ind_buff,
                .x_min = x_min_buff,
                .x_max = x_max_buff,
                .y_min = y_min_buff,
                .y_max = y_max_buff,
            };
            
            print("ELEMENT BATCH: {d}:\n",.{simd_elem_box_count});
            print("elem_inds={}\n",.{elem_boxes_simd[simd_elem_box_count].elem_ind});
            print("x_min={}\n",.{elem_boxes_simd[simd_elem_box_count].x_min});
            print("x_max={}\n",.{elem_boxes_simd[simd_elem_box_count].x_max});
            print("y_min={}\n",.{elem_boxes_simd[simd_elem_box_count].y_min});
            print("y_max={}\n",.{elem_boxes_simd[simd_elem_box_count].y_max});
            print("\n",.{});           
            
            simd_lane_count = 0;
            simd_elem_box_count += 1;
        }
        elems_in_image += 1;
 
        // print("Element: {d}\n",.{ee});
        // print("x_min_f={d:.2} , x_max_f={d:.2}, x_min_i={d}, x_max_i={d}\n",
        //       .{x_min,x_max,x_min_i,x_max_i});
        // print("y_min_f={d:.2} , y_max_f={d:.2}, y_min_i={d}, y_max_i={d}\n",
        //       .{y_min,y_max,y_min_i,y_max_i});
        // print("\n",.{});

    }

    // Fill the tail if we don't evenly divide L into our bounding boxes
    if (simd_lane_count != 0) {
        // Fill the tail with values that won't ruin AABB checks
        while (simd_lane_count < L) : (simd_lane_count += 1) {
            elem_ind_buff[simd_lane_count] = std.math.maxInt(usize); 
            x_min_buff[simd_lane_count] = std.math.maxInt(u16);
            x_max_buff[simd_lane_count] = 0;
            y_min_buff[simd_lane_count] = std.math.maxInt(u16);
            y_max_buff[simd_lane_count] = 0;
        }

        elem_boxes_simd[simd_elem_box_count] = BBoxSIMD(L){
             .elem_ind = elem_ind_buff,
             .x_min = x_min_buff,
             .x_max = x_max_buff,
             .y_min = y_min_buff,
             .y_max = y_max_buff,
         }; 

         simd_elem_box_count += 1;
    }

    //----------------------------------------------------------------------------------
    // Element Tile Overlap Sort: Pass 1, How many element in each tile? 
    //const sub_px_num_x: usize = camera.pixels_num[0]*camera.sub_sample; 
    //const sub_px_num_y: usize = camera.pixels_num[1]*camera.sub_sample;

    // flat_ind = (rr * num_cols) + cc, flat_ind = (yy * num_x) + xx, (y,x)
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));
    const tile_size: usize = 16;
    const tiles_num_x: usize = try std.math.divCeil(usize,camera.pixels_num[0],tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize,camera.pixels_num[1],tile_size);
    const tiles_num: usize = tiles_num_x*tiles_num_y;    

     print("Tiles:\n    tile_size={d}, tiles_num_x={d}, tiles_num_y={d}, tiles_num={}\n\n",
          .{tile_size,tiles_num_x,tiles_num_y,tiles_num});

    for (0..tiles_num_y) |ty| {
        const start_px_y: u16 = @as(u16,@intCast(ty*tile_size));
        const end_px_y: u16 = @as(u16,@min(start_px_y+tile_size,screen_px_y));
        
        for (0..tiles_num_x) |tx| {
            const start_px_x: u16 = @as(u16,@intCast(tx*tile_size)); 
            const end_px_x: u16 = @as(u16,@min(start_px_x+tile_size,screen_px_x));

            print("TILE: ty={d}, tx={d}\n",.{tx,ty});
            print("start_y={d}, end_y={d}\n",.{start_px_y,end_px_y});
            print("start_x={d}, end_x={d}\n",.{start_px_x,end_px_x});
            print("\n",.{});
             
        }
    }

    // - Loop over element bounding boxes
    //  - If on screen work out which tile it overlaps and increment the count for that tile
    // Need to allocate a slice of memory to store the `tile_counts`

    // const tile_counts: []u16 = allocator.alloc(u16,tiles_num); 
    // for (0..elems_in_image) |ee| {
    //     for (0..tiles_num) |tt| {
    //         
    //     }
    // }

    // Needs to be allocate because we could have a high res camera with 1000s of tiles
    // const tile_elem_counts: []usize = try alloc.alloc(usize,tiles_num); 

    //-----------------------------------------------------------------------------------------
    // **TILE SPLIT**

    // TODO
    // - **BACK FACE CULLING**
    // - Project all elements onto screen space
    // - Work out which elements are in which tile and allocate a buffer to store this
    // - Need bounding boxes of all elements, bounding boxes of all tiles

// 
//     print("\n",.{});
//     print("Camera:\n    pixels_x={d}, pixels_y={d}\n",
//           .{camera.pixels_num[0],camera.pixels_num[1]});
//     print("    sub_sample={}, sub_pixels_x={d}, sub_pixels_y={d}\n\n",
//           .{camera.sub_sample,sub_px_num_x,sub_px_num_y});

    // **LOOP** over elements, calculate raster coords and crop
    //const cam_px_x_f = @as(f64, @floatFromInt(camera.pixels_num[0] - 1));
    //const cam_px_y_f = @as(f64, @floatFromInt(camera.pixels_num[1] - 1));
}
                      
