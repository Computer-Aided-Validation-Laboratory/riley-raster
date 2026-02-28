const std = @import("std");
const Camera = @import("../src/zigraster/zig/camera.zig").Camera;
const NDArray = @import("../src/zigraster/zig/ndarray.zig").NDArray;
const MatSlice = @import("../src/zigraster/zig/matslice.zig").MatSlice;

const BBox = struct {
    elem_ind: usize,
    x_min: u16,
    x_max: u16,
    y_min: u16,
    y_max: u16,
};

const ActiveTile = struct {
    overlap_start: usize,
    overlap_count: usize,
    x_px_min: u16,
    y_px_min: u16,
};

pub fn Vec3OfSlices(comptime T: type) type {
    return struct {
        x: []T,
        y: []T,
        z: []T,
    };
}

pub fn loadVec3SlicesFromElemArray(
    comptime N: usize,
    comptime T: type,
    elem_array: *const NDArray(T),
    elem_ind: usize,
) !Vec3OfSlices(T) {
    var start_slice: usize = elem_array.getFlatInd(&[_]usize{ elem_ind, 0, 0 });
    const stride: usize = elem_array.strides[1];

    const x_slice = elem_array.elems[start_slice .. start_slice + N];
    start_slice += stride;
    const y_slice = elem_array.elems[start_slice .. start_slice + N];
    start_slice += stride;
    const z_slice = elem_array.elems[start_slice .. start_slice + N];

    return Vec3OfSlices(T){
        .x = x_slice,
        .y = y_slice,
        .z = z_slice,
    };
}

pub inline fn edgeFun3(x0: f64, y0: f64, x1: f64, y1: f64, x2: f64, y2: f64) f64 {
    return ((x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0));
}

pub fn rasterTilesLinTriV0(
    comptime N: usize,
    arena_alloc: std.mem.Allocator,
    camera: *const Camera,
    tile_size: u16,
    fields_num: usize,
    active_tiles: []const ActiveTile,
    overlap_bboxes: []const BBox,
    elem_coord_arr: *const NDArray(f64),
    elem_field_arr: *const NDArray(f64),
    screen_px_x: u16,
    screen_px_y: u16,
    image_out_arr: *NDArray(f64),
) !void {
    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = @as(usize, tile_size) * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;

    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    const spx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

    const spx_inv_z_scratch = try arena_alloc.alloc(f64, spx_tile_total);

    const spx_image_scratch_mem = try arena_alloc.alloc(f64, spx_tile_total * fields_num);
    var spx_image_scratch = MatSlice(f64).init(
        spx_image_scratch_mem,
        spx_tile_total,
        fields_num,
    );

    const spx_field_avg = try arena_alloc.alloc(f64, fields_num);

    // TODO: Thread this for large images and large meshes, each active tile is independent
    // TODO: Implement non-linear elements   
    // NOTE: this loop only works for linear triangles! It uses barycentric interpolation
    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        const overlaps: []const BBox = overlap_bboxes[tile.overlap_start .. tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        var nodes_weight: [N]f64 = undefined;

        for (overlaps) |overlap| {
            const nodes_rast: Vec3OfSlices(f64) = try loadVec3SlicesFromElemArray(
                N,
                f64,
                elem_coord_arr,
                overlap.elem_ind,
            );

            for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            }

            const inv_elem_area: f64 = 1.0 / edgeFun3(
                nodes_rast.x[0],
                nodes_rast.y[0],
                nodes_rast.x[1],
                nodes_rast.y[1],
                nodes_rast.x[2],
                nodes_rast.y[2],
            );

            const scratch_start_ind_x: usize = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);
            const scratch_end_ind_x: usize = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
            const scratch_start_ind_y: usize = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);
            const scratch_end_ind_y: usize = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

            const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
            const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));

            var spx_coord_x: f64 = xi_min_f + spx_offset;
            var spx_coord_y: f64 = yi_min_f + spx_offset;

            //--------------------------------------------------------------------------------
            // RASTER HOT LOOP
            for (scratch_start_ind_y..scratch_end_ind_y) |yy| {
                const scratch_row_offset: usize = yy * spx_tile_size;
                spx_coord_x = xi_min_f + spx_offset;

                for (scratch_start_ind_x..scratch_end_ind_x) |xx| {
                    // NOTE: not a weight until mult by inv area! Only used for edge check
                    nodes_weight[0] = edgeFun3(
                        nodes_rast.x[1],
                        nodes_rast.y[1],
                        nodes_rast.x[2],
                        nodes_rast.y[2],
                        spx_coord_x,
                        spx_coord_y,
                    );
                    nodes_weight[1] = edgeFun3(
                        nodes_rast.x[2],
                        nodes_rast.y[2],
                        nodes_rast.x[0],
                        nodes_rast.y[0],
                        spx_coord_x,
                        spx_coord_y,
                    );
                    nodes_weight[2] = edgeFun3(
                        nodes_rast.x[0],
                        nodes_rast.y[0],
                        nodes_rast.x[1],
                        nodes_rast.y[1],
                        spx_coord_x,
                        spx_coord_y,
                    );

                    const scratch_flat_ind: usize = scratch_row_offset + xx;

                    if (nodes_weight[0] >= 0.0 and
                        nodes_weight[1] >= 0.0 and
                        nodes_weight[2] >= 0.0)
                    {

                        // NOTE: now it is a weight
                        for (0..N) |nn| {
                            nodes_weight[nn] = nodes_weight[nn] * inv_elem_area;
                        }

                        // Perspective correct interpolation to get the inverse of the z
                        // (weights) dot (nodes_inv_z) 
                        var spx_inv_z: f64 = 0.0;
                        for (0..N) |nn| {
                            spx_inv_z += nodes_weight[nn] * nodes_inv_z[nn];
                        }

                        // INV DEPTH CHECK: 
                        // 1/large number = far away = approach 0, far away = LESS THAN
                        // 1/small number = closer = approach inf, close = GREATER THAN
                        if (spx_inv_z > spx_inv_z_scratch[scratch_flat_ind]) {
                            spx_inv_z_scratch[scratch_flat_ind] = spx_inv_z;

                            // CALC: for each field, subpx value based on node values and 
                            // weights:
                            // spx_field = (vec(nodes_field[nn] * nodes_inv_z[nn]) 
                            //             dot vec(nodes_weights)) * spx_z_coord
                            const spx_z: f64 = 1.0 / spx_inv_z;
                            for (0..fields_num) |ff| {
                                var field_at_spx: f64 = 0.0;
                                for (0..N) |nn| {
                                    const elem_field_inds = [_]usize{ overlap.elem_ind, ff, nn };
                                    // CALC:(nodes_field[nn]) * (nodes_inv_z[nn])
                                    const field_at_node_div_z = elem_field_arr.get(
                                        elem_field_inds[0..],
                                    ) * nodes_inv_z[nn];

                                    // CALC: (node_weights) dot (nodes_field_div_z)
                                    field_at_spx += nodes_weight[nn] * field_at_node_div_z;
                                }

                                // CALC: ((node_weights) dot (nodes_field_div_z)) * subpx_z
                                field_at_spx *= spx_z;

                                spx_image_scratch.set(scratch_flat_ind, ff, field_at_spx);
                            }
                        }
                    }
                    spx_coord_x += spx_step;
                } // LOOP subpx x            
                spx_coord_y += spx_step;
            } // LOOP subpx y    
        } // LOOP overlapping elems / boxes

        // Average scratch and push into main image buffer
        const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
        const curr_tile_size_x = @min(@as(u16, tile_size), screen_px_x - tile.x_px_min);
        const curr_tile_size_y = @min(@as(u16, tile_size), screen_px_y - tile.y_px_min);

        for (0..curr_tile_size_y) |ty| {
            const image_px_y: usize = tile.y_px_min + ty;
            const spx_start_y: usize = sub_samp * ty;

            for (0..curr_tile_size_x) |tx| {
                const image_px_x: usize = tile.x_px_min + tx;
                const spx_start_x: usize = sub_samp * tx;

                @memset(spx_field_avg, 0.0);

                for (0..sub_samp) |sy| { // Index into scratch
                    const scratch_row_offset: usize = (spx_start_y + sy)
                        * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_ind: usize = scratch_row_offset + spx_start_x + sx;

                        for (0..fields_num) |ff| {
                            spx_field_avg[ff] += spx_image_scratch.get(scratch_flat_ind, ff);
                        }
                    } // AVG LOOP: sub samp x
                } // AVG LOOP: sub samp y

                for (0..fields_num) |ff| {
                    const image_inds = [_]usize{ ff, image_px_y, image_px_x };
                    const image_val: f64 = spx_field_avg[ff] * inv_sub_samp_sq;

                    image_out_arr.set(image_inds[0..], image_val);
                }
            } // AVG LOOP: tile x
        } // AVG LOOP: tile y        
    } // LOOP active tiles   
}
