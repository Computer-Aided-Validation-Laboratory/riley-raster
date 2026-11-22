// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const pdemo = @import("dev_support/proceduraldemo.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const data_dir = "data/rabbits/riley_tri6/";
const demo_spec = pdemo.DemoSpec{
    .command_name = "demo-procedural-rabbit",
    .output_default = "out/demo-procedural-rabbit",
    .pixels_num_default = .{ 800, 500 },
    .length_default = 0.005,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    try pdemo.runStaticTri6Demo(demo_spec, init, .{
        .coords_path = data_dir ++ "coords.csv",
        .connect_path = data_dir ++ "connectivity.csv",
        .uvs_path = data_dir ++ "uvs.csv",
        // The committed atlas reaches V = -0.000792 between nodes. A translation
        // keeps the quadratic patch in the unit domain without changing its metric.
        .v_offset = 0.001,
        // Match the camera view in the texture-mapped rabbit demos.
        .rotation = Rotation.init(0.0, 0.0, 0.0),
        .fov_scale = 1.01,
        .title = "Procedural rabbit demo",
        .image_label = "Rabbit",
    });
}
