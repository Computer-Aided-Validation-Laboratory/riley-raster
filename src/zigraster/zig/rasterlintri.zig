const std = @import("std");
const print = std.debug.print;
const time = std.time;

const Camera = @import("camera.zig").Camera;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;


pub fn countElemsCalcBBoxes(camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            elem_bboxes: []BBox) !usize {

    const N: usize = 3;
    const area_tol: f64 = -1e-9;
    
    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N,f64,elem_coord_arr,ee
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
        const elem_area: f64 = rops.edgeFun3Slices(0,1,2,coords_raster.x,coords_raster.y);
        
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
    }

    return elems_in_image;
}

pub fn rasterElems(
    allocator: std.mem.Allocator,
    camera: *const Camera,
    tile_size: u16,
    active_tiles: []ActiveTile,
    overlap_bboxes: []BBox,
    elem_coord_arr: *const NDArray(f64),
    elem_field_arr: *const NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {

    @setFloatMode(.optimized);

    const N: usize = 3;

    const fields_num: usize = elem_field_arr.dims[2];
    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = tile_size * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;
    
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    const spx_offset: f64 = 1.0 / (2.0 * sub_samp_f);
    
    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_total);

    const spx_image_scratch_mem = try allocator.alloc(f64, spx_tile_total*fields_num); 
    var spx_image_scratch = MatSlice(f64).init(spx_image_scratch_mem,
                                               spx_tile_total,
                                               fields_num);

    const spx_field_avg = try allocator.alloc(f64, fields_num);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
                                                tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        var nodes_weight: [N]f64 = undefined;
        
        for (overlaps) |overlap| {
            const nodes_rast: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N,f64,elem_coord_arr,overlap.elem_ind
            );

            for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            }

            const inv_elem_area: f64 = 1.0 / rops.edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
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

                const scratch_row_offset: usize = yy * spx_tile_size;
                //DEBUG
                //const spx_image_iy: usize = tile.y_px_min*sub_samp + yy;
                                
                spx_coord_x = xi_min_f + spx_offset;
                
                for (scratch_start_ind_x .. scratch_end_ind_x) |xx| {
                    // NOTE: not a weight until mult by inv area! Only used for edge check
                    nodes_weight[0] = rops.edgeFun3(nodes_rast.x[1],nodes_rast.y[1],
                                               nodes_rast.x[2],nodes_rast.y[2],
                                               spx_coord_x,spx_coord_y);
                    nodes_weight[1] = rops.edgeFun3(nodes_rast.x[2],nodes_rast.y[2],
                                               nodes_rast.x[0],nodes_rast.y[0],
                                               spx_coord_x,spx_coord_y);
                    nodes_weight[2] = rops.edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
                                               nodes_rast.x[1],nodes_rast.y[1],
                                               spx_coord_x,spx_coord_y);

                    const scratch_flat_ind: usize = scratch_row_offset + xx;

                    // DEBUG
                    //const spx_image_ix: usize = tile.x_px_min*sub_samp + xx;
                    if (nodes_weight[0] >= 0.0 and 
                        nodes_weight[1] >= 0.0 and 
                        nodes_weight[2] >= 0.0){

                        // NOTE: now it is a weight
                        for (0..N) |nn| {
                            nodes_weight[nn] = nodes_weight[nn] * inv_elem_area;
                        }

                        // Perspective correct interpolation to get the inverse of the z
                        // (weights) dot (nodes_inv_z) 
                        var spx_inv_z: f64 = 0.0;
                        for (0..N) |nn| {
                            spx_inv_z += nodes_weight[nn] * nodes_inv_z[nn];
                        }

                        // INV DEPTH CHECK: 
                        // 1/large number = far away = approach 0, far away = LESS THAN
                        // 1/small number = closer = approach inf, close = GREATER THAN
                        if (spx_inv_z > spx_inv_z_scratch[scratch_flat_ind]) {
                            
                            spx_inv_z_scratch[scratch_flat_ind] = spx_inv_z;           
                            
                            //spx_image_scratch[scratch_flat_ind] = spx_z;

                            
                            // CALC: for each field, subpx value based on node values and 
                            // weights:
                            // spx_field = (vec(nodes_field[nn] * nodes_inv_z[nn]) 
                            //             dot vec(nodes_weights)) * spx_z_coord
                            const spx_z: f64 = 1/spx_inv_z; 
                            for (0..fields_num) |ff| {

                                var field_at_spx: f64 = 0.0;
                                for (0..N) |nn| { 
                                    const elem_field_inds = [_]usize{overlap.elem_ind,
                                                                     ff,
                                                                     nn};
                                    // CALC:(nodes_field[nn]) * (nodes_inv_z[nn])
                                    const field_at_node_div_z = elem_field_arr.get(
                                        elem_field_inds[0..]) * nodes_inv_z[nn];

                                    // CALC: (node_weights) dot (nodes_field_div_z)
                                    field_at_spx += nodes_weight[nn]*field_at_node_div_z;  
                                }
                                
                                // CALC: ((node_weights) dot (nodes_field_div_z)) * subpx_z
                                field_at_spx *= spx_z;
                                
                                spx_image_scratch.set(scratch_flat_ind,ff,field_at_spx);
                            }                                
                            // DEBUG
                            //spx_image.set(spx_image_iy,spx_image_ix,spx_z);
                        }
                    } 
                    spx_coord_x += spx_step;           
                } // LOOP subpx x            
                spx_coord_y += spx_step;
            } // LOOP subpx y    
        } // LOOP overlapping elems / boxes

        // Average scratch and push into main image buffer
        rops.averageScratch(tile, 
                            tile_size, 
                            screen_px_x, 
                            screen_px_y, 
                            sub_samp, 
                            spx_tile_size, 
                            fields_num, 
                            &spx_image_scratch, 
                            spx_field_avg, 
                            image_out_arr);    
    } // LOOP active tiles   
}
