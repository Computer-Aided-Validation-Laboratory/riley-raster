// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
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
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const CameraInput = camera_mod.CameraInput;
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/min/tri6_sphere200/";
    const out_dir_root = "out/demo1a_texture_sphere";

    const total_threads: u16 = 4;

    // -------------------------------------------------------------------------
    // 2. Load mesh data and texture shader
    // -------------------------------------------------------------------------
    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(local_alloc, io, data_dir ++ "uvs.csv");
    const texture = try iio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );

    const mesh_input = MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
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
    // 3. Position and create camera
    // -------------------------------------------------------------------------
    const pixels_num = [_]u32{ 800, 500 };
    const pixels_size = [_]F{
        5.3e-6,
        5.3e-6,
    };
    const focal_leng: F = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: F = 1.0;

    // Aim at the bounding-box centre and use the sphere's extent to choose camera distance.
    const roi_pos = sceneops.boundsCenter(&sim_data.coords);
    const cam_pos = cameraops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixels_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );

    const camera_input = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cam_pos,
        .rot_world = rot,
        .roi_cent_world = roi_pos,
        .focal_length = focal_leng,
        .sub_sample = 4,
    };

    // -------------------------------------------------------------------------
    // 4. Configure raster engine
    // -------------------------------------------------------------------------
    const config = RasterConfig{
        .save_strategy = .disk,
        .parallel = .{ .threads = total_threads },
        .output = .{
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        },
        .report = .{ .mode = .bench },
    };

    // -------------------------------------------------------------------------
    // 5. Render sphere scene
    // -------------------------------------------------------------------------
    std.debug.print("Rendering sphere to {s}/...\n", .{out_dir_root});

    // Disk-only rendering returns null.
    _ = try riley.raster(
        outer_alloc,
        io,
        &.{camera_input},
        &.{mesh_input},
        config,
        out_dir_root,
    );

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
