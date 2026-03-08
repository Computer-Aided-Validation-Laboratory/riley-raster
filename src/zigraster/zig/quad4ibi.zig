const std = @import("std");

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const Camera = @import("camera.zig").Camera;
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const texops = @import("textureops.zig");
const shaderops = @import("shaderops.zig");
const FlatShader = shaderops.FlatShader;
const TexShader = shaderops.TexShader;

const N: usize = 4;

const SolverParams = struct {
    ae_x: f64,
    ae_z: f64,
    be_x: f64,
    be_z: f64,
    ce_x: f64,
    ce_z: f64,
    de_x: f64,
    de_z: f64,
    af_x: f64,
    af_z: f64,
    bf_x: f64,
    bf_z: f64,
    cf_x: f64,
    cf_z: f64,
    df_x: f64,
    df_z: f64,
};

fn solveQuadraticRobust(a: f64, b: f64, c: f64, u_out: *f64) bool {
    const tol_area = 1e-12;
    if (@abs(a) < tol_area) {
        if (@abs(b) < tol_area) {
            return false;
        }
        const u = -c / b;
        if (u >= -1e-7 and u <= 1.0 + 1e-7) {
            u_out.* = u;
            return true;
        }
        return false;
    }

    const det = b * b - 4.0 * a * c;
    if (det < 0) {
        return false;
    }
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
    overlap: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    sub_pixel_tile_size: usize,
    sub_pixel_step: f64,
    x_off: f64,
    y_off: f64,
    solver_k: SolverParams,
    node_coords: Vec3OfSlices(f64),
    flat_shader: *const FlatShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const tol_den = 1e-12;

    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const scratch_row_offset = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;
        const tys = sub_pixel_y - y_off;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            const txs = sub_pixel_x - x_off;

            const ae = solver_k.ae_x - solver_k.ae_z * txs;
            const be = solver_k.be_x - solver_k.be_z * txs;
            const ce = solver_k.ce_x - solver_k.ce_z * txs;
            const de = solver_k.de_x - solver_k.de_z * txs;

            const af = solver_k.af_x - solver_k.af_z * tys;
            const bf = solver_k.bf_x - solver_k.bf_z * tys;
            const cf = solver_k.cf_x - solver_k.cf_z * tys;
            const df = solver_k.df_x - solver_k.df_z * tys;

            const qA = af * be - ae * bf;
            const qB = af * de - ae * df + be * cf - bf * ce;
            const qC = cf * de - ce * df;

            var u: f64 = -1.0;
            if (solveQuadraticRobust(qA, qB, qC, &u)) {
                const den_e = ae * u + ce;
                const den_f = af * u + cf;
                var v: f64 = -1.0;

                if (@abs(den_f) > @abs(den_e)) {
                    if (@abs(den_f) > tol_den) {
                        v = -(bf * u + df) / den_f;
                    }
                } else {
                    if (@abs(den_e) > tol_den) {
                        v = -(be * u + de) / den_e;
                    }
                }

                if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                    const n_vals = [_]f64{
                        (1.0 - u) * (1.0 - v),
                        u * (1.0 - v),
                        u * v,
                        (1.0 - u) * v,
                    };

                    var sub_pixel_inv_z: f64 = 0.0;
                    inline for (0..N) |i| {
                        sub_pixel_inv_z += n_vals[i] * node_coords.z[i];
                    }

                    const inv_z = 1.0 / sub_pixel_inv_z;
                    const scratch_flat_ind = scratch_row_offset + xx;

                    if (inv_z > sub_pixel_inv_z_scratch[scratch_flat_ind]) {
                        sub_pixel_inv_z_scratch[scratch_flat_ind] = inv_z;
                        shaderops.fillFlat(
                            N,
                            frame_ind,
                            overlap.elem_ind,
                            actual_fields,
                            fields_num,
                            n_vals,
                            flat_shader,
                            scratch_flat_ind,
                            sub_pixel_image_scratch,
                        );
                    }
                }
            }
        }
    }
}

fn shadeTex(
    overlap: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    sub_pixel_tile_size: usize,
    sub_pixel_step: f64,
    x_off: f64,
    y_off: f64,
    solver_k: SolverParams,
    node_coords: Vec3OfSlices(f64),
    tex_shader: *const TexShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const tol_den = 1e-12;

    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const scratch_row_offset = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;
        const tys = sub_pixel_y - y_off;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            const txs = sub_pixel_x - x_off;

            const ae = solver_k.ae_x - solver_k.ae_z * txs;
            const be = solver_k.be_x - solver_k.be_z * txs;
            const ce = solver_k.ce_x - solver_k.ce_z * txs;
            const de = solver_k.de_x - solver_k.de_z * txs;

            const af = solver_k.af_x - solver_k.af_z * tys;
            const bf = solver_k.bf_x - solver_k.bf_z * tys;
            const cf = solver_k.cf_x - solver_k.cf_z * tys;
            const df = solver_k.df_x - solver_k.df_z * tys;

            const qA = af * be - ae * bf;
            const qB = af * de - ae * df + be * cf - bf * ce;
            const qC = cf * de - ce * df;

            var u: f64 = -1.0;
            if (solveQuadraticRobust(qA, qB, qC, &u)) {
                const den_e = ae * u + ce;
                const den_f = af * u + cf;
                var v: f64 = -1.0;

                if (@abs(den_f) > @abs(den_e)) {
                    if (@abs(den_f) > tol_den) {
                        v = -(bf * u + df) / den_f;
                    }
                } else {
                    if (@abs(den_e) > tol_den) {
                        v = -(be * u + de) / den_e;
                    }
                }

                if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                    const n_vals = [_]f64{
                        (1.0 - u) * (1.0 - v),
                        u * (1.0 - v),
                        u * v,
                        (1.0 - u) * v,
                    };

                    var sub_pixel_inv_z: f64 = 0.0;
                    inline for (0..N) |i| {
                        sub_pixel_inv_z += n_vals[i] * node_coords.z[i];
                    }

                    const inv_z = 1.0 / sub_pixel_inv_z;
                    const scratch_flat_ind = scratch_row_offset + xx;

                    if (inv_z > sub_pixel_inv_z_scratch[scratch_flat_ind]) {
                        sub_pixel_inv_z_scratch[scratch_flat_ind] = inv_z;
                        switch (tex_shader.interp_type) {
                            inline else => |it| shaderops.fillTex(
                                N,
                                it,
                                overlap.elem_ind,
                                n_vals,
                                tex_shader,
                                scratch_flat_ind,
                                sub_pixel_image_scratch,
                            ),
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
    shader: anytype,
    image_out_arr: *NDArray(f64),
) !void {
    @setFloatMode(.optimized);

    const fields_num: usize = switch (@TypeOf(shader)) {
        *const FlatShader => shader.field.dims[2],
        *const TexShader => 1,
        else => @compileError("Unsupported shader type"),
    };
    const actual_fields = if (@TypeOf(shader) == *const FlatShader)
        @min(fields_num, 3)
    else
        1;

    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const sub_pixel_tile_size = tile_size * sub_samp;
    const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
    const sub_pixel_step = 1.0 / sub_samp_f;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const sub_pixel_inv_z_scratch = try allocator.alloc(
        f64,
        sub_pixel_tile_size * sub_pixel_tile_size,
    );
    defer allocator.free(sub_pixel_inv_z_scratch);
    const sub_pixel_img_mem = try allocator.alloc(
        f64,
        sub_pixel_tile_size * sub_pixel_tile_size * fields_num,
    );
    defer allocator.free(sub_pixel_img_mem);
    var sub_pixel_image_scratch = MatSlice(f64).init(
        sub_pixel_img_mem,
        sub_pixel_tile_size * sub_pixel_tile_size,
        fields_num,
    );
    const sub_pixel_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(sub_pixel_field_avg);

    for (active_tiles) |tile| {
        @memset(sub_pixel_inv_z_scratch, 0.0);
        @memset(sub_pixel_image_scratch.elems, 0.0);

        for (overlap_bboxes[tile.overlap_start..
                            tile.overlap_start + tile.overlap_count]) |overlap| {
            const node_coords = try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                elem_coord_arr,
                overlap.elem_ind,
            );

            const solver_k = SolverParams{
                .ae_x = node_coords.x[0] - node_coords.x[1] + 
                        node_coords.x[2] - node_coords.x[3],
                .ae_z = node_coords.z[0] - node_coords.z[1] + 
                        node_coords.z[2] - node_coords.z[3],
                .be_x = node_coords.x[1] - node_coords.x[0],
                .be_z = node_coords.z[1] - node_coords.z[0],
                .ce_x = node_coords.x[3] - node_coords.x[0],
                .ce_z = node_coords.z[3] - node_coords.z[0],
                .de_x = node_coords.x[0],
                .de_z = node_coords.z[0],
                .af_x = node_coords.y[0] - node_coords.y[1] + 
                        node_coords.y[2] - node_coords.y[3],
                .af_z = node_coords.z[0] - node_coords.z[1] + 
                        node_coords.z[2] - node_coords.z[3],
                .bf_x = node_coords.y[1] - node_coords.y[0],
                .bf_z = node_coords.z[1] - node_coords.z[0],
                .cf_x = node_coords.y[3] - node_coords.y[0],
                .cf_z = node_coords.z[3] - node_coords.z[0],
                .df_x = node_coords.y[0],
                .df_z = node_coords.z[0],
            };

            switch (@TypeOf(shader)) {
                *const FlatShader => shadeFlat(
                    frame_ind,
                    actual_fields,
                    fields_num,
                    overlap,
                    tile,
                    sub_samp,
                    sub_pixel_tile_size,
                    sub_pixel_step,
                    x_off,
                    y_off,
                    solver_k,
                    node_coords,
                    shader,
                    sub_pixel_inv_z_scratch,
                    &sub_pixel_image_scratch,
                ),
                *const TexShader => shadeTex(
                    overlap,
                    tile,
                    sub_samp,
                    sub_pixel_tile_size,
                    sub_pixel_step,
                    x_off,
                    y_off,
                    solver_k,
                    node_coords,
                    shader,
                    sub_pixel_inv_z_scratch,
                    &sub_pixel_image_scratch,
                ),
                else => unreachable,
            }
        }
        rops.averageScratch(
            tile,
            tile_size,
            @intCast(camera.pixels_num[0]),
            @intCast(camera.pixels_num[1]),
            sub_samp,
            sub_pixel_tile_size,
            fields_num,
            &sub_pixel_image_scratch,
            sub_pixel_field_avg,
            image_out_arr,
        );
    }
}
