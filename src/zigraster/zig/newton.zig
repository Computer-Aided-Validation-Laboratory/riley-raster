const shapefun = @import("shapefun.zig");

pub fn solveInverse(comptime N: usize,
                    txs: f64, tys: f64, 
                    ex: []const f64, ey: []const f64, ew: []const f64,
                    xi_in: f64, eta_in: f64,
                    xi_out: *f64, eta_out: *f64) bool {

    const tol_iter: f64 = 1e-8;
    const tol_det: f64 = 1e-12;
    const eps: f64 = 1e-5;
    const max_iter: usize = 10;

    var xi = xi_in;
    var eta = eta_in;

    var n_vals: [N]f64 = undefined;
    var dN_dxi: [N]f64 = undefined;
    var dN_deta: [N]f64 = undefined;

    for (0..max_iter) |_| {
        shapefun.shapeFunctions(N, xi, eta, &n_vals, &dN_dxi, &dN_deta);

        var Rx: f64 = 0.0; var Ry: f64 = 0.0;
        var J11: f64 = 0.0; var J12: f64 = 0.0;
        var J21: f64 = 0.0; var J22: f64 = 0.0;

        for (0..N) |i| {
            const tx = txs * ew[i] - ex[i];
            const ty = tys * ew[i] - ey[i];
            Rx += n_vals[i] * tx;
            Ry += n_vals[i] * ty;
            J11 += dN_dxi[i] * tx;
            J12 += dN_deta[i] * tx;
            J21 += dN_dxi[i] * ty;
            J22 += dN_deta[i] * ty;
        }

        if (@abs(Rx) < tol_iter and @abs(Ry) < tol_iter) {
            break;
        }

        const det = J11 * J22 - J12 * J21;
        if (@abs(det) < tol_det) {
            return false;
        }

        const inv_det = 1.0 / det;
        xi -= inv_det * (J22 * Rx - J12 * Ry);
        eta -= inv_det * (-J21 * Rx + J11 * Ry);
    }

    if (comptime N == 6) {
        // Triangle 6: xi, eta in [0, 1], xi + eta <= 1
        if (xi >= -eps and eta >= -eps and (xi + eta) <= 1.0 + eps) {
            xi_out.* = xi;
            eta_out.* = eta;
            return true;
        }
    } else {
        // Quads: xi, eta in [-1, 1]
        if (xi >= -1.0 - eps and xi <= 1.0 + eps and 
            eta >= -1.0 - eps and eta <= 1.0 + eps) {
            xi_out.* = xi;
            eta_out.* = eta;
            return true;
        }
    }

    return false;
}
