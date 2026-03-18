const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(allocator, io, "texture/speckle.bmp", .bmp, u8, 1);
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(allocator, io, "texture/speckle_rgb.bmp", .bmp, u8, 3);
    defer texture_rgb.deinit(allocator);

    const pixel_num = [_]u32{ 512, 512 };

    std.debug.print("Comparing tri3_flat_rgb consistency between Full and Geom...\n", .{});

    _ = try common.runBenchmark(allocator, io, .tri3, .flat_rgb, "data-bench/tri3_fullraster", "out-test-consist-full", pixel_num, texture_grey, texture_rgb);
    _ = try common.runBenchmark(allocator, io, .tri3, .flat_rgb, "data-bench/tri3_geom", "out-test-consist-geom", pixel_num, texture_grey, texture_rgb);

    // Load CSVs and compare
    const full_csv_path = "out-test-consist-full/tri3_flat_rgb/frame_0_field_0_2.csv";
    const geom_csv_path = "out-test-consist-geom/tri3_flat_rgb/frame_0_field_0_2.csv";

    const full_arr = try common.loadNDArrayFromCSV(allocator, io, full_csv_path, 3, false);
    var full_arr_mut = full_arr;
    defer {
        allocator.free(full_arr_mut.elems);
        full_arr_mut.deinit(allocator);
    }
    const geom_arr = try common.loadNDArrayFromCSV(allocator, io, geom_csv_path, 3, false);
    var geom_arr_mut = geom_arr;
    defer {
        allocator.free(geom_arr_mut.elems);
        geom_arr_mut.deinit(allocator);
    }

    var diff_count: usize = 0;
    var max_diff: f64 = 0;
    const tol = 1e-6;

    for (full_arr.elems, 0..) |v_full, ii| {
        const v_geom = geom_arr.elems[ii];
        const diff = @abs(v_full - v_geom);
        if (diff > tol) {
            diff_count += 1;
            if (diff > max_diff) max_diff = diff;
        }
    }

    if (diff_count == 0) {
        std.debug.print("SUCCESS: Full and Geom outputs match exactly!\n", .{});
    } else {
        std.debug.print("FAILURE: Found {d} mismatched pixels. Max diff: {d:.10}\n", .{diff_count, max_diff});
    }
}
