// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const tol = buildconfig.config.tolerance;
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
const camcommon = @import("camera_common.zig");
const common = @import("rasterengine_common.zig");
const rasterreport = @import("rasterreport.zig");

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


// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const SubpxScratchBuffers = struct {
    stride_subpx: usize,
    inv_z: []F,
    image: MatSlice(F),
    filter_tmp: MatSlice(F),
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pixel_centers: []F,
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;

//------------------------------------------------------------------------------------------
// Scratch Buffer Helpers
//------------------------------------------------------------------------------------------


// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn initSubpxScratch(
    arena_alloc: std.mem.Allocator,
    fields_num: u8,
    subpx_tile_size: usize,
) !SubpxScratchBuffers {
    const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;
    const subpx_inv_z_scratch = try arena_alloc.alloc(F, subpx_tile_total);
    const subpx_img_mem = try arena_alloc.alloc(
        F,
        subpx_tile_total * @as(usize, fields_num),
    );
    const subpx_image_scratch = MatSlice(F).init(
        subpx_img_mem,
        @as(usize, fields_num),
        subpx_tile_total,
    );
    const filter_tmp_mem = try arena_alloc.alloc(
        F,
        subpx_tile_total * @as(usize, fields_num),
    );
    const filter_tmp = MatSlice(F).init(
        filter_tmp_mem,
        @as(usize, fields_num),
        subpx_tile_total,
    );

    const ideal_pixel_centers = try arena_alloc.alloc(F, subpx_tile_total * 2);

    return .{
        .stride_subpx = subpx_tile_size,
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .filter_tmp = filter_tmp,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .ideal_pixel_centers = ideal_pixel_centers,
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffers,
    subpx_tile_size: usize,
    background_value: F,
) void {
    @memset(subpx_scratch.inv_z, -std.math.inf(F));
    @memset(subpx_scratch.image.slice, background_value);
    @memset(subpx_scratch.filter_tmp.slice, background_value);
    @memset(subpx_scratch.touched_min_x, subpx_tile_size);
    @memset(subpx_scratch.touched_max_x, 0);
}

pub fn rasterScene(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
    tiling: rops.TilingOverlaps,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(F),
    image_out_arr: *NDArray(F),
) !void {
    try common.rasterSceneCommon(
        @This(),
        report_mode,
        outer_alloc,
        io,
        ctx_rast,
        ctx_report,
        requested_workers,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );
}

//------------------------------------------------------------------------------------------
// Raster Pass Implementation
//------------------------------------------------------------------------------------------

pub fn RasterEngine(
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
            mesh_in: rops.MeshRaster,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const sub_samp_u: usize = @intCast(ctx_rast.camera.sub_sample);
            const sub_samp_f: F = @as(F, @floatFromInt(ctx_rast.camera.sub_sample));

            const subpx_domain = SubpxDomain{
                .step = 1.0 / sub_samp_f,
                .offset = 1.0 / (2.0 * sub_samp_f),
                .tile_size = subpx_scratch.stride_subpx,
                .x_off = 0.5 * @as(F, @floatFromInt(ctx_rast.camera.pixels_num[0])),
                .y_off = 0.5 * @as(F, @floatFromInt(ctx_rast.camera.pixels_num[1])),
            };

            const scratch_start_x_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.x_min) - targ_overlap.tile.scratch_x_px_min);
            const scratch_end_x_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.x_max) - targ_overlap.tile.scratch_x_px_min);
            const scratch_start_y_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.y_min) - targ_overlap.tile.scratch_y_px_min);
            const scratch_end_y_u = sub_samp_u *
                (@as(usize, targ_overlap.overlap.y_max) - targ_overlap.tile.scratch_y_px_min);

            const rast_bounds = RasterBounds{
                .start_x_u = scratch_start_x_u,
                .end_x_u = scratch_end_x_u,
                .start_y_u = scratch_start_y_u,
                .end_y_u = scratch_end_y_u,
                .x_min_f = @as(F, @floatFromInt(targ_overlap.overlap.x_min)),
                .y_min_f = @as(F, @floatFromInt(targ_overlap.overlap.y_min)),
            };

            const nodes_coords = try rops.loadElemVec3Slices(
                Geometry.nodes_num,
                F,
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
            mesh_in: rops.MeshRaster,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(F),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            if (comptime Geometry == geomkerns.Tri3OptKernel()) {
                return rasterDirectSteppedScalar(
                    Geometry,
                    ShaderKernel,
                    ShaderData,
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
            if (comptime Geometry.solver_kind != .newton) {
                return rasterDirectImpl(
                    Geometry,
                    ShaderKernel,
                    ShaderData,
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

            return rasterNewtonImpl(
                Geometry,
                ShaderKernel,
                ShaderData,
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
            mesh_in: rops.MeshRaster,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(F),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            return rasterNewtonImpl(
                Geometry,
                ShaderKernel,
                ShaderData,
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
    };
}

fn rasterDirectImpl(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
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

fn rasterNewtonImpl(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
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

    var nodes_inv_z: [N]F = undefined;
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
    const ideal_x_plane = camcommon.getIdealXPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );
    const ideal_y_plane = camcommon.getIdealYPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
        const row_offset = scratch_y * subpx_domain.tile_size;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
            const scratch_idx = row_offset + scratch_x;
            const ideal_x_px = ideal_x_plane[scratch_idx];
            const ideal_y_px = ideal_y_plane[scratch_idx];

            const global_subx = targ_overlap.tile.scratch_x_px_min * sub_samp + scratch_x;
            const global_suby = targ_overlap.tile.scratch_y_px_min * sub_samp + scratch_y;

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
                rasterreport.recordEarlyOut(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    tess_res.is_in,
                );
                if (!tess_res.is_in) continue;
            } else {
                rasterreport.recordEarlyOut(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                );
            }

            ctx_report.recordSolverCalls(1);
            const result = blk: {
                if (ctx_rast.config.newton_seed_mode == .hull) {
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
                const base_seed = Geometry.initSeed(
                    ctx_rast.config.newton_seed_mode,
                    hull_seed,
                );
                const selected_seed = newton.selectSeed(
                    ctx_rast.config.newton_seed_reuse,
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
            const solve_state = newton.evaluateSolveState(
                N,
                ideal_x_px - subpx_domain.x_off,
                ideal_y_px - subpx_domain.y_off,
                nodes_coords.x,
                nodes_coords.y,
                nodes_coords.z,
                result.xi_final,
                result.eta_final,
            );
            const domain_violation = Geometry.domainViolation(
                result.xi_final,
                result.eta_final,
            );
            const hit_iter_limit = newton.hitIterLimitStatus(result.status);
            const jacobian_det = newton.calcJacobianDet2D(
                N,
                result.xi_final,
                result.eta_final,
                nodes_coords.x,
                nodes_coords.y,
            );
            if (result.weights == null) {
                if (comptime report_mode == .full_stats) {
                    rasterreport.recordPixelConvergedStats(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        false,
                        result.xi_final,
                        result.eta_final,
                        jacobian_det,
                    );
                    rasterreport.recordPixelSolverDiagnostics(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        result.status,
                        result.pre_domain_converged,
                        hit_iter_limit,
                        solve_state.residual_x,
                        solve_state.residual_y,
                        solve_state.interpolated_w,
                        solve_state.residual_mag,
                        solve_state.normalized_residual_mag,
                        domain_violation,
                    );
                }
                if (result.iters > 0) ctx_report.recordSolverDiverged();
                continue;
            }

            if (comptime report_mode == .full_stats) {
                rasterreport.recordPixelConvergedStats(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                    result.xi_out,
                    result.eta_out,
                    jacobian_det,
                );
                rasterreport.recordPixelSolverDiagnostics(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    result.status,
                    result.pre_domain_converged,
                    hit_iter_limit,
                    solve_state.residual_x,
                    solve_state.residual_y,
                    solve_state.interpolated_w,
                    solve_state.residual_mag,
                    solve_state.normalized_residual_mag,
                    domain_violation,
                );
            }

            if (ctx_rast.config.newton_seed_reuse == .last_converged) {
                newton.updateSeedState(
                    &seed_state,
                    result.xi_out,
                    result.eta_out,
                );
            }

            const weights = result.weights.?;
            const inv_z = Geometry.calcInvZ(nodes_coords, weights);
            if (inv_z + tol.geometry.depth_buffer_inv_z_cmp <
                subpx_scratch.inv_z[scratch_idx]) continue;

            subpx_scratch.inv_z[scratch_idx] = inv_z;
            if (scratch_x < subpx_scratch.touched_min_x[scratch_y]) {
                subpx_scratch.touched_min_x[scratch_y] = scratch_x;
            }
            if (scratch_x > subpx_scratch.touched_max_x[scratch_y]) {
                subpx_scratch.touched_max_x[scratch_y] = scratch_x;
            }
            const subpx_z = 1.0 / inv_z;
            shaded_px += 1;

            rasterreport.recordPixelIterAndOccupancy(
                report_mode,
                ctx_report,
                global_subx,
                global_suby,
                result.iters,
                targ_overlap.tile.scratch_x_px_min + scratch_x / sub_samp,
                targ_overlap.tile.scratch_y_px_min + scratch_y / sub_samp,
            );

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
                .xi = result.xi_out,
                .eta = result.eta_out,
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
    return shaded_px;
}

fn rasterDirectSteppedScalar(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const tile_subx: usize = @intCast(targ_overlap.tile.scratch_x_px_min);
    const tile_suby: usize = @intCast(targ_overlap.tile.scratch_y_px_min);
    const start_subx_global = tile_subx * sub_samp + rast_bounds.start_x_u;
    const start_suby_global = tile_suby * sub_samp + rast_bounds.start_y_u;
    const width = rast_bounds.end_x_u - rast_bounds.start_x_u;
    const height = rast_bounds.end_y_u - rast_bounds.start_y_u;
    const max_x_steps = if (width > 0) width - 1 else 0;
    const max_y_steps = if (height > 0) height - 1 else 0;

    if (common.Tri3FixedEdges.init(
        nodes_coords,
        sub_samp,
        start_subx_global,
        start_suby_global,
        max_x_steps,
        max_y_steps,
    )) |fixed| {
        return rasterDirectSteppedScalarFixed(
            Geometry,
            ShaderKernel,
            ShaderData,
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
            fixed,
        );
    }

    return rasterDirectSteppedScalarFloatFallback(
        Geometry,
        ShaderKernel,
        ShaderData,
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

fn rasterDirectSteppedScalarFixed(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
    fixed: common.Tri3FixedEdges,
) !u64 {
    _ = mesh_in;
    const N = Geometry.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    const x0 = nodes_coords.x[0];
    const y0 = nodes_coords.y[0];
    const x1 = nodes_coords.x[1];
    const y1 = nodes_coords.y[1];
    const x2 = nodes_coords.x[2];
    const y2 = nodes_coords.y[2];
    const area = @mulAdd(
        F,
        x2 - x0,
        y1 - y0,
        -((y2 - y0) * (x1 - x0)),
    );

    const tile_subx: usize = @intCast(targ_overlap.tile.scratch_x_px_min);
    const tile_suby: usize = @intCast(targ_overlap.tile.scratch_y_px_min);
    const tile_subx_off = tile_subx * sub_samp;
    const tile_suby_off = tile_suby * sub_samp;

    const z0 = nodes_coords.z[0];
    const z1 = nodes_coords.z[1];
    const z2 = nodes_coords.z[2];
    const is_const_depth = (z0 == z1 and z1 == z2);
    const inv_z0 = 1.0 / z0;
    const inv_z1 = 1.0 / z1;
    const inv_z2 = 1.0 / z2;
    const nodes_inv_z = [3]F{ inv_z0, inv_z1, inv_z2 };

    const scratch_stride = subpx_domain.tile_size;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * scratch_stride;
        const global_suby = tile_suby_off + scratch_y_u;
        const y_steps: buildconfig.Tri3FixedEdge = @intCast(
            scratch_y_u - rast_bounds.start_y_u,
        );

        var e0 = fixed.start[0] + y_steps * fixed.step_y[0];
        var e1 = fixed.start[1] + y_steps * fixed.step_y[1];
        var e2 = fixed.start[2] + y_steps * fixed.step_y[2];

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const global_subx = tile_subx_off + scratch_x_u;

            rasterreport.recordEarlyOut(
                report_mode,
                ctx_report,
                global_subx,
                global_suby,
                true,
            );

            ctx_report.recordSolverCalls(1);
            ctx_report.recordSolverIters(1);

            if (e0 >= -fixed.edge_tolerance and
                e1 >= -fixed.edge_tolerance and
                e2 >= -fixed.edge_tolerance)
            {
                const w1 = @as(F, @floatFromInt(e1)) * fixed.inv_area;
                const w2 = @as(F, @floatFromInt(e2)) * fixed.inv_area;
                const w0 = 1.0 - w1 - w2;
                const inv_z = if (is_const_depth)
                    inv_z0
                else
                    @mulAdd(
                        F,
                        w0,
                        inv_z0,
                        @mulAdd(F, w1, inv_z1, w2 * inv_z2),
                    );

                if (inv_z + buildconfig.config.tolerance.geometry.depth_buffer_inv_z_cmp >=
                    subpx_scratch.inv_z[scratch_idx])
                {
                    subpx_scratch.inv_z[scratch_idx] = inv_z;
                    if (scratch_x_u < subpx_scratch.touched_min_x[scratch_y_u]) {
                        subpx_scratch.touched_min_x[scratch_y_u] = scratch_x_u;
                    }
                    if (scratch_x_u > subpx_scratch.touched_max_x[scratch_y_u]) {
                        subpx_scratch.touched_max_x[scratch_y_u] = scratch_x_u;
                    }
                    const subpx_z = 1.0 / inv_z;
                    shaded_px += 1;

                    rasterreport.recordPixelIterAndOccupancy(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        1,
                        targ_overlap.tile.scratch_x_px_min + scratch_x_u / sub_samp,
                        targ_overlap.tile.scratch_y_px_min + scratch_y_u / sub_samp,
                    );

                    const weights = [3]F{ w0, w1, w2 };
                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, w1, inv_z1, 0.0) / inv_z;
                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, w2, inv_z2, 0.0) / inv_z;

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelConvergedStats(
                            report_mode,
                            ctx_report,
                            global_subx,
                            global_suby,
                            true,
                            xi,
                            eta,
                            area,
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
                        .xi = xi,
                        .eta = eta,
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
                if (comptime report_mode == .full_stats) {
                    const nan = std.math.nan(F);
                    rasterreport.recordPixelConvergedStats(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        false,
                        nan,
                        nan,
                        nan,
                    );
                }
            }

            e0 += fixed.step_x[0];
            e1 += fixed.step_x[1];
            e2 += fixed.step_x[2];
        }
    }

    return shaded_px;
}

fn rasterDirectSteppedScalarFloatFallback(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    _ = mesh_in;
    const N = Geometry.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    const x0 = nodes_coords.x[0];
    const y0 = nodes_coords.y[0];
    const x1 = nodes_coords.x[1];
    const y1 = nodes_coords.y[1];
    const x2 = nodes_coords.x[2];
    const y2 = nodes_coords.y[2];

    const area = @mulAdd(
        F,
        x2 - x0,
        y1 - y0,
        -((y2 - y0) * (x1 - x0)),
    );
    const inv_area = 1.0 / area;

    const a0 = (y2 - y1) * inv_area;
    const b0 = (x1 - x2) * inv_area;
    const c0 = @mulAdd(
        F,
        x2,
        y1,
        -(x1 * y2),
    ) * inv_area;

    const a1 = (y0 - y2) * inv_area;
    const b1 = (x2 - x0) * inv_area;
    const c1 = @mulAdd(
        F,
        x0,
        y2,
        -(x2 * y0),
    ) * inv_area;

    const a2 = (y1 - y0) * inv_area;
    const b2 = (x0 - x1) * inv_area;
    const c2 = @mulAdd(
        F,
        x1,
        y0,
        -(x0 * y1),
    ) * inv_area;

    const step = subpx_domain.step;
    const offset = subpx_domain.offset;

    const dw0_dx = a0 * step;
    const dw0_dy = b0 * step;
    const dw1_dx = a1 * step;
    const dw1_dy = b1 * step;
    const dw2_dx = a2 * step;
    const dw2_dy = b2 * step;

    const tile_subx: usize = @intCast(targ_overlap.tile.scratch_x_px_min);
    const tile_suby: usize = @intCast(targ_overlap.tile.scratch_y_px_min);
    const tile_subx_off = tile_subx * sub_samp;
    const tile_suby_off = tile_suby * sub_samp;

    const z0 = nodes_coords.z[0];
    const z1 = nodes_coords.z[1];
    const z2 = nodes_coords.z[2];
    const is_const_depth = (z0 == z1 and z1 == z2);
    const inv_z0 = 1.0 / z0;
    const inv_z1 = 1.0 / z1;
    const inv_z2 = 1.0 / z2;
    const nodes_inv_z = [3]F{ inv_z0, inv_z1, inv_z2 };

    const edge_tol = tol.edge.tri_weight_inclusion;

    const start_subx_global = tile_subx_off + rast_bounds.start_x_u;
    const start_suby_global = tile_suby_off + rast_bounds.start_y_u;

    const x_start_f = @mulAdd(
        F,
        @as(F, @floatFromInt(start_subx_global)),
        step,
        offset,
    );
    const y_start_f = @mulAdd(
        F,
        @as(F, @floatFromInt(start_suby_global)),
        step,
        offset,
    );

    const w0_start = @mulAdd(
        F,
        a0,
        x_start_f,
        @mulAdd(F, b0, y_start_f, c0),
    );
    const w1_start = @mulAdd(
        F,
        a1,
        x_start_f,
        @mulAdd(F, b1, y_start_f, c1),
    );
    const w2_start = @mulAdd(
        F,
        a2,
        x_start_f,
        @mulAdd(F, b2, y_start_f, c2),
    );

    const scratch_stride = subpx_domain.tile_size;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * scratch_stride;
        const global_suby = tile_suby_off + scratch_y_u;
        const y_steps = @as(F, @floatFromInt(scratch_y_u - rast_bounds.start_y_u));

        var w0 = @mulAdd(F, y_steps, dw0_dy, w0_start);
        var w1 = @mulAdd(F, y_steps, dw1_dy, w1_start);
        var w2 = @mulAdd(F, y_steps, dw2_dy, w2_start);

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const global_subx = tile_subx_off + scratch_x_u;

            rasterreport.recordEarlyOut(
                report_mode,
                ctx_report,
                global_subx,
                global_suby,
                true,
            );

            ctx_report.recordSolverCalls(1);
            ctx_report.recordSolverIters(1);

            if (w0 >= -edge_tol and w1 >= -edge_tol and w2 >= -edge_tol) {
                const inv_z = if (is_const_depth)
                    inv_z0
                else
                    @mulAdd(
                        F,
                        w0,
                        inv_z0,
                        @mulAdd(F, w1, inv_z1, w2 * inv_z2),
                    );

                if (inv_z + buildconfig.config.tolerance.geometry.depth_buffer_inv_z_cmp >=
                    subpx_scratch.inv_z[scratch_idx])
                {
                    subpx_scratch.inv_z[scratch_idx] = inv_z;
                    if (scratch_x_u < subpx_scratch.touched_min_x[scratch_y_u]) {
                        subpx_scratch.touched_min_x[scratch_y_u] = scratch_x_u;
                    }
                    if (scratch_x_u > subpx_scratch.touched_max_x[scratch_y_u]) {
                        subpx_scratch.touched_max_x[scratch_y_u] = scratch_x_u;
                    }
                    const subpx_z = 1.0 / inv_z;
                    shaded_px += 1;

                    rasterreport.recordPixelIterAndOccupancy(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        1,
                        targ_overlap.tile.scratch_x_px_min + scratch_x_u / sub_samp,
                        targ_overlap.tile.scratch_y_px_min + scratch_y_u / sub_samp,
                    );

                    const weights = [3]F{ w0, w1, w2 };
                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, w1, inv_z1, 0.0) / inv_z;
                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, w2, inv_z2, 0.0) / inv_z;

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelConvergedStats(
                            report_mode,
                            ctx_report,
                            global_subx,
                            global_suby,
                            true,
                            xi,
                            eta,
                            area,
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
                        .xi = xi,
                        .eta = eta,
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
                if (comptime report_mode == .full_stats) {
                    const nan = std.math.nan(F);
                    rasterreport.recordPixelConvergedStats(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        false,
                        nan,
                        nan,
                        nan,
                    );
                }
            }

            w0 += dw0_dx;
            w1 += dw1_dx;
            w2 += dw2_dx;
        }
    }

    return shaded_px;
}
