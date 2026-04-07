const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    const outer_alloc = std.heap.page_allocator;

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture = try gengold.iio.loadImage(
        outer_alloc,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
        u8,
        1,
    );
    defer texture.deinit(outer_alloc);

    const mesh_types = [_]gengold.MeshType{ .tri3, .tri3opt, .tri6, .quad4ibi, .quad4newton, .quad8, .quad9 };
    const interp_types = [_]gengold.texops.InterpType{.cubic_lut_lerp};

    const pixel_num = [_]u32{ 800, 500 };

    const out_dir_root = "out-bench-simple";
    const data_dir = "data-simple";

    const config = gengold.zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .full_stats,
        .full_stats_opts = .{
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

    std.debug.print("Rendering Simple Data (Two Elements only) to {s}/...\n", .{
        out_dir_root,
    });
    try gengold.runGenerationExt(
        outer_alloc,
        io,
        "twoelems",
        &mesh_types,
        1.1,
        texture,
        pixel_num,
        &interp_types,
        out_dir_root,
        data_dir,
        config,
    );

    std.debug.print("Done.\n", .{});
}
