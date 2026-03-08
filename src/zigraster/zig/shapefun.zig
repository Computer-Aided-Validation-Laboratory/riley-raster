pub fn shapeFunctions(comptime N: usize, xi: f64, eta: f64, n_v: *[N]f64, dNu: *[N]f64, dNv: *[N]f64) void {
    switch (N) {
        4 => shapeFunctions4(xi, eta, n_v, dNu, dNv),
        6 => shapeFunctions6(xi, eta, n_v, dNu, dNv),
        8 => shapeFunctions8(xi, eta, n_v, dNu, dNv),
        9 => shapeFunctions9(xi, eta, n_v, dNu, dNv),
        else => @compileError("Unsupported number of nodes"),
    }
}

fn shapeFunctions4(xi: f64, eta: f64, n_v: *[4]f64, dNu: *[4]f64, dNv: *[4]f64) void {
    n_v[0] = 0.25 * (1.0 - xi) * (1.0 - eta);
    n_v[1] = 0.25 * (1.0 + xi) * (1.0 - eta);
    n_v[2] = 0.25 * (1.0 + xi) * (1.0 + eta);
    n_v[3] = 0.25 * (1.0 - xi) * (1.0 + eta);

    dNu[0] = -0.25 * (1.0 - eta); dNu[1] = 0.25 * (1.0 - eta);
    dNu[2] = 0.25 * (1.0 + eta);  dNu[3] = -0.25 * (1.0 + eta);

    dNv[0] = -0.25 * (1.0 - xi);  dNv[1] = -0.25 * (1.0 + xi);
    dNv[2] = 0.25 * (1.0 + xi);   dNv[3] = 0.25 * (1.0 - xi);
}

fn shapeFunctions6(xi: f64, eta: f64, n_vals: *[6]f64, dN_dxi: *[6]f64, dN_deta: *[6]f64) void {
    const L1 = 1.0 - xi - eta;
    const L2 = xi;
    const L3 = eta;

    n_vals[0] = L1 * (2.0 * L1 - 1.0);
    dN_dxi[0] = -(4.0 * L1 - 1.0);
    dN_deta[0] = -(4.0 * L1 - 1.0);

    n_vals[1] = L2 * (2.0 * L2 - 1.0);
    dN_dxi[1] = 4.0 * L2 - 1.0;
    dN_deta[1] = 0.0;

    n_vals[2] = L3 * (2.0 * L3 - 1.0);
    dN_dxi[2] = 0.0;
    dN_deta[2] = 4.0 * L3 - 1.0;

    n_vals[3] = 4.0 * L1 * L2;
    dN_dxi[3] = 4.0 * (L1 - L2);
    dN_deta[3] = -4.0 * L2;

    n_vals[4] = 4.0 * L2 * L3;
    dN_dxi[4] = 4.0 * L3;
    dN_deta[4] = 4.0 * L2;

    n_vals[5] = 4.0 * L3 * L1;
    dN_dxi[5] = -4.0 * L3;
    dN_deta[5] = 4.0 * (L1 - L3);
}

fn shapeFunctions8(xi: f64, eta: f64, n_v: *[8]f64, dNu: *[8]f64, dNv: *[8]f64) void {
    const x = xi; const y = eta;
    n_v[0] = -0.25 * (1.0 - x) * (1.0 - y) * (1.0 + x + y);
    n_v[1] = -0.25 * (1.0 + x) * (1.0 - y) * (1.0 - x + y);
    n_v[2] = -0.25 * (1.0 + x) * (1.0 + y) * (1.0 - x - y);
    n_v[3] = -0.25 * (1.0 - x) * (1.0 + y) * (1.0 + x - y);
    n_v[4] = 0.5 * (1.0 - x * x) * (1.0 - y);
    n_v[5] = 0.5 * (1.0 + x) * (1.0 - y * y);
    n_v[6] = 0.5 * (1.0 - x * x) * (1.0 + y);
    n_v[7] = 0.5 * (1.0 - x) * (1.0 - y * y);

    dNu[0] = 0.25 * (1.0 - y) * (2.0 * x + y);
    dNu[1] = 0.25 * (1.0 - y) * (2.0 * x - y);
    dNu[2] = 0.25 * (1.0 + y) * (2.0 * x + y);
    dNu[3] = 0.25 * (1.0 + y) * (2.0 * x - y);
    dNu[4] = -x * (1.0 - y); dNu[5] = 0.5 * (1.0 - y * y);
    dNu[6] = -x * (1.0 + y); dNu[7] = -0.5 * (1.0 - y * y);

    dNv[0] = 0.25 * (1.0 - x) * (x + 2.0 * y);
    dNv[1] = 0.25 * (1.0 + x) * (2.0 * y - x);
    dNv[2] = 0.25 * (1.0 + x) * (x + 2.0 * y);
    dNv[3] = 0.25 * (1.0 - x) * (2.0 * y - x);
    dNv[4] = -0.5 * (1.0 - x * x); dNv[5] = -y * (1.0 + x);
    dNv[6] = 0.5 * (1.0 - x * x);  dNv[7] = -y * (1.0 - x);
}

fn shapeFunctions9(xi: f64, eta: f64, n_v: *[9]f64, dNu: *[9]f64, dNv: *[9]f64) void {
    const x = xi; const y = eta;
    const phi = [3]f64{ 0.5 * x * (x - 1.0), 1.0 - x * x, 0.5 * x * (x + 1.0) };
    const psi = [3]f64{ 0.5 * y * (y - 1.0), 1.0 - y * y, 0.5 * y * (y + 1.0) };
    const dphi = [3]f64{ x - 0.5, -2.0 * x, x + 0.5 };
    const dpsi = [3]f64{ y - 0.5, -2.0 * y, y + 0.5 };

    n_v[0] = phi[0] * psi[0]; n_v[1] = phi[2] * psi[0]; 
    n_v[2] = phi[2] * psi[2]; n_v[3] = phi[0] * psi[2];
    n_v[4] = phi[1] * psi[0]; n_v[5] = phi[2] * psi[1]; 
    n_v[6] = phi[1] * psi[2]; n_v[7] = phi[0] * psi[1];
    n_v[8] = phi[1] * psi[1];

    dNu[0] = dphi[0] * psi[0]; dNu[1] = dphi[2] * psi[0]; 
    dNu[2] = dphi[2] * psi[2]; dNu[3] = dphi[0] * psi[2];
    dNu[4] = dphi[1] * psi[0]; dNu[5] = dphi[2] * psi[1]; 
    dNu[6] = dphi[1] * psi[2]; dNu[7] = dphi[0] * psi[1];
    dNu[8] = dphi[1] * psi[1];

    dNv[0] = phi[0] * dpsi[0]; dNv[1] = phi[2] * dpsi[0]; 
    dNv[2] = phi[2] * dpsi[2]; dNv[3] = phi[0] * dpsi[2];
    dNv[4] = phi[1] * dpsi[0]; dNv[5] = phi[2] * dpsi[1]; 
    dNv[6] = phi[1] * dpsi[2]; dNv[7] = phi[0] * dpsi[1];
    dNv[8] = phi[1] * dpsi[1];
}
