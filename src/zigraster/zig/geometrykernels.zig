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
        pub const nodes_num = 3;
        pub const coord_space = .raster;
        pub const strategy = .pointwise;

        pub inline fn getInvElemArea(nodes: Vec3OfSlices(f64)) f64 {
            return 1.0 / rops.edgeFun3(nodes.x[0], nodes.y[0],
                                       nodes.x[1], nodes.y[1],
                                       nodes.x[2], nodes.y[2],);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, inv_area: f64, 
                                   ) ?[nodes_num]f64 {
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
                return weights;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        pub const nodes_num = 3;
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
    };
}

pub fn Tri6Kernel() type {
    return struct {
        pub const nodes_num = 6;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) ?[nodes_num]f64 {
            _ = state;
            
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const xi_guess_def: f64 = 1.0/3.0;
            const eta_guess_def: f64 = 1.0/3.0;
            var converged = false;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (getTessellatedGuess(target_x,target_y,
                                    nodes.x,nodes.y,nodes.z,
                                    &xi,&eta,)) {
                                    
                converged = newton.solveInverse(nodes_num, target_x, target_y, 
                                                nodes.x, nodes.y, nodes.z, 
                                                xi, eta, &xi, &eta,);
            }

            if (!converged) {
                converged = newton.solveInverse(nodes_num, target_x, target_y, 
                                                nodes.x, nodes.y, nodes.z, 
                                                xi_guess_def, eta_guess_def, &xi, &eta,);
            }

            if (converged) {
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

                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }

        fn getTessellatedGuess(target_x: f64, target_y: f64, 
                               elem_x: []const f64, elem_y: []const f64, elem_w: []const f64,
                               xi_out: *f64, eta_out: *f64,) bool {

            const area_tol: f64 = 1e-12;
            const eps: f64 = 1e-5;
            
            const SubTriangle = struct {
                nodes: [3]u8,
                xi: [3]f64,
                eta: [3]f64,
            };
            
            const sub_triangles = [_]SubTriangle{
                .{
                    .nodes = .{ 0, 3, 5 },
                    .xi = .{ 0.0, 0.5, 0.0 },
                    .eta = .{ 0.0, 0.0, 0.5 },
                },
                .{
                    .nodes = .{ 3, 1, 4 },
                    .xi = .{ 0.5, 1.0, 0.5 },
                    .eta = .{ 0.0, 0.0, 0.5 },
                },
                .{
                    .nodes = .{ 5, 4, 2 },
                    .xi = .{ 0.0, 0.5, 0.0 },
                    .eta = .{ 0.5, 0.5, 1.0 },
                },
                .{
                    .nodes = .{ 3, 4, 5 },
                    .xi = .{ 0.5, 0.5, 0.0 },
                    .eta = .{ 0.0, 0.5, 0.5 },
                },
            };

            for (sub_triangles) |sub_tri| {
                var vx: [3]f64 = undefined;
                var vy: [3]f64 = undefined;

                inline for (0..3) |ii| {
                    const node_ind = sub_tri.nodes[ii];
                    vx[ii] = elem_x[node_ind] / elem_w[node_ind];
                    vy[ii] = elem_y[node_ind] / elem_w[node_ind];
                }

                const area = rops.edgeFun3(vx[0], vy[0], vx[1], vy[1], vx[2], vy[2]);

                if (@abs(area) < area_tol) {
                    continue;
                }

                const inv_area = 1.0 / area;
                
                var weights: [3]f64 = undefined;
                weights[0] = rops.edgeFun3(vx[1], vy[1], vx[2], vy[2], 
                                           target_x, target_y) * inv_area;
                weights[1] = rops.edgeFun3(vx[2], vy[2], vx[0], vy[0], 
                                           target_x, target_y) * inv_area;
                weights[2] = 1.0 - weights[0] - weights[1];

                if (weights[0] >= -eps and weights[1] >= -eps and weights[2] >= -eps) {
                    var xi_res: f64 = 0.0;
                    var eta_res: f64 = 0.0;

                    inline for (0..3) |ii| {
                        xi_res += weights[ii] * sub_tri.xi[ii];
                        eta_res += weights[ii] * sub_tri.eta[ii];
                    }

                    xi_out.* = xi_res;
                    eta_out.* = eta_res;
                    return true;
                }
            }
            return false;
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        pub const nodes_num = 4;
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
                                   ) ?[nodes_num]f64 {
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
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64,state: anytype,
                                   ) ?[nodes_num]f64 {
            _ = state;

            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (newton.solveInverse(nodes_num, target_x, target_y, nodes.x, nodes.y, 
                                    nodes.z, xi_guess_def, eta_guess_def, &xi, &eta, )) {
                var node_values: [nodes_num]f64 = undefined;
                var deriv_nu: [nodes_num]f64 = undefined;
                var deriv_nv: [nodes_num]f64 = undefined;
                
                shapefun.shapeFunctions(nodes_num, xi, eta, &node_values, 
                                        &deriv_nu, &deriv_nv,);
                
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad89Kernel(comptime N: usize) type {
    return struct {
        pub const nodes_num = N;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .pointwise;

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), pixel_x: f64, pixel_y: f64,
                                   x_offset: f64, y_offset: f64, state: anytype,
                                   ) ?[nodes_num]f64 {
            _ = state;

            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (newton.solveInverse(nodes_num, target_x, target_y, nodes.x, nodes.y, 
                nodes.z, xi_guess_def, eta_guess_def, &xi, &eta,)) {

                var node_values: [nodes_num]f64 = undefined;
                var deriv_nu: [nodes_num]f64 = undefined;
                var deriv_nv: [nodes_num]f64 = undefined;

                shapefun.shapeFunctions(nodes_num, xi, eta, &node_values, 
                                        &deriv_nu, &deriv_nv,);
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
