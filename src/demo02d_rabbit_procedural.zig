// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Use procedural speckles as a shader-pipe source on the TRI6 rabbit mesh.
const std = @import("std");

const cli = @import("dev_support/proceduralcli.zig");
const riley = @import("riley/zig/api.zig");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

const usage =
    \\Usage: zig run ./src/demo02d_rabbit_procedural.zig -- [--pattern disk|gaussian|perlin]
    \\       [--output DIR] [-h|--help]
    \\Defaults: disk, out/demo02d_rabbit_procedural/cam0_frame0_field0.bmp
    \\
;

pub fn main(init: std.process.Init) !void {
    try run(init, try init.minimal.args.toSlice(init.arena.allocator()));
}

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();
    const options = (try cli.parse(
        io,
        args,
        usage,
        "out/demo02d_rabbit_procedural",
        null,
    )) orelse return;
    const pattern = options.pattern;
    const out_dir = options.out_dir;

    // 1. Load the static quadratic triangle mesh and its nodal UV atlas.
    const data_dir = "data/rabbits/riley_tri6/";
    const sim = try datio.loadSimData(
        local_alloc,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connectivity.csv",
        null,
        null,
    );
    const uvs = try datio.loadUVMap(local_alloc, io, data_dir ++ "uvs.csv");
    // The quadratic atlas dips just below V = 0 between nodes. Translate it
    // into the unit domain without changing its physical calibration.
    for (0..uvs.array.dims[0]) |nn| uvs.getUV(nn)[1] += 0.001;

    // 2. Use speckle as a mono pipe source. Radius and cell size are in reference-mesh units.
    const seed: u32 = 0xa511e9b3; // Riley's default seed; change it for another realization.
    const spot_radius = 0.005;
    const nominal_coverage = 0.5;
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = .{ .seed = seed, .radius = spot_radius, .coverage = nominal_coverage } },
        .gaussian => .{ .gaussian = .{ .seed = seed, .radius = spot_radius, .coverage = nominal_coverage } },
        .perlin => .{ .perlin = .{ .seed = seed, .cell_size = 0.005 } },
    };
    const speckle: riley.SpeckleInput = .{
        .uvs = uvs.array,
        .params = params,
        .scaling = .auto,
    };
    const channel: riley.Register = .{ .kind = .channel, .index = 0 };
    const stages = [_]riley.ShaderPipeStageInput{.{ .shader = .{
        .shader = .{ .speckle = speckle },
        .register_dest = channel,
    } }};
    const rabbit = riley.MeshInput{
        .mesh_type = .tri6,
        .coords = sim.coords,
        .connect = sim.connect,
        .disp = null,
        .shaders = .{
            .mono_pipe = .{
                .stages = &stages,
                // Pass the channel through unchanged; other resolvers can combine it with lighting.
                .resolver = .{ .identity = &.{channel} },
            },
        },
    };

    // 3. Frame the rabbit with a small margin.
    const pixels_num: [2]u32 = .{ 800, 500 };
    const pixels_size: [2]maths.F = .{ 5.3e-6, 5.3e-6 };
    const focal_length: maths.F = 50e-3;
    const rotation = maths.Rotation.init(0, 0, 0);
    const camera = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = ops.posFillFrameFromRot(
            &sim.coords,
            pixels_num,
            pixels_size,
            focal_length,
            rotation,
            1.01,
        ),
        .rot_world = rotation,
        .roi_cent_world = ops.boundsCenter(&sim.coords),
        .focal_length = focal_length,
        .sub_sample = 2,
        .render_format = .mono,
        // Save-time .auto stretches the rendered gray levels, including the black background.
        .output_files = &.{.{ .format = .bmp, .file_bits = 8, .scaling = .auto }},
    };

    // 4. Render the resolved mono channel to disk.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
    };
    _ = try riley.raster(init.gpa, io, &.{camera}, &.{rabbit}, config, out_dir);
    std.debug.print("Saved {s}/cam0_frame0_field0.bmp\n", .{out_dir});
}
