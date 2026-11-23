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
const sceneops = @import("riley/zig/sceneops.zig");

const Rotation = @import("riley/zig/rotation.zig").Rotation;
const StereoPairInput = camera_mod.StereoPairInput;
const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Set paths and reset this demo's previous results
    // -------------------------------------------------------------------------
    const data_dir = "data/calplate/tri3_calplate3d/";
    const texture_path = "texture/cal_target.tiff";
    const out_dir_root = "./out/demo4_stereocal";

    const total_threads: u16 = 4;

    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const uv_path = data_dir ++ "uvs.csv";
    const disp_paths = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };

    const cwd = std.Io.Dir.cwd();
    try cwd.deleteTree(io, out_dir_root);
    const out_dir = try cwd.createDirPathOpen(io, out_dir_root, .{});
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

    // Translate the reference plate to the stereo target before applying the sampled motion.
    const matched_roi = [3]F{ 0.0125, 0.0175, 0.0005 };
    sceneops.centerCoordsAt(&sim_data.coords, matched_roi);
    const roi_pos = sceneops.boundsCenter(&sim_data.coords);

    // -------------------------------------------------------------------------
    // 3. Create, save, and reload stereo camera pair
    // -------------------------------------------------------------------------
    const coord_sys = camera_mod.CameraCoordSys.opengl;
    const stereo_file_name = if (coord_sys == .opencv)
        "stereo_data_opencv.csv"
    else
        "stereo_data_opengl.csv";

    const distort: camera_mod.DistortParams = .{ .brown_con = .{
        .k1 = -0.2,
        .k2 = 0.1,
        .k3 = 0.0,
        .p1 = 0.0001,
        .p2 = -0.0001,
    } };

    const pixels_num = [2]u32{ 2464, 2056 };
    const pixels_size = [2]F{ 3.45e-6, 3.45e-6 };
    const focal_length: F = 50.0e-3;
    const stereo_angle_deg: F = 20.0;
    const sub_sample: u32 = 4;
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

    const cam0_in = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = .{ .vec = matched_cam0_pos },
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_length,
        .sub_sample = sub_sample,
        .distort = distort,
        .coord_sys = coord_sys,
    };
    var cam1_in = cam0_in;
    cam1_in.rot_world = cam1_rot;
    cam1_in.pos_world = .{ .vec = matched_cam1_pos };

    const stereo_pair = StereoPairInput{
        .cameras = .{ cam0_in, cam1_in },
    };

    // Write the stereo manifest and individual camera CSVs.
    try cameraio.saveStereoPair(io, out_dir, stereo_file_name, stereo_pair);

    // Render from the exported calibration to demonstrate the CSV round trip.
    const loaded_stereo = try cameraio.LoadedStereoPair.init(
        local_alloc,
        io,
        out_dir,
        stereo_file_name,
    );
    defer loaded_stereo.deinit(local_alloc);

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
                .mode = .direct,
            },
            .bits = 8,
            .scaling = .none,
        } },
    };

    const config = RasterConfig{
        .render_mode = .offline,
        .parallel = .{ .threads = total_threads },
        .save_strategy = .disk,
        .background_value = 128.0,
        .output = .{
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        },
        .report = .{ .mode = .bench },
    };

    // -------------------------------------------------------------------------
    // 5. Render stereocal poses
    // -------------------------------------------------------------------------
    const images = try riley.raster(
        outer_alloc,
        io,
        &loaded_stereo.stereo_pair.cameras,
        &.{mesh_input},
        config,
        out_dir_root,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }
}
