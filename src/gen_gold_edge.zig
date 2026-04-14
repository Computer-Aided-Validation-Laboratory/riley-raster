const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.iio.loadImage(
        allocator,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
        u8,
        1,
    );
    defer texture.deinit(allocator);

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
            .{ .format = .csv, .bits = null, .scaling = .none },
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
    };

    std.debug.print("Generating Edge Cases to gold-edge/...\n", .{});

    try gengold.runGenerationExt(
        allocator,
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
        allocator,
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
        allocator,
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
