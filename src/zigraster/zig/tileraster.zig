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

const ActiveTile = struct {
    overlap_start: usize, // index into overlap_bboxes
    overlap_count: usize, // count to take from overlap bboxes
    flat_ind: usize,
    x_px_min: u16,
    y_px_min: u16,
};

pub inline fn edgeFun3Slices(comptime ind0: usize, 
                             comptime ind1: usize,
                             comptime ind2: usize,
                             x: []f64, 
                             y: []f64) f64 {
    return ((x[ind2] - x[ind0]) * (y[ind1] - y[ind0]) 
          - (y[ind2] - y[ind0]) * (x[ind1] - x[ind0]));
}

pub inline fn edgeFun3(x0: f64, y0: f64,
                       x1: f64, y1: f64,
                       x2: f64, y2: f64) f64 {
    return ((x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0));
}

pub inline fn flatInd2D(yy: usize, xx: usize, xx_len: usize) usize {
    return yy*xx_len + xx;
}

//---------------------------------------------------------------------------------------------
// NOTES:
// - Should calculate world->raster coords before transforming to NDArray
//      - NO! Coords is currently slices of x then slice of y = poor locality, extra work of
//        repeatedly transforming elements is offset by SIMD and threading ability after 
//        transform. 
// - Calculating element area in the raster loop, probably should do backface culling before
//      - YES, can probably do this before storing the overlapping bounding boxes
//
// NOTE: 
// NOW: image_out_arr.dims=(num_fields,num_px_y,num_px_x)
// EVENTUALLY: image_out_arr.dims=(num_frames,num_fields,num_px_y,num_px_x)
pub fn rasterOneFrame(allocator: std.mem.Allocator, 
                      frame_ind: usize, 
                      coords: *const Coords, 
                      connect: *const Connect, 
                      field: *const Field, 
                      camera: *const Camera, 
                      image_out_arr: *NDArray(f64),
                      ) !void {

    const raster_start = try Instant.now();
    
    //_ = frame_ind;
    _ = field;
    //_ = image_out_arr;

    const N: usize = 3; // Set to nodes per elem 
    // SIMD lanes for batching bounding boxes of u16 - should be 32 for AVX-512
    
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

    // TODO: 
    // - Add backface culling for higher order elements, performant and accurate:
    //     - Check normals at far corners, if they are all strongly backfacing discard
    //     - Then do normal check inside raster loop at hit location after Newton iterations
    //     - Note need to do the Z divide
    elem_inds = .{0,0,0}; 

    const elem_bboxes: []BBox = try arena_alloc.alloc(BBox,elems_num);
    var elems_in_image: usize = 0;
    const area_tol: f64 = 1e-9;
                
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
            N,f64,&elem_coord_arr,ee
        );

        // Width (X) on screen check and crop
        const x_max: f64 = std.mem.max(f64,coords_raster.x);
        const x_min: f64 = std.mem.min(f64,coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        // Height (Y) on on screen check and crop
        const y_max: f64 = std.mem.max(f64,coords_raster.y);
        const y_min: f64 = std.mem.min(f64,coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }

        // Backface culling, negative area = crop for linear triangles
        const elem_area: f64 = edgeFun3Slices(0,1,2,coords_raster.x,coords_raster.y);
        //print("{d} ELEM AREA : {d:.4}\n",.{ee,elem_area});           
        
        if (elem_area < area_tol) {
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

    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = tile_size * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;
    
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    const spx_offset: f64 = 1.0 / (2.0 * sub_samp_f);
    
    const spx_inv_z_scratch = try arena_alloc.alloc(f64, spx_tile_total);
    const spx_image_scratch = try arena_alloc.alloc(f64, spx_tile_total);

    //const raster_tol = 1e-9;

    //-----------------------------------------------------------------------------------------
    // TODO: thread this for large images and large meshes 
    // NOTE: this loop only works for linear triangles! It uses barycentric interpolation

    // DEBUG
    const spx_image_size = camera.pixels_num[1]*sub_samp*camera.pixels_num[0]*sub_samp;
    const spx_image_buff = try arena_alloc.alloc(f64, spx_image_size);
    @memset(spx_image_buff,0.0);
    var spx_image = try MatSlice(f64).init(spx_image_buff,
                                          camera.pixels_num[1]*sub_samp,
                                          camera.pixels_num[0]*sub_samp);


    //=========================================================================================
    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch, 0.0);

        const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
                                                tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        var nodes_weight: [N]f64 = undefined;
        
        for (overlaps) |overlap| {
            const nodes_rast: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
                N,f64,&elem_coord_arr,overlap.elem_ind
            );

            for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            }

            const inv_elem_area: f64 = 1.0 / edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
                                                      nodes_rast.x[1],nodes_rast.y[1],
                                                      nodes_rast.x[2],nodes_rast.y[2]);

            const scratch_start_ind_x: usize = sub_samp
                * (@as(usize,overlap.x_min) - tile.x_px_min);  
            const scratch_end_ind_x: usize = sub_samp
                * (@as(usize,overlap.x_max) - tile.x_px_min);
            const scratch_start_ind_y: usize = sub_samp
                * (@as(usize,overlap.y_min) - tile.y_px_min);  
            const scratch_end_ind_y: usize = sub_samp
                * (@as(usize,overlap.y_max) - tile.y_px_min);

            const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
            const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));

            var spx_coord_x: f64 = xi_min_f + spx_offset;
            var spx_coord_y: f64 = yi_min_f + spx_offset;

            //--------------------------------------------------------------------------------
            // RASTER HOT LOOP
            for (scratch_start_ind_y .. scratch_end_ind_y) |yy| {

                const spx_image_iy: usize = tile.y_px_min*sub_samp + yy;
                const scratch_row_offset: usize = yy * spx_tile_size;

                spx_coord_x = xi_min_f + spx_offset;
                
                for (scratch_start_ind_x .. scratch_end_ind_x) |xx| {

                    // NOTE: not a weight until mult by inv area! Only used for edge check
                    nodes_weight[0] = edgeFun3(nodes_rast.x[1],nodes_rast.y[1],
                                               nodes_rast.x[2],nodes_rast.y[2],
                                               spx_coord_x,spx_coord_y);
                    nodes_weight[1] = edgeFun3(nodes_rast.x[2],nodes_rast.y[2],
                                               nodes_rast.x[0],nodes_rast.y[0],
                                               spx_coord_x,spx_coord_y);
                    nodes_weight[2] = edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
                                               nodes_rast.x[1],nodes_rast.y[1],
                                               spx_coord_x,spx_coord_y);

                    const spx_image_ix: usize = tile.x_px_min*sub_samp + xx;
                    const scratch_flat_ind: usize = scratch_row_offset + xx;

                    if (nodes_weight[0] >= 0.0 and 
                        nodes_weight[1] >= 0.0 and 
                        nodes_weight[2] >= 0.0){

                        // NOTE: now it is a weight
                        for (0..N) |nn| {
                            nodes_weight[nn] = nodes_weight[nn] * inv_elem_area;
                        }

                        // Perspective correct interpolation to get the inverse of the z
                        var spx_inv_z: f64 = 0.0;
                        for (0..N) |nn| {
                            spx_inv_z += nodes_weight[nn] * nodes_inv_z[nn];
                        }

                        // INV DEPTH CHECK: 
                        // 1/large number = far away = approach 0, far away = LESS THAN
                        // 1/small number = closer = approach inf, close = GREATER THAN
                        if (spx_inv_z > spx_inv_z_scratch[scratch_flat_ind]) {
                            const spx_z: f64 = 1/spx_inv_z; 

                            spx_inv_z_scratch[scratch_flat_ind] = spx_inv_z;           
                            spx_image_scratch[scratch_flat_ind] = spx_z;
                            
                            spx_image.set(spx_image_iy,spx_image_ix,spx_z);
                        }
                    } 
                    spx_coord_x += spx_step;           
                } // LOOP subpx x            
                spx_coord_y += spx_step;
            } // LOOP subpx y    
        } // LOOP overlapping elems / boxes

        // Average and push into main image buffer
        const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
        for (0..tile_size) |ty| { 
            const image_px_y: usize = tile.y_px_min + ty;
            const spx_start_y: usize = sub_samp * ty;
            
            for (0..tile_size) |tx| {
                const image_px_x: usize = tile.x_px_min + tx;
                const spx_start_x: usize = sub_samp * tx;
                
                var px_sum: f64 = 0.0;
                        
                for (0..sub_samp) |sy| { // Index into scratch
                    const scratch_row_offset: usize = (spx_start_y + sy) 
                                                     * spx_tile_size;  
                        
                    for (0..sub_samp) |sx| {
                        const scratch_flat_ind: usize = scratch_row_offset+spx_start_x+sx;
                        px_sum += spx_image_scratch[scratch_flat_ind];
                    } // AVG LOOP: sub samp x
                } // AVG LOOP: sub samp y

                for (0..3) |ff| {
                    const image_inds = [_]usize{ff,image_px_y,image_px_x};
                    try image_out_arr.set(image_inds[0..], px_sum*inv_sub_samp_sq);
                }
            } // AVG LOOP: tile x
        } // AVG LOOP: tile y        
                   
    } // LOOP active tiles
                                              
    //=========================================================================================
    // OPTIMISED EDGE FUNCTION
//     for (active_tiles) |tile| {
//         @memset(subpx_z_inv_scratch, 0.0);
//         @memset(subpx_image_scratch, 0.0);
// 
//         const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
//                                                 tile.overlap_start + tile.overlap_count];
// 
//         var inv_z: [3]f64 = undefined;
//         
//         for (overlaps) |overlap| {
//             const nodes: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
//                 N,f64,&elem_coord_arr,overlap.elem_ind
//             );
// 
//             for (0..3) |nn| {
//                 inv_z[nn] = 1.0 / nodes.z[nn];
//             }
// 
//             const inv_elem_area: f64 = 1.0 / edgeFun3(nodes.x[0],nodes.y[0],
//                                                       nodes.x[1],nodes.y[1],
//                                                       nodes.x[2],nodes.y[2]);
//             const inv_area_step: f64 = inv_elem_area * subpx_step;
// 
//             const dw0_dx = (nodes.y[1] - nodes.y[2]) * inv_area_step;
//             const dw0_dy = (nodes.x[2] - nodes.x[1]) * inv_area_step;
//             const dw1_dx = (nodes.y[2] - nodes.y[0]) * inv_area_step;
//             const dw1_dy = (nodes.x[0] - nodes.x[2]) * inv_area_step;
//             const dw2_dx = (nodes.y[0] - nodes.y[1]) * inv_area_step;
//             const dw2_dy = (nodes.x[1] - nodes.x[0]) * inv_area_step;
// 
//             const dz_dx = (dw0_dx * inv_z[0] + dw1_dx * inv_z[1] + dw2_dx * inv_z[2]);
//             const dz_dy = (dw0_dy * inv_z[0] + dw1_dy * inv_z[1] + dw2_dy * inv_z[2]);
// 
//             const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
//             const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));
// 
//             const subpx_coord_x: f64 = xi_min_f + subpx_offset;
//             const subpx_coord_y: f64 = yi_min_f + subpx_offset;
// 
//             var w0_row_start: f64 = edgeFun3(nodes.x[1], nodes.y[1], 
//                                              nodes.x[2], nodes.y[2], 
//                                              subpx_coord_x, subpx_coord_y) * inv_elem_area;
//             var w1_row_start: f64 = edgeFun3(nodes.x[2], nodes.y[2], 
//                                              nodes.x[0], nodes.y[0], 
//                                              subpx_coord_x, subpx_coord_y) * inv_elem_area;
//             var w2_row_start: f64 = edgeFun3(nodes.x[0], nodes.y[0], 
//                                              nodes.x[1], nodes.y[1], 
//                                              subpx_coord_x, subpx_coord_y) * inv_elem_area;
//             var z_inv_row_start: f64  = (w0_row_start * inv_z[0] 
//                                        + w1_row_start * inv_z[1] 
//                                        + w2_row_start * inv_z[2]);
// 
//             const scratch_start_ind_x: usize = sub_samp
//                 * (@as(usize,overlap.x_min) - tile.x_px_min);  
//             const scratch_end_ind_x: usize = sub_samp
//                 * (@as(usize,overlap.x_max) - tile.x_px_min);
//             const scratch_start_ind_y: usize = sub_samp
//                 * (@as(usize,overlap.y_min) - tile.y_px_min);  
//             const scratch_end_ind_y: usize = sub_samp
//                 * (@as(usize,overlap.y_max) - tile.y_px_min);
//             //---------------------------------------------------------------------------------
//             // DEBUG
//             // print("tile_ind_start_x={}, tile_ind_start_y={}\n",
//             //       .{tile_ind_min_x,tile_ind_min_y});
//             // print("tile_px_start_x={}, tile_px_start_y={}\n",
//             //       .{tile_px_min_x,tile_px_min_y});
//             // print("overlap. elem_ind={}, px_x_min={}, px_y_min={} \n",
//             //       .{overlap.elem_ind,overlap.x_min,overlap.x_max});
//             // print("subpx_tile_size={}, subpx_tile_total={}\n",
//             //       .{subpx_tile_size,subpx_tile_total});
//             // print("scratch_start_x={}, scratch_end_x={}\n",
//             //       .{scratch_start_ind_x, scratch_end_ind_x});
//             // print("scratch_start_y={}, scratch_end_y={}\n",
//             //       .{scratch_start_ind_y, scratch_end_ind_y});
//             // const flat_start_x = flatInd2D(scratch_start_ind_y,
//             //                                scratch_start_ind_x,
//             //                                subpx_tile_size);
//             // const flat_end_x = flatInd2D(scratch_end_ind_y-1,
//             //                              scratch_end_ind_x,
//             //                              subpx_tile_size);
//             // print("scratch_flat_start_x={}, scratch_flat_end_x={}\n",
//             //       .{flat_start_x, flat_end_x});
//             // print("\n",.{});
// 
//             //---------------------------------------------------------------------------------
//             // RASTER HOT LOOP
//             for (scratch_start_ind_y .. scratch_end_ind_y) |yy| {
//                 const sp_image_iy: usize = tile.y_px_min*sub_samp + yy;
// 
//                 var w0_curr: f64 = w0_row_start;
//                 var w1_curr: f64 = w1_row_start;
//                 var w2_curr: f64 = w2_row_start;
//                 var z_inv_curr: f64 = z_inv_row_start;
// 
//                 const scratch_row_offset: usize = yy * subpx_tile_size;
//                 
//                 for (scratch_start_ind_x .. scratch_end_ind_x) |xx| {
//                     const sp_image_ix: usize = tile.x_px_min*sub_samp + xx;
//                     
//                     const scratch_flat_ind: usize = scratch_row_offset + xx;
// 
//                     if (w0_curr >= 0.0 and w1_curr >= 0.0 and w2_curr >= 0){
//                         if (z_inv_curr > subpx_z_inv_scratch[scratch_flat_ind]) {
//                             subpx_z_inv_scratch[scratch_flat_ind] = z_inv_curr;           
//                             subpx_image_scratch[scratch_flat_ind] = z_inv_curr;
// 
//                             sp_image.set(sp_image_iy,sp_image_ix,1/z_inv_curr);
//                         }
//                     }           
// 
//                     w0_curr += dw0_dx;
//                     w1_curr += dw1_dx;
//                     w2_curr += dw2_dx;
//                     z_inv_curr += dz_dx;        
//                 }
// 
//                 w0_row_start += dw0_dy;
//                 w1_row_start += dw1_dy;
//                 w2_row_start += dw2_dy;
//                 z_inv_row_start += dz_dy;
//             }   
//         } 
//         
//         // Average over the subpixels and write to image_out
//         const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
//         for (0..tile_size) |ty| { 
//             const image_px_y: usize = tile.y_px_min + ty;
//             const subpx_start_y: usize = sub_samp * ty;
//             
//             for (0..tile_size) |tx| {
//                 const image_px_x: usize = tile.x_px_min + tx;
//                 const subpx_start_x: usize = sub_samp * tx;
//                 
//                 var px_sum: f64 = 0.0;
//                         
//                 for (0..sub_samp) |sy| { // Index into scratch
//                     const scratch_row_offset: usize = (subpx_start_y + sy) 
//                                                        * subpx_tile_size;  
//                         
//                     for (0..sub_samp) |sx| {
//                         const scratch_flat_ind: usize = scratch_row_offset+subpx_start_x+sx;
//                         px_sum += subpx_image_scratch[scratch_flat_ind];
//                     }
//                 }
// 
//                 const image_inds = [_]usize{0,image_px_y,image_px_x};
//                 try image_out_arr.set(image_inds[0..], px_sum*inv_sub_samp_sq);
//                 
//             }
//         }          
//     }
    // OPTIMISED EDGE FUNCTION
    //-----------------------------------------------------------------------------------------

    //-----------------------------------------------------------------------------------------
    // DEBUG: Save
    var single_thread_io: std.Io.Threaded = .init_single_threaded;
    const io = single_thread_io.io();

    const cwd: std.Io.Dir = std.Io.Dir.cwd();        

    const dir_name = "raster-test";
    var name_buff: [1024]u8 = undefined;
    
    cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Path exists do nothing
        else => return err, // Propagate any other error
    };
    
    var out_dir: std.Io.Dir = try cwd.openDir(io, dir_name, .{});
    defer out_dir.close(io);

    const file_name = try std.fmt.bufPrint(name_buff[0..], 
                                           "tile_depth_frame{d}", 
                                           .{ frame_ind });
    try rops.saveImage(io, out_dir, file_name, &spx_image, .ppm);
    try rops.saveImage(io, out_dir, file_name, &spx_image, .csv);

    //-----------------------------------------------------------------------------------------
    const raster_end = try Instant.now();
    const time_raster: f64 = @floatFromInt(raster_end.since(raster_start));
    print("\nTOTAL TIME RASTER = {d}ns\n",.{time_raster});    
}
