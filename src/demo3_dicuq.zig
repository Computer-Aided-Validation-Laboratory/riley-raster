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
const print = std.debug.print;

const riley = @import("riley/zig/riley.zig");
const RasterConfig = riley.RasterConfig;
const meshio = @import("riley/zig/meshio.zig");
const uvio = @import("riley/zig/uvio.zig");
const iio = @import("riley/zig/imageio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const MeshInput = meshpipe.MeshInput;
const gk = @import("riley/zig/geometrykernels.zig");
const MeshType = gk.MeshType;
const camera_mod = @import("riley/zig/camera.zig");
const cameraio = @import("riley/zig/cameraio.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const CameraInput = camera_mod.CameraInput;
const DistortModel = camera_mod.DistortParams;
const BrownCon = camera_mod.BrownCon;
const BrownConExt = camera_mod.BrownConExt;
const MatSlice = @import("riley/zig/matslice.zig").MatSlice;

const buildconfig = @import("riley/zig/buildconfig.zig");
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

    const io = init.io;

    // -------------------------------------------------------------------------
    // 1. Setup paths, config and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/FE/platehole3d_2mr_7f/";
    const texture_path = "texture/speckle_mono.bmp";
    const out_dir_root = "./out/demo3_dicuq";

    const config = RasterConfig{
        .render_mode = .offline,
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .background_value = 128.0,
        .output = .{
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .none },
            },
        },
        .report = .{ .mode = .bench },
    };


    // -------------------------------------------------------------------------
    // 2. Load simulation data, frames, and texture shader
    // -------------------------------------------------------------------------
    std.debug.print("Loading simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";

    const field_files = &[_][]const u8{
        data_dir ++ "field_disp_x.csv",
        data_dir ++ "field_disp_y.csv",
        data_dir ++ "field_disp_z.csv",
    };

    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        coord_path,
        conn_path,
        null,
        field_files,
    );
    const disp_source = sim_data.disp orelse return error.MissingDisplacement;

    const frame_indices = try sceneops.selectFirstLastFrameIndices(
        local_alloc,
        disp_source.getTimeN(),
    );

    const selected_disp = try sceneops.selectFieldFrames(
        local_alloc,
        &disp_source,
        frame_indices,
    );

    std.debug.print("Loading UV map...\n", .{});
    const uv_path = data_dir ++ "uvs.csv";
    const uvs = try uvio.loadUVMap(local_alloc, io, uv_path);

    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        texture_path,
        .bmp,
    );

    std.debug.print("Preparing mesh input...\n", .{});
    const mesh_input = MeshInput{
        .mesh_type = .quad8,
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

    // -------------------------------------------------------------------------
    // 3. Create stereo cameras
    // -------------------------------------------------------------------------
    const pixels_num = [2]u32{ 2464, 2056 };
    const pixels_size = [2]F{ 3.45e-6, 3.45e-6 };
    const focal_length: F = 50.0e-3;
    const fov_scale_factor: F = 0.65;
    const sub_sample: u32 = 4;
    const stereo_angle_deg: F = 20.0;

    std.debug.print("Setting up camera...\n", .{});
    const roi_pos = sceneops.boundsCenter(&sim_data.coords);
    const distort_case: DistortCase = .brown_con;
    const distort = buildDistort(distort_case);

    // Camera 0: face on
    const cam0_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(0.0),
    );

    const cam0_pos = cameraops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixels_size,
        focal_length,
        cam0_rot,
        fov_scale_factor,
    );

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

    // Camera 1: stereo angle
    const cam1_rot = Rotation.init(
        std.math.degreesToRadians(0.0),
        std.math.degreesToRadians(stereo_angle_deg),
        std.math.degreesToRadians(0.0),
    );

    const cam1_pos = cameraops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixels_size,
        focal_length,
        cam1_rot,
        fov_scale_factor,
    );

    var cam1_in = cam0_in;
    cam1_in.rot_world = cam1_rot;
    cam1_in.pos_world = cam1_pos;

    // -------------------------------------------------------------------------
    // 4. Configure raster engine and render
    // -------------------------------------------------------------------------
    std.debug.print("Rendering simulation to {s}/...\n", .{out_dir_root});

    var out_dir = try demo_common.resetOutputDir(io, out_dir_root);
    defer out_dir.close(io);

    const images = try riley.raster(
        outer_alloc,
        io,
        &.{cam0_in, cam1_in},
        &.{mesh_input},
        config,
        out_dir_root,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }

    // -------------------------------------------------------------------------
    // 5. Export stereo calibration and camera position data
    // -------------------------------------------------------------------------
    var cam0_opengl = cam0_in;
    cam0_opengl.coord_sys = .opengl;
    var cam1_opengl = cam1_in;
    cam1_opengl.coord_sys = .opengl;

    try cameraio.saveStereoPair(
        io,
        out_dir,
        "stereo_data_opengl.csv",
        .{ .cameras = .{ cam0_opengl, cam1_opengl } },
    );

    var cam0_opencv = cam0_in;
    cam0_opencv.coord_sys = .opencv;
    var cam1_opencv = cam1_in;
    cam1_opencv.coord_sys = .opencv;

    try cameraio.saveStereoPair(
        io,
        out_dir,
        "stereo_data_opencv.csv",
        .{ .cameras = .{ cam0_opencv, cam1_opencv } },
    );

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
