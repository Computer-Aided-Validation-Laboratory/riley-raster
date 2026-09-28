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
const gk = @import("riley/zig/geometrykernels.zig");
const MeshType = gk.MeshType;
const camera_mod = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const CameraInput = camera_mod.CameraInput;
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const MatSlice = @import("riley/zig/matslice.zig").MatSlice;
const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    // -------------------------------------------------------------------------
    // 1. Setup paths and parameters
    // -------------------------------------------------------------------------
    const data_dir = "data/min/tri6_sphere200/";
    const out_dir_root = "./out/demo1_sphere";

    const total_threads: u16 = 4;
    var groups = try riley.ManagedRenderGroups.init(outer_alloc, init.minimal, .{
        .thread_budget = total_threads,
        .max_groups = 1,
    });
    defer groups.deinit(outer_alloc);
    const io = groups.specs[0].io;

    // -------------------------------------------------------------------------
    // 2. Load mesh data and texture shader
    // -------------------------------------------------------------------------
    std.debug.print("Loading sphere simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        coord_path,
        conn_path,
        null,
        null,
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
        "texture/speckle_mono.bmp",
        .bmp,
    );

    std.debug.print("Preparing mesh input...\n", .{});
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
                .mode = .lut_lerp,
            },
            .bits = 8,
            .scaling = .none,
        } },
    };

    // -------------------------------------------------------------------------
    // 3. Position and create camera
    // -------------------------------------------------------------------------
    std.debug.print("Setting up camera...\n", .{});

    const pixels_num = [_]u32{ 800, 500 };
    const pixels_size = [_]F{
        5.3e-6,
        5.3e-6,
    };
    const focal_leng: F = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: F = 1.0;

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
        .sub_sample = 2,
    };

    // -------------------------------------------------------------------------
    // 4. Configure raster engine
    // -------------------------------------------------------------------------
    const config = RasterConfig{
        .save_strategy = .disk,
        .total_threads = total_threads,
        .max_raster_workers_per_job = total_threads,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };

    // -------------------------------------------------------------------------
    // 5. Render sphere scene
    // -------------------------------------------------------------------------
    std.debug.print("Rendering sphere to {s}/...\n", .{out_dir_root});

    const images = try riley.raster(
        outer_alloc,
        groups.specs,
        &.{camera_input},
        &.{mesh_input},
        config,
        out_dir_root,
    );

    if (images) |img| {
        outer_alloc.free(img.slice);
        img.deinit(outer_alloc);
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
