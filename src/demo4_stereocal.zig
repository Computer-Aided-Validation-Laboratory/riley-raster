// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const demo_common = @import("demo_common.zig");

const buildconfig = @import("riley/zig/buildconfig.zig");
const riley = @import("riley/zig/riley.zig");
const RasterConfig = riley.RasterConfig;
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const iio = @import("riley/zig/imageio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const MeshInput = meshpipe.MeshInput;
const camera_mod = @import("riley/zig/camera.zig");
const CameraInput = camera_mod.CameraInput;
const cameraio = @import("riley/zig/cameraio.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const vecstack = @import("riley/zig/vecstack.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const DistortModel = camera_mod.DistortParams;
const BrownCon = camera_mod.BrownCon;
const BrownConExt = camera_mod.BrownConExt;
const StereoPairInput = camera_mod.StereoPairInput;
const F = buildconfig.F;

const DistortCase = enum {
    none,
    brown_con,
    brown_con_ext,
};

fn buildDistort(distort_case: DistortCase) DistortModel {
    return switch (distort_case) {
        .none => .none,
        .brown_con => .{ .brown_con = BrownCon.Params{
            .k1 = -0.2,
            .k2 = 0.1,
            .k3 = 0.0,
            .p1 = 0.0001,
            .p2 = -0.0001,
        } },
        .brown_con_ext => .{ .brown_con_ext = BrownConExt.Params{
            .k1 = -0.2,
            .k2 = 0.1,
            .k3 = -0.01,
            .k4 = -0.04,
            .k5 = 0.18,
            .k6 = -0.02,
            .p1 = 0.0001,
            .p2 = -0.0001,
        } },
    };
}

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/calplate/tri3_calplate3d/";
    const texture_path = "texture/cal_target.tiff";
    const out_dir_root = "./out/demo4_stereocal";

    const total_threads: u16 = 8;

    var coord_sys = camera_mod.CameraCoordSys.opengl;
    var arg_it = try std.process.Args.Iterator.initAllocator(
        init.minimal.args,
        local_alloc,
    );
    defer arg_it.deinit();
    _ = arg_it.next();
    if (arg_it.next()) |arg| {
        if (std.mem.eql(u8, arg, "opencv")) {
            coord_sys = .opencv;
        }
    }
    const stereo_file_name = if (coord_sys == .opencv)
        "stereo_data_opencv.csv"
    else
        "stereo_data_opengl.csv";

    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const uv_path = data_dir ++ "uvs.csv";
    const disp_paths = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };

    var groups = try riley.ManagedRenderGroups.init(outer_alloc, init.minimal, .{
        .thread_budget = total_threads,
    });
    defer groups.deinit(outer_alloc);
    const io = groups.specs[0].io;

    var out_dir = try demo_common.resetOutputDir(io, out_dir_root);
    defer out_dir.close(io);

    // -------------------------------------------------------------------------
    // 2. Load calibration plate mesh, sample frames, and apply texture
    // -------------------------------------------------------------------------
    var sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        coord_path,
        conn_path,
        null,
        disp_paths,
    );
    defer sim_data.deinit(local_alloc);
    const disp_source = sim_data.disp orelse return error.MissingDisplacement;
    const frames_max: usize = 8;
    const frame_indices = try sceneops.selectEvenlySpacedFrameIndices(
        local_alloc,
        disp_source.getTimeN(),
        frames_max,
    );
    var selected_disp = try sceneops.selectFieldFrames(
        local_alloc,
        &disp_source,
        frame_indices,
    );
    defer selected_disp.deinit(local_alloc);

    var uvs = try uvio.loadUVMap(local_alloc, io, uv_path);
    defer uvs.deinit(local_alloc);

    var texture = try iio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        texture_path,
        .tiff,
    );
    defer texture.deinit(local_alloc);

    const distort_case: DistortCase = .brown_con;
    const distort = buildDistort(distort_case);

    const matched_roi = [3]F{ 0.0125, 0.0175, 0.0005 };

    const target_roi = vecstack.Vec3f.initSlice(matched_roi[0..]);
    sceneops.centerCoordsAt(&sim_data.coords, target_roi.vec);
    const roi_pos = sceneops.boundsCenter(&sim_data.coords);

    // -------------------------------------------------------------------------
    // 3. Create, save, and reload stereo camera pair
    // -------------------------------------------------------------------------
    const pixels_num = [2]u32{ 2464, 2056 };
    const pixels_size = [2]F{ 3.45e-6, 3.45e-6 };
    const focal_length: F = 50.0e-3;
    const stereo_angle_deg: F = 20.0;
    const sub_sample: u32 = 2;
    const matched_cam0_pos = [3]F{ 0.0125, 0.0175, 0.160864856482 };
    const matched_cam1_pos = [3]F{ 0.067348011198, 0.0175, 0.151193672270 };

    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
    );
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(stereo_angle_deg),
        std.math.degreesToRadians(0.0),
    );

    const cam0_pos = vecstack.Vec3f.initSlice(matched_cam0_pos[0..]);
    const cam1_pos = vecstack.Vec3f.initSlice(matched_cam1_pos[0..]);

    const cam0_in = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cam0_pos,
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_length,
        .sub_sample = sub_sample,
        .distort = distort,
    };
    var cam1_in = cam0_in;
    cam1_in.rot_world = cam1_rot;
    cam1_in.pos_world = cam1_pos;

    var stereo_pair = StereoPairInput{
        .cameras = .{ cam0_in, cam1_in },
    };

    // Save stereo pair to output directory
    try cameraio.saveStereoPair(io, out_dir, stereo_file_name, stereo_pair);

    // Load stereo pair back from output directory (standalone test)
    const loaded_stereo = try cameraio.LoadedStereoPair.init(
        local_alloc,
        io,
        out_dir,
        stereo_file_name,
    );
    defer loaded_stereo.deinit(local_alloc);
    stereo_pair = loaded_stereo.stereo_pair;

    // -------------------------------------------------------------------------
    // 4. Build mesh and raster configuration
    // -------------------------------------------------------------------------
    const mesh_input = MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = selected_disp,
        .shader = .{ .tex_u8 = .{
            .uvs = uvs.array,
            .tex = texture,
            .samp_cfg = .{
                .sample = .cubic_catmull_rom,
                .mode = .lut_lerp,
            },
            .bits = 8,
            .scaling = .none,
        } },
    };

    const config = RasterConfig{
        .render_mode = .offline,
        .total_threads = total_threads,
        .frame_batch_size_per_group = frames_max,
        .max_geom_jobs_in_flight_per_group = frames_max,
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

    // -------------------------------------------------------------------------
    // 5. Render stereocal poses
    // -------------------------------------------------------------------------
    const meshes = [_]MeshInput{mesh_input};
    const images = try riley.raster(
        outer_alloc,
        groups.specs,
        &stereo_pair.cameras,
        &meshes,
        config,
        out_dir_root,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }
}
