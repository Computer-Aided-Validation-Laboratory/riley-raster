const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const tol = buildconfig.config.tolerance;
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;

pub const RasterMode = enum {
    direct,
    incremental,
};

pub const SolverKind = enum {
    hyperb,
    newton,
    inv_bi,
};

pub const NewtonSeedMode = enum {
    centroid,
    hull,
};

pub const NewtonSeedReuse = enum {
    off,
    last_converged,
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
        weights: [N]VecSF,
        mask: VecSB,
        pre_domain_converged: VecSB,
        iters: @Vector(S, u8),
        xi_out: VecSF,
        eta_out: VecSF,
        residual_x: VecSF,
        residual_y: VecSF,
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

pub const NewtonSeed = newton.NewtonSeed;
pub const NewtonSeedSIMD = newton.NewtonSeedSIMD;

pub fn TriWeightStepSIMD(comptime N: usize) type {
    return struct {
        v_dx_step: [N]VecSF,
        v_dy_step: [N]VecSF,
        v_dx_lane_offset: [N]VecSF,
    };
}

pub fn Tri3Kernel() type {
    return struct {
        pub const nodes_num = 3;
        pub const hull_nodes_num = 0;
        pub const tess_triangles_num = 0;
        pub const coord_space = .raster;
        pub const raster_mode = .incremental;
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

        pub inline fn getSIMDInvZ(nodes: Vec3Slices(f64)) [nodes_num]VecSF {
            var out: [nodes_num]VecSF = undefined;
            inline for (0..nodes_num) |ii| {
                out[ii] = @splat(1.0 / nodes.z[ii]);
            }
            return out;
        }

        pub inline fn getSIMDRowWeights(
            nodes: Vec3Slices(f64),
            inv_area: f64,
            start_x_f: f64,
            start_y_f: f64,
            v_steps: TriWeightStepSIMD(nodes_num),
        ) [nodes_num]VecSF {
            const weights_start = getWeightsAt(
                nodes,
                start_x_f,
                start_y_f,
                inv_area,
            );

            var v_weights_row: [nodes_num]VecSF = undefined;
            inline for (0..nodes_num) |ii| {
                v_weights_row[ii] = @splat(weights_start[ii]);
                v_weights_row[ii] += v_steps.v_dx_lane_offset[ii];
            }

            return v_weights_row;
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

            var v_dx_step: [nodes_num]VecSF = undefined;
            var v_dy_step: [nodes_num]VecSF = undefined;
            var v_dx_lane_offset: [nodes_num]VecSF = undefined;

            const v_lane_idx: VecSF = @floatFromInt(std.simd.iota(usize, S));

            inline for (0..nodes_num) |ii| {
                v_dx_step[ii] = @splat(dx_scalar[ii] * 8.0);
                v_dy_step[ii] = @splat(dy_scalar[ii]);
                v_dx_lane_offset[ii] = @splat(dx_scalar[ii]);
                v_dx_lane_offset[ii] *= v_lane_idx;
            }

            return .{
                .v_dx_step = v_dx_step,
                .v_dy_step = v_dy_step,
                .v_dx_lane_offset = v_dx_lane_offset,
            };
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        pub const nodes_num = 6;
        pub const hull_nodes_num = 6;
        pub const tess_triangles_num = 6;
        pub const coord_space = .clip_px_leng;
        pub const raster_mode = .direct;
        pub const solver_kind = .newton;
        pub const seed_mode = .centroid;
        pub const seed_reuse = .last_converged;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = 1.0 / 3.0, .eta = 1.0 / 3.0 };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(1.0 / 3.0),
                .v_eta = @splat(1.0 / 3.0),
            };
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
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_seed: @Vector(S, f64),
            v_eta_seed: @Vector(S, f64),
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
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.v_converged,
                .pre_domain_converged = res.v_pre_domain_converged,
                .iters = res.v_iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.v_residual_x,
                .residual_y = res.v_residual_y,
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
        pub const raster_mode = .direct;
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

        inline fn solveOtherCoordFromXi(
            xi: f64,
            a1: f64,
            a2: f64,
            a3: f64,
            a4: f64,
            b1: f64,
            b2: f64,
            b3: f64,
            b4: f64,
            denom_tol: f64,
        ) ?f64 {
            const denom_x = a3 + (a4 * xi);
            const denom_y = b3 + (b4 * xi);

            if (@abs(denom_x) > @abs(denom_y)) {
                if (@abs(denom_x) <= denom_tol) return null;
                return -((a1 + (a2 * xi)) / denom_x);
            }
            if (@abs(denom_y) <= denom_tol) return null;
            return -((b1 + (b2 * xi)) / denom_y);
        }

        inline fn solveOtherCoordFromEta(
            eta: f64,
            a1: f64,
            a2: f64,
            a3: f64,
            a4: f64,
            b1: f64,
            b2: f64,
            b3: f64,
            b4: f64,
            denom_tol: f64,
        ) ?f64 {
            const denom_x = a2 + (a4 * eta);
            const denom_y = b2 + (b4 * eta);

            if (@abs(denom_x) > @abs(denom_y)) {
                if (@abs(denom_x) <= denom_tol) return null;
                return -((a1 + (a3 * eta)) / denom_x);
            }
            if (@abs(denom_y) <= denom_tol) return null;
            return -((b1 + (b3 * eta)) / denom_y);
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
            a1: f64,
            a2: f64,
            a3: f64,
            a4: f64,
            b1: f64,
            b2: f64,
            b3: f64,
            b4: f64,
            eps: f64,
        ) void {
            if (xi < -eps or xi > 1.0 + eps) return;
            if (eta < -eps or eta > 1.0 + eps) return;

            const resid_x = a1 + (a2 * xi) + (a3 * eta) + (a4 * xi * eta);
            const resid_y = b1 + (b2 * xi) + (b3 * eta) + (b4 * xi * eta);
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

            const a1 = solve_params.x_const - (solve_params.w_const * target_x);
            const a2 = solve_params.x_u_coeff - (solve_params.w_u_coeff * target_x);
            const a3 = solve_params.x_v_coeff - (solve_params.w_v_coeff * target_x);
            const a4 = solve_params.x_uv_coeff - (solve_params.w_uv_coeff * target_x);

            const b1 = solve_params.y_const - (solve_params.w_const * target_y);
            const b2 = solve_params.y_u_coeff - (solve_params.w_u_coeff * target_y);
            const b3 = solve_params.y_v_coeff - (solve_params.w_v_coeff * target_y);
            const b4 = solve_params.y_uv_coeff - (solve_params.w_uv_coeff * target_y);

            const p_coeff = (a4 * b2) - (a2 * b4);
            const s_coeff = (a4 * b3) - (a3 * b4);

            var best_candidate: ?Candidate = null;

            if (@abs(p_coeff) > zero_tol or @abs(s_coeff) > zero_tol) {
                if (@abs(s_coeff) < @abs(p_coeff)) {
                    const q_coeff = (a4 * b1) - (a1 * b4) + (a3 * b2) - (a2 * b3);
                    const r_coeff = (a3 * b1) - (a1 * b3);
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
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            denom_tol,
                        )) |eta| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                a1,
                                a2,
                                a3,
                                a4,
                                b1,
                                b2,
                                b3,
                                b4,
                                eps,
                            );
                        }
                    }
                } else {
                    const t_coeff = (a4 * b1) - (a1 * b4) - (a3 * b2) + (a2 * b3);
                    const u_coeff = (a2 * b1) - (a1 * b2);
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
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                a1,
                                a2,
                                a3,
                                a4,
                                b1,
                                b2,
                                b3,
                                b4,
                                eps,
                            );
                        }
                    }
                }
            } else if (@abs(a4) > zero_tol and @abs(b4) > zero_tol) {
                if (@abs(p_coeff) < @abs(s_coeff)) {
                    const eta = ((a4 * b1) - (a1 * b4) + (a3 * b2) - (a2 * b3)) /
                        (-s_coeff);
                    if (solveOtherCoordFromEta(
                        eta,
                        a1,
                        a2,
                        a3,
                        a4,
                        b1,
                        b2,
                        b3,
                        b4,
                        denom_tol,
                    )) |xi| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            eps,
                        );
                    }
                } else {
                    const xi = ((a4 * b1) - (a1 * b4) - (a3 * b2) + (a2 * b3)) /
                        (-p_coeff);
                    if (solveOtherCoordFromXi(
                        xi,
                        a1,
                        a2,
                        a3,
                        a4,
                        b1,
                        b2,
                        b3,
                        b4,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            eps,
                        );
                    }
                }
            } else if (@abs(a4) > zero_tol and @abs(b4) <= zero_tol) {
                if (@abs(b3) > @abs(b2)) {
                    if (@abs(b3) > denom_tol) {
                        const eta = -b1 / b3;
                        if (solveOtherCoordFromEta(
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                a1,
                                a2,
                                a3,
                                a4,
                                b1,
                                b2,
                                b3,
                                b4,
                                eps,
                            );
                        }
                    }
                } else if (@abs(b2) > denom_tol) {
                    const xi = -b1 / b2;
                    if (solveOtherCoordFromXi(
                        xi,
                        a1,
                        a2,
                        a3,
                        a4,
                        b1,
                        b2,
                        b3,
                        b4,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            eps,
                        );
                    }
                }
            } else if (@abs(a4) <= zero_tol and @abs(b4) > zero_tol) {
                if (@abs(a2) < @abs(a3)) {
                    if (@abs(a3) > denom_tol) {
                        const eta = -a1 / a3;
                        if (solveOtherCoordFromEta(
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            denom_tol,
                        )) |xi| {
                            tryCandidate(
                                &best_candidate,
                                xi,
                                eta,
                                a1,
                                a2,
                                a3,
                                a4,
                                b1,
                                b2,
                                b3,
                                b4,
                                eps,
                            );
                        }
                    }
                } else if (@abs(a2) > denom_tol) {
                    const xi = -a1 / a2;
                    if (solveOtherCoordFromXi(
                        xi,
                        a1,
                        a2,
                        a3,
                        a4,
                        b1,
                        b2,
                        b3,
                        b4,
                        denom_tol,
                    )) |eta| {
                        tryCandidate(
                            &best_candidate,
                            xi,
                            eta,
                            a1,
                            a2,
                            a3,
                            a4,
                            b1,
                            b2,
                            b3,
                            b4,
                            eps,
                        );
                    }
                }
            } else {
                const denom = (a2 * b3) - (a3 * b2);
                if (@abs(denom) > denom_tol) {
                    const xi = ((b1 * a3) - (a1 * b3)) / denom;
                    const eta = ((a2 * b1) - (a1 * b2)) / (-denom);
                    tryCandidate(
                        &best_candidate,
                        xi,
                        eta,
                        a1,
                        a2,
                        a3,
                        a4,
                        b1,
                        b2,
                        b3,
                        b4,
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
        pub const raster_mode = .direct;
        pub const solver_kind = .newton;
        pub const seed_mode = .centroid;
        pub const seed_reuse = .last_converged;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = 0.5, .eta = 0.5 };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(0.5),
                .v_eta = @splat(0.5),
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
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_seed: @Vector(S, f64),
            v_eta_seed: @Vector(S, f64),
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
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.v_converged,
                .pre_domain_converged = res.v_pre_domain_converged,
                .iters = res.v_iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.v_residual_x,
                .residual_y = res.v_residual_y,
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
        pub const raster_mode = .direct;
        pub const solver_kind = .newton;
        pub const seed_mode = .centroid;
        pub const seed_reuse = .last_converged;

        pub inline fn initSeed(hull_seed: ?NewtonSeed) NewtonSeed {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{ .xi = 0.5, .eta = 0.5 };
        }

        pub inline fn initSeedSIMD(hull_seed: ?NewtonSeedSIMD) NewtonSeedSIMD {
            if (comptime @This().seed_mode == .hull) {
                if (hull_seed) |seed| {
                    return seed;
                }
            }
            return .{
                .v_xi = @splat(0.5),
                .v_eta = @splat(0.5),
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
            v_pixel_x: @Vector(S, f64),
            v_pixel_y: @Vector(S, f64),
            v_xi_seed: @Vector(S, f64),
            v_eta_seed: @Vector(S, f64),
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
                v_xi_seed,
                v_eta_seed,
                &v_xi_out,
                &v_eta_out,
                &v_weights,
                &v_dNu,
                &v_dNv,
            );

            return .{
                .weights = v_weights,
                .mask = res.v_converged,
                .pre_domain_converged = res.v_pre_domain_converged,
                .iters = res.v_iterations,
                .xi_out = v_xi_out,
                .eta_out = v_eta_out,
                .residual_x = res.v_residual_x,
                .residual_y = res.v_residual_y,
            };
        }

        pub inline fn calcInvZ(nodes: Vec3Slices(f64), weights: [nodes_num]f64) f64 {
            return calcInvZClip(nodes_num, nodes, weights);
        }
    };
}
