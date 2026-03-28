const std = @import("std");
const common = @import("bench_common.zig");
const tcfg = @import("testconfig.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");
const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

const config = common.BenchConfig{ .run = .all };

fn calculateDiff(
    allocator: std.mem.Allocator,
    actual: NDArray(f64),
    gold: NDArray(f64),
) !NDArray(f64) {
    var diff = try NDArray(f64).initFlat(allocator, actual.dims);
    for (0..actual.elems.len) |ii| {
        diff.elems[ii] = @abs(actual.elems[ii] - gold.elems[ii]);
    }
    return diff;
}

test "Sphere Gold Tests (SIMD)" {
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
        .{ .ds = "sphere200", .gold = "gold-sphere200", .out = "out-simd-sphere200" },
        .{ .ds = "sphere2000", .gold = "gold-sphere2000", .out = "out-simd-sphere2000" },
    };

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const interp_types = [_]common.InterpType{ .linear, .cubic, .cubic_lut_lerp, .quintic, .quintic_lut_lerp };

    var total_fails: usize = 0;

    const fails_dir_name = "fails";
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, fails_dir_name, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var fails_dir = try cwd.openDir(io, fails_dir_name, .{});
    defer fails_dir.close(io);

    std.debug.print("Running Sphere Gold Tests (SIMD)...\n", .{});

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

                        const test_csv_rel = try std.fmt.allocPrint(
                            allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ c.out, case_name, suffix }
                        );
                        defer allocator.free(test_csv_rel);
                        const gold_csv_rel = try std.fmt.allocPrint(
                            allocator, "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ c.gold, case_name, suffix }
                        );
                        defer allocator.free(gold_csv_rel);

                        // 3. Load and Compare
                        const t_arr_res = common.loadNDArrayFromCSV(
                            allocator, io, test_csv_rel, channels, false
                        );
                        if (t_arr_res) |t_arr| {
                            var t_mut = t_arr;
                            defer {
                                allocator.free(t_mut.elems);
                                t_mut.deinit(allocator);
                            }

                            const g_arr_res = common.loadNDArrayFromCSV(
                                allocator, io, gold_csv_rel, channels, false
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

                                    // SAVE DIAGNOSTICS
                                    const fail_case_prefix = try std.fmt.allocPrint(
                                        allocator, "{s}_{s}", .{ c.ds, case_name }
                                    );
                                    defer allocator.free(fail_case_prefix);

                                    // Save Actual Raw CSV
                                    const act_csv_name = try std.fmt.allocPrint(allocator, "{s}_actual.csv", .{fail_case_prefix});
                                    defer allocator.free(act_csv_name);
                                    var act_mat = MatSlice(f64).init(t_mut.elems, t_mut.dims[1], t_mut.dims[2] * channels);
                                    try act_mat.saveCSV(io, fails_dir, act_csv_name);

                                    // Save Actual Scaled BMP
                                    const act_bmp_name = try std.fmt.allocPrint(allocator, "{s}_actual.bmp", .{fail_case_prefix});
                                    defer allocator.free(act_bmp_name);
                                    try iio.saveBMP(io, fails_dir, act_bmp_name, &t_mut, 0, .{
                                        .format = .bmp, .bits = 8, .scaling = .auto, .channels = channels
                                    });

                                    // Calculate and Save Diff
                                    var diff_arr = try calculateDiff(allocator, t_mut, g_mut);
                                    defer {
                                        allocator.free(diff_arr.elems);
                                        diff_arr.deinit(allocator);
                                    }

                                    const diff_csv_name = try std.fmt.allocPrint(allocator, "{s}_diff.csv", .{fail_case_prefix});
                                    defer allocator.free(diff_csv_name);
                                    var diff_mat = MatSlice(f64).init(diff_arr.elems, diff_arr.dims[1], diff_arr.dims[2] * channels);
                                    try diff_mat.saveCSV(io, fails_dir, diff_csv_name);

                                    const diff_bmp_name = try std.fmt.allocPrint(allocator, "{s}_diff.bmp", .{fail_case_prefix});
                                    defer allocator.free(diff_bmp_name);
                                    try iio.saveBMP(io, fails_dir, diff_bmp_name, &diff_arr, 0, .{
                                        .format = .bmp, .bits = 8, .scaling = .auto, .channels = channels
                                    });
                                }
                            } else |err| {
                                std.debug.print(
                                    "GOLD LOAD ERROR: {s} ({s})\n",
                                    .{ gold_csv_rel, @errorName(err) }
                                );
                                total_fails += 1;
                            }
                        } else |err| {
                            std.debug.print(
                                "TEST LOAD ERROR: {s} ({s})\n",
                                .{ test_csv_rel, @errorName(err) }
                            );
                            total_fails += 1;
                        }
                    }
                }
            }
        }
    }

    if (total_fails == 0) {
        std.debug.print("\nALL SIMD SPHERE GOLD TESTS PASSED!\n", .{});
    } else {
        std.debug.print("\n{d} TESTS FAILED! (Diagnostics in ./fails/)\n", .{total_fails});
        try std.testing.expect(total_fails == 0);
    }
}
