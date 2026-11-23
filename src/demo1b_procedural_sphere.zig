// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Track one physical speckle pattern through reference, stretch, and twist frames.
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
    \\Usage: zig build demo1b-procedural-sphere -- [--pattern disk|gaussian|perlin]
    \\       [--output DIR] [-h|--help]
    \\Defaults: disk, out/demo1b_procedural_sphere/ (reference, stretch, twist)
    \\
;

pub fn main(init: std.process.Init) !void {
    try run(init, try init.minimal.args.toSlice(init.arena.allocator()));
}

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const io = init.io;
    const alloc = init.arena.allocator();
    const options = (try cli.parse(
        std.meta.Tag(riley.SpeckleParams),
        io,
        args,
        usage,
        "out/demo1b_procedural_sphere",
        null,
    )) orelse return;
    const pattern = options.pattern;
    const out_dir = options.out_dir;

    // 1. Load the quadratic triangle mesh and UV atlas, then generate displacement frames.
    const data_dir = "data/min/tri6_sphere200/";
    const sim_data = try meshio.loadSimData(
        alloc,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null, // No scalar fields.
        null, // Generate displacements below instead of loading CSVs.
    );
    const uvs = try uvio.loadUVMap(alloc, io, data_dir ++ "uvs.csv");
    const disp = try makeDemoDisp(alloc, &sim_data.coords);

    // 2. Attach one immutable pattern to the mesh across all three frames.
    //    Radius and cell size are in reference-mesh units.
    const seed: u32 = 0xa511e9b3; // Riley's default seed; change it for another realization.
    const spots: riley.Dot2DParams = .{ .seed = seed, .radius = 0.02, .coverage = 0.5 };
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = spots },
        .gaussian => .{ .gaussian = spots },
        .perlin => .{ .perlin = .{ .seed = seed, .cell_size = 0.02 } },
    };
    const mesh_input = MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = disp,
        .shader = .{ .speckle = .{
            .uvs = uvs.array,
            .params = params,
            .scaling = .auto,
        } },
    };

    // 3. Frame the mesh with extra room for the deformed frames.
    const pixels_num: [2]u32 = .{ 720, 450 };
    const pixels_size: [2]F = .{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale: F = 1.28;
    const camera_input = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = cameraops.posFillFrameFromRot(
            &sim_data.coords,
            pixels_num,
            pixels_size,
            focal_length,
            rot,
            fov_scale,
        ),
        .rot_world = rot,
        .roi_cent_world = sceneops.boundsCenter(&sim_data.coords),
        .focal_length = focal_length,
        .sub_sample = 2,
    };

    // 4. Keep the shader's nominal 8-bit range and the white background. Skip
    //    save-time rescaling so the same intensity has the same gray level in every frame.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output = .{
            .image_save_mode = .grey,
            .image_save_opts = &.{.{ .format = .bmp, .bits = 8, .scaling = .none }},
        },
        .background_value = 255.0,
        .report = .{ .mode = .off },
    };
    std.debug.print("Rendering {s}: reference, stretch, twist...\n", .{@tagName(pattern)});
    _ = try riley.raster(init.gpa, io, &.{camera_input}, &.{mesh_input}, config, out_dir);
    std.debug.print("Images saved under {s}/\n", .{out_dir});
}

fn makeDemoDisp(
    outer_alloc: std.mem.Allocator,
    coords: *const meshio.Coords,
) !meshio.Field {
    const node_num = coords.mat.rows_num;
    // Field layout is [frame, node, component]. Frame 0 stays zero (reference).
    var disp = try meshio.Field.initAlloc(outer_alloc, 3, node_num, 3);

    var center = [3]F{ 0.0, 0.0, 0.0 };
    var z_min = coords.z(0);
    var z_max = z_min;
    for (0..node_num) |node_idx| {
        const z = coords.z(node_idx);
        center[0] += coords.x(node_idx);
        center[1] += coords.y(node_idx);
        center[2] += z;
        z_min = @min(z_min, z);
        z_max = @max(z_max, z);
    }
    const node_num_f: F = @floatFromInt(node_num);
    for (0..3) |axis| center[axis] /= node_num_f;

    const z_extent = @max(@abs(z_min - center[2]), @abs(z_max - center[2]), 1.0e-12);

    for (0..node_num) |node_idx| {
        const rel_x = coords.x(node_idx) - center[0];
        const rel_y = coords.y(node_idx) - center[1];
        const rel_z = coords.z(node_idx) - center[2];

        disp.array.set(&.{ 1, node_idx, 0 }, 0.18 * rel_x);
        disp.array.set(&.{ 1, node_idx, 1 }, -0.08 * rel_y);
        disp.array.set(&.{ 1, node_idx, 2 }, 0.04 * rel_z);

        const twist = 0.16 * rel_z / z_extent;
        disp.array.set(&.{ 2, node_idx, 0 }, -twist * rel_y);
        disp.array.set(&.{ 2, node_idx, 1 }, twist * rel_x);
        disp.array.set(&.{ 2, node_idx, 2 }, 0.12 * rel_z);
    }
    return disp;
}
