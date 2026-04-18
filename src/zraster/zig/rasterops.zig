// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const vecstack = @import("vecstack.zig");
const Vec3T = vecstack.Vec3T;
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;
const ndarray = @import("ndarray.zig");
const NDArray = ndarray.NDArray;
const MappedNDArray = ndarray.MappedNDArray;
const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const Camera = @import("camera.zig").Camera;
const shapefun = @import("shapefun.zig");
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const tol = cfg.tolerance;
const matrix = @import("matstack.zig");
const Mat44Ops = matrix.Mat44Ops;

const buildAdaptiveHulls = @import("hull.zig").buildAdaptiveHulls;
const geomkerns = @import("geometrykernels.zig");
const shaderops = @import("shaderops.zig");
const report = @import("report.zig");

fn edgeFun3Slices(
    comptime ind0: usize,
    comptime ind1: usize,
    comptime ind2: usize,
    x: []const f64,
    y: []const f64,
) f64 {
    return ((x[ind2] - x[ind0]) * (y[ind1] - y[ind0]) -
        (y[ind2] - y[ind0]) * (x[ind1] - x[ind0]));
}

pub inline fn edgeFun3(x0: f64, y0: f64, x1: f64, y1: f64, px: f64, py: f64) f64 {
    return (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
}

pub inline fn edgeFun3SIMD(
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,
    v_px: VecSF,
    v_py: VecSF,
) VecSF {
    const v_x0: VecSF = @splat(x0);
    const v_y0: VecSF = @splat(y0);
    const v_x1: VecSF = @splat(x1);
    const v_y1: VecSF = @splat(y1);
    return (v_px - v_x0) * (v_y1 - v_y0) - (v_py - v_y0) * (v_x1 - v_x0);
}

fn boundIndMin(comptime T: type, val: f64) T {
    const val_int = @as(isize, @intFromFloat(@floor(val)));
    return @as(T, @intCast(@max(0, val_int)));
}

fn boundIndMax(comptime T: type, val: f64, max: T) T {
    const val_int = @as(isize, @intFromFloat(@ceil(val)));
    return @as(T, @intCast(@max(0, @min(val_int, @as(isize, @intCast(max))))));
}

pub fn Vec3Slices(comptime T: type) type {
    return struct {
        x: []T,
        y: []T,
        z: []T,
    };
}

pub const ElemBBox = struct {
    elem_idx: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const OverlapBBox = struct {
    mesh_idx: usize,
    elem_idx: usize,
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

pub const RasterContext = struct {
    camera: *const Camera,
    frame_idx: usize,
    tile_size: u16,
};

pub const MeshInput = struct {
    coords: *const NDArray(f64),
    hull: ?*const NDArray(f64),
};

fn AdaptiveHullPoints(comptime N: usize) type {
    const NH = comptime switch (N) {
        4 => 4,
        6 => 6,
        8, 9 => 8,
        else => 0,
    };

    return struct {
        x: [NH]f64,
        y: [NH]f64,
    };
}

fn GatheredElemCoords(comptime N: usize) type {
    return struct {
        x: [N]f64,
        y: [N]f64,
        z: [N]f64,
    };
}

fn transformWorldNodeToRaster(
    camera: *const Camera,
    coord_world: Vec3T(f64),
) Vec3T(f64) {
    var coord_raster = Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);

    coord_raster.slice[0] = camera.image_dist * coord_raster.slice[0] /
        (-coord_raster.slice[2]);
    coord_raster.slice[1] = camera.image_dist * coord_raster.slice[1] /
        (-coord_raster.slice[2]);

    coord_raster.slice[0] = 2.0 * coord_raster.slice[0] / camera.image_dims[0];
    coord_raster.slice[1] = 2.0 * coord_raster.slice[1] / camera.image_dims[1];

    coord_raster.slice[0] = (coord_raster.slice[0] + 1.0) * 0.5 *
        @as(f64, @floatFromInt(camera.pixels_num[0]));
    coord_raster.slice[1] = (1.0 - coord_raster.slice[1]) * 0.5 *
        @as(f64, @floatFromInt(camera.pixels_num[1]));
    coord_raster.slice[2] = -coord_raster.slice[2];

    return coord_raster;
}

fn transformWorldNodeToClipPx(
    camera: *const Camera,
    coord_world: Vec3T(f64),
) Vec3T(f64) {
    const x_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[0])) / camera.image_dims[0];
    const y_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[1])) / camera.image_dims[1];

    var coord_clip = Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);
    coord_clip.slice[0] *= x_scale;
    coord_clip.slice[1] *= -y_scale;
    coord_clip.slice[2] = -coord_clip.slice[2];
    return coord_clip;
}

pub fn nodesToRasterInPlace(
    camera: *const Camera,
    coords_nodes: *Coords,
) void {
    nodesToRasterRangeInPlace(camera, coords_nodes, 0, coords_nodes.mat.rows_num);
}

pub fn nodesToRasterRangeInPlace(
    camera: *const Camera,
    coords_nodes: *Coords,
    node_start: usize,
    node_end: usize,
) void {
    for (node_start..node_end) |nn| {
        const coord_world = coords_nodes.getVec3(nn);
        const coord_raster = transformWorldNodeToRaster(camera, coord_world);
        coords_nodes.mat.set(nn, 0, coord_raster.slice[0]);
        coords_nodes.mat.set(nn, 1, coord_raster.slice[1]);
        coords_nodes.mat.set(nn, 2, coord_raster.slice[2]);
    }
}

pub fn nodesToClipPxLengInPlace(
    camera: *const Camera,
    coords_nodes: *Coords,
) void {
    nodesToClipPxLengRangeInPlace(
        camera,
        coords_nodes,
        0,
        coords_nodes.mat.rows_num,
    );
}

pub fn nodesToClipPxLengRangeInPlace(
    camera: *const Camera,
    coords_nodes: *Coords,
    node_start: usize,
    node_end: usize,
) void {
    for (node_start..node_end) |nn| {
        const coord_world = coords_nodes.getVec3(nn);
        const coord_clip = transformWorldNodeToClipPx(camera, coord_world);
        coords_nodes.mat.set(nn, 0, coord_clip.slice[0]);
        coords_nodes.mat.set(nn, 1, coord_clip.slice[1]);
        coords_nodes.mat.set(nn, 2, coord_clip.slice[2]);
    }
}

fn gatherElemNodeCoords(
    comptime N: usize,
    coords_nodes: *const Coords,
    connect: *const Connect,
    elem_idx: usize,
) GatheredElemCoords(N) {
    var coords_elem: GatheredElemCoords(N) = undefined;
    const coord_inds = connect.getElem(elem_idx);

    for (0..N) |nn| {
        const node_idx = coord_inds[nn];
        coords_elem.x[nn] = coords_nodes.x(node_idx);
        coords_elem.y[nn] = coords_nodes.y(node_idx);
        coords_elem.z[nn] = coords_nodes.z(node_idx);
    }

    return coords_elem;
}

fn buildAdaptiveHullPoints(
    comptime N: usize,
    camera: *const Camera,
    coords_elem: GatheredElemCoords(N),
) AdaptiveHullPoints(N) {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    var lx: [N]f64 = undefined;
    var ly: [N]f64 = undefined;
    for (0..N) |nn| {
        lx[nn] = coords_elem.x[nn] / coords_elem.z[nn] + x_off;
        ly[nn] = coords_elem.y[nn] / coords_elem.z[nn] + y_off;
    }

    var hull_points: AdaptiveHullPoints(N) = undefined;
    if (N == 4) {
        inline for (0..4) |nn| {
            hull_points.x[nn] = lx[nn];
            hull_points.y[nn] = ly[nn];
        }
    } else if (N == 6) {
        const edges = [3][3]usize{
            .{ 0, 1, 3 },
            .{ 1, 2, 4 },
            .{ 2, 0, 5 },
        };

        inline for (edges, 0..) |edge, ee| {
            const p0 = edge[0];
            const p1 = edge[1];
            const pm = edge[2];
            const edge_val = edgeFun3(
                lx[p0],
                ly[p0],
                lx[p1],
                ly[p1],
                lx[pm],
                ly[pm],
            );
            hull_points.x[ee * 2] = lx[p0];
            hull_points.y[ee * 2] = ly[p0];
            if (edge_val < 0.0) {
                hull_points.x[ee * 2 + 1] =
                    2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
                hull_points.y[ee * 2 + 1] =
                    2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
            } else {
                hull_points.x[ee * 2 + 1] = lx[pm];
                hull_points.y[ee * 2 + 1] = ly[pm];
            }
        }
    } else if (N == 8 or N == 9) {
        const edges = [4][3]usize{
            .{ 0, 1, 4 },
            .{ 1, 2, 5 },
            .{ 2, 3, 6 },
            .{ 3, 0, 7 },
        };

        inline for (edges, 0..) |edge, ee| {
            const p0 = edge[0];
            const p1 = edge[1];
            const pm = edge[2];
            const edge_val = edgeFun3(
                lx[p0],
                ly[p0],
                lx[p1],
                ly[p1],
                lx[pm],
                ly[pm],
            );
            hull_points.x[ee * 2] = lx[p0];
            hull_points.y[ee * 2] = ly[p0];
            if (edge_val < 0.0) {
                hull_points.x[ee * 2 + 1] =
                    2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
                hull_points.y[ee * 2 + 1] =
                    2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
            } else {
                hull_points.x[ee * 2 + 1] = lx[pm];
                hull_points.y[ee * 2 + 1] = ly[pm];
            }
        }
    }

    return hull_points;
}

pub fn loadElemVec3Slices(
    comptime N: usize,
    comptime T: type,
    elem_array: *const NDArray(T),
    elem_idx: usize,
) !Vec3Slices(T) {
    std.debug.assert(elem_array.dims.len == 3);
    std.debug.assert(elem_idx < elem_array.dims[0]);
    var start_slice: usize = elem_idx * elem_array.strides[0];
    const stride: usize = elem_array.strides[1];

    const x_slice = elem_array.slice[start_slice .. start_slice + N];
    start_slice += stride;
    const y_slice = elem_array.slice[start_slice .. start_slice + N];
    start_slice += stride;
    const z_slice = elem_array.slice[start_slice .. start_slice + N];

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
        const coords_world: Vec3SIMD(N, T) = try vsd.loadElemVec3SIMD(
            N,
            T,
            elem_coord_arr,
            ee,
        );
        const coords_raster = worldToRasterSIMD(N, T, coords_world, camera);
        try vsd.saveElemVec3SIMD(N, T, elem_coord_arr, ee, coords_raster);
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
        const coords_world = try vsd.loadElemVec3SIMD(
            N,
            f64,
            elem_coord_arr,
            ee,
        );
        var coords_raster = vsd.mat44Mul(
            N,
            f64,
            camera.world_to_cam_mat,
            coords_world,
        );
        coords_raster.x *= @splat(x_scale);
        coords_raster.y *= @splat(-y_scale);
        try vsd.saveElemVec3SIMD(
            N,
            f64,
            elem_coord_arr,
            ee,
            Vec3SIMD(N, f64){
                .x = coords_raster.x,
                .y = coords_raster.y,
                .z = -coords_raster.z,
            },
        );
    }
}

pub fn cullElemsCalcBBoxesHighOrd(
    comptime N: usize,
    comptime NH: usize,
    camera: *const Camera,
    dim_elem: usize,
    elem_coord_arr: *const NDArray(f64),
    raster_hull: ?*const NDArray(f64),
    elem_bboxes: []ElemBBox,
) !usize {
    var elems_in_image: usize = 0;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    const tolerance = tol.culling.higher_order_backface_nz;

    const total_elems = elem_coord_arr.dims[dim_elem];

    for (0..total_elems) |ee| {
        var x_min: f64 = std.math.inf(f64);
        var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64);
        var y_max: f64 = -std.math.inf(f64);

        const cr: Vec3Slices(f64) = try loadElemVec3Slices(
            N,
            f64,
            elem_coord_arr,
            ee,
        );

        var sx_nodes: [N]f64 = undefined;
        var sy_nodes: [N]f64 = undefined;

        for (0..N) |ii| {
            sx_nodes[ii] = cr.x[ii] / cr.z[ii] + x_off;
            sy_nodes[ii] = cr.y[ii] / cr.z[ii] + y_off;
        }

        if (comptime N >= 4) {
            var all_backface = true;
            for (0..N) |ii| {
                var dx_dxi: f64 = 0;
                var dx_deta: f64 = 0;
                var dy_dxi: f64 = 0;
                var dy_deta: f64 = 0;
                for (0..N) |jj| {
                    dx_dxi += nodal_derivs.dNu[ii][jj] * sx_nodes[jj];
                    dx_deta += nodal_derivs.dNv[ii][jj] * sx_nodes[jj];
                    dy_dxi += nodal_derivs.dNu[ii][jj] * sy_nodes[jj];
                    dy_deta += nodal_derivs.dNv[ii][jj] * sy_nodes[jj];
                }
                const nz = dx_dxi * dy_deta - dx_deta * dy_dxi;
                if (nz <= tolerance) {
                    all_backface = false;
                    break;
                }
            }
            if (all_backface) continue;
        }

        if (raster_hull) |rh| {
            // Use pre-calculated raster hull (NH points)
            const hull_x = rh.getSlice(&[_]usize{ ee, 0, 0 }, 1);
            const hull_y = rh.getSlice(&[_]usize{ ee, 1, 0 }, 1);

            for (0..NH) |ii| {
                const sx = hull_x[ii];
                const sy = hull_y[ii];
                x_min = @min(x_min, sx);
                x_max = @max(x_max, sx);
                y_min = @min(y_min, sy);
                y_max = @max(y_max, sy);
            }
        } else {
            for (0..N) |ii| {
                const sx = sx_nodes[ii];
                const sy = sy_nodes[ii];
                x_min = @min(x_min, sx);
                x_max = @max(x_max, sx);
                y_min = @min(y_min, sy);
                y_max = @max(y_max, sy);
            }
        }

        if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1)) or
            x_max < 0.0 or
            y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1)) or
            y_max < 0.0)
        {
            continue;
        }

        elem_bboxes[elems_in_image] = ElemBBox{
            .elem_idx = ee,
            .x_min = boundIndMin(u16, x_min),
            .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = boundIndMin(u16, y_min),
            .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
        };
        elems_in_image += 1;
    }
    return elems_in_image;
}

pub fn cullElemsCalcBBoxesTri3(
    camera: *const Camera,
    dim_elem: usize,
    elem_coord_arr: *const NDArray(f64),
    elem_bboxes: []ElemBBox,
) !usize {
    const N: usize = 3;
    const tol_area = tol.culling.tri3_signed_area;

    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3Slices(f64) = try loadElemVec3Slices(
            N,
            f64,
            elem_coord_arr,
            ee,
        );

        // Width (X) on screen check and crop
        const x_max: f64 = std.mem.max(f64, coords_raster.x);
        const x_min: f64 = std.mem.min(f64, coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or
            (x_max < 0.0))
        {
            continue;
        }

        // Height (Y) on on screen check and crop
        const y_max: f64 = std.mem.max(f64, coords_raster.y);
        const y_min: f64 = std.mem.min(f64, coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or
            (y_max < 0.0))
        {
            continue;
        }

        // Backface culling, negative area = crop for linear triangles
        const elem_area: f64 = edgeFun3Slices(0, 1, 2, coords_raster.x, coords_raster.y);

        if (elem_area < tol_area) {
            continue;
        }

        const x_min_i: u16 = boundIndMin(u16, x_min);
        const x_max_i: u16 = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0]));
        const y_min_i: u16 = boundIndMin(u16, y_min);
        const y_max_i: u16 = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1]));

        elem_bboxes[elems_in_image] = ElemBBox{
            .elem_idx = ee,
            .x_min = x_min_i,
            .x_max = x_max_i,
            .y_min = y_min_i,
            .y_max = y_max_i,
        };
        elems_in_image += 1;
    }

    return elems_in_image;
}

fn cullNodesCalcBBoxesTri3(
    camera: *const Camera,
    coords_nodes: *const Coords,
    connect: *const Connect,
    elem_bboxes: []ElemBBox,
) usize {
    const tol_area = tol.culling.tri3_signed_area;
    var elems_in_image: usize = 0;

    for (0..connect.getElemsNum()) |ee| {
        const coords_elem = gatherElemNodeCoords(3, coords_nodes, connect, ee);
        const x_max = std.mem.max(f64, &coords_elem.x);
        const x_min = std.mem.min(f64, &coords_elem.x);
        if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1)) or
            x_max < 0.0)
        {
            continue;
        }

        const y_max = std.mem.max(f64, &coords_elem.y);
        const y_min = std.mem.min(f64, &coords_elem.y);
        if (y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1)) or
            y_max < 0.0)
        {
            continue;
        }

        const elem_area = edgeFun3(
            coords_elem.x[0],
            coords_elem.y[0],
            coords_elem.x[1],
            coords_elem.y[1],
            coords_elem.x[2],
            coords_elem.y[2],
        );
        if (elem_area < tol_area) {
            continue;
        }

        elem_bboxes[elems_in_image] = .{
            .elem_idx = ee,
            .x_min = boundIndMin(u16, x_min),
            .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = boundIndMin(u16, y_min),
            .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
        };
        elems_in_image += 1;
    }

    return elems_in_image;
}

fn calcVisibleNodeBBoxTri3(
    camera: *const Camera,
    coords_nodes: *const Coords,
    connect: *const Connect,
    elem_idx: usize,
) ?ElemBBox {
    const coords_elem = gatherElemNodeCoords(3, coords_nodes, connect, elem_idx);
    const weight = edgeFun3Slices(0, 1, 2, &coords_elem.x, &coords_elem.y);
    if (weight <= tol.culling.tri3_signed_area) {
        return null;
    }

    const x_min = std.mem.min(f64, &coords_elem.x);
    const x_max = std.mem.max(f64, &coords_elem.x);
    const y_min = std.mem.min(f64, &coords_elem.y);
    const y_max = std.mem.max(f64, &coords_elem.y);

    if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1)) or
        x_max < 0.0 or
        y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1)) or
        y_max < 0.0)
    {
        return null;
    }

    return .{
        .elem_idx = elem_idx,
        .x_min = boundIndMin(u16, x_min),
        .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
        .y_min = boundIndMin(u16, y_min),
        .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
    };
}

fn cullNodesCalcBBoxesHighOrd(
    comptime N: usize,
    camera: *const Camera,
    coords_nodes: *const Coords,
    connect: *const Connect,
    elem_bboxes: []ElemBBox,
) usize {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    const tolerance = tol.culling.higher_order_backface_nz;
    var elems_in_image: usize = 0;

    for (0..connect.getElemsNum()) |ee| {
        const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, ee);
        var sx_nodes: [N]f64 = undefined;
        var sy_nodes: [N]f64 = undefined;

        for (0..N) |nn| {
            sx_nodes[nn] = coords_elem.x[nn] / coords_elem.z[nn] + x_off;
            sy_nodes[nn] = coords_elem.y[nn] / coords_elem.z[nn] + y_off;
        }

        var all_backface = true;
        for (0..N) |nn| {
            var dx_dxi: f64 = 0.0;
            var dx_deta: f64 = 0.0;
            var dy_dxi: f64 = 0.0;
            var dy_deta: f64 = 0.0;

            for (0..N) |mm| {
                dx_dxi += nodal_derivs.dNu[nn][mm] * sx_nodes[mm];
                dx_deta += nodal_derivs.dNv[nn][mm] * sx_nodes[mm];
                dy_dxi += nodal_derivs.dNu[nn][mm] * sy_nodes[mm];
                dy_deta += nodal_derivs.dNv[nn][mm] * sy_nodes[mm];
            }

            const nz = dx_dxi * dy_deta - dx_deta * dy_dxi;
            if (nz <= tolerance) {
                all_backface = false;
                break;
            }
        }
        if (all_backface) {
            continue;
        }

        const hull_points = buildAdaptiveHullPoints(N, camera, coords_elem);
        const x_min = std.mem.min(f64, &hull_points.x);
        const x_max = std.mem.max(f64, &hull_points.x);
        const y_min = std.mem.min(f64, &hull_points.y);
        const y_max = std.mem.max(f64, &hull_points.y);

        if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1)) or
            x_max < 0.0 or
            y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1)) or
            y_max < 0.0)
        {
            continue;
        }

        elem_bboxes[elems_in_image] = .{
            .elem_idx = ee,
            .x_min = boundIndMin(u16, x_min),
            .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = boundIndMin(u16, y_min),
            .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
        };
        elems_in_image += 1;
    }

    return elems_in_image;
}

fn calcVisibleNodeBBoxHighOrd(
    comptime N: usize,
    camera: *const Camera,
    coords_nodes: *const Coords,
    connect: *const Connect,
    elem_idx: usize,
) ?ElemBBox {
    const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, elem_idx);
    var all_backface = true;
    for (0..N) |nn| {
        if (coords_elem.z[nn] > tol.culling.higher_order_backface_nz) {
            all_backface = false;
            break;
        }
    }
    if (all_backface) {
        return null;
    }

    const hull_points = buildAdaptiveHullPoints(N, camera, coords_elem);
    const x_min = std.mem.min(f64, &hull_points.x);
    const x_max = std.mem.max(f64, &hull_points.x);
    const y_min = std.mem.min(f64, &hull_points.y);
    const y_max = std.mem.max(f64, &hull_points.y);

    if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1)) or
        x_max < 0.0 or
        y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1)) or
        y_max < 0.0)
    {
        return null;
    }

    return .{
        .elem_idx = elem_idx,
        .x_min = boundIndMin(u16, x_min),
        .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
        .y_min = boundIndMin(u16, y_min),
        .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
    };
}

pub fn countVisibleElemsRange(
    camera: *const Camera,
    mesh_type: anytype,
    connect: *const Connect,
    coords_nodes: *const Coords,
    elem_start: usize,
    elem_end: usize,
) usize {
    var visible_count: usize = 0;

    switch (mesh_type) {
        .tri3 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxTri3(camera, coords_nodes, connect, ee) != null) {
                    visible_count += 1;
                }
            }
        },
        .tri6 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    6,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                ) != null) {
                    visible_count += 1;
                }
            }
        },
        .quad4ibi, .quad4newton => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    4,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                ) != null) {
                    visible_count += 1;
                }
            }
        },
        .quad8 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    8,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                ) != null) {
                    visible_count += 1;
                }
            }
        },
        .quad9 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    9,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                ) != null) {
                    visible_count += 1;
                }
            }
        },
    }

    return visible_count;
}

pub fn fillVisibleElemsRange(
    camera: *const Camera,
    mesh_type: anytype,
    connect: *const Connect,
    coords_nodes: *const Coords,
    visible_orig_elem_indices: []usize,
    elem_bboxes: []ElemBBox,
    elem_start: usize,
    elem_end: usize,
    write_start: usize,
) void {
    var write_idx = write_start;

    switch (mesh_type) {
        .tri3 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxTri3(camera, coords_nodes, connect, ee)) |bbox| {
                    visible_orig_elem_indices[write_idx] = ee;
                    elem_bboxes[write_idx] = bbox;
                    write_idx += 1;
                }
            }
        },
        .tri6 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    6,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                )) |bbox| {
                    visible_orig_elem_indices[write_idx] = ee;
                    elem_bboxes[write_idx] = bbox;
                    write_idx += 1;
                }
            }
        },
        .quad4ibi, .quad4newton => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    4,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                )) |bbox| {
                    visible_orig_elem_indices[write_idx] = ee;
                    elem_bboxes[write_idx] = bbox;
                    write_idx += 1;
                }
            }
        },
        .quad8 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    8,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                )) |bbox| {
                    visible_orig_elem_indices[write_idx] = ee;
                    elem_bboxes[write_idx] = bbox;
                    write_idx += 1;
                }
            }
        },
        .quad9 => {
            for (elem_start..elem_end) |ee| {
                if (calcVisibleNodeBBoxHighOrd(
                    9,
                    camera,
                    coords_nodes,
                    connect,
                    ee,
                )) |bbox| {
                    visible_orig_elem_indices[write_idx] = ee;
                    elem_bboxes[write_idx] = bbox;
                    write_idx += 1;
                }
            }
        },
    }
}

pub fn prepareVisibleWorkspace(
    allocator: std.mem.Allocator,
    camera: *const Camera,
    mesh_type: anytype,
    connect: *const Connect,
    coords_nodes: *const Coords,
    visible_orig_elem_indices: *[]usize,
    elem_bboxes: *[]ElemBBox,
    elems_in_image: *usize,
) !void {
    const elems_num = connect.getElemsNum();
    elem_bboxes.* = try allocator.alloc(ElemBBox, elems_num);

    elems_in_image.* = switch (mesh_type) {
        .tri3 => cullNodesCalcBBoxesTri3(
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        ),
        .tri6 => cullNodesCalcBBoxesHighOrd(
            6,
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        ),
        .quad4ibi, .quad4newton => cullNodesCalcBBoxesHighOrd(
            4,
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        ),
        .quad8 => cullNodesCalcBBoxesHighOrd(
            8,
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        ),
        .quad9 => cullNodesCalcBBoxesHighOrd(
            9,
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        ),
    };

    visible_orig_elem_indices.* = try allocator.alloc(usize, elems_in_image.*);
    for (0..elems_in_image.*) |pp| {
        visible_orig_elem_indices.*[pp] = elem_bboxes.*[pp].elem_idx;
    }
}

fn calcElementNodeNormal(
    comptime N: usize,
    nodal_derivs: shapefun.NodalDerivs,
    sx: []const f64,
    sy: []const f64,
    sz: []const f64,
    node_idx: usize,
) [3]f64 {
    var dx_dxi: f64 = 0;
    var dx_deta: f64 = 0;
    var dy_dxi: f64 = 0;
    var dy_deta: f64 = 0;
    var dz_dxi: f64 = 0;
    var dz_deta: f64 = 0;

    for (0..N) |nn| {
        const du = nodal_derivs.dNu[node_idx][nn];
        const dv = nodal_derivs.dNv[node_idx][nn];
        dx_dxi += du * sx[nn];
        dx_deta += dv * sx[nn];
        dy_dxi += du * sy[nn];
        dy_deta += dv * sy[nn];
        dz_dxi += du * sz[nn];
        dz_deta += dv * sz[nn];
    }

    return .{
        dy_dxi * dz_deta - dz_dxi * dy_deta,
        dz_dxi * dx_deta - dx_dxi * dz_deta,
        dx_dxi * dy_deta - dy_dxi * dx_deta,
    };
}

fn normalizeNormal(normal_vec: *[3]f64) void {
    const nx = normal_vec[0];
    const ny = normal_vec[1];
    const nz = normal_vec[2];
    const magnitude = @sqrt(nx * nx + ny * ny + nz * nz);

    if (magnitude > tol.normals.normalise_magnitude) {
        normal_vec[0] = nx / magnitude;
        normal_vec[1] = ny / magnitude;
        normal_vec[2] = nz / magnitude;
    }
}

fn initPreparedNormals(
    allocator: std.mem.Allocator,
    mesh_coords: *const NDArray(f64),
    elem_bboxes: []const ElemBBox,
    prep_count: usize,
    comptime N: usize,
) !MappedNDArray(f64) {
    const elems_num = mesh_coords.dims[0];
    const prep_normals = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ prep_count, 3, N },
    );
    var map = try allocator.alloc(usize, elems_num);
    @memset(map, std.math.maxInt(usize));

    for (0..prep_count) |pp| {
        const orig_ee = elem_bboxes[pp].elem_idx;
        map[orig_ee] = pp;
    }

    return .{
        .array = prep_normals,
        .map = map,
    };
}

fn calculatePreparedExactNormals(
    mesh_coords: *const NDArray(f64),
    prep_normals: *NDArray(f64),
    elem_bboxes: []const ElemBBox,
    prep_count: usize,
    comptime N: usize,
) void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (0..prep_count) |pp| {
        const orig_ee = elem_bboxes[pp].elem_idx;
        const sx = mesh_coords.getSlice(&[_]usize{ orig_ee, 0, 0 }, 1);
        const sy = mesh_coords.getSlice(&[_]usize{ orig_ee, 1, 0 }, 1);
        const sz = mesh_coords.getSlice(&[_]usize{ orig_ee, 2, 0 }, 1);

        for (0..N) |nn| {
            var normal_vec = calcElementNodeNormal(N, nodal_derivs, sx, sy, sz, nn);
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

fn calculatePreparedAveragedNormals(
    allocator: std.mem.Allocator,
    mesh_coords: *const NDArray(f64),
    mesh_connect: anytype,
    prep_normals: *NDArray(f64),
    elem_bboxes: []const ElemBBox,
    prep_count: usize,
    comptime N: usize,
) !void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    var max_node_idx: usize = 0;
    for (mesh_connect.table_mem) |node_idx| {
        if (node_idx > max_node_idx) {
            max_node_idx = node_idx;
        }
    }
    const nodes_num = max_node_idx + 1;
    const node_normals = try allocator.alloc(f64, nodes_num * 3);
    defer allocator.free(node_normals);
    @memset(node_normals, 0.0);

    for (0..mesh_coords.dims[0]) |ee| {
        const coord_inds = mesh_connect.getElem(ee);
        const sx = mesh_coords.getSlice(&[_]usize{ ee, 0, 0 }, 1);
        const sy = mesh_coords.getSlice(&[_]usize{ ee, 1, 0 }, 1);
        const sz = mesh_coords.getSlice(&[_]usize{ ee, 2, 0 }, 1);

        for (0..N) |nn| {
            const normal_vec = calcElementNodeNormal(N, nodal_derivs, sx, sy, sz, nn);
            const node_idx = coord_inds[nn];
            node_normals[node_idx * 3 + 0] += normal_vec[0];
            node_normals[node_idx * 3 + 1] += normal_vec[1];
            node_normals[node_idx * 3 + 2] += normal_vec[2];
        }
    }

    for (0..prep_count) |pp| {
        const orig_ee = elem_bboxes[pp].elem_idx;
        const coord_inds = mesh_connect.getElem(orig_ee);

        for (0..N) |nn| {
            const node_idx = coord_inds[nn];
            var normal_vec = [3]f64{
                node_normals[node_idx * 3 + 0],
                node_normals[node_idx * 3 + 1],
                node_normals[node_idx * 3 + 2],
            };
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

fn calculatePreparedNormals(
    allocator: std.mem.Allocator,
    mesh_coords: *const NDArray(f64),
    mesh_connect: anytype,
    elem_bboxes: []const ElemBBox,
    prep_count: usize,
    normal_type: shaderops.NormalType,
    comptime N: usize,
) !MappedNDArray(f64) {
    var prep_normals = try initPreparedNormals(
        allocator,
        mesh_coords,
        elem_bboxes,
        prep_count,
        N,
    );

    switch (normal_type) {
        .none => unreachable,
        .exact => calculatePreparedExactNormals(
            mesh_coords,
            &prep_normals.array,
            elem_bboxes,
            prep_count,
            N,
        ),
        .averaged => try calculatePreparedAveragedNormals(
            allocator,
            mesh_coords,
            mesh_connect,
            &prep_normals.array,
            elem_bboxes,
            prep_count,
            N,
        ),
    }

    return prep_normals;
}

fn initIdentityMappedNormals(
    allocator: std.mem.Allocator,
    prep_count: usize,
    comptime N: usize,
) !MappedNDArray(f64) {
    const prep_normals = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ prep_count, 3, N },
    );
    const map = try allocator.alloc(usize, prep_count);
    for (0..prep_count) |pp| {
        map[pp] = pp;
    }

    return .{
        .array = prep_normals,
        .map = map,
    };
}

fn calculateVisibleExactNormals(
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *NDArray(f64),
    comptime N: usize,
) void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (visible_orig_elem_indices, 0..) |orig_ee, pp| {
        const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, orig_ee);
        for (0..N) |nn| {
            var normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

fn calculateVisibleExactNormalsRange(
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
    comptime N: usize,
) void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (visible_start..visible_end) |pp| {
        const orig_ee = visible_orig_elem_indices[pp];
        const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, orig_ee);
        for (0..N) |nn| {
            var normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

fn calculateVisibleAveragedNormals(
    allocator: std.mem.Allocator,
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *NDArray(f64),
    comptime N: usize,
) !void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }

    const nodes_num = max_node_idx + 1;
    const node_normals = try allocator.alloc(f64, nodes_num * 3);
    defer allocator.free(node_normals);
    @memset(node_normals, 0.0);

    for (0..connect.getElemsNum()) |ee| {
        const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, ee);
        const coord_inds = connect.getElem(ee);

        for (0..N) |nn| {
            const normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            const node_idx = coord_inds[nn];
            node_normals[node_idx * 3 + 0] += normal_vec[0];
            node_normals[node_idx * 3 + 1] += normal_vec[1];
            node_normals[node_idx * 3 + 2] += normal_vec[2];
        }
    }

    for (visible_orig_elem_indices, 0..) |orig_ee, pp| {
        const coord_inds = connect.getElem(orig_ee);
        for (0..N) |nn| {
            const node_idx = coord_inds[nn];
            var normal_vec = [3]f64{
                node_normals[node_idx * 3 + 0],
                node_normals[node_idx * 3 + 1],
                node_normals[node_idx * 3 + 2],
            };
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn prepareVisibleNormals(
    allocator: std.mem.Allocator,
    mesh_type: anytype,
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    normal_type: shaderops.NormalType,
) !MappedNDArray(f64) {
    return switch (mesh_type) {
        .tri3 => blk: {
            var prep_normals = try initIdentityMappedNormals(
                allocator,
                visible_orig_elem_indices.len,
                3,
            );
            switch (normal_type) {
                .none => unreachable,
                .exact => calculateVisibleExactNormals(
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    3,
                ),
                .averaged => try calculateVisibleAveragedNormals(
                    allocator,
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    3,
                ),
            }
            break :blk prep_normals;
        },
        .tri6 => blk: {
            var prep_normals = try initIdentityMappedNormals(
                allocator,
                visible_orig_elem_indices.len,
                6,
            );
            switch (normal_type) {
                .none => unreachable,
                .exact => calculateVisibleExactNormals(
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    6,
                ),
                .averaged => try calculateVisibleAveragedNormals(
                    allocator,
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    6,
                ),
            }
            break :blk prep_normals;
        },
        .quad4ibi, .quad4newton => blk: {
            var prep_normals = try initIdentityMappedNormals(
                allocator,
                visible_orig_elem_indices.len,
                4,
            );
            switch (normal_type) {
                .none => unreachable,
                .exact => calculateVisibleExactNormals(
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    4,
                ),
                .averaged => try calculateVisibleAveragedNormals(
                    allocator,
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    4,
                ),
            }
            break :blk prep_normals;
        },
        .quad8 => blk: {
            var prep_normals = try initIdentityMappedNormals(
                allocator,
                visible_orig_elem_indices.len,
                8,
            );
            switch (normal_type) {
                .none => unreachable,
                .exact => calculateVisibleExactNormals(
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    8,
                ),
                .averaged => try calculateVisibleAveragedNormals(
                    allocator,
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    8,
                ),
            }
            break :blk prep_normals;
        },
        .quad9 => blk: {
            var prep_normals = try initIdentityMappedNormals(
                allocator,
                visible_orig_elem_indices.len,
                9,
            );
            switch (normal_type) {
                .none => unreachable,
                .exact => calculateVisibleExactNormals(
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    9,
                ),
                .averaged => try calculateVisibleAveragedNormals(
                    allocator,
                    coords_nodes,
                    connect,
                    visible_orig_elem_indices,
                    &prep_normals.array,
                    9,
                ),
            }
            break :blk prep_normals;
        },
    };
}

pub fn prepareVisibleExactNormalsRange(
    mesh_type: anytype,
    coords_nodes: *const Coords,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    prep_normals: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    switch (mesh_type) {
        .tri3 => calculateVisibleExactNormalsRange(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            prep_normals,
            visible_start,
            visible_end,
            3,
        ),
        .tri6 => calculateVisibleExactNormalsRange(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            prep_normals,
            visible_start,
            visible_end,
            6,
        ),
        .quad4ibi, .quad4newton => calculateVisibleExactNormalsRange(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            prep_normals,
            visible_start,
            visible_end,
            4,
        ),
        .quad8 => calculateVisibleExactNormalsRange(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            prep_normals,
            visible_start,
            visible_end,
            8,
        ),
        .quad9 => calculateVisibleExactNormalsRange(
            coords_nodes,
            connect,
            visible_orig_elem_indices,
            prep_normals,
            visible_start,
            visible_end,
            9,
        ),
    }
}

fn accumulateAveragedNodeNormalsRangeImpl(
    comptime N: usize,
    coords_nodes: *const Coords,
    connect: *const Connect,
    node_normals: []f64,
    elem_start: usize,
    elem_end: usize,
) void {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);

    for (elem_start..elem_end) |ee| {
        const coords_elem = gatherElemNodeCoords(N, coords_nodes, connect, ee);
        const coord_inds = connect.getElem(ee);

        for (0..N) |nn| {
            const normal_vec = calcElementNodeNormal(
                N,
                nodal_derivs,
                &coords_elem.x,
                &coords_elem.y,
                &coords_elem.z,
                nn,
            );
            const node_idx = coord_inds[nn];
            node_normals[node_idx * 3 + 0] += normal_vec[0];
            node_normals[node_idx * 3 + 1] += normal_vec[1];
            node_normals[node_idx * 3 + 2] += normal_vec[2];
        }
    }
}

pub fn accumulateAveragedNodeNormalsRange(
    mesh_type: anytype,
    coords_nodes: *const Coords,
    connect: *const Connect,
    node_normals: []f64,
    elem_start: usize,
    elem_end: usize,
) void {
    switch (mesh_type) {
        .tri3 => accumulateAveragedNodeNormalsRangeImpl(
            3,
            coords_nodes,
            connect,
            node_normals,
            elem_start,
            elem_end,
        ),
        .tri6 => accumulateAveragedNodeNormalsRangeImpl(
            6,
            coords_nodes,
            connect,
            node_normals,
            elem_start,
            elem_end,
        ),
        .quad4ibi, .quad4newton => accumulateAveragedNodeNormalsRangeImpl(
            4,
            coords_nodes,
            connect,
            node_normals,
            elem_start,
            elem_end,
        ),
        .quad8 => accumulateAveragedNodeNormalsRangeImpl(
            8,
            coords_nodes,
            connect,
            node_normals,
            elem_start,
            elem_end,
        ),
        .quad9 => accumulateAveragedNodeNormalsRangeImpl(
            9,
            coords_nodes,
            connect,
            node_normals,
            elem_start,
            elem_end,
        ),
    }
}

fn writeVisibleAveragedNormalsRangeImpl(
    comptime N: usize,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    node_normals: []const f64,
    prep_normals: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    for (visible_start..visible_end) |pp| {
        const coord_inds = connect.getElem(visible_orig_elem_indices[pp]);
        for (0..N) |nn| {
            const node_idx = coord_inds[nn];
            var normal_vec = [3]f64{
                node_normals[node_idx * 3 + 0],
                node_normals[node_idx * 3 + 1],
                node_normals[node_idx * 3 + 2],
            };
            normalizeNormal(&normal_vec);
            prep_normals.set(&[_]usize{ pp, 0, nn }, normal_vec[0]);
            prep_normals.set(&[_]usize{ pp, 1, nn }, normal_vec[1]);
            prep_normals.set(&[_]usize{ pp, 2, nn }, normal_vec[2]);
        }
    }
}

pub fn writeVisibleAveragedNormalsRange(
    mesh_type: anytype,
    connect: *const Connect,
    visible_orig_elem_indices: []const usize,
    node_normals: []const f64,
    prep_normals: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    switch (mesh_type) {
        .tri3 => writeVisibleAveragedNormalsRangeImpl(
            3,
            connect,
            visible_orig_elem_indices,
            node_normals,
            prep_normals,
            visible_start,
            visible_end,
        ),
        .tri6 => writeVisibleAveragedNormalsRangeImpl(
            6,
            connect,
            visible_orig_elem_indices,
            node_normals,
            prep_normals,
            visible_start,
            visible_end,
        ),
        .quad4ibi, .quad4newton => writeVisibleAveragedNormalsRangeImpl(
            4,
            connect,
            visible_orig_elem_indices,
            node_normals,
            prep_normals,
            visible_start,
            visible_end,
        ),
        .quad8 => writeVisibleAveragedNormalsRangeImpl(
            8,
            connect,
            visible_orig_elem_indices,
            node_normals,
            prep_normals,
            visible_start,
            visible_end,
        ),
        .quad9 => writeVisibleAveragedNormalsRangeImpl(
            9,
            connect,
            visible_orig_elem_indices,
            node_normals,
            prep_normals,
            visible_start,
            visible_end,
        ),
    }
}

pub fn prepareVisibleRasterHulls(
    allocator: std.mem.Allocator,
    camera: *const Camera,
    mesh_type: anytype,
    elem_coords: *NDArray(f64),
) !?NDArray(f64) {
    return switch (mesh_type) {
        .tri3 => null,
        .quad4ibi, .quad4newton => blk: {
            var raster_hull = try NDArray(f64).initFlat(
                allocator,
                &[_]usize{ elem_coords.dims[0], 2, 4 },
            );
            try buildAdaptiveHulls(4, camera, 0, elem_coords, &raster_hull);
            break :blk raster_hull;
        },
        .tri6 => blk: {
            var raster_hull = try NDArray(f64).initFlat(
                allocator,
                &[_]usize{ elem_coords.dims[0], 2, 6 },
            );
            try buildAdaptiveHulls(6, camera, 0, elem_coords, &raster_hull);
            break :blk raster_hull;
        },
        .quad8 => blk: {
            var raster_hull = try NDArray(f64).initFlat(
                allocator,
                &[_]usize{ elem_coords.dims[0], 2, 8 },
            );
            try buildAdaptiveHulls(8, camera, 0, elem_coords, &raster_hull);
            break :blk raster_hull;
        },
        .quad9 => blk: {
            var raster_hull = try NDArray(f64).initFlat(
                allocator,
                &[_]usize{ elem_coords.dims[0], 2, 8 },
            );
            try buildAdaptiveHulls(9, camera, 0, elem_coords, &raster_hull);
            break :blk raster_hull;
        },
    };
}

fn prepareVisibleRasterHullsRangeImpl(
    comptime N: usize,
    comptime NH: usize,
    camera: *const Camera,
    elem_coords: *const NDArray(f64),
    raster_hull: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    for (visible_start..visible_end) |pp| {
        var coords_elem: GatheredElemCoords(N) = undefined;
        const sx = elem_coords.getSlice(&[_]usize{ pp, 0, 0 }, 1);
        const sy = elem_coords.getSlice(&[_]usize{ pp, 1, 0 }, 1);
        const sz = elem_coords.getSlice(&[_]usize{ pp, 2, 0 }, 1);
        for (0..N) |nn| {
            coords_elem.x[nn] = sx[nn];
            coords_elem.y[nn] = sy[nn];
            coords_elem.z[nn] = sz[nn];
        }

        const hull_points = buildAdaptiveHullPoints(N, camera, coords_elem);
        for (0..NH) |nn| {
            raster_hull.set(&[_]usize{ pp, 0, nn }, hull_points.x[nn]);
            raster_hull.set(&[_]usize{ pp, 1, nn }, hull_points.y[nn]);
        }
    }
}

pub fn prepareVisibleRasterHullsRange(
    camera: *const Camera,
    mesh_type: anytype,
    elem_coords: *const NDArray(f64),
    raster_hull: *NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    switch (mesh_type) {
        .tri3 => {},
        .quad4ibi, .quad4newton => prepareVisibleRasterHullsRangeImpl(
            4,
            4,
            camera,
            elem_coords,
            raster_hull,
            visible_start,
            visible_end,
        ),
        .tri6 => prepareVisibleRasterHullsRangeImpl(
            6,
            6,
            camera,
            elem_coords,
            raster_hull,
            visible_start,
            visible_end,
        ),
        .quad8 => prepareVisibleRasterHullsRangeImpl(
            8,
            8,
            camera,
            elem_coords,
            raster_hull,
            visible_start,
            visible_end,
        ),
        .quad9 => prepareVisibleRasterHullsRangeImpl(
            9,
            8,
            camera,
            elem_coords,
            raster_hull,
            visible_start,
            visible_end,
        ),
    }
}

pub fn prepareSceneGeometry(
    comptime report_mode: report.ReportMode,
    ctx_report: report.ReportContext(report_mode),
    arena_alloc: std.mem.Allocator,
    camera: *const Camera,
    meshes: anytype,
    raster_hulls: []?NDArray(f64),
    elem_bboxes_by_mesh: [][]ElemBBox,
    elems_in_image_by_mesh: []usize,
    total_elems_num: *usize,
    total_elems_in_image: *usize,
) !void {
    total_elems_num.* = 0;
    total_elems_in_image.* = 0;

    for (meshes, 0..) |*mesh, ii| {
        const elems_num = mesh.coords.dims[0];
        total_elems_num.* += elems_num;
        elem_bboxes_by_mesh[ii] = try arena_alloc.alloc(ElemBBox, elems_num);
        raster_hulls[ii] = null;

        switch (mesh.mesh_type) {
            inline else => |mesh_tag| {
                const GK = comptime switch (mesh_tag) {
                    .tri3 => geomkerns.Tri3Kernel(),
                    .tri6 => geomkerns.Tri6Kernel(),
                    .quad4ibi => geomkerns.Quad4IBIKernel(),
                    .quad4newton => geomkerns.Quad4NewtonKernel(),
                    .quad8 => geomkerns.Quad89Kernel(8),
                    .quad9 => geomkerns.Quad89Kernel(9),
                };
                const N = GK.nodes_num;
                const NH = GK.hull_nodes_num;
                const dim_elem = 0;

                const normal_type = switch (mesh.shader) {
                    inline else => |s| s.normal_type,
                };

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    try elemsToRasterSIMD(
                        N,
                        f64,
                        camera,
                        dim_elem,
                        @constCast(&mesh.coords),
                    );
                } else {
                    try elemsToClipPxLengSIMD(N, f64, camera, dim_elem, &mesh.coords);
                }

                if (comptime GK.hull_nodes_num > 0) {
                    raster_hulls[ii] = try NDArray(f64).initFlat(
                        arena_alloc,
                        &[_]usize{ elems_num, 2, NH },
                    );
                    try buildAdaptiveHulls(
                        N,
                        camera,
                        dim_elem,
                        &mesh.coords,
                        &raster_hulls[ii].?,
                    );
                }

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    elems_in_image_by_mesh[ii] = try cullElemsCalcBBoxesTri3(
                        camera,
                        dim_elem,
                        &mesh.coords,
                        elem_bboxes_by_mesh[ii],
                    );
                } else {
                    const rh_ptr = if (raster_hulls[ii]) |*rh| rh else null;
                    elems_in_image_by_mesh[ii] = try cullElemsCalcBBoxesHighOrd(
                        N,
                        NH,
                        camera,
                        dim_elem,
                        &mesh.coords,
                        rh_ptr,
                        elem_bboxes_by_mesh[ii],
                    );
                }

                if (normal_type != .none) {
                    const prep_count = elems_in_image_by_mesh[ii];
                    const prep_normals = try calculatePreparedNormals(
                        arena_alloc,
                        &mesh.coords,
                        mesh.connect,
                        elem_bboxes_by_mesh[ii],
                        prep_count,
                        normal_type,
                        N,
                    );

                    switch (mesh.shader) {
                        inline else => |*s| {
                            s.elem_normals = prep_normals;
                        },
                    }
                }
            },
        }
        total_elems_in_image.* += elems_in_image_by_mesh[ii];
    }

    ctx_report.recordGeometry(total_elems_num.*, total_elems_in_image.*);
}

pub fn sceneTileElemOverlap(
    allocator: std.mem.Allocator,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []ElemBBox,
) !TilingOverlaps {
    const tiles_num = tiles_num_x * tiles_num_y;
    const tile_elem_counts = try allocator.alloc(usize, tiles_num);
    defer allocator.free(tile_elem_counts);
    @memset(tile_elem_counts, 0);

    for (0..elems_in_image_by_mesh.len) |mesh_idx| {
        for (0..elems_in_image_by_mesh[mesh_idx]) |ee| {
            const ebb = elem_bboxes_by_mesh[mesh_idx][ee];
            const tile_ind_min_x: u16 = ebb.x_min / tile_size;
            const tile_ind_max_x: u16 = (ebb.x_max + tile_size - 1) / tile_size;
            const tile_ind_min_y: u16 = ebb.y_min / tile_size;
            const tile_ind_max_y: u16 = (ebb.y_max + tile_size - 1) / tile_size;

            const tx_end = @min(tiles_num_x, @as(usize, tile_ind_max_x));
            const ty_end = @min(tiles_num_y, @as(usize, tile_ind_max_y));

            for (tile_ind_min_y..ty_end) |ty| {
                const row_off = ty * tiles_num_x;
                for (tile_ind_min_x..tx_end) |tx| {
                    tile_elem_counts[row_off + tx] += 1;
                }
            }
        }
    }

    var overlap_total: usize = 0;
    var num_active_tiles: usize = 0;
    for (tile_elem_counts) |count| {
        overlap_total += count;
        if (count > 0) num_active_tiles += 1;
    }

    const overlaps = try allocator.alloc(OverlapBBox, overlap_total);
    const active_tiles = try allocator.alloc(ActiveTile, num_active_tiles);

    const tile_write_inds = try allocator.alloc(usize, tiles_num);
    defer allocator.free(tile_write_inds);

    var current_off: usize = 0;
    var active_idx: usize = 0;
    for (tile_elem_counts, 0..) |count, ii| {
        tile_write_inds[ii] = current_off;
        if (count > 0) {
            const tx = ii % tiles_num_x;
            const ty = ii / tiles_num_x;
            active_tiles[active_idx] = .{
                .overlap_start = current_off,
                .overlap_count = count,
                .x_px_min = @intCast(tx * tile_size),
                .y_px_min = @intCast(ty * tile_size),
                .x_px_max = @min(screen_px_x, @as(u16, @intCast((tx + 1) * tile_size))),
                .y_px_max = @min(screen_px_y, @as(u16, @intCast((ty + 1) * tile_size))),
            };
            active_idx += 1;
        }
        current_off += count;
    }

    for (0..elems_in_image_by_mesh.len) |mesh_idx| {
        for (0..elems_in_image_by_mesh[mesh_idx]) |ee| {
            const ebb = elem_bboxes_by_mesh[mesh_idx][ee];
            const tx_start = ebb.x_min / tile_size;
            const tx_end = @min(
                tiles_num_x,
                @as(usize, (ebb.x_max + tile_size - 1) / tile_size),
            );
            const ty_start = ebb.y_min / tile_size;
            const ty_end = @min(
                tiles_num_y,
                @as(usize, (ebb.y_max + tile_size - 1) / tile_size),
            );

            for (ty_start..ty_end) |ty| {
                const tile_px_min_y = @as(u16, @intCast(ty * tile_size));
                const tile_px_max_y = @as(u16, @min(@as(u32, tile_px_min_y) +
                    tile_size, screen_px_y));
                const overlap_y_min = @max(ebb.y_min, tile_px_min_y);
                const overlap_y_max = @min(ebb.y_max, tile_px_max_y);

                for (tx_start..tx_end) |tx| {
                    const tile_px_min_x = @as(u16, @intCast(tx * tile_size));
                    const tile_px_max_x = @as(u16, @min(@as(u32, tile_px_min_x) +
                        tile_size, screen_px_x));

                    const tile_idx = ty * tiles_num_x + tx;
                    const write_idx = tile_write_inds[tile_idx];
                    overlaps[write_idx] = .{
                        .mesh_idx = mesh_idx,
                        .elem_idx = ebb.elem_idx,
                        .x_min = @max(ebb.x_min, tile_px_min_x),
                        .x_max = @min(ebb.x_max, tile_px_max_x),
                        .y_min = overlap_y_min,
                        .y_max = overlap_y_max,
                    };
                    tile_write_inds[tile_idx] += 1;
                }
            }
        }
    }

    return TilingOverlaps{ .overlaps = overlaps, .active_tiles = active_tiles };
}
