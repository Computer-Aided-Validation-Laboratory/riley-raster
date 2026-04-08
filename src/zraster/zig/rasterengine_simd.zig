const std = @import("std");
const Camera = @import("camera.zig").Camera;
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const S = buildconfig.config.simd_vector_width;
const tol = buildconfig.config.tolerance;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const shapefun = @import("shapefun.zig");
const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const OverlapBBox = rops.OverlapBBox;
const ActiveTile = rops.ActiveTile;
const Vec3Slices = rops.Vec3Slices;
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("rasterengine_common.zig");

const spec = @import("zraster.zig");
const mr = @import("meshraster.zig");
const MeshPrepared = mr.MeshPrepared;
const MeshType = mr.MeshType;
const Shader = mr.Shader;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const newton = @import("newton.zig");
const shadekerns = @import("shaderkernels.zig");

const CandidateBlock = struct {
    scratch_x: [S]usize,
    scratch_y: [S]usize,
    px: [S]f64,
    py: [S]f64,
    seed_xi: [S]f64,
    seed_eta: [S]f64,
    count: usize,
};

pub const ScratchBuffers = struct {
    inv_z: []align(64) f64,
    image: *MatSlice(f64),
    candidate_buffer: []CandidateBlock,
    subpx_mask: []align(64) bool,
    subpx_xi: []align(64) f64,
    subpx_eta: []align(64) f64,
    touched_min_x: []usize,
    touched_max_x: []usize,
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;

pub fn rasterScene(
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext(report_mode),
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    tiling: rops.TilingOverlaps,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.debug.assert(image_out_arr.dims[0] <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(image_out_arr.dims[0]);

    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
    const subpx_tile_total = subpx_tile_size * subpx_tile_size;
    // Round up to the nearest multiple of 8 for padding
    const subpx_tile_total_padded = (subpx_tile_total + 7) & ~@as(usize, 7);

    const alignment = std.mem.Alignment.@"64";
    const subpx_inv_z_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + 8,
    );

    const subpx_mask_scratch = try arena_alloc.alignedAlloc(
        bool,
        alignment,
        subpx_tile_total_padded + 8,
    );

    const subpx_xi_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + 8,
    );

    const subpx_eta_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + 8,
    );

    const subpx_img_mem = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        (subpx_tile_total_padded + 8) * @as(usize, fields_num),
    );
    var subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        @as(usize, fields_num),
        subpx_tile_total_padded + 8,
    );

    const candidate_block_count = @divFloor(subpx_tile_total_padded + 7, 8) + 1;
    const candidate_buffer = try arena_alloc.alloc(CandidateBlock, candidate_block_count);

    const touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size);

    const touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size);

    const scratch = ScratchBuffers{
        .inv_z = subpx_inv_z_scratch,
        .image = &subpx_image_scratch,
        .candidate_buffer = candidate_buffer,
        .subpx_mask = subpx_mask_scratch,
        .subpx_xi = subpx_xi_scratch,
        .subpx_eta = subpx_eta_scratch,
        .touched_min_x = touched_min_x,
        .touched_max_x = touched_max_x,
    };

    const subpx_field_avg = try arena_alloc.alloc(f64, fields_num);

    for (tiling.active_tiles) |tile| {
        const tile_start = Timestamp.now(io, .awake);
        var shaded_px: u64 = 0;

        @memset(subpx_inv_z_scratch, -std.math.inf(f64));
        @memset(subpx_image_scratch.elems, 0.0);
        for (0..subpx_tile_size) |yy| {
            scratch.touched_min_x[yy] = subpx_tile_size;
            scratch.touched_max_x[yy] = 0;
        }

        const overlap_start = tile.overlap_start;
        const overlap_end = overlap_start + tile.overlap_count;
        const overlaps = tiling.overlaps[overlap_start..overlap_end];

        for (overlaps) |ov| {
            const mesh = &meshes[ov.mesh_idx];

            const targ_overlap = common.OverlapTarget{ .tile = tile, .overlap = ov };

            std.debug.assert(ov.mesh_idx < raster_hulls.len);
            const rhull_ptr = raster_hulls[ov.mesh_idx];

            const mesh_in = rops.MeshInput{
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
                    const mesh_fields: u8 = switch (mesh.shader) {
                        .nodal => |s| @intCast(s.elem_field.dims[2]),
                        .tex_u8, .tex_u16 => 1,
                        .tex_rgb_u8, .tex_rgb_u16 => 3,
                    };

                    switch (mesh.shader) {
                        .nodal => |*shader| {
                            const SK = shadekerns.NodalKernel(N);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};

                            const tt = @min(ctx_rast.frame_idx, shader.elem_field.dims[0] - 1);
                            const start_idx = shader.elem_field.getFlatInd(
                                &[_]usize{ tt, targ_overlap.overlap.elem_idx, 0, 0 },
                            );

                            local_shader_buf.load(
                                shader.elem_field,
                                start_idx,
                                mesh_fields,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, NodalPrepared).render(
                                report_mode,
                                ctx_rast,
                                targ_overlap,
                                mesh_in,
                                mesh,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                        .tex_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 1);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 1)).render(
                                report_mode,
                                ctx_rast,
                                targ_overlap,
                                mesh_in,
                                mesh,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                        .tex_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 1);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 1)).render(
                                report_mode,
                                ctx_rast,
                                targ_overlap,
                                mesh_in,
                                mesh,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                        .tex_rgb_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 3);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 3)).render(
                                report_mode,
                                ctx_rast,
                                targ_overlap,
                                mesh_in,
                                mesh,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                        .tex_rgb_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 3);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 3)).render(
                                report_mode,
                                ctx_rast,
                                targ_overlap,
                                mesh_in,
                                mesh,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                    }
                },
            }
        }

        if (sub_samp > 1) {
            averageScratch(
                tile,
                @intCast(sub_samp),
                subpx_tile_size,
                fields_num,
                &subpx_image_scratch,
                scratch.touched_min_x,
                scratch.touched_max_x,
                subpx_field_avg,
                image_out_arr,
            );
        } else {
            resolveScratchDirect(
                tile,
                subpx_tile_size,
                fields_num,
                &subpx_image_scratch,
                image_out_arr,
            );
        }

        const tile_end = if (comptime report_mode == .full_stats)
            Timestamp.now(io, .awake)
        else {};
        const tile_duration_ns = if (comptime report_mode == .full_stats)
            tile_start.durationTo(tile_end).raw.nanoseconds
        else
            0;
        const screen_px_x = @as(u16, @intCast(ctx_rast.camera.pixels_num[0]));
        const tiles_x = (screen_px_x + ctx_rast.tile_size - 1) / ctx_rast.tile_size;
        const spatial_idx = (tile.y_px_min / ctx_rast.tile_size) * tiles_x +
            (tile.x_px_min / ctx_rast.tile_size);
        ctx_rast.ctx_perf.recordTile(
            spatial_idx,
            @intCast(tile_duration_ns),
            shaded_px,
            overlaps.len,
        );
    }
}

pub fn RasterPass(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    return struct {
        pub fn render(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            mesh: *const MeshPrepared,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            _ = mesh;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            const subpx_tile_size = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;

            const sub_samp_f: f64 = @as(f64, @floatFromInt(ctx_rast.camera.sub_sample));
            const subpx_step: f64 = 1.0 / sub_samp_f;
            const subpx_offset: f64 = 1.0 / (2.0 * sub_samp_f);

            const x_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[0]));
            const y_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[1]));

            const nodes_coords = try rops.loadElemVec3Slices(
                Geometry.nodes_num,
                f64,
                mesh_in.coords,
                targ_overlap.overlap.elem_idx,
            );

            const scratch_start_x_u = sub_samp *
                (@as(usize, @intCast(targ_overlap.overlap.x_min)) -
                targ_overlap.tile.x_px_min);
            const scratch_end_x_u = sub_samp *
                (@as(usize, @intCast(targ_overlap.overlap.x_max)) -
                targ_overlap.tile.x_px_min);
            const scratch_start_y_u = sub_samp *
                (@as(usize, @intCast(targ_overlap.overlap.y_min)) -
                targ_overlap.tile.y_px_min);
            const scratch_end_y_u = sub_samp *
                (@as(usize, @intCast(targ_overlap.overlap.y_max)) -
                targ_overlap.tile.y_px_min);

            const x_min_f: f64 = @as(f64, @floatFromInt(targ_overlap.overlap.x_min));
            const y_min_f: f64 = @as(f64, @floatFromInt(targ_overlap.overlap.y_min));

            const subpx_domain = SubpxDomain{
                .step = subpx_step,
                .offset = subpx_offset,
                .tile_size = subpx_tile_size,
                .x_off = x_off,
                .y_off = y_off,
            };

            const rast_bounds = RasterBounds{
                .start_x_u = scratch_start_x_u,
                .end_x_u = scratch_end_x_u,
                .start_y_u = scratch_start_y_u,
                .end_y_u = scratch_end_y_u,
                .x_min_f = x_min_f,
                .y_min_f = y_min_f,
            };

            const shaded_px = if (comptime (Geometry == geomkerns.Tri3Kernel() or
                Geometry == geomkerns.Tri3OptKernel()))
                try rasterDirectSIMD(
                    report_mode,
                    ctx_rast,
                    targ_overlap,
                    subpx_domain,
                    rast_bounds,
                    scratch_start_x_u,
                    nodes_coords,
                    shader,
                    shader_buf,
                    scratch,
                )
            else if (Geometry.raster_mode == .incremental)
                try rasterIncrementalSIMD(
                    report_mode,
                    ctx_rast,
                    targ_overlap,
                    subpx_domain,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    scratch,
                )
            else if (Geometry.solver_kind == .newton)
                try rasterNewtonSIMD(
                    report_mode,
                    ctx_rast,
                    targ_overlap,
                    &mesh_in,
                    subpx_domain,
                    rast_bounds,
                    scratch_start_x_u,
                    nodes_coords,
                    shader,
                    shader_buf,
                    scratch,
                )
            else
                try rasterDirect(
                    report_mode,
                    ctx_rast,
                    targ_overlap,
                    mesh_in,
                    subpx_domain,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    scratch,
                );

            return shaded_px;
        }

        fn rasterDirectSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            original_start_x: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            std.debug.assert(scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.rows_num);

            const inv_area = 1.0 / rops.edgeFun3(
                nodes_coords.x[0],
                nodes_coords.y[0],
                nodes_coords.x[1],
                nodes_coords.y[1],
                nodes_coords.x[2],
                nodes_coords.y[2],
            );

            const v_nodes_inv_z = Geometry.getSIMDConstants(nodes_coords);
            const v_steps = Geometry.getSIMDSteps(nodes_coords, inv_area, subpx_domain.step);

            const start_x = rast_bounds.x_min_f + subpx_domain.offset;
            const start_y = rast_bounds.y_min_f + subpx_domain.offset;
            const weights_start = Geometry.getWeightsAt(
                nodes_coords,
                start_x,
                start_y,
                inv_area,
            );

            var v_weights_row: [N]@Vector(S, f64) = undefined;
            inline for (0..N) |ii| {
                v_weights_row[ii] = @splat(weights_start[ii]);
                v_weights_row[ii] += v_steps.x07[ii];
            }

            const edge_tol = tol.edge.simd_raster_weight_inclusion;
            const v_edge_tol: @Vector(S, f64) = @splat(-edge_tol);

            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var v_weights = v_weights_row;

                var scratch_x = rast_bounds.start_x_u;
                while (scratch_x < rast_bounds.end_x_u) : (scratch_x += 8) {
                    const v_07: @Vector(S, usize) = std.simd.iota(usize, S);
                    const v_scratch_x: @Vector(S, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >=
                            @as(@Vector(S, usize), @splat(original_start_x))) &
                        (v_scratch_x + v_07 <
                            @as(@Vector(S, usize), @splat(rast_bounds.end_x_u)));

                    var v_mask: @Vector(S, bool) = v_x_mask;
                    inline for (0..N) |ii| {
                        v_mask = v_mask & (v_weights[ii] >= v_edge_tol);
                    }

                    if (@reduce(.Or, v_mask)) {
                        var v_inv_z: @Vector(S, f64) = @splat(0.0);
                        inline for (0..N) |ii| {
                            v_inv_z += v_weights[ii] * v_nodes_inv_z[ii];
                        }

                        const scratch_idx = row_offset + scratch_x;
                        const ptr_old_inv_z: *align(8) const @Vector(S, f64) =
                            @ptrCast(&scratch.inv_z[scratch_idx]);
                        const v_old_inv_z = ptr_old_inv_z.*;

                        const v_depth_mask = v_mask & (v_inv_z >= v_old_inv_z);

                        if (@reduce(.Or, v_depth_mask)) {
                            const ptr_new_inv_z: *align(8) @Vector(S, f64) =
                                @ptrCast(&scratch.inv_z[scratch_idx]);
                            const v_new_inv_z = @select(
                                f64,
                                v_depth_mask,
                                v_inv_z,
                                v_old_inv_z,
                            );
                            ptr_new_inv_z.* = v_new_inv_z;

                            const depth_mask_arr: [S]bool = v_depth_mask;
                            for (0..S) |ll| {
                                if (depth_mask_arr[ll]) {
                                    const touched_x = scratch_x + ll;
                                    if (touched_x < scratch.touched_min_x[scratch_y]) {
                                        scratch.touched_min_x[scratch_y] = touched_x;
                                    }
                                    if (touched_x > scratch.touched_max_x[scratch_y]) {
                                        scratch.touched_max_x[scratch_y] = touched_x;
                                    }
                                }
                            }

                            const v_subpx_z = @as(@Vector(S, f64), @splat(1.0)) / v_inv_z;
                            shaded_px += @intCast(@reduce(
                                .Add,
                                @as(
                                    @Vector(S, u8),
                                    @select(
                                        u8,
                                        v_depth_mask,
                                        @as(@Vector(S, u8), @splat(1)),
                                        @as(@Vector(S, u8), @splat(0)),
                                    ),
                                ),
                            ));

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = 0,
                                .global_suby = 0,
                                .shader_buf = shader_buf,
                                .v_mask = v_depth_mask,
                            };

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                ctx_shade,
                                ctx_rast.ctx_perf,
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

        fn rasterNewtonSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: *const rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            original_start_x: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.rows_num);

            var nodes_inv_z: [N]f64 = undefined;
            var v_nodes_z: [N]@Vector(S, f64) = undefined;
            var v_nodes_inv_z_simd: [N]@Vector(S, f64) = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
                v_nodes_z[nn] = @splat(nodes_coords.z[nn]);
                v_nodes_inv_z_simd[nn] = @splat(nodes_inv_z[nn]);
            }

            var element_tess: hull.Tessellation(Geometry.tess_triangles_num) = undefined;
            if (comptime Geometry.hull_nodes_num > 0) {
                if (mesh_in.hull) |rh| {
                    const hx = rh.getSlice(
                        &[_]usize{ targ_overlap.overlap.elem_idx, 0, 0 },
                        1,
                    );
                    const hy = rh.getSlice(
                        &[_]usize{ targ_overlap.overlap.elem_idx, 1, 0 },
                        1,
                    );
                    element_tess = hull.getTessellation(
                        N,
                        Geometry.hull_nodes_num,
                        Geometry.tess_triangles_num,
                        hx,
                        hy,
                    );
                }
            } else {
                @panic("rasterNewtonSIMD requires hull_nodes_num > 0");
            }

            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                const mask_start = row_offset + rast_bounds.start_x_u;
                const mask_end = row_offset + rast_bounds.end_x_u;
                @memset(
                    scratch.subpx_mask[mask_start..mask_end],
                    false,
                );
            }

            var candidate_count: usize = 0;
            const v_07: @Vector(S, usize) = std.simd.iota(usize, S);

            const v_px_min: @Vector(S, f64) =
                @splat(@as(f64, @floatFromInt(targ_overlap.tile.x_px_min)));
            const v_step: @Vector(S, f64) =
                @splat(subpx_domain.step);
            const v_05: @Vector(S, f64) = @splat(0.5);
            const v_original_start_x: @Vector(S, usize) = @splat(original_start_x);
            const v_bounds_end_x: @Vector(S, usize) = @splat(rast_bounds.end_x_u);

            // Pass 1: Vectorized Coarse In/Out
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const subpx_y = @as(f64, @floatFromInt(targ_overlap.tile.y_px_min)) +
                    (@as(f64, @floatFromInt(scratch_y)) + 0.5) * subpx_domain.step;
                var scratch_x = rast_bounds.start_x_u;
                while (scratch_x < rast_bounds.end_x_u) : (scratch_x += 8) {
                    const v_scratch_x: @Vector(S, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >= v_original_start_x) &
                        (v_scratch_x + v_07 < v_bounds_end_x);

                    const v_subpx_x = v_px_min +
                        (@as(@Vector(S, f64), @floatFromInt(v_scratch_x + v_07)) + v_05) *
                            v_step;
                    const v_subpx_y: @Vector(S, f64) = @splat(subpx_y);

                    const v_hull_res = element_tess.isInSIMD(v_subpx_x, v_subpx_y);
                    const tess_check_num: u64 = @intCast(@reduce(
                        .Add,
                        @as(
                            @Vector(S, u8),
                            @select(
                                u8,
                                v_x_mask,
                                @as(@Vector(S, u8), @splat(1)),
                                @as(@Vector(S, u8), @splat(0)),
                            ),
                        ),
                    ));
                    ctx_rast.ctx_perf.recordTessChecks(tess_check_num);
                    const v_mask = v_x_mask & v_hull_res.isIn;
                    const tess_pass_num: u64 = @intCast(@reduce(
                        .Add,
                        @as(
                            @Vector(S, u8),
                            @select(
                                u8,
                                v_mask,
                                @as(@Vector(S, u8), @splat(1)),
                                @as(@Vector(S, u8), @splat(0)),
                            ),
                        ),
                    ));
                    ctx_rast.ctx_perf.recordTessPasses(tess_pass_num);

                    if (@reduce(.Or, v_mask)) {
                        const mask_arr: [S]bool = v_mask;
                        const x_arr: [S]f64 = v_subpx_x;
                        const y_arr: [S]f64 = v_subpx_y;
                        const init_seed = Geometry.initSeedSIMD(
                            v_subpx_x,
                            v_subpx_y,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            .{
                                .xi = v_hull_res.seed_xi,
                                .eta = v_hull_res.seed_eta,
                            },
                        );
                        const xi_arr: [S]f64 = init_seed.xi;
                        const eta_arr: [S]f64 = init_seed.eta;

                        for (0..S) |jj| {
                            if (mask_arr[jj]) {
                                const block_idx = candidate_count / 8;
                                const lane_idx = candidate_count % 8;

                                if (lane_idx == 0) {
                                    scratch.candidate_buffer[block_idx] = .{
                                        .scratch_x = [_]usize{0} ** S,
                                        .scratch_y = [_]usize{0} ** S,
                                        .px = [_]f64{0.0} ** S,
                                        .py = [_]f64{0.0} ** S,
                                        .seed_xi = [_]f64{0.0} ** S,
                                        .seed_eta = [_]f64{0.0} ** S,
                                        .count = 0,
                                    };
                                }

                                scratch.candidate_buffer[block_idx].scratch_x[lane_idx] =
                                    scratch_x + jj;
                                scratch.candidate_buffer[block_idx].scratch_y[lane_idx] =
                                    scratch_y;
                                scratch.candidate_buffer[block_idx].px[lane_idx] =
                                    x_arr[jj];
                                scratch.candidate_buffer[block_idx].py[lane_idx] =
                                    y_arr[jj];
                                scratch.candidate_buffer[block_idx].seed_xi[lane_idx] =
                                    xi_arr[jj];
                                scratch.candidate_buffer[block_idx].seed_eta[lane_idx] =
                                    eta_arr[jj];
                                scratch.candidate_buffer[block_idx].count = lane_idx + 1;
                                candidate_count += 1;
                            }
                        }
                    }
                }
            }

            // Pass 2: Vectorized Solving in chunks of 8
            const candidate_block_count = @divFloor(candidate_count + 7, 8);
            const default_seed = Geometry.initSeed(
                0.0,
                0.0,
                subpx_domain.x_off,
                subpx_domain.y_off,
                null,
            );
            _ = default_seed;
            var seed_state = newton.NewtonSeedState{};

            for (0..candidate_block_count) |block_idx| {
                var candidate_block = scratch.candidate_buffer[block_idx];
                var chunk_mask_arr = [_]bool{false} ** S;
                for (0..candidate_block.count) |jj| {
                    chunk_mask_arr[jj] = true;
                }
                newton.fillSeedBlock(
                    Geometry.seed_reuse,
                    candidate_block.count,
                    candidate_block.seed_xi[0..candidate_block.count],
                    candidate_block.seed_eta[0..candidate_block.count],
                    seed_state,
                    candidate_block.seed_xi[0..candidate_block.count],
                    candidate_block.seed_eta[0..candidate_block.count],
                );

                const v_target_x: @Vector(S, f64) = candidate_block.px;
                const v_target_y: @Vector(S, f64) = candidate_block.py;
                const v_xi_seed: @Vector(S, f64) = candidate_block.seed_xi;
                const v_eta_seed: @Vector(S, f64) = candidate_block.seed_eta;
                const v_chunk_mask: @Vector(S, bool) = chunk_mask_arr;

                ctx_rast.ctx_perf.recordSolverCalls(candidate_block.count);
                const result = Geometry.solveWeightsNewtonSIMD(
                    nodes_coords,
                    v_target_x,
                    v_target_y,
                    v_xi_seed,
                    v_eta_seed,
                    subpx_domain.x_off,
                    subpx_domain.y_off,
                );
                const v_solver_iters = @select(
                    u8,
                    v_chunk_mask,
                    result.iters,
                    @as(@Vector(S, u8), @splat(0)),
                );
                const solver_iters: u64 = @intCast(@reduce(.Add, v_solver_iters));
                ctx_rast.ctx_perf.recordSolverIters(solver_iters);

                const v_conv_mask = v_chunk_mask & result.mask;
                if (@reduce(.Or, v_conv_mask)) {
                    const conv_mask_arr: [S]bool = v_conv_mask;
                    const xi_out_arr: [S]f64 = result.xi_out;
                    const eta_out_arr: [S]f64 = result.eta_out;
                    const residual_x_arr: [S]f64 = result.residual_x;
                    const residual_y_arr: [S]f64 = result.residual_y;
                    var best_lane: ?usize = null;
                    var best_resid_sq = std.math.inf(f64);

                    for (0..S) |jj| {
                        if (conv_mask_arr[jj]) {
                            const scratch_idx =
                                candidate_block.scratch_y[jj] * subpx_domain.tile_size +
                                candidate_block.scratch_x[jj];
                            scratch.subpx_xi[scratch_idx] = xi_out_arr[jj];
                            scratch.subpx_eta[scratch_idx] = eta_out_arr[jj];
                            scratch.subpx_mask[scratch_idx] = true;

                            const residual_sq =
                                residual_x_arr[jj] * residual_x_arr[jj] +
                                residual_y_arr[jj] * residual_y_arr[jj];
                            if (best_lane == null or residual_sq < best_resid_sq) {
                                best_lane = jj;
                                best_resid_sq = residual_sq;
                            }
                        }
                    }

                    if (comptime Geometry.seed_reuse == .last_converged) {
                        if (best_lane != null) {
                            newton.updateSeedStateFromSIMDResult(
                                &seed_state,
                                v_chunk_mask,
                                result.mask,
                                result.xi_out,
                                result.eta_out,
                                result.residual_x,
                                result.residual_y,
                            );
                        }
                    }
                }
            }

            // Pass 3: Spatially Grouped SIMD Shading
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var scratch_x = rast_bounds.start_x_u;
                while (scratch_x < rast_bounds.end_x_u) : (scratch_x += 8) {
                    const scratch_idx = row_offset + scratch_x;
                    var mask_arr: [S]bool = undefined;
                    @memcpy(
                        &mask_arr,
                        scratch.subpx_mask[scratch_idx .. scratch_idx + 8],
                    );
                    const v_mask_full: @Vector(S, bool) = mask_arr;

                    const v_scratch_x: @Vector(S, usize) = @splat(scratch_x);
                    const v_x_mask = (v_scratch_x + v_07 >=
                        @as(@Vector(S, usize), @splat(original_start_x))) &
                        (v_scratch_x + v_07 <
                            @as(@Vector(S, usize), @splat(rast_bounds.end_x_u)));

                    const v_mask = v_mask_full & v_x_mask;

                    if (@reduce(.Or, v_mask)) {
                        var xi_arr: [S]f64 = undefined;
                        var eta_arr: [S]f64 = undefined;
                        @memcpy(&xi_arr, scratch.subpx_xi[scratch_idx .. scratch_idx + 8]);
                        @memcpy(
                            &eta_arr,
                            scratch.subpx_eta[scratch_idx .. scratch_idx + 8],
                        );
                        const v_xi: @Vector(S, f64) = xi_arr;
                        const v_eta: @Vector(S, f64) = eta_arr;

                        var v_weights: [N]@Vector(S, f64) = undefined;
                        var v_dNu: [N]@Vector(S, f64) = undefined;
                        var v_dNv: [N]@Vector(S, f64) = undefined;
                        shapefun.shapeFunctionsSIMD(
                            N,
                            v_xi,
                            v_eta,
                            &v_weights,
                            &v_dNu,
                            &v_dNv,
                        );

                        var v_sum_z: @Vector(S, f64) = @splat(0.0);
                        inline for (0..N) |nn| {
                            v_sum_z += v_weights[nn] * v_nodes_z[nn];
                        }
                        const v_inv_z = @as(@Vector(S, f64), @splat(1.0)) / v_sum_z;

                        const ptr_old_inv_z: *align(8) const @Vector(S, f64) =
                            @ptrCast(&scratch.inv_z[scratch_idx]);
                        const v_old_inv_z = ptr_old_inv_z.*;
                        const v_depth_mask = v_mask & (v_inv_z >= v_old_inv_z);

                        if (@reduce(.Or, v_depth_mask)) {
                            const v_new_inv_z = @select(
                                f64,
                                v_depth_mask,
                                v_inv_z,
                                v_old_inv_z,
                            );
                            const ptr_new_inv_z: *align(8) @Vector(S, f64) =
                                @ptrCast(&scratch.inv_z[scratch_idx]);
                            ptr_new_inv_z.* = v_new_inv_z;

                            const depth_mask_arr: [S]bool = v_depth_mask;
                            for (0..S) |ll| {
                                if (depth_mask_arr[ll]) {
                                    const touched_x = scratch_x + ll;
                                    if (touched_x < scratch.touched_min_x[scratch_y]) {
                                        scratch.touched_min_x[scratch_y] = touched_x;
                                    }
                                    if (touched_x > scratch.touched_max_x[scratch_y]) {
                                        scratch.touched_max_x[scratch_y] = touched_x;
                                    }
                                }
                            }

                            const v_subpx_z = @as(@Vector(S, f64), @splat(1.0)) / v_inv_z;
                            shaded_px += @intCast(@reduce(
                                .Add,
                                @as(
                                    @Vector(S, u8),
                                    @select(
                                        u8,
                                        v_depth_mask,
                                        @as(@Vector(S, u8), @splat(1)),
                                        @as(@Vector(S, u8), @splat(0)),
                                    ),
                                ),
                            ));

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = targ_overlap.tile.x_px_min * sub_samp +
                                    scratch_x,
                                .global_suby = targ_overlap.tile.y_px_min * sub_samp +
                                    scratch_y,
                                .shader_buf = shader_buf,
                                .v_mask = v_depth_mask,
                            };

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                ctx_shade,
                                ctx_rast.ctx_perf,
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

        fn rasterIncrementalSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.rows_num);

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_idx| {
                nodes_inv_z[node_idx] = 1.0 / nodes_coords.z[node_idx];
            }

            const inv_area = 1.0 / rops.edgeFun3(
                nodes_coords.x[0],
                nodes_coords.y[0],
                nodes_coords.x[1],
                nodes_coords.y[1],
                nodes_coords.x[2],
                nodes_coords.y[2],
            );

            const dweights_dx = Geometry.getDWeightsDx(
                nodes_coords,
                inv_area,
                subpx_domain.step,
            );
            const dweights_dy = Geometry.getDWeightsDy(
                nodes_coords,
                inv_area,
                subpx_domain.step,
            );

            const start_x = rast_bounds.x_min_f + subpx_domain.offset;
            const start_y = rast_bounds.y_min_f + subpx_domain.offset;
            var weights_row = Geometry.getWeightsAt(
                nodes_coords,
                start_x,
                start_y,
                inv_area,
            );

            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var weights = weights_row;

                for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
                    if (Geometry.isInElement(weights)) {
                        ctx_rast.ctx_perf.recordSolverCalls(1);
                        ctx_rast.ctx_perf.recordSolverIters(0);
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[scratch_idx]) {
                            scratch.inv_z[scratch_idx] = inv_z;
                            if (scratch_x < scratch.touched_min_x[scratch_y]) {
                                scratch.touched_min_x[scratch_y] = scratch_x;
                            }
                            if (scratch_x > scratch.touched_max_x[scratch_y]) {
                                scratch.touched_max_x[scratch_y] = scratch_x;
                            }
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            const global_subx = targ_overlap.tile.x_px_min * sub_samp +
                                scratch_x;
                            const global_suby = targ_overlap.tile.y_px_min * sub_samp +
                                scratch_y;

                            if (comptime report_mode == .full_stats) {
                                ctx_rast.ctx_perf.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    0,
                                );
                                report.maybeRecordPixelOccupancy(
                                    ctx_rast.ctx_perf,
                                    targ_overlap.tile.x_px_min + scratch_x / sub_samp,
                                    targ_overlap.tile.y_px_min + scratch_y / sub_samp,
                                );
                            }

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = global_subx,
                                .global_suby = global_suby,
                                .shader_buf = shader_buf,
                            };
                            const interp_data = shaderops.InterpData(N){
                                .weights = weights,
                                .nodes_inv_z = nodes_inv_z,
                                .sub_pixel_z = subpx_z,
                            };

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                ctx_shade,
                                interp_data,
                                shader,
                                ctx_rast.ctx_perf,
                                scratch.image,
                            );
                        }
                    }
                    inline for (0..N) |node_idx| {
                        weights[node_idx] += dweights_dx[node_idx];
                    }
                }
                inline for (0..N) |node_idx| {
                    weights_row[node_idx] += dweights_dy[node_idx];
                }
            }
            return shaded_px;
        }

        fn rasterDirect(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.rows_num);

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
            }

            const solver_state = if (comptime Geometry.solver_kind == .newton)
                if (@hasDecl(Geometry, "getNewtonParams"))
                    Geometry.getNewtonParams(nodes_coords)
                else
                    {}
            else if (comptime Geometry.solver_kind == .inv_bi)
                Geometry.getBilinearParams(nodes_coords)
            else if (@hasDecl(Geometry, "getInvElemArea"))
                Geometry.getInvElemArea(nodes_coords)
            else
                {};

            var element_tess: hull.Tessellation(Geometry.tess_triangles_num) = undefined;

            if (comptime Geometry.hull_nodes_num > 0) {
                if (mesh_in.hull) |rh| {
                    const hx = rh.getSlice(
                        &[_]usize{ targ_overlap.overlap.elem_idx, 0, 0 },
                        1,
                    );
                    const hy = rh.getSlice(
                        &[_]usize{ targ_overlap.overlap.elem_idx, 1, 0 },
                        1,
                    );
                    element_tess = hull.getTessellation(
                        N,
                        Geometry.hull_nodes_num,
                        Geometry.tess_triangles_num,
                        hx,
                        hy,
                    );
                }
            }

            var subpx_y: f64 = rast_bounds.y_min_f + subpx_domain.offset;
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var subpx_x: f64 = rast_bounds.x_min_f + subpx_domain.offset;

                for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
                    const global_subx = targ_overlap.tile.x_px_min * sub_samp + scratch_x;
                    const global_suby = targ_overlap.tile.y_px_min * sub_samp + scratch_y;

                    if (comptime Geometry.hull_nodes_num > 0) {
                        ctx_rast.ctx_perf.recordTessChecks(1);
                        const is_in_tess = element_tess.isInScalar(subpx_x, subpx_y);
                        if (is_in_tess) {
                            ctx_rast.ctx_perf.recordTessPasses(1);
                        }
                        if (comptime report_mode == .full_stats) {
                            report.maybeRecordEarlyOut(
                                ctx_rast.ctx_perf,
                                global_subx,
                                global_suby,
                                is_in_tess,
                            );
                        }
                        if (!is_in_tess) {
                            subpx_x += subpx_domain.step;
                            continue;
                        }
                    } else if (comptime report_mode == .full_stats) {
                        report.maybeRecordEarlyOut(
                            ctx_rast.ctx_perf,
                            global_subx,
                            global_suby,
                            true,
                        );
                    }

                    ctx_rast.ctx_perf.recordSolverCalls(1);
                    const result = if (comptime Geometry.solver_kind == .inv_bi)
                        Geometry.solveWeightsInvBi(
                            subpx_x,
                            subpx_y,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            solver_state,
                        )
                    else
                        Geometry.solveWeightsHyperb(
                            nodes_coords,
                            subpx_x,
                            subpx_y,
                            solver_state,
                        );
                    ctx_rast.ctx_perf.recordSolverIters(result.iters);

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[scratch_idx]) {
                            scratch.inv_z[scratch_idx] = inv_z;
                            if (scratch_x < scratch.touched_min_x[scratch_y]) {
                                scratch.touched_min_x[scratch_y] = scratch_x;
                            }
                            if (scratch_x > scratch.touched_max_x[scratch_y]) {
                                scratch.touched_max_x[scratch_y] = scratch_x;
                            }
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report_mode == .full_stats) {
                                ctx_rast.ctx_perf.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    result.iters,
                                );
                                report.maybeRecordPixelOccupancy(
                                    ctx_rast.ctx_perf,
                                    targ_overlap.tile.x_px_min + scratch_x / sub_samp,
                                    targ_overlap.tile.y_px_min + scratch_y / sub_samp,
                                );
                            }

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = global_subx,
                                .global_suby = global_suby,
                                .shader_buf = shader_buf,
                            };
                            const interp_data = shaderops.InterpData(N){
                                .weights = weights,
                                .nodes_inv_z = nodes_inv_z,
                                .sub_pixel_z = subpx_z,
                            };

                            ShaderKernel.shade(
                                Geometry.coord_space,
                                ctx_shade,
                                interp_data,
                                shader,
                                ctx_rast.ctx_perf,
                                scratch.image,
                            );
                        }
                    } else {
                        if (result.iters > 0) ctx_rast.ctx_perf.recordSolverDiverged();
                    }
                    subpx_x += subpx_domain.step;
                }
                subpx_y += subpx_domain.step;
            }
            return shaded_px;
        }
    };
}

pub fn resolveScratchDirect(
    tile: ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const scratch_row_offset = ty * spx_tile_size;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const scratch_flat_idx = scratch_row_offset + tx;

            if (fields_num == 1) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    spx_image_scratch.get(0, scratch_flat_idx),
                );
            } else if (fields_num == 3) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    spx_image_scratch.get(0, scratch_flat_idx),
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    spx_image_scratch.get(1, scratch_flat_idx),
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    spx_image_scratch.get(2, scratch_flat_idx),
                );
            } else {
                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        spx_image_scratch.get(ff, scratch_flat_idx),
                    );
                }
            }
        }
    }
}

pub fn averageScratch(
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    spx_field_avg: []f64,
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;
        var touched_min_px_x = curr_tile_size_x;
        var touched_max_px_x: usize = 0;

        for (0..sub_samp) |sy| {
            const scratch_y = spx_start_y + sy;
            const row_min_x = touched_min_x[scratch_y];
            const row_max_x = touched_max_x[scratch_y];

            if (row_min_x <= row_max_x) {
                const row_min_px_x = row_min_x / sub_samp;
                const row_max_px_x = row_max_x / sub_samp;
                if (row_min_px_x < touched_min_px_x) {
                    touched_min_px_x = row_min_px_x;
                }
                if (row_max_px_x > touched_max_px_x) {
                    touched_max_px_x = row_max_px_x;
                }
            }
        }

        if (touched_min_px_x > touched_max_px_x) {
            continue;
        }

        for (touched_min_px_x..@min(curr_tile_size_x, touched_max_px_x + 1)) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            if (fields_num == 1) {
                var field_sum_0: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;
                        field_sum_0 += spx_image_scratch.get(0, scratch_flat_idx);
                    }
                }

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
            } else if (fields_num == 3) {
                var field_sum_0: f64 = 0.0;
                var field_sum_1: f64 = 0.0;
                var field_sum_2: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;
                        field_sum_0 += spx_image_scratch.get(0, scratch_flat_idx);
                        field_sum_1 += spx_image_scratch.get(1, scratch_flat_idx);
                        field_sum_2 += spx_image_scratch.get(2, scratch_flat_idx);
                    }
                }

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    field_sum_1 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    field_sum_2 * inv_sub_samp_sq,
                );
            } else {
                @memset(spx_field_avg, 0.0);

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;

                        for (0..@as(usize, fields_num)) |ff| {
                            spx_field_avg[ff] += spx_image_scratch.get(ff, scratch_flat_idx);
                        }
                    }
                }

                for (0..@as(usize, fields_num)) |ff| {
                    const image_val: f64 = spx_field_avg[ff] * inv_sub_samp_sq;
                    image_out_arr.set(&[_]usize{ ff, image_px_y, image_px_x }, image_val);
                }
            }
        }
    }
}
