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

const matstack = @import("matstack.zig");
const Mat22f = matstack.Mat22f;
const Mat22Ops = matstack.Mat22Ops;
const Mat33f = matstack.Mat33f;
const Mat33Ops = matstack.Mat33Ops;
const Vec2f = @import("vecstack.zig").Vec2f;
const Vec3f = @import("vecstack.zig").Vec3f;

const cfg = buildconfig.config;
const tol = cfg.tol;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------
// Brown Conrady
// --------------------------------------------------------------------------------------

pub const DistortCoords = struct {
    x: F,
    y: F,
};

pub const DistortFordJacResult = struct {
    coords: DistortCoords,
    jac: Mat22f,
};

pub const BrownConParams = struct {
    k1: F = 0,
    k2: F = 0,
    k3: F = 0,
    p1: F = 0,
    p2: F = 0,
};

pub const BrownCon = struct {
    pub const Params = BrownConParams;

    pub fn ford(params: Params, x: F, y: F) DistortCoords {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const radial_scale = 1.0 + params.k1 * r2 + params.k2 * r4 + params.k3 * r6;
        return distortFordFromRadialScale(
            x,
            y,
            radial_scale,
            params.p1,
            params.p2,
        );
    }

    pub fn fordWithJac(params: Params, x: F, y: F) DistortFordJacResult {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const radial_scale = 1.0 + params.k1 * r2 + params.k2 * r4 + params.k3 * r6;
        const dradial_dr2 = params.k1 + 2.0 * params.k2 * r2 + 3.0 * params.k3 * r4;
        return distortFordWithJacFromRadialScale(
            x,
            y,
            radial_scale,
            dradial_dr2,
            params.p1,
            params.p2,
        );
    }

    pub fn inv(params: Params, x_d: F, y_d: F) !DistortCoords {
        return invFromFordWithJac(BrownCon, params, x_d, y_d);
    }
};

pub const BrownConExtParams = struct {
    k1: F = 0,
    k2: F = 0,
    k3: F = 0,
    k4: F = 0,
    k5: F = 0,
    k6: F = 0,
    p1: F = 0,
    p2: F = 0,
    s1: F = 0,
    s2: F = 0,
    s3: F = 0,
    s4: F = 0,
    tau_x: F = 0,
    tau_y: F = 0,
};

pub const BrownConExt = struct {
    pub const Params = BrownConExtParams;
    params: Params,
    tilt: ?TiltProjection = null,

    pub fn init(params: Params) !@This() {
        if (!isTiltActive(params)) return .{ .params = params };
        const ford_matrix = calcTiltMatrix(params.tau_x, params.tau_y);
        const inv_matrix = Mat33Ops.invChecked(
            F,
            ford_matrix,
            tol.distort.det,
        ) catch return error.SingularTiltProjection;
        return .{
            .params = params,
            .tilt = .{ .ford_matrix = ford_matrix, .inv_matrix = inv_matrix },
        };
    }

    pub inline fn ford(self: @This(), x: F, y: F) DistortCoords {
        const lens = fordLensWithJac(self.params, x, y);
        return applyTilt(self.tilt, lens.coords.x, lens.coords.y).coords;
    }

    pub inline fn fordWithJac(self: @This(), x: F, y: F) DistortFordJacResult {
        const lens = fordLensWithJac(self.params, x, y);
        const tilt = applyTilt(self.tilt, lens.coords.x, lens.coords.y);
        return .{ .coords = tilt.coords, .jac = tilt.jac.mulMat(lens.jac) };
    }

    pub inline fn inv(self: @This(), x_d: F, y_d: F) !DistortCoords {
        const untilted = try removeTilt(self.tilt, x_d, y_d);
        return invFromFordWithJac(
            BrownConExt,
            BrownConExt{ .params = self.params },
            untilted.x,
            untilted.y,
        );
    }
};

const TiltResult = struct {
    coords: DistortCoords,
    jac: Mat22f,
};

pub const TiltProjection = struct {
    ford_matrix: Mat33f,
    inv_matrix: Mat33f,
};

fn isTiltActive(params: BrownConExtParams) bool {
    return @abs(params.tau_x) > tol.distort.tilt_identity or
        @abs(params.tau_y) > tol.distort.tilt_identity;
}

fn calcRadialScaleAndDerivative(
    params: BrownConExtParams,
    x: F,
    y: F,
) struct { radial_scale: F, dradial_dr2: F } {
    const r2 = x * x + y * y;
    const r4 = r2 * r2;
    const r6 = r4 * r2;

    const numerator = 1.0 + params.k1 * r2 + params.k2 * r4 + params.k3 * r6;
    const denominator = 1.0 + params.k4 * r2 + params.k5 * r4 + params.k6 * r6;
    const dnum_dr2 = params.k1 + 2.0 * params.k2 * r2 + 3.0 * params.k3 * r4;
    const dden_dr2 = params.k4 + 2.0 * params.k5 * r2 + 3.0 * params.k6 * r4;

    return .{
        .radial_scale = numerator / denominator,
        .dradial_dr2 = (dnum_dr2 * denominator - numerator * dden_dr2) /
            (denominator * denominator),
    };
}

fn fordLensWithJac(
    params: BrownConExtParams,
    x: F,
    y: F,
) DistortFordJacResult {
    const radial = calcRadialScaleAndDerivative(params, x, y);
    var result = distortFordWithJacFromRadialScale(
        x,
        y,
        radial.radial_scale,
        radial.dradial_dr2,
        params.p1,
        params.p2,
    );

    const r2 = x * x + y * y;
    const r4 = r2 * r2;
    result.coords.x += params.s1 * r2 + params.s2 * r4;
    result.coords.y += params.s3 * r2 + params.s4 * r4;

    const jac = &result.jac.mat;
    jac[0][0] += 2.0 * x * (params.s1 + 2.0 * params.s2 * r2);
    jac[0][1] += 2.0 * y * (params.s1 + 2.0 * params.s2 * r2);
    jac[1][0] += 2.0 * x * (params.s3 + 2.0 * params.s4 * r2);
    jac[1][1] += 2.0 * y * (params.s3 + 2.0 * params.s4 * r2);

    return result;
}

fn applyTilt(tilt: ?TiltProjection, x: F, y: F) TiltResult {
    const projection = tilt orelse return .{
        .coords = .{ .x = x, .y = y },
        .jac = Mat22f.initIdentity(),
    };

    return applyHomography(projection.ford_matrix, x, y) catch .{
        .coords = .{ .x = std.math.nan(F), .y = std.math.nan(F) },
        .jac = Mat22f.initFill(std.math.nan(F)),
    };
}

fn removeTilt(tilt: ?TiltProjection, x: F, y: F) !DistortCoords {
    const projection = tilt orelse return .{ .x = x, .y = y };
    return (try applyHomography(projection.inv_matrix, x, y)).coords;
}

pub fn calcTiltMatrix(tau_x: F, tau_y: F) Mat33f {
    const cos_x = @cos(tau_x);
    const sin_x = @sin(tau_x);
    const cos_y = @cos(tau_y);
    const sin_y = @sin(tau_y);
    const r02 = -sin_y * cos_x;
    const r12 = sin_x;
    const r22 = cos_y * cos_x;

    return Mat33f.initRows(.{
        .{ r22 * cos_y - r02 * sin_y, r22 * sin_y * sin_x + r02 * cos_y * sin_x, 0.0 },
        .{ -r12 * sin_y, r22 * cos_x + r12 * cos_y * sin_x, 0.0 },
        .{ sin_y, -cos_y * sin_x, r22 },
    });
}

fn applyHomography(matrix: Mat33f, x: F, y: F) !TiltResult {
    const mat = matrix.mat;
    const projected = matrix.mulVec(Vec3f.initSlice(&[_]F{ x, y, 1.0 }));
    const numerator_x = projected.get(0);
    const numerator_y = projected.get(1);
    const denominator = projected.get(2);

    if (!std.math.isFinite(denominator) or @abs(denominator) < tol.distort.det) {
        return error.SingularTiltProjection;
    }

    const inv_denominator = 1.0 / denominator;
    const out_x = numerator_x * inv_denominator;
    const out_y = numerator_y * inv_denominator;
    const inv_denominator_sq = inv_denominator * inv_denominator;

    return .{
        .coords = .{ .x = out_x, .y = out_y },
        .jac = Mat22f.initRows(.{
            .{
                (mat[0][0] * denominator - numerator_x * mat[2][0]) * inv_denominator_sq,
                (mat[0][1] * denominator - numerator_x * mat[2][1]) * inv_denominator_sq,
            },
            .{
                (mat[1][0] * denominator - numerator_y * mat[2][0]) * inv_denominator_sq,
                (mat[1][1] * denominator - numerator_y * mat[2][1]) * inv_denominator_sq,
            },
        }),
    };
}

// --------------------------------------------------------------------------------------
// Polynomial Distortion
// --------------------------------------------------------------------------------------

pub const poly_powers_u = [10]u8{ 0, 1, 0, 2, 1, 0, 3, 2, 1, 0 };
pub const poly_powers_v = [10]u8{ 0, 0, 1, 0, 1, 2, 0, 1, 2, 3 };

pub const PolyOrder = enum(u8) {
    linear = 1,
    quadratic = 2,
    cubic = 3,

    pub fn termCount(self: PolyOrder) usize {
        return switch (self) {
            .linear => 3,
            .quadratic => 6,
            .cubic => 10,
        };
    }
};

pub const PolyMap = struct {
    pub const Params = @This();
    order: PolyOrder = .quadratic,
    coeffs_u: [10]F = [_]F{0.0} ** 10,
    coeffs_v: [10]F = [_]F{0.0} ** 10,

    /// Ideal to distorted normalized coordinates, using displacement coefficients.
    pub fn ford(
        self: PolyMap,
        x: F,
        y: F,
    ) DistortCoords {
        const poly = evalPolyDisplacement(self, x, y);
        return .{ .x = x + poly.du, .y = y + poly.dv };
    }

    pub fn fordWithJac(
        self: PolyMap,
        x: F,
        y: F,
    ) DistortFordJacResult {
        const distorted = self.ford(x, y);
        var ddu_dx: F = 0.0;
        var ddu_dy: F = 0.0;
        var ddv_dx: F = 0.0;
        var ddv_dy: F = 0.0;
        const term_count = self.order.termCount();

        for (0..term_count) |ii| {
            const pu = poly_powers_u[ii];
            const pv = poly_powers_v[ii];

            if (pu > 0) {
                const basis_dx = @as(F, @floatFromInt(pu)) *
                    powSmall(x, pu - 1) *
                    powSmall(y, pv);
                ddu_dx += self.coeffs_u[ii] * basis_dx;
                ddv_dx += self.coeffs_v[ii] * basis_dx;
            }

            if (pv > 0) {
                const basis_dy = @as(F, @floatFromInt(pv)) *
                    powSmall(x, pu) *
                    powSmall(y, pv - 1);
                ddu_dy += self.coeffs_u[ii] * basis_dy;
                ddv_dy += self.coeffs_v[ii] * basis_dy;
            }
        }

        return .{
            .coords = distorted,
            .jac = Mat22f.initRows(.{
                .{ 1.0 + ddu_dx, ddu_dy },
                .{ ddv_dx, 1.0 + ddv_dy },
            }),
        };
    }

    /// Numerically invert the forward map. Singular, non-finite, or non-convergent
    /// mappings return an error rather than claiming a valid inverse.
    pub fn inv(self: PolyMap, x_d: F, y_d: F) !DistortCoords {
        return invFromFordWithJac(PolyMap, self, x_d, y_d);
    }
};

pub const BrownConPoly = struct {
    brown_con: BrownCon.Params = .{},
    poly: PolyMap = .{},

    pub fn ford(
        self: BrownConPoly,
        x: F,
        y: F,
    ) DistortCoords {
        const brown = BrownCon.ford(self.brown_con, x, y);
        return self.poly.ford(brown.x, brown.y);
    }

    pub fn inv(
        self: BrownConPoly,
        x_d: F,
        y_d: F,
    ) !DistortCoords {
        const poly_inv = try self.poly.inv(x_d, y_d);
        return try BrownCon.inv(self.brown_con, poly_inv.x, poly_inv.y);
    }
};

pub const BrownConExtPolyParams = struct {
    brown_con_ext: BrownConExt.Params = .{},
    poly: PolyMap = .{},
};

pub const BrownConExtPoly = struct {
    brown_con_ext: BrownConExt,
    poly: PolyMap = .{},

    pub fn init(params: BrownConExtPolyParams) !@This() {
        return .{
            .brown_con_ext = try BrownConExt.init(params.brown_con_ext),
            .poly = params.poly,
        };
    }

    pub fn ford(
        self: BrownConExtPoly,
        x: F,
        y: F,
    ) DistortCoords {
        const brown = self.brown_con_ext.ford(x, y);
        return self.poly.ford(brown.x, brown.y);
    }

    pub fn inv(
        self: BrownConExtPoly,
        x_d: F,
        y_d: F,
    ) !DistortCoords {
        const poly_inv = try self.poly.inv(x_d, y_d);
        return try self.brown_con_ext.inv(poly_inv.x, poly_inv.y);
    }
};

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

pub const DistortParams = union(enum) {
    none,
    brown_con: BrownCon.Params,
    brown_con_ext: BrownConExt.Params,
    poly: PolyMap,
    brown_con_poly: BrownConPoly,
    brown_con_ext_poly: BrownConExtPolyParams,
};

pub const DistortModel = union(enum) {
    none,
    brown_con: BrownCon.Params,
    brown_con_ext: BrownConExt,
    poly: PolyMap,
    brown_con_poly: BrownConPoly,
    brown_con_ext_poly: BrownConExtPoly,

    pub fn init(params: DistortParams) !@This() {
        return switch (params) {
            .none => .none,
            .brown_con => |brown| .{ .brown_con = brown },
            .brown_con_ext => |brown| .{ .brown_con_ext = try BrownConExt.init(brown) },
            .poly => |poly| .{ .poly = poly },
            .brown_con_poly => |chain| .{ .brown_con_poly = chain },
            .brown_con_ext_poly => |chain| .{
                .brown_con_ext_poly = try BrownConExtPoly.init(chain),
            },
        };
    }

    pub fn paramsFromModel(self: @This()) DistortParams {
        return switch (self) {
            .none => .none,
            .brown_con => |brown| .{ .brown_con = brown },
            .brown_con_ext => |brown| .{
                .brown_con_ext = brown.params,
            },
            .poly => |poly| .{ .poly = poly },
            .brown_con_poly => |chain| .{ .brown_con_poly = chain },
            .brown_con_ext_poly => |chain| .{ .brown_con_ext_poly = .{
                .brown_con_ext = chain.brown_con_ext.params,
                .poly = chain.poly,
            } },
        };
    }
};

// --------------------------------------------------------------------------------------
// Point Spread Func
// --------------------------------------------------------------------------------------

pub const SeparablePSF = enum {
    no,
    yes,
};

pub const PixelBoxPSF = struct {
    supp_rad_px: F = 0.5,
};

pub const GaussianPSF = struct {
    sigma_px: F,
    supp_rad_px: F,
    separable: SeparablePSF = .yes,
};

pub const AnisotropicGaussianPSF = struct {
    sigma_x_px: F,
    sigma_y_px: F,
    theta_rad: F = 0.0,
    supp_rad_px: F,
    separable: SeparablePSF = .no,
};

pub const PointSpreadFunc = union(enum) {
    pixel_box: PixelBoxPSF,
    gaussian: GaussianPSF,
    anisotropic_gaussian: AnisotropicGaussianPSF,
};

pub const PreparedPSFMode = enum {
    identity_fast,
    separable,
    nonseparable,
};

pub const PreparedPSF = struct {
    mode: PreparedPSFMode = .identity_fast,
    halo_px: u16 = 0,
    halo_subpx: usize = 0,
    radius_x_subpx: usize = 0,
    radius_y_subpx: usize = 0,
    weights_x: []F = &.{},
    weights_y: []F = &.{},
    weights_2d: []F = &.{},

    pub fn deinit(self: *PreparedPSF, allocator: std.mem.Allocator) void {
        if (self.weights_x.len > 0) allocator.free(self.weights_x);
        if (self.weights_y.len > 0) allocator.free(self.weights_y);
        if (self.weights_2d.len > 0) allocator.free(self.weights_2d);
        self.* = .{};
    }

    pub fn hasFilter(self: PreparedPSF) bool {
        return self.mode != .identity_fast;
    }
};

fn psfKernelValue1D(psf: PointSpreadFunc, dist_px: F) F {
    const abs_dist = @abs(dist_px);
    return switch (psf) {
        .pixel_box => |box| if (abs_dist <= box.supp_rad_px +
            tol.psf.supp_radius_inclusion) 1.0 else 0.0,
        .gaussian => |gauss| if (abs_dist <= gauss.supp_rad_px +
            tol.psf.supp_radius_inclusion)
            @exp(-0.5 * (dist_px * dist_px) / (gauss.sigma_px * gauss.sigma_px))
        else
            0.0,
        .anisotropic_gaussian => unreachable,
    };
}

fn psfKernelValue2D(psf: PointSpreadFunc, dx_px: F, dy_px: F) F {
    return switch (psf) {
        .pixel_box => |box| if (@abs(dx_px) <= box.supp_rad_px +
            tol.psf.supp_radius_inclusion and
            @abs(dy_px) <= box.supp_rad_px +
                tol.psf.supp_radius_inclusion)
            1.0
        else
            0.0,
        .gaussian => |gauss| if (@abs(dx_px) <= gauss.supp_rad_px +
            tol.psf.supp_radius_inclusion and
            @abs(dy_px) <= gauss.supp_rad_px +
                tol.psf.supp_radius_inclusion)
            @exp(-0.5 * (dx_px * dx_px + dy_px * dy_px) /
                (gauss.sigma_px * gauss.sigma_px))
        else
            0.0,
        .anisotropic_gaussian => |gauss| blk: {
            if (@abs(dx_px) > gauss.supp_rad_px +
                tol.psf.supp_radius_inclusion or
                @abs(dy_px) > gauss.supp_rad_px +
                    tol.psf.supp_radius_inclusion)
            {
                break :blk 0.0;
            }
            const c = @cos(gauss.theta_rad);
            const s = @sin(gauss.theta_rad);
            const xr = c * dx_px + s * dy_px;
            const yr = -s * dx_px + c * dy_px;
            break :blk @exp(-0.5 * ((xr * xr) / (gauss.sigma_x_px * gauss.sigma_x_px) +
                (yr * yr) / (gauss.sigma_y_px * gauss.sigma_y_px)));
        },
    };
}

fn normalizeKernel(weights: []F) void {
    var sum: F = 0.0;
    for (weights) |weight| sum += weight;
    if (sum == 0.0) return;
    for (weights) |*weight| weight.* /= sum;
}

fn buildKernel1D(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    radius_subpx: usize,
    sub_sample: u32,
) ![]F {
    const size = 2 * radius_subpx + 1;
    const weights = try allocator.alloc(F, size);
    const sub_samp_f = @as(F, @floatFromInt(sub_sample));

    for (0..size) |ii| {
        const offset = @as(isize, @intCast(ii)) - @as(isize, @intCast(radius_subpx));
        const dist_px = @as(F, @floatFromInt(offset)) / sub_samp_f;
        weights[ii] = psfKernelValue1D(psf, dist_px);
    }

    normalizeKernel(weights);
    return weights;
}

fn invFromFordWithJac(
    comptime Evaluator: type,
    params: anytype,
    x_d: F,
    y_d: F,
) !DistortCoords {
    if (!std.math.isFinite(x_d) or !std.math.isFinite(y_d)) return error.NonFiniteDistort;
    var x = x_d;
    var y = y_d;
    // Check the residual after the final permitted Newton step as well.
    for (0..cfg.distort_newton_iter_max + 1) |iteration| {
        const fwd = Evaluator.fordWithJac(params, x, y);
        const f0 = fwd.coords.x - x_d;
        const f1 = fwd.coords.y - y_d;
        if (!std.math.isFinite(f0) or !std.math.isFinite(f1)) return error.NonFiniteDistort;
        if (@max(@abs(f0), @abs(f1)) < tol.distort.resid) return .{ .x = x, .y = y };
        if (iteration == cfg.distort_newton_iter_max) break;
        for (fwd.jac.mat) |row| {
            for (row) |value| {
                if (!std.math.isFinite(value)) return error.NonFiniteDistort;
            }
        }
        if (!std.math.isFinite(Mat22Ops.det(F, fwd.jac))) return error.NonFiniteDistort;
        const delta = Mat22Ops.solveChecked(
            F,
            fwd.jac,
            Vec2f.initSlice(&.{ -f0, -f1 }),
            tol.distort.det,
        ) catch return error.SingularJac;
        x += delta.x();
        y += delta.y();
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) return error.NonFiniteDistort;
    }
    return error.DistortInvFailed;
}

fn evalPolyDisplacement(
    poly: PolyMap,
    x: F,
    y: F,
) struct { du: F, dv: F } {
    var du: F = 0.0;
    var dv: F = 0.0;
    const term_count = poly.order.termCount();

    for (0..term_count) |ii| {
        const basis = powSmall(x, poly_powers_u[ii]) *
            powSmall(y, poly_powers_v[ii]);
        du += poly.coeffs_u[ii] * basis;
        dv += poly.coeffs_v[ii] * basis;
    }

    return .{ .du = du, .dv = dv };
}

fn powSmall(
    x: F,
    power: u8,
) F {
    var out: F = 1.0;
    for (0..power) |_| {
        out *= x;
    }
    return out;
}

fn distortFordFromRadialScale(
    x: F,
    y: F,
    radial_scale: F,
    p1: F,
    p2: F,
) DistortCoords {
    const r2 = x * x + y * y;
    const x_d =
        x * radial_scale + 2.0 * p1 * x * y + p2 * (r2 + 2.0 * x * x);
    const y_d =
        y * radial_scale + p1 * (r2 + 2.0 * y * y) + 2.0 * p2 * x * y;
    return .{ .x = x_d, .y = y_d };
}

fn distortFordWithJacFromRadialScale(
    x: F,
    y: F,
    radial_scale: F,
    dradial_dr2: F,
    p1: F,
    p2: F,
) DistortFordJacResult {
    const distorted = distortFordFromRadialScale(
        x,
        y,
        radial_scale,
        p1,
        p2,
    );
    const dradial_dx = dradial_dr2 * 2.0 * x;
    const dradial_dy = dradial_dr2 * 2.0 * y;

    const dx_fwd_dx =
        radial_scale + x * dradial_dx + 2.0 * p1 * y + 6.0 * p2 * x;
    const dx_fwd_dy = x * dradial_dy + 2.0 * p1 * x + 2.0 * p2 * y;
    const dy_fwd_dx = y * dradial_dx + 2.0 * p1 * x + 2.0 * p2 * y;
    const dy_fwd_dy =
        radial_scale + y * dradial_dy + 6.0 * p1 * y + 2.0 * p2 * x;

    return .{
        .coords = distorted,
        .jac = Mat22f.initRows(.{
            .{ dx_fwd_dx, dx_fwd_dy },
            .{ dy_fwd_dx, dy_fwd_dy },
        }),
    };
}

fn buildKernel2D(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    radius_x_subpx: usize,
    radius_y_subpx: usize,
    sub_sample: u32,
) ![]F {
    const width = 2 * radius_x_subpx + 1;
    const height = 2 * radius_y_subpx + 1;
    const weights = try allocator.alloc(F, width * height);
    const sub_samp_f = @as(F, @floatFromInt(sub_sample));

    for (0..height) |yy| {
        const y_off = @as(isize, @intCast(yy)) - @as(isize, @intCast(radius_y_subpx));
        const dy_px = @as(F, @floatFromInt(y_off)) / sub_samp_f;
        for (0..width) |xx| {
            const x_off = @as(isize, @intCast(xx)) - @as(isize, @intCast(radius_x_subpx));
            const dx_px = @as(F, @floatFromInt(x_off)) / sub_samp_f;

            weights[yy * width + xx] = psfKernelValue2D(psf, dx_px, dy_px);
        }
    }

    normalizeKernel(weights);
    return weights;
}

pub fn preparePSF(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    sub_sample: u32,
) !PreparedPSF {
    switch (psf) {
        .pixel_box => |box| {
            if (box.supp_rad_px <= 0.5 +
                tol.psf.pixel_box_identity_supp_radius)
            {
                return .{};
            }
            const halo_px: u16 = @intCast(@max(
                @as(usize, 0),
                @as(usize, @intFromFloat(@ceil(box.supp_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(box.supp_rad_px * @as(F, @floatFromInt(sub_sample))),
            );
            return .{
                .mode = .separable,
                .halo_px = halo_px,
                .halo_subpx = @as(usize, halo_px) * @as(usize, sub_sample),
                .radius_x_subpx = radius_subpx,
                .radius_y_subpx = radius_subpx,
                .weights_x = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                .weights_y = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
            };
        },
        .gaussian => |gauss| {
            const halo_px: u16 = @intCast(@max(
                @as(usize, 0),
                @as(usize, @intFromFloat(@ceil(gauss.supp_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(gauss.supp_rad_px * @as(F, @floatFromInt(sub_sample))),
            );
            if (gauss.separable == .yes) {
                return .{
                    .mode = .separable,
                    .halo_px = halo_px,
                    .halo_subpx = @as(usize, halo_px) * @as(usize, sub_sample),
                    .radius_x_subpx = radius_subpx,
                    .radius_y_subpx = radius_subpx,
                    .weights_x = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                    .weights_y = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                };
            }
            return .{
                .mode = .nonseparable,
                .halo_px = halo_px,
                .halo_subpx = @as(usize, halo_px) * @as(usize, sub_sample),
                .radius_x_subpx = radius_subpx,
                .radius_y_subpx = radius_subpx,
                .weights_2d = try buildKernel2D(
                    allocator,
                    psf,
                    radius_subpx,
                    radius_subpx,
                    sub_sample,
                ),
            };
        },
        .anisotropic_gaussian => |gauss| {
            const halo_px: u16 = @intCast(@max(
                @as(usize, 0),
                @as(usize, @intFromFloat(@ceil(gauss.supp_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(gauss.supp_rad_px * @as(F, @floatFromInt(sub_sample))),
            );
            const axis_aligned = @abs(@sin(gauss.theta_rad)) <
                tol.psf.anisotropic_axis_align;
            if (gauss.separable == .yes and axis_aligned) {
                const psf_x = PointSpreadFunc{
                    .gaussian = .{
                        .sigma_px = gauss.sigma_x_px,
                        .supp_rad_px = gauss.supp_rad_px,
                        .separable = .yes,
                    },
                };
                const psf_y = PointSpreadFunc{
                    .gaussian = .{
                        .sigma_px = gauss.sigma_y_px,
                        .supp_rad_px = gauss.supp_rad_px,
                        .separable = .yes,
                    },
                };
                return .{
                    .mode = .separable,
                    .halo_px = halo_px,
                    .halo_subpx = @as(usize, halo_px) * @as(usize, sub_sample),
                    .radius_x_subpx = radius_subpx,
                    .radius_y_subpx = radius_subpx,
                    .weights_x = try buildKernel1D(
                        allocator,
                        psf_x,
                        radius_subpx,
                        sub_sample,
                    ),
                    .weights_y = try buildKernel1D(
                        allocator,
                        psf_y,
                        radius_subpx,
                        sub_sample,
                    ),
                };
            }
            return .{
                .mode = .nonseparable,
                .halo_px = halo_px,
                .halo_subpx = @as(usize, halo_px) * @as(usize, sub_sample),
                .radius_x_subpx = radius_subpx,
                .radius_y_subpx = radius_subpx,
                .weights_2d = try buildKernel2D(
                    allocator,
                    psf,
                    radius_subpx,
                    radius_subpx,
                    sub_sample,
                ),
            };
        },
    }
}

//------------------------------------------------------------------------------------------
// Tests
//------------------------------------------------------------------------------------------

test "BrownConradyExt init caches tilt and evaluates correctly" {
    const params = BrownConExt.Params{
        .k1 = -0.08,
        .s1 = 1.2e-3,
        .tau_x = 0.023,
        .tau_y = -0.031,
    };
    const model = try BrownConExt.init(params);
    try std.testing.expect(model.tilt != null);
    const actual = model.ford(0.47, -0.29);
    const recovered = try model.inv(actual.x, actual.y);
    try std.testing.expectApproxEqAbs(@as(F, 0.47), recovered.x, 2.0e-5);
    try std.testing.expectApproxEqAbs(@as(F, -0.29), recovered.y, 2.0e-5);
}

test "BrownConradyExt cached tilt matrices compose to identity" {
    const distort = try BrownConExt.init(.{
        .tau_x = 0.023,
        .tau_y = -0.031,
    });
    const projection = distort.tilt.?;
    const ford = projection.ford_matrix;
    const inv = projection.inv_matrix;
    const product = ford.mulMat(inv);
    const identity = Mat33f.initIdentity();
    const identity_mat = identity.mat;
    const product_mat = product.mat;
    inline for (0..3) |row| {
        inline for (0..3) |col| {
            try std.testing.expectApproxEqAbs(
                identity_mat[row][col],
                product_mat[row][col],
                1.0e-14,
            );
        }
    }
}

test "BrownConradyExt rejects singular prepared tilt" {
    const singular = BrownConExt.Params{ .tau_y = std.math.pi / 2.0 };
    try std.testing.expectError(
        error.SingularTiltProjection,
        BrownConExt.init(singular),
    );
}

test "BrownConradyExt inverse rejects singular tilt projection" {
    const singular = BrownConExt.Params{ .tau_y = std.math.pi / 2.0 };
    try std.testing.expectError(
        error.SingularTiltProjection,
        BrownConExt.init(singular),
    );
}

test "BrownConradyExt rational pole propagates non-finite forward value" {
    const pole = BrownConExt.Params{ .k4 = -1.0 };
    const result = (try BrownConExt.init(pole)).ford(1.0, 0.0);
    try std.testing.expect(!std.math.isFinite(result.x));
}

test "PolynomialMap inverse rejects a singular Jacobian" {
    const singular = PolyMap{
        .order = .linear,
        .coeffs_u = .{ 0.0, -1.0, 0.0 } ++ [_]F{0.0} ** 7,
    };
    try std.testing.expectError(error.SingularJac, singular.inv(0.3, -0.2));
}

test "PolynomialMap identity and inverse failures are explicit" {
    const identity = PolyMap{};
    try std.testing.expectEqualDeep(DistortCoords{ .x = 0.3, .y = -0.2 }, identity.ford(0.3, -0.2));
    try std.testing.expectEqualDeep(
        DistortCoords{ .x = 0.3, .y = -0.2 },
        try identity.inv(0.3, -0.2),
    );
    const stalled = PolyMap{
        .coeffs_u = .{ 0.0, 0.0, 0.0, 1e22 } ++ [_]F{0.0} ** 6,
    };
    // A tiny Newton step is not evidence that this residual has converged.
    try std.testing.expectError(error.DistortInvFailed, stalled.inv(1e-11, 0.0));
    const invalid = PolyMap{ .coeffs_u = .{std.math.nan(F)} ++ [_]F{0.0} ** 9 };
    try std.testing.expectError(error.NonFiniteDistort, invalid.inv(0.3, -0.2));
    try std.testing.expectError(error.NonFiniteDistort, identity.inv(std.math.inf(F), 0.0));
    try std.testing.expectError(error.NonFiniteDistort, identity.inv(std.math.nan(F), 0.0));
    try std.testing.expectError(error.NonFiniteDistort, BrownCon.inv(.{}, std.math.inf(F), 0.0));
    const brown_ext = try BrownConExt.init(.{});
    try std.testing.expectError(error.NonFiniteDistort, brown_ext.inv(std.math.nan(F), 0.0));
}

test "DistortionModel paramsFromModel round trips every variant" {
    const poly = PolyMap{ .coeffs_u = .{0.01} ++ [_]F{0.0} ** 9 };
    const cases = [_]DistortParams{
        .none,
        .{ .brown_con = .{ .k1 = -0.12 } },
        .{ .brown_con_ext = .{ .tau_x = 0.02, .s1 = 0.003 } },
        .{ .poly = poly },
        .{ .brown_con_poly = .{ .poly = poly } },
        .{ .brown_con_ext_poly = .{
            .brown_con_ext = .{ .tau_y = -0.03 },
            .poly = poly,
        } },
    };
    for (cases) |params| {
        const model = try DistortModel.init(params);
        try std.testing.expectEqualDeep(params, model.paramsFromModel());
    }
}
