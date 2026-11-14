// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const pdemo = @import("dev_support/proceduraldemo.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");
const imageio = @import("riley/zig/imageio.zig");
const matslice = @import("riley/zig/matslice.zig");
const speckleops = @import("riley/zig/speckleops.zig");

const F = buildconfig.F;
const demo_spec = pdemo.DemoSpec{
    .command_name = "demo-procedural-pattern",
    .output_default = "./out/procedural_pattern",
    .pixels_num_default = .{ 1024, 1024 },
    .params_default = .{ .cells_per_uv = .{ 64, 64 } },
    .mask_report_label = "generated mask allocation",
};
// Map final [0, 1] intensities directly to 0..255, without contrast stretching.
const save_opts = imageio.ImageSaveOpts{
    .format = .bmp,
    .bits = 8,
    .scaling = .{ .fixed = .{ 0, 1 } },
};

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = (try pdemo.parseDemoArgs(init.minimal.args.vector, demo_spec)) orelse return;
    _ = try imageio.bmpDataSize(args.pixels_num[0], args.pixels_num[1], save_opts.bits.?);
    std.debug.print("Direct procedural image\n", .{});
    try pdemo.printProceduralConfig(args.params, args.pixels_num, demo_spec);

    var resources = try speckleops.Resources.init(allocator, args.params);
    defer resources.deinit(allocator);

    const image = try matslice.MatSlice(F).initAlloc(
        allocator,
        args.pixels_num[1],
        args.pixels_num[0],
    );
    defer allocator.free(image.slice);

    speckleops.fillImage(image, args.params, &resources);

    const io = init.io;
    var out_dir = try std.Io.Dir.cwd().createDirPathOpen(io, args.out_dir, .{});
    defer out_dir.close(io);
    try imageio.saveMatAsImage(
        io,
        out_dir,
        @tagName(args.params.pattern),
        &image,
        save_opts,
    );
    std.debug.print("Saved {s}/{s}.bmp\n", .{ args.out_dir, @tagName(args.params.pattern) });
}
