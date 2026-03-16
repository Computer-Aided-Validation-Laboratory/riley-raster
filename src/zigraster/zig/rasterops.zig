const std = @import("std");

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
const perf = @import("perf.zig");


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
    var min_ind: usize = @as(isize, @intFromFloat(@floor(min_val)));
    if (min_ind < 0) {
        min_ind = 0;
    }
    return @as(usize,@intCast(min_ind));
}

pub fn boundIndexMax(max_val: f64, pixels_num: usize) usize {
    var max_ind: isize = @as(isize, @intFromFloat(@ceil(max_val)));
    const px = @as(isize,@intCast(pixels_num - 1));
    if (max_ind > px) {
        max_ind = px;
    }
    return @as(usize,@intCast(max_ind));
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


//---------------------------------------------------------------------------------------------
// Tiling Raster: Structs and Types

pub fn Vec3OfSlices(comptime T: type) type {
    return struct{
        x: []T,
        y: []T,
        z: []T,
    };   
}

pub const BBox = struct {
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

pub const ElemBBox = struct {
    elem_ind: usize,
    bbox: BBox,
};

pub const OverlapBBox = struct {
    mesh_idx: u32,
    elem_idx: u32, // Stores the original element index in the mesh
    bbox: BBox,    // Geometric only
};

pub const ActiveTile = struct {
    overlap_start: usize, // index into overlap_bboxes
    overlap_count: usize, // count to take from overlap bboxes
    x_px_min: u16,
    y_px_min: u16,
    x_px_max: u16,
    y_px_max: u16,
};

pub const TilingOverlaps = struct {
    overlaps: []OverlapBBox,
    active_tiles: []ActiveTile,
};

//---------------------------------------------------------------------------------------------
// Tiling Raster: Helper Functions

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

pub fn transformElemsRasterSIMD(comptime N: usize,
                                 comptime T: type,
                                 camera: *const Camera, 
                                 dim_elem: usize,  
                                 elem_coord_arr: *NDArray(T)) !void {

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N,T) = try vsd.loadVec3SIMDFromElemArray(
            N,T,elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,T) = worldToRasterSIMD(
            N,T,coords_world,camera); 

        try vsd.saveVec3SIMDToElemArray(N,T,elem_coord_arr,ee,coords_raster);
    }
}

pub fn transformElemsClipPxLengSIMD(comptime N: usize,
                             comptime T: type,
                             camera: *const Camera, 
                             dim_elem: usize,  
                             elem_coord_arr: *NDArray(T)) !void {

    const x_scale = camera.image_dist * @as(f64, @floatFromInt(camera.pixels_num[0])) / 
                    camera.image_dims[0];
    const y_scale = camera.image_dist * @as(f64, @floatFromInt(camera.pixels_num[1])) / 
                    camera.image_dims[1];

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cw: Vec3SIMD(N, f64) = try vsd.loadVec3SIMDFromElemArray(N, f64, 
                                                                       elem_coord_arr, ee);
        
        var cr = vsd.mat44Mul(N, f64, camera.world_to_cam_mat, cw);
        
        cr.x *= @splat(x_scale);
        cr.y *= @splat(-y_scale);
        try vsd.saveVec3SIMDToElemArray(N, f64, elem_coord_arr, ee,
                                        Vec3SIMD(N, f64){ .x = cr.x, .y = cr.y, 
                                                          .z = -cr.z });
    }
}

pub fn countElemsCalcBBoxes(comptime N: usize,
                            comptime NH: usize,
                            camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            raster_hull: ?*const NDArray(f64),
                            elem_bboxes: []ElemBBox) !usize {
    var elems_in_image: usize = 0;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        var x_min: f64 = std.math.inf(f64);
        var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64);
        var y_max: f64 = -std.math.inf(f64);

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
            // Use raw coords (N nodes) and do perspective divide
            const cr: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
                N, f64, elem_coord_arr, ee,
            );

            for (0..N) |i| {
                const sx = cr.x[i] / cr.z[i] + x_off;
                const sy = cr.y[i] / cr.z[i] + y_off;
                
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
            .bbox = BBox{
                .x_min = boundIndMin(u16, x_min),
                .x_max = boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
                .y_min = boundIndMin(u16, y_min),
                .y_max = boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
            },
        };
        elems_in_image += 1;
    }
    return elems_in_image;
}

pub fn countElemsCalcBBoxesTri3(camera: *const Camera,
                               dim_elem: usize,
                               elem_coord_arr: *const NDArray(f64),
                               elem_bboxes: []ElemBBox) !usize {
    const N: usize = 3;
    const tol_area: f64 = 1e-12;

    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
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
            .bbox = BBox{
                .x_min = x_min_i,
                .x_max = x_max_i,
                .y_min = y_min_i,
                .y_max = y_max_i,
            },
        };
        elems_in_image += 1;
    }

    return elems_in_image;
}

//---------------------------------------------------------------------------------------------
// Tiling Raster Step 1: Prepare Scene Geometry

pub fn prepareSceneGeometry(
    comptime report: perf.Report,
    perf_ctx: perf.PerfContext(report),
    arena_alloc: std.mem.Allocator,
    camera: *const Camera,
    meshes: anytype,
    raster_hulls: []?NDArray(f64),
    elem_bboxes_by_mesh: [][]ElemBBox,
    elems_in_image_by_mesh: []usize,
    total_elems_num_out: *usize,
    total_elems_in_image_out: *usize,
) !void {
    total_elems_num_out.* = 0;
    total_elems_in_image_out.* = 0;

    for (meshes, 0..) |*mesh, ii| {
        const elems_num = mesh.coords.dims[0];
        total_elems_num_out.* += elems_num;
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

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    try transformElemsRasterSIMD(N, f64, camera, dim_elem, &mesh.coords);
                } else {
                    try transformElemsClipPxLengSIMD(
                        N, f64, camera, dim_elem, &mesh.coords
                    );
                }

                if (comptime GK.has_hull) {
                    raster_hulls[ii] = try NDArray(f64).initFlat(
                        arena_alloc,
                        &[_]usize{ elems_num, 2, NH },
                    );
                    try buildAdaptiveHulls(
                        N, camera, dim_elem, &mesh.coords, &raster_hulls[ii].?
                    );
                }

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    elems_in_image_by_mesh[ii] = try countElemsCalcBBoxesTri3(
                        camera, dim_elem, &mesh.coords, elem_bboxes_by_mesh[ii],
                    );
                } else {
                    const rh_ptr = if (raster_hulls[ii]) |*rh| rh else null;
                    elems_in_image_by_mesh[ii] = try countElemsCalcBBoxes(
                        N, NH, camera, dim_elem, &mesh.coords, rh_ptr, elem_bboxes_by_mesh[ii],
                    );
                }
            }
        }
        total_elems_in_image_out.* += elems_in_image_by_mesh[ii];
    }
    
    if (comptime report == .perf) {
        perf_ctx.recordGeometry(total_elems_num_out.*, total_elems_in_image_out.*);
    }
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
            const tile_ind_min_x: u16 = ebb.bbox.x_min / tile_size;
            const tile_ind_max_x: u16 = (ebb.bbox.x_max + tile_size - 1) / tile_size;
            const tile_ind_min_y: u16 = ebb.bbox.y_min / tile_size;
            const tile_ind_max_y: u16 = (ebb.bbox.y_max + tile_size - 1) / tile_size;

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
            const tx_start = ebb.bbox.x_min / tile_size;
            const tx_end = @min(tiles_num_x, 
                                @as(usize, (ebb.bbox.x_max + tile_size - 1) / tile_size));
            const ty_start = ebb.bbox.y_min / tile_size;
            const ty_end = @min(tiles_num_y, 
                                @as(usize, (ebb.bbox.y_max + tile_size - 1) / tile_size));

            for (ty_start..ty_end) |ty| {
                const tile_px_min_y = @as(u16, @intCast(ty * tile_size));
                const tile_px_max_y = @as(u16, @min(@as(u32, tile_px_min_y) + 
                                                   tile_size, screen_px_y));
                const overlap_y_min = @max(ebb.bbox.y_min, tile_px_min_y);
                const overlap_y_max = @min(ebb.bbox.y_max, tile_px_max_y);

                for (tx_start..tx_end) |tx| {
                    const tile_px_min_x = @as(u16, @intCast(tx * tile_size));
                    const tile_px_max_x = @as(u16, @min(@as(u32, tile_px_min_x) + 
                                                       tile_size, screen_px_x));

                    const tile_idx = ty * tiles_num_x + tx;
                    const write_idx = tile_write_inds[tile_idx];
                    overlaps[write_idx] = .{
                        .mesh_idx = @intCast(mesh_idx),
                        .elem_idx = @intCast(ebb.elem_ind),
                        .bbox = BBox{
                            .x_min = @max(ebb.bbox.x_min, tile_px_min_x),
                            .x_max = @min(ebb.bbox.x_max, tile_px_max_x),
                            .y_min = overlap_y_min,
                            .y_max = overlap_y_max,
                        },
                    };
                    tile_write_inds[tile_idx] += 1;
                }
            }
        }
    }

    return TilingOverlaps{ .overlaps = overlaps, .active_tiles = active_tiles };
}
