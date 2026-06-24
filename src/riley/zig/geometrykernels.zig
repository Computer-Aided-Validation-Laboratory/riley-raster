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
const F = buildconfig.F;
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU8 = buildconfig.VecSU8;
const tol = cfg.tolerance;

const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const NewtonSeed = newton.NewtonSeed;
const NewtonSeedSIMD = newton.NewtonSeedSIMD;
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;
const rastcfg = @import("rasterconfig.zig");

pub const TRI_CENTROID_XI: F = 1.0 / 3.0;
pub const TRI_CENTROID_ETA: F = 1.0 / 3.0;
pub const QUAD_CENTROID_XI: F = 0.0;
pub const QUAD_CENTROID_ETA: F = 0.0;

pub const MeshType = enum {
    tri3,
    tri3opt,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,

    pub inline fn getNodesNum(self: MeshType) usize {
        return switch (self) {
            .tri3, .tri3opt => 3,
            .tri6 => 6,
            .quad4ibi, .quad4newton => 4,
            .quad8 => 8,
            .quad9 => 9,
        };
    }

    pub inline fn getNumHullPoints(self: MeshType) usize {
        return switch (self) {
            .tri3, .tri3opt => 0,
            .tri6 => 6,
            .quad4ibi, .quad4newton => 4,
            .quad8, .quad9 => 8,
        };
    }
};

pub const SolverKind = enum {
    hyperb,
    newton,
    inv_bi,
};

pub const CoordSpace = enum {
    raster,
    clip_px_leng,
};

pub fn GeometryResult(comptime N: usize) type {
    return struct {
        weights: ?[N]F,
        iters: u8,
        xi_out: F = 0.0,
        eta_out: F = 0.0,
    };
}

pub fn GeometryResultSIMD(comptime N: usize) type {
    return struct {
        v_weights: [N]VecSF,
        v_mask: VecSB,
        v_pre_domain_converged: VecSB = @splat(true),
        v_iters: VecSU8,
        v_xi_out: VecSF = undefined,
        v_eta_out: VecSF = undefined,
        v_residual_x: VecSF = undefined,
        v_residual_y: VecSF = undefined,
    };
}

pub inline fn calcInvZClip(
    comptime N: usize,
    nodes: Vec3Slices(F),
    weights: [N]F,
) F {
    var sum_weighted_z: F = 0.0;

    inline for (0..N) |ind| {
        sum_weighted_z += weights[ind] * nodes.z[ind];
    }

    return 1.0 / sum_weighted_z;
}

pub const NewtonParams = struct {
    w_u_coeff: F,
    w_v_coeff: F,
    w_const: F,
};

pub fn Tri3Kernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const solver_kind = .hyperb;

        pub inline fn getInvElemArea(nodes: Vec3Slices(F)) F {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn solveWeightsHyperb(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            inv_area: F,
        ) GeometryResult(nodes_num) {
            const weights = getWeightsAt(nodes, pixel_x, pixel_y, inv_area);

            if (isInElement(weights)) {
                return .{ .weights = weights, .iters = 1 };
            }

            return .{ .weights = null, .iters = 1 };
        }

        pub inline fn getWeightsAt(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            inv_area: F,
        ) [nodes_num]F {
            return [_]F{
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

        pub inline fn isInElement(weights: [nodes_num]F) bool {
            const edge_tol = tol.edge.tri_weight_inclusion;

            return weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol;
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
            var inv_z: F = 0.0;

            inline for (0..nodes_num) |nn| {
                inv_z += weights[nn] * (1.0 / nodes.z[nn]);
            }

            return inv_z;
        }

        pub inline fn solveWeightsHyperbSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_inv_area: VecSF,
        ) GeometryResultSIMD(nodes_num) {
            const v_weights = getWeightsAtSIMD(
                nodes,
                v_pixel_x,
                v_pixel_y,
                v_inv_area,
            );
            const v_mask = isInElementSIMD(v_weights);

            return .{
                .v_weights = v_weights,
                .v_mask = v_mask,
                .v_iters = @splat(1),
            };
        }

        pub inline fn getWeightsAtSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_inv_area: VecSF,
        ) [nodes_num]VecSF {
            return [_]VecSF{
                rops.edgeFun3SIMD(
                    nodes.x[1],
                    nodes.y[1],
                    nodes.x[2],
                    nodes.y[2],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
                rops.edgeFun3SIMD(
                    nodes.x[2],
                    nodes.y[2],
                    nodes.x[0],
                    nodes.y[0],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
                rops.edgeFun3SIMD(
                    nodes.x[0],
                    nodes.y[0],
                    nodes.x[1],
                    nodes.y[1],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
            };
        }

        pub inline fn isInElementSIMD(v_weights: [nodes_num]VecSF) VecSB {
            const edge_tol = tol.edge.tri_weight_inclusion;
            const v_edge_tol: VecSF = @splat(-edge_tol);

            return (v_weights[0] >= v_edge_tol) &
                (v_weights[1] >= v_edge_tol) &
                (v_weights[2] >= v_edge_tol);
        }

        pub inline fn calcInvZSIMD(
            nodes_inv_z: [nodes_num]VecSF,
            v_weights: [nodes_num]VecSF,
        ) VecSF {
            var v_inv_z: VecSF = @splat(0.0);

            inline for (0..nodes_num) |nn| {
                v_inv_z += v_weights[nn] * nodes_inv_z[nn];
            }

            return v_inv_z;
        }

        pub inline fn getSIMDInvZ(nodes: Vec3Slices(F)) [nodes_num]VecSF {
            var out: [nodes_num]VecSF = undefined;
            inline for (0..nodes_num) |ii| {
                out[ii] = @splat(1.0 / nodes.z[ii]);
            }
            return out;
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const solver_kind = .hyperb;

        pub inline fn getInvElemArea(nodes: Vec3Slices(F)) F {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn solveWeightsHyperb(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            inv_area: F,
        ) GeometryResult(nodes_num) {
            const weights = getWeightsAt(nodes, pixel_x, pixel_y, inv_area);

            if (isInElement(weights)) {
                return .{ .weights = weights, .iters = 1 };
            }

            return .{ .weights = null, .iters = 1 };
        }

        pub inline fn getWeightsAt(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            inv_area: F,
        ) [nodes_num]F {
            return [_]F{
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

        pub inline fn isInElement(weights: [nodes_num]F) bool {
            const edge_tol = tol.edge.tri_weight_inclusion;

            return weights[0] >= -edge_tol and
                weights[1] >= -edge_tol and
                weights[2] >= -edge_tol;
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
            var inv_z: F = 0.0;

            inline for (0..nodes_num) |nn| {
                inv_z += weights[nn] * (1.0 / nodes.z[nn]);
            }

            return inv_z;
        }

        pub inline fn solveWeightsHyperbSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_inv_area: VecSF,
        ) GeometryResultSIMD(nodes_num) {
            const v_weights = getWeightsAtSIMD(
                nodes,
                v_pixel_x,
                v_pixel_y,
                v_inv_area,
            );
            const v_mask = isInElementSIMD(v_weights);

            return .{
                .v_weights = v_weights,
                .v_mask = v_mask,
                .v_iters = @splat(1),
            };
        }

        pub inline fn getWeightsAtSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_inv_area: VecSF,
        ) [nodes_num]VecSF {
            return [_]VecSF{
                rops.edgeFun3SIMD(
                    nodes.x[1],
                    nodes.y[1],
                    nodes.x[2],
                    nodes.y[2],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
                rops.edgeFun3SIMD(
                    nodes.x[2],
                    nodes.y[2],
                    nodes.x[0],
                    nodes.y[0],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
                rops.edgeFun3SIMD(
                    nodes.x[0],
                    nodes.y[0],
                    nodes.x[1],
                    nodes.y[1],
                    v_pixel_x,
                    v_pixel_y,
                ) * v_inv_area,
            };
        }

        pub inline fn isInElementSIMD(v_weights: [nodes_num]VecSF) VecSB {
            const edge_tol = tol.edge.tri_weight_inclusion;
            const v_edge_tol: VecSF = @splat(-edge_tol);

            return (v_weights[0] >= v_edge_tol) &
                (v_weights[1] >= v_edge_tol) &
                (v_weights[2] >= v_edge_tol);
        }

        pub inline fn calcInvZSIMD(
            nodes_inv_z: [nodes_num]VecSF,
            v_weights: [nodes_num]VecSF,
        ) VecSF {
            var v_inv_z: VecSF = @splat(0.0);

            inline for (0..nodes_num) |nn| {
                v_inv_z += v_weights[nn] * nodes_inv_z[nn];
            }

            return v_inv_z;
        }

        pub inline fn getSIMDInvZ(nodes: Vec3Slices(F)) [nodes_num]VecSF {
            var out: [nodes_num]VecSF = undefined;
            inline for (0..nodes_num) |ii| {
                out[ii] = @splat(1.0 / nodes.z[ii]);
            }
            return out;
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        pub const nodes_num = 6;
        pub const hull_nodes_num = 6;
        pub const tess_triangles_num = 6;
        pub const coord_space = .clip_px_leng;
        pub const solver_kind = .newton;

        pub inline fn initSeed(seed_mode: rastcfg.NewtonSeedMode, hull_seed: ?NewtonSeed) NewtonSeed {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = TRI_CENTROID_XI, .eta = TRI_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(
            seed_mode: rastcfg.NewtonSeedMode,
            hull_seed: ?NewtonSeedSIMD,
        ) NewtonSeedSIMD {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(TRI_CENTROID_XI),
                .v_eta = @splat(TRI_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: F, eta: F) F {
            return @max(-xi, 0.0) + @max(-eta, 0.0) + @max(xi + eta - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            x_offset: F,
            y_offset: F,
            xi_seed: F,
            eta_seed: F,
        ) GeometryResult(nodes_num) {
            var xi: F = 0.0;
            var eta: F = 0.0;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]F = undefined;
            var deriv_nu: [nodes_num]F = undefined;
            var deriv_nv: [nodes_num]F = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_seed,
                eta_seed,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );

            if (result.converged) {
                return .{
                    .weights = node_values,
                    .iters = result.iterations,
                    .xi_out = xi,
                    .eta_out = eta,
                };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsNewtonSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: F,
            y_offset: F,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(VecSF, @splat(x_offset));
            const v_target_y = v_pixel_y - @as(VecSF, @splat(y_offset));

            var v_xi_out: VecSF = undefined;
            var v_eta_out: VecSF = undefined;

            var v_weights: [nodes_num]VecSF = undefined;
            var v_dNu: [nodes_num]VecSF = undefined;
            var v_dNv: [nodes_num]VecSF = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .v_weights = v_weights,
                .v_mask = res.v_converged,
                .v_pre_domain_converged = res.v_pre_domain_converged,
                .v_iters = res.v_iterations,
                .v_xi_out = v_xi_out,
                .v_eta_out = v_eta_out,
                .v_residual_x = res.v_residual_x,
                .v_residual_y = res.v_residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        pub const nodes_num = 4;
        pub const hull_nodes_num = 4;
        pub const tess_triangles_num = 2;
        pub const coord_space = .clip_px_leng;
        pub const solver_kind = .inv_bi;

        pub const BilinearParams = struct {
            x_uv_coeff: F,
            x_u_coeff: F,
            x_v_coeff: F,
            x_const: F,
            y_uv_coeff: F,
            y_u_coeff: F,
            y_v_coeff: F,
            y_const: F,
            w_uv_coeff: F,
            w_u_coeff: F,
            w_v_coeff: F,
            w_const: F,
        };

        pub inline fn getBilinearParams(nodes: Vec3Slices(F)) BilinearParams {
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

        const InvBiPoly = struct {
            const_term: F,
            xi_term: F,
            eta_term: F,
            xi_eta_term: F,
        };

        const InvBiResidual = struct {
            x: InvBiPoly,
            y: InvBiPoly,
        };

        const Candidate = struct {
            xi: F,
            eta: F,
            resid_sq: F,
        };

        inline fn buildWeights(xi: F, eta: F) [nodes_num]F {
            const v_xi_terms = @Vector(2, F){ 1.0 - xi, xi };
            const v_eta_terms = @Vector(2, F){ 1.0 - eta, eta };
            return .{
                v_xi_terms[0] * v_eta_terms[0],
                v_xi_terms[1] * v_eta_terms[0],
                v_xi_terms[1] * v_eta_terms[1],
                v_xi_terms[0] * v_eta_terms[1],
            };
        }

        inline fn getInvBiResidual(
            target_x: F,
            target_y: F,
            solve_params: BilinearParams,
        ) InvBiResidual {
            return .{
                .x = .{
                    .const_term = solve_params.x_const - (solve_params.w_const * target_x),
                    .xi_term = solve_params.x_u_coeff - (solve_params.w_u_coeff * target_x),
                    .eta_term = solve_params.x_v_coeff - (solve_params.w_v_coeff * target_x),
                    .xi_eta_term = solve_params.x_uv_coeff -
                        (solve_params.w_uv_coeff * target_x),
                },
                .y = .{
                    .const_term = solve_params.y_const - (solve_params.w_const * target_y),
                    .xi_term = solve_params.y_u_coeff - (solve_params.w_u_coeff * target_y),
                    .eta_term = solve_params.y_v_coeff - (solve_params.w_v_coeff * target_y),
                    .xi_eta_term = solve_params.y_uv_coeff -
                        (solve_params.w_uv_coeff * target_y),
                },
            };
        }

        inline fn solveOtherCoordFromXi(
            xi: F,
            residual: InvBiResidual,
            denom_tol: F,
        ) ?F {
            const denom_x = residual.x.eta_term + (residual.x.xi_eta_term * xi);
            const denom_y = residual.y.eta_term + (residual.y.xi_eta_term * xi);

            if (@abs(denom_x) > @abs(denom_y)) {
                if (@abs(denom_x) <= denom_tol) return null;
                return -((residual.x.const_term + (residual.x.xi_term * xi)) / denom_x);
            }
            if (@abs(denom_y) <= denom_tol) return null;
            return -((residual.y.const_term + (residual.y.xi_term * xi)) / denom_y);
        }

        inline fn solveOtherCoordFromEta(
            eta: F,
            residual: InvBiResidual,
            denom_tol: F,
        ) ?F {
            const denom_x = residual.x.xi_term + (residual.x.xi_eta_term * eta);
            const denom_y = residual.y.xi_term + (residual.y.xi_eta_term * eta);

            if (@abs(denom_x) > @abs(denom_y)) {
                if (@abs(denom_x) <= denom_tol) return null;
                return -((residual.x.const_term + (residual.x.eta_term * eta)) / denom_x);
            }
            if (@abs(denom_y) <= denom_tol) return null;
            return -((residual.y.const_term + (residual.y.eta_term * eta)) / denom_y);
        }

        inline fn rootsFromQuadratic(
            a_coeff: F,
            b_coeff: F,
            c_coeff: F,
            zero_tol: F,
        ) struct { count: u8, roots: [2]F } {
            var roots = [2]F{ 0.0, 0.0 };

            if (@abs(a_coeff) < zero_tol) {
                if (@abs(b_coeff) < zero_tol) {
                    return .{ .count = 0, .roots = roots };
                }
                roots[0] = -c_coeff / b_coeff;
                return .{ .count = 1, .roots = roots };
            }

            var disc = (b_coeff * b_coeff) - (4.0 * a_coeff * c_coeff);
            if (disc < -zero_tol) {
                return .{ .count = 0, .roots = roots };
            }
            if (disc < 0.0) disc = 0.0;

            const sqrt_disc = @sqrt(disc);
            if (sqrt_disc < zero_tol) {
                roots[0] = -0.5 * b_coeff / a_coeff;
                return .{ .count = 1, .roots = roots };
            }

            const q_term = -0.5 * (b_coeff +
                (if (b_coeff >= 0.0) sqrt_disc else -sqrt_disc));

            if (@abs(q_term) < zero_tol) {
                roots[0] = (-b_coeff + sqrt_disc) / (2.0 * a_coeff);
                roots[1] = (-b_coeff - sqrt_disc) / (2.0 * a_coeff);
                return .{ .count = 2, .roots = roots };
            }

            roots[0] = q_term / a_coeff;
            roots[1] = c_coeff / q_term;
            return .{ .count = 2, .roots = roots };
        }

        inline fn tryCandidate(
            best_candidate: *?Candidate,
            xi: F,
            eta: F,
            residual: InvBiResidual,
            eps: F,
        ) void {
            if (xi < -eps or xi > 1.0 + eps) return;
            if (eta < -eps or eta > 1.0 + eps) return;

            const resid_x =
                residual.x.const_term +
                (residual.x.xi_term * xi) +
                (residual.x.eta_term * eta) +
                (residual.x.xi_eta_term * xi * eta);
            const resid_y =
                residual.y.const_term +
                (residual.y.xi_term * xi) +
                (residual.y.eta_term * eta) +
                (residual.y.xi_eta_term * xi * eta);
            const resid_sq = (resid_x * resid_x) + (resid_y * resid_y);

            if (best_candidate.*) |curr| {
                if (resid_sq >= curr.resid_sq) return;
            }
            best_candidate.* = .{
                .xi = xi,
                .eta = eta,
                .resid_sq = resid_sq,
            };
        }

        pub inline fn solveWeightsInvBi(
            pixel_x: F,
            pixel_y: F,
            x_offset: F,
            y_offset: F,
            solve_params: BilinearParams,
        ) GeometryResult(nodes_num) {
            const eps = tol.geometry.bilinear_parametric_domain;
            const zero_tol = tol.geometry.quadratic_area;
            const denom_tol = tol.geometry.bilinear_denom;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;
            const residual = getInvBiResidual(
                target_x,
                target_y,
                solve_params,
            );

            const p_coeff =
                (residual.x.xi_eta_term * residual.y.xi_term) -
                (residual.x.xi_term * residual.y.xi_eta_term);
            const s_coeff =
                (residual.x.xi_eta_term * residual.y.eta_term) -
                (residual.x.eta_term * residual.y.xi_eta_term);

            var best_candidate: ?Candidate = null;

            if (@abs(p_coeff) > zero_tol or @abs(s_coeff) > zero_tol) {
                if (@abs(s_coeff) < @abs(p_coeff)) {
                    const q_coeff =
                        (residual.x.xi_eta_term * residual.y.const_term) -
                        (residual.x.const_term * residual.y.xi_eta_term) +
                        (residual.x.eta_term * residual.y.xi_term) -
                        (residual.x.xi_term * residual.y.eta_term);
                    const r_coeff =
                        (residual.x.eta_term * residual.y.const_term) -
                        (residual.x.const_term * residual.y.eta_term);
                    const roots = rootsFromQuadratic(
                        p_coeff,
                        q_coeff,
                        r_coeff,
                        zero_tol,
                    );

                    for (0..roots.count) |ii| {
                        const xi = roots.roots[ii];
                        if (solveOtherCoordFromXi(
                            xi,
                            residual,
                            denom_tol,
                        )) |eta| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                residual,
                                eps,
                            );
                        }
                    }
                } else {
                    const t_coeff =
                        (residual.x.xi_eta_term * residual.y.const_term) -
                        (residual.x.const_term * residual.y.xi_eta_term) -
                        (residual.x.eta_term * residual.y.xi_term) +
                        (residual.x.xi_term * residual.y.eta_term);
                    const u_coeff =
                        (residual.x.xi_term * residual.y.const_term) -
                        (residual.x.const_term * residual.y.xi_term);
                    const roots = rootsFromQuadratic(
                        s_coeff,
                        t_coeff,
                        u_coeff,
                        zero_tol,
                    );

                    for (0..roots.count) |ii| {
                        const eta = roots.roots[ii];
                        if (solveOtherCoordFromEta(
                            eta,
                            residual,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                residual,
                                eps,
                            );
                        }
                    }
                }
            } else if (@abs(residual.x.xi_eta_term) > zero_tol and
                @abs(residual.y.xi_eta_term) > zero_tol)
            {
                if (@abs(p_coeff) < @abs(s_coeff)) {
                    const eta =
                        ((residual.x.xi_eta_term * residual.y.const_term) -
                            (residual.x.const_term * residual.y.xi_eta_term) +
                            (residual.x.eta_term * residual.y.xi_term) -
                            (residual.x.xi_term * residual.y.eta_term)) / (-s_coeff);
                    if (solveOtherCoordFromEta(
                        eta,
                        residual,
                        denom_tol,
                    )) |xi| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            residual,
                            eps,
                        );
                    }
                } else {
                    const xi =
                        ((residual.x.xi_eta_term * residual.y.const_term) -
                            (residual.x.const_term * residual.y.xi_eta_term) -
                            (residual.x.eta_term * residual.y.xi_term) +
                            (residual.x.xi_term * residual.y.eta_term)) / (-p_coeff);
                    if (solveOtherCoordFromXi(
                        xi,
                        residual,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            residual,
                            eps,
                        );
                    }
                }
            } else if (@abs(residual.x.xi_eta_term) > zero_tol and
                @abs(residual.y.xi_eta_term) <= zero_tol)
            {
                if (@abs(residual.y.eta_term) > @abs(residual.y.xi_term)) {
                    if (@abs(residual.y.eta_term) > denom_tol) {
                        const eta =
                            -residual.y.const_term / residual.y.eta_term;
                        if (solveOtherCoordFromEta(
                            eta,
                            residual,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                residual,
                                eps,
                            );
                        }
                    }
                } else if (@abs(residual.y.xi_term) > denom_tol) {
                    const xi = -residual.y.const_term / residual.y.xi_term;
                    if (solveOtherCoordFromXi(
                        xi,
                        residual,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            residual,
                            eps,
                        );
                    }
                }
            } else if (@abs(residual.x.xi_eta_term) <= zero_tol and
                @abs(residual.y.xi_eta_term) > zero_tol)
            {
                if (@abs(residual.x.xi_term) < @abs(residual.x.eta_term)) {
                    if (@abs(residual.x.eta_term) > denom_tol) {
                        const eta =
                            -residual.x.const_term / residual.x.eta_term;
                        if (solveOtherCoordFromEta(
                            eta,
                            residual,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                residual,
                                eps,
                            );
                        }
                    }
                } else if (@abs(residual.x.xi_term) > denom_tol) {
                    const xi = -residual.x.const_term / residual.x.xi_term;
                    if (solveOtherCoordFromXi(
                        xi,
                        residual,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            residual,
                            eps,
                        );
                    }
                }
            } else {
                const denom =
                    (residual.x.xi_term * residual.y.eta_term) -
                    (residual.x.eta_term * residual.y.xi_term);
                if (@abs(denom) > denom_tol) {
                    const xi =
                        ((residual.y.const_term * residual.x.eta_term) -
                            (residual.x.const_term * residual.y.eta_term)) / denom;
                    const eta =
                        ((residual.x.xi_term * residual.y.const_term) -
                            (residual.x.const_term * residual.y.xi_term)) / (-denom);
                    tryCandidate(
                        &best_candidate,
                        xi,
                        eta,
                        residual,
                        eps,
                    );
                }
            }

            if (best_candidate) |candidate| {
                return .{
                    .weights = buildWeights(candidate.xi, candidate.eta),
                    .iters = 1,
                    .xi_out = candidate.xi,
                    .eta_out = candidate.eta,
                };
            }

            return .{ .weights = null, .iters = 0 };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}

pub fn Quad4NewtonKernel() type {
    return struct {
        pub const nodes_num = 4;
        pub const hull_nodes_num = 4;
        pub const tess_triangles_num = 2;
        pub const coord_space = .clip_px_leng;
        pub const solver_kind = .newton;

        pub inline fn initSeed(seed_mode: rastcfg.NewtonSeedMode, hull_seed: ?NewtonSeed) NewtonSeed {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = QUAD_CENTROID_XI, .eta = QUAD_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(
            seed_mode: rastcfg.NewtonSeedMode,
            hull_seed: ?NewtonSeedSIMD,
        ) NewtonSeedSIMD {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(QUAD_CENTROID_XI),
                .v_eta = @splat(QUAD_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: F, eta: F) F {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            x_offset: F,
            y_offset: F,
            xi_seed: F,
            eta_seed: F,
        ) GeometryResult(nodes_num) {
            var xi: F = 0.0;
            var eta: F = 0.0;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]F = undefined;
            var deriv_nu: [nodes_num]F = undefined;
            var deriv_nv: [nodes_num]F = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_seed,
                eta_seed,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );
            if (result.converged) {
                return .{
                    .weights = node_values,
                    .iters = result.iterations,
                    .xi_out = xi,
                    .eta_out = eta,
                };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsNewtonSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: F,
            y_offset: F,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(VecSF, @splat(x_offset));
            const v_target_y = v_pixel_y - @as(VecSF, @splat(y_offset));

            var v_xi_out: VecSF = undefined;
            var v_eta_out: VecSF = undefined;

            var v_weights: [nodes_num]VecSF = undefined;
            var v_dNu: [nodes_num]VecSF = undefined;
            var v_dNv: [nodes_num]VecSF = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .v_weights = v_weights,
                .v_mask = res.v_converged,
                .v_pre_domain_converged = res.v_pre_domain_converged,
                .v_iters = res.v_iterations,
                .v_xi_out = v_xi_out,
                .v_eta_out = v_eta_out,
                .v_residual_x = res.v_residual_x,
                .v_residual_y = res.v_residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
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
        pub const solver_kind = .newton;

        pub inline fn initSeed(seed_mode: rastcfg.NewtonSeedMode, hull_seed: ?NewtonSeed) NewtonSeed {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = QUAD_CENTROID_XI, .eta = QUAD_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(
            seed_mode: rastcfg.NewtonSeedMode,
            hull_seed: ?NewtonSeedSIMD,
        ) NewtonSeedSIMD {
            if (seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(QUAD_CENTROID_XI),
                .v_eta = @splat(QUAD_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: F, eta: F) F {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(F),
            pixel_x: F,
            pixel_y: F,
            x_offset: F,
            y_offset: F,
            xi_seed: F,
            eta_seed: F,
        ) GeometryResult(nodes_num) {
            var xi: F = 0.0;
            var eta: F = 0.0;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            var node_values: [nodes_num]F = undefined;
            var deriv_nu: [nodes_num]F = undefined;
            var deriv_nv: [nodes_num]F = undefined;

            const result = newton.solveInverse(
                nodes_num,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                xi_seed,
                eta_seed,
                &xi,
                &eta,
                &node_values,
                &deriv_nu,
                &deriv_nv,
            );

            if (result.converged) {
                return .{
                    .weights = node_values,
                    .iters = result.iterations,
                    .xi_out = xi,
                    .eta_out = eta,
                };
            }
            return .{ .weights = null, .iters = result.iterations };
        }

        pub inline fn solveWeightsNewtonSIMD(
            nodes: Vec3Slices(F),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: F,
            y_offset: F,
        ) GeometryResultSIMD(nodes_num) {
            const v_target_x = v_pixel_x - @as(VecSF, @splat(x_offset));
            const v_target_y = v_pixel_y - @as(VecSF, @splat(y_offset));

            var v_xi_out: VecSF = undefined;
            var v_eta_out: VecSF = undefined;

            var v_weights: [nodes_num]VecSF = undefined;
            var v_dNu: [nodes_num]VecSF = undefined;
            var v_dNv: [nodes_num]VecSF = undefined;

            const res = newton.solveInverseSIMD(
                nodes_num,
                v_target_x,
                v_target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .v_weights = v_weights,
                .v_mask = res.v_converged,
                .v_pre_domain_converged = res.v_pre_domain_converged,
                .v_iters = res.v_iterations,
                .v_xi_out = v_xi_out,
                .v_eta_out = v_eta_out,
                .v_residual_x = res.v_residual_x,
                .v_residual_y = res.v_residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(F), weights: [nodes_num]F) F {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
