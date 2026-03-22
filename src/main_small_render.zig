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
        .tri3, .tri6, .quad4ibi, .quad8, .quad9 
    };
    const interp_types = [_]gengold.texops.InterpType{ 
        .linear, .cubic, .cubic_lut, .cubic_lut_lerp, .quintic, .quintic_lut, .quintic_lut_lerp 
    };

    const pixel_num = [_]u32{ 160, 100 };

    const out_dir_root = "out-bench-small";
    const data_dir = "data-small";

    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 16,
        .report = .perf,
        .perf_opts = .{
            .formats = &[_]gengold.iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
                .{ .format = .csv, .bits = null, .scaling = .none },
            },
            .save_iteration_map = true,
            .save_tile_timing_map = true,
            .save_tile_density_map = true,
            .save_tile_occupancy_map = true,
            .save_depth_map = true,
            .save_earlyout_map = true,
            .save_pixel_occupancy_map = true,
        },
    };

    std.debug.print("Rendering Small Data to out-bench-mm0-small/...\n", .{});
    try gengold.runGenerationExt(
        allocator, io, "single", &mesh_types, 1.1, texture, pixel_num, &interp_types, 
        out_dir_root, data_dir, config
    );

    std.debug.print("Done.\n", .{});
}
