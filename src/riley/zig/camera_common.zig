// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const vector = @import("vecstack.zig");
const matrix = @import("matstack.zig");
const rotation = @import("rotation.zig");
const ndarray = @import("ndarray.zig");
const buildconfig = @import("buildconfig.zig");
const rastcfg = @import("rasterconfig.zig");
const cameramodels = @import("cameramodels.zig");
const camera_scalar = @import("camera_scalar.zig");
const camera_simd = @import("camera_simd.zig");

const cfg = buildconfig.config;
const camera_impl = if (cfg.simd == .on) camera_simd else camera_scalar;

pub const DistortionModel = cameramodels.DistortionModel;
pub const BrownConrady = cameramodels.BrownConrady;
pub const BrownConradyExt = cameramodels.BrownConradyExt;
pub const DistortionInverseResult = cameramodels.DistortionInverseResult;
pub const DistortionForwardJacResult = cameramodels.DistortionForwardJacResult;
pub const PsfSeparable = cameramodels.PsfSeparable;
pub const PixelBoxPSF = cameramodels.PixelBoxPSF;
pub const GaussianPSF = cameramodels.GaussianPSF;
pub const AnisotropicGaussianPSF = cameramodels.AnisotropicGaussianPSF;
pub const PointSpreadFunc = cameramodels.PointSpreadFunc;
pub const PreparedPSFMode = cameramodels.PreparedPSFMode;
pub const PreparedPSF = cameramodels.PreparedPSF;

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
    subpixel_center_map: rastcfg.SubPixelCenterMap = .per_tile,
};

pub const StereoPairInput = struct {
    cameras: [2]CameraInput,
};

pub const CameraCoordSys = enum {
    opengl,
    opencv,
};

pub const FOVScaling = struct {
    plane_dist: f64,
    plane_size: [2]f64,
    leng_per_pixel: [2]f64,
    pixel_per_leng: [2]f64,
};

pub const CameraPrepared = CameraPreparedType(camera_impl);

pub inline fn isNoDistortion(distortion: anytype) bool {
    return switch (distortion) {
        .none => true,
        else => false,
    };
}

pub inline fn calcPixelCenterCoord(pixel: usize) f64 {
    return @as(f64, @floatFromInt(pixel)) + 0.5;
}

pub inline fn storeIdealPairScratch(
    ideal_pixel_centers: []f64,
    scratch_idx: usize,
    ideal_x: f64,
    ideal_y: f64,
) void {
    ideal_pixel_centers[scratch_idx * 2 + 0] = ideal_x;
    ideal_pixel_centers[scratch_idx * 2 + 1] = ideal_y;
}

pub fn calcIdealObservedRasterPointScalar(
    camera: anytype,
    observed_x_px: f64,
    observed_y_px: f64,
) ![2]f64 {
    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    const x_dist = (observed_x_px - offsets.x_off) / focal_px.fx;
    const y_dist = (observed_y_px - offsets.y_off) / focal_px.fy;

    return switch (camera.distortion) {
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

fn calcSensorSize(pixels_num: [2]u32, pixels_size: [2]f64) [2]f64 {
    return .{
        @as(f64, @floatFromInt(pixels_num[0])) * pixels_size[0],
        @as(f64, @floatFromInt(pixels_num[1])) * pixels_size[1],
    };
}

pub fn allCamerasSharePixels(cameras: []const CameraPrepared) bool {
    std.debug.assert(cameras.len != 0);

    const pixels_num = cameras[0].pixels_num;
    for (cameras[1..]) |camera| {
        if (!std.meta.eql(camera.pixels_num, pixels_num)) {
            return false;
        }
    }
    return true;
}

pub fn CameraPreparedType(comptime CameraBackend: type) type {
    return struct {
        const Self = @This();

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
        ideal_pixel_centers: ndarray.NDArray(f64),
        pixel_center_jac: ndarray.NDArray(f64),
        subpixel_center_map: rastcfg.SubPixelCenterMap,

        pub fn init(
            allocator: std.mem.Allocator,
            input: CameraInput,
        ) !Self {
            const subpixel_center_map = input.subpixel_center_map;
            const actual_sub_sample = if (input.sub_sample == 0)
                @as(u8, 2)
            else
                input.sub_sample;
            const sensor_size = calcSensorSize(
                input.pixels_num,
                input.pixels_size,
            );

            const pos_w = input.pos_world;
            const rot_matrix = input.rot_world.matrix;
            const image_dist: f64 = pos_w.sub(input.roi_cent_world).vecLen();

            const image_dims = [2]f64{
                (image_dist / input.focal_length) * sensor_size[0],
                (image_dist / input.focal_length) * sensor_size[1],
            };

            var cam_to_world_mat = matrix.Mat44f.initIdentity();
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
                    break :blk try ndarray.NDArray(f64).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
                else => blk: {
                    const dims = [_]usize{ 0, 0, 2 };
                    break :blk try ndarray.NDArray(f64).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
            };
            const pixel_center_jac = switch (subpixel_center_map) {
                .affine_jac => blk: {
                    const dims = [_]usize{
                        input.pixels_num[1],
                        input.pixels_num[0],
                        6,
                    };
                    break :blk try ndarray.NDArray(f64).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
                else => blk: {
                    const dims = [_]usize{ 0, 0, 6 };
                    break :blk try ndarray.NDArray(f64).initFlat(
                        allocator,
                        dims[0..],
                    );
                },
            };

            var self = Self{
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
                .prepared_psf = try cameramodels.preparePSF(
                    allocator,
                    input.psf,
                    actual_sub_sample,
                ),
                .coord_sys = input.coord_sys,
                .ideal_pixel_centers = ideal_pixel_centers,
                .pixel_center_jac = pixel_center_jac,
                .subpixel_center_map = subpixel_center_map,
            };

            switch (subpixel_center_map) {
                .full_in_mem => try self.initFullIdealPixelCenters(),
                .affine_jac => try CameraBackend.initPixelCenterJac(&self),
                .per_tile => {},
            }

            return self;
        }

        pub fn deinit(
            self: *const Self,
            allocator: std.mem.Allocator,
        ) void {
            var prepared_psf = self.prepared_psf;
            prepared_psf.deinit(allocator);
            allocator.free(self.ideal_pixel_centers.slice);
            self.ideal_pixel_centers.deinit(allocator);
            allocator.free(self.pixel_center_jac.slice);
            self.pixel_center_jac.deinit(allocator);
        }

        pub inline fn calcIdealObservedRasterPoint(
            self: *const Self,
            observed_x_px: f64,
            observed_y_px: f64,
        ) ![2]f64 {
            return CameraBackend.calcIdealObservedRasterPoint(
                self,
                observed_x_px,
                observed_y_px,
            );
        }

        pub inline fn calcIdealObservedRasterPointSIMD(
            self: *const Self,
            v_observed_x_px: buildconfig.VecSF,
            v_observed_y_px: buildconfig.VecSF,
            v_lane_active: buildconfig.VecSB,
        ) !struct { x: buildconfig.VecSF, y: buildconfig.VecSF } {
            return CameraBackend.calcIdealObservedRasterPointSIMD(
                self,
                v_observed_x_px,
                v_observed_y_px,
                v_lane_active,
            );
        }

        fn initFullIdealPixelCenters(self: *Self) !void {
            const sub_samp_u: usize = @intCast(self.sub_sample);
            const sub_samp_f = @as(f64, @floatFromInt(self.sub_sample));
            const subpx_step = 1.0 / sub_samp_f;
            const subpx_off = 0.5 / sub_samp_f;

            const slice = self.ideal_pixel_centers.slice;
            const stride_y = self.ideal_pixel_centers.strides[0];
            const stride_x = self.ideal_pixel_centers.strides[1];

            for (0..self.pixels_num[1] * sub_samp_u) |jj| {
                const subpx_y_f = @as(f64, @floatFromInt(jj)) *
                    subpx_step + subpx_off;
                const row_off = jj * stride_y;

                for (0..self.pixels_num[0] * sub_samp_u) |ii| {
                    const subpx_x_f = @as(f64, @floatFromInt(ii)) *
                        subpx_step + subpx_off;
                    const ideal = try self.calcIdealObservedRasterPoint(
                        subpx_x_f,
                        subpx_y_f,
                    );
                    const col_off = ii * stride_x;
                    slice[row_off + col_off + 0] = ideal[0];
                    slice[row_off + col_off + 1] = ideal[1];
                }
            }
        }

        pub fn calcFocalPx(self: *const Self) struct { fx: f64, fy: f64 } {
            return .{
                .fx = self.focal_length / self.pixels_size[0],
                .fy = self.focal_length / self.pixels_size[1],
            };
        }

        pub fn calcRasterOffsets(self: *const Self) struct { x_off: f64, y_off: f64 } {
            return .{
                .x_off = 0.5 * @as(f64, @floatFromInt(self.pixels_num[0])),
                .y_off = 0.5 * @as(f64, @floatFromInt(self.pixels_num[1])),
            };
        }
    };
}

// --------------------------------------------------------------------------
// Unit Tests
// --------------------------------------------------------------------------

const test_tol: f64 = 1e-4;
const pix_num = [_]u32{ 500, 500 };
const pix_size = [_]f64{ 5e-3, 5e-3 };
const foc_leng: f64 = 50.0;
const rotat_world = rotation.Rotation.init(
    0,
    0,
    std.math.degreesToRadians(-45),
);
const bb: f64 = 20.0;
const coord_n: usize = 8;
const coord_x = [_]f64{ -bb, bb, bb, -bb, -bb, bb, bb, -bb };
const coord_y = [_]f64{ bb, bb, -bb, -bb, bb, bb, -bb, -bb };
const coord_z = [_]f64{ bb, bb, bb, bb, -bb, -bb, -bb, -bb };
const roi_world_arr = [_]f64{ 0, 0, 0 };
const roi_world = vector.Vec3f.initSlice(&roi_world_arr);
const sub_samp: u8 = 2;

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
            const recovered = try distortion.inverse(
                distorted[0],
                distorted[1],
            );
            try expectApproxEqRelAbs(x, recovered.x, rel_tol, abs_tol);
            try expectApproxEqRelAbs(y, recovered.y, rel_tol, abs_tol);
        }
    }
}

test "CameraPrepared.init" {
    const input = CameraInput{
        .pixels_num = pix_num,
        .pixels_size = pix_size,
        .pos_world = vector.initVec3(f64, 0.0, 800.0, 800.0),
        .rot_world = rotat_world,
        .roi_cent_world = roi_world,
        .focal_length = foc_leng,
        .sub_sample = sub_samp,
        .subpixel_center_map = .full_in_mem,
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

    try checkDistortionGridInverse(
        BrownConradyExt,
        bc_ext_mild,
        1e-6,
        1e-6,
    );
    try checkDistortionGridInverse(
        BrownConradyExt,
        bc_ext_strong,
        1e-6,
        1e-6,
    );
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
        .subpixel_center_map = .full_in_mem,
    };

    const camera = try CameraPrepared.init(std.testing.allocator, input);
    defer camera.deinit(std.testing.allocator);

    const x_ideal = camera.ideal_pixel_centers.get(&[_]usize{ 0, 0, 0 });
    try std.testing.expectApproxEqAbs(0.5, x_ideal, 1e-10);
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
        .subpixel_center_map = .full_in_mem,
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

test "PreparedPSF gaussian kernels normalize" {
    var prepared = try cameramodels.preparePSF(
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
    var prepared_sep = try cameramodels.preparePSF(
        std.testing.allocator,
        .{ .gaussian = .{
            .sigma_px = 0.35,
            .support_rad_px = 1.25,
            .separable = .yes,
        } },
        2,
    );
    defer prepared_sep.deinit(std.testing.allocator);

    var prepared_nonsep = try cameramodels.preparePSF(
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
        const expected = prepared_sep.weights_y[yy] *
            prepared_sep.weights_x[xx];
        try std.testing.expectApproxEqAbs(
            expected,
            prepared_nonsep.weights_2d[ii],
            1e-12,
        );
    }
}
