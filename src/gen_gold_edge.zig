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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.iio.loadImage(
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
        u8,
        1,
    );

    const mesh_types = [_]gengold.MeshType{
        .tri6,
        .quad8,
        .quad9,
    };

    const sample_configs = [_]gengold.texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 320, 200 };
    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .fimg, .bits = null, .scaling = .none },
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .off,
    };

    std.debug.print("Generating Edge Cases to gold-edge/...\n", .{});

    try gengold.runGenerationExt(
        aa,
        io,
        "vertbulge",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        "gold-edge",
        "data-edge",
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
        "gold-edge",
        "data-edge",
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
        "gold-edge",
        "data-edge",
        config,
    );

    std.debug.print("Done.\n", .{});
}
