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


pub fn Vec3OfSlices(comptime T: type) type {
    return struct{
        x: []T,
        y: []T,
        z: []T,
    };   
}

pub fn loadVec3SlicesFromElemArray(comptime N: usize,
                                   comptime T: type, 
                                   elem_array: *const NDArray(T),
                                   elem_ind: usize) !Vec3OfSlices(T) {

    var start_slice: usize = try elem_array.getFlatInd(&[_]usize{elem_ind,0,0});
    // if coords then stride=3, if fields then stride=fields_num
    const stride: usize = elem_array.strides[1];  

    const x_slice = elem_array.elems[start_slice..start_slice+N];
    start_slice += stride;
    const y_slice = elem_array.elems[start_slice..start_slice+N];
    start_slice += stride;
    const z_slice = elem_array.elems[start_slice..start_slice+N];

    return Vec3OfSlices(T){
        .x = x_slice,
        .y = y_slice,
        .z = z_slice,
    };
}


pub fn rasterOneFrame(allocator: std.mem.Allocator, 
                      frame_ind: usize, 
                      coords: *const Coords, 
                      connect: *const Connect, 
                      field: *const Field, 
                      camera: *const Camera, 
                      image_out_arr: *NDArray(f64),
                      ) !void {

    const raster_start = try Instant.now();
    
    _ = frame_ind;
    _ = field;
    _ = image_out_arr;

    const N: usize = 3; // Set to nodes per elem 
    // SIMD lanes for batching bounding boxes of u16 - should be 32 for AVX-512
    //const L: usize = 16; 
    //print("DEBUG\n",.{});

    
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
    
    // DEBUG:
    // print("\n",.{});
    // print("elem_coord_arr:\n",.{});
    // print("    dims=[{d},{d},{d}]\n",
    //       .{elem_coord_arr.dims[0],elem_coord_arr.dims[1],elem_coord_arr.dims[2]});
    // print("    strides=[{d},{d},{d}]\n",
    //       .{elem_coord_arr.strides[0],elem_coord_arr.strides[1],elem_coord_arr.strides[2]});
    // print("\n",.{});

    //-----------------------------------------------------------------------------------------
    // World to Raster Coords - SIMD
        
    time_start = try Instant.now();
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N,f64) = try vsd.loadVec3SIMDFromElemArray(
            N,f64,&elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,f64) = rops.worldToRasterSIMD(
            N,f64,coords_world,camera); 

        try vsd.saveVec3SIMDToElemArray(N,f64,&elem_coord_arr,ee,coords_raster);
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
    // Extract Element Bounding Boxes
    elem_inds = .{0,0,0}; 

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);
    var elems_in_image: usize = 0;
                
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3SIMD(N,f64) = try vsd.loadVec3SIMDFromElemArray(
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

        elem_bboxes[elems_in_image] = BBox{
            .elem_ind = ee,
            .x_min = x_min_i,
            .x_max = x_max_i,
            .y_min = y_min_i,
            .y_max = y_max_i,
        };

        elems_in_image += 1;

        // DEBUG:
        // print("ELEMENT: {d}\n",.{ee});
        // print("x_min_f={d:.2} , x_max_f={d:.2}, x_min_i={d}, x_max_i={d}\n",
        //       .{x_min,x_max,x_min_i,x_max_i});
        // print("y_min_f={d:.2} , y_max_f={d:.2}, y_min_i={d}, y_max_i={d}\n",
        //       .{y_min,y_max,y_min_i,y_max_i});
        // print("\n",.{});
    }

    //----------------------------------------------------------------------------------
    // Element Tile Overlap COUNT: Pass 1, How many element in each tile? 
    // - Need this to alloc for our overlapping bounding boxes
    // - Do this over elements as mesh is sparse and elements only overlap a few tiles on 
    //  average, therefore elements should be the outer loop
    // - Run this single threaded for low mesh counts

    const tile_size: u16 = 16;
    const tiles_num_x: usize = try std.math.divCeil(usize,camera.pixels_num[0],tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize,camera.pixels_num[1],tile_size);
    const tiles_num: usize = tiles_num_x*tiles_num_y;    

    // TODO: does this need to be a slice of usize?
    const tile_elem_counts: []usize = try arena_alloc.alloc(usize,tiles_num);
    @memset(tile_elem_counts,0);

    for (0..elems_in_image) |ee| {
        const tile_ind_min_x: u16 = elem_bboxes[ee].x_min / tile_size;
        const tile_ind_max_x: u16 = try std.math.divCeil(u16,elem_bboxes[ee].x_max,tile_size);
        const tile_ind_min_y: u16 = elem_bboxes[ee].y_min / tile_size;
        const tile_ind_max_y: u16 = try std.math.divCeil(u16,elem_bboxes[ee].y_max,tile_size);

        for (tile_ind_min_y..tile_ind_max_y) |ty| {
            const tile_row_offset: usize = ty * tiles_num_x;
            
            for (tile_ind_min_x..tile_ind_max_x) |tx| {
                const tile_ind_flat: usize = tile_row_offset + tx;

                tile_elem_counts[tile_ind_flat] += 1;
                
            }
        }
    }

    // DEBUG:
//     print("TILES:\n    tile_size={d}, tiles_num_x={d}, tiles_num_y={d}, tiles_num={}\n\n",
//           .{tile_size,tiles_num_x,tiles_num_y,tiles_num});
// 
//     for (0..tiles_num_y) |ty| {
//         const tile_row_offset: usize = ty * tiles_num_x;
//         for (0..tiles_num_x) |tx| {
//             const tile_ind: usize = tile_row_offset + tx;
//             print("TILE: ty={d}, tx={d}, TILE COUNT={}\n",
//                   .{tx,ty,tile_elem_counts[tile_ind]});
//         }
//     }
//     print("\n",.{});

    //-----------------------------------------------------------------------------------------
    // Element Tile Overlap, Pass 2: Store overlap bounding boxes for ACTIVE tiles only.
    // Coarse, bounding box overlap based raster. Assumes a sparse mesh with each element 
    // touching ~5 tiles.
    
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    // Count the active tiles and work out the write offsets into the overlap boxes
    const tile_write_inds: []usize = try arena_alloc.alloc(usize,tiles_num); 
    var current_offset: usize = 0;
    var num_active_tiles: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
        tile_write_inds[ii] = current_offset;
        current_offset += cc;
        if (cc > 0) {
            num_active_tiles += 1;            
        }
    }

    const overlap_total: usize = sliceops.sum(usize,tile_elem_counts);
    const overlap_bboxes: []BBox = try arena_alloc.alloc(BBox,overlap_total);

    const ActiveTile = struct {
        overlap_start: usize, // index into overlap_bboxes
        overlap_count: usize, // count to take from overlap bboxes
        flat_ind: usize,
        x_px_min: u16,
        y_px_min: u16,
    };

    // Main raster loop will only need to analyse active tiles
    const active_tiles: []ActiveTile = try arena_alloc.alloc(ActiveTile,num_active_tiles);

    var active_ind: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
    
        if (cc > 0) {
            const tx = @as(u16, @intCast(ii % tiles_num_x));
            const ty = @as(u16, @intCast(ii / tiles_num_x));
        
            active_tiles[active_ind] = ActiveTile{
                .overlap_start = tile_write_inds[ii],
                .overlap_count = cc,
                .flat_ind = ii,
                .x_px_min = tx*tile_size,
                .y_px_min = ty*tile_size,
            };
            active_ind += 1;      
        }
    }

    // TODO
    // NOTE: only loops over elements in image so ee is not the element number for coord data
    // in the NDArray!    
    for (0..elems_in_image) |ee| {
        const tile_ind_min_x: u16 = elem_bboxes[ee].x_min / tile_size;
        const tile_ind_min_y: u16 = elem_bboxes[ee].y_min / tile_size;
        
        // No 'try' divCeil
        const tile_ind_max_x = @min(@as(u16, @intCast(tiles_num_x)),
            (elem_bboxes[ee].x_max + tile_size - 1) / tile_size);
        const tile_ind_max_y = @min(@as(u16, @intCast(tiles_num_y)),
            (elem_bboxes[ee].y_max + tile_size - 1) / tile_size);

        for (tile_ind_min_y..tile_ind_max_y) |ty| {
            const tile_row_offset: usize = ty * tiles_num_x;

            const tile_px_min_y: u16 = @as(u16,@intCast(ty*tile_size));
            const tile_px_max_y: u16 = @as(u16,@min(tile_px_min_y+tile_size,screen_px_y));

            const overlap_y_min = @max(elem_bboxes[ee].y_min, tile_px_min_y);
            const overlap_y_max = @min(elem_bboxes[ee].y_max, tile_px_max_y);

            for (tile_ind_min_x..tile_ind_max_x) |tx| {
                
                const tile_px_min_x: u16 = @as(u16,@intCast(tx*tile_size));
                const tile_px_max_x: u16 = @as(u16,@min(tile_px_min_x+tile_size,screen_px_x));

                const tile_ind_flat: usize = tile_row_offset + tx;
                const write_ind = tile_write_inds[tile_ind_flat]; 
                tile_write_inds[tile_ind_flat] += 1;

                overlap_bboxes[write_ind] = BBox{
                    .elem_ind = elem_bboxes[ee].elem_ind,
                    .x_min = @max(elem_bboxes[ee].x_min,tile_px_min_x),
                    .x_max = @min(elem_bboxes[ee].x_max,tile_px_max_x),
                    .y_min = overlap_y_min,
                    .y_max = overlap_y_max,
                };  
            }
        }
    }

    //-----------------------------------------------------------------------------------------
    // Raster Loop, pass 3: Loop over ACTIVE tiles and check corners

    const sub_sample: usize = @intCast(camera.sub_sample);
    const subpx_tile_size: usize = tile_size * sub_sample;
    const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;
    //const sub_step: f64 = 1.0 / @as(f64,@floatFromInt(sub_sample));
    const area_tol: f64 = 1e-9;
    
    const subpx_depth_scratch = try arena_alloc.alloc(f32, subpx_tile_total);
    const subpx_image_scratch = try arena_alloc.alloc(f64, subpx_tile_total);

    // TODO: thread this for large images and large meshes 
    // NOTE: this loop only works for linear triangles! It uses barycentric interpolation
    for (active_tiles) |tile| {
        @memset(subpx_depth_scratch, std.math.inf(f32));
        @memset(subpx_image_scratch, 0.0);

        const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
                                                tile.overlap_start + tile.overlap_count];

        

        for (overlaps) |overlap| {
            const nodes: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
                N,f64,&elem_coord_arr,overlap.elem_ind
            );

            // vert_2 = [2]
            // vert_1 = [1]
            // vert_0 = [0]
            // .get(0) = x
            // .get(1) = y
            // .get(2) = z
            // const area: f64 = ((vert_2.get(0) - vert_0.get(0)) 
            //                  * (vert_1.get(1) - vert_0.get(1)) 
            //                  - (vert_2.get(1) - vert_0.get(1)) 
            //                  * (vert_1.get(0) - vert_0.get(0)));
            const elem_area: f64 = ((nodes.x[2] - nodes.x[0]) 
                                  * (nodes.y[1] - nodes.y[0]) 
                                  - (nodes.y[2] - nodes.y[0]) 
                                  * (nodes.x[1] - nodes.x[0]));

            print("{d} ELEM AREA : {d:.4}\n",.{overlap.elem_ind,elem_area});           
            // Backface culling
            if (elem_area < area_tol) {
                continue;
            }
        } 

        // Average over the subpixels and write to image_out  
    }


    //-----------------------------------------------------------------------------------------
    // Write tile buffer -> image out buffer
    
    //-----------------------------------------------------------------------------------------
    const raster_end = try Instant.now();
    const time_raster: f64 = @floatFromInt(raster_end.since(raster_start));
    print("\nTOTAL TIME RASTER = {d}ns\n",.{time_raster});    
}
                      
