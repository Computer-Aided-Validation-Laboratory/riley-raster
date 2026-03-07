const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Instant = time.Instant;

const vecstack = @import("vecstack.zig");
const Vec3f = vecstack.Vec3f;
const Vec3T = vecstack.Vec3T;
const Vec3SliceOps = vecstack.Vec3SliceOps;

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

pub fn worldToRasterCoords(coord_world: Vec3T(f64), camera: *const Camera) Vec3T(f64) {
    // TODO: simplify this to a matrix mult
    var coord_raster: Vec3T(f64) = Mat44Ops.mulVec3(f64, 
    										        camera.world_to_cam_mat, 
    										        coord_world);

    coord_raster.elems[0] = camera.image_dist 
                            * coord_raster.elems[0] 
                            / (-coord_raster.elems[2]);
    coord_raster.elems[1] = camera.image_dist 
                            * coord_raster.elems[1] 
                            / (-coord_raster.elems[2]);

    coord_raster.elems[0] = 2.0 * coord_raster.elems[0] 
                            / camera.image_dims[0];
    coord_raster.elems[1] = 2.0 * coord_raster.elems[1] 
                            / camera.image_dims[1];

    coord_raster.elems[0] = (coord_raster.elems[0] + 1.0) 
    	/ 2.0 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    coord_raster.elems[1] = (1.0 - coord_raster.elems[1]) 
    	/ 2.0 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    coord_raster.elems[2] = -1.0 * coord_raster.elems[2];

    return coord_raster;
}


pub fn edgeFun(vert_0: Vec3f, vert_1: Vec3f, vert_2: Vec3f) f64 {
    return ((vert_2.get(0) - vert_0.get(0)) 
          * (vert_1.get(1) - vert_0.get(1)) 
          - (vert_2.get(1) - vert_0.get(1)) 
          * (vert_1.get(0) - vert_0.get(0)));
}

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

pub fn boundIndexMin(min_val: f64) usize {
    var min_ind: i32 = @as(i32, @intFromFloat(@floor(min_val)));
    if (min_ind < 0) {
        min_ind = 0;
    }
    return @as(usize,@intCast(min_ind));
}

pub fn boundIndexMax(max_val: f64, pixels_num: usize) usize {
    var max_ind: i32 = @as(i32, @intFromFloat(@ceil(max_val)));
    const px = @as(i32,@intCast(pixels_num - 1));
    if (max_ind > px) {
        max_ind = px;
    }
    return @as(usize,@intCast(max_ind));
}

// pub fn boundIndMin(comptime T: type, min_val: f64) T {
//     var min_ind: i32 = @as(i32, @intFromFloat(@floor(min_val)));
//     if (min_ind < 0) {
//         min_ind = 0;
//     }
//     return @as(T,@intCast(min_ind));
// }
// 
// pub fn boundIndMax(comptime T: type, max_val: f64, pixels_num: T) T {
//     var max_ind: i32 = @as(i32, @intFromFloat(@ceil(max_val)));
//     const px = @as(i32,@intCast(pixels_num - 1));
//     if (max_ind > px) {
//         max_ind = px;
//     }
//     return @as(T,@intCast(max_ind));
// }

pub inline fn boundIndMin(comptime T: type, val: f64) T {
    const val_int = @as(isize, @intFromFloat(@floor(val)));
    return @as(T, @intCast(@max(0, val_int)));
}

pub inline fn boundIndMax(comptime T: type, val: f64, max: T) T {
    const val_int = @as(isize, @intFromFloat(@ceil(val)));
    return @as(T, @intCast(@max(0, @min(val_int, @as(isize, @intCast(max))))));
}

pub fn averageImage(image_subpx: *const MatSlice(f64), 
                    sub_samp: u8, 
                    image_avg: *MatSlice(f64)) void {
                    
    const num_px_x: usize = (image_subpx.cols_n) / @as(usize, sub_samp);
    const num_px_y: usize = (image_subpx.rows_n) / @as(usize, sub_samp);
    const sub_samp_us: usize = @as(usize, sub_samp);
    const sub_samp_f: f64 = @as(f64, @floatFromInt(sub_samp));
    const subpx_per_px: f64 = sub_samp_f * sub_samp_f;

    // TODO: do some error checking on the Matrices here to check dims agree
    // with the variables above

    var px_sum: f64 = 0.0;

    for (0..num_px_y) |iy| {
        for (0..num_px_x) |ix| {
            px_sum = 0.0;
            for (0..sub_samp_us) |sy| {
                for (0..sub_samp_us) |sx| {
                    px_sum += image_subpx.get(sub_samp_us * iy + sy, 
                                              sub_samp_us * ix + sx);
                }
            }
            image_avg.set(iy, ix, px_sum / subpx_per_px);
        }
    }
}


//---------------------------------------------------------------------------------------------
// Tiling Raster: Helper Functions

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

    var start_slice: usize = elem_array.getFlatInd(&[_]usize{elem_ind,0,0});
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

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 1: World to Camera/Raster Coords

pub fn worldToRasterSIMD(comptime N: usize,
                         comptime T: type, 
                         coord_world: Vec3SIMD(N,T), 
                         camera: *const Camera) Vec3SIMD(N,T) {

    var coord_raster: Vec3SIMD(N,T) = vsd.mat44Mul(N,T,
                                                       camera.world_to_cam_mat,
                                                       coord_world);

    const image_dist_simd: @Vector(N,T) = @splat(camera.image_dist);
    const inv_neg_z: @Vector(N,T) = @as(@Vector(N,T),@splat(1.0)) / (-coord_raster.z);

    coord_raster.x = image_dist_simd * coord_raster.x * inv_neg_z; 
    coord_raster.y = image_dist_simd * coord_raster.y * inv_neg_z;

    coord_raster.x *= @splat(2.0/camera.image_dims[0]);
    coord_raster.y *= @splat(2.0/camera.image_dims[1]);

    const px_x = @as(T,@floatFromInt(camera.pixels_num[0]));
    const px_y = @as(T,@floatFromInt(camera.pixels_num[1]));

    const px_x_half_vec: @Vector(N,T) = @splat(px_x/2.0);
    const px_y_half_vec: @Vector(N,T) = @splat(px_y/2.0); 
    const ones_vec: @Vector(N,T) = @splat(1.0);
    
    coord_raster.x = px_x_half_vec*(coord_raster.x + ones_vec);
    coord_raster.y = px_y_half_vec*(ones_vec - coord_raster.y);
    coord_raster.z = -coord_raster.z;

    return coord_raster;
}


//---------------------------------------------------------------------------------------------
// Tiling Raster Structs

pub const BBox = struct {
    elem_ind: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const ActiveTile = struct {
    overlap_start: usize, // index into overlap_bboxes
    overlap_count: usize, // count to take from overlap bboxes
    x_px_min: u16,
    y_px_min: u16,
};

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 3: Element Tile Overlap - COUNT only 

// TODO: remove the divCeil for the error free version
pub fn elemTileOverlapCount(tile_size: u16,
                            tiles_num_x: usize,
                            elems_in_image: usize,
                            elem_bboxes: []BBox,
                            tile_elem_counts: []usize,
                            tile_write_inds: []usize) !usize {

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

    // Count the active tiles and work out the write offsets into the overlap boxes
    var num_active_tiles: usize = 0;
    var current_offset: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
        tile_write_inds[ii] = current_offset;
        current_offset += cc;
        if (cc > 0) {
            num_active_tiles += 1;            
        }
    }

    return num_active_tiles;   
}

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 4: Element Tile Overlap- Store overlap bounding boxes for ACTIVE tiles

pub fn storeActiveTiles(tile_size: u16,
                        tiles_num_x: usize,
                        tiles_num_y: usize,
                        screen_px_x: u16,
                        screen_px_y: u16,
                        elems_in_image: usize,
                        elem_bboxes: []const BBox,
                        tile_elem_counts: []const usize,
                        tile_write_inds: []usize,
                        overlap_bboxes: []BBox,
                        active_tiles: []ActiveTile) void {

    var active_ind: usize = 0;
    for (tile_elem_counts,0..) |cc,ii| {
    
        if (cc > 0) {
            // TODO: check for bug here - should this both be tiles_num_x?
            const tx = @as(u16, @intCast(ii % tiles_num_x));
            const ty = @as(u16, @intCast(ii / tiles_num_x));
        
            active_tiles[active_ind] = ActiveTile{
                .overlap_start = tile_write_inds[ii],
                .overlap_count = cc,
                .x_px_min = tx*tile_size,
                .y_px_min = ty*tile_size,
            };
            active_ind += 1;      
        }
    }

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
}

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 5: Raster Loop Helpers

pub fn averageScratch(tile: ActiveTile,
                      tile_size: u16,
                      screen_px_x: u16,
                      screen_px_y: u16,
                      sub_samp: usize,
                      spx_tile_size: usize,
                      fields_num: usize,
                      spx_image_scratch: *const MatSlice(f64),
                      spx_field_avg: []f64,
                      image_out_arr: *NDArray(f64)) void {

    const curr_tile_size_x = @min(@as(u16, tile_size), screen_px_x - tile.x_px_min);
    const curr_tile_size_y = @min(@as(u16, tile_size), screen_px_y - tile.y_px_min);
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            @memset(spx_field_avg, 0.0);

            for (0..sub_samp) |sy| {
                const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                for (0..sub_samp) |sx| {
                    const scratch_flat_ind: usize = scratch_row_offset + spx_start_x + sx;

                    for (0..fields_num) |ff| {
                        spx_field_avg[ff] += spx_image_scratch.get(scratch_flat_ind, ff);
                    }
                }
            }

            for (0..fields_num) |ff| {
                const image_inds = [_]usize{ ff, image_px_y, image_px_x };
                const image_val: f64 = spx_field_avg[ff] * inv_sub_samp_sq;
                image_out_arr.set(image_inds[0..], image_val);
            }
        }
    }
}
