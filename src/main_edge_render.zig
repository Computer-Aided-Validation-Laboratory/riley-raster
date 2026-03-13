const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture =  try gengold.iio.loadImage(
        allocator, io, "temp-test/speckle-simple.tiff", .tiff, u8, 1
    );
    defer texture.deinit(allocator);

    const interp_types = [_]gengold.texops.InterpType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 800, 500 };
    const gold_dir = "out-edge";
    const data_dir = "data-edge";

    const config = gengold.specraster.RasterConfig{
        .save_opt = .disk,
        .save_formats = &[_]gengold.iio.ImageFormat{ .bmp },
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

    std.debug.print("Rendering Edge Cases to out-edge/...\n", .{});
    
    // Tri6
    {
        const mt = [_]gengold.MeshType{ .tri6 };
        try gengold.runGenerationExt(
            allocator, io, "bulgein_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "bulgeout_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "vertbulge", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
    }

    // Quad8
    {
        const mt = [_]gengold.MeshType{ .quad8 };
        try gengold.runGenerationExt(
            allocator, io, "bulgein_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "bulgeout_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "vertbulge", &mt, 1.1, texture, pixel_num, &interp_types, gold_dir, 
            data_dir, config
        );
    }

    // Quad9
    {
        const mt = [_]gengold.MeshType{ .quad9 };
        try gengold.runGenerationExt(
            allocator, io, "bulgein_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "bulgeout_rot", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
        try gengold.runGenerationExt(
            allocator, io, "vertbulge", &mt, 1.1, texture, pixel_num, &interp_types, 
            gold_dir, data_dir, config
        );
    }
    
    std.debug.print("Done.\n", .{});
}
