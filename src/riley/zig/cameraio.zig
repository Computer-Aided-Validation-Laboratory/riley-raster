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

const cam = @import("camera.zig");
const cameraops = @import("cameraops.zig");
const rotation = @import("rotation.zig");
const vec = @import("vecstack.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

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
    try writer.print("{s},{d}\n", .{ "camera_idx", camera_idx });
    const coord_sys_str = if (camera_input.coord_sys == .opencv) "opencv" else "opengl";
    try writer.print("{s},{s}\n", .{ "coord_sys", coord_sys_str });
    try writer.print("{s},{d}\n", .{ "pixels_x", camera_input.pixels_num[0] });
    try writer.print("{s},{d}\n", .{ "pixels_y", camera_input.pixels_num[1] });
    try writer.print("{s},{d:.12}\n", .{
        "pixel_size_x_m",
        camera_input.pixels_size[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "pixel_size_y_m",
        camera_input.pixels_size[1],
    });
    try writer.print("{s},{d:.12}\n", .{
        "focal_length_m",
        camera_input.focal_length,
    });
    try writer.print("{s},{d}\n", .{ "sub_sample", camera_input.sub_sample });
    var pos_val = camera_input.pos_world;
    var rot_val = camera_input.rot_world;

    if (camera_input.coord_sys == .opencv) {
        const r_riley = camera_input.rot_world.matrix;
        const r_riley_t = r_riley.transpose();
        var r_opencv = r_riley_t;
        r_opencv.set(1, 0, -r_opencv.get(1, 0));
        r_opencv.set(1, 1, -r_opencv.get(1, 1));
        r_opencv.set(1, 2, -r_opencv.get(1, 2));
        r_opencv.set(2, 0, -r_opencv.get(2, 0));
        r_opencv.set(2, 1, -r_opencv.get(2, 1));
        r_opencv.set(2, 2, -r_opencv.get(2, 2));

        const r_opencv_c = r_opencv.mulVec(camera_input.pos_world);
        pos_val = @import("vecstack.zig").initVec3(
            F,
            -r_opencv_c.get(0),
            -r_opencv_c.get(1),
            -r_opencv_c.get(2),
        );
        rot_val = @import("rotation.zig").Rotation.fromMat33(r_opencv);
    }

    try writer.print("{s},{d:.12}\n", .{ "pos_x_m", pos_val.get(0) });
    try writer.print("{s},{d:.12}\n", .{ "pos_y_m", pos_val.get(1) });
    try writer.print("{s},{d:.12}\n", .{ "pos_z_m", pos_val.get(2) });
    try writer.print("{s},{d:.12}\n", .{
        "rot_alpha_z_deg",
        std.math.radiansToDegrees(rot_val.alpha_z),
    });
    try writer.print("{s},{d:.12}\n", .{
        "rot_beta_y_deg",
        std.math.radiansToDegrees(rot_val.beta_y),
    });
    try writer.print("{s},{d:.12}\n", .{
        "rot_gamma_x_deg",
        std.math.radiansToDegrees(rot_val.gamma_x),
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_x_m",
        camera_input.roi_cent_world.get(0),
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_y_m",
        camera_input.roi_cent_world.get(1),
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_z_m",
        camera_input.roi_cent_world.get(2),
    });
    try writer.print("{s},{d:.12}\n", .{
        "sensor_size_x_m",
        metrics.sensor_size[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "sensor_size_y_m",
        metrics.sensor_size[1],
    });
    try writer.print("{s},{d:.12}\n", .{ "fx_px", metrics.focal_px[0] });
    try writer.print("{s},{d:.12}\n", .{ "fy_px", metrics.focal_px[1] });
    try writer.print("{s},{d:.12}\n", .{
        "cx_px",
        metrics.principal_point_px[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "cy_px",
        metrics.principal_point_px[1],
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_plane_dist_m",
        metrics.roi_plane_dist,
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_plane_size_x_m",
        metrics.roi_plane_size[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_plane_size_y_m",
        metrics.roi_plane_size[1],
    });
    try writer.print("{s},{d:.12}\n", .{
        "avg_leng_per_pixel_m",
        metrics.avg_leng_per_pixel,
    });
    try writer.print("{s},{d:.12}\n", .{
        "avg_pixel_per_leng",
        metrics.avg_pixel_per_leng,
    });
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
            try std.fmt.parseInt(u32, try requireValue(&kv, "pixels_x"), 10),
            try std.fmt.parseInt(u32, try requireValue(&kv, "pixels_y"), 10),
        },
        .pixels_size = .{
            try std.fmt.parseFloat(F, try requireValue(&kv, "pixel_size_x_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "pixel_size_y_m")),
        },
        .pos_world = @import("vecstack.zig").initVec3(
            F,
            try std.fmt.parseFloat(F, try requireValue(&kv, "pos_x_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "pos_y_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "pos_z_m")),
        ),
        .rot_world = @import("rotation.zig").Rotation.init(
            std.math.degreesToRadians(
                try std.fmt.parseFloat(F, try requireValue(&kv, "rot_alpha_z_deg")),
            ),
            std.math.degreesToRadians(
                try std.fmt.parseFloat(F, try requireValue(&kv, "rot_beta_y_deg")),
            ),
            std.math.degreesToRadians(
                try std.fmt.parseFloat(F, try requireValue(&kv, "rot_gamma_x_deg")),
            ),
        ),
        .roi_cent_world = @import("vecstack.zig").initVec3(
            F,
            try std.fmt.parseFloat(F, try requireValue(&kv, "roi_cent_x_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "roi_cent_y_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "roi_cent_z_m")),
        ),
        .focal_length = try std.fmt.parseFloat(
            F,
            try requireValue(&kv, "focal_length_m"),
        ),
        .sub_sample = try std.fmt.parseInt(
            u32,
            try requireValue(&kv, "sub_sample"),
            10,
        ),
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
    const baseline = calculateStereoBaseline(stereo_pair);
    const baseline_len = baseline.vecLen();
    const cam0_metrics = cameraops.calcPlaneMetrics(cam0);
    const cam1_metrics = cameraops.calcPlaneMetrics(cam1);

    const csv_file = try out_dir.createFile(io, stereo_file_name, .{});
    defer csv_file.close(io);
    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    try writer.writeAll("key,value\n");
    try writer.print("{s},{s}\n", .{ "cam0_file", cam0_name });
    try writer.print("{s},{s}\n", .{ "cam1_file", cam1_name });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_x_m",
        cam0.roi_cent_world.get(0),
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_y_m",
        cam0.roi_cent_world.get(1),
    });
    try writer.print("{s},{d:.12}\n", .{
        "roi_cent_z_m",
        cam0.roi_cent_world.get(2),
    });
    try writer.print("{s},{d:.12}\n", .{ "baseline_x_m", baseline.get(0) });
    try writer.print("{s},{d:.12}\n", .{ "baseline_y_m", baseline.get(1) });
    try writer.print("{s},{d:.12}\n", .{ "baseline_z_m", baseline.get(2) });
    try writer.print("{s},{d:.12}\n", .{ "baseline_len_m", baseline_len });
    try writer.print("{s},{d:.12}\n", .{
        "rel_rot_alpha_z_deg",
        std.math.radiansToDegrees(
            cam1_opengl.rot_world.alpha_z - cam0_opengl.rot_world.alpha_z,
        ),
    });
    try writer.print("{s},{d:.12}\n", .{
        "rel_rot_beta_y_deg",
        std.math.radiansToDegrees(
            cam1_opengl.rot_world.beta_y - cam0_opengl.rot_world.beta_y,
        ),
    });
    try writer.print("{s},{d:.12}\n", .{
        "rel_rot_gamma_x_deg",
        std.math.radiansToDegrees(
            cam1_opengl.rot_world.gamma_x - cam0_opengl.rot_world.gamma_x,
        ),
    });
    try writer.print("{s},{d:.12}\n", .{ "cam0_fx_px", cam0_metrics.focal_px[0] });
    try writer.print("{s},{d:.12}\n", .{ "cam0_fy_px", cam0_metrics.focal_px[1] });
    try writer.print("{s},{d:.12}\n", .{
        "cam0_cx_px",
        cam0_metrics.principal_point_px[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "cam0_cy_px",
        cam0_metrics.principal_point_px[1],
    });
    try writer.print("{s},{d:.12}\n", .{
        "cam0_focal_length_m",
        cam0.focal_length,
    });
    try writer.print("{s},{d:.12}\n", .{ "cam1_fx_px", cam1_metrics.focal_px[0] });
    try writer.print("{s},{d:.12}\n", .{ "cam1_fy_px", cam1_metrics.focal_px[1] });
    try writer.print("{s},{d:.12}\n", .{
        "cam1_cx_px",
        cam1_metrics.principal_point_px[0],
    });
    try writer.print("{s},{d:.12}\n", .{
        "cam1_cy_px",
        cam1_metrics.principal_point_px[1],
    });
    try writer.print("{s},{d:.12}\n", .{
        "cam1_focal_length_m",
        cam1.focal_length,
    });
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

fn calculateStereoBaseline(stereo_pair: cam.StereoPairInput) vec.Vec3f {
    const cam0 = stereo_pair.cameras[0];
    const cam1 = stereo_pair.cameras[1];
    return cam1.pos_world.sub(cam0.pos_world);
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

fn writePolynomialMap(
    writer: *std.Io.Writer,
    prefix: []const u8,
    poly_map: cam.PolynomialMap,
) !void {
    var key_buf: [64]u8 = undefined;
    const term_count = poly_map.order.termCount();
    for (0..term_count) |ii| {
        const key_u = try std.fmt.bufPrint(
            key_buf[0..],
            "{s}_u_{d}",
            .{ prefix, ii },
        );
        try writer.print("{s},{d:.12}\n", .{ key_u, poly_map.coeffs_u[ii] });
        const key_v = try std.fmt.bufPrint(
            key_buf[0..],
            "{s}_v_{d}",
            .{ prefix, ii },
        );
        try writer.print("{s},{d:.12}\n", .{ key_v, poly_map.coeffs_v[ii] });
    }
}

fn writePolynomialMetadata(
    writer: *std.Io.Writer,
    polynomial: ?cam.BidirectionalPolynomial,
) !void {
    if (polynomial) |poly| {
        const order = if (poly.forward_map) |forward_map|
            forward_map.order
        else if (poly.inv_map) |inv_map|
            inv_map.order
        else
            cam.PolynomialOrder.quadratic;
        try writer.print("{s},{d}\n", .{ "poly_order", @intFromEnum(order) });
        try writer.print("{s},{d}\n", .{
            "poly_has_forward",
            @intFromBool(poly.forward_map != null),
        });
        try writer.print("{s},{d}\n", .{
            "poly_has_inv",
            @intFromBool(poly.inv_map != null),
        });
        if (poly.forward_map) |forward_map| {
            try writePolynomialMap(writer, "poly_forward", forward_map);
        }
        if (poly.inv_map) |inv_map| {
            try writePolynomialMap(writer, "poly_inv", inv_map);
        }
    } else {
        try writer.print("{s},{d}\n", .{
            "poly_order",
            @intFromEnum(cam.PolynomialOrder.quadratic),
        });
        try writer.print("{s},{d}\n", .{ "poly_has_forward", 0 });
        try writer.print("{s},{d}\n", .{ "poly_has_inv", 0 });
    }
}

fn parseOptionalU8Value(
    kv: *const std.StringHashMap([]const u8),
    key: []const u8,
    def: u8,
) !u8 {
    if (kv.get(key)) |value| {
        return std.fmt.parseInt(u8, value, 10);
    }
    return def;
}

fn parseOptionalFloatValue(
    kv: *const std.StringHashMap([]const u8),
    key: []const u8,
    def: F,
) !F {
    if (kv.get(key)) |value| return std.fmt.parseFloat(F, value);
    return def;
}

fn writeExtendedDistortion(
    writer: *std.Io.Writer,
    model: ?cam.BrownConradyExt.Params,
) !void {
    const ext = model orelse cam.BrownConradyExt.Params{};
    try writer.print("{s},{d:.12}\n", .{ "s1", ext.s1 });
    try writer.print("{s},{d:.12}\n", .{ "s2", ext.s2 });
    try writer.print("{s},{d:.12}\n", .{ "s3", ext.s3 });
    try writer.print("{s},{d:.12}\n", .{ "s4", ext.s4 });
    try writer.print("{s},{d:.12}\n", .{ "tau_x", ext.tau_x });
    try writer.print("{s},{d:.12}\n", .{ "tau_y", ext.tau_y });
}

fn parsePolynomialMap(
    kv: *const std.StringHashMap([]const u8),
    prefix: []const u8,
    order: cam.PolynomialOrder,
) !cam.PolynomialMap {
    var map: cam.PolynomialMap = .{ .order = order };
    var key_buf: [64]u8 = undefined;
    const term_count = order.termCount();
    for (0..term_count) |ii| {
        const key_u = try std.fmt.bufPrint(
            key_buf[0..],
            "{s}_u_{d}",
            .{ prefix, ii },
        );
        map.coeffs_u[ii] = try std.fmt.parseFloat(F, try requireValue(kv, key_u));
        const key_v = try std.fmt.bufPrint(
            key_buf[0..],
            "{s}_v_{d}",
            .{ prefix, ii },
        );
        map.coeffs_v[ii] = try std.fmt.parseFloat(F, try requireValue(kv, key_v));
    }
    return map;
}

fn loadPolynomial(
    kv: *const std.StringHashMap([]const u8),
) !?cam.BidirectionalPolynomial {
    const has_forward = (try parseOptionalU8Value(kv, "poly_has_forward", 0)) != 0;
    const has_inv = (try parseOptionalU8Value(kv, "poly_has_inv", 0)) != 0;
    if (!has_forward and !has_inv) {
        return null;
    }
    const order_val = try parseOptionalU8Value(
        kv,
        "poly_order",
        @intFromEnum(cam.PolynomialOrder.quadratic),
    );
    const order: cam.PolynomialOrder = switch (order_val) {
        1 => .linear,
        2 => .quadratic,
        3 => .cubic,
        else => return error.InvalidPolynomialOrder,
    };

    var polynomial: cam.BidirectionalPolynomial = .{};
    if (has_forward) {
        polynomial.forward_map = try parsePolynomialMap(kv, "poly_forward", order);
    }
    if (has_inv) {
        polynomial.inv_map = try parsePolynomialMap(kv, "poly_inv", order);
    }
    return polynomial;
}

fn writeDistortion(
    writer: *std.Io.Writer,
    distortion: cam.DistortionParams,
) !void {
    switch (distortion) {
        .none => {
            try writer.print("{s},{s}\n", .{ "distortion_model", "none" });
            try writer.print("{s},{d:.12}\n", .{ "k1", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k2", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k3", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k4", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k5", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k6", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p1", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p2", 0.0 });
            try writeExtendedDistortion(writer, null);
            try writePolynomialMetadata(writer, null);
        },
        .brown_conrady => |model| {
            try writer.print("{s},{s}\n", .{
                "distortion_model",
                "brown_conrady",
            });
            try writer.print("{s},{d:.12}\n", .{ "k1", model.k1 });
            try writer.print("{s},{d:.12}\n", .{ "k2", model.k2 });
            try writer.print("{s},{d:.12}\n", .{ "k3", model.k3 });
            try writer.print("{s},{d:.12}\n", .{ "k4", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k5", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k6", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p1", model.p1 });
            try writer.print("{s},{d:.12}\n", .{ "p2", model.p2 });
            try writeExtendedDistortion(writer, null);
            try writePolynomialMetadata(writer, null);
        },
        .brown_conrady_ext => |model| {
            try writer.print("{s},{s}\n", .{
                "distortion_model",
                "brown_conrady_ext",
            });
            try writer.print("{s},{d:.12}\n", .{ "k1", model.k1 });
            try writer.print("{s},{d:.12}\n", .{ "k2", model.k2 });
            try writer.print("{s},{d:.12}\n", .{ "k3", model.k3 });
            try writer.print("{s},{d:.12}\n", .{ "k4", model.k4 });
            try writer.print("{s},{d:.12}\n", .{ "k5", model.k5 });
            try writer.print("{s},{d:.12}\n", .{ "k6", model.k6 });
            try writer.print("{s},{d:.12}\n", .{ "p1", model.p1 });
            try writer.print("{s},{d:.12}\n", .{ "p2", model.p2 });
            try writeExtendedDistortion(writer, model);
            try writePolynomialMetadata(writer, null);
        },
        .polynomial => |poly| {
            try writer.print("{s},{s}\n", .{ "distortion_model", "polynomial" });
            try writer.print("{s},{d:.12}\n", .{ "k1", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k2", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k3", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k4", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k5", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k6", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p1", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p2", 0.0 });
            try writeExtendedDistortion(writer, null);
            try writePolynomialMetadata(writer, poly);
        },
        .brown_conrady_polynomial => |chain| {
            try writer.print("{s},{s}\n", .{
                "distortion_model",
                "brown_conrady_polynomial",
            });
            try writer.print("{s},{d:.12}\n", .{ "k1", chain.brown_conrady.k1 });
            try writer.print("{s},{d:.12}\n", .{ "k2", chain.brown_conrady.k2 });
            try writer.print("{s},{d:.12}\n", .{ "k3", chain.brown_conrady.k3 });
            try writer.print("{s},{d:.12}\n", .{ "k4", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k5", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "k6", 0.0 });
            try writer.print("{s},{d:.12}\n", .{ "p1", chain.brown_conrady.p1 });
            try writer.print("{s},{d:.12}\n", .{ "p2", chain.brown_conrady.p2 });
            try writeExtendedDistortion(writer, null);
            try writePolynomialMetadata(writer, chain.polynomial);
        },
        .brown_conrady_ext_polynomial => |chain| {
            try writer.print("{s},{s}\n", .{
                "distortion_model",
                "brown_conrady_ext_polynomial",
            });
            try writer.print("{s},{d:.12}\n", .{
                "k1",
                chain.brown_conrady_ext.k1,
            });
            try writer.print("{s},{d:.12}\n", .{
                "k2",
                chain.brown_conrady_ext.k2,
            });
            try writer.print("{s},{d:.12}\n", .{
                "k3",
                chain.brown_conrady_ext.k3,
            });
            try writer.print("{s},{d:.12}\n", .{
                "k4",
                chain.brown_conrady_ext.k4,
            });
            try writer.print("{s},{d:.12}\n", .{
                "k5",
                chain.brown_conrady_ext.k5,
            });
            try writer.print("{s},{d:.12}\n", .{
                "k6",
                chain.brown_conrady_ext.k6,
            });
            try writer.print("{s},{d:.12}\n", .{
                "p1",
                chain.brown_conrady_ext.p1,
            });
            try writer.print("{s},{d:.12}\n", .{
                "p2",
                chain.brown_conrady_ext.p2,
            });
            try writeExtendedDistortion(writer, chain.brown_conrady_ext);
            try writePolynomialMetadata(writer, chain.polynomial);
        },
    }
}

fn loadDistortion(
    kv: *const std.StringHashMap([]const u8),
) !cam.DistortionParams {
    const model_name = try requireValue(kv, "distortion_model");
    const polynomial = try loadPolynomial(kv);
    if (std.mem.eql(u8, model_name, "none")) {
        return .none;
    }
    if (std.mem.eql(u8, model_name, "brown_conrady")) {
        return .{ .brown_conrady = .{
            .k1 = try std.fmt.parseFloat(F, try requireValue(kv, "k1")),
            .k2 = try std.fmt.parseFloat(F, try requireValue(kv, "k2")),
            .k3 = try std.fmt.parseFloat(F, try requireValue(kv, "k3")),
            .p1 = try std.fmt.parseFloat(F, try requireValue(kv, "p1")),
            .p2 = try std.fmt.parseFloat(F, try requireValue(kv, "p2")),
        } };
    }
    if (std.mem.eql(u8, model_name, "brown_conrady_ext")) {
        return .{ .brown_conrady_ext = .{
            .k1 = try std.fmt.parseFloat(F, try requireValue(kv, "k1")),
            .k2 = try std.fmt.parseFloat(F, try requireValue(kv, "k2")),
            .k3 = try std.fmt.parseFloat(F, try requireValue(kv, "k3")),
            .k4 = try std.fmt.parseFloat(F, try requireValue(kv, "k4")),
            .k5 = try std.fmt.parseFloat(F, try requireValue(kv, "k5")),
            .k6 = try std.fmt.parseFloat(F, try requireValue(kv, "k6")),
            .p1 = try std.fmt.parseFloat(F, try requireValue(kv, "p1")),
            .p2 = try std.fmt.parseFloat(F, try requireValue(kv, "p2")),
            .s1 = try parseOptionalFloatValue(kv, "s1", 0.0),
            .s2 = try parseOptionalFloatValue(kv, "s2", 0.0),
            .s3 = try parseOptionalFloatValue(kv, "s3", 0.0),
            .s4 = try parseOptionalFloatValue(kv, "s4", 0.0),
            .tau_x = try parseOptionalFloatValue(kv, "tau_x", 0.0),
            .tau_y = try parseOptionalFloatValue(kv, "tau_y", 0.0),
        } };
    }
    if (std.mem.eql(u8, model_name, "polynomial")) {
        return .{ .polynomial = polynomial orelse return error.MissingPolynomialMap };
    }
    if (std.mem.eql(u8, model_name, "brown_conrady_polynomial")) {
        return .{ .brown_conrady_polynomial = .{
            .brown_conrady = .{
                .k1 = try std.fmt.parseFloat(F, try requireValue(kv, "k1")),
                .k2 = try std.fmt.parseFloat(F, try requireValue(kv, "k2")),
                .k3 = try std.fmt.parseFloat(F, try requireValue(kv, "k3")),
                .p1 = try std.fmt.parseFloat(F, try requireValue(kv, "p1")),
                .p2 = try std.fmt.parseFloat(F, try requireValue(kv, "p2")),
            },
            .polynomial = polynomial orelse return error.MissingPolynomialMap,
        } };
    }
    if (std.mem.eql(u8, model_name, "brown_conrady_ext_polynomial")) {
        return .{ .brown_conrady_ext_polynomial = .{
            .brown_conrady_ext = .{
                .k1 = try std.fmt.parseFloat(F, try requireValue(kv, "k1")),
                .k2 = try std.fmt.parseFloat(F, try requireValue(kv, "k2")),
                .k3 = try std.fmt.parseFloat(F, try requireValue(kv, "k3")),
                .k4 = try std.fmt.parseFloat(F, try requireValue(kv, "k4")),
                .k5 = try std.fmt.parseFloat(F, try requireValue(kv, "k5")),
                .k6 = try std.fmt.parseFloat(F, try requireValue(kv, "k6")),
                .p1 = try std.fmt.parseFloat(F, try requireValue(kv, "p1")),
                .p2 = try std.fmt.parseFloat(F, try requireValue(kv, "p2")),
                .s1 = try parseOptionalFloatValue(kv, "s1", 0.0),
                .s2 = try parseOptionalFloatValue(kv, "s2", 0.0),
                .s3 = try parseOptionalFloatValue(kv, "s3", 0.0),
                .s4 = try parseOptionalFloatValue(kv, "s4", 0.0),
                .tau_x = try parseOptionalFloatValue(kv, "tau_x", 0.0),
                .tau_y = try parseOptionalFloatValue(kv, "tau_y", 0.0),
            },
            .polynomial = polynomial orelse return error.MissingPolynomialMap,
        } };
    }
    return error.InvalidDistortionModel;
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

const testing = std.testing;
const temp_test_dir = "out/test_cameraio";

fn initTestCamera(
    pos_world: [3]F,
    alpha_z: F,
    beta_y: F,
    gamma_x: F,
    coord_sys: cam.CameraCoordSys,
) cam.CameraInput {
    return .{
        .pixels_num = .{ 640, 480 },
        .pixels_size = .{ 3.45e-6, 3.45e-6 },
        .pos_world = vec.initVec3(F, pos_world[0], pos_world[1], pos_world[2]),
        .rot_world = rotation.Rotation.init(alpha_z, beta_y, gamma_x),
        .roi_cent_world = vec.initVec3(F, 0.01, 0.02, 0.0),
        .focal_length = 50.0e-3,
        .sub_sample = 2,
        .coord_sys = coord_sys,
    };
}

fn expectVecApproxEqual(expected: vec.Vec3f, actual: vec.Vec3f) !void {
    const tol: F = if (F == f32) 1.0e-5 else 1.0e-11;
    try testing.expectApproxEqAbs(expected.get(0), actual.get(0), tol);
    try testing.expectApproxEqAbs(expected.get(1), actual.get(1), tol);
    try testing.expectApproxEqAbs(expected.get(2), actual.get(2), tol);
}

const StereoBaselineSummary = struct {
    baseline: vec.Vec3f,
    length: F,
};

fn readSummaryBaseline(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    file_name: []const u8,
) !StereoBaselineSummary {
    var kv = try parseKeyValueCsv(allocator, io, dir, file_name);
    defer deinitKeyValueCsv(allocator, &kv);
    return .{
        .baseline = vec.initVec3(
            F,
            try std.fmt.parseFloat(F, try requireValue(&kv, "baseline_x_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "baseline_y_m")),
            try std.fmt.parseFloat(F, try requireValue(&kv, "baseline_z_m")),
        ),
        .length = try std.fmt.parseFloat(
            F,
            try requireValue(&kv, "baseline_len_m"),
        ),
    };
}

test "camera I/O preserves physical stereo baseline across OpenGL and OpenCV exports" {
    const allocator = testing.allocator;
    const io = testing.io;
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "out", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    cwd.deleteTree(io, temp_test_dir) catch {};
    try cwd.createDir(io, temp_test_dir, .default_dir);
    defer cwd.deleteTree(io, temp_test_dir) catch {};

    var out_dir = try cwd.openDir(io, temp_test_dir, .{});
    defer out_dir.close(io);

    const cam0 = initTestCamera(.{ 0.0125, 0.0175, 0.1600 }, 0.0, 0.0, 0.0, .opengl);
    const cam1 = initTestCamera(.{ 0.0675, 0.0175, 0.1500 }, 0.0, 0.35, 0.0, .opengl);
    const expected_baseline = cam1.pos_world.sub(cam0.pos_world);

    try saveCamera(io, out_dir, "camera_opengl.csv", 0, cam0);
    const loaded_opengl = try loadCamera(allocator, io, out_dir, "camera_opengl.csv");
    try expectVecApproxEqual(cam0.pos_world, loaded_opengl.pos_world);

    var cam0_opencv = cam0;
    var cam1_opencv = cam1;
    cam0_opencv.coord_sys = .opencv;
    cam1_opencv.coord_sys = .opencv;
    try saveCamera(io, out_dir, "camera_opencv.csv", 0, cam0_opencv);
    const loaded_opencv = try loadCamera(allocator, io, out_dir, "camera_opencv.csv");
    try expectVecApproxEqual(cam0.pos_world, loaded_opencv.pos_world);

    try saveStereoPair(
        io,
        out_dir,
        "stereo_data_opengl.csv",
        .{ .cameras = .{ cam0, cam1 } },
    );
    try saveStereoPair(
        io,
        out_dir,
        "stereo_data_opencv.csv",
        .{ .cameras = .{ cam0_opencv, cam1_opencv } },
    );

    const loaded_stereo = try loadStereoPair(
        allocator,
        io,
        out_dir,
        "stereo_data_opencv.csv",
    );
    try expectVecApproxEqual(cam0.pos_world, loaded_stereo.cameras[0].pos_world);
    try expectVecApproxEqual(cam1.pos_world, loaded_stereo.cameras[1].pos_world);

    const opengl_summary = try readSummaryBaseline(
        allocator,
        io,
        out_dir,
        "stereo_data_opengl.csv",
    );
    const opencv_summary = try readSummaryBaseline(
        allocator,
        io,
        out_dir,
        "stereo_data_opencv.csv",
    );
    try expectVecApproxEqual(expected_baseline, opengl_summary.baseline);
    try expectVecApproxEqual(expected_baseline, opencv_summary.baseline);
    const expected_baseline_len = expected_baseline.vecLen();
    const tol: F = if (F == f32) 1.0e-5 else 1.0e-11;
    try testing.expectApproxEqAbs(expected_baseline_len, opengl_summary.length, tol);
    try testing.expectApproxEqAbs(expected_baseline_len, opencv_summary.length, tol);
}
