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
const shader = @import("shader.zig");
const FlatShader = shader.FlatShader;
const TexShader = shader.TexShader;

fn shadeFlat(
    comptime N: usize,
    frame_ind: usize,
    actual_fields: usize,
    fields_num: usize,
    ol: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    spx_step: f64,
    spx_offset: f64,
    nodes_inv_z: [N]f64,
    inv_elem_area: f64,
    nr: Vec3OfSlices(f64),
    sh: *const FlatShader,
    spx_inv_z_scratch: []f64,
    spx_image_scratch: *MatSlice(f64),
) void {
    const tol_edge: f64 = 1e-9;

    const s_sx: usize = sub_samp * (@as(usize, ol.x_min) - tile.x_px_min);
    const s_ex: usize = sub_samp * (@as(usize, ol.x_max) - tile.x_px_min);
    const s_sy: usize = sub_samp * (@as(usize, ol.y_min) - tile.y_px_min);
    const s_ey: usize = sub_samp * (@as(usize, ol.y_max) - tile.y_px_min);

    const xi_min_f: f64 = @as(f64, @floatFromInt(ol.x_min));
    const yi_min_f: f64 = @as(f64, @floatFromInt(ol.y_min));

    var spx_coord_y: f64 = yi_min_f + spx_offset;

    for (s_sy..s_ey) |yy| {
        const row_off: usize = yy * spx_tile_size;
        var spx_coord_x: f64 = xi_min_f + spx_offset;

        for (s_sx..s_ex) |xx| {
            var w: [N]f64 = undefined;
            w[0] = rops.edgeFun3(nr.x[1], nr.y[1], nr.x[2], nr.y[2], spx_coord_x, spx_coord_y);
            w[1] = rops.edgeFun3(nr.x[2], nr.y[2], nr.x[0], nr.y[0], spx_coord_x, spx_coord_y);
            w[2] = rops.edgeFun3(nr.x[0], nr.y[0], nr.x[1], nr.y[1], spx_coord_x, spx_coord_y);

            inline for (0..N) |nn| w[nn] *= inv_elem_area;

            if (w[0] >= -tol_edge and w[1] >= -tol_edge and w[2] >= -tol_edge) {
                var spx_inv_z: f64 = 0.0;
                for (0..N) |nn| spx_inv_z += w[nn] * nodes_inv_z[nn];

                const idx = row_off + xx;
                if (spx_inv_z > spx_inv_z_scratch[idx]) {
                    spx_inv_z_scratch[idx] = spx_inv_z;
                    shader.fillFlatPerspective(N, frame_ind, ol.elem_ind, actual_fields, 
                                               fields_num, w, nodes_inv_z, 
                                               1.0 / spx_inv_z, sh, idx, 
                                               spx_image_scratch);
                }
            }
            spx_coord_x += spx_step;
        }
        spx_coord_y += spx_step;
    }
}

fn shadeTex(
    comptime N: usize,
    ol: BBox,
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    spx_step: f64,
    spx_offset: f64,
    nodes_inv_z: [N]f64,
    inv_elem_area: f64,
    nr: Vec3OfSlices(f64),
    sh: *const TexShader,
    spx_inv_z_scratch: []f64,
    spx_image_scratch: *MatSlice(f64),
) void {
    const tol_edge: f64 = 1e-9;

    const s_sx: usize = sub_samp * (@as(usize, ol.x_min) - tile.x_px_min);
    const s_ex: usize = sub_samp * (@as(usize, ol.x_max) - tile.x_px_min);
    const s_sy: usize = sub_samp * (@as(usize, ol.y_min) - tile.y_px_min);
    const s_ey: usize = sub_samp * (@as(usize, ol.y_max) - tile.y_px_min);

    const xi_min_f: f64 = @as(f64, @floatFromInt(ol.x_min));
    const yi_min_f: f64 = @as(f64, @floatFromInt(ol.y_min));

    var spx_coord_y: f64 = yi_min_f + spx_offset;

    for (s_sy..s_ey) |yy| {
        const row_off: usize = yy * spx_tile_size;
        var spx_coord_x: f64 = xi_min_f + spx_offset;

        for (s_sx..s_ex) |xx| {
            var w: [N]f64 = undefined;
            w[0] = rops.edgeFun3(nr.x[1], nr.y[1], nr.x[2], nr.y[2], spx_coord_x, spx_coord_y);
            w[1] = rops.edgeFun3(nr.x[2], nr.y[2], nr.x[0], nr.y[0], spx_coord_x, spx_coord_y);
            w[2] = rops.edgeFun3(nr.x[0], nr.y[0], nr.x[1], nr.y[1], spx_coord_x, spx_coord_y);

            inline for (0..N) |nn| w[nn] *= inv_elem_area;

            if (w[0] >= -tol_edge and w[1] >= -tol_edge and w[2] >= -tol_edge) {
                var spx_inv_z: f64 = 0.0;
                for (0..N) |nn| spx_inv_z += w[nn] * nodes_inv_z[nn];

                const idx = row_off + xx;
                if (spx_inv_z > spx_inv_z_scratch[idx]) {
                    spx_inv_z_scratch[idx] = spx_inv_z;
                    switch (sh.interp_type) {
                        inline else => |it| shader.fillTexPerspective(N, it, 
                                                ol.elem_ind, w, nodes_inv_z, 
                                                1.0 / spx_inv_z, sh, idx, 
                                                spx_image_scratch),
                    }
                }
            }
            spx_coord_x += spx_step;
        }
        spx_coord_y += spx_step;
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

    const N: usize = 3;

    const fields_num: usize = switch (@TypeOf(sh)) {
        *const FlatShader => sh.field.dims[2],
        *const TexShader => 1,
        else => @compileError("Unsupported shader type"),
    };
    const actual_fields = if (@TypeOf(sh) == *const FlatShader) 
        @min(fields_num, 3) else 1;

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

        for (overlaps) |ol| {
            const nr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N, f64, elem_coord_arr, ol.elem_ind,
            );

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| nodes_inv_z[nn] = 1.0 / nr.z[nn];

            const inv_elem_area: f64 = 1.0 / rops.edgeFun3(
                nr.x[0], nr.y[0], nr.x[1], nr.y[1], nr.x[2], nr.y[2],
            );

            switch (@TypeOf(sh)) {
                *const FlatShader => shadeFlat(N, frame_ind, actual_fields, fields_num, 
                    ol, tile, sub_samp, spx_tile_size, spx_step, spx_offset, nodes_inv_z, 
                    inv_elem_area, nr, sh, spx_inv_z_scratch, &spx_image_scratch),
                *const TexShader => shadeTex(N, ol, tile, sub_samp, spx_tile_size, 
                    spx_step, spx_offset, nodes_inv_z, inv_elem_area, nr, sh, 
                    spx_inv_z_scratch, &spx_image_scratch),
                else => unreachable,
            }
        }

        rops.averageScratch(tile, tile_size, screen_px_x, screen_px_y, sub_samp, 
                            spx_tile_size, fields_num, &spx_image_scratch, 
                            spx_field_avg, image_out_arr);
    }
}
