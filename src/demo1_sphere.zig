// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const riley = @import("riley");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

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
    const out_dir_root = "./out/demo1_sphere";

    // -------------------------------------------------------------------------
    // 2. Load mesh data and texture shader
    // -------------------------------------------------------------------------
    std.debug.print("Loading sphere simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    const sim_data = try datio.loadSimData(
        local_alloc,
        io,
        coord_path,
        conn_path,
        null,
        null,
    );

    std.debug.print("Loading UV map...\n", .{});
    const uv_path = data_dir ++ "uvs.csv";
    const uvs = try datio.loadUVMap(local_alloc, io, uv_path);

    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try datio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );

    const speckle_shader: riley.ShaderMonoInput = .{ .tex_u8 = .{
        .uvs = uvs.array,
        .tex = texture,
        .samp_cfg = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        .scaling = .none,
    } };

    std.debug.print("Preparing mesh input...\n", .{});
    const mesh_input = riley.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shaders = .{ .mono_direct = speckle_shader },
    };

    // -------------------------------------------------------------------------
    // 3. Position and create camera
    // -------------------------------------------------------------------------
    std.debug.print("Setting up camera...\n", .{});

    const pixels_num = [_]u32{ 800, 500 };
    const pixels_size = [_]maths.F{
        5.3e-6,
        5.3e-6,
    };
    const focal_leng: maths.F = 50.0e-3;
    const rot = maths.Rotation.init(0, 0, 0);
    const fov_scale_factor: maths.F = 1.0;

    const roi_pos = ops.boundsCenter(&sim_data.coords);
    const cam_pos = ops.posFillFrameFromRot(
        &sim_data.coords,
        pixels_num,
        pixels_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );

    const camera_input = riley.CameraInput{
        .output_files = &.{.{ .format = .bmp, .file_bits = 8, .scaling = .auto }},
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
    const config = riley.RasterConfig{
        .save_strategy = .disk,
        .parallel = .{ .threads = 4 },
        .report_perf = .bench,
        .report_console = true,
    };

    // -------------------------------------------------------------------------
    // 5. Render sphere scene
    // -------------------------------------------------------------------------
    std.debug.print("Rendering sphere to {s}/...\n", .{out_dir_root});

    const images = try riley.raster(
        outer_alloc,
        io,
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
