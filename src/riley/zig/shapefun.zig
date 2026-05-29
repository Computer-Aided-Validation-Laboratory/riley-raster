// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");

const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;

pub const NodalDerivs = struct {
    dNu: [9][9]f64,
    dNv: [9][9]f64,
};

pub fn getNodalDerivs(comptime N: usize) NodalDerivs {
    var nodal_derivs = NodalDerivs{
        .dNu = [_][9]f64{[_]f64{0} ** 9} ** 9,
        .dNv = [_][9]f64{[_]f64{0} ** 9} ** 9,
    };
    const node_coords = switch (N) {
        3 => [3][2]f64{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 },
        },
        4 => [4][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
        },
        6 => [6][2]f64{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 0.5, 0 }, .{ 0.5, 0.5 }, .{ 0, 0.5 },
        },
        8 => [8][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
            .{ 0, -1 },  .{ 1, 0 },  .{ 0, 1 }, .{ -1, 0 },
        },
        9 => [9][2]f64{
            .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
            .{ 0, -1 },  .{ 1, 0 },  .{ 0, 1 }, .{ -1, 0 },
            .{ 0, 0 },
        },
        else => return nodal_derivs,
    };

    for (0..N) |ii| {
        var n_v: [N]f64 = undefined;
        var dNu: [N]f64 = undefined;
        var dNv: [N]f64 = undefined;
        shapeFunctions(N, node_coords[ii][0], node_coords[ii][1], &n_v, &dNu, &dNv);
        for (0..N) |jj| {
            nodal_derivs.dNu[ii][jj] = dNu[jj];
            nodal_derivs.dNv[ii][jj] = dNv[jj];
        }
    }

    return nodal_derivs;
}

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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[N]VecSF,
    v_dN_dxi: *[N]VecSF,
    v_dN_deta: *[N]VecSF,
) void {
    switch (N) {
        3 => shapeFunctions3SIMD(
            v_xi,
            v_eta,
            v_shape_vals,
            v_dN_dxi,
            v_dN_deta,
        ),
        4 => shapeFunctions4SIMD(
            v_xi,
            v_eta,
            v_shape_vals,
            v_dN_dxi,
            v_dN_deta,
        ),
        6 => shapeFunctions6SIMD(
            v_xi,
            v_eta,
            v_shape_vals,
            v_dN_dxi,
            v_dN_deta,
        ),
        8 => shapeFunctions8SIMD(
            v_xi,
            v_eta,
            v_shape_vals,
            v_dN_dxi,
            v_dN_deta,
        ),
        9 => shapeFunctions9SIMD(
            v_xi,
            v_eta,
            v_shape_vals,
            v_dN_dxi,
            v_dN_deta,
        ),
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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[3]VecSF,
    v_dN_dxi: *[3]VecSF,
    v_dN_deta: *[3]VecSF,
) void {
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_zero: VecSF = @splat(0.0);
    const v_splat_neg_one: VecSF = @splat(-1.0);

    const v_L1 = v_splat_one - v_xi - v_eta;
    const v_L2 = v_xi;
    const v_L3 = v_eta;

    v_shape_vals[0] = v_L1;
    v_shape_vals[1] = v_L2;
    v_shape_vals[2] = v_L3;

    v_dN_dxi[0] = v_splat_neg_one;
    v_dN_dxi[1] = v_splat_one;
    v_dN_dxi[2] = v_splat_zero;

    v_dN_deta[0] = v_splat_neg_one;
    v_dN_deta[1] = v_splat_zero;
    v_dN_deta[2] = v_splat_one;
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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[4]VecSF,
    v_dN_dxi: *[4]VecSF,
    v_dN_deta: *[4]VecSF,
) void {
    const v_splat_quarter: VecSF = @splat(0.25);
    const v_splat_neg_quarter: VecSF = @splat(-0.25);
    const v_splat_one: VecSF = @splat(1.0);

    const v_one_minus_xi = v_splat_one - v_xi;
    const v_one_plus_xi = v_splat_one + v_xi;
    const v_one_minus_eta = v_splat_one - v_eta;
    const v_one_plus_eta = v_splat_one + v_eta;

    v_shape_vals[0] = v_splat_quarter * v_one_minus_xi * v_one_minus_eta;
    v_shape_vals[1] = v_splat_quarter * v_one_plus_xi * v_one_minus_eta;
    v_shape_vals[2] = v_splat_quarter * v_one_plus_xi * v_one_plus_eta;
    v_shape_vals[3] = v_splat_quarter * v_one_minus_xi * v_one_plus_eta;

    v_dN_dxi[0] = v_splat_neg_quarter * v_one_minus_eta;
    v_dN_dxi[1] = v_splat_quarter * v_one_minus_eta;
    v_dN_dxi[2] = v_splat_quarter * v_one_plus_eta;
    v_dN_dxi[3] = v_splat_neg_quarter * v_one_plus_eta;

    v_dN_deta[0] = v_splat_neg_quarter * v_one_minus_xi;
    v_dN_deta[1] = v_splat_neg_quarter * v_one_plus_xi;
    v_dN_deta[2] = v_splat_quarter * v_one_plus_xi;
    v_dN_deta[3] = v_splat_quarter * v_one_minus_xi;
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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[6]VecSF,
    v_dN_dxi: *[6]VecSF,
    v_dN_deta: *[6]VecSF,
) void {
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);
    const v_splat_four: VecSF = @splat(4.0);
    const v_splat_zero: VecSF = @splat(0.0);

    const v_L1 = v_splat_one - v_xi - v_eta;
    const v_L2 = v_xi;
    const v_L3 = v_eta;

    const v_four_L1_minus_one = v_splat_four * v_L1 - v_splat_one;
    const v_four_L2_minus_one = v_splat_four * v_L2 - v_splat_one;
    const v_four_L3_minus_one = v_splat_four * v_L3 - v_splat_one;

    v_shape_vals[0] = v_L1 * (v_splat_two * v_L1 - v_splat_one);
    v_dN_dxi[0] = -v_four_L1_minus_one;
    v_dN_deta[0] = -v_four_L1_minus_one;

    v_shape_vals[1] = v_L2 * (v_splat_two * v_L2 - v_splat_one);
    v_dN_dxi[1] = v_four_L2_minus_one;
    v_dN_deta[1] = v_splat_zero;

    v_shape_vals[2] = v_L3 * (v_splat_two * v_L3 - v_splat_one);
    v_dN_dxi[2] = v_splat_zero;
    v_dN_deta[2] = v_four_L3_minus_one;

    v_shape_vals[3] = v_splat_four * v_L1 * v_L2;
    v_dN_dxi[3] = v_splat_four * (v_L1 - v_L2);
    v_dN_deta[3] = -v_splat_four * v_L2;

    v_shape_vals[4] = v_splat_four * v_L2 * v_L3;
    v_dN_dxi[4] = v_splat_four * v_L3;
    v_dN_deta[4] = v_splat_four * v_L2;

    v_shape_vals[5] = v_splat_four * v_L3 * v_L1;
    v_dN_dxi[5] = -v_splat_four * v_L3;
    v_dN_deta[5] = v_splat_four * (v_L1 - v_L3);
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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[8]VecSF,
    v_dN_dxi: *[8]VecSF,
    v_dN_deta: *[8]VecSF,
) void {
    const v_x = v_xi;
    const v_y = v_eta;
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);
    const v_splat_half: VecSF = @splat(0.5);
    const v_splat_neg_half: VecSF = @splat(-0.5);
    const v_splat_quarter: VecSF = @splat(0.25);
    const v_splat_neg_quarter: VecSF = @splat(-0.25);

    const v_x_sq = v_x * v_x;
    const v_y_sq = v_y * v_y;
    const v_one_minus_x = v_splat_one - v_x;
    const v_one_plus_x = v_splat_one + v_x;
    const v_one_minus_y = v_splat_one - v_y;
    const v_one_plus_y = v_splat_one + v_y;

    v_shape_vals[0] =
        v_splat_neg_quarter * v_one_minus_x * v_one_minus_y *
        (v_splat_one + v_x + v_y);
    v_shape_vals[1] =
        v_splat_neg_quarter * v_one_plus_x * v_one_minus_y *
        (v_splat_one - v_x + v_y);
    v_shape_vals[2] =
        v_splat_neg_quarter * v_one_plus_x * v_one_plus_y *
        (v_splat_one - v_x - v_y);
    v_shape_vals[3] =
        v_splat_neg_quarter * v_one_minus_x * v_one_plus_y *
        (v_splat_one + v_x - v_y);
    v_shape_vals[4] = v_splat_half * (v_splat_one - v_x_sq) * v_one_minus_y;
    v_shape_vals[5] = v_splat_half * v_one_plus_x * (v_splat_one - v_y_sq);
    v_shape_vals[6] = v_splat_half * (v_splat_one - v_x_sq) * v_one_plus_y;
    v_shape_vals[7] = v_splat_half * v_one_minus_x * (v_splat_one - v_y_sq);

    const v_two_x = v_splat_two * v_x;
    const v_two_y = v_splat_two * v_y;
    const v_one_minus_y_sq = v_splat_one - v_y_sq;
    const v_one_minus_x_sq = v_splat_one - v_x_sq;

    v_dN_dxi[0] = v_splat_quarter * v_one_minus_y * (v_two_x + v_y);
    v_dN_dxi[1] = v_splat_quarter * v_one_minus_y * (v_two_x - v_y);
    v_dN_dxi[2] = v_splat_quarter * v_one_plus_y * (v_two_x + v_y);
    v_dN_dxi[3] = v_splat_quarter * v_one_plus_y * (v_two_x - v_y);
    v_dN_dxi[4] = -v_x * v_one_minus_y;
    v_dN_dxi[5] = v_splat_half * v_one_minus_y_sq;
    v_dN_dxi[6] = -v_x * v_one_plus_y;
    v_dN_dxi[7] = v_splat_neg_half * v_one_minus_y_sq;

    v_dN_deta[0] = v_splat_quarter * v_one_minus_x * (v_x + v_two_y);
    v_dN_deta[1] = v_splat_quarter * v_one_plus_x * (v_two_y - v_x);
    v_dN_deta[2] = v_splat_quarter * v_one_plus_x * (v_x + v_two_y);
    v_dN_deta[3] = v_splat_quarter * v_one_minus_x * (v_two_y - v_x);
    v_dN_deta[4] = v_splat_neg_half * v_one_minus_x_sq;
    v_dN_deta[5] = -v_y * v_one_plus_x;
    v_dN_deta[6] = v_splat_half * v_one_minus_x_sq;
    v_dN_deta[7] = -v_y * v_one_minus_x;
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
    v_xi: VecSF,
    v_eta: VecSF,
    v_shape_vals: *[9]VecSF,
    v_dN_dxi: *[9]VecSF,
    v_dN_deta: *[9]VecSF,
) void {
    const v_x = v_xi;
    const v_y = v_eta;
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_half: VecSF = @splat(0.5);
    const v_splat_neg_two: VecSF = @splat(-2.0);

    const v_x_minus_one = v_x - v_splat_one;
    const v_x_plus_one = v_x + v_splat_one;
    const v_y_minus_one = v_y - v_splat_one;
    const v_y_plus_one = v_y + v_splat_one;

    const v_phi = [3]VecSF{
        v_splat_half * v_x * v_x_minus_one,
        v_splat_one - v_x * v_x,
        v_splat_half * v_x * v_x_plus_one,
    };
    const v_psi = [3]VecSF{
        v_splat_half * v_y * v_y_minus_one,
        v_splat_one - v_y * v_y,
        v_splat_half * v_y * v_y_plus_one,
    };
    const v_dphi = [3]VecSF{
        v_x - v_splat_half,
        v_splat_neg_two * v_x,
        v_x + v_splat_half,
    };
    const v_dpsi = [3]VecSF{
        v_y - v_splat_half,
        v_splat_neg_two * v_y,
        v_y + v_splat_half,
    };

    v_shape_vals[0] = v_phi[0] * v_psi[0];
    v_shape_vals[1] = v_phi[2] * v_psi[0];
    v_shape_vals[2] = v_phi[2] * v_psi[2];
    v_shape_vals[3] = v_phi[0] * v_psi[2];
    v_shape_vals[4] = v_phi[1] * v_psi[0];
    v_shape_vals[5] = v_phi[2] * v_psi[1];
    v_shape_vals[6] = v_phi[1] * v_psi[2];
    v_shape_vals[7] = v_phi[0] * v_psi[1];
    v_shape_vals[8] = v_phi[1] * v_psi[1];

    v_dN_dxi[0] = v_dphi[0] * v_psi[0];
    v_dN_dxi[1] = v_dphi[2] * v_psi[0];
    v_dN_dxi[2] = v_dphi[2] * v_psi[2];
    v_dN_dxi[3] = v_dphi[0] * v_psi[2];
    v_dN_dxi[4] = v_dphi[1] * v_psi[0];
    v_dN_dxi[5] = v_dphi[2] * v_psi[1];
    v_dN_dxi[6] = v_dphi[1] * v_psi[2];
    v_dN_dxi[7] = v_dphi[0] * v_psi[1];
    v_dN_dxi[8] = v_dphi[1] * v_psi[1];

    v_dN_deta[0] = v_phi[0] * v_dpsi[0];
    v_dN_deta[1] = v_phi[2] * v_dpsi[0];
    v_dN_deta[2] = v_phi[2] * v_dpsi[2];
    v_dN_deta[3] = v_phi[0] * v_dpsi[2];
    v_dN_deta[4] = v_phi[1] * v_dpsi[0];
    v_dN_deta[5] = v_phi[2] * v_dpsi[1];
    v_dN_deta[6] = v_phi[1] * v_dpsi[2];
    v_dN_deta[7] = v_phi[0] * v_dpsi[1];
    v_dN_deta[8] = v_phi[1] * v_dpsi[1];
}
