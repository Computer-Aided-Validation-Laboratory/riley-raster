const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    const outer_alloc = std.heap.page_allocator;

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

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
            },
            .save_iteration_map = true,
            .save_depth_map = true,
        },
    };

    const out_dir_root = "out-bench-multimesh";
    std.debug.print("Rendering Multimesh Data to {s}/...\n", .{out_dir_root});

    try gengold.runMultimeshGenerationExt(outer_alloc, io, config, out_dir_root);
    try gengold.runMultimeshMixedGenerationExt(
        outer_alloc,
        io,
        config,
        out_dir_root ++ "/allelem_allshade",
    );
    try gengold.runMultimeshMixedRGBGenerationExt(
        outer_alloc,
        io,
        config,
        out_dir_root ++ "/allelem_allshade_rgb",
    );

    std.debug.print("Done.\n", .{});
}
