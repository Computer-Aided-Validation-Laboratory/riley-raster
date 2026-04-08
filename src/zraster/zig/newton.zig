const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const shapefun = @import("shapefun.zig");

const S = buildconfig.config.simd_vector_width;
const tol = buildconfig.config.tolerance;

pub const NewtonSeed = struct {
    xi: f64,
    eta: f64,
};

pub const NewtonSeedSIMD = struct {
    xi: @Vector(S, f64),
    eta: @Vector(S, f64),
};

pub const NewtonSeedState = struct {
    is_valid: bool = false,
    xi: f64 = 0.0,
    eta: f64 = 0.0,
};

pub const NewtonSeedQuality = struct {
    is_usable: bool,
    domain_violation: f64,
    residual_sq: f64,
    det_abs: f64,
};

pub const NewtonResult = struct {
    converged: bool,
    pre_domain_converged: bool,
    iterations: u8,
    residual_x: f64,
    residual_y: f64,
};

pub const NewtonResultSIMD = struct {
    converged: @Vector(S, bool),
    pre_domain_converged: @Vector(S, bool),
    iterations: @Vector(S, u8),
    residual_x: @Vector(S, f64),
    residual_y: @Vector(S, f64),
};

pub inline fn clearSeedState(seed_state: *NewtonSeedState) void {
    seed_state.* = .{};
}

pub inline fn selectSeed(
    comptime seed_reuse: anytype,
    base_seed: NewtonSeed,
    seed_state: NewtonSeedState,
) NewtonSeed {
    if (comptime seed_reuse == .last_converged) {
        if (seed_state.is_valid) {
            return .{
                .xi = seed_state.xi,
                .eta = seed_state.eta,
            };
        }
    }
    return base_seed;
}

pub inline fn isSeedFinite(seed: NewtonSeed) bool {
    return std.math.isFinite(seed.xi) and std.math.isFinite(seed.eta);
}

pub inline fn isSeedInRelaxedDomain(
    comptime domainViolationFn: anytype,
    seed: NewtonSeed,
) bool {
    const domain_tol = tol.newton.parametric_domain;
    return domainViolationFn(seed.xi, seed.eta) <= domain_tol;
}

pub inline fn updateSeedState(
    seed_state: *NewtonSeedState,
    xi: f64,
    eta: f64,
) void {
    seed_state.* = .{
        .is_valid = true,
        .xi = xi,
        .eta = eta,
    };
}

pub inline fn fillSeedBlock(
    comptime seed_reuse: anytype,
    lane_count: usize,
    base_seed_xi: []const f64,
    base_seed_eta: []const f64,
    seed_state: NewtonSeedState,
    seed_xi_out: []f64,
    seed_eta_out: []f64,
) void {
    if (comptime seed_reuse == .last_converged) {
        if (seed_state.is_valid) {
            for (0..lane_count) |jj| {
                seed_xi_out[jj] = seed_state.xi;
                seed_eta_out[jj] = seed_state.eta;
            }
            return;
        }
    }

    for (0..lane_count) |jj| {
        seed_xi_out[jj] = base_seed_xi[jj];
        seed_eta_out[jj] = base_seed_eta[jj];
    }
}

pub inline fn updateSeedStateFromSIMDResult(
    seed_state: *NewtonSeedState,
    chunk_mask: @Vector(S, bool),
    converged_mask: @Vector(S, bool),
    xi_out: @Vector(S, f64),
    eta_out: @Vector(S, f64),
    residual_x: @Vector(S, f64),
    residual_y: @Vector(S, f64),
) void {
    const v_mask = chunk_mask & converged_mask;
    if (!@reduce(.Or, v_mask)) {
        return;
    }

    const mask_arr: [S]bool = v_mask;
    const xi_out_arr: [S]f64 = xi_out;
    const eta_out_arr: [S]f64 = eta_out;
    const residual_x_arr: [S]f64 = residual_x;
    const residual_y_arr: [S]f64 = residual_y;

    var best_lane_idx: ?usize = null;
    var best_resid_sq = std.math.inf(f64);

    for (0..S) |jj| {
        if (mask_arr[jj]) {
            const resid_sq = residual_x_arr[jj] * residual_x_arr[jj] +
                residual_y_arr[jj] * residual_y_arr[jj];
            if (best_lane_idx == null or resid_sq < best_resid_sq) {
                best_lane_idx = jj;
                best_resid_sq = resid_sq;
            }
        }
    }

    if (best_lane_idx) |jj| {
        updateSeedState(seed_state, xi_out_arr[jj], eta_out_arr[jj]);
    }
}

pub fn evaluateSeedQuality(
    comptime N: usize,
    comptime domainViolationFn: anytype,
    target_screen_x: f64,
    target_screen_y: f64,
    element_node_x: []const f64,
    element_node_y: []const f64,
    element_node_w: []const f64,
    seed: NewtonSeed,
) NewtonSeedQuality {
    if (!isSeedFinite(seed)) {
        return .{
            .is_usable = false,
            .domain_violation = std.math.inf(f64),
            .residual_sq = std.math.inf(f64),
            .det_abs = 0.0,
        };
    }

    var node_values: [N]f64 = undefined;
    var deriv_n_xi: [N]f64 = undefined;
    var deriv_n_eta: [N]f64 = undefined;
    shapefun.shapeFunctions(
        N,
        seed.xi,
        seed.eta,
        &node_values,
        &deriv_n_xi,
        &deriv_n_eta,
    );

    var residual_x: f64 = 0.0;
    var residual_y: f64 = 0.0;
    var jacobian_11: f64 = 0.0;
    var jacobian_12: f64 = 0.0;
    var jacobian_21: f64 = 0.0;
    var jacobian_22: f64 = 0.0;

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

// Solves: $$ \sum_{i=1}^N N_i(\xi, \eta) \cdot (X_{pixel} \cdot W_i - X_i) = 0 $$
// N_i are the shape functions,
// xi, eta = element parametric coords, 0 to 1 for tri6 and -1 to 1 for quad8,quad9
// X_pixel = target screen coords we are solving at in pixels
// W_i = perspective divisor in length units. For a pinhole camera this is the z coord.
// X_i = scaled clip space coords of the nodes in pixel.length units
// NOTE: solves in pixel.length units to account for the perspective divide!
// $$\begin{bmatrix} \xi_{new} \\ \eta_{new} \end{bmatrix} = \begin{bmatrix} \xi \\
// \eta \end{bmatrix} - J^{-1} \begin{bmatrix} R_x \\ R_y \end{bmatrix}$$
pub fn solveInverse(
    comptime N: usize, // Number of nodes in the element.
    target_screen_x: f64, // in pixels
    target_screen_y: f64, // in pixels
    element_node_x: []const f64, // Scaled clip space x coord, in pixels.length
    element_node_y: []const f64, // Scaled clip space y coord, in pixels.length
    element_node_w: []const f64, // Perspective divisor, for pin-hole = z, in length units
    xi_in: f64, // Parametric coords initial seed, unitless
    eta_in: f64,
    xi_out: *f64, // Parametric coords output, unitless
    eta_out: *f64,
    node_values: *[N]f64,
    deriv_n_xi: *[N]f64,
    deriv_n_eta: *[N]f64,
) NewtonResult {
    const iter_tol = tol.newton.residual;
    const det_tol = tol.newton.determinant;
    const eps = tol.newton.parametric_domain;
    const iter_max: u8 = 10;

    var xi = xi_in;
    var eta = eta_in;

    var term_x: [N]f64 = undefined;
    var term_y: [N]f64 = undefined;
    inline for (0..N) |nn| {
        term_x[nn] = target_screen_x * element_node_w[nn] - element_node_x[nn];
        term_y[nn] = target_screen_y * element_node_w[nn] - element_node_y[nn];
    }

    var met_residual = false;
    var iters: u8 = 0;
    var residual_x: f64 = 0.0;
    var residual_y: f64 = 0.0;

    for (0..iter_max) |ii| {
        iters = @intCast(ii + 1);
        shapefun.shapeFunctions(N, xi, eta, node_values, deriv_n_xi, deriv_n_eta);

        residual_x = 0.0;
        residual_y = 0.0;
        var jacobian_11: f64 = 0.0;
        var jacobian_12: f64 = 0.0;
        var jacobian_21: f64 = 0.0;
        var jacobian_22: f64 = 0.0;

        for (0..N) |nn| {
            residual_x += node_values[nn] * term_x[nn];
            residual_y += node_values[nn] * term_y[nn];
            jacobian_11 += deriv_n_xi[nn] * term_x[nn];
            jacobian_12 += deriv_n_eta[nn] * term_x[nn];
            jacobian_21 += deriv_n_xi[nn] * term_y[nn];
            jacobian_22 += deriv_n_eta[nn] * term_y[nn];
        }

        if (@abs(residual_x) < iter_tol and @abs(residual_y) < iter_tol) {
            met_residual = true;
            break;
        }

        const determinant = jacobian_11 * jacobian_22 - jacobian_12 * jacobian_21;
        if (@abs(determinant) < det_tol) {
            return .{
                .converged = false,
                .pre_domain_converged = false,
                .iterations = iters,
                .residual_x = residual_x,
                .residual_y = residual_y,
            };
        }

        const inverse_determinant = 1.0 / determinant;
        xi -= inverse_determinant * (jacobian_22 * residual_x - jacobian_12 * residual_y);
        eta -= inverse_determinant * (-jacobian_21 * residual_x + jacobian_11 * residual_y);
    }

    if (!met_residual) {
        return .{
            .converged = false,
            .pre_domain_converged = false,
            .iterations = iters,
            .residual_x = residual_x,
            .residual_y = residual_y,
        };
    }

    const is_in = if (comptime N == 6)
        (xi >= -eps and eta >= -eps and (xi + eta) <= 1.0 + eps)
    else
        (xi >= -1.0 - eps and xi <= 1.0 + eps and eta >= -1.0 - eps and eta <= 1.0 + eps);

    if (is_in) {
        xi_out.* = xi;
        eta_out.* = eta;
        return .{
            .converged = true,
            .pre_domain_converged = true,
            .iterations = iters,
            .residual_x = residual_x,
            .residual_y = residual_y,
        };
    }

    return .{
        .converged = false,
        .pre_domain_converged = true,
        .iterations = iters,
        .residual_x = residual_x,
        .residual_y = residual_y,
    };
}

pub fn solveInverseSIMD(
    comptime N: usize,
    v_target_x: @Vector(S, f64),
    v_target_y: @Vector(S, f64),
    elem_node_x: []const f64,
    elem_node_y: []const f64,
    elem_node_w: []const f64,
    v_xi_in: @Vector(S, f64),
    v_eta_in: @Vector(S, f64),
    v_xi_out: *@Vector(S, f64),
    v_eta_out: *@Vector(S, f64),
    v_node_values: *[N]@Vector(S, f64),
    v_deriv_n_xi: *[N]@Vector(S, f64),
    v_deriv_n_eta: *[N]@Vector(S, f64),
) NewtonResultSIMD {
    const v_iter_tol: @Vector(S, f64) = @splat(
        tol.newton.residual,
    );
    const v_det_tol: @Vector(S, f64) = @splat(
        tol.newton.determinant,
    );
    const v_eps: @Vector(S, f64) = @splat(
        tol.newton.parametric_domain,
    );
    const iter_max: u8 = 10;

    var v_xi = v_xi_in;
    var v_eta = v_eta_in;

    var v_converged: @Vector(S, bool) = @splat(false);
    var v_iters: @Vector(S, u8) = @splat(0);
    var v_active: @Vector(S, bool) = @splat(true);
    var v_residual_x_final: @Vector(S, f64) = @splat(0.0);
    var v_residual_y_final: @Vector(S, f64) = @splat(0.0);

    var v_term_x: [N]@Vector(S, f64) = undefined;
    var v_term_y: [N]@Vector(S, f64) = undefined;
    inline for (0..N) |nn| {
        const v_node_x: @Vector(S, f64) = @splat(elem_node_x[nn]);
        const v_node_y: @Vector(S, f64) = @splat(elem_node_y[nn]);
        const v_node_w: @Vector(S, f64) = @splat(elem_node_w[nn]);
        v_term_x[nn] = v_target_x * v_node_w - v_node_x;
        v_term_y[nn] = v_target_y * v_node_w - v_node_y;
    }

    for (0..iter_max) |ii| {
        if (!@reduce(.Or, v_active)) break;

        v_iters = @select(
            u8,
            v_active,
            @as(@Vector(S, u8), @splat(@intCast(ii + 1))),
            v_iters,
        );

        shapefun.shapeFunctionsSIMD(N, v_xi, v_eta, v_node_values, v_deriv_n_xi, v_deriv_n_eta);

        var v_residual_x: @Vector(S, f64) = @splat(0.0);
        var v_residual_y: @Vector(S, f64) = @splat(0.0);
        var v_jac11: @Vector(S, f64) = @splat(0.0);
        var v_jac12: @Vector(S, f64) = @splat(0.0);
        var v_jac21: @Vector(S, f64) = @splat(0.0);
        var v_jac22: @Vector(S, f64) = @splat(0.0);

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
            f64,
            v_active,
            v_det,
            @as(@Vector(S, f64), @splat(1.0)),
        );
        const v_inv_det = @as(@Vector(S, f64), @splat(1.0)) / v_safe_det;

        const v_dxi = v_inv_det * (v_jac22 * v_residual_x - v_jac12 * v_residual_y);
        const v_deta = v_inv_det * (-v_jac21 * v_residual_x + v_jac11 * v_residual_y);

        v_xi -= @select(f64, v_active, v_dxi, @as(@Vector(S, f64), @splat(0.0)));
        v_eta -= @select(f64, v_active, v_deta, @as(@Vector(S, f64), @splat(0.0)));
    }

    const v_1: @Vector(S, f64) = @splat(1.0);
    const v_m1: @Vector(S, f64) = @splat(-1.0);

    const v_is_in = if (comptime N == 6)
        (v_xi >= -v_eps) & (v_eta >= -v_eps) & ((v_xi + v_eta) <= v_1 + v_eps)
    else
        (v_xi >= v_m1 - v_eps) & (v_xi <= v_1 + v_eps) &
            (v_eta >= v_m1 - v_eps) & (v_eta <= v_1 + v_eps);

    const v_final_converged = v_converged & v_is_in;
    v_xi_out.* = v_xi;
    v_eta_out.* = v_eta;

    return .{
        .converged = v_final_converged,
        .pre_domain_converged = v_converged,
        .iterations = v_iters,
        .residual_x = v_residual_x_final,
        .residual_y = v_residual_y_final,
    };
}
