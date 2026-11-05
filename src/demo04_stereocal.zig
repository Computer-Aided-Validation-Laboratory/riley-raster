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

const riley = @import("riley");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

const DistortCase = enum {
    none,
    brown_con,
    brown_con_ext,
};

fn buildDistort(distort_case: DistortCase) riley.DistortParams {
    return switch (distort_case) {
        .none => .none,
        .brown_con => .{ .brown_con = riley.BrownConParams{
            .k1 = -0.2,
            .k2 = 0.1,
            .k3 = 0.0,
            .p1 = 0.0001,
            .p2 = -0.0001,
        } },
        .brown_con_ext => .{ .brown_con_ext = riley.BrownConExtParams{
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
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/calplate/tri3_calplate3d/";
    const texture_path = "texture/cal_target.tiff";
    const out_dir_root = "./out/demo04_stereocal";

    const total_threads: u16 = 4;

    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const uv_path = data_dir ++ "uvs.csv";
    const disp_paths = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };

    var out_dir = try demo_common.resetOutputDir(io, out_dir_root);
    defer out_dir.close(io);

    // -------------------------------------------------------------------------
    // 2. Load calibration plate mesh, sample frames, and apply texture
    // -------------------------------------------------------------------------
    var sim_data = try datio.loadSimData(
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
    const frame_indices = try ops.selectEvenlySpacedFrameIndices(
        local_alloc,
        disp_source.getTimeN(),
        frames_max,
    );

    var selected_disp = try ops.selectFieldFrames(
        local_alloc,
        &disp_source,
        frame_indices,
    );
    defer selected_disp.deinit(local_alloc);

    var uvs = try datio.loadUVMap(local_alloc, io, uv_path);
    defer uvs.deinit(local_alloc);

    var texture = try datio.loadImage(
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

    const matched_roi = [3]maths.F{ 0.0125, 0.0175, 0.0005 };

    const target_roi = maths.Vec3F.initSlice(matched_roi[0..]);
    ops.centerCoordsAt(&sim_data.coords, target_roi.vec);
    const roi_pos = ops.boundsCenter(&sim_data.coords);

    // -------------------------------------------------------------------------
    // 3. Create, save, and reload stereo camera pair
    // -------------------------------------------------------------------------
    const coord_sys = riley.CameraCoordSys.opengl;
    const stereo_file_name = if (coord_sys == .opencv)
        "stereo_data_opencv.csv"
    else
        "stereo_data_opengl.csv";

    const pixels_num = [2]u32{ 2464, 2056 };
    const pixels_size = [2]maths.F{ 3.45e-6, 3.45e-6 };
    const focal_length: maths.F = 50.0e-3;
    const stereo_angle_deg: maths.F = 20.0;
    const sub_sample: u32 = 4;
    const matched_cam0_pos = [3]maths.F{ 0.0125, 0.0175, 0.160864856482 };
    const matched_cam1_pos = [3]maths.F{ 0.067348011198, 0.0175, 0.151193672270 };

    const cam0_rot = maths.Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
    );

    const cam1_rot = maths.Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(stereo_angle_deg),
        std.math.degreesToRadians(0.0),
    );

    const cam0_pos = maths.Vec3F.initSlice(matched_cam0_pos[0..]);
    const cam1_pos = maths.Vec3F.initSlice(matched_cam1_pos[0..]);

    const cam0_in = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cam0_pos,
        .rot_world = cam0_rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_length,
        .sub_sample = sub_sample,
        .render_format = .mono,
        .distort = distort,
        .coord_sys = coord_sys,
    };
    var cam1_in = cam0_in;
    cam1_in.rot_world = cam1_rot;
    cam1_in.pos_world = cam1_pos;

    var stereo_pair = riley.StereoPairInput{
        .cameras = .{ cam0_in, cam1_in },
    };

    // Save stereo pair to output directory
    try datio.saveStereoPair(io, out_dir, stereo_file_name, stereo_pair);

    // Load stereo pair back from output directory (standalone test)
    const loaded_stereo = try datio.LoadedStereoPair.init(
        local_alloc,
        io,
        out_dir,
        stereo_file_name,
    );
    defer loaded_stereo.deinit(local_alloc);
    stereo_pair = loaded_stereo.stereo_pair;
    for (&stereo_pair.cameras) |*camera_input| {
        camera_input.background_value = 128.0;
        camera_input.render_format = .mono;
        camera_input.output_files = &.{.{ .format = .bmp, .file_bits = 8, .scaling = .auto }};
    }

    // -------------------------------------------------------------------------
    // 4. Build mesh and raster configuration
    // -------------------------------------------------------------------------
    const speckle_shader: riley.ShaderMonoInput = .{ .tex_u8 = .{
        .uvs = uvs.array,
        .tex = texture,
        .samp_cfg = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },

        .scaling = .none,
    } };

    const mesh_input = riley.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = selected_disp,
        .shaders = .{ .mono_direct = speckle_shader },
    };

    const config = riley.RasterConfig{
        .render_mode = .offline,
        .parallel = .{ .threads = total_threads },
        .save_strategy = .disk,
        .report_perf = .bench,
        .report_console = true,
    };

    // -------------------------------------------------------------------------
    // 5. Render stereocal poses
    // -------------------------------------------------------------------------
    const images = try riley.raster(
        outer_alloc,
        io,
        &stereo_pair.cameras,
        &.{mesh_input},
        config,
        out_dir_root,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }
}
