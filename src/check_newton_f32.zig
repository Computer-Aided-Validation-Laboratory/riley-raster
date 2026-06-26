// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("riley/zig/buildconfig.zig");
const common = @import("common/benchcommon.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const riley = @import("riley/zig/riley.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const mo = @import("riley/zig/meshops.zig");
const iio = @import("riley/zig/imageio.zig");
const cam = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const F = buildconfig.F;
const CameraPrepared = cam.CameraPrepared;
const CameraInput = cam.CameraInput;

pub fn main(init: std.process.Init) !void {
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
    const allocator = init.gpa;
    const io = init.io;

    const texture_grey = try iio.loadImage(
        u8,
        1,
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    defer texture_grey.deinit(allocator);

    const texture_rgb = try iio.loadImage(
        u8,
        3,
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(allocator);

    const data_dir = "data/bench/quad8_fullraster";
    const render_defaults = common.BenchRenderDefaults{
        .pixels_num = .{ 800, 500 },
        .sub_sample = 2,
        .focal_leng = 50.0e-3,
        .pixels_size = .{ 5.3e-6, 5.3e-6 },
        .fov_scale = 1.0,
        .rot = Rotation.init(0, 0, 0),
    };
    const out_dir = if (F == f32)
        "out/check_newton/quad8_nodal_rgb"
    else if (F == f64)
        "out/check_newton_f64/quad8_nodal_rgb"
    else
        @compileError("Only f32 and f64 precision are supported.");

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const mesh_input = try common.loadBenchmarkMeshInput(
        u8,
        aa,
        io,
        .quad8,
        .nodal_rgb,
        null,
        null,
        data_dir,
        texture_grey,
        texture_rgb,
    );

    const roi_pos = cameraops.roiCentFromCoords(&mesh_input.coords);
    const cam_pos = cameraops.posFillFrameFromRot(
        &mesh_input.coords,
        render_defaults.pixels_num,
        render_defaults.pixels_size,
        render_defaults.focal_leng,
        render_defaults.rot,
        render_defaults.fov_scale,
    );
    const camera = try CameraPrepared.init(
        aa,
        .{
            .pixels_num = render_defaults.pixels_num,
            .pixels_size = render_defaults.pixels_size,
            .pos_world = cam_pos,
            .rot_world = render_defaults.rot,
            .roi_cent_world = roi_pos,
            .focal_length = render_defaults.focal_leng,
            .sub_sample = render_defaults.sub_sample,
            .distortion = render_defaults.distortion,
        },
    );
    defer camera.deinit(aa);

    const camera_input = CameraInput{
        .pixels_num = camera.pixels_num,
        .pixels_size = camera.pixels_size,
        .pos_world = camera.pos_world,
        .rot_world = camera.rot_world,
        .roi_cent_world = camera.roi_cent_world,
        .focal_length = camera.focal_length,
        .sub_sample = camera.sub_sample,
        .distortion = camera.distortion,
    };

    var config = tcfg.getRasterConfig(.testing);
    config.total_threads = 1;
    config.max_geom_workers_per_job = 1;
    config.max_raster_workers_per_job = 1;
    config.max_geom_jobs_in_flight_per_group = 1;
    config.frame_batch_size_per_group = 1;
    config.save_strategy = .disk;
    config.report = .full_stats;
    config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .fimg, .bits = null, .scaling = .none, .channels = 3 },
        .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
    };
    config.full_stats_opts = .{
        .formats = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .save_iteration_map = true,
        .save_xi_map = true,
        .save_eta_map = true,
        .save_converged_map = true,
        .save_jacobian_det_map = true,
        .save_tile_timing_map = true,
        .save_tile_density_map = true,
        .save_tile_occupancy_map = true,
        .save_depth_map = true,
        .save_earlyout_map = true,
        .save_pixel_occupancy_map = true,
        .save_normals_map = false,
    };

    var out_dir_handle = try orch.openDirEnsured(io, out_dir);
    out_dir_handle.close(io);

    const render_groups = [_]riley.RenderGroupSpec{
        .{ .io = io, .workers = @max(@as(u16, 1), config.total_threads) },
    };

    const images = try riley.raster(
        aa,
        &render_groups,
        &[_]CameraInput{camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        out_dir,
    );
    if (images) |img| {
        aa.free(img.slice);
        var img_mut = img;
        img_mut.deinit(aa);
    }

    std.debug.print(
        "Saved quad8 nodal RGB full_stats diagnostics to {s}\n",
        .{out_dir},
    );
}
