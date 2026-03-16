const std = @import("std");
const Camera = @import("camera.zig").Camera;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ElemBBox = rops.ElemBBox;
const OverlapBBox = rops.OverlapBBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const perf = @import("perf.zig");
const Report = perf.Report;
const Timestamp = std.Io.Clock.Timestamp;

const spec = @import("specraster.zig");
const mr = @import("meshraster.zig");
const MeshTransform = mr.MeshTransform;
const MeshType = mr.MeshType;
const Shader = mr.Shader;
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");

pub fn rasterScene(
    comptime report: Report,
    perf_ctx: perf.PerfContext(report),
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_ind: usize,
    tile_size: u16,
    active_tiles: []const ActiveTile,
    overlap_mms: []const OverlapBBox,
    meshes: []const MeshTransform,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {

    @setFloatMode(.optimized);

    const fields_num = image_out_arr.dims[0];
    
    const sub_samp: usize = @intCast(camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(tile_size)) * sub_samp;
    const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;

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

    for (active_tiles) |tile| {
        const tile_start = if (comptime report == .perf) Timestamp.now(io, .awake) else {};
        var shaded_px: u64 = 0;

        @memset(subpx_inv_z_scratch, 0.0);
        @memset(subpx_image_scratch.elems, 0.0);

        const overlaps = overlap_mms[tile.overlap_start .. 
                                     tile.overlap_start + tile.overlap_count];

        for (overlaps) |ov| {
            const mesh = &meshes[ov.mesh_idx];

            const rhull = if (ov.mesh_idx < raster_hulls.len) 
                raster_hulls[ov.mesh_idx] else null;
            const rhull_ptr = if (rhull) |*h| h else null;
            
            switch (mesh.mesh_type) {
                inline else => |mesh_tag| {
                    const GK = comptime switch (mesh_tag) {
                        .tri3 => geomkerns.Tri3Kernel(),
                        .tri3opt => geomkerns.Tri3OptKernel(),
                        .tri6 => geomkerns.Tri6Kernel(),
                        .quad4ibi => geomkerns.Quad4IBIKernel(),
                        .quad4newton => geomkerns.Quad4NewtonKernel(),
                        .quad8 => geomkerns.Quad89Kernel(8),
                        .quad9 => geomkerns.Quad89Kernel(9),
                    };
                    const N = GK.nodes_num;

                    switch (mesh.shader) {
                        .flat => |*shader| {
                            const SK = shadekerns.FlatKernel(N);
                            shaded_px += try RasterPass(GK, SK, FlatShader).render(
                                report, perf_ctx, camera, frame_ind, ov.elem_idx, tile_size,
                                tile, ov, &mesh.coords, shader, rhull_ptr,
                                subpx_inv_z_scratch, &subpx_image_scratch
                            );
                        },
                        .tex_u8 => |*shader| {
                            switch (shader.interp_type) {
                                inline else => |itp_type| {
                                    const SK = shadekerns.TexKernel(N, u8, itp_type);
                                    shaded_px += try RasterPass(GK, SK, TexShader(u8)).render(
                                        report, perf_ctx, camera, frame_ind, ov.elem_idx,
                                        tile_size, tile, ov, &mesh.coords, shader, rhull_ptr,
                                        subpx_inv_z_scratch, &subpx_image_scratch
                                    );
                                }
                            }
                        },
                        .tex_u16 => |*shader| {
                            switch (shader.interp_type) {
                                inline else => |itp_type| {
                                    const SK = shadekerns.TexKernel(N, u16, itp_type);
                                    shaded_px += try RasterPass(GK, SK, TexShader(u16)).render(
                                        report, perf_ctx, camera, frame_ind, ov.elem_idx,
                                        tile_size, tile, ov, &mesh.coords, shader, rhull_ptr,
                                        subpx_inv_z_scratch, &subpx_image_scratch,
                                    );
                                }
                            }
                        },
                    }
                }
            }
        }

        rops.averageScratch(
            tile,
            @intCast(sub_samp),
            subpx_tile_size,
            fields_num,
            &subpx_image_scratch,
            subpx_field_avg,
            image_out_arr,
        );

        if (comptime report == .perf) {
            const tile_end = Timestamp.now(io, .awake);
            const dur = tile_start.durationTo(tile_end).raw.nanoseconds;
            const screen_px_x = @as(u16, @intCast(camera.pixels_num[0])); 
            const tiles_x = (screen_px_x + tile_size - 1) / tile_size;
            const spatial_idx = (tile.y_px_min / tile_size) * tiles_x 
                                + (tile.x_px_min / tile_size);
            perf_ctx.recordTile(spatial_idx, @intCast(dur), shaded_px, overlaps.len);
        }
    }
}

pub fn RasterPass(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    return struct {
        pub fn render(
            comptime report: Report,
            perf_ctx: perf.PerfContext(report),
            camera: *const Camera,
            frame_ind: usize,
            elem_ind: usize,
            tile_size: u16,
            tile: ActiveTile,
            overlap: OverlapBBox,
            elem_coord_arr: *const NDArray(f64),
            shader: *const ShaderData,
            raster_hull: ?*const NDArray(f64),
            subpx_inv_z_scratch: []f64,
            subpx_image_scratch: *MatSlice(f64),
        ) !u64 {
            const fields_num = subpx_image_scratch.cols_num;

            const sub_samp: usize = @intCast(camera.sub_sample);
            const subpx_tile_size = @as(usize, @intCast(tile_size)) * sub_samp;

            const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
            const subpx_step: f64 = 1.0 / sub_samp_f;
            const subpx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

            const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
            const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

            const nodes = try rops.loadVec3SlicesFromElemArray(
                Geometry.nodes_num,
                f64,
                elem_coord_arr,
                overlap.elem_idx,
            );

            const scratch_start_x = sub_samp * (@as(usize, overlap.bbox.x_min) - tile.x_px_min);
            const scratch_end_x = sub_samp * (@as(usize, overlap.bbox.x_max) - tile.x_px_min);
            const scratch_start_y = sub_samp * (@as(usize, overlap.bbox.y_min) - tile.y_px_min);
            const scratch_end_y = sub_samp * (@as(usize, overlap.bbox.y_max) - tile.y_px_min);

            const xi_min_f: f64 = @as(f64, @floatFromInt(overlap.bbox.x_min));
            const yi_min_f: f64 = @as(f64, @floatFromInt(overlap.bbox.y_min));

            if (Geometry.strategy == .incremental) {
                return try rasterIncremental(
                    report, perf_ctx, frame_ind, elem_ind, fields_num, fields_num,
                    sub_samp, tile.x_px_min, tile.y_px_min, subpx_tile_size, subpx_step,
                    subpx_offset, scratch_start_x, scratch_end_x, scratch_start_y,
                    scratch_end_y, xi_min_f, yi_min_f, nodes, shader, subpx_inv_z_scratch,
                    subpx_image_scratch,
                );
            } else {
                return try rasterPointwise(
                    report, perf_ctx, frame_ind, elem_ind, fields_num, fields_num,
                    sub_samp, tile.x_px_min, tile.y_px_min, subpx_tile_size, subpx_step, 
                    subpx_offset, x_off, y_off, scratch_start_x, scratch_end_x, 
                    scratch_start_y, scratch_end_y, xi_min_f, yi_min_f, nodes, shader, 
                    raster_hull, subpx_inv_z_scratch, subpx_image_scratch,
                );
            }
        }

        fn rasterIncremental(
            comptime report: Report,
            perf_ctx: perf.PerfContext(report),
            frame_index: usize,
            elem_ind: usize,
            actual_fields: usize,
            fields_num: usize,
            sub_samp: usize,
            tile_x_px_min: usize,
            tile_y_px_min: usize,
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

                        if (inv_z >= subpx_inv_z_scratch[index]) {
                            subpx_inv_z_scratch[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report == .perf) {
                                const global_subx = tile_x_px_min * sub_samp + scratch_x;
                                const global_suby = tile_y_px_min * sub_samp + scratch_y;
                                perf_ctx.recordPixel(global_subx, global_suby, 0);
                                perf_ctx.recordPixelOccupancy(
                                    tile_x_px_min + scratch_x / sub_samp,
                                    tile_y_px_min + scratch_y / sub_samp,
                                );
                            }

                            ShaderKernel.shade(
                                Geometry.coord_space, frame_index, elem_ind, 
                                actual_fields, fields_num, weights, nodes_inv_z, subpx_z,
                                shader, index, subpx_image_scratch, perf_ctx, 
                                tile_x_px_min * sub_samp + scratch_x,
                                tile_y_px_min * sub_samp + scratch_y,
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
            elem_ind: usize,
            actual_fields: usize,
            fields_num: usize,
            sub_samp: usize,
            tile_x_px_min: usize,
            tile_y_px_min: usize,
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
            raster_hull: ?*const NDArray(f64),
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

            const NT = if (N == 4) 2 else if (N == 6) 6 else 8;
            var element_tess: hull.Tessellation(NT) = undefined;

            if (comptime Geometry.has_hull) {
                if (raster_hull) |rh| {
                    const hx = rh.getSlice(&[_]usize{ elem_ind, 0, 0 }, 1);
                    const hy = rh.getSlice(&[_]usize{ elem_ind, 1, 0 }, 1);
                    element_tess = hull.getTessellation(N, hx, hy);
                }
            }

            var subpx_y: f64 = yi_min_f + subpx_offset;
            for (scratch_start_y..scratch_end_y) |scratch_y| {
                const row_offset = scratch_y * subpx_tile_size;
                var subpx_x: f64 = xi_min_f + subpx_offset;

                for (scratch_start_x..scratch_end_x) |scratch_x| {
                    const global_subx = tile_x_px_min * sub_samp + scratch_x;
                    const global_suby = tile_y_px_min * sub_samp + scratch_y;

                    if (comptime Geometry.has_hull) {
                        const in_tess = element_tess.isIn(subpx_x, subpx_y);
                        if (comptime report == .perf) {
                            perf_ctx.recordEarlyOut(global_subx, global_suby, in_tess);
                        }
                        if (!in_tess) {
                            subpx_x += subpx_step;
                            continue;
                        }
                    } else if (comptime report == .perf) {
                        perf_ctx.recordEarlyOut(global_subx, global_suby, true);
                    }

                    const result = Geometry.solveWeights(
                        nodes, subpx_x, subpx_y, x_offset, y_offset, geometry_state,
                    );

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inv_z >= subpx_inv_z_scratch[index]) {
                            subpx_inv_z_scratch[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report == .perf) {
                                perf_ctx.recordPixel(global_subx, global_suby, result.iters);
                                perf_ctx.recordPixelOccupancy(
                                    tile_x_px_min + scratch_x / sub_samp,
                                    tile_y_px_min + scratch_y / sub_samp,
                                );
                            }

                            ShaderKernel.shade(
                                Geometry.coord_space, frame_index, elem_ind, 
                                actual_fields, fields_num, weights, nodes_inv_z, subpx_z,
                                shader, index, subpx_image_scratch, perf_ctx, global_subx,
                                global_suby,
                            );
                        }
                    } else if (comptime report == .perf) {
                        if (result.iters > 0) perf_ctx.recordSolverDiverged();
                    }
                    subpx_x += subpx_step;
                }
                subpx_y += subpx_step;
            }
            return shaded_px;
        }
    };
}
