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
const tol = buildconfig.config.tol;
const cam = @import("camera.zig");
const CameraPrepared = cam.CameraPrepared;
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
const comm = @import("rasterengine_common.zig");
const rasterreport = @import("rasterreport.zig");

const mo = @import("meshpipeline.zig");
const MeshPrepared = mo.MeshPrepared;
const MeshType = mo.MeshType;
const Shader = mo.Shader;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const newton = @import("newton.zig");
const coherent = @import("coherentseed.zig");
const shadekerns = @import("shaderkernels.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const SubpxScratchBuffs = struct {
    pub const exclusive_subpx_target = false;

    stride_subpx: usize,
    inv_z: []F,
    image: MatSlice(F),
    filter_tmp: MatSlice(F),
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pix_cent: []F,
    coherent_caches: []coherent.Cache,

    pub inline fn imageIndex(
        _: *const SubpxScratchBuffs,
        local_idx: usize,
    ) usize {
        return local_idx;
    }
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn initSubpxScratch(
    arena_alloc: std.mem.Allocator,
    fields_num: u8,
    subpx_tile_size: usize,
) !SubpxScratchBuffs {
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

    const ideal_pix_cent = try arena_alloc.alloc(F, subpx_tile_total * 2);

    return .{
        .stride_subpx = subpx_tile_size,
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .filter_tmp = filter_tmp,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .ideal_pix_cent = ideal_pix_cent,
        .coherent_caches = try arena_alloc.alloc(
            coherent.Cache,
            4 * subpx_tile_size,
        ),
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffs,
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
    try comm.rasterSceneComm(
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
// Raster Engine Builder
//------------------------------------------------------------------------------------------
const SubpxDom = comm.SubpxDom;
const RasterBounds = comm.RasterBounds;

pub fn RasterEngine(
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime root_class: rops.RootClass,
) type {
    return RasterEngineFor(
        SubpxScratchBuffs,
        Geom,
        ShaderKern,
        ShaderData,
        root_class,
    );
}

pub fn RasterEngineFor(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime root_class: rops.RootClass,
) type {
    return struct {
        pub fn render(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            tile: rops.ActiveTile,
            overlap: rops.OverlapBBox,
            coords: *const NDArray(F),
            raster_hull: ?*const NDArray(F),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
            subpx_scratch: *ScratchBuffs,
        ) !u64 {
            const sub_samp_u: usize = @intCast(ctx_rast.camera.sub_sample);
            const sub_samp_f: F = @as(F, @floatFromInt(ctx_rast.camera.sub_sample));

            const subpx_dom = SubpxDom{
                .step = 1.0 / sub_samp_f,
                .offset = 1.0 / (2.0 * sub_samp_f),
                .tile_size = subpx_scratch.stride_subpx,
                .x_off = 0.5 * @as(F, @floatFromInt(ctx_rast.camera.pixels_num[0])),
                .y_off = 0.5 * @as(F, @floatFromInt(ctx_rast.camera.pixels_num[1])),
            };

            const overlap_start_x_px = overlap.x_min - tile.scratch_x_px_min;
            const overlap_end_x_px = overlap.x_max - tile.scratch_x_px_min;
            const overlap_start_y_px = overlap.y_min - tile.scratch_y_px_min;
            const overlap_end_y_px = overlap.y_max - tile.scratch_y_px_min;
            const scratch_start_x_u = sub_samp_u * @as(usize, @intCast(overlap_start_x_px));
            const scratch_end_x_u = sub_samp_u * @as(usize, @intCast(overlap_end_x_px));
            const scratch_start_y_u = sub_samp_u * @as(usize, @intCast(overlap_start_y_px));
            const scratch_end_y_u = sub_samp_u * @as(usize, @intCast(overlap_end_y_px));

            const rast_bounds = RasterBounds{
                .start_x_u = scratch_start_x_u,
                .end_x_u = scratch_end_x_u,
                .start_y_u = scratch_start_y_u,
                .end_y_u = scratch_end_y_u,
                .x_min_f = @as(F, @floatFromInt(overlap.x_min)),
                .y_min_f = @as(F, @floatFromInt(overlap.y_min)),
            };

            const nodes_coords = try rops.loadElemVec3Slices(
                Geom.nodes_num,
                F,
                coords,
                overlap.elem_idx,
            );

            const shaded_px = try rasterDirect(
                report_mode,
                ctx_rast,
                ctx_report,
                tile,
                overlap,
                raster_hull,
                subpx_dom,
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
            tile: rops.ActiveTile,
            overlap: rops.OverlapBBox,
            raster_hull: ?*const NDArray(F),
            subpx_dom: SubpxDom,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(F),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
            subpx_scratch: *ScratchBuffs,
        ) !u64 {
            if (comptime Geom == geomkerns.Tri3OptKernel()) {
                return rasterSteppedScal(
                    ScratchBuffs,
                    Geom,
                    ShaderKern,
                    ShaderData,
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    tile,
                    overlap,
                    raster_hull,
                    subpx_dom,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                );
            }
            if (comptime Geom.solver_kind != .newton) {
                return rasterDirectImpl(
                    ScratchBuffs,
                    Geom,
                    ShaderKern,
                    ShaderData,
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    tile,
                    overlap,
                    raster_hull,
                    subpx_dom,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                );
            }

            return (if (comptime root_class == .multi_root)
                rasterNewtonMultiImpl
            else
                rasterNewtonImpl)(
                ScratchBuffs,
                Geom,
                ShaderKern,
                ShaderData,
                report_mode,
                ctx_rast,
                ctx_report,
                tile,
                overlap,
                raster_hull,
                subpx_dom,
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
            tile: rops.ActiveTile,
            overlap: rops.OverlapBBox,
            raster_hull: ?*const NDArray(F),
            subpx_dom: SubpxDom,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(F),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
            subpx_scratch: *ScratchBuffs,
        ) !u64 {
            return rasterNewtonImpl(
                ScratchBuffs,
                Geom,
                ShaderKern,
                ShaderData,
                report_mode,
                ctx_rast,
                ctx_report,
                tile,
                overlap,
                raster_hull,
                subpx_dom,
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
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    return comm.rasterDirectScalComm(
        Geom,
        ShaderKern,
        ShaderData,
        report_mode,
        ScratchBuffs,
        ctx_rast,
        ctx_report,
        tile,
        overlap,
        subpx_dom,
        rast_bounds,
        fields_num,
        nodes_coords,
        shader,
        shader_buf,
        subpx_scratch,
    );
}

fn rasterNewtonImpl(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    raster_hull: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    comptime {
        if (Geom.solver_kind != .newton) {
            @compileError("rasterNewton only supps Newton geometries");
        }
    }

    const N = Geom.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    }

    var elem_tess: hull.Tessellation(Geom.tess_triangles_num) = undefined;
    if (comptime Geom.hull_nodes_num > 0) {
        if (raster_hull) |rh| {
            const hx = rh.getSlice(
                &[_]usize{ overlap.elem_idx, 0, 0 },
                1,
            );
            const hy = rh.getSlice(
                &[_]usize{ overlap.elem_idx, 1, 0 },
                1,
            );
            elem_tess = hull.getTessellation(
                N,
                Geom.hull_nodes_num,
                Geom.tess_triangles_num,
                hx,
                hy,
            );
        }
    }

    var seed_state = newton.NewtonSeedState{};
    const ideal_x_plane = cam.getIdealXPlaneScratch(
        subpx_scratch.ideal_pix_cent,
    );
    const ideal_y_plane = cam.getIdealYPlaneScratch(
        subpx_scratch.ideal_pix_cent,
    );

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
        const row_offset = scratch_y * subpx_dom.tile_size;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
            const scratch_idx = row_offset + scratch_x;
            const ideal_x_pix = ideal_x_plane[scratch_idx];
            const ideal_y_pix = ideal_y_plane[scratch_idx];

            const global_subx = comm.globalSubpxForReport(
                tile.scratch_x_px_min,
                sub_samp,
                scratch_x,
            );
            const global_suby = comm.globalSubpxForReport(
                tile.scratch_y_px_min,
                sub_samp,
                scratch_y,
            );

            var hull_seed: ?newton.NewtonSeed = null;
            if (comptime Geom.hull_nodes_num > 0) {
                ctx_report.recordTessChecks(1);
                const tess_res = elem_tess.isInScalar(ideal_x_pix, ideal_y_pix);
                if (tess_res.is_in) {
                    ctx_report.recordTessPasses(1);
                    hull_seed = .{
                        .xi = tess_res.seed_xi,
                        .eta = tess_res.seed_eta,
                    };
                }
                if (comptime report_mode == .full_stats) {
                    rasterreport.recordEarlyOut(
                        ctx_report,
                        global_subx,
                        global_suby,
                        tess_res.is_in,
                    );
                }
                if (!tess_res.is_in) continue;
            } else {
                if (comptime report_mode == .full_stats) {
                    rasterreport.recordEarlyOut(
                        ctx_report,
                        global_subx,
                        global_suby,
                        true,
                    );
                }
            }

            ctx_report.recordSolverCalls(1);
            const result = blk: {
                if (ctx_rast.config.advanced.solver.one_root.mode == .hull) {
                    if (hull_seed) |seed| {
                        const seed_quality = newton.evaluateSeedQuality(
                            Geom.nodes_num,
                            Geom.domViolation,
                            ideal_x_pix - subpx_dom.x_off,
                            ideal_y_pix - subpx_dom.y_off,
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
                const base_seed = Geom.initSeed(
                    ctx_rast.config.advanced.solver.one_root.mode,
                    hull_seed,
                );
                const selected_seed = newton.selectSeed(
                    ctx_rast.config.advanced.solver.one_root.reuse,
                    base_seed,
                    seed_state,
                );
                break :blk Geom.solveWeightsNewton(
                    nodes_coords,
                    ideal_x_pix,
                    ideal_y_pix,
                    subpx_dom.x_off,
                    subpx_dom.y_off,
                    selected_seed.xi,
                    selected_seed.eta,
                );
            };

            ctx_report.recordSolverIters(result.iters);
            const solve_state = newton.evaluateSolveState(
                N,
                ideal_x_pix - subpx_dom.x_off,
                ideal_y_pix - subpx_dom.y_off,
                nodes_coords.x,
                nodes_coords.y,
                nodes_coords.z,
                result.xi_final,
                result.eta_final,
            );
            const dom_violation = Geom.domViolation(
                result.xi_final,
                result.eta_final,
            );
            const hit_iter_lim = newton.hitIterLimitStatus(result.status);
            const jac_det = newton.calcJacDet2D(
                N,
                result.xi_final,
                result.eta_final,
                nodes_coords.x,
                nodes_coords.y,
            );

            if (result.weights == null) {
                if (comptime report_mode == .full_stats) {
                    rasterreport.recordPixelConvStats(
                        ctx_report,
                        global_subx,
                        global_suby,
                        false,
                        result.xi_final,
                        result.eta_final,
                        jac_det,
                    );

                    rasterreport.recordPixelSolverDiagnostics(
                        ctx_report,
                        global_subx,
                        global_suby,
                        result.status,
                        result.pre_dom_conv,
                        hit_iter_lim,
                        solve_state.resid_x,
                        solve_state.resid_y,
                        solve_state.interp_w,
                        solve_state.resid_mag,
                        solve_state.norm_resid_mag,
                        dom_violation,
                    );
                }
                if (result.iters > 0) ctx_report.recordSolverDiverged();
                continue;
            }

            if (comptime report_mode == .full_stats) {
                rasterreport.recordPixelConvStats(
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                    result.xi_out,
                    result.eta_out,
                    jac_det,
                );
                rasterreport.recordPixelSolverDiagnostics(
                    ctx_report,
                    global_subx,
                    global_suby,
                    result.status,
                    result.pre_dom_conv,
                    hit_iter_lim,
                    solve_state.resid_x,
                    solve_state.resid_y,
                    solve_state.interp_w,
                    solve_state.resid_mag,
                    solve_state.norm_resid_mag,
                    dom_violation,
                );
            }

            if (ctx_rast.config.advanced.solver.one_root.reuse == .last_conv) {
                newton.updateSeedState(
                    &seed_state,
                    result.xi_out,
                    result.eta_out,
                );
            }

            const weights = result.weights.?;
            const inv_z = Geom.calcInvZ(nodes_coords, weights);
            if (inv_z + tol.geometry.depth_buff_inv_z_cmp <
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

            if (comptime report_mode == .full_stats) {
                rasterreport.recordPixelIterAndOccupancy(
                    ctx_report,
                    global_subx,
                    global_suby,
                    result.iters,
                    @intCast(@max(0, tile.scratch_x_px_min + @as(
                        i32,
                        @intCast(scratch_x / sub_samp),
                    ))),
                    @intCast(@max(0, tile.scratch_y_px_min + @as(
                        i32,
                        @intCast(scratch_y / sub_samp),
                    ))),
                );
            }

            const ctx_shade = shaderops.ShadeContext{
                .frame_idx = ctx_rast.frame_idx,
                .elem_idx = overlap.elem_idx,
                .fields_num = fields_num,
                .actual_fields = fields_num,
                .scratch_idx = subpx_scratch.imageIndex(scratch_idx),
                .global_subx = global_subx,
                .global_suby = global_suby,
            };
            const interp_data = shaderops.InterpData(N){
                .weights = weights,
                .nodes_inv_z = nodes_inv_z,
                .sub_pixel_z = subpx_z,
                .xi = result.xi_out,
                .eta = result.eta_out,
            };

            ShaderKern.shade(
                Geom.coord_space,
                ctx_shade,
                interp_data,
                shader_buf,
                shader,
                ctx_report,
                &subpx_scratch.image,
            );
        }
    }
    return shaded_px;
}

fn solveMultiRootSeedScal(
    comptime Geom: type,
    comptime report_mode: ReportMode,
    ctx_report: report.ReportContext(report_mode),
    nodes_coords: Vec3Slices(F),
    ideal_x: F,
    ideal_y: F,
    x_off: F,
    y_off: F,
    seed: [2]F,
    frozen: bool,
) ?struct {
    weights: [Geom.nodes_num]F,
    xi: F,
    eta: F,
    inv_z: F,
} {
    const start = if (frozen)
        newton.refineSeedFrozenScal(
            Geom.nodes_num,
            ideal_x - x_off,
            ideal_y - y_off,
            nodes_coords.x,
            nodes_coords.y,
            nodes_coords.z,
            .{ .xi = seed[0], .eta = seed[1] },
            .{ .max_iters = 1, .handoff_tol_mult = 0 },
        ).seed
    else
        newton.NewtonSeed{ .xi = seed[0], .eta = seed[1] };
    const retry = frozen and
        (start.xi != seed[0] or start.eta != seed[1]);
    for (0..@as(usize, if (retry) 2 else 1)) |pass| {
        const uv = if (pass == 0) start else newton.NewtonSeed{ .xi = seed[0], .eta = seed[1] };
        ctx_report.recordSolverCalls(1);
        const result = Geom.solveWeightsNewton(
            nodes_coords,
            ideal_x,
            ideal_y,
            x_off,
            y_off,
            uv.xi,
            uv.eta,
        );
        ctx_report.recordSolverIters(result.iters);
        const weights = result.weights orelse {
            if (result.iters > 0) ctx_report.recordSolverDiverged();
            continue;
        };
        if (!std.math.isFinite(result.xi_out) or
            !std.math.isFinite(result.eta_out) or
            Geom.domViolation(result.xi_out, result.eta_out) > 0)
        {
            continue;
        }
        const state = newton.evaluateSolveState(
            Geom.nodes_num,
            ideal_x - x_off,
            ideal_y - y_off,
            nodes_coords.x,
            nodes_coords.y,
            nodes_coords.z,
            result.xi_out,
            result.eta_out,
        );
        if (!std.math.isFinite(state.norm_resid_mag) or
            state.norm_resid_mag > tol.newton.norm_resid)
        {
            continue;
        }
        const facing = rops.projectedJacDetPhysical(
            Geom.nodes_num,
            nodes_coords,
            result.xi_out,
            result.eta_out,
        );
        if (!std.math.isFinite(facing) or
            facing >= -tol.culling.projected_jacobian_abs)
        {
            continue;
        }
        const inv_z = Geom.calcInvZ(nodes_coords, weights);
        if (!std.math.isFinite(inv_z) or inv_z <= 0) continue;
        return .{
            .weights = weights,
            .xi = result.xi_out,
            .eta = result.eta_out,
            .inv_z = inv_z,
        };
    }
    return null;
}

fn rasterNewtonMultiImpl(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    raster_hull: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const method = ctx_rast.config.advanced.solver.multi_root.method;
    return switch (method) {
        .legacy_depth, .legacy_front => rasterNewtonMultiMode(
            false,
            ScratchBuffs,
            Geom,
            ShaderKern,
            ShaderData,
            report_mode,
            ctx_rast,
            ctx_report,
            tile,
            overlap,
            raster_hull,
            subpx_dom,
            rast_bounds,
            nodes_coords,
            shader,
            shader_buf,
            subpx_scratch,
        ),
        .fixed4,
        .fixed4_reuse,
        .fixed4_centre_reuse,
        .fixed16,
        .adaptive,
        .patch_center,
        .patch_reuse,
        .patch_reuse_seedbank,
        .patch_extrapolate,
        .patch_extrapolate_seedbank,
        .all_seeds,
        => rasterNewtonMultiMode(
            true,
            ScratchBuffs,
            Geom,
            ShaderKern,
            ShaderData,
            report_mode,
            ctx_rast,
            ctx_report,
            tile,
            overlap,
            raster_hull,
            subpx_dom,
            rast_bounds,
            nodes_coords,
            shader,
            shader_buf,
            subpx_scratch,
        ),
    };
}

fn rasterNewtonMultiMode(
    comptime use_hierarchy: bool,
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    raster_hull: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const N = Geom.nodes_num;
    const method = ctx_rast.config.advanced.solver.multi_root.method;
    const use_coherent = switch (method) {
        .fixed4_reuse,
        .fixed4_centre_reuse,
        .patch_center,
        .patch_reuse,
        .patch_reuse_seedbank,
        .patch_extrapolate,
        .patch_extrapolate_seedbank,
        .all_seeds,
        => true,
        else => false,
    };
    const extrapolate = method == .patch_extrapolate or
        method == .patch_extrapolate_seedbank;
    const all_seeds = method == .all_seeds;
    const use_bank = method == .patch_reuse_seedbank or
        method == .patch_extrapolate_seedbank or all_seeds or
        ctx_rast.config.advanced.solver.multi_root.legacy_fallback;
    var coherent_stats = report.CoherentStats{};
    if (use_coherent) {
        @memset(subpx_scratch.coherent_caches, .{});
    }
    _ = raster_hull;
    if (ctx_rast.multi_root_by_mesh.len <= overlap.mesh_idx) {
        return error.MissingMultiRootData;
    }
    const prepared = ctx_rast.multi_root_by_mesh[overlap.mesh_idx] orelse
        return error.MissingMultiRootData;
    const slot = prepared.slot_by_visible_elem.get(overlap.elem_idx);
    if (slot == std.math.maxInt(u32)) return error.MissingMultiRootData;
    const hull_count = prepared.hull_count.get(slot);
    const hx = prepared.hull_x.getSlice(slot)[0..hull_count];
    const hy = prepared.hull_y.getSlice(slot)[0..hull_count];
    var edge_slack: [9]F = undefined;
    hull.prepareMultiRootEdgeSlack(hx, hy, edge_slack[0..hull_count]);
    const seed_count = prepared.valid_depth.get(slot);
    const seeds = prepared.indices.getSlice(slot)[0..seed_count];
    const leaves = if (comptime use_hierarchy) blk: {
        const start: usize = prepared.leaf_start[slot];
        const count: usize = prepared.leaf_count[slot];
        break :blk prepared.leaves[start .. start + count];
    } else &.{};
    var seed_uvs: [geomkerns.multiRootSeedCount(N)][2]F = undefined;
    for (seeds, 0..) |seed_idx, ii| {
        seed_uvs[ii] = geomkerns.multiRootSeedCoords(N, seed_idx);
    }
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);
    const ideal_x_plane = cam.getIdealXPlaneScratch(subpx_scratch.ideal_pix_cent);
    const ideal_y_plane = cam.getIdealYPlaneScratch(subpx_scratch.ideal_pix_cent);
    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    var shaded_px: u64 = 0;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
        const row_offset = scratch_y * subpx_dom.tile_size;
        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
            const scratch_idx = row_offset + scratch_x;
            const ideal_x = ideal_x_plane[scratch_idx];
            const ideal_y = ideal_y_plane[scratch_idx];
            const global_subx = comm.globalSubpxForReport(
                tile.scratch_x_px_min,
                sub_samp,
                scratch_x,
            );
            const global_suby = comm.globalSubpxForReport(
                tile.scratch_y_px_min,
                sub_samp,
                scratch_y,
            );
            var best_inv_z: F = -std.math.inf(F);
            var best_weights: ?[N]F = null;
            var best_xi: F = 0;
            var best_eta: F = 0;
            const has_hit = hull.containsMultiRootHullPrepared(
                hx,
                hy,
                edge_slack[0..hull_count],
                ideal_x,
                ideal_y,
            );
            if (comptime use_hierarchy) {
                if (has_hit) {
                    var candidate_count: usize = 0;
                    for (leaves, 0..) |*leaf, leaf_idx| {
                        if (!leaf.contains(ideal_x, ideal_y)) continue;
                        candidate_count += 1;
                        if (use_coherent) {
                            coherent_stats.candidate_children += 1;
                            const cache_idx = leaf_idx * subpx_dom.tile_size +
                                scratch_x;
                            const cache = &subpx_scratch.coherent_caches[cache_idx];
                            const child_caches = subpx_scratch.coherent_caches[leaf_idx * subpx_dom.tile_size .. (leaf_idx + 1) * subpx_dom.tile_size];
                            const center_first = method == .patch_center or
                                method == .fixed4_centre_reuse;
                            var choice = if (center_first)
                                coherent.Choice{
                                    .uv = leaf.seed,
                                    .kind = .center,
                                }
                            else if (method == .fixed4_reuse)
                                coherent.chooseLocal(
                                    child_caches,
                                    scratch_x,
                                    scratch_y,
                                    ctx_rast.config.advanced.solver.multi_root.reuse_radius_rows,
                                    ctx_rast.config.advanced.solver.multi_root.reuse_method,
                                    leaf.seed,
                                )
                            else
                                cache.choose(
                                    scratch_y,
                                    ctx_rast.config.advanced.solver.multi_root.reuse_radius_rows,
                                    extrapolate,
                                    leaf.seed,
                                );
                            if (choice.kind == .extrapolate and
                                !leaf.containsParent(N, choice.uv[0], choice.uv[1]))
                            {
                                choice = .{
                                    .uv = cache.last_uv,
                                    .kind = .reuse,
                                };
                            }
                            if (method == .fixed4_reuse and
                                choice.kind != .center and
                                !leaf.containsParent(N, choice.uv[0], choice.uv[1]))
                            {
                                choice = .{ .uv = leaf.seed, .kind = .center };
                            }
                            var local_hit = false;
                            if (choice.kind != .center) {
                                coherent_stats.cache_eligible += 1;
                                coherent_stats.cache_attempts += 1;
                                if (choice.kind == .extrapolate) {
                                    coherent_stats.extrap_attempts += 1;
                                }
                                if (solveMultiRootSeedScal(
                                    Geom,
                                    report_mode,
                                    ctx_report,
                                    nodes_coords,
                                    ideal_x,
                                    ideal_y,
                                    subpx_dom.x_off,
                                    subpx_dom.y_off,
                                    choice.uv,
                                    false,
                                )) |hit| {
                                    local_hit = leaf.containsParent(
                                        N,
                                        hit.xi,
                                        hit.eta,
                                    );
                                    if (local_hit) {
                                        cache.update(
                                            scratch_y,
                                            .{ hit.xi, hit.eta },
                                            hit.inv_z,
                                        );
                                        coherent_stats.cache_successes += 1;
                                        if (choice.kind == .extrapolate) {
                                            coherent_stats.extrap_successes += 1;
                                        }
                                    } else {
                                        coherent_stats.cross_child += 1;
                                    }
                                    if (hit.inv_z > best_inv_z) {
                                        best_inv_z = hit.inv_z;
                                        best_weights = hit.weights;
                                        best_xi = hit.xi;
                                        best_eta = hit.eta;
                                    }
                                }
                                if (!local_hit) coherent_stats.cache_failures += 1;
                            }
                            if (choice.kind == .center or
                                (!local_hit and method != .fixed4_reuse) or
                                all_seeds)
                            {
                                coherent_stats.center_attempts += 1;
                                if (solveMultiRootSeedScal(
                                    Geom,
                                    report_mode,
                                    ctx_report,
                                    nodes_coords,
                                    ideal_x,
                                    ideal_y,
                                    subpx_dom.x_off,
                                    subpx_dom.y_off,
                                    leaf.seed,
                                    false,
                                )) |hit| {
                                    coherent_stats.center_successes += 1;
                                    if (leaf.containsParent(N, hit.xi, hit.eta)) {
                                        local_hit = true;
                                        cache.update(
                                            scratch_y,
                                            .{ hit.xi, hit.eta },
                                            hit.inv_z,
                                        );
                                    } else {
                                        coherent_stats.cross_child += 1;
                                    }
                                    if (hit.inv_z > best_inv_z) {
                                        best_inv_z = hit.inv_z;
                                        best_weights = hit.weights;
                                        best_xi = hit.xi;
                                        best_eta = hit.eta;
                                    }
                                }
                            }
                            if (method == .fixed4_centre_reuse and !local_hit) {
                                coherent_stats.center_failures += 1;
                                choice = coherent.chooseLocal(
                                    child_caches,
                                    scratch_x,
                                    scratch_y,
                                    ctx_rast.config.advanced.solver.multi_root.reuse_radius_rows,
                                    ctx_rast.config.advanced.solver.multi_root.reuse_method,
                                    leaf.seed,
                                );
                                if (choice.kind != .center and
                                    leaf.containsParent(N, choice.uv[0], choice.uv[1]))
                                {
                                    coherent_stats.cache_eligible += 1;
                                    coherent_stats.cache_attempts += 1;
                                    if (solveMultiRootSeedScal(
                                        Geom,
                                        report_mode,
                                        ctx_report,
                                        nodes_coords,
                                        ideal_x,
                                        ideal_y,
                                        subpx_dom.x_off,
                                        subpx_dom.y_off,
                                        choice.uv,
                                        false,
                                    )) |hit| {
                                        const in_child = leaf.containsParent(
                                            N,
                                            hit.xi,
                                            hit.eta,
                                        );
                                        if (in_child) {
                                            cache.update(
                                                scratch_y,
                                                .{ hit.xi, hit.eta },
                                                hit.inv_z,
                                            );
                                            coherent_stats.cache_successes += 1;
                                            coherent_stats.reuse_recoveries += 1;
                                        } else {
                                            coherent_stats.cross_child += 1;
                                        }
                                        if (hit.inv_z > best_inv_z) {
                                            best_inv_z = hit.inv_z;
                                            best_weights = hit.weights;
                                            best_xi = hit.xi;
                                            best_eta = hit.eta;
                                        }
                                        if (!in_child) coherent_stats.cache_failures += 1;
                                    } else coherent_stats.cache_failures += 1;
                                }
                            }
                            continue;
                        }
                        const hit = solveMultiRootSeedScal(
                            Geom,
                            report_mode,
                            ctx_report,
                            nodes_coords,
                            ideal_x,
                            ideal_y,
                            subpx_dom.x_off,
                            subpx_dom.y_off,
                            leaf.seed,
                            ctx_rast.config.advanced.solver.multi_root.single_frozen_jac,
                        ) orelse continue;
                        if (hit.inv_z <= best_inv_z) continue;
                        best_inv_z = hit.inv_z;
                        best_weights = hit.weights;
                        best_xi = hit.xi;
                        best_eta = hit.eta;
                    }
                    if (candidate_count > 0 and
                        (all_seeds or (best_weights == null and use_bank)))
                    {
                        const before_bank = best_inv_z;
                        const had_hit = best_weights != null;
                        coherent_stats.bank_fallbacks += 1;
                        for (seed_uvs[0..seeds.len]) |seed| {
                            const hit = solveMultiRootSeedScal(
                                Geom,
                                report_mode,
                                ctx_report,
                                nodes_coords,
                                ideal_x,
                                ideal_y,
                                subpx_dom.x_off,
                                subpx_dom.y_off,
                                seed,
                                false,
                            ) orelse continue;
                            if (hit.inv_z <= best_inv_z) continue;
                            best_inv_z = hit.inv_z;
                            best_weights = hit.weights;
                            best_xi = hit.xi;
                            best_eta = hit.eta;
                        }
                        if (best_weights != null and !had_hit) {
                            coherent_stats.bank_fallback_successes += 1;
                            coherent_stats.bank_recovered += 1;
                        } else if (best_inv_z > before_bank) {
                            if (coherent.distinctDepthGain(
                                before_bank,
                                best_inv_z,
                            )) {
                                coherent_stats.bank_fallback_successes += 1;
                                coherent_stats.bank_improved += 1;
                            } else {
                                coherent_stats.bank_numerical_ties += 1;
                            }
                        }
                    }
                }
            } else if (has_hit) for (seeds, 0..) |_, pass| {
                const seed = seed_uvs[pass];
                ctx_report.recordSolverCalls(1);
                const result = Geom.solveWeightsNewton(
                    nodes_coords,
                    ideal_x,
                    ideal_y,
                    subpx_dom.x_off,
                    subpx_dom.y_off,
                    seed[0],
                    seed[1],
                );
                ctx_report.recordSolverIters(result.iters);
                const weights = result.weights orelse {
                    if (result.iters > 0) ctx_report.recordSolverDiverged();
                    continue;
                };
                if (!std.math.isFinite(result.xi_out) or
                    !std.math.isFinite(result.eta_out) or
                    Geom.domViolation(result.xi_out, result.eta_out) > 0)
                {
                    continue;
                }
                const state = newton.evaluateSolveState(
                    N,
                    ideal_x - subpx_dom.x_off,
                    ideal_y - subpx_dom.y_off,
                    nodes_coords.x,
                    nodes_coords.y,
                    nodes_coords.z,
                    result.xi_out,
                    result.eta_out,
                );
                if (!std.math.isFinite(state.norm_resid_mag) or
                    state.norm_resid_mag > tol.newton.norm_resid)
                {
                    continue;
                }
                const facing = rops.projectedJacDetPhysical(
                    N,
                    nodes_coords,
                    result.xi_out,
                    result.eta_out,
                );
                if (!std.math.isFinite(facing) or
                    facing >= -tol.culling.projected_jacobian_abs)
                {
                    continue;
                }
                const inv_z = Geom.calcInvZ(nodes_coords, weights);
                if (!std.math.isFinite(inv_z) or inv_z <= 0 or
                    inv_z <= best_inv_z)
                {
                    continue;
                }
                best_inv_z = inv_z;
                best_weights = weights;
                best_xi = result.xi_out;
                best_eta = result.eta_out;
                if (pass == 0) break;
            };
            ctx_report.recordTessChecks(1);
            if (has_hit) ctx_report.recordTessPasses(1);
            if (comptime report_mode == .full_stats) {
                rasterreport.recordEarlyOut(
                    ctx_report,
                    global_subx,
                    global_suby,
                    has_hit,
                );
            }
            const weights = best_weights orelse continue;
            if (best_inv_z + tol.geometry.depth_buff_inv_z_cmp <
                subpx_scratch.inv_z[scratch_idx]) continue;
            subpx_scratch.inv_z[scratch_idx] = best_inv_z;
            subpx_scratch.touched_min_x[scratch_y] =
                @min(subpx_scratch.touched_min_x[scratch_y], scratch_x);
            subpx_scratch.touched_max_x[scratch_y] =
                @max(subpx_scratch.touched_max_x[scratch_y], scratch_x);
            shaded_px += 1;
            const ctx_shade = shaderops.ShadeContext{
                .frame_idx = ctx_rast.frame_idx,
                .elem_idx = overlap.elem_idx,
                .fields_num = fields_num,
                .actual_fields = fields_num,
                .scratch_idx = subpx_scratch.imageIndex(scratch_idx),
                .global_subx = global_subx,
                .global_suby = global_suby,
            };
            const interp_data = shaderops.InterpData(N){
                .weights = weights,
                .nodes_inv_z = nodes_inv_z,
                .sub_pixel_z = 1.0 / best_inv_z,
                .xi = best_xi,
                .eta = best_eta,
            };
            ShaderKern.shade(
                Geom.coord_space,
                ctx_shade,
                interp_data,
                shader_buf,
                shader,
                ctx_report,
                &subpx_scratch.image,
            );
        }
    }
    if (use_coherent) ctx_report.recordCoherentStats(coherent_stats);
    return shaded_px;
}

fn rasterSteppedScal(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    raster_hull: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const tile_subpx_x = @as(isize, tile.scratch_x_px_min) *
        @as(isize, @intCast(sub_samp));
    const tile_subpx_y = @as(isize, tile.scratch_y_px_min) *
        @as(isize, @intCast(sub_samp));
    const start_subx_global = tile_subpx_x + @as(isize, @intCast(rast_bounds.start_x_u));
    const start_suby_global = tile_subpx_y + @as(isize, @intCast(rast_bounds.start_y_u));
    const width = rast_bounds.end_x_u - rast_bounds.start_x_u;
    const height = rast_bounds.end_y_u - rast_bounds.start_y_u;
    const max_x_steps = if (width > 0) width - 1 else 0;
    const max_y_steps = if (height > 0) height - 1 else 0;

    if (comm.Tri3FixedEdges.init(
        nodes_coords,
        sub_samp,
        start_subx_global,
        start_suby_global,
        max_x_steps,
        max_y_steps,
    )) |fixed| {
        return rasterSteppedScalFixP(
            ScratchBuffs,
            Geom,
            ShaderKern,
            ShaderData,
            report_mode,
            ctx_rast,
            ctx_report,
            tile,
            overlap,
            raster_hull,
            subpx_dom,
            rast_bounds,
            nodes_coords,
            shader,
            shader_buf,
            subpx_scratch,
            fixed,
        );
    }

    return rasterSteppedScalFloat(
        ScratchBuffs,
        Geom,
        ShaderKern,
        ShaderData,
        report_mode,
        ctx_rast,
        ctx_report,
        tile,
        overlap,
        raster_hull,
        subpx_dom,
        rast_bounds,
        nodes_coords,
        shader,
        shader_buf,
        subpx_scratch,
    );
}

fn rasterSteppedScalFixP(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
    fixed: comm.Tri3FixedEdges,
) !u64 {
    const N = Geom.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    var x: [3]F = undefined;
    var y: [3]F = undefined;
    var z: [3]F = undefined;
    var inv_z_node: [3]F = undefined;
    inline for (0..3) |nn| {
        x[nn] = nodes_coords.x[nn];
        y[nn] = nodes_coords.y[nn];
        z[nn] = nodes_coords.z[nn];
        inv_z_node[nn] = 1.0 / z[nn];
    }
    const dx: [2]F = .{ x[2] - x[0], x[1] - x[0] };
    const dy: [2]F = .{ y[1] - y[0], y[2] - y[0] };
    const area_cross = -(dy[1] * dx[1]);
    const area = @mulAdd(F, dx[0], dy[0], area_cross);

    const is_const_depth = z[0] == z[1] and z[1] == z[2];
    const nodes_inv_z = inv_z_node;

    const scratch_stride = subpx_dom.tile_size;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * scratch_stride;
        const global_suby = comm.globalSubpxForReport(
            tile.scratch_y_px_min,
            sub_samp,
            scratch_y_u,
        );
        const y_steps: buildconfig.Tri3FixedEdge = @intCast(
            scratch_y_u - rast_bounds.start_y_u,
        );

        var edge: [3]buildconfig.Tri3FixedEdge = undefined;
        inline for (0..3) |nn| {
            edge[nn] = fixed.start[nn] + y_steps * fixed.step_y[nn];
        }

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const global_subx = comm.globalSubpxForReport(
                tile.scratch_x_px_min,
                sub_samp,
                scratch_x_u,
            );

            if (comptime report_mode == .full_stats) {
                rasterreport.recordEarlyOut(
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                );
            }

            ctx_report.recordSolverCalls(1);
            ctx_report.recordSolverIters(1);

            if (edge[0] >= -fixed.edge_tol and
                edge[1] >= -fixed.edge_tol and
                edge[2] >= -fixed.edge_tol)
            {
                var weights: [3]F = undefined;
                weights[1] = @as(F, @floatFromInt(edge[1])) * fixed.inv_area;
                weights[2] = @as(F, @floatFromInt(edge[2])) * fixed.inv_area;
                weights[0] = 1.0 - weights[1] - weights[2];
                const inv_z_sum = @mulAdd(
                    F,
                    weights[1],
                    inv_z_node[1],
                    weights[2] * inv_z_node[2],
                );
                const inv_z = if (is_const_depth)
                    inv_z_node[0]
                else
                    @mulAdd(F, weights[0], inv_z_node[0], inv_z_sum);

                if (inv_z + buildconfig.config.tol.geometry.depth_buff_inv_z_cmp >=
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

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelIterAndOccupancy(
                            ctx_report,
                            global_subx,
                            global_suby,
                            1,
                            @intCast(@max(0, tile.scratch_x_px_min + @as(
                                i32,
                                @intCast(scratch_x_u / sub_samp),
                            ))),
                            @intCast(@max(0, tile.scratch_y_px_min + @as(
                                i32,
                                @intCast(scratch_y_u / sub_samp),
                            ))),
                        );
                    }

                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, weights[1], inv_z_node[1], 0.0) / inv_z;

                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, weights[2], inv_z_node[2], 0.0) / inv_z;

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelConvStats(
                            ctx_report,
                            global_subx,
                            global_suby,
                            true,
                            xi,
                            eta,
                            area,
                        );
                    }

                    const ctx_shade = shaderops.ShadeContext{
                        .frame_idx = ctx_rast.frame_idx,
                        .elem_idx = overlap.elem_idx,
                        .fields_num = fields_num,
                        .actual_fields = fields_num,
                        .scratch_idx = subpx_scratch.imageIndex(scratch_idx),
                        .global_subx = global_subx,
                        .global_suby = global_suby,
                    };

                    const interp_data = shaderops.InterpData(N){
                        .weights = weights,
                        .nodes_inv_z = nodes_inv_z,
                        .sub_pixel_z = subpx_z,
                        .xi = xi,
                        .eta = eta,
                    };

                    ShaderKern.shade(
                        Geom.coord_space,
                        ctx_shade,
                        interp_data,
                        shader_buf,
                        shader,
                        ctx_report,
                        &subpx_scratch.image,
                    );
                }
            } else {
                if (comptime report_mode == .full_stats) {
                    const nan = std.math.nan(F);
                    rasterreport.recordPixelConvStats(
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

            inline for (0..3) |nn| {
                edge[nn] += fixed.step_x[nn];
            }
        }
    }

    return shaded_px;
}

fn rasterSteppedScalFloat(
    comptime ScratchBuffs: type,
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const N = Geom.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    var x: [3]F = undefined;
    var y: [3]F = undefined;
    var z: [3]F = undefined;
    var inv_z_node: [3]F = undefined;
    inline for (0..3) |nn| {
        x[nn] = nodes_coords.x[nn];
        y[nn] = nodes_coords.y[nn];
        z[nn] = nodes_coords.z[nn];
        inv_z_node[nn] = 1.0 / z[nn];
    }

    const dx: [2]F = .{ x[2] - x[0], x[1] - x[0] };
    const dy: [2]F = .{ y[1] - y[0], y[2] - y[0] };
    const area_cross = -(dy[1] * dx[1]);
    const area = @mulAdd(F, dx[0], dy[0], area_cross);
    const inv_area = 1.0 / area;

    var a: [3]F = undefined;
    var b: [3]F = undefined;
    var c: [3]F = undefined;
    a[0] = (y[2] - y[1]) * inv_area;
    a[1] = (y[0] - y[2]) * inv_area;
    a[2] = (y[1] - y[0]) * inv_area;
    b[0] = (x[1] - x[2]) * inv_area;
    b[1] = (x[2] - x[0]) * inv_area;
    b[2] = (x[0] - x[1]) * inv_area;
    c[0] = @mulAdd(F, x[2], y[1], -(x[1] * y[2])) * inv_area;
    c[1] = @mulAdd(F, x[0], y[2], -(x[2] * y[0])) * inv_area;
    c[2] = @mulAdd(F, x[1], y[0], -(x[0] * y[1])) * inv_area;

    const step = subpx_dom.step;
    const offset = subpx_dom.offset;

    var dw_dx: [3]F = undefined;
    var dw_dy: [3]F = undefined;
    inline for (0..3) |nn| {
        dw_dx[nn] = a[nn] * step;
        dw_dy[nn] = b[nn] * step;
    }

    const tile_subx_off = @as(isize, tile.scratch_x_px_min) *
        @as(isize, @intCast(sub_samp));
    const tile_suby_off = @as(isize, tile.scratch_y_px_min) *
        @as(isize, @intCast(sub_samp));

    const is_const_depth = z[0] == z[1] and z[1] == z[2];
    const nodes_inv_z = inv_z_node;

    const edge_tol = tol.edge.tri_weight_inclusion;

    const start_subx_global = tile_subx_off +
        @as(isize, @intCast(rast_bounds.start_x_u));
    const start_suby_global = tile_suby_off +
        @as(isize, @intCast(rast_bounds.start_y_u));

    const start_subx_f = @as(F, @floatFromInt(start_subx_global));
    const start_suby_f = @as(F, @floatFromInt(start_suby_global));
    const x_start_pix = @mulAdd(F, start_subx_f, step, offset);
    const y_start_pix = @mulAdd(F, start_suby_f, step, offset);

    var w_start_y: [3]F = undefined;
    var w_start: [3]F = undefined;
    inline for (0..3) |nn| {
        w_start_y[nn] = @mulAdd(F, b[nn], y_start_pix, c[nn]);
        w_start[nn] = @mulAdd(F, a[nn], x_start_pix, w_start_y[nn]);
    }

    const scratch_stride = subpx_dom.tile_size;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * scratch_stride;
        const global_suby = comm.globalSubpxForReport(
            tile.scratch_y_px_min,
            sub_samp,
            scratch_y_u,
        );
        const y_steps = @as(F, @floatFromInt(scratch_y_u - rast_bounds.start_y_u));

        var weights: [3]F = undefined;
        inline for (0..3) |nn| {
            weights[nn] = @mulAdd(F, y_steps, dw_dy[nn], w_start[nn]);
        }

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const global_subx = comm.globalSubpxForReport(
                tile.scratch_x_px_min,
                sub_samp,
                scratch_x_u,
            );

            if (comptime report_mode == .full_stats) {
                rasterreport.recordEarlyOut(
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                );
            }

            ctx_report.recordSolverCalls(1);
            ctx_report.recordSolverIters(1);

            if (weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol)
            {
                const inv_z_tail = @mulAdd(
                    F,
                    weights[1],
                    inv_z_node[1],
                    weights[2] * inv_z_node[2],
                );
                const inv_z = if (is_const_depth)
                    inv_z_node[0]
                else
                    @mulAdd(F, weights[0], inv_z_node[0], inv_z_tail);

                if (inv_z + buildconfig.config.tol.geometry.depth_buff_inv_z_cmp >=
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

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelIterAndOccupancy(
                            ctx_report,
                            global_subx,
                            global_suby,
                            1,
                            @intCast(@max(0, tile.scratch_x_px_min + @as(
                                i32,
                                @intCast(scratch_x_u / sub_samp),
                            ))),
                            @intCast(@max(0, tile.scratch_y_px_min + @as(
                                i32,
                                @intCast(scratch_y_u / sub_samp),
                            ))),
                        );
                    }

                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, weights[1], inv_z_node[1], 0.0) / inv_z;

                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, weights[2], inv_z_node[2], 0.0) / inv_z;

                    if (comptime report_mode == .full_stats) {
                        rasterreport.recordPixelConvStats(
                            ctx_report,
                            global_subx,
                            global_suby,
                            true,
                            xi,
                            eta,
                            area,
                        );
                    }

                    const ctx_shade = shaderops.ShadeContext{
                        .frame_idx = ctx_rast.frame_idx,
                        .elem_idx = overlap.elem_idx,
                        .fields_num = fields_num,
                        .actual_fields = fields_num,
                        .scratch_idx = subpx_scratch.imageIndex(scratch_idx),
                        .global_subx = global_subx,
                        .global_suby = global_suby,
                    };
                    const interp_data = shaderops.InterpData(N){
                        .weights = weights,
                        .nodes_inv_z = nodes_inv_z,
                        .sub_pixel_z = subpx_z,
                        .xi = xi,
                        .eta = eta,
                    };

                    ShaderKern.shade(
                        Geom.coord_space,
                        ctx_shade,
                        interp_data,
                        shader_buf,
                        shader,
                        ctx_report,
                        &subpx_scratch.image,
                    );
                }
            } else {
                if (comptime report_mode == .full_stats) {
                    const nan = std.math.nan(F);
                    rasterreport.recordPixelConvStats(
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

            inline for (0..3) |nn| {
                weights[nn] += dw_dx[nn];
            }
        }
    }

    return shaded_px;
}
