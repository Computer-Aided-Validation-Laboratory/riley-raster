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

const iter_max = cfg.raster_newton_iter_max;
const tol = cfg.tolerance;

pub fn solveInverse(
    comptime N: usize,
    target_screen_x: F,
    target_screen_y: F,
    element_node_x: []const F,
    element_node_y: []const F,
    element_node_w: []const F,
    xi_in: F,
    eta_in: F,
    xi_out: *F,
    eta_out: *F,
    node_values: *[N]F,
    deriv_n_xi: *[N]F,
    deriv_n_eta: *[N]F,
) common.NewtonResult {
    const resid_norm_tol = tol.newton.normalized_residual;
    const det_tol = tol.newton.determinant;
    const eps = tol.newton.parametric_domain;

    var xi = xi_in;
    var eta = eta_in;

    var term_x: [N]F = undefined;
    var term_y: [N]F = undefined;
    inline for (0..N) |nn| {
        term_x[nn] = target_screen_x * element_node_w[nn] - element_node_x[nn];
        term_y[nn] = target_screen_y * element_node_w[nn] - element_node_y[nn];
    }

    var met_residual = false;
    var iters: u8 = 0;
    var residual_x: F = 0.0;
    var residual_y: F = 0.0;

    for (0..iter_max) |ii| {
        iters = @intCast(ii + 1);
        shapefun.shapeFunctions(N, xi, eta, node_values, deriv_n_xi, deriv_n_eta);

        residual_x = 0.0;
        residual_y = 0.0;
        var interpolated_w: F = 0.0;
        var jacobian_11: F = 0.0;
        var jacobian_12: F = 0.0;
        var jacobian_21: F = 0.0;
        var jacobian_22: F = 0.0;

        for (0..N) |nn| {
            residual_x += node_values[nn] * term_x[nn];
            residual_y += node_values[nn] * term_y[nn];
            interpolated_w += node_values[nn] * element_node_w[nn];

            jacobian_11 += deriv_n_xi[nn] * term_x[nn];
            jacobian_12 += deriv_n_eta[nn] * term_x[nn];
            jacobian_21 += deriv_n_xi[nn] * term_y[nn];
            jacobian_22 += deriv_n_eta[nn] * term_y[nn];
        }

        const w_abs = @abs(interpolated_w);
        if (w_abs > 0.0) {
            const residual_sq =
                residual_x * residual_x + residual_y * residual_y;
            const w_scaled_tol = w_abs * resid_norm_tol;

            if (residual_sq <= w_scaled_tol * w_scaled_tol) {
                met_residual = true;
                break;
            }
        }

        const determinant = jacobian_11 * jacobian_22 - jacobian_12 * jacobian_21;
        if (@abs(determinant) < det_tol) {
            return .{
                .converged = false,
                .pre_domain_converged = false,
                .iterations = iters,
                .residual_x = residual_x,
                .residual_y = residual_y,
                .xi_final = xi,
                .eta_final = eta,
            };
        }

        const inverse_determinant = 1.0 / determinant;
        xi -= inverse_determinant *
            (jacobian_22 * residual_x - jacobian_12 * residual_y);
        eta -= inverse_determinant *
            (-jacobian_21 * residual_x + jacobian_11 * residual_y);
    }

    if (!met_residual) {
        return .{
            .converged = false,
            .pre_domain_converged = false,
            .iterations = iters,
            .residual_x = residual_x,
            .residual_y = residual_y,
            .xi_final = xi,
            .eta_final = eta,
        };
    }

    const is_in = if (comptime N == 6)
        (xi >= -eps and eta >= -eps and (xi + eta) <= 1.0 + eps)
    else
        (xi >= -1.0 - eps and xi <= 1.0 + eps and
            eta >= -1.0 - eps and eta <= 1.0 + eps);

    if (is_in) {
        xi_out.* = xi;
        eta_out.* = eta;
        return .{
            .converged = true,
            .pre_domain_converged = true,
            .iterations = iters,
            .residual_x = residual_x,
            .residual_y = residual_y,
            .xi_final = xi,
            .eta_final = eta,
        };
    }

    return .{
        .converged = false,
        .pre_domain_converged = true,
        .iterations = iters,
        .residual_x = residual_x,
        .residual_y = residual_y,
        .xi_final = xi,
        .eta_final = eta,
    };
}
