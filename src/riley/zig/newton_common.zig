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
const rastcfg = @import("rasterconfig.zig");

const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU8 = buildconfig.VecSU8;
const tol = cfg.tolerance;

pub const NewtonSeed = struct {
    xi: F,
    eta: F,
};

pub const NewtonSeedSIMD = struct {
    v_xi: VecSF,
    v_eta: VecSF,
};

pub const NewtonSeedState = struct {
    is_valid: bool = false,
    xi: F = 0.0,
    eta: F = 0.0,
};

pub const NewtonSeedQuality = struct {
    is_usable: bool,
    domain_violation: F,
    residual_sq: F,
    det_abs: F,
};

pub const NewtonResult = struct {
    converged: bool,
    pre_domain_converged: bool,
    iterations: u8,
    residual_x: F,
    residual_y: F,
};

pub const NewtonResultSIMD = struct {
    v_converged: VecSB,
    v_pre_domain_converged: VecSB,
    v_iterations: VecSU8,
    v_residual_x: VecSF,
    v_residual_y: VecSF,
};

pub inline fn selectSeed(
    seed_reuse: rastcfg.NewtonSeedReuse,
    base_seed: NewtonSeed,
    seed_state: NewtonSeedState,
) NewtonSeed {
    if (seed_reuse == .last_converged and seed_state.is_valid) {
        return .{
            .xi = seed_state.xi,
            .eta = seed_state.eta,
        };
    }
    return base_seed;
}

pub inline fn isSeedFinite(seed: NewtonSeed) bool {
    return std.math.isFinite(seed.xi) and std.math.isFinite(seed.eta);
}

pub inline fn updateSeedState(
    seed_state: *NewtonSeedState,
    xi: F,
    eta: F,
) void {
    seed_state.* = .{
        .is_valid = true,
        .xi = xi,
        .eta = eta,
    };
}

pub inline fn applySeedReuseInPlace(
    lane_count: usize,
    seed_state: NewtonSeedState,
    seed_xi: []F,
    seed_eta: []F,
) void {
    if (seed_state.is_valid) {
        for (0..lane_count) |jj| {
            seed_xi[jj] = seed_state.xi;
            seed_eta[jj] = seed_state.eta;
        }
    }
}

pub inline fn updateSeedStateFromSIMDResult(
    seed_state: *NewtonSeedState,
    v_chunk_mask: VecSB,
    v_converged_mask: VecSB,
    v_xi_out: VecSF,
    v_eta_out: VecSF,
    v_residual_x: VecSF,
    v_residual_y: VecSF,
) void {
    const v_mask_valid = v_chunk_mask & v_converged_mask;
    if (!@reduce(.Or, v_mask_valid)) return;

    const lane_mask_valid: [S]bool = v_mask_valid;
    const lane_xi_out: [S]F = v_xi_out;
    const lane_eta_out: [S]F = v_eta_out;
    const lane_residual_x: [S]F = v_residual_x;
    const lane_residual_y: [S]F = v_residual_y;

    var best_lane_idx: ?usize = null;
    var best_resid_sq = std.math.inf(F);

    for (0..S) |jj| {
        if (lane_mask_valid[jj]) {
            const resid_sq =
                lane_residual_x[jj] * lane_residual_x[jj] +
                lane_residual_y[jj] * lane_residual_y[jj];
            if (best_lane_idx == null or resid_sq < best_resid_sq) {
                best_lane_idx = jj;
                best_resid_sq = resid_sq;
            }
        }
    }

    if (best_lane_idx) |jj| {
        updateSeedState(seed_state, lane_xi_out[jj], lane_eta_out[jj]);
    }
}

pub fn evaluateSeedQuality(
    comptime N: usize,
    comptime domainViolationFn: anytype,
    target_screen_x: F,
    target_screen_y: F,
    element_node_x: []const F,
    element_node_y: []const F,
    element_node_w: []const F,
    seed: NewtonSeed,
) NewtonSeedQuality {
    if (!isSeedFinite(seed)) {
        return .{
            .is_usable = false,
            .domain_violation = std.math.inf(F),
            .residual_sq = std.math.inf(F),
            .det_abs = 0.0,
        };
    }

    var node_values: [N]F = undefined;
    var deriv_n_xi: [N]F = undefined;
    var deriv_n_eta: [N]F = undefined;
    shapefun.shapeFunctions(
        N,
        seed.xi,
        seed.eta,
        &node_values,
        &deriv_n_xi,
        &deriv_n_eta,
    );

    var residual_x: F = 0.0;
    var residual_y: F = 0.0;
    var jacobian_11: F = 0.0;
    var jacobian_12: F = 0.0;
    var jacobian_21: F = 0.0;
    var jacobian_22: F = 0.0;

    for (0..N) |nn| {
        const term_x = target_screen_x * element_node_w[nn] - element_node_x[nn];
        const term_y = target_screen_y * element_node_w[nn] - element_node_y[nn];

        residual_x += node_values[nn] * term_x;
        residual_y += node_values[nn] * term_y;

        jacobian_11 += deriv_n_xi[nn] * term_x;
        jacobian_12 += deriv_n_eta[nn] * term_x;
        jacobian_21 += deriv_n_xi[nn] * term_y;
        jacobian_22 += deriv_n_eta[nn] * term_y;
    }

    const determinant = jacobian_11 * jacobian_22 - jacobian_12 * jacobian_21;
    const det_abs = @abs(determinant);
    const residual_sq = residual_x * residual_x + residual_y * residual_y;
    const domain_violation = domainViolationFn(seed.xi, seed.eta);
    const seed_tol = tol.newton_seed;

    const is_usable = domain_violation <= seed_tol.parametric_domain and
        det_abs >= seed_tol.determinant and
        residual_sq <= seed_tol.residual_sq and
        std.math.isFinite(residual_sq);

    return .{
        .is_usable = is_usable,
        .domain_violation = domain_violation,
        .residual_sq = residual_sq,
        .det_abs = det_abs,
    };
}

pub fn calcJacobianDet2D(
    comptime N: usize,
    xi: F,
    eta: F,
    node_x: []const F,
    node_y: []const F,
) F {
    var node_values: [N]F = undefined;
    var deriv_n_xi: [N]F = undefined;
    var deriv_n_eta: [N]F = undefined;
    shapefun.shapeFunctions(
        N,
        xi,
        eta,
        &node_values,
        &deriv_n_xi,
        &deriv_n_eta,
    );

    var dx_dxi: F = 0.0;
    var dx_deta: F = 0.0;
    var dy_dxi: F = 0.0;
    var dy_deta: F = 0.0;

    for (0..N) |nn| {
        dx_dxi += deriv_n_xi[nn] * node_x[nn];
        dx_deta += deriv_n_eta[nn] * node_x[nn];
        dy_dxi += deriv_n_xi[nn] * node_y[nn];
        dy_deta += deriv_n_eta[nn] * node_y[nn];
    }

    return dx_dxi * dy_deta - dx_deta * dy_dxi;
}
