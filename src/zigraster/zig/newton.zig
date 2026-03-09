const shapefun = @import("shapefun.zig");


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
) bool {
    const iter_tol: f64 = 1e-8;
    const det_tol: f64 = 1e-12;
    const eps: f64 = 1e-5;
    const iter_max: usize = 10;

    var xi = xi_in;
    var eta = eta_in;

    var node_values: [N]f64 = undefined;
    var deriv_n_xi: [N]f64 = undefined;
    var deriv_n_eta: [N]f64 = undefined;

    for (0..iter_max) |_| {
        shapefun.shapeFunctions(N, xi, eta, &node_values, &deriv_n_xi, &deriv_n_eta);

        var residual_x: f64 = 0.0;
        var residual_y: f64 = 0.0;
        var jacobian_11: f64 = 0.0;
        var jacobian_12: f64 = 0.0;
        var jacobian_21: f64 = 0.0;
        var jacobian_22: f64 = 0.0;

        // \sum_{i=1}^N N_i(\xi, \eta) \cdot (X_{pixel} \cdot W_i - X_i) = 0
        // $$\begin{bmatrix} \xi_{new} \\ \eta_{new} \end{bmatrix} = 
        // \begin{bmatrix} \xi \\ \eta \end{bmatrix} - J^{-1} \begin{bmatrix} R_x 
        // \\ R_y \end{bmatrix}$$
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
            break;
        }

        const determinant = jacobian_11 * jacobian_22 - jacobian_12 * jacobian_21;
        if (@abs(determinant) < det_tol) {
            return false;
        }

        const inverse_determinant = 1.0 / determinant;
        xi -= inverse_determinant * (jacobian_22 * residual_x - jacobian_12 * residual_y);
        eta -= inverse_determinant * (-jacobian_21 * residual_x + jacobian_11 * residual_y);
    }

    if (comptime N == 6) {
        // Tri 6: xi, eta in [0, 1], xi + eta <= 1
        const is_in_triangle = (xi >= -eps and
            eta >= -eps and
            (xi + eta) <= 1.0 + eps);
        if (is_in_triangle) {
            xi_out.* = xi;
            eta_out.* = eta;
            return true;
        }
    } else {
        // Quad 4,8,9: xi, eta in [-1, 1]
        const is_in_quad = (xi >= -1.0 - eps and
            xi <= 1.0 + eps and
            eta >= -1.0 - eps and
            eta <= 1.0 + eps);
        if (is_in_quad) {
            xi_out.* = xi;
            eta_out.* = eta;
            return true;
        }
    }

    return false;
}
