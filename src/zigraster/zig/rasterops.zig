const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Instant = time.Instant;

const vecstack = @import("vecstack.zig");
const Vec3f = vecstack.Vec3f;
const Vec3T = vecstack.Vec3T;
const Vec3SliceOps = vecstack.Vec3SliceOps;

const vecsimd = @import("vecsimd.zig");
const Vec3SIMD = vecsimd.Vec3SIMD;

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

pub fn worldToRasterSIMD(comptime N: usize,
                         comptime T: type, 
                         coord_world: Vec3SIMD(N,T), 
                         camera: *const Camera) Vec3SIMD(N,T) {

    var coord_raster: Vec3SIMD(N,T) = vecsimd.mat44Mul(N,T,
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

pub fn edgeFun(vert_0: Vec3f, vert_1: Vec3f, vert_2: Vec3f) f64 {
    return ((vert_2.get(0) - vert_0.get(0)) 
          * (vert_1.get(1) - vert_0.get(1)) 
          - (vert_2.get(1) - vert_0.get(1)) 
          * (vert_1.get(0) - vert_0.get(0)));
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

pub fn boundIndMin(comptime T: type, min_val: f64) T {
    var min_ind: i32 = @as(i32, @intFromFloat(@floor(min_val)));
    if (min_ind < 0) {
        min_ind = 0;
    }
    return @as(T,@intCast(min_ind));
}

pub fn boundIndMax(comptime T: type, max_val: f64, pixels_num: T) T {
    var max_ind: i32 = @as(i32, @intFromFloat(@ceil(max_val)));
    const px = @as(i32,@intCast(pixels_num - 1));
    if (max_ind > px) {
        max_ind = px;
    }
    return @as(T,@intCast(max_ind));
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

pub const BBox = struct {
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
                      ) void {
    var elem_inds = [_]usize{0,0,0};

    for (0..elem_array.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_array.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;
                                
            elem_inds[dim_field] = 0;            
            elem_array.set(elem_inds[0..],coords.x(coord_inds[nn]));
            elem_inds[dim_field] = 1;            
            elem_array.set(elem_inds[0..],coords.y(coord_inds[nn]));
            elem_inds[dim_field] = 2;            
            elem_array.set(elem_inds[0..],coords.z(coord_inds[nn]));
            
        } 
    }    
}

pub fn fillElemFields(connect: *const Connect,
                      field: *const Field,
                      frame_ind: usize,
                      dim_elem: usize,
                      dim_node: usize,
                      dim_field: usize,
                      field_array: *NDArray(f64),
                      ) void {

    const fields_num = field.getFieldsN();
    var set_elem_inds = [_]usize{0,0,0}; // dims=(elem,field,node)
    var get_field_inds = [_]usize{frame_ind,0,0}; // dims=(time,coord,field)

    for (0..field_array.dims[dim_elem]) |ee| {
        set_elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..field_array.dims[dim_node]) |nn| {
            set_elem_inds[dim_node] = nn;
            get_field_inds[1] = coord_inds[nn];
            
            for (0..fields_num) |ff| {
                get_field_inds[2] = ff;
                const field_val: f64 = field.array.get(get_field_inds[0..]);

                set_elem_inds[dim_field] = ff;
                field_array.set(set_elem_inds[0..],field_val);    
            }
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

pub const ActiveTile = struct {
    overlap_start: usize, // index into overlap_bboxes
    overlap_count: usize, // count to take from overlap bboxes
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
