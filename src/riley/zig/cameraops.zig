// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const cam = @import("camera.zig");
const meshio = @import("meshio.zig");
const mo = @import("meshops.zig");
const vector = @import("vecstack.zig");
const matrix = @import("matstack.zig");
const rotation = @import("rotation.zig");
const rastcfg = @import("rasterconfig.zig");

const CameraPlaneMetrics = struct {
    sensor_size: [2]f64,
    focal_px: [2]f64,
    principal_point_px: [2]f64,
    roi_plane_dist: f64,
    roi_plane_size: [2]f64,
    avg_leng_per_pixel: f64,
    avg_pixel_per_leng: f64,
};

pub fn prepareCameraSlice(
    allocator: std.mem.Allocator,
    camera_inputs: []const cam.CameraInput,
) ![]cam.CameraPrepared {
    const cameras = try allocator.alloc(cam.CameraPrepared, camera_inputs.len);
    for (camera_inputs, 0..) |camera_input, cc| {
        cameras[cc] = cam.CameraPrepared.init(
            allocator,
            camera_input,
        ) catch |err| {
            for (0..cc) |pp| cameras[pp].deinit(allocator);
            allocator.free(cameras);
            return err;
        };
    }

    return cameras;
}

pub fn toOpenGLInput(input: cam.CameraInput) cam.CameraInput {
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

pub fn calcPlaneMetrics(camera_input: cam.CameraInput) CameraPlaneMetrics {
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

    return .{
        bb_cam_max[0] - bb_cam_min[0],
        bb_cam_max[1] - bb_cam_min[1],
    };
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

    return .{
        bb_cam_max[0] - bb_cam_min[0],
        bb_cam_max[1] - bb_cam_min[1],
    };
}

pub fn calcSensorSize(pixels_num: [2]u32, pixels_size: [2]f64) [2]f64 {
    return .{
        @as(f64, @floatFromInt(pixels_num[0])) * pixels_size[0],
        @as(f64, @floatFromInt(pixels_num[1])) * pixels_size[1],
    };
}

pub fn imageDistFromFov(
    pixels_num: [2]u32,
    pixels_size: [2]f64,
    focal_leng: f64,
    fov_leng: [2]f64,
) [2]f64 {
    const sensor_size = calcSensorSize(pixels_num, pixels_size);

    const fov_angle = [2]f64{
        2 * std.math.atan(sensor_size[0] / (2 * focal_leng)),
        2 * std.math.atan(sensor_size[1] / (2 * focal_leng)),
    };

    return .{
        fov_leng[0] / (2 * std.math.tan(fov_angle[0] / 2)),
        fov_leng[1] / (2 * std.math.tan(fov_angle[1] / 2)),
    };
}

pub fn calcFOVScaling(
    camera_input: cam.CameraInput,
    plane_cent_world: vector.Vec3f,
) cam.FOVScaling {
    const cam_z_axis = camera_input.rot_world.matrix.getColVec(2);
    const plane_vec = (&camera_input.pos_world).sub(plane_cent_world);
    const plane_dist = @abs(plane_vec.dot(cam_z_axis));
    const sensor_size = calcSensorSize(
        camera_input.pixels_num,
        camera_input.pixels_size,
    );

    const plane_size = [2]f64{
        (plane_dist / camera_input.focal_length) * sensor_size[0],
        (plane_dist / camera_input.focal_length) * sensor_size[1],
    };
    const leng_per_pixel = [2]f64{
        plane_size[0] / @as(f64, @floatFromInt(camera_input.pixels_num[0])),
        plane_size[1] / @as(f64, @floatFromInt(camera_input.pixels_num[1])),
    };

    return .{
        .plane_dist = plane_dist,
        .plane_size = plane_size,
        .leng_per_pixel = leng_per_pixel,
        .pixel_per_leng = .{
            1.0 / leng_per_pixel[0],
            1.0 / leng_per_pixel[1],
        },
    };
}

pub fn calcCamPos(
    roi_pos_world: vector.Vec3f,
    cam_rot: rotation.Rotation,
    image_dist: f64,
) vector.Vec3f {
    var cam_z_axis_vec = cam_rot.matrix.getColVec(2);
    cam_z_axis_vec = cam_z_axis_vec.mulScalar(image_dist);
    return (&roi_pos_world).add(cam_z_axis_vec);
}

pub fn centFromCoordsMean(coords_world: *const meshio.Coords) vector.Vec3f {
    var cent_world = vector.Vec3f.initZeros();
    const coords_num = coords_world.mat.rows_num;

    for (0..coords_num) |nn| {
        cent_world.slice[0] += coords_world.mat.get(nn, 0);
        cent_world.slice[1] += coords_world.mat.get(nn, 1);
        cent_world.slice[2] += coords_world.mat.get(nn, 2);
    }

    return cent_world.mulScalar(1.0 / @as(f64, @floatFromInt(coords_num)));
}

pub fn roiCentFromCoords(coords_world: *const meshio.Coords) vector.Vec3f {
    const max_vec = vector.initVec3(
        f64,
        coords_world.mat.maxByRow(0),
        coords_world.mat.maxByRow(1),
        coords_world.mat.maxByRow(2),
    );
    const min_vec = vector.initVec3(
        f64,
        coords_world.mat.minByRow(0),
        coords_world.mat.minByRow(1),
        coords_world.mat.minByRow(2),
    );

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
    var fov_leng = fovFromCamRot(cam_rot, coords_world);
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
    return calcCamPos(roiCentFromCoords(coords_world), cam_rot, image_dist);
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
    var fov_leng = fovFromCamRotOverMeshes(cam_rot, meshes);
    fov_leng[0] = frame_fill * fov_leng[0];
    fov_leng[1] = frame_fill * fov_leng[1];

    const image_dists = imageDistFromFov(
        pixels_num,
        pixels_size,
        focal_leng,
        fov_leng,
    );
    const image_dist = @max(image_dists[0], image_dists[1]);
    return calcCamPos(roiCentOverMeshes(meshes), cam_rot, image_dist);
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
