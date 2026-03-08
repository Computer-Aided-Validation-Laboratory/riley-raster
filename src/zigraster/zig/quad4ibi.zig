const std = @import("std");

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const Camera = @import("camera.zig").Camera;
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const ti = @import("textureinterp.zig");
const mr = @import("meshraster.zig");
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;

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

        var x_min: f64 = std.math.inf(f64); 
        var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64); 
        var y_max: f64 = -std.math.inf(f64);

        for (0..N) |i| {
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

fn solveQuadraticRobust(a: f64, b: f64, c: f64, u_out: *f64) bool {
    const tol_area = 1e-12;
    if (@abs(a) < tol_area) {
        if (@abs(b) < tol_area) return false;
        const u = -c / b;
        if (u >= -1e-7 and u <= 1.0 + 1e-7) {
            u_out.* = u;
            return true;
        }
        return false;
    }

    const det = b * b - 4.0 * a * c;
    if (det < 0) return false;
    const sdet = @sqrt(det);
    const q = -0.5 * (b + (if (b >= 0) sdet else -sdet));
    const roots = [2]f64{ q / a, c / q };
    const eps = 1e-7;
    for (roots) |r| {
        if (r >= -eps and r <= 1.0 + eps) {
            u_out.* = r;
            return true;
        }
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

    const N: usize = 4; // nodes per element
    const tol_den = 1e-12;
    //const F: usize = 3; // max number of fields to render
    
    const fields_num = shader.field.dims[2];
    const actual_fields = @min(fields_num, 3);
    
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
            
            const k_ae_x = nr.x[0] - nr.x[1] + nr.x[2] - nr.x[3];
            const k_ae_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3];
            const k_be_x = nr.x[1] - nr.x[0];
            const k_be_z = nr.z[1] - nr.z[0];
            const k_ce_x = nr.x[3] - nr.x[0];
            const k_ce_z = nr.z[3] - nr.z[0];
            const k_de_x = nr.x[0];
            const k_de_z = nr.z[0];

            const k_af_x = nr.y[0] - nr.y[1] + nr.y[2] - nr.y[3];
            const k_af_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3];
            const k_bf_x = nr.y[1] - nr.y[0];
            const k_bf_z = nr.z[1] - nr.z[0];
            const k_cf_x = nr.y[3] - nr.y[0];
            const k_cf_z = nr.z[3] - nr.z[0];
            const k_df_x = nr.y[0];
            const k_df_z = nr.z[0];

            // Hoist fields from shader.field
            const elem_field_stride = shader.field.strides[1];
            const ff_stride = shader.field.strides[2];
            const elem_off = frame_ind * shader.field.strides[0] 
                             + ov.elem_ind * elem_field_stride;

            var f_vals = [3][4]f64{ undefined, undefined, undefined };
            
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

                    const ae = k_ae_x - k_ae_z * txs;
                    const be = k_be_x - k_be_z * txs;
                    const ce = k_ce_x - k_ce_z * txs;
                    const de = k_de_x - k_de_z * txs;

                    const af = k_af_x - k_af_z * tys;
                    const bf = k_bf_x - k_bf_z * tys;
                    const cf = k_cf_x - k_cf_z * tys;
                    const df = k_df_x - k_df_z * tys;

                    const qA = af * be - ae * bf;
                    const qB = af * de - ae * df + be * cf - bf * ce;
                    const qC = cf * de - ce * df;

                    var u: f64 = -1.0;
                    if (solveQuadraticRobust(qA, qB, qC, &u)) {
                        const den_e = ae * u + ce;
                        const den_f = af * u + cf;
                        var v: f64 = -1.0;

                        if (@abs(den_f) > @abs(den_e)) {
                            if (@abs(den_f) > tol_den) v = -(bf * u + df) / den_f;
                        } else {
                            if (@abs(den_e) > tol_den) v = -(be * u + de) / den_e;
                        }

                        if (v >= -1e-7 and v <= 1.0 + 1e-7) {

                            const N0 = (1.0-u)*(1.0-v); const N1 = u*(1.0-v);
                            const N2 = u*v; const N3 = (1.0-u)*v;
                            
                            const sw: f64 = N0 * nr.z[0] + N1 * nr.z[1] + 
                                            N2 * nr.z[2] + N3 * nr.z[3];
                            const inv_z = 1.0 / sw; const idx = row_off + xx;
                            
                            if (inv_z > spx_inv_z_scratch[idx]) {
                                spx_inv_z_scratch[idx] = inv_z;
                                for (0..actual_fields) |ff| {
                                    const val = N0 * f_vals[ff][0] + N1 * f_vals[ff][1] +
                                                N2 * f_vals[ff][2] + N3 * f_vals[ff][3];
                                    spx_image_scratch.elems[idx * fields_num + ff] = val;
                                }
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
    const tol_den = 1e-12;
    const fields_num: usize = 1;

    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step = 1.0 / sub_samp_f;
    
    const spx_tile_size = tile_size * sub_samp;
        
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

            const nr = try rops.loadVec3SlicesFromElemArray(
                N, f64, elem_coord_arr, ov.elem_ind,
            );

            const k_ae_x = nr.x[0] - nr.x[1] + nr.x[2] - nr.x[3];
            const k_ae_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3];
            const k_be_x = nr.x[1] - nr.x[0];
            const k_be_z = nr.z[1] - nr.z[0];
            const k_ce_x = nr.x[3] - nr.x[0];
            const k_ce_z = nr.z[3] - nr.z[0];
            const k_de_x = nr.x[0];
            const k_de_z = nr.z[0];

            const k_af_x = nr.y[0] - nr.y[1] + nr.y[2] - nr.y[3];
            const k_af_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3];
            const k_bf_x = nr.y[1] - nr.y[0];
            const k_bf_z = nr.z[1] - nr.z[0];
            const k_cf_x = nr.y[3] - nr.y[0];
            const k_cf_z = nr.z[3] - nr.z[0];
            const k_df_x = nr.y[0];
            const k_df_z = nr.z[0];

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

                    const ae = k_ae_x - k_ae_z * txs;
                    const be = k_be_x - k_be_z * txs;
                    const ce = k_ce_x - k_ce_z * txs;
                    const de = k_de_x - k_de_z * txs;

                    const af = k_af_x - k_af_z * tys;
                    const bf = k_bf_x - k_bf_z * tys;
                    const cf = k_cf_x - k_cf_z * tys;
                    const df = k_df_x - k_df_z * tys;

                    const qA = af * be - ae * bf;
                    const qB = af * de - ae * df + be * cf - bf * ce;
                    const qC = cf * de - ce * df;

                    var u: f64 = -1.0;
                    if (solveQuadraticRobust(qA, qB, qC, &u)) {
                        const den_e = ae * u + ce;
                        const den_f = af * u + cf;
                        var v: f64 = -1.0;
                        if (@abs(den_f) > @abs(den_e)) {
                            if (@abs(den_f) > tol_den) v = -(bf * u + df) / den_f;
                        } else {
                            if (@abs(den_e) > tol_den) v = -(be * u + de) / den_e;
                        }

                        if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                            const N0 = (1.0-u)*(1.0-v); const N1 = u*(1.0-v);
                            const N2 = u*v; const N3 = (1.0-u)*v;
                            const sw: f64 = N0 * nr.z[0] + N1 * nr.z[1] + 
                                            N2 * nr.z[2] + N3 * nr.z[3];
                            const inv_z = 1.0 / sw; const idx = row_off + xx;
                            if (inv_z > spx_inv_z_scratch[idx]) {
                                spx_inv_z_scratch[idx] = inv_z;
                                const u_at = N0 * uv_vals[0][0] + N1 * uv_vals[0][1] +
                                             N2 * uv_vals[0][2] + N3 * uv_vals[0][3];
                                const v_at = N0 * uv_vals[1][0] + N1 * uv_vals[1][1] +
                                             N2 * uv_vals[1][2] + N3 * uv_vals[1][3];

                                spx_image_scratch.elems[idx] = ti.sampleGreyscale(
                                    interp_type,
                                    shader.texture,
                                    u_at,
                                    v_at,
                                );
                            }
                        }
                    }
                }
            }
        }

        rops.averageScratch(
            tile,
            tile_size,
            @intCast(camera.pixels_num[0]),
            @intCast(camera.pixels_num[1]),
            sub_samp,
            spx_tile_size,
            fields_num,
            &spx_image_scratch,
            spx_field_avg,
            image_out_arr,
        );

    }
}
