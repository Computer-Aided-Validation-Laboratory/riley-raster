const std = @import("std");
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;
const perf = @import("perf.zig");
const shadekerns = @import("shaderkernels.zig");

pub const Strategy = enum {
    pointwise,
    incremental,
};

pub const CoordSpace = enum {
    raster,
    clip_px_leng,
};

pub fn GeometryResult(comptime N: usize) type {
    return struct {
        weights: ?[N]f64,
        iters: u8,
    };
}

pub inline fn calcInvZRast(comptime N: usize, nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
    var inv_z: f64 = 0.0;
    
    inline for (0..N) |ind| {
        inv_z += weights[ind] * (1.0 / nodes.z[ind]);
    }
    
    return inv_z;
}

pub inline fn calcInvZClip(comptime N: usize, nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
    var sum_weighted_z: f64 = 0.0;
    
    inline for (0..N) |ind| {
        sum_weighted_z += weights[ind] * nodes.z[ind];
    }
    
    return 1.0 / sum_weighted_z;
}

pub fn Tri3Kernel() type {
    return struct {
        const Self = @This();
        pub const nodes_num = 3;
        pub const has_hull = false;
        pub const coord_space = .raster;
        pub const strategy = .pointwise;

        pub inline fn getInvElemArea(nodes: Vec3OfSlices(f64)) f64 {
            return 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                       nodes.x[1], nodes.y[1],
                                       nodes.x[2], nodes.y[2],);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, inv_area: f64, 
                                   ) GeometryResult(nodes_num) {
            _ = x_offset;
            _ = y_offset;
            
            const edge_tol: f64 = 1e-9;

            var weights: [nodes_num]f64 = undefined;
            weights[0] = rops.edgeFun3(nodes.x[1],nodes.y[1],
                                       nodes.x[2],nodes.y[2],
                                       pixel_x,pixel_y,) * inv_area;
            weights[1] = rops.edgeFun3(nodes.x[2],nodes.y[2],
                                       nodes.x[0],nodes.y[0],
                                       pixel_x,pixel_y,) * inv_area;
            weights[2] = rops.edgeFun3(nodes.x[0],nodes.y[0],
                                       nodes.x[1],nodes.y[1],
                                       pixel_x,pixel_y,) * inv_area;

            if (weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol)
            {
                return .{ .weights = weights, .iters = 1 };
            }
            return .{ .weights = null, .iters = 0 };
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }

        pub inline fn fastFill(
            comptime report: perf.Report,
            comptime ShaderKernel: type,
            ctx_rast: anytype,
            target: anytype,
            domain: anytype,
            bounds: anytype,
            nodes: Vec3OfSlices(f64),
            shader: anytype,
            scratch: anytype,
            local_buf: anytype,
        ) !u64 {
            return incrementalFastFill(
                nodes_num, report, ShaderKernel, ctx_rast, target, domain,
                bounds, nodes, shader, scratch, local_buf,
            );
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const has_hull = false;
        pub const coord_space = .raster;
        pub const strategy = .incremental;

        pub inline fn getDWeightsDx(nodes: Vec3OfSlices(f64),
                                    inv_area: f64,
                                    step_size: f64,
                                    ) [nodes_num]f64 {
            return [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inv_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inv_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inv_area,
            };
        }

        pub inline fn getDWeightsDy(nodes: Vec3OfSlices(f64), 
                                    inv_area: f64,
                                    step_size: f64,
                                    ) [nodes_num]f64 {
            return [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inv_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inv_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inv_area,
            };
        }

        pub inline fn getWeightsAt(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   inv_area: f64,) [nodes_num]f64 {
            return [_]f64{
                rops.edgeFun3(nodes.x[1], nodes.y[1],
                              nodes.x[2], nodes.y[2],
                              pixel_x, pixel_y,) * inv_area,
                rops.edgeFun3(nodes.x[2], nodes.y[2],
                              nodes.x[0], nodes.y[0],
                              pixel_x, pixel_y,) * inv_area,
                rops.edgeFun3(nodes.x[0], nodes.y[0],
                              nodes.x[1], nodes.y[1],
                              pixel_x, pixel_y,) * inv_area,
            };
        }

        pub inline fn isInElement(weights: [nodes_num]f64) bool {
            const edge_tol: f64 = 1e-9;

            return weights[0] >= -edge_tol and
                   weights[1] >= -edge_tol and
                   weights[2] >= -edge_tol;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }

        pub inline fn fastFill(
            comptime report: perf.Report,
            comptime ShaderKernel: type,
            ctx_rast: anytype,
            target: anytype,
            domain: anytype,
            bounds: anytype,
            nodes: Vec3OfSlices(f64),
            shader: anytype,
            scratch: anytype,
            local_buf: anytype,
        ) !u64 {
            return incrementalFastFill(
                nodes_num, report, ShaderKernel, ctx_rast, target, domain,
                bounds, nodes, shader, scratch, local_buf,
            );
        }
    };
}

pub fn incrementalFastFill(
    comptime N: usize,
    comptime report: perf.Report,
    comptime ShaderKernel: type,
    ctx_rast: anytype,
    target: anytype,
    domain: anytype,
    bounds: anytype,
    nodes: rops.Vec3OfSlices(f64),
    shader: anytype,
    scratch: anytype,
    local_buf: anytype,
) !u64 {
    var shaded_px: u64 = 0;
    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const fields_num = scratch.image.cols_num;

    var nodes_inv_z: [N]f64 = undefined;
    inline for (0..N) |nn| {
        nodes_inv_z[nn] = 1.0 / nodes.z[nn];
    }

    const inv_area = 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                         nodes.x[1], nodes.y[1],
                                         nodes.x[2], nodes.y[2]);

    const dweights_dx = [_]f64{
        (nodes.y[2] - nodes.y[1]) * domain.step * inv_area,
        (nodes.y[0] - nodes.y[2]) * domain.step * inv_area,
        (nodes.y[1] - nodes.y[0]) * domain.step * inv_area,
    };
    const dweights_dy = [_]f64{
        (nodes.x[1] - nodes.x[2]) * domain.step * inv_area,
        (nodes.x[2] - nodes.x[0]) * domain.step * inv_area,
        (nodes.x[0] - nodes.x[1]) * domain.step * inv_area,
    };

    const start_x = bounds.x_min_f + domain.offset;
    const start_y = bounds.y_min_f + domain.offset;
    var weights_row = [_]f64{
        rops.edgeFun3(nodes.x[1], nodes.y[1], nodes.x[2], nodes.y[2], 
                      start_x, start_y) * inv_area,
        rops.edgeFun3(nodes.x[2], nodes.y[2], nodes.x[0], nodes.y[0], 
                      start_x, start_y) * inv_area,
        rops.edgeFun3(nodes.x[0], nodes.y[0], nodes.x[1], nodes.y[1], 
                      start_x, start_y) * inv_area,
    };

    for (bounds.start_y..bounds.end_y) |scratch_y| {
        const row_offset = scratch_y * domain.tile_size;
        var weights = weights_row;

        for (bounds.start_x..bounds.end_x) |scratch_x| {
            var inv_z: f64 = 0.0;
            inline for (0..N) |nn| {
                inv_z += weights[nn] * nodes_inv_z[nn];
            }
            const index = row_offset + scratch_x;

            if (inv_z >= scratch.inv_z[index]) {
                scratch.inv_z[index] = inv_z;
                const subpx_z = 1.0 / inv_z;
                shaded_px += 1;

                const global_subx = target.tile.x_px_min * sub_samp + scratch_x;
                const global_suby = target.tile.y_px_min * sub_samp + scratch_y;

                if (comptime report == .perf) {
                    ctx_rast.ctx_perf.recordPixel(global_subx, global_suby, 0);
                    ctx_rast.ctx_perf.recordPixelOccupancy(
                        target.tile.x_px_min + scratch_x / sub_samp,
                        target.tile.y_px_min + scratch_y / sub_samp,
                    );
                }

                if (comptime @typeInfo(@TypeOf(ShaderKernel.shade)).@"fn".params.len == 5) {
                    ShaderKernel.shade(
                        .raster,
                        .{
                            .frame_index = ctx_rast.frame_ind,
                            .elem_index = target.overlap.elem_idx,
                            .fields_num = fields_num,
                            .actual_fields = fields_num,
                            .idx = index,
                            .global_subx = global_subx,
                            .global_suby = global_suby,
                            .local_buf = local_buf,
                        },
                        .{
                            .weights = weights,
                            .nodes_inv_z = nodes_inv_z,
                            .sub_pixel_z = subpx_z,
                        },
                        ctx_rast.ctx_perf,
                        scratch.image,
                    );
                } else {
                    ShaderKernel.shade(
                        .raster,
                        .{
                            .frame_index = ctx_rast.frame_ind,
                            .elem_index = target.overlap.elem_idx,
                            .fields_num = fields_num,
                            .actual_fields = fields_num,
                            .idx = index,
                            .global_subx = global_subx,
                            .global_suby = global_suby,
                            .local_buf = local_buf,
                        },
                        .{
                            .weights = weights,
                            .nodes_inv_z = nodes_inv_z,
                            .sub_pixel_z = subpx_z,
                        },
                        shader,
                        ctx_rast.ctx_perf,
                        scratch.image,
                    );
                }
            }
            inline for (0..N) |nn| {
                weights[nn] += dweights_dx[nn];
            }
        }
        inline for (0..N) |nn| {
            weights_row[nn] += dweights_dy[nn];
        }
    }
    return shaded_px;
}

pub fn Tri6Kernel() type {
    return struct {
        pub const nodes_num = 6;
        pub const has_hull = true;
        pub const hull_nodes_num = 6;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) GeometryResult(nodes_num) {
            _ = state;
            
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const xi_guess_def: f64 = 1.0/3.0;
            const eta_guess_def: f64 = 1.0/3.0;
            
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            const result = newton.solveInverse(
                nodes_num, target_x, target_y, 
                nodes.x, nodes.y, nodes.z, 
                xi_guess_def, eta_guess_def, &xi, &eta,
            );

            if (result.converged) {
                var node_values: [nodes_num]f64 = undefined;
                var deriv_nu: [nodes_num]f64 = undefined;
                var deriv_nv: [nodes_num]f64 = undefined;

                shapefun.shapeFunctions(
                    nodes_num,
                    xi,
                    eta,
                    &node_values,
                    &deriv_nu,
                    &deriv_nv,
                );

                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        pub const nodes_num = 4;
        pub const has_hull = false;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub const BilinearParams = struct {
            x_uv_coeff: f64,
            x_u_coeff: f64,
            x_v_coeff: f64,
            x_const: f64,
            y_uv_coeff: f64,
            y_u_coeff: f64,
            y_v_coeff: f64,
            y_const: f64,
            w_uv_coeff: f64,
            w_u_coeff: f64,
            w_v_coeff: f64,
            w_const: f64,
        };

        pub inline fn getBilinearParams(nodes: Vec3OfSlices(f64)) BilinearParams {
            return BilinearParams{
                .x_uv_coeff = nodes.x[0] - nodes.x[1] + nodes.x[2] - nodes.x[3],
                .x_u_coeff = nodes.x[1] - nodes.x[0],
                .x_v_coeff = nodes.x[3] - nodes.x[0],
                .x_const = nodes.x[0],
                .y_uv_coeff = nodes.y[0] - nodes.y[1] + nodes.y[2] - nodes.y[3],
                .y_u_coeff = nodes.y[1] - nodes.y[0],
                .y_v_coeff = nodes.y[3] - nodes.y[0],
                .y_const = nodes.y[0],
                .w_uv_coeff = nodes.z[0] - nodes.z[1] + nodes.z[2] - nodes.z[3],
                .w_u_coeff = nodes.z[1] - nodes.z[0],
                .w_v_coeff = nodes.z[3] - nodes.z[0],
                .w_const = nodes.z[0],
            };
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64,y_offset: f64, solve_params: BilinearParams,
                                   ) GeometryResult(nodes_num) {
            _ = nodes;
            const eps: f64 = 1e-7;
            const denom_tol = 1e-12;
            
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            const res_x_uv = solve_params.x_uv_coeff - (solve_params.w_uv_coeff * target_x);
            const res_x_u = solve_params.x_u_coeff - (solve_params.w_u_coeff * target_x);
            const res_x_v = solve_params.x_v_coeff - (solve_params.w_v_coeff * target_x);
            const res_x_const = solve_params.x_const - (solve_params.w_const * target_x);

            const res_y_uv = solve_params.y_uv_coeff - (solve_params.w_uv_coeff * target_y);
            const res_y_u = solve_params.y_u_coeff - (solve_params.w_u_coeff * target_y);
            const res_y_v = solve_params.y_v_coeff - (solve_params.w_v_coeff * target_y);
            const res_y_const = solve_params.y_const - (solve_params.w_const * target_y);

            const quad_a = (res_y_uv * res_x_u) - (res_x_uv * res_y_u);
            const quad_b = (res_y_uv * res_x_const) - (res_x_uv * res_y_const) + 
                           (res_x_v * res_y_u) - (res_y_v * res_x_u);
            const quad_c = (res_x_v * res_y_const) - (res_y_v * res_x_const);

            var coord_u: f64 = -1.0;

            if (solveQuadraticRobust(quad_a, quad_b, quad_c, &coord_u)) {
                const denom_e = (res_x_uv * coord_u) + res_x_v;
                const denom_f = (res_y_uv * coord_u) + res_y_v;
                var coord_v: f64 = -1.0;

                if (@abs(denom_f) > @abs(denom_e)) {
                    if (@abs(denom_f) > denom_tol) {
                        coord_v = -((res_y_u * coord_u) + res_y_const) / denom_f;
                    }
                } else {
                    if (@abs(denom_e) > denom_tol) {
                        coord_v = -((res_x_u * coord_u) + res_x_const) / denom_e;
                    }
                }

                if (coord_v >= -eps and coord_v <= 1.0 + eps) {
                    return .{
                        .weights = [_]f64{
                            (1.0 - coord_u) * (1.0 - coord_v),
                            coord_u * (1.0 - coord_v),
                            coord_u * coord_v,
                            (1.0 - coord_u) * coord_v,
                        },
                        .iters = 1,
                    };
                }
            }
            return .{ .weights = null, .iters = 0 };
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }

        fn solveQuadraticRobust(a_coeff: f64, b_coeff: f64, c_coeff: f64, root_out: *f64,
                                ) bool {
            const eps = 1e-7;
            const area_tol = 1e-12;
            
            if (@abs(a_coeff) < area_tol) {
                if (@abs(b_coeff) < area_tol) {
                    return false;
                }
                const root = -c_coeff / b_coeff;
                if (root >= -eps and root <= 1.0 + eps) {
                    root_out.* = root;
                    return true;
                }
                return false;
            }

            const disc = (b_coeff * b_coeff) - (4.0 * a_coeff * c_coeff);

            if (disc < 0) {
                return false;
            }

            const sqrt_disc = @sqrt(disc);
            const intermediate_q = -0.5 * (b_coeff + (if (b_coeff >= 0)
                sqrt_disc
            else
                -sqrt_disc));

            const roots = [2]f64{
                intermediate_q / a_coeff,
                c_coeff / intermediate_q,
            };

            for (roots) |root| {
                if (root >= -eps and root <= 1.0 + eps) {
                    root_out.* = root;
                    return true;
                }
            }
            return false;
        }
    };
}

pub fn Quad4NewtonKernel() type {
    return struct {
        pub const nodes_num = 4;
        pub const has_hull = true;
        pub const hull_nodes_num = 4;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64,state: anytype,
                                   ) GeometryResult(nodes_num) {
            _ = state;

            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            const result = newton.solveInverse(
                nodes_num, target_x, target_y, 
                nodes.x, nodes.y, nodes.z, 
                xi_guess_def, eta_guess_def, &xi, &eta,
            );
            if (result.converged) {
                var node_values: [nodes_num]f64 = undefined;
                var deriv_nu: [nodes_num]f64 = undefined;
                var deriv_nv: [nodes_num]f64 = undefined;
                
                shapefun.shapeFunctions(nodes_num, xi, eta, &node_values, 
                                        &deriv_nu, &deriv_nv,);
                
                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad89Kernel(comptime N: usize) type {
    return struct {
        pub const nodes_num = N;
        pub const has_hull = true;
        pub const hull_nodes_num = 8;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, state: anytype,
                                   ) GeometryResult(nodes_num) {
            _ = state;

            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            const result = newton.solveInverse(
                nodes_num, target_x, target_y, 
                nodes.x, nodes.y, nodes.z, 
                xi_guess_def, eta_guess_def, &xi, &eta,
            );

            if (result.converged) {

                var node_values: [nodes_num]f64 = undefined;
                var deriv_nu: [nodes_num]f64 = undefined;
                var deriv_nv: [nodes_num]f64 = undefined;

                shapefun.shapeFunctions(nodes_num, xi, eta, &node_values, 
                                        &deriv_nu, &deriv_nv,);
                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
