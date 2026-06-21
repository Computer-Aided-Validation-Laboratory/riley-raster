// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
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
    const v_iter_tol: VecSF = @splat(tol.newton.residual);
    const v_det_tol: VecSF = @splat(tol.newton.determinant);
    const v_eps: VecSF = @splat(tol.newton.parametric_domain);

    var v_xi = v_xi_in;
    var v_eta = v_eta_in;

    var v_converged: VecSB = @splat(false);
    var v_iters: VecSU8 = @splat(0);
    var v_active: VecSB = @splat(true);
    var v_residual_x_final: VecSF = @splat(0.0);
    var v_residual_y_final: VecSF = @splat(0.0);

    var v_term_x: [N]VecSF = undefined;
    var v_term_y: [N]VecSF = undefined;
    inline for (0..N) |nn| {
        const v_node_x: VecSF = @splat(elem_node_x[nn]);
        const v_node_y: VecSF = @splat(elem_node_y[nn]);
        const v_node_w: VecSF = @splat(elem_node_w[nn]);
        v_term_x[nn] = v_target_x * v_node_w - v_node_x;
        v_term_y[nn] = v_target_y * v_node_w - v_node_y;
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
        var v_jac11: VecSF = @splat(0.0);
        var v_jac12: VecSF = @splat(0.0);
        var v_jac21: VecSF = @splat(0.0);
        var v_jac22: VecSF = @splat(0.0);

        inline for (0..N) |nn| {
            v_residual_x += v_node_values[nn] * v_term_x[nn];
            v_residual_y += v_node_values[nn] * v_term_y[nn];
            v_jac11 += v_deriv_n_xi[nn] * v_term_x[nn];
            v_jac12 += v_deriv_n_eta[nn] * v_term_x[nn];
            v_jac21 += v_deriv_n_xi[nn] * v_term_y[nn];
            v_jac22 += v_deriv_n_eta[nn] * v_term_y[nn];
        }

        v_residual_x_final = v_residual_x;
        v_residual_y_final = v_residual_y;

        const v_met_tol = (@abs(v_residual_x) < v_iter_tol) &
            (@abs(v_residual_y) < v_iter_tol);
        v_converged = v_converged | (v_active & v_met_tol);
        v_active = v_active & !v_met_tol;

        if (!@reduce(.Or, v_active)) break;

        const v_det = v_jac11 * v_jac22 - v_jac12 * v_jac21;
        const v_bad_det = @abs(v_det) < v_det_tol;
        v_active = v_active & !v_bad_det;

        if (!@reduce(.Or, v_active)) break;

        const v_safe_det = @select(
            F,
            v_active,
            v_det,
            @as(VecSF, @splat(1.0)),
        );
        const v_inv_det = @as(VecSF, @splat(1.0)) / v_safe_det;

        const v_dxi = v_inv_det *
            (v_jac22 * v_residual_x - v_jac12 * v_residual_y);
        const v_deta = v_inv_det *
            (-v_jac21 * v_residual_x + v_jac11 * v_residual_y);

        v_xi -= @select(F, v_active, v_dxi, @as(VecSF, @splat(0.0)));
        v_eta -= @select(F, v_active, v_deta, @as(VecSF, @splat(0.0)));
    }

    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_neg_one: VecSF = @splat(-1.0);

    const v_is_in = if (comptime N == 6)
        (v_xi >= -v_eps) & (v_eta >= -v_eps) &
            ((v_xi + v_eta) <= v_splat_one + v_eps)
    else
        (v_xi >= v_splat_neg_one - v_eps) & (v_xi <= v_splat_one + v_eps) &
            (v_eta >= v_splat_neg_one - v_eps) & (v_eta <= v_splat_one + v_eps);

    const v_final_converged = v_converged & v_is_in;
    v_xi_out.* = v_xi;
    v_eta_out.* = v_eta;

    return .{
        .v_converged = v_final_converged,
        .v_pre_domain_converged = v_converged,
        .v_iterations = v_iters,
        .v_residual_x = v_residual_x_final,
        .v_residual_y = v_residual_y_final,
    };
}
