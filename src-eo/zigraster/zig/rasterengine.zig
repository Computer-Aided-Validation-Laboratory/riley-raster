const std = @import("std");
const Camera = @import("camera.zig").Camera;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const OverlapBBox = rops.OverlapBBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;
const perf = @import("perf.zig");
const Report = perf.Report;
const Timestamp = std.Io.Clock.Timestamp;

const spec = @import("zraster.zig");
const mr = @import("meshraster.zig");
const MeshTransform = mr.MeshTransform;
const MeshType = mr.MeshType;
const Shader = mr.Shader;
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const feat = @import("featureconfig.zig").FeatureConfig;

const ScratchBuffers = struct {
    inv_z: []f64,
    image: *MatSlice(f64),
};

const SubpxDomain = struct {
    step: f64,
    offset: f64,
    tile_size: usize,
    x_off: f64,
    y_off: f64,
};

const RasterBounds = struct {
    start_x: usize,
    end_x: usize,
    start_y: usize,
    end_y: usize,
    x_min_f: f64,
    y_min_f: f64,
};

pub fn rasterScene(
    comptime report: Report,
    ctx_rast: rops.RasterContext(report),
    allocator: std.mem.Allocator,
    io: std.Io,
    tiling: rops.TilingOverlaps,
    meshes: []const MeshTransform,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {

    @setFloatMode(.optimized);

    const fields_num = image_out_arr.dims[0];
    
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
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
    const scratch = ScratchBuffers{
        .inv_z = subpx_inv_z_scratch,
        .image = &subpx_image_scratch,
    };

    const subpx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(subpx_field_avg);

    for (tiling.active_tiles) |tile| {
        const tile_start = if (comptime report == .perf) Timestamp.now(io, .awake) else {};
        var shaded_px: u64 = 0;

        @memset(subpx_inv_z_scratch, 0.0);
        @memset(subpx_image_scratch.elems, 0.0);

        const overlaps = tiling.overlaps[tile.overlap_start .. 
                                         tile.overlap_start + tile.overlap_count];

        for (overlaps) |ov| {
            const mesh = &meshes[ov.mesh_idx];

            const target = rops.OverlapTarget{ .tile = tile, .overlap = ov };

            const rhull_ptr = if (ov.mesh_idx < raster_hulls.len) 
                raster_hulls[ov.mesh_idx] else null;

            const input = rops.MeshInput{ 
                .coords = &mesh.coords, 
                .hull = if (rhull_ptr) |*h| h else null,
            };
            
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
                                report, ctx_rast, target, input, mesh, shader, scratch,
                            );
                        },
                        .tex_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 1);
                            shaded_px += try RasterPass(GK, SK, TexShader(u8, 1)).render(
                                report, ctx_rast, target, input, mesh, shader, scratch,
                            );
                        },
                        .tex_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 1);
                            shaded_px += try RasterPass(GK, SK, TexShader(u16, 1)).render(
                                report, ctx_rast, target, input, mesh, shader, scratch,
                            );
                        },
                        .tex_rgb_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 3);
                            shaded_px += try RasterPass(GK, SK, TexShader(u8, 3)).render(
                                report, ctx_rast, target, input, mesh, shader, scratch,
                            );
                        },
                        .tex_rgb_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 3);
                            shaded_px += try RasterPass(GK, SK, TexShader(u16, 3)).render(
                                report, ctx_rast, target, input, mesh, shader, scratch,
                            );
                        },
                    }
                }
            }
        }

        averageScratch(
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
            const screen_px_x = @as(u16, @intCast(ctx_rast.camera.pixels_num[0])); 
            const tiles_x = (screen_px_x + ctx_rast.tile_size - 1) / ctx_rast.tile_size;
            const spatial_idx = (tile.y_px_min / ctx_rast.tile_size) * tiles_x 
                                + (tile.x_px_min / ctx_rast.tile_size);
            ctx_rast.ctx_perf.recordTile(spatial_idx, @intCast(dur), shaded_px, overlaps.len);
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
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            input: rops.MeshInput,
            mesh: *const MeshTransform,
            shader: *const ShaderData,
            scratch: ScratchBuffers,
        ) !u64 {
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const subpx_tile_size = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;

            const sub_samp_f: f64 = @as(f64, @floatFromInt(ctx_rast.camera.sub_sample));
            const subpx_step: f64 = 1.0 / sub_samp_f;
            const subpx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

            const x_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[0]));
            const y_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[1]));

            const nodes = try rops.loadVec3SlicesFromElemArray(
                Geometry.nodes_num,
                f64,
                input.coords,
                target.overlap.elem_idx,
            );

            const scratch_start_x = sub_samp * (@as(usize, target.overlap.x_min) - 
                                                target.tile.x_px_min);
            const scratch_end_x = sub_samp * (@as(usize, target.overlap.x_max) - 
                                              target.tile.x_px_min);
            const scratch_start_y = sub_samp * (@as(usize, target.overlap.y_min) - 
                                                target.tile.y_px_min);
            const scratch_end_y = sub_samp * (@as(usize, target.overlap.y_max) - 
                                              target.tile.y_px_min);

            const x_min_f: f64 = @as(f64, @floatFromInt(target.overlap.x_min));
            const y_min_f: f64 = @as(f64, @floatFromInt(target.overlap.y_min));

            const domain = SubpxDomain{
                .step = subpx_step,
                .offset = subpx_offset,
                .tile_size = subpx_tile_size,
                .x_off = x_off,
                .y_off = y_off,
            };

            const bounds = RasterBounds{
                .start_x = scratch_start_x,
                .end_x = scratch_end_x,
                .start_y = scratch_start_y,
                .end_y = scratch_end_y,
                .x_min_f = x_min_f,
                .y_min_f = y_min_f,
            };

            const N = Geometry.nodes_num;

            if (comptime feat.tri3_earlyinout and N == 3) {
                const ox_min = @as(f64, @floatFromInt(target.overlap.x_min));
                const ox_max = @as(f64, @floatFromInt(target.overlap.x_max));
                const oy_min = @as(f64, @floatFromInt(target.overlap.y_min));
                const oy_max = @as(f64, @floatFromInt(target.overlap.y_max));

                const corners_x = [4]f64{ ox_min, ox_max, ox_max, ox_min };
                const corners_y = [4]f64{ oy_min, oy_min, oy_max, oy_max };

                var all_in = true;
                var any_out = false;
                const edge_tol: f64 = 1e-9;
                
                // Store results for reuse: corners are [TL, TR, BR, BL]
                var corners_ef: [3][4]f64 = undefined;

                inline for (0..3) |ii| {
                    const ii0 = ii;
                    const ii1 = (ii + 1) % 3;
                    var corners_in_count: usize = 0;
                    
                    inline for (0..4) |jj| {
                        const ef = rops.edgeFun3(nodes.x[ii0], nodes.y[ii0],
                                                 nodes.x[ii1], nodes.y[ii1],
                                                 corners_x[jj], corners_y[jj]);
                        corners_ef[ii][jj] = ef;
                        if (ef >= -edge_tol) {
                            corners_in_count += 1;
                        }
                    }

                    if (corners_in_count == 0) {
                        any_out = true;
                        break;
                    }
                    if (corners_in_count < 4) {
                        all_in = false;
                    }
                }

                if (any_out) return 0;

                if (all_in) {
                    var local_buf = shadekerns.shaderops.LocalNodeBuffer(N){};
                    try loadLocalBuf(N, report, ctx_rast, target, mesh, &local_buf);
                    return try Geometry.fastFill(
                        report, ShaderKernel, ctx_rast, target, domain, 
                        bounds, nodes, shader, scratch, &local_buf,
                    );
                }

                // If partially in and using incremental, we can reuse TL corner [index 0]
                if (Geometry.strategy == .incremental) {
                    var local_buf = shadekerns.shaderops.LocalNodeBuffer(N){};
                    try loadLocalBuf(N, report, ctx_rast, target, mesh, &local_buf);
                    
                    const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                                         nodes.x[1], nodes.y[1],
                                                         nodes.x[2], nodes.y[2]);
                    // Weight 0: edge 1-2 [index 1 in corners_ef]
                    // Weight 1: edge 2-0 [index 2 in corners_ef]
                    // Weight 2: edge 0-1 [index 0 in corners_ef]
                    const tl_weights = [_]f64{
                        corners_ef[1][0] * inv_area,
                        corners_ef[2][0] * inv_area,
                        corners_ef[0][0] * inv_area,
                    };

                    return try rasterIncremental(
                        report, ctx_rast, target, domain, bounds, nodes, shader, scratch, 
                        &local_buf, tl_weights,
                    );
                }
            }

            var local_buf = shadekerns.shaderops.LocalNodeBuffer(N){};
            try loadLocalBuf(N, report, ctx_rast, target, mesh, &local_buf);

            if (Geometry.strategy == .incremental) {
                return try rasterIncremental(
                    report, ctx_rast, target, domain, bounds, nodes, shader, scratch, 
                    &local_buf, null,
                );
            } else {
                return try rasterPointwise(
                    report, ctx_rast, target, input, domain, bounds, nodes, shader, scratch, &local_buf,
                );
            }
        }

        fn loadLocalBuf(
            comptime N: usize,
            comptime rep: Report,
            ctx_rast: rops.RasterContext(rep),
            target: rops.OverlapTarget,
            mesh: *const MeshTransform,
            local_buf: *shadekerns.shaderops.LocalNodeBuffer(N),
        ) !void {
            const fields_num = getFieldsNum(mesh.shader);
            switch (mesh.shader) {
                .flat => |*s| {
                    const f_idx = @min(ctx_rast.frame_ind, s.field.array.dims[0] - 1);
                    const start_idx = s.field.array.getFlatInd(&[_]usize{ 
                        f_idx, target.overlap.elem_idx, 0, 0 
                    });
                    local_buf.load(s.field.array, start_idx, fields_num);
                },
                .tex_u8 => |*s| {
                    const start_idx = s.uvs.getFlatInd(&[_]usize{ 
                        target.overlap.elem_idx, 0, 0 
                    });
                    local_buf.load(s.uvs, start_idx, 2);
                },
                .tex_u16 => |*s| {
                    const start_idx = s.uvs.getFlatInd(&[_]usize{ 
                        target.overlap.elem_idx, 0, 0 
                    });
                    local_buf.load(s.uvs, start_idx, 2);
                },
                .tex_rgb_u8 => |*s| {
                    const start_idx = s.uvs.getFlatInd(&[_]usize{ 
                        target.overlap.elem_idx, 0, 0 
                    });
                    local_buf.load(s.uvs, start_idx, 2);
                },
                .tex_rgb_u16 => |*s| {
                    const start_idx = s.uvs.getFlatInd(&[_]usize{ 
                        target.overlap.elem_idx, 0, 0 
                    });
                    local_buf.load(s.uvs, start_idx, 2);
                },
            }
        }

        fn rasterIncremental(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            domain: SubpxDomain,
            bounds: RasterBounds,
            nodes: Vec3OfSlices(f64),
            shader: *const ShaderData,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
            init_weights: ?[Geometry.nodes_num]f64,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const fields_num = scratch.image.cols_num;

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_index| {
                nodes_inv_z[node_index] = 1.0 / nodes.z[node_index];
            }

            const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                                 nodes.x[1], nodes.y[1],
                                                 nodes.x[2], nodes.y[2]);
            
            const dweights_dx = Geometry.getDWeightsDx(nodes, inv_area, domain.step);
            const dweights_dy = Geometry.getDWeightsDy(nodes, inv_area, domain.step);

            var weights_row = if (init_weights) |iw| iw else blk: {
                const start_x = bounds.x_min_f + domain.offset;
                const start_y = bounds.y_min_f + domain.offset;
                break :blk Geometry.getWeightsAt(nodes, start_x, start_y, inv_area);
            };

            // If we reused weights from corner check, they are at the pixel edge.
            // We need to shift them to the sub-pixel center.
            if (init_weights != null) {
                inline for (0..N) |nn| {
                    weights_row[nn] += dweights_dx[nn] * (domain.offset / domain.step);
                    weights_row[nn] += dweights_dy[nn] * (domain.offset / domain.step);
                }
            }

            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                var weights = weights_row;

                for (bounds.start_x..bounds.end_x) |scratch_x| {
                    if (Geometry.isInElement(weights)) {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[index]) {
                            scratch.inv_z[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            const global_subx = target.tile.x_px_min * sub_samp + 
                                                scratch_x;
                            const global_suby = target.tile.y_px_min * sub_samp + 
                                                scratch_y;

                            if (comptime report == .perf) {
                                ctx_rast.ctx_perf.recordPixel(global_subx, global_suby, 0);
                                ctx_rast.ctx_perf.recordPixelOccupancy(
                                    target.tile.x_px_min + scratch_x / sub_samp,
                                    target.tile.y_px_min + scratch_y / sub_samp,
                                );
                            }

                            if (comptime ShaderKernel == shadekerns.FlatKernel(N)) {
                                ShaderKernel.shade(
                                    Geometry.coord_space,
                                    .{
                                        .frame_index = ctx_rast.frame_ind,
                                        .elem_index = target.overlap.elem_idx,
                                        .fields_num = fields_num,
                                        .actual_fields = fields_num,
                                        .idx = index,
                                        .global_subx = global_subx,
                                        .global_suby = global_suby,
                                        .local_buf = local_buf,
                                    },
                                    .{
                                        .weights = weights,
                                        .nodes_inv_z = nodes_inv_z,
                                        .sub_pixel_z = subpx_z,
                                    },
                                    ctx_rast.ctx_perf,
                                    scratch.image,
                                );
                            } else {
                                ShaderKernel.shade(
                                    Geometry.coord_space,
                                    .{
                                        .frame_index = ctx_rast.frame_ind,
                                        .elem_index = target.overlap.elem_idx,
                                        .fields_num = fields_num,
                                        .actual_fields = fields_num,
                                        .idx = index,
                                        .global_subx = global_subx,
                                        .global_suby = global_suby,
                                        .local_buf = local_buf,
                                    },
                                    .{
                                        .weights = weights,
                                        .nodes_inv_z = nodes_inv_z,
                                        .sub_pixel_z = subpx_z,
                                    },
                                    shader,
                                    ctx_rast.ctx_perf,
                                    scratch.image,
                                );
                            }
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

const CornerCheck = enum {
    all_in,
    all_out,
    partial,
};

        fn rasterPointwise(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            input: rops.MeshInput,
            domain: SubpxDomain,
            bounds: RasterBounds,
            nodes: Vec3OfSlices(f64),
            shader: *const ShaderData,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const fields_num = scratch.image.cols_num;

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

            var corner_state: CornerCheck = .partial;

            if (comptime Geometry.has_hull) {
                if (input.hull) |rh| {
                    const hx = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 0, 0 }, 1);
                    const hy = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 1, 0 }, 1);
                    element_tess = hull.getTessellation(N, hx, hy);

                    const ox_min = @as(f64, @floatFromInt(target.overlap.x_min));
                    const ox_max = @as(f64, @floatFromInt(target.overlap.x_max));
                    const oy_min = @as(f64, @floatFromInt(target.overlap.y_min));
                    const oy_max = @as(f64, @floatFromInt(target.overlap.y_max));

                    const c0 = element_tess.isIn(ox_min, oy_min);
                    const c1 = element_tess.isIn(ox_max, oy_min);
                    const c2 = element_tess.isIn(ox_max, oy_max);
                    const c3 = element_tess.isIn(ox_min, oy_max);

                    if (c0 and c1 and c2 and c3) {
                        corner_state = .all_in;
                    } else {
                        // It is NOT safe to assume all_out if 4 corners are out.
                        // The hull could still cross the box.
                        corner_state = .partial;
                    }
                }
            }

            if (corner_state == .all_out) return 0;

            var subpx_y: f64 = bounds.y_min_f + domain.offset;
            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                var subpx_x: f64 = bounds.x_min_f + domain.offset;

                for (bounds.start_x..bounds.end_x) |scratch_x| {
                    const global_subx = target.tile.x_px_min * sub_samp + scratch_x;
                    const global_suby = target.tile.y_px_min * sub_samp + scratch_y;

                    if (comptime Geometry.has_hull) {
                        const skip_hull = (corner_state == .all_in);
                        const in_tess = if (skip_hull) true else element_tess.isIn(subpx_x, subpx_y);
                        
                        if (comptime report == .perf) {
                            ctx_rast.ctx_perf.recordEarlyOut(global_subx, global_suby, in_tess);
                        }
                        if (!in_tess) {
                            subpx_x += domain.step;
                            continue;
                        }
                    } else if (comptime report == .perf) {
                        ctx_rast.ctx_perf.recordEarlyOut(global_subx, global_suby, true);
                    }

                    const result = Geometry.solveWeights(
                        nodes, subpx_x, subpx_y, domain.x_off, domain.y_off, geometry_state,
                    );

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[index]) {
                            scratch.inv_z[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report == .perf) {
                                ctx_rast.ctx_perf.recordPixel(
                                    global_subx, global_suby, result.iters,
                                );
                                ctx_rast.ctx_perf.recordPixelOccupancy(
                                    target.tile.x_px_min + scratch_x / sub_samp,
                                    target.tile.y_px_min + scratch_y / sub_samp,
                                );
                            }

                            if (comptime ShaderKernel == shadekerns.FlatKernel(N)) {
                                ShaderKernel.shade(
                                    Geometry.coord_space,
                                    .{
                                        .frame_index = ctx_rast.frame_ind,
                                        .elem_index = target.overlap.elem_idx,
                                        .fields_num = fields_num,
                                        .actual_fields = fields_num,
                                        .idx = index,
                                        .global_subx = global_subx,
                                        .global_suby = global_suby,
                                        .local_buf = local_buf,
                                    },
                                    .{
                                        .weights = weights,
                                        .nodes_inv_z = nodes_inv_z,
                                        .sub_pixel_z = subpx_z,
                                    },
                                    ctx_rast.ctx_perf,
                                    scratch.image,
                                );
                            } else {
                                ShaderKernel.shade(
                                    Geometry.coord_space,
                                    .{
                                        .frame_index = ctx_rast.frame_ind,
                                        .elem_index = target.overlap.elem_idx,
                                        .fields_num = fields_num,
                                        .actual_fields = fields_num,
                                        .idx = index,
                                        .global_subx = global_subx,
                                        .global_suby = global_suby,
                                        .local_buf = local_buf,
                                    },
                                    .{
                                        .weights = weights,
                                        .nodes_inv_z = nodes_inv_z,
                                        .sub_pixel_z = subpx_z,
                                    },
                                    shader,
                                    ctx_rast.ctx_perf,
                                    scratch.image,
                                );
                            }
                        }
                    } else if (comptime report == .perf) {
                        if (result.iters > 0) ctx_rast.ctx_perf.recordSolverDiverged();
                    }
                    subpx_x += domain.step;
                }
                subpx_y += domain.step;
            }
            return shaded_px;
        }
    };
}

pub fn getFieldsNum(shader: Shader) usize {
    return switch (shader) {
        .flat => |s| s.field.array.dims[2],
        .tex_u8, .tex_u16 => 1,
        .tex_rgb_u8, .tex_rgb_u16 => 3,
    };
}

pub fn averageScratch(tile: ActiveTile,
                      sub_samp: usize,
                      spx_tile_size: usize,
                      fields_num: usize,
                      spx_image_scratch: *const MatSlice(f64),
                      spx_field_avg: []f64,
                      image_out_arr: *NDArray(f64)) void {

    const curr_tile_size_x = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            @memset(spx_field_avg, 0.0);

            for (0..sub_samp) |sy| {
                const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                for (0..sub_samp) |sx| {
                    const scratch_flat_ind: usize = scratch_row_offset + spx_start_x + sx;

                    for (0..fields_num) |ff| {
                        spx_field_avg[ff] += spx_image_scratch.get(scratch_flat_ind, ff);
                    }
                }
            }

            for (0..fields_num) |ff| {
                const image_inds = [_]usize{ ff, image_px_y, image_px_x };
                const image_val: f64 = spx_field_avg[ff] * inv_sub_samp_sq;
                
                image_out_arr.set(image_inds[0..], image_val);
            }
        }
    }
}
