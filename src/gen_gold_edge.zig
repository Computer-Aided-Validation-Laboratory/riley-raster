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
const zraster = @import("zraster/zig/zraster.zig");
const mo = @import("zraster/zig/meshops.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const aa = arena.allocator();

    const texture = try iio.loadImage(
        u8,
        1,
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
    );

    const mesh_types = [_]mo.MeshType{
        .tri6,
        .quad8,
        .quad9,
    };

    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 320, 200 };
    const config = zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
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
