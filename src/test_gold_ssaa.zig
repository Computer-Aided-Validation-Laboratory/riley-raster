// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;
const common = @import("common/tests.zig");
const suite = @import("common/ssaasuite.zig");
const tcfg = @import("common/testconfig.zig");

test "Gold SSAA Suite" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    std.debug.print("Running Gold SSAA Tests with .simd = .on...\n", .{});
    const suite_start = Timestamp.now(io, .awake);

    var first_err: ?anyerror = null;

    const strategies = [_]struct {
        map: @import("zraster/zig/rasterconfig.zig").SubPixelCenterMap,
        expect_match: bool,
    }{
        .{ .map = .per_tile, .expect_match = true },
        .{ .map = .affine_jac, .expect_match = false },
    };

    for (suite.mesh_types) |mesh_type| {
        for (suite.ssaa_values) |ssaa| {
            _ = arena.reset(.retain_capacity);
            const case_name = try suite.caseName(aa, mesh_type, ssaa);
            const gold_dir = try std.fmt.allocPrint(aa, "{s}/{s}", .{ suite.gold_root, case_name });
            for (strategies) |strategy| {
                const strategy_name = @tagName(strategy.map);
                if (tcfg.TEST_CASE_VERBOSE) {
                    std.debug.print("Testing {s} {s} ... ", .{ case_name, strategy_name });
                }
                const start_time = Timestamp.now(io, .awake);
                const image = try suite.renderCase(
                    allocator,
                    io,
                    mesh_type,
                    ssaa,
                    strategy.map,
                );
                defer {
                    allocator.free(image.slice);
                    var image_mut = image;
                    image_mut.deinit(allocator);
                }
                var result = try @import("zraster/zig/ndarray.zig").NDArray(f64).initFlat(
                    allocator,
                    &[_]usize{ 1, 1, 1, image.dims[1], image.dims[2] },
                );
                defer {
                    allocator.free(result.slice);
                    result.deinit(allocator);
                }
                for (0..image.dims[1]) |rr| {
                    for (0..image.dims[2]) |cc| {
                        result.set(&[_]usize{ 0, 0, 0, rr, cc }, image.get(&[_]usize{ 0, rr, cc }));
                    }
                }
                const gold_path = try common.findGoldPath(
                    aa,
                    io,
                    gold_dir,
                    0,
                    0,
                    0,
                    false,
                );
                const cmp_res = common.compareNDArrayToGold(
                    allocator,
                    io,
                    &result,
                    0,
                    0,
                    0,
                    1,
                    gold_path,
                    tcfg.REL_TOL,
                    tcfg.ABS_TOL,
                );
                const end_time = Timestamp.now(io, .awake);
                const duration_ms = @as(
                    f64,
                    @floatFromInt(start_time.durationTo(end_time).raw.nanoseconds),
                ) / 1e6;

                if (cmp_res) |_| {
                    if (!strategy.expect_match) {
                        std.debug.print(
                            "Unexpected pass for {s} {s} in {d:.3} ms\n",
                            .{ case_name, strategy_name, duration_ms },
                        );
                    } else if (tcfg.TEST_CASE_VERBOSE) {
                        std.debug.print("OK ({d:.3} ms)\n", .{duration_ms});
                    }
                } else |err| {
                    if (first_err == null) first_err = err;
                    const fail_dir_name = try std.fmt.allocPrint(
                        aa,
                        "{s}_{s}{s}",
                        .{ case_name, strategy_name, common.impl_suffix },
                    );
                    try common.saveComparisonArtifactsFromResult(
                        allocator,
                        io,
                        common.default_fails_root,
                        fail_dir_name,
                        &result,
                        0,
                        0,
                        0,
                        gold_path,
                        1,
                    );
                    if (tcfg.TEST_CASE_VERBOSE) {
                        std.debug.print("FAIL ({d:.3} ms)\n", .{duration_ms});
                    }
                }
            }
        }
    }

    const suite_end = Timestamp.now(io, .awake);
    const suite_ms = @as(
        f64,
        @floatFromInt(suite_start.durationTo(suite_end).raw.nanoseconds),
    ) / 1e6;
    std.debug.print("Gold SSAA Test Suite took {d:.3} ms\n", .{suite_ms});

    if (first_err) |err| return err;
}
