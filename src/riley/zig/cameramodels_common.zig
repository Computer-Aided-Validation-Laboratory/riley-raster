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

pub const POLY_MAX_DEGREE: u8 = 7;
pub const PolyMode = enum(u8) { coordinate = 0, displacement = 1 };
pub const PolyPowers = struct { px: u8, py: u8 };

/// Call with a validated degree (1 through POLY_MAX_DEGREE).
pub fn polyTermCount(degree: u8) usize {
    const n: usize = degree;
    return (n + 1) * (n + 2) / 2;
}

fn generatePolyPowers() [polyTermCount(POLY_MAX_DEGREE)]PolyPowers {
    var out: [polyTermCount(POLY_MAX_DEGREE)]PolyPowers = undefined;
    var ii: usize = 0;
    for (0..POLY_MAX_DEGREE + 1) |total| {
        for (0..total + 1) |py| {
            out[ii] = .{ .px = @intCast(total - py), .py = @intCast(py) };
            ii += 1;
        }
    }
    return out;
}

pub const poly_powers = generatePolyPowers();
const identity_poly_coeffs = [_]F{0} ** 6;

pub const PolyMap = struct {
    pub const Params = @This();
    degree: u8 = 1,
    mode: PolyMode = .displacement,
    /// Borrowed immutable row-major [term_count, 2] coefficients.
    /// Caller storage must remain alive and unchanged until all workers finish.
    coeffs: []const F = &identity_poly_coeffs,

    pub fn init(degree: u8, mode: PolyMode, coeffs: []const F) !PolyMap {
        const self = PolyMap{ .degree = degree, .mode = mode, .coeffs = coeffs };
        try self.validate();
        return self;
    }

    pub fn validate(self: PolyMap) !void {
        if (self.degree < 1 or self.degree > POLY_MAX_DEGREE)
            return error.InvalidPolyDegree;
        if (self.coeffs.len != 2 * polyTermCount(self.degree))
            return error.InvalidPolyCoeffCount;
        for (self.coeffs) |coeff| {
            if (!std.math.isFinite(coeff)) return error.NonFinitePolyCoeff;
        }
    }

    pub fn ford(self: PolyMap, x: F, y: F) DistortCoords {
        const result = evalPoly(F, false, self, x, y);
        return .{ .x = result.x, .y = result.y };
    }

    pub fn fordWithJac(self: PolyMap, x: F, y: F) DistortFordJacResult {
        const result = evalPoly(F, true, self, x, y);
        return .{
            .coords = .{ .x = result.x, .y = result.y },
            .jac = Mat22f.initRows(.{
                .{ result.xx, result.xy },
                .{ result.yx, result.yy },
            }),
        };
    }

    /// Local numerical inversion of the same forward map; uniqueness is not guaranteed.
    pub fn inv(self: PolyMap, x_d: F, y_d: F) !DistortCoords {
        return invFromFordWithJac(PolyMap, self, x_d, y_d);
    }
};

fn polyValue(comptime T: type, value: F) T {
    if (T == F) return value;
    return @splat(value);
}

/// Shared scalar/SIMD arithmetic. Derivatives are eliminated at comptime for ford().
pub fn evalPoly(
    comptime T: type,
    comptime with_jac: bool,
    poly: PolyMap,
    x: T,
    y: T,
) struct { x: T, y: T, xx: T, xy: T, yx: T, yy: T } {
    std.debug.assert(poly.degree >= 1 and poly.degree <= POLY_MAX_DEGREE);
    std.debug.assert(poly.coeffs.len == 2 * polyTermCount(poly.degree));
    var xp: [POLY_MAX_DEGREE + 1]T = undefined;
    var yp: [POLY_MAX_DEGREE + 1]T = undefined;
    xp[0] = polyValue(T, 1);
    yp[0] = polyValue(T, 1);
    for (1..@as(usize, poly.degree) + 1) |ii| {
        xp[ii] = xp[ii - 1] * x;
        yp[ii] = yp[ii - 1] * y;
    }
    const zero = polyValue(T, 0);
    var out = .{ .x = zero, .y = zero, .xx = zero, .xy = zero, .yx = zero, .yy = zero };
    for (poly_powers[0..polyTermCount(poly.degree)], 0..) |powers, ii| {
        const cu = polyValue(T, poly.coeffs[2 * ii]);
        const cv = polyValue(T, poly.coeffs[2 * ii + 1]);
        const basis = xp[powers.px] * yp[powers.py];
        out.x += cu * basis;
        out.y += cv * basis;
        if (with_jac) {
            if (powers.px > 0) {
                const dx = polyValue(T, @floatFromInt(powers.px)) *
                    xp[powers.px - 1] * yp[powers.py];
                out.xx += cu * dx;
                out.yx += cv * dx;
            }
            if (powers.py > 0) {
                const dy = polyValue(T, @floatFromInt(powers.py)) *
                    xp[powers.px] * yp[powers.py - 1];
                out.xy += cu * dy;
                out.yy += cv * dy;
            }
        }
    }
    if (poly.mode == .displacement) {
        out.x += x;
        out.y += y;
        if (with_jac) {
            out.xx += polyValue(T, 1);
            out.yy += polyValue(T, 1);
        }
    }
    return .{ .x = out.x, .y = out.y, .xx = out.xx, .xy = out.xy, .yx = out.yx, .yy = out.yy };
}

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

    pub fn fordWithJac(self: BrownConPoly, x: F, y: F) DistortFordJacResult {
        const brown = BrownCon.fordWithJac(self.brown_con, x, y);
        const poly = self.poly.fordWithJac(brown.coords.x, brown.coords.y);
        return .{ .coords = poly.coords, .jac = poly.jac.mulMat(brown.jac) };
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
        try params.poly.validate();
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

    pub fn fordWithJac(self: BrownConExtPoly, x: F, y: F) DistortFordJacResult {
        const brown = self.brown_con_ext.fordWithJac(x, y);
        const poly = self.poly.fordWithJac(brown.coords.x, brown.coords.y);
        return .{ .coords = poly.coords, .jac = poly.jac.mulMat(brown.jac) };
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
            .poly => |poly| blk: {
                try poly.validate();
                break :blk .{ .poly = poly };
            },
            .brown_con_poly => |chain| blk: {
                try chain.poly.validate();
                break :blk .{ .brown_con_poly = chain };
            },
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

    pub fn init(
        allocator: std.mem.Allocator,
        psf: PointSpreadFunc,
        sub_sample: u32,
    ) !PreparedPSF {
        return preparePSF(allocator, psf, sub_sample);
    }

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
                if (F == f32) 2e-6 else 1e-14,
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
        .degree = 1,
        .mode = .displacement,
        .coeffs = &.{ 0.0, 0, -1.0, 0, 0.0, 0 },
    };
    try std.testing.expectError(error.SingularJac, singular.inv(0.3, -0.2));
}

test "PolynomialMap identity and inverse failures are explicit" {
    const identity = PolyMap{};
    try std.testing.expectEqualDeep(
        DistortCoords{ .x = 0.3, .y = -0.2 },
        identity.ford(0.3, -0.2),
    );
    try std.testing.expectEqualDeep(
        DistortCoords{ .x = 0.3, .y = -0.2 },
        try identity.inv(0.3, -0.2),
    );
    const stalled = PolyMap{
        .degree = 2,
        .mode = .displacement,
        .coeffs = &.{ 0.0, 0, 0.0, 0, 0.0, 0, 1e22, 0, 0, 0, 0, 0 },
    };
    // A tiny Newton step is not evidence that this residual has converged.
    try std.testing.expectError(
        error.DistortInvFailed,
        stalled.inv(if (F == f32) 0.1 else 1e-11, 0.0),
    );
    const invalid = PolyMap{ .coeffs = &.{ std.math.nan(F), 0, 0, 0, 0, 0 } };
    try std.testing.expectError(error.NonFiniteDistort, invalid.inv(0.3, -0.2));
    try std.testing.expectError(error.NonFiniteDistort, identity.inv(std.math.inf(F), 0.0));
    try std.testing.expectError(error.NonFiniteDistort, identity.inv(std.math.nan(F), 0.0));
    try std.testing.expectError(
        error.NonFiniteDistort,
        BrownCon.inv(.{}, std.math.inf(F), 0.0),
    );
    const brown_ext = try BrownConExt.init(.{});
    try std.testing.expectError(error.NonFiniteDistort, brown_ext.inv(std.math.nan(F), 0.0));
}

test "DistortionModel paramsFromModel round trips every variant" {
    const poly = PolyMap{ .coeffs = &.{ 0.01, 0, 0, 0, 0, 0 } };
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

test "polynomial table ordering and checked construction" {
    const counts = [_]usize{ 3, 6, 10, 15, 21, 28, 36 };
    var index: usize = 0;
    for (0..8) |total| {
        for (0..total + 1) |py| {
            try std.testing.expectEqual(@as(u8, @intCast(total - py)), poly_powers[index].px);
            try std.testing.expectEqual(@as(u8, @intCast(py)), poly_powers[index].py);
            index += 1;
        }
    }
    for (counts, 1..) |count, degree| {
        try std.testing.expectEqual(count, polyTermCount(@intCast(degree)));
    }
    try std.testing.expectError(error.InvalidPolyDegree, PolyMap.init(0, .coordinate, &.{}));
    try std.testing.expectError(error.InvalidPolyDegree, PolyMap.init(8, .displacement, &.{}));
    try std.testing.expectError(
        error.InvalidPolyCoeffCount,
        PolyMap.init(1, .coordinate, &.{0}),
    );
    try std.testing.expectError(
        error.InvalidPolyCoeffCount,
        PolyMap.init(1, .coordinate, &([_]F{0} ** 8)),
    );
    for ([_]F{ std.math.nan(F), std.math.inf(F), -std.math.inf(F) }) |invalid| {
        try std.testing.expectError(
            error.NonFinitePolyCoeff,
            PolyMap.init(1, .coordinate, &.{ invalid, 0, 0, 0, 0, 0 }),
        );
    }
    const coeffs = [_]F{ 0.01, -0.02, 1.1, 0.03, -0.04, 0.9 };
    const map = try PolyMap.init(1, .coordinate, &coeffs);
    try std.testing.expect(map.coeffs.ptr == &coeffs);
    const observed = map.ford(0.2, -0.1);
    const recovered = try map.inv(observed.x, observed.y);
    const allowed: F = if (F == f32) 2e-5 else 1e-10;
    try std.testing.expectApproxEqAbs(@as(F, 0.2), recovered.x, allowed);
    try std.testing.expectApproxEqAbs(@as(F, -0.1), recovered.y, allowed);
    const zero = try PolyMap.init(1, .coordinate, &.{ 0, 0, 0, 0, 0, 0 });
    try std.testing.expectEqualDeep(DistortCoords{ .x = 0, .y = 0 }, zero.ford(0.3, -0.2));
    try std.testing.expectError(error.SingularJac, zero.inv(1, 0));
    const identity = try PolyMap.init(1, .coordinate, &.{ 0, 0, 1, 0, 0, 1 });
    try std.testing.expectEqualDeep(identity.fordWithJac(0, 0), (PolyMap{}).fordWithJac(0, 0));
}

test "degree seven polynomial matches BC and polynomial BCExt subset" {
    const cases = [_]struct { degree: u8, brown: BrownConExtParams }{
        .{ .degree = 2, .brown = .{ .p1 = 0.003, .p2 = -0.002 } },
        .{ .degree = 3, .brown = .{ .k1 = -0.05 } },
        .{ .degree = 5, .brown = .{ .k2 = 0.02 } },
        .{ .degree = 7, .brown = .{ .k3 = -0.01 } },
        .{ .degree = 7, .brown = .{
            .k1 = -0.05,
            .k2 = 0.02,
            .k3 = -0.01,
            .p1 = 0.003,
            .p2 = -0.002,
        } },
        .{ .degree = 7, .brown = .{
            .k1 = -0.05,
            .k2 = 0.02,
            .k3 = -0.01,
            .p1 = 0.003,
            .p2 = -0.002,
            .s1 = 0.001,
            .s2 = -0.002,
            .s3 = -0.003,
            .s4 = 0.001,
        } },
    };
    const allowed: F = if (F == f32) 3e-6 else 1e-12;
    const inv_allowed: F = if (F == f32) 3e-5 else 1e-9;
    for (cases) |case| {
        const p = case.brown;
        var coeffs = [_]F{0} ** 72;
        // Independent, explicit binomial expansion in the documented term order.
        coeffs[2 * 3] = 3 * p.p2 + p.s1;
        coeffs[2 * 3 + 1] = p.p1 + p.s3;
        coeffs[2 * 4] = 2 * p.p1;
        coeffs[2 * 4 + 1] = 2 * p.p2;
        coeffs[2 * 5] = p.p2 + p.s1;
        coeffs[2 * 5 + 1] = 3 * p.p1 + p.s3;
        for ([_]usize{ 10, 12, 14 }, [_]F{ 1, 2, 1 }) |term, factor| {
            coeffs[2 * term] = factor * p.s2;
            coeffs[2 * term + 1] = factor * p.s4;
        }
        for ([_]usize{ 6, 8 }, [_]usize{ 7, 9 }) |u, v| {
            coeffs[2 * u] = p.k1;
            coeffs[2 * v + 1] = p.k1;
        }
        for ([_]usize{ 15, 17, 19 }, [_]usize{ 16, 18, 20 }, [_]F{ 1, 2, 1 }) |u, v, factor| {
            coeffs[2 * u] = factor * p.k2;
            coeffs[2 * v + 1] = factor * p.k2;
        }
        for (
            [_]usize{ 28, 30, 32, 34 },
            [_]usize{ 29, 31, 33, 35 },
            [_]F{ 1, 3, 3, 1 },
        ) |u, v, factor| {
            coeffs[2 * u] = factor * p.k3;
            coeffs[2 * v + 1] = factor * p.k3;
        }
        const brown = try BrownConExt.init(p);
        for ([_]PolyMode{ .displacement, .coordinate }) |mode| {
            coeffs[2] = if (mode == .coordinate) 1 else 0;
            coeffs[5] = if (mode == .coordinate) 1 else 0;
            const map = try PolyMap.init(
                case.degree,
                mode,
                coeffs[0 .. 2 * polyTermCount(case.degree)],
            );
            for ([_]F{ -0.8, -0.3, 0, 0.4, 0.8 }) |x| {
                for ([_]F{ -0.6, 0, 0.2, 0.6 }) |y| {
                    const expected = brown.fordWithJac(x, y);
                    const actual = map.fordWithJac(x, y);
                    try std.testing.expectApproxEqAbs(
                        expected.coords.x,
                        actual.coords.x,
                        allowed,
                    );
                    try std.testing.expectApproxEqAbs(
                        expected.coords.y,
                        actual.coords.y,
                        allowed,
                    );
                    for (0..2) |rr| {
                        for (0..2) |cc| {
                            try std.testing.expectApproxEqAbs(
                                expected.jac.get(rr, cc),
                                actual.jac.get(rr, cc),
                                allowed,
                            );
                        }
                    }
                    const recovered = try map.inv(expected.coords.x, expected.coords.y);
                    try std.testing.expectApproxEqAbs(x, recovered.x, inv_allowed);
                    try std.testing.expectApproxEqAbs(y, recovered.y, inv_allowed);
                }
            }
        }
    }
}
