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
const SolverConfig = newton.SolverConfig;

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

fn shapeFunctions(u: f64, v: f64, n_v: *[6]f64, dNu: *[6]f64, dNv: *[6]f64) void {
    const shapefun = @import("shapefun.zig");
    shapefun.shapeFunctions(6, u, v, n_v, dNu, dNv);
}

fn getTessellatedGuess(txs: f64, tys: f64, ex: []const f64, ey: []const f64, ew: []const f64,
                       xi_out: *f64, eta_out: *f64) bool {

    const tol_area: f64 = 1e-12;
    const eps = 1e-5;

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
        if (@abs(area) < tol_area) continue;

        const w0 = ((txs - x0) * (y1 - y0) - (tys - y0) * (x1 - x0)) / area;
        const w1 = ((txs - x1) * (y2 - y1) - (tys - y1) * (x2 - x1)) / area;
        const w2 = ((txs - x2) * (y0 - y2) - (tys - y2) * (x0 - x2)) / area;

        if (w0 >= -eps and w1 >= -eps and w2 >= -eps) {
            xi_out.* = w0 * st.xi0 + w1 * st.xi1 + w2 * st.xi2;
            eta_out.* = w0 * st.eta0 + w1 * st.eta1 + w2 * st.eta2;
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
    
    const N: usize = 6;

    const elem_field_arr = shader.field;
    const fields_num = elem_field_arr.dims[2];
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

                    if (getTessellatedGuess(spx_x - x_off, spx_y - y_off, nr.x, nr.y, nr.z, &xi, &eta)) {
                        converged = newton.solveInverse(N, spx_x - x_off, 
                                                             spx_y - y_off, 
                                                             nr.x, nr.y, nr.z, 
                                                             xi, eta, &xi, &eta);
                    }

                    if (!converged) {
                        converged = newton.solveInverse(N, spx_x - x_off, 
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
                                for (0..6) |ii| vs += n_vals[ii] * elem_field_arr.get(
                                    &[_]usize{ frame_ind, ov.elem_ind, ff, ii },
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

pub fn rasterElemsTex(
    comptime interp_type: ti.InterpType,
    allocator: std.mem.Allocator,
    camera: *const Camera,
    tile_size: u16,
    active_tiles: []ActiveTile,
    overlap_bboxes: []BBox,
    elem_coord_arr: *const NDArray(f64),
    shader: *const TexShader,
    image_out_arr: *NDArray(f64),
) !void {

    @setFloatMode(.optimized);

    const N: usize = 6;

    const fields_num: usize = 1;
    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const spx_tile_size = @as(usize, @intCast(tile_size)) * sub_samp;
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
            
            // Hoist UVs from shader.uvs
            const elem_uv_stride = shader.uvs.strides[0];
            const comp_uv_stride = shader.uvs.strides[1];
            const elem_uv_off = ov.elem_ind * elem_uv_stride;
            var uv_vals = [2][6]f64{ undefined, undefined };
            inline for (0..2) |cc| {
                const comp_off = elem_uv_off + cc * comp_uv_stride;
                inline for (0..6) |ii| {
                    uv_vals[cc][ii] = shader.uvs.elems[comp_off + ii];
                }
            }

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
                    if (getTessellatedGuess(spx_x - x_off, spx_y - y_off, nr.x, nr.y, nr.z, &xi, &eta)) {
                        converged = newton.solveInverse(
                            N, spx_x - x_off, spx_y - y_off, nr.x, nr.y, nr.z, xi, eta, &xi, &eta
                        );
                    }
                    if (!converged) {
                        converged = newton.solveInverse(
                            N, spx_x - x_off, spx_y - y_off, nr.x, nr.y, nr.z, 1.0/3.0, 1.0/3.0, 
                            &xi, &eta
                        );
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
                            var u_at: f64 = 0.0; var v_at: f64 = 0.0;
                            inline for (0..6) |ii| {
                                u_at += n_vals[ii] * uv_vals[0][ii];
                                v_at += n_vals[ii] * uv_vals[1][ii];
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
