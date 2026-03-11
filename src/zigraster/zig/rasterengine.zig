const std = @import("std");
const Camera = @import("camera.zig").Camera;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const perf = @import("perf.zig");
const Report = perf.Report;
const Timestamp = std.Io.Clock.Timestamp;

pub fn RasterEngine(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    return struct {
        pub fn raster(
            comptime report: Report,
            perf_ctx: perf.PerfContext(report),
            allocator: std.mem.Allocator,
            io: std.Io,
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
            const subpx_tile_size: usize = tile_size * sub_samp;
            const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;

            const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
            const subpx_step: f64 = 1.0 / sub_samp_f;
            const subpx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

            const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
            const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

            const subpx_inv_z_scratch = try allocator.alloc(f64, subpx_tile_total);
            defer allocator.free(subpx_inv_z_scratch);

            const subpx_img_mem = try allocator.alloc(f64, subpx_tile_total * fields_num);
            defer allocator.free(subpx_img_mem);
            var subpx_image_scratch = MatSlice(f64).init(
                subpx_img_mem,
                subpx_tile_total,
                fields_num,
            );

            const subpx_field_avg = try allocator.alloc(f64, fields_num);
            defer allocator.free(subpx_field_avg);

            for (active_tiles, 0..) |tile, tile_idx| {
                const tile_start = if (comptime report == .perf)
                    Timestamp.now(io, .awake)
                else
                    {};
                var shaded_px: u64 = 0;

                @memset(subpx_inv_z_scratch, 0.0);
                @memset(subpx_image_scratch.elems, 0.0);

                const overlaps = overlap_bboxes[tile.overlap_start .. 
                                                tile.overlap_start + tile.overlap_count];

                for (overlaps) |overlap| {
                    const nodes = try rops.loadVec3SlicesFromElemArray(
                        Geometry.nodes_num,
                        f64,
                        elem_coord_arr,
                        overlap.elem_ind,
                    );

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
                                shaded_px += try rasterIncremental(
                                    report,
                                    perf_ctx,
                                    frame_ind,
                                    overlap.elem_ind,
                                    actual_fields,
                                    fields_num,
                                    subpx_tile_size,
                                    subpx_step,
                                    subpx_offset,
                                    scratch_start_x,
                                    scratch_end_x,
                                    scratch_start_y,
                                    scratch_end_y,
                                    xi_min_f,
                                    yi_min_f,
                                    nodes,
                                    shader,
                                    subpx_inv_z_scratch,
                                    &subpx_image_scratch,
                                );
                            } else {
                                shaded_px += try rasterPointwise(
                                    report,
                                    perf_ctx,
                                    frame_ind,
                                    overlap.elem_ind,
                                    actual_fields,
                                    fields_num,
                                    subpx_tile_size,
                                    subpx_step,
                                    subpx_offset,
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
                                    subpx_inv_z_scratch,
                                    &subpx_image_scratch,
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
                    subpx_tile_size,
                    fields_num,
                    &subpx_image_scratch,
                    subpx_field_avg,
                    image_out_arr,
                );

                if (comptime report == .perf) {
                    const tile_end = Timestamp.now(io, .awake);
                    const dur = tile_start.durationTo(tile_end).raw.nanoseconds;
                    perf_ctx.recordTile(tile_idx, @intCast(dur), shaded_px, overlaps.len);
                }
            }
        }

        fn rasterIncremental(
            comptime report: Report,
            perf_ctx: perf.PerfContext(report),
            frame_index: usize,
            element_index: usize,
            actual_fields: usize,
            fields_num: usize,
            subpx_tile_size: usize,
            subpx_step: f64,
            subpx_offset: f64,
            scratch_start_x: usize,
            scratch_end_x: usize,
            scratch_start_y: usize,
            scratch_end_y: usize,
            xi_min_f: f64,
            yi_min_f: f64,
            nodes: Vec3OfSlices(f64),
            shader: *const ShaderData,
            subpx_inv_z_scratch: []f64,
            subpx_image_scratch: *MatSlice(f64),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_index| {
                nodes_inv_z[node_index] = 1.0 / nodes.z[node_index];
            }

            const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                                 nodes.x[1], nodes.y[1],
                                                 nodes.x[2], nodes.y[2]);
            
            const dweights_dx = Geometry.getDWeightsDx(nodes, inv_area, subpx_step);
            const dweights_dy = Geometry.getDWeightsDy(nodes, inv_area, subpx_step);

            const start_x = xi_min_f + subpx_offset;
            const start_y = yi_min_f + subpx_offset;
            var weights_row = Geometry.getWeightsAt(nodes, start_x, start_y, inv_area);

            for (scratch_start_y..scratch_end_y) |scratch_y| {
                const row_offset = scratch_y * subpx_tile_size;
                var weights = weights_row;

                for (scratch_start_x..scratch_end_x) |scratch_x| {
                    if (Geometry.isInElement(weights)) {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (comptime report == .perf) {
                            perf_ctx.recordDepthTest(inv_z <= subpx_inv_z_scratch[index]);
                        }

                        if (inv_z > subpx_inv_z_scratch[index]) {
                            subpx_inv_z_scratch[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                frame_index,
                                element_index,
                                actual_fields,
                                fields_num,
                                weights,
                                nodes_inv_z,
                                subpx_z,
                                shader,
                                index,
                                subpx_image_scratch,
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
            return shaded_px;
        }

        fn rasterPointwise(
            comptime report: Report,
            perf_ctx: perf.PerfContext(report),
            frame_index: usize,
            element_index: usize,
            actual_fields: usize,
            fields_num: usize,
            subpx_tile_size: usize,
            subpx_step: f64,
            subpx_offset: f64,
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
            subpx_inv_z_scratch: []f64,
            subpx_image_scratch: *MatSlice(f64),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes.z[nn];
            }

            const geometry_state = if (@hasDecl(Geometry, "getInvElemArea"))
                Geometry.getInvElemArea(nodes)
            else if (@hasDecl(Geometry, "getBilinearParams"))
                Geometry.getBilinearParams(nodes)
            else
                {};

            var subpx_y: f64 = yi_min_f + subpx_offset;
            for (scratch_start_y..scratch_end_y) |scratch_y| {
                const row_offset = scratch_y * subpx_tile_size;
                var subpx_x: f64 = xi_min_f + subpx_offset;

                for (scratch_start_x..scratch_end_x) |scratch_x| {
                    const result = Geometry.solveWeights(
                        nodes,
                        subpx_x,
                        subpx_y,
                        x_offset,
                        y_offset,
                        geometry_state,
                    );

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (comptime report == .perf) {
                            perf_ctx.recordDepthTest(inv_z <= subpx_inv_z_scratch[index]);
                        }

                        if (inv_z > subpx_inv_z_scratch[index]) {
                            subpx_inv_z_scratch[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report == .perf) {
                                perf_ctx.recordPixel(
                                    @intFromFloat(subpx_x),
                                    @intFromFloat(subpx_y),
                                    result.iters,
                                );
                            }

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                frame_index,
                                element_index,
                                actual_fields,
                                fields_num,
                                weights,
                                nodes_inv_z,
                                subpx_z,
                                shader,
                                index,
                                subpx_image_scratch,
                            );
                        }
                    } else {
                        if (result.iters > 0) {
                            if (comptime report == .perf) {
                                perf_ctx.recordSolverDiverged();
                            }
                        }
                    }
                    subpx_x += subpx_step;
                }
                subpx_y += subpx_step;
            }
            return shaded_px;
        }
    };
}
