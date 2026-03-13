const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture =  try gengold.iio.loadImage(
        allocator, io, "texture/speckle-simple.tiff", .tiff, u8, 1
    );
    defer texture.deinit(allocator);

    const mesh_types = [_]gengold.MeshType{ 
        .tri3, .tri3opt, .tri6, .quad4ibi, .quad4newton, .quad8, .quad9 
    };
    const interp_types = std.enums.values(gengold.texops.InterpType);

    const pixel_num = [_]u32{ 320, 200 };

    const out_dir_root = "out-small";
    const data_dir = "data-small";

    const config = gengold.specraster.RasterConfig{
        .save_opt = .disk,
        .save_formats = &[_]gengold.iio.ImageFormat{ .bmp, .csv },
        .tile_size = 16,
        .report = .perf,
        .perf_opts = .{
            .formats = &[_]gengold.iio.ImageFormat{ .bmp, .csv },
            .save_iteration_map = true,
            .save_tile_timing_map = true,
            .save_tile_density_map = true,
            .save_tile_occupancy_map = true,
            .save_depth_map = true,
            .save_earlyout_map = true,
            .save_pixel_occupancy_map = true,
        },
    };

    std.debug.print("Rendering Small Data to out-small/...\n", .{});

    std.debug.print("Single Element Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator, io, "single", &mesh_types, 1.1, texture, pixel_num, interp_types, 
        out_dir_root, data_dir, config,
    );

    std.debug.print("Full Screen Cases...\n", .{});
    try gengold.runGenerationExt(
        allocator, io, "full", &mesh_types, 1.0, texture, pixel_num, interp_types, 
        out_dir_root, data_dir, config,
    );
    
    std.debug.print("Done.\n", .{});
}
