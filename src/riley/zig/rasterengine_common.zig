// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const cfg = buildconfig.config;
const SimdWidth = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const rastcfg = @import("rasterconfig.zig");
const cam = @import("camera.zig");
const camcommon = @import("camera_common.zig");
const ReportMode = rastcfg.ReportMode;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const report = @import("report.zig");
const rasterreport = @import("rasterreport.zig");
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const pce = @import("parachunkexec.zig");
const scratchfilter = @import("scratchfilter.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const mo = @import("meshops.zig");
const MeshPrepared = mo.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const FuncPrepared = shaderops.FuncPrepared;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const Timestamp = std.Io.Clock.Timestamp;

pub const OverlapTarget = struct {
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
};

pub const SubpxDomain = struct {
    step: F,
    offset: F,
    tile_size: usize,
    x_off: F,
    y_off: F,
};

pub const RasterBounds = struct {
    start_x_u: usize,
    end_x_u: usize,
    start_y_u: usize,
    end_y_u: usize,
    x_min_f: F,
    y_min_f: F,
};

pub const ScratchTileGeometry = scratchfilter.ScratchTileGeometry;

fn fillTileIdealCentersFullInMem(
    ctx_rast: rops.RasterContext,
    tile: rops.ActiveTile,
    subpx_scratch: anytype,
    subpx_tile_size: usize,
) void {
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const camera_prepared = ctx_rast.camera;
    const stride_y = camera_prepared.ideal_pixel_centers.strides[0];
    const stride_x = camera_prepared.ideal_pixel_centers.strides[1];
    const slice = camera_prepared.ideal_pixel_centers.slice;
    const ideal_x_plane = camcommon.getIdealXPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );
    const ideal_y_plane = camcommon.getIdealYPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );

    const start_x = @as(usize, @intCast(tile.scratch_x_px_min)) * sub_samp;
    const start_y = @as(usize, @intCast(tile.scratch_y_px_min)) * sub_samp;
    const tile_w = @as(usize, tile.scratch_x_px_max - tile.scratch_x_px_min) * sub_samp;
    const tile_h = @as(usize, tile.scratch_y_px_max - tile.scratch_y_px_min) * sub_samp;

    for (0..tile_h) |jj| {
        const global_y = start_y + jj;
        const row_off = global_y * stride_y;
        const scratch_row_off = jj * subpx_tile_size;

        for (0..tile_w) |ii| {
            const global_x = start_x + ii;
            const col_off = global_x * stride_x;
            const scratch_idx = scratch_row_off + ii;

            ideal_x_plane[scratch_idx] = slice[row_off + col_off + 0];
            ideal_y_plane[scratch_idx] = slice[row_off + col_off + 1];
        }
    }
}

const ParamCoords = struct { xi: F, eta: F };

fn calcTri3PerspectiveParamCoords(
    inv_z: F,
    nodes_inv_z: [3]F,
    weights: [3]F,
) ParamCoords {
    return .{
        .xi = weights[1] * nodes_inv_z[1] / inv_z,
        .eta = weights[2] * nodes_inv_z[2] / inv_z,
    };
}

pub fn calcInterpParamCoords(
    comptime Geometry: type,
    nodes_inv_z: [Geometry.nodes_num]F,
    weights: [Geometry.nodes_num]F,
    inv_z: F,
    xi_out: F,
    eta_out: F,
) ParamCoords {
    if (comptime Geometry.solver_kind == .hyperb) {
        return calcTri3PerspectiveParamCoords(inv_z, nodes_inv_z, weights);
    }

    return .{ .xi = xi_out, .eta = eta_out };
}

//------------------------------------------------------------------------------------------
// Direct Raster Helper
//------------------------------------------------------------------------------------------

pub fn rasterDirectScalarCommon(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    comptime ScratchBuffers: type,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: OverlapTarget,
    mesh_in: rops.MeshRaster,
    subpx_domain: SubpxDomain,
    rast_bounds: RasterBounds,
    fields_num: u8,
    nodes_coords: rops.Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
    subpx_scratch: *ScratchBuffers,
) !u64 {
    comptime {
        if (Geometry.solver_kind == .newton) {
            @compileError("rasterDirectScalarCommon only supports non-Newton paths");
        }
    }

    const N = Geometry.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);

    var nodes_inv_z: [N]F = undefined;
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

    const ideal_x_plane = camcommon.getIdealXPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );
    const ideal_y_plane = camcommon.getIdealYPlaneScratch(
        subpx_scratch.ideal_pixel_centers,
    );

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const ideal_x_px = ideal_x_plane[scratch_idx];
            const ideal_y_px = ideal_y_plane[scratch_idx];

            const tile_subx: usize = @intCast(targ_overlap.tile.scratch_x_px_min);
            const tile_suby: usize = @intCast(targ_overlap.tile.scratch_y_px_min);
            const tile_subx_off: usize = tile_subx * sub_samp;
            const tile_suby_off: usize = tile_suby * sub_samp;
            const global_subx: usize = tile_subx_off +% scratch_x_u;
            const global_suby: usize = tile_suby_off +% scratch_y_u;

            if (comptime Geometry.hull_nodes_num > 0) {
                ctx_report.recordTessChecks(1);
                const tess_res = element_tess.isInScalar(ideal_x_px, ideal_y_px);
                if (tess_res.is_in) {
                    ctx_report.recordTessPasses(1);
                }
                rasterreport.recordEarlyOut(
                    report_mode,
                    ctx_report,
                    global_subx,
                    global_suby,
                    tess_res.is_in,
                );
                if (!tess_res.is_in) {
                    continue;
                }
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
            const result = if (comptime Geometry.solver_kind == .inv_bi)
                Geometry.solveWeightsInvBi(
                    ideal_x_px,
                    ideal_y_px,
                    subpx_domain.x_off,
                    subpx_domain.y_off,
                    bilinear_params,
                )
            else
                Geometry.solveWeightsHyperb(
                    nodes_coords,
                    ideal_x_px,
                    ideal_y_px,
                    inv_elem_area,
                );

            ctx_report.recordSolverIters(result.iters);

            if (result.weights == null) {
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
                if (result.iters > 0) ctx_report.recordSolverDiverged();
                continue;
            }

            const weights = result.weights.?;
            const inv_z = Geometry.calcInvZ(nodes_coords, weights);
            const interp = calcInterpParamCoords(
                Geometry,
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

            if (inv_z + cfg.tolerance.geometry.depth_buffer_inv_z_cmp <
                subpx_scratch.inv_z[scratch_idx]) continue;

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
                result.iters,
                targ_overlap.tile.scratch_x_px_min + scratch_x_u / sub_samp,
                targ_overlap.tile.scratch_y_px_min + scratch_y_u / sub_samp,
            );

            const param_coords = calcInterpParamCoords(
                Geometry,
                nodes_inv_z,
                weights,
                inv_z,
                result.xi_out,
                result.eta_out,
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
                .xi = param_coords.xi,
                .eta = param_coords.eta,
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

//------------------------------------------------------------------------------------------
// Tile Raster Helpers
//------------------------------------------------------------------------------------------

fn rasterTileCommon(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlaps_all: []const rops.OverlapBBox,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(F),
    image_out_arr: *NDArray(F),
    subpx_scratch: *RasterBackend.SubpxScratchBuffers,
    fields_num: u8,
    subpx_tile_size: usize,
) !void {
    const tile_scope = rasterreport.beginTile(report_mode, io);

    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const scratch_geom = ScratchTileGeometry.init(tile, sub_samp);
    RasterBackend.resetSubpxScratch(
        subpx_scratch,
        subpx_tile_size,
        ctx_rast.config.background_value,
    );

    const time_cam_start: ?Timestamp =
        if (comptime report_mode != .off)
            Timestamp.now(io, .awake)
        else
            null;

    switch (ctx_rast.camera.subpixel_center_map) {
        .full_in_mem => fillTileIdealCentersFullInMem(
            ctx_rast,
            tile,
            subpx_scratch,
            subpx_tile_size,
        ),
        .per_tile => try cam.fillTileIdealCentersPerTile(
            ctx_rast.camera,
            @intCast(tile.scratch_x_px_min),
            @intCast(tile.scratch_x_px_max),
            @intCast(tile.scratch_y_px_min),
            @intCast(tile.scratch_y_px_max),
            subpx_tile_size,
            subpx_scratch.ideal_pixel_centers,
        ),
        .affine_jac => cam.fillTileIdealCentersAffineJac(
            ctx_rast.camera,
            @intCast(tile.scratch_x_px_min),
            @intCast(tile.scratch_x_px_max),
            @intCast(tile.scratch_y_px_min),
            @intCast(tile.scratch_y_px_max),
            subpx_tile_size,
            subpx_scratch.ideal_pixel_centers,
        ),
    }

    const cam_duration_ns: u64 =
        if (comptime report_mode != .off)
            @intCast(
                time_cam_start.?.durationTo(
                    Timestamp.now(io, .awake),
                ).raw.nanoseconds,
            )
        else
            0;

    const overlap_start = tile.overlap_start;
    const overlap_end = overlap_start + tile.overlap_count;
    const overlaps = overlaps_all[overlap_start..overlap_end];

    for (overlaps) |ov| {
        const mesh_idx: usize = ov.mesh_idx;
        const mesh_ptr = &meshes[mesh_idx];
        const targ_overlap = OverlapTarget{ .tile = tile, .overlap = ov };

        std.debug.assert(mesh_idx < raster_hulls.len);
        const mesh_in = rops.MeshRaster{
            .coords = &mesh_ptr.coords,
            .hull = if (raster_hulls[mesh_idx]) |*h| h else null,
        };

        switch (mesh_ptr.mesh_type) {
            inline else => |geom_tag| {
                const GK = comptime switch (geom_tag) {
                    .tri3 => geomkerns.Tri3Kernel(),
                    .tri6 => geomkerns.Tri6Kernel(),
                    .quad4ibi => geomkerns.Quad4IBIKernel(),
                    .quad4newton => geomkerns.Quad4NewtonKernel(),
                    .quad8 => geomkerns.Quad89Kernel(8),
                    .quad9 => geomkerns.Quad89Kernel(9),
                };
                const N = GK.nodes_num;

                const mesh_fields_num: u8 = switch (mesh_ptr.shader) {
                    .nodal => |s| if (s.elem_field.dims.len == 3)
                        @intCast(s.elem_field.dims[1])
                    else
                        @intCast(s.elem_field.dims[2]),
                    .tex_u8, .tex_u16 => 1,
                    .tex_rgb_u8, .tex_rgb_u16 => 3,
                    .func => 1,
                    .func_rgb => 3,
                };

                switch (mesh_ptr.shader) {
                    .nodal => |*shader| {
                        const SK = shadekerns.NodalKernel(N);
                        var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                        const start_idx = if (shader.elem_field.dims.len == 3)
                            shader.elem_field.getFlatIdx(
                                &[_]usize{ targ_overlap.overlap.elem_idx, 0, 0 },
                            )
                        else blk: {
                            const tt = @min(
                                ctx_rast.frame_idx,
                                shader.elem_field.dims[0] - 1,
                            );
                            break :blk shader.elem_field.getFlatIdx(
                                &[_]usize{ tt, targ_overlap.overlap.elem_idx, 0, 0 },
                            );
                        };

                        local_shader_buf.load(
                            shader.elem_field,
                            start_idx,
                            mesh_fields_num,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            NodalPrepared,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
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

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u8, 1),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
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

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u16, 1),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
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

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u8, 3),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
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

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u16, 3),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .func => |*shader| {
                        const SK = shadekerns.FuncKernel(N, 1);
                        var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                        switch (shader.coord_mode) {
                            .uv => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_uvs.?,
                                    targ_overlap.overlap.elem_idx * 2 * N,
                                    2,
                                );
                            },
                            .world_reference => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_ref.?,
                                    targ_overlap.overlap.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .world_deformed => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_def.?,
                                    targ_overlap.overlap.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .parametric => {},
                        }
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            FuncPrepared(1),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .func_rgb => |*shader| {
                        const SK = shadekerns.FuncKernel(N, 3);
                        var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                        switch (shader.coord_mode) {
                            .uv => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_uvs.?,
                                    targ_overlap.overlap.elem_idx * 2 * N,
                                    2,
                                );
                            },
                            .world_reference => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_ref.?,
                                    targ_overlap.overlap.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .world_deformed => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_def.?,
                                    targ_overlap.overlap.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .parametric => {},
                        }
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            FuncPrepared(3),
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            targ_overlap,
                            mesh_in,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                }
            },
        }
    }

    const time_resolve_start: ?Timestamp =
        if (comptime report_mode != .off)
            Timestamp.now(io, .awake)
        else
            null;

    if (ctx_rast.camera.prepared_psf.hasFilter()) {
        scratchfilter.resolveTileWithPSF(
            tile,
            sub_samp,
            subpx_tile_size,
            fields_num,
            ctx_rast.config.background_value,
            ctx_rast.camera.prepared_psf,
            scratch_geom,
            &subpx_scratch.image,
            &subpx_scratch.filter_tmp,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    } else if (sub_samp > 1) {
        scratchfilter.averageScratch(
            tile,
            @intCast(sub_samp),
            subpx_tile_size,
            fields_num,
            &subpx_scratch.image,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    } else {
        scratchfilter.resolveScratchDirect(
            tile,
            subpx_tile_size,
            fields_num,
            &subpx_scratch.image,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    }

    const resolve_duration_ns: u64 =
        if (comptime report_mode != .off)
            @intCast(
                time_resolve_start.?.durationTo(
                    Timestamp.now(io, .awake),
                ).raw.nanoseconds,
            )
        else
            0;

    rasterreport.finishTile(
        report_mode,
        io,
        ctx_report,
        ctx_rast,
        tile,
        tile_scope,
        shaded_px,
        overlaps.len,
        cam_duration_ns,
        resolve_duration_ns,
    );
}

//------------------------------------------------------------------------------------------
// Scene Raster Execution Helpers
//------------------------------------------------------------------------------------------

fn initThreadReportLog(
    comptime report_mode: ReportMode,
) report.LogType(report_mode) {
    return switch (report_mode) {
        .off => .{},
        .bench => .{},
        .full_stats => unreachable,
    };
}

fn ThreadState(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        subpx_scratch: RasterBackend.SubpxScratchBuffers,
        log: report.LogType(report_mode),
    };
}

fn TileRangeContext(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
) type {
    const WorkerState = ThreadState(RasterBackend, report_mode);

    return struct {
        io: std.Io,
        ctx_rast: rops.RasterContext,
        tiling: rops.TilingOverlaps,
        meshes: []const MeshPrepared,
        raster_hulls: []const ?NDArray(F),
        image_out_arr: *NDArray(F),
        worker_states: []WorkerState,
        fields_num: u8,
        subpx_tile_size: usize,
    };
}

pub fn rasterSceneCommon(
    comptime RasterBackend: type,
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
    const WorkerState = comptime ThreadState(RasterBackend, report_mode);
    const TileRangeCtx = TileRangeContext(RasterBackend, report_mode);
    // ParaChunkExec expects a plain function pointer, so this adapter binds our
    // comptime RasterBackend and report_mode parameters into a concrete callback.
    const TileRangeWorkerAdapter = struct {
        fn run(
            ctx_ptr: *anyopaque,
            worker_idx: usize,
            range_start: usize,
            range_end: usize,
        ) anyerror!void {
            const tile_rng_ctx: *TileRangeCtx = @ptrCast(@alignCast(ctx_ptr));
            const worker_state = &tile_rng_ctx.worker_states[worker_idx];
            const ctx_report_task = report.ReportContext(report_mode){
                .log = &worker_state.log,
            };

            for (range_start..range_end) |tile_idx| {
                const tile = tile_rng_ctx.tiling.active_tiles[tile_idx];
                try rasterTileCommon(
                    RasterBackend,
                    report_mode,
                    tile_rng_ctx.io,
                    tile_rng_ctx.ctx_rast,
                    ctx_report_task,
                    tile,
                    tile_rng_ctx.tiling.overlaps,
                    tile_rng_ctx.meshes,
                    tile_rng_ctx.raster_hulls,
                    tile_rng_ctx.image_out_arr,
                    &worker_state.subpx_scratch,
                    tile_rng_ctx.fields_num,
                    tile_rng_ctx.subpx_tile_size,
                );
            }
        }
    };

    std.debug.assert(image_out_arr.dims[0] <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(image_out_arr.dims[0]);
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const scratch_tile_px: usize = @as(usize, @intCast(ctx_rast.tile_size)) +
        2 * @as(usize, ctx_rast.camera.prepared_psf.halo_px);
    const subpx_tile_size: usize = scratch_tile_px * sub_samp;
    const active_tiles_num = tiling.active_tiles.len;

    const worker_count = scalingpolicy.rasterWorkers(
        requested_workers,
        active_tiles_num,
    );
    const grain_size = scalingpolicy.rasterGrainSize(
        active_tiles_num,
        worker_count,
    );

    var worker_states = try outer_alloc.alloc(WorkerState, worker_count);
    defer {
        for (worker_states) |*worker_state| {
            worker_state.arena.deinit();
        }
        outer_alloc.free(worker_states);
    }
    for (0..worker_count) |ii| {
        worker_states[ii].arena = std.heap.ArenaAllocator.init(outer_alloc);
        const arena_alloc = worker_states[ii].arena.allocator();
        worker_states[ii].subpx_scratch = try RasterBackend.initSubpxScratch(
            arena_alloc,
            fields_num,
            subpx_tile_size,
        );
        worker_states[ii].log = initThreadReportLog(report_mode);
    }

    var tile_rng_ctx = TileRangeCtx{
        .io = io,
        .ctx_rast = ctx_rast,
        .tiling = tiling,
        .meshes = meshes,
        .raster_hulls = raster_hulls,
        .image_out_arr = image_out_arr,
        .worker_states = worker_states,
        .fields_num = fields_num,
        .subpx_tile_size = subpx_tile_size,
    };

    var chunk_exec = pce.ParaChunkExecutor.init(io, @intCast(worker_count));

    try pce.runDynamicRangeWithWorkerError(
        &chunk_exec,
        &tile_rng_ctx,
        TileRangeWorkerAdapter.run,
        active_tiles_num,
        grain_size,
    );

    if (report.getBenchLog(report_mode, ctx_report.log)) |bench_log| {
        for (worker_states) |*worker_state| {
            const worker_bench = report.getBenchLog(
                report_mode,
                &worker_state.log,
            ).?;
            report.reduceBenchLog(bench_log, worker_bench);
        }
    }
}
