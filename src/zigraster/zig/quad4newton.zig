const std = @import("std");

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const ti = @import("textureinterp.zig");
const shaderops = @import("shaderops.zig");
const FlatShader = shaderops.FlatShader;
const TexShader = shaderops.TexShader;

const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");

const N: usize = 4;

fn shapeFunctions4(u: f64, v: f64, n_v: *[N]f64, dNu: *[N]f64, dNv: *[N]f64) void {
    shapefun.shapeFunctions(N, u, v, n_v, dNu, dNv);
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
    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const row_off = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;
        const tys = sub_pixel_y - y_off;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            const txs = sub_pixel_x - x_off;

            var u: f64 = 0.0;
            var v: f64 = 0.0;
            if (newton.solveInverse(
                N,
                txs,
                tys,
                node_coords.x,
                node_coords.y,
                node_coords.z,
                u,
                v,
                &u,
                &v,
            )) {
                var node_weights: [N]f64 = undefined;
                var dNu: [N]f64 = undefined;
                var dNv: [N]f64 = undefined;
                shapeFunctions4(u, v, &node_weights, &dNu, &dNv);

                var sub_pixel_inv_z: f64 = 0.0;
                inline for (0..N) |i| {
                    sub_pixel_inv_z += node_weights[i] * node_coords.z[i];
                }
                const inv_z = 1.0 / sub_pixel_inv_z;
                const idx = row_off + xx;

                if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                    sub_pixel_inv_z_scratch[idx] = inv_z;
                    shaderops.fillFlat(
                        N,
                        frame_ind,
                        overlap.elem_ind,
                        actual_fields,
                        fields_num,
                        node_weights,
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
    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);
    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);

    for (scratch_start_y..scratch_end_y) |yy| {
        const row_off = yy * sub_pixel_tile_size;
        const sub_pixel_y = @as(f64, @floatFromInt(tile.y_px_min)) +
            (@as(f64, @floatFromInt(yy)) + 0.5) * sub_pixel_step;
        const tys = sub_pixel_y - y_off;

        for (scratch_start_x..scratch_end_x) |xx| {
            const sub_pixel_x = @as(f64, @floatFromInt(tile.x_px_min)) +
                (@as(f64, @floatFromInt(xx)) + 0.5) * sub_pixel_step;
            const txs = sub_pixel_x - x_off;

            var u: f64 = 0.0;
            var v: f64 = 0.0;
            if (newton.solveInverse(
                N,
                txs,
                tys,
                node_coords.x,
                node_coords.y,
                node_coords.z,
                u,
                v,
                &u,
                &v,
            )) {
                var node_weights: [N]f64 = undefined;
                var dNu: [N]f64 = undefined;
                var dNv: [N]f64 = undefined;
                shapeFunctions4(u, v, &node_weights, &dNu, &dNv);

                var sub_pixel_inv_z: f64 = 0.0;
                inline for (0..N) |i| {
                    sub_pixel_inv_z += node_weights[i] * node_coords.z[i];
                }
                const inv_z = 1.0 / sub_pixel_inv_z;
                const idx = row_off + xx;

                if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                    sub_pixel_inv_z_scratch[idx] = inv_z;
                    switch (tex_shader.interp_type) {
                        inline else => |it| shaderops.fillTex(
                            N,
                            it,
                            overlap.elem_ind,
                            node_weights,
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
