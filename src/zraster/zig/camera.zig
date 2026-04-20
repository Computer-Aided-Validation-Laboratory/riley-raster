// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectApproxEqAbs = testing.expectApproxEqAbs;

const Coords = @import("meshio.zig").Coords;
const mr = @import("meshraster.zig");
const MeshInput = mr.MeshInput;
const vector = @import("vecstack.zig");
const Vec3f = vector.Vec3f;
const matrix = @import("matstack.zig");
const Mat33Ops = matrix.Mat33Ops;
const Mat44f = matrix.Mat44f;
const Mat44Ops = matrix.Mat44Ops;
pub const Rotation = @import("rotation.zig").Rotation;

const NDArray = @import("ndarray.zig").NDArray;

pub const DistortionModel = union(enum) {
    none,
    brown_conrady: BrownConrady,
};

pub const BrownConrady = struct {
    k1: f64 = 0,
    k2: f64 = 0,
    k3: f64 = 0,
    p1: f64 = 0,
    p2: f64 = 0,
};

pub const CameraInput = struct {
    pixels_num: [2]u32,
    pixels_size: [2]f64,
    pos_world: Vec3f,
    rot_world: Rotation,
    roi_cent_world: Vec3f,
    focal_length: f64,
    sub_sample: u8,
    distortion: DistortionModel = .none,
};

pub const CameraPrepared = struct {
    pixels_num: [2]u32,
    pixels_size: [2]f64,
    pos_world: Vec3f,
    rot_world: Rotation,
    roi_cent_world: Vec3f,
    focal_length: f64,
    sub_sample: u8,
    sensor_size: [2]f64,
    image_dims: [2]f64,
    image_dist: f64,
    cam_to_world_mat: Mat44f,
    world_to_cam_mat: Mat44f,
    distortion: DistortionModel,
    // Prepared ideal pinhole sample target per output pixel center.
    // Conceptual shape: [height, width, 2]
    ideal_pixel_centers: NDArray(f64),

    pub fn init(
        allocator: std.mem.Allocator,
        input: CameraInput,
    ) !CameraPrepared {
        const actual_sub_sample = if (input.sub_sample == 0) 2 else input.sub_sample;
        const sensor_size = CameraOps.calcSensorSize(input.pixels_num, input.pixels_size);
        const image_dist: f64 = @as(Vec3f, input.pos_world).sub(input.roi_cent_world).vecLen();

        var image_dims: [2]f64 = undefined;
        image_dims[0] = (image_dist / input.focal_length) * sensor_size[0];
        image_dims[1] = (image_dist / input.focal_length) * sensor_size[1];

        var cam_to_world_mat: Mat44f = Mat44f.initIdentity();
        cam_to_world_mat.insertColVec(3, 0, 3, input.pos_world);
        cam_to_world_mat.insertSubMat(0, 0, 3, 3, input.rot_world.matrix);

        const world_to_cam_mat = Mat44Ops.inv(f64, cam_to_world_mat);

        const sub_samp_u: usize = @intCast(actual_sub_sample);
        const dims = [_]usize{
            input.pixels_num[1] * sub_samp_u,
            input.pixels_num[0] * sub_samp_u,
            2,
        };
        const ideal_pixel_centers = try NDArray(f64).initFlat(allocator, dims[0..]);

        const self = CameraPrepared{
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
            .ideal_pixel_centers = ideal_pixel_centers,
        };

        const sub_samp_f = @as(f64, @floatFromInt(actual_sub_sample));
        const subpx_step = 1.0 / sub_samp_f;
        const subpx_off = 0.5 / sub_samp_f;

        const x_off = 0.5 * @as(f64, @floatFromInt(input.pixels_num[0]));
        const y_off = 0.5 * @as(f64, @floatFromInt(input.pixels_num[1]));

        const fx = input.focal_length / input.pixels_size[0];
        const fy = input.focal_length / input.pixels_size[1];

        const slice = self.ideal_pixel_centers.slice;
        const stride_y = self.ideal_pixel_centers.strides[0];
        const stride_x = self.ideal_pixel_centers.strides[1];

        for (0..input.pixels_num[1] * sub_samp_u) |jj| {
            const subpx_y_f = @as(f64, @floatFromInt(jj)) * subpx_step + subpx_off;
            const y_d = (subpx_y_f - y_off) / fy;
            const row_off = jj * stride_y;

            for (0..input.pixels_num[0] * sub_samp_u) |ii| {
                const subpx_x_f = @as(f64, @floatFromInt(ii)) * subpx_step + subpx_off;
                const x_d = (subpx_x_f - x_off) / fx;

                var ideal_x: f64 = undefined;
                var ideal_y: f64 = undefined;

                switch (input.distortion) {
                    .none => {
                        ideal_x = x_d;
                        ideal_y = y_d;
                    },
                    .brown_conrady => |bc| {
                        const solved = try brownConradyInverse(x_d, y_d, bc);
                        ideal_x = solved.x;
                        ideal_y = solved.y;
                    },
                }

                const col_off = ii * stride_x;
                slice[row_off + col_off + 0] = ideal_x * fx + x_off;
                slice[row_off + col_off + 1] = ideal_y * fy + y_off;
            }
        }

        return self;
    }

    pub fn deinit(self: *const CameraPrepared, allocator: std.mem.Allocator) void {
        allocator.free(self.ideal_pixel_centers.slice);
        self.ideal_pixel_centers.deinit(allocator);
    }

    pub fn brownConradyForward(
        x: f64,
        y: f64,
        bc: BrownConrady,
    ) [2]f64 {
        const r2 = x * x + y * y;
        const rad = 1.0 + bc.k1 * r2 + bc.k2 * r2 * r2 + bc.k3 * r2 * r2 * r2;
        const x_d = x * rad + 2.0 * bc.p1 * x * y + bc.p2 * (r2 + 2.0 * x * x);
        const y_d = y * rad + bc.p1 * (r2 + 2.0 * y * y) + 2.0 * bc.p2 * x * y;
        return .{ x_d, y_d };
    }

    pub fn brownConradyForwardWithJacobian(
        x: f64,
        y: f64,
        bc: BrownConrady,
    ) struct { x_d: f64, y_d: f64, jac: [2][2]f64 } {
        const r2 = x * x + y * y;
        const r4 = r2 * r2;
        const r6 = r4 * r2;
        const rad = 1.0 + bc.k1 * r2 + bc.k2 * r4 + bc.k3 * r6;

        const x_d = x * rad + 2.0 * bc.p1 * x * y + bc.p2 * (r2 + 2.0 * x * x);
        const y_d = y * rad + bc.p1 * (r2 + 2.0 * y * y) + 2.0 * bc.p2 * x * y;

        const drad_dr2 = bc.k1 + 2.0 * bc.k2 * r2 + 3.0 * bc.k3 * r4;
        const drad_dx = drad_dr2 * 2.0 * x;
        const drad_dy = drad_dr2 * 2.0 * y;

        const dx_fwd_dx = rad + x * drad_dx + 2.0 * bc.p1 * y + 6.0 * bc.p2 * x;
        const dx_fwd_dy = x * drad_dy + 2.0 * bc.p1 * x + 2.0 * bc.p2 * y;
        const dy_fwd_dx = y * drad_dx + 2.0 * bc.p1 * x + 2.0 * bc.p2 * y;
        const dy_fwd_dy = rad + y * drad_dy + 6.0 * bc.p1 * y + 2.0 * bc.p2 * x;

        return .{
            .x_d = x_d,
            .y_d = y_d,
            .jac = .{
                .{ dx_fwd_dx, dx_fwd_dy },
                .{ dy_fwd_dx, dy_fwd_dy },
            },
        };
    }

    pub fn brownConradyInverse(
        x_d: f64,
        y_d: f64,
        bc: BrownConrady,
    ) !struct { x: f64, y: f64 } {
        var x = x_d;
        var y = y_d;

        const max_iters = 12;
        const tol_resid = 1e-12;
        const tol_delta = 1e-12;

        for (0..max_iters) |_| {
            const fwd = brownConradyForwardWithJacobian(x, y, bc);
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
            if (@abs(det) < 1e-15) return error.SingularJacobian;

            const delta_x = (-f0 * d + b * f1) / det;
            const delta_y = (c * f0 - a * f1) / det;

            x += delta_x;
            y += delta_y;

            if (@max(@abs(delta_x), @abs(delta_y)) < tol_delta) {
                return .{ .x = x, .y = y };
            }
        }

        return error.BrownConradyInverseFailed;
    }
};

pub const Camera = CameraPrepared;

pub const CameraOps = struct {
    pub fn fovFromCamRot(cam_rot: Rotation, coords_world: *const Coords) [2]f64 {
        const world_to_cam_mat = Mat33Ops.inv(f64, cam_rot.matrix);

        // 0=x, 1=y, 2=z
        const bb_min_x = coords_world.mat.minByRow(0);
        const bb_min_y = coords_world.mat.minByRow(1);
        const bb_min_z = coords_world.mat.minByRow(2);
        const bb_max_x = coords_world.mat.maxByRow(0);
        const bb_max_y = coords_world.mat.maxByRow(1);
        const bb_max_z = coords_world.mat.maxByRow(2);

        var bb_world_vecs: [8]Vec3f = undefined;
        bb_world_vecs[0] = vector.initVec3(f64, bb_min_x, bb_min_y, bb_max_z);
        bb_world_vecs[1] = vector.initVec3(f64, bb_max_x, bb_min_y, bb_max_z);
        bb_world_vecs[2] = vector.initVec3(f64, bb_max_x, bb_max_y, bb_max_z);
        bb_world_vecs[3] = vector.initVec3(f64, bb_min_x, bb_max_y, bb_max_z);
        bb_world_vecs[4] = vector.initVec3(f64, bb_min_x, bb_min_y, bb_min_z);
        bb_world_vecs[5] = vector.initVec3(f64, bb_max_x, bb_min_y, bb_min_z);
        bb_world_vecs[6] = vector.initVec3(f64, bb_max_x, bb_max_y, bb_min_z);
        bb_world_vecs[7] = vector.initVec3(f64, bb_min_x, bb_max_y, bb_min_z);

        var bb_cam_vec: Vec3f = undefined;
        bb_cam_vec = world_to_cam_mat.mulVec(bb_world_vecs[0]);
        var bb_cam_max = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };
        var bb_cam_min = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };

        for (bb_world_vecs[1..]) |vec| {
            bb_cam_vec = world_to_cam_mat.mulVec(vec);

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

    pub fn fovFromCamRotOverMeshes(cam_rot: Rotation, meshes: []const MeshInput) [2]f64 {
        const world_to_cam_mat = Mat33Ops.inv(f64, cam_rot.matrix);

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

        var bb_world_vecs: [8]Vec3f = undefined;
        bb_world_vecs[0] = vector.initVec3(f64, bb_min[0], bb_min[1], bb_max[2]);
        bb_world_vecs[1] = vector.initVec3(f64, bb_max[0], bb_min[1], bb_max[2]);
        bb_world_vecs[2] = vector.initVec3(f64, bb_max[0], bb_max[1], bb_max[2]);
        bb_world_vecs[3] = vector.initVec3(f64, bb_min[0], bb_max[1], bb_max[2]);
        bb_world_vecs[4] = vector.initVec3(f64, bb_min[0], bb_min[1], bb_min[2]);
        bb_world_vecs[5] = vector.initVec3(f64, bb_max[0], bb_min[1], bb_min[2]);
        bb_world_vecs[6] = vector.initVec3(f64, bb_max[0], bb_max[1], bb_min[2]);
        bb_world_vecs[7] = vector.initVec3(f64, bb_min[0], bb_max[1], bb_min[2]);

        var bb_cam_vec: Vec3f = undefined;
        bb_cam_vec = world_to_cam_mat.mulVec(bb_world_vecs[0]);
        var bb_cam_max = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };
        var bb_cam_min = [_]f64{ bb_cam_vec.get(0), bb_cam_vec.get(1) };

        for (bb_world_vecs[1..]) |vec| {
            bb_cam_vec = world_to_cam_mat.mulVec(vec);

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

    pub fn calcCamPos(roi_pos_world: Vec3f, cam_rot: Rotation, image_dist: f64) Vec3f {
        var cam_z_axis_vec = cam_rot.matrix.getColVec(2);
        cam_z_axis_vec = cam_z_axis_vec.mulScalar(image_dist);
        const cam_pos = (&roi_pos_world).add(cam_z_axis_vec);
        return cam_pos;
    }

    pub fn roiCentFromCoords(coords_world: *const Coords) Vec3f {
        var max_vec: Vec3f = undefined;
        max_vec.slice[0] = coords_world.mat.maxByRow(0);
        max_vec.slice[1] = coords_world.mat.maxByRow(1);
        max_vec.slice[2] = coords_world.mat.maxByRow(2);

        var min_vec: Vec3f = undefined;
        min_vec.slice[0] = coords_world.mat.minByRow(0);
        min_vec.slice[1] = coords_world.mat.minByRow(1);
        min_vec.slice[2] = coords_world.mat.minByRow(2);

        var roi_cent: Vec3f = (&max_vec).add(min_vec);
        roi_cent = roi_cent.mulScalar(0.5);
        return roi_cent;
    }

    pub fn roiCentOverMeshes(meshes: []const MeshInput) Vec3f {
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

        var roi_cent: Vec3f = (&max_vec).add(min_vec);
        roi_cent = roi_cent.mulScalar(0.5);
        return roi_cent;
    }

    pub fn posFillFrameFromRot(
        coords_world: *const Coords,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: Rotation,
        frame_fill: f64,
    ) Vec3f {
        var fov_leng: [2]f64 = fovFromCamRot(cam_rot, coords_world);
        fov_leng[0] = frame_fill * fov_leng[0];
        fov_leng[1] = frame_fill * fov_leng[1];

        const image_dists: [2]f64 = imageDistFromFov(
            pixels_num,
            pixels_size,
            focal_leng,
            fov_leng,
        );
        const image_dist = @max(image_dists[0], image_dists[1]);

        const roi_pos: Vec3f = roiCentFromCoords(coords_world);

        const cam_pos: Vec3f = calcCamPos(roi_pos, cam_rot, image_dist);

        return cam_pos;
    }

    pub fn posFillFrameFromRotOverMeshes(
        meshes: []const MeshInput,
        pixels_num: [2]u32,
        pixels_size: [2]f64,
        focal_leng: f64,
        cam_rot: Rotation,
        frame_fill: f64,
    ) Vec3f {
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

        const roi_pos: Vec3f = roiCentOverMeshes(meshes);

        const cam_pos: Vec3f = calcCamPos(roi_pos, cam_rot, image_dist);

        return cam_pos;
    }
};

const test_tol: f64 = 1e-4;
const pix_num = [_]u32{ 500, 500 };
const pix_size = [_]f64{ 5e-3, 5e-3 };
const foc_leng: f64 = 50.0;
const rotat_world = Rotation.init(0, 0, std.math.degreesToRadians(-45));
const bb: f64 = 20.0;
const coord_n: usize = 8;
const coord_x = [_]f64{ -bb, bb, bb, -bb, -bb, bb, bb, -bb };
const coord_y = [_]f64{ bb, bb, -bb, -bb, bb, bb, -bb, -bb };
const coord_z = [_]f64{ bb, bb, bb, bb, -bb, -bb, -bb, -bb };
const roi_world_arr = [_]f64{ 0, 0, 0 };
const roi_world = Vec3f.initSlice(&roi_world_arr);
const sub_samp: u8 = 2;

const fov_exp = [2]f64{ 40.0, 56.56854249 };
const image_dist_exp = [2]f64{ 800.0, 1131.3708499 };
const sensor_size_exp = [2]f64{ 2.5, 2.5 };
const cam_pos_arr = [_]f64{ 0.0, 800.0, 800.0 };
const cam_pos_exp = Vec3f.initSlice(&cam_pos_arr);

test "CameraOps.calcCamPos" {
    var coords = try Coords.initAlloc(testing.allocator, coord_n);
    defer testing.allocator.free(coords.mem);

    for (0..coord_n) |ii| {
        coords.mat.set(ii, 0, coord_x[ii]);
        coords.mat.set(ii, 1, coord_y[ii]);
        coords.mat.set(ii, 2, coord_z[ii]);
    }

    const fov_leng = CameraOps.fovFromCamRot(rotat_world, &coords);
    const image_dist = CameraOps.imageDistFromFov(pix_num, pix_size, foc_leng, fov_leng);
    const image_dist_max = @max(image_dist[0], image_dist[1]);
    const cam_pos = CameraOps.calcCamPos(roi_world, rotat_world, image_dist_max);

    try expectApproxEqAbs(cam_pos_exp.get(0), cam_pos.get(0), test_tol);
    try expectApproxEqAbs(cam_pos_exp.get(1), cam_pos.get(1), test_tol);
    try expectApproxEqAbs(cam_pos_exp.get(2), cam_pos.get(2), test_tol);
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

    const camera = try CameraPrepared.init(testing.allocator, input);
    defer camera.deinit(testing.allocator);

    try expectEqual(pix_num, camera.pixels_num);
    try expectEqual(pix_size, camera.pixels_size);
    try expectEqual(foc_leng, camera.focal_length);
    try expectEqual(sub_samp, camera.sub_sample);
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

    const distorted = CameraPrepared.brownConradyForward(x_ideal, y_ideal, bc);
    const recovered = try CameraPrepared.brownConradyInverse(distorted[0], distorted[1], bc);

    try expectApproxEqAbs(x_ideal, recovered.x, 1e-10);
    try expectApproxEqAbs(y_ideal, recovered.y, 1e-10);
}

test "CameraPrepared.distortionNone" {
    const input = CameraInput{
        .pixels_num = .{ 10, 10 },
        .pixels_size = .{ 0.01, 0.01 },
        .pos_world = Vec3f.initZeros(),
        .rot_world = Rotation.init(0, 0, 0),
        .roi_cent_world = Vec3f.initZeros(),
        .focal_length = 1.0,
        .sub_sample = 1,
        .distortion = .none,
    };

    const camera = try CameraPrepared.init(testing.allocator, input);
    defer camera.deinit(testing.allocator);

    // Check pixel center (0, 0)
    // subpx_x_f = 0.5
    const x_px_exp = 0.5;
    const x_ideal = camera.ideal_pixel_centers.get(&[_]usize{ 0, 0, 0 });
    try expectApproxEqAbs(x_px_exp, x_ideal, 1e-10);
}

test "CameraOps.calcSensorSize" {
    const sensor_size = CameraOps.calcSensorSize(pix_num, pix_size);

    try expectEqual(sensor_size_exp, sensor_size);
}
