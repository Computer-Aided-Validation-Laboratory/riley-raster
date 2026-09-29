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

pub const DistortFordJacSIMDResult = struct {
    coords: DistortCoordsSIMD,
    jac: DistortJacSIMD,
};

pub const DistortCoordsSIMD = struct {
    x: VecSF,
    y: VecSF,
};

pub const DistortJacSIMD = struct {
    xx: VecSF,
    xy: VecSF,
    yx: VecSF,
    yy: VecSF,
};

pub const BrownConSIMD = struct {
    pub const Params = common.BrownConParams;

    pub inline fn ford(params: Params, x: VecSF, y: VecSF) DistortCoordsSIMD {
        const result = fordDistortSIMD(Params, params, x, y);
        return result;
    }

    pub inline fn fordWithJac(
        params: Params,
        x: VecSF,
        y: VecSF,
    ) DistortFordJacSIMDResult {
        return fordDistortWithJacSIMD(Params, params, x, y);
    }

    pub inline fn inv(
        params: Params,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortCoordsSIMD {
        return invDistortSIMD(Params, params, x_d, y_d, active);
    }
};

pub const BrownConExtSIMD = struct {
    pub const Params = common.BrownConExt.Params;
    pub const Model = common.BrownConExt;

    pub inline fn ford(model: Model, x: VecSF, y: VecSF) DistortCoordsSIMD {
        const result = fordDistortSIMD(Model, model, x, y);
        return result;
    }

    pub inline fn fordWithJac(
        model: Model,
        x: VecSF,
        y: VecSF,
    ) DistortFordJacSIMDResult {
        return fordDistortWithJacSIMD(Model, model, x, y);
    }

    pub inline fn inv(
        model: Model,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortCoordsSIMD {
        return invDistortSIMD(Model, model, x_d, y_d, active);
    }
};

pub const PolyMapSIMD = struct {
    pub const Params = common.PolyMap;

    pub inline fn ford(params: Params, x: VecSF, y: VecSF) DistortCoordsSIMD {
        return evaluatePolyMapSIMD(params, x, y);
    }

    pub inline fn fordWithJac(
        params: Params,
        x: VecSF,
        y: VecSF,
    ) DistortFordJacSIMDResult {
        return evaluatePolyMapWithJacSIMD(params, x, y);
    }

    pub inline fn inv(
        params: Params,
        x_d: VecSF,
        y_d: VecSF,
        active: VecSB,
    ) !DistortCoordsSIMD {
        return invPolySIMD(params, x_d, y_d, active);
    }
};

pub fn fordDistortSIMD(
    comptime DistortType: type,
    distort: DistortType,
    x: VecSF,
    y: VecSF,
) DistortCoordsSIMD {
    const fwd = fordDistortWithJacSIMD(
        DistortType,
        distort,
        x,
        y,
    );
    return .{
        .x = fwd.coords.x,
        .y = fwd.coords.y,
    };
}

pub fn fordDistortWithJacSIMD(
    comptime DistortType: type,
    distort: DistortType,
    x: VecSF,
    y: VecSF,
) DistortFordJacSIMDResult {
    const params = if (DistortType == common.BrownConExt)
        distort.params
    else
        distort;
    const r2 = x * x + y * y;
    const r4 = r2 * r2;
    const r6 = r4 * r2;

    const radial_and_deriv = if (DistortType == common.BrownConExt) blk: {
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

    if (DistortType == common.BrownConExt) {
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

        if (distort.tilt) |projection| {
            const matrix = projection.ford_matrix;
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

pub fn invDistortSIMD(
    comptime DistortType: type,
    distort: DistortType,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active_init: VecSB,
) !DistortCoordsSIMD {
    const v_resid_tol: VecSF = @splat(tol.distort.resid);
    const v_det_tol: VecSF = @splat(tol.distort.det);

    if (@reduce(.Or, v_lane_active_init &
        (!isFiniteSIMD(v_x_d) | !isFiniteSIMD(v_y_d)))) return error.NonFiniteDistort;
    var v_x = v_x_d;
    var v_y = v_y_d;
    var v_active = v_lane_active_init;

    for (0..cfg.distort_newton_iter_max + 1) |iteration| {
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const fwd = fordDistortWithJacSIMD(
            DistortType,
            distort,
            v_x,
            v_y,
        );
        const f0 = fwd.coords.x - v_x_d;
        const f1 = fwd.coords.y - v_y_d;

        if (@reduce(.Or, v_active & (!isFiniteSIMD(f0) | !isFiniteSIMD(f1))))
            return error.NonFiniteDistort;
        const v_met_resid = (@abs(f0) < v_resid_tol) & (@abs(f1) < v_resid_tol);
        v_active = v_active & !v_met_resid;
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        if (iteration == cfg.distort_newton_iter_max) break;
        const finite_jac = isFiniteSIMD(fwd.jac.xx) & isFiniteSIMD(fwd.jac.xy) &
            isFiniteSIMD(fwd.jac.yx) & isFiniteSIMD(fwd.jac.yy);
        if (@reduce(.Or, v_active & !finite_jac)) return error.NonFiniteDistort;
        const v_det = fwd.jac.xx * fwd.jac.yy - fwd.jac.xy * fwd.jac.yx;
        if (@reduce(.Or, v_active & !isFiniteSIMD(v_det))) return error.NonFiniteDistort;
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

        if (@reduce(.Or, v_active & (!isFiniteSIMD(v_x) | !isFiniteSIMD(v_y))))
            return error.NonFiniteDistort;
    }

    if (@reduce(.Or, v_active)) {
        return error.DistortInvFailed;
    }
    return .{ .x = v_x, .y = v_y };
}

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

fn evaluatePolyMapSIMD(poly: common.PolyMap, x: VecSF, y: VecSF) DistortCoordsSIMD {
    const result = common.evalPoly(VecSF, false, poly, x, y);
    return .{ .x = result.x, .y = result.y };
}

fn evaluatePolyMapWithJacSIMD(
    poly: common.PolyMap,
    x: VecSF,
    y: VecSF,
) DistortFordJacSIMDResult {
    const result = common.evalPoly(VecSF, true, poly, x, y);
    return .{
        .coords = .{ .x = result.x, .y = result.y },
        .jac = .{ .xx = result.xx, .xy = result.xy, .yx = result.yx, .yy = result.yy },
    };
}

fn invPolySIMD(
    poly: common.PolyMap,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active_init: VecSB,
) !DistortCoordsSIMD {
    const v_resid_tol: VecSF = @splat(tol.distort.resid);
    const v_det_tol: VecSF = @splat(tol.distort.det);

    if (@reduce(.Or, v_lane_active_init &
        (!isFiniteSIMD(v_x_d) | !isFiniteSIMD(v_y_d)))) return error.NonFiniteDistort;
    var v_x = v_x_d;
    var v_y = v_y_d;
    var v_active = v_lane_active_init;

    for (0..cfg.distort_newton_iter_max + 1) |iteration| {
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        const fwd = evaluatePolyMapWithJacSIMD(poly, v_x, v_y);
        const f0 = fwd.coords.x - v_x_d;
        const f1 = fwd.coords.y - v_y_d;

        if (@reduce(.Or, v_active & (!isFiniteSIMD(f0) | !isFiniteSIMD(f1))))
            return error.NonFiniteDistort;
        const v_met_resid = (@abs(f0) < v_resid_tol) & (@abs(f1) < v_resid_tol);
        v_active = v_active & !v_met_resid;
        if (!@reduce(.Or, v_active)) {
            return .{ .x = v_x, .y = v_y };
        }

        if (iteration == cfg.distort_newton_iter_max) break;
        const finite_jac = isFiniteSIMD(fwd.jac.xx) & isFiniteSIMD(fwd.jac.xy) &
            isFiniteSIMD(fwd.jac.yx) & isFiniteSIMD(fwd.jac.yy);
        if (@reduce(.Or, v_active & !finite_jac)) return error.NonFiniteDistort;
        const v_det = fwd.jac.xx * fwd.jac.yy - fwd.jac.xy * fwd.jac.yx;
        if (@reduce(.Or, v_active & !isFiniteSIMD(v_det))) return error.NonFiniteDistort;
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

        if (@reduce(.Or, v_active & (!isFiniteSIMD(v_x) | !isFiniteSIMD(v_y))))
            return error.NonFiniteDistort;
    }

    if (@reduce(.Or, v_active)) {
        return error.DistortInvFailed;
    }
    return .{ .x = v_x, .y = v_y };
}

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortModel = common.DistortModel;

/// Explicit model dispatch keeps the tagged-union boundary visible to callers;
/// the selected evaluator is fully resolved at compile time inside each arm.
pub fn fordDistortModelSIMD(
    distort: DistortModel,
    x: VecSF,
    y: VecSF,
) DistortCoordsSIMD {
    return switch (distort) {
        .none => .{ .x = x, .y = y },
        .brown_con => |params| BrownConSIMD.ford(params, x, y),
        .brown_con_ext => |params| BrownConExtSIMD.ford(params, x, y),
        .poly => |params| PolyMapSIMD.ford(params, x, y),
        .brown_con_poly => |chain| blk: {
            const brown = BrownConSIMD.ford(chain.brown_con, x, y);
            break :blk PolyMapSIMD.ford(
                chain.poly,
                brown.x,
                brown.y,
            );
        },
        .brown_con_ext_poly => |chain| blk: {
            const brown = BrownConExtSIMD.ford(chain.brown_con_ext, x, y);
            break :blk PolyMapSIMD.ford(
                chain.poly,
                brown.x,
                brown.y,
            );
        },
    };
}

fn removeTiltSIMD(
    distort: common.BrownConExt,
    x_d: VecSF,
    y_d: VecSF,
    lane_active: VecSB,
) !struct { x: VecSF, y: VecSF } {
    const projection = distort.tilt orelse return .{ .x = x_d, .y = y_d };

    const matrix = projection.inv_matrix;
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

    const singular = @abs(denominator) < @as(VecSF, @splat(tol.distort.det));

    if (@reduce(.Or, lane_active & singular)) {
        return error.SingularTiltProjection;
    }

    const inv_denominator = @as(VecSF, @splat(1.0)) / denominator;

    return .{
        .x = numerator_x * inv_denominator,
        .y = numerator_y * inv_denominator,
    };
}

fn invBrownConExtSIMD(
    distort: common.BrownConExt,
    x_d: VecSF,
    y_d: VecSF,
    lane_active: VecSB,
) !DistortCoordsSIMD {
    const untilted = try removeTiltSIMD(distort, x_d, y_d, lane_active);
    const lens = common.BrownConExt{ .params = distort.params };

    return invDistortSIMD(
        common.BrownConExt,
        lens,
        untilted.x,
        untilted.y,
        lane_active,
    );
}

pub fn invDistortModelSIMD(
    distort: DistortModel,
    v_x_d: VecSF,
    v_y_d: VecSF,
    v_lane_active: VecSB,
) !DistortCoordsSIMD {
    return switch (distort) {
        .none => .{ .x = v_x_d, .y = v_y_d },
        .brown_con => |bc| invDistortSIMD(
            common.BrownCon.Params,
            bc,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .brown_con_ext => |bc_ext| invBrownConExtSIMD(
            bc_ext,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .poly => |poly| invPolySIMD(
            poly,
            v_x_d,
            v_y_d,
            v_lane_active,
        ),
        .brown_con_poly => |chain| blk: {
            const poly_inv = try invPolySIMD(
                chain.poly,
                v_x_d,
                v_y_d,
                v_lane_active,
            );
            break :blk try invDistortSIMD(
                common.BrownCon.Params,
                chain.brown_con,
                poly_inv.x,
                poly_inv.y,
                v_lane_active,
            );
        },
        .brown_con_ext_poly => |chain| blk: {
            const poly_inv = try invPolySIMD(
                chain.poly,
                v_x_d,
                v_y_d,
                v_lane_active,
            );
            break :blk try invBrownConExtSIMD(
                chain.brown_con_ext,
                poly_inv.x,
                poly_inv.y,
                v_lane_active,
            );
        },
    };
}

fn isFiniteSIMD(values: VecSF) VecSB {
    return @abs(values) <= @as(VecSF, @splat(std.math.floatMax(F)));
}

test "polynomial scalar and SIMD forward agree for every order" {
    const degrees = [_]u8{ 1, 2, 3, 4, 5, 6, 7 };
    var coeffs = [_]F{0} ** 72;
    for (&coeffs, 0..) |*coeff, ii| coeff.* = @as(F, @floatFromInt(ii % 7)) * 0.001;
    for (degrees) |degree| {
        const poly = try common.PolyMap.init(
            degree,
            .displacement,
            coeffs[0 .. 2 * common.polyTermCount(degree)],
        );
        const scalar = poly.ford(0.12, -0.23);
        const simd = PolyMapSIMD.ford(poly, @splat(0.12), @splat(-0.23));
        const recovered = try PolyMapSIMD.inv(poly, simd.x, simd.y, @splat(true));
        const ford_x: [S]F = simd.x;
        const ford_y: [S]F = simd.y;
        const inv_x: [S]F = recovered.x;
        const inv_y: [S]F = recovered.y;
        for (0..S) |lane| {
            try std.testing.expectApproxEqAbs(
                scalar.x,
                ford_x[lane],
                if (F == f32) 1e-6 else 1e-12,
            );
            try std.testing.expectApproxEqAbs(
                scalar.y,
                ford_y[lane],
                if (F == f32) 1e-6 else 1e-12,
            );
            try std.testing.expectApproxEqAbs(
                @as(F, 0.12),
                inv_x[lane],
                if (F == f32) 2e-5 else 1e-9,
            );
            try std.testing.expectApproxEqAbs(
                @as(F, -0.23),
                inv_y[lane],
                if (F == f32) 2e-5 else 1e-9,
            );
        }
    }
}

test "polynomial SIMD reports failures only in active lanes" {
    const singular = common.PolyMap{
        .degree = 1,
        .mode = .displacement,
        .coeffs = &.{ 0.0, 0, -1.0, 0, 0.0, 0 },
    };
    try std.testing.expectError(
        error.SingularJac,
        PolyMapSIMD.inv(singular, @splat(0.3), @splat(-0.2), @splat(true)),
    );
    _ = try PolyMapSIMD.inv(singular, @splat(0.3), @splat(-0.2), @splat(false));
    const stalled = common.PolyMap{
        .degree = 2,
        .mode = .displacement,
        .coeffs = &.{ 0.0, 0, 0.0, 0, 0.0, 0, 1e22, 0, 0, 0, 0, 0 },
    };
    try std.testing.expectError(
        error.DistortInvFailed,
        PolyMapSIMD.inv(stalled, @splat(if (F == f32) 0.1 else 1e-11), @splat(0.0), @splat(true)),
    );
    try std.testing.expectError(
        error.NonFiniteDistort,
        PolyMapSIMD.inv(.{}, @splat(std.math.inf(F)), @splat(0.0), @splat(true)),
    );
    var x: VecSF = @splat(std.math.nan(F));
    var active: VecSB = @splat(false);
    x[0] = 0.12;
    active[0] = true;
    const recovered = try PolyMapSIMD.inv(.{}, x, @splat(0.0), active);
    try std.testing.expectEqual(@as(F, 0.12), recovered.x[0]);
}
