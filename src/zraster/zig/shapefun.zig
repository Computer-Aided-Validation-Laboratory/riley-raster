const buildconfig = @import("buildconfig.zig");

const S = buildconfig.config.simd_vector_width;

pub fn shapeFunctions(
    comptime N: usize,
    xi: f64,
    eta: f64,
    n_v: *[N]f64,
    dNu: *[N]f64,
    dNv: *[N]f64,
) void {
    switch (N) {
        3 => shapeFunctions3(xi, eta, n_v, dNu, dNv),
        4 => shapeFunctions4(xi, eta, n_v, dNu, dNv),
        6 => shapeFunctions6(xi, eta, n_v, dNu, dNv),
        8 => shapeFunctions8(xi, eta, n_v, dNu, dNv),
        9 => shapeFunctions9(xi, eta, n_v, dNu, dNv),
        else => @compileError("Unsupported number of nodes"),
    }
}

pub fn shapeFunctionsSIMD(
    comptime N: usize,
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[N]@Vector(S, f64),
    v_dNu: *[N]@Vector(S, f64),
    v_dNv: *[N]@Vector(S, f64),
) void {
    switch (N) {
        3 => shapeFunctions3SIMD(v_xi, v_eta, v_n_v, v_dNu, v_dNv),
        4 => shapeFunctions4SIMD(v_xi, v_eta, v_n_v, v_dNu, v_dNv),
        6 => shapeFunctions6SIMD(v_xi, v_eta, v_n_v, v_dNu, v_dNv),
        8 => shapeFunctions8SIMD(v_xi, v_eta, v_n_v, v_dNu, v_dNv),
        9 => shapeFunctions9SIMD(v_xi, v_eta, v_n_v, v_dNu, v_dNv),
        else => @compileError("Unsupported number of nodes"),
    }
}

fn shapeFunctions3(xi: f64, eta: f64, n_v: *[3]f64, dNu: *[3]f64, dNv: *[3]f64) void {
    const L1 = 1.0 - xi - eta;
    const L2 = xi;
    const L3 = eta;

    n_v[0] = L1;
    n_v[1] = L2;
    n_v[2] = L3;

    dNu[0] = -1.0;
    dNu[1] = 1.0;
    dNu[2] = 0.0;

    dNv[0] = -1.0;
    dNv[1] = 0.0;
    dNv[2] = 1.0;
}

fn shapeFunctions3SIMD(
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[3]@Vector(S, f64),
    v_dNu: *[3]@Vector(S, f64),
    v_dNv: *[3]@Vector(S, f64),
) void {
    const v_1: @Vector(S, f64) = @splat(1.0);
    const v_0: @Vector(S, f64) = @splat(0.0);
    const v_m1: @Vector(S, f64) = @splat(-1.0);

    const v_L1 = v_1 - v_xi - v_eta;
    const v_L2 = v_xi;
    const v_L3 = v_eta;

    v_n_v[0] = v_L1;
    v_n_v[1] = v_L2;
    v_n_v[2] = v_L3;

    v_dNu[0] = v_m1;
    v_dNu[1] = v_1;
    v_dNu[2] = v_0;

    v_dNv[0] = v_m1;
    v_dNv[1] = v_0;
    v_dNv[2] = v_1;
}

fn shapeFunctions4(xi: f64, eta: f64, n_v: *[4]f64, dNu: *[4]f64, dNv: *[4]f64) void {
    n_v[0] = 0.25 * (1.0 - xi) * (1.0 - eta);
    n_v[1] = 0.25 * (1.0 + xi) * (1.0 - eta);
    n_v[2] = 0.25 * (1.0 + xi) * (1.0 + eta);
    n_v[3] = 0.25 * (1.0 - xi) * (1.0 + eta);

    dNu[0] = -0.25 * (1.0 - eta);
    dNu[1] = 0.25 * (1.0 - eta);
    dNu[2] = 0.25 * (1.0 + eta);
    dNu[3] = -0.25 * (1.0 + eta);

    dNv[0] = -0.25 * (1.0 - xi);
    dNv[1] = -0.25 * (1.0 + xi);
    dNv[2] = 0.25 * (1.0 + xi);
    dNv[3] = 0.25 * (1.0 - xi);
}

fn shapeFunctions4SIMD(
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[4]@Vector(S, f64),
    v_dNu: *[4]@Vector(S, f64),
    v_dNv: *[4]@Vector(S, f64),
) void {
    const v_025: @Vector(S, f64) = @splat(0.25);
    const v_m025: @Vector(S, f64) = @splat(-0.25);
    const v_1: @Vector(S, f64) = @splat(1.0);

    const v_1_m_xi = v_1 - v_xi;
    const v_1_p_xi = v_1 + v_xi;
    const v_1_m_eta = v_1 - v_eta;
    const v_1_p_eta = v_1 + v_eta;

    v_n_v[0] = v_025 * v_1_m_xi * v_1_m_eta;
    v_n_v[1] = v_025 * v_1_p_xi * v_1_m_eta;
    v_n_v[2] = v_025 * v_1_p_xi * v_1_p_eta;
    v_n_v[3] = v_025 * v_1_m_xi * v_1_p_eta;

    v_dNu[0] = v_m025 * v_1_m_eta;
    v_dNu[1] = v_025 * v_1_m_eta;
    v_dNu[2] = v_025 * v_1_p_eta;
    v_dNu[3] = v_m025 * v_1_p_eta;

    v_dNv[0] = v_m025 * v_1_m_xi;
    v_dNv[1] = v_m025 * v_1_p_xi;
    v_dNv[2] = v_025 * v_1_p_xi;
    v_dNv[3] = v_025 * v_1_m_xi;
}

fn shapeFunctions6(
    xi: f64,
    eta: f64,
    n_vals: *[6]f64,
    dN_dxi: *[6]f64,
    dN_deta: *[6]f64,
) void {
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

fn shapeFunctions6SIMD(
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[6]@Vector(S, f64),
    v_dNu: *[6]@Vector(S, f64),
    v_dNv: *[6]@Vector(S, f64),
) void {
    const v_1: @Vector(S, f64) = @splat(1.0);
    const v_2: @Vector(S, f64) = @splat(2.0);
    const v_4: @Vector(S, f64) = @splat(4.0);
    const v_0: @Vector(S, f64) = @splat(0.0);

    const v_L1 = v_1 - v_xi - v_eta;
    const v_L2 = v_xi;
    const v_L3 = v_eta;

    const v_4_L1_m_1 = v_4 * v_L1 - v_1;
    const v_4_L2_m_1 = v_4 * v_L2 - v_1;
    const v_4_L3_m_1 = v_4 * v_L3 - v_1;

    v_n_v[0] = v_L1 * (v_2 * v_L1 - v_1);
    v_dNu[0] = -v_4_L1_m_1;
    v_dNv[0] = -v_4_L1_m_1;

    v_n_v[1] = v_L2 * (v_2 * v_L2 - v_1);
    v_dNu[1] = v_4_L2_m_1;
    v_dNv[1] = v_0;

    v_n_v[2] = v_L3 * (v_2 * v_L3 - v_1);
    v_dNu[2] = v_0;
    v_dNv[2] = v_4_L3_m_1;

    v_n_v[3] = v_4 * v_L1 * v_L2;
    v_dNu[3] = v_4 * (v_L1 - v_L2);
    v_dNv[3] = -v_4 * v_L2;

    v_n_v[4] = v_4 * v_L2 * v_L3;
    v_dNu[4] = v_4 * v_L3;
    v_dNv[4] = v_4 * v_L2;

    v_n_v[5] = v_4 * v_L3 * v_L1;
    v_dNu[5] = -v_4 * v_L3;
    v_dNv[5] = v_4 * (v_L1 - v_L3);
}

fn shapeFunctions8(xi: f64, eta: f64, n_v: *[8]f64, dNu: *[8]f64, dNv: *[8]f64) void {
    const x = xi;
    const y = eta;
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
    dNu[4] = -x * (1.0 - y);
    dNu[5] = 0.5 * (1.0 - y * y);
    dNu[6] = -x * (1.0 + y);
    dNu[7] = -0.5 * (1.0 - y * y);

    dNv[0] = 0.25 * (1.0 - x) * (x + 2.0 * y);
    dNv[1] = 0.25 * (1.0 + x) * (2.0 * y - x);
    dNv[2] = 0.25 * (1.0 + x) * (x + 2.0 * y);
    dNv[3] = 0.25 * (1.0 - x) * (2.0 * y - x);
    dNv[4] = -0.5 * (1.0 - x * x);
    dNv[5] = -y * (1.0 + x);
    dNv[6] = 0.5 * (1.0 - x * x);
    dNv[7] = -y * (1.0 - x);
}

fn shapeFunctions8SIMD(
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[8]@Vector(S, f64),
    v_dNu: *[8]@Vector(S, f64),
    v_dNv: *[8]@Vector(S, f64),
) void {
    const x = v_xi;
    const y = v_eta;
    const v_1: @Vector(S, f64) = @splat(1.0);
    const v_2: @Vector(S, f64) = @splat(2.0);
    const v_05: @Vector(S, f64) = @splat(0.5);
    const v_m05: @Vector(S, f64) = @splat(-0.5);
    const v_025: @Vector(S, f64) = @splat(0.25);
    const v_m025: @Vector(S, f64) = @splat(-0.25);

    const x2 = x * x;
    const y2 = y * y;
    const v_1_m_x = v_1 - x;
    const v_1_p_x = v_1 + x;
    const v_1_m_y = v_1 - y;
    const v_1_p_y = v_1 + y;

    v_n_v[0] = v_m025 * v_1_m_x * v_1_m_y * (v_1 + x + y);
    v_n_v[1] = v_m025 * v_1_p_x * v_1_m_y * (v_1 - x + y);
    v_n_v[2] = v_m025 * v_1_p_x * v_1_p_y * (v_1 - x - y);
    v_n_v[3] = v_m025 * v_1_m_x * v_1_p_y * (v_1 + x - y);
    v_n_v[4] = v_05 * (v_1 - x2) * v_1_m_y;
    v_n_v[5] = v_05 * v_1_p_x * (v_1 - y2);
    v_n_v[6] = v_05 * (v_1 - x2) * v_1_p_y;
    v_n_v[7] = v_05 * v_1_m_x * (v_1 - y2);

    const v_2x = v_2 * x;
    const v_2y = v_2 * y;
    const v_1_m_y2 = v_1 - y2;
    const v_1_m_x2 = v_1 - x2;

    v_dNu[0] = v_025 * v_1_m_y * (v_2x + y);
    v_dNu[1] = v_025 * v_1_m_y * (v_2x - y);
    v_dNu[2] = v_025 * v_1_p_y * (v_2x + y);
    v_dNu[3] = v_025 * v_1_p_y * (v_2x - y);
    v_dNu[4] = -x * v_1_m_y;
    v_dNu[5] = v_05 * v_1_m_y2;
    v_dNu[6] = -x * v_1_p_y;
    v_dNu[7] = v_m05 * v_1_m_y2;

    v_dNv[0] = v_025 * v_1_m_x * (x + v_2y);
    v_dNv[1] = v_025 * v_1_p_x * (v_2y - x);
    v_dNv[2] = v_025 * v_1_p_x * (x + v_2y);
    v_dNv[3] = v_025 * v_1_m_x * (v_2y - x);
    v_dNv[4] = v_m05 * v_1_m_x2;
    v_dNv[5] = -y * v_1_p_x;
    v_dNv[6] = v_05 * v_1_m_x2;
    v_dNv[7] = -y * v_1_m_x;
}

fn shapeFunctions9(xi: f64, eta: f64, n_v: *[9]f64, dNu: *[9]f64, dNv: *[9]f64) void {
    const x = xi;
    const y = eta;
    const phi = [3]f64{ 0.5 * x * (x - 1.0), 1.0 - x * x, 0.5 * x * (x + 1.0) };
    const psi = [3]f64{ 0.5 * y * (y - 1.0), 1.0 - y * y, 0.5 * y * (y + 1.0) };
    const dphi = [3]f64{ x - 0.5, -2.0 * x, x + 0.5 };
    const dpsi = [3]f64{ y - 0.5, -2.0 * y, y + 0.5 };

    n_v[0] = phi[0] * psi[0];
    n_v[1] = phi[2] * psi[0];
    n_v[2] = phi[2] * psi[2];
    n_v[3] = phi[0] * psi[2];
    n_v[4] = phi[1] * psi[0];
    n_v[5] = phi[2] * psi[1];
    n_v[6] = phi[1] * psi[2];
    n_v[7] = phi[0] * psi[1];
    n_v[8] = phi[1] * psi[1];

    dNu[0] = dphi[0] * psi[0];
    dNu[1] = dphi[2] * psi[0];
    dNu[2] = dphi[2] * psi[2];
    dNu[3] = dphi[0] * psi[2];
    dNu[4] = dphi[1] * psi[0];
    dNu[5] = dphi[2] * psi[1];
    dNu[6] = dphi[1] * psi[2];
    dNu[7] = dphi[0] * psi[1];
    dNu[8] = dphi[1] * psi[1];

    dNv[0] = phi[0] * dpsi[0];
    dNv[1] = phi[2] * dpsi[0];
    dNv[2] = phi[2] * dpsi[2];
    dNv[3] = phi[0] * dpsi[2];
    dNv[4] = phi[1] * dpsi[0];
    dNv[5] = phi[2] * dpsi[1];
    dNv[6] = phi[1] * dpsi[2];
    dNv[7] = phi[0] * dpsi[1];
    dNv[8] = phi[1] * dpsi[1];
}

fn shapeFunctions9SIMD(
    v_xi: @Vector(S, f64),
    v_eta: @Vector(S, f64),
    v_n_v: *[9]@Vector(S, f64),
    v_dNu: *[9]@Vector(S, f64),
    v_dNv: *[9]@Vector(S, f64),
) void {
    const x = v_xi;
    const y = v_eta;
    const v_1: @Vector(S, f64) = @splat(1.0);
    const v_05: @Vector(S, f64) = @splat(0.5);
    const v_m2: @Vector(S, f64) = @splat(-2.0);

    const x_m_1 = x - v_1;
    const x_p_1 = x + v_1;
    const y_m_1 = y - v_1;
    const y_p_1 = y + v_1;

    const v_phi = [3]@Vector(S, f64){
        v_05 * x * x_m_1,
        v_1 - x * x,
        v_05 * x * x_p_1,
    };
    const v_psi = [3]@Vector(S, f64){
        v_05 * y * y_m_1,
        v_1 - y * y,
        v_05 * y * y_p_1,
    };
    const v_dphi = [3]@Vector(S, f64){ x - v_05, v_m2 * x, x + v_05 };
    const v_dpsi = [3]@Vector(S, f64){ y - v_05, v_m2 * y, y + v_05 };

    v_n_v[0] = v_phi[0] * v_psi[0];
    v_n_v[1] = v_phi[2] * v_psi[0];
    v_n_v[2] = v_phi[2] * v_psi[2];
    v_n_v[3] = v_phi[0] * v_psi[2];
    v_n_v[4] = v_phi[1] * v_psi[0];
    v_n_v[5] = v_phi[2] * v_psi[1];
    v_n_v[6] = v_phi[1] * v_psi[2];
    v_n_v[7] = v_phi[0] * v_psi[1];
    v_n_v[8] = v_phi[1] * v_psi[1];

    v_dNu[0] = v_dphi[0] * v_psi[0];
    v_dNu[1] = v_dphi[2] * v_psi[0];
    v_dNu[2] = v_dphi[2] * v_psi[2];
    v_dNu[3] = v_dphi[0] * v_psi[2];
    v_dNu[4] = v_dphi[1] * v_psi[0];
    v_dNu[5] = v_dphi[2] * v_psi[1];
    v_dNu[6] = v_dphi[1] * v_psi[2];
    v_dNu[7] = v_dphi[0] * v_psi[1];
    v_dNu[8] = v_dphi[1] * v_psi[1];

    v_dNv[0] = v_phi[0] * v_dpsi[0];
    v_dNv[1] = v_phi[2] * v_dpsi[0];
    v_dNv[2] = v_phi[2] * v_dpsi[2];
    v_dNv[3] = v_phi[0] * v_dpsi[2];
    v_dNv[4] = v_phi[1] * v_dpsi[0];
    v_dNv[5] = v_phi[2] * v_dpsi[1];
    v_dNv[6] = v_phi[1] * v_dpsi[2];
    v_dNv[7] = v_phi[0] * v_dpsi[1];
    v_dNv[8] = v_phi[1] * v_dpsi[1];
}
