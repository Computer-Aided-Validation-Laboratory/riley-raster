// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

const pdemo = @import("dev_support/proceduraldemo.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const data_dir = "data/rabbits/riley_tri6/";
const demo_spec = pdemo.DemoSpec{
    .command_name = "demo-procedural-rabbit",
    .output_default = "out/demo-procedural-rabbit",
    .pixels_num_default = .{ 800, 500 },
    .mask_report_label = "mask storage (compile-time)",
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    try pdemo.runStaticTri6Demo(demo_spec, init.gpa, init.minimal, .{
        .coords_path = data_dir ++ "coords.csv",
        .connect_path = data_dir ++ "connectivity.csv",
        .uvs_path = data_dir ++ "uvs.csv",
        .rotation = Rotation.init(0.0, std.math.pi, 0.0),
        .fov_scale = 1.01,
        .title = "Procedural rabbit demo",
        .image_label = "Rabbit",
    });
}
