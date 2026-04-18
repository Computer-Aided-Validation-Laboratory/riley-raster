// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const hull = @import("hull.zig");
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const rops = @import("rasterops.zig");
const mr = @import("meshraster.zig");
const MeshPrepared = mr.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
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
    comptime Backend: type,
    comptime report_mode: ReportMode,
) type {
    return struct {
        arena: std.heap.ArenaAllocator,
        subpx_scratch: Backend.SubpxScratchBuffers,
        log: report.LogType(report_mode),
    };
}

fn ThreadContext() type {
    return struct {
        next_tile_idx: std.atomic.Value(usize),
        ctx_rast: rops.RasterContext,
        tiling: rops.TilingOverlaps,
        meshes: []const MeshPrepared,
        raster_hulls: []const ?NDArray(f64),
        image_out_arr: *NDArray(f64),
    };
}

pub fn rasterDirectScalarCommon(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
    comptime report_mode: ReportMode,
    comptime ScratchBuffers: type,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    targ_overlap: OverlapTarget,
    mesh_in: rops.MeshInput,
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

    var subpx_y_f: f64 = rast_bounds.y_min_f + subpx_domain.offset;
    for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
        const row_offset = scratch_y_u * subpx_domain.tile_size;
        var subpx_x_f: f64 = rast_bounds.x_min_f + subpx_domain.offset;

        for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x_u| {
            const tile_subx: usize = @intCast(targ_overlap.tile.x_px_min);
            const tile_suby: usize = @intCast(targ_overlap.tile.y_px_min);
            const tile_subx_off: usize = tile_subx * sub_samp;
            const tile_suby_off: usize = tile_suby * sub_samp;
            const global_subx: usize = tile_subx_off +% scratch_x_u;
            const global_suby: usize = tile_suby_off +% scratch_y_u;

            if (comptime Geometry.hull_nodes_num > 0) {
                ctx_report.recordTessChecks(1);
                const tess_res = element_tess.isInScalar(subpx_x_f, subpx_y_f);
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
                    subpx_x_f += subpx_domain.step;
                    continue;
                }
            } else if (comptime report_mode == .full_stats) {
                ctx_report.recordEarlyOut(global_subx, global_suby, true);
            }

            ctx_report.recordSolverCalls(1);
            const result = if (comptime Geometry.solver_kind == .inv_bi)
                Geometry.solveWeightsInvBi(
                    subpx_x_f,
                    subpx_y_f,
                    subpx_domain.x_off,
                    subpx_domain.y_off,
                    bilinear_params,
                )
            else
                Geometry.solveWeightsHyperb(
                    nodes_coords,
                    subpx_x_f,
                    subpx_y_f,
                    inv_elem_area,
                );

            ctx_report.recordSolverIters(result.iters);

            if (result.weights) |weights| {
                const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                const scratch_idx = row_offset + scratch_x_u;

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
            subpx_x_f += subpx_domain.step;
        }
        subpx_y_f += subpx_domain.step;
    }

    return shaded_px;
}

pub fn rasterSceneCommon(
    comptime Backend: type,
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
    if (threads_within_image <= 1 or tiling.active_tiles.len <= 1) {
        try rasterSceneSingleThreadCommon(
            Backend,
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
        return;
    }

    if (comptime report_mode == .full_stats) {
        return error.ThreadedFullStatsUnsupported;
    }

    try rasterSceneThreadedCommon(
        Backend,
        report_mode,
        outer_alloc,
        ctx_rast,
        ctx_report,
        threads_within_image,
        tiling,
        meshes,
        raster_hulls,
        image_out_arr,
    );
}

fn rasterSceneSingleThreadCommon(
    comptime Backend: type,
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
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.debug.assert(image_out_arr.dims[0] <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(image_out_arr.dims[0]);

    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
    var subpx_scratch = try Backend.initSubpxScratch(
        arena_alloc,
        fields_num,
        subpx_tile_size,
    );

    for (tiling.active_tiles) |tile| {
        try rasterTileCommon(
            Backend,
            report_mode,
            io,
            ctx_rast,
            ctx_report,
            tile,
            tiling.overlaps,
            meshes,
            raster_hulls,
            image_out_arr,
            &subpx_scratch,
            fields_num,
            subpx_tile_size,
        );
    }
}

fn rasterSceneThreadedCommon(
    comptime Backend: type,
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    threads_within_image: u16,
    tiling: rops.TilingOverlaps,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    const Worker = ThreadState(Backend, report_mode);
    const Context = ThreadContext();

    std.debug.assert(image_out_arr.dims[0] <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(image_out_arr.dims[0]);
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
    const active_tiles_num = tiling.active_tiles.len;
    const worker_count_u16 = @min(
        threads_within_image,
        @as(u16, @intCast(active_tiles_num)),
    );
    const worker_count: usize = @intCast(@max(@as(u16, 1), worker_count_u16));

    var threads = try outer_alloc.alloc(std.Thread, worker_count - 1);
    defer outer_alloc.free(threads);
    var workers = try outer_alloc.alloc(Worker, worker_count);
    defer {
        for (workers) |*worker| {
            worker.arena.deinit();
        }
        outer_alloc.free(workers);
    }

    for (0..worker_count) |ii| {
        workers[ii].arena = std.heap.ArenaAllocator.init(outer_alloc);
        const arena_alloc = workers[ii].arena.allocator();
        workers[ii].subpx_scratch = try Backend.initSubpxScratch(
            arena_alloc,
            fields_num,
            subpx_tile_size,
        );
        workers[ii].log = initThreadReportLog(report_mode);
    }

    var ctx_thread = Context{
        .next_tile_idx = .init(0),
        .ctx_rast = ctx_rast,
        .tiling = tiling,
        .meshes = meshes,
        .raster_hulls = raster_hulls,
        .image_out_arr = image_out_arr,
    };

    for (1..worker_count) |ii| {
        threads[ii - 1] = try std.Thread.spawn(
            .{},
            rasterThreadWorker,
            .{
                Backend,
                report_mode,
                &ctx_thread,
                &workers[ii],
                fields_num,
                subpx_tile_size,
            },
        );
    }

    rasterThreadWorker(
        Backend,
        report_mode,
        &ctx_thread,
        &workers[0],
        fields_num,
        subpx_tile_size,
    );

    for (threads) |thread| {
        thread.join();
    }

    if (report.getBenchLog(report_mode, ctx_report.log)) |bench_log| {
        for (workers) |*worker| {
            const worker_bench = report.getBenchLog(report_mode, &worker.log).?;
            report.reduceBenchLog(bench_log, worker_bench);
        }
    }
}

fn rasterThreadWorker(
    comptime Backend: type,
    comptime report_mode: ReportMode,
    ctx_thread: *ThreadContext(),
    worker: *ThreadState(Backend, report_mode),
    fields_num: u8,
    subpx_tile_size: usize,
) void {
    const ctx_report = report.ReportContext(report_mode){ .log = &worker.log };

    while (true) {
        const tile_idx = ctx_thread.next_tile_idx.fetchAdd(1, .monotonic);
        if (tile_idx >= ctx_thread.tiling.active_tiles.len) {
            break;
        }

        const tile = ctx_thread.tiling.active_tiles[tile_idx];
        rasterTileCommon(
            Backend,
            report_mode,
            undefined,
            ctx_thread.ctx_rast,
            ctx_report,
            tile,
            ctx_thread.tiling.overlaps,
            ctx_thread.meshes,
            ctx_thread.raster_hulls,
            ctx_thread.image_out_arr,
            &worker.subpx_scratch,
            fields_num,
            subpx_tile_size,
        ) catch unreachable;
    }
}

fn rasterTileCommon(
    comptime Backend: type,
    comptime report_mode: ReportMode,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tile: rops.ActiveTile,
    overlaps_all: []const rops.OverlapBBox,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
    subpx_scratch: *Backend.SubpxScratchBuffers,
    fields_num: u8,
    subpx_tile_size: usize,
) !void {
    const tile_start = if (comptime report_mode == .full_stats)
        Timestamp.now(io, .awake)
    else {};

    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    Backend.resetSubpxScratch(subpx_scratch, subpx_tile_size);

    const overlap_start = tile.overlap_start;
    const overlap_end = overlap_start + tile.overlap_count;
    const overlaps = overlaps_all[overlap_start..overlap_end];

    for (overlaps) |ov| {
        const mesh_idx: usize = ov.mesh_idx;
        const mesh_ptr = &meshes[mesh_idx];
        const targ_overlap = OverlapTarget{ .tile = tile, .overlap = ov };

        std.debug.assert(mesh_idx < raster_hulls.len);
        const mesh_in = rops.MeshInput{
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

                        shaded_px += try Backend.RasterPass(
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

                        shaded_px += try Backend.RasterPass(
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

                        shaded_px += try Backend.RasterPass(
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
                }
            },
        }
    }

    if (sub_samp > 1) {
        averageScratch(
            Backend.scratch_layout,
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
            Backend.scratch_layout,
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

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const scratch_row_offset = ty * spx_tile_size;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const scratch_flat_idx = scratch_row_offset + tx;

            if (fields_num == 1) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
            } else if (fields_num == 3) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        1,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        2,
                    ),
                );
            } else {
                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            ff,
                        ),
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

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
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

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    field_sum_1 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    field_sum_2 * inv_sub_samp_sq,
                );
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
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        spx_field_avg[ff] * inv_sub_samp_sq,
                    );
                }
            }
        }
    }
}
