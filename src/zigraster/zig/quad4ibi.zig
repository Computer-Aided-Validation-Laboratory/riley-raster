const std = @import("std");

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const Camera = @import("camera.zig").Camera;
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const ti = @import("textureinterp.zig");
const shader = @import("shader.zig");
const FlatShader = shader.FlatShader;
const TexShader = shader.TexShader;

const SolverParams = struct {
    ae_x: f64, ae_z: f64, be_x: f64, be_z: f64, ce_x: f64, ce_z: f64, de_x: f64, de_z: f64,
    af_x: f64, af_z: f64, bf_x: f64, bf_z: f64, cf_x: f64, cf_z: f64, df_x: f64, df_z: f64,
};

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

fn shadeFlat(
    frame_ind: usize,
    actual_fields: usize,
    fields_num: usize,
    ov: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    spx_step: f64,
    x_off: f64,
    y_off: f64,
    k: SolverParams,
    nr: Vec3OfSlices(f64),
    sh: *const FlatShader,
    spx_inv_z_scratch: []f64,
    spx_image_scratch: *MatSlice(f64),
) void {
    const N = 4;
    const tol_den = 1e-12;

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
            const ae = k.ae_x - k.ae_z * txs; const be = k.be_x - k.be_z * txs;
            const ce = k.ce_x - k.ce_z * txs; const de = k.de_x - k.de_z * txs;
            const af = k.af_x - k.af_z * tys; const bf = k.bf_x - k.bf_z * tys;
            const cf = k.cf_x - k.cf_z * tys; const df = k.df_x - k.df_z * tys;
            const qA = af * be - ae * bf;
            const qB = af * de - ae * df + be * cf - bf * ce;
            const qC = cf * de - ce * df;
            var u: f64 = -1.0;
            if (solveQuadraticRobust(qA, qB, qC, &u)) {
                const den_e = ae * u + ce; const den_f = af * u + cf;
                var v: f64 = -1.0;
                if (@abs(den_f) > @abs(den_e)) {
                    if (@abs(den_f) > tol_den) v = -(bf * u + df) / den_f;
                } else {
                    if (@abs(den_e) > tol_den) v = -(be * u + de) / den_e;
                }
                if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                    const n_vals = [_]f64{
                        (1.0 - u) * (1.0 - v), u * (1.0 - v), u * v, (1.0 - u) * v,
                    };
                    const sw = n_vals[0]*nr.z[0] + n_vals[1]*nr.z[1] + 
                               n_vals[2]*nr.z[2] + n_vals[3]*nr.z[3];
                    const inv_z = 1.0 / sw; const idx = row_off + xx;
                    if (inv_z > spx_inv_z_scratch[idx]) {
                        spx_inv_z_scratch[idx] = inv_z;
                        shader.fillFlat(N, frame_ind, ov.elem_ind, actual_fields, 
                                        fields_num, n_vals, sh, idx, spx_image_scratch);
                    }
                }
            }
        }
    }
}

fn shadeTex(
    ov: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    spx_step: f64,
    x_off: f64,
    y_off: f64,
    k: SolverParams,
    nr: Vec3OfSlices(f64),
    sh: *const TexShader,
    spx_inv_z_scratch: []f64,
    spx_image_scratch: *MatSlice(f64),
) void {
    const N = 4;
    const tol_den = 1e-12;

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
            const ae = k.ae_x - k.ae_z * txs; const be = k.be_x - k.be_z * txs;
            const ce = k.ce_x - k.ce_z * txs; const de = k.de_x - k.de_z * txs;
            const af = k.af_x - k.af_z * tys; const bf = k.bf_x - k.bf_z * tys;
            const cf = k.cf_x - k.cf_z * tys; const df = k.df_x - k.df_z * tys;
            const qA = af * be - ae * bf;
            const qB = af * de - ae * df + be * cf - bf * ce;
            const qC = cf * de - ce * df;
            var u: f64 = -1.0;
            if (solveQuadraticRobust(qA, qB, qC, &u)) {
                const den_e = ae * u + ce; const den_f = af * u + cf;
                var v: f64 = -1.0;
                if (@abs(den_f) > @abs(den_e)) {
                    if (@abs(den_f) > tol_den) v = -(bf * u + df) / den_f;
                } else {
                    if (@abs(den_e) > tol_den) v = -(be * u + de) / den_e;
                }
                if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                    const n_vals = [_]f64{
                        (1.0 - u) * (1.0 - v), u * (1.0 - v), u * v, (1.0 - u) * v,
                    };
                    const sw = n_vals[0]*nr.z[0] + n_vals[1]*nr.z[1] + 
                               n_vals[2]*nr.z[2] + n_vals[3]*nr.z[3];
                    const inv_z = 1.0 / sw; const idx = row_off + xx;
                    if (inv_z > spx_inv_z_scratch[idx]) {
                        spx_inv_z_scratch[idx] = inv_z;
                        switch (sh.interp_type) {
                            inline else => |it| shader.fillTex(N, it, ov.elem_ind, 
                                n_vals, sh, idx, spx_image_scratch),
                        }
                    }
                }
            }
        }
    }
}

pub fn rasterElems(
    allocator: std.mem.Allocator,
    camera: *const Camera,
    frame_ind: usize,
    tile_size: u16,
    active_tiles: []ActiveTile,
    overlap_bboxes: []BBox,
    elem_coord_arr: *const NDArray(f64),
    sh: anytype,
    image_out_arr: *NDArray(f64),
) !void {
    @setFloatMode(.optimized);

    const N: usize = 4;

    const fields_num: usize = switch (@TypeOf(sh)) {
        *const FlatShader => sh.field.dims[2],
        *const TexShader => 1,
        else => @compileError("Unsupported shader type"),
    };
    const actual_fields = if (@TypeOf(sh) == *const FlatShader) 
        @min(fields_num, 3) else 1;

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
    var spx_image_scratch = MatSlice(f64).init(spx_img_mem, spx_tile_size * spx_tile_size, 
                                               fields_num);
    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        for (overlap_bboxes[tile.overlap_start .. 
                            tile.overlap_start + tile.overlap_count]) |ov| {
            const nr = try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, 
                                                            ov.elem_ind);

            const k = SolverParams{
                .ae_x = nr.x[0] - nr.x[1] + nr.x[2] - nr.x[3],
                .ae_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3],
                .be_x = nr.x[1] - nr.x[0], .be_z = nr.z[1] - nr.z[0],
                .ce_x = nr.x[3] - nr.x[0], .ce_z = nr.z[3] - nr.z[0],
                .de_x = nr.x[0], .de_z = nr.z[0],
                .af_x = nr.y[0] - nr.y[1] + nr.y[2] - nr.y[3],
                .af_z = nr.z[0] - nr.z[1] + nr.z[2] - nr.z[3],
                .bf_x = nr.y[1] - nr.y[0], .bf_z = nr.z[1] - nr.z[0],
                .cf_x = nr.y[3] - nr.y[0], .cf_z = nr.z[3] - nr.z[0],
                .df_x = nr.y[0], .df_z = nr.z[0],
            };

            switch (@TypeOf(sh)) {
                *const FlatShader => shadeFlat(frame_ind, actual_fields, fields_num, 
                    ov, tile, sub_samp, spx_tile_size, spx_step, x_off, y_off, k, nr, 
                    sh, spx_inv_z_scratch, &spx_image_scratch),
                *const TexShader => shadeTex(ov, tile, sub_samp, spx_tile_size, 
                    spx_step, x_off, y_off, k, nr, sh, spx_inv_z_scratch, 
                    &spx_image_scratch),
                else => unreachable,
            }
        }
        rops.averageScratch(tile, tile_size, @intCast(camera.pixels_num[0]), 
                            @intCast(camera.pixels_num[1]), sub_samp, spx_tile_size, 
                            fields_num, &spx_image_scratch, spx_field_avg, image_out_arr);
    }
}
