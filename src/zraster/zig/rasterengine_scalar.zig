// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const CameraPrepared = @import("camera.zig").CameraPrepared;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const OverlapBBox = rops.OverlapBBox;
const ActiveTile = rops.ActiveTile;
const Vec3Slices = rops.Vec3Slices;
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("rasterengine_common.zig");

const mo = @import("meshops.zig");
const MeshPrepared = mo.MeshPrepared;
const MeshType = mo.MeshType;
const Shader = mo.Shader;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const newton = @import("newton.zig");
const shadekerns = @import("shaderkernels.zig");

pub const SubpxScratchBuffers = struct {
    inv_z: []f64,
    image: MatSlice(f64),
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pixel_centers: []f64,
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
    const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;
    const subpx_inv_z_scratch = try arena_alloc.alloc(f64, subpx_tile_total);
    const subpx_img_mem = try arena_alloc.alloc(
        f64,
        subpx_tile_total * @as(usize, fields_num),
    );
    const subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        @as(usize, fields_num),
        subpx_tile_total,
    );

    const ideal_pixel_centers = try arena_alloc.alloc(f64, subpx_tile_total * 2);

    return .{
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .ideal_pixel_centers = ideal_pixel_centers,
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffers,
    subpx_tile_size: usize,
) void {
    @memset(subpx_scratch.inv_z, -std.math.inf(f64));
    @memset(subpx_scratch.image.slice, 0.0);
    @memset(subpx_scratch.touched_min_x, subpx_tile_size);
    @memset(subpx_scratch.touched_max_x, 0);
}

pub fn rasterScene(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    threads_within_image: u16,
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
        threads_within_image,
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

            const shaded_px = try rasterDirect(
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
            if (comptime Geometry.solver_kind != .newton) {
                std.debug.assert(
                    subpx_scratch.image.rows_num <= std.math.maxInt(u8),
                );
                const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

                return common.rasterDirectScalarCommon(
                    Geometry,
                    ShaderKernel,
                    ShaderData,
                    report_mode,
                    SubpxScratchBuffers,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    mesh_in,
                    subpx_domain,
                    rast_bounds,
                    fields_num,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                );
            }

            return rasterNewton(
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
        }

        fn rasterNewton(
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
            comptime {
                if (Geometry.solver_kind != .newton) {
                    @compileError("rasterNewton only supports Newton geometries");
                }
            }

            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
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
            }

            var seed_state = newton.NewtonSeedState{};

            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;

                for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
                    const scratch_idx = row_offset + scratch_x;
                    const ideal_x_px = subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 0];
                    const ideal_y_px = subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 1];

                    const global_subx = targ_overlap.tile.x_px_min * sub_samp +
                        scratch_x;
                    const global_suby = targ_overlap.tile.y_px_min * sub_samp +
                        scratch_y;

                    var hull_seed: ?newton.NewtonSeed = null;

                    if (comptime Geometry.hull_nodes_num > 0) {
                        ctx_report.recordTessChecks(1);
                        const tess_res = element_tess.isInScalar(ideal_x_px, ideal_y_px);
                        if (tess_res.is_in) {
                            ctx_report.recordTessPasses(1);
                            hull_seed = .{
                                .xi = tess_res.seed_xi,
                                .eta = tess_res.seed_eta,
                            };
                        }
                        if (comptime report_mode == .full_stats) {
                            ctx_report.recordEarlyOut(
                                global_subx,
                                global_suby,
                                tess_res.is_in,
                            );
                        }
                        if (!tess_res.is_in) {
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
                    const result = blk: {
                        if (comptime Geometry.seed_mode == .hull) {
                            if (hull_seed) |seed| {
                                const seed_quality = newton.evaluateSeedQuality(
                                    Geometry.nodes_num,
                                    Geometry.domainViolation,
                                    ideal_x_px - subpx_domain.x_off,
                                    ideal_y_px - subpx_domain.y_off,
                                    nodes_coords.x,
                                    nodes_coords.y,
                                    nodes_coords.z,
                                    seed,
                                );
                                if (!seed_quality.is_usable) {
                                    hull_seed = null;
                                }
                            }
                        }
                        const base_seed = Geometry.initSeed(hull_seed);
                        const selected_seed = newton.selectSeed(
                            Geometry.seed_reuse,
                            base_seed,
                            seed_state,
                        );
                        break :blk Geometry.solveWeightsNewton(
                            nodes_coords,
                            ideal_x_px,
                            ideal_y_px,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            selected_seed.xi,
                            selected_seed.eta,
                        );
                    };

                    ctx_report.recordSolverIters(result.iters);

                    if (comptime Geometry.seed_reuse == .last_converged) {
                        if (result.weights != null) {
                            newton.updateSeedState(
                                &seed_state,
                                result.xi_out,
                                result.eta_out,
                            );
                        }
                    }

                    if (result.weights) |weights| {
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);

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
                }
            }
            return shaded_px;
        }
    };
}
