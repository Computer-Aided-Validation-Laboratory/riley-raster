// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

const common = @import("cameramodels_common.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const tol = cfg.tol;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const DistortionForwardJacSIMDResult = struct {
    coords: DistortionCoordsSIMD,
    jac: DistortionJacSIMD,
};

pub const DistortionCoordsSIMD = struct {
    x: VecSF,
    y: VecSF,
};

/// SIMD Jacobian storage deliberately remains four vectors rather than a stack
/// matrix: each field is consumed as a SIMD register in the Newton hot path.
pub const DistortionJacSIMD = struct {
    xx: VecSF,
    xy: VecSF,
    yx: VecSF,
    yy: VecSF,
};

pub const BrownConradySIMD = struct {
    pub const Params = common.BrownConradyParams;

    pub inline fn forward(params: Params, x: VecSF, y: VecSF) DistortionCoordsSIMD {
        const result = forwardDistortionSIMD(Params, params, x, y);
        return result;
    }

    pub inline fn forwardWithJac(
        params: Params,
        x: VecSF,
        y: VecSF,
    ) DistortionForwardJacSIMDResult {
        return forwardDistortionWithJacSIMD(Params, params, x, y);
    }

    pub inline fn inv(
        params: Params,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortionCoordsSIMD {
        return invDistortionSIMD(Params, params, x_d, y_d, active);
    }
};

pub const BrownConradyExtSIMD = struct {
    pub const Params = common.BrownConradyExt.Params;
    pub const Model = common.BrownConradyExt;

    pub inline fn forward(model: Model, x: VecSF, y: VecSF) DistortionCoordsSIMD {
        const result = forwardDistortionSIMD(Model, model, x, y);
        return result;
    }

    pub inline fn forwardWithJac(
        model: Model,
        x: VecSF,
        y: VecSF,
    ) DistortionForwardJacSIMDResult {
        return forwardDistortionWithJacSIMD(Model, model, x, y);
    }

    pub inline fn inv(
        model: Model,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortionCoordsSIMD {
        return invDistortionSIMD(Model, model, x_d, y_d, active);
    }
};

pub const PolynomialMapSIMD = struct {
    pub const Params = common.PolynomialMap;

    pub inline fn forward(params: Params, x: VecSF, y: VecSF) DistortionCoordsSIMD {
        return evaluatePolynomialMapSIMD(params, x, y);
    }

    pub inline fn forwardWithJac(
        params: Params,
        x: VecSF,
        y: VecSF,
    ) DistortionForwardJacSIMDResult {
        return evaluatePolynomialMapWithJacSIMD(params, x, y);
    }

    pub inline fn inv(
        params: Params,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortionCoordsSIMD {
        return invertPolynomialMapSIMD(params, x_d, y_d, active);
    }
};

pub const BidirectionalPolynomialSIMD = struct {
    pub const Params = common.BidirectionalPolynomial;

    pub inline fn forward(params: Params, x: VecSF, y: VecSF) !DistortionCoordsSIMD {
        if (params.forward_map) |map| return PolynomialMapSIMD.forward(map, x, y);
        return error.MissingPolynomialMap;
    }

    pub inline fn inv(
        params: Params,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortionCoordsSIMD {
        return invPolynomialSIMD(params, x_d, y_d, active);
    }
};

// --------------------------------------------------------------------------------------
// Brown Conrady
// --------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn forwardDistortionSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    x: VecSF,
    y: VecSF,
) DistortionCoordsSIMD {
    const fwd = forwardDistortionWithJacSIMD(
        DistortionType,
        distortion,
        x,
        y,
    );
    return .{
        .x = fwd.coords.x,
        .y = fwd.coords.y,
    };
}

pub fn forwardDistortionWithJacSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    x: VecSF,
    y: VecSF,
) DistortionForwardJacSIMDResult {
    const params = if (DistortionType == common.BrownConradyExt) distortion.params else distortion;
    const r2 = x * x + y * y;
    const r4 = r2 * r2;
    const r6 = r4 * r2;

    const radial_and_deriv = if (DistortionType == common.BrownConradyExt) blk: {
        const numerator = @as(VecSF, @splat(1.0)) +
            @as(VecSF, @splat(params.k1)) * r2 +
            @as(VecSF, @splat(params.k2)) * r4 +
            @as(VecSF, @splat(params.k3)) * r6;

        const denominator = @as(VecSF, @splat(1.0)) +
            @as(VecSF, @splat(params.k4)) * r2 +
            @as(VecSF, @splat(params.k5)) * r4 +
            @as(VecSF, @splat(params.k6)) * r6;

        const dnum_dr2 = @as(VecSF, @splat(params.k1)) +
            @as(VecSF, @splat(2.0 * params.k2)) * r2 +
            @as(VecSF, @splat(3.0 * params.k3)) * r4;

        const dden_dr2 = @as(VecSF, @splat(params.k4)) +
            @as(VecSF, @splat(2.0 * params.k5)) * r2 +
            @as(VecSF, @splat(3.0 * params.k6)) * r4;

        const radial_scale = numerator / denominator;
        const dradial_dr2 =
            (dnum_dr2 * denominator - numerator * dden_dr2) /
            (denominator * denominator);

        break :blk .{
            .radial_scale = radial_scale,
            .dradial_dr2 = dradial_dr2,
        };
    } else blk: {
        const radial_scale = @as(VecSF, @splat(1.0)) +
            @as(VecSF, @splat(params.k1)) * r2 +
            @as(VecSF, @splat(params.k2)) * r4 +
            @as(VecSF, @splat(params.k3)) * r6;

        const dradial_dr2 = @as(VecSF, @splat(params.k1)) +
            @as(VecSF, @splat(2.0 * params.k2)) * r2 +
            @as(VecSF, @splat(3.0 * params.k3)) * r4;

        break :blk .{
            .radial_scale = radial_scale,
            .dradial_dr2 = dradial_dr2,
        };
    };

    const radial_scale = radial_and_deriv.radial_scale;
    const dradial_dr2 = radial_and_deriv.dradial_dr2;
    const dradial_dx = dradial_dr2 * @as(VecSF, @splat(2.0)) * x;
    const dradial_dy = dradial_dr2 * @as(VecSF, @splat(2.0)) * y;
    const p1: VecSF = @splat(params.p1);
    const p2: VecSF = @splat(params.p2);

    var x_d = x * radial_scale + @as(VecSF, @splat(2.0)) * p1 * x * y +
        p2 * (r2 + @as(VecSF, @splat(2.0)) * x * x);
    var y_d = y * radial_scale + p1 * (r2 + @as(VecSF, @splat(2.0)) * y * y) +
        @as(VecSF, @splat(2.0)) * p2 * x * y;

    var j11 = radial_scale + x * dradial_dx +
        @as(VecSF, @splat(2.0)) * p1 * y +
        @as(VecSF, @splat(6.0)) * p2 * x;
    var j12 = x * dradial_dy +
        @as(VecSF, @splat(2.0)) * p1 * x +
        @as(VecSF, @splat(2.0)) * p2 * y;
    var j21 = y * dradial_dx +
        @as(VecSF, @splat(2.0)) * p1 * x +
        @as(VecSF, @splat(2.0)) * p2 * y;
    var j22 = radial_scale + y * dradial_dy +
        @as(VecSF, @splat(6.0)) * p1 * y +
        @as(VecSF, @splat(2.0)) * p2 * x;

    if (DistortionType == common.BrownConradyExt) {
        const s1: VecSF = @splat(params.s1);
        const s2: VecSF = @splat(params.s2);
        const s3: VecSF = @splat(params.s3);
        const s4: VecSF = @splat(params.s4);
        x_d += s1 * r2 + s2 * r4;
        y_d += s3 * r2 + s4 * r4;
        j11 += @as(VecSF, @splat(2.0)) * x *
            (s1 + @as(VecSF, @splat(2.0)) * s2 * r2);
        j12 += @as(VecSF, @splat(2.0)) * y *
            (s1 + @as(VecSF, @splat(2.0)) * s2 * r2);
        j21 += @as(VecSF, @splat(2.0)) * x *
            (s3 + @as(VecSF, @splat(2.0)) * s4 * r2);
        j22 += @as(VecSF, @splat(2.0)) * y *
            (s3 + @as(VecSF, @splat(2.0)) * s4 * r2);

        if (distortion.tilt) |projection| {
            const matrix = projection.forward_matrix;
            const mat = matrix.mat;
            const m00: VecSF = @splat(mat[0][0]);
            const m01: VecSF = @splat(mat[0][1]);
            const m02: VecSF = @splat(mat[0][2]);
            const m10: VecSF = @splat(mat[1][0]);
            const m11: VecSF = @splat(mat[1][1]);
            const m12: VecSF = @splat(mat[1][2]);
            const m20: VecSF = @splat(mat[2][0]);
            const m21: VecSF = @splat(mat[2][1]);
            const m22: VecSF = @splat(mat[2][2]);
            const numerator_x = m00 * x_d + m01 * y_d + m02;
            const numerator_y = m10 * x_d + m11 * y_d + m12;
            const denominator = m20 * x_d + m21 * y_d + m22;
            const inv_denominator = @as(VecSF, @splat(1.0)) / denominator;
            const inv_denominator_sq = inv_denominator * inv_denominator;
            const tilt_j11 = (m00 * denominator - numerator_x * m20) * inv_denominator_sq;
            const tilt_j12 = (m01 * denominator - numerator_x * m21) * inv_denominator_sq;
            const tilt_j21 = (m10 * denominator - numerator_y * m20) * inv_denominator_sq;
            const tilt_j22 = (m11 * denominator - numerator_y * m21) * inv_denominator_sq;
            const lens_j11 = j11;
            const lens_j12 = j12;
            const lens_j21 = j21;
            const lens_j22 = j22;
            j11 = tilt_j11 * lens_j11 + tilt_j12 * lens_j21;
            j12 = tilt_j11 * lens_j12 + tilt_j12 * lens_j22;
            j21 = tilt_j21 * lens_j11 + tilt_j22 * lens_j21;
            j22 = tilt_j21 * lens_j12 + tilt_j22 * lens_j22;
            x_d = numerator_x * inv_denominator;
            y_d = numerator_y * inv_denominator;
        }
    }

    return .{
        .coords = .{ .x = x_d, .y = y_d },
        .jac = .{ .xx = j11, .xy = j12, .yx = j21, .yy = j22 },
    };
}

pub fn invDistortionSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active_init: VecSB,
) !DistortionCoordsSIMD {
    const v_resid_tol: VecSF = @splat(tol.distortion.resid);
    const v_delta_tol: VecSF = @splat(tol.distortion.delta);
    const v_det_tol: VecSF = @splat(tol.distortion.det);

    var v_x = v_x_d;
    var v_y = v_y_d;
    var v_active = v_lane_active_init;

    for (0..cfg.distortion_newton_iter_max) |_| {
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const fwd = forwardDistortionWithJacSIMD(
            DistortionType,
            distortion,
            v_x,
            v_y,
        );
        const f0 = fwd.coords.x - v_x_d;
        const f1 = fwd.coords.y - v_y_d;

        const v_met_resid = (@abs(f0) < v_resid_tol) & (@abs(f1) < v_resid_tol);
        v_active = v_active & !v_met_resid;
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const v_det = fwd.jac.xx * fwd.jac.yy - fwd.jac.xy * fwd.jac.yx;
        const v_bad_det = @abs(v_det) < v_det_tol;
        if (@reduce(.Or, v_active & v_bad_det)) {
            return error.SingularJac;
        }

        const v_safe_det = @select(
            F,
            v_active,
            v_det,
            @as(VecSF, @splat(1.0)),
        );
        const v_delta_x = (-f0 * fwd.jac.yy + fwd.jac.xy * f1) / v_safe_det;
        const v_delta_y = (fwd.jac.yx * f0 - fwd.jac.xx * f1) / v_safe_det;

        v_x += @select(F, v_active, v_delta_x, @as(VecSF, @splat(0.0)));
        v_y += @select(F, v_active, v_delta_y, @as(VecSF, @splat(0.0)));

        const v_met_delta =
            (@abs(v_delta_x) < v_delta_tol) & (@abs(v_delta_y) < v_delta_tol);
        v_active = v_active & !v_met_delta;
    }

    if (@reduce(.Or, v_active)) {
        return error.DistortionInvFailed;
    }
    return .{ .x = v_x, .y = v_y };
}

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

fn invPolynomialSIMD(
    polynomial: common.BidirectionalPolynomial,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active: VecSB,
) !DistortionCoordsSIMD {
    if (polynomial.inv_map) |inv_map| {
        const eval = evaluatePolynomialMapSIMD(inv_map, v_x_d, v_y_d);
        return eval;
    }
    if (polynomial.forward_map) |forward_map| {
        return try invertPolynomialMapSIMD(
            forward_map,
            v_x_d,
            v_y_d,
            v_lane_active,
        );
    }
    return error.MissingPolynomialMap;
}

fn evaluatePolynomialMapSIMD(
    polynomial: common.PolynomialMap,
    x: VecSF,
    y: VecSF,
) DistortionCoordsSIMD {
    const poly = evaluatePolynomialMapWithJacSIMD(polynomial, x, y);
    return poly.coords;
}

fn evaluatePolynomialMapWithJacSIMD(
    polynomial: common.PolynomialMap,
    x: VecSF,
    y: VecSF,
) DistortionForwardJacSIMDResult {
    var du: VecSF = @splat(0.0);
    var dv: VecSF = @splat(0.0);
    var ddu_dx: VecSF = @splat(0.0);
    var ddu_dy: VecSF = @splat(0.0);
    var ddv_dx: VecSF = @splat(0.0);
    var ddv_dy: VecSF = @splat(0.0);
    const term_count = polynomial.order.termCount();

    for (0..term_count) |ii| {
        const pu = common.poly_powers_u[ii];
        const pv = common.poly_powers_v[ii];
        const basis = powSmallSIMD(x, pu) * powSmallSIMD(y, pv);
        du += @as(VecSF, @splat(polynomial.coeffs_u[ii])) * basis;
        dv += @as(VecSF, @splat(polynomial.coeffs_v[ii])) * basis;

        if (pu > 0) {
            const basis_dx = @as(VecSF, @splat(@as(F, @floatFromInt(pu)))) *
                powSmallSIMD(x, pu - 1) *
                powSmallSIMD(y, pv);
            ddu_dx += @as(VecSF, @splat(polynomial.coeffs_u[ii])) * basis_dx;
            ddv_dx += @as(VecSF, @splat(polynomial.coeffs_v[ii])) * basis_dx;
        }
        if (pv > 0) {
            const basis_dy = @as(VecSF, @splat(@as(F, @floatFromInt(pv)))) *
                powSmallSIMD(x, pu) *
                powSmallSIMD(y, pv - 1);
            ddu_dy += @as(VecSF, @splat(polynomial.coeffs_u[ii])) * basis_dy;
            ddv_dy += @as(VecSF, @splat(polynomial.coeffs_v[ii])) * basis_dy;
        }
    }

    return .{
        .coords = .{ .x = x + du, .y = y + dv },
        .jac = .{
            .xx = @as(VecSF, @splat(1.0)) + ddu_dx,
            .xy = ddu_dy,
            .yx = ddv_dx,
            .yy = @as(VecSF, @splat(1.0)) + ddv_dy,
        },
    };
}

fn invertPolynomialMapSIMD(
    polynomial: common.PolynomialMap,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active_init: VecSB,
) !DistortionCoordsSIMD {
    const v_resid_tol: VecSF = @splat(tol.distortion.resid);
    const v_delta_tol: VecSF = @splat(tol.distortion.delta);
    const v_det_tol: VecSF = @splat(tol.distortion.det);

    var v_x = v_x_d;
    var v_y = v_y_d;
    var v_active = v_lane_active_init;

    for (0..cfg.distortion_newton_iter_max) |_| {
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const fwd = evaluatePolynomialMapWithJacSIMD(polynomial, v_x, v_y);
        const f0 = fwd.coords.x - v_x_d;
        const f1 = fwd.coords.y - v_y_d;

        const v_met_resid = (@abs(f0) < v_resid_tol) & (@abs(f1) < v_resid_tol);
        v_active = v_active & !v_met_resid;
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const v_det = fwd.jac.xx * fwd.jac.yy - fwd.jac.xy * fwd.jac.yx;
        const v_bad_det = @abs(v_det) < v_det_tol;
        if (@reduce(.Or, v_active & v_bad_det)) {
            return error.SingularJac;
        }

        const v_safe_det = @select(
            F,
            v_active,
            v_det,
            @as(VecSF, @splat(1.0)),
        );
        const v_delta_x = (-f0 * fwd.jac.yy + fwd.jac.xy * f1) / v_safe_det;
        const v_delta_y = (fwd.jac.yx * f0 - fwd.jac.xx * f1) / v_safe_det;

        v_x += @select(F, v_active, v_delta_x, @as(VecSF, @splat(0.0)));
        v_y += @select(F, v_active, v_delta_y, @as(VecSF, @splat(0.0)));

        const v_met_delta =
            (@abs(v_delta_x) < v_delta_tol) & (@abs(v_delta_y) < v_delta_tol);
        v_active = v_active & !v_met_delta;
    }

    if (@reduce(.Or, v_active)) {
        return error.DistortionInvFailed;
    }
    return .{ .x = v_x, .y = v_y };
}

fn powSmallSIMD(
    x: VecSF,
    power: u8,
) VecSF {
    var out: VecSF = @splat(1.0);
    for (0..power) |_| {
        out *= x;
    }
    return out;
}

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortionModel = common.DistortionModel;

/// Explicit model dispatch keeps the tagged-union boundary visible to callers;
/// the selected evaluator is fully resolved at compile time inside each arm.
pub fn forwardDistortionModelSIMD(
    distortion: DistortionModel,
    x: VecSF,
    y: VecSF,
) !DistortionCoordsSIMD {
    return switch (distortion) {
        .none => .{ .x = x, .y = y },
        .brown_conrady => |params| BrownConradySIMD.forward(params, x, y),
        .brown_conrady_ext => |params| BrownConradyExtSIMD.forward(params, x, y),
        .polynomial => |params| BidirectionalPolynomialSIMD.forward(params, x, y),
        .brown_conrady_polynomial => |chain| blk: {
            const brown = BrownConradySIMD.forward(chain.brown_conrady, x, y);
            break :blk try BidirectionalPolynomialSIMD.forward(
                chain.polynomial,
                brown.x,
                brown.y,
            );
        },
        .brown_conrady_ext_polynomial => |chain| blk: {
            const brown = BrownConradyExtSIMD.forward(chain.brown_conrady_ext, x, y);
            break :blk try BidirectionalPolynomialSIMD.forward(
                chain.polynomial,
                brown.x,
                brown.y,
            );
        },
    };
}

fn removeTiltSIMD(
    distortion: common.BrownConradyExt,
    x_d: VecSF,
    y_d: VecSF,
    lane_active: VecSB,
) !struct { x: VecSF, y: VecSF } {
    const projection = distortion.tilt orelse return .{ .x = x_d, .y = y_d };
    const matrix = projection.inverse_matrix;
    const mat = matrix.mat;
    const m00: VecSF = @splat(mat[0][0]);
    const m01: VecSF = @splat(mat[0][1]);
    const m02: VecSF = @splat(mat[0][2]);
    const m10: VecSF = @splat(mat[1][0]);
    const m11: VecSF = @splat(mat[1][1]);
    const m12: VecSF = @splat(mat[1][2]);
    const m20: VecSF = @splat(mat[2][0]);
    const m21: VecSF = @splat(mat[2][1]);
    const m22: VecSF = @splat(mat[2][2]);
    const numerator_x = m00 * x_d + m01 * y_d + m02;
    const numerator_y = m10 * x_d + m11 * y_d + m12;
    const denominator = m20 * x_d + m21 * y_d + m22;
    const singular = @abs(denominator) < @as(VecSF, @splat(tol.distortion.det));
    if (@reduce(.Or, lane_active & singular)) {
        return error.SingularTiltProjection;
    }
    const inv_denominator = @as(VecSF, @splat(1.0)) / denominator;
    return .{
        .x = numerator_x * inv_denominator,
        .y = numerator_y * inv_denominator,
    };
}

fn invBrownConradyExtSIMD(
    distortion: common.BrownConradyExt,
    x_d: VecSF,
    y_d: VecSF,
    lane_active: VecSB,
) !DistortionCoordsSIMD {
    const untilted = try removeTiltSIMD(distortion, x_d, y_d, lane_active);
    const lens = common.BrownConradyExt{ .params = distortion.params };
    return invDistortionSIMD(
        common.BrownConradyExt,
        lens,
        untilted.x,
        untilted.y,
        lane_active,
    );
}

pub fn invDistortionModelSIMD(
    distortion: DistortionModel,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active: VecSB,
) !DistortionCoordsSIMD {
    return switch (distortion) {
        .none => .{ .x = v_x_d, .y = v_y_d },
        .brown_conrady => |bc| invDistortionSIMD(
            common.BrownConrady.Params,
            bc,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .brown_conrady_ext => |bc_ext| invBrownConradyExtSIMD(
            bc_ext,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .polynomial => |poly| invPolynomialSIMD(
            poly,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .brown_conrady_polynomial => |chain| blk: {
            const poly_inv = try invPolynomialSIMD(
                chain.polynomial,
                v_x_d,
                v_y_d,
                v_lane_active,
            );
            break :blk try invDistortionSIMD(
                common.BrownConrady.Params,
                chain.brown_conrady,
                poly_inv.x,
                poly_inv.y,
                v_lane_active,
            );
        },
        .brown_conrady_ext_polynomial => |chain| blk: {
            const poly_inv = try invPolynomialSIMD(
                chain.polynomial,
                v_x_d,
                v_y_d,
                v_lane_active,
            );
            break :blk try invBrownConradyExtSIMD(
                chain.brown_conrady_ext,
                poly_inv.x,
                poly_inv.y,
                v_lane_active,
            );
        },
    };
}
