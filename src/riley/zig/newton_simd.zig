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
const shapefun = @import("shapefun.zig");
const common = @import("newton_common.zig");

const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU8 = buildconfig.VecSU8;
const iter_max = cfg.raster_newton_iter_max;
const tol = cfg.tolerance;
const policy = common.newtonPolicy(F, cfg.newton_solver_mode);

inline fn finiteMask(vals: VecSF) VecSB {
    const v_inf: VecSF = @splat(std.math.inf(F));
    return (vals == vals) & (vals != v_inf) & (vals != -v_inf);
}

pub fn solveInverseSIMD(
    comptime N: usize,
    v_target_x: VecSF,
    v_target_y: VecSF,
    elem_node_x: []const F,
    elem_node_y: []const F,
    elem_node_w: []const F,
    v_xi_in: VecSF,
    v_eta_in: VecSF,
    v_xi_out: *VecSF,
    v_eta_out: *VecSF,
    v_node_values: *[N]VecSF,
    v_deriv_n_xi: *[N]VecSF,
    v_deriv_n_eta: *[N]VecSF,
) common.NewtonResultSIMD {
    const v_strict_resid_norm_tol: VecSF =
        @splat(tol.newton.normalized_residual);
    const v_relaxed_resid_norm_tol: VecSF =
        @splat(tol.newton.stagnation_normalized_residual);
    const rel_det_tol_sq = tol.newton.relative_determinant *
        tol.newton.relative_determinant;
    const v_rel_det_tol_sq: VecSF = @splat(rel_det_tol_sq);
    const v_eps: VecSF = @splat(tol.newton.parametric_domain);
    const v_step_abs: VecSF = @splat(tol.newton.parametric_step_abs);
    const v_step_rel: VecSF = @splat(tol.newton.parametric_step_rel);
    const v_max_parametric_step: VecSF =
        @splat(tol.newton.max_parametric_step);
    const v_one: VecSF = @splat(1.0);
    const v_zero: VecSF = @splat(0.0);

    var v_xi = v_xi_in;
    var v_eta = v_eta_in;
    var v_xi_two_back: VecSF = @splat(0.0);
    var v_eta_two_back: VecSF = @splat(0.0);
    var v_has_two_back: VecSB = @splat(false);

    var v_converged: VecSB = @splat(false);
    var v_pre_domain_converged: VecSB = @splat(false);
    var v_iters: VecSU8 = @splat(0);
    var v_status: VecSU8 =
        @splat(@intFromEnum(common.NewtonStatus.failed_iteration_limit));
    var v_active: VecSB = @splat(true);
    var v_residual_x_final: VecSF = @splat(0.0);
    var v_residual_y_final: VecSF = @splat(0.0);
    var v_xi_final = v_xi_in;
    var v_eta_final = v_eta_in;

    var v_term_x: [N]VecSF = undefined;
    var v_term_y: [N]VecSF = undefined;
    inline for (0..N) |nn| {
        const v_node_x: VecSF = @splat(elem_node_x[nn]);
        const v_node_y: VecSF = @splat(elem_node_y[nn]);
        const v_node_w: VecSF = @splat(elem_node_w[nn]);
        v_term_x[nn] = @mulAdd(
            VecSF,
            v_target_x,
            v_node_w,
            -v_node_x,
        );
        v_term_y[nn] = @mulAdd(
            VecSF,
            v_target_y,
            v_node_w,
            -v_node_y,
        );
    }

    for (0..iter_max) |ii| {
        if (!@reduce(.Or, v_active)) break;

        v_iters = @select(
            u8,
            v_active,
            @as(VecSU8, @splat(@intCast(ii + 1))),
            v_iters,
        );

        shapefun.shapeFunctionsSIMD(
            N,
            v_xi,
            v_eta,
            v_node_values,
            v_deriv_n_xi,
            v_deriv_n_eta,
        );

        var v_residual_x: VecSF = @splat(0.0);
        var v_residual_y: VecSF = @splat(0.0);
        var v_interpolated_w: VecSF = @splat(0.0);
        var v_jac11: VecSF = @splat(0.0);
        var v_jac12: VecSF = @splat(0.0);
        var v_jac21: VecSF = @splat(0.0);
        var v_jac22: VecSF = @splat(0.0);

        inline for (0..N) |nn| {
            v_residual_x = @mulAdd(
                VecSF,
                v_node_values[nn],
                v_term_x[nn],
                v_residual_x,
            );
            v_residual_y = @mulAdd(
                VecSF,
                v_node_values[nn],
                v_term_y[nn],
                v_residual_y,
            );
            v_interpolated_w = @mulAdd(
                VecSF,
                v_node_values[nn],
                @as(VecSF, @splat(elem_node_w[nn])),
                v_interpolated_w,
            );
            v_jac11 = @mulAdd(
                VecSF,
                v_deriv_n_xi[nn],
                v_term_x[nn],
                v_jac11,
            );
            v_jac12 = @mulAdd(
                VecSF,
                v_deriv_n_eta[nn],
                v_term_x[nn],
                v_jac12,
            );
            v_jac21 = @mulAdd(
                VecSF,
                v_deriv_n_xi[nn],
                v_term_y[nn],
                v_jac21,
            );
            v_jac22 = @mulAdd(
                VecSF,
                v_deriv_n_eta[nn],
                v_term_y[nn],
                v_jac22,
            );
        }

        v_residual_x_final = v_residual_x;
        v_residual_y_final = v_residual_y;
        v_xi_final = @select(F, v_active, v_xi, v_xi_final);
        v_eta_final = @select(F, v_active, v_eta, v_eta_final);

        if (comptime policy.check_state_finite) {
            const v_invalid_state = v_active & !finiteMask(v_residual_x) |
                v_active & !finiteMask(v_residual_y) |
                v_active & !finiteMask(v_interpolated_w) |
                v_active & !finiteMask(v_jac11) |
                v_active & !finiteMask(v_jac12) |
                v_active & !finiteMask(v_jac21) |
                v_active & !finiteMask(v_jac22);
            v_status = @select(
                u8,
                v_invalid_state,
                @as(
                    VecSU8,
                    @splat(@intFromEnum(common.NewtonStatus.failed_invalid_state)),
                ),
                v_status,
            );
            v_active = v_active & !v_invalid_state;
        }

        const v_w_abs = @abs(v_interpolated_w);
        const v_residual_sq =
            v_residual_x * v_residual_x + v_residual_y * v_residual_y;
        const v_strict_w_scaled_tol = v_w_abs * v_strict_resid_norm_tol;
        const v_relaxed_w_scaled_tol = v_w_abs * v_relaxed_resid_norm_tol;
        const v_strict_residual = v_active &
            (v_w_abs > v_zero) &
            (v_residual_sq <=
                v_strict_w_scaled_tol * v_strict_w_scaled_tol);
        const v_relaxed_residual = if (comptime policy.use_relaxed_residual)
            (v_active &
                (v_w_abs > v_zero) &
                (v_residual_sq <=
                    v_relaxed_w_scaled_tol * v_relaxed_w_scaled_tol))
        else
            @as(VecSB, @splat(false));
        v_converged = v_converged | v_strict_residual;
        v_pre_domain_converged = v_pre_domain_converged | v_strict_residual;
        v_status = @select(
            u8,
            v_strict_residual,
            @as(
                VecSU8,
                @splat(@intFromEnum(common.NewtonStatus.converged_residual)),
            ),
            v_status,
        );
        v_active = v_active & !v_strict_residual;

        if (!@reduce(.Or, v_active)) break;

        const v_is_last_iter = @as(VecSB, @splat(ii + 1 == iter_max));
        const v_hit_iter_limit = v_active & v_is_last_iter;
        v_status = @select(
            u8,
            v_hit_iter_limit,
            @as(
                VecSU8,
                @splat(@intFromEnum(common.NewtonStatus.failed_iteration_limit)),
            ),
            v_status,
        );
        v_active = v_active & !v_hit_iter_limit;
        if (!@reduce(.Or, v_active)) break;

        const v_det = @mulAdd(
            VecSF,
            v_jac11,
            v_jac22,
            -(v_jac12 * v_jac21),
        );
        const v_col_xi_norm_sq = @mulAdd(
            VecSF,
            v_jac11,
            v_jac11,
            v_jac21 * v_jac21,
        );
        const v_col_eta_norm_sq = @mulAdd(
            VecSF,
            v_jac12,
            v_jac12,
            v_jac22 * v_jac22,
        );
        const v_det_sq = v_det * v_det;
        if (comptime policy.check_state_finite) {
            const v_invalid_det_state = v_active &
                (!finiteMask(v_det) |
                    !finiteMask(v_col_xi_norm_sq) |
                    !finiteMask(v_col_eta_norm_sq));
            v_status = @select(
                u8,
                v_invalid_det_state,
                @as(
                    VecSU8,
                    @splat(@intFromEnum(common.NewtonStatus.failed_invalid_state)),
                ),
                v_status,
            );
            v_active = v_active & !v_invalid_det_state;
        }
        const v_near_singular = if (comptime policy.use_relative_determinant)
            (v_active &
                (v_det_sq <=
                    v_rel_det_tol_sq * v_col_xi_norm_sq * v_col_eta_norm_sq))
        else
            (v_active &
                (@abs(v_det) <= @as(VecSF, @splat(tol.newton.relative_determinant))));
        v_status = @select(
            u8,
            v_near_singular,
            @as(
                VecSU8,
                @splat(
                    @intFromEnum(common.NewtonStatus.failed_near_singular),
                ),
            ),
            v_status,
        );
        v_active = v_active & !v_near_singular;

        if (!@reduce(.Or, v_active)) break;

        const v_safe_det = @select(
            F,
            v_active,
            v_det,
            v_one,
        );
        const v_inv_det = v_one / v_safe_det;
        if (comptime policy.check_inverse_determinant_finite) {
            const v_invalid_inv_det = v_active & !finiteMask(v_inv_det);
            v_status = @select(
                u8,
                v_invalid_inv_det,
                @as(
                    VecSU8,
                    @splat(@intFromEnum(common.NewtonStatus.failed_invalid_state)),
                ),
                v_status,
            );
            v_active = v_active & !v_invalid_inv_det;
        }

        if (!@reduce(.Or, v_active)) break;

        const v_delta_xi_num = @mulAdd(
            VecSF,
            v_jac22,
            v_residual_x,
            -(v_jac12 * v_residual_y),
        );
        const v_delta_eta_num = @mulAdd(
            VecSF,
            v_jac11,
            v_residual_y,
            -(v_jac21 * v_residual_x),
        );
        var v_step_xi = v_inv_det * v_delta_xi_num;
        var v_step_eta = v_inv_det * v_delta_eta_num;
        const v_step_tol_xi = v_step_abs +
            v_step_rel * @max(@abs(v_xi), v_one);
        const v_step_tol_eta = v_step_abs +
            v_step_rel * @max(@abs(v_eta), v_one);
        const v_met_step = if (comptime policy.use_step_convergence)
            (v_active &
                (@abs(v_step_xi) <= v_step_tol_xi) &
                (@abs(v_step_eta) <= v_step_tol_eta))
        else
            @as(VecSB, @splat(false));

        if (comptime policy.limit_parametric_step) {
            const v_max_component = @max(@abs(v_step_xi), @abs(v_step_eta));
            const v_safe_max_component = @select(
                F,
                v_max_component > v_zero,
                v_max_component,
                v_one,
            );
            const v_step_scale = @min(
                v_one,
                v_max_parametric_step / v_safe_max_component,
            );
            v_step_xi *= v_step_scale;
            v_step_eta *= v_step_scale;
        }
        const v_next_xi = v_xi - v_step_xi;
        const v_next_eta = v_eta - v_step_eta;
        const v_stagnated = if (comptime policy.detect_stagnation)
            (v_active &
                (v_next_xi == v_xi) &
                (v_next_eta == v_eta))
        else
            @as(VecSB, @splat(false));
        const v_two_cycle = if (comptime policy.detect_two_cycle)
            (v_active &
                v_has_two_back &
                (v_next_xi == v_xi_two_back) &
                (v_next_eta == v_eta_two_back))
        else
            @as(VecSB, @splat(false));
        const v_machine_limit = v_met_step | v_stagnated | v_two_cycle;
        const v_converged_step = if (comptime policy.use_relaxed_residual)
            (v_machine_limit & v_relaxed_residual)
        else
            @as(VecSB, @splat(false));
        const v_status_step = @select(
            u8,
            v_stagnated,
            @as(
                VecSU8,
                @splat(
                    @intFromEnum(common.NewtonStatus.converged_stagnated),
                ),
            ),
            @select(
                u8,
                v_two_cycle,
                @as(
                    VecSU8,
                    @splat(
                        @intFromEnum(common.NewtonStatus.converged_two_cycle),
                    ),
                ),
                @as(
                    VecSU8,
                    @splat(@intFromEnum(common.NewtonStatus.converged_step)),
                ),
            ),
        );
        v_converged = v_converged | v_converged_step;
        v_pre_domain_converged =
            v_pre_domain_converged | v_converged_step;
        v_status = @select(u8, v_converged_step, v_status_step, v_status);
        v_active = v_active & !v_converged_step;

        if (comptime policy.check_step_finite) {
            const v_invalid_step = v_active &
                (!finiteMask(v_step_xi) |
                    !finiteMask(v_step_eta) |
                    !finiteMask(v_next_xi) |
                    !finiteMask(v_next_eta));
            v_status = @select(
                u8,
                v_invalid_step,
                @as(
                    VecSU8,
                    @splat(@intFromEnum(common.NewtonStatus.failed_invalid_step)),
                ),
                v_status,
            );
            v_active = v_active & !v_invalid_step;
        }

        if (!@reduce(.Or, v_active)) break;

        if (comptime policy.detect_two_cycle) {
            v_xi_two_back = @select(F, v_active, v_xi, v_xi_two_back);
            v_eta_two_back = @select(F, v_active, v_eta, v_eta_two_back);
            v_has_two_back = v_has_two_back | v_active;
        }
        v_xi = @select(F, v_active, v_next_xi, v_xi);
        v_eta = @select(F, v_active, v_next_eta, v_eta);
    }

    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_neg_one: VecSF = @splat(-1.0);

    const v_is_in = if (comptime N == 6)
        (v_xi >= -v_eps) & (v_eta >= -v_eps) &
            ((v_xi + v_eta) <= v_splat_one + v_eps)
    else
        (v_xi >= v_splat_neg_one - v_eps) & (v_xi <= v_splat_one + v_eps) &
            (v_eta >= v_splat_neg_one - v_eps) & (v_eta <= v_splat_one + v_eps);

    const v_failed_domain = v_converged & !v_is_in;
    const v_final_converged = v_converged & v_is_in;
    v_status = @select(
        u8,
        v_failed_domain,
        @as(VecSU8, @splat(@intFromEnum(common.NewtonStatus.failed_domain))),
        v_status,
    );
    v_xi_out.* = v_xi_final;
    v_eta_out.* = v_eta_final;

    return .{
        .v_converged = v_final_converged,
        .v_pre_domain_converged = v_pre_domain_converged | v_failed_domain,
        .v_iterations = v_iters,
        .v_status = v_status,
        .v_residual_x = v_residual_x_final,
        .v_residual_y = v_residual_y_final,
        .v_xi_final = v_xi_final,
        .v_eta_final = v_eta_final,
    };
}
