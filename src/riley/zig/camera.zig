// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const meshio = @import("meshio.zig");
const mo = @import("meshops.zig");
const vector = @import("vecstack.zig");
const matrix = @import("matstack.zig");
const rotation = @import("rotation.zig");
const csvio = @import("csvio.zig");

const ndarray = @import("ndarray.zig");
const buildconfig = @import("buildconfig.zig");
const rastcfg = @import("rasterconfig.zig");
const camera_scalar = @import("camera_scalar.zig");
const camera_simd = @import("camera_simd.zig");
const cfg = buildconfig.config;
const tol = cfg.tolerance;
const camera_impl = if (cfg.simd == .on) camera_simd else camera_scalar;

pub fn allCamerasSharePixels(
    cameras: []const CameraPrepared,
) bool {
    if (cameras.len == 0) {
        return true;
    }

    const pixels_num = cameras[0].pixels_num;
    for (cameras[1..]) |camera| {
        if (!std.meta.eql(camera.pixels_num, pixels_num)) {
            return false;
        }
    }
    return true;
}

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

    const dx_fwd_dx = radial_scale + x * dradial_dx + 2.0 * p1 * y + 6.0 * p2 * x;
    const dx_fwd_dy = x * dradial_dy + 2.0 * p1 * x + 2.0 * p2 * y;
    const dy_fwd_dx = y * dradial_dx + 2.0 * p1 * x + 2.0 * p2 * y;
    const dy_fwd_dy = radial_scale + y * dradial_dy + 6.0 * p1 * y + 2.0 * p2 * x;

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

pub const CameraCoordSys = enum {
    opengl,
    opencv,
};

pub const PsfSeparable = enum {
    no,
    yes,
};

pub const PixelBoxPSF = struct {
    support_rad_px: f64 = 0.5,
};

pub const GaussianPSF = struct {
    sigma_px: f64,
    support_rad_px: f64,
    separable: PsfSeparable = .yes,
};

pub const AnisotropicGaussianPSF = struct {
    sigma_x_px: f64,
    sigma_y_px: f64,
    theta_rad: f64 = 0.0,
    support_rad_px: f64,
    separable: PsfSeparable = .no,
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

fn preparePSF(
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
                    .weights_x = try buildKernel1D(allocator, psf_x, radius_subpx, sub_sample),
                    .weights_y = try buildKernel1D(allocator, psf_y, radius_subpx, sub_sample),
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

pub const CameraInput = struct {
    pixels_num: [2]u32,
    pixels_size: [2]f64,
    pos_world: vector.Vec3f,
    rot_world: rotation.Rotation,
    roi_cent_world: vector.Vec3f,
    focal_length: f64,
    sub_sample: u8,
    distortion: DistortionModel = .none,
    psf: PointSpreadFunc = .{ .pixel_box = .{} },
    coord_sys: CameraCoordSys = .opengl,
};

pub const StereoPairInput = struct {
    cameras: [2]CameraInput,
};

pub const CameraPrepared = struct {
    pixels_num: [2]u32,
    pixels_size: [2]f64,
    pos_world: vector.Vec3f,
    rot_world: rotation.Rotation,
    roi_cent_world: vector.Vec3f,
    focal_length: f64,
    sub_sample: u8,
    sensor_size: [2]f64,
    image_dims: [2]f64,
    image_dist: f64,
    cam_to_world_mat: matrix.Mat44f,
    world_to_cam_mat: matrix.Mat44f,
    distortion: DistortionModel,
    psf: PointSpreadFunc,
    prepared_psf: PreparedPSF,
    coord_sys: CameraCoordSys,
    // Prepared ideal pinhole sample target per output pixel center.
    // Conceptual shape: [height, width, 2]
    ideal_pixel_centers: ndarray.NDArray(f64),
    // [height, width, 6] = [ideal_x, ideal_y, J11, J12, J21, J22]
    pixel_center_jac: ndarray.NDArray(f64),

    pub fn init(
        allocator: std.mem.Allocator,
        input: CameraInput,
    ) !CameraPrepared {
        return try initForSubPixelCenterMap(
            allocator,
            input,
            .full_in_mem,
        );
    }

    pub fn initForSubPixelCenterMap(
        allocator: std.mem.Allocator,
        input: CameraInput,
        subpixel_center_map: rastcfg.SubPixelCenterMap,
    ) !CameraPrepared {
        const actual_sub_sample = if (input.sub_sample == 0) 2 else input.sub_sample;
        const sensor_size = CameraOps.calcSensorSize(input.pixels_num, input.pixels_size);

        const pos_w = input.pos_world;
        const rot_matrix = input.rot_world.matrix;

        const image_dist: f64 = @as(vector.Vec3f, pos_w).sub(input.roi_cent_world).vecLen();

        var image_dims: [2]f64 = undefined;
        image_dims[0] = (image_dist / input.focal_length) * sensor_size[0];
        image_dims[1] = (image_dist / input.focal_length) * sensor_size[1];

        var cam_to_world_mat: matrix.Mat44f = matrix.Mat44f.initIdentity();
        cam_to_world_mat.insertColVec(3, 0, 3, pos_w);
        cam_to_world_mat.insertSubMat(0, 0, 3, 3, rot_matrix);

        const world_to_cam_mat = matrix.Mat44Ops.inv(f64, cam_to_world_mat);

        const ideal_pixel_centers = switch (subpixel_center_map) {
            .full_in_mem => blk: {
                const sub_samp_u: usize = @intCast(actual_sub_sample);
                const dims = [_]usize{
                    input.pixels_num[1] * sub_samp_u,
                    input.pixels_num[0] * sub_samp_u,
                    2,
                };
                break :blk try ndarray.NDArray(f64).initFlat(allocator, dims[0..]);
            },
            else => blk: {
                const dims = [_]usize{ 0, 0, 2 };
                break :blk try ndarray.NDArray(f64).initFlat(allocator, dims[0..]);
            },
        };
        const pixel_center_jac = switch (subpixel_center_map) {
            .affine_jac => blk: {
                const dims = [_]usize{ input.pixels_num[1], input.pixels_num[0], 6 };
                break :blk try ndarray.NDArray(f64).initFlat(allocator, dims[0..]);
            },
            else => blk: {
                const dims = [_]usize{ 0, 0, 6 };
                break :blk try ndarray.NDArray(f64).initFlat(allocator, dims[0..]);
            },
        };

        var self = CameraPrepared{
            .pixels_num = input.pixels_num,
            .pixels_size = input.pixels_size,
            .pos_world = input.pos_world,
            .rot_world = input.rot_world,
            .roi_cent_world = input.roi_cent_world,
            .focal_length = input.focal_length,
            .sub_sample = actual_sub_sample,
            .sensor_size = sensor_size,
            .image_dims = image_dims,
            .image_dist = image_dist,
            .cam_to_world_mat = cam_to_world_mat,
            .world_to_cam_mat = world_to_cam_mat,
            .distortion = input.distortion,
            .psf = input.psf,
            .prepared_psf = try preparePSF(allocator, input.psf, actual_sub_sample),
            .coord_sys = input.coord_sys,
            .ideal_pixel_centers = ideal_pixel_centers,
            .pixel_center_jac = pixel_center_jac,
        };

        switch (subpixel_center_map) {
            .full_in_mem => try self.initFullIdealPixelCenters(),
            .affine_jac => try camera_impl.initPixelCenterJac(&self),
            .per_tile => {},
        }

        return self;
    }

    pub fn deinit(self: *const CameraPrepared, allocator: std.mem.Allocator) void {
        var prepared_psf = self.prepared_psf;
        prepared_psf.deinit(allocator);
        allocator.free(self.ideal_pixel_centers.slice);
        self.ideal_pixel_centers.deinit(allocator);
        allocator.free(self.pixel_center_jac.slice);
        self.pixel_center_jac.deinit(allocator);
    }

    pub fn calcIdealObservedRasterPoint(
        self: *const CameraPrepared,
        observed_x_px: f64,
        observed_y_px: f64,
    ) ![2]f64 {
        const focal_px = self.calcFocalPx();
        const offsets = self.calcRasterOffsets();
        const x_dist = (observed_x_px - offsets.x_off) / focal_px.fx;
        const y_dist = (observed_y_px - offsets.y_off) / focal_px.fy;

        return switch (self.distortion) {
            .none => .{ observed_x_px, observed_y_px },
            .brown_conrady => |bc| blk: {
                const solved = try bc.inverse(x_dist, y_dist);
                break :blk .{
                    solved.x * focal_px.fx + offsets.x_off,
                    solved.y * focal_px.fy + offsets.y_off,
                };
            },
            .brown_conrady_ext => |bc_ext| blk: {
                const solved = try bc_ext.inverse(x_dist, y_dist);
                break :blk .{
                    solved.x * focal_px.fx + offsets.x_off,
                    solved.y * focal_px.fy + offsets.y_off,
                };
            },
        };
    }

    fn initFullIdealPixelCenters(self: *CameraPrepared) !void {
        const sub_samp_u: usize = @intCast(self.sub_sample);
        const sub_samp_f = @as(f64, @floatFromInt(self.sub_sample));
        const subpx_step = 1.0 / sub_samp_f;
        const subpx_off = 0.5 / sub_samp_f;

        const slice = self.ideal_pixel_centers.slice;
        const stride_y = self.ideal_pixel_centers.strides[0];
        const stride_x = self.ideal_pixel_centers.strides[1];

        for (0..self.pixels_num[1] * sub_samp_u) |jj| {
            const subpx_y_f = @as(f64, @floatFromInt(jj)) * subpx_step + subpx_off;
            const row_off = jj * stride_y;

            for (0..self.pixels_num[0] * sub_samp_u) |ii| {
                const subpx_x_f = @as(f64, @floatFromInt(ii)) * subpx_step + subpx_off;
                const ideal = try self.calcIdealObservedRasterPoint(subpx_x_f, subpx_y_f);
                const col_off = ii * stride_x;
                slice[row_off + col_off + 0] = ideal[0];
                slice[row_off + col_off + 1] = ideal[1];
            }
        }
    }

    pub fn calcFocalPx(self: *const CameraPrepared) struct { fx: f64, fy: f64 } {
        return .{
            .fx = self.focal_length / self.pixels_size[0],
            .fy = self.focal_length / self.pixels_size[1],
        };
    }

    pub fn calcRasterOffsets(
        self: *const CameraPrepared,
    ) struct { x_off: f64, y_off: f64 } {
        return .{
            .x_off = 0.5 * @as(f64, @floatFromInt(self.pixels_num[0])),
            .y_off = 0.5 * @as(f64, @floatFromInt(self.pixels_num[1])),
        };
    }
};

pub fn fillTileIdealCentersPerTile(
    ctx_rast: anytype,
    tile: anytype,
    subpx_scratch: anytype,
    subpx_tile_size: usize,
) !void {
    return camera_impl.fillTileIdealCentersPerTile(
        ctx_rast,
        tile,
        subpx_scratch,
        subpx_tile_size,
    );
}

pub fn fillTileIdealCentersAffineJac(
    ctx_rast: anytype,
    tile: anytype,
    subpx_scratch: anytype,
    subpx_tile_size: usize,
) void {
    camera_impl.fillTileIdealCentersAffineJac(
        ctx_rast,
        tile,
        subpx_scratch,
        subpx_tile_size,
    );
}

pub const FOVScaling = struct {
    plane_dist: f64,
    plane_size: [2]f64,
    leng_per_pixel: [2]f64,
    pixel_per_leng: [2]f64,
};

pub const CameraOps = struct {
    const CameraPlaneMetrics = struct {
        sensor_size: [2]f64,
        focal_px: [2]f64,
        principal_point_px: [2]f64,
        roi_plane_dist: f64,
        roi_plane_size: [2]f64,
        avg_leng_per_pixel: f64,
        avg_pixel_per_leng: f64,
    };

    pub fn prepareSlice(
        allocator: std.mem.Allocator,
        camera_inputs: []const CameraInput,
        subpixel_center_map: rastcfg.SubPixelCenterMap,
    ) ![]CameraPrepared {
        const cameras = try allocator.alloc(CameraPrepared, camera_inputs.len);
        for (camera_inputs, 0..) |camera_input, cc| {
            cameras[cc] = CameraPrepared.initForSubPixelCenterMap(
                allocator,
                camera_input,
                subpixel_center_map,
            ) catch |err| {
                for (0..cc) |pp| cameras[pp].deinit(allocator);
                allocator.free(cameras);
                return err;
            };
        }

        return cameras;
    }

    fn parseKeyValueCsv(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        file_name: []const u8,
    ) !std.StringHashMap([]const u8) {
        var file = try dir.openFile(io, file_name, .{ .mode = .read_only });
        defer file.close(io);

        var read_buf: [128 * 1024]u8 = undefined;
        var file_reader = file.reader(io, &read_buf);
        const reader = &file_reader.interface;

        var kv = std.StringHashMap([]const u8).init(allocator);
        errdefer {
            var iter = kv.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            kv.deinit();
        }

        var is_first = true;
        while (try reader.takeDelimiter('\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\t");
            if (trimmed.len == 0) continue;
            if (is_first) {
                is_first = false;
                if (std.mem.eql(u8, trimmed, "key,value")) continue;
            }

            var iter = std.mem.splitScalar(u8, trimmed, ',');
            const key = iter.next() orelse return error.InvalidCameraCsv;
            const value = iter.next() orelse return error.InvalidCameraCsv;
            if (iter.next() != null) return error.InvalidCameraCsv;

            try kv.put(
                try allocator.dupe(u8, std.mem.trim(u8, key, " \r\t")),
                try allocator.dupe(u8, std.mem.trim(u8, value, " \r\t")),
            );
        }

        return kv;
    }

    fn deinitKeyValueCsv(
        allocator: std.mem.Allocator,
        kv: *std.StringHashMap([]const u8),
    ) void {
        var iter = kv.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        kv.deinit();
    }

    fn requireValue(
        kv: *const std.StringHashMap([]const u8),
        key: []const u8,
    ) ![]const u8 {
        return kv.get(key) orelse error.MissingCameraField;
    }

    fn parseF64Value(
        kv: *const std.StringHashMap([]const u8),
        key: []const u8,
    ) !f64 {
        return std.fmt.parseFloat(f64, try requireValue(kv, key));
    }

    fn parseU32Value(
        kv: *const std.StringHashMap([]const u8),
        key: []const u8,
    ) !u32 {
        return std.fmt.parseInt(u32, try requireValue(kv, key), 10);
    }

    fn parseU8Value(
        kv: *const std.StringHashMap([]const u8),
        key: []const u8,
    ) !u8 {
        return std.fmt.parseInt(u8, try requireValue(kv, key), 10);
    }

    pub fn toOpenGLInput(input: CameraInput) CameraInput {
        if (input.coord_sys == .opengl) return input;
        var opengl_input = input;
        const r_opencv = input.rot_world.matrix;
        const r_opencv_t = r_opencv.transpose();
        const neg_t = vector.initVec3(
            f64,
            -input.pos_world.get(0),
            -input.pos_world.get(1),
            -input.pos_world.get(2),
        );
        opengl_input.pos_world = r_opencv_t.mulVec(neg_t);
        var r_riley = r_opencv_t;
        r_riley.slice[1] = -r_riley.slice[1];
        r_riley.slice[2] = -r_riley.slice[2];
        r_riley.slice[4] = -r_riley.slice[4];
        r_riley.slice[5] = -r_riley.slice[5];
        r_riley.slice[7] = -r_riley.slice[7];
        r_riley.slice[8] = -r_riley.slice[8];
        opengl_input.rot_world = rotation.Rotation.fromMat33(r_riley);
        opengl_input.coord_sys = .opengl;
        return opengl_input;
    }

    fn calcPlaneMetrics(
        camera_input: CameraInput,
    ) CameraPlaneMetrics {
        const opengl_input = toOpenGLInput(camera_input);
        const scaling = calcFOVScaling(
            opengl_input,
            opengl_input.roi_cent_world,
        );
        const sensor_size = calcSensorSize(
            opengl_input.pixels_num,
            opengl_input.pixels_size,
        );
        const focal_px_x = opengl_input.focal_length / opengl_input.pixels_size[0];
        const focal_px_y = opengl_input.focal_length / opengl_input.pixels_size[1];
        const principal_x = 0.5 * @as(f64, @floatFromInt(opengl_input.pixels_num[0]));
        const principal_y = 0.5 * @as(f64, @floatFromInt(opengl_input.pixels_num[1]));
        return .{
            .sensor_size = sensor_size,
            .focal_px = .{ focal_px_x, focal_px_y },
            .principal_point_px = .{ principal_x, principal_y },
            .roi_plane_dist = scaling.plane_dist,
            .roi_plane_size = scaling.plane_size,
            .avg_leng_per_pixel = 0.5 * (scaling.leng_per_pixel[0] + scaling.leng_per_pixel[1]),
            .avg_pixel_per_leng = 0.5 * (scaling.pixel_per_leng[0] + scaling.pixel_per_leng[1]),
        };
    }

    fn writeKeyValueRow(
        writer: *std.Io.Writer,
        key: []const u8,
        value: []const u8,
    ) !void {
        try writer.print("{s},{s}\n", .{ key, value });
    }

    fn writeKeyValueF64(
        writer: *std.Io.Writer,
        key: []const u8,
        value: f64,
    ) !void {
        try writer.print("{s},{d:.12}\n", .{ key, value });
    }

    fn writeKeyValueInt(
        writer: *std.Io.Writer,
        key: []const u8,
        value: anytype,
    ) !void {
        try writer.print("{s},{d}\n", .{ key, value });
    }

    fn writeDistortion(
        writer: *std.Io.Writer,
        distortion: DistortionModel,
    ) !void {
        switch (distortion) {
            .none => {
                try writeKeyValueRow(writer, "distortion_model", "none");
                try writeKeyValueF64(writer, "k1", 0.0);
                try writeKeyValueF64(writer, "k2", 0.0);
                try writeKeyValueF64(writer, "k3", 0.0);
                try writeKeyValueF64(writer, "k4", 0.0);
                try writeKeyValueF64(writer, "k5", 0.0);
                try writeKeyValueF64(writer, "k6", 0.0);
                try writeKeyValueF64(writer, "p1", 0.0);
                try writeKeyValueF64(writer, "p2", 0.0);
            },
            .brown_conrady => |model| {
                try writeKeyValueRow(writer, "distortion_model", "brown_conrady");
                try writeKeyValueF64(writer, "k1", model.k1);
                try writeKeyValueF64(writer, "k2", model.k2);
                try writeKeyValueF64(writer, "k3", model.k3);
                try writeKeyValueF64(writer, "k4", 0.0);
                try writeKeyValueF64(writer, "k5", 0.0);
                try writeKeyValueF64(writer, "k6", 0.0);
                try writeKeyValueF64(writer, "p1", model.p1);
                try writeKeyValueF64(writer, "p2", model.p2);
            },
            .brown_conrady_ext => |model| {
                try writeKeyValueRow(writer, "distortion_model", "brown_conrady_ext");
                try writeKeyValueF64(writer, "k1", model.k1);
                try writeKeyValueF64(writer, "k2", model.k2);
                try writeKeyValueF64(writer, "k3", model.k3);
                try writeKeyValueF64(writer, "k4", model.k4);
                try writeKeyValueF64(writer, "k5", model.k5);
                try writeKeyValueF64(writer, "k6", model.k6);
                try writeKeyValueF64(writer, "p1", model.p1);
                try writeKeyValueF64(writer, "p2", model.p2);
            },
        }
    }

    fn loadDistortion(
        kv: *const std.StringHashMap([]const u8),
    ) !DistortionModel {
        const model_name = try requireValue(kv, "distortion_model");
        if (std.mem.eql(u8, model_name, "none")) {
            return .none;
        }
        if (std.mem.eql(u8, model_name, "brown_conrady")) {
            return .{ .brown_conrady = .{
                .k1 = try parseF64Value(kv, "k1"),
                .k2 = try parseF64Value(kv, "k2"),
                .k3 = try parseF64Value(kv, "k3"),
                .p1 = try parseF64Value(kv, "p1"),
                .p2 = try parseF64Value(kv, "p2"),
            } };
        }
        if (std.mem.eql(u8, model_name, "brown_conrady_ext")) {
            return .{ .brown_conrady_ext = .{
                .k1 = try parseF64Value(kv, "k1"),
                .k2 = try parseF64Value(kv, "k2"),
                .k3 = try parseF64Value(kv, "k3"),
                .k4 = try parseF64Value(kv, "k4"),
                .k5 = try parseF64Value(kv, "k5"),
                .k6 = try parseF64Value(kv, "k6"),
                .p1 = try parseF64Value(kv, "p1"),
                .p2 = try parseF64Value(kv, "p2"),
            } };
        }
        return error.InvalidDistortionModel;
    }

    pub fn saveCamera(
        io: std.Io,
        out_dir: std.Io.Dir,
        file_name: []const u8,
        camera_idx: usize,
        camera_input: CameraInput,
    ) !void {
        const metrics = calcPlaneMetrics(camera_input);

        const csv_file = try out_dir.createFile(io, file_name, .{});
        defer csv_file.close(io);
        var write_buf: [4096]u8 = undefined;
        var file_writer = csv_file.writer(io, &write_buf);
        const writer = &file_writer.interface;

        try writer.writeAll("key,value\n");
        try writeKeyValueInt(writer, "camera_idx", camera_idx);
        const coord_sys_str = if (camera_input.coord_sys == .opencv) "opencv" else "opengl";
        try writeKeyValueRow(writer, "coord_sys", coord_sys_str);
        try writeKeyValueInt(writer, "pixels_x", camera_input.pixels_num[0]);
        try writeKeyValueInt(writer, "pixels_y", camera_input.pixels_num[1]);
        try writeKeyValueF64(writer, "pixel_size_x_m", camera_input.pixels_size[0]);
        try writeKeyValueF64(writer, "pixel_size_y_m", camera_input.pixels_size[1]);
        try writeKeyValueF64(writer, "focal_length_m", camera_input.focal_length);
        try writeKeyValueInt(writer, "sub_sample", camera_input.sub_sample);
        var pos_val = camera_input.pos_world;
        var rot_val = camera_input.rot_world;

        if (camera_input.coord_sys == .opencv) {
            const r_riley = camera_input.rot_world.matrix;
            const r_riley_t = r_riley.transpose();
            var r_opencv = r_riley_t;
            r_opencv.slice[3] = -r_opencv.slice[3];
            r_opencv.slice[4] = -r_opencv.slice[4];
            r_opencv.slice[5] = -r_opencv.slice[5];
            r_opencv.slice[6] = -r_opencv.slice[6];
            r_opencv.slice[7] = -r_opencv.slice[7];
            r_opencv.slice[8] = -r_opencv.slice[8];

            const r_opencv_c = r_opencv.mulVec(camera_input.pos_world);
            pos_val = vector.initVec3(
                f64,
                -r_opencv_c.get(0),
                -r_opencv_c.get(1),
                -r_opencv_c.get(2),
            );
            rot_val = rotation.Rotation.fromMat33(r_opencv);
        }

        try writeKeyValueF64(writer, "pos_x_m", pos_val.get(0));
        try writeKeyValueF64(writer, "pos_y_m", pos_val.get(1));
        try writeKeyValueF64(writer, "pos_z_m", pos_val.get(2));
        try writeKeyValueF64(
            writer,
            "rot_alpha_z_deg",
            std.math.radiansToDegrees(rot_val.alpha_z),
        );
        try writeKeyValueF64(
            writer,
            "rot_beta_y_deg",
            std.math.radiansToDegrees(rot_val.beta_y),
        );
        try writeKeyValueF64(
            writer,
            "rot_gamma_x_deg",
            std.math.radiansToDegrees(rot_val.gamma_x),
        );
        try writeKeyValueF64(
            writer,
            "roi_cent_x_m",
            camera_input.roi_cent_world.get(0),
        );
        try writeKeyValueF64(
            writer,
            "roi_cent_y_m",
            camera_input.roi_cent_world.get(1),
        );
        try writeKeyValueF64(
            writer,
            "roi_cent_z_m",
            camera_input.roi_cent_world.get(2),
        );
        try writeKeyValueF64(writer, "sensor_size_x_m", metrics.sensor_size[0]);
        try writeKeyValueF64(writer, "sensor_size_y_m", metrics.sensor_size[1]);
        try writeKeyValueF64(writer, "fx_px", metrics.focal_px[0]);
        try writeKeyValueF64(writer, "fy_px", metrics.focal_px[1]);
        try writeKeyValueF64(writer, "cx_px", metrics.principal_point_px[0]);
        try writeKeyValueF64(writer, "cy_px", metrics.principal_point_px[1]);
        try writeKeyValueF64(writer, "roi_plane_dist_m", metrics.roi_plane_dist);
        try writeKeyValueF64(writer, "roi_plane_size_x_m", metrics.roi_plane_size[0]);
        try writeKeyValueF64(writer, "roi_plane_size_y_m", metrics.roi_plane_size[1]);
        try writeKeyValueF64(
            writer,
            "avg_leng_per_pixel_m",
            metrics.avg_leng_per_pixel,
        );
        try writeKeyValueF64(
            writer,
            "avg_pixel_per_leng",
            metrics.avg_pixel_per_leng,
        );
        try writeDistortion(writer, camera_input.distortion);
        try file_writer.flush();
    }

    pub fn loadCamera(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        file_name: []const u8,
    ) !CameraInput {
        var kv = try parseKeyValueCsv(allocator, io, dir, file_name);
        defer deinitKeyValueCsv(allocator, &kv);

        const coord_sys = blk: {
            if (kv.get("coord_sys")) |sys_str| {
                if (std.mem.eql(u8, sys_str, "opencv")) {
                    break :blk CameraCoordSys.opencv;
                }
            }
            break :blk CameraCoordSys.opengl;
        };

        var camera_input = CameraInput{
            .pixels_num = .{
                try parseU32Value(&kv, "pixels_x"),
                try parseU32Value(&kv, "pixels_y"),
            },
            .pixels_size = .{
                try parseF64Value(&kv, "pixel_size_x_m"),
                try parseF64Value(&kv, "pixel_size_y_m"),
            },
            .pos_world = vector.initVec3(
                f64,
                try parseF64Value(&kv, "pos_x_m"),
                try parseF64Value(&kv, "pos_y_m"),
                try parseF64Value(&kv, "pos_z_m"),
            ),
            .rot_world = rotation.Rotation.init(
                std.math.degreesToRadians(
                    try parseF64Value(&kv, "rot_alpha_z_deg"),
                ),
                std.math.degreesToRadians(
                    try parseF64Value(&kv, "rot_beta_y_deg"),
                ),
                std.math.degreesToRadians(
                    try parseF64Value(&kv, "rot_gamma_x_deg"),
                ),
            ),
            .roi_cent_world = vector.initVec3(
                f64,
                try parseF64Value(&kv, "roi_cent_x_m"),
                try parseF64Value(&kv, "roi_cent_y_m"),
                try parseF64Value(&kv, "roi_cent_z_m"),
            ),
            .focal_length = try parseF64Value(&kv, "focal_length_m"),
            .sub_sample = try parseU8Value(&kv, "sub_sample"),
            .distortion = try loadDistortion(&kv),
            .coord_sys = coord_sys,
        };

        if (coord_sys == .opencv) {
            camera_input = CameraOps.toOpenGLInput(camera_input);
            camera_input.coord_sys = .opencv;
        }

        return camera_input;
    }

    pub fn saveStereoPair(
        io: std.Io,
        out_dir: std.Io.Dir,
        stereo_file_name: []const u8,
        stereo_pair: StereoPairInput,
    ) !void {
        var suffix: []const u8 = "";
        if (stereo_file_name.len > 11 and std.mem.eql(
            u8,
            stereo_file_name[0..11],
            "stereo_data",
        )) {
            suffix = stereo_file_name[11 .. stereo_file_name.len - 4];
        }

        var cam0_name_buf: [64]u8 = undefined;
        const cam0_name = try std.fmt.bufPrint(
            &cam0_name_buf,
            "cam0_data{s}.csv",
            .{suffix},
        );

        var cam1_name_buf: [64]u8 = undefined;
        const cam1_name = try std.fmt.bufPrint(
            &cam1_name_buf,
            "cam1_data{s}.csv",
            .{suffix},
        );

        try saveCamera(io, out_dir, cam0_name, 0, stereo_pair.cameras[0]);
        try saveCamera(io, out_dir, cam1_name, 1, stereo_pair.cameras[1]);

        const cam0 = stereo_pair.cameras[0];
        const cam1 = stereo_pair.cameras[1];
        const cam0_opengl = toOpenGLInput(cam0);
        const cam1_opengl = toOpenGLInput(cam1);
        const baseline = cam1_opengl.pos_world.sub(cam0_opengl.pos_world);
        const baseline_len = baseline.vecLen();
        const cam0_metrics = calcPlaneMetrics(cam0);
        const cam1_metrics = calcPlaneMetrics(cam1);

        const csv_file = try out_dir.createFile(io, stereo_file_name, .{});
        defer csv_file.close(io);
        var write_buf: [4096]u8 = undefined;
        var file_writer = csv_file.writer(io, &write_buf);
        const writer = &file_writer.interface;

        try writer.writeAll("key,value\n");
        try writeKeyValueRow(writer, "cam0_file", cam0_name);
        try writeKeyValueRow(writer, "cam1_file", cam1_name);
        try writeKeyValueF64(writer, "roi_cent_x_m", cam0.roi_cent_world.get(0));
        try writeKeyValueF64(writer, "roi_cent_y_m", cam0.roi_cent_world.get(1));
        try writeKeyValueF64(writer, "roi_cent_z_m", cam0.roi_cent_world.get(2));
        try writeKeyValueF64(writer, "baseline_x_m", baseline.get(0));
        try writeKeyValueF64(writer, "baseline_y_m", baseline.get(1));
        try writeKeyValueF64(writer, "baseline_z_m", baseline.get(2));
        try writeKeyValueF64(writer, "baseline_len_m", baseline_len);
        try writeKeyValueF64(
            writer,
            "rel_rot_alpha_z_deg",
            std.math.radiansToDegrees(
                cam1_opengl.rot_world.alpha_z - cam0_opengl.rot_world.alpha_z,
            ),
        );
        try writeKeyValueF64(
            writer,
            "rel_rot_beta_y_deg",
            std.math.radiansToDegrees(
                cam1_opengl.rot_world.beta_y - cam0_opengl.rot_world.beta_y,
            ),
        );
        try writeKeyValueF64(
            writer,
            "rel_rot_gamma_x_deg",
            std.math.radiansToDegrees(
                cam1_opengl.rot_world.gamma_x - cam0_opengl.rot_world.gamma_x,
            ),
        );
        try writeKeyValueF64(writer, "cam0_fx_px", cam0_metrics.focal_px[0]);
        try writeKeyValueF64(writer, "cam0_fy_px", cam0_metrics.focal_px[1]);
        try writeKeyValueF64(
            writer,
            "cam0_cx_px",
            cam0_metrics.principal_point_px[0],
        );
        try writeKeyValueF64(
            writer,
            "cam0_cy_px",
            cam0_metrics.principal_point_px[1],
        );
        try writeKeyValueF64(
            writer,
            "cam0_focal_length_m",
            cam0.focal_length,
        );
        try writeKeyValueF64(writer, "cam1_fx_px", cam1_metrics.focal_px[0]);
        try writeKeyValueF64(writer, "cam1_fy_px", cam1_metrics.focal_px[1]);
        try writeKeyValueF64(
            writer,
            "cam1_cx_px",
            cam1_metrics.principal_point_px[0],
        );
        try writeKeyValueF64(
            writer,
            "cam1_cy_px",
            cam1_metrics.principal_point_px[1],
        );
        try writeKeyValueF64(
            writer,
            "cam1_focal_length_m",
            cam1.focal_length,
        );
        try file_writer.flush();
    }

    pub fn loadStereoPair(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        stereo_file_name: []const u8,
    ) !StereoPairInput {
        var kv = try parseKeyValueCsv(allocator, io, dir, stereo_file_name);
        defer deinitKeyValueCsv(allocator, &kv);

        const cam0_file = try requireValue(&kv, "cam0_file");
        const cam1_file = try requireValue(&kv, "cam1_file");

        return .{
            .cameras = .{
                try loadCamera(allocator, io, dir, cam0_file),
                try loadCamera(allocator, io, dir, cam1_file),
            },
        };
    }

    pub fn fovFromCamRot(
        cam_rot: rotation.Rotation,
        coords_world: *const meshio.Coords,
    ) [2]f64 {
        const world_to_cam_mat = matrix.Mat33Ops.inv(f64, cam_rot.matrix);
        var bb_cam_vec = world_to_cam_mat.mulVec(coords_world.getVec3(0));
        var bb_cam_max = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };
        var bb_cam_min = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };

        for (1..coords_world.mat.rows_num) |nn| {
            bb_cam_vec = world_to_cam_mat.mulVec(coords_world.getVec3(nn));

            if (bb_cam_vec.get(0) > bb_cam_max[0]) {
                bb_cam_max[0] = bb_cam_vec.get(0);
            } else if (bb_cam_vec.get(0) < bb_cam_min[0]) {
                bb_cam_min[0] = bb_cam_vec.get(0);
            }

            if (bb_cam_vec.get(1) > bb_cam_max[1]) {
                bb_cam_max[1] = bb_cam_vec.get(1);
            } else if (bb_cam_vec.get(1) < bb_cam_min[1]) {
                bb_cam_min[1] = bb_cam_vec.get(1);
            }
        }

        const fov_x = bb_cam_max[0] - bb_cam_min[0];
        const fov_y = bb_cam_max[1] - bb_cam_min[1];
        const fov_leng = [2]f64{ fov_x, fov_y };
        return fov_leng;
    }

    pub fn fovFromCamRotOverMeshes(
        cam_rot: rotation.Rotation,
        meshes: []const mo.MeshInput,
    ) [2]f64 {
        const world_to_cam_mat = matrix.Mat33Ops.inv(f64, cam_rot.matrix);
        var first_coord: ?vector.Vec3f = null;
        var bb_cam_max: [2]f64 = undefined;
        var bb_cam_min: [2]f64 = undefined;

        for (meshes) |mesh| {
            for (0..mesh.coords.mat.rows_num) |nn| {
                const coord = mesh.coords.getVec3(nn);
                const bb_cam_vec = world_to_cam_mat.mulVec(coord);

                if (first_coord == null) {
                    first_coord = coord;
                    bb_cam_max = .{ bb_cam_vec.get(0), bb_cam_vec.get(1) };
                    bb_cam_min = .{ bb_cam_vec.get(0), bb_cam_vec.get(1) };
                    continue;
                }

                if (bb_cam_vec.get(0) > bb_cam_max[0]) {
                    bb_cam_max[0] = bb_cam_vec.get(0);
                } else if (bb_cam_vec.get(0) < bb_cam_min[0]) {
                    bb_cam_min[0] = bb_cam_vec.get(0);
                }

                if (bb_cam_vec.get(1) > bb_cam_max[1]) {
                    bb_cam_max[1] = bb_cam_vec.get(1);
                } else if (bb_cam_vec.get(1) < bb_cam_min[1]) {
                    bb_cam_min[1] = bb_cam_vec.get(1);
                }
            }
        }

        const fov_x = bb_cam_max[0] - bb_cam_min[0];
        const fov_y = bb_cam_max[1] - bb_cam_min[1];
        const fov_leng = [2]f64{ fov_x, fov_y };
        return fov_leng;
    }

    pub fn calcSensorSize(pixels_num: [2]u32, pixels_size: [2]f64) [2]f64 {
        var sensor_size: [2]f64 = undefined;
        sensor_size[0] = @as(f64, @floatFromInt(pixels_num[0])) * pixels_size[0];
        sensor_size[1] = @as(f64, @floatFromInt(pixels_num[1])) * pixels_size[1];
        return sensor_size;
    }

    pub fn imageDistFromFov(
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        fov_leng: [2]f64,
    ) [2]f64 {
        const sensor_size = calcSensorSize(pixels_num, pixels_size);

        var fov_angle: [2]f64 = undefined;
        fov_angle[0] = 2 * std.math.atan(sensor_size[0] / (2 * focal_leng));
        fov_angle[1] = 2 * std.math.atan(sensor_size[1] / (2 * focal_leng));

        var image_dist: [2]f64 = undefined;
        image_dist[0] = fov_leng[0] / (2 * std.math.tan(fov_angle[0] / 2));
        image_dist[1] = fov_leng[1] / (2 * std.math.tan(fov_angle[1] / 2));

        return image_dist;
    }

    pub fn calcFOVScaling(
        camera_input: CameraInput,
        plane_cent_world: vector.Vec3f,
    ) FOVScaling {
        const cam_z_axis = camera_input.rot_world.matrix.getColVec(2);
        const plane_vec = (&camera_input.pos_world).sub(plane_cent_world);
        const plane_dist = @abs(plane_vec.dot(cam_z_axis));
        const sensor_size = calcSensorSize(
            camera_input.pixels_num,
            camera_input.pixels_size,
        );

        var plane_size: [2]f64 = undefined;
        plane_size[0] = (plane_dist / camera_input.focal_length) * sensor_size[0];
        plane_size[1] = (plane_dist / camera_input.focal_length) * sensor_size[1];

        var leng_per_pixel: [2]f64 = undefined;
        leng_per_pixel[0] = plane_size[0] /
            @as(f64, @floatFromInt(camera_input.pixels_num[0]));
        leng_per_pixel[1] = plane_size[1] /
            @as(f64, @floatFromInt(camera_input.pixels_num[1]));

        var pixel_per_leng: [2]f64 = undefined;
        pixel_per_leng[0] = 1.0 / leng_per_pixel[0];
        pixel_per_leng[1] = 1.0 / leng_per_pixel[1];

        return .{
            .plane_dist = plane_dist,
            .plane_size = plane_size,
            .leng_per_pixel = leng_per_pixel,
            .pixel_per_leng = pixel_per_leng,
        };
    }

    pub fn calcCamPos(
        roi_pos_world: vector.Vec3f,
        cam_rot: rotation.Rotation,
        image_dist: f64,
    ) vector.Vec3f {
        var cam_z_axis_vec = cam_rot.matrix.getColVec(2);
        cam_z_axis_vec = cam_z_axis_vec.mulScalar(image_dist);
        const cam_pos = (&roi_pos_world).add(cam_z_axis_vec);
        return cam_pos;
    }

    pub fn centFromCoordsMean(coords_world: *const meshio.Coords) vector.Vec3f {
        var cent_world = vector.Vec3f.initZeros();
        const coords_num = coords_world.mat.rows_num;

        for (0..coords_num) |nn| {
            cent_world.slice[0] += coords_world.mat.get(nn, 0);
            cent_world.slice[1] += coords_world.mat.get(nn, 1);
            cent_world.slice[2] += coords_world.mat.get(nn, 2);
        }

        const inv_coords_num = 1.0 / @as(f64, @floatFromInt(coords_num));
        return cent_world.mulScalar(inv_coords_num);
    }

    pub fn roiCentFromCoords(coords_world: *const meshio.Coords) vector.Vec3f {
        var max_vec: vector.Vec3f = undefined;
        max_vec.slice[0] = coords_world.mat.maxByRow(0);
        max_vec.slice[1] = coords_world.mat.maxByRow(1);
        max_vec.slice[2] = coords_world.mat.maxByRow(2);

        var min_vec: vector.Vec3f = undefined;
        min_vec.slice[0] = coords_world.mat.minByRow(0);
        min_vec.slice[1] = coords_world.mat.minByRow(1);
        min_vec.slice[2] = coords_world.mat.minByRow(2);

        var roi_cent: vector.Vec3f = (&max_vec).add(min_vec);
        roi_cent = roi_cent.mulScalar(0.5);
        return roi_cent;
    }

    pub fn lookAtPoint(
        pos_world: vector.Vec3f,
        target_world: vector.Vec3f,
    ) rotation.Rotation {
        const cam_z_axis = (&pos_world).sub(target_world);
        const cam_z_leng = cam_z_axis.vecLen();

        if (cam_z_leng == 0.0) {
            return rotation.Rotation.init(0, 0, 0);
        }

        const cam_z_unit = cam_z_axis.mulScalar(1.0 / cam_z_leng);
        const alpha_z = std.math.atan2(cam_z_unit.get(1), cam_z_unit.get(0));
        const beta_y = std.math.atan2(
            @sqrt(
                cam_z_unit.get(0) * cam_z_unit.get(0) +
                    cam_z_unit.get(1) * cam_z_unit.get(1),
            ),
            cam_z_unit.get(2),
        );

        return rotation.Rotation.init(alpha_z, beta_y, 0.0);
    }

    pub fn roiCentOverMeshes(meshes: []const mo.MeshInput) vector.Vec3f {
        var bb_min = [3]f64{ std.math.inf(f64), std.math.inf(f64), std.math.inf(f64) };
        var bb_max = [3]f64{ -std.math.inf(f64), -std.math.inf(f64), -std.math.inf(f64) };

        for (meshes) |mesh| {
            for (0..3) |ii| {
                const mesh_min = mesh.coords.mat.minByRow(ii);
                const mesh_max = mesh.coords.mat.maxByRow(ii);
                if (mesh_min < bb_min[ii]) bb_min[ii] = mesh_min;
                if (mesh_max > bb_max[ii]) bb_max[ii] = mesh_max;
            }
        }

        const max_vec = vector.initVec3(f64, bb_max[0], bb_max[1], bb_max[2]);
        const min_vec = vector.initVec3(f64, bb_min[0], bb_min[1], bb_min[2]);

        var roi_cent: vector.Vec3f = (&max_vec).add(min_vec);
        roi_cent = roi_cent.mulScalar(0.5);
        return roi_cent;
    }

    pub fn imageDistFillFrameFromRot(
        coords_world: *const meshio.Coords,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) f64 {
        var fov_leng: [2]f64 = fovFromCamRot(cam_rot, coords_world);
        fov_leng[0] = frame_fill * fov_leng[0];
        fov_leng[1] = frame_fill * fov_leng[1];

        const image_dists = imageDistFromFov(
            pixels_num,
            pixels_size,
            focal_leng,
            fov_leng,
        );
        return @max(image_dists[0], image_dists[1]);
    }

    fn imageDistFillFrameFromRotAndTarget(
        coords_world: *const meshio.Coords,
        target_world: vector.Vec3f,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) f64 {
        const world_to_cam_mat = matrix.Mat33Ops.inv(f64, cam_rot.matrix);
        var coord_cam = world_to_cam_mat.mulVec(coords_world.getVec3(0).sub(target_world));
        var max_abs_x = @abs(coord_cam.get(0));
        var max_abs_y = @abs(coord_cam.get(1));

        for (1..coords_world.mat.rows_num) |nn| {
            coord_cam = world_to_cam_mat.mulVec(coords_world.getVec3(nn).sub(target_world));
            max_abs_x = @max(max_abs_x, @abs(coord_cam.get(0)));
            max_abs_y = @max(max_abs_y, @abs(coord_cam.get(1)));
        }

        const fov_leng = [2]f64{
            2.0 * frame_fill * max_abs_x,
            2.0 * frame_fill * max_abs_y,
        };
        const image_dists = imageDistFromFov(
            pixels_num,
            pixels_size,
            focal_leng,
            fov_leng,
        );
        return @max(image_dists[0], image_dists[1]);
    }

    pub fn posFillFrameFromRot(
        coords_world: *const meshio.Coords,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) vector.Vec3f {
        const image_dist = imageDistFillFrameFromRot(
            coords_world,
            pixels_num,
            pixels_size,
            focal_leng,
            cam_rot,
            frame_fill,
        );
        const roi_pos: vector.Vec3f = roiCentFromCoords(coords_world);
        const cam_pos: vector.Vec3f = calcCamPos(roi_pos, cam_rot, image_dist);
        return cam_pos;
    }

    pub fn posFillFrameFromRotAndTarget(
        coords_world: *const meshio.Coords,
        target_world: vector.Vec3f,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) vector.Vec3f {
        const image_dist = imageDistFillFrameFromRotAndTarget(
            coords_world,
            target_world,
            pixels_num,
            pixels_size,
            focal_leng,
            cam_rot,
            frame_fill,
        );
        return calcCamPos(target_world, cam_rot, image_dist);
    }

    fn imageDistFillFrameFromRotOverMeshesAndTarget(
        meshes: []const mo.MeshInput,
        target_world: vector.Vec3f,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) f64 {
        const world_to_cam_mat = matrix.Mat33Ops.inv(f64, cam_rot.matrix);
        var max_abs_x: f64 = 0.0;
        var max_abs_y: f64 = 0.0;
        var is_first = true;

        for (meshes) |mesh| {
            for (0..mesh.coords.mat.rows_num) |nn| {
                const coord_cam = world_to_cam_mat.mulVec(
                    mesh.coords.getVec3(nn).sub(target_world),
                );
                if (is_first) {
                    max_abs_x = @abs(coord_cam.get(0));
                    max_abs_y = @abs(coord_cam.get(1));
                    is_first = false;
                } else {
                    max_abs_x = @max(max_abs_x, @abs(coord_cam.get(0)));
                    max_abs_y = @max(max_abs_y, @abs(coord_cam.get(1)));
                }
            }
        }

        const fov_leng = [2]f64{
            2.0 * frame_fill * max_abs_x,
            2.0 * frame_fill * max_abs_y,
        };
        const image_dists = imageDistFromFov(
            pixels_num,
            pixels_size,
            focal_leng,
            fov_leng,
        );
        return @max(image_dists[0], image_dists[1]);
    }

    pub fn posFillFrameFromRotOverMeshes(
        meshes: []const mo.MeshInput,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) vector.Vec3f {
        var fov_leng: [2]f64 = fovFromCamRotOverMeshes(cam_rot, meshes);
        fov_leng[0] = frame_fill * fov_leng[0];
        fov_leng[1] = frame_fill * fov_leng[1];

        const image_dists: [2]f64 = imageDistFromFov(
            pixels_num,
            pixels_size,
            focal_leng,
            fov_leng,
        );
        const image_dist = @max(image_dists[0], image_dists[1]);

        const roi_pos: vector.Vec3f = roiCentOverMeshes(meshes);

        const cam_pos: vector.Vec3f = calcCamPos(roi_pos, cam_rot, image_dist);

        return cam_pos;
    }

    pub fn posFillFrameFromRotOverMeshesAndTarget(
        meshes: []const mo.MeshInput,
        target_world: vector.Vec3f,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: rotation.Rotation,
        frame_fill: f64,
    ) vector.Vec3f {
        const image_dist = imageDistFillFrameFromRotOverMeshesAndTarget(
            meshes,
            target_world,
            pixels_num,
            pixels_size,
            focal_leng,
            cam_rot,
            frame_fill,
        );
        return calcCamPos(target_world, cam_rot, image_dist);
    }
};

const test_tol: f64 = 1e-4;
const pix_num = [_]u32{ 500, 500 };
const pix_size = [_]f64{ 5e-3, 5e-3 };
const foc_leng: f64 = 50.0;
const rotat_world = rotation.Rotation.init(0, 0, std.math.degreesToRadians(-45));
const bb: f64 = 20.0;
const coord_n: usize = 8;
const coord_x = [_]f64{ -bb, bb, bb, -bb, -bb, bb, bb, -bb };
const coord_y = [_]f64{ bb, bb, -bb, -bb, bb, bb, -bb, -bb };
const coord_z = [_]f64{ bb, bb, bb, bb, -bb, -bb, -bb, -bb };
const roi_world_arr = [_]f64{ 0, 0, 0 };
const roi_world = vector.Vec3f.initSlice(&roi_world_arr);
const sub_samp: u8 = 2;

const fov_exp = [2]f64{ 40.0, 56.56854249 };
const image_dist_exp = [2]f64{ 800.0, 1131.3708499 };
const sensor_size_exp = [2]f64{ 2.5, 2.5 };
const cam_pos_arr = [_]f64{ 0.0, 800.0, 800.0 };
const cam_pos_exp = vector.Vec3f.initSlice(&cam_pos_arr);

fn expectApproxEqRelAbs(
    expected: f64,
    actual: f64,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    const diff = @abs(expected - actual);
    if (diff <= abs_tol) {
        return;
    }

    const scale = @max(@abs(expected), @abs(actual));
    if (scale == 0.0) {
        return error.TestExpectedApproxEqRelAbs;
    }
    if (diff / scale > rel_tol) {
        return error.TestExpectedApproxEqRelAbs;
    }
}

fn checkDistortionGridInverse(
    comptime DistortionType: type,
    distortion: DistortionType,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    const grid_num = 25;
    const min_coord = -0.45;
    const max_coord = 0.45;
    const coord_step = (max_coord - min_coord) / @as(f64, grid_num - 1);

    for (0..grid_num) |jj| {
        const y = min_coord + @as(f64, @floatFromInt(jj)) * coord_step;
        for (0..grid_num) |ii| {
            const x = min_coord + @as(f64, @floatFromInt(ii)) * coord_step;
            const distorted = distortion.forward(x, y);
            const recovered = try distortion.inverse(distorted[0], distorted[1]);
            try expectApproxEqRelAbs(x, recovered.x, rel_tol, abs_tol);
            try expectApproxEqRelAbs(y, recovered.y, rel_tol, abs_tol);
        }
    }
}

test "CameraOps.calcCamPos" {
    var coords = try meshio.Coords.initAlloc(std.testing.allocator, coord_n);
    defer std.testing.allocator.free(coords.mem);

    for (0..coord_n) |ii| {
        coords.mat.set(ii, 0, coord_x[ii]);
        coords.mat.set(ii, 1, coord_y[ii]);
        coords.mat.set(ii, 2, coord_z[ii]);
    }

    const fov_leng = CameraOps.fovFromCamRot(rotat_world, &coords);
    const image_dist = CameraOps.imageDistFromFov(pix_num, pix_size, foc_leng, fov_leng);
    const image_dist_max = @max(image_dist[0], image_dist[1]);
    const cam_pos = CameraOps.calcCamPos(roi_world, rotat_world, image_dist_max);

    try std.testing.expectApproxEqAbs(cam_pos_exp.get(0), cam_pos.get(0), test_tol);
    try std.testing.expectApproxEqAbs(cam_pos_exp.get(1), cam_pos.get(1), test_tol);
    try std.testing.expectApproxEqAbs(cam_pos_exp.get(2), cam_pos.get(2), test_tol);
}

test "CameraPrepared.init" {
    const input = CameraInput{
        .pixels_num = pix_num,
        .pixels_size = pix_size,
        .pos_world = cam_pos_exp,
        .rot_world = rotat_world,
        .roi_cent_world = roi_world,
        .focal_length = foc_leng,
        .sub_sample = sub_samp,
    };

    const camera = try CameraPrepared.init(std.testing.allocator, input);
    defer camera.deinit(std.testing.allocator);

    try std.testing.expectEqual(pix_num, camera.pixels_num);
    try std.testing.expectEqual(pix_size, camera.pixels_size);
    try std.testing.expectEqual(foc_leng, camera.focal_length);
    try std.testing.expectEqual(sub_samp, camera.sub_sample);
}

test "BrownConrady.forwardInverse" {
    const bc = BrownConrady{
        .k1 = -0.2,
        .k2 = 0.03,
        .k3 = -0.005,
        .p1 = 0.001,
        .p2 = -0.0015,
    };

    const x_ideal = 0.1;
    const y_ideal = -0.15;

    const distorted = bc.forward(x_ideal, y_ideal);
    const recovered = try bc.inverse(distorted[0], distorted[1]);

    try std.testing.expectApproxEqAbs(x_ideal, recovered.x, 1e-10);
    try std.testing.expectApproxEqAbs(y_ideal, recovered.y, 1e-10);
}

test "BrownConradyExt.forwardInverse" {
    const bc_ext = BrownConradyExt{
        .k1 = -0.18,
        .k2 = 0.02,
        .k3 = -0.004,
        .k4 = 0.01,
        .k5 = -0.002,
        .k6 = 0.0004,
        .p1 = 0.0012,
        .p2 = -0.0018,
    };

    const x_ideal = -0.12;
    const y_ideal = 0.18;

    const distorted = bc_ext.forward(x_ideal, y_ideal);
    const recovered = try bc_ext.inverse(distorted[0], distorted[1]);

    try std.testing.expectApproxEqAbs(x_ideal, recovered.x, 1e-10);
    try std.testing.expectApproxEqAbs(y_ideal, recovered.y, 1e-10);
}

test "BrownConrady.gridInverseRoundTrip" {
    const bc_mild = BrownConrady{
        .k1 = -0.08,
        .k2 = 0.01,
        .k3 = -0.002,
        .p1 = 0.0004,
        .p2 = -0.0007,
    };
    const bc_strong = BrownConrady{
        .k1 = -0.2,
        .k2 = 0.03,
        .k3 = -0.005,
        .p1 = 0.001,
        .p2 = -0.0015,
    };

    try checkDistortionGridInverse(BrownConrady, bc_mild, 1e-6, 1e-6);
    try checkDistortionGridInverse(BrownConrady, bc_strong, 1e-6, 1e-6);
}

test "BrownConradyExt.gridInverseRoundTrip" {
    const bc_ext_mild = BrownConradyExt{
        .k1 = -0.09,
        .k2 = 0.012,
        .k3 = -0.0015,
        .k4 = 0.004,
        .k5 = -0.0008,
        .k6 = 0.00015,
        .p1 = 0.0005,
        .p2 = -0.0006,
    };
    const bc_ext_strong = BrownConradyExt{
        .k1 = -0.18,
        .k2 = 0.02,
        .k3 = -0.004,
        .k4 = 0.01,
        .k5 = -0.002,
        .k6 = 0.0004,
        .p1 = 0.0012,
        .p2 = -0.0018,
    };

    try checkDistortionGridInverse(BrownConradyExt, bc_ext_mild, 1e-6, 1e-6);
    try checkDistortionGridInverse(BrownConradyExt, bc_ext_strong, 1e-6, 1e-6);
}

test "CameraPrepared.distortionNone" {
    const input = CameraInput{
        .pixels_num = .{ 10, 10 },
        .pixels_size = .{ 0.01, 0.01 },
        .pos_world = vector.Vec3f.initZeros(),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vector.Vec3f.initZeros(),
        .focal_length = 1.0,
        .sub_sample = 1,
        .distortion = .none,
    };

    const camera = try CameraPrepared.init(std.testing.allocator, input);
    defer camera.deinit(std.testing.allocator);

    // Check pixel center (0, 0)
    // subpx_x_f = 0.5
    const x_px_exp = 0.5;
    const x_ideal = camera.ideal_pixel_centers.get(&[_]usize{ 0, 0, 0 });
    try std.testing.expectApproxEqAbs(x_px_exp, x_ideal, 1e-10);
}

test "CameraPrepared.brownConradyExtDistortionApplied" {
    const distortion = BrownConradyExt{
        .k1 = -0.18,
        .k2 = 0.02,
        .k3 = -0.004,
        .k4 = 0.01,
        .k5 = -0.002,
        .k6 = 0.0004,
        .p1 = 0.0012,
        .p2 = -0.0018,
    };
    const input = CameraInput{
        .pixels_num = .{ 10, 10 },
        .pixels_size = .{ 0.01, 0.01 },
        .pos_world = vector.Vec3f.initZeros(),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vector.Vec3f.initZeros(),
        .focal_length = 1.0,
        .sub_sample = 1,
        .distortion = .{ .brown_conrady_ext = distortion },
    };

    const camera = try CameraPrepared.init(std.testing.allocator, input);
    defer camera.deinit(std.testing.allocator);

    const x_off = 0.5 * @as(f64, @floatFromInt(input.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(input.pixels_num[1]));
    const fx = input.focal_length / input.pixels_size[0];
    const fy = input.focal_length / input.pixels_size[1];
    const x_d = (0.5 - x_off) / fx;
    const y_d = (0.5 - y_off) / fy;
    const solved = try distortion.inverse(x_d, y_d);

    const x_ideal = camera.ideal_pixel_centers.get(&[_]usize{ 0, 0, 0 });
    const y_ideal = camera.ideal_pixel_centers.get(&[_]usize{ 0, 0, 1 });
    try expectApproxEqRelAbs(solved.x * fx + x_off, x_ideal, 1e-6, 1e-6);
    try expectApproxEqRelAbs(solved.y * fy + y_off, y_ideal, 1e-6, 1e-6);
}

test "CameraOps.calcSensorSize" {
    const sensor_size = CameraOps.calcSensorSize(pix_num, pix_size);

    try std.testing.expectEqual(sensor_size_exp, sensor_size);
}

test "CameraOps.calcFOVScaling" {
    const input = CameraInput{
        .pixels_num = pix_num,
        .pixels_size = pix_size,
        .pos_world = cam_pos_exp,
        .rot_world = rotat_world,
        .roi_cent_world = roi_world,
        .focal_length = foc_leng,
        .sub_sample = sub_samp,
    };

    const scaling = CameraOps.calcFOVScaling(input, roi_world);
    const plane_size_exp = [_]f64{
        image_dist_exp[1] / foc_leng * sensor_size_exp[0],
        image_dist_exp[1] / foc_leng * sensor_size_exp[1],
    };

    try std.testing.expectApproxEqAbs(image_dist_exp[1], scaling.plane_dist, test_tol);
    try std.testing.expectApproxEqAbs(plane_size_exp[0], scaling.plane_size[0], test_tol);
    try std.testing.expectApproxEqAbs(plane_size_exp[1], scaling.plane_size[1], test_tol);
    try std.testing.expectApproxEqAbs(
        plane_size_exp[0] / @as(f64, @floatFromInt(pix_num[0])),
        scaling.leng_per_pixel[0],
        test_tol,
    );
    try std.testing.expectApproxEqAbs(
        plane_size_exp[1] / @as(f64, @floatFromInt(pix_num[1])),
        scaling.leng_per_pixel[1],
        test_tol,
    );
}

test "CameraOps.coordinatesRoundTrip" {
    const Vec3f = vector.Vec3f;
    const Rotation = rotation.Rotation;

    const pos_orig = vector.initVec3(f64, 12.3, -45.6, 78.9);
    const rot_orig = Rotation.init(
        std.math.degreesToRadians(15.0),
        std.math.degreesToRadians(-25.0),
        std.math.degreesToRadians(45.0),
    );

    const r_riley_t = rot_orig.matrix.transpose();
    var r_opencv = r_riley_t;
    r_opencv.slice[3] = -r_opencv.slice[3];
    r_opencv.slice[4] = -r_opencv.slice[4];
    r_opencv.slice[5] = -r_opencv.slice[5];
    r_opencv.slice[6] = -r_opencv.slice[6];
    r_opencv.slice[7] = -r_opencv.slice[7];
    r_opencv.slice[8] = -r_opencv.slice[8];

    const r_opencv_c = r_opencv.mulVec(pos_orig);
    const pos_opencv = vector.initVec3(
        f64,
        -r_opencv_c.get(0),
        -r_opencv_c.get(1),
        -r_opencv_c.get(2),
    );
    const rot_opencv = Rotation.fromMat33(r_opencv);

    const input_opencv = CameraInput{
        .pixels_num = .{ 1024, 768 },
        .pixels_size = .{ 3.45e-6, 3.45e-6 },
        .pos_world = pos_opencv,
        .rot_world = rot_opencv,
        .roi_cent_world = Vec3f.initZeros(),
        .focal_length = 50.0e-3,
        .sub_sample = 2,
        .coord_sys = .opencv,
    };

    const input_converted = CameraOps.toOpenGLInput(input_opencv);

    const eps_coord = 1e-12;
    try std.testing.expectApproxEqAbs(
        pos_orig.get(0),
        input_converted.pos_world.get(0),
        eps_coord,
    );
    try std.testing.expectApproxEqAbs(
        pos_orig.get(1),
        input_converted.pos_world.get(1),
        eps_coord,
    );
    try std.testing.expectApproxEqAbs(
        pos_orig.get(2),
        input_converted.pos_world.get(2),
        eps_coord,
    );

    var ii: usize = 0;
    while (ii < 9) : (ii += 1) {
        try std.testing.expectApproxEqAbs(
            rot_orig.matrix.slice[ii],
            input_converted.rot_world.matrix.slice[ii],
            eps_coord,
        );
    }
}

test "PreparedPSF gaussian kernels normalize" {
    var prepared = try preparePSF(
        std.testing.allocator,
        .{ .gaussian = .{
            .sigma_px = 0.35,
            .support_rad_px = 1.25,
            .separable = .yes,
        } },
        2,
    );
    defer prepared.deinit(std.testing.allocator);

    var sum_x: f64 = 0.0;
    var sum_y: f64 = 0.0;
    for (prepared.weights_x) |weight| sum_x += weight;
    for (prepared.weights_y) |weight| sum_y += weight;

    try std.testing.expectApproxEqAbs(1.0, sum_x, 1e-12);
    try std.testing.expectApproxEqAbs(1.0, sum_y, 1e-12);
    try std.testing.expectEqual(@as(u16, 2), prepared.halo_px);
}

test "PreparedPSF isotropic gaussian separable matches non-separable outer product" {
    var prepared_sep = try preparePSF(
        std.testing.allocator,
        .{ .gaussian = .{
            .sigma_px = 0.35,
            .support_rad_px = 1.25,
            .separable = .yes,
        } },
        2,
    );
    defer prepared_sep.deinit(std.testing.allocator);

    var prepared_nonsep = try preparePSF(
        std.testing.allocator,
        .{ .gaussian = .{
            .sigma_px = 0.35,
            .support_rad_px = 1.25,
            .separable = .no,
        } },
        2,
    );
    defer prepared_nonsep.deinit(std.testing.allocator);

    const width = 2 * prepared_sep.radius_x_subpx + 1;
    for (0..prepared_nonsep.weights_2d.len) |ii| {
        const yy = ii / width;
        const xx = ii % width;
        const expected = prepared_sep.weights_y[yy] * prepared_sep.weights_x[xx];
        try std.testing.expectApproxEqAbs(
            expected,
            prepared_nonsep.weights_2d[ii],
            1e-12,
        );
    }
}
