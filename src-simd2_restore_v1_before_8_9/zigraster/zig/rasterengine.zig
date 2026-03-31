const std = @import("std");
const Camera = @import("camera.zig").Camera;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const shapefun = @import("shapefun.zig");
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
const MeshPrepared = mr.MeshPrepared;
const MeshType = mr.MeshType;
const Shader = mr.Shader;
const FlatPrepared = shadekerns.shaderops.FlatPrepared;
const TexPrepared = shadekerns.shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");

const CandidateBlock = struct {
    scratch_x: [8]usize,
    scratch_y: [8]usize,
    px: [8]f64,
    py: [8]f64,
    guess_xi: [8]f64,
    guess_eta: [8]f64,
    count: usize,
};

pub const ScratchBuffers = struct {
    inv_z: []align(64) f64,
    image: *MatSlice(f64),
    candidate_buffer: []CandidateBlock,
    subpx_mask: []align(64) bool,
    subpx_xi: []align(64) f64,
    subpx_eta: []align(64) f64,
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
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    @setFloatMode(.optimized);

    const fields_num = image_out_arr.dims[0];

    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
    const subpx_tile_total = subpx_tile_size * subpx_tile_size;
    const subpx_tile_total_padded = (subpx_tile_total + 7) & ~@as(usize, 7);

    const alignment = std.mem.Alignment.@"64";
    const subpx_inv_z_scratch = try allocator.alignedAlloc(f64, alignment, subpx_tile_total_padded + 8);
    defer allocator.free(subpx_inv_z_scratch);

    const subpx_mask_scratch = try allocator.alignedAlloc(bool, alignment, subpx_tile_total_padded + 8);
    defer allocator.free(subpx_mask_scratch);

    const subpx_xi_scratch = try allocator.alignedAlloc(f64, alignment, subpx_tile_total_padded + 8);
    defer allocator.free(subpx_xi_scratch);

    const subpx_eta_scratch = try allocator.alignedAlloc(f64, alignment, subpx_tile_total_padded + 8);
    defer allocator.free(subpx_eta_scratch);

    const subpx_img_mem = try allocator.alignedAlloc(f64, alignment, (subpx_tile_total_padded + 8) * fields_num);
    defer allocator.free(subpx_img_mem);
    var subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        fields_num,
        subpx_tile_total_padded + 8,
    );

    const candidate_block_count = @divFloor(subpx_tile_total_padded + 7, 8) + 1;
    const candidate_buffer = try allocator.alloc(CandidateBlock, candidate_block_count);
    defer allocator.free(candidate_buffer);

    const scratch = ScratchBuffers{
        .inv_z = subpx_inv_z_scratch,
        .image = &subpx_image_scratch,
        .candidate_buffer = candidate_buffer,
        .subpx_mask = subpx_mask_scratch,
        .subpx_xi = subpx_xi_scratch,
        .subpx_eta = subpx_eta_scratch,
    };

    const subpx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(subpx_field_avg);

    for (tiling.active_tiles) |tile| {
        const tile_start = Timestamp.now(io, .awake);
        var shaded_px: u64 = 0;

        @memset(subpx_inv_z_scratch, -std.math.inf(f64));
        @memset(subpx_image_scratch.elems, 0.0);

        const overlaps = tiling.overlaps[tile.overlap_start .. tile.overlap_start + tile.overlap_count];

        for (overlaps) |ov| {
            const mesh = &meshes[ov.mesh_idx];

            const target = rops.OverlapTarget{ .tile = tile, .overlap = ov };

            const rhull_ptr = if (ov.mesh_idx < raster_hulls.len)
                raster_hulls[ov.mesh_idx]
            else
                null;

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
                    const mesh_fields = switch (mesh.shader) {
                        .flat, .normals => |s| s.elem_field.dims[2],
                        .tex_u8, .tex_u16 => 1,
                        .tex_rgb_u8, .tex_rgb_u16 => 3,
                    };

                    switch (mesh.shader) {
                        .flat => |*shader| {
                            const SK = shadekerns.FlatKernel(N);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};

                            const tt = @min(ctx_rast.frame_ind, shader.elem_field.dims[0] - 1);
                            const start_idx = shader.elem_field.getFlatInd(&[_]usize{ tt, target.overlap.elem_idx, 0, 0 });

                            local_node_buf.load(
                                shader.elem_field,
                                start_idx,
                                mesh_fields,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, FlatPrepared).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                        .normals => |*shader| {
                            const SK = shadekerns.NormalKernel(N);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};

                            const tt = @min(ctx_rast.frame_ind, shader.elem_field.dims[0] - 1);
                            const start_idx = shader.elem_field.getFlatInd(&[_]usize{ tt, target.overlap.elem_idx, 0, 0 });

                            local_node_buf.load(
                                shader.elem_field,
                                start_idx,
                                mesh_fields,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, FlatPrepared).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                        .tex_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 1);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};
                            local_node_buf.load(
                                shader.elem_uvs,
                                target.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 1)).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                        .tex_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 1);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};
                            local_node_buf.load(
                                shader.elem_uvs,
                                target.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 1)).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                        .tex_rgb_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 3);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};
                            local_node_buf.load(
                                shader.elem_uvs,
                                target.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 3)).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                        .tex_rgb_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 3);
                            var local_node_buf: shadekerns.shaderops.LocalNodeBuffer(N) = .{};
                            local_node_buf.load(
                                shader.elem_uvs,
                                target.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[target.overlap.elem_idx];
                                local_node_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 3)).render(
                                report,
                                ctx_rast,
                                target,
                                input,
                                mesh,
                                shader,
                                scratch,
                                &local_node_buf,
                            );
                        },
                    }
                },
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

        if (comptime report != .off) {
            const tile_end = if (comptime report != .off) Timestamp.now(io, .awake) else {};
            const dur = tile_start.durationTo(tile_end).raw.nanoseconds;
            const screen_px_x = @as(u16, @intCast(ctx_rast.camera.pixels_num[0]));
            const tiles_x = (screen_px_x + ctx_rast.tile_size - 1) / ctx_rast.tile_size;
            const spatial_idx = (tile.y_px_min / ctx_rast.tile_size) * tiles_x + (tile.x_px_min / ctx_rast.tile_size);
            ctx_rast.ctx_perf.recordTile(spatial_idx, @intCast(dur), shaded_px, overlaps.len);
        } else {
            ctx_rast.ctx_perf.recordTile(0, 0, shaded_px, 0);
        }
    }
}

pub fn RasterPass(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    const PreparedShader = switch (ShaderData) {
        shadekerns.shaderops.FlatInput, shadekerns.shaderops.FlatPrepared => shadekerns.shaderops.FlatPrepared,
        shadekerns.shaderops.TexInput(u8, 1), shadekerns.shaderops.TexPrepared(u8, 1) => shadekerns.shaderops.TexPrepared(u8, 1),
        shadekerns.shaderops.TexInput(u16, 1), shadekerns.shaderops.TexPrepared(u16, 1) => shadekerns.shaderops.TexPrepared(u16, 1),
        shadekerns.shaderops.TexInput(u8, 3), shadekerns.shaderops.TexPrepared(u8, 3) => shadekerns.shaderops.TexPrepared(u8, 3),
        shadekerns.shaderops.TexInput(u16, 3), shadekerns.shaderops.TexPrepared(u16, 3) => shadekerns.shaderops.TexPrepared(u16, 3),
        else => ShaderData,
    };

    return struct {
        pub fn render(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            input: rops.MeshInput,
            mesh: *const MeshPrepared,
            shader: *const PreparedShader,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            _ = mesh;
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

            const scratch_start_x = sub_samp * (@as(usize, @intCast(target.overlap.x_min)) -
                target.tile.x_px_min);
            const scratch_end_x = sub_samp * (@as(usize, @intCast(target.overlap.x_max)) -
                target.tile.x_px_min);
            const scratch_start_y = sub_samp * (@as(usize, @intCast(target.overlap.y_min)) -
                target.tile.y_px_min);
            const scratch_end_y = sub_samp * (@as(usize, @intCast(target.overlap.y_max)) -
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

            const shaded_px = if (comptime (Geometry == geomkerns.Tri3Kernel() or
                Geometry == geomkerns.Tri3OptKernel()))
                try rasterSIM(
                    report,
                    ctx_rast,
                    target,
                    domain,
                    bounds,
                    scratch_start_x,
                    nodes,
                    shader,
                    scratch,
                    local_buf,
                )
            else if (Geometry.strategy == .incremental)
                try rasterIncremental(
                    report,
                    ctx_rast,
                    target,
                    domain,
                    bounds,
                    nodes,
                    shader,
                    scratch,
                    local_buf,
                )
            else if (Geometry.strategy == .newton_simd)
                try rasterSIMDNewton(
                    report,
                    ctx_rast,
                    target,
                    &input,
                    domain,
                    bounds,
                    scratch_start_x,
                    nodes,
                    shader,
                    scratch,
                    local_buf,
                )
            else
                try rasterPointwise(
                    report,
                    ctx_rast,
                    target,
                    input,
                    domain,
                    bounds,
                    nodes,
                    shader,
                    scratch,
                    local_buf,
                );

            return shaded_px;
        }

        fn rasterSIM(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            domain: SubpxDomain,
            bounds: RasterBounds,
            original_start_x: usize,
            nodes: Vec3OfSlices(f64),
            shader: anytype,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const fields_num = scratch.image.rows_num;

            const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0], nodes.x[1], nodes.y[1], nodes.x[2], nodes.y[2]);

            const v_nodes_inv_z = Geometry.getSIMDConstants(nodes);
            const v_steps = Geometry.getSIMDSteps(nodes, inv_area, domain.step);

            const start_x = bounds.x_min_f + domain.offset;
            const start_y = bounds.y_min_f + domain.offset;
            const weights_start = Geometry.getWeightsAt(nodes, start_x, start_y, inv_area);

            var v_weights_row: [N]@Vector(8, f64) = undefined;
            inline for (0..N) |ii| {
                v_weights_row[ii] = @splat(weights_start[ii]);
                v_weights_row[ii] += v_steps.x07[ii];
            }

            const edge_tol: f64 = 1e-9;
            const v_edge_tol: @Vector(8, f64) = @splat(-edge_tol);

            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                var v_weights = v_weights_row;

                var scratch_x = bounds.start_x;
                while (scratch_x < bounds.end_x) : (scratch_x += 8) {
                    const v_07: @Vector(8, usize) = .{ 0, 1, 2, 3, 4, 5, 6, 7 };
                    const v_scratch_x: @Vector(8, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >= @as(@Vector(8, usize), @splat(original_start_x))) &
                        (v_scratch_x + v_07 < @as(@Vector(8, usize), @splat(bounds.end_x)));

                    var v_mask: @Vector(8, bool) = v_x_mask;
                    inline for (0..N) |ii| {
                        v_mask = v_mask & (v_weights[ii] >= v_edge_tol);
                    }

                    if (@reduce(.Or, v_mask)) {
                        var v_inv_z: @Vector(8, f64) = @splat(0.0);
                        inline for (0..N) |ii| {
                            v_inv_z += v_weights[ii] * v_nodes_inv_z[ii];
                        }

                        const index = row_offset + scratch_x;
                        const ptr_old_inv_z: *align(8) const @Vector(8, f64) = @ptrCast(&scratch.inv_z[index]);
                        const v_old_inv_z = ptr_old_inv_z.*;

                        const v_depth_mask = v_mask & (v_inv_z >= v_old_inv_z);

                        if (@reduce(.Or, v_depth_mask)) {
                            const ptr_new_inv_z: *align(8) @Vector(8, f64) = @ptrCast(&scratch.inv_z[index]);
                            const v_new_inv_z = @select(
                                f64,
                                v_depth_mask,
                                v_inv_z,
                                v_old_inv_z,
                            );
                            ptr_new_inv_z.* = v_new_inv_z;

                            const v_subpx_z = @as(@Vector(8, f64), @splat(1.0)) / v_inv_z;
                            shaded_px += @intCast(@reduce(
                                .Add,
                                @as(
                                    @Vector(8, u8),
                                    @select(
                                        u8,
                                        v_depth_mask,
                                        @as(@Vector(8, u8), @splat(1)),
                                        @as(@Vector(8, u8), @splat(0)),
                                    ),
                                ),
                            ));

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                .{
                                    .frame_index = ctx_rast.frame_ind,
                                    .elem_index = target.overlap.elem_idx,
                                    .fields_num = fields_num,
                                    .actual_fields = fields_num,
                                    .idx = index,
                                    .global_subx = 0,
                                    .global_suby = 0,
                                    .local_buf = local_buf,
                                    .v_mask = v_depth_mask,
                                },
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z,
                                v_subpx_z,
                                shader,
                                scratch.image,
                            );
                        }
                    }
                    inline for (0..N) |ii| {
                        v_weights[ii] += v_steps.dx[ii];
                    }
                }
                inline for (0..N) |ii| {
                    v_weights_row[ii] += v_steps.dy[ii];
                }
            }
            return shaded_px;
        }

        fn rasterSIMDNewton(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            input: *const rops.MeshInput,
            domain: SubpxDomain,
            bounds: RasterBounds,
            original_start_x: usize,
            nodes: Vec3OfSlices(f64),
            shader: anytype,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const fields_num = scratch.image.rows_num;

            var nodes_inv_z: [N]f64 = undefined;
            var v_nodes_z: [N]@Vector(8, f64) = undefined;
            var v_nodes_inv_z_simd: [N]@Vector(8, f64) = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes.z[nn];
                v_nodes_z[nn] = @splat(nodes.z[nn]);
                v_nodes_inv_z_simd[nn] = @splat(nodes_inv_z[nn]);
            }

            const NT = if (N == 4) 2 else if (N == 6) 6 else 8;
            var element_tess: hull.Tessellation(NT) = undefined;
            if (comptime Geometry.has_hull) {
                if (input.hull) |rh| {
                    const hx = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 0, 0 }, 1);
                    const hy = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 1, 0 }, 1);
                    element_tess = hull.getTessellation(N, hx, hy);
                }
            } else {
                @panic("rasterSIMDNewton requires has_hull = true");
            }

            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                @memset(scratch.subpx_mask[row_offset + bounds.start_x .. row_offset + bounds.end_x], false);
            }

            var candidate_count: usize = 0;
            const v_07: @Vector(8, usize) = .{ 0, 1, 2, 3, 4, 5, 6, 7 };

            const v_px_min: @Vector(8, f64) = @splat(@as(f64, @floatFromInt(target.tile.x_px_min)));
            const v_step: @Vector(8, f64) = @splat(domain.step);
            const v_05: @Vector(8, f64) = @splat(0.5);
            const v_original_start_x: @Vector(8, usize) = @splat(original_start_x);
            const v_bounds_end_x: @Vector(8, usize) = @splat(bounds.end_x);

            // Pass 1: Vectorized Coarse In/Out
            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const subpx_y = @as(f64, @floatFromInt(target.tile.y_px_min)) +
                    (@as(f64, @floatFromInt(scratch_y)) + 0.5) * domain.step;
                var scratch_x = bounds.start_x;
                while (scratch_x < bounds.end_x) : (scratch_x += 8) {
                    const v_scratch_x: @Vector(8, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >= v_original_start_x) &
                        (v_scratch_x + v_07 < v_bounds_end_x);

                    const v_subpx_x = v_px_min + (@as(@Vector(8, f64), @floatFromInt(v_scratch_x + v_07)) + v_05) * v_step;
                    const v_subpx_y: @Vector(8, f64) = @splat(subpx_y);

                    const v_hull_res = element_tess.isInSIMD(v_subpx_x, v_subpx_y);
                    const v_mask = v_x_mask & v_hull_res.isIn;

                    if (@reduce(.Or, v_mask)) {
                        const mask_arr: [8]bool = v_mask;
                        const x_arr: [8]f64 = v_subpx_x;
                        const y_arr: [8]f64 = v_subpx_y;
                        var xi_arr: [8]f64 = v_hull_res.guess_xi;
                        var eta_arr: [8]f64 = v_hull_res.guess_eta;

                        if (comptime @hasDecl(Geometry, "getNewtonGuess")) {
                            const def_guess = Geometry.getNewtonGuess();
                            xi_arr = [_]f64{def_guess.xi} ** 8;
                            eta_arr = [_]f64{def_guess.eta} ** 8;
                        }

                        for (0..8) |jj| {
                            if (mask_arr[jj]) {
                                const block_index = candidate_count / 8;
                                const lane_index = candidate_count % 8;

                                if (lane_index == 0) {
                                    scratch.candidate_buffer[block_index] = .{
                                        .scratch_x = [_]usize{0} ** 8,
                                        .scratch_y = [_]usize{0} ** 8,
                                        .px = [_]f64{0.0} ** 8,
                                        .py = [_]f64{0.0} ** 8,
                                        .guess_xi = [_]f64{0.0} ** 8,
                                        .guess_eta = [_]f64{0.0} ** 8,
                                        .count = 0,
                                    };
                                }

                                scratch.candidate_buffer[block_index].scratch_x[lane_index] =
                                    scratch_x + jj;
                                scratch.candidate_buffer[block_index].scratch_y[lane_index] =
                                    scratch_y;
                                scratch.candidate_buffer[block_index].px[lane_index] =
                                    x_arr[jj];
                                scratch.candidate_buffer[block_index].py[lane_index] =
                                    y_arr[jj];
                                scratch.candidate_buffer[block_index].guess_xi[lane_index] =
                                    xi_arr[jj];
                                scratch.candidate_buffer[block_index].guess_eta[lane_index] =
                                    eta_arr[jj];
                                scratch.candidate_buffer[block_index].count = lane_index + 1;
                                candidate_count += 1;
                            }
                        }
                    }
                }
            }

            // Pass 2: Vectorized Solving in chunks of 8
            const candidate_block_count = @divFloor(candidate_count + 7, 8);
            const geometry_state = if (@hasDecl(Geometry, "getNewtonParams"))
                Geometry.getNewtonParams(nodes)
            else if (@hasDecl(Geometry, "getInvElemArea"))
                Geometry.getInvElemArea(nodes)
            else if (@hasDecl(Geometry, "getBilinearParams"))
                Geometry.getBilinearParams(nodes)
            else {};
            const default_guess = if (@hasDecl(Geometry, "getNewtonGuess"))
                Geometry.getNewtonGuess()
            else
                .{ .xi = 0.0, .eta = 0.0 };
            var last_seed_valid = false;
            var last_seed_xi = default_guess.xi;
            var last_seed_eta = default_guess.eta;

            for (0..candidate_block_count) |block_index| {
                var candidate_block = scratch.candidate_buffer[block_index];
                var chunk_mask_arr = [_]bool{false} ** 8;
                for (0..candidate_block.count) |jj| {
                    chunk_mask_arr[jj] = true;
                    candidate_block.guess_xi[jj] = if (last_seed_valid)
                        last_seed_xi
                    else
                        default_guess.xi;
                    candidate_block.guess_eta[jj] = if (last_seed_valid)
                        last_seed_eta
                    else
                        default_guess.eta;
                }

                const v_target_x: @Vector(8, f64) = candidate_block.px;
                const v_target_y: @Vector(8, f64) = candidate_block.py;
                const v_xi_guess: @Vector(8, f64) = candidate_block.guess_xi;
                const v_eta_guess: @Vector(8, f64) = candidate_block.guess_eta;
                const v_chunk_mask: @Vector(8, bool) = chunk_mask_arr;

                const result = Geometry.solveWeightsSIMD(
                    nodes,
                    v_target_x,
                    v_target_y,
                    v_xi_guess,
                    v_eta_guess,
                    domain.x_off,
                    domain.y_off,
                    geometry_state,
                );

                const v_conv_mask = v_chunk_mask & result.mask;
                if (@reduce(.Or, v_conv_mask)) {
                    const conv_mask_arr: [8]bool = v_conv_mask;
                    const xi_out_arr: [8]f64 = result.xi_out;
                    const eta_out_arr: [8]f64 = result.eta_out;
                    const residual_x_arr: [8]f64 = result.residual_x;
                    const residual_y_arr: [8]f64 = result.residual_y;
                    var best_lane: ?usize = null;
                    var best_resid_sq = std.math.inf(f64);

                    for (0..8) |jj| {
                        if (conv_mask_arr[jj]) {
                            const index =
                                candidate_block.scratch_y[jj] * domain.tile_size +
                                candidate_block.scratch_x[jj];
                            scratch.subpx_xi[index] = xi_out_arr[jj];
                            scratch.subpx_eta[index] = eta_out_arr[jj];
                            scratch.subpx_mask[index] = true;

                            const residual_sq =
                                residual_x_arr[jj] * residual_x_arr[jj] +
                                residual_y_arr[jj] * residual_y_arr[jj];
                            if (best_lane == null or residual_sq < best_resid_sq) {
                                best_lane = jj;
                                best_resid_sq = residual_sq;
                            }
                        }
                    }

                    if (best_lane) |lane_index| {
                        last_seed_valid = true;
                        last_seed_xi = xi_out_arr[lane_index];
                        last_seed_eta = eta_out_arr[lane_index];
                    }
                }
            }

            // Pass 3: Spatially Grouped SIMD Shading
            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                var scratch_x = bounds.start_x;
                while (scratch_x < bounds.end_x) : (scratch_x += 8) {
                    const index = row_offset + scratch_x;
                    var mask_arr: [8]bool = undefined;
                    @memcpy(&mask_arr, scratch.subpx_mask[index .. index + 8]);
                    const v_mask_full: @Vector(8, bool) = mask_arr;

                    const v_scratch_x: @Vector(8, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >= @as(@Vector(8, usize), @splat(original_start_x))) &
                        (v_scratch_x + v_07 < @as(@Vector(8, usize), @splat(bounds.end_x)));

                    const v_mask = v_mask_full & v_x_mask;

                    if (@reduce(.Or, v_mask)) {
                        var xi_arr: [8]f64 = undefined;
                        var eta_arr: [8]f64 = undefined;
                        @memcpy(&xi_arr, scratch.subpx_xi[index .. index + 8]);
                        @memcpy(&eta_arr, scratch.subpx_eta[index .. index + 8]);
                        const v_xi: @Vector(8, f64) = xi_arr;
                        const v_eta: @Vector(8, f64) = eta_arr;

                        var v_weights: [N]@Vector(8, f64) = undefined;
                        var v_dNu: [N]@Vector(8, f64) = undefined;
                        var v_dNv: [N]@Vector(8, f64) = undefined;
                        shapefun.shapeFunctionsSIMD(N, v_xi, v_eta, &v_weights, &v_dNu, &v_dNv);

                        var v_sum_z: @Vector(8, f64) = @splat(0.0);
                        inline for (0..N) |nn| {
                            v_sum_z += v_weights[nn] * v_nodes_z[nn];
                        }
                        const v_inv_z = @as(@Vector(8, f64), @splat(1.0)) / v_sum_z;

                        const ptr_old_inv_z: *align(8) const @Vector(8, f64) = @ptrCast(&scratch.inv_z[index]);
                        const v_old_inv_z = ptr_old_inv_z.*;
                        const v_depth_mask = v_mask & (v_inv_z >= v_old_inv_z);

                        if (@reduce(.Or, v_depth_mask)) {
                            const v_new_inv_z = @select(f64, v_depth_mask, v_inv_z, v_old_inv_z);
                            const ptr_new_inv_z: *align(8) @Vector(8, f64) = @ptrCast(&scratch.inv_z[index]);
                            ptr_new_inv_z.* = v_new_inv_z;

                            const v_subpx_z = @as(@Vector(8, f64), @splat(1.0)) / v_inv_z;
                            shaded_px += @intCast(@reduce(.Add, @as(@Vector(8, u8), @select(u8, v_depth_mask, @as(@Vector(8, u8), @splat(1)), @as(@Vector(8, u8), @splat(0))))));

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                .{
                                    .frame_index = ctx_rast.frame_ind,
                                    .elem_index = target.overlap.elem_idx,
                                    .fields_num = fields_num,
                                    .actual_fields = fields_num,
                                    .idx = index,
                                    .global_subx = target.tile.x_px_min * sub_samp + scratch_x,
                                    .global_suby = target.tile.y_px_min * sub_samp + scratch_y,
                                    .local_buf = local_buf,
                                    .v_mask = v_depth_mask,
                                },
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z_simd,
                                v_subpx_z,
                                shader,
                                scratch.image,
                            );
                        }
                    }
                }
            }

            return shaded_px;
        }

        fn rasterIncremental(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            domain: SubpxDomain,
            bounds: RasterBounds,
            nodes: Vec3OfSlices(f64),
            shader: *const PreparedShader,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const fields_num = scratch.image.rows_num;

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_index| {
                nodes_inv_z[node_index] = 1.0 / nodes.z[node_index];
            }

            const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0], nodes.x[1], nodes.y[1], nodes.x[2], nodes.y[2]);

            const dweights_dx = Geometry.getDWeightsDx(nodes, inv_area, domain.step);
            const dweights_dy = Geometry.getDWeightsDy(nodes, inv_area, domain.step);

            const start_x = bounds.x_min_f + domain.offset;
            const start_y = bounds.y_min_f + domain.offset;
            var weights_row = Geometry.getWeightsAt(nodes, start_x, start_y, inv_area);

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

                            if (comptime report != .off) {
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
                                    shader,
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

        fn rasterPointwise(
            comptime report: Report,
            ctx_rast: rops.RasterContext(report),
            target: rops.OverlapTarget,
            input: rops.MeshInput,
            domain: SubpxDomain,
            bounds: RasterBounds,
            nodes: Vec3OfSlices(f64),
            shader: *const PreparedShader,
            scratch: ScratchBuffers,
            local_buf: *const shadekerns.shaderops.LocalNodeBuffer(Geometry.nodes_num),
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const fields_num = scratch.image.rows_num;

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes.z[nn];
            }

            const geometry_state = if (@hasDecl(Geometry, "getNewtonParams"))
                Geometry.getNewtonParams(nodes)
            else if (@hasDecl(Geometry, "getInvElemArea"))
                Geometry.getInvElemArea(nodes)
            else if (@hasDecl(Geometry, "getBilinearParams"))
                Geometry.getBilinearParams(nodes)
            else {};

            const NT = if (N == 4) 2 else if (N == 6) 6 else 8;
            var element_tess: hull.Tessellation(NT) = undefined;

            if (comptime Geometry.has_hull) {
                if (input.hull) |rh| {
                    const hx = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 0, 0 }, 1);
                    const hy = rh.getSlice(&[_]usize{ target.overlap.elem_idx, 1, 0 }, 1);
                    element_tess = hull.getTessellation(N, hx, hy);
                }
            }

            var subpx_y: f64 = bounds.y_min_f + domain.offset;
            for (bounds.start_y..bounds.end_y) |scratch_y| {
                const row_offset = scratch_y * domain.tile_size;
                var subpx_x: f64 = bounds.x_min_f + domain.offset;

                for (bounds.start_x..bounds.end_x) |scratch_x| {
                    const global_subx = target.tile.x_px_min * sub_samp + scratch_x;
                    const global_suby = target.tile.y_px_min * sub_samp + scratch_y;

                    if (comptime Geometry.has_hull) {
                        const hull_res = element_tess.isIn(subpx_x, subpx_y);
                        if (comptime report == .perf) {
                            ctx_rast.ctx_perf.recordEarlyOut(global_subx, global_suby, hull_res.isIn);
                        }
                        if (!hull_res.isIn) {
                            subpx_x += domain.step;
                            continue;
                        }
                    } else if (comptime report == .perf) {
                        ctx_rast.ctx_perf.recordEarlyOut(global_subx, global_suby, true);
                    }

                    const result = Geometry.solveWeights(
                        nodes,
                        subpx_x,
                        subpx_y,
                        domain.x_off,
                        domain.y_off,
                        geometry_state,
                    );

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes, weights);
                        const index = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[index]) {
                            scratch.inv_z[index] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report != .off) {
                                ctx_rast.ctx_perf.recordPixel(global_subx, global_suby, result.iters);
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
                                    shader,
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
                    } else if (comptime report != .off) {
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

pub fn averageScratch(tile: ActiveTile, sub_samp: usize, spx_tile_size: usize, fields_num: usize, spx_image_scratch: *const MatSlice(f64), spx_field_avg: []f64, image_out_arr: *NDArray(f64)) void {
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
                        spx_field_avg[ff] += spx_image_scratch.get(ff, scratch_flat_ind);
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
