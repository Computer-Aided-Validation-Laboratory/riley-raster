const std = @import("std");
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;

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
    };
}

const FeatureConfig = @import("featureconfig.zig").FeatureConfig;
const L = FeatureConfig.simd_lane_width;

pub inline fn calcInvZRastSIMD(comptime N: usize, nodes: Vec3OfSlices(f64), 
                               weights: [N]@Vector(L, f64)) @Vector(L, f64) {
    var inv_z: @Vector(L, f64) = @splat(0.0);
    
    inline for (0..N) |ind| {
        const node_z_inv: @Vector(L, f64) = @splat(1.0 / nodes.z[ind]);
        inv_z += weights[ind] * node_z_inv;
    }
    
    return inv_z;
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

        pub inline fn getWeightsAtSIMD(nodes: Vec3OfSlices(f64), 
                                      pixel_x: f64, pixel_y: f64,
                                      inv_area: f64, step_size: f64,
                                      ) [nodes_num]@Vector(L, f64) {
            const w0 = getWeightsAt(nodes, pixel_x, pixel_y, inv_area);
            const dwdx = getDWeightsDx(nodes, inv_area, step_size);
            
            var weights_simd: [nodes_num]@Vector(L, f64) = undefined;
            inline for (0..nodes_num) |nn| {
                var w_vec: @Vector(L, f64) = undefined;
                inline for (0..L) |ll| {
                    w_vec[ll] = w0[nn] + dwdx[nn] * @as(f64, @floatFromInt(ll));
                }
                weights_simd[nn] = w_vec;
            }
            return weights_simd;
        }

        pub inline fn isInElement(weights: [nodes_num]f64) bool {
            const edge_tol: f64 = 1e-9;

            return weights[0] >= -edge_tol and
                   weights[1] >= -edge_tol and
                   weights[2] >= -edge_tol;
        }

        pub inline fn isInElementSIMD(weights: [nodes_num]@Vector(L, f64)) @Vector(L, bool) {
            const edge_tol_vec: @Vector(L, f64) = @splat(1e-9);

            return (weights[0] >= -edge_tol_vec) &
                   (weights[1] >= -edge_tol_vec) &
                   (weights[2] >= -edge_tol_vec);
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }

        pub inline fn calcInvZSIMD(nodes: Vec3OfSlices(f64), 
                                   weights: [nodes_num]@Vector(L, f64)) @Vector(L, f64) {
            return calcInvZRastSIMD(nodes_num, nodes, weights);
        }
    };
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
