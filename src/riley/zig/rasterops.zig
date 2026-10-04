// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const vecstack = @import("vecstack.zig");
const vsd = @import("vecsimd.zig");
const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const vecslice = @import("vecslice.zig");
const meshio = @import("meshio.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const tol = buildconfig.config.tol;
const cam = @import("camera.zig");
const shapefun = @import("shapefun.zig");
const matrix = @import("matstack.zig");
const rastcfg = @import("rasterconfig.zig");

const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;
const hull = @import("hull.zig");
const shaderops = @import("shaderops.zig");
const db = @import("distortbounds.zig");

pub const RootClass = enum(u8) {
    one_root,
    multi_root,
};

pub const Bucket = enum(u8) {
    tri3,
    tri3opt,
    tri6_one_root,
    tri6_multi_root,
    quad4_one_root,
    quad4_multi_root,
    quad8_one_root,
    quad8_multi_root,
    quad9_one_root,
    quad9_multi_root,
};

pub const bucket_count = @typeInfo(Bucket).@"enum".fields.len;

pub const BucketRange = struct {
    start: usize = 0,
    count: usize = 0,
};

pub fn bucketForElem(
    mesh_type: MeshType,
    classes: []const RootClass,
    elem_idx: usize,
) Bucket {
    return switch (mesh_type) {
        .tri3 => .tri3,
        .tri3opt => .tri3opt,
        .tri6 => if (classes[elem_idx] == .one_root)
            .tri6_one_root
        else
            .tri6_multi_root,
        .quad4 => if (classes[elem_idx] == .one_root)
            .quad4_one_root
        else
            .quad4_multi_root,
        .quad8 => if (classes[elem_idx] == .one_root)
            .quad8_one_root
        else
            .quad8_multi_root,
        .quad9 => if (classes[elem_idx] == .one_root)
            .quad9_one_root
        else
            .quad9_multi_root,
    };
}

pub fn bucketMeshType(comptime bucket: Bucket) MeshType {
    return switch (bucket) {
        .tri3 => .tri3,
        .tri3opt => .tri3opt,
        .tri6_one_root, .tri6_multi_root => .tri6,
        .quad4_one_root, .quad4_multi_root => .quad4,
        .quad8_one_root, .quad8_multi_root => .quad8,
        .quad9_one_root, .quad9_multi_root => .quad9,
    };
}

pub fn bucketRootClass(comptime bucket: Bucket) RootClass {
    return switch (bucket) {
        .tri6_multi_root,
        .quad4_multi_root,
        .quad8_multi_root,
        .quad9_multi_root,
        => .multi_root,
        else => .one_root,
    };
}

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn edgeFun3Slices(
    comptime ind0: usize,
    comptime ind1: usize,
    comptime ind2: usize,
    x: []const F,
    y: []const F,
) F {
    return ((x[ind2] - x[ind0]) * (y[ind1] - y[ind0]) -
        (y[ind2] - y[ind0]) * (x[ind1] - x[ind0]));
}

pub inline fn edgeFun3(x0: F, y0: F, x1: F, y1: F, px: F, py: F) F {
    return (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
}

pub inline fn edgeFun3SIMD(
    x0: F,
    y0: F,
    x1: F,
    y1: F,
    v_px: buildconfig.VecSF,
    v_py: buildconfig.VecSF,
) buildconfig.VecSF {
    const v_x0: buildconfig.VecSF = @splat(x0);
    const v_y0: buildconfig.VecSF = @splat(y0);
    const v_x1: buildconfig.VecSF = @splat(x1);
    const v_y1: buildconfig.VecSF = @splat(y1);
    return (v_px - v_x0) * (v_y1 - v_y0) - (v_py - v_y0) * (v_x1 - v_x0);
}

pub fn boundIndMin(comptime T: type, val: F) T {
    const val_int = @as(isize, @intFromFloat(@floor(val)));
    return @as(T, @intCast(@max(0, val_int)));
}

pub fn boundIndMax(comptime T: type, val: F, max: T) T {
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

pub fn RasterCoords2D(comptime N: usize) type {
    return struct {
        x: [N]F,
        y: [N]F,
    };
}

pub const ElemBBox = struct {
    elem_idx: usize,
    x_min: i32,
    x_max: i32,
    y_min: i32,
    y_max: i32,
};

pub const DistortElemBBox = struct {
    box_ints: ElemBBox,
    box_floats: db.DistortBounds,
};

pub fn calcVisibleDistortBBox(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
    hull_mode: rastcfg.HullMode,
    raster_halo_px: u16,
    ideal_sensor: db.DistortBounds,
    edge_spacing_px: F,
) ?DistortElemBBox {
    const N = comptime MT.getNodesNum();
    const coords = gatherElemNodeCoords(N, coords_nodes, connect, elem_idx);
    if (isElemBehindCamera(N, coords) or !isNodeZInvertible(N, coords)) {
        return null;
    }

    var ideal_bounds = db.DistortBounds.initEmpty();
    if (comptime MT == .tri3 or MT == .tri3opt) {
        const nodes = RasterCoords2D(N){ .x = coords.x, .y = coords.y };

        if (isTri3BackfaceRaster(nodes)) return null;

        ideal_bounds = db.DistortBounds.fromCoords2D(N, nodes);
    } else {
        const nodes = projectClipToIdealRaster(N, camera, coords);
        const root_class = classifyHighOrdFacing(N, nodes) orelse return null;
        if (root_class == .multi_root) {
            const points = hull.buildMultiRootHullFromClip(N, camera, coords);
            for (0..points.count) |nn| {
                ideal_bounds.include(points.x[nn], points.y[nn]);
            }
        } else {
            const NH = comptime MT.getNumHullPoints();
            const points = hull.buildAdaptiveHullPointsFromClip(
                N,
                camera,
                coords,
                hull_mode,
            );
            ideal_bounds = db.DistortBounds.fromCoords2D(NH, points);
        }
    }

    const walk = ideal_bounds.intersect(ideal_sensor) orelse return null;

    var observed = db.sampleRectEdges(camera, walk, edge_spacing_px);

    if (!isOnScreen(
        camera,
        observed.x_min,
        observed.x_max,
        observed.y_min,
        observed.y_max,
        raster_halo_px,
    )) return null;

    const halo: F = @floatFromInt(raster_halo_px);
    const width: F = @floatFromInt(camera.pixels_num[0]);
    const height: F = @floatFromInt(camera.pixels_num[1]);
    observed = observed.intersect(.{
        .x_min = -halo,
        .x_max = width + halo,
        .y_min = -halo,
        .y_max = height + halo,
    }) orelse return null;

    return .{
        .box_ints = .{
            .elem_idx = elem_idx,
            .x_min = boundIndMinSigned(observed.x_min, -@as(i32, raster_halo_px)),
            .x_max = boundIndMaxSigned(
                observed.x_max,
                @as(i32, @intCast(camera.pixels_num[0])) + raster_halo_px,
            ),
            .y_min = boundIndMinSigned(observed.y_min, -@as(i32, raster_halo_px)),
            .y_max = boundIndMaxSigned(
                observed.y_max,
                @as(i32, @intCast(camera.pixels_num[1])) + raster_halo_px,
            ),
        },
        .box_floats = observed,
    };
}

pub const RasterContext = struct {
    camera: *const cam.CameraPrepared,
    config: rastcfg.RasterConfig,
    frame_idx: usize,
    tile_size: u16,
    multi_root_by_mesh: []const ?MultiRootPrepared = &.{},
};

pub const MultiRootPrepared = struct {
    hull_x: matslice.MatSlice(F),
    hull_y: matslice.MatSlice(F),
    hull_count: vecslice.VecSlice(u8),
    indices: matslice.MatSlice(u8),
    valid_depth: vecslice.VecSlice(u8),
    slot_by_visible_elem: vecslice.VecSlice(u32),
};

//------------------------------------------------------------------------------------------
// Coordinate Transformations
//------------------------------------------------------------------------------------------

pub fn nodesToRasterRangeInPlace(
    camera: *const cam.CameraPrepared,
    coords_nodes: *meshio.Coords,
    node_start: usize,
    node_end: usize,
) void {
    for (node_start..node_end) |nn| {
        const coord_world = coords_nodes.getVec3(nn);
        const coord_raster = transformWorldNodeToRaster(camera, coord_world);
        coords_nodes.mat.set(nn, 0, coord_raster.vec[0]);
        coords_nodes.mat.set(nn, 1, coord_raster.vec[1]);
        coords_nodes.mat.set(nn, 2, coord_raster.vec[2]);
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
        coords_nodes.mat.set(nn, 0, coord_clip.vec[0]);
        coords_nodes.mat.set(nn, 1, coord_clip.vec[1]);
        coords_nodes.mat.set(nn, 2, coord_clip.vec[2]);
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
        @as(F, @floatFromInt(camera.pixels_num[0])) / camera.image_dims[0];
    const y_scale = camera.image_dist *
        @as(F, @floatFromInt(camera.pixels_num[1])) / camera.image_dims[1];

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world = try vsd.loadElemVec3SIMD(
            N,
            F,
            elem_coord_arr,
            ee,
        );
        var coords_raster = vsd.mat44Mul(
            N,
            F,
            camera.world_to_cam_mat,
            coords_world,
        );
        coords_raster.x *= @splat(x_scale);
        coords_raster.y *= @splat(-y_scale);
        try vsd.saveElemVec3SIMD(
            N,
            F,
            elem_coord_arr,
            ee,
            vsd.Vec3SIMD(N, F){
                .x = coords_raster.x,
                .y = coords_raster.y,
                .z = -coords_raster.z,
            },
        );
    }
}

//------------------------------------------------------------------------------------------
// Culling & Visibility
//------------------------------------------------------------------------------------------

pub fn calcVisibleNodeBBoxTri3(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
) ?ElemBBox {
    return calcVisibleNodeBBoxTri3WithHalo(MT, camera, coords_nodes, connect, elem_idx, 0);
}

pub fn calcVisibleNodeBBoxTri3WithHalo(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
    raster_halo_px: u16,
) ?ElemBBox {
    comptime {
        if (MT != .tri3 and MT != .tri3opt) {
            @compileError("calcVisibleNodeBBoxTri3 only supps .tri3 and .tri3opt");
        }
    }

    const N = comptime MT.getNodesNum();
    const coords_ideal = gatherElemNodeCoords(N, coords_nodes, connect, elem_idx);

    if (isElemBehindCamera(N, coords_ideal)) {
        return null;
    }

    const coords_ideal_raster = RasterCoords2D(N){
        .x = coords_ideal.x,
        .y = coords_ideal.y,
    };

    if (isTri3BackfaceRaster(coords_ideal_raster)) {
        return null;
    }
    if (!isNodeZInvertible(N, coords_ideal)) {
        return null;
    }

    const coords_distorted = distortIdealRasterCoords(
        N,
        camera,
        coords_ideal_raster,
    );
    return calcBBoxFromRasterCoords(
        N,
        camera,
        elem_idx,
        coords_distorted,
        raster_halo_px,
    );
}

pub fn calcVisibleNodeBBoxHighOrd(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
    hull_mode: rastcfg.HullMode,
) ?ElemBBox {
    return calcVisibleNodeBBoxHighOrdWithHalo(
        MT,
        camera,
        coords_nodes,
        connect,
        elem_idx,
        hull_mode,
        0,
    );
}

pub fn calcVisibleNodeBBoxHighOrdWithHalo(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
    hull_mode: rastcfg.HullMode,
    raster_halo_px: u16,
) ?ElemBBox {
    comptime {
        if (MT == .tri3) {
            @compileError("calcVisibleNodeBBoxHighOrd does not supp .tri3");
        }
    }

    const N = comptime MT.getNodesNum();
    const NH = comptime MT.getNumHullPoints();
    const coords_clip = gatherElemNodeCoords(N, coords_nodes, connect, elem_idx);

    if (isElemBehindCamera(N, coords_clip)) {
        return null;
    }
    if (!isNodeZInvertible(N, coords_clip)) {
        return null;
    }

    const coords_ideal_raster = projectClipToIdealRaster(N, camera, coords_clip);
    const root_class = classifyHighOrdFacing(N, coords_ideal_raster) orelse
        return null;

    if (root_class == .multi_root) {
        const points = hull.buildMultiRootHullFromClip(N, camera, coords_clip);
        var bounds = db.DistortBounds.initEmpty();
        for (0..points.count) |nn| {
            bounds.include(points.x[nn], points.y[nn]);
        }
        return calcBBoxFromBounds(camera, elem_idx, bounds, raster_halo_px);
    }

    const hull_points_ideal = hull.buildAdaptiveHullPointsFromClip(
        N,
        camera,
        coords_clip,
        hull_mode,
    );
    const hull_ideal_raster = packHullPointsAsRasterCoords(NH, hull_points_ideal);
    const hull_distorted = distortIdealRasterCoords(
        NH,
        camera,
        hull_ideal_raster,
    );

    return calcBBoxFromRasterCoords(
        NH,
        camera,
        elem_idx,
        hull_distorted,
        raster_halo_px,
    );
}

//------------------------------------------------------------------------------------------
// Elem Data Gathering
//------------------------------------------------------------------------------------------
pub fn GatheredElemCoords(comptime N: usize) type {
    return struct {
        x: [N]F,
        y: [N]F,
        z: [N]F,
    };
}

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

//------------------------------------------------------------------------------------------
// Raster Hull Generation
//------------------------------------------------------------------------------------------

pub fn prepareVisibleRasterHullsRange(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    elem_coords: *const ndarray.NDArray(F),
    raster_hull: *ndarray.NDArray(F),
    root_classes: []const RootClass,
    hull_mode: rastcfg.HullMode,
    visible_start: usize,
    visible_end: usize,
) void {
    if (MT == .tri3) return;

    const N = comptime MT.getNodesNum();
    const NH = comptime MT.getNumHullPoints();

    for (visible_start..visible_end) |pp| {
        if (root_classes[pp] == .multi_root) continue;
        var coords_elem: GatheredElemCoords(N) = undefined;
        const sx = elem_coords.getSlice(&[_]usize{ pp, 0, 0 }, 1);
        const sy = elem_coords.getSlice(&[_]usize{ pp, 1, 0 }, 1);
        const sz = elem_coords.getSlice(&[_]usize{ pp, 2, 0 }, 1);
        for (0..N) |nn| {
            coords_elem.x[nn] = sx[nn];
            coords_elem.y[nn] = sy[nn];
            coords_elem.z[nn] = sz[nn];
        }

        const hull_points = hull.buildAdaptiveHullPointsFromClip(
            N,
            camera,
            coords_elem,
            hull_mode,
        );
        for (0..NH) |nn| {
            raster_hull.set(&[_]usize{ pp, 0, nn }, hull_points.x[nn]);
            raster_hull.set(&[_]usize{ pp, 1, nn }, hull_points.y[nn]);
        }
    }
}

//------------------------------------------------------------------------------------------
// Scene-Tile Binning
//------------------------------------------------------------------------------------------

pub const OverlapBBox = struct {
    mesh_idx: usize,
    elem_idx: usize,
    x_min: i32,
    x_max: i32,
    y_min: i32,
    y_max: i32,
};

pub fn clipElemBBoxToTile(
    elem_bbox: ElemBBox,
    floating: ?db.DistortBounds,
    mesh_idx: usize,
    scratch_x_min: i32,
    scratch_x_max: i32,
    scratch_y_min: i32,
    scratch_y_max: i32,
) OverlapBBox {
    if (floating) |bounds| {
        const clamp_x_min = @max(bounds.x_min, @as(F, @floatFromInt(scratch_x_min)));
        const clamp_x_max = @min(bounds.x_max, @as(F, @floatFromInt(scratch_x_max)));
        const clamp_y_min = @max(bounds.y_min, @as(F, @floatFromInt(scratch_y_min)));
        const clamp_y_max = @min(bounds.y_max, @as(F, @floatFromInt(scratch_y_max)));

        return .{
            .mesh_idx = mesh_idx,
            .elem_idx = elem_bbox.elem_idx,
            .x_min = boundIndMinSigned(clamp_x_min, scratch_x_min),
            .x_max = boundIndMaxSigned(clamp_x_max, scratch_x_max),
            .y_min = boundIndMinSigned(clamp_y_min, scratch_y_min),
            .y_max = boundIndMaxSigned(clamp_y_max, scratch_y_max),
        };
    }
    return .{
        .mesh_idx = mesh_idx,
        .elem_idx = elem_bbox.elem_idx,
        .x_min = @max(elem_bbox.x_min, scratch_x_min),
        .x_max = @min(elem_bbox.x_max, scratch_x_max),
        .y_min = @max(elem_bbox.y_min, scratch_y_min),
        .y_max = @min(elem_bbox.y_max, scratch_y_max),
    };
}

pub const ActiveTile = struct {
    overlap_start: usize,
    overlap_count: usize,
    buckets: [bucket_count]BucketRange = [_]BucketRange{.{}} ** bucket_count,
    x_px_min: u16,
    y_px_min: u16,
    x_px_max: u16,
    y_px_max: u16,
    scratch_x_px_min: i32,
    scratch_y_px_min: i32,
    scratch_x_px_max: i32,
    scratch_y_px_max: i32,
    // Global sub-pixel modes populate these exact target ownership bounds.
    // Tile-local modes do not use them.
    core_subx_min: i32 = 0,
    core_suby_min: i32 = 0,
    core_subx_max: i32 = 0,
    core_suby_max: i32 = 0,
    scratch_subx_min: i32 = 0,
    scratch_suby_min: i32 = 0,
    scratch_subx_max: i32 = 0,
    scratch_suby_max: i32 = 0,
};

pub const TilingOverlaps = struct {
    overlaps: []OverlapBBox,
    active_tiles: []ActiveTile,
};

pub fn sceneTileElemOverlap(
    allocator: std.mem.Allocator,
    chunk_exec: *pce.ParaChunkExecutor,
    workers_num: usize,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    halo_px: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []ElemBBox,
    elem_float_bboxes_by_mesh: []const ?[]db.DistortBounds,
    mesh_types: []const MeshType,
    root_classes_by_mesh: []const []RootClass,
) !TilingOverlaps {
    const tiles_num = tiles_num_x * tiles_num_y;

    // Stage 1 - Parallel Counting Pass: Determine the number of elem-tile
    // intersections across all meshes.
    const tile_elem_counts = try allocator.alloc(
        std.atomic.Value(usize),
        tiles_num * bucket_count,
    );
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
            .halo_px = halo_px,
            .elems_num = elems_num,
            .elem_bbox_slice = elem_bboxes_by_mesh[mesh_idx],
            .mesh_type = mesh_types[mesh_idx],
            .root_classes = root_classes_by_mesh[mesh_idx],
        };

        const chunk_size = scalingpolicy.tilingChunkSize(
            elems_num,
            workers_num,
        );

        pce.runStaticRange(
            chunk_exec,
            &count_stage,
            runTilingCount,
            elems_num,
            chunk_size,
        );
    }

    // Stage 2 - Serial Management Pass: Allocate overlap buffs and calc
    // global offsets for each tile.
    var overlap_total: usize = 0;
    var num_active_tiles: usize = 0;
    for (0..tiles_num) |tile_idx| {
        var count: usize = 0;
        for (0..bucket_count) |bb| {
            count += tile_elem_counts[tile_idx * bucket_count + bb].load(.monotonic);
        }
        overlap_total += count;
        if (count > 0) num_active_tiles += 1;
    }

    const overlaps = try allocator.alloc(OverlapBBox, overlap_total);
    const active_tiles = try allocator.alloc(ActiveTile, num_active_tiles);

    const tile_write_inds = try allocator.alloc(
        std.atomic.Value(usize),
        tiles_num * bucket_count,
    );
    defer allocator.free(tile_write_inds);

    var current_off: usize = 0;
    var active_idx: usize = 0;
    for (0..tiles_num) |ii| {
        var count: usize = 0;
        var ranges = [_]BucketRange{.{}} ** bucket_count;
        for (0..bucket_count) |bb| {
            const bucket_count_here =
                tile_elem_counts[ii * bucket_count + bb].load(.monotonic);
            ranges[bb] = .{ .start = current_off + count, .count = bucket_count_here };
            tile_write_inds[ii * bucket_count + bb] =
                std.atomic.Value(usize).init(current_off + count);
            count += bucket_count_here;
        }

        if (count > 0) {
            const tx = ii % tiles_num_x;
            const ty = ii / tiles_num_x;

            active_tiles[active_idx] = .{
                .overlap_start = current_off,
                .overlap_count = count,
                .buckets = ranges,
                .x_px_min = @intCast(tx * tile_size),
                .y_px_min = @intCast(ty * tile_size),
                .x_px_max = @min(screen_px_x, @as(u16, @intCast((tx + 1) * tile_size))),
                .y_px_max = @min(screen_px_y, @as(u16, @intCast((ty + 1) * tile_size))),
                .scratch_x_px_min = @as(i32, @intCast(tx * tile_size)) - halo_px,
                .scratch_y_px_min = @as(i32, @intCast(ty * tile_size)) - halo_px,
                .scratch_x_px_max = @as(i32, @intCast(@min(screen_px_x, @as(u16, @intCast((tx + 1) * tile_size))))) + halo_px,
                .scratch_y_px_max = @as(i32, @intCast(@min(screen_px_y, @as(u16, @intCast((ty + 1) * tile_size))))) + halo_px,
            };

            active_idx += 1;
        }
        current_off += count;
    }

    // Stage 3 - Parallel Filling Pass: Populate the allocated buffs with
    // elem metadata and clipped bounding boxes.
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
            .halo_px = halo_px,
            .mesh_idx = mesh_idx,
            .elem_bbox_slice = elem_bboxes_by_mesh[mesh_idx],
            .float_bbox_slice = elem_float_bboxes_by_mesh[mesh_idx],
            .mesh_type = mesh_types[mesh_idx],
            .root_classes = root_classes_by_mesh[mesh_idx],
        };

        const chunk_size = scalingpolicy.tilingChunkSize(
            elems_num,
            workers_num,
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

const TilingCountStage = struct {
    tile_elem_counts: []std.atomic.Value(usize),
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    halo_px: u16,
    elems_num: usize,
    elem_bbox_slice: []const ElemBBox,
    mesh_type: MeshType,
    root_classes: []const RootClass,
};

fn runTilingCount(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const tiling: *TilingCountStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const elem_bbox = tiling.elem_bbox_slice[ee];
        const bucket_idx = @intFromEnum(bucketForElem(
            tiling.mesh_type,
            tiling.root_classes,
            elem_bbox.elem_idx,
        ));
        const tile_range = calcElemTileRange(elem_bbox, tiling.tile_size, tiling.halo_px, tiling.tiles_num_x, tiling.tiles_num_y);
        const tx_start = tile_range.tx_start;
        const tx_end = tile_range.tx_end;
        const ty_start = tile_range.ty_start;
        const ty_end = tile_range.ty_end;

        for (ty_start..ty_end) |ty| {
            const row_off = ty * tiling.tiles_num_x;
            for (tx_start..tx_end) |tx| {
                _ = tiling.tile_elem_counts[
                    (row_off + tx) * bucket_count + bucket_idx
                ].fetchAdd(1, .monotonic);
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
    halo_px: u16,
    mesh_idx: usize,
    elem_bbox_slice: []const ElemBBox,
    float_bbox_slice: ?[]const db.DistortBounds,
    mesh_type: MeshType,
    root_classes: []const RootClass,
};

fn runTilingFill(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const tiling: *TilingFillStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const elem_bbox = tiling.elem_bbox_slice[ee];
        const bucket_idx = @intFromEnum(bucketForElem(
            tiling.mesh_type,
            tiling.root_classes,
            elem_bbox.elem_idx,
        ));
        const floating: ?db.DistortBounds = if (tiling.float_bbox_slice) |float_bboxes|
            float_bboxes[ee]
        else
            null;
        const tile_range = calcElemTileRange(elem_bbox, tiling.tile_size, tiling.halo_px, tiling.tiles_num_x, tiling.tiles_num_y);
        const tx_start = tile_range.tx_start;
        const tx_end = tile_range.tx_end;
        const ty_start = tile_range.ty_start;
        const ty_end = tile_range.ty_end;

        for (ty_start..ty_end) |ty| {
            const tile_px_min_y = @as(u16, @intCast(ty * tiling.tile_size));
            const tile_px_max_y = @as(
                u16,
                @min(@as(u32, tile_px_min_y) + tiling.tile_size, tiling.screen_px_y),
            );
            const scratch_px_min_y: i32 = @as(i32, tile_px_min_y) - tiling.halo_px;
            const scratch_px_max_y: i32 = @as(i32, tile_px_max_y) + tiling.halo_px;

            for (tx_start..tx_end) |tx| {
                const tile_px_min_x = @as(u16, @intCast(tx * tiling.tile_size));
                const tile_px_max_x = @as(
                    u16,
                    @min(@as(u32, tile_px_min_x) + tiling.tile_size, tiling.screen_px_x),
                );
                const scratch_px_min_x: i32 = @as(i32, tile_px_min_x) - tiling.halo_px;
                const scratch_px_max_x: i32 = @as(i32, tile_px_max_x) + tiling.halo_px;

                const tile_idx = ty * tiling.tiles_num_x + tx;
                const write_idx = tiling.tile_write_inds[
                    tile_idx * bucket_count + bucket_idx
                ].fetchAdd(1, .monotonic);

                tiling.overlaps[write_idx] = clipElemBBoxToTile(
                    elem_bbox,
                    floating,
                    tiling.mesh_idx,
                    scratch_px_min_x,
                    scratch_px_max_x,
                    scratch_px_min_y,
                    scratch_px_max_y,
                );
            }
        }
    }
}

fn calcElemTileRange(
    elem_bbox: ElemBBox,
    tile_size: u16,
    halo_px: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
) struct { tx_start: usize, tx_end: usize, ty_start: usize, ty_end: usize } {
    const tile_i: i32 = tile_size;
    const halo_i: i32 = halo_px;
    const x_min = @max(@as(i32, 0), @divFloor(elem_bbox.x_min - halo_i, tile_i));
    const y_min = @max(@as(i32, 0), @divFloor(elem_bbox.y_min - halo_i, tile_i));
    const x_max = @min(@as(i32, @intCast(tiles_num_x)), @divFloor(elem_bbox.x_max + halo_i + tile_i - 1, tile_i));
    const y_max = @min(@as(i32, @intCast(tiles_num_y)), @divFloor(elem_bbox.y_max + halo_i + tile_i - 1, tile_i));
    return .{
        .tx_start = @intCast(x_min),
        .tx_end = @intCast(x_max),
        .ty_start = @intCast(y_min),
        .ty_end = @intCast(y_max),
    };
}

fn transformWorldNodeToRaster(
    camera: *const cam.CameraPrepared,
    coord_world: vecstack.Vec3T(F),
) vecstack.Vec3T(F) {
    var coord_raster = matrix.Mat44Ops.mulVec3(F, camera.world_to_cam_mat, coord_world);

    coord_raster.vec[0] = camera.image_dist * coord_raster.vec[0] /
        (-coord_raster.vec[2]);
    coord_raster.vec[1] = camera.image_dist * coord_raster.vec[1] /
        (-coord_raster.vec[2]);

    coord_raster.vec[0] = 2.0 * coord_raster.vec[0] / camera.image_dims[0];
    coord_raster.vec[1] = 2.0 * coord_raster.vec[1] / camera.image_dims[1];

    coord_raster.vec[0] = (coord_raster.vec[0] + 1.0) * 0.5 *
        @as(F, @floatFromInt(camera.pixels_num[0]));
    coord_raster.vec[1] = (1.0 - coord_raster.vec[1]) * 0.5 *
        @as(F, @floatFromInt(camera.pixels_num[1]));
    coord_raster.vec[2] = -coord_raster.vec[2];

    return coord_raster;
}

fn transformWorldNodeToClipPx(
    camera: *const cam.CameraPrepared,
    coord_world: vecstack.Vec3T(F),
) vecstack.Vec3T(F) {
    const x_scale = camera.image_dist *
        @as(F, @floatFromInt(camera.pixels_num[0])) / camera.image_dims[0];
    const y_scale = camera.image_dist *
        @as(F, @floatFromInt(camera.pixels_num[1])) / camera.image_dims[1];

    var coord_clip = matrix.Mat44Ops.mulVec3(F, camera.world_to_cam_mat, coord_world);
    coord_clip.vec[0] *= x_scale;
    coord_clip.vec[1] *= -y_scale;
    coord_clip.vec[2] = -coord_clip.vec[2];
    return coord_clip;
}

fn isElemBehindCamera(
    comptime N: usize,
    coords_elem: GatheredElemCoords(N),
) bool {
    var behind_camera = true;
    for (0..N) |nn| {
        if (coords_elem.z[nn] > tol.culling.behind_camera_z) {
            behind_camera = false;
            break;
        }
    }
    return behind_camera;
}

fn isNodeZInvertible(
    comptime N: usize,
    coords_elem: GatheredElemCoords(N),
) bool {
    for (0..N) |nn| {
        if (coords_elem.z[nn] <= tol.culling.projective_z_min) {
            return false;
        }
    }
    return true;
}

fn isTri3Backface(coords_elem: GatheredElemCoords(3)) bool {
    const signed_area = edgeFun3Slices(0, 1, 2, &coords_elem.x, &coords_elem.y);
    return signed_area <= tol.culling.tri3_signed_area;
}

fn isTri3BackfaceRaster(coords_raster: RasterCoords2D(3)) bool {
    const signed_area = edgeFun3Slices(0, 1, 2, &coords_raster.x, &coords_raster.y);
    return signed_area <= tol.culling.tri3_signed_area;
}

fn isHighOrdBackface(
    comptime N: usize,
    coords_raster: RasterCoords2D(N),
) bool {
    return classifyHighOrdFacing(N, coords_raster) == null;
}

pub fn classifyHighOrdFacing(
    comptime N: usize,
    coords_raster: RasterCoords2D(N),
) ?RootClass {
    const nodal_derivs = comptime shapefun.getNodalDerivs(N);
    var determinants: [N + 1]F = undefined;
    var max_abs: F = 0.0;
    for (0..N) |nn| {
        var dx_dxi: F = 0.0;
        var dx_deta: F = 0.0;
        var dy_dxi: F = 0.0;
        var dy_deta: F = 0.0;

        for (0..N) |mm| {
            dx_dxi += nodal_derivs.dNu[nn][mm] * coords_raster.x[mm];
            dx_deta += nodal_derivs.dNv[nn][mm] * coords_raster.x[mm];
            dy_dxi += nodal_derivs.dNu[nn][mm] * coords_raster.y[mm];
            dy_deta += nodal_derivs.dNv[nn][mm] * coords_raster.y[mm];
        }

        const determinant = dx_dxi * dy_deta - dx_deta * dy_dxi;
        determinants[nn] = determinant;
        max_abs = @max(max_abs, @abs(determinant));
    }

    const centroid_xi: F = if (N == 6) 1.0 / 3.0 else 0.0;
    const centroid_eta: F = if (N == 6) 1.0 / 3.0 else 0.0;
    determinants[N] = projectedJacDetAt(
        N,
        coords_raster,
        centroid_xi,
        centroid_eta,
    );
    max_abs = @max(max_abs, @abs(determinants[N]));

    const margin = @max(
        tol.culling.projected_jacobian_abs,
        tol.culling.projected_jacobian_rel * max_abs,
    );
    var all_front = true;
    var all_back = true;
    for (determinants) |determinant| {
        if (!std.math.isFinite(determinant)) return .multi_root;
        if (determinant >= -margin) all_front = false;
        if (determinant <= margin) all_back = false;
    }
    if (all_back) return null;
    if (all_front) return .one_root;
    return .multi_root;
}

pub fn classifyElemFacing(
    comptime MT: MeshType,
    camera: *const cam.CameraPrepared,
    coords_nodes: *const meshio.Coords,
    connect: *const meshio.Connect,
    elem_idx: usize,
) ?RootClass {
    comptime {
        if (MT == .tri3 or MT == .tri3opt) {
            @compileError("classifyElemFacing requires a Newton element");
        }
    }
    const N = comptime MT.getNodesNum();
    const coords_clip = gatherElemNodeCoords(N, coords_nodes, connect, elem_idx);
    const coords_raster = projectClipToIdealRaster(N, camera, coords_clip);
    return classifyHighOrdFacing(N, coords_raster);
}

pub fn projectedJacDetAt(
    comptime N: usize,
    coords_raster: RasterCoords2D(N),
    xi: F,
    eta: F,
) F {
    var weights: [N]F = undefined;
    var d_xi: [N]F = undefined;
    var d_eta: [N]F = undefined;
    shapefun.shapeFunc(N, xi, eta, &weights, &d_xi, &d_eta);
    var dx_dxi: F = 0.0;
    var dx_deta: F = 0.0;
    var dy_dxi: F = 0.0;
    var dy_deta: F = 0.0;
    for (0..N) |nn| {
        dx_dxi += d_xi[nn] * coords_raster.x[nn];
        dx_deta += d_eta[nn] * coords_raster.x[nn];
        dy_dxi += d_xi[nn] * coords_raster.y[nn];
        dy_deta += d_eta[nn] * coords_raster.y[nn];
    }
    return dx_dxi * dy_deta - dx_deta * dy_dxi;
}

pub fn projectedJacDetPhysical(
    comptime N: usize,
    nodes: Vec3Slices(F),
    xi: F,
    eta: F,
) F {
    var weights: [N]F = undefined;
    var d_xi: [N]F = undefined;
    var d_eta: [N]F = undefined;
    shapefun.shapeFunc(N, xi, eta, &weights, &d_xi, &d_eta);
    var x: F = 0;
    var y: F = 0;
    var z: F = 0;
    var x_xi: F = 0;
    var x_eta: F = 0;
    var y_xi: F = 0;
    var y_eta: F = 0;
    var z_xi: F = 0;
    var z_eta: F = 0;
    for (0..N) |nn| {
        x += weights[nn] * nodes.x[nn];
        y += weights[nn] * nodes.y[nn];
        z += weights[nn] * nodes.z[nn];
        x_xi += d_xi[nn] * nodes.x[nn];
        x_eta += d_eta[nn] * nodes.x[nn];
        y_xi += d_xi[nn] * nodes.y[nn];
        y_eta += d_eta[nn] * nodes.y[nn];
        z_xi += d_xi[nn] * nodes.z[nn];
        z_eta += d_eta[nn] * nodes.z[nn];
    }
    const dx_xi = x_xi * z - x * z_xi;
    const dx_eta = x_eta * z - x * z_eta;
    const dy_xi = y_xi * z - y * z_xi;
    const dy_eta = y_eta * z - y * z_eta;
    return (dx_xi * dy_eta - dx_eta * dy_xi) / (z * z * z * z);
}

fn isOnScreen(
    camera: *const cam.CameraPrepared,
    x_min: F,
    x_max: F,
    y_min: F,
    y_max: F,
    raster_halo_px: u16,
) bool {
    const halo: F = @floatFromInt(raster_halo_px);
    return x_min < @as(F, @floatFromInt(camera.pixels_num[0])) + halo and
        x_max >= -halo and
        y_min < @as(F, @floatFromInt(camera.pixels_num[1])) + halo and
        y_max >= -halo;
}

fn projectClipToIdealRaster(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_clip: GatheredElemCoords(N),
) RasterCoords2D(N) {
    const offsets = camera.calcRasterOffsets();
    var coords_ideal: RasterCoords2D(N) = undefined;
    for (0..N) |nn| {
        coords_ideal.x[nn] = coords_clip.x[nn] / coords_clip.z[nn] + offsets.x_off;
        coords_ideal.y[nn] = coords_clip.y[nn] / coords_clip.z[nn] + offsets.y_off;
    }
    return coords_ideal;
}

fn distortIdealRasterCoords(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_ideal: RasterCoords2D(N),
) RasterCoords2D(N) {
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    var coords_distorted = coords_ideal;

    if (cam.isNoDistort(camera.distort)) {
        return coords_distorted;
    }

    for (0..N) |nn| {
        const x_ideal = (coords_ideal.x[nn] - offsets.x_off) / focal_px.fx;
        const y_ideal = (coords_ideal.y[nn] - offsets.y_off) / focal_px.fy;
        const distorted = cam.fordDistortModelScal(
            camera.distort,
            x_ideal,
            y_ideal,
        );
        coords_distorted.x[nn] = distorted.x * focal_px.fx + offsets.x_off;
        coords_distorted.y[nn] = distorted.y * focal_px.fy + offsets.y_off;
    }

    return coords_distorted;
}

fn packHullPointsAsRasterCoords(
    comptime NH: usize,
    hull_points: anytype,
) RasterCoords2D(NH) {
    var coords_raster: RasterCoords2D(NH) = undefined;
    inline for (0..NH) |nn| {
        coords_raster.x[nn] = hull_points.x[nn];
        coords_raster.y[nn] = hull_points.y[nn];
    }
    return coords_raster;
}

fn calcBBoxFromRasterCoords(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    elem_idx: usize,
    coords_raster: RasterCoords2D(N),
    raster_halo_px: u16,
) ?ElemBBox {
    const x_min = std.mem.min(F, &coords_raster.x);
    const x_max = std.mem.max(F, &coords_raster.x);
    const y_min = std.mem.min(F, &coords_raster.y);
    const y_max = std.mem.max(F, &coords_raster.y);

    return calcBBoxFromBounds(
        camera,
        elem_idx,
        .{ .x_min = x_min, .x_max = x_max, .y_min = y_min, .y_max = y_max },
        raster_halo_px,
    );
}

fn calcBBoxFromBounds(
    camera: *const cam.CameraPrepared,
    elem_idx: usize,
    bounds: db.DistortBounds,
    raster_halo_px: u16,
) ?ElemBBox {
    if (!isOnScreen(
        camera,
        bounds.x_min,
        bounds.x_max,
        bounds.y_min,
        bounds.y_max,
        raster_halo_px,
    )) {
        return null;
    }

    return .{
        .elem_idx = elem_idx,
        .x_min = boundIndMinSigned(bounds.x_min, -@as(i32, raster_halo_px)),
        .x_max = boundIndMaxSigned(
            bounds.x_max,
            @as(i32, @intCast(camera.pixels_num[0])) + raster_halo_px,
        ),
        .y_min = boundIndMinSigned(bounds.y_min, -@as(i32, raster_halo_px)),
        .y_max = boundIndMaxSigned(
            bounds.y_max,
            @as(i32, @intCast(camera.pixels_num[1])) + raster_halo_px,
        ),
    };
}

fn boundIndMinSigned(val: F, min: i32) i32 {
    if (val <= @as(F, @floatFromInt(min))) return min;
    return @as(i32, @intFromFloat(@floor(val)));
}

fn boundIndMaxSigned(val: F, max: i32) i32 {
    if (val >= @as(F, @floatFromInt(max))) return max;
    return @as(i32, @intFromFloat(@ceil(val)));
}

//------------------------------------------------------------------------------------------
// Tests & Test Helpers
//------------------------------------------------------------------------------------------

fn initTestCullCamera(
    allocator: std.mem.Allocator,
) !cam.CameraPrepared {
    return try initTestCullCameraWithDistort(
        allocator,
        .{
            .brown_con = .{
                .k1 = 0.0,
                .k2 = 0.0,
                .k3 = 0.0,
                .p1 = 0.0,
                .p2 = 0.0,
            },
        },
    );
}

fn initTestCullCameraWithDistort(
    allocator: std.mem.Allocator,
    distort: cam.DistortModel,
) !cam.CameraPrepared {
    const Vec3f = @import("vecstack.zig").Vec3f;
    const Rotation = @import("rotation.zig").Rotation;
    return cam.CameraPrepared.init(
        allocator,
        .{
            .pixels_num = .{ 10, 10 },
            .pixels_size = .{ 0.01, 0.01 },
            .pos_world = Vec3f.initZeros(),
            .rot_world = Rotation.init(0, 0, 0),
            .roi_cent_world = Vec3f.initZeros(),
            .focal_length = 1.0,
            .sub_sample = 1,
            .distort = distort.paramsFromModel(),
        },
    );
}

fn initSingleElemConnect(
    comptime N: usize,
    allocator: std.mem.Allocator,
) !meshio.Connect {
    var connect = try meshio.Connect.initAlloc(allocator, 1, N);
    for (0..N) |nn| {
        connect.table_mem[nn] = nn;
    }
    return connect;
}

fn initElemCoords(
    comptime N: usize,
    allocator: std.mem.Allocator,
    x_coords: [N]F,
    y_coords: [N]F,
    z_coords: [N]F,
) !meshio.Coords {
    var coords = try meshio.Coords.initAlloc(allocator, N);
    for (0..N) |nn| {
        coords.mat.set(nn, 0, x_coords[nn]);
        coords.mat.set(nn, 1, y_coords[nn]);
        coords.mat.set(nn, 2, z_coords[nn]);
    }
    return coords;
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

fn initTestCullCameraManual(distort: cam.DistortModel) cam.CameraPrepared {
    const Vec3f = @import("vecstack.zig").Vec3f;
    const Rotation = @import("rotation.zig").Rotation;
    const Mat44f = @import("matstack.zig").Mat44f;

    return .{
        .pixels_num = .{ 10, 10 },
        .pixels_size = .{ 0.01, 0.01 },
        .pos_world = Vec3f.initZeros(),
        .rot_world = Rotation.init(0, 0, 0),
        .roi_cent_world = Vec3f.initZeros(),
        .focal_length = 1.0,
        .sub_sample = 1,
        .sensor_size = .{ 0.1, 0.1 },
        .image_dims = .{ 0.1, 0.1 },
        .image_dist = 1.0,
        .cam_to_world_mat = Mat44f.initIdentity(),
        .world_to_cam_mat = Mat44f.initIdentity(),
        .distort = distort,
        .psf = .{ .pixel_box = .{} },
        .prep_psf = .{},
        .coord_sys = .opengl,
        .ideal_pixel_centers = undefined,
        .subpixel_center_map = .full_in_mem,
    };
}

test "fixed scalar and SIMD bounds recover the distorted triangle interior" {
    const outer_alloc = std.testing.allocator;
    var camera = initTestCullCameraManual(.{ .brown_con = .{
        .k1 = 1.0,
        .k2 = 0.0,
        .k3 = 0.0,
        .p1 = 0.0,
        .p2 = 0.0,
    } });
    camera.pixels_num = .{ 200, 200 };

    var coords = try initElemCoords(
        3,
        outer_alloc,
        .{ 110.0, 110.0, 120.0 },
        .{ 50.0, 150.0, 100.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer outer_alloc.free(coords.mem);
    var connect = try initSingleElemConnect(3, outer_alloc);
    defer connect.deinit(outer_alloc);

    const sensor = db.DistortBounds{
        .x_min = 0.0,
        .x_max = 200.0,
        .y_min = 0.0,
        .y_max = 200.0,
    };
    const bbox = (calcVisibleDistortBBox(
        .tri3,
        &camera,
        &coords,
        &connect,
        0,
        .on_no_fallback,
        0,
        sensor,
        1.0,
    )).?;
    const old_bbox = calcVisibleNodeBBoxTri3(
        .tri3,
        &camera,
        &coords,
        &connect,
        0,
    ).?;
    try std.testing.expectEqual(@as(i32, 112), old_bbox.x_min);
    try std.testing.expectEqual(@as(i32, 110), bbox.box_ints.x_min);
    const overlap = clipElemBBoxToTile(
        bbox.box_ints,
        bbox.box_floats,
        0,
        0,
        200,
        0,
        200,
    );
    try std.testing.expect(overlap.x_min <= 110 and overlap.x_max > 110);
    try std.testing.expect(overlap.y_min <= 100 and overlap.y_max > 100);
    const ideal = try camera.calcPinholeRasterPoint(110.5, 100.5);
    try std.testing.expect(ideal[0] > 110.0 and ideal[0] < 120.0);
    try std.testing.expect(ideal[1] > 50.0 and ideal[1] < 150.0);

    const rect = db.DistortBounds{
        .x_min = 110.0,
        .x_max = 120.0,
        .y_min = 50.0,
        .y_max = 150.0,
    };
    const scalar = db.sampleRectEdgesScalar(&camera, rect, 1.0);
    const simd = db.sampleRectEdgesSIMD(&camera, rect, 1.0);
    const bound_tol: F = if (F == f32) 1e-4 else 1e-10;
    try std.testing.expectApproxEqAbs(scalar.x_min, simd.x_min, bound_tol);
    try std.testing.expectApproxEqAbs(scalar.x_max, simd.x_max, bound_tol);
    try std.testing.expectApproxEqAbs(scalar.y_min, simd.y_min, bound_tol);
    try std.testing.expectApproxEqAbs(scalar.y_max, simd.y_max, bound_tol);
}

test "one-pixel fixed spacing resolves a smooth between-sample radial minimum" {
    var camera = initTestCullCameraManual(.{ .brown_con = .{
        .k1 = 0.3,
        .k2 = 0.0,
        .k3 = 0.0,
        .p1 = 0.0,
        .p2 = 0.0,
    } });
    camera.pixels_num = .{ 2000, 2000 };
    camera.pixels_size = .{ 0.001, 0.001 };
    const rect = db.DistortBounds{
        .x_min = 1600.0,
        .x_max = 1700.0,
        .y_min = 560.3,
        .y_max = 1560.3,
    };
    const scalar = db.sampleRectEdgesScalar(&camera, rect, 1.0);
    const simd = db.sampleRectEdgesSIMD(&camera, rect, 1.0);
    const exact_min: F = 1000.0 + 1000.0 * 0.6 * (1.0 + 0.3 * 0.6 * 0.6);
    const error_limit: F = if (F == f32) 0.002 else 0.0001;
    try std.testing.expect(scalar.x_min >= exact_min - error_limit);
    try std.testing.expect(scalar.x_min <= exact_min + error_limit);
    try std.testing.expectApproxEqAbs(scalar.x_min, simd.x_min, error_limit);
    try std.testing.expectEqual(
        @as(i32, 1664),
        boundIndMinSigned(scalar.x_min, 0),
    );
}

test "calcVisibleNodeBBoxTri3 on_screen" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 2.0, 4.0, 6.0 },
        .{ 2.0, 6.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0);
    try std.testing.expect(bbox != null);
}

test "calcVisibleNodeBBoxTri3 retains an element in the PSF halo" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);
    var coords = try initElemCoords(
        3,
        allocator,
        .{ -1.75, -1.75, -0.25 },
        .{ 2.0, 4.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    try std.testing.expect(
        calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0) == null,
    );
    const bbox = calcVisibleNodeBBoxTri3WithHalo(
        .tri3,
        &camera,
        &coords,
        &connect,
        0,
        2,
    ).?;
    try std.testing.expectEqual(@as(i32, -2), bbox.x_min);
    try std.testing.expect(bbox.x_max <= 0);
}

test "calcVisibleNodeBBoxTri3 uses the final pixel boundary for visibility" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);
    var coords = try initElemCoords(
        3,
        allocator,
        .{ 9.25, 9.25, 9.75 },
        .{ 2.0, 4.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0);
    try std.testing.expect(bbox != null);
    try std.testing.expectEqual(@as(i32, 9), bbox.?.x_min);
    try std.testing.expectEqual(@as(i32, 10), bbox.?.x_max);
}

test "calcVisibleNodeBBoxTri3 rejects an element beyond the final pixel boundary" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);
    var coords = try initElemCoords(
        3,
        allocator,
        .{ 10.0, 10.0, 10.5 },
        .{ 2.0, 4.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    try std.testing.expect(
        calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0) == null,
    );
}

test "calcVisibleNodeBBoxTri3 extends the final pixel boundary by the halo" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);
    var coords = try initElemCoords(
        3,
        allocator,
        .{ 10.25, 10.25, 11.75 },
        .{ 2.0, 4.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3WithHalo(
        .tri3,
        &camera,
        &coords,
        &connect,
        0,
        2,
    );
    try std.testing.expect(bbox != null);
    try std.testing.expectEqual(@as(i32, 10), bbox.?.x_min);
    try std.testing.expectEqual(@as(i32, 12), bbox.?.x_max);
}

test "calcVisibleNodeBBoxTri3 rejects an element beyond the halo boundary" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);
    var coords = try initElemCoords(
        3,
        allocator,
        .{ 12.0, 12.0, 12.5 },
        .{ 2.0, 4.0, 2.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    try std.testing.expect(
        calcVisibleNodeBBoxTri3WithHalo(
            .tri3,
            &camera,
            &coords,
            &connect,
            0,
            2,
        ) == null,
    );
}

test "calcVisibleNodeBBoxTri3 backface" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 2.0, 6.0, 4.0 },
        .{ 2.0, 2.0, 6.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0);
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxTri3 behind_camera" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 2.0, 4.0, 6.0 },
        .{ 2.0, 6.0, 2.0 },
        .{ -1.0, -1.0, -1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0);
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxTri3 noninvertible_z" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 100.0, 200.0, 100.0 },
        .{ 100.0, 100.0, 200.0 },
        .{ tol.culling.projective_z_min, 10.0, 10.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0);
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxHighOrd on_screen" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ -3.0, -1.0, 1.0, -2.0, 0.0, -1.0 },
        .{ -3.0, 1.0, -3.0, -1.0, -1.0, -3.0 },
        .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxHighOrd(
        .tri6,
        &camera,
        &coords,
        &connect,
        0,
        .on_no_fallback,
    );
    try std.testing.expect(bbox != null);
}

test "calcVisibleNodeBBoxHighOrd backface" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ -3.0, 1.0, -1.0, -1.0, 0.0, -2.0 },
        .{ -3.0, -3.0, 1.0, -3.0, -1.0, -1.0 },
        .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    const coords_clip = gatherElemNodeCoords(6, &coords, &connect, 0);
    const coords_ideal = projectClipToIdealRaster(6, &camera, coords_clip);
    try std.testing.expect(isHighOrdBackface(6, coords_ideal));
}

test "calcVisibleNodeBBoxHighOrd behind_camera" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ -3.0, 1.0, -1.0, -1.0, 0.0, -2.0 },
        .{ -3.0, -3.0, 1.0, -3.0, -1.0, -1.0 },
        .{ -1.0, -1.0, -1.0, -1.0, -1.0, -1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxHighOrd(
        .tri6,
        &camera,
        &coords,
        &connect,
        0,
        .on_no_fallback,
    );
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxHighOrd noninvertible_z" {
    const allocator = std.testing.allocator;
    const camera = try initTestCullCamera(allocator);
    defer camera.deinit(allocator);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ -0.5, 0.5, 0.0, 0.0, 0.25, -0.25 },
        .{ -0.5, -0.5, 0.5, -0.5, 0.0, 0.0 },
        .{ tol.culling.projective_z_min, 5.0, 5.0, 5.0, 5.0, 5.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxHighOrd(
        .tri6,
        &camera,
        &coords,
        &connect,
        0,
        .on_no_fallback,
    );
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxTri3 distorted_on_screen_shift" {
    const allocator = std.testing.allocator;
    const distort = cam.DistortModel{
        .brown_con = .{
            .k1 = 0.05,
            .k2 = 0.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 0.0,
        },
    };
    var camera = initTestCullCameraManual(.{
        .brown_con = .{},
    });

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 1.0, 2.0, 3.0 },
        .{ 4.0, 6.0, 4.0 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox_none = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0).?;
    camera.distort = distort;
    const bbox_distorted = calcVisibleNodeBBoxTri3(.tri3, &camera, &coords, &connect, 0).?;

    try std.testing.expect(
        bbox_distorted.x_min != bbox_none.x_min or
            bbox_distorted.x_max != bbox_none.x_max or
            bbox_distorted.y_min != bbox_none.y_min or
            bbox_distorted.y_max != bbox_none.y_max,
    );
}

test "calcVisibleNodeBBoxTri3 distorted_off_screen_shift" {
    const allocator = std.testing.allocator;
    const distort = cam.DistortModel{
        .brown_con = .{
            .k1 = 0.0,
            .k2 = 0.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 8.0,
        },
    };
    const camera_none = initTestCullCameraManual(.{
        .brown_con = .{},
    });
    const camera_distorted = initTestCullCameraManual(distort);

    var connect = try initSingleElemConnect(3, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        3,
        allocator,
        .{ 8.8, 9.0, 9.0 },
        .{ 4.5, 5.5, 4.5 },
        .{ 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox_none = calcVisibleNodeBBoxTri3(
        .tri3,
        &camera_none,
        &coords,
        &connect,
        0,
    );
    try std.testing.expect(bbox_none != null);
    const bbox_distorted = calcVisibleNodeBBoxTri3(
        .tri3,
        &camera_distorted,
        &coords,
        &connect,
        0,
    );
    try std.testing.expect(bbox_distorted == null);
}

test "high_order_distorted_hull_shift" {
    const distort = cam.DistortModel{
        .brown_con = .{
            .k1 = 0.0,
            .k2 = 0.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 8.0,
        },
    };
    var camera = initTestCullCameraManual(.{
        .brown_con = .{},
    });
    const coords_clip = GatheredElemCoords(6){
        .x = .{ 5.5, 6.5, 7.0, 6.0, 6.8, 6.2 },
        .y = .{ 4.0, 5.0, 4.0, 4.6, 4.6, 4.0 },
        .z = .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
    };

    const hull_points_ideal = hull.buildAdaptiveHullPointsFromClip(
        6,
        &camera,
        coords_clip,
        .on_no_fallback,
    );
    const hull_ideal_raster = packHullPointsAsRasterCoords(6, hull_points_ideal);
    camera.distort = distort;
    const hull_distorted = distortIdealRasterCoords(6, &camera, hull_ideal_raster);

    var changed_coord = false;
    for (0..6) |nn| {
        if (@abs(hull_distorted.x[nn] - hull_ideal_raster.x[nn]) > 1e-9 or
            @abs(hull_distorted.y[nn] - hull_ideal_raster.y[nn]) > 1e-9)
        {
            changed_coord = true;
            break;
        }
    }

    try std.testing.expect(changed_coord);
}

test "calcVisibleNodeBBoxHighOrd distorted_off_screen_shift" {
    const allocator = std.testing.allocator;
    const distort = cam.DistortModel{
        .brown_con = .{
            .k1 = 0.2,
            .k2 = 0.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 0.0,
        },
    };
    const camera_distorted = initTestCullCameraManual(distort);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ 3.5, 4.5, 4.5, 4.0, 4.5, 3.5 },
        .{ 4.0, 4.0, 5.0, 4.0, 4.5, 4.5 },
        .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxHighOrd(
        .tri6,
        &camera_distorted,
        &coords,
        &connect,
        0,
        .on_no_fallback,
    );
    try std.testing.expect(bbox == null);
}

test "calcVisibleNodeBBoxHighOrd backface_uses_ideal_pinhole" {
    const allocator = std.testing.allocator;
    const distort = try cam.DistortModel.init(.{
        .brown_con_ext = .{
            .k1 = -0.2,
            .k2 = 0.05,
            .k3 = 0.0,
            .k4 = 0.01,
            .k5 = 0.0,
            .k6 = 0.0,
            .p1 = 0.01,
            .p2 = -0.01,
        },
    });
    const camera = initTestCullCameraManual(distort);

    var connect = try initSingleElemConnect(6, allocator);
    defer connect.deinit(allocator);

    var coords = try initElemCoords(
        6,
        allocator,
        .{ -3.0, -1.0, 1.0, -2.0, 0.0, -1.0 },
        .{ -3.0, 1.0, -3.0, -1.0, -1.0, -3.0 },
        .{ 1.0, 1.0, 1.0, 1.0, 1.0, 1.0 },
    );
    defer allocator.free(coords.mem);

    const bbox = calcVisibleNodeBBoxHighOrd(
        .tri6,
        &camera,
        &coords,
        &connect,
        0,
        .on_no_fallback,
    );
    try std.testing.expect(bbox != null);
}
