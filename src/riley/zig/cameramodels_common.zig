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

const cfg = buildconfig.config;
const tol = cfg.tolerance;

pub const DistortionModel = union(enum) {
    none,
    brown_conrady: BrownConrady,
    brown_conrady_ext: BrownConradyExt,
};

pub const BrownConrady = struct {
    k1: f64 = 0,
    k2: f64 = 0,
    k3: f64 = 0,
    p1: f64 = 0,
    p2: f64 = 0,

    pub fn forward(self: BrownConrady, x: f64, y: f64) [2]f64 {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const radial_scale = 1.0 + self.k1 * r2 + self.k2 * r4 + self.k3 * r6;
        return distortionForwardFromRadialScale(
            x,
            y,
            radial_scale,
            self.p1,
            self.p2,
        );
    }

    pub fn forwardWithJac(
        self: BrownConrady,
        x: f64,
        y: f64,
    ) DistortionForwardJacResult {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const radial_scale = 1.0 + self.k1 * r2 + self.k2 * r4 + self.k3 * r6;
        const dradial_dr2 = self.k1 + 2.0 * self.k2 * r2 + 3.0 * self.k3 * r4;
        return distortionForwardWithJacFromRadialScale(
            x,
            y,
            radial_scale,
            dradial_dr2,
            self.p1,
            self.p2,
        );
    }

    pub fn inverse(
        self: BrownConrady,
        x_d: f64,
        y_d: f64,
    ) !DistortionInverseResult {
        return try distortionInverseFromModel(BrownConrady, self, x_d, y_d);
    }
};

pub const BrownConradyExt = struct {
    k1: f64 = 0,
    k2: f64 = 0,
    k3: f64 = 0,
    k4: f64 = 0,
    k5: f64 = 0,
    k6: f64 = 0,
    p1: f64 = 0,
    p2: f64 = 0,

    pub fn forward(self: BrownConradyExt, x: f64, y: f64) [2]f64 {
        const radial = self.calcRadialScaleAndDerivative(x, y);
        return distortionForwardFromRadialScale(
            x,
            y,
            radial.radial_scale,
            self.p1,
            self.p2,
        );
    }

    pub fn forwardWithJac(
        self: BrownConradyExt,
        x: f64,
        y: f64,
    ) DistortionForwardJacResult {
        const radial = self.calcRadialScaleAndDerivative(x, y);
        return distortionForwardWithJacFromRadialScale(
            x,
            y,
            radial.radial_scale,
            radial.dradial_dr2,
            self.p1,
            self.p2,
        );
    }

    pub fn inverse(
        self: BrownConradyExt,
        x_d: f64,
        y_d: f64,
    ) !DistortionInverseResult {
        return try distortionInverseFromModel(BrownConradyExt, self, x_d, y_d);
    }

    fn calcRadialScaleAndDerivative(
        self: BrownConradyExt,
        x: f64,
        y: f64,
    ) struct { radial_scale: f64, dradial_dr2: f64 } {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const numerator = 1.0 + self.k1 * r2 + self.k2 * r4 + self.k3 * r6;
        const denominator = 1.0 + self.k4 * r2 + self.k5 * r4 + self.k6 * r6;
        const dnum_dr2 = self.k1 + 2.0 * self.k2 * r2 + 3.0 * self.k3 * r4;
        const dden_dr2 = self.k4 + 2.0 * self.k5 * r2 + 3.0 * self.k6 * r4;
        const radial_scale = numerator / denominator;
        const dradial_dr2 =
            (dnum_dr2 * denominator - numerator * dden_dr2) /
            (denominator * denominator);
        return .{
            .radial_scale = radial_scale,
            .dradial_dr2 = dradial_dr2,
        };
    }
};

pub const DistortionInverseResult = struct {
    x: f64,
    y: f64,
};

pub const DistortionForwardJacResult = struct {
    x_d: f64,
    y_d: f64,
    jac: [2][2]f64,
};

fn distortionForwardFromRadialScale(
    x: f64,
    y: f64,
    radial_scale: f64,
    p1: f64,
    p2: f64,
) [2]f64 {
    const r2 = x * x + y * y;
    const x_d = x * radial_scale + 2.0 * p1 * x * y + p2 * (r2 + 2.0 * x * x);
    const y_d = y * radial_scale + p1 * (r2 + 2.0 * y * y) + 2.0 * p2 * x * y;
    return .{ x_d, y_d };
}

fn distortionForwardWithJacFromRadialScale(
    x: f64,
    y: f64,
    radial_scale: f64,
    dradial_dr2: f64,
    p1: f64,
    p2: f64,
) DistortionForwardJacResult {
    const distorted = distortionForwardFromRadialScale(
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
        .x_d = distorted[0],
        .y_d = distorted[1],
        .jac = .{
            .{ dx_fwd_dx, dx_fwd_dy },
            .{ dy_fwd_dx, dy_fwd_dy },
        },
    };
}

fn distortionInverseFromModel(
    comptime DistortionType: type,
    distortion: DistortionType,
    x_d: f64,
    y_d: f64,
) !DistortionInverseResult {
    var x = x_d;
    var y = y_d;

    const max_iters = cfg.distortion_newton_iter_max;
    const tol_resid = tol.distortion.residual;
    const tol_delta = tol.distortion.delta;

    for (0..max_iters) |_| {
        const fwd = distortion.forwardWithJac(x, y);
        const f0 = fwd.x_d - x_d;
        const f1 = fwd.y_d - y_d;

        if (@max(@abs(f0), @abs(f1)) < tol_resid) {
            return .{ .x = x, .y = y };
        }

        const a = fwd.jac[0][0];
        const b = fwd.jac[0][1];
        const c = fwd.jac[1][0];
        const d = fwd.jac[1][1];

        const det = a * d - b * c;
        if (@abs(det) < tol.distortion.determinant) {
            return error.SingularJacobian;
        }

        const delta_x = (-f0 * d + b * f1) / det;
        const delta_y = (c * f0 - a * f1) / det;

        x += delta_x;
        y += delta_y;

        if (@max(@abs(delta_x), @abs(delta_y)) < tol_delta) {
            return .{ .x = x, .y = y };
        }
    }

    return error.DistortionInverseFailed;
}

pub const SeparablePSF = enum {
    no,
    yes,
};

pub const PixelBoxPSF = struct {
    support_rad_px: f64 = 0.5,
};

pub const GaussianPSF = struct {
    sigma_px: f64,
    support_rad_px: f64,
    separable: SeparablePSF = .yes,
};

pub const AnisotropicGaussianPSF = struct {
    sigma_x_px: f64,
    sigma_y_px: f64,
    theta_rad: f64 = 0.0,
    support_rad_px: f64,
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
    halo_subpx: u16 = 0,
    radius_x_subpx: usize = 0,
    radius_y_subpx: usize = 0,
    weights_x: []f64 = &.{},
    weights_y: []f64 = &.{},
    weights_2d: []f64 = &.{},

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

fn psfKernelValue1D(psf: PointSpreadFunc, dist_px: f64) f64 {
    const abs_dist = @abs(dist_px);
    return switch (psf) {
        .pixel_box => |box| if (abs_dist <= box.support_rad_px + 1e-12) 1.0 else 0.0,
        .gaussian => |gauss| if (abs_dist <= gauss.support_rad_px + 1e-12)
            @exp(-0.5 * (dist_px * dist_px) / (gauss.sigma_px * gauss.sigma_px))
        else
            0.0,
        .anisotropic_gaussian => unreachable,
    };
}

fn psfKernelValue2D(psf: PointSpreadFunc, dx_px: f64, dy_px: f64) f64 {
    return switch (psf) {
        .pixel_box => |box| if (@abs(dx_px) <= box.support_rad_px + 1e-12 and
            @abs(dy_px) <= box.support_rad_px + 1e-12)
            1.0
        else
            0.0,
        .gaussian => |gauss| if (@abs(dx_px) <= gauss.support_rad_px + 1e-12 and
            @abs(dy_px) <= gauss.support_rad_px + 1e-12)
            @exp(-0.5 * (dx_px * dx_px + dy_px * dy_px) /
                (gauss.sigma_px * gauss.sigma_px))
        else
            0.0,
        .anisotropic_gaussian => |gauss| blk: {
            if (@abs(dx_px) > gauss.support_rad_px + 1e-12 or
                @abs(dy_px) > gauss.support_rad_px + 1e-12)
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

fn normalizeKernel(weights: []f64) void {
    var sum: f64 = 0.0;
    for (weights) |weight| sum += weight;
    if (sum == 0.0) return;
    for (weights) |*weight| weight.* /= sum;
}

fn buildKernel1D(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    radius_subpx: usize,
    sub_sample: u8,
) ![]f64 {
    const size = 2 * radius_subpx + 1;
    const weights = try allocator.alloc(f64, size);
    const sub_samp_f = @as(f64, @floatFromInt(sub_sample));

    for (0..size) |ii| {
        const offset = @as(isize, @intCast(ii)) - @as(isize, @intCast(radius_subpx));
        const dist_px = @as(f64, @floatFromInt(offset)) / sub_samp_f;
        weights[ii] = psfKernelValue1D(psf, dist_px);
    }

    normalizeKernel(weights);
    return weights;
}

fn buildKernel2D(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    radius_x_subpx: usize,
    radius_y_subpx: usize,
    sub_sample: u8,
) ![]f64 {
    const width = 2 * radius_x_subpx + 1;
    const height = 2 * radius_y_subpx + 1;
    const weights = try allocator.alloc(f64, width * height);
    const sub_samp_f = @as(f64, @floatFromInt(sub_sample));

    for (0..height) |yy| {
        const y_off = @as(isize, @intCast(yy)) - @as(isize, @intCast(radius_y_subpx));
        const dy_px = @as(f64, @floatFromInt(y_off)) / sub_samp_f;
        for (0..width) |xx| {
            const x_off = @as(isize, @intCast(xx)) - @as(isize, @intCast(radius_x_subpx));
            const dx_px = @as(f64, @floatFromInt(x_off)) / sub_samp_f;
            
            weights[yy * width + xx] = psfKernelValue2D(psf, dx_px, dy_px);
        }
    }

    normalizeKernel(weights);
    return weights;
}

pub fn preparePSF(
    allocator: std.mem.Allocator,
    psf: PointSpreadFunc,
    sub_sample: u8,
) !PreparedPSF {
    switch (psf) {
        .pixel_box => |box| {
            if (box.support_rad_px <= 0.5 + 1e-12) {
                return .{};
            }
            const halo_px: u16 = @intCast(@max(
                @as(usize, 0),
                @as(usize, @intFromFloat(@ceil(box.support_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(box.support_rad_px * @as(f64, @floatFromInt(sub_sample))),
            );
            return .{
                .mode = .separable,
                .halo_px = halo_px,
                .halo_subpx = halo_px * sub_sample,
                .radius_x_subpx = radius_subpx,
                .radius_y_subpx = radius_subpx,
                .weights_x = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                .weights_y = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
            };
        },
        .gaussian => |gauss| {
            const halo_px: u16 = @intCast(@max(
                @as(usize, 0),
                @as(usize, @intFromFloat(@ceil(gauss.support_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(gauss.support_rad_px * @as(f64, @floatFromInt(sub_sample))),
            );
            if (gauss.separable == .yes) {
                return .{
                    .mode = .separable,
                    .halo_px = halo_px,
                    .halo_subpx = halo_px * sub_sample,
                    .radius_x_subpx = radius_subpx,
                    .radius_y_subpx = radius_subpx,
                    .weights_x = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                    .weights_y = try buildKernel1D(allocator, psf, radius_subpx, sub_sample),
                };
            }
            return .{
                .mode = .nonseparable,
                .halo_px = halo_px,
                .halo_subpx = halo_px * sub_sample,
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
                @as(usize, @intFromFloat(@ceil(gauss.support_rad_px))),
            ));
            const radius_subpx: usize = @intFromFloat(
                @ceil(gauss.support_rad_px * @as(f64, @floatFromInt(sub_sample))),
            );
            const axis_aligned = @abs(@sin(gauss.theta_rad)) < 1e-12;
            if (gauss.separable == .yes and axis_aligned) {
                const psf_x = PointSpreadFunc{
                    .gaussian = .{
                        .sigma_px = gauss.sigma_x_px,
                        .support_rad_px = gauss.support_rad_px,
                        .separable = .yes,
                    },
                };
                const psf_y = PointSpreadFunc{
                    .gaussian = .{
                        .sigma_px = gauss.sigma_y_px,
                        .support_rad_px = gauss.support_rad_px,
                        .separable = .yes,
                    },
                };
                return .{
                    .mode = .separable,
                    .halo_px = halo_px,
                    .halo_subpx = halo_px * sub_sample,
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
                .halo_subpx = halo_px * sub_sample,
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
