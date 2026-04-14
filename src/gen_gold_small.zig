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
        .tri3,
        .tri6,
        .quad4ibi,
        .quad4newton,
        .quad8,
        .quad9,
    };

    const sample_configs = [_]gengold.texops.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const pixel_num = [_]u32{ 160, 100 };
    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .fimg, .bits = null, .scaling = .none },
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .off,
    };

    std.debug.print("Generating ALL Small Gold Data...\n", .{});
    std.debug.print("Single Element Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator,
        io,
        "single",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &sample_configs,
        "gold-small",
        "data-small",
        config,
    );

    std.debug.print("Full Screen Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator,
        io,
        "full",
        &mesh_types,
        1.0,
        texture,
        pixel_num,
        &sample_configs,
        "gold-small",
        "data-small",
        config,
    );

    std.debug.print("Done.\n", .{});
}
