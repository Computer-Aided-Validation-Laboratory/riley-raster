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
const HullMultiRoot = @import("hullmultiroot.zig").HullMultiRoot;
const HullAdaptive = @import("hulladaptive.zig").HullAdaptive;
const frontend = @import("rasterfrontend.zig");
const elemtilebin = @import("elemtilebinning.zig");
const edgeops = @import("hulledge.zig");
const ElemBBox = frontend.ElemBBox;
const OverlapBBox = elemtilebin.OverlapBBox;
const ActiveTile = elemtilebin.ActiveTile;
const Vec3Slices = frontend.Vec3Slices;
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const comm = @import("rasterengine_common.zig");

const meshpipe = @import("meshpipeline.zig");
const MeshPrepared = meshpipe.MeshPrepared;
const MeshType = meshpipe.MeshType;
const Shader = meshpipe.Shader;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const newton = @import("newton.zig");
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

    // Polymorphic interface matching global-buffer scratch buffers. In tile-local
    // mode, image storage is tile-local, so local_idx is returned directly.
    pub inline fn resolveImageIdx(
        _: *const SubpxScratchBuffs,
        local_subx: usize,
        local_suby: usize,
        local_idx: usize,
    ) usize {
        _ = local_subx;
        _ = local_suby;
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

//------------------------------------------------------------------------------------------
// Raster Engine Builder
//------------------------------------------------------------------------------------------
const SubpxDom = comm.SubpxDom;
const RasterBounds = comm.RasterBounds;

pub fn RasterEngine(
    comptime ScratchBuffs: type,
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime root_class: frontend.ElemRootClass,
) type {
    return struct {
        pub const HullType = if (root_class == .multi_root)
            *const meshpipe.MultiRootHulls
        else
            ?*const NDArray(F);

        pub fn rasterElemInTile(
            comptime report_mode: ReportMode,
            ctx_rast: frontend.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            tile: elemtilebin.ActiveTile,
            overlap: elemtilebin.OverlapBBox,
            coords: *const NDArray(F),
            hull: HullType,
            shader: *const ShaderData,
            shader_buf: *const ShaderKern.LocalBuff,
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

            const overlap_start_x_px = overlap.x_min - tile.scratch_px.x_min;
            const overlap_end_x_px = overlap.x_max - tile.scratch_px.x_min;
            const overlap_start_y_px = overlap.y_min - tile.scratch_px.y_min;
            const overlap_end_y_px = overlap.y_max - tile.scratch_px.y_min;
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

            const nodes_coords = try frontend.loadElemVec3Slices(
                GeomKern.nodes_num,
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
                hull,
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
            ctx_rast: frontend.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            tile: elemtilebin.ActiveTile,
            overlap: elemtilebin.OverlapBBox,
            hull: HullType,
            subpx_dom: SubpxDom,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(F),
            shader: *const ShaderData,
            shader_buf: *const ShaderKern.LocalBuff,
            subpx_scratch: *ScratchBuffs,
        ) !u64 {
            if (comptime GeomKern == geomkerns.Tri3OptKernel()) {
                return rasterSteppedScal(
                    ScratchBuffs,
                    GeomKern,
                    ShaderKern,
                    ShaderData,
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    tile,
                    overlap,
                    hull,
                    subpx_dom,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    subpx_scratch,
                );
            }
            if (comptime GeomKern.solver_kind != .newton) {
                return rasterDirectImpl(
                    ScratchBuffs,
                    GeomKern,
                    ShaderKern,
                    ShaderData,
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    tile,
                    overlap,
                    hull,
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
                GeomKern,
                ShaderKern,
                ShaderData,
                report_mode,
                ctx_rast,
                ctx_report,
                tile,
                overlap,
                hull,
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

pub fn rasterDirectScalComm(
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    comptime ScratchBuffs: type,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    fields_num: u8,
    nodes_coords: frontend.Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
    if (comptime GeomKern.solver_kind == .newton) {
        @compileError(
            "rasterDirectScalComm only supps non-Newton paths",
        );
    }

    const N = GeomKern.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);

    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    }

    const inv_elem_area = if (comptime GeomKern.solver_kind == .hyperb)
        GeomKern.getInvElemArea(nodes_coords)
    else {};

    const ideal_x_plane = cam.getIdealXPlaneScratch(
        subpx_scratch.ideal_pix_cent,
    );
    const ideal_y_plane = cam.getIdealYPlaneScratch(
        subpx_scratch.ideal_pix_cent,
    );

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_dom.tile_size;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const ideal_x_pix = ideal_x_plane[scratch_idx];
            const ideal_y_pix = ideal_y_plane[scratch_idx];

            const global_subx = comm.globalSubpxForReport(
                tile.scratch_px.x_min,
                sub_samp,
                scratch_x_u,
            );
            const global_suby = comm.globalSubpxForReport(
                tile.scratch_px.y_min,
                sub_samp,
                scratch_y_u,
            );

            ctx_report.recordSolverCalls(1);
            const geometry_result = switch (comptime GeomKern.solver_kind) {
                .hyperb => GeomKern.solveWeightsHyperb(
                    nodes_coords,
                    ideal_x_pix,
                    ideal_y_pix,
                    inv_elem_area,
                ),
                else => unreachable,
            };
            ctx_report.recordSolverIters(geometry_result.iters);

            const weights = geometry_result.weights orelse {
                if (geometry_result.iters > 0) {
                    ctx_report.recordSolverDiverged();
                }
                continue;
            };

            const inv_z = GeomKern.calcInvZ(nodes_coords, weights);
            if (inv_z + tol.geometry.depth_buff_inv_z_cmp <
                subpx_scratch.inv_z[scratch_idx])
            {
                continue;
            }

            subpx_scratch.inv_z[scratch_idx] = inv_z;
            if (scratch_x_u < subpx_scratch.touched_min_x[scratch_y_u]) {
                subpx_scratch.touched_min_x[scratch_y_u] = scratch_x_u;
            }

            if (scratch_x_u > subpx_scratch.touched_max_x[scratch_y_u]) {
                subpx_scratch.touched_max_x[scratch_y_u] = scratch_x_u;
            }

            const xi = if (comptime GeomKern.solver_kind == .hyperb)
                weights[1] * nodes_inv_z[1] / inv_z
            else
                geometry_result.xi_out;
            const eta = if (comptime GeomKern.solver_kind == .hyperb)
                weights[2] * nodes_inv_z[2] / inv_z
            else
                geometry_result.eta_out;

            ShaderKern.shade(
                GeomKern.coord_space,
                shaderops.ShadeContext{
                    .frame_idx = ctx_rast.frame_idx,
                    .elem_idx = overlap.elem_idx,
                    .fields_num = fields_num,
                    .actual_fields = fields_num,
                    .scratch_idx = subpx_scratch.resolveImageIdx(
                        scratch_x_u,
                        scratch_y_u,
                        scratch_idx,
                    ),
                    .global_subx = global_subx,
                    .global_suby = global_suby,
                },
                ShaderKern.Hit{
                    .weights = weights,
                    .nodes_inv_z = nodes_inv_z,
                    .sub_pixel_z = 1.0 / inv_z,
                    .xi = xi,
                    .eta = eta,
                },
                shader_buf,
                shader,
                ctx_report,
                &subpx_scratch.image,
            );

            shaded_px += 1;
        }
    }

    return shaded_px;
}

fn rasterDirectImpl(
    comptime ScratchBuffs: type,
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    return rasterDirectScalComm(
        GeomKern,
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
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    hull_adaptive: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
    comptime {
        if (GeomKern.solver_kind != .newton) {
            @compileError("rasterNewton only supps Newton geometries");
        }
    }

    const N = GeomKern.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    }

    var elem_tess: HullAdaptive.Tessellation(GeomKern.tess_triangles_num) = undefined;
    if (comptime GeomKern.hull_nodes_num > 0) {
        if (hull_adaptive) |rh| {
            const hx = rh.getSlice(
                &[_]usize{ overlap.elem_idx, 0, 0 },
                1,
            );
            const hy = rh.getSlice(
                &[_]usize{ overlap.elem_idx, 1, 0 },
                1,
            );
            elem_tess = HullAdaptive.makeTessellation(
                N,
                GeomKern.hull_nodes_num,
                GeomKern.tess_triangles_num,
                hx,
                hy,
            );
            if (ctx_rast.config.advanced.solver.oneroot.edge_fun_mode == .pre_calc)
                elem_tess.prepareEdges();
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
                tile.scratch_px.x_min,
                sub_samp,
                scratch_x,
            );
            const global_suby = comm.globalSubpxForReport(
                tile.scratch_px.y_min,
                sub_samp,
                scratch_y,
            );

            var hull_seed: ?newton.NewtonSeed = null;
            if (comptime GeomKern.hull_nodes_num > 0) {
                ctx_report.recordTessChecks(1);
                const seed_mode = ctx_rast.config.advanced.solver.oneroot.newton_seed_mode;
                const edge_mode = ctx_rast.config.advanced.solver.oneroot.edge_fun_mode;
                const is_in = if (seed_mode == .hull) blk: {
                    const tess_res = elem_tess.isInScalar(ideal_x_pix, ideal_y_pix, edge_mode);
                    if (tess_res.is_in) {
                        hull_seed = .{ .xi = tess_res.seed_xi, .eta = tess_res.seed_eta };
                    }
                    break :blk tess_res.is_in;
                } else elem_tess.containsScalar(ideal_x_pix, ideal_y_pix, edge_mode);
                if (is_in) {
                    ctx_report.recordTessPasses(1);
                }

                if (!is_in) continue;
            } else {}

            ctx_report.recordSolverCalls(1);
            const result = blk: {
                if (ctx_rast.config.advanced.solver.oneroot.newton_seed_mode == .hull) {
                    if (hull_seed) |seed| {
                        const seed_quality = newton.evaluateSeedQuality(
                            GeomKern.nodes_num,
                            GeomKern.domViolation,
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
                const base_seed = GeomKern.initSeed(
                    ctx_rast.config.advanced.solver.oneroot.newton_seed_mode,
                    hull_seed,
                );
                const selected_seed = newton.selectSeed(
                    ctx_rast.config.advanced.solver.oneroot.newton_seed_reuse,
                    base_seed,
                    seed_state,
                );
                break :blk GeomKern.solveWeightsNewton(
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
            if (result.weights == null) {
                if (result.iters > 0) ctx_report.recordSolverDiverged();
                continue;
            }

            if (ctx_rast.config.advanced.solver.oneroot.newton_seed_reuse == .last_conv) {
                newton.updateSeedState(
                    &seed_state,
                    result.xi_out,
                    result.eta_out,
                );
            }

            const weights = result.weights.?;
            const inv_z = GeomKern.calcInvZ(nodes_coords, weights);
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

            const ctx_shade = shaderops.ShadeContext{
                .frame_idx = ctx_rast.frame_idx,
                .elem_idx = overlap.elem_idx,
                .fields_num = fields_num,
                .actual_fields = fields_num,
                .scratch_idx = subpx_scratch.resolveImageIdx(
                    scratch_x,
                    scratch_y,
                    scratch_idx,
                ),
                .global_subx = global_subx,
                .global_suby = global_suby,
            };
            const interp_data = ShaderKern.Hit{
                .weights = weights,
                .nodes_inv_z = nodes_inv_z,
                .sub_pixel_z = subpx_z,
                .xi = result.xi_out,
                .eta = result.eta_out,
            };

            ShaderKern.shade(
                GeomKern.coord_space,
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
    comptime GeomKern: type,
    comptime report_mode: ReportMode,
    ctx_report: report.ReportContext(report_mode),
    nodes_coords: Vec3Slices(F),
    ideal_x: F,
    ideal_y: F,
    x_off: F,
    y_off: F,
    seed: [2]F,
) ?struct {
    weights: [GeomKern.nodes_num]F,
    xi: F,
    eta: F,
    inv_z: F,
} {
    ctx_report.recordSolverCalls(1);

    const result = GeomKern.solveWeightsNewton(
        nodes_coords,
        ideal_x,
        ideal_y,
        x_off,
        y_off,
        seed[0],
        seed[1],
    );

    ctx_report.recordSolverIters(result.iters);

    const weights = result.weights orelse {
        if (result.iters > 0) ctx_report.recordSolverDiverged();
        return null;
    };

    if (!std.math.isFinite(result.xi_out) or
        !std.math.isFinite(result.eta_out) or
        GeomKern.domViolation(result.xi_out, result.eta_out) > 0)
    {
        return null;
    }

    const state = newton.evaluateSolveState(
        GeomKern.nodes_num,
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
        return null;
    }

    const facing = frontend.projectedJacDetPhysical(
        GeomKern.nodes_num,
        nodes_coords,
        result.xi_out,
        result.eta_out,
    );

    if (!std.math.isFinite(facing) or
        facing >= -tol.culling.projected_jacobian_abs)
    {
        return null;
    }

    const inv_z = GeomKern.calcInvZ(nodes_coords, weights);

    if (!std.math.isFinite(inv_z) or inv_z <= 0) return null;

    return .{
        .weights = weights,
        .xi = result.xi_out,
        .eta = result.eta_out,
        .inv_z = inv_z,
    };
}

fn rasterNewtonMultiImpl(
    comptime ScratchBuffs: type,
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    hull_multiroot: *const meshpipe.MultiRootHulls,
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const N = GeomKern.nodes_num;
    const slot = hull_multiroot.slot_by_visible_elem.get(overlap.elem_idx);
    if (slot == std.math.maxInt(u32)) return error.MissingMultiRootData;
    const edge_fun_mode = ctx_rast.config.advanced.solver.multiroot.edge_fun_mode;

    const fallback_seed_count = hull_multiroot.valid_depth.get(slot);
    const fallback_seeds =
        hull_multiroot.indices.getSlice(slot)[0..fallback_seed_count];
    var fallback_seed_uvs: [3][2]F = undefined;
    for (fallback_seeds, 0..) |seed_idx, ii| {
        fallback_seed_uvs[ii] = geomkerns.multiRootSeedCoords(N, seed_idx);
    }

    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);
    const ideal_x_plane = cam.getIdealXPlaneScratch(subpx_scratch.ideal_pix_cent);
    const ideal_y_plane = cam.getIdealYPlaneScratch(subpx_scratch.ideal_pix_cent);
    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    var shaded_px: u64 = 0;
    const is_robust = ctx_rast.config.advanced.solver.multiroot.mode == .robust;
    const leaf_offset = @as(usize, slot) * 4;
    const leaves_pre_calc = if (edge_fun_mode == .pre_calc)
        hull_multiroot.leaves_pre_calc[leaf_offset .. leaf_offset + 4]
    else
        &.{};
    const leaves_on_the_fly = if (edge_fun_mode == .on_the_fly)
        hull_multiroot.leaves_on_the_fly[leaf_offset .. leaf_offset + 4]
    else
        &.{};

    var seeds: [4][2]F = undefined;
    inline for (0..4) |ii| {
        seeds[ii] = if (edge_fun_mode == .pre_calc)
            leaves_pre_calc[ii].parameter_seed
        else
            leaves_on_the_fly[ii].parameter_seed;
    }

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
        const row_offset = scratch_y * subpx_dom.tile_size;
        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
            const scratch_idx = row_offset + scratch_x;
            const ideal_x = ideal_x_plane[scratch_idx];
            const ideal_y = ideal_y_plane[scratch_idx];
            const global_subx = comm.globalSubpxForReport(
                tile.scratch_px.x_min,
                sub_samp,
                scratch_x,
            );
            const global_suby = comm.globalSubpxForReport(
                tile.scratch_px.y_min,
                sub_samp,
                scratch_y,
            );

            const child_mask = if (edge_fun_mode == .pre_calc)
                HullMultiRoot.childMaskPreCalcScalar(leaves_pre_calc, ideal_x, ideal_y)
            else
                HullMultiRoot.childMaskOnTheFlyScalar(leaves_on_the_fly, ideal_x, ideal_y);

            ctx_report.recordTessChecks(1);
            if (child_mask == 0) {
                continue;
            }
            ctx_report.recordTessPasses(1);

            var best_inv_z: F = -std.math.inf(F);
            var best_weights: ?[N]F = null;
            var best_xi: F = 0;
            var best_eta: F = 0;
            var had_candidate_child = false;

            for (0..4) |leaf_idx| {
                const bit = @as(u8, 1) << @as(u3, @intCast(leaf_idx));
                if ((child_mask & bit) == 0) continue;
                had_candidate_child = true;
                const seed = seeds[leaf_idx];
                if (solveMultiRootSeedScal(
                    GeomKern,
                    report_mode,
                    ctx_report,
                    nodes_coords,
                    ideal_x,
                    ideal_y,
                    subpx_dom.x_off,
                    subpx_dom.y_off,
                    seed,
                )) |hit| {
                    if (hit.inv_z > best_inv_z) {
                        best_inv_z = hit.inv_z;
                        best_weights = hit.weights;
                        best_xi = hit.xi;
                        best_eta = hit.eta;
                    }
                }
            }

            if (best_weights == null and had_candidate_child and is_robust) {
                for (fallback_seed_uvs[0..fallback_seed_count]) |seed_uv| {
                    if (solveMultiRootSeedScal(
                        GeomKern,
                        report_mode,
                        ctx_report,
                        nodes_coords,
                        ideal_x,
                        ideal_y,
                        subpx_dom.x_off,
                        subpx_dom.y_off,
                        seed_uv,
                    )) |hit| {
                        if (hit.inv_z > best_inv_z) {
                            best_inv_z = hit.inv_z;
                            best_weights = hit.weights;
                            best_xi = hit.xi;
                            best_eta = hit.eta;
                        }
                    }
                }
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
                .scratch_idx = subpx_scratch.resolveImageIdx(
                    scratch_x,
                    scratch_y,
                    scratch_idx,
                ),
                .global_subx = global_subx,
                .global_suby = global_suby,
            };

            const interp_data = ShaderKern.Hit{
                .weights = weights,
                .nodes_inv_z = nodes_inv_z,
                .sub_pixel_z = 1.0 / best_inv_z,
                .xi = best_xi,
                .eta = best_eta,
            };

            ShaderKern.shade(
                GeomKern.coord_space,
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

fn rasterSteppedScal(
    comptime ScratchBuffs: type,
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    hull_adaptive: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const tile_subpx_x = @as(isize, tile.scratch_px.x_min) *
        @as(isize, @intCast(sub_samp));
    const tile_subpx_y = @as(isize, tile.scratch_px.y_min) *
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
            GeomKern,
            ShaderKern,
            ShaderData,
            report_mode,
            ctx_rast,
            ctx_report,
            tile,
            overlap,
            hull_adaptive,
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
        GeomKern,
        ShaderKern,
        ShaderData,
        report_mode,
        ctx_rast,
        ctx_report,
        tile,
        overlap,
        hull_adaptive,
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
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
    fixed: comm.Tri3FixedEdges,
) !u64 {
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

    const is_const_depth = z[0] == z[1] and z[1] == z[2];
    const nodes_inv_z = inv_z_node;

    const scratch_stride = subpx_dom.tile_size;

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * scratch_stride;
        const global_suby = comm.globalSubpxForReport(
            tile.scratch_px.y_min,
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
                tile.scratch_px.x_min,
                sub_samp,
                scratch_x_u,
            );

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

                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, weights[1], inv_z_node[1], 0.0) / inv_z;

                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, weights[2], inv_z_node[2], 0.0) / inv_z;

                    const ctx_shade = shaderops.ShadeContext{
                        .frame_idx = ctx_rast.frame_idx,
                        .elem_idx = overlap.elem_idx,
                        .fields_num = fields_num,
                        .actual_fields = fields_num,
                        .scratch_idx = subpx_scratch.resolveImageIdx(
                            scratch_x_u,
                            scratch_y_u,
                            scratch_idx,
                        ),
                        .global_subx = global_subx,
                        .global_suby = global_suby,
                    };

                    const interp_data = ShaderKern.Hit{
                        .weights = weights,
                        .nodes_inv_z = nodes_inv_z,
                        .sub_pixel_z = subpx_z,
                        .xi = xi,
                        .eta = eta,
                    };

                    ShaderKern.shade(
                        GeomKern.coord_space,
                        ctx_shade,
                        interp_data,
                        shader_buf,
                        shader,
                        ctx_report,
                        &subpx_scratch.image,
                    );
                }
            } else {}

            inline for (0..3) |nn| {
                edge[nn] += fixed.step_x[nn];
            }
        }
    }

    return shaded_px;
}

fn rasterSteppedScalFloat(
    comptime ScratchBuffs: type,
    comptime GeomKern: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: frontend.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: elemtilebin.ActiveTile,
    overlap: elemtilebin.OverlapBBox,
    _: ?*const NDArray(F),
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const ShaderKern.LocalBuff,
    subpx_scratch: *ScratchBuffs,
) !u64 {
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

    const tile_subx_off = @as(isize, tile.scratch_px.x_min) *
        @as(isize, @intCast(sub_samp));
    const tile_suby_off = @as(isize, tile.scratch_px.y_min) *
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
            tile.scratch_px.y_min,
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
                tile.scratch_px.x_min,
                sub_samp,
                scratch_x_u,
            );

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

                    const xi = if (is_const_depth)
                        weights[1]
                    else
                        @mulAdd(F, weights[1], inv_z_node[1], 0.0) / inv_z;

                    const eta = if (is_const_depth)
                        weights[2]
                    else
                        @mulAdd(F, weights[2], inv_z_node[2], 0.0) / inv_z;

                    const ctx_shade = shaderops.ShadeContext{
                        .frame_idx = ctx_rast.frame_idx,
                        .elem_idx = overlap.elem_idx,
                        .fields_num = fields_num,
                        .actual_fields = fields_num,
                        .scratch_idx = subpx_scratch.resolveImageIdx(
                            scratch_x_u,
                            scratch_y_u,
                            scratch_idx,
                        ),
                        .global_subx = global_subx,
                        .global_suby = global_suby,
                    };
                    const interp_data = ShaderKern.Hit{
                        .weights = weights,
                        .nodes_inv_z = nodes_inv_z,
                        .sub_pixel_z = subpx_z,
                        .xi = xi,
                        .eta = eta,
                    };

                    ShaderKern.shade(
                        GeomKern.coord_space,
                        ctx_shade,
                        interp_data,
                        shader_buf,
                        shader,
                        ctx_report,
                        &subpx_scratch.image,
                    );
                }
            } else {}

            inline for (0..3) |nn| {
                weights[nn] += dw_dx[nn];
            }
        }
    }

    return shaded_px;
}
