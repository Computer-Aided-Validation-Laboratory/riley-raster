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

const newton = @import("newton.zig");

pub fn countElemsCalcBBoxes(camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            elem_bboxes: []BBox) !usize {
    const N: usize = 8;
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

fn shapeFunctions8(u: f64, v: f64, n_v: *[8]f64, dNu: *[8]f64, dNv: *[8]f64) void {
    const shapefun = @import("shapefun.zig");
    shapefun.shapeFunctions(8, u, v, n_v, dNu, dNv);
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
    const N: usize = 8;

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
            const frame_offset = frame_ind * shader.field.strides[0];
            const elem_offset = frame_offset + ov.elem_ind * elem_field_stride;
            var f_vals = [3][8]f64{ undefined, undefined, undefined };
            const actual_fields = @min(fields_num, 3);
            for (0..actual_fields) |ff| {
                const ff_off = elem_offset + ff * ff_stride;
                inline for (0..8) |ii| {
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
                    if (newton.solveInverse(N, txs, tys, nr.x, nr.y, nr.z, u, v, &u, &v)) {
                        var n_v: [8]f64 = undefined; var dNu: [8]f64 = undefined; 
                        var dNv: [8]f64 = undefined;
                        shapeFunctions8(u, v, &n_v, &dNu, &dNv);
                        var sw: f64 = 0.0;
                        for (0..8) |i| sw += n_v[i] * nr.z[i];
                        const inv_z = 1.0 / sw; const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            for (0..actual_fields) |ff| {
                                var vs: f64 = 0.0;
                                for (0..8) |i| {
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
    const N: usize = 8;
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
            var uv_vals = [2][8]f64{ undefined, undefined };
            inline for (0..2) |cc| {
                const comp_off = elem_uv_off + cc * comp_uv_stride;
                inline for (0..8) |ii| {
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
                    if (newton.solveInverse(N, txs, tys, nr.x, nr.y, nr.z, u, v, &u, &v)) {
                        var n_v: [8]f64 = undefined; 
                        var dNu_full: [8]f64 = undefined; 
                        var dNv_full: [8]f64 = undefined;
                        shapeFunctions8(u, v, &n_v, &dNu_full, &dNv_full);
                        var sw: f64 = 0.0;
                        for (0..8) |i| sw += n_v[i] * nr.z[i];
                        const inv_z = 1.0 / sw; const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            var u_at: f64 = 0.0; var v_at: f64 = 0.0;
                            for (0..8) |i| {
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
