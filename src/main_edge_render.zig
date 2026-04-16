// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    const mesh_types = [_]gengold.MeshType{ .tri6, .quad8, .quad9 };
    const sample_configs = [_]gengold.texops.TextureSampleConfig{
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
    };

    const pixel_num = [_]u32{ 320, 200 };

    const out_dir_root = "out-bench-edge";
    const data_dir = "data-edge";

    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .full_stats,
        .full_stats_opts = .{
            .formats = &[_]gengold.iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
                .{ .format = .csv, .bits = null, .scaling = .none },
            },
            .save_iteration_map = true,
            .save_tile_timing_map = true,
            .save_tile_density_map = true,
            .save_tile_occupancy_map = true,
            .save_depth_map = true,
            .save_earlyout_map = true,
            .save_pixel_occupancy_map = true,
        },
    };

    std.debug.print("Rendering Edge Data to {s}/...\n", .{out_dir_root});

    try gengold.runGenerationExt(
        aa,
        io,
        "vertbulge",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        out_dir_root,
        data_dir,
        config,
    );

    try gengold.runGenerationExt(
        aa,
        io,
        "bulgein_rot",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        out_dir_root,
        data_dir,
        config,
    );

    try gengold.runGenerationExt(
        aa,
        io,
        "bulgeout_rot",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        out_dir_root,
        data_dir,
        config,
    );

    std.debug.print("Done.\n", .{});
}
