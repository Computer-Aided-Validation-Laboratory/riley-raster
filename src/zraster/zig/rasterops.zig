const std = @import("std");
const vecstack = @import("vecstack.zig");
const Vec3T = vecstack.Vec3T;
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;
const ndarray = @import("ndarray.zig");
const NDArray = ndarray.NDArray;
const MappedNDArray = ndarray.MappedNDArray;
const buildconfig = @import("buildconfig.zig");
const Camera = @import("camera.zig").Camera;
const shapefun = @import("shapefun.zig");
const S = buildconfig.config.simd_vector_width;
const tol = buildconfig.config.tolerance;

const buildAdaptiveHulls = @import("hull.zig").buildAdaptiveHulls;
const geomkerns = @import("geometrykernels.zig");
const shaderops = @import("shaderops.zig");
const report = @import("report.zig");

fn edgeFun3Slices(
    comptime ind0: usize,
    comptime ind1: usize,
    comptime ind2: usize,
    x: []f64,
    y: []f64,
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
    v_px: @Vector(S, f64),
    v_py: @Vector(S, f64),
) @Vector(S, f64) {
    const v_x0: @Vector(S, f64) = @splat(x0);
    const v_y0: @Vector(S, f64) = @splat(y0);
    const v_x1: @Vector(S, f64) = @splat(x1);
    const v_y1: @Vector(S, f64) = @splat(y1);
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
        frame_idx: usize,
        tile_size: u16,
    };
}

pub const MeshInput = struct {
    coords: *const NDArray(f64),
    hull: ?*const NDArray(f64),
};

pub fn loadElemVec3Slices(
    comptime N: usize,
    comptime T: type,
    elem_array: *const NDArray(T),
    elem_idx: usize,
) !Vec3Slices(T) {
    var start_slice: usize = elem_array.getFlatInd(&[_]usize{ elem_idx, 0, 0 });
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
    const prep_normals = try NDArray(f64).initFlat(allocator, &[_]usize{ prep_count, 3, N });
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

pub fn prepareSceneGeometry(
    comptime report_mode: report.ReportMode,
    ctx_perf: report.ReportContext(report_mode),
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
                const NH = GK.hull_nodes_num;
                const dim_elem = 0;

                const normal_type = switch (mesh.shader) {
                    inline else => |s| s.normal_type,
                };

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    try elemsToRasterSIMD(N, f64, camera, dim_elem, @constCast(&mesh.coords));
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

    ctx_perf.recordGeometry(total_elems_num.*, total_elems_in_image.*);
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
                        .mesh_idx = @intCast(mesh_idx),
                        .elem_idx = @intCast(ebb.elem_idx),
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
