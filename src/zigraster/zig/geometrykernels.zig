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
        const N = 3;
        pub const node_n = N;
        pub const coord_space = CoordSpace.raster;
        pub const strategy = .pointwise;

        pub inline fn getInvElemArea(nodes: Vec3OfSlices(f64)) f64 {
            return 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                       nodes.x[1], nodes.y[1],
                                       nodes.x[2], nodes.y[2],);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, inv_area: f64, ) ?[N]f64 {
            _ = x_offset;
            _ = y_offset;
            
            const edge_tol: f64 = 1e-9;

            var weights: [N]f64 = undefined;
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
                return weights;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            return calcInvZRast(N, nodes, weights);
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        const N = 3;
        pub const node_n = N;
        pub const coord_space = CoordSpace.raster;
        pub const strategy = .incremental;

        pub inline fn getDWeightsDx(nodes: Vec3OfSlices(f64),
                                    inv_area: f64,
                                    step_size: f64,
                                    ) [N]f64 {
            return [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inv_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inv_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inv_area,
            };
        }

        pub inline fn getDWeightsDy(nodes: Vec3OfSlices(f64), 
                                    inv_area: f64,
                                    step_size: f64,
                                    ) [N]f64 {
            return [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inv_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inv_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inv_area,
            };
        }

        pub inline fn getWeightsAt(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   inv_area: f64,) [N]f64 {
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

        pub inline fn isInElement(weights: [N]f64) bool {
            const edge_tol: f64 = 1e-9;

            return weights[0] >= -edge_tol and
                   weights[1] >= -edge_tol and
                   weights[2] >= -edge_tol;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            return calcInvZRast(N, nodes, weights);
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        const N = 6;
        pub const node_n = N;
        pub const coord_space = CoordSpace.clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            var converged = false;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (getTessellatedGuess(target_x,target_y,
                                    nodes.x,nodes.y,nodes.z,
                                    &xi,&eta,)) {
                                    
                converged = newton.solveInverse(N, target_x, target_y, nodes.x, nodes.y,
                                                nodes.z, xi, eta, &xi, &eta,);
            }

            if (!converged) {
                converged = newton.solveInverse(N, target_x, target_y, nodes.x, nodes.y,
                                                nodes.z, 1.0 / 3.0, 1.0 / 3.0, &xi, &eta,);
            }

            if (converged) {
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;

                shapefun.shapeFunctions(
                    N,
                    xi,
                    eta,
                    &node_values,
                    &deriv_nu,
                    &deriv_nv,
                );

                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            return calcInvZClip(N, nodes, weights);
        }

        fn getTessellatedGuess(target_x: f64, target_y: f64, 
                               elem_x: []const f64, elem_y: []const f64, elem_w: []const f64,
                               xi_out: *f64, eta_out: *f64,) bool {

            const area_tol: f64 = 1e-12;
            const eps: f64 = 1e-5;
            
            const SubTriangle = struct {
                node0: u8,
                node1: u8,
                node2: u8,
                xi0: f64,
                eta0: f64,
                xi1: f64,
                eta1: f64,
                xi2: f64,
                eta2: f64,
            };
            
            const sub_triangle_definitions = [_]SubTriangle{
                .{
                    .node0 = 0,
                    .node1 = 3,
                    .node2 = 5,
                    .xi0 = 0.0,
                    .eta0 = 0.0,
                    .xi1 = 0.5,
                    .eta1 = 0.0,
                    .xi2 = 0.0,
                    .eta2 = 0.5,
                },
                .{
                    .node0 = 3,
                    .node1 = 1,
                    .node2 = 4,
                    .xi0 = 0.5,
                    .eta0 = 0.0,
                    .xi1 = 1.0,
                    .eta1 = 0.0,
                    .xi2 = 0.5,
                    .eta2 = 0.5,
                },
                .{
                    .node0 = 5,
                    .node1 = 4,
                    .node2 = 2,
                    .xi0 = 0.0,
                    .eta0 = 0.5,
                    .xi1 = 0.5,
                    .eta1 = 0.5,
                    .xi2 = 0.0,
                    .eta2 = 1.0,
                },
                .{
                    .node0 = 3,
                    .node1 = 4,
                    .node2 = 5,
                    .xi0 = 0.5,
                    .eta0 = 0.0,
                    .xi1 = 0.5,
                    .eta1 = 0.5,
                    .xi2 = 0.0,
                    .eta2 = 0.5,
                },
            };
            for (sub_triangle_definitions) |sub_tri| {
                const x0 = elem_x[sub_tri.node0] / elem_w[sub_tri.node0];
                const y0 = elem_y[sub_tri.node0] / elem_w[sub_tri.node0];
                const x1 = elem_x[sub_tri.node1] / elem_w[sub_tri.node1];
                const y1 = elem_y[sub_tri.node1] / elem_w[sub_tri.node1];
                const x2 = elem_x[sub_tri.node2] / elem_w[sub_tri.node2];
                const y2 = elem_y[sub_tri.node2] / elem_w[sub_tri.node2];

                const area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0);

                if (@abs(area) < area_tol) {
                    continue;
                }
                const weight0 = ((target_x - x0) * (y1 - y0) - (target_y - y0) * (x1 - x0)) 
                    / area;
                const weight1 = ((target_x - x1) * (y2 - y1) - (target_y - y1) * (x2 - x1)) 
                    / area;
                const weight2 = ((target_x - x2) * (y0 - y2) - (target_y - y2) * (x0 - x2)) 
                    / area;

                if (weight0 >= -eps and weight1 >= -eps and weight2 >= -eps) {
                    xi_out.* = weight0 * sub_tri.xi0 
                             + weight1 * sub_tri.xi1 
                             + weight2 * sub_tri.xi2;
                    eta_out.* = weight0 * sub_tri.eta0 
                              + weight1 * sub_tri.eta1 
                              + weight2 * sub_tri.eta2;
                    return true;
                }
            }
            return false;
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        const N = 4;
        pub const node_n = N;
        pub const coord_space = CoordSpace.clip_px_leng;
        pub const strategy = .pointwise;

        pub const SolverParams = struct {
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

        pub inline fn getSolverParams(nodes: Vec3OfSlices(f64)) SolverParams {
            return SolverParams{
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
                                   x_offset: f64,y_offset: f64, solve_params: SolverParams,
                                   ) ?[N]f64 {
            _ = nodes;
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            const ae = solve_params.x_uv_coeff - (solve_params.w_uv_coeff * target_x);
            const be = solve_params.x_u_coeff - (solve_params.w_u_coeff * target_x);
            const ce = solve_params.x_v_coeff - (solve_params.w_v_coeff * target_x);
            const de = solve_params.x_const - (solve_params.w_const * target_x);

            const af = solve_params.y_uv_coeff - (solve_params.w_uv_coeff * target_y);
            const bf = solve_params.y_u_coeff - (solve_params.w_u_coeff * target_y);
            const cf = solve_params.y_v_coeff - (solve_params.w_v_coeff * target_y);
            const df = solve_params.y_const - (solve_params.w_const * target_y);

            const quad_a = (af * be) - (ae * bf);
            const quad_b = (af * de) - (ae * df) + (be * cf) - (bf * ce);
            const quad_c = (cf * de) - (ce * df);

            var coord_u: f64 = -1.0;

            if (solveQuadraticRobust(quad_a, quad_b, quad_c, &coord_u)) {
                const denom_e = (ae * coord_u) + ce;
                const denom_f = (af * coord_u) + cf;
                var coord_v: f64 = -1.0;
                const tolerance_denom = 1e-12;

                if (@abs(denom_f) > @abs(denom_e)) {
                    if (@abs(denom_f) > tolerance_denom) {
                        coord_v = -((bf * coord_u) + df) / denom_f;
                    }
                } else {
                    if (@abs(denom_e) > tolerance_denom) {
                        coord_v = -((be * coord_u) + de) / denom_e;
                    }
                }

                if (coord_v >= -1e-7 and coord_v <= 1.0 + 1e-7) {
                    return [_]f64{
                        (1.0 - coord_u) * (1.0 - coord_v),
                        coord_u * (1.0 - coord_v),
                        coord_u * coord_v,
                        (1.0 - coord_u) * coord_v,
                    };
                }
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sum_weighted_z: f64 = 0.0;
            
            inline for (0..N) |ind| {
                sum_weighted_z += weights[ind] * nodes.z[ind];
            }
            
            return 1.0 / sum_weighted_z;
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
        const N = 4;
        pub const node_n = N;
        pub const coord_space = CoordSpace.clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64,state: anytype,) ?[N]f64 {
            _ = state;

            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (newton.solveInverse(N, target_x, target_y, nodes.x, nodes.y, nodes.z, 
                                    0.5, 0.5, &xi, &eta, )) {
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;
                
                shapefun.shapeFunctions(N, xi, eta, &node_values, &deriv_nu, &deriv_nv,);
                
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            return calcInvZClip(N, nodes, weights);
        }
    };
}

pub fn Quad89Kernel(comptime N: usize) type {
    return struct {
        pub const node_n = N;
        pub const coord_space = CoordSpace.clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, state: anytype,) ?[N]f64 {
            _ = state;
            
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (newton.solveInverse(N, target_x, target_y, nodes.x, nodes.y, nodes.z, 
                0.5, 0.5, &xi, &eta,)) {
                
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;

                shapefun.shapeFunctions(N, xi, eta, &node_values, &deriv_nu, &deriv_nv,);
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            return calcInvZClip(N, nodes, weights);
        }
    };
}
