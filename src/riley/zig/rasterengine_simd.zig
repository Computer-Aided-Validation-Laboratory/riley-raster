// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const CameraPrepared = @import("camera.zig").CameraPrepared;
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU = buildconfig.VecSU;
const VecSU8 = buildconfig.VecSU8;

const rastcfg = @import("rasterconfig.zig");
const ReportMode = rastcfg.ReportMode;
const tol = cfg.tolerance;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const HullResultSIMD = hull.HullResultSIMD;
const shapefun = @import("shapefun.zig");
const rops = @import("rasterops.zig");
const ElemBBox = rops.ElemBBox;
const OverlapBBox = rops.OverlapBBox;
const ActiveTile = rops.ActiveTile;
const Vec3Slices = rops.Vec3Slices;
const report = @import("report.zig");
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("rasterengine_common.zig");
const rasterreport = @import("rasterreport.zig");
const simdops = @import("simdops.zig");

const spec = @import("riley.zig");
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

const SubpxSimdChunk = struct {
    scratch_x_u: [S]usize,
    scratch_y_u: [S]usize,
    px_f: [S]f64,
    py_f: [S]f64,
    seed_xi: [S]f64,
    seed_eta: [S]f64,
    count: usize,
};

pub const SubpxScratchBuffers = struct {
    stride_subpx: usize,
    inv_z: []align(64) f64,
    image: MatSlice(f64),
    filter_tmp: MatSlice(f64),
    simd_chunks: []SubpxSimdChunk,
    mask: []align(64) bool,
    xi: []align(64) f64,
    eta: []align(64) f64,
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pixel_centers: []align(64) f64,
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;
const ScratchLayout = common.ScratchLayout;

pub const scratch_layout = ScratchLayout.field_major;

//------------------------------------------------------------------------------------------
// Scratch Buffer Helpers
//------------------------------------------------------------------------------------------

pub fn initSubpxScratch(
    arena_alloc: std.mem.Allocator,
    fields_num: u8,
    subpx_tile_size: usize,
) !SubpxScratchBuffers {
    const subpx_tile_total = subpx_tile_size * subpx_tile_size;
    // Rounds up to the nearest multiple of S for alignment
    const subpx_tile_total_padded = std.mem.alignForward(usize, subpx_tile_total, S);
    const alignment = std.mem.Alignment.@"64";

    const subpx_inv_z_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + S,
    );

    const subpx_mask_scratch = try arena_alloc.alignedAlloc(
        bool,
        alignment,
        subpx_tile_total_padded + S,
    );

    const subpx_xi_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + S,
    );

    const subpx_eta_scratch = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        subpx_tile_total_padded + S,
    );

    const subpx_img_mem = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        (subpx_tile_total_padded + S) * @as(usize, fields_num),
    );
    const subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        @as(usize, fields_num),
        subpx_tile_total_padded + S,
    );
    const filter_tmp_mem = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        (subpx_tile_total_padded + S) * @as(usize, fields_num),
    );
    const filter_tmp = MatSlice(f64).init(
        filter_tmp_mem,
        @as(usize, fields_num),
        subpx_tile_total_padded + S,
    );

    const subpx_simd_chunk_count =
        @divFloor(subpx_tile_total_padded + (S - 1), S) + 1;
    const subpx_simd_chunks = try arena_alloc.alloc(
        SubpxSimdChunk,
        subpx_simd_chunk_count,
    );

    const ideal_pixel_centers = try arena_alloc.alignedAlloc(
        f64,
        alignment,
        (subpx_tile_total_padded + S) * 2,
    );

    return .{
        .stride_subpx = subpx_tile_size,
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .filter_tmp = filter_tmp,
        .simd_chunks = subpx_simd_chunks,
        .mask = subpx_mask_scratch,
        .xi = subpx_xi_scratch,
        .eta = subpx_eta_scratch,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .ideal_pixel_centers = ideal_pixel_centers,
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffers,
    subpx_tile_size: usize,
    background_value: f64,
) void {
    @memset(subpx_scratch.inv_z, -std.math.inf(f64));
    @memset(subpx_scratch.image.slice, background_value);
    @memset(subpx_scratch.filter_tmp.slice, background_value);
    @memset(subpx_scratch.touched_min_x, subpx_tile_size);
    @memset(subpx_scratch.touched_max_x, 0);
}

//------------------------------------------------------------------------------------------
// Raster Pass Implementation
//------------------------------------------------------------------------------------------
pub fn RasterEngine(
    comptime GeometryKernel: type, // geometrykernels.zig
    comptime ShaderKernel: type, // shaderkernels.zig
    comptime ShaderData: type, // shaderops_common.zig, ShaderPrepared
) type {
    return struct {
        pub fn render(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshRaster,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const sub_samp_u: usize = @intCast(ctx_rast.camera.sub_sample);
            const sub_samp_f: f64 = @as(f64, @floatFromInt(ctx_rast.camera.sub_sample));

            const subpx_domain = SubpxDomain{
                .step = 1.0 / sub_samp_f,
                .offset = 1.0 / (2.0 * sub_samp_f),
                .tile_size = subpx_scratch.stride_subpx,
                .x_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[0])),
                .y_off = 0.5 * @as(f64, @floatFromInt(ctx_rast.camera.pixels_num[1])),
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
                .x_min_f = @as(f64, @floatFromInt(targ_overlap.overlap.x_min)),
                .y_min_f = @as(f64, @floatFromInt(targ_overlap.overlap.y_min)),
            };

            const nodes_coords = try rops.loadElemVec3Slices(
                GeometryKernel.nodes_num,
                f64,
                mesh_in.coords,
                targ_overlap.overlap.elem_idx,
            );

            const shaded_px = if (GeometryKernel.solver_kind == .hyperb)
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
            else if (GeometryKernel.solver_kind == .inv_bi)
                // NOTE: SIMD is very inefficient for highly branched inverse bilinear
                // solve fallback to scalar
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
                )
            else if (GeometryKernel.solver_kind == .newton)
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
                @compileError("Unsupported geometry in rasterengine_simd");

            return shaded_px;
        }

        fn rasterDirectSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            orig_start_x_u: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            return rasterDirectSIMDImpl(
                GeometryKernel,
                ShaderKernel,
                report_mode,
                ctx_rast,
                ctx_report,
                targ_overlap,
                subpx_domain,
                rast_bounds,
                orig_start_x_u,
                nodes_coords,
                shader,
                shader_buf,
                subpx_scratch,
            );
        }

        /// To use our S wide SIMD effectively for Newton we need to process in
        /// multiple passes to fill the S lanes where possible.
        fn rasterNewtonSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: *const rops.MeshRaster,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            orig_start_x_u: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            return rasterNewtonSIMDImpl(
                GeometryKernel,
                ShaderKernel,
                report_mode,
                ctx_rast,
                ctx_report,
                targ_overlap,
                mesh_in,
                subpx_domain,
                rast_bounds,
                orig_start_x_u,
                nodes_coords,
                shader,
                shader_buf,
                subpx_scratch,
            );
        }

        /// Scalar fallback for the quad4ibi kernel which didn't work well in SIMD due to
        /// the large amount of branching logic required to handle all cases.
        fn rasterDirect(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshRaster,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            return rasterDirectImpl(
                GeometryKernel,
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

fn rasterDirectSIMDImpl(
    comptime GeometryKernel: type,
    comptime ShaderKernel: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    orig_start_x_u: usize,
    nodes_coords: Vec3Slices(f64),
    shader: anytype,
    shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    const N = GeometryKernel.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    const inv_area = GeometryKernel.getInvElemArea(nodes_coords);
    const v_inv_area: VecSF = @splat(inv_area);
    var nodes_inv_z: [N]f64 = undefined;

    inline for (0..N) |nn| nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    const v_nodes_inv_z = GeometryKernel.getSIMDInvZ(nodes_coords);

    const v_orig_start_x_u: VecSU = @splat(orig_start_x_u);
    const v_end_x_u: VecSU = @splat(rast_bounds.end_x_u);

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;

        var scratch_x_u = rast_bounds.start_x_u;
        while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
            const v_lane_idx_u: VecSU = std.simd.iota(usize, S);
            const v_scratch_x_u: VecSU = @splat(scratch_x_u);
            const v_subpx_x_u = v_scratch_x_u + v_lane_idx_u;
            const v_x_mask = (v_subpx_x_u >= v_orig_start_x_u) &
                (v_subpx_x_u < v_end_x_u);

            const scratch_idx = row_offset + scratch_x_u;
            var v_ideal_x_px: VecSF = undefined;
            var v_ideal_y_px: VecSF = undefined;
            inline for (0..S) |ll| {
                v_ideal_x_px[ll] =
                    subpx_scratch.ideal_pixel_centers[(scratch_idx + ll) * 2 + 0];
                v_ideal_y_px[ll] =
                    subpx_scratch.ideal_pixel_centers[(scratch_idx + ll) * 2 + 1];
            }

            ctx_report.recordSolverCalls(S);
            const res = GeometryKernel.solveWeightsHyperbSIMD(
                nodes_coords,
                v_ideal_x_px,
                v_ideal_y_px,
                v_inv_area,
            );
            const v_mask_active = v_x_mask & res.v_mask;

            const lane_x_mask: [S]bool = v_x_mask;
            const lane_active_mask: [S]bool = v_mask_active;
            const lane_weights_0: [S]f64 = res.v_weights[0];
            const lane_weights_1: [S]f64 = res.v_weights[1];
            const lane_weights_2: [S]f64 = res.v_weights[2];
            const lane_inv_z: [S]f64 = GeometryKernel.calcInvZSIMD(
                v_nodes_inv_z,
                res.v_weights,
            );
            for (0..S) |ll| {
                if (!lane_x_mask[ll]) continue;

                const global_subx =
                    @as(usize, @intCast(targ_overlap.tile.scratch_x_px_min)) *
                    sub_samp + scratch_x_u + ll;
                const global_suby =
                    @as(usize, @intCast(targ_overlap.tile.scratch_y_px_min)) *
                    sub_samp + scratch_y_u;
                if (lane_active_mask[ll]) {
                    const weights = [3]f64{
                        lane_weights_0[ll],
                        lane_weights_1[ll],
                        lane_weights_2[ll],
                    };
                    const inv_z = lane_inv_z[ll];
                    const interp = common.calcInterpParamCoords(
                        GeometryKernel,
                        nodes_inv_z,
                        weights,
                        inv_z,
                        0.0,
                        0.0,
                    );
                    rasterreport.recordPixelConvergedStats(
                        report_mode,
                        ctx_report,
                        global_subx,
                        global_suby,
                        true,
                        interp.xi,
                        interp.eta,
                        newton.calcJacobianDet2D(
                            N,
                            interp.xi,
                            interp.eta,
                            nodes_coords.x,
                            nodes_coords.y,
                        ),
                    );
                    continue;
                }

                const nan = std.math.nan(f64);
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

            if (!@reduce(.Or, v_mask_active)) continue;

            const v_inv_z = GeometryKernel.calcInvZSIMD(
                v_nodes_inv_z,
                res.v_weights,
            );
            const v_old_inv_z = simdops.loadVecSF(
                subpx_scratch.inv_z,
                scratch_idx,
            );
            const v_depth_tol: VecSF =
                @splat(tol.geometry.depth_buffer_inv_z_cmp);
            const v_depth_mask =
                v_mask_active & (v_inv_z + v_depth_tol >= v_old_inv_z);
            if (!@reduce(.Or, v_depth_mask)) continue;

            const v_new_inv_z = @select(
                f64,
                v_depth_mask,
                v_inv_z,
                v_old_inv_z,
            );
            simdops.storeVecSF(
                subpx_scratch.inv_z,
                scratch_idx,
                v_new_inv_z,
            );
            const v_subpx_z: VecSF = @as(VecSF, @splat(1.0)) / v_inv_z;
            const v_xi = res.v_weights[1] * v_nodes_inv_z[1] / v_inv_z;
            const v_eta = res.v_weights[2] * v_nodes_inv_z[2] / v_inv_z;

            const v_depth_mask_arr: [S]bool = v_depth_mask;
            inline for (0..S) |ll| {
                if (v_depth_mask_arr[ll]) {
                    const touched_x_u = scratch_x_u + ll;
                    if (touched_x_u < subpx_scratch.touched_min_x[scratch_y_u]) {
                        subpx_scratch.touched_min_x[scratch_y_u] = touched_x_u;
                    }
                    if (touched_x_u > subpx_scratch.touched_max_x[scratch_y_u]) {
                        subpx_scratch.touched_max_x[scratch_y_u] = touched_x_u;
                    }
                }
            }

            const v_hit_one: VecSU8 = @splat(1);
            const v_hit_zero: VecSU8 = @splat(0);
            const v_hit_count = @select(u8, v_depth_mask, v_hit_one, v_hit_zero);
            shaded_px += @intCast(@reduce(.Add, v_hit_count));

            const ctx_shade = shaderops.ShadeContext(N){
                .frame_idx = ctx_rast.frame_idx,
                .elem_idx = targ_overlap.overlap.elem_idx,
                .fields_num = fields_num,
                .actual_fields = fields_num,
                .scratch_idx = scratch_idx,
                .global_subx = targ_overlap.tile.scratch_x_px_min * sub_samp + scratch_x_u,
                .global_suby = targ_overlap.tile.scratch_y_px_min * sub_samp + scratch_y_u,
                .shader_buf = shader_buf,
                .v_mask_active = v_depth_mask,
            };

            ShaderKernel.shadeSIMD(
                GeometryKernel.coord_space,
                ctx_shade,
                ctx_report,
                v_depth_mask,
                res.v_weights,
                v_xi,
                v_eta,
                v_nodes_inv_z,
                v_subpx_z,
                shader,
                &subpx_scratch.image,
            );
        }
    }
    return shaded_px;
}

fn rasterNewtonSIMDImpl(
    comptime GeometryKernel: type,
    comptime ShaderKernel: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: *const rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    orig_start_x_u: usize,
    nodes_coords: Vec3Slices(f64),
    shader: anytype,
    shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    const N = GeometryKernel.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

    var nodes_inv_z: [N]f64 = undefined;
    var v_nodes_z: [N]VecSF = undefined;
    var v_nodes_inv_z: [N]VecSF = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
        v_nodes_z[nn] = @splat(nodes_coords.z[nn]);
        v_nodes_inv_z[nn] = @splat(nodes_inv_z[nn]);
    }

    const maybe_raster_hull = mesh_in.hull;
    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;
        const mask_start = row_offset + rast_bounds.start_x_u;
        const mask_end = row_offset + rast_bounds.end_x_u;
        @memset(subpx_scratch.mask[mask_start..mask_end], false);
    }

    var subpx_tess_pass_count: usize = 0;
    const v_lane_idx: VecSU = std.simd.iota(usize, S);
    const v_orig_start_x_u: VecSU = @splat(orig_start_x_u);
    const v_bounds_end_x_u: VecSU = @splat(rast_bounds.end_x_u);

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;

        var scratch_x_u: usize = rast_bounds.start_x_u;
        while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
            const v_scratch_x_u: VecSU = @splat(scratch_x_u);
            const v_subpx_x_u = v_scratch_x_u + v_lane_idx;
            const v_x_mask = (v_subpx_x_u >= v_orig_start_x_u) &
                (v_subpx_x_u < v_bounds_end_x_u);

            const scratch_idx = row_offset + scratch_x_u;
            var v_ideal_x_px: VecSF = undefined;
            var v_ideal_y_px: VecSF = undefined;
            inline for (0..S) |ll| {
                v_ideal_x_px[ll] =
                    subpx_scratch.ideal_pixel_centers[(scratch_idx + ll) * 2 + 0];
                v_ideal_y_px[ll] =
                    subpx_scratch.ideal_pixel_centers[(scratch_idx + ll) * 2 + 1];
            }

            var v_mask_active = v_x_mask;
            var xi_arr = [_]f64{0.0} ** S;
            var eta_arr = [_]f64{0.0} ** S;

            if (maybe_raster_hull) |raster_hull| {
                const hx = raster_hull.getSlice(
                    &[_]usize{ targ_overlap.overlap.elem_idx, 0, 0 },
                    1,
                );
                const hy = raster_hull.getSlice(
                    &[_]usize{ targ_overlap.overlap.elem_idx, 1, 0 },
                    1,
                );
                const element_tess = hull.getTessellation(
                    N,
                    GeometryKernel.hull_nodes_num,
                    GeometryKernel.tess_triangles_num,
                    hx,
                    hy,
                );
                const v_hull_res: HullResultSIMD = element_tess.isInSIMD(
                    v_ideal_x_px,
                    v_ideal_y_px,
                );
                const init_seed = GeometryKernel.initSeedSIMD(
                    ctx_rast.config.newton_seed_mode,
                    .{
                        .v_xi = v_hull_res.v_seed_xi,
                        .v_eta = v_hull_res.v_seed_eta,
                    },
                );
                xi_arr = init_seed.v_xi;
                eta_arr = init_seed.v_eta;

                const v_mask_one_u8: VecSU8 = @splat(1);
                const v_mask_zero_u8: VecSU8 = @splat(0);
                const v_tess_check_u8 = @select(u8, v_x_mask, v_mask_one_u8, v_mask_zero_u8);
                ctx_report.recordTessChecks(@intCast(@reduce(.Add, v_tess_check_u8)));

                v_mask_active = v_x_mask & v_hull_res.v_is_in;
                const v_tess_pass_u8 = @select(u8, v_mask_active, v_mask_one_u8, v_mask_zero_u8);
                ctx_report.recordTessPasses(@intCast(@reduce(.Add, v_tess_pass_u8)));
            } else {
                const init_seed = GeometryKernel.initSeed(
                    ctx_rast.config.newton_seed_mode,
                    null,
                );
                @memset(&xi_arr, init_seed.xi);
                @memset(&eta_arr, init_seed.eta);
            }

            if (!@reduce(.Or, v_mask_active)) continue;

            const mask_arr: [S]bool = v_mask_active;
            const x_arr_f: [S]f64 = v_ideal_x_px;
            const y_arr_f: [S]f64 = v_ideal_y_px;

            for (0..S) |ss| {
                if (!mask_arr[ss]) continue;

                var seed_xi = xi_arr[ss];
                var seed_eta = eta_arr[ss];
                if (ctx_rast.config.newton_seed_mode == .hull) {
                    const hull_seed = newton.NewtonSeed{
                        .xi = seed_xi,
                        .eta = seed_eta,
                    };
                    const seed_quality = newton.evaluateSeedQuality(
                        GeometryKernel.nodes_num,
                        GeometryKernel.domainViolation,
                        x_arr_f[ss] - subpx_domain.x_off,
                        y_arr_f[ss] - subpx_domain.y_off,
                        nodes_coords.x,
                        nodes_coords.y,
                        nodes_coords.z,
                        hull_seed,
                    );
                    if (!seed_quality.is_usable) {
                        const centroid_seed = GeometryKernel.initSeed(
                            ctx_rast.config.newton_seed_mode,
                            null,
                        );
                        seed_xi = centroid_seed.xi;
                        seed_eta = centroid_seed.eta;
                    }
                }

                const chunk_idx = subpx_tess_pass_count / S;
                const lane_idx = subpx_tess_pass_count % S;
                if (lane_idx == 0) {
                    subpx_scratch.simd_chunks[chunk_idx] = .{
                        .scratch_x_u = [_]usize{0} ** S,
                        .scratch_y_u = [_]usize{0} ** S,
                        .px_f = [_]f64{0.0} ** S,
                        .py_f = [_]f64{0.0} ** S,
                        .seed_xi = [_]f64{0.0} ** S,
                        .seed_eta = [_]f64{0.0} ** S,
                        .count = 0,
                    };
                }

                subpx_scratch.simd_chunks[chunk_idx].scratch_x_u[lane_idx] = scratch_x_u + ss;
                subpx_scratch.simd_chunks[chunk_idx].scratch_y_u[lane_idx] = scratch_y_u;
                subpx_scratch.simd_chunks[chunk_idx].px_f[lane_idx] = x_arr_f[ss];
                subpx_scratch.simd_chunks[chunk_idx].py_f[lane_idx] = y_arr_f[ss];
                subpx_scratch.simd_chunks[chunk_idx].seed_xi[lane_idx] = seed_xi;
                subpx_scratch.simd_chunks[chunk_idx].seed_eta[lane_idx] = seed_eta;
                subpx_scratch.simd_chunks[chunk_idx].count = lane_idx + 1;
                subpx_tess_pass_count += 1;
            }
        }
    }

    const subpx_simd_chunk_count = @divFloor(subpx_tess_pass_count + (S - 1), S);
    var seed_state = newton.NewtonSeedState{};
    const v_full_mask: VecSB = @splat(true);

    for (0..subpx_simd_chunk_count) |chunk_idx| {
        var subpx_simd_chunk = subpx_scratch.simd_chunks[chunk_idx];
        if (ctx_rast.config.newton_seed_reuse == .last_converged) {
            newton.applySeedReuseInPlace(
                subpx_simd_chunk.count,
                seed_state,
                subpx_simd_chunk.seed_xi[0..subpx_simd_chunk.count],
                subpx_simd_chunk.seed_eta[0..subpx_simd_chunk.count],
            );
        }

        const v_target_x_f: VecSF = subpx_simd_chunk.px_f;
        const v_target_y_f: VecSF = subpx_simd_chunk.py_f;
        const v_xi_seed: VecSF = subpx_simd_chunk.seed_xi;
        const v_eta_seed: VecSF = subpx_simd_chunk.seed_eta;
        const v_chunk_mask: VecSB = if (subpx_simd_chunk.count == S)
            v_full_mask
        else
            v_lane_idx < @as(VecSU, @splat(subpx_simd_chunk.count));

        const result = GeometryKernel.solveWeightsNewtonSIMD(
            nodes_coords,
            v_target_x_f,
            v_target_y_f,
            v_xi_seed,
            v_eta_seed,
            subpx_domain.x_off,
            subpx_domain.y_off,
        );

        const v_solver_iters = @select(
            u8,
            v_chunk_mask,
            result.v_iters,
            @as(VecSU8, @splat(0)),
        );
        ctx_report.recordSolverIters(@intCast(@reduce(.Add, v_solver_iters)));
        ctx_report.recordSolverCalls(subpx_simd_chunk.count);

        const chunk_mask_arr: [S]bool = v_chunk_mask;
        const conv_mask_arr: [S]bool = result.v_mask;
        const iters_arr: [S]u8 = result.v_iters;
        const xi_out_arr: [S]f64 = result.v_xi_out;
        const eta_out_arr: [S]f64 = result.v_eta_out;
        for (0..S) |jj| {
            if (!chunk_mask_arr[jj]) continue;

            const global_subx = @as(usize, subpx_simd_chunk.scratch_x_u[jj]) +
                @as(usize, @intCast(targ_overlap.tile.scratch_x_px_min)) * sub_samp;
            const global_suby = @as(usize, subpx_simd_chunk.scratch_y_u[jj]) +
                @as(usize, @intCast(targ_overlap.tile.scratch_y_px_min)) * sub_samp;
            rasterreport.recordPixelIters(
                report_mode,
                ctx_report,
                global_subx,
                global_suby,
                iters_arr[jj],
            );
            if (conv_mask_arr[jj]) {
                rasterreport.recordPixelConvergedStats(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    true,
                    xi_out_arr[jj],
                    eta_out_arr[jj],
                    newton.calcJacobianDet2D(
                        N,
                        xi_out_arr[jj],
                        eta_out_arr[jj],
                        nodes_coords.x,
                        nodes_coords.y,
                    ),
                );
                continue;
            }

            const nan = std.math.nan(f64);
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

        const v_conv_mask = v_chunk_mask & result.v_mask;
        if (!@reduce(.Or, v_conv_mask)) continue;

        const v_scratch_idx =
            @as(VecSU, subpx_simd_chunk.scratch_y_u) *
            @as(VecSU, @splat(subpx_domain.tile_size)) +
            @as(VecSU, subpx_simd_chunk.scratch_x_u);
        const write_mask_arr: [S]bool = v_conv_mask;
        const write_xi_arr: [S]f64 = result.v_xi_out;
        const write_eta_arr: [S]f64 = result.v_eta_out;
        const scratch_idx_arr: [S]usize = v_scratch_idx;
        for (0..S) |jj| {
            if (!write_mask_arr[jj]) continue;
            const scratch_idx = scratch_idx_arr[jj];
            subpx_scratch.xi[scratch_idx] = write_xi_arr[jj];
            subpx_scratch.eta[scratch_idx] = write_eta_arr[jj];
            subpx_scratch.mask[scratch_idx] = true;
        }

        if (ctx_rast.config.newton_seed_reuse == .last_converged) {
            newton.updateSeedStateFromSIMDResult(
                &seed_state,
                v_chunk_mask,
                result.v_mask,
                result.v_xi_out,
                result.v_eta_out,
                result.v_residual_x,
                result.v_residual_y,
            );
        }
    }

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;

        var scratch_x_u = rast_bounds.start_x_u;
        while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
            const scratch_idx = row_offset + scratch_x_u;
            var mask_arr: [S]bool = undefined;
            @memcpy(
                &mask_arr,
                subpx_scratch.mask[scratch_idx .. scratch_idx + S],
            );
            const v_mask_full: VecSB = mask_arr;

            const v_scratch_x_u: VecSU = @splat(scratch_x_u);
            const v_x_mask = (v_scratch_x_u + v_lane_idx >= v_orig_start_x_u) &
                (v_scratch_x_u + v_lane_idx < v_bounds_end_x_u);
            const v_mask_active = v_mask_full & v_x_mask;
            if (!@reduce(.Or, v_mask_active)) continue;

            var xi_arr: [S]f64 = undefined;
            var eta_arr: [S]f64 = undefined;
            const xi_slice = subpx_scratch.xi[scratch_idx .. scratch_idx + S];
            const eta_slice = subpx_scratch.eta[scratch_idx .. scratch_idx + S];
            @memcpy(&xi_arr, xi_slice);
            @memcpy(&eta_arr, eta_slice);
            const v_xi: VecSF = xi_arr;
            const v_eta: VecSF = eta_arr;

            var v_weights: [N]VecSF = undefined;
            var v_dNu: [N]VecSF = undefined;
            var v_dNv: [N]VecSF = undefined;
            shapefun.shapeFunctionsSIMD(
                N,
                v_xi,
                v_eta,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            var v_sum_z: VecSF = @splat(0.0);
            inline for (0..N) |nn| v_sum_z += v_weights[nn] * v_nodes_z[nn];
            const v_inv_z: VecSF = @as(VecSF, @splat(1.0)) / v_sum_z;

            const v_old_inv_z = simdops.loadVecSF(
                subpx_scratch.inv_z,
                scratch_idx,
            );
            const v_depth_tol: VecSF =
                @splat(tol.geometry.depth_buffer_inv_z_cmp);
            const v_depth_mask =
                v_mask_active & (v_inv_z + v_depth_tol >= v_old_inv_z);
            if (!@reduce(.Or, v_depth_mask)) continue;

            const v_new_inv_z = @select(
                f64,
                v_depth_mask,
                v_inv_z,
                v_old_inv_z,
            );
            simdops.storeVecSF(
                subpx_scratch.inv_z,
                scratch_idx,
                v_new_inv_z,
            );
            const v_subpx_z: VecSF = @as(VecSF, @splat(1.0)) / v_inv_z;

            const lane_depth_mask: [S]bool = v_depth_mask;
            inline for (0..S) |ll| {
                if (lane_depth_mask[ll]) {
                    const touched_x_u = scratch_x_u + ll;
                    if (touched_x_u < subpx_scratch.touched_min_x[scratch_y_u]) {
                        subpx_scratch.touched_min_x[scratch_y_u] = touched_x_u;
                    }
                    if (touched_x_u > subpx_scratch.touched_max_x[scratch_y_u]) {
                        subpx_scratch.touched_max_x[scratch_y_u] = touched_x_u;
                    }
                }
            }

            const v_hit_one: VecSU8 = @splat(1);
            const v_hit_zero: VecSU8 = @splat(0);
            const v_hit_count = @select(u8, v_depth_mask, v_hit_one, v_hit_zero);
            shaded_px += @intCast(@reduce(.Add, v_hit_count));

            const ctx_shade = shaderops.ShadeContext(N){
                .frame_idx = ctx_rast.frame_idx,
                .elem_idx = targ_overlap.overlap.elem_idx,
                .fields_num = fields_num,
                .actual_fields = fields_num,
                .scratch_idx = scratch_idx,
                .global_subx = targ_overlap.tile.scratch_x_px_min * sub_samp + scratch_x_u,
                .global_suby = targ_overlap.tile.scratch_y_px_min * sub_samp + scratch_y_u,
                .shader_buf = shader_buf,
                .v_mask_active = v_depth_mask,
            };

            ShaderKernel.shadeSIMD(
                GeometryKernel.coord_space,
                ctx_shade,
                ctx_report,
                v_depth_mask,
                v_weights,
                v_xi,
                v_eta,
                v_nodes_inv_z,
                v_subpx_z,
                shader,
                &subpx_scratch.image,
            );
        }
    }

    return shaded_px;
}

fn rasterDirectImpl(
    comptime GeometryKernel: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: common.OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    nodes_coords: Vec3Slices(f64),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(GeometryKernel.nodes_num),
    subpx_scratch: *SubpxScratchBuffers,
) !u64 {
    std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);
    return common.rasterDirectScalarCommon(
        GeometryKernel,
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

//------------------------------------------------------------------------------------------
// External API
//------------------------------------------------------------------------------------------

pub fn rasterScene(
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    requested_workers: u16,
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
        requested_workers,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );
}
