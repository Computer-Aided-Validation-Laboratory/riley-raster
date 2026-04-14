const std = @import("std");
const common = @import("common/benchcommon.zig");
const testcommon = @import("common/tests.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");

const config = common.BenchConfig{ .run = .all };
const simd_on = buildconfig.config.simd == .on;
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
            .name = "sphere200",
            .gold_dir = if (simd_on)
                "gold-simd-sphere200"
            else
                "gold-sphere200",
            .out_dir = "out-sphere200",
            .is_sphere = true,
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
    const interp_types = [_]common.InterpType{
        .linear, .cubic, .cubic_lut_lerp, .quintic, .quintic_lut_lerp,
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
                for (interp_types) |it| {
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

                    if (common.shouldRun(run_config, mt, st, it, data_dir)) {
                        const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}_{s}",
                                .{ @tagName(mt), @tagName(st), @tagName(it) },
                            )
                        else
                            try std.fmt.allocPrint(
                                aa,
                                "{s}_{s}",
                                .{ @tagName(mt), @tagName(st) },
                            );

                        std.debug.print("Testing {s}/{s} ... ", .{ cc.name, case_name });

                        // 1. Run benchmark
                        _ = try common.runBenchmarkQuiet(
                            outer_alloc,
                            io,
                            mt,
                            st,
                            it,
                            data_dir,
                            cc.out_dir,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
                        );

                        // 2. Map filenames
                        const is_rgb = (st == .flat_rgb or st == .tex8_rgb);
                        const channels: usize = if (is_rgb) 3 else 1;
                        const suffix = if (is_rgb) "_rgb" else "";

                        const test_csv = try std.fmt.allocPrint(
                            aa,
                            "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ cc.out_dir, case_name, suffix },
                        );
                        const gold_csv = try std.fmt.allocPrint(
                            aa,
                            "{s}/{s}/frame_0_field_0{s}.csv",
                            .{ cc.gold_dir, case_name, suffix },
                        );

                        // 3. Load and Compare
                        const t_arr_res = common.loadNDArrayFromCSV(
                            outer_alloc,
                            io,
                            test_csv,
                            channels,
                            false,
                        );
                        if (t_arr_res) |t_arr| {
                            var t_mut = t_arr;
                            defer {
                                outer_alloc.free(t_mut.slice);
                                t_mut.deinit(outer_alloc);
                            }

                            const g_arr_res = common.loadNDArrayFromCSV(
                                outer_alloc,
                                io,
                                gold_csv,
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
                                    .{ gold_csv, @errorName(err) },
                                );
                                total_fails += 1;
                            }
                        } else |err| {
                            std.debug.print(
                                "TEST LOAD ERROR: {s} ({s})\n",
                                .{ test_csv, @errorName(err) },
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
