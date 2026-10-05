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

const data_dir = "data/min/tri6_sphere200/";
const demo_spec = pdemo.DemoSpec{
    .command_name = "demo-procedural-sphere200",
    .output_default = "./out/demo-procedural-sphere200",
    .pixels_num_default = .{ 800, 500 },
    .comparison = .{
        .texture_command = "demo1-sphere",
        .procedural_command = "demo-procedural-sphere200",
    },
    .mask_report_label = "generated mask allocation",
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    try pdemo.runStaticTri6Demo(demo_spec, init.gpa, init.minimal, .{
        .coords_path = data_dir ++ "coords.csv",
        .connect_path = data_dir ++ "connect.csv",
        .uvs_path = data_dir ++ "uvs.csv",
        .rotation = Rotation.init(0.0, 0.0, 0.0),
        .fov_scale = 1.0,
        .title = "Procedural sphere200 comparison demo",
        .image_label = "Comparison",
    });
}
