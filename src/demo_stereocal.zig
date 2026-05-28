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
const Vec3f = @import("zraster/zig/vecstack.zig").Vec3f;
const camera_mod = @import("zraster/zig/camera.zig");
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const CameraInput = camera_mod.CameraInput;
const CameraOps = camera_mod.CameraOps;
const DistortionModel = camera_mod.DistortionModel;
const BrownConrady = camera_mod.BrownConrady;
const StereoPairInput = camera_mod.StereoPairInput;

const DATA_DIR = "data/calplate/tri3_calplate3d/";
const TEXTURE_PATH = "texture/cal_target-simple.tiff";
const OUT_DIR_ROOT = "./out/demo-stereocal";
const PIXELS_NUM = [2]u32{ 2464, 2056 };
const PIXELS_SIZE = [2]f64{ 3.45e-6, 3.45e-6 };
const FOCAL_LENGTH: f64 = 50.0e-3;
const FOV_SCALE_FACTOR: f64 = 1.1;
const STEREO_ANGLE_DEG: f64 = 20.0;
const SUB_SAMPLE: u8 = 2;
const DICUQ_MATCHED_ROI = [3]f64{ 0.0125, 0.0175, 0.0005 };
const DICUQ_MATCHED_CAM0_POS = [3]f64{ 0.0125, 0.0175, 0.160864856482 };
const DICUQ_MATCHED_CAM1_POS = [3]f64{ 0.125895077483, 0.0175, 0.113895077483 };
const DICUQ_MATCHED_CAM1_BETA_DEG: f64 = 20.0;

const TOTAL_THREADS: u16 = 8;
const RENDER_GROUP_COUNT: u16 = 8;
const WORKERS_PER_GROUP: u16 = 1;
const DISTORTION = false;

const CameraPlacementMode = enum {
    auto_fov,
    manual_match_dicuq,
};

const CAMERA_PLACEMENT_MODE: CameraPlacementMode = .manual_match_dicuq;

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
    out_dir.deleteFile(io, "cameradata.csv") catch |err| {
        if (err != error.FileNotFound) return err;
    };

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

    var roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);

    var stereo_pair = switch (CAMERA_PLACEMENT_MODE) {
        .auto_fov => blk: {
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

            break :blk StereoPairInput{
                .cameras = .{
                    .{
                        .pixels_num = PIXELS_NUM,
                        .pixels_size = PIXELS_SIZE,
                        .pos_world = cam0_pos,
                        .rot_world = cam0_rot,
                        .roi_cent_world = roi_pos,
                        .focal_length = FOCAL_LENGTH,
                        .sub_sample = SUB_SAMPLE,
                        .distortion = distortion,
                    },
                    .{
                        .pixels_num = PIXELS_NUM,
                        .pixels_size = PIXELS_SIZE,
                        .pos_world = cam1_pos,
                        .rot_world = cam1_rot,
                        .roi_cent_world = roi_pos,
                        .focal_length = FOCAL_LENGTH,
                        .sub_sample = SUB_SAMPLE,
                        .distortion = distortion,
                    },
                },
            };
        },
        .manual_match_dicuq => blk: {
            var sp: StereoPairInput = undefined;
            sp.cameras[0] = .{
                .pixels_num = PIXELS_NUM,
                .pixels_size = PIXELS_SIZE,
                .pos_world = Vec3f{ .slice = DICUQ_MATCHED_CAM0_POS },
                .rot_world = Rotation.init(0.0, 0.0, 0.0),
                .roi_cent_world = Vec3f{ .slice = DICUQ_MATCHED_ROI },
                .focal_length = FOCAL_LENGTH,
                .sub_sample = SUB_SAMPLE,
                .distortion = distortion,
            };
            sp.cameras[1] = .{
                .pixels_num = PIXELS_NUM,
                .pixels_size = PIXELS_SIZE,
                .pos_world = Vec3f{ .slice = DICUQ_MATCHED_CAM1_POS },
                .rot_world = Rotation.init(
                    0.0,
                    std.math.degreesToRadians(DICUQ_MATCHED_CAM1_BETA_DEG),
                    0.0,
                ),
                .roi_cent_world = Vec3f{ .slice = DICUQ_MATCHED_ROI },
                .focal_length = FOCAL_LENGTH,
                .sub_sample = SUB_SAMPLE,
                .distortion = distortion,
            };
            break :blk sp;
        },
    };

    if (CAMERA_PLACEMENT_MODE == .manual_match_dicuq) {
        const target_roi = stereo_pair.cameras[0].roi_cent_world;
        const roi_shift = target_roi.sub(roi_pos);
        for (0..sim_data.coords.mat.rows_num) |nn| {
            sim_data.coords.mat.set(
                nn,
                0,
                sim_data.coords.mat.get(nn, 0) + roi_shift.get(0),
            );
            sim_data.coords.mat.set(
                nn,
                1,
                sim_data.coords.mat.get(nn, 1) + roi_shift.get(1),
            );
            sim_data.coords.mat.set(
                nn,
                2,
                sim_data.coords.mat.get(nn, 2) + roi_shift.get(2),
            );
        }
        roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
        stereo_pair.cameras[0].distortion = distortion;
        stereo_pair.cameras[0].roi_cent_world = roi_pos;
        stereo_pair.cameras[1].distortion = distortion;
        stereo_pair.cameras[1].roi_cent_world = roi_pos;
    }
    try CameraOps.saveStereoPair(io, out_dir, stereo_pair);

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

    const meshes = [_]MeshInput{mesh_input};
    const images = try zraster.rasterAllFrames(
        aa,
        render_groups,
        &stereo_pair.cameras,
        &meshes,
        config,
        OUT_DIR_ROOT,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }
}
