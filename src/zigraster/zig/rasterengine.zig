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

            const N = Geometry.node_n;
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
                    
                    var nodes_inv_z: [N]f64 = undefined;
                    inline for (0..N) |nn| {
                        nodes_inv_z[nn] = 1.0 / nodes.z[nn];
                    }

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

                    // Use specialized loop for Tri3Opt
                    if (comptime std.mem.indexOf(u8, @typeName(Geometry), "Tri3Opt") != null) {
                        const inv_area = 1.0 / rops.edgeFun3(
                            nodes.x[0], nodes.y[0],
                            nodes.x[1], nodes.y[1],
                            nodes.x[2], nodes.y[2],
                        );
                        const dw_dx = Geometry.getDWeightsDx(nodes, inv_area, sub_pixel_step);
                        const dw_dy = Geometry.getDWeightsDy(nodes, inv_area, sub_pixel_step);
                        const start_x = xi_min_f + sub_pixel_offset;
                        const start_y = yi_min_f + sub_pixel_offset;
                        var weights_row = Geometry.getWeightsAt(nodes, start_x, 
                                                                start_y, inv_area);

                        var sy = scratch_start_y;
                        while (sy < scratch_end_y) : (sy += 1) {
                            const row_off = sy * sub_pixel_tile_size;
                            var weights = weights_row;

                            var sx = scratch_start_x;
                            while (sx < scratch_end_x) : (sx += 1) {
                                if (Geometry.isInElement(weights)) {
                                    const inv_z = Geometry.calcInvZ(nodes, weights);
                                    const idx = row_off + sx;

                                    if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                                        sub_pixel_inv_z_scratch[idx] = inv_z;
                                        const sub_pixel_z = 1.0 / inv_z;

                                        ShaderKernel.shade(
                                            Geometry.is_parent_space,
                                            frame_ind,
                                            overlap.elem_ind,
                                            actual_fields,
                                            fields_num,
                                            weights,
                                            nodes_inv_z,
                                            sub_pixel_z,
                                            shader,
                                            idx,
                                            &sub_pixel_image_scratch,
                                        );
                                    }
                                }
                                inline for (0..N) |nn| weights[nn] += dw_dx[nn];
                            }
                            inline for (0..N) |nn| weights_row[nn] += dw_dy[nn];
                        }
                    } else {
                        // Pointwise loop for all other kernels
                        const geom_state = if (@hasDecl(Geometry, "getInvElemArea"))
                            Geometry.getInvElemArea(nodes)
                        else if (@hasDecl(Geometry, "getSolverParams"))
                            Geometry.getSolverParams(nodes)
                        else
                            {};

                        var py: f64 = yi_min_f + sub_pixel_offset;
                        var sy = scratch_start_y;
                        while (sy < scratch_end_y) : (sy += 1) {
                            const row_off = sy * sub_pixel_tile_size;
                            var px: f64 = xi_min_f + sub_pixel_offset;

                            var sx = scratch_start_x;
                            while (sx < scratch_end_x) : (sx += 1) {
                                const maybe_weights = Geometry.solveWeights(
                                    nodes, px, py, x_off, y_off, geom_state
                                );

                                if (maybe_weights) |weights| {
                                    const inv_z = Geometry.calcInvZ(nodes, weights);
                                    const idx = row_off + sx;

                                    if (inv_z > sub_pixel_inv_z_scratch[idx]) {
                                        sub_pixel_inv_z_scratch[idx] = inv_z;
                                        const sub_pixel_z = 1.0 / inv_z;

                                        ShaderKernel.shade(
                                            Geometry.is_parent_space,
                                            frame_ind,
                                            overlap.elem_ind,
                                            actual_fields,
                                            fields_num,
                                            weights,
                                            nodes_inv_z,
                                            sub_pixel_z,
                                            shader,
                                            idx,
                                            &sub_pixel_image_scratch,
                                        );
                                    }
                                }
                                px += sub_pixel_step;
                            }
                            py += sub_pixel_step;
                        }
                    }
                }

                rops.averageScratch(
                    tile, tile_size, screen_px_x, screen_px_y, sub_samp, 
                    sub_pixel_tile_size, fields_num, &sub_pixel_image_scratch, 
                    sub_pixel_field_avg, image_out_arr
                );
            }
        }
    };
}
