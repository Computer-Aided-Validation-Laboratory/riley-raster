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

pub const NEWTON_SEED_MODE: NewtonSeedMode = .centroid;
pub const NEWTON_SEED_REUSE: NewtonSeedReuse = .off;
pub const TRI_CENTROID_XI: f64 = 1.0 / 3.0;
pub const TRI_CENTROID_ETA: f64 = 1.0 / 3.0;
pub const QUAD_CENTROID_XI: f64 = 0.0;
pub const QUAD_CENTROID_ETA: f64 = 0.0;

pub const NewtonSeedMode = enum {
    centroid,
    hull,
};

pub const NewtonSeedReuse = enum {
    off,
    last_converged,
};

pub const MeshType = enum {
    tri3,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,

    pub inline fn getNodesNum(self: MeshType) usize {
        return switch (self) {
            .tri3 => 3,
            .tri6 => 6,
            .quad4ibi, .quad4newton => 4,
            .quad8 => 8,
            .quad9 => 9,
        };
    }

    pub inline fn getNumHullPoints(self: MeshType) usize {
        return switch (self) {
            .tri3 => 0,
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
        weights: ?[N]f64,
        iters: u8,
        xi_out: f64 = 0.0,
        eta_out: f64 = 0.0,
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
    nodes: Vec3Slices(f64),
    weights: [N]f64,
) f64 {
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

pub fn Tri3Kernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const solver_kind = .hyperb;

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

        pub inline fn solveWeightsHyperb(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            inv_area: f64,
        ) GeometryResult(nodes_num) {
            const weights = getWeightsAt(nodes, pixel_x, pixel_y, inv_area);

            if (isInElement(weights)) {
                return .{ .weights = weights, .iters = 1 };
            }

            return .{ .weights = null, .iters = 1 };
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
            var inv_z: f64 = 0.0;

            inline for (0..nodes_num) |nn| {
                inv_z += weights[nn] * (1.0 / nodes.z[nn]);
            }

            return inv_z;
        }

        pub inline fn solveWeightsHyperbSIMD(
            nodes: Vec3Slices(f64),
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
            nodes: Vec3Slices(f64),
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

        pub inline fn getSIMDInvZ(nodes: Vec3Slices(f64)) [nodes_num]VecSF {
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
        pub const seed_mode = NEWTON_SEED_MODE;
        pub const seed_reuse = NEWTON_SEED_REUSE;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = TRI_CENTROID_XI, .eta = TRI_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(TRI_CENTROID_XI),
                .v_eta = @splat(TRI_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(-xi, 0.0) + @max(-eta, 0.0) + @max(xi + eta - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            xi_seed: f64,
            eta_seed: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

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
            nodes: Vec3Slices(f64),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: f64,
            y_offset: f64,
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

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
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

        const InvBiPoly = struct {
            const_term: f64,
            xi_term: f64,
            eta_term: f64,
            xi_eta_term: f64,
        };

        const InvBiResidual = struct {
            x: InvBiPoly,
            y: InvBiPoly,
        };

        const Candidate = struct {
            xi: f64,
            eta: f64,
            resid_sq: f64,
        };

        inline fn buildWeights(xi: f64, eta: f64) [nodes_num]f64 {
            const v_xi_terms = @Vector(2, f64){ 1.0 - xi, xi };
            const v_eta_terms = @Vector(2, f64){ 1.0 - eta, eta };
            return .{
                v_xi_terms[0] * v_eta_terms[0],
                v_xi_terms[1] * v_eta_terms[0],
                v_xi_terms[1] * v_eta_terms[1],
                v_xi_terms[0] * v_eta_terms[1],
            };
        }

        inline fn getInvBiResidual(
            target_x: f64,
            target_y: f64,
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
            xi: f64,
            residual: InvBiResidual,
            denom_tol: f64,
        ) ?f64 {
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
            eta: f64,
            residual: InvBiResidual,
            denom_tol: f64,
        ) ?f64 {
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
            a_coeff: f64,
            b_coeff: f64,
            c_coeff: f64,
            zero_tol: f64,
        ) struct { count: u8, roots: [2]f64 } {
            var roots = [2]f64{ 0.0, 0.0 };

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
            xi: f64,
            eta: f64,
            residual: InvBiResidual,
            eps: f64,
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
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
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

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
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
        pub const seed_mode = NEWTON_SEED_MODE;
        pub const seed_reuse = NEWTON_SEED_REUSE;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = QUAD_CENTROID_XI, .eta = QUAD_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(QUAD_CENTROID_XI),
                .v_eta = @splat(QUAD_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            xi_seed: f64,
            eta_seed: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

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
            nodes: Vec3Slices(f64),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: f64,
            y_offset: f64,
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
        pub const solver_kind = .newton;
        pub const seed_mode = NEWTON_SEED_MODE;
        pub const seed_reuse = NEWTON_SEED_REUSE;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = QUAD_CENTROID_XI, .eta = QUAD_CENTROID_ETA };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(QUAD_CENTROID_XI),
                .v_eta = @splat(QUAD_CENTROID_ETA),
            };
        }

        pub inline fn domainViolation(xi: f64, eta: f64) f64 {
            return @max(@abs(xi) - 1.0, 0.0) + @max(@abs(eta) - 1.0, 0.0);
        }

        pub inline fn solveWeightsNewton(
            nodes: Vec3Slices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            xi_seed: f64,
            eta_seed: f64,
        ) GeometryResult(nodes_num) {
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;

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
            nodes: Vec3Slices(f64),
            v_pixel_x: VecSF,
            v_pixel_y: VecSF,
            v_xi_seed: VecSF,
            v_eta_seed: VecSF,
            x_offset: f64,
            y_offset: f64,
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

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
