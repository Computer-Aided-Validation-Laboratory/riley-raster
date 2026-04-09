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

const SubpxSimdChunk = struct {
    scratch_x: [S]usize,
    scratch_y: [S]usize,
    px: [S]f64,
    py: [S]f64,
    seed_xi: [S]f64,
    seed_eta: [S]f64,
    count: usize,
};

pub const SubpxScratchBuffers = struct {
    inv_z: []align(64) f64,
    image: MatSlice(f64),
    simd_chunks: []SubpxSimdChunk,
    mask: []align(64) bool,
    xi: []align(64) f64,
    eta: []align(64) f64,
    touched_min_x: []usize,
    touched_max_x: []usize,
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;
const ScratchLayout = common.ScratchLayout;

pub const scratch_layout = ScratchLayout.field_major;

pub fn initSubpxScratch(
    arena_alloc: std.mem.Allocator,
    fields_num: u8,
    subpx_tile_size: usize,
) !SubpxScratchBuffers {
    const subpx_tile_total = subpx_tile_size * subpx_tile_size;
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
    const subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        @as(usize, fields_num),
        subpx_tile_total_padded + 8,
    );

    const subpx_simd_chunk_count =
        @divFloor(subpx_tile_total_padded + 7, 8) + 1;
    const subpx_simd_chunks = try arena_alloc.alloc(
        SubpxSimdChunk,
        subpx_simd_chunk_count,
    );

    return .{
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .simd_chunks = subpx_simd_chunks,
        .mask = subpx_mask_scratch,
        .xi = subpx_xi_scratch,
        .eta = subpx_eta_scratch,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffers,
    subpx_tile_size: usize,
) void {
    @memset(subpx_scratch.inv_z, -std.math.inf(f64));
    @memset(subpx_scratch.image.elems, 0.0);
    @memset(subpx_scratch.touched_min_x, subpx_tile_size);
    @memset(subpx_scratch.touched_max_x, 0);
}

pub fn rasterScene(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tiling: rops.TilingOverlaps,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    try common.rasterSceneCommon(
        @This(),
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );
}

pub fn RasterPass(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    return struct {
        pub fn render(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const sub_samp_u: usize = @intCast(ctx_rast.camera.sub_sample);
            const sub_samp_f: f64 = @as(f64, @floatFromInt(ctx_rast.camera.sub_sample));

            const subpx_domain = SubpxDomain{
                .step = 1.0 / sub_samp_f,
                .offset = 1.0 / (2.0 * sub_samp_f),
                .tile_size = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp_u,
                .x_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[0])),
                .y_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[1])),
            };

            const scratch_start_x_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.x_min) - targ_overlap.tile.x_px_min);
            const scratch_end_x_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.x_max) - targ_overlap.tile.x_px_min);
            const scratch_start_y_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.y_min) - targ_overlap.tile.y_px_min);
            const scratch_end_y_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.y_max) - targ_overlap.tile.y_px_min);

            const rast_bounds = RasterBounds{
                .start_x_u = scratch_start_x_u,
                .end_x_u = scratch_end_x_u,
                .start_y_u = scratch_start_y_u,
                .end_y_u = scratch_end_y_u,
                .x_min_f = @as(f64, @floatFromInt(targ_overlap.overlap.x_min)),
                .y_min_f = @as(f64, @floatFromInt(targ_overlap.overlap.y_min)),
            };

            const nodes_coords = try rops.loadElemVec3Slices(
                Geometry.nodes_num,
                f64,
                mesh_in.coords,
                targ_overlap.overlap.elem_idx,
            );

            const shaded_px = if (comptime Geometry == geomkerns.Tri3Kernel())
                try rasterDirectSIMD(
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    subpx_domain,
                    rast_bounds,
                    scratch_start_x_u,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                )
            else if (Geometry.raster_mode == .incremental)
                try rasterIncrementalSIMD(
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    subpx_domain,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                )
            else if (Geometry.solver_kind == .newton)
                try rasterNewtonSIMD(
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    &mesh_in,
                    subpx_domain,
                    rast_bounds,
                    scratch_start_x_u,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                )
            else
                try rasterDirect(
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    mesh_in,
                    subpx_domain,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                );

            return shaded_px;
        }

        fn rasterDirectSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            original_start_x: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

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
                while (scratch_x < rast_bounds.end_x_u) : (scratch_x += S) {
                    const v_07: @Vector(S, usize) = std.simd.iota(usize, S);
                    const v_scratch_x: @Vector(S, usize) = @splat(scratch_x);

                    const v_x = v_scratch_x + v_07;
                    const v_start = @as(@Vector(S, usize), @splat(original_start_x));
                    const v_end = @as(@Vector(S, usize), @splat(rast_bounds.end_x_u));
                    const v_x_mask = (v_x >= v_start) & (v_x < v_end);

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
                            @ptrCast(&subpx_scratch.inv_z[scratch_idx]);
                        const v_old_inv_z = ptr_old_inv_z.*;

                        const v_depth_mask = v_mask & (v_inv_z >= v_old_inv_z);

                        if (@reduce(.Or, v_depth_mask)) {
                            const ptr_new_inv_z: *align(8) @Vector(S, f64) =
                                @ptrCast(&subpx_scratch.inv_z[scratch_idx]);
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
                                    if (touched_x < subpx_scratch.touched_min_x[scratch_y]) {
                                        subpx_scratch.touched_min_x[scratch_y] = touched_x;
                                    }
                                    if (touched_x > subpx_scratch.touched_max_x[scratch_y]) {
                                        subpx_scratch.touched_max_x[scratch_y] = touched_x;
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
                                ctx_report,
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z,
                                v_subpx_z,
                                shader,
                                &subpx_scratch.image,
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
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: *const rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            original_start_x: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

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
                    subpx_scratch.mask[mask_start..mask_end],
                    false,
                );
            }

            var subpx_simd_sample_count: usize = 0;
            const v_07: @Vector(S, usize) = std.simd.iota(usize, S);

            const v_px_min: @Vector(S, f64) =
                @splat(@as(f64, @floatFromInt(targ_overlap.tile.x_px_min)));
            const v_step: @Vector(S, f64) = @splat(subpx_domain.step);
            const v_05: @Vector(S, f64) = @splat(0.5);
            const v_original_start_x: @Vector(S, usize) = @splat(original_start_x);
            const v_bounds_end_x: @Vector(S, usize) = @splat(rast_bounds.end_x_u);

            // Pass 1: Vectorized Coarse In/Out
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const subpx_y = @as(f64, @floatFromInt(targ_overlap.tile.y_px_min)) +
                    (@as(f64, @floatFromInt(scratch_y)) + 0.5) * subpx_domain.step;
                var scratch_x = rast_bounds.start_x_u;

                while (scratch_x < rast_bounds.end_x_u) : (scratch_x += S) {
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
                    ctx_report.recordTessChecks(tess_check_num);
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
                    ctx_report.recordTessPasses(tess_pass_num);

                    if (@reduce(.Or, v_mask)) {
                        const mask_arr: [S]bool = v_mask;
                        const x_arr: [S]f64 = v_subpx_x;
                        const y_arr: [S]f64 = v_subpx_y;
                        const init_seed = Geometry.initSeedSIMD(.{
                            .xi = v_hull_res.seed_xi,
                            .eta = v_hull_res.seed_eta,
                        });
                        const xi_arr: [S]f64 = init_seed.xi;
                        const eta_arr: [S]f64 = init_seed.eta;

                        for (0..S) |jj| {
                            if (mask_arr[jj]) {
                                var seed_xi = xi_arr[jj];
                                var seed_eta = eta_arr[jj];

                                if (comptime Geometry.seed_mode == .hull) {
                                    const hull_seed = newton.NewtonSeed{
                                        .xi = seed_xi,
                                        .eta = seed_eta,
                                    };
                                    const seed_quality = newton.evaluateSeedQuality(
                                        Geometry.nodes_num,
                                        Geometry.domainViolation,
                                        x_arr[jj] - subpx_domain.x_off,
                                        y_arr[jj] - subpx_domain.y_off,
                                        nodes_coords.x,
                                        nodes_coords.y,
                                        nodes_coords.z,
                                        hull_seed,
                                    );
                                    if (!seed_quality.is_usable) {
                                        const centroid_seed = Geometry.initSeed(null);
                                        seed_xi = centroid_seed.xi;
                                        seed_eta = centroid_seed.eta;
                                    }
                                }

                                const chunk_idx = subpx_simd_sample_count / 8;
                                const lane_idx = subpx_simd_sample_count % 8;

                                if (lane_idx == 0) {
                                    subpx_scratch.simd_chunks[chunk_idx] = .{
                                        .scratch_x = [_]usize{0} ** S,
                                        .scratch_y = [_]usize{0} ** S,
                                        .px = [_]f64{0.0} ** S,
                                        .py = [_]f64{0.0} ** S,
                                        .seed_xi = [_]f64{0.0} ** S,
                                        .seed_eta = [_]f64{0.0} ** S,
                                        .count = 0,
                                    };
                                }

                                subpx_scratch.simd_chunks[chunk_idx].scratch_x[lane_idx] =
                                    scratch_x + jj;
                                subpx_scratch.simd_chunks[chunk_idx].scratch_y[lane_idx] =
                                    scratch_y;
                                subpx_scratch.simd_chunks[chunk_idx].px[lane_idx] =
                                    x_arr[jj];
                                subpx_scratch.simd_chunks[chunk_idx].py[lane_idx] =
                                    y_arr[jj];
                                subpx_scratch.simd_chunks[chunk_idx].seed_xi[lane_idx] =
                                    seed_xi;
                                subpx_scratch.simd_chunks[chunk_idx].seed_eta[lane_idx] =
                                    seed_eta;
                                subpx_scratch.simd_chunks[chunk_idx].count = lane_idx + 1;
                                subpx_simd_sample_count += 1;
                            }
                        }
                    }
                }
            }

            // Pass 2: Vectorized Solving in chunks of 8
            const subpx_simd_chunk_count =
                @divFloor(subpx_simd_sample_count + 7, 8);
            const default_seed = Geometry.initSeed(null);
            _ = default_seed;
            var seed_state = newton.NewtonSeedState{};

            for (0..subpx_simd_chunk_count) |chunk_idx| {
                var subpx_simd_chunk = subpx_scratch.simd_chunks[chunk_idx];
                var chunk_mask_arr = [_]bool{false} ** S;
                for (0..subpx_simd_chunk.count) |jj| {
                    chunk_mask_arr[jj] = true;
                }
                newton.fillSeedBlock(
                    Geometry.seed_reuse,
                    subpx_simd_chunk.count,
                    subpx_simd_chunk.seed_xi[0..subpx_simd_chunk.count],
                    subpx_simd_chunk.seed_eta[0..subpx_simd_chunk.count],
                    seed_state,
                    subpx_simd_chunk.seed_xi[0..subpx_simd_chunk.count],
                    subpx_simd_chunk.seed_eta[0..subpx_simd_chunk.count],
                );

                const v_target_x: @Vector(S, f64) = subpx_simd_chunk.px;
                const v_target_y: @Vector(S, f64) = subpx_simd_chunk.py;
                const v_xi_seed: @Vector(S, f64) = subpx_simd_chunk.seed_xi;
                const v_eta_seed: @Vector(S, f64) = subpx_simd_chunk.seed_eta;
                const v_chunk_mask: @Vector(S, bool) = chunk_mask_arr;

                ctx_report.recordSolverCalls(subpx_simd_chunk.count);
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
                ctx_report.recordSolverIters(solver_iters);

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
                                subpx_simd_chunk.scratch_y[jj] * subpx_domain.tile_size +
                                subpx_simd_chunk.scratch_x[jj];
                            subpx_scratch.xi[scratch_idx] = xi_out_arr[jj];
                            subpx_scratch.eta[scratch_idx] = eta_out_arr[jj];
                            subpx_scratch.mask[scratch_idx] = true;

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
                        subpx_scratch.mask[scratch_idx .. scratch_idx + 8],
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
                        @memcpy(&xi_arr, subpx_scratch.xi[scratch_idx .. scratch_idx + 8]);
                        @memcpy(
                            &eta_arr,
                            subpx_scratch.eta[scratch_idx .. scratch_idx + 8],
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
                            @ptrCast(&subpx_scratch.inv_z[scratch_idx]);
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
                                @ptrCast(&subpx_scratch.inv_z[scratch_idx]);
                            ptr_new_inv_z.* = v_new_inv_z;

                            const depth_mask_arr: [S]bool = v_depth_mask;
                            for (0..S) |ll| {
                                if (depth_mask_arr[ll]) {
                                    const touched_x = scratch_x + ll;
                                    if (touched_x < subpx_scratch.touched_min_x[scratch_y]) {
                                        subpx_scratch.touched_min_x[scratch_y] = touched_x;
                                    }
                                    if (touched_x > subpx_scratch.touched_max_x[scratch_y]) {
                                        subpx_scratch.touched_max_x[scratch_y] = touched_x;
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
                                ctx_report,
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z_simd,
                                v_subpx_z,
                                shader,
                                &subpx_scratch.image,
                            );
                        }
                    }
                }
            }

            return shaded_px;
        }

        fn rasterIncrementalSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

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
                        ctx_report.recordSolverStats(1, 0);
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= subpx_scratch.inv_z[scratch_idx]) {
                            subpx_scratch.inv_z[scratch_idx] = inv_z;
                            if (scratch_x < subpx_scratch.touched_min_x[scratch_y]) {
                                subpx_scratch.touched_min_x[scratch_y] = scratch_x;
                            }
                            if (scratch_x > subpx_scratch.touched_max_x[scratch_y]) {
                                subpx_scratch.touched_max_x[scratch_y] = scratch_x;
                            }
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            const global_subx = targ_overlap.tile.x_px_min * sub_samp +
                                scratch_x;
                            const global_suby = targ_overlap.tile.y_px_min * sub_samp +
                                scratch_y;

                            if (comptime report_mode == .full_stats) {
                                ctx_report.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    0,
                                );
                                ctx_report.recordPixelOccupancy(
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
                                ctx_report,
                                &subpx_scratch.image,
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
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
            }

            const bilinear_params = if (comptime Geometry.solver_kind == .inv_bi)
                Geometry.getBilinearParams(nodes_coords)
            else {};
            const inv_elem_area = if (comptime Geometry.solver_kind == .hyperb)
                Geometry.getInvElemArea(nodes_coords)
            else {};

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
                        ctx_report.recordTessChecks(1);
                        const tess_res = element_tess.isInScalar(subpx_x, subpx_y);
                        if (tess_res.is_in) {
                            ctx_report.recordTessPasses(1);
                        }
                        if (comptime report_mode == .full_stats) {
                            ctx_report.recordEarlyOut(
                                global_subx,
                                global_suby,
                                tess_res.is_in,
                            );
                        }
                        if (!tess_res.is_in) {
                            subpx_x += subpx_domain.step;
                            continue;
                        }
                    } else if (comptime report_mode == .full_stats) {
                        ctx_report.recordEarlyOut(
                            global_subx,
                            global_suby,
                            true,
                        );
                    }

                    ctx_report.recordSolverCalls(1);
                    const result = if (comptime Geometry.solver_kind == .inv_bi)
                        Geometry.solveWeightsInvBi(
                            subpx_x,
                            subpx_y,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            bilinear_params,
                        )
                    else
                        Geometry.solveWeightsHyperb(
                            nodes_coords,
                            subpx_x,
                            subpx_y,
                            inv_elem_area,
                        );
                    ctx_report.recordSolverIters(result.iters);

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= subpx_scratch.inv_z[scratch_idx]) {
                            subpx_scratch.inv_z[scratch_idx] = inv_z;
                            if (scratch_x < subpx_scratch.touched_min_x[scratch_y]) {
                                subpx_scratch.touched_min_x[scratch_y] = scratch_x;
                            }
                            if (scratch_x > subpx_scratch.touched_max_x[scratch_y]) {
                                subpx_scratch.touched_max_x[scratch_y] = scratch_x;
                            }
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report_mode == .full_stats) {
                                ctx_report.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    result.iters,
                                );
                                ctx_report.recordPixelOccupancy(
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
                                ctx_report,
                                &subpx_scratch.image,
                            );
                        }
                    } else {
                        if (result.iters > 0) ctx_report.recordSolverDiverged();
                    }
                    subpx_x += subpx_domain.step;
                }
                subpx_y += subpx_domain.step;
            }
            return shaded_px;
        }
    };
}
