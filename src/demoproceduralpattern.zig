// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
//! Render a physical speckle pattern on a flat, front-facing plane.
const std = @import("std");

const cli = @import("dev_support/proceduralcli.zig");
const F = @import("riley/zig/buildconfig.zig").F;
const CameraInput = @import("riley/zig/camera.zig").CameraInput;
const imageio = @import("riley/zig/imageio.zig");
const meshio = @import("riley/zig/meshio.zig");
const MeshInput = @import("riley/zig/meshpipeline.zig").MeshInput;
const NDArray = @import("riley/zig/ndarray.zig").NDArray;
const riley = @import("riley/zig/riley.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;

const usage =
    \\Usage: zig build demo-procedural-pattern -- [--pattern disk|gaussian|perlin]
    \\       [--output DIR] [--width PIXELS] [--height PIXELS] [-h|--help]
    \\Defaults: disk, 1024 x 1024 pixels, out/procedural_pattern/<pattern>.bmp
    \\
;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    var pixels_num: [2]u32 = .{ 1024, 1024 };
    const options = (try cli.parse(
        std.meta.Tag(riley.SpeckleParams),
        io,
        args,
        usage,
        "out/procedural_pattern",
        &pixels_num,
    )) orelse return;
    const pattern = options.pattern;
    const out_dir = options.out_dir;

    // Check the BMP header and padded pixel-data size limits before allocating render buffers.
    _ = imageio.bmpDataSize(pixels_num[0], pixels_num[1], 8) catch
        cli.reject(io, usage, "--width/--height", "dimensions exceed BMP size limits");

    // 1. Set the pattern in physical plane units, independently of image resolution.
    const seed: u32 = 0xa511e9b3; // Riley's default seed; change it for another realization.
    // Gaussian coverage counts nominal support, not opacity; its soft profile looks lighter.
    const spots: riley.Speckle2DParams = .{ .seed = seed, .radius = 0.25, .coverage = 0.5 };
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = spots },
        .gaussian => .{ .gaussian = spots },
        .perlin => .{ .perlin = .{ .seed = seed, .cell_size = 0.25 } },
    };

    // 2. Map the full UV square onto one 40 x 40 quad. V grows down the image.
    const side: F = 40;
    const h = side / 2;
    var coords = [12]F{
        -h, -h, 0,
        h,  -h, 0,
        h,  h,  0,
        -h, h,  0,
    };
    var connect = [_]usize{ 0, 1, 2, 3 };
    var uv = [8]F{ 0, 1, 1, 1, 1, 0, 0, 0 };
    const plane = MeshInput{
        .mesh_type = .quad4,
        .coords = meshio.Coords.init(&coords, 4),
        .connect = meshio.Connect.init(&connect, 1, 4),
        .disp = null,
        .shader = .{ .speckle = .{
            .uvs = try NDArray(F).init(alloc, &uv, &.{ 4, 2 }),
            .params = params,
            .scaling = .none,
        } },
    };

    // 3. Look down -Z. The projected square fills the sensor at any resolution.
    //    Unequal width and height give non-square physical pixels, so circular
    //    speckles look elliptical when the BMP is displayed with square pixels.
    const focal_length: F = 50e-3;
    const camera = CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = .{
            focal_length / @as(F, @floatFromInt(pixels_num[0])),
            focal_length / @as(F, @floatFromInt(pixels_num[1])),
        },
        .pos_world = .{ .vec = .{ 0, 0, side } },
        .rot_world = Rotation.init(0, 0, 0),
        .roi_cent_world = .initZeros(),
        .focal_length = focal_length,
        .sub_sample = 1,
    };

    // 4. Map raw [0, 1] shader values to 8-bit gray without a contrast stretch,
    //    so intensities can be compared across patterns and resolutions.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output_name_format = @tagName(pattern),
        .output = .{ .image_save_opts = &.{
            .{ .format = .bmp, .bits = 8, .scaling = .{ .fixed = .{ 0, 1 } } },
        } },
        .report = .{ .mode = .off },
    };
    _ = try riley.raster(init.gpa, io, &.{camera}, &.{plane}, config, out_dir);
    std.debug.print("Saved {s}/{s}.bmp\n", .{ out_dir, @tagName(pattern) });
}
