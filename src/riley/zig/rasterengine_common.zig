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
const cfg = buildconfig.config;
const tol = cfg.tol;
const SimdWidth = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const rastcfg = @import("rasterconfig.zig");
const cam = @import("camera.zig");
const ReportMode = rastcfg.ReportMode;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const report = @import("report.zig");
const rasterreport = @import("rasterreport.zig");
const rops = @import("rasterfrontend.zig");
const bin = @import("elemtilebinning.zig");
const edgeops = @import("hulledge.zig");
const newton = @import("newton.zig");
const pce = @import("parachunkexec.zig");
const scratchresolve = @import("scratchresolve.zig");
const subpxframe = @import("subpxframe_globbuff.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const mo = @import("meshpipeline.zig");
const MeshPrepared = mo.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const FuncPrepared = shaderops.FuncPrepared;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const Timestamp = std.Io.Clock.Timestamp;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const SubpxDom = struct {
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

pub fn globalSubpxForReport(
    tile_px_min: i32,
    sub_samp: usize,
    scratch_subpx: usize,
) usize {
    const tile_subpx = tile_px_min * @as(i32, @intCast(sub_samp));
    const global_subpx = tile_subpx + @as(i32, @intCast(scratch_subpx));
    return @intCast(@max(0, global_subpx));
}

pub fn rasterDirectScalComm(
    comptime Geom: type,
    comptime ShaderKern: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    comptime ScratchBuffs: type,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: bin.ActiveTile,
    overlap: bin.OverlapBBox,
    subpx_dom: SubpxDom,
    rast_bounds: RasterBounds,
    fields_num: u8,
    nodes_coords: rops.Vec3Slices(F),
    shader: *const ShaderData,
    shader_buf: *const shaderops.LocalShaderBuff(Geom.nodes_num),
    subpx_scratch: *ScratchBuffs,
) !u64 {
    if (comptime Geom.solver_kind == .newton) {
        @compileError(
            "rasterDirectScalComm only supps non-Newton paths",
        );
    }

    const N = Geom.nodes_num;
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);

    var nodes_inv_z: [N]F = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
    }

    const inv_elem_area = if (comptime Geom.solver_kind == .hyperb)
        Geom.getInvElemArea(nodes_coords)
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

            const global_subx = globalSubpxForReport(
                tile.scratch_x_px_min,
                sub_samp,
                scratch_x_u,
            );
            const global_suby = globalSubpxForReport(
                tile.scratch_y_px_min,
                sub_samp,
                scratch_y_u,
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
            const geometry_result = switch (comptime Geom.solver_kind) {
                .hyperb => Geom.solveWeightsHyperb(
                    nodes_coords,
                    ideal_x_pix,
                    ideal_y_pix,
                    inv_elem_area,
                ),
                else => unreachable,
            };
            ctx_report.recordSolverIters(geometry_result.iters);

            const weights = geometry_result.weights orelse {
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
                if (geometry_result.iters > 0) {
                    ctx_report.recordSolverDiverged();
                }
                continue;
            };

            const inv_z = Geom.calcInvZ(nodes_coords, weights);
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

            if (comptime report_mode == .full_stats) {
                rasterreport.recordPixelIterAndOccupancy(
                    ctx_report,
                    global_subx,
                    global_suby,
                    geometry_result.iters,
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

            const xi = if (comptime Geom.solver_kind == .hyperb)
                weights[1] * nodes_inv_z[1] / inv_z
            else
                geometry_result.xi_out;
            const eta = if (comptime Geom.solver_kind == .hyperb)
                weights[2] * nodes_inv_z[2] / inv_z
            else
                geometry_result.eta_out;

            ShaderKern.shade(
                Geom.coord_space,
                shaderops.ShadeContext{
                    .frame_idx = ctx_rast.frame_idx,
                    .elem_idx = overlap.elem_idx,
                    .fields_num = fields_num,
                    .actual_fields = fields_num,
                    .scratch_idx = subpx_scratch.imageIndexCoord(
                        scratch_x_u,
                        scratch_y_u,
                        scratch_idx,
                    ),
                    .global_subx = global_subx,
                    .global_suby = global_suby,
                },
                shaderops.InterpData(Geom.nodes_num){
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

//------------------------------------------------------------------------------------------
// Direct Stepped Tri3 Fixed-Point Helpers
//------------------------------------------------------------------------------------------

pub const Tri3FixedEdges = struct {
    const Tri3FixedCoord = buildconfig.Tri3FixedCoord;
    const Tri3FixedSetup = buildconfig.Tri3FixedSetup;
    const Tri3FixedEdge = buildconfig.Tri3FixedEdge;
    const Tri3FixedFracBits = buildconfig.Tri3FixedFracBits;

    start: [3]Tri3FixedEdge,
    step_x: [3]Tri3FixedEdge,
    step_y: [3]Tri3FixedEdge,
    area: Tri3FixedEdge,
    inv_area: F,
    edge_tol: Tri3FixedEdge,
    sample_step: Tri3FixedEdge,

    fn quantiseCoord(value: F) ?Tri3FixedCoord {
        const scale_f: F = @floatFromInt(
            @as(Tri3FixedSetup, 1) << Tri3FixedFracBits,
        );
        const rounded = @round(value * scale_f);
        const min_f: F = @floatFromInt(std.math.minInt(Tri3FixedCoord));
        const max_f: F = @floatFromInt(std.math.maxInt(Tri3FixedCoord));
        if (!(rounded >= min_f and rounded <= max_f)) {
            return null;
        }
        return @intFromFloat(rounded);
    }

    fn fitsEdge(value: Tri3FixedSetup) bool {
        const min_edge: Tri3FixedSetup = std.math.minInt(Tri3FixedEdge);
        const max_edge: Tri3FixedSetup = std.math.maxInt(Tri3FixedEdge);
        return value >= min_edge and value <= max_edge;
    }

    fn narrowEdge(value: Tri3FixedSetup) ?Tri3FixedEdge {
        if (!fitsEdge(value)) {
            return null;
        }
        return std.math.cast(Tri3FixedEdge, value);
    }

    fn cornerFits(
        start: Tri3FixedSetup,
        step_x: Tri3FixedSetup,
        step_y: Tri3FixedSetup,
        x_steps: Tri3FixedSetup,
        y_steps: Tri3FixedSetup,
    ) bool {
        const x_val = start + x_steps * step_x;
        const y_val = start + y_steps * step_y;
        const xy_val = start + x_steps * step_x + y_steps * step_y;
        return fitsEdge(start) and
            fitsEdge(x_val) and
            fitsEdge(y_val) and
            fitsEdge(xy_val);
    }

    pub fn init(
        nodes_coords: rops.Vec3Slices(F),
        sub_samp: usize,
        start_subx_global: isize,
        start_suby_global: isize,
        max_x_steps: usize,
        max_y_steps: usize,
    ) ?@This() {
        const fixed_one: Tri3FixedSetup =
            @as(Tri3FixedSetup, 1) << Tri3FixedFracBits;
        const sub_samp_setup = std.math.cast(Tri3FixedSetup, sub_samp) orelse
            return null;
        const divisor = sub_samp_setup * 2;
        if (divisor == 0 or @mod(fixed_one, divisor) != 0) {
            return null;
        }

        const sample_step = @divExact(fixed_one, sub_samp_setup);
        const sample_offset = @divExact(sample_step, 2);
        const start_x_base = std.math.cast(Tri3FixedSetup, start_subx_global) orelse
            return null;
        const start_y_base = std.math.cast(Tri3FixedSetup, start_suby_global) orelse
            return null;
        const start_x_i = start_x_base * sample_step + sample_offset;
        const start_y_i = start_y_base * sample_step + sample_offset;

        const quant_x0 = quantiseCoord(nodes_coords.x[0]) orelse return null;
        const quant_y0 = quantiseCoord(nodes_coords.y[0]) orelse return null;
        const quant_x1 = quantiseCoord(nodes_coords.x[1]) orelse return null;
        const quant_y1 = quantiseCoord(nodes_coords.y[1]) orelse return null;
        const quant_x2 = quantiseCoord(nodes_coords.x[2]) orelse return null;
        const quant_y2 = quantiseCoord(nodes_coords.y[2]) orelse return null;

        const x0 = @as(Tri3FixedSetup, quant_x0) - start_x_i;
        const y0 = @as(Tri3FixedSetup, quant_y0) - start_y_i;
        const x1 = @as(Tri3FixedSetup, quant_x1) - start_x_i;
        const y1 = @as(Tri3FixedSetup, quant_y1) - start_y_i;
        const x2 = @as(Tri3FixedSetup, quant_x2) - start_x_i;
        const y2 = @as(Tri3FixedSetup, quant_y2) - start_y_i;

        var start = [3]Tri3FixedSetup{
            x2 * y1 - x1 * y2,
            x0 * y2 - x2 * y0,
            x1 * y0 - x0 * y1,
        };
        var step_x = [3]Tri3FixedSetup{
            (y2 - y1) * sample_step,
            (y0 - y2) * sample_step,
            (y1 - y0) * sample_step,
        };
        var step_y = [3]Tri3FixedSetup{
            (x1 - x2) * sample_step,
            (x2 - x0) * sample_step,
            (x0 - x1) * sample_step,
        };

        var area = start[0] + start[1] + start[2];
        if (area == 0) {
            return null;
        }
        if (area < 0) {
            area = -area;
            for (0..3) |ii| {
                start[ii] = -start[ii];
                step_x[ii] = -step_x[ii];
                step_y[ii] = -step_y[ii];
            }
        }

        const area_f: F = @floatFromInt(area);
        const edge_tol_mag = @ceil(
            tol.edge.tri_weight_inclusion * area_f,
        );
        if (!(edge_tol_mag >= 0.0)) {
            return null;
        }
        const edge_tol_setup = std.math.cast(
            Tri3FixedSetup,
            @as(i128, @intFromFloat(edge_tol_mag)),
        ) orelse return null;

        const max_x = std.math.cast(Tri3FixedSetup, max_x_steps) orelse
            return null;
        const max_y = std.math.cast(Tri3FixedSetup, max_y_steps) orelse
            return null;
        for (0..3) |ii| {
            if (!cornerFits(start[ii], step_x[ii], step_y[ii], max_x, max_y)) {
                return null;
            }
        }

        const start0 = narrowEdge(start[0]) orelse return null;
        const start1 = narrowEdge(start[1]) orelse return null;
        const start2 = narrowEdge(start[2]) orelse return null;
        const step_x0 = narrowEdge(step_x[0]) orelse return null;
        const step_x1 = narrowEdge(step_x[1]) orelse return null;
        const step_x2 = narrowEdge(step_x[2]) orelse return null;
        const step_y0 = narrowEdge(step_y[0]) orelse return null;
        const step_y1 = narrowEdge(step_y[1]) orelse return null;
        const step_y2 = narrowEdge(step_y[2]) orelse return null;
        const area_edge = narrowEdge(area) orelse return null;
        const edge_tol = narrowEdge(edge_tol_setup) orelse return null;
        const sample_step_edge = narrowEdge(sample_step) orelse return null;

        return .{
            .start = [3]Tri3FixedEdge{ start0, start1, start2 },
            .step_x = [3]Tri3FixedEdge{ step_x0, step_x1, step_x2 },
            .step_y = [3]Tri3FixedEdge{ step_y0, step_y1, step_y2 },
            .area = area_edge,
            .inv_area = 1.0 / area_f,
            .edge_tol = edge_tol,
            .sample_step = sample_step_edge,
        };
    }
};

fn fillTileIdealCentFullInMem(
    ctx_rast: rops.RasterContext,
    tile: bin.ActiveTile,
    subpx_scratch: anytype,
    subpx_tile_size: usize,
) void {
    ctx_rast.camera.fillTileIdealCentersPerTile(
        tile.scratch_x_px_min,
        tile.scratch_x_px_max,
        tile.scratch_y_px_min,
        tile.scratch_y_px_max,
        subpx_tile_size,
        subpx_scratch.ideal_pix_cent,
    ) catch unreachable;
}

fn fillTileIdealCent(
    ctx_rast: rops.RasterContext,
    tile: bin.ActiveTile,
    subpx_scratch: anytype,
    subpx_tile_size: usize,
) !void {
    switch (ctx_rast.camera.subpixel_center_map) {
        .full_in_mem => fillTileIdealCentFullInMem(
            ctx_rast,
            tile,
            subpx_scratch,
            subpx_tile_size,
        ),
        .per_tile => try ctx_rast.camera.fillTileIdealCentersPerTile(
            tile.scratch_x_px_min,
            tile.scratch_x_px_max,
            tile.scratch_y_px_min,
            tile.scratch_y_px_max,
            subpx_tile_size,
            subpx_scratch.ideal_pix_cent,
        ),
    }
}

//------------------------------------------------------------------------------------------
// Tile Raster Helpers
//------------------------------------------------------------------------------------------

pub const TileCoreResult = struct {
    shaded_px: u64,
    cam_duration_ns: u64,
    elem_duration_ns: u64,
};

pub fn rasterTileCore(
    comptime RasterBackend: type,
    comptime report_mode: ReportMode,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: bin.ActiveTile,
    overlaps_all: []const bin.OverlapBBox,
    meshes: []const MeshPrepared,
    root_inputs: mo.MeshRootInputs,
    subpx_scratch: *RasterBackend.SubpxScratchBuffs,
    subpx_tile_size: usize,
) !TileCoreResult {
    var shaded_px: u64 = 0;
    // Report aggregate worker-time for the overlap loop. Camera fill is timed
    // separately and removed below so all three raster phases share one basis.
    const time_elem_start: ?Timestamp =
        if (comptime report_mode != .off)
            Timestamp.now(io, .awake)
        else
            null;

    var camera_fill_ready = false;
    var cam_duration_ns: u64 = 0;

    inline for (@typeInfo(bin.ElemBucket).@"enum".fields) |bucket_field| {
        const bucket = @field(bin.ElemBucket, bucket_field.name);
        const geom_tag = comptime bin.bucketMeshType(bucket);
        const root_class = comptime bin.bucketRootClass(bucket);
        const range = tile.buckets[@intFromEnum(bucket)];
        const overlaps = overlaps_all[range.start .. range.start + range.count];
        for (overlaps) |ov| {
            const mesh_idx: usize = ov.mesh_idx;
            const mesh_ptr = &meshes[mesh_idx];
            std.debug.assert(mesh_ptr.mesh_type == geom_tag);
            const coords = &mesh_ptr.coords;
            const hull = if (comptime root_class == .multi_root) blk: {
                std.debug.assert(mesh_idx < root_inputs.hull_multiroot_by_mesh.len);
                if (root_inputs.hull_multiroot_by_mesh[mesh_idx]) |*prepared| {
                    break :blk prepared;
                }
                return error.MissingMultiRootData;
            } else blk: {
                std.debug.assert(mesh_idx < root_inputs.hull_adaptive_by_mesh.len);
                if (root_inputs.hull_adaptive_by_mesh[mesh_idx]) |*prepared| {
                    break :blk prepared;
                }
                break :blk null;
            };

            {
                if (!camera_fill_ready and comptime geom_tag != .tri3opt) {
                    const time_cam_start: ?Timestamp =
                        if (comptime report_mode != .off)
                            Timestamp.now(io, .awake)
                        else
                            null;
                    try fillTileIdealCent(
                        ctx_rast,
                        tile,
                        subpx_scratch,
                        subpx_tile_size,
                    );
                    camera_fill_ready = true;
                    if (comptime report_mode != .off) {
                        cam_duration_ns = @intCast(
                            time_cam_start.?.durationTo(
                                Timestamp.now(io, .awake),
                            ).raw.nanoseconds,
                        );
                    }
                }
                const GK = comptime switch (geom_tag) {
                    .tri3 => geomkerns.Tri3Kernel(),
                    .tri3opt => geomkerns.Tri3OptKernel(),
                    .tri6 => geomkerns.Tri6Kernel(),
                    .quad4 => geomkerns.Quad4Kernel(),
                    .quad8 => geomkerns.Quad89Kernel(8),
                    .quad9 => geomkerns.Quad89Kernel(9),
                };
                const N = GK.nodes_num;

                const mesh_fields_num: u8 = switch (mesh_ptr.shader) {
                    .nodal => |s| if (s.elem_field.dims.len == 3)
                        @intCast(s.elem_field.dims[1])
                    else
                        @intCast(s.elem_field.dims[2]),
                    .tex_u8, .tex_u16, .tex_f => 1,
                    .tex_rgb_u8, .tex_rgb_u16, .tex_rgb_f => 3,
                    .func => 1,
                    .func_rgb => 3,
                };

                switch (mesh_ptr.shader) {
                    .nodal => |*shader| {
                        const SK = shadekerns.NodalKernel(N);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        const start_idx = if (shader.elem_field.dims.len == 3)
                            shader.elem_field.getFlatIdx(
                                &[_]usize{ ov.elem_idx, 0, 0 },
                            )
                        else blk: {
                            const tt = @min(
                                ctx_rast.frame_idx,
                                shader.elem_field.dims[0] - 1,
                            );
                            break :blk shader.elem_field.getFlatIdx(
                                &[_]usize{ tt, ov.elem_idx, 0, 0 },
                            );
                        };

                        local_shader_buf.load(
                            shader.elem_field,
                            start_idx,
                            mesh_fields_num,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            NodalPrepared,
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_u8 => |*shader| {
                        const SK = shadekerns.TexKernel(N, u8, 1);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(
                            shader.elem_uvs,
                            ov.elem_idx * 2 * N,
                            2,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u8, 1),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_u16 => |*shader| {
                        const SK = shadekerns.TexKernel(N, u16, 1);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(
                            shader.elem_uvs,
                            ov.elem_idx * 2 * N,
                            2,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u16, 1),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_f => |*shader| {
                        const SK = shadekerns.TexKernel(N, F, 1);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(shader.elem_uvs, ov.elem_idx * 2 * N, 2);
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }
                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(F, 1),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_rgb_u8 => |*shader| {
                        const SK = shadekerns.TexKernel(N, u8, 3);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(
                            shader.elem_uvs,
                            ov.elem_idx * 2 * N,
                            2,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u8, 3),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_rgb_u16 => |*shader| {
                        const SK = shadekerns.TexKernel(N, u16, 3);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(
                            shader.elem_uvs,
                            ov.elem_idx * 2 * N,
                            2,
                        );
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(u16, 3),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .tex_rgb_f => |*shader| {
                        const SK = shadekerns.TexKernel(N, F, 3);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        local_shader_buf.load(shader.elem_uvs, ov.elem_idx * 2 * N, 2);
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }
                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            TexPrepared(F, 3),
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .func => |*shader| {
                        const SK = shadekerns.FuncKernel(N, 1);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        switch (shader.coord_mode) {
                            .uv => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_uvs.?,
                                    ov.elem_idx * 2 * N,
                                    2,
                                );
                            },
                            .world_reference => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_ref.?,
                                    ov.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .world_deformed => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_def.?,
                                    ov.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .para => {},
                        }
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            FuncPrepared,
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                    .func_rgb => |*shader| {
                        const SK = shadekerns.FuncKernel(N, 3);
                        var local_shader_buf: shaderops.LocalShaderBuff(N) = .{};
                        switch (shader.coord_mode) {
                            .uv => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_uvs.?,
                                    ov.elem_idx * 2 * N,
                                    2,
                                );
                            },
                            .world_reference => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_ref.?,
                                    ov.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .world_deformed => {
                                local_shader_buf.loadFuncCoords(
                                    shader.elem_world_def.?,
                                    ov.elem_idx * 3 * N,
                                    3,
                                );
                            },
                            .para => {},
                        }
                        if (shader.elem_normals) |en| {
                            const prep_idx = en.map[ov.elem_idx];
                            local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                        }

                        shaded_px += try RasterBackend.RasterEngine(
                            GK,
                            SK,
                            FuncPrepared,
                            root_class,
                        ).render(
                            report_mode,
                            ctx_rast,
                            ctx_report,
                            tile,
                            ov,
                            coords,
                            hull,
                            shader,
                            &local_shader_buf,
                            subpx_scratch,
                        );
                    },
                }
            }
        }
    }

    const elem_duration_ns: u64 = if (comptime report_mode != .off) blk: {
        const overlap_duration_ns: u64 = @intCast(
            time_elem_start.?.durationTo(
                Timestamp.now(io, .awake),
            ).raw.nanoseconds,
        );
        std.debug.assert(overlap_duration_ns >= cam_duration_ns);
        break :blk overlap_duration_ns - cam_duration_ns;
    } else 0;

    return .{
        .shaded_px = shaded_px,
        .cam_duration_ns = cam_duration_ns,
        .elem_duration_ns = elem_duration_ns,
    };
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "Tri3FixedEdges preserves edge sum across a row" {
    var x = [_]F{ 1.25, 5.5, 2.0 };
    var y = [_]F{ 1.75, 2.5, 6.25 };
    var z = [_]F{ 1.0, 1.0, 1.0 };
    const nodes = rops.Vec3Slices(F){
        .x = x[0..],
        .y = y[0..],
        .z = z[0..],
    };
    const fixed = Tri3FixedEdges.init(nodes, 2, 0, 0, 8, 8) orelse
        return error.TestUnexpectedResult;

    var e0 = fixed.start[0];
    var e1 = fixed.start[1];
    var e2 = fixed.start[2];
    for (0..8) |_| {
        try std.testing.expectEqual(fixed.area, e0 + e1 + e2);
        e0 += fixed.step_x[0];
        e1 += fixed.step_x[1];
        e2 += fixed.step_x[2];
    }
}
