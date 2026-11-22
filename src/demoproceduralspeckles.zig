// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const orch = @import("dev_support/orchestration.zig");
const pdemo = @import("dev_support/proceduraldemo.zig");
const camera = @import("riley/zig/camera.zig");
const iio = @import("riley/zig/imageio.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipeline = @import("riley/zig/meshpipeline.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const riley = @import("riley/zig/riley.zig");
const uvio = @import("riley/zig/uvio.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");

const F = buildconfig.F;
const data_dir = "data/min/tri6_sphere200/";
const demo_spec = pdemo.DemoSpec{
    .command_name = "demo-procedural-speckles",
    .output_default = "./out/demo-procedural-speckles",
    .pixels_num_default = .{ 720, 450 },
    .length_default = 0.02,
    .dimensions = .hidden,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const raw_args = try init.minimal.args.toSlice(allocator);
    const args = (try pdemo.parseDemoArgs(raw_args, demo_spec)) orelse return;

    const workers: u16 = 4;
    const config = rastcfg.RasterConfig{
        .parallel = .{ .threads = workers },
        .save_strategy = .disk,
        .output = .{
            .image_save_mode = .grey,
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .none },
            },
        },
        .background_value = 255.0,
        .report = .{ .mode = .off },
    };
    var threaded_io = riley.getThreadedIo(
        init.gpa,
        init.minimal,
        workers,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.debug.print("Procedural speckle prototype\n", .{});
    pdemo.printProceduralConfig(args.params, args.pixels_num, demo_spec);
    std.debug.print("Loading UV-mapped sphere and preparing three deformation frames...\n", .{});

    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(allocator, io, data_dir ++ "uvs.csv");
    const disp = try makeDemoDisp(allocator, &sim_data.coords);
    // One immutable pattern is attached to this mesh for all three deformation frames.
    const mesh_input = meshpipeline.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = disp,
        .shader = .{ .speckle = .{
            .uvs = uvs.array,
            .params = args.params,
            .scaling = .auto,
        } },
    };

    const camera_prep = try orch.initCameraForCoords(
        allocator,
        &sim_data.coords,
        args.pixels_num,
        1.28,
    );
    const camera_input = camera.CameraInput{
        .pixels_num = camera_prep.pixels_num,
        .pixels_size = camera_prep.pixels_size,
        .pos_world = camera_prep.pos_world,
        .rot_world = camera_prep.rot_world,
        .roi_cent_world = camera_prep.roi_cent_world,
        .focal_length = camera_prep.focal_length,
        .sub_sample = 2,
        .distort = camera_prep.distort.paramsFromModel(),
    };
    const render_groups = [_]riley.RenderGroup{
        .{ .io = io, .workers = workers },
    };

    std.debug.print("Rendering reference, stretch, and twist frames...\n", .{});
    _ = try riley.rasterAdvanced(
        init.gpa,
        io,
        &[_]camera.CameraInput{camera_input},
        &[_]meshpipeline.MeshInput{mesh_input},
        config,
        args.out_dir,
        .{ .render_groups = .{ .supplied = &render_groups } },
    );

    std.debug.print("Demo complete. Images saved under {s}/\n", .{args.out_dir});
}

// --------------------------------------------------------------------------------------
// Deformation Preparation
// --------------------------------------------------------------------------------------

fn makeDemoDisp(
    allocator: std.mem.Allocator,
    coords: *const meshio.Coords,
) !meshio.Field {
    const node_num = coords.mat.rows_num;
    var disp = try meshio.Field.initAlloc(allocator, 3, node_num, 3);

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
