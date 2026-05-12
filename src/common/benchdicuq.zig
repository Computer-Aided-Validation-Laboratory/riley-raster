// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const benchargs = @import("benchargs.zig");
const common = @import("benchcommon.zig");
const zraster = @import("../zraster/zig/zraster.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const uvio = @import("../zraster/zig/uvio.zig");
const iio = @import("../zraster/zig/imageio.zig");
const mo = @import("../zraster/zig/meshops.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const texops = @import("../zraster/zig/textureops.zig");
const camera_mod = @import("../zraster/zig/camera.zig");
const Rotation = @import("../zraster/zig/rotation.zig").Rotation;
const report = @import("../zraster/zig/report.zig");
const tcfg = @import("testconfig.zig");

const CameraInput = camera_mod.CameraInput;
const MeshInput = mo.MeshInput;

pub const PreparedDicuqBenchmark = struct {
    mesh_input: MeshInput,
    camera_inputs: [2]CameraInput,
    sample_config: texops.TextureSampleConfig,
    fov_scale: f64,
};

pub fn getBaseRasterConfig() zraster.RasterConfig {
    var base_raster_config = tcfg.getRasterConfig(.bench);
    base_raster_config.total_threads = 4;
    base_raster_config.max_frames_in_flight = 2;
    base_raster_config.max_geom_workers_per_frame = 1;
    base_raster_config.max_raster_workers_per_frame = 4;
    base_raster_config.save_strategy = .disk;
    base_raster_config.tile_size_min = 8;
    base_raster_config.tile_size_max = 128;
    base_raster_config.background_value = 128.0;
    base_raster_config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };
    return base_raster_config;
}

pub fn makeSampleConfig(
    bench_args: benchargs.BenchArgs,
) !texops.TextureSampleConfig {
    const sample_config = texops.TextureSampleConfig{
        .sample = bench_args.sample orelse .cubic_catmull_rom,
        .mode = bench_args.sample_mode orelse .lut_lerp,
    };
    if (!sample_config.isValid()) {
        return error.InvalidTextureSampleConfig;
    }
    return sample_config;
}

pub fn prepareBenchmark(
    allocator: std.mem.Allocator,
    io: std.Io,
    pixel_num: [2]u32,
    sub_sample: u8,
    sample_config: texops.TextureSampleConfig,
) !PreparedDicuqBenchmark {
    const data_dir = "data/FE/platehole3d_4mr_2f/";
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const field_files = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };
    const uv_path = data_dir ++ "uvs.csv";

    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        coord_path,
        conn_path,
        null,
        field_files,
    );
    const uvs = try uvio.loadUVMap(allocator, io, uv_path);
    const texture = try iio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
    );

    const mesh_input = MeshInput{
        .mesh_type = .quad8,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = sim_data.disp,
        .shader = .{ .tex = .{
            .uvs = uvs.array,
            .texture = texture,
            .sample_config = sample_config,
            .bits = 8,
            .scaling = .none,
        } },
    };

    const pixel_size = [_]f64{ 3.45e-6, 3.45e-6 };
    const focal_length: f64 = 50.0e-3;
    const fov_scale: f64 = 0.9;
    const roi_pos = camera_mod.CameraOps.roiCentFromCoords(
        &sim_data.coords,
    );

    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
    );
    const cam0_pos = camera_mod.CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_length,
        cam0_rot,
        fov_scale,
    );
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(20.0),
        std.math.degreesToRadians(0.0),
    );
    const cam1_pos = camera_mod.CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_length,
        cam1_rot,
        fov_scale,
    );

    return .{
        .mesh_input = mesh_input,
        .camera_inputs = .{
            .{
                .pixels_num = pixel_num,
                .pixels_size = pixel_size,
                .pos_world = cam0_pos,
                .rot_world = cam0_rot,
                .roi_cent_world = roi_pos,
                .focal_length = focal_length,
                .sub_sample = sub_sample,
            },
            .{
                .pixels_num = pixel_num,
                .pixels_size = pixel_size,
                .pos_world = cam1_pos,
                .rot_world = cam1_rot,
                .roi_cent_world = roi_pos,
                .focal_length = focal_length,
                .sub_sample = sub_sample,
            },
        },
        .sample_config = sample_config,
        .fov_scale = fov_scale,
    };
}

pub fn calcCaseName(
    allocator: std.mem.Allocator,
    sample_config: texops.TextureSampleConfig,
) ![]const u8 {
    return common.calcCaseName(
        allocator,
        .quad8,
        .tex8_grey,
        sample_config,
        null,
        1.0,
    );
}

pub fn runBenchmark(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera_inputs: []const CameraInput,
    mesh_input: MeshInput,
    config: zraster.RasterConfig,
    out_dir_path: ?[]const u8,
) !common.BenchResult {
    const frame_count = if (mesh_input.disp) |disp|
        disp.getTimeN() * camera_inputs.len
    else
        camera_inputs.len;
    const bench_capture = try outer_alloc.alloc(
        report.FrameBenchCapture,
        frame_count,
    );
    defer outer_alloc.free(bench_capture);

    const start = std.Io.Clock.Timestamp.now(io, .awake);
    const image_arr = try zraster.rasterAllFrames(
        outer_alloc,
        io,
        camera_inputs,
        &[_]MeshInput{mesh_input},
        config,
        out_dir_path,
        bench_capture,
    );
    const end = std.Io.Clock.Timestamp.now(io, .awake);

    if (image_arr) |images| {
        outer_alloc.free(images.slice);
        var images_mut = images;
        images_mut.deinit(outer_alloc);
    }

    const frame_times = aggregateFrameTimes(bench_capture);
    const bench_log = aggregateBenchLog(bench_capture);
    const e2e_ms = @as(
        f64,
        @floatFromInt(start.durationTo(end).raw.nanoseconds),
    ) / 1e6;
    const frame_count_f = @as(f64, @floatFromInt(frame_count));

    return .{
        .e2e_ms = e2e_ms,
        .geom_ms = (frame_times.geometry_prep + frame_times.tile_overlap) /
            1e6,
        .raster_ms = frame_times.raster_loop / 1e6,
        .fps = if (e2e_ms > 0)
            (frame_count_f * 1000.0 / e2e_ms)
        else
            0.0,
        .metrics = calcDicuqMetrics(
            mesh_input.mesh_type,
            camera_inputs[0].pixels_num,
            camera_inputs[0].sub_sample,
            frame_count,
            frame_times,
            bench_log,
        ),
        .pipeline_times = frame_times,
        .image = null,
    };
}

fn aggregateFrameTimes(
    bench_capture: []const report.FrameBenchCapture,
) report.FrameTimes {
    var frame_times = report.FrameTimes{};

    for (bench_capture) |capture| {
        frame_times.geometry_prep +=
            capture.bench_log.frame_times.geometry_prep;
        frame_times.tile_overlap +=
            capture.bench_log.frame_times.tile_overlap;
        frame_times.raster_loop +=
            capture.bench_log.frame_times.raster_loop;
        frame_times.save_frame +=
            capture.bench_log.frame_times.save_frame;
        frame_times.total_time +=
            capture.bench_log.frame_times.total_time;
    }

    return frame_times;
}

fn aggregateBenchLog(
    bench_capture: []const report.FrameBenchCapture,
) report.BenchLog {
    var bench_log = report.BenchLog{};

    for (bench_capture) |capture| {
        report.reduceBenchLog(&bench_log, &capture.bench_log);
        bench_log.total_elements += capture.bench_log.total_elements;
        bench_log.visible_elements += capture.bench_log.visible_elements;
    }

    bench_log.frame_times = aggregateFrameTimes(bench_capture);
    return bench_log;
}

fn calcDicuqMetrics(
    mesh_type: gk.MeshType,
    pixel_num: [2]u32,
    sub_sample: u8,
    frame_count: usize,
    frame_times: report.FrameTimes,
    bench_log: report.BenchLog,
) common.CalculatedMetrics {
    const raster_sec = frame_times.raster_loop / 1e9;
    const geom_tiling_sec =
        (frame_times.geometry_prep + frame_times.tile_overlap) / 1e9;
    const total_sec = frame_times.total_time / 1e9;

    const nodes_per_elem = @as(f64, @floatFromInt(mesh_type.getNodesNum()));
    const pixels_x = @as(f64, @floatFromInt(pixel_num[0]));
    const pixels_y = @as(f64, @floatFromInt(pixel_num[1]));
    const frame_count_f = @as(f64, @floatFromInt(frame_count));
    const sub_samp_f = @as(f64, @floatFromInt(sub_sample));

    const total_px = pixels_x * pixels_y * frame_count_f;
    const total_subpx = total_px * sub_samp_f * sub_samp_f;

    const shaded_subpx = @as(
        f64,
        @floatFromInt(bench_log.total_shaded_pixels),
    );
    const est_shaded_px = shaded_subpx / (sub_samp_f * sub_samp_f);
    const total_elems = @as(
        f64,
        @floatFromInt(bench_log.total_elements),
    );

    return .{
        .mpx_sec = if (raster_sec > 0)
            (total_px / (raster_sec * 1e6))
        else
            0,
        .msubpx_sec = if (raster_sec > 0)
            (total_subpx / (raster_sec * 1e6))
        else
            0,
        .mshades_sec = if (raster_sec > 0)
            (est_shaded_px / (raster_sec * 1e6))
        else
            0,
        .msubshades_sec = if (raster_sec > 0)
            (shaded_subpx / (raster_sec * 1e6))
        else
            0,
        .melems_sec = if (geom_tiling_sec > 0)
            (total_elems / (geom_tiling_sec * 1e6))
        else
            0,
        .mnodes_sec = if (geom_tiling_sec > 0)
            (total_elems * nodes_per_elem / (geom_tiling_sec * 1e6))
        else
            0,
        .mops_sec = if (total_sec > 0)
            (nodes_per_elem * total_subpx / (total_sec * 1e6))
        else
            0,
    };
}
