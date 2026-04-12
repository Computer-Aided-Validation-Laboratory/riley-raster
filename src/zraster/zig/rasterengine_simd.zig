const std = @import("std");
const Camera = @import("camera.zig").Camera;
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU = buildconfig.VecSU;
const VecSU8 = buildconfig.VecSU8;

const tol = buildconfig.config.tolerance;
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
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("rasterengine_common.zig");

const spec = @import("zraster.zig");
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
    inv_z: []align(64) f64,
    image: MatSlice(f64),
    simd_chunks: []SubpxSimdChunk,
    mask: []align(64) bool,
    xi: []align(64) f64,
    eta: []align(64) f64,
    touched_min_x: []usize,
    touched_max_x: []usize,
};

const SubpxDomain = common.SubpxDomain;
const RasterBounds = common.RasterBounds;
const ScratchLayout = common.ScratchLayout;

pub const scratch_layout = ScratchLayout.field_major;

inline fn loadVecSF(subpx_vals: []const f64, start_u: usize) VecSF {
    // slice of a slice, equivalent to [start_u..start_u+S]
    const lane_vals: [S]f64 = subpx_vals[start_u..][0..S].*;
    return @as(VecSF, lane_vals);
}

inline fn storeVecSF(subpx_vals: []f64, start_u: usize, v_vals: VecSF) void {
    const lane_vals: [S]f64 = @as([S]f64, v_vals);
    // slice of a slice, equivalent to [start_u..start_u+S]
    subpx_vals[start_u..][0..S].* = lane_vals;
}

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

    const subpx_simd_chunk_count =
        @divFloor(subpx_tile_total_padded + (S - 1), S) + 1;
    const subpx_simd_chunks = try arena_alloc.alloc(
        SubpxSimdChunk,
        subpx_simd_chunk_count,
    );

    return .{
        .inv_z = subpx_inv_z_scratch,
        .image = subpx_image_scratch,
        .simd_chunks = subpx_simd_chunks,
        .mask = subpx_mask_scratch,
        .xi = subpx_xi_scratch,
        .eta = subpx_eta_scratch,
        .touched_min_x = try arena_alloc.alloc(usize, subpx_tile_size),
        .touched_max_x = try arena_alloc.alloc(usize, subpx_tile_size),
    };
}

pub fn resetSubpxScratch(
    subpx_scratch: *SubpxScratchBuffers,
    subpx_tile_size: usize,
) void {
    @memset(subpx_scratch.inv_z, -std.math.inf(f64));
    @memset(subpx_scratch.image.elems, 0.0);
    @memset(subpx_scratch.touched_min_x, subpx_tile_size);
    @memset(subpx_scratch.touched_max_x, 0);
}

pub fn rasterScene(
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
    try common.rasterSceneCommon(
        @This(), // Link up the functions in this file to rasterScene
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
}

pub fn RasterPass(
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
            mesh_in: rops.MeshInput,
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
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

            const shaded_px = if (comptime Geometry == geomkerns.Tri3Kernel())
                try rasterIncrementalSIMD(
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
            else if (Geometry.solver_kind == .inv_bi)
                // NOTE: SIMD is very inefficient for highly branched inverse bilinear solve
                // fallback to scalar
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
            else if (Geometry.solver_kind == .newton)
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

        /// We run our visibility checks S wide SIMD over sub-pixels. For interpolated nodal
        /// shading we stay S wide over sub-pixels but for texture shading we switch to 
        /// inner-SIMD within sub-pixels. This is because the texel fetches for cubic and 
        /// quintic interpolation of the texture S wide made memory fetches the bottleneck.
        fn rasterIncrementalSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            orig_start_x_u: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

            const inv_area = 1.0 / rops.edgeFun3(
                nodes_coords.x[0],
                nodes_coords.y[0],
                nodes_coords.x[1],
                nodes_coords.y[1],
                nodes_coords.x[2],
                nodes_coords.y[2],
            );

            // Init our sub-pixel step wise derivatives for weights and their initial
            // values, also init vector constants
            const v_nodes_inv_z: [N]VecSF = Geometry.getSIMDInvZ(nodes_coords);
            const v_steps: geomkerns.TriWeightStepSIMD(N) = Geometry.getSIMDSteps(
                nodes_coords,
                inv_area,
                subpx_domain.step,
            );

            const start_x_f = rast_bounds.x_min_f + subpx_domain.offset;
            const start_y_f = rast_bounds.y_min_f + subpx_domain.offset;
            var v_weights_row: [N]VecSF = Geometry.getSIMDRowWeights(
                nodes_coords,
                inv_area,
                start_x_f,
                start_y_f,
                v_steps,
            );

            const edge_tol = tol.edge.simd_raster_weight_inclusion;
            const v_edge_tol: VecSF = @splat(-edge_tol);

            const v_orig_start_x_u: VecSU = @splat(orig_start_x_u);
            const v_end_x_u: VecSU = @splat(rast_bounds.end_x_u);

            // Step row by row along y
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
                const row_offset = scratch_y_u * subpx_domain.tile_size;
                var v_weights = v_weights_row;

                // Step S width along the x row of subpixels in scratch
                var scratch_x_u = rast_bounds.start_x_u;
                while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
                    const v_lane_idx: VecSU = std.simd.iota(usize, S);
                    const v_scratch_x_u: VecSU = @splat(scratch_x_u);

                    // Masking for when we hit the end of an X row of subpixels and it is
                    // not divisible by S, mask off inactive lanes that overflow.
                    const v_subpx_x_u = v_scratch_x_u + v_lane_idx;
                    const v_x_mask =
                        (v_subpx_x_u >= v_orig_start_x_u) &
                        (v_subpx_x_u < v_end_x_u);
                    var v_mask_active: VecSB = v_x_mask;
                    inline for (0..N) |ss| {
                        v_mask_active =
                            v_mask_active & (v_weights[ss] >= v_edge_tol);
                    }

                    if (@reduce(.Or, v_mask_active)) {
                        var v_inv_z: VecSF = @splat(0.0);
                        inline for (0..N) |ss| {
                            v_inv_z += v_weights[ss] * v_nodes_inv_z[ss];
                        }

                        const scratch_idx = row_offset + scratch_x_u;
                        const v_old_inv_z = loadVecSF(
                            subpx_scratch.inv_z,
                            scratch_idx,
                        );

                        // Depth visibility check on active lanes only
                        const v_depth_mask =
                            v_mask_active & (v_inv_z >= v_old_inv_z);
                        const has_depth_hit = @reduce(.Or, v_depth_mask);
                        if (has_depth_hit) {
                            const v_new_inv_z = @select(
                                f64,
                                v_depth_mask,
                                v_inv_z,
                                v_old_inv_z,
                            );
                            storeVecSF(
                                subpx_scratch.inv_z,
                                scratch_idx,
                                v_new_inv_z,
                            );
                            const v_subpx_z: VecSF = @as(VecSF, @splat(1.0)) / v_inv_z;
                            
                            // Record the x sub-pixel limits we have actually shaded to 
                            // reduce the range of nested loops we evaluate to resolve the
                            // sub-pixel anti-aliasing.
                            const lane_depth_mask: [S]bool = v_depth_mask;
                            inline for (0..S) |ll| {
                                if (lane_depth_mask[ll]) {
                                    const touched_x_u = scratch_x_u + ll;
                                    if (touched_x_u <
                                        subpx_scratch.touched_min_x[scratch_y_u])
                                    {
                                        subpx_scratch.touched_min_x[scratch_y_u] =
                                            touched_x_u;
                                    }
                                    if (touched_x_u >
                                        subpx_scratch.touched_max_x[scratch_y_u])
                                    {
                                        subpx_scratch.touched_max_x[scratch_y_u] =
                                            touched_x_u;
                                    }
                                }
                            }

                            
                            // Count the number of shaded pixels for performance analysis
                            // TODO: should we comptime remove this with report = .off?
                            const v_hit_one: VecSU8 = @splat(1);
                            const v_hit_zero: VecSU8 = @splat(0);
                            const v_hit_count = @select(
                                u8,
                                v_depth_mask,
                                v_hit_one,
                                v_hit_zero,
                            );
                            const hit_count = @reduce(.Add, v_hit_count);
                            shaded_px += @intCast(hit_count);

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = 0,
                                .global_suby = 0,
                                .shader_buf = shader_buf,
                                .v_mask_active = v_depth_mask,
                            };

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                ctx_shade,
                                ctx_report,
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z,
                                v_subpx_z,
                                shader,
                                &subpx_scratch.image,
                            );
                        }
                    }
                    inline for (0..N) |ss| {
                        v_weights[ss] += v_steps.v_dx_step[ss];
                    }
                }
                inline for (0..N) |ss| {
                    v_weights_row[ss] += v_steps.v_dy_step[ss];
                }
            }
            return shaded_px;
        }

        /// To use our S wide SIMD effectively for Newton we need to process in multiple 
        /// passes to fill the S lanes where possible. Pass 1: Vectorised coarse in/out with
        /// our hull tessellation. Pass 2: 
        fn rasterNewtonSIMD(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: *const rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            orig_start_x_u: usize,
            nodes_coords: Vec3Slices(f64),
            shader: anytype,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

            // Hoist our node z and inverse z so we only need to do this once
            var nodes_inv_z: [N]f64 = undefined;
            var v_nodes_z: [N]VecSF = undefined;
            var v_nodes_inv_z: [N]VecSF = undefined;
            inline for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_coords.z[nn];
                v_nodes_z[nn] = @splat(nodes_coords.z[nn]);
                v_nodes_inv_z[nn] = @splat(nodes_inv_z[nn]);
            }

            // Use our hull to get the triangular tessellation we will use for our coarse
            // in/out check to avoid the Newton solver where possible.
            const raster_hull = mesh_in.hull orelse
                @panic("rasterNewtonSIMD requires mesh hull data");
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
                Geometry.hull_nodes_num,
                Geometry.tess_triangles_num,
                hx,
                hy,
            );

            // Mask off our buffer based on the tile/elem overlap bounds to avoid needless
            // processing 
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
                const row_offset = scratch_y_u * subpx_domain.tile_size;
                const mask_start = row_offset + rast_bounds.start_x_u;
                const mask_end = row_offset + rast_bounds.end_x_u;
                @memset(
                    subpx_scratch.mask[mask_start..mask_end],
                    false,
                );
            }

            // We count the passes of the tessellation check so we can assign chunks and 
            // lane idx for the Newton solver in the next pass.
            var subpx_tess_pass_count: usize = 0;

            const v_lane_idx: VecSU = std.simd.iota(usize, S);

            // Hoist these vector constants
            const v_subpx_min_x_f: VecSF =
                @splat(@as(f64, @floatFromInt(targ_overlap.tile.x_px_min)));
            const v_step_f: VecSF = @splat(subpx_domain.step);
            const v_splat_half: VecSF = @splat(0.5);
            const v_orig_start_x_u: VecSU = @splat(orig_start_x_u);
            const v_bounds_end_x_u: VecSU = @splat(rast_bounds.end_x_u);

            //------------------------------------------------------------------------------
            // Pass 1: Vectorized Coarse In/Out
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
                const scratch_y_f: f64 = @as(f64, @floatFromInt(scratch_y_u));
                const subpx_y_f: f64 =
                    @as(f64, @floatFromInt(targ_overlap.tile.y_px_min)) +
                    (scratch_y_f + 0.5) * subpx_domain.step;

                // Step S wide along the row 
                var scratch_x_u: usize = rast_bounds.start_x_u;
                while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
                    // Mask off lanes that overrun the edges of our bounds in x so when we
                    // have a buffer that is not /S we don't process it
                    const v_scratch_x_u: VecSU = @splat(scratch_x_u);
                    const v_subpx_x_u = v_scratch_x_u + v_lane_idx;
                    const v_x_mask = (v_subpx_x_u >= v_orig_start_x_u) &
                                     (v_subpx_x_u < v_bounds_end_x_u);

                    const v_subpx_x_lane_f: VecSF = @floatFromInt(v_subpx_x_u);
                    const v_subpx_x_off_f = (v_subpx_x_lane_f + v_splat_half) * v_step_f;
                    const v_subpx_x_f = v_subpx_min_x_f + v_subpx_x_off_f;
                    
                    const v_subpx_y_f: VecSF = @splat(subpx_y_f);

                    const v_hull_res: HullResultSIMD = element_tess.isInSIMD(
                        v_subpx_x_f,
                        v_subpx_y_f,
                    );
                    
                    // Report: count passes of the tessellation check 
                    const v_mask_one_u8: VecSU8 = @splat(1);
                    const v_mask_zero_u8: VecSU8 = @splat(0);
                    const v_tess_check_u8 = @select(
                        u8,
                        v_x_mask,
                        v_mask_one_u8,
                        v_mask_zero_u8,
                    );
                    const tess_check_num: u64 = @intCast(@reduce(.Add, v_tess_check_u8));
                    ctx_report.recordTessChecks(tess_check_num);

                    const v_mask_active = v_x_mask & v_hull_res.v_is_in;
                    
                    // Report: count of masked passes of the tessellation for reporting
                    const v_tess_pass_u8 = @select(
                        u8,
                        v_mask_active,
                        v_mask_one_u8,
                        v_mask_zero_u8,
                    );
                    const tess_pass_num: u64 = 
                        @intCast(@reduce(.Add, v_tess_pass_u8));
                    ctx_report.recordTessPasses(tess_pass_num);

                    // We only take sub-pixels that pass the tessellation check to run the
                    // Newton solver in the next pass
                    if (@reduce(.Or, v_mask_active)) {
                        const mask_arr: [S]bool = v_mask_active;
                        const x_arr_f: [S]f64 = v_subpx_x_f;
                        const y_arr_f: [S]f64 = v_subpx_y_f;

                        // Initial seed can be the centroid in parametric coords or it can
                        // be estimated from the hull check, testing showed centroid is more
                        // robust.
                        const init_seed = Geometry.initSeedSIMD(.{
                            .v_xi = v_hull_res.v_seed_xi,
                            .v_eta = v_hull_res.v_seed_eta,
                        });
                        const xi_arr: [S]f64 = init_seed.v_xi;
                        const eta_arr: [S]f64 = init_seed.v_eta;

                        for (0..S) |ss| {
                            if (mask_arr[ss]) {
                                var seed_xi = xi_arr[ss];
                                var seed_eta = eta_arr[ss];

                                if (comptime Geometry.seed_mode == .hull) {
                                    const hull_seed = newton.NewtonSeed{
                                        .xi = seed_xi,
                                        .eta = seed_eta,
                                    };
                                    const seed_quality = newton.evaluateSeedQuality(
                                        Geometry.nodes_num,
                                        Geometry.domainViolation,
                                        x_arr_f[ss] - subpx_domain.x_off,
                                        y_arr_f[ss] - subpx_domain.y_off,
                                        nodes_coords.x,
                                        nodes_coords.y,
                                        nodes_coords.z,
                                        hull_seed,
                                    );
                                    if (!seed_quality.is_usable) {
                                        const centroid_seed = Geometry.initSeed(null);
                                        seed_xi = centroid_seed.xi;
                                        seed_eta = centroid_seed.eta;
                                    }
                                }

                                // Assign an S wide chunk and a lane for this subpixel to 
                                // be processed by the Newton solver
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

                                subpx_scratch.simd_chunks[chunk_idx]
                                    .scratch_x_u[lane_idx] = scratch_x_u + ss;
                                subpx_scratch.simd_chunks[chunk_idx]
                                    .scratch_y_u[lane_idx] = scratch_y_u;
                                subpx_scratch.simd_chunks[chunk_idx]
                                    .px_f[lane_idx] = x_arr_f[ss];
                                subpx_scratch.simd_chunks[chunk_idx]
                                    .py_f[lane_idx] = y_arr_f[ss];
                                subpx_scratch.simd_chunks[chunk_idx]
                                    .seed_xi[lane_idx] = seed_xi;
                                subpx_scratch.simd_chunks[chunk_idx]
                                    .seed_eta[lane_idx] = seed_eta;
                                subpx_scratch.simd_chunks[chunk_idx].count = lane_idx + 1;

                                subpx_tess_pass_count += 1;
                            }
                        }
                    }
                }
            }

            //------------------------------------------------------------------------------
            // Pass 2: Vectorized Newton solve in chunks of S from tessellation passes
            const subpx_simd_chunk_count = 
                @divFloor(subpx_tess_pass_count + (S-1), S);
            // Storage for seed reuse if needed
            var seed_state = newton.NewtonSeedState{};
            const v_full_mask: VecSB = @splat(true);

            // Data is already in S wide chunks so we can just loop over our chunks
            for (0..subpx_simd_chunk_count) |chunk_idx| {
                var subpx_simd_chunk = subpx_scratch.simd_chunks[chunk_idx];

                // If we have a good seed from the last run and we have set the mode to 
                // reuse it we write it into our vector in place
                if (comptime Geometry.seed_reuse == .last_converged) {
                    newton.applySeedReuseInPlace(
                        subpx_simd_chunk.count,
                        seed_state,
                        subpx_simd_chunk.seed_xi[0..subpx_simd_chunk.count],
                        subpx_simd_chunk.seed_eta[0..subpx_simd_chunk.count],
                    );
                }

                // Convert fixed size arrays to SIMD vectors for the Newton solve S wide
                const v_target_x_f: VecSF = subpx_simd_chunk.px_f;
                const v_target_y_f: VecSF = subpx_simd_chunk.py_f;
                const v_xi_seed: VecSF = subpx_simd_chunk.seed_xi;
                const v_eta_seed: VecSF = subpx_simd_chunk.seed_eta;
                const v_chunk_mask: VecSB = if (subpx_simd_chunk.count == S)
                    v_full_mask
                else
                    v_lane_idx < @as(VecSU, @splat(subpx_simd_chunk.count));

                // Actual Newton solver call S wide
                const result = Geometry.solveWeightsNewtonSIMD(
                    nodes_coords,
                    v_target_x_f,
                    v_target_y_f,
                    v_xi_seed,
                    v_eta_seed,
                    subpx_domain.x_off,
                    subpx_domain.y_off,
                );

                // Report: solver statistics 
                const v_solver_iters = @select(
                    u8,
                    v_chunk_mask,
                    result.v_iters,
                    @as(VecSU8, @splat(0)),
                );
                const solver_iters: u64 = @intCast(@reduce(.Add, v_solver_iters));
                ctx_report.recordSolverIters(solver_iters);
                ctx_report.recordSolverCalls(subpx_simd_chunk.count);

                // We store anything that converged with parametric coords inside the 
                // element           
                const v_conv_mask = v_chunk_mask & result.v_mask;
                if (@reduce(.Or, v_conv_mask)) {
                    // Vectorised flat index for writes to scratch buffer                 
                    const v_scratch_idx = 
                        @as(VecSU, subpx_simd_chunk.scratch_y_u) *
                        @as(VecSU, @splat(subpx_domain.tile_size)) +
                        @as(VecSU, subpx_simd_chunk.scratch_x_u);

                    // Convert our vectors to fixed sized arrays for our scattered write
                    const conv_mask_arr: [S]bool = v_conv_mask;
                    const xi_out_arr: [S]f64 = result.v_xi_out;
                    const eta_out_arr: [S]f64 = result.v_eta_out;
                    const scratch_idx_arr: [S]usize = v_scratch_idx;

                    // Scattered write into scratch buffer, not guaranteed to be aligned 
                    // because of how we have assigned SIMD chunks from the tessellation 
                    // check
                    for (0..S) |jj| {
                        if (conv_mask_arr[jj]) {
                            // Write the parametric coords to the scratch buffers along with
                            // a mask so we know which sub-pixels to shade in the next pass
                            const scratch_idx = scratch_idx_arr[jj];
                            subpx_scratch.xi[scratch_idx] = xi_out_arr[jj];
                            subpx_scratch.eta[scratch_idx] = eta_out_arr[jj];
                            subpx_scratch.mask[scratch_idx] = true;
                        }
                    }

                    // If we are reusing seeds for the solver we store the best one to splat
                    // it as our seed for the next batch
                    if (comptime Geometry.seed_reuse == .last_converged) {
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
            }
            
            //------------------------------------------------------------------------------
            // Pass 3: Spatially Grouped SIMD Shading
            for (rast_bounds.start_y_u..rast_bounds.end_y_u) |scratch_y_u| {
                const row_offset = scratch_y_u * subpx_domain.tile_size;

                // Raster in steps S wide along X rows of sub-pixels
                var scratch_x_u = rast_bounds.start_x_u;
                while (scratch_x_u < rast_bounds.end_x_u) : (scratch_x_u += S) {
                    const scratch_idx = row_offset + scratch_x_u;

                    // Mask based on sub-pixels that have passed the Newton solve stage
                    var mask_arr: [S]bool = undefined;
                    @memcpy(
                        &mask_arr,
                        subpx_scratch.mask[scratch_idx .. scratch_idx + S],
                    );
                    const v_mask_full: VecSB = mask_arr;

                    // Mask based on bounds of the tile/elem overlap
                    const v_scratch_x_u: VecSU = @splat(scratch_x_u);
                    const v_x_mask = (v_scratch_x_u + v_lane_idx >= v_orig_start_x_u) 
                                   & (v_scratch_x_u + v_lane_idx < v_bounds_end_x_u);

                    // Combined mask for sub-pixels to be shaded 
                    const v_mask_active = v_mask_full & v_x_mask;
                    if (@reduce(.Or, v_mask_active)) {
                        // Load our parametric coords into vectors so we can calculate our
                        // shape functions and their derivatives for shading
                        var xi_arr: [S]f64 = undefined;
                        var eta_arr: [S]f64 = undefined;
                        const xi_slice = subpx_scratch.xi[scratch_idx .. scratch_idx + S];
                        const eta_slice = subpx_scratch.eta[scratch_idx .. scratch_idx + S]; 
                        @memcpy(&xi_arr, xi_slice);
                        @memcpy(&eta_arr, eta_slice);
                        const v_xi: VecSF = xi_arr;
                        const v_eta: VecSF = eta_arr;

                        // Shape function weights and derivative calculation based on 
                        // paremetric coords for shading
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

                        // Vectorised depth visibility check on active lanes only, S wide 
                        var v_sum_z: VecSF = @splat(0.0);
                        inline for (0..N) |nn| {
                            v_sum_z += v_weights[nn] * v_nodes_z[nn];
                        }
                        const v_inv_z: VecSF = @as(VecSF, @splat(1.0)) / v_sum_z;

                        const v_old_inv_z = loadVecSF(
                            subpx_scratch.inv_z,
                            scratch_idx,
                        );
                        const v_depth_mask = v_mask_active & (v_inv_z >= v_old_inv_z);
                        const has_depth_hit = @reduce(.Or, v_depth_mask);

                        if (has_depth_hit) {
                            const v_new_inv_z = @select(
                                f64,
                                v_depth_mask,
                                v_inv_z,
                                v_old_inv_z,
                            );
                            storeVecSF(
                                subpx_scratch.inv_z,
                                scratch_idx,
                                v_new_inv_z,
                            );
                            const v_subpx_z: VecSF = @as(VecSF, @splat(1.0)) / v_inv_z;

                            // Record the x sub-pixel limits we have actually shaded to 
                            // reduce the range of nested loops we evaluate to resolve the
                            // sub-pixel anti-aliasing.
                            const lane_depth_mask: [S]bool = v_depth_mask;
                            inline for (0..S) |ll| {
                                if (lane_depth_mask[ll]) {
                                    const touched_x_u = scratch_x_u + ll;
                                    if (touched_x_u <
                                        subpx_scratch.touched_min_x[scratch_y_u])
                                    {
                                        subpx_scratch.touched_min_x[scratch_y_u] =
                                            touched_x_u;
                                    }
                                    if (touched_x_u >
                                        subpx_scratch.touched_max_x[scratch_y_u])
                                    {
                                        subpx_scratch.touched_max_x[scratch_y_u] =
                                            touched_x_u;
                                    }
                                }
                            }


                            // Report: count the pixels to be shaded based on hits
                            const v_hit_one: VecSU8 = @splat(1);
                            const v_hit_zero: VecSU8 = @splat(0);
                            const v_hit_count = @select(
                                u8,
                                v_depth_mask,
                                v_hit_one,
                                v_hit_zero,
                            );
                            const hit_count = @reduce(.Add, v_hit_count);
                            shaded_px += @intCast(hit_count);

                            const ctx_shade = shaderops.ShadeContext(N){
                                .frame_idx = ctx_rast.frame_idx,
                                .elem_idx = targ_overlap.overlap.elem_idx,
                                .fields_num = fields_num,
                                .actual_fields = fields_num,
                                .scratch_idx = scratch_idx,
                                .global_subx = targ_overlap.tile.x_px_min * sub_samp +
                                    scratch_x_u,
                                .global_suby = targ_overlap.tile.y_px_min * sub_samp +
                                    scratch_y_u,
                                .shader_buf = shader_buf,
                                .v_mask_active = v_depth_mask,
                            };

                            ShaderKernel.shadeSIMD(
                                Geometry.coord_space,
                                ctx_shade,
                                ctx_report,
                                v_depth_mask,
                                v_weights,
                                v_nodes_inv_z,
                                v_subpx_z,
                                shader,
                                &subpx_scratch.image,
                            );
                        }
                    }
                }
            }

            return shaded_px;
        }

        /// Scalar fallback for the quad4ibi kernel which didn't work well in SIMD due to
        /// the large amount of branching logic required to handle all cases.
        fn rasterDirect(
            comptime report_mode: ReportMode,
            ctx_rast: rops.RasterContext,
            ctx_report: report.ReportContext(report_mode),
            targ_overlap: common.OverlapTarget,
            mesh_in: rops.MeshInput,
            subpx_domain: SubpxDomain,
            rast_bounds: RasterBounds,
            nodes_coords: Vec3Slices(f64),
            shader: *const ShaderData,
            shader_buf: *const shaderops.LocalShaderBuffer(Geometry.nodes_num),
            subpx_scratch: *SubpxScratchBuffers,
        ) !u64 {
            const N = Geometry.nodes_num;
            var shaded_px: u64 = 0;
            const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
            std.debug.assert(subpx_scratch.image.rows_num <= std.math.maxInt(u8));
            const fields_num: u8 = @intCast(subpx_scratch.image.rows_num);

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
                    const global_subx = targ_overlap.tile.x_px_min *
                        sub_samp + scratch_x_u;
                    const global_suby = targ_overlap.tile.y_px_min *
                        sub_samp + scratch_y_u;

                    if (comptime Geometry.hull_nodes_num > 0) {
                        ctx_report.recordTessChecks(1);
                        const tess_res = element_tess.isInScalar(
                            subpx_x_f,
                            subpx_y_f,
                        );
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
                        ctx_report.recordEarlyOut(
                            global_subx,
                            global_suby,
                            true,
                        );
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
                            if (scratch_x_u <
                                subpx_scratch.touched_min_x[scratch_y_u])
                            {
                                subpx_scratch.touched_min_x[scratch_y_u] =
                                    scratch_x_u;
                            }
                            if (scratch_x_u >
                                subpx_scratch.touched_max_x[scratch_y_u])
                            {
                                subpx_scratch.touched_max_x[scratch_y_u] =
                                    scratch_x_u;
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
                                    targ_overlap.tile.x_px_min +
                                        scratch_x_u / sub_samp,
                                    targ_overlap.tile.y_px_min +
                                        scratch_y_u / sub_samp,
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
    };
}
