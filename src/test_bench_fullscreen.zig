const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

test "Unified Fullscreen Benchmark Tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(
        allocator, io, "texture/speckle.bmp", .bmp, u8, 1
    );
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(
        allocator, io, "texture/speckle_rgb.bmp", .bmp, u8, 3
    );
    defer texture_rgb.deinit(allocator);

    const gold_dir_base = "gold-bench-fullscreen";
    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);

    const tol = 1e-6;
    var total_fails: usize = 0;

    const bench_types = [_][]const u8{ "fullraster", "geom" };

    std.debug.print("Running Unified Fullscreen Benchmark Tests...\n", .{});

    inline for (bench_types) |bt| {
        std.debug.print("\n--- Testing benchmark type: {s} ---\n", .{bt});
        const out_dir_base = "out-bench-old-" ++ bt;

        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                const case_name = comptime @tagName(mt) ++ "_" ++ @tagName(st);
                const data_dir = comptime "data-bench/" ++ @tagName(mt) ++ "_" ++ bt;

                std.debug.print("Testing {s} ... ", .{case_name});

                // 1. Run benchmark
                _ = try common.runBenchmark(
                    allocator, io, mt, st, data_dir, out_dir_base,
                    pixel_num, texture_grey, texture_rgb
                );

                // 2. Map filenames
                const is_rgb = (st == .flat_rgb or st == .tex8_rgb);
                const channels: usize = if (is_rgb) 3 else 1;
                const suffix = if (is_rgb) "_rgb" else "";

                const bench_csv = try std.fmt.allocPrint(
                    allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                    .{ out_dir_base, case_name, suffix }
                );
                defer allocator.free(bench_csv);
                const gold_csv = try std.fmt.allocPrint(
                    allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                    .{ gold_dir_base, case_name, suffix }
                );
                defer allocator.free(gold_csv);

                // 3. Load and Compare
                const b_arr_res = common.loadNDArrayFromCSV(
                    allocator, io, bench_csv, channels, false
                );
                if (b_arr_res) |b_arr| {
                    var b_mut = b_arr;
                    defer {
                        allocator.free(b_mut.elems);
                        b_mut.deinit(allocator);
                    }

                    const g_arr_res = common.loadNDArrayFromCSV(
                        allocator, io, gold_csv, channels, false
                    );
                    if (g_arr_res) |g_arr| {
                        var g_mut = g_arr;
                        defer {
                            allocator.free(g_mut.elems);
                            g_mut.deinit(allocator);
                        }

                        var diff_count: usize = 0;
                        for (b_mut.elems, 0..) |v_b, ii| {
                            if (@abs(v_b - g_mut.elems[ii]) > tol) diff_count += 1;
                        }

                        if (diff_count == 0) {
                            std.debug.print("MATCHED\n", .{});
                        } else {
                            std.debug.print("MISMATCH! ({d} px)\n", .{diff_count});
                            total_fails += 1;
                        }
                    } else |err| {
                        std.debug.print(
                            "GOLD LOAD ERROR: {s} ({s})\n",
                            .{ gold_csv, @errorName(err) }
                        );
                        total_fails += 1;
                    }
                } else |err| {
                    std.debug.print(
                        "BENCH LOAD ERROR: {s} ({s})\n",
                        .{ bench_csv, @errorName(err) }
                    );
                    total_fails += 1;
                }
            }
        }
    }

    if (total_fails == 0) {
        std.debug.print("\nALL UNIFIED FULLSCREEN TESTS PASSED!\n", .{});
    } else {
        std.debug.print("\n{d} TESTS FAILED!\n", .{total_fails});
        try std.testing.expect(total_fails == 0);
    }
}
