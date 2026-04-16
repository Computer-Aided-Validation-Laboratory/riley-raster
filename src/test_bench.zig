const std = @import("std");
const common = @import("common/benchcommon.zig");
const testcommon = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const cfg = buildconfig.config;
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");

const config = common.BenchConfig{ .run = .all };
const simd_on = cfg.simd == .on;
const impl_suffix = if (simd_on) "_simd" else "_scalar";

test "Unified Benchmark Tests" {
    const outer_alloc = std.heap.page_allocator;

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(
        outer_alloc,
        io,
        "texture/speckle.bmp",
        .bmp,
        u8,
        1,
    );
    defer texture_grey.deinit(outer_alloc);
    const texture_rgb = try iio.loadImage(
        outer_alloc,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
        u8,
        3,
    );
    defer texture_rgb.deinit(outer_alloc);

    const cases = [_]struct {
        name: []const u8,
        gold_dir: []const u8,
        out_dir: []const u8,
        is_sphere: bool = false,
    }{
        .{
            .name = "fullraster",
            .gold_dir = "gold-bench-fullscreen",
            .out_dir = "out-bench-fullraster",
        },
        .{
            .name = "geom",
            .gold_dir = "gold-bench-fullscreen",
            .out_dir = "out-bench-geom",
        },
        .{
            .name = "sphere2000",
            .gold_dir = if (simd_on)
                "gold-simd-sphere2000"
            else
                "gold-sphere2000",
            .out_dir = "out-sphere2000",
            .is_sphere = true,
        },
    };

    const pixel_num = [_]u32{ 800, 500 };

    const mesh_types = std.enums.values(mr.MeshType);
    const shader_types = std.enums.values(common.ShaderType);
    const sample_configs = [_]common.TextureSampleConfig{
        .{ .sample = .nearest, .mode = .direct },
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    var total_fails: usize = 0;

    std.debug.print("Running Unified Benchmark Tests...\n", .{});

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    for (cases) |cc| {
        std.debug.print("\n--- Testing benchmark: {s} ---\n", .{cc.name});

        for (mesh_types) |mt| {
            for (shader_types) |st| {
                for (sample_configs) |sc| {
                    _ = arena.reset(.free_all);

                    const data_dir = try std.fmt.allocPrint(
                        aa,
                        "data-bench/{s}_{s}",
                        .{ @tagName(mt), cc.name },
                    );

                    const run_config = if (cc.is_sphere)
                        common.BenchConfig{ .run = .all, .skip_quad4ibi_sphere = true }
                    else
                        config;

                    if (common.shouldRun(run_config, mt, st, sc, data_dir)) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}_{s}_{s}",
                                .{ @tagName(mt), @tagName(st), @tagName(sc.sample), @tagName(sc.mode) },
                            )
                        else
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );

                        std.debug.print("Testing {s}/{s} ... ", .{ cc.name, case_name });

                        // 1. Run benchmark
                        var result = try common.runBenchmarkQuiet(
                            outer_alloc,
                            io,
                            mt,
                            st,
                            sc,
                            data_dir,
                            cc.out_dir,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
                        );
                        result.deinit(outer_alloc);

                        // 2. Map filenames
                        const is_rgb = (st == .nodal_rgb or st == .tex8_rgb);
                        const channels: usize = if (is_rgb) 3 else 1;

                        const test_dir_case = try std.fs.path.join(aa, &[_][]const u8{ cc.out_dir, case_name });
                        const test_path = try testcommon.findGoldPath(aa, io, test_dir_case, 0, 0, is_rgb);
                        const gold_dir_case = try std.fs.path.join(aa, &[_][]const u8{ cc.gold_dir, case_name });
                        const gold_path = try testcommon.findGoldPath(aa, io, gold_dir_case, 0, 0, is_rgb);

                        // 3. Load and Compare
                        const t_arr_res = common.loadNDArray(
                            outer_alloc,
                            io,
                            test_path,
                            channels,
                            false,
                        );
                        if (t_arr_res) |t_arr| {
                            var t_mut = t_arr;
                            defer {
                                outer_alloc.free(t_mut.slice);
                                t_mut.deinit(outer_alloc);
                            }

                            const g_arr_res = common.loadNDArray(
                                outer_alloc,
                                io,
                                gold_path,
                                channels,
                                false,
                            );
                            if (g_arr_res) |g_arr| {
                                var g_mut = g_arr;
                                defer {
                                    outer_alloc.free(g_mut.slice);
                                    g_mut.deinit(outer_alloc);
                                }

                                var diff_count: usize = 0;
                                for (t_mut.slice, 0..) |v_t, ii| {
                                    if (@abs(v_t - g_mut.slice[ii]) > tcfg.REL_TOL) {
                                        diff_count += 1;
                                    }
                                }

                                if (diff_count == 0) {
                                    std.debug.print("MATCHED\n", .{});
                                } else {
                                    std.debug.print(
                                        "MISMATCH! ({d} px)\n",
                                        .{diff_count},
                                    );
                                    const fail_dir_name = try std.fmt.allocPrint(
                                        aa,
                                        "bench_{s}_{s}{s}",
                                        .{ cc.name, case_name, impl_suffix },
                                    );
                                    try testcommon.saveComparisonArtifactsFromImages(
                                        aa,
                                        io,
                                        "fails",
                                        fail_dir_name,
                                        &t_mut,
                                        &g_mut,
                                    );
                                    total_fails += 1;
                                }
                            } else |err| {
                                std.debug.print(
                                    "GOLD LOAD ERROR: {s} ({s})\n",
                                    .{ gold_path, @errorName(err) },
                                );
                                total_fails += 1;
                            }
                        } else |err| {
                            std.debug.print(
                                "TEST LOAD ERROR: {s} ({s})\n",
                                .{ test_path, @errorName(err) },
                            );
                            total_fails += 1;
                        }
                    }
                }
            }
        }
    }

    if (total_fails == 0) {
        std.debug.print("\nALL BENCHMARK TESTS PASSED!\n", .{});
    } else {
        std.debug.print("\n{d} TESTS FAILED!\n", .{total_fails});
        try std.testing.expect(total_fails == 0);
    }
}
