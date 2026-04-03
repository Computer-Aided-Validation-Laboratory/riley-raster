const std = @import("std");
const common = @import("rasterops_common.zig");

const vecstack = @import("vecstack.zig");
const Vec3f = vecstack.Vec3f;
const Vec3T = vecstack.Vec3T;

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const Camera = @import("camera.zig").Camera;

pub const buildAdaptiveHulls = @import("hull.zig").buildAdaptiveHulls;
const geomkerns = @import("geometrykernels.zig");
const shaderops = @import("shaderops.zig");
const perf = @import("perf.zig");

pub const edgeFun = common.edgeFun;

pub const edgeFun3Slices = common.edgeFun3Slices;

pub inline fn edgeFun3(x0: f64, y0: f64, x1: f64, y1: f64, px: f64, py: f64) f64 {
    return (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
}

pub inline fn edgeFun3SIMD(x0: f64, y0: f64, x1: f64, y1: f64, v_px: @Vector(8, f64), v_py: @Vector(8, f64)) @Vector(8, f64) {
    const v_x0: @Vector(8, f64) = @splat(x0);
    const v_y0: @Vector(8, f64) = @splat(y0);
    const v_x1: @Vector(8, f64) = @splat(x1);
    const v_y1: @Vector(8, f64) = @splat(y1);
    return (v_px - v_x0) * (v_y1 - v_y0) - (v_py - v_y0) * (v_x1 - v_x0);
}

pub const boundIndexMin = common.boundIndexMin;

pub const boundIndexMax = common.boundIndexMax;

pub const boundIndMin = common.boundIndMin;

pub const boundIndMax = common.boundIndMax;

pub const worldToRasterCoords = common.worldToRasterCoords;

//---------------------------------------------------------------------------------------------
// Tiling Raster: Structs and Types

pub const Vec3OfSlices = common.Vec3OfSlices;
pub const ElemBBox = common.ElemBBox;
pub const OverlapBBox = common.OverlapBBox;
pub const ActiveTile = common.ActiveTile;
pub const TilingOverlaps = common.TilingOverlaps;
pub const RasterContext = common.RasterContext;
pub const OverlapTarget = common.OverlapTarget;
pub const MeshInput = common.MeshInput;

//---------------------------------------------------------------------------------------------
// Tiling Raster: Helper Functions

pub const loadVec3SlicesFromElemArray = common.loadVec3SlicesFromElemArray;

pub const worldToRasterSIMD = common.worldToRasterSIMD;

pub const elemsToRasterSIMD = common.elemsToRasterSIMD;

pub const elemsToClipPxLengSIMD = common.elemsToClipPxLengSIMD;

const NodalDerivs = struct {
    dNu: [9][9]f64,
    dNv: [9][9]f64,
};

fn getNodalDerivs(comptime N: usize) NodalDerivs {
    var nd = NodalDerivs{
        .dNu = [_][9]f64{[_]f64{0} ** 9} ** 9,
        .dNv = [_][9]f64{[_]f64{0} ** 9} ** 9,
    };
    const shapefun = @import("shapefun.zig");
    const node_coords = switch (N) {
        3 => [3][2]f64{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 },
        },
        4 => [4][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
        },
        6 => [6][2]f64{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0.5, 0 }, .{ 0.5, 0.5 }, .{ 0, 0.5 },
        },
        8 => [8][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
            .{ 0, -1 },  .{ 1, 0 },  .{ 0, 1 }, .{ -1, 0 },
        },
        9 => [9][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
            .{ 0, -1 },  .{ 1, 0 },  .{ 0, 1 }, .{ -1, 0 },
            .{ 0, 0 },
        },
        else => return nd,
    };

    for (0..N) |ii| {
        var n_v: [N]f64 = undefined;
        var dNu: [N]f64 = undefined;
        var dNv: [N]f64 = undefined;
        shapefun.shapeFunctions(N, node_coords[ii][0], node_coords[ii][1], &n_v, &dNu, &dNv);
        for (0..N) |jj| {
            nd.dNu[ii][jj] = dNu[jj];
            nd.dNv[ii][jj] = dNv[jj];
        }
    }
    return nd;
}

pub fn countElemsCalcBBoxes(comptime N: usize, comptime NH: usize, camera: *const Camera, dim_elem: usize, elem_coord_arr: *const NDArray(f64), raster_hull: ?*const NDArray(f64), elem_bboxes: []ElemBBox) !usize {
    var elems_in_image: usize = 0;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const nodal_derivs = comptime getNodalDerivs(N);
    const tolerance = 1e-8;

    const total_elems = elem_coord_arr.dims[dim_elem];

    for (0..total_elems) |ee| {
        var x_min: f64 = std.math.inf(f64);
        var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64);
        var y_max: f64 = -std.math.inf(f64);

        const cr: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
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
            .elem_ind = ee,
            .x_min = boundIndMin(u16, x_min),
            .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = boundIndMin(u16, y_min),
            .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
        };
        elems_in_image += 1;
    }
    return elems_in_image;
}

pub fn countElemsCalcBBoxesTri3(camera: *const Camera, dim_elem: usize, elem_coord_arr: *const NDArray(f64), elem_bboxes: []ElemBBox) !usize {
    const N: usize = 3;
    const tol_area: f64 = 1e-12;

    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
            N,
            f64,
            elem_coord_arr,
            ee,
        );

        // Width (X) on screen check and crop
        const x_max: f64 = std.mem.max(f64, coords_raster.x);
        const x_min: f64 = std.mem.min(f64, coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        // Height (Y) on on screen check and crop
        const y_max: f64 = std.mem.max(f64, coords_raster.y);
        const y_min: f64 = std.mem.min(f64, coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
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

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 1: Prepare Scene Geometry

fn calculateMeshNormals(
    allocator: std.mem.Allocator,
    mesh_coords: *const NDArray(f64),
    mesh_connect: anytype,
    normal_type: shaderops.NormalType,
    comptime N: usize,
) !NDArray(f64) {
    const elems_num = mesh_coords.dims[0];
    var all_normals = try NDArray(f64).initFlat(allocator, &[_]usize{ elems_num, 3, N });
    const nodal_derivs = comptime getNodalDerivs(N);

    if (normal_type == .exact) {
        for (0..elems_num) |ee| {
            const sx = mesh_coords.getSlice(&[_]usize{ ee, 0, 0 }, 1);
            const sy = mesh_coords.getSlice(&[_]usize{ ee, 1, 0 }, 1);
            const sz = mesh_coords.getSlice(&[_]usize{ ee, 2, 0 }, 1);

            for (0..N) |ii| {
                var dx_dxi: f64 = 0;
                var dx_deta: f64 = 0;
                var dy_dxi: f64 = 0;
                var dy_deta: f64 = 0;
                var dz_dxi: f64 = 0;
                var dz_deta: f64 = 0;
                for (0..N) |jj| {
                    const du = nodal_derivs.dNu[ii][jj];
                    const dv = nodal_derivs.dNv[ii][jj];
                    dx_dxi += du * sx[jj];
                    dx_deta += dv * sx[jj];
                    dy_dxi += du * sy[jj];
                    dy_deta += dv * sy[jj];
                    dz_dxi += du * sz[jj];
                    dz_deta += dv * sz[jj];
                }
                var nx = dy_dxi * dz_deta - dz_dxi * dy_deta;
                var ny = dz_dxi * dx_deta - dx_dxi * dz_deta;
                var nz = dx_dxi * dy_deta - dy_dxi * dx_deta;
                const mag = @sqrt(nx * nx + ny * ny + nz * nz);
                if (mag > 1e-12) {
                    nx /= mag;
                    ny /= mag;
                    nz /= mag;
                }
                all_normals.set(&[_]usize{ ee, 0, ii }, nx);
                all_normals.set(&[_]usize{ ee, 1, ii }, ny);
                all_normals.set(&[_]usize{ ee, 2, ii }, nz);
            }
        }
    } else if (normal_type == .averaged) {
        var max_node_idx: usize = 0;
        for (mesh_connect.table_mem) |idx| {
            if (idx > max_node_idx) max_node_idx = idx;
        }
        const num_nodes = max_node_idx + 1;
        const node_normals = try allocator.alloc(f64, num_nodes * 3);
        @memset(node_normals, 0.0);

        for (0..elems_num) |ee| {
            const coord_inds = mesh_connect.getElem(ee);
            const sx = mesh_coords.getSlice(&[_]usize{ ee, 0, 0 }, 1);
            const sy = mesh_coords.getSlice(&[_]usize{ ee, 1, 0 }, 1);
            const sz = mesh_coords.getSlice(&[_]usize{ ee, 2, 0 }, 1);

            for (0..N) |ii| {
                var dx_dxi: f64 = 0;
                var dx_deta: f64 = 0;
                var dy_dxi: f64 = 0;
                var dy_deta: f64 = 0;
                var dz_dxi: f64 = 0;
                var dz_deta: f64 = 0;
                for (0..N) |jj| {
                    const du = nodal_derivs.dNu[ii][jj];
                    const dv = nodal_derivs.dNv[ii][jj];
                    dx_dxi += du * sx[jj];
                    dx_deta += dv * sx[jj];
                    dy_dxi += du * sy[jj];
                    dy_deta += dv * sy[jj];
                    dz_dxi += du * sz[jj];
                    dz_deta += dv * sz[jj];
                }
                const nx = dy_dxi * dz_deta - dz_dxi * dy_deta;
                const ny = dz_dxi * dx_deta - dx_dxi * dz_deta;
                const nz = dx_dxi * dy_deta - dy_dxi * dx_deta;

                const ni = coord_inds[ii];
                node_normals[ni * 3 + 0] += nx;
                node_normals[ni * 3 + 1] += ny;
                node_normals[ni * 3 + 2] += nz;
            }
        }

        for (0..elems_num) |ee| {
            const coord_inds = mesh_connect.getElem(ee);
            for (0..N) |ii| {
                const ni = coord_inds[ii];
                var nx = node_normals[ni * 3 + 0];
                var ny = node_normals[ni * 3 + 1];
                var nz = node_normals[ni * 3 + 2];
                const mag = @sqrt(nx * nx + ny * ny + nz * nz);
                if (mag > 1e-12) {
                    nx /= mag;
                    ny /= mag;
                    nz /= mag;
                }
                all_normals.set(&[_]usize{ ee, 0, ii }, nx);
                all_normals.set(&[_]usize{ ee, 1, ii }, ny);
                all_normals.set(&[_]usize{ ee, 2, ii }, nz);
            }
        }
        allocator.free(node_normals);
    }
    return all_normals;
}

pub fn prepareSceneGeometry(
    comptime report: perf.Report,
    ctx_perf: perf.PerfContext(report),
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
                    .tri3opt => geomkerns.Tri3OptKernel(),
                    .tri6 => geomkerns.Tri6Kernel(),
                    .quad4ibi => geomkerns.Quad4IBIKernel(),
                    .quad4newton => geomkerns.Quad4NewtonKernel(),
                    .quad8 => geomkerns.Quad89Kernel(8),
                    .quad9 => geomkerns.Quad89Kernel(9),
                };
                const N = GK.nodes_num;
                const NH = if (comptime GK.has_hull) GK.hull_nodes_num else 0;
                const dim_elem = 0;

                const normal_type = switch (mesh.shader) {
                    .flat => |s| s.normal_type,
                    inline else => |s| s.normal_type,
                };

                var all_normals: ?NDArray(f64) = null;
                if (normal_type != .none) {
                    all_normals = try calculateMeshNormals(
                        arena_alloc,
                        &mesh.coords,
                        mesh.connect,
                        normal_type,
                        N,
                    );
                }

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    try elemsToRasterSIMD(N, f64, camera, dim_elem, @constCast(&mesh.coords));
                } else {
                    try elemsToClipPxLengSIMD(N, f64, camera, dim_elem, &mesh.coords);
                }

                if (comptime GK.has_hull) {
                    raster_hulls[ii] = try NDArray(f64).initFlat(
                        arena_alloc,
                        &[_]usize{ elems_num, 2, NH },
                    );
                    try buildAdaptiveHulls(N, camera, dim_elem, &mesh.coords, &raster_hulls[ii].?);
                }

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    elems_in_image_by_mesh[ii] = try countElemsCalcBBoxesTri3(
                        camera,
                        dim_elem,
                        &mesh.coords,
                        elem_bboxes_by_mesh[ii],
                    );
                } else {
                    const rh_ptr = if (raster_hulls[ii]) |*rh| rh else null;
                    elems_in_image_by_mesh[ii] = try countElemsCalcBBoxes(
                        N,
                        NH,
                        camera,
                        dim_elem,
                        &mesh.coords,
                        rh_ptr,
                        elem_bboxes_by_mesh[ii],
                    );
                }

                if (all_normals) |an| {
                    const prep_count = elems_in_image_by_mesh[ii];
                    var prep_normals = try NDArray(f64).initFlat(
                        arena_alloc,
                        &[_]usize{ prep_count, 3, N },
                    );
                    var map = try arena_alloc.alloc(usize, elems_num);
                    @memset(map, std.math.maxInt(usize));

                    for (0..prep_count) |pp| {
                        const orig_ee = elem_bboxes_by_mesh[ii][pp].elem_ind;
                        map[orig_ee] = pp;

                        // Contiguous copy of normal data for this element
                        @memcpy(
                            prep_normals.elems[pp * 3 * N .. (pp + 1) * 3 * N],
                            an.elems[orig_ee * 3 * N .. (orig_ee + 1) * 3 * N],
                        );
                    }

                    switch (mesh.shader) {
                        .flat => |*s| s.elem_normals = .{ .array = prep_normals, .map = map },
                        inline else => |*s| s.elem_normals = .{ .array = prep_normals, .map = map },
                    }
                }
            },
        }
        total_elems_in_image.* += elems_in_image_by_mesh[ii];
    }

    ctx_perf.recordGeometry(total_elems_num.*, total_elems_in_image.*);
}

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 2: Tile/Element Overlaps for the Whole Scene

pub fn sceneTileElemOverlap(
    allocator: std.mem.Allocator,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    meshes_len: usize,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []ElemBBox,
) !TilingOverlaps {
    const tiles_num = tiles_num_x * tiles_num_y;
    const tile_elem_counts = try allocator.alloc(usize, tiles_num);
    defer allocator.free(tile_elem_counts);
    @memset(tile_elem_counts, 0);

    for (0..meshes_len) |mesh_idx| {
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

    for (0..meshes_len) |mesh_idx| {
        for (0..elems_in_image_by_mesh[mesh_idx]) |ee| {
            const ebb = elem_bboxes_by_mesh[mesh_idx][ee];
            const tx_start = ebb.x_min / tile_size;
            const tx_end = @min(tiles_num_x, @as(usize, (ebb.x_max + tile_size - 1) / tile_size));
            const ty_start = ebb.y_min / tile_size;
            const ty_end = @min(tiles_num_y, @as(usize, (ebb.y_max + tile_size - 1) / tile_size));

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
                        .mesh_idx = @intCast(mesh_idx),
                        .elem_idx = @intCast(ebb.elem_ind),
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
