// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Render a physical speckle pattern on a flat, front-facing plane.
const std = @import("std");

const cli = @import("dev_support/proceduralcli.zig");
const riley = @import("riley/zig/api.zig");
const imageio = @import("riley/zig/imageio.zig");
const maths = riley.maths;

const usage =
    \\Usage: zig run ./src/demo00b_procedural_quickstart.zig -- [--pattern disk|gaussian|perlin]
    \\       [--output DIR] [--width PIXELS] [--height PIXELS] [-h|--help]
    \\Defaults: disk, 1024 x 1024 pixels, out/demo00b_procedural_quickstart/<pattern>.bmp
    \\
;

pub fn main(init: std.process.Init) !void {
    try run(init, try init.minimal.args.toSlice(init.arena.allocator()));
}

pub fn run(init: std.process.Init, args: []const []const u8) !void {
    const io = init.io;
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();
    var pixels_num: [2]u32 = .{ 1024, 1024 };
    const options = (try cli.parse(
        io,
        args,
        usage,
        "out/demo00b_procedural_quickstart",
        &pixels_num,
    )) orelse return;
    const pattern = options.pattern;
    const out_dir = options.out_dir;

    const file_bits = 8;
    _ = imageio.bmpDataSize(pixels_num[0], pixels_num[1], file_bits) catch
        cli.reject(io, usage, "--width/--height", "dimensions exceed BMP size limits");

    // 1. Set the pattern in physical plane units, independently of image resolution.
    const seed: u32 = 0xa511e9b3; // Riley's default seed; change it for another realization.
    // Gaussian coverage counts nominal support, not opacity; its soft profile looks lighter.
    const spot_radius = 0.25;
    const nominal_coverage = 0.5;
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = .{ .seed = seed, .radius = spot_radius, .coverage = nominal_coverage } },
        .gaussian => .{ .gaussian = .{ .seed = seed, .radius = spot_radius, .coverage = nominal_coverage } },
        .perlin => .{ .perlin = .{ .seed = seed, .cell_size = 0.25 } },
    };

    // 2. Map the full UV square onto one 40 x 40 quad. V grows down the image.
    const side: maths.F = 40;
    const h = side / 2;
    var coords = [12]maths.F{
        -h, -h, 0,
        h,  -h, 0,
        h,  h,  0,
        -h, h,  0,
    };
    var connect = [_]usize{ 0, 1, 2, 3 };
    var uv = [8]maths.F{ 0, 1, 1, 1, 1, 0, 0, 0 };
    const plane = riley.MeshInput{
        .mesh_type = .quad4,
        .coords = riley.Coords.init(&coords, 4),
        .connect = riley.Connect.init(&connect, 1, 4),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .speckle = .{
            .uvs = try maths.NDArray(maths.F).init(local_alloc, &uv, &.{ 4, 2 }),
            .params = params,
            .scaling = .none,
        } } },
    };

    // 3. Look down -Z. The projected square fills the sensor at any resolution.
    //    Unequal width and height give non-square physical pixels, so circular
    //    speckles look elliptical when the BMP is displayed with square pixels.
    const focal_length: maths.F = 50e-3;
    // Map raw [0, 1] shader values to 8-bit gray without a contrast stretch.
    const camera = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = .{
            focal_length / @as(maths.F, @floatFromInt(pixels_num[0])),
            focal_length / @as(maths.F, @floatFromInt(pixels_num[1])),
        },
        .pos_world = .{ .vec = .{ 0, 0, side } },
        .rot_world = maths.Rotation.init(0, 0, 0),
        .roi_cent_world = .initZeros(),
        .focal_length = focal_length,
        .sub_sample = 1,
        .render_format = .mono,
        .output_files = &.{.{ .format = .bmp, .file_bits = file_bits, .scaling = .{ .fixed = .{ 0, 1 } } }},
    };

    // 4. Render to disk only; there is no image buffer to free.
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .output_name_format = @tagName(pattern),
    };
    _ = try riley.raster(init.gpa, io, &.{camera}, &.{plane}, config, out_dir);
    std.debug.print("Saved {s}/{s}.bmp\n", .{ out_dir, @tagName(pattern) });
}
