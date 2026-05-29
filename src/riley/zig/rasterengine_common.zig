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
const rastcfg = @import("rasterconfig.zig");
const cam = @import("camera.zig");
const ReportMode = rastcfg.ReportMode;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const report = @import("report.zig");
const Timestamp = std.Io.Clock.Timestamp;
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const mo = @import("meshops.zig");
const MeshPrepared = mo.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const TexFuncPrepared = shaderops.TexFuncPrepared;
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

    const start_x = @as(usize, @intCast(tile.x_px_min)) * sub_samp;
    const start_y = @as(usize, @intCast(tile.y_px_min)) * sub_samp;
    const tile_w = @as(usize, tile.x_px_max - tile.x_px_min) * sub_samp;
    const tile_h = @as(usize, tile.y_px_max - tile.y_px_min) * sub_samp;

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

            const tile_subx: usize = @intCast(targ_overlap.tile.x_px_min);
            const tile_suby: usize = @intCast(targ_overlap.tile.y_px_min);
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
                ctx_report.recordEarlyOut(global_subx, global_suby, true);
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

            if (comptime report_mode == .full_stats) {
                if (result.weights) |weights| {
                    const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                    const interp = calcInterpParamCoords(
                        Geometry,
                        nodes_inv_z,
                        weights,
                        inv_z,
                        0.0,
                        0.0,
                    );
                    ctx_report.recordPixelConverged(
                        global_subx,
                        global_suby,
                        true,
                    );
                    ctx_report.recordPixelXi(
                        global_subx,
                        global_suby,
                        interp.xi,
                    );
                    ctx_report.recordPixelEta(
                        global_subx,
                        global_suby,
                        interp.eta,
                    );
                    ctx_report.recordPixelJacobianDet(
                        global_subx,
                        global_suby,
                        newton.calcJacobianDet2D(
                            N,
                            interp.xi,
                            interp.eta,
                            nodes_coords.x,
                            nodes_coords.y,
                        ),
                    );
                } else {
                    ctx_report.recordPixelConverged(
                        global_subx,
                        global_suby,
                        false,
                    );
                    ctx_report.recordPixelXi(
                        global_subx,
                        global_suby,
                        std.math.nan(f64),
                    );
                    ctx_report.recordPixelEta(
                        global_subx,
                        global_suby,
                        std.math.nan(f64),
                    );
                    ctx_report.recordPixelJacobianDet(
                        global_subx,
                        global_suby,
                        std.math.nan(f64),
                    );
                }
            }

            // If weights are not null we are inside the element and we need to check the
            // depth buffer
            if (result.weights) |weights| {
                const inv_z = Geometry.calcInvZ(nodes_coords, weights);

                if (inv_z >= subpx_scratch.inv_z[scratch_idx]) {
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
                        ctx_report.recordPixelIters(
                            global_subx,
                            global_suby,
                            result.iters,
                        );
                        ctx_report.recordPixelOccupancy(
                            targ_overlap.tile.x_px_min + scratch_x_u / sub_samp,
                            targ_overlap.tile.y_px_min + scratch_y_u / sub_samp,
                        );
                    }

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
            } else {
                if (result.iters > 0) ctx_report.recordSolverDiverged();
            }
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
    const tile_start = if (comptime report_mode == .full_stats)
        Timestamp.now(io, .awake)
    else {};

    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    RasterBackend.resetSubpxScratch(
        subpx_scratch,
        subpx_tile_size,
        ctx_rast.config.background_value,
    );

    switch (ctx_rast.config.subpixel_center_map) {
        .full_in_mem => fillTileIdealCentersFullInMem(
            ctx_rast,
            tile,
            subpx_scratch,
            subpx_tile_size,
        ),
        .per_tile => try cam.fillTileIdealCentersPerTile(
            ctx_rast,
            tile,
            subpx_scratch,
            subpx_tile_size,
        ),
        .affine_jac => cam.fillTileIdealCentersAffineJac(
            ctx_rast,
            tile,
            subpx_scratch,
            subpx_tile_size,
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
                    .tex_func => 1,
                    .tex_func_rgb => 3,
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
                    .tex_func => |*shader| {
                        const SK = shadekerns.TexFuncKernel(N, 1);
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
                            TexFuncPrepared(1),
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
                    .tex_func_rgb => |*shader| {
                        const SK = shadekerns.TexFuncKernel(N, 3);
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
                            TexFuncPrepared(3),
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

    if (sub_samp > 1) {
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
    ctx_report.recordTile(
        spatial_idx,
        @intCast(tile_duration_ns),
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

pub fn resolveScratchDirect(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;
    const writer = FrameImageWriter.init(image_out_arr);

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const scratch_row_offset = ty * spx_tile_size;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const scratch_flat_idx = scratch_row_offset + tx;
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
                for (0..@as(usize, fields_num)) |ff| {
                    writer.slice[ff * writer.field_stride + image_px_base] = getScratchField(
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
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    var field_avg_buff = [_]f64{0.0} ** cfg.max_nodal_fields;
    const spx_field_avg = field_avg_buff[0..@as(usize, fields_num)];
    const writer = FrameImageWriter.init(image_out_arr);

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
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            if (fields_num == 1) {
                var field_sum_0: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;
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

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;
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
                @memset(spx_field_avg, 0.0);

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;

                        for (0..@as(usize, fields_num)) |ff| {
                            spx_field_avg[ff] += getScratchField(
                                scratch_layout,
                                spx_image_scratch,
                                scratch_flat_idx,
                                ff,
                            );
                        }
                    }
                }

                for (0..@as(usize, fields_num)) |ff| {
                    writer.slice[ff * writer.field_stride + image_px_base] =
                        spx_field_avg[ff] * inv_sub_samp_sq;
                }
            }
        }
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
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
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
