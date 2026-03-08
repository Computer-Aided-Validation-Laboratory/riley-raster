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

const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");

const N: usize = 6;

fn shapeFunctions(u: f64, v: f64, n_v: *[N]f64, dNu: *[N]f64, dNv: *[N]f64) void {
    shapefun.shapeFunctions(N, u, v, n_v, dNu, dNv);
}

fn getTessellatedGuess(
    txs: f64,
    tys: f64,
    ex: []const f64,
    ey: []const f64,
    ew: []const f64,
    xi_out: *f64,
    eta_out: *f64,
) bool {
    const tol_area: f64 = 1e-12;
    const eps = 1e-5;

    const SubTri = struct {
        n0: u8,
        n1: u8,
        n2: u8,
        xi0: f64,
        eta0: f64,
        xi1: f64,
        eta1: f64,
        xi2: f64,
        eta2: f64,
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
        const x0 = ex[st.n0] / ew[st.n0];
        const y0 = ey[st.n0] / ew[st.n0];
        const x1 = ex[st.n1] / ew[st.n1];
        const y1 = ey[st.n1] / ew[st.n1];
        const x2 = ex[st.n2] / ew[st.n2];
        const y2 = ey[st.n2] / ew[st.n2];

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
    node_coords: Vec3OfSlices(f64),
    flat_shader: *const FlatShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const row_off = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            var converged = false;

            if (getTessellatedGuess(
                sub_pixel_x - x_off,
                sub_pixel_y - y_off,
                node_coords.x,
                node_coords.y,
                node_coords.z,
                &xi,
                &eta,
            )) {
                converged = newton.solveInverse(
                    N,
                    sub_pixel_x - x_off,
                    sub_pixel_y - y_off,
                    node_coords.x,
                    node_coords.y,
                    node_coords.z,
                    xi,
                    eta,
                    &xi,
                    &eta,
                );
            }

            if (!converged) {
                converged = newton.solveInverse(
                    N,
                    sub_pixel_x - x_off,
                    sub_pixel_y - y_off,
                    node_coords.x,
                    node_coords.y,
                    node_coords.z,
                    1.0 / 3.0,
                    1.0 / 3.0,
                    &xi,
                    &eta,
                );
            }

            if (converged) {
                var n_vals: [N]f64 = undefined;
                var dN_dxi: [N]f64 = undefined;
                var dN_deta: [N]f64 = undefined;
                shapeFunctions(xi, eta, &n_vals, &dN_dxi, &dN_deta);

                var sw: f64 = 0.0;
                inline for (0..N) |i| {
                    sw += n_vals[i] * node_coords.z[i];
                }
                const inv_z = 1.0 / sw;

                const idx = row_off + xx;
                if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                    sub_pixel_inv_z_scratch[idx] = inv_z;
                    shaderops.fillFlat(
                        N,
                        frame_ind,
                        overlap.elem_ind,
                        actual_fields,
                        fields_num,
                        n_vals,
                        flat_shader,
                        idx,
                        sub_pixel_image_scratch,
                    );
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
    node_coords: Vec3OfSlices(f64),
    tex_shader: *const TexShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const row_off = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            var converged = false;

            if (getTessellatedGuess(
                sub_pixel_x - x_off,
                sub_pixel_y - y_off,
                node_coords.x,
                node_coords.y,
                node_coords.z,
                &xi,
                &eta,
            )) {
                converged = newton.solveInverse(
                    N,
                    sub_pixel_x - x_off,
                    sub_pixel_y - y_off,
                    node_coords.x,
                    node_coords.y,
                    node_coords.z,
                    xi,
                    eta,
                    &xi,
                    &eta,
                );
            }

            if (!converged) {
                converged = newton.solveInverse(
                    N,
                    sub_pixel_x - x_off,
                    sub_pixel_y - y_off,
                    node_coords.x,
                    node_coords.y,
                    node_coords.z,
                    1.0 / 3.0,
                    1.0 / 3.0,
                    &xi,
                    &eta,
                );
            }

            if (converged) {
                var n_vals: [N]f64 = undefined;
                var dN_dxi: [N]f64 = undefined;
                var dN_deta: [N]f64 = undefined;
                shapeFunctions(xi, eta, &n_vals, &dN_dxi, &dN_deta);

                var sw: f64 = 0.0;
                inline for (0..N) |i| {
                    sw += n_vals[i] * node_coords.z[i];
                }
                const inv_z = 1.0 / sw;

                const idx = row_off + xx;
                if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                    sub_pixel_inv_z_scratch[idx] = inv_z;
                    switch (tex_shader.interp_type) {
                        inline else => |it| shaderops.fillTex(
                            N,
                            it,
                            overlap.elem_ind,
                            n_vals,
                            tex_shader,
                            idx,
                            sub_pixel_image_scratch,
                        ),
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

    const sub_samp: usize = @intCast(camera.sub_sample);
    const sub_pixel_tile_size = tile_size * sub_samp;
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const sub_pixel_step: f64 = 1.0 / sub_samp_f;
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    const sub_pixel_inv_z_scratch = try allocator.alloc(
        f64, sub_pixel_tile_size * sub_pixel_tile_size
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

        const overlaps = overlap_bboxes[tile.overlap_start .. 
                                        tile.overlap_start + tile.overlap_count];

        for (overlaps) |overlap| {
            const node_coords = try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                elem_coord_arr,
                overlap.elem_ind,
            );

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
