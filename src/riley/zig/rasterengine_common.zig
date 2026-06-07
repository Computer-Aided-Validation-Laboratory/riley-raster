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
const cfg = buildconfig.config;
const SimdWidth = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const rastcfg = @import("rasterconfig.zig");
const cam = @import("camera.zig");
const ReportMode = rastcfg.ReportMode;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const report = @import("report.zig");
const rasterreport = @import("rasterreport.zig");
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const mo = @import("meshops.zig");
const MeshPrepared = mo.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const FuncPrepared = shaderops.FuncPrepared;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");

pub const OverlapTarget = struct {
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
};

pub const SubpxDomain = struct {
    step: f64,
    offset: f64,
    tile_size: usize,
    x_off: f64,
    y_off: f64,
};

pub const RasterBounds = struct {
    start_x_u: usize,
    end_x_u: usize,
    start_y_u: usize,
    end_y_u: usize,
    x_min_f: f64,
    y_min_f: f64,
};

pub const ScratchTileGeometry = struct {
    core_w_px: usize,
    core_h_px: usize,
    scratch_w_px: usize,
    scratch_h_px: usize,
    scratch_w_subpx: usize,
    scratch_h_subpx: usize,
    core_start_x_subpx: usize,
    core_start_y_subpx: usize,

    pub fn init(tile: rops.ActiveTile, sub_sample: usize) ScratchTileGeometry {
        const core_w_px = @as(usize, tile.x_px_max - tile.x_px_min);
        const core_h_px = @as(usize, tile.y_px_max - tile.y_px_min);
        const scratch_w_px = @as(usize, tile.scratch_x_px_max - tile.scratch_x_px_min);
        const scratch_h_px = @as(usize, tile.scratch_y_px_max - tile.scratch_y_px_min);
        return .{
            .core_w_px = core_w_px,
            .core_h_px = core_h_px,
            .scratch_w_px = scratch_w_px,
            .scratch_h_px = scratch_h_px,
            .scratch_w_subpx = scratch_w_px * sub_sample,
            .scratch_h_subpx = scratch_h_px * sub_sample,
            .core_start_x_subpx = (@as(usize, tile.x_px_min - tile.scratch_x_px_min)) * sub_sample,
            .core_start_y_subpx = (@as(usize, tile.y_px_min - tile.scratch_y_px_min)) * sub_sample,
        };
    }
};

pub const ScratchLayout = enum {
    subpx_major,
    field_major,
};

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

            subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 0] =
                slice[row_off + col_off + 0];
            subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 1] =
                slice[row_off + col_off + 1];
        }
    }
}

const ParamCoords = struct { xi: f64, eta: f64 };

fn calcTri3PerspectiveParamCoords(
    inv_z: f64,
    nodes_inv_z: [3]f64,
    weights: [3]f64,
) ParamCoords {
    return .{
        .xi = weights[1] * nodes_inv_z[1] / inv_z,
        .eta = weights[2] * nodes_inv_z[2] / inv_z,
    };
}

pub fn calcInterpParamCoords(
    comptime Geometry: type,
    nodes_inv_z: [Geometry.nodes_num]f64,
    weights: [Geometry.nodes_num]f64,
    inv_z: f64,
    xi_out: f64,
    eta_out: f64,
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
    nodes_coords: rops.Vec3Slices(f64),
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

    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const scratch_idx = row_offset + scratch_x_u;
            const ideal_x_px = subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 0];
            const ideal_y_px = subpx_scratch.ideal_pixel_centers[scratch_idx * 2 + 1];

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
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
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
                    .tex => 1,
                    .tex_rgb => 3,
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
                    .tex => |*shader| {
                        const SK = shadekerns.TexKernel(N, 1);
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
                            TexPrepared(1),
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
                    .tex_rgb => |*shader| {
                        const SK = shadekerns.TexKernel(N, 3);
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
                            TexPrepared(3),
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
                        if (shader.elem_uvs != null) {
                            local_shader_buf.load(
                                shader.elem_uvs.?,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
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
                        if (shader.elem_uvs != null) {
                            local_shader_buf.load(
                                shader.elem_uvs.?,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
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

    if (ctx_rast.camera.prepared_psf.hasFilter()) {
        resolveTileWithPSF(
            RasterBackend.scratch_layout,
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
        averageScratch(
            RasterBackend.scratch_layout,
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
        resolveScratchDirect(
            RasterBackend.scratch_layout,
            tile,
            subpx_tile_size,
            fields_num,
            &subpx_scratch.image,
            subpx_scratch.touched_min_x,
            subpx_scratch.touched_max_x,
            image_out_arr,
        );
    }

    rasterreport.finishTile(
        report_mode,
        io,
        ctx_report,
        ctx_rast,
        tile,
        tile_scope,
        shaded_px,
        overlaps.len,
    );
}

pub inline fn getScratchField(
    comptime scratch_layout: ScratchLayout,
    spx_image_scratch: *const MatSlice(f64),
    scratch_flat_idx: usize,
    field_idx: usize,
) f64 {
    return switch (scratch_layout) {
        .subpx_major => spx_image_scratch.get(scratch_flat_idx, field_idx),
        .field_major => spx_image_scratch.get(field_idx, scratch_flat_idx),
    };
}

pub inline fn setScratchField(
    comptime scratch_layout: ScratchLayout,
    spx_image_scratch: *MatSlice(f64),
    scratch_flat_idx: usize,
    field_idx: usize,
    val: f64,
) void {
    switch (scratch_layout) {
        .subpx_major => spx_image_scratch.set(scratch_flat_idx, field_idx, val),
        .field_major => spx_image_scratch.set(field_idx, scratch_flat_idx, val),
    }
}

const FrameImageWriter = struct {
    slice: []f64,
    field_stride: usize,
    row_stride: usize,

    inline fn init(image_out_arr: *NDArray(f64)) FrameImageWriter {
        return .{
            .slice = image_out_arr.slice,
            .field_stride = image_out_arr.strides[0],
            .row_stride = image_out_arr.strides[1],
        };
    }

    inline fn set(self: *const FrameImageWriter, field_idx: usize, row_idx: usize, col_idx: usize, val: f64) void {
        self.slice[field_idx * self.field_stride + row_idx * self.row_stride + col_idx] = val;
    }

    inline fn pixelBase(self: *const FrameImageWriter, row_idx: usize, col_idx: usize) usize {
        return row_idx * self.row_stride + col_idx;
    }
};

inline fn loadScratchRowSimd(
    comptime scratch_layout: ScratchLayout,
    src: *const MatSlice(f64),
    x: isize,
    y: isize,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    field_idx: usize,
    background_value: f64,
) VecSF {
    const cols_num = src.cols_num;
    if (y < 0 or y >= @as(isize, @intCast(scratch_geom.scratch_h_subpx))) {
        return @as(VecSF, @splat(background_value));
    }
    const uy = @as(usize, @intCast(y));

    const chunk_in_bounds = (x >= 0 and
        x + @as(isize, @intCast(SimdWidth)) <=
        @as(isize, @intCast(scratch_geom.scratch_w_subpx)));

    if (chunk_in_bounds) {
        const ux = @as(usize, @intCast(x));
        const flat_idx = uy * spx_stride + ux;
        if (scratch_layout == .field_major) {
            const offset = field_idx * cols_num + flat_idx;
            return @as(*const [SimdWidth]f64, @ptrCast(&src.slice[offset])).*;
        }
    }

    var result: [SimdWidth]f64 = undefined;
    var ii: usize = 0;
    while (ii < SimdWidth) : (ii += 1) {
        result[ii] = sampleScratchOrBackground(
            scratch_layout,
            src,
            x + @as(isize, @intCast(ii)),
            y,
            scratch_geom,
            spx_stride,
            field_idx,
            background_value,
        );
    }
    return result;
}

inline fn storeScratchRowSimd(
    comptime scratch_layout: ScratchLayout,
    dst: *MatSlice(f64),
    x: usize,
    y: usize,
    spx_stride: usize,
    field_idx: usize,
    val_vec: VecSF,
) void {
    const cols_num = dst.cols_num;
    const flat_idx = y * spx_stride + x;
    if (scratch_layout == .field_major) {
        const offset = field_idx * cols_num + flat_idx;
        @as(*[SimdWidth]f64, @ptrCast(&dst.slice[offset])).* = val_vec;
    } else {
        var ii: usize = 0;
        while (ii < SimdWidth) : (ii += 1) {
            setScratchField(
                scratch_layout,
                dst,
                flat_idx + ii,
                field_idx,
                val_vec[ii],
            );
        }
    }
}

pub fn resolveScratchDirect(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(f64),
) void {
    const dummy_geom = ScratchTileGeometry{
        .scratch_w_px = tile.x_px_max - tile.x_px_min,
        .scratch_h_px = tile.y_px_max - tile.y_px_min,
        .scratch_w_subpx = tile.x_px_max - tile.x_px_min,
        .scratch_h_subpx = tile.y_px_max - tile.y_px_min,
        .core_w_px = tile.x_px_max - tile.x_px_min,
        .core_h_px = tile.y_px_max - tile.y_px_min,
        .core_start_x_subpx = 0,
        .core_start_y_subpx = 0,
    };
    resolveScratchDirectCore(
        scratch_layout,
        tile,
        dummy_geom,
        spx_tile_size,
        fields_num,
        spx_image_scratch,
        touched_min_x,
        touched_max_x,
        0,
        0,
        image_out_arr,
    );
}

fn resolveScratchDirectCore(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    radius_x: usize,
    radius_y: usize,
    image_out_arr: *NDArray(f64),
) void {
    const writer = FrameImageWriter.init(image_out_arr);

    var ii: usize = 0;
    while (ii < scratch_geom.core_h_px) : (ii += 1) {
        const image_px_y = tile.y_px_min + ii;
        const spx_start_y = scratch_geom.core_start_y_subpx + ii;

        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;

        const start_y = if (spx_start_y >= radius_y) spx_start_y - radius_y else 0;
        const end_y = @min(scratch_geom.scratch_h_subpx - 1, spx_start_y + radius_y);

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) {
            continue;
        }

        const active_subpx_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_subpx_max = max_x + radius_x;

        var tx_start: usize = 0;
        if (active_subpx_min > scratch_geom.core_start_x_subpx) {
            tx_start = active_subpx_min - scratch_geom.core_start_x_subpx;
        }
        var tx_end: usize = scratch_geom.core_w_px - 1;
        if (active_subpx_max >= scratch_geom.core_start_x_subpx) {
            const calculated_end = active_subpx_max - scratch_geom.core_start_x_subpx;
            if (calculated_end < tx_end) {
                tx_end = calculated_end;
            }
        } else {
            continue;
        }

        const scratch_row_offset = spx_start_y * spx_stride;

        var jj = tx_start;
        while (jj <= tx_end) : (jj += 1) {
            const image_px_x = tile.x_px_min + jj;
            const scratch_flat_idx = scratch_row_offset +
                scratch_geom.core_start_x_subpx + jj;
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            if (fields_num == 1) {
                writer.slice[image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    0,
                );
            } else if (fields_num == 3) {
                writer.slice[image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    0,
                );
                writer.slice[writer.field_stride + image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    1,
                );
                writer.slice[2 * writer.field_stride + image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    2,
                );
            } else {
                var ff: usize = 0;
                while (ff < @as(usize, fields_num)) : (ff += 1) {
                    writer.slice[ff * writer.field_stride + image_px_base] =
                        getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        ff,
                    );
                }
            }
        }
    }
}

pub fn averageScratch(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(f64),
) void {
    const dummy_geom = ScratchTileGeometry{
        .scratch_w_px = tile.x_px_max - tile.x_px_min,
        .scratch_h_px = tile.y_px_max - tile.y_px_min,
        .scratch_w_subpx = (tile.x_px_max - tile.x_px_min) * sub_samp,
        .scratch_h_subpx = (tile.y_px_max - tile.y_px_min) * sub_samp,
        .core_w_px = tile.x_px_max - tile.x_px_min,
        .core_h_px = tile.y_px_max - tile.y_px_min,
        .core_start_x_subpx = 0,
        .core_start_y_subpx = 0,
    };
    averageScratchCore(
        scratch_layout,
        tile,
        dummy_geom,
        sub_samp,
        spx_tile_size,
        fields_num,
        spx_image_scratch,
        touched_min_x,
        touched_max_x,
        0,
        0,
        image_out_arr,
    );
}

fn averageScratchCore(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    radius_x: usize,
    radius_y: usize,
    image_out_arr: *NDArray(f64),
) void {
    if (cfg.resolve_scratch_simd == .on and scratch_layout == .field_major) {
        averageScratchCoreSIMD(
            scratch_layout,
            tile,
            scratch_geom,
            sub_samp,
            spx_stride,
            fields_num,
            spx_image_scratch,
            touched_min_x,
            touched_max_x,
            radius_x,
            radius_y,
            image_out_arr,
        );
        return;
    }

    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    const writer = FrameImageWriter.init(image_out_arr);

    var ii: usize = 0;
    while (ii < scratch_geom.core_h_px) : (ii += 1) {
        const image_px_y = tile.y_px_min + ii;
        const spx_start_y = scratch_geom.core_start_y_subpx + sub_samp * ii;

        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;

        const start_y = if (spx_start_y >= radius_y) spx_start_y - radius_y else 0;
        const end_y = @min(
            scratch_geom.scratch_h_subpx - 1,
            spx_start_y + sub_samp - 1 + radius_y,
        );

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) {
            continue;
        }

        const active_subpx_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_subpx_max = max_x + radius_x;

        var tx_start: usize = 0;
        if (active_subpx_min > scratch_geom.core_start_x_subpx) {
            tx_start = (active_subpx_min - scratch_geom.core_start_x_subpx) / sub_samp;
        }
        var tx_end: usize = scratch_geom.core_w_px - 1;
        if (active_subpx_max >= scratch_geom.core_start_x_subpx) {
            const calculated_end =
                (active_subpx_max - scratch_geom.core_start_x_subpx) / sub_samp;
            if (calculated_end < tx_end) {
                tx_end = calculated_end;
            }
        } else {
            continue;
        }

        var jj = tx_start;
        while (jj <= tx_end) : (jj += 1) {
            const image_px_x = tile.x_px_min + jj;
            const spx_start_x = scratch_geom.core_start_x_subpx + sub_samp * jj;
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            if (fields_num == 1) {
                var field_sum_0: f64 = 0.0;
                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset + spx_start_x + col_idx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                    }
                }
                writer.slice[image_px_base] = field_sum_0 * inv_sub_samp_sq;
            } else if (fields_num == 3) {
                var field_sum_0: f64 = 0.0;
                var field_sum_1: f64 = 0.0;
                var field_sum_2: f64 = 0.0;
                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset + spx_start_x + col_idx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                        field_sum_1 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            1,
                        );
                        field_sum_2 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            2,
                        );
                    }
                }
                writer.slice[image_px_base] = field_sum_0 * inv_sub_samp_sq;
                writer.slice[writer.field_stride + image_px_base] =
                    field_sum_1 * inv_sub_samp_sq;
                writer.slice[2 * writer.field_stride + image_px_base] =
                    field_sum_2 * inv_sub_samp_sq;
            } else {
                var field_avg_buff = [_]f64{0.0} ** cfg.max_nodal_fields;
                const spx_field_avg = field_avg_buff[0..@as(usize, fields_num)];
                @memset(spx_field_avg, 0.0);

                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset + spx_start_x + col_idx;
                        var ff: usize = 0;
                        while (ff < @as(usize, fields_num)) : (ff += 1) {
                            spx_field_avg[ff] += getScratchField(
                                scratch_layout,
                                spx_image_scratch,
                                scratch_flat_idx,
                                ff,
                            );
                        }
                    }
                }

                var ff: usize = 0;
                while (ff < @as(usize, fields_num)) : (ff += 1) {
                    writer.slice[ff * writer.field_stride + image_px_base] =
                        spx_field_avg[ff] * inv_sub_samp_sq;
                }
            }
        }
    }
}

fn averageScratchCoreSIMD(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    radius_x: usize,
    radius_y: usize,
    image_out_arr: *NDArray(f64),
) void {
    const cols_num = spx_image_scratch.cols_num;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    const writer = FrameImageWriter.init(image_out_arr);

    var ii: usize = 0;
    while (ii < scratch_geom.core_h_px) : (ii += 1) {
        const image_px_y = tile.y_px_min + ii;
        const spx_start_y = scratch_geom.core_start_y_subpx + sub_samp * ii;

        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;

        const start_y = if (spx_start_y >= radius_y) spx_start_y - radius_y else 0;
        const end_y = @min(
            scratch_geom.scratch_h_subpx - 1,
            spx_start_y + sub_samp - 1 + radius_y,
        );

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) {
            continue;
        }

        const active_subpx_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_subpx_max = max_x + radius_x;

        var tx_start: usize = 0;
        if (active_subpx_min > scratch_geom.core_start_x_subpx) {
            tx_start = (active_subpx_min - scratch_geom.core_start_x_subpx) / sub_samp;
        }
        var tx_end: usize = scratch_geom.core_w_px - 1;
        if (active_subpx_max >= scratch_geom.core_start_x_subpx) {
            const calculated_end =
                (active_subpx_max - scratch_geom.core_start_x_subpx) / sub_samp;
            if (calculated_end < tx_end) {
                tx_end = calculated_end;
            }
        } else {
            continue;
        }

        var jj = tx_start;
        while (jj <= tx_end) : (jj += 1) {
            const image_px_x = tile.x_px_min + jj;
            const spx_start_x = scratch_geom.core_start_x_subpx + sub_samp * jj;
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            var ff: usize = 0;
            while (ff < @as(usize, fields_num)) : (ff += 1) {
                var field_sum: f64 = 0.0;

                if (sub_samp == 8 and SimdWidth == 8) {
                    var sum_vec = @as(VecSF, @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 8) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                        const scratch_flat_idx = scratch_row_offset + spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [8]f64,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else if (sub_samp == 4) {
                    var sum_vec = @as(@Vector(4, f64), @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 4) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                        const scratch_flat_idx = scratch_row_offset + spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [4]f64,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else if (sub_samp == 2) {
                    var sum_vec = @as(@Vector(2, f64), @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 2) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                        const scratch_flat_idx = scratch_row_offset + spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [2]f64,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else {
                    var row_idx: usize = 0;
                    while (row_idx < sub_samp) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) * spx_stride;
                        var col_idx: usize = 0;
                        while (col_idx < sub_samp) {
                            if (col_idx + SimdWidth <= sub_samp) {
                                const scratch_flat_idx = scratch_row_offset +
                                    spx_start_x + col_idx;
                                const offset = ff * cols_num + scratch_flat_idx;
                                const val_vec = @as(
                                    VecSF,
                                    @as(
                                        *const [SimdWidth]f64,
                                        @ptrCast(&spx_image_scratch.slice[offset]),
                                    ).*,
                                );
                                field_sum += @reduce(.Add, val_vec);
                                col_idx += SimdWidth;
                            } else {
                                const scratch_flat_idx = scratch_row_offset +
                                    spx_start_x + col_idx;
                                field_sum += getScratchField(
                                    scratch_layout,
                                    spx_image_scratch,
                                    scratch_flat_idx,
                                    ff,
                                );
                                col_idx += 1;
                            }
                        }
                    }
                }
                writer.slice[ff * writer.field_stride + image_px_base] =
                    field_sum * inv_sub_samp_sq;
            }
        }
    }
}

fn sampleScratchOrBackground(
    comptime scratch_layout: ScratchLayout,
    src: *const MatSlice(f64),
    x: isize,
    y: isize,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    field_idx: usize,
    background_value: f64,
) f64 {
    if (x < 0 or y < 0 or
        x >= @as(isize, @intCast(scratch_geom.scratch_w_subpx)) or
        y >= @as(isize, @intCast(scratch_geom.scratch_h_subpx)))
    {
        return background_value;
    }
    const flat_idx = @as(usize, @intCast(y)) * spx_stride + @as(usize, @intCast(x));
    return getScratchField(scratch_layout, src, flat_idx, field_idx);
}

fn filterScratchSeparable(
    comptime scratch_layout: ScratchLayout,
    fields_num: u8,
    background_value: f64,
    psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    src: *const MatSlice(f64),
    tmp: *MatSlice(f64),
    dst: *MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
) void {
    tmp.fill(background_value);

    const radius_x = psf.radius_x_subpx;
    const radius_y = psf.radius_y_subpx;

    // Horizontal pass
    var yy: usize = 0;
    while (yy < scratch_geom.scratch_h_subpx) : (yy += 1) {
        const min_x = touched_min_x[yy];
        const max_x = touched_max_x[yy];
        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            if (cfg.resolve_scratch_simd == .on and scratch_layout == .field_major) {
                var xx = xx_start;
                while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                    var sum_h_vec = @as(VecSF, @splat(0.0));
                    var kk: usize = 0;
                    while (kk < psf.weights_x.len) : (kk += 1) {
                        const x_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_x));
                        const input_vec = loadScratchRowSimd(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)),
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                        sum_h_vec += input_vec * @as(
                            VecSF,
                            @splat(psf.weights_x[kk]),
                        );
                    }
                    storeScratchRowSimd(
                        scratch_layout,
                        tmp,
                        xx,
                        yy,
                        spx_stride,
                        ff,
                        sum_h_vec,
                    );
                }

                // Scalar tail
                while (xx <= xx_end) : (xx += 1) {
                    var sum_h: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_x.len) : (kk += 1) {
                        const x_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_x));
                        sum_h += psf.weights_x[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)),
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        tmp,
                        yy * spx_stride + xx,
                        ff,
                        sum_h,
                    );
                }
            } else {
                // Scalar path
                var xx = xx_start;
                while (xx <= xx_end) : (xx += 1) {
                    var sum_h: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_x.len) : (kk += 1) {
                        const x_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_x));
                        sum_h += psf.weights_x[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)),
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        tmp,
                        yy * spx_stride + xx,
                        ff,
                        sum_h,
                    );
                }
            }
        }
    }

    // Vertical pass
    dst.fill(background_value);
    yy = scratch_geom.core_start_y_subpx;
    const core_end_y = scratch_geom.core_start_y_subpx +
        scratch_geom.core_h_px * sub_samp - 1;
    while (yy <= core_end_y) : (yy += 1) {
        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;
        const start_y = if (yy >= radius_y) yy - radius_y else 0;
        const end_y = @min(scratch_geom.scratch_h_subpx - 1, yy + radius_y);

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            if (cfg.resolve_scratch_simd == .on and scratch_layout == .field_major) {
                var xx = xx_start;
                while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                    var sum_v_vec = @as(VecSF, @splat(0.0));
                    var kk: usize = 0;
                    while (kk < psf.weights_y.len) : (kk += 1) {
                        const y_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_y));
                        const input_vec = loadScratchRowSimd(
                            scratch_layout,
                            tmp,
                            @as(isize, @intCast(xx)),
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                        sum_v_vec += input_vec * @as(
                            VecSF,
                            @splat(psf.weights_y[kk]),
                        );
                    }
                    storeScratchRowSimd(
                        scratch_layout,
                        dst,
                        xx,
                        yy,
                        spx_stride,
                        ff,
                        sum_v_vec,
                    );
                }

                // Scalar tail
                while (xx <= xx_end) : (xx += 1) {
                    var sum_v: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_y.len) : (kk += 1) {
                        const y_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_y));
                        sum_v += psf.weights_y[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            tmp,
                            @as(isize, @intCast(xx)),
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        dst,
                        yy * spx_stride + xx,
                        ff,
                        sum_v,
                    );
                }
            } else {
                // Scalar path
                var xx = xx_start;
                while (xx <= xx_end) : (xx += 1) {
                    var sum_v: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_y.len) : (kk += 1) {
                        const y_off = @as(
                            isize,
                            @intCast(kk),
                        ) - @as(isize, @intCast(radius_y));
                        sum_v += psf.weights_y[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            tmp,
                            @as(isize, @intCast(xx)),
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        dst,
                        yy * spx_stride + xx,
                        ff,
                        sum_v,
                    );
                }
            }
        }
    }
}

fn filterScratchNonSeparable(
    comptime scratch_layout: ScratchLayout,
    fields_num: u8,
    background_value: f64,
    psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    src: *const MatSlice(f64),
    dst: *MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
) void {
    dst.fill(background_value);

    const radius_x = psf.radius_x_subpx;
    const radius_y = psf.radius_y_subpx;
    const kernel_w = 2 * radius_x + 1;

    var yy = scratch_geom.core_start_y_subpx;
    const core_end_y = scratch_geom.core_start_y_subpx +
        scratch_geom.core_h_px * sub_samp - 1;
    while (yy <= core_end_y) : (yy += 1) {
        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;
        const start_y = if (yy >= radius_y) yy - radius_y else 0;
        const end_y = @min(scratch_geom.scratch_h_subpx - 1, yy + radius_y);

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            if (cfg.resolve_scratch_simd == .on and scratch_layout == .field_major) {
                var xx = xx_start;
                while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                    var sum_vec = @as(VecSF, @splat(0.0));
                    var kk: usize = 0;
                    while (kk < psf.weights_2d.len) : (kk += 1) {
                        const ky = kk / kernel_w;
                        const kx = kk % kernel_w;
                        const x_off = @as(
                            isize,
                            @intCast(kx),
                        ) - @as(isize, @intCast(radius_x));
                        const y_off = @as(
                            isize,
                            @intCast(ky),
                        ) - @as(isize, @intCast(radius_y));
                        const input_vec = loadScratchRowSimd(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                        sum_vec += input_vec * @as(
                            VecSF,
                            @splat(psf.weights_2d[kk]),
                        );
                    }
                    storeScratchRowSimd(
                        scratch_layout,
                        dst,
                        xx,
                        yy,
                        spx_stride,
                        ff,
                        sum_vec,
                    );
                }

                // Scalar tail
                while (xx <= xx_end) : (xx += 1) {
                    var sum: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_2d.len) : (kk += 1) {
                        const ky = kk / kernel_w;
                        const kx = kk % kernel_w;
                        const x_off = @as(
                            isize,
                            @intCast(kx),
                        ) - @as(isize, @intCast(radius_x));
                        const y_off = @as(
                            isize,
                            @intCast(ky),
                        ) - @as(isize, @intCast(radius_y));
                        sum += psf.weights_2d[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        dst,
                        yy * spx_stride + xx,
                        ff,
                        sum,
                    );
                }
            } else {
                // Scalar path
                var xx = xx_start;
                while (xx <= xx_end) : (xx += 1) {
                    var sum: f64 = 0.0;
                    var kk: usize = 0;
                    while (kk < psf.weights_2d.len) : (kk += 1) {
                        const ky = kk / kernel_w;
                        const kx = kk % kernel_w;
                        const x_off = @as(
                            isize,
                            @intCast(kx),
                        ) - @as(isize, @intCast(radius_x));
                        const y_off = @as(
                            isize,
                            @intCast(ky),
                        ) - @as(isize, @intCast(radius_y));
                        sum += psf.weights_2d[kk] * sampleScratchOrBackground(
                            scratch_layout,
                            src,
                            @as(isize, @intCast(xx)) + x_off,
                            @as(isize, @intCast(yy)) + y_off,
                            scratch_geom,
                            spx_stride,
                            ff,
                            background_value,
                        );
                    }
                    setScratchField(
                        scratch_layout,
                        dst,
                        yy * spx_stride + xx,
                        ff,
                        sum,
                    );
                }
            }
        }
    }
}

fn resolveTileWithPSF(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    background_value: f64,
    prepared_psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    spx_image_scratch: *MatSlice(f64),
    filter_tmp: *MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(f64),
) void {
    switch (prepared_psf.mode) {
        .identity_fast => {
            if (sub_samp > 1) {
                averageScratchCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    0,
                    0,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    0,
                    0,
                    image_out_arr,
                );
            }
        },
        .separable => {
            filterScratchSeparable(
                scratch_layout,
                fields_num,
                background_value,
                prepared_psf,
                scratch_geom,
                sub_samp,
                spx_stride,
                spx_image_scratch,
                filter_tmp,
                spx_image_scratch,
                touched_min_x,
                touched_max_x,
            );
            if (sub_samp > 1) {
                averageScratchCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            }
        },
        .nonseparable => {
            filterScratchNonSeparable(
                scratch_layout,
                fields_num,
                background_value,
                prepared_psf,
                scratch_geom,
                sub_samp,
                spx_stride,
                spx_image_scratch,
                filter_tmp,
                touched_min_x,
                touched_max_x,
            );
            if (sub_samp > 1) {
                averageScratchCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    filter_tmp,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    scratch_layout,
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    filter_tmp,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            }
        },
    }
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
        raster_hulls: []const ?NDArray(f64),
        image_out_arr: *NDArray(f64),
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
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
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
