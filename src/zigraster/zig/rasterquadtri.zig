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

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

fn shapeFunctions(xi: f64, eta: f64, N: *[6]f64, dN_dxi: *[6]f64, dN_deta: *[6]f64) void {
    const L1 = 1.0 - xi - eta;
    const L2 = xi;
    const L3 = eta;

    N[0] = L1 * (2.0 * L1 - 1.0);
    dN_dxi[0] = -(4.0 * L1 - 1.0);
    dN_deta[0] = -(4.0 * L1 - 1.0);

    N[1] = L2 * (2.0 * L2 - 1.0);
    dN_dxi[1] = 4.0 * L2 - 1.0;
    dN_deta[1] = 0.0;

    N[2] = L3 * (2.0 * L3 - 1.0);
    dN_dxi[2] = 0.0;
    dN_deta[2] = 4.0 * L3 - 1.0;

    N[3] = 4.0 * L1 * L2;
    dN_dxi[3] = 4.0 * (L1 - L2);
    dN_deta[3] = -4.0 * L2;

    N[4] = 4.0 * L2 * L3;
    dN_dxi[4] = 4.0 * L3;
    dN_deta[4] = 4.0 * L2;

    N[5] = 4.0 * L3 * L1;
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

        const area = edgeFun3(x0, y0, x1, y1, x2, y2);
        if (@abs(area) < 1e-12) continue;

        const w0 = edgeFun3(x1, y1, x2, y2, txs, tys) / area;
        const w1 = edgeFun3(x2, y2, x0, y0, txs, tys) / area;
        const w2 = edgeFun3(x0, y0, x1, y1, txs, tys) / area;

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
    var N_vals: [6]f64 = undefined;
    var dN_dxi: [6]f64 = undefined;
    var dN_deta: [6]f64 = undefined;

    for (0..max_iter) |_| {
        shapeFunctions(xi, eta, &N_vals, &dN_dxi, &dN_deta);

        var Rx: f64 = 0.0; var Ry: f64 = 0.0;
        var J11: f64 = 0.0; var J12: f64 = 0.0;
        var J21: f64 = 0.0; var J22: f64 = 0.0;

        for (0..6) |i| {
            const tx = txs * ew[i] - ex[i];
            const ty = tys * ew[i] - ey[i];
            Rx += N_vals[i] * tx;
            Ry += N_vals[i] * ty;
            J11 += dN_dxi[i] * tx;
            J12 += dN_deta[i] * tx;
            J21 += dN_dxi[i] * ty;
            J22 += dN_deta[i] * ty;
        }

        if (@abs(Rx) < tol and @abs(Ry) < tol) break;

        const det = J11 * J22 - J12 * J21;
        if (@abs(det) < 1e-12) return false;

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

//---------------------------------------------------------------------------------------------
pub fn rasterFrame(allocator: std.mem.Allocator,
                   io: std.Io,
                   frame_ind: usize,
                   coords: *const Coords,
                   connect: *const Connect,
                   field: *const Field,
                   camera: *const Camera,
                   image_out_arr: *NDArray(f64)) !void {

    const tile_size: u16 = 32;

    const raster_start = std.Io.Clock.Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // 0. Element Data Pre-transform
    const elems_num = connect.elem_n;
    const fields_num = field.getFieldsN();

    var elem_coord_arr = try initElemArray(f64, arena_alloc, elems_num, 3, 6);
    var elem_field_arr = try initElemArray(f64, arena_alloc, elems_num, fields_num, 6);

    fillElemCoords(coords, connect, 0, 2, 1, &elem_coord_arr);
    fillElemFields(connect, field, frame_ind, 0, 2, 1, &elem_field_arr);

    const x_scale = camera.image_dist * @as(f64, @floatFromInt(camera.pixels_num[0])) 
                    / camera.image_dims[0];
    const y_scale = camera.image_dist * @as(f64, @floatFromInt(camera.pixels_num[1])) 
                    / camera.image_dims[1];

    //-----------------------------------------------------------------------------------------
    // 1. World to Camera/Raster Coords
    
    // TODO: refactor this - SIMD check.
    for (0..elems_num) |ee| {
        const cw: Vec3SIMD(6, f64) = try vsd.loadVec3SIMDFromElemArray(6, 
                                                                      f64, 
                                                                      &elem_coord_arr, 
                                                                      ee);
        var cr = vsd.mat44Mul(6, f64, camera.world_to_cam_mat, cw);

        cr.x *= @splat(x_scale);
        cr.y *= @splat(-y_scale);
        
        try vsd.saveVec3SIMDToElemArray(6, 
                                        f64, 
                                        &elem_coord_arr, 
                                        ee,
                                        Vec3SIMD(6, f64){ .x = cr.x, .y = cr.y, .z = -cr.z });
    }

    //-----------------------------------------------------------------------------------------
    // 2. Calculate Elem Bounding Boxes

    const elem_bboxes = try arena_alloc.alloc(BBox, elems_num);
    var elems_in_image: usize = 0;

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elems_num) |ee| {
        const cr = try loadVec3SlicesFromElemArray(6, f64, &elem_coord_arr, ee);

        var x_min: f64 = std.math.inf(f64); var x_max: f64 = -std.math.inf(f64);
        var y_min: f64 = std.math.inf(f64); var y_max: f64 = -std.math.inf(f64);
        for (0..6) |i| {
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

    //-----------------------------------------------------------------------------------------
    // 3. Element Tile Overlap: COUNT only to alloc 

    // TODO: refactor this for naming
    const tx_n = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const ty_n = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);
    const t_elem_counts = try arena_alloc.alloc(usize, tx_n * ty_n);
    @memset(t_elem_counts, 0);

    for (elem_bboxes[0..elems_in_image]) |bbox| {
        const tmin_x = bbox.x_min / tile_size;
        const tmax_x = (bbox.x_max + tile_size - 1) / tile_size;
        const tmin_y = bbox.y_min / tile_size;
        const tmax_y = (bbox.y_max + tile_size - 1) / tile_size;
        for (tmin_y..tmax_y) |ty| {
            for (tmin_x..tmax_x) |tx| {
                t_elem_counts[ty * tx_n + tx] += 1;
            }
        }
    }

    
    // Count the active tiles and work out the write offsets into the overlap boxes
    const t_write_inds = try arena_alloc.alloc(usize, tx_n * ty_n);
    var offset: usize = 0; 
    var num_active: usize = 0;
    for (t_elem_counts, 0..) |cc, ii| {
        t_write_inds[ii] = offset; 
        offset += cc;
        if (cc > 0) {
            num_active += 1;
        }
    }


    //-----------------------------------------------------------------------------------------
    // 4. Element Tile Overlap: Store overlap bounding boxes for ACTIVE tiles only.

    const overlap_bboxes = try arena_alloc.alloc(BBox, offset);
    const active_tiles = try arena_alloc.alloc(ActiveTile, num_active);
    var act_ptr: usize = 0;

    for (t_elem_counts, 0..) |cc, ii| {
        if (cc > 0) {
            active_tiles[act_ptr] = ActiveTile{
                .overlap_start = t_write_inds[ii], .overlap_count = cc,
                .x_px_min = @as(u16, @intCast(ii % tx_n)) * tile_size,
                .y_px_min = @as(u16, @intCast(ii / tx_n)) * tile_size
            };
            act_ptr += 1;
        }
    }

    for (elem_bboxes[0..elems_in_image]) |bbox| {
        const tmin_x = bbox.x_min / tile_size; const tmin_y = bbox.y_min / tile_size;
        const tmax_x = @min(@as(u16, @intCast(tx_n)), (bbox.x_max + tile_size - 1) / tile_size);
        const tmax_y = @min(@as(u16, @intCast(ty_n)), (bbox.y_max + tile_size - 1) / tile_size);

        for (tmin_y..tmax_y) |ty| {
            for (tmin_x..tmax_x) |tx| {
                const write_idx = t_write_inds[ty * tx_n + tx]; t_write_inds[ty * tx_n + tx] += 1;
                const px_lim_x = @as(u16, @intCast(camera.pixels_num[0]));
                const px_lim_y = @as(u16, @intCast(camera.pixels_num[1]));

                overlap_bboxes[write_idx] = BBox{
                    .elem_ind = bbox.elem_ind,
                    .x_min = @max(bbox.x_min, @as(u16, @intCast(tx * tile_size))),
                    .x_max = @min(bbox.x_max, @as(u16, @min(@as(u16, @intCast((tx + 1) * tile_size)), px_lim_x))),
                    .y_min = @max(bbox.y_min, @as(u16, @intCast(ty * tile_size))),
                    .y_max = @min(bbox.y_max, @as(u16, @min(@as(u16, @intCast((ty + 1) * tile_size)), px_lim_y)))
                };
            }
        }
    }

    //-----------------------------------------------------------------------------------------
    // 5. Raster Loop
    
    try rasterTilesQuadProjected(allocator, 
                                 camera, 
                                 tile_size, 
                                 active_tiles,
                                 overlap_bboxes, 
                                 &elem_coord_arr, 
                                 &elem_field_arr, 
                                 image_out_arr);

    const raster_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time_all = @as(f64, 
        @floatFromInt(raster_start.durationTo(raster_end).raw.nanoseconds));
    const px_cnt = @as(f64, @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
    const total_px = px_cnt * @as(f64, @floatFromInt(camera.sub_sample * camera.sub_sample));
    const p_break = [_]u8{'='} ** 80;

    print("\n{s}\nSoftware Raster Times (NonLinear Proj V2)\n{s}\n", .{ p_break, p_break });
    print("TOTAL RASTER TIME  = {d:.3} ms\n", .{time_all / 1e6});
    print("MOps/second = {d:.2}\n", .{ 1e3 * total_px / time_all });
    print("MTri/second = {d:.2}\n{s}\n", .{ 1e3 * @as(f64, @floatFromInt(elems_num)) / time_all, p_break });
}

pub fn rasterTilesQuadProjected(allocator: std.mem.Allocator,
                                camera: *const Camera,
                                tile_size: u16,
                                active_tiles: []ActiveTile,
                                overlap_bboxes: []BBox,
                                elem_coord_arr: *const NDArray(f64),
                                elem_field_arr: *const NDArray(f64),
                                image_out_arr: *NDArray(f64)) !void {

    const fields_num = elem_field_arr.dims[1];

    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
        
    const spx_tile_size = tile_size * sub_samp;

    const spx_step = 1.0 / sub_samp_f;
    const spx_offset = 1.0 / (2.0 * sub_samp_f);

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_size * spx_tile_size);
    defer allocator.free(spx_inv_z_scratch);
    
    const spx_img_scratch_mem = try allocator.alloc(f64,spx_tile_size*spx_tile_size*fields_num)
    defer allocator.free(spx_img_scratch_mem);
    
    var spx_image_scratch = MatSlice(f64).init(spx_img_scratch_mem,
                                               spx_tile_size * spx_tile_size,
                                               fields_num);

    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        for (overlap_bboxes[tile.overlap_start .. tile.overlap_start + tile.overlap_count]) |ov| {
            const nr = try loadVec3SlicesFromElemArray(6, f64, elem_coord_arr, ov.elem_ind);

            const s_start_x = sub_samp * (@as(usize, ov.x_min) - tile.x_px_min);
            const s_end_x = sub_samp * (@as(usize, ov.x_max) - tile.x_px_min);
            const s_start_y = sub_samp * (@as(usize, ov.y_min) - tile.y_px_min);
            const s_end_y = sub_samp * (@as(usize, ov.y_max) - tile.y_px_min);

            for (s_start_y..s_end_y) |yy| {
                const row_off = yy * spx_tile_size;

                const spx_y = @as(f64, @floatFromInt(ov.y_min)) 
                              + spx_offset 
                              + @as(f64, @floatFromInt(yy - s_start_y)) * spx_step;

                for (s_start_x..s_end_x) |xx| {
                    const spx_x = @as(f64, @floatFromInt(ov.x_min)) 
                                  + spx_offset 
                                  + @as(f64, @floatFromInt(xx - s_start_x)) * spx_step;

                    var xi: f64 = 0.0; 
                    var eta: f64 = 0.0;

                    if (solveInverseMapProjected(spx_x - x_off, spx_y - y_off, nr.x, nr.y, nr.z,
                                                 0.0, 0.0, &xi, &eta)) {
                        var N_vals: [6]f64 = undefined;
                        var dN_dxi: [6]f64 = undefined;
                        var dN_deta: [6]f64 = undefined;
                        shapeFunctions(xi, eta, &N_vals, &dN_dxi, &dN_deta);

                        var sw: f64 = 0.0;
                        for (0..6) |i| sw += N_vals[i] * nr.z[i];
                        const inv_z = 1.0 / sw;

                        const idx = row_off + xx;
                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            for (0..fields_num) |ff| {
                                var vs: f64 = 0.0;
                                for (0..6) |i| vs += N_vals[i] * elem_field_arr.get(&[_]usize{ ov.elem_ind, ff, i });
                                spx_image_scratch.set(idx, ff, vs);
                            }
                        }
                    }
                }
            }
        }

        const inv_ss_sq = 1.0 / (sub_samp_f * sub_samp_f);
        const px_lim_x = @as(u16, @intCast(camera.pixels_num[0]));
        const px_lim_y = @as(u16, @intCast(camera.pixels_num[1]));
        const cur_ts_x = @min(@as(u16, tile_size), px_lim_x - tile.x_px_min);
        const cur_ts_y = @min(@as(u16, tile_size), px_lim_y - tile.y_px_min);

        for (0..cur_ts_y) |ty| {
            for (0..cur_ts_x) |tx| {
                @memset(spx_field_avg, 0.0);
                for (0..sub_samp) |sy| {
                    const r_off = (sub_samp * ty + sy) * spx_tile_size;
                    for (0..sub_samp) |sx| {
                        const idx = r_off + sub_samp * tx + sx;
                        for (0..fields_num) |ff| spx_field_avg[ff] += spx_image_scratch.get(idx, ff);
                    }
                }
                for (0..fields_num) |ff| {
                    const img_y = tile.y_px_min + ty;
                    const img_x = tile.x_px_min + tx;
                    image_out_arr.set(&[_]usize{ ff, img_y, img_x }, spx_field_avg[ff] * inv_ss_sq);
                }
            }
        }
    }
}
