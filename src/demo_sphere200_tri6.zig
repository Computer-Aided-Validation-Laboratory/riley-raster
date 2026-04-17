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
const mr = @import("zraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const camera_mod = @import("zraster/zig/camera.zig");
const Rotation = camera_mod.Rotation;
const Camera = camera_mod.Camera;
const CameraOps = camera_mod.CameraOps;
const MatSlice = @import("zraster/zig/matslice.zig").MatSlice;

pub fn main() !void {
    const outer_alloc = std.heap.page_allocator;

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    // 1. Setup Rasteriser Configuration
    const config = RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };

    const data_dir = "data-bench/tri6_sphere200/";
    const out_dir_root = "demo-sphere200";
    const pixel_num = [_]u32{ 800, 500 };

    // 2. Load Simulation Data
    std.debug.print("Loading sphere simulation data from {s}...\n", .{data_dir});
    const coord_path = data_dir ++ "coords.csv";
    const conn_path = data_dir ++ "connect.csv";
    // For this demo, we don't need the field data as we are using texture shading
    const sim_data = try meshio.loadSimData(aa, io, coord_path, conn_path, null, null);

    // 3. Load UV map for the texture
    std.debug.print("Loading UV map...\n", .{});
    const uv_path = data_dir ++ "uvs.csv";
    const uvs = try uvio.loadUVMap(aa, io, uv_path);

    // 4. Load Texture for shading
    std.debug.print("Loading speckle texture...\n", .{});
    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle.bmp",
        .bmp,
    );

    // 5. Prepare Mesh Input
    std.debug.print("Preparing mesh input...\n", .{});
    const mesh_input = MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
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

    // 6. Setup Camera
    // Position camera to frame the sphere
    std.debug.print("Setting up camera...\n", .{});
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.0;

    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );

    // 7. Create Output Directory
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try cwd.openDir(io, out_dir_root, .{});
    defer out_dir.close(io);

    // 8. Run the Rasteriser
    std.debug.print("Rendering sphere to {s}/...\n", .{out_dir_root});
    const meshes = [_]MeshInput{mesh_input};
    const images = try zraster.rasterAllFrames(
        aa,
        io,
        &camera,
        &meshes,
        config,
        out_dir,
    );

    if (images) |img| {
        aa.free(img.slice);
        img.deinit(aa);
    }

    std.debug.print("Demo complete. Images saved to {s}/\n", .{out_dir_root});
}
