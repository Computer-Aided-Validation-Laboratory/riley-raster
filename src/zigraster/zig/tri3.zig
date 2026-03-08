const std = @import("std");

const Camera = @import("camera.zig").Camera;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const shaderops = @import("shaderops.zig");
const FlatShader = shaderops.FlatShader;
const TexShader = shaderops.TexShader;

const N: usize = 3;

fn shadeFlat(
    frame_ind: usize,
    actual_fields: usize,
    fields_num: usize,
    overlap: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    sub_pixel_tile_size: usize,
    sub_pixel_step: f64,
    sub_pixel_offset: f64,
    nodes_inv_z: [N]f64,
    inv_elem_area: f64,
    node_coords: Vec3OfSlices(f64),
    flat_shader: *const FlatShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const tol_edge: f64 = 1e-9;

    const scratch_start_x: usize = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x: usize = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
    const scratch_start_y: usize = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y: usize = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

    const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
    const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));

    var sub_pixel_coord_y: f64 = yi_min_f + sub_pixel_offset;

    for (scratch_start_y..scratch_end_y) |yy| {
        const scratch_row_offset: usize = yy * sub_pixel_tile_size;
        var sub_pixel_coord_x: f64 = xi_min_f + sub_pixel_offset;

        for (scratch_start_x..scratch_end_x) |xx| {
            var node_weights: [N]f64 = undefined;
            node_weights[0] = rops.edgeFun3(
                node_coords.x[1], node_coords.y[1],
                node_coords.x[2], node_coords.y[2],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );
            node_weights[1] = rops.edgeFun3(
                node_coords.x[2], node_coords.y[2],
                node_coords.x[0], node_coords.y[0],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );
            node_weights[2] = rops.edgeFun3(
                node_coords.x[0], node_coords.y[0],
                node_coords.x[1], node_coords.y[1],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );

            inline for (0..N) |nn| {
                node_weights[nn] *= inv_elem_area;
            }

            if (node_weights[0] >= -tol_edge and
                node_weights[1] >= -tol_edge and
                node_weights[2] >= -tol_edge)
            {
                var sub_pixel_inv_z: f64 = 0.0;
                inline for (0..N) |nn| {
                    sub_pixel_inv_z += node_weights[nn] * nodes_inv_z[nn];
                }

                const scratch_flat_ind = scratch_row_offset + xx;
                if (sub_pixel_inv_z > sub_pixel_inv_z_scratch[scratch_flat_ind]) {
                    sub_pixel_inv_z_scratch[scratch_flat_ind] = sub_pixel_inv_z;
                    const sub_pixel_z: f64 = 1.0 / sub_pixel_inv_z;

                    shaderops.fillFlatPerspective(
                        N,
                        frame_ind,
                        overlap.elem_ind,
                        actual_fields,
                        fields_num,
                        node_weights,
                        nodes_inv_z,
                        sub_pixel_z,
                        flat_shader,
                        scratch_flat_ind,
                        sub_pixel_image_scratch,
                    );
                }
            }
            sub_pixel_coord_x += sub_pixel_step;
        }
        sub_pixel_coord_y += sub_pixel_step;
    }
}

fn shadeTex(
    overlap: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    sub_pixel_tile_size: usize,
    sub_pixel_step: f64,
    sub_pixel_offset: f64,
    nodes_inv_z: [N]f64,
    inv_elem_area: f64,
    node_coords: Vec3OfSlices(f64),
    tex_shader: *const TexShader,
    sub_pixel_inv_z_scratch: []f64,
    sub_pixel_image_scratch: *MatSlice(f64),
) void {
    const tol_edge: f64 = 1e-9;

    const scratch_start_x: usize = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
    const scratch_end_x: usize = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
    const scratch_start_y: usize = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
    const scratch_end_y: usize = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

    const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
    const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));

    var sub_pixel_coord_y: f64 = yi_min_f + sub_pixel_offset;

    for (scratch_start_y..scratch_end_y) |yy| {
        const scratch_row_offset: usize = yy * sub_pixel_tile_size;
        var sub_pixel_coord_x: f64 = xi_min_f + sub_pixel_offset;

        for (scratch_start_x..scratch_end_x) |xx| {
            var node_weights: [N]f64 = undefined;
            node_weights[0] = rops.edgeFun3(
                node_coords.x[1], node_coords.y[1],
                node_coords.x[2], node_coords.y[2],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );
            node_weights[1] = rops.edgeFun3(
                node_coords.x[2], node_coords.y[2],
                node_coords.x[0], node_coords.y[0],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );
            node_weights[2] = rops.edgeFun3(
                node_coords.x[0], node_coords.y[0],
                node_coords.x[1], node_coords.y[1],
                sub_pixel_coord_x, sub_pixel_coord_y,
            );

            inline for (0..N) |nn| {
                node_weights[nn] *= inv_elem_area;
            }

            if (node_weights[0] >= -tol_edge and
                node_weights[1] >= -tol_edge and
                node_weights[2] >= -tol_edge)
            {
                var sub_pixel_inv_z: f64 = 0.0;
                inline for (0..N) |nn| {
                    sub_pixel_inv_z += node_weights[nn] * nodes_inv_z[nn];
                }

                const scratch_flat_ind = scratch_row_offset + xx;
                if (sub_pixel_inv_z > sub_pixel_inv_z_scratch[scratch_flat_ind]) {
                    sub_pixel_inv_z_scratch[scratch_flat_ind] = sub_pixel_inv_z;
                    const sub_pixel_z: f64 = 1.0 / sub_pixel_inv_z;
                    switch (tex_shader.interp_type) {
                        inline else => |it| shaderops.fillTexPerspective(
                            N,
                            it,
                            overlap.elem_ind,
                            node_weights,
                            nodes_inv_z,
                            sub_pixel_z,
                            tex_shader,
                            scratch_flat_ind,
                            sub_pixel_image_scratch,
                        ),
                    }
                }
            }
            sub_pixel_coord_x += sub_pixel_step;
        }
        sub_pixel_coord_y += sub_pixel_step;
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

    const screen_px_x = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16, @intCast(camera.pixels_num[1]));

    const sub_samp: usize = @intCast(camera.sub_sample);
    const sub_pixel_tile_size: usize = tile_size * sub_samp;
    const sub_pixel_tile_total: usize = sub_pixel_tile_size * sub_pixel_tile_size;

    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const sub_pixel_step: f64 = 1.0 / sub_samp_f;
    const sub_pixel_offset: f64 = 1.0 / (2.0 * sub_samp_f);

    const sub_pixel_inv_z_scratch = try allocator.alloc(f64, sub_pixel_tile_total);
    defer allocator.free(sub_pixel_inv_z_scratch);

    const sub_pixel_img_mem = try allocator.alloc(f64, sub_pixel_tile_total * fields_num);
    defer allocator.free(sub_pixel_img_mem);
    var sub_pixel_image_scratch = MatSlice(f64).init(
        sub_pixel_img_mem,
        sub_pixel_tile_total,
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
            const node_coords: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                elem_coord_arr,
                overlap.elem_ind,
            );

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / node_coords.z[nn];
            }

            const inv_elem_area: f64 = 1.0 / rops.edgeFun3(
                node_coords.x[0], node_coords.y[0],
                node_coords.x[1], node_coords.y[1],
                node_coords.x[2], node_coords.y[2],
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
                    sub_pixel_offset,
                    nodes_inv_z,
                    inv_elem_area,
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
                    sub_pixel_offset,
                    nodes_inv_z,
                    inv_elem_area,
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
            screen_px_x,
            screen_px_y,
            sub_samp,
            sub_pixel_tile_size,
            fields_num,
            &sub_pixel_image_scratch,
            sub_pixel_field_avg,
            image_out_arr,
        );
    }
}
