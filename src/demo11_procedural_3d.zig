// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Render slices of 3D Perlin noise on a flat plate and curved sphere, without UVs.
const std = @import("std");
const riley = @import("riley/zig/api.zig");
const maths = riley.maths;

const out_dir = "out/demo11_procedural_3d";
const image_output: riley.dataio.ImageSaveOpts = .{
    .format = .bmp,
    .file_bits = 8,
    .scaling = .{ .fixed = .{ 0, 1 } },
};

pub fn main(init: std.process.Init) !void {
    try renderPlate(init.gpa, init.io);
    try renderSphere(init.gpa, init.io);
    std.debug.print("Saved {s}/plate.bmp and {s}/sphere.bmp\n", .{ out_dir, out_dir });
}

fn renderPlate(alloc: std.mem.Allocator, io: std.Io) !void {
    const side: maths.F = 40;
    const h = side / 2;
    var coords = [_]maths.F{
        -h, -h, 0,
        h,  -h, 0,
        h,  h,  0,
        -h, h,  0,
    };
    var connect = [_]usize{ 0, 1, 2, 3 };
    const plate: riley.MeshInput = .{
        .mesh_type = .quad4,
        .coords = riley.Coords.init(&coords, 4),
        .connect = riley.Connect.init(&connect, 1, 4),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .speckle3d = .{
            .params = .{ .perlin = .{ .cell_size = 0.25 } },
            .bits = null,
            .scaling = .none,
        } } },
    };
    const focal_length: maths.F = 50e-3;
    const pixels = 1024;
    const camera: riley.CameraInput = .{
        .pixels_num = .{ pixels, pixels },
        .pixels_size = .{ focal_length / pixels, focal_length / pixels },
        .pos_world = .{ .vec = .{ 0, 0, side } },
        .rot_world = maths.Rotation.init(0, 0, 0),
        .roi_cent_world = .initZeros(),
        .focal_length = focal_length,
        .sub_sample = 1,
        .render_format = .mono,
        .output_files = &.{image_output},
    };
    _ = try riley.raster(alloc, io, &.{camera}, &.{plate}, .{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output_name_format = "plate",
    }, out_dir);
}

fn renderSphere(alloc: std.mem.Allocator, io: std.Io) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const data_dir = "data/min/tri6_sphere200/";
    const sim_data = try riley.dataio.loadSimData(
        arena.allocator(),
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    var stages: [1]riley.ShaderPipeStageInput = undefined;
    const sphere: riley.MeshInput = .{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shaders = .{ .mono_pipe = riley.ops.identityMulti(1, .{ .speckle3d = .{
            .params = .{ .perlin = .{ .cell_size = 0.02 } },
            .bits = null,
            .scaling = .none,
        } }, &stages) },
    };
    const pixels_num: [2]u32 = .{ 720, 450 };
    const pixels_size: [2]maths.F = .{ 5.3e-6, 5.3e-6 };
    const focal_length: maths.F = 50e-3;
    const rot = maths.Rotation.init(0, 0, 0);
    const camera: riley.CameraInput = .{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = riley.ops.posFillFrameFromRot(
            &sim_data.coords,
            pixels_num,
            pixels_size,
            focal_length,
            rot,
            1.28,
        ),
        .rot_world = rot,
        .roi_cent_world = riley.ops.boundsCenter(&sim_data.coords),
        .focal_length = focal_length,
        .sub_sample = 2,
        .render_format = .mono,
        .background_value = 0.9,
        .output_files = &.{image_output},
    };
    _ = try riley.raster(alloc, io, &.{camera}, &.{sphere}, .{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output_name_format = "sphere",
    }, out_dir);
}
