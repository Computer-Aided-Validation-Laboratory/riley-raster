const std = @import("std");
const vecstack = @import("vecstack.zig");
const Vec3f = vecstack.Vec3f;
const Vec3T = vecstack.Vec3T;
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;
const Mat44Ops = @import("matstack.zig").Mat44Ops;
const NDArray = @import("ndarray.zig").NDArray;
const Camera = @import("camera.zig").Camera;
const report = @import("report.zig");

pub fn edgeFun(vert_0: Vec3f, vert_1: Vec3f, vert_2: Vec3f) f64 {
    return ((vert_2.get(0) - vert_0.get(0)) *
        (vert_1.get(1) - vert_0.get(1)) -
        (vert_2.get(1) - vert_0.get(1)) *
            (vert_1.get(0) - vert_0.get(0)));
}

pub inline fn edgeFun3Slices(
    comptime ind0: usize,
    comptime ind1: usize,
    comptime ind2: usize,
    x: []f64,
    y: []f64,
) f64 {
    return ((x[ind2] - x[ind0]) * (y[ind1] - y[ind0]) -
        (y[ind2] - y[ind0]) * (x[ind1] - x[ind0]));
}

pub fn boundIndexMin(min_val: f64) usize {
    var min_ind: usize = @as(isize, @intFromFloat(@floor(min_val)));
    if (min_ind < 0) {
        min_ind = 0;
    }
    return @as(usize, @intCast(min_ind));
}

pub fn boundIndexMax(max_val: f64, pixels_num: usize) usize {
    var max_ind: isize = @as(isize, @intFromFloat(@ceil(max_val)));
    const px = @as(isize, @intCast(pixels_num - 1));
    if (max_ind > px) {
        max_ind = px;
    }
    return @as(usize, @intCast(max_ind));
}

pub inline fn boundIndMin(comptime T: type, val: f64) T {
    const val_int = @as(isize, @intFromFloat(@floor(val)));
    return @as(T, @intCast(@max(0, val_int)));
}

pub inline fn boundIndMax(comptime T: type, val: f64, max: T) T {
    const val_int = @as(isize, @intFromFloat(@ceil(val)));
    return @as(T, @intCast(@max(0, @min(val_int, @as(isize, @intCast(max))))));
}

pub fn worldToRasterCoords(coord_world: Vec3T(f64), camera: *const Camera) Vec3T(f64) {
    var coord_raster: Vec3T(f64) = Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);

    coord_raster.elems[0] = camera.image_dist * coord_raster.elems[0] /
        (-coord_raster.elems[2]);
    coord_raster.elems[1] = camera.image_dist * coord_raster.elems[1] /
        (-coord_raster.elems[2]);

    coord_raster.elems[0] = 2.0 * coord_raster.elems[0] / camera.image_dims[0];
    coord_raster.elems[1] = 2.0 * coord_raster.elems[1] / camera.image_dims[1];

    coord_raster.elems[0] = (coord_raster.elems[0] + 1.0) / 2.0 *
        @as(f64, @floatFromInt(camera.pixels_num[0]));
    coord_raster.elems[1] = (1.0 - coord_raster.elems[1]) / 2.0 *
        @as(f64, @floatFromInt(camera.pixels_num[1]));
    coord_raster.elems[2] = -1.0 * coord_raster.elems[2];

    return coord_raster;
}

pub fn Vec3OfSlices(comptime T: type) type {
    return struct {
        x: []T,
        y: []T,
        z: []T,
    };
}

pub const ElemBBox = struct {
    elem_ind: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const OverlapBBox = struct {
    mesh_idx: u32,
    elem_idx: u32,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const ActiveTile = struct {
    overlap_start: usize,
    overlap_count: usize,
    x_px_min: u16,
    y_px_min: u16,
    x_px_max: u16,
    y_px_max: u16,
};

pub const TilingOverlaps = struct {
    overlaps: []OverlapBBox,
    active_tiles: []ActiveTile,
};

pub fn RasterContext(comptime report_mode: report.ReportMode) type {
    return struct {
        ctx_perf: report.ReportContext(report_mode),
        camera: *const Camera,
        frame_ind: usize,
        tile_size: u16,
    };
}

pub const OverlapTarget = struct {
    tile: ActiveTile,
    overlap: OverlapBBox,
};

pub const MeshInput = struct {
    coords: *const NDArray(f64),
    hull: ?*const NDArray(f64),
};

pub fn loadVec3SlicesFromElemArray(
    comptime N: usize,
    comptime T: type,
    elem_array: *const NDArray(T),
    elem_ind: usize,
) !Vec3OfSlices(T) {
    var start_slice: usize = elem_array.getFlatInd(&[_]usize{ elem_ind, 0, 0 });
    const stride: usize = elem_array.strides[1];

    const x_slice = elem_array.elems[start_slice .. start_slice + N];
    start_slice += stride;
    const y_slice = elem_array.elems[start_slice .. start_slice + N];
    start_slice += stride;
    const z_slice = elem_array.elems[start_slice .. start_slice + N];

    return .{
        .x = x_slice,
        .y = y_slice,
        .z = z_slice,
    };
}

pub fn worldToRasterSIMD(
    comptime N: usize,
    comptime T: type,
    coord_world: Vec3SIMD(N, T),
    camera: *const Camera,
) Vec3SIMD(N, T) {
    var coord_raster: Vec3SIMD(N, T) = vsd.mat44Mul(
        N,
        T,
        camera.world_to_cam_mat,
        coord_world,
    );

    const image_dist_simd: @Vector(N, T) = @splat(camera.image_dist);
    const inv_neg_z: @Vector(N, T) = @as(@Vector(N, T), @splat(1.0)) / (-coord_raster.z);

    coord_raster.x = image_dist_simd * coord_raster.x * inv_neg_z;
    coord_raster.y = image_dist_simd * coord_raster.y * inv_neg_z;

    coord_raster.x *= @splat(2.0 / camera.image_dims[0]);
    coord_raster.y *= @splat(2.0 / camera.image_dims[1]);

    const px_x = @as(T, @floatFromInt(camera.pixels_num[0]));
    const px_y = @as(T, @floatFromInt(camera.pixels_num[1]));
    const px_x_half_vec: @Vector(N, T) = @splat(px_x / 2.0);
    const px_y_half_vec: @Vector(N, T) = @splat(px_y / 2.0);
    const ones_vec: @Vector(N, T) = @splat(1.0);

    coord_raster.x = px_x_half_vec * (coord_raster.x + ones_vec);
    coord_raster.y = px_y_half_vec * (ones_vec - coord_raster.y);
    coord_raster.z = -coord_raster.z;

    return coord_raster;
}

pub fn elemsToRasterSIMD(
    comptime N: usize,
    comptime T: type,
    camera: *const Camera,
    dim_elem: usize,
    elem_coord_arr: *NDArray(T),
) !void {
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N, T) = try vsd.loadVec3SIMDFromElemArray(
            N,
            T,
            elem_coord_arr,
            ee,
        );
        const coords_raster = worldToRasterSIMD(N, T, coords_world, camera);
        try vsd.saveVec3SIMDToElemArray(N, T, elem_coord_arr, ee, coords_raster);
    }
}

pub fn elemsToClipPxLengSIMD(
    comptime N: usize,
    comptime T: type,
    camera: *const Camera,
    dim_elem: usize,
    elem_coord_arr: *NDArray(T),
) !void {
    const x_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[0])) / camera.image_dims[0];
    const y_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[1])) / camera.image_dims[1];

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cw: Vec3SIMD(N, f64) = try vsd.loadVec3SIMDFromElemArray(
            N,
            f64,
            elem_coord_arr,
            ee,
        );
        var cr = vsd.mat44Mul(N, f64, camera.world_to_cam_mat, cw);
        cr.x *= @splat(x_scale);
        cr.y *= @splat(-y_scale);
        try vsd.saveVec3SIMDToElemArray(
            N,
            f64,
            elem_coord_arr,
            ee,
            Vec3SIMD(N, f64){ .x = cr.x, .y = cr.y, .z = -cr.z },
        );
    }
}
