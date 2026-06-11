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
const cameraops = @import("cameraops.zig");

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
    distortion: cam.DistortionModel,
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
) !cam.DistortionModel {
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
    camera_input: cam.CameraInput,
) !void {
    const metrics = cameraops.calcPlaneMetrics(camera_input);

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
        pos_val = @import("vecstack.zig").initVec3(
            f64,
            -r_opencv_c.get(0),
            -r_opencv_c.get(1),
            -r_opencv_c.get(2),
        );
        rot_val = @import("rotation.zig").Rotation.fromMat33(r_opencv);
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
    try writeKeyValueF64(writer, "roi_cent_x_m", camera_input.roi_cent_world.get(0));
    try writeKeyValueF64(writer, "roi_cent_y_m", camera_input.roi_cent_world.get(1));
    try writeKeyValueF64(writer, "roi_cent_z_m", camera_input.roi_cent_world.get(2));
    try writeKeyValueF64(writer, "sensor_size_x_m", metrics.sensor_size[0]);
    try writeKeyValueF64(writer, "sensor_size_y_m", metrics.sensor_size[1]);
    try writeKeyValueF64(writer, "fx_px", metrics.focal_px[0]);
    try writeKeyValueF64(writer, "fy_px", metrics.focal_px[1]);
    try writeKeyValueF64(writer, "cx_px", metrics.principal_point_px[0]);
    try writeKeyValueF64(writer, "cy_px", metrics.principal_point_px[1]);
    try writeKeyValueF64(writer, "roi_plane_dist_m", metrics.roi_plane_dist);
    try writeKeyValueF64(writer, "roi_plane_size_x_m", metrics.roi_plane_size[0]);
    try writeKeyValueF64(writer, "roi_plane_size_y_m", metrics.roi_plane_size[1]);
    try writeKeyValueF64(writer, "avg_leng_per_pixel_m", metrics.avg_leng_per_pixel);
    try writeKeyValueF64(writer, "avg_pixel_per_leng", metrics.avg_pixel_per_leng);
    try writeDistortion(writer, camera_input.distortion);
    try file_writer.flush();
}

pub fn loadCamera(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    file_name: []const u8,
) !cam.CameraInput {
    var kv = try parseKeyValueCsv(allocator, io, dir, file_name);
    defer deinitKeyValueCsv(allocator, &kv);

    const coord_sys = blk: {
        if (kv.get("coord_sys")) |sys_str| {
            if (std.mem.eql(u8, sys_str, "opencv")) {
                break :blk cam.CameraCoordSys.opencv;
            }
        }
        break :blk cam.CameraCoordSys.opengl;
    };

    var camera_input = cam.CameraInput{
        .pixels_num = .{
            try parseU32Value(&kv, "pixels_x"),
            try parseU32Value(&kv, "pixels_y"),
        },
        .pixels_size = .{
            try parseF64Value(&kv, "pixel_size_x_m"),
            try parseF64Value(&kv, "pixel_size_y_m"),
        },
        .pos_world = @import("vecstack.zig").initVec3(
            f64,
            try parseF64Value(&kv, "pos_x_m"),
            try parseF64Value(&kv, "pos_y_m"),
            try parseF64Value(&kv, "pos_z_m"),
        ),
        .rot_world = @import("rotation.zig").Rotation.init(
            std.math.degreesToRadians(try parseF64Value(&kv, "rot_alpha_z_deg")),
            std.math.degreesToRadians(try parseF64Value(&kv, "rot_beta_y_deg")),
            std.math.degreesToRadians(try parseF64Value(&kv, "rot_gamma_x_deg")),
        ),
        .roi_cent_world = @import("vecstack.zig").initVec3(
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
        camera_input = cameraops.toOpenGLInput(camera_input);
        camera_input.coord_sys = .opencv;
    }

    return camera_input;
}

pub fn saveStereoPair(
    io: std.Io,
    out_dir: std.Io.Dir,
    stereo_file_name: []const u8,
    stereo_pair: cam.StereoPairInput,
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
    const cam0_opengl = cameraops.toOpenGLInput(cam0);
    const cam1_opengl = cameraops.toOpenGLInput(cam1);
    const baseline = cam1_opengl.pos_world.sub(cam0_opengl.pos_world);
    const baseline_len = baseline.vecLen();
    const cam0_metrics = cameraops.calcPlaneMetrics(cam0);
    const cam1_metrics = cameraops.calcPlaneMetrics(cam1);

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
    try writeKeyValueF64(writer, "cam0_cx_px", cam0_metrics.principal_point_px[0]);
    try writeKeyValueF64(writer, "cam0_cy_px", cam0_metrics.principal_point_px[1]);
    try writeKeyValueF64(writer, "cam0_focal_length_m", cam0.focal_length);
    try writeKeyValueF64(writer, "cam1_fx_px", cam1_metrics.focal_px[0]);
    try writeKeyValueF64(writer, "cam1_fy_px", cam1_metrics.focal_px[1]);
    try writeKeyValueF64(writer, "cam1_cx_px", cam1_metrics.principal_point_px[0]);
    try writeKeyValueF64(writer, "cam1_cy_px", cam1_metrics.principal_point_px[1]);
    try writeKeyValueF64(writer, "cam1_focal_length_m", cam1.focal_length);
    try file_writer.flush();
}

pub fn loadStereoPair(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    stereo_file_name: []const u8,
) !cam.StereoPairInput {
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
