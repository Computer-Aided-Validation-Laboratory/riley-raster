const shapefun = @import("shapefun.zig");

pub const NewtonResult = struct {
    converged: bool,
    iterations: u8,
};

pub const NewtonResultSIMD = struct {
    converged: @Vector(8, bool),
    iterations: @Vector(8, u8),
};

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
    xi_in: f64,     // Parametric coords initial guess, unitless
    eta_in: f64,
    xi_out: *f64,   // Parametric coords output, unitless 
    eta_out: *f64,
) NewtonResult {
    const iter_tol: f64 = 1e-8;
    const det_tol: f64 = 1e-12;
    const eps: f64 = 1e-5;
    const iter_max: u8 = 10;

    var xi = xi_in;
    var eta = eta_in;

    var node_values: [N]f64 = undefined;
    var deriv_n_xi: [N]f64 = undefined;
    var deriv_n_eta: [N]f64 = undefined;

    var met_residual = false;
    var iters: u8 = 0;
    for (0..iter_max) |ii| {
        iters = @intCast(ii + 1);
        shapefun.shapeFunctions(N, xi, eta, &node_values, &deriv_n_xi, &deriv_n_eta);

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

        if (@abs(residual_x) < iter_tol and @abs(residual_y) < iter_tol) {
            met_residual = true;
            break;
        }

        const determinant = jacobian_11 * jacobian_22 - jacobian_12 * jacobian_21;
        if (@abs(determinant) < det_tol) {
            return .{ .converged = false, .iterations = iters };
        }

        const inverse_determinant = 1.0 / determinant;
        xi -= inverse_determinant * (jacobian_22 * residual_x - jacobian_12 * residual_y);
        eta -= inverse_determinant * (-jacobian_21 * residual_x + jacobian_11 * residual_y);
    }

    if (!met_residual) return .{ .converged = false, .iterations = iters };

    const is_in = if (comptime N == 6)
        (xi >= -eps and eta >= -eps and (xi + eta) <= 1.0 + eps)
    else
        (xi >= -1.0 - eps and xi <= 1.0 + eps and eta >= -1.0 - eps and eta <= 1.0 + eps);

    if (is_in) {
        xi_out.* = xi;
        eta_out.* = eta;
        return .{ .converged = true, .iterations = iters };
    }

    return .{ .converged = false, .iterations = iters };
}

pub fn solveInverseSIMD(
    comptime N: usize,
    v_target_x: @Vector(8, f64),
    v_target_y: @Vector(8, f64),
    elem_node_x: []const f64,
    elem_node_y: []const f64,
    elem_node_w: []const f64,
    v_xi_in: @Vector(8, f64),
    v_eta_in: @Vector(8, f64),
    v_xi_out: *@Vector(8, f64),
    v_eta_out: *@Vector(8, f64),
) NewtonResultSIMD {
    const v_iter_tol: @Vector(8, f64) = @splat(1e-8);
    const v_det_tol: @Vector(8, f64) = @splat(1e-12);
    const v_eps: @Vector(8, f64) = @splat(1e-5);
    const iter_max: u8 = 50;

    var v_xi = v_xi_in;
    var v_eta = v_eta_in;

    var v_node_values: [N]@Vector(8, f64) = undefined;
    var v_deriv_n_xi: [N]@Vector(8, f64) = undefined;
    var v_deriv_n_eta: [N]@Vector(8, f64) = undefined;

    var v_converged: @Vector(8, bool) = @splat(false);
    var v_iters: @Vector(8, u8) = @splat(0);
    var v_active: @Vector(8, bool) = @splat(true);

    for (0..iter_max) |ii| {
        if (!@reduce(.Or, v_active)) break;
        
        v_iters = @select(u8, v_active, @as(@Vector(8, u8), @splat(@intCast(ii + 1))), v_iters);
        
        shapefun.shapeFunctionsSIMD(N, v_xi, v_eta, &v_node_values, &v_deriv_n_xi, &v_deriv_n_eta);

        var v_residual_x: @Vector(8, f64) = @splat(0.0);
        var v_residual_y: @Vector(8, f64) = @splat(0.0);
        var v_jac11: @Vector(8, f64) = @splat(0.0);
        var v_jac12: @Vector(8, f64) = @splat(0.0);
        var v_jac21: @Vector(8, f64) = @splat(0.0);
        var v_jac22: @Vector(8, f64) = @splat(0.0);

        inline for (0..N) |nn| {
            const v_node_x: @Vector(8, f64) = @splat(elem_node_x[nn]);
            const v_node_y: @Vector(8, f64) = @splat(elem_node_y[nn]);
            const v_node_w: @Vector(8, f64) = @splat(elem_node_w[nn]);

            const v_term_x = v_target_x * v_node_w - v_node_x;
            const v_term_y = v_target_y * v_node_w - v_node_y;
            
            v_residual_x += v_node_values[nn] * v_term_x;
            v_residual_y += v_node_values[nn] * v_term_y;
            v_jac11 += v_deriv_n_xi[nn] * v_term_x;
            v_jac12 += v_deriv_n_eta[nn] * v_term_x;
            v_jac21 += v_deriv_n_xi[nn] * v_term_y;
            v_jac22 += v_deriv_n_eta[nn] * v_term_y;
        }

        const v_met_tol = (@abs(v_residual_x) < v_iter_tol) & (@abs(v_residual_y) < v_iter_tol);
        v_converged = v_converged | (v_active & v_met_tol);
        v_active = v_active & !v_met_tol;

        if (!@reduce(.Or, v_active)) break;

        const v_det = v_jac11 * v_jac22 - v_jac12 * v_jac21;
        const v_bad_det = @abs(v_det) < v_det_tol;
        
        // Disable lanes with bad determinants
        v_active = v_active & !v_bad_det;
        
        if (!@reduce(.Or, v_active)) break;

        const v_safe_det = @select(f64, v_active, v_det, @as(@Vector(8, f64), @splat(1.0)));
        const v_inv_det = @as(@Vector(8, f64), @splat(1.0)) / v_safe_det;
        
        const v_dxi = v_inv_det * (v_jac22 * v_residual_x - v_jac12 * v_residual_y);
        const v_deta = v_inv_det * (-v_jac21 * v_residual_x + v_jac11 * v_residual_y);
        
        v_xi -= @select(f64, v_active, v_dxi, @as(@Vector(8, f64), @splat(0.0)));
        v_eta -= @select(f64, v_active, v_deta, @as(@Vector(8, f64), @splat(0.0)));
    }

    const v_1: @Vector(8, f64) = @splat(1.0);
    const v_m1: @Vector(8, f64) = @splat(-1.0);

    const v_is_in = if (comptime N == 6)
        (v_xi >= -v_eps) & (v_eta >= -v_eps) & ((v_xi + v_eta) <= v_1 + v_eps)
    else
        (v_xi >= v_m1 - v_eps) & (v_xi <= v_1 + v_eps) & 
        (v_eta >= v_m1 - v_eps) & (v_eta <= v_1 + v_eps);

    const v_final_converged = v_converged & v_is_in;
    v_xi_out.* = v_xi;
    v_eta_out.* = v_eta;

    return .{ .converged = v_final_converged, .iterations = v_iters };
}
