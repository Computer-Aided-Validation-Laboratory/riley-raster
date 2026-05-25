// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const zraster = @import("zraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;
const meshio = @import("zraster/zig/meshio.zig");
const uvio = @import("zraster/zig/uvio.zig");
const iio = @import("zraster/zig/imageio.zig");
const mo = @import("zraster/zig/meshops.zig");
const MeshInput = mo.MeshInput;
const camera_mod = @import("zraster/zig/camera.zig");
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const CameraInput = camera_mod.CameraInput;
const CameraOps = camera_mod.CameraOps;
const DistortionModel = camera_mod.DistortionModel;
const BrownConrady = camera_mod.BrownConrady;

const DATA_DIR = "data/calplate/tri3_calplate/";
const TEXTURE_PATH = "texture/cal_target-simple.tiff";
const OUT_DIR_ROOT = "out/calibration";

const PIXELS_NUM = [2]u32{ 2464, 2056 };
const PIXELS_SIZE = [2]f64{ 3.45e-6, 3.45e-6 };
const FOCAL_LENGTH: f64 = 50.0e-3;
const FOV_SCALE_FACTOR: f64 = 1.2;
const STEREO_ANGLE_DEG: f64 = 20.0;
const SUB_SAMPLE: u8 = 2;

const TOTAL_THREADS: u16 = 8;
const RENDER_GROUP_COUNT: u16 = 8;
const WORKERS_PER_GROUP: u16 = 1;
const DISTORTION = false;

fn getDistortionModel() DistortionModel {
    if (!DISTORTION) {
        return .none;
    }

    return .{ .brown_conrady = BrownConrady{
        .k1 = -0.08,
        .k2 = 0.01,
        .k3 = 0.0,
        .p1 = 0.0004,
        .p2 = -0.0007,
    } };
}

fn writeCsvRow(
    writer: *std.Io.Writer,
    entity: []const u8,
    camera_idx: ?usize,
    key: []const u8,
    unit: []const u8,
    value: f64,
) !void {
    if (camera_idx) |idx| {
        try writer.print("{s},{d},{s},{s},{d:.10}\n", .{
            entity,
            idx,
            key,
            unit,
            value,
        });
    } else {
        try writer.print("{s},,{s},{s},{d:.10}\n", .{
            entity,
            key,
            unit,
            value,
        });
    }
}

fn writeCameraDataCsv(
    io: std.Io,
    out_dir: std.Io.Dir,
    cameras: []const CameraInput,
    target_coords: *const meshio.Coords,
    distortion: DistortionModel,
) !void {
    const file_name = "cameradata.csv";
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    try writer.writeAll("entity,camera_idx,key,unit,value\n");

    const sensor_size = CameraOps.calcSensorSize(PIXELS_NUM, PIXELS_SIZE);
    const roi_cent_world = CameraOps.roiCentFromCoords(target_coords);

    try writeCsvRow(writer, "target", null, "roi_cent_x", "m", roi_cent_world.get(0));
    try writeCsvRow(writer, "target", null, "roi_cent_y", "m", roi_cent_world.get(1));
    try writeCsvRow(writer, "target", null, "roi_cent_z", "m", roi_cent_world.get(2));

    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_min_x",
        "m",
        target_coords.mat.minByRow(0),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_min_y",
        "m",
        target_coords.mat.minByRow(1),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_min_z",
        "m",
        target_coords.mat.minByRow(2),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_max_x",
        "m",
        target_coords.mat.maxByRow(0),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_max_y",
        "m",
        target_coords.mat.maxByRow(1),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "bbox_max_z",
        "m",
        target_coords.mat.maxByRow(2),
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "normal_x",
        "-",
        0.0,
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "normal_y",
        "-",
        0.0,
    );
    try writeCsvRow(
        writer,
        "target",
        null,
        "normal_z",
        "-",
        1.0,
    );

    try writeCsvRow(
        writer,
        "render",
        null,
        "pixels_x",
        "px",
        @floatFromInt(PIXELS_NUM[0]),
    );
    try writeCsvRow(
        writer,
        "render",
        null,
        "pixels_y",
        "px",
        @floatFromInt(PIXELS_NUM[1]),
    );
    try writeCsvRow(
        writer,
        "render",
        null,
        "pixel_size_x",
        "m",
        PIXELS_SIZE[0],
    );
    try writeCsvRow(
        writer,
        "render",
        null,
        "pixel_size_y",
        "m",
        PIXELS_SIZE[1],
    );
    try writeCsvRow(
        writer,
        "render",
        null,
        "sub_sample",
        "-",
        @floatFromInt(SUB_SAMPLE),
    );

    for (cameras, 0..) |camera, cc| {
        try writeCsvRow(writer, "camera", cc, "pos_x", "m", camera.pos_world.get(0));
        try writeCsvRow(writer, "camera", cc, "pos_y", "m", camera.pos_world.get(1));
        try writeCsvRow(writer, "camera", cc, "pos_z", "m", camera.pos_world.get(2));

        try writeCsvRow(
            writer,
            "camera",
            cc,
            "rot_alpha_z_deg",
            "deg",
            std.math.radiansToDegrees(camera.rot_world.alpha_z),
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "rot_beta_y_deg",
            "deg",
            std.math.radiansToDegrees(camera.rot_world.beta_y),
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "rot_gamma_x_deg",
            "deg",
            std.math.radiansToDegrees(camera.rot_world.gamma_x),
        );

        try writeCsvRow(
            writer,
            "camera",
            cc,
            "focal_length",
            "m",
            camera.focal_length,
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "sensor_size_x",
            "m",
            sensor_size[0],
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "sensor_size_y",
            "m",
            sensor_size[1],
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "roi_cent_x",
            "m",
            camera.roi_cent_world.get(0),
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "roi_cent_y",
            "m",
            camera.roi_cent_world.get(1),
        );
        try writeCsvRow(
            writer,
            "camera",
            cc,
            "roi_cent_z",
            "m",
            camera.roi_cent_world.get(2),
        );
    }

    switch (distortion) {
        .none => {
            try writeCsvRow(
                writer,
                "distortion",
                null,
                "enabled",
                "-",
                0.0,
            );
        },
        .brown_conrady => |model| {
            try writeCsvRow(
                writer,
                "distortion",
                null,
                "enabled",
                "-",
                1.0,
            );
            try writeCsvRow(
                writer,
                "distortion",
                null,
                "model_brown_conrady",
                "-",
                1.0,
            );
            try writeCsvRow(writer, "distortion", null, "k1", "-", model.k1);
            try writeCsvRow(writer, "distortion", null, "k2", "-", model.k2);
            try writeCsvRow(writer, "distortion", null, "k3", "-", model.k3);
            try writeCsvRow(writer, "distortion", null, "p1", "-", model.p1);
            try writeCsvRow(writer, "distortion", null, "p2", "-", model.p2);
        },
        .brown_conrady_ext => |model| {
            try writeCsvRow(
                writer,
                "distortion",
                null,
                "enabled",
                "-",
                1.0,
            );
            try writeCsvRow(
                writer,
                "distortion",
                null,
                "model_brown_conrady_ext",
                "-",
                1.0,
            );
            try writeCsvRow(writer, "distortion", null, "k1", "-", model.k1);
            try writeCsvRow(writer, "distortion", null, "k2", "-", model.k2);
            try writeCsvRow(writer, "distortion", null, "k3", "-", model.k3);
            try writeCsvRow(writer, "distortion", null, "k4", "-", model.k4);
            try writeCsvRow(writer, "distortion", null, "k5", "-", model.k5);
            try writeCsvRow(writer, "distortion", null, "k6", "-", model.k6);
            try writeCsvRow(writer, "distortion", null, "p1", "-", model.p1);
            try writeCsvRow(writer, "distortion", null, "p2", "-", model.p2);
        },
    }

    try file_writer.flush();
}

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const distortion = getDistortionModel();
    const config = RasterConfig{
        .render_mode = .offline,
        .total_threads = TOTAL_THREADS,
        .max_frames_in_flight = RENDER_GROUP_COUNT,
        .max_geom_workers_per_frame = 1,
        .max_raster_workers_per_frame = 1,
        .frame_batch_size_per_group = 8,
        .max_geom_jobs_in_flight_per_group = 8,
        .max_geom_workers_per_job = 1,
        .geom_scheduling_mode = .spread,
        .max_raster_workers_per_job = 1,
        .save_strategy = .disk,
        .tile_size_min = 8,
        .tile_size_max = 128,
        .background_value = 128.0,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };

    const coord_path = DATA_DIR ++ "coords.csv";
    const conn_path = DATA_DIR ++ "connect.csv";
    const uv_path = DATA_DIR ++ "uvs.csv";
    const disp_paths = &[_][]const u8{
        DATA_DIR ++ "field_disp_x.csv",
        DATA_DIR ++ "field_disp_y.csv",
        DATA_DIR ++ "field_disp_z.csv",
    };

    const managed_ios = try outer_alloc.alloc(std.Io.Threaded, RENDER_GROUP_COUNT);
    defer {
        for (managed_ios) |*managed_io| {
            managed_io.deinit();
        }
        outer_alloc.free(managed_ios);
    }

    const render_groups = try outer_alloc.alloc(
        zraster.RenderGroupSpec,
        RENDER_GROUP_COUNT,
    );
    defer outer_alloc.free(render_groups);

    for (0..RENDER_GROUP_COUNT) |gg| {
        managed_ios[gg] = zraster.getThreadedIo(
            outer_alloc,
            init.minimal,
            WORKERS_PER_GROUP,
        );
        render_groups[gg] = .{
            .io = managed_ios[gg].io(),
            .workers = WORKERS_PER_GROUP,
        };
    }
    const io = render_groups[0].io;

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "out", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    cwd.createDir(io, OUT_DIR_ROOT, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try cwd.openDir(io, OUT_DIR_ROOT, .{});
    defer out_dir.close(io);

    var sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        conn_path,
        null,
        disp_paths,
    );
    defer sim_data.deinit(aa);

    var uvs = try uvio.loadUVMap(aa, io, uv_path);
    defer uvs.deinit(aa);

    var texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        TEXTURE_PATH,
        .tiff,
    );
    defer texture.deinit(aa);

    const mesh_input = MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = sim_data.disp,
        .shader = .{ .tex = .{
            .uvs = uvs.array,
            .texture = texture,
            .sample_config = .{
                .sample = .cubic_catmull_rom,
                .mode = .lut_lerp,
            },
            .bits = 8,
            .scaling = .none,
        } },
    };

    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);

    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
    );
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(STEREO_ANGLE_DEG),
        std.math.degreesToRadians(0.0),
    );

    const cam0_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        PIXELS_NUM,
        PIXELS_SIZE,
        FOCAL_LENGTH,
        cam0_rot,
        FOV_SCALE_FACTOR,
    );
    const cam1_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        PIXELS_NUM,
        PIXELS_SIZE,
        FOCAL_LENGTH,
        cam1_rot,
        FOV_SCALE_FACTOR,
    );

    const cam0_in = CameraInput{
        .pixels_num = PIXELS_NUM,
        .pixels_size = PIXELS_SIZE,
        .pos_world = cam0_pos,
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = FOCAL_LENGTH,
        .sub_sample = SUB_SAMPLE,
        .distortion = distortion,
    };
    const cam1_in = CameraInput{
        .pixels_num = PIXELS_NUM,
        .pixels_size = PIXELS_SIZE,
        .pos_world = cam1_pos,
        .rot_world = cam1_rot,
        .roi_cent_world = roi_pos,
        .focal_length = FOCAL_LENGTH,
        .sub_sample = SUB_SAMPLE,
        .distortion = distortion,
    };

    const cameras = [_]CameraInput{ cam0_in, cam1_in };
    try writeCameraDataCsv(
        io,
        out_dir,
        &cameras,
        &sim_data.coords,
        distortion,
    );

    const meshes = [_]MeshInput{mesh_input};
    const images = try zraster.rasterAllFrames(
        f64,
        aa,
        render_groups,
        &cameras,
        &meshes,
        config,
        OUT_DIR_ROOT,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }
}
