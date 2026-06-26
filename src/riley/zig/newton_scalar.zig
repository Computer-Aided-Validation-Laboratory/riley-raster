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
    const strict_resid_norm_tol = tol.newton.normalized_residual;
    const relaxed_resid_norm_tol = tol.newton.stagnation_normalized_residual;
    const rel_det_tol_sq =
        tol.newton.relative_determinant * tol.newton.relative_determinant;
    const eps = tol.newton.parametric_domain;
    const step_abs = tol.newton.parametric_step_abs;
    const step_rel = tol.newton.parametric_step_rel;
    const max_parametric_step = tol.newton.max_parametric_step;

    var xi = xi_in;
    var eta = eta_in;
    var xi_two_back: F = 0.0;
    var eta_two_back: F = 0.0;
    var has_two_back = false;

    var term_x: [N]F = undefined;
    var term_y: [N]F = undefined;
    inline for (0..N) |nn| {
        term_x[nn] = @mulAdd(
            F,
            target_screen_x,
            element_node_w[nn],
            -element_node_x[nn],
        );
        term_y[nn] = @mulAdd(
            F,
            target_screen_y,
            element_node_w[nn],
            -element_node_y[nn],
        );
    }

    var iters: u8 = 0;
    var residual_x: F = 0.0;
    var residual_y: F = 0.0;
    var status: common.NewtonStatus = .failed_iteration_limit;
    var pre_domain_converged = false;

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
            residual_x = @mulAdd(
                F,
                node_values[nn],
                term_x[nn],
                residual_x,
            );
            residual_y = @mulAdd(
                F,
                node_values[nn],
                term_y[nn],
                residual_y,
            );
            interpolated_w = @mulAdd(
                F,
                node_values[nn],
                element_node_w[nn],
                interpolated_w,
            );

            jacobian_11 = @mulAdd(
                F,
                deriv_n_xi[nn],
                term_x[nn],
                jacobian_11,
            );
            jacobian_12 = @mulAdd(
                F,
                deriv_n_eta[nn],
                term_x[nn],
                jacobian_12,
            );
            jacobian_21 = @mulAdd(
                F,
                deriv_n_xi[nn],
                term_y[nn],
                jacobian_21,
            );
            jacobian_22 = @mulAdd(
                F,
                deriv_n_eta[nn],
                term_y[nn],
                jacobian_22,
            );
        }

        const invalid_residual_state =
            !std.math.isFinite(residual_x) or
            !std.math.isFinite(residual_y) or
            !std.math.isFinite(interpolated_w) or
            !std.math.isFinite(jacobian_11) or
            !std.math.isFinite(jacobian_12) or
            !std.math.isFinite(jacobian_21) or
            !std.math.isFinite(jacobian_22);
        if (invalid_residual_state) {
            status = .failed_invalid_state;
            break;
        }

        const w_abs = @abs(interpolated_w);
        const residual_sq =
            residual_x * residual_x + residual_y * residual_y;
        const strict_w_scaled_tol = w_abs * strict_resid_norm_tol;
        const relaxed_w_scaled_tol = w_abs * relaxed_resid_norm_tol;
        const strict_residual = w_abs > 0.0 and
            residual_sq <= strict_w_scaled_tol * strict_w_scaled_tol;
        const relaxed_residual = w_abs > 0.0 and
            residual_sq <= relaxed_w_scaled_tol * relaxed_w_scaled_tol;
        if (strict_residual) {
            status = .converged_residual;
            pre_domain_converged = true;
            break;
        }

        if (ii + 1 == iter_max) {
            status = .failed_iteration_limit;
            break;
        }

        const determinant = @mulAdd(
            F,
            jacobian_11,
            jacobian_22,
            -(jacobian_12 * jacobian_21),
        );
        const col_xi_norm_sq = @mulAdd(
            F,
            jacobian_11,
            jacobian_11,
            jacobian_21 * jacobian_21,
        );
        const col_eta_norm_sq = @mulAdd(
            F,
            jacobian_12,
            jacobian_12,
            jacobian_22 * jacobian_22,
        );
        const determinant_sq = determinant * determinant;
        const near_singular = determinant_sq <=
            rel_det_tol_sq * col_xi_norm_sq * col_eta_norm_sq;
        const invalid_det_state =
            !std.math.isFinite(determinant) or
            !std.math.isFinite(col_xi_norm_sq) or
            !std.math.isFinite(col_eta_norm_sq);
        if (invalid_det_state) {
            status = .failed_invalid_state;
            break;
        }
        if (near_singular) {
            status = .failed_near_singular;
            break;
        }

        const inverse_determinant = 1.0 / determinant;
        if (!std.math.isFinite(inverse_determinant)) {
            status = .failed_invalid_state;
            break;
        }

        const delta_xi_num = @mulAdd(
            F,
            jacobian_22,
            residual_x,
            -(jacobian_12 * residual_y),
        );
        const delta_eta_num = @mulAdd(
            F,
            jacobian_11,
            residual_y,
            -(jacobian_21 * residual_x),
        );
        const step_xi = inverse_determinant * delta_xi_num;
        const step_eta = inverse_determinant * delta_eta_num;
        const step_tol_xi =
            step_abs + step_rel * @max(@abs(xi), @as(F, 1.0));
        const step_tol_eta =
            step_abs + step_rel * @max(@abs(eta), @as(F, 1.0));
        const met_step = @abs(step_xi) <= step_tol_xi and
            @abs(step_eta) <= step_tol_eta;

        var limited_step_xi = step_xi;
        var limited_step_eta = step_eta;
        const max_component = @max(@abs(step_xi), @abs(step_eta));
        if (max_component > max_parametric_step) {
            const step_scale = max_parametric_step / max_component;
            limited_step_xi *= step_scale;
            limited_step_eta *= step_scale;
        }

        const next_xi = xi - limited_step_xi;
        const next_eta = eta - limited_step_eta;
        const stagnated = next_xi == xi and next_eta == eta;
        const two_cycle = has_two_back and
            next_xi == xi_two_back and
            next_eta == eta_two_back;
        const machine_limit =
            met_step or stagnated or two_cycle;
        if (machine_limit and relaxed_residual) {
            status = if (stagnated)
                .converged_stagnated
            else if (two_cycle)
                .converged_two_cycle
            else
                .converged_step;
            pre_domain_converged = true;
            break;
        }

        const invalid_step =
            !std.math.isFinite(step_xi) or
            !std.math.isFinite(step_eta) or
            !std.math.isFinite(next_xi) or
            !std.math.isFinite(next_eta);
        if (invalid_step) {
            status = .failed_invalid_step;
            break;
        }

        xi_two_back = xi;
        eta_two_back = eta;
        has_two_back = true;
        xi = next_xi;
        eta = next_eta;
    }

    if (common.isPreDomainConvergedStatus(status)) {
        pre_domain_converged = true;
    }
    if (common.isConvergedStatus(status)) {
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
                .pre_domain_converged = pre_domain_converged,
                .iterations = iters,
                .status = status,
                .residual_x = residual_x,
                .residual_y = residual_y,
                .xi_final = xi,
                .eta_final = eta,
            };
        }
        status = .failed_domain;
        pre_domain_converged = true;
    }

    return .{
        .converged = false,
        .pre_domain_converged = pre_domain_converged,
        .iterations = iters,
        .status = status,
        .residual_x = residual_x,
        .residual_y = residual_y,
        .xi_final = xi,
        .eta_final = eta,
    };
}

pub fn traceSolveInverse(
    comptime N: usize,
    writer: anytype,
    pixel_x: usize,
    pixel_y: usize,
    target_screen_x: F,
    target_screen_y: F,
    element_node_x: []const F,
    element_node_y: []const F,
    element_node_w: []const F,
    xi_in: F,
    eta_in: F,
) !void {
    const strict_resid_norm_tol = tol.newton.normalized_residual;
    const relaxed_resid_norm_tol = tol.newton.stagnation_normalized_residual;
    const rel_det_tol_sq =
        tol.newton.relative_determinant * tol.newton.relative_determinant;
    const step_abs = tol.newton.parametric_step_abs;
    const step_rel = tol.newton.parametric_step_rel;
    const max_parametric_step = tol.newton.max_parametric_step;

    var xi = xi_in;
    var eta = eta_in;
    var xi_two_back: F = 0.0;
    var eta_two_back: F = 0.0;
    var has_two_back = false;

    var node_values: [N]F = undefined;
    var deriv_n_xi: [N]F = undefined;
    var deriv_n_eta: [N]F = undefined;
    var term_x: [N]F = undefined;
    var term_y: [N]F = undefined;
    inline for (0..N) |nn| {
        term_x[nn] = @mulAdd(
            F,
            target_screen_x,
            element_node_w[nn],
            -element_node_x[nn],
        );
        term_y[nn] = @mulAdd(
            F,
            target_screen_y,
            element_node_w[nn],
            -element_node_y[nn],
        );
    }

    try writer.print(
        "Trace for pixel ({d}, {d}) seed=({d}, {d})\n",
        .{ pixel_x, pixel_y, xi_in, eta_in },
    );

    for (0..iter_max) |ii| {
        shapefun.shapeFunctions(N, xi, eta, &node_values, &deriv_n_xi, &deriv_n_eta);

        var residual_x: F = 0.0;
        var residual_y: F = 0.0;
        var interpolated_w: F = 0.0;
        var jacobian_11: F = 0.0;
        var jacobian_12: F = 0.0;
        var jacobian_21: F = 0.0;
        var jacobian_22: F = 0.0;

        for (0..N) |nn| {
            residual_x = @mulAdd(F, node_values[nn], term_x[nn], residual_x);
            residual_y = @mulAdd(F, node_values[nn], term_y[nn], residual_y);
            interpolated_w = @mulAdd(
                F,
                node_values[nn],
                element_node_w[nn],
                interpolated_w,
            );
            jacobian_11 = @mulAdd(F, deriv_n_xi[nn], term_x[nn], jacobian_11);
            jacobian_12 = @mulAdd(F, deriv_n_eta[nn], term_x[nn], jacobian_12);
            jacobian_21 = @mulAdd(F, deriv_n_xi[nn], term_y[nn], jacobian_21);
            jacobian_22 = @mulAdd(F, deriv_n_eta[nn], term_y[nn], jacobian_22);
        }

        const residual_sq =
            residual_x * residual_x + residual_y * residual_y;
        const w_abs = @abs(interpolated_w);
        const strict_w_scaled_tol = w_abs * strict_resid_norm_tol;
        const relaxed_w_scaled_tol = w_abs * relaxed_resid_norm_tol;
        const strict_residual = w_abs > 0.0 and
            residual_sq <= strict_w_scaled_tol * strict_w_scaled_tol;
        const relaxed_residual = w_abs > 0.0 and
            residual_sq <= relaxed_w_scaled_tol * relaxed_w_scaled_tol;

        const determinant = @mulAdd(
            F,
            jacobian_11,
            jacobian_22,
            -(jacobian_12 * jacobian_21),
        );
        const col_xi_norm_sq = @mulAdd(
            F,
            jacobian_11,
            jacobian_11,
            jacobian_21 * jacobian_21,
        );
        const col_eta_norm_sq = @mulAdd(
            F,
            jacobian_12,
            jacobian_12,
            jacobian_22 * jacobian_22,
        );
        const determinant_sq = determinant * determinant;
        const near_singular = determinant_sq <=
            rel_det_tol_sq * col_xi_norm_sq * col_eta_norm_sq;

        try writer.print(
            "iter={d} xi={d} eta={d} rx={d} ry={d} w={d} nres={d} det={d} strict={any} relaxed={any} near_singular={any}\n",
            .{
                ii + 1,
                xi,
                eta,
                residual_x,
                residual_y,
                interpolated_w,
                if (w_abs > 0.0) @sqrt(residual_sq) / w_abs else std.math.nan(F),
                determinant,
                strict_residual,
                relaxed_residual,
                near_singular,
            },
        );

        if (strict_residual) {
            try writer.writeAll("  -> converged_residual\n\n");
            return;
        }
        if (ii + 1 == iter_max) {
            try writer.writeAll("  -> failed_iteration_limit\n\n");
            return;
        }
        if (near_singular) {
            try writer.writeAll("  -> failed_near_singular\n\n");
            return;
        }

        const inverse_determinant = 1.0 / determinant;
        const delta_xi_num = @mulAdd(
            F,
            jacobian_22,
            residual_x,
            -(jacobian_12 * residual_y),
        );
        const delta_eta_num = @mulAdd(
            F,
            jacobian_11,
            residual_y,
            -(jacobian_21 * residual_x),
        );
        const step_xi = inverse_determinant * delta_xi_num;
        const step_eta = inverse_determinant * delta_eta_num;
        const step_tol_xi =
            step_abs + step_rel * @max(@abs(xi), @as(F, 1.0));
        const step_tol_eta =
            step_abs + step_rel * @max(@abs(eta), @as(F, 1.0));
        const met_step = @abs(step_xi) <= step_tol_xi and
            @abs(step_eta) <= step_tol_eta;

        var limited_step_xi = step_xi;
        var limited_step_eta = step_eta;
        const max_component = @max(@abs(step_xi), @abs(step_eta));
        if (max_component > max_parametric_step) {
            const step_scale = max_parametric_step / max_component;
            limited_step_xi *= step_scale;
            limited_step_eta *= step_scale;
        }

        const next_xi = xi - limited_step_xi;
        const next_eta = eta - limited_step_eta;
        const stagnated = next_xi == xi and next_eta == eta;
        const two_cycle = has_two_back and
            next_xi == xi_two_back and
            next_eta == eta_two_back;

        try writer.print(
            "  step_xi={d} step_eta={d} limited_step_xi={d} limited_step_eta={d} met_step={any} stagnated={any} two_cycle={any} next_xi={d} next_eta={d}\n",
            .{
                step_xi,
                step_eta,
                limited_step_xi,
                limited_step_eta,
                met_step,
                stagnated,
                two_cycle,
                next_xi,
                next_eta,
            },
        );

        if ((met_step or stagnated or two_cycle) and relaxed_residual) {
            const label = if (stagnated)
                "converged_stagnated"
            else if (two_cycle)
                "converged_two_cycle"
            else
                "converged_step";
            try writer.print("  -> {s}\n\n", .{label});
            return;
        }

        xi_two_back = xi;
        eta_two_back = eta;
        has_two_back = true;
        xi = next_xi;
        eta = next_eta;
    }
}
