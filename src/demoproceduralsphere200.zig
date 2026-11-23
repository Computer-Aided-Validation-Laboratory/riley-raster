// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Render the TRI6 sphere with the procedural counterpart to demo1-sphere's texture.
const std = @import("std");

const cli = @import("dev_support/proceduralcli.zig");
const F = @import("riley/zig/buildconfig.zig").F;
const CameraInput = @import("riley/zig/camera.zig").CameraInput;
const cameraops = @import("riley/zig/cameraops.zig");
const meshio = @import("riley/zig/meshio.zig");
const MeshInput = @import("riley/zig/meshpipeline.zig").MeshInput;
const riley = @import("riley/zig/riley.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const sceneops = @import("riley/zig/sceneops.zig");
const uvio = @import("riley/zig/uvio.zig");

const usage =
    \\Usage: zig build demo-procedural-sphere200 -- [--pattern disk|gaussian|perlin]
    \\       [--output DIR] [-h|--help]
    \\Defaults: disk, out/demo-procedural-sphere200/cam0_frame0_field0.bmp
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    const options = (try cli.parse(
        std.meta.Tag(riley.SpeckleParams),
        io,
        args,
        usage,
        "out/demo-procedural-sphere200",
        null,
    )) orelse return;
    const pattern = options.pattern;
    const out_dir = options.out_dir;

    // 1. Load the static quadratic triangle sphere and its nodal UV atlas.
    const data_dir = "data/min/tri6_sphere200/";
    const sim = try meshio.loadSimData(
        alloc,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(alloc, io, data_dir ++ "uvs.csv");

    // 2. Attach a speckle shader. Radius and cell size are in reference-mesh units.
    const seed: u32 = 0xa511e9b3; // Riley's default seed; change it for another realization.
    const spots: riley.Speckle2DParams = .{ .seed = seed, .radius = 0.02, .coverage = 0.5 };
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = spots },
        .gaussian => .{ .gaussian = spots },
        .perlin => .{ .perlin = .{ .seed = seed, .cell_size = 0.02 } },
    };
    const sphere = MeshInput{
        .mesh_type = .tri6,
        .coords = sim.coords,
        .connect = sim.connect,
        .disp = null,
        .shader = .{ .speckle = .{ .uvs = uvs.array, .params = params, .scaling = .auto } },
    };

    // 3. Match the framing of the texture-mapped sphere for comparison.
    const pixels_num: [2]u32 = .{ 800, 500 };
    const pixels_size: [2]F = .{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50e-3;
    const rotation = Rotation.init(0, 0, 0);
    const camera = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cameraops.posFillFrameFromRot(
            &sim.coords,
            pixels_num,
            pixels_size,
            focal_length,
            rotation,
            1.0,
        ),
        .rot_world = rotation,
        .roi_cent_world = sceneops.boundsCenter(&sim.coords),
        .focal_length = focal_length,
        .sub_sample = 2,
    };

    // 4. Stretch the saved image to the full 8-bit range for display. Unlike
    //    shader scaling of nominal values, save-time .auto includes the black background.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output = .{ .image_save_opts = &.{.{ .format = .bmp, .bits = 8, .scaling = .auto }} },
        .report = .{ .mode = .off },
    };
    _ = try riley.raster(init.gpa, io, &.{camera}, &.{sphere}, config, out_dir);
    std.debug.print("Saved {s}/cam0_frame0_field0.bmp\n", .{out_dir});
}
