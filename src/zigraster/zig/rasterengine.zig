const std = @import("std");
const Camera = @import("camera.zig").Camera;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

pub fn RasterEngine(comptime Geometry: type, 
                    comptime ShaderKernel: type, 
                    comptime ShaderData: type) type {
    return struct {
        pub fn raster(
            allocator: std.mem.Allocator,
            camera: *const Camera,
            frame_ind: usize,
            tile_size: u16,
            active_tiles: []ActiveTile,
            overlap_bboxes: []BBox,
            elem_coord_arr: *const NDArray(f64),
            shader: *const ShaderData,
            image_out_arr: *NDArray(f64),
        ) !void {
            @setFloatMode(.optimized);

            const fields_num = image_out_arr.dims[0];
            const actual_fields = if (@hasField(ShaderData, "field")) 
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

            const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
            const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

            const sub_pixel_inv_z_scratch = try allocator.alloc(f64, sub_pixel_tile_total);
            defer allocator.free(sub_pixel_inv_z_scratch);

            const sub_pixel_img_mem = try allocator.alloc(
                f64, sub_pixel_tile_total * fields_num
            );
            defer allocator.free(sub_pixel_img_mem);
            var sub_pixel_image_scratch = MatSlice(f64).init(
                sub_pixel_img_mem, sub_pixel_tile_total, fields_num
            );

            const sub_pixel_field_avg = try allocator.alloc(f64, fields_num);
            defer allocator.free(sub_pixel_field_avg);

            for (active_tiles) |tile| {
                @memset(sub_pixel_inv_z_scratch, 0.0);
                @memset(sub_pixel_image_scratch.elems, 0.0);

                const overlaps = overlap_bboxes[tile.overlap_start .. 
                                                tile.overlap_start + tile.overlap_count];

                for (overlaps) |overlap| {
                    const nodes = try Geometry.loadNodes(elem_coord_arr, overlap.elem_ind);
                    
                    const scratch_start_x = sub_samp * (@as(usize, overlap.x_min) - 
                                                        tile.x_px_min);
                    const scratch_end_x = sub_samp * (@as(usize, overlap.x_max) - 
                                                      tile.x_px_min);
                    const scratch_start_y = sub_samp * (@as(usize, overlap.y_min) - 
                                                        tile.y_px_min);
                    const scratch_end_y = sub_samp * (@as(usize, overlap.y_max) - 
                                                      tile.y_px_min);

                    const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.x_min));
                    const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.y_min));

                    switch (Geometry.strategy) {
                        inline else => |strat| {
                            if (strat == .incremental) {
                                try rasterIncremental(
                                    frame_ind,
                                    overlap.elem_ind,
                                    actual_fields,
                                    fields_num,
                                    sub_pixel_tile_size,
                                    sub_pixel_step,
                                    sub_pixel_offset,
                                    scratch_start_x,
                                    scratch_end_x,
                                    scratch_start_y,
                                    scratch_end_y,
                                    xi_min_f,
                                    yi_min_f,
                                    nodes,
                                    shader,
                                    sub_pixel_inv_z_scratch,
                                    &sub_pixel_image_scratch,
                                );
                            } else {
                                try rasterPointwise(
                                    frame_ind,
                                    overlap.elem_ind,
                                    actual_fields,
                                    fields_num,
                                    sub_pixel_tile_size,
                                    sub_pixel_step,
                                    sub_pixel_offset,
                                    x_off,
                                    y_off,
                                    scratch_start_x,
                                    scratch_end_x,
                                    scratch_start_y,
                                    scratch_end_y,
                                    xi_min_f,
                                    yi_min_f,
                                    nodes,
                                    shader,
                                    sub_pixel_inv_z_scratch,
                                    &sub_pixel_image_scratch,
                                );
                            }
                        },
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

        fn rasterIncremental(
            frame_index: usize,
            element_index: usize,
            actual_fields: usize,
            fields_num: usize,
            sub_pixel_tile_size: usize,
            sub_pixel_step: f64,
            sub_pixel_offset: f64,
            scratch_start_x: usize,
            scratch_end_x: usize,
            scratch_start_y: usize,
            scratch_end_y: usize,
            xi_min_f: f64,
            yi_min_f: f64,
            nodes: Vec3OfSlices(f64),
            shader: *const ShaderData,
            sub_pixel_inv_z_scratch: []f64,
            sub_pixel_image_scratch: *MatSlice(f64),
        ) !void {
            const N = Geometry.node_n;
            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_index| {
                nodes_inv_z[node_index] = 1.0 / nodes.z[node_index];
            }

            const inverse_area = 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
            const dweights_dx = Geometry.getDWeightsDx(nodes, inverse_area, sub_pixel_step);
            const dweights_dy = Geometry.getDWeightsDy(nodes, inverse_area, sub_pixel_step);

            const start_x = xi_min_f + sub_pixel_offset;
            const start_y = yi_min_f + sub_pixel_offset;
            var weights_row = Geometry.getWeightsAt(nodes, start_x, start_y, inverse_area);

            for (scratch_start_y..scratch_end_y) |scratch_y| {
                const row_offset = scratch_y * sub_pixel_tile_size;
                var weights = weights_row;

                for (scratch_start_x..scratch_end_x) |scratch_x| {
                    if (Geometry.isInElement(weights)) {
                        const inverse_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inverse_z > sub_pixel_inv_z_scratch[index]) {
                            sub_pixel_inv_z_scratch[index] = inverse_z;
                            const sub_pixel_z = 1.0 / inverse_z;

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                frame_index,
                                element_index,
                                actual_fields,
                                fields_num,
                                weights,
                                nodes_inv_z,
                                sub_pixel_z,
                                shader,
                                index,
                                sub_pixel_image_scratch,
                            );
                        }
                    }
                    inline for (0..N) |node_index| {
                        weights[node_index] += dweights_dx[node_index];
                    }
                }
                inline for (0..N) |node_index| {
                    weights_row[node_index] += dweights_dy[node_index];
                }
            }
        }

        fn rasterPointwise(
            frame_index: usize,
            element_index: usize,
            actual_fields: usize,
            fields_num: usize,
            sub_pixel_tile_size: usize,
            sub_pixel_step: f64,
            sub_pixel_offset: f64,
            x_offset: f64,
            y_offset: f64,
            scratch_start_x: usize,
            scratch_end_x: usize,
            scratch_start_y: usize,
            scratch_end_y: usize,
            xi_min_f: f64,
            yi_min_f: f64,
            nodes: Vec3OfSlices(f64),
            shader: *const ShaderData,
            sub_pixel_inv_z_scratch: []f64,
            sub_pixel_image_scratch: *MatSlice(f64),
        ) !void {
            const N = Geometry.node_n;
            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_index| {
                nodes_inv_z[node_index] = 1.0 / nodes.z[node_index];
            }

            const geometry_state = if (@hasDecl(Geometry, "getInvElemArea"))
                Geometry.getInvElemArea(nodes)
            else if (@hasDecl(Geometry, "getSolverParams"))
                Geometry.getSolverParams(nodes)
            else
                {};

            var pixel_y: f64 = yi_min_f + sub_pixel_offset;
            for (scratch_start_y..scratch_end_y) |scratch_y| {
                const row_offset = scratch_y * sub_pixel_tile_size;
                var pixel_x: f64 = xi_min_f + sub_pixel_offset;

                for (scratch_start_x..scratch_end_x) |scratch_x| {
                    const maybe_weights = Geometry.solveWeights(
                        nodes,
                        pixel_x,
                        pixel_y,
                        x_offset,
                        y_offset,
                        geometry_state,
                    );

                    if (maybe_weights) |weights| {
                        const inverse_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inverse_z > sub_pixel_inv_z_scratch[index]) {
                            sub_pixel_inv_z_scratch[index] = inverse_z;
                            const sub_pixel_z = 1.0 / inverse_z;

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                frame_index,
                                element_index,
                                actual_fields,
                                fields_num,
                                weights,
                                nodes_inv_z,
                                sub_pixel_z,
                                shader,
                                index,
                                sub_pixel_image_scratch,
                            );
                        }
                    }
                    pixel_x += sub_pixel_step;
                }
                pixel_y += sub_pixel_step;
            }
        }
    };
}
