// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const demo0a_quickstart = @import("demo0a_quickstart.zig");
const demo0b_procedural_quickstart = @import("demo0b_procedural_quickstart.zig");
const demo1a_texture_sphere = @import("demo1a_texture_sphere.zig");
const demo1b_procedural_sphere = @import("demo1b_procedural_sphere.zig");
const demo2a_rabbits_mono = @import("demo2a_rabbits_mono.zig");
const demo2b_rabbits_rgb = @import("demo2b_rabbits_rgb.zig");
const demo2c_rabbits_fields = @import("demo2c_rabbits_fields.zig");
const demo2d_rabbit_procedural = @import("demo2d_rabbit_procedural.zig");
const demo3_dicuq = @import("demo3_dicuq.zig");
const demo4_stereocal = @import("demo4_stereocal.zig");
const demo5_cameramodels = @import("demo5_cameramodels.zig");
const demo6_featurezoo = @import("demo6_featurezoo.zig");

pub fn main(init: std.process.Init) !void {
    try demo0a_quickstart.main(init);
    try demo0b_procedural_quickstart.run(init, &.{});
    try demo1a_texture_sphere.main(init);
    try demo1b_procedural_sphere.run(init, &.{});
    try demo2a_rabbits_mono.main(init);
    try demo2b_rabbits_rgb.main(init);
    try demo2c_rabbits_fields.main(init);
    try demo2d_rabbit_procedural.run(init, &.{});
    try demo3_dicuq.main(init);
    try demo4_stereocal.main(init);
    try demo5_cameramodels.main(init);
    try demo6_featurezoo.main(init);
}
