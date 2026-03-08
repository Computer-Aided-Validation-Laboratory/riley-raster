const std = @import("std");
const print = std.debug.print;

const Camera = @import("camera.zig").Camera;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const ti = @import("textureinterp.zig");
const mr = @import("meshraster.zig");
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;

inline fn fillFlat(
    comptime N: usize,
    comptime F: usize,
    weights: [N]f64,
    field_div_z: [F][N]f64,
    spx_z: f64,
    scratch_flat_ind: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    for (0..F) |ff| {
        var field_at_spx: f64 = 0.0;
        for (0..N) |nn| {
            field_at_spx += weights[nn] * field_div_z[ff][nn];
        }
        field_at_spx *= spx_z;
        spx_image_scratch.set(scratch_flat_ind, ff, field_at_spx);
    }
}

inline fn fillTex(
    comptime N: usize,
    comptime interp_type: ti.InterpType,
    weights: [N]f64,
    uv_div_z: [2][N]f64,
    spx_z: f64,
    shader: *const TexShader,
    scratch_flat_ind: usize,
    spx_image_scratch: *MatSlice(f64),
) void {
    var u_at_spx: f64 = 0.0;
    inline for (0..N) |nn| {
        u_at_spx += weights[nn] * uv_div_z[0][nn];
    }

    var v_at_spx: f64 = 0.0;
    inline for (0..N) |nn| {
        v_at_spx += weights[nn] * uv_div_z[1][nn];
    }

    u_at_spx *= spx_z;
    v_at_spx *= spx_z;

    const tex_at_spx = ti.sampleGreyscale(
        interp_type,
        shader.texture,
        u_at_spx,
        v_at_spx,
    );

    spx_image_scratch.set(scratch_flat_ind, 0, tex_at_spx);
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

    const N: usize = 3;
    const tol_edge: f64 = 1e-9;

    const fields_num: usize = switch (@TypeOf(shader)) {
        *const FlatShader => shader.field.dims[2],
        *const TexShader => 1,
        else => @compileError("Unsupported shader type"),
    };

    const screen_px_x = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16, @intCast(camera.pixels_num[1]));

    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = tile_size * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;

    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    const spx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_total);
    defer allocator.free(spx_inv_z_scratch);

    const spx_img_mem = try allocator.alloc(f64, spx_tile_total * fields_num);
    defer allocator.free(spx_img_mem);
    var spx_image_scratch = MatSlice(f64).init(spx_img_mem, spx_tile_total, fields_num);

    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        const overlaps = overlap_bboxes[tile.overlap_start .. 
                                        tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        var nodes_weight: [N]f64 = undefined;

        for (overlaps) |ol| {
            const nr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                elem_coord_arr,
                ol.elem_ind,
            );

            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nr.z[nn];
            }

            const inv_elem_area: f64 = 1.0 / rops.edgeFun3(
                nr.x[0], nr.y[0],
                nr.x[1], nr.y[1],
                nr.x[2], nr.y[2],
            );

            const scratch_start_x: usize = sub_samp * (@as(usize, ol.x_min) - tile.x_px_min);
            const scratch_end_x: usize = sub_samp * (@as(usize, ol.x_max) - tile.x_px_min);
            const scratch_start_y: usize = sub_samp * (@as(usize, ol.y_min) - tile.y_px_min);
            const scratch_end_y: usize = sub_samp * (@as(usize, ol.y_max) - tile.y_px_min);

            const xi_min_f: f64 = @as(f64, @floatFromInt(ol.x_min));
            const yi_min_f: f64 = @as(f64, @floatFromInt(ol.y_min));

            var spx_coord_y: f64 = yi_min_f + spx_offset;

            switch (@TypeOf(shader)) {
                *const FlatShader => {
                    const F = 3; // Fixed for FlatShader in tri3
                    const e_stride = shader.field.strides[1];
                    const f_stride = shader.field.strides[2];
                    const f_off = frame_ind * shader.field.strides[0] + ol.elem_ind * e_stride;

                    var field_div_z: [F][N]f64 = undefined;
                    inline for (0..F) |ff| {
                        const ff_off = f_off + ff * f_stride;
                        inline for (0..N) |nn| {
                            field_div_z[ff][nn] = shader.field.elems[ff_off + nn] * 
                                                  nodes_inv_z[nn];
                        }
                    }

                    for (scratch_start_y..scratch_end_y) |yy| {
                        const row_off: usize = yy * spx_tile_size;
                        var spx_coord_x: f64 = xi_min_f + spx_offset;

                        for (scratch_start_x..scratch_end_x) |xx| {
                            nodes_weight[0] = rops.edgeFun3(nr.x[1], nr.y[1], nr.x[2], 
                                                            nr.y[2], spx_coord_x, spx_coord_y);
                            nodes_weight[1] = rops.edgeFun3(nr.x[2], nr.y[2], nr.x[0], 
                                                            nr.y[0], spx_coord_x, spx_coord_y);
                            nodes_weight[2] = rops.edgeFun3(nr.x[0], nr.y[0], nr.x[1], 
                                                            nr.y[1], spx_coord_x, spx_coord_y);

                            inline for (0..N) |nn| nodes_weight[nn] *= inv_elem_area;

                            if (nodes_weight[0] >= -tol_edge and
                                nodes_weight[1] >= -tol_edge and
                                nodes_weight[2] >= -tol_edge)
                            {
                                var spx_inv_z: f64 = 0.0;
                                for (0..N) |nn| spx_inv_z += nodes_weight[nn] * nodes_inv_z[nn];

                                const idx = row_off + xx;
                                if (spx_inv_z > spx_inv_z_scratch[idx]) {
                                    spx_inv_z_scratch[idx] = spx_inv_z;
                                    const spx_z: f64 = 1.0 / spx_inv_z;
                                    fillFlat(N, F, nodes_weight, field_div_z, spx_z, idx, 
                                             &spx_image_scratch);
                                }
                            }
                            spx_coord_x += spx_step;
                        }
                        spx_coord_y += spx_step;
                    }
                },
                *const TexShader => {
                    const U = 2;
                    const e_stride = shader.uvs.strides[0];
                    const c_stride = shader.uvs.strides[1];
                    const uv_off = ol.elem_ind * e_stride;

                    var uv_div_z: [U][N]f64 = undefined;
                    inline for (0..U) |uu| {
                        const c_off = uv_off + uu * c_stride;
                        inline for (0..N) |nn| {
                            uv_div_z[uu][nn] = shader.uvs.elems[c_off + nn] * nodes_inv_z[nn];
                        }
                    }

                    for (scratch_start_y..scratch_end_y) |yy| {
                        const row_off: usize = yy * spx_tile_size;
                        var spx_coord_x: f64 = xi_min_f + spx_offset;

                        for (scratch_start_x..scratch_end_x) |xx| {
                            nodes_weight[0] = rops.edgeFun3(nr.x[1], nr.y[1], nr.x[2], 
                                                            nr.y[2], spx_coord_x, spx_coord_y);
                            nodes_weight[1] = rops.edgeFun3(nr.x[2], nr.y[2], nr.x[0], 
                                                            nr.y[0], spx_coord_x, spx_coord_y);
                            nodes_weight[2] = rops.edgeFun3(nr.x[0], nr.y[0], nr.x[1], 
                                                            nr.y[1], spx_coord_x, spx_coord_y);

                            inline for (0..N) |nn| nodes_weight[nn] *= inv_elem_area;

                            if (nodes_weight[0] >= -tol_edge and
                                nodes_weight[1] >= -tol_edge and
                                nodes_weight[2] >= -tol_edge)
                            {
                                var spx_inv_z: f64 = 0.0;
                                for (0..N) |nn| spx_inv_z += nodes_weight[nn] * nodes_inv_z[nn];

                                const idx = row_off + xx;
                                if (spx_inv_z > spx_inv_z_scratch[idx]) {
                                    spx_inv_z_scratch[idx] = spx_inv_z;
                                    const spx_z: f64 = 1.0 / spx_inv_z;
                                    switch (shader.interp_type) {
                                        inline else => |it| fillTex(N, it, nodes_weight, 
                                                                    uv_div_z, spx_z, shader, 
                                                                    idx, &spx_image_scratch),
                                    }
                                }
                            }
                            spx_coord_x += spx_step;
                        }
                        spx_coord_y += spx_step;
                    }
                },
                else => unreachable,
            }
        }

        rops.averageScratch(
            tile, tile_size, screen_px_x, screen_px_y, sub_samp, spx_tile_size, fields_num, 
            &spx_image_scratch, spx_field_avg, image_out_arr,
        );
    }
}
