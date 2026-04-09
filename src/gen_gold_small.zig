const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.iio.loadImage(allocator, io, "texture/speckle-simple.tiff", .tiff, u8, 1);
    defer texture.deinit(allocator);

    const mesh_types = [_]gengold.MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad4newton,
        .quad8,
        .quad9,
    };

    const interp_types = [_]gengold.texops.InterpType{
        .linear,
        .cubic,
        .cubic_lut,
        .cubic_lut_lerp,
        .quintic,
        .quintic_lut,
        .quintic_lut_lerp,
    };
    const pixel_num = [_]u32{ 160, 100 };
    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
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
        &interp_types,
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
        &interp_types,
        "gold-small",
        "data-small",
        config,
    );

    std.debug.print("Done.\n", .{});
}
