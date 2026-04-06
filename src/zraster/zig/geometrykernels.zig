const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const S = buildconfig.config.simd_vector_width;
const tol = buildconfig.config.tolerance;
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;

pub const Strategy = enum {
    direct,
    incremental,
    newton,
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

pub fn GeometryResultSIMD(comptime N: usize) type {
    return struct {
        weights: [N]@Vector(S, f64),
        mask: @Vector(S, bool),
        pre_domain_converged: @Vector(S, bool),
        iters: @Vector(S, u8),
        xi_out: @Vector(S, f64),
        eta_out: @Vector(S, f64),
        residual_x: @Vector(S, f64),
        residual_y: @Vector(S, f64),
    };
}

pub inline fn calcInvZRast(comptime N: usize, nodes: Vec3Slices(f64), weights: [N]f64) f64 {
    var inv_z: f64 = 0.0;

    inline for (0..N) |ind| {
        inv_z += weights[ind] * (1.0 / nodes.z[ind]);
    }

    return inv_z;
}

pub inline fn calcInvZClip(comptime N: usize, nodes: Vec3Slices(f64), weights: [N]f64) f64 {
    var sum_weighted_z: f64 = 0.0;

    inline for (0..N) |ind| {
        sum_weighted_z += weights[ind] * nodes.z[ind];
    }

    return 1.0 / sum_weighted_z;
}

pub const NewtonParams = struct {
    w_u_coeff: f64,
    w_v_coeff: f64,
    w_const: f64,
};

pub fn TriWeightStepSIMD(comptime N: usize) type {
    return struct {
        dx: [N]@Vector(S, f64),
        dy: [N]@Vector(S, f64),
        x07: [N]@Vector(S, f64),
    };
}

pub fn Tri3Kernel() type {
    return struct {
        const Self = @This();
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const strategy = .direct;

        pub inline fn getInvElemArea(nodes: Vec3Slices(f64)) f64 {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn getWeightsAt(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            inv_area: f64,
        ) [nodes_num]f64 {
            return [_]f64{
                rops.edgeFun3(
                    nodes.x[1],
                    nodes.y[1],
                    nodes.x[2],
                    nodes.y[2],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
                rops.edgeFun3(
                    nodes.x[2],
                    nodes.y[2],
                    nodes.x[0],
                    nodes.y[0],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
                rops.edgeFun3(
                    nodes.x[0],
                    nodes.y[0],
                    nodes.x[1],
                    nodes.y[1],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
            };
        }

        pub inline fn solveWeights(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            inv_area: f64,
        ) GeometryResult(nodes_num) {
            _ = x_offset;
            _ = y_offset;

            const edge_tol = tol.edge.tri_weight_inclusion;

            var weights: [nodes_num]f64 = undefined;
            weights[0] = rops.edgeFun3(
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
                pixel_x,
                pixel_y,
            ) * inv_area;
            weights[1] = rops.edgeFun3(
                nodes.x[2],
                nodes.y[2],
                nodes.x[0],
                nodes.y[0],
                pixel_x,
                pixel_y,
            ) * inv_area;
            weights[2] = rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                pixel_x,
                pixel_y,
            ) * inv_area;

            if (weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol)
            {
                return .{ .weights = weights, .iters = 1 };
            }
            return .{ .weights = null, .iters = 0 };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }

        pub inline fn getSIMDConstants(nodes: Vec3Slices(f64)) [nodes_num]@Vector(S, f64) {
            var out: [nodes_num]@Vector(S, f64) = undefined;
            inline for (0..nodes_num) |ii| {
                out[ii] = @splat(1.0 / nodes.z[ii]);
            }
            return out;
        }

        pub inline fn getSIMDSteps(
            nodes: Vec3Slices(f64),
            inv_area: f64,
            step_size: f64,
        ) TriWeightStepSIMD(nodes_num) {
            const dx_scalar = [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inv_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inv_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inv_area,
            };
            const dy_scalar = [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inv_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inv_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inv_area,
            };

            var dx: [nodes_num]@Vector(S, f64) = undefined;
            var dy: [nodes_num]@Vector(S, f64) = undefined;
            var x07: [nodes_num]@Vector(S, f64) = undefined;

            const v_07: @Vector(S, f64) = @floatFromInt(std.simd.iota(usize, S));

            inline for (0..nodes_num) |ii| {
                dx[ii] = @splat(dx_scalar[ii] * 8.0);
                dy[ii] = @splat(dy_scalar[ii]);
                x07[ii] = @splat(dx_scalar[ii]);
                x07[ii] *= v_07;
            }

            return .{ .dx = dx, .dy = dy, .x07 = x07 };
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const strategy = .incremental;

        pub inline fn getInvElemArea(nodes: Vec3Slices(f64)) f64 {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn getDWeightsDx(
            nodes: Vec3Slices(f64),
            inv_area: f64,
            step_size: f64,
        ) [nodes_num]f64 {
            return [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inv_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inv_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inv_area,
            };
        }

        pub inline fn getDWeightsDy(
            nodes: Vec3Slices(f64),
            inv_area: f64,
            step_size: f64,
        ) [nodes_num]f64 {
            return [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inv_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inv_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inv_area,
            };
        }

        pub inline fn getWeightsAt(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            inv_area: f64,
        ) [nodes_num]f64 {
            return [_]f64{
                rops.edgeFun3(
                    nodes.x[1],
                    nodes.y[1],
                    nodes.x[2],
                    nodes.y[2],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
                rops.edgeFun3(
                    nodes.x[2],
                    nodes.y[2],
                    nodes.x[0],
                    nodes.y[0],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
                rops.edgeFun3(
                    nodes.x[0],
                    nodes.y[0],
                    nodes.x[1],
                    nodes.y[1],
                    pixel_x,
                    pixel_y,
                ) * inv_area,
            };
        }

        pub inline fn isInElement(weights: [nodes_num]f64) bool {
            const edge_tol = tol.edge.tri_weight_inclusion;

            return weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol;
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZRast(nodes_num, nodes, weights);
        }

        pub inline fn getSIMDConstants(nodes: Vec3Slices(f64)) [nodes_num]@Vector(S, f64) {
            var out: [nodes_num]@Vector(S, f64) = undefined;
            inline for (0..nodes_num) |ii| {
                out[ii] = @splat(1.0 / nodes.z[ii]);
            }
            return out;
        }

        pub inline fn getSIMDSteps(
            nodes: Vec3Slices(f64),
            inv_area: f64,
            step_size: f64,
        ) TriWeightStepSIMD(nodes_num) {
            const dx_scalar = [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inv_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inv_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inv_area,
            };
            const dy_scalar = [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inv_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inv_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inv_area,
            };

            var dx: [nodes_num]@Vector(S, f64) = undefined;
            var dy: [nodes_num]@Vector(S, f64) = undefined;
            var x07: [nodes_num]@Vector(S, f64) = undefined;

            const v_07: @Vector(S, f64) = @floatFromInt(std.simd.iota(usize, S));

            inline for (0..nodes_num) |ii| {
                dx[ii] = @splat(dx_scalar[ii] * 8.0);
                dy[ii] = @splat(dy_scalar[ii]);
                x07[ii] = @splat(dx_scalar[ii]);
                x07[ii] *= v_07;
            }

            return .{ .dx = dx, .dy = dy, .x07 = x07 };
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        pub const nodes_num = 6;
        pub const hull_nodes_num = 6;
        pub const tess_triangles_num = 6;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .newton;

        pub inline fn getNewtonGuess() struct { xi: f64, eta: f64 } {
            return .{ .xi = 1.0 / 3.0, .eta = 1.0 / 3.0 };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(-xi, 0.0) + @max(-eta, 0.0) + @max(xi + eta - 1.0, 0.0);
        }

        pub inline fn getInvElemArea(nodes: Vec3Slices(f64)) f64 {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn solveWeights(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const xi_guess_def: f64 = 1.0 / 3.0;
            const eta_guess_def: f64 = 1.0 / 3.0;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]f64 = undefined;
            var deriv_nu: [nodes_num]f64 = undefined;
            var deriv_nv: [nodes_num]f64 = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_guess_def,
                eta_guess_def,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );

            if (result.converged) {
                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsSIMD(
            nodes: Vec3Slices(f64),
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_guess: @Vector(S, f64),
            v_eta_guess: @Vector(S, f64),
            x_offset: f64,
            y_offset: f64,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(@Vector(S, f64), @splat(x_offset));
            const v_target_y = v_pixel_y - @as(@Vector(S, f64), @splat(y_offset));

            var v_xi_out: @Vector(S, f64) = undefined;
            var v_eta_out: @Vector(S, f64) = undefined;

            var v_weights: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNu: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNv: [nodes_num]@Vector(S, f64) = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_guess,
                v_eta_guess,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.converged,
                .pre_domain_converged = res.pre_domain_converged,
                .iters = res.iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.residual_x,
                .residual_y = res.residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        pub const nodes_num = 4;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .direct;

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

        pub inline fn getBilinearParams(nodes: Vec3Slices(f64)) BilinearParams {
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

        pub inline fn solveWeights(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            solve_params: BilinearParams,
        ) GeometryResult(nodes_num) {
            _ = nodes;
            const eps = tol.geometry.bilinear_parametric_domain;
            const denom_tol = tol.geometry.bilinear_denom;

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

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }

        fn solveQuadraticRobust(
            a_coeff: f64,
            b_coeff: f64,
            c_coeff: f64,
            root_out: *f64,
        ) bool {
            const eps = tol.geometry.bilinear_parametric_domain;
            const area_tol = tol.geometry.quadratic_area;

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
        pub const hull_nodes_num = 4;
        pub const tess_triangles_num = 2;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .newton;

        pub inline fn getNewtonGuess() struct { xi: f64, eta: f64 } {
            return .{ .xi = 0.5, .eta = 0.5 };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeights(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]f64 = undefined;
            var deriv_nu: [nodes_num]f64 = undefined;
            var deriv_nv: [nodes_num]f64 = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_guess_def,
                eta_guess_def,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );
            if (result.converged) {
                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsSIMD(
            nodes: Vec3Slices(f64),
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_guess: @Vector(S, f64),
            v_eta_guess: @Vector(S, f64),
            x_offset: f64,
            y_offset: f64,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(@Vector(S, f64), @splat(x_offset));
            const v_target_y = v_pixel_y - @as(@Vector(S, f64), @splat(y_offset));

            var v_xi_out: @Vector(S, f64) = undefined;
            var v_eta_out: @Vector(S, f64) = undefined;

            var v_weights: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNu: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNv: [nodes_num]@Vector(S, f64) = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_guess,
                v_eta_guess,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.converged,
                .pre_domain_converged = res.pre_domain_converged,
                .iters = res.iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.residual_x,
                .residual_y = res.residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad89Kernel(comptime N: usize) type {
    return struct {
        pub const nodes_num = N;
        pub const hull_nodes_num = 8;
        pub const tess_triangles_num = 8;
        pub const coord_space = .clip_px_leng;
        pub const strategy = .newton;

        pub inline fn getNewtonGuess() struct { xi: f64, eta: f64 } {
            return .{ .xi = 0.5, .eta = 0.5 };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeights(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

            const xi_guess_def: f64 = 0.5;
            const eta_guess_def: f64 = 0.5;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]f64 = undefined;
            var deriv_nu: [nodes_num]f64 = undefined;
            var deriv_nv: [nodes_num]f64 = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_guess_def,
                eta_guess_def,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );

            if (result.converged) {
                return .{ .weights = node_values, .iters = result.iterations };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsSIMD(
            nodes: Vec3Slices(f64),
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_guess: @Vector(S, f64),
            v_eta_guess: @Vector(S, f64),
            x_offset: f64,
            y_offset: f64,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(@Vector(S, f64), @splat(x_offset));
            const v_target_y = v_pixel_y - @as(@Vector(S, f64), @splat(y_offset));

            var v_xi_out: @Vector(S, f64) = undefined;
            var v_eta_out: @Vector(S, f64) = undefined;

            var v_weights: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNu: [nodes_num]@Vector(S, f64) = undefined;
            var v_dNv: [nodes_num]@Vector(S, f64) = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_guess,
                v_eta_guess,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.converged,
                .pre_domain_converged = res.pre_domain_converged,
                .iters = res.iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.residual_x,
                .residual_y = res.residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
