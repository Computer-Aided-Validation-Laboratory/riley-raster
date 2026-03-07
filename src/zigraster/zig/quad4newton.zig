const std = @import("std");
const print = std.debug.print;
const time = std.time;

const vecstack = @import("vecstack.zig");
const Vec3T = vecstack.Vec3T;
const Vec3SliceOps = vecstack.Vec3SliceOps;

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
const ti = @import("textureinterp.zig");
const mr = @import("meshraster.zig");
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;

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
    const N: usize = 4;
    var elems_in_image: usize = 0;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
        );
        var x_min: f64 = std.math.inf(f64); var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64); var y_max: f64 = -std.math.inf(f64);
        for (0..N) |i| {
            const sx = cr.x[i] / cr.z[i] + x_off;
            const sy = cr.y[i] / cr.z[i] + y_off;
            x_min = @min(x_min, sx); x_max = @max(x_max, sx);
            y_min = @min(y_min, sy); y_max = @max(y_max, sy);
        }
        if (x_min > @as(f64, @floatFromInt(camera.pixels_num[0]-1)) or
            x_max < 0.0 or y_min > @as(f64, @floatFromInt(camera.pixels_num[1]-1)) or
            y_max < 0.0) continue;

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

fn shapeFunctions4(xi: f64, eta: f64, n_v: *[4]f64, dNu: *[4]f64, dNv: *[4]f64) void {
    n_v[0] = 0.25 * (1.0 - xi) * (1.0 - eta);
    n_v[1] = 0.25 * (1.0 + xi) * (1.0 - eta);
    n_v[2] = 0.25 * (1.0 + xi) * (1.0 + eta);
    n_v[3] = 0.25 * (1.0 - xi) * (1.0 + eta);

    dNu[0] = -0.25 * (1.0 - eta); dNu[1] = 0.25 * (1.0 - eta);
    dNu[2] = 0.25 * (1.0 + eta);  dNu[3] = -0.25 * (1.0 + eta);

    dNv[0] = -0.25 * (1.0 - xi);  dNv[1] = -0.25 * (1.0 + xi);
    dNv[2] = 0.25 * (1.0 + xi);   dNv[3] = 0.25 * (1.0 - xi);
}

fn solveInverseMapping(nr: Vec3OfSlices(f64), txs: f64, tys: f64,
                       xi_out: *f64, eta_out: *f64) bool {
    var xi = xi_out.*; var eta = eta_out.*;
    const max_iter = 10; const tol = 1e-8;
    var n_v: [4]f64 = undefined; var dNu: [4]f64 = undefined; var dNv: [4]f64 = undefined;

    for (0..max_iter) |_| {
        shapeFunctions4(xi, eta, &n_v, &dNu, &dNv);
        var Rx: f64 = 0.0; var Ry: f64 = 0.0;
        var J11: f64 = 0.0; var J12: f64 = 0.0;
        var J21: f64 = 0.0; var J22: f64 = 0.0;

        for (0..4) |i| {
            const f_x = txs * nr.z[i] - nr.x[i];
            const f_y = tys * nr.z[i] - nr.y[i];
            Rx += n_v[i] * f_x; Ry += n_v[i] * f_y;
            J11 += dNu[i] * f_x; J12 += dNv[i] * f_x;
            J21 += dNu[i] * f_y; J22 += dNv[i] * f_y;
        }

        if (@abs(Rx) < tol and @abs(Ry) < tol) break;
        const det = J11 * J22 - J12 * J21;
        if (@abs(det) < 1e-12) return false;
        const inv_det = 1.0 / det;
        xi -= inv_det * (J22 * Rx - J12 * Ry);
        eta -= inv_det * (-J21 * Rx + J11 * Ry);
    }
    const eps = 1e-5;
    if (xi >= -1.0 - eps and xi <= 1.0 + eps and eta >= -1.0 - eps and 
        eta <= 1.0 + eps) {
        xi_out.* = xi; eta_out.* = eta;
        return true;
    }
    return false;
}

pub fn rasterElemsFlat(allocator: std.mem.Allocator,
                       camera: *const Camera,
                       frame_ind: usize,
                       tile_size: u16,
                       active_tiles: []ActiveTile,
                       overlap_bboxes: []BBox,
                       elem_coord_arr: *const NDArray(f64),
                       shader: *const FlatShader,
                       image_out_arr: *NDArray(f64)) !void {
    @setFloatMode(.optimized);
    const N: usize = 4;
    const fields_num = shader.field.dims[2];
    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const spx_tile_size = tile_size * sub_samp;
    const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step = 1.0 / sub_samp_f;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_size * spx_tile_size);
    defer allocator.free(spx_inv_z_scratch);
    const spx_img_mem = try allocator.alloc(f64, spx_tile_size * spx_tile_size * fields_num);
    defer allocator.free(spx_img_mem);
    var spx_image_scratch = MatSlice(f64).init(
        spx_img_mem, spx_tile_size * spx_tile_size, fields_num,
    );
    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);
        for (overlap_bboxes[tile.overlap_start .. 
                            tile.overlap_start + tile.overlap_count]) |ov| {
            const nr = try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, 
                                                            ov.elem_ind);
            
            // Hoist fields from shader.field
            const elem_field_stride = shader.field.strides[1];
            const ff_stride = shader.field.strides[2];
            const elem_off = frame_ind * shader.field.strides[0] + ov.elem_ind * elem_field_stride;
            var f_vals = [3][4]f64{ undefined, undefined, undefined };
            const actual_fields = @min(fields_num, 3);
            for (0..actual_fields) |ff| {
                const ff_off = elem_off + ff * ff_stride;
                inline for (0..4) |ii| {
                    f_vals[ff][ii] = shader.field.elems[ff_off + ii];
                }
            }

            const s_sy = sub_samp * (@as(usize, ov.y_min) - tile.y_px_min);
            const s_ey = sub_samp * (@as(usize, ov.y_max) - tile.y_px_min);
            const s_sx = sub_samp * (@as(usize, ov.x_min) - tile.x_px_min);
            const s_ex = sub_samp * (@as(usize, ov.x_max) - tile.x_px_min);

            for (s_sy..s_ey) |yy| {
                const row_off = yy * spx_tile_size;
                const spx_y = @as(f64, @floatFromInt(tile.y_px_min)) + 
                              (@as(f64, @floatFromInt(yy)) + 0.5) * spx_step;
                const tys = spx_y - y_off;
                for (s_sx..s_ex) |xx| {
                    const spx_x = @as(f64, @floatFromInt(tile.x_px_min)) + 
                                  (@as(f64, @floatFromInt(xx)) + 0.5) * spx_step;
                    const txs = spx_x - x_off;
                    var u: f64 = 0.0; var v: f64 = 0.0;
                    if (solveInverseMapping(nr, txs, tys, &u, &v)) {
                        var n_v: [4]f64 = undefined; var dNu: [4]f64 = undefined; 
                        var dNv: [4]f64 = undefined;
                        shapeFunctions4(u, v, &n_v, &dNu, &dNv);
                        var sw: f64 = 0.0;
                        for (0..4) |i| sw += n_v[i] * nr.z[i];
                        const inv_z = 1.0 / sw; const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            for (0..actual_fields) |ff| {
                                var vs: f64 = 0.0;
                                for (0..4) |i| {
                                    vs += n_v[i] * f_vals[ff][i];
                                }
                                spx_image_scratch.elems[idx * fields_num + ff] = vs;
                            }
                        }
                    }
                }
            }
        }
        rops.averageScratch(
            tile, tile_size, @intCast(camera.pixels_num[0]), @intCast(camera.pixels_num[1]), 
            sub_samp, spx_tile_size, fields_num, &spx_image_scratch, spx_field_avg, 
            image_out_arr,
        );
    }
}

pub fn rasterElemsTex(comptime interp_type: ti.InterpType,
                      allocator: std.mem.Allocator,
                      camera: *const Camera,
                      tile_size: u16,
                      active_tiles: []ActiveTile,
                      overlap_bboxes: []BBox,
                      elem_coord_arr: *const NDArray(f64),
                      shader: *const TexShader,
                      image_out_arr: *NDArray(f64)) !void {
    @setFloatMode(.optimized);
    const N: usize = 4;
    const fields_num: usize = 1;
    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const spx_tile_size = tile_size * sub_samp;
    const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step = 1.0 / sub_samp_f;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_size * spx_tile_size);
    defer allocator.free(spx_inv_z_scratch);
    const spx_img_mem = try allocator.alloc(f64, spx_tile_size * spx_tile_size * fields_num);
    defer allocator.free(spx_img_mem);
    var spx_image_scratch = MatSlice(f64).init(
        spx_img_mem, spx_tile_size * spx_tile_size, fields_num,
    );
    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0); @memset(spx_image_scratch.elems, 0.0);
        for (overlap_bboxes[tile.overlap_start .. 
                            tile.overlap_start + tile.overlap_count]) |ov| {
            const nr = try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, 
                                                            ov.elem_ind);
            
            // Hoist UVs from shader.uvs
            const elem_uv_stride = shader.uvs.strides[0];
            const comp_uv_stride = shader.uvs.strides[1];
            const elem_uv_off = ov.elem_ind * elem_uv_stride;
            var uv_vals = [2][4]f64{ undefined, undefined };
            inline for (0..2) |cc| {
                const comp_off = elem_uv_off + cc * comp_uv_stride;
                inline for (0..4) |ii| {
                    uv_vals[cc][ii] = shader.uvs.elems[comp_off + ii];
                }
            }

            const s_sy = sub_samp * (@as(usize, ov.y_min) - tile.y_px_min);
            const s_ey = sub_samp * (@as(usize, ov.y_max) - tile.y_px_min);
            const s_sx = sub_samp * (@as(usize, ov.x_min) - tile.x_px_min);
            const s_ex = sub_samp * (@as(usize, ov.x_max) - tile.x_px_min);

            for (s_sy..s_ey) |yy| {
                const row_off = yy * spx_tile_size;
                const spx_y = @as(f64, @floatFromInt(tile.y_px_min)) + 
                              (@as(f64, @floatFromInt(yy)) + 0.5) * spx_step;
                const tys = spx_y - y_off;
                for (s_sx..s_ex) |xx| {
                    const spx_x = @as(f64, @floatFromInt(tile.x_px_min)) + 
                                  (@as(f64, @floatFromInt(xx)) + 0.5) * spx_step;
                    const txs = spx_x - x_off;
                    var u: f64 = 0.0; var v: f64 = 0.0;
                    if (solveInverseMapping(nr, txs, tys, &u, &v)) {
                        var n_v: [4]f64 = undefined; var dNu: [4]f64 = undefined; 
                        var dNv: [4]f64 = undefined;
                        shapeFunctions4(u, v, &n_v, &dNu, &dNv);
                        var sw: f64 = 0.0;
                        for (0..4) |i| sw += n_v[i] * nr.z[i];
                        const inv_z = 1.0 / sw; const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            var u_at: f64 = 0.0; var v_at: f64 = 0.0;
                            for (0..4) |i| {
                                u_at += n_v[i] * uv_vals[0][i];
                                v_at += n_v[i] * uv_vals[1][i];
                            }
                            spx_image_scratch.elems[idx] = ti.sampleGreyscale(
                                interp_type, shader.texture, u_at, v_at,
                            );
                        }
                    }
                }
            }
        }
        rops.averageScratch(
            tile, tile_size, @intCast(camera.pixels_num[0]), @intCast(camera.pixels_num[1]), 
            sub_samp, spx_tile_size, fields_num, &spx_image_scratch, spx_field_avg, 
            image_out_arr,
        );
    }
}
