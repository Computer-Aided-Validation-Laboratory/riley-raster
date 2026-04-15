const std = @import("std");
const common = @import("common/benchcommon.zig");
const testcommon = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");

const config = common.BenchConfig{ .run = .all };
const simd_on = buildconfig.config.simd == .on;

test "Sphere Gold Tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(
        allocator,
        io,
        "texture/speckle.bmp",
        .bmp,
        u8,
        1,
    );
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(
        allocator,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
        u8,
        3,
    );
    defer texture_rgb.deinit(allocator);

    const fails_root = "fails";
    const impl_suffix = if (simd_on) "_simd" else "_scalar";

    const cases = [_]struct { ds: []const u8, gold: []const u8, out: []const u8 }{
        .{
            .ds = "sphere200",
            .gold = if (simd_on) "gold-simd-sphere200" else "gold-sphere200",
            .out = "out-sphere200",
        },
        .{
            .ds = "sphere2000",
            .gold = if (simd_on) "gold-simd-sphere2000" else "gold-sphere2000",
            .out = "out-sphere2000",
        },
    };

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const sample_configs = [_]common.TextureSampleConfig{
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    var total_fails: usize = 0;

    std.debug.print("Running Sphere Gold Tests with .simd = .{s}...\n", .{
        if (simd_on) "on" else "off",
    });

    inline for (cases) |c| {
        std.debug.print("\n--- Testing dataset: {s} ---\n", .{c.ds});

        inline for (mesh_types) |mt| {
            inline for (shader_types) |st| {
                inline for (sample_configs) |sc| {
                    const data_dir = try std.fmt.allocPrint(
                        allocator,
                        "data-bench/{s}_{s}",
                        .{ @tagName(mt), c.ds },
                    );
                    defer allocator.free(data_dir);

                    if (common.shouldRun(.{ .run = .all }, mt, st, sc, data_dir)) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}_{s}_{s}",
                                .{ @tagName(mt), @tagName(st), @tagName(sc.sample), @tagName(sc.mode) },
                            )
                        else
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );
                        defer allocator.free(case_name);

                        const gold_mesh_name = if (mt == .quad4ibi)
                            "quad4newton"
                        else
                            @tagName(mt);
                        const gold_case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}_{s}_{s}",
                                .{ gold_mesh_name, @tagName(st), @tagName(sc.sample), @tagName(sc.mode) },
                            )
                        else
                            try std.fmt.allocPrint(
                                allocator,
                                "{s}_{s}",
                                .{ gold_mesh_name, @tagName(st) },
                            );
                        defer allocator.free(gold_case_name);

                        std.debug.print("Testing {s}/{s} ... ", .{ c.ds, case_name });

                        // 1. Run benchmark
                        var result = try common.runBenchmarkQuiet(
                            allocator,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            c.out,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
                        );
                        result.deinit(allocator);

                        // 2. Map filenames
                        const is_rgb = (st == .flat_rgb or st == .tex8_rgb);
                        const channels: usize = if (is_rgb) 3 else 1;

                        const test_path = try common.findGoldPath(allocator, io, c.out, 0, 0, is_rgb);
                        defer allocator.free(test_path);
                        const gold_path = try common.findGoldPath(allocator, io, c.gold, 0, 0, is_rgb);
                        defer allocator.free(gold_path);

                        // 3. Load and Compare
                        const t_arr_res = common.loadNDArray(
                            allocator,
                            io,
                            test_path,
                            channels,
                            false,
                        );
                        if (t_arr_res) |t_arr| {
                            var t_mut = t_arr;
                            defer {
                                allocator.free(t_mut.slice);
                                t_mut.deinit(allocator);
                            }

                            const g_arr_res = common.loadNDArray(
                                allocator,
                                io,
                                gold_path,
                                channels,
                                false,
                            );
                            if (g_arr_res) |g_arr| {
                                var g_mut = g_arr;
                                defer {
                                    allocator.free(g_mut.slice);
                                    g_mut.deinit(allocator);
                                }

                                var diff_count: usize = 0;
                                for (t_mut.slice, 0..) |v_t, ii| {
                                    if (@abs(v_t - g_mut.slice[ii]) > tcfg.REL_TOL)
                                        diff_count += 1;
                                }

                                if (diff_count == 0) {
                                    std.debug.print("MATCHED\n", .{});
                                } else {
                                    std.debug.print(
                                        "MISMATCH! ({d} px)\n",
                                        .{diff_count},
                                    );
                                    total_fails += 1;

                                    const fail_dir_name = try std.fmt.allocPrint(
                                        allocator,
                                        "all_{s}_{s}{s}",
                                        .{ c.ds, case_name, impl_suffix },
                                    );
                                    defer allocator.free(fail_dir_name);
                                    try testcommon.saveComparisonArtifactsFromImages(
                                        allocator,
                                        io,
                                        fails_root,
                                        fail_dir_name,
                                        &t_mut,
                                        &g_mut,
                                    );
                                }
                            } else |err| {
                                std.debug.print(
                                    "GOLD LOAD ERROR: {s} ({s})\n",
                                    .{ gold_csv_rel, @errorName(err) },
                                );
                                total_fails += 1;
                            }
                        } else |err| {
                            std.debug.print(
                                "TEST LOAD ERROR: {s} ({s})\n",
                                .{ test_csv_rel, @errorName(err) },
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
        std.debug.print(
            "\n{d} TESTS FAILED! (Diagnostics in ./fails/)\n",
            .{total_fails},
        );
        try std.testing.expect(total_fails == 0);
    }
}
