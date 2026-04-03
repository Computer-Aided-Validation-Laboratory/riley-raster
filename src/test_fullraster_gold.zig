const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

test "Fullraster Gold Comparison" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);

    const tol = 1e-6;
    var total_fails: usize = 0;

    std.debug.print("Comparing out-bench-norm-old-fullraster against Gold data...\n", .{});

    inline for (mesh_types) |mt| {
        inline for (shader_types) |st| {
            const case_name = comptime @tagName(mt) ++ "_" ++ @tagName(st);

            const bench_csv = try std.fmt.allocPrint(allocator, "out-bench-norm-old-fullraster/{s}/frame_0_field_0{s}.csv", .{ case_name, if (st == .flat_rgb or st == .tex8_rgb) "_rgb" else "" });
            defer allocator.free(bench_csv);

            const gold_csv: ?[]u8 = if (st == .flat_grey or st == .flat_rgb)
                try std.fmt.allocPrint(allocator, "gold-rgb/{s}/frame_0_field_0{s}.csv", .{ case_name, if (st == .flat_rgb) "_rgb" else "" })
            else if (st == .tex8_grey)
                try std.fmt.allocPrint(allocator, "gold-small/full_{s}_dispon_tex_cubic_lut_lerp/frame_0_field_0.csv", .{@tagName(mt)})
            else
                null;

            if (gold_csv) |g_csv| {
                defer allocator.free(g_csv);

                std.debug.print("Checking {s} ... ", .{case_name});

                const b_arr_maybe = common.loadNDArrayFromCSV(allocator, io, bench_csv, if (st == .flat_rgb or st == .tex8_rgb) 3 else 1, false);
                if (b_arr_maybe) |b_arr| {
                    var b_arr_mut = b_arr;
                    defer {
                        allocator.free(b_arr_mut.elems);
                        b_arr_mut.deinit(allocator);
                    }

                    const g_arr_maybe = common.loadNDArrayFromCSV(allocator, io, g_csv, if (st == .flat_rgb) 3 else 1, false);
                    if (g_arr_maybe) |g_arr| {
                        var g_arr_mut = g_arr;
                        defer {
                            allocator.free(g_arr_mut.elems);
                            g_arr_mut.deinit(allocator);
                        }

                        var diff_count: usize = 0;
                        var max_diff: f64 = 0;

                        for (b_arr_mut.elems, 0..) |v_b, ii| {
                            const v_g = g_arr_mut.elems[ii];
                            const diff = @abs(v_b - v_g);
                            if (diff > tol) {
                                diff_count += 1;
                                if (diff > max_diff) max_diff = diff;
                            }
                        }

                        if (diff_count == 0) {
                            std.debug.print("MATCHED\n", .{});
                        } else {
                            std.debug.print("MISMATCH! ({d} px, max diff: {d:.10})\n", .{ diff_count, max_diff });
                            total_fails += 1;
                        }
                    } else |err| {
                        std.debug.print("FAILED to load gold CSV: {s} ({s})\n", .{ g_csv, @errorName(err) });
                        total_fails += 1;
                    }
                } else |err| {
                    std.debug.print("FAILED to load bench CSV: {s} ({s})\n", .{ bench_csv, @errorName(err) });
                    total_fails += 1;
                }
            } else {
                std.debug.print("Skipping {s} (no gold comparison defined)\n", .{case_name});
            }
        }
    }

    if (total_fails == 0) {
        std.debug.print("\nALL COMPARISONS PASSED!\n", .{});
    } else {
        std.debug.print("\n{d} COMPARISONS FAILED!\n", .{total_fails});
        try std.testing.expect(total_fails == 0);
    }
}
