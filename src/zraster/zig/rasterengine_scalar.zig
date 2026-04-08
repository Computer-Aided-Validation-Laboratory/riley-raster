const std = @import("std");
const Camera = @import("camera.zig").Camera;
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

const mr = @import("meshraster.zig");
const MeshPrepared = mr.MeshPrepared;
const MeshType = mr.MeshType;
const Shader = mr.Shader;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const newton = @import("newton.zig");
const shadekerns = @import("shaderkernels.zig");

const ScratchBuffers = struct {
    inv_z: []f64,
    image: *MatSlice(f64),
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;

pub fn rasterScene(
    comptime report_mode: ReportMode,
    ctx_rast: rops.RasterContext(report_mode),
    ctx_report: report.ReportContext(report_mode),
    outer_alloc: std.mem.Allocator,
    io: std.Io,
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
    const subpx_tile_total: usize = subpx_tile_size * subpx_tile_size;

    const subpx_inv_z_scratch = try arena_alloc.alloc(f64, subpx_tile_total);

    const subpx_img_mem = try arena_alloc.alloc(
        f64,
        subpx_tile_total * @as(usize, fields_num),
    );
    var subpx_image_scratch = MatSlice(f64).init(
        subpx_img_mem,
        subpx_tile_total,
        @as(usize, fields_num),
    );
    const scratch = ScratchBuffers{
        .inv_z = subpx_inv_z_scratch,
        .image = &subpx_image_scratch,
    };

    const subpx_field_avg = try arena_alloc.alloc(f64, fields_num);

    for (tiling.active_tiles) |tile| {
        const tile_start = if (comptime report_mode == .full_stats)
            Timestamp.now(io, .awake)
        else {};
        
        var shaded_px: u64 = 0;

        @memset(subpx_inv_z_scratch, -std.math.inf(f64));
        @memset(subpx_image_scratch.elems, 0.0);

        const overlap_start = tile.overlap_start;
        const overlap_end = overlap_start + tile.overlap_count;
        const overlaps = tiling.overlaps[overlap_start..overlap_end];

        for (overlaps) |ov| {
            const mesh_ptr = &meshes[ov.mesh_idx];

            const targ_overlap = common.OverlapTarget{ .tile = tile, .overlap = ov };

            std.debug.assert(ov.mesh_idx < raster_hulls.len);
            const mesh_in = rops.MeshInput{
                .coords = &mesh_ptr.coords,
                .hull = if (raster_hulls[ov.mesh_idx]) |*h| h else null,
            };

            switch (mesh_ptr.mesh_type) {
                inline else => |geom_tag| {
                    const GK = comptime switch (geom_tag) {
                        .tri3 => geomkerns.Tri3Kernel(),
                        .tri3opt => geomkerns.Tri3OptKernel(),
                        .tri6 => geomkerns.Tri6Kernel(),
                        .quad4ibi => geomkerns.Quad4IBIKernel(),
                        .quad4newton => geomkerns.Quad4NewtonKernel(),
                        .quad8 => geomkerns.Quad89Kernel(8),
                        .quad9 => geomkerns.Quad89Kernel(9),
                    };
                    const N = GK.nodes_num;

                    const mesh_fields_num: u8 = switch (mesh_ptr.shader) {
                        .nodal => |s| @intCast(s.elem_field.dims[2]),
                        .tex_u8, .tex_u16 => 1,
                        .tex_rgb_u8, .tex_rgb_u16 => 3,
                    };

                    switch (mesh_ptr.shader) {
                        .nodal => |*shader| {
                            const SK = shadekerns.NodalKernel(N);
                            
                            const tt = @min(ctx_rast.frame_idx, shader.elem_field.dims[0] - 1);
                            const start_idx = shader.elem_field.getFlatInd(
                                &[_]usize{ tt, targ_overlap.overlap.elem_idx, 0, 0 },
                            );

                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_field,
                                start_idx,
                                mesh_fields_num,
                            );
                            
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }
                            
                            shaded_px += try RasterPass(GK, SK, NodalPrepared).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                scratch,
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

                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 1)).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                scratch,
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

                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 1)).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                scratch,
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

                            shaded_px += try RasterPass(GK, SK, TexPrepared(u8, 3)).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                scratch,
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

                            shaded_px += try RasterPass(GK, SK, TexPrepared(u16, 3)).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                scratch,
                            );
                        },
                    }
                },
            }
        }

        averageScratch(
            tile,
            @intCast(sub_samp),
            subpx_tile_size,
            fields_num,
            &subpx_image_scratch,
            subpx_field_avg,
            image_out_arr,
        );

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
}

pub fn RasterPass(
    comptime Geometry: type,
    comptime ShaderKernel: type,
    comptime ShaderData: type,
) type {
    return struct {
        pub fn render(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
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

            const shaded_px = if (Geometry.raster_mode == .incremental)
                try rasterIncremental(
                    report_mode,
                    ctx_rast,
                    ctx_report,
                    targ_overlap,
                    subpx_domain,
                    rast_bounds,
                    nodes_coords,
                    shader,
                    shader_buf,
                    scratch,
                )
            else
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
                    scratch,
                );

            return shaded_px;
        }

        fn rasterIncremental(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(scratch.image.cols_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.cols_num);

            var shaded_px: u64 = 0;
                        
            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |node_idx| {
                nodes_inv_z[node_idx] = 1.0 / nodes_coords.z[node_idx];
            }

            const inv_area = 1.0 / rops.edgeFun3(
                nodes_coords.x[0],
                nodes_coords.y[0],
                nodes_coords.x[1],
                nodes_coords.y[1],
                nodes_coords.x[2],
                nodes_coords.y[2],
            );

            const dweights_dx = Geometry.getDWeightsDx(
                nodes_coords,
                inv_area,
                subpx_domain.step,
            );
            const dweights_dy = Geometry.getDWeightsDy(
                nodes_coords,
                inv_area,
                subpx_domain.step,
            );

            const start_x = rast_bounds.x_min_f + subpx_domain.offset;
            const start_y = rast_bounds.y_min_f + subpx_domain.offset;
            var weights_row = Geometry.getWeightsAt(nodes_coords, start_x, start_y, inv_area);

            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var weights = weights_row;

                for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
                    if (Geometry.isInElement(weights)) {
                        ctx_report.recordSolverCalls(1);
                        ctx_report.recordSolverIters(0);
                        const inv_z = Geometry.calcInvZ(nodes_coords, weights);
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[scratch_idx]) {
                            scratch.inv_z[scratch_idx] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            const global_subx = targ_overlap.tile.x_px_min * sub_samp +
                                scratch_x;
                            const global_suby = targ_overlap.tile.y_px_min * sub_samp +
                                scratch_y;

                            if (comptime report_mode == .full_stats) {
                                ctx_report.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    0,
                                );
                                report.maybeRecordPixelOccupancy(
                                    ctx_report,
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
                                scratch.image,
                            );
                        }
                    }
                    inline for (0..N) |node_idx| {
                        weights[node_idx] += dweights_dx[node_idx];
                    }
                }
                inline for (0..N) |node_idx| {
                    weights_row[node_idx] += dweights_dy[node_idx];
                }
            }
            return shaded_px;
        }

        fn rasterDirect(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext(report_mode),
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            scratch: ScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(scratch.image.cols_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(scratch.image.cols_num);

            var nodes_inv_z: [N]f64 = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
            }

            const bilinear_params = if (comptime Geometry.solver_kind == .inv_bi)
                Geometry.getBilinearParams(nodes_coords)
            else
                {};
            const inv_elem_area = if (comptime Geometry.solver_kind == .hyperb)
                Geometry.getInvElemArea(nodes_coords)
            else
                {};

            var element_tess: hull.Tessellation(Geometry.tess_triangles_num) = undefined;

            if (comptime Geometry.hull_nodes_num > 0) {
                if (mesh_in.hull) |rh| {
                    const hx = rh.getSlice(&[_]usize{ targ_overlap.overlap.elem_idx, 0, 0 }, 1);
                    const hy = rh.getSlice(&[_]usize{ targ_overlap.overlap.elem_idx, 1, 0 }, 1);
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

            var subpx_y: f64 = rast_bounds.y_min_f + subpx_domain.offset;
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y| {
                const row_offset = scratch_y * subpx_domain.tile_size;
                var subpx_x: f64 = rast_bounds.x_min_f + subpx_domain.offset;

                for (rast_bounds.start_x_u..rast_bounds.end_x_u) |scratch_x| {
                    const global_subx = targ_overlap.tile.x_px_min * sub_samp + scratch_x;
                    const global_suby = targ_overlap.tile.y_px_min * sub_samp + scratch_y;
                    var hull_seed: ?newton.NewtonSeed = null;

                    if (comptime Geometry.hull_nodes_num > 0) {
                        ctx_report.recordTessChecks(1);
                        const tess_res = element_tess.isInScalar(subpx_x, subpx_y);
                        if (tess_res.is_in) {
                            ctx_report.recordTessPasses(1);
                            hull_seed = .{
                                .xi = tess_res.seed_xi,
                                .eta = tess_res.seed_eta,
                            };
                        }
                        if (comptime report_mode == .full_stats) {
                            report.maybeRecordEarlyOut(
                                ctx_report,
                                global_subx,
                                global_suby,
                                tess_res.is_in,
                            );
                        }
                        if (!tess_res.is_in) {
                            subpx_x += subpx_domain.step;
                            continue;
                        }
                    } else if (comptime report_mode == .full_stats) {
                        report.maybeRecordEarlyOut(
                            ctx_report,
                            global_subx,
                            global_suby,
                            true,
                        );
                    }

                    ctx_report.recordSolverCalls(1);
                    const result = if (comptime Geometry.solver_kind == .newton) blk: {
                        if (comptime Geometry.seed_mode == .hull) {
                            if (hull_seed) |seed| {
                                const seed_quality = newton.evaluateSeedQuality(
                                    Geometry.nodes_num,
                                    Geometry.domainViolation,
                                    subpx_x - subpx_domain.x_off,
                                    subpx_y - subpx_domain.y_off,
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
                            subpx_x,
                            subpx_y,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            selected_seed.xi,
                            selected_seed.eta,
                        );
                    } else if (comptime Geometry.solver_kind == .inv_bi)
                        Geometry.solveWeightsInvBi(
                            subpx_x,
                            subpx_y,
                            subpx_domain.x_off,
                            subpx_domain.y_off,
                            bilinear_params,
                        )
                    else
                        Geometry.solveWeightsHyperb(
                            nodes_coords,
                            subpx_x,
                            subpx_y,
                            inv_elem_area,
                        );
                    ctx_report.recordSolverIters(result.iters);

                    if (comptime Geometry.solver_kind == .newton and
                        Geometry.seed_reuse == .last_converged)
                    {
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
                        const scratch_idx = row_offset + scratch_x;

                        if (inv_z >= scratch.inv_z[scratch_idx]) {
                            scratch.inv_z[scratch_idx] = inv_z;
                            const subpx_z = 1.0 / inv_z;
                            shaded_px += 1;

                            if (comptime report_mode == .full_stats) {
                                ctx_report.recordPixelIters(
                                    global_subx,
                                    global_suby,
                                    result.iters,
                                );
                                report.maybeRecordPixelOccupancy(
                                    ctx_report,
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
                                scratch.image,
                            );
                        }
                    } else {
                        if (result.iters > 0) ctx_report.recordSolverDiverged();
                    }
                    subpx_x += subpx_domain.step;
                }
                subpx_y += subpx_domain.step;
            }
            return shaded_px;
        }
    };
}

pub fn averageScratch(
    tile: ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    spx_field_avg: []f64,
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            @memset(spx_field_avg, 0.0);

            for (0..sub_samp) |sy| {
                const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                for (0..sub_samp) |sx| {
                    const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;

                    for (0..@as(usize, fields_num)) |ff| {
                        spx_field_avg[ff] += spx_image_scratch.get(scratch_flat_idx, ff);
                    }
                }
            }

            for (0..@as(usize, fields_num)) |ff| {
                const image_idxs = [_]usize{ ff, image_px_y, image_px_x };
                const image_val: f64 = spx_field_avg[ff] * inv_sub_samp_sq;

                image_out_arr.set(image_idxs[0..], image_val);
            }
        }
    }
}
