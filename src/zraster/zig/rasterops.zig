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
const vsd = @import("vecsimd.zig");
const ndarray = @import("ndarray.zig");
const meshio = @import("meshio.zig");
const buildconfig = @import("buildconfig.zig");
const tol = buildconfig.config.tolerance;
const cam = @import("camera.zig");
const shapefun = @import("shapefun.zig");
const matrix = @import("matstack.zig");

const pce = @import("parachunkexec.zig");
const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;
const hull = @import("hull.zig");
const shaderops = @import("shaderops.zig");
const report = @import("report.zig");

//==========================================================================================
// Low-Level Math, Bounding & Helpers
//==========================================================================================

pub fn edgeFun3Slices(
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
    v_px: buildconfig.VecSF,
    v_py: buildconfig.VecSF,
) buildconfig.VecSF {
    const v_x0: buildconfig.VecSF = @splat(x0);
    const v_y0: buildconfig.VecSF = @splat(y0);
    const v_x1: buildconfig.VecSF = @splat(x1);
    const v_y1: buildconfig.VecSF = @splat(y1);
    return (v_px - v_x0) * (v_y1 - v_y0) - (v_py - v_y0) * (v_x1 - v_x0);
}

pub fn boundIndMin(comptime T: type, val: f64) T {
    const val_int = @as(isize, @intFromFloat(@floor(val)));
    return @as(T, @intCast(@max(0, val_int)));
}

pub fn boundIndMax(comptime T: type, val: f64, max: T) T {
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

pub fn GatheredElemCoords(comptime N: usize) type {
    return struct {
        x: [N]f64,
        y: [N]f64,
        z: [N]f64,
    };
}

pub const ElemBBox = struct {
    elem_idx: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const RasterContext = struct {
    camera: *const cam.CameraPrepared,
    frame_idx: usize,
    tile_size: u16,
};

pub const MeshRaster = struct {
    coords: *const ndarray.NDArray(f64),
    hull: ?*const ndarray.NDArray(f64),
};

//==========================================================================================
// Coordinate Transformations
//==========================================================================================

fn transformWorldNodeToRaster(
    camera: *const cam.CameraPrepared,
    coord_world: vecstack.Vec3T(f64),
) vecstack.Vec3T(f64) {
    var coord_raster = matrix.Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);

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
    camera: *const cam.CameraPrepared,
    coord_world: vecstack.Vec3T(f64),
) vecstack.Vec3T(f64) {
    const x_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[0])) / camera.image_dims[0];
    const y_scale = camera.image_dist *
        @as(f64, @floatFromInt(camera.pixels_num[1])) / camera.image_dims[1];

    var coord_clip = matrix.Mat44Ops.mulVec3(f64, camera.world_to_cam_mat, coord_world);
    coord_clip.slice[0] *= x_scale;
    coord_clip.slice[1] *= -y_scale;
    coord_clip.slice[2] = -coord_clip.slice[2];
    return coord_clip;
}

pub fn nodesToRasterRangeInPlace(
    camera: *const cam.CameraPrepared,
    coords_nodes: *meshio.Coords,
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

pub fn nodesToClipPxLengRangeInPlace(
    camera: *const cam.CameraPrepared,
    coords_nodes: *meshio.Coords,
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

pub fn worldToRasterSIMD(
    comptime N: usize,
    comptime T: type,
    coord_world: vsd.Vec3SIMD(N, T),
    camera: *const cam.CameraPrepared,
) vsd.Vec3SIMD(N, T) {
    var coord_raster: vsd.Vec3SIMD(N, T) = vsd.mat44Mul(
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
    camera: *const cam.CameraPrepared,
    dim_elem: usize,
    elem_coord_arr: *ndarray.NDArray(T),
) !void {
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: vsd.Vec3SIMD(N, T) = try vsd.loadElemVec3SIMD(
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
    camera: *const cam.CameraPrepared,
    dim_elem: usize,
    elem_coord_arr: *ndarray.NDArray(T),
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
            vsd.Vec3SIMD(N, f64){
                .x = coords_raster.x,
                .y = coords_raster.y,
                .z = -coords_raster.z,
            },
        );
    }
}

//==========================================================================================
// Culling & Visibility
//==========================================================================================

pub fn calcVisibleNodeBBoxTri3(
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
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

pub fn calcVisibleNodeBBoxHighOrd(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
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

    const hull_points = hull.buildAdaptiveHullPoints(N, camera, coords_elem);
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

fn cullNodesCalcBBoxesTri3(
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
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

fn cullNodesCalcBBoxesHighOrd(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
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

        const hull_points = hull.buildAdaptiveHullPoints(N, camera, coords_elem);
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

pub fn prepareVisibleWorkspace(
    comptime MT: MeshType,
    allocator: std.mem.Allocator,
    camera: *const cam.CameraPrepared,
    connect: *const meshio.Connect,
    coords_nodes: *const meshio.Coords,
    elem_bboxes: *[]ElemBBox,
    visible_orig_elem_indices: *[]usize,
    elems_in_image: *usize,
) !void {
    const elems_num = connect.getElemsNum();
    elem_bboxes.* = try allocator.alloc(ElemBBox, elems_num);

    elems_in_image.* = if (MT == .tri3)
        cullNodesCalcBBoxesTri3(
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        )
    else
        cullNodesCalcBBoxesHighOrd(
            comptime MT.getNodesNum(),
            camera,
            coords_nodes,
            connect,
            elem_bboxes.*,
        );

    visible_orig_elem_indices.* = try allocator.alloc(usize, elems_in_image.*);
    for (0..elems_in_image.*) |pp| {
        visible_orig_elem_indices.*[pp] = elem_bboxes.*[pp].elem_idx;
    }
}

//==========================================================================================
// Element Data Gathering
//==========================================================================================

pub fn gatherElemNodeCoords(
    comptime N: usize,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
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

pub fn loadElemVec3Slices(
    comptime N: usize,
    comptime T: type,
    elem_array: *const ndarray.NDArray(T),
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

//==========================================================================================
// Raster Hull Generation
//==========================================================================================

pub fn prepareVisibleRasterHulls(
    comptime MT: MeshType,
    allocator: std.mem.Allocator,
    camera: *const cam.CameraPrepared,
    elem_coords: *ndarray.NDArray(f64),
) !?ndarray.NDArray(f64) {
    if (MT == .tri3) return null;

    const N = comptime MT.getNodesNum();
    var raster_hull = try ndarray.NDArray(f64).initFlat(
        allocator,
        &[_]usize{ elem_coords.dims[0], 2, N },
    );
    try hull.buildAdaptiveHulls(N, camera, 0, elem_coords, &raster_hull);
    return raster_hull;
}

pub fn prepareVisibleRasterHullsRange(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    elem_coords: *const ndarray.NDArray(f64),
    raster_hull: *ndarray.NDArray(f64),
    visible_start: usize,
    visible_end: usize,
) void {
    if (MT == .tri3) return;

    const N = comptime MT.getNodesNum();
    const NH = comptime MT.getNumHullPoints();

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

        const hull_points = hull.buildAdaptiveHullPoints(N, camera, coords_elem);
        for (0..NH) |nn| {
            raster_hull.set(&[_]usize{ pp, 0, nn }, hull_points.x[nn]);
            raster_hull.set(&[_]usize{ pp, 1, nn }, hull_points.y[nn]);
        }
    }
}

//==========================================================================================
// Scene-Tile Binning
//==========================================================================================

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

const TilingCountStage = struct {
    tile_elem_counts: []std.atomic.Value(usize),
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    elems_num: usize,
    ebb_slice: []const ElemBBox,
};

fn runTilingCount(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const s: *TilingCountStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const ebb = s.ebb_slice[ee];
        const tx_start: usize = ebb.x_min / s.tile_size;
        const tx_end: usize = @min(s.tiles_num_x, @as(usize, (ebb.x_max +
            s.tile_size - 1) / s.tile_size));
        const ty_start: usize = ebb.y_min / s.tile_size;
        const ty_end: usize = @min(s.tiles_num_y, @as(usize, (ebb.y_max +
            s.tile_size - 1) / s.tile_size));

        for (ty_start..ty_end) |ty| {
            const row_off = ty * s.tiles_num_x;
            for (tx_start..tx_end) |tx| {
                _ = s.tile_elem_counts[row_off + tx].fetchAdd(1, .monotonic);
            }
        }
    }
}

const TilingFillStage = struct {
    tile_write_inds: []std.atomic.Value(usize),
    overlaps: []OverlapBBox,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    mesh_idx: usize,
    ebb_slice: []const ElemBBox,
};

fn runTilingFill(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const s: *TilingFillStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const ebb = s.ebb_slice[ee];
        const tx_start = ebb.x_min / s.tile_size;
        const tx_end = @min(
            s.tiles_num_x,
            @as(usize, (ebb.x_max + s.tile_size - 1) / s.tile_size),
        );
        const ty_start = ebb.y_min / s.tile_size;
        const ty_end = @min(
            s.tiles_num_y,
            @as(usize, (ebb.y_max + s.tile_size - 1) / s.tile_size),
        );

        for (ty_start..ty_end) |ty| {
            const tile_px_min_y = @as(u16, @intCast(ty * s.tile_size));
            const tile_px_max_y = @as(u16, @min(@as(u32, tile_px_min_y) +
                s.tile_size, s.screen_px_y));
            const overlap_y_min = @max(ebb.y_min, tile_px_min_y);
            const overlap_y_max = @min(ebb.y_max, tile_px_max_y);

            for (tx_start..tx_end) |tx| {
                const tile_px_min_x = @as(u16, @intCast(tx * s.tile_size));
                const tile_px_max_x = @as(u16, @min(@as(u32, tile_px_min_x) +
                    s.tile_size, s.screen_px_x));

                const tile_idx = ty * s.tiles_num_x + tx;
                const write_idx = s.tile_write_inds[tile_idx].fetchAdd(1, .monotonic);
                s.overlaps[write_idx] = .{
                    .mesh_idx = s.mesh_idx,
                    .elem_idx = ebb.elem_idx,
                    .x_min = @max(ebb.x_min, tile_px_min_x),
                    .x_max = @min(ebb.x_max, tile_px_max_x),
                    .y_min = overlap_y_min,
                    .y_max = overlap_y_max,
                };
            }
        }
    }
}

pub fn sceneTileElemOverlap(
    allocator: std.mem.Allocator,
    chunk_exec: ?*pce.ParaChunkExecutor,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []ElemBBox,
) !TilingOverlaps {
    const tiles_num = tiles_num_x * tiles_num_y;
    const tile_elem_counts = try allocator.alloc(std.atomic.Value(usize), tiles_num);
    defer allocator.free(tile_elem_counts);
    for (tile_elem_counts) |*count| count.* = std.atomic.Value(usize).init(0);

    for (0..elems_in_image_by_mesh.len) |mesh_idx| {
        const elems_num = elems_in_image_by_mesh[mesh_idx];
        if (elems_num == 0) continue;

        var count_stage = TilingCountStage{
            .tile_elem_counts = tile_elem_counts,
            .tile_size = tile_size,
            .tiles_num_x = tiles_num_x,
            .tiles_num_y = tiles_num_y,
            .elems_num = elems_num,
            .ebb_slice = elem_bboxes_by_mesh[mesh_idx],
        };

        const chunk_size = pce.getChunkSize(
            elems_num,
            pce.getWorkerCount(chunk_exec),
        );
        pce.runStaticRange(
            chunk_exec,
            &count_stage,
            runTilingCount,
            elems_num,
            chunk_size,
        );
    }

    var overlap_total: usize = 0;
    var num_active_tiles: usize = 0;
    for (tile_elem_counts) |count_atomic| {
        const count = count_atomic.load(.monotonic);
        overlap_total += count;
        if (count > 0) num_active_tiles += 1;
    }

    const overlaps = try allocator.alloc(OverlapBBox, overlap_total);
    const active_tiles = try allocator.alloc(ActiveTile, num_active_tiles);

    const tile_write_inds = try allocator.alloc(std.atomic.Value(usize), tiles_num);
    defer allocator.free(tile_write_inds);

    var current_off: usize = 0;
    var active_idx: usize = 0;
    for (tile_elem_counts, 0..) |count_atomic, ii| {
        const count = count_atomic.load(.monotonic);
        tile_write_inds[ii] = std.atomic.Value(usize).init(current_off);
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
        const elems_num = elems_in_image_by_mesh[mesh_idx];
        if (elems_num == 0) continue;

        var fill_stage = TilingFillStage{
            .tile_write_inds = tile_write_inds,
            .overlaps = overlaps,
            .tile_size = tile_size,
            .tiles_num_x = tiles_num_x,
            .tiles_num_y = tiles_num_y,
            .screen_px_x = screen_px_x,
            .screen_px_y = screen_px_y,
            .mesh_idx = mesh_idx,
            .ebb_slice = elem_bboxes_by_mesh[mesh_idx],
        };

        const chunk_size = pce.getChunkSize(
            elems_num,
            pce.getWorkerCount(chunk_exec),
        );
        pce.runStaticRange(
            chunk_exec,
            &fill_stage,
            runTilingFill,
            elems_num,
            chunk_size,
        );
    }

    return TilingOverlaps{ .overlaps = overlaps, .active_tiles = active_tiles };
}
