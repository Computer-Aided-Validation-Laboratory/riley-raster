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

const common = @import("cameramodels_common.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const tol = cfg.tolerance;

pub const DistortionForwardJacSIMDResult = struct {
    x_d: VecSF,
    y_d: VecSF,
    j11: VecSF,
    j12: VecSF,
    j21: VecSF,
    j22: VecSF,
};

pub fn forwardDistortionSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    x: VecSF,
    y: VecSF,
) struct { x_d: VecSF, y_d: VecSF } {
    const fwd = forwardDistortionWithJacSIMD(
        DistortionType,
        distortion,
        x,
        y,
    );
    return .{
        .x_d = fwd.x_d,
        .y_d = fwd.y_d,
    };
}

pub fn forwardDistortionWithJacSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    x: VecSF,
    y: VecSF,
) DistortionForwardJacSIMDResult {
    const r2 = x * x + y * y;
    const r4 = r2 * r2;
    const r6 = r4 * r2;

    const radial_and_deriv = if (@hasField(DistortionType, "k4")) blk: {
        const numerator = @as(VecSF, @splat(1.0)) +
            @as(VecSF, @splat(distortion.k1)) * r2 +
            @as(VecSF, @splat(distortion.k2)) * r4 +
            @as(VecSF, @splat(distortion.k3)) * r6;

        const denominator = @as(VecSF, @splat(1.0)) +
            @as(VecSF, @splat(distortion.k4)) * r2 +
            @as(VecSF, @splat(distortion.k5)) * r4 +
            @as(VecSF, @splat(distortion.k6)) * r6;

        const dnum_dr2 = @as(VecSF, @splat(distortion.k1)) +
            @as(VecSF, @splat(2.0 * distortion.k2)) * r2 +
            @as(VecSF, @splat(3.0 * distortion.k3)) * r4;

        const dden_dr2 = @as(VecSF, @splat(distortion.k4)) +
            @as(VecSF, @splat(2.0 * distortion.k5)) * r2 +
            @as(VecSF, @splat(3.0 * distortion.k6)) * r4;

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
            @as(VecSF, @splat(distortion.k1)) * r2 +
            @as(VecSF, @splat(distortion.k2)) * r4 +
            @as(VecSF, @splat(distortion.k3)) * r6;

        const dradial_dr2 = @as(VecSF, @splat(distortion.k1)) +
            @as(VecSF, @splat(2.0 * distortion.k2)) * r2 +
            @as(VecSF, @splat(3.0 * distortion.k3)) * r4;

        break :blk .{
            .radial_scale = radial_scale,
            .dradial_dr2 = dradial_dr2,
        };
    };

    const radial_scale = radial_and_deriv.radial_scale;
    const dradial_dr2 = radial_and_deriv.dradial_dr2;
    const dradial_dx = dradial_dr2 * @as(VecSF, @splat(2.0)) * x;
    const dradial_dy = dradial_dr2 * @as(VecSF, @splat(2.0)) * y;
    const p1: VecSF = @splat(distortion.p1);
    const p2: VecSF = @splat(distortion.p2);

    const x_d = x * radial_scale + @as(VecSF, @splat(2.0)) * p1 * x * y +
        p2 * (r2 + @as(VecSF, @splat(2.0)) * x * x);
    const y_d = y * radial_scale + p1 * (r2 + @as(VecSF, @splat(2.0)) * y * y) +
        @as(VecSF, @splat(2.0)) * p2 * x * y;

    const j11 = radial_scale + x * dradial_dx +
        @as(VecSF, @splat(2.0)) * p1 * y +
        @as(VecSF, @splat(6.0)) * p2 * x;
    const j12 = x * dradial_dy +
        @as(VecSF, @splat(2.0)) * p1 * x +
        @as(VecSF, @splat(2.0)) * p2 * y;
    const j21 = y * dradial_dx +
        @as(VecSF, @splat(2.0)) * p1 * x +
        @as(VecSF, @splat(2.0)) * p2 * y;
    const j22 = radial_scale + y * dradial_dy +
        @as(VecSF, @splat(6.0)) * p1 * y +
        @as(VecSF, @splat(2.0)) * p2 * x;

    return .{
        .x_d = x_d,
        .y_d = y_d,
        .j11 = j11,
        .j12 = j12,
        .j21 = j21,
        .j22 = j22,
    };
}

pub fn inverseDistortionSIMD(
    comptime DistortionType: type,
    distortion: DistortionType,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active_init: VecSB,
) !struct { x: VecSF, y: VecSF } {
    const v_resid_tol: VecSF = @splat(tol.distortion.residual);
    const v_delta_tol: VecSF = @splat(tol.distortion.delta);
    const v_det_tol: VecSF = @splat(tol.distortion.determinant);

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
        const f0 = fwd.x_d - v_x_d;
        const f1 = fwd.y_d - v_y_d;

        const v_met_resid = (@abs(f0) < v_resid_tol) & (@abs(f1) < v_resid_tol);
        v_active = v_active & !v_met_resid;
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const v_det = fwd.j11 * fwd.j22 - fwd.j12 * fwd.j21;
        const v_bad_det = @abs(v_det) < v_det_tol;
        if (@reduce(.Or, v_active & v_bad_det)) {
            return error.SingularJacobian;
        }

        const v_safe_det = @select(
            f64,
            v_active,
            v_det,
            @as(VecSF, @splat(1.0)),
        );
        const v_delta_x = (-f0 * fwd.j22 + fwd.j12 * f1) / v_safe_det;
        const v_delta_y = (fwd.j21 * f0 - fwd.j11 * f1) / v_safe_det;

        v_x += @select(f64, v_active, v_delta_x, @as(VecSF, @splat(0.0)));
        v_y += @select(f64, v_active, v_delta_y, @as(VecSF, @splat(0.0)));

        const v_met_delta =
            (@abs(v_delta_x) < v_delta_tol) & (@abs(v_delta_y) < v_delta_tol);
        v_active = v_active & !v_met_delta;
    }

    if (@reduce(.Or, v_active)) {
        return error.DistortionInverseFailed;
    }
    return .{ .x = v_x, .y = v_y };
}

pub const DistortionModel = common.DistortionModel;
