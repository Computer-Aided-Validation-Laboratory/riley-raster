const std = @import("std");
const gengold = @import("common/gengold.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const config = gengold.specraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]gengold.iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 32,
        .report = .off,
    };

    std.debug.print("Generating Multimesh Gold Data...\n", .{});
    try gengold.runMultimeshGeneration(allocator, io, config);
    std.debug.print("Done.\n", .{});
}
