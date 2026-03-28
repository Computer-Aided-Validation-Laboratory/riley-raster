const std = @import("std");
const common = @import("bench_common.zig");
const tcfg = @import("testconfig.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

const config = common.BenchConfig{ .run = .all };

test "Sphere Gold Tests" {
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

    const cases = [_]struct { ds: []const u8, gold: []const u8, out: []const u8 }{
        .{ .ds = "sphere200", .gold = "gold-sphere200", .out = "out-sphere200" },
        .{ .ds = "sphere2000", .gold = "gold-sphere2000", .out = "out-sphere2000" },
    };

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const interp_types = [_]common.InterpType{ .linear, .cubic, .cubic_lut_lerp, .quintic, .quintic_lut_lerp };

    var total_fails: usize = 0;

    std.debug.print("Running Sphere Gold Tests...\n", .{});

    inline for (cases) |c| {
        std.debug.print("\n--- Testing dataset: {s} ---\n", .{c.ds});

        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (interp_types) |it| {
                    const data_dir = try std.fmt.allocPrint(allocator, "data-bench/{s}_{s}", .{@tagName(mt), c.ds});
                    defer allocator.free(data_dir);

                    if (common.shouldRun(.{ .run = .all, .skip_quad4ibi_sphere = true }, mt, st, it, data_dir)) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            comptime @tagName(mt) ++ "_" ++ @tagName(st) ++ "_" ++ @tagName(it)
                        else
                            comptime @tagName(mt) ++ "_" ++ @tagName(st);

                        std.debug.print("Testing {s}/{s} ... ", .{c.ds, case_name});

                        // 1. Run benchmark
                        _ = try common.runBenchmark(
                            allocator, io, mt, st, it, data_dir, c.out,
                            pixel_num, texture_grey, texture_rgb
                        );

                        // 2. Map filenames
                        const is_rgb = (st == .flat_rgb or st == .tex8_rgb);
                        const channels: usize = if (is_rgb) 3 else 1;
                        const suffix = if (is_rgb) "_rgb" else "";

                        const test_csv = try std.fmt.allocPrint(
                            allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ c.out, case_name, suffix }
                        );
                        defer allocator.free(test_csv);
                        const gold_csv = try std.fmt.allocPrint(
                            allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ c.gold, case_name, suffix }
                        );
                        defer allocator.free(gold_csv);

                        // 3. Load and Compare
                        const t_arr_res = common.loadNDArrayFromCSV(
                            allocator, io, test_csv, channels, false
                        );
                        if (t_arr_res) |t_arr| {
                            var t_mut = t_arr;
                            defer {
                                allocator.free(t_mut.elems);
                                t_mut.deinit(allocator);
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
                                for (t_mut.elems, 0..) |v_t, ii| {
                                    if (@abs(v_t - g_mut.elems[ii]) > tcfg.REL_TOL) diff_count += 1;
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
                                "TEST LOAD ERROR: {s} ({s})\n",
                                .{ test_csv, @errorName(err) }
                            );
                            total_fails += 1;
                        }
                    }
                }
            }
        }
    }

    if (total_fails == 0) {
        std.debug.print("\nALL SPHERE GOLD TESTS PASSED!\n", .{});
    } else {
        std.debug.print("\n{d} TESTS FAILED!\n", .{total_fails});
        try std.testing.expect(total_fails == 0);
    }
}
