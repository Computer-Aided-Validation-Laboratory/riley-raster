const std = @import("std");
const print = std.debug.print;
const time = std.time;

const vecstack = @import("vecstack.zig");
const Vec3T = @import("vecstack.zig").Vec3T;
const Vec3SliceOps = @import("vecstack.zig").Vec3SliceOps;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;


pub fn transformElemsToCamSIMD(comptime N: usize,
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

pub fn countElemsCalcBBoxes(camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            elem_bboxes: []BBox) !usize {
    const N: usize = 6;
    var elems_in_image: usize = 0;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
    
        const cr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
        );
        
        var x_min: f64 = std.math.inf(f64); 
        var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64); 
        var y_max: f64 = -std.math.inf(f64);

        for (0..6) |i| {
            const sx = cr.x[i] / cr.z[i] + x_off;
            const sy = cr.y[i] / cr.z[i] + y_off;
            x_min = @min(x_min, sx); x_max = @max(x_max, sx);
            y_min = @min(y_min, sy); y_max = @max(y_max, sy);
        }
        
        if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0]-1)) 
            or x_max < 0.0 
            or y_min > @as(f64, @floatFromInt(camera.pixels_num[1]-1)) 
            or y_max < 0.0) {
            continue;
        }

        elem_bboxes[elems_in_image] = BBox{
            .elem_ind = ee,
            .x_min = rops.boundIndMin(u16, x_min),
            .x_max = rops.boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = rops.boundIndMin(u16, y_min),
            .y_max = rops.boundIndMax(u16, y_max, @intCast(camera.pixels_num[1]))
        };
        elems_in_image += 1;
    }
    return elems_in_image;
}

fn shapeFunctions(xi: f64, eta: f64, n_vals: *[6]f64, dN_dxi: *[6]f64, dN_deta: *[6]f64) void {
    const L1 = 1.0 - xi - eta;
    const L2 = xi;
    const L3 = eta;

    n_vals[0] = L1 * (2.0 * L1 - 1.0);
    dN_dxi[0] = -(4.0 * L1 - 1.0);
    dN_deta[0] = -(4.0 * L1 - 1.0);

    n_vals[1] = L2 * (2.0 * L2 - 1.0);
    dN_dxi[1] = 4.0 * L2 - 1.0;
    dN_deta[1] = 0.0;

    n_vals[2] = L3 * (2.0 * L3 - 1.0);
    dN_dxi[2] = 0.0;
    dN_deta[2] = 4.0 * L3 - 1.0;

    n_vals[3] = 4.0 * L1 * L2;
    dN_dxi[3] = 4.0 * (L1 - L2);
    dN_deta[3] = -4.0 * L2;

    n_vals[4] = 4.0 * L2 * L3;
    dN_dxi[4] = 4.0 * L3;
    dN_deta[4] = 4.0 * L2;

    n_vals[5] = 4.0 * L3 * L1;
    dN_dxi[5] = -4.0 * L3;
    dN_deta[5] = 4.0 * (L1 - L3);
}

fn getTessellatedGuess(txs: f64, tys: f64, ex: []f64, ey: []f64, ew: []f64,
                       xi_out: *f64, eta_out: *f64) bool {

    const SubTri = struct {
        n0: u8, n1: u8, n2: u8,
        xi0: f64, eta0: f64,
        xi1: f64, eta1: f64,
        xi2: f64, eta2: f64,
    };

    const subtri_defs = [_]SubTri{
        .{ .n0 = 0, .n1 = 3, .n2 = 5, .xi0 = 0.0, .eta0 = 0.0,
           .xi1 = 0.5, .eta1 = 0.0, .xi2 = 0.0, .eta2 = 0.5 },
        .{ .n0 = 3, .n1 = 1, .n2 = 4, .xi0 = 0.5, .eta0 = 0.0,
           .xi1 = 1.0, .eta1 = 0.0, .xi2 = 0.5, .eta2 = 0.5 },
        .{ .n0 = 5, .n1 = 4, .n2 = 2, .xi0 = 0.0, .eta0 = 0.5,
           .xi1 = 0.5, .eta1 = 0.5, .xi2 = 0.0, .eta2 = 1.0 },
        .{ .n0 = 3, .n1 = 4, .n2 = 5, .xi0 = 0.5, .eta0 = 0.0,
           .xi1 = 0.5, .eta1 = 0.5, .xi2 = 0.0, .eta2 = 0.5 },
    };

    for (subtri_defs) |st| {
        const x0 = ex[st.n0]/ew[st.n0]; const y0 = ey[st.n0]/ew[st.n0];
        const x1 = ex[st.n1]/ew[st.n1]; const y1 = ey[st.n1]/ew[st.n1];
        const x2 = ex[st.n2]/ew[st.n2]; const y2 = ey[st.n2]/ew[st.n2];

        const area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0);
        if (@abs(area) < 1e-12) continue;

        const w0 = ((txs - x0) * (y1 - y0) - (tys - y0) * (x1 - x0)) / area;
        const w1 = ((txs - x1) * (y2 - y1) - (tys - y1) * (x2 - x1)) / area;
        const w2 = ((txs - x2) * (y0 - y2) - (tys - y2) * (x0 - x2)) / area;

        const eps = 1e-5;
        if (w0 >= -eps and w1 >= -eps and w2 >= -eps) {
            xi_out.* = w0 * st.xi0 + w1 * st.xi1 + w2 * st.xi2;
            eta_out.* = w0 * st.eta0 + w1 * st.eta1 + w2 * st.eta2;
            return true;
        }
    }
    
    return false;
}

fn solveInverseMapProjected(txs: f64, tys: f64, ex: []f64, ey: []f64, ew: []f64,
                            xi_in: f64, eta_in: f64,
                            xi_out: *f64, eta_out: *f64) bool {

    var xi = xi_in;
    var eta = eta_in;

    const max_iter = 10;
    const tol = 1e-8;
    
    var n_vals: [6]f64 = undefined;
    var dN_dxi: [6]f64 = undefined;
    var dN_deta: [6]f64 = undefined;

    for (0..max_iter) |_| {
        shapeFunctions(xi, eta, &n_vals, &dN_dxi, &dN_deta);

        var Rx: f64 = 0.0; var Ry: f64 = 0.0;
        var J11: f64 = 0.0; var J12: f64 = 0.0;
        var J21: f64 = 0.0; var J22: f64 = 0.0;

        for (0..6) |i| {
            const tx = txs * ew[i] - ex[i];
            const ty = tys * ew[i] - ey[i];
            Rx += n_vals[i] * tx;
            Ry += n_vals[i] * ty;
            J11 += dN_dxi[i] * tx;
            J12 += dN_deta[i] * tx;
            J21 += dN_dxi[i] * ty;
            J22 += dN_deta[i] * ty;
        }

        if (@abs(Rx) < tol and @abs(Ry) < tol) {
            break;
        }

        const det = J11 * J22 - J12 * J21;
        if (@abs(det) < 1e-12) {
            return false;
        }

        const inv_det = 1.0 / det;
        xi -= inv_det * (J22 * Rx - J12 * Ry);
        eta -= inv_det * (-J21 * Rx + J11 * Ry);
    }

    const eps = 1e-5;
    if (xi >= -eps and eta >= -eps and (xi + eta) <= 1.0 + eps) {
        xi_out.* = xi;
        eta_out.* = eta;
        return true;
    }
    
    return false;
}

pub fn rasterElems(allocator: std.mem.Allocator,
                   camera: *const Camera,
                   tile_size: u16,
                   active_tiles: []ActiveTile,
                   overlap_bboxes: []BBox,
                   elem_coord_arr: *const NDArray(f64),
                   elem_field_arr: *const NDArray(f64),
                   image_out_arr: *NDArray(f64)) !void {

    @setFloatMode(.optimized);
    const N: usize = 6;
    const fields_num = elem_field_arr.dims[1];
    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size = tile_size * sub_samp;
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_size * spx_tile_size);
    defer allocator.free(spx_inv_z_scratch);
    const spx_img_mem = try allocator.alloc(f64, spx_tile_size * spx_tile_size * fields_num);
    defer allocator.free(spx_img_mem);
    var spx_image_scratch = MatSlice(f64).init(spx_img_mem, spx_tile_size * spx_tile_size, 
                                               fields_num);
    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        for (overlap_bboxes[tile.overlap_start .. tile.overlap_start + 
                            tile.overlap_count]) |ov| {
            const nr = try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, 
                                                            ov.elem_ind);

            const s_start_x = sub_samp * (@as(usize, ov.x_min) - tile.x_px_min);
            const s_end_x = sub_samp * (@as(usize, ov.x_max) - tile.x_px_min);
            const s_start_y = sub_samp * (@as(usize, ov.y_min) - tile.y_px_min);
            const s_end_y = sub_samp * (@as(usize, ov.y_max) - tile.y_px_min);

            for (s_start_y..s_end_y) |yy| {
                const row_off = yy * spx_tile_size;
                const spx_y = @as(f64, @floatFromInt(tile.y_px_min)) + 
                              (@as(f64, @floatFromInt(yy)) + 0.5) * spx_step;

                for (s_start_x..s_end_x) |xx| {
                    const spx_x = @as(f64, @floatFromInt(tile.x_px_min)) + 
                                  (@as(f64, @floatFromInt(xx)) + 0.5) * spx_step;
                    var xi: f64 = 0.0; var eta: f64 = 0.0;
                    var converged = false;

                    if (getTessellatedGuess(spx_x - x_off, spx_y - y_off, nr.x, 
                                            nr.y, nr.z, &xi, &eta)) {
                        converged = solveInverseMapProjected(spx_x - x_off, 
                                                             spx_y - y_off, 
                                                             nr.x, nr.y, nr.z, 
                                                             xi, eta, &xi, &eta);
                    }
                    
                    if (!converged) {
                        converged = solveInverseMapProjected(spx_x - x_off, 
                                                             spx_y - y_off, 
                                                             nr.x, nr.y, nr.z, 
                                                             1.0/3.0, 1.0/3.0, 
                                                             &xi, &eta);
                    }

                    if (converged) {
                        var n_vals: [6]f64 = undefined;
                        var dN_dxi: [6]f64 = undefined;
                        var dN_deta: [6]f64 = undefined;
                        shapeFunctions(xi, eta, &n_vals, &dN_dxi, &dN_deta);

                        var sw: f64 = 0.0;
                        for (0..6) |i| sw += n_vals[i] * nr.z[i];
                        const inv_z = 1.0 / sw;

                        const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            for (0..fields_num) |ff| {
                                var vs: f64 = 0.0;
                                for (0..6) |i| vs += n_vals[i] * elem_field_arr.get(
                                    &[_]usize{ ov.elem_ind, ff, i },
                                );
                                spx_image_scratch.set(idx, ff, vs);
                            }
                        }
                    }
                }
            }
        }

        rops.averageScratch(tile, 
                            tile_size, 
                            @intCast(camera.pixels_num[0]), 
                            @intCast(camera.pixels_num[1]), 
                            sub_samp, 
                            spx_tile_size, 
                            fields_num, 
                            &spx_image_scratch, 
                            spx_field_avg, 
                            image_out_arr);
    }
}
