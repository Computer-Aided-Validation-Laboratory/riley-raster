// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rastcfg = @import("../zraster/zig/rasterconfig.zig");
const texops = @import("../zraster/zig/textureops.zig");

pub const BenchArgs = struct {
    out_dir: []const u8,
    render_mode: rastcfg.RenderMode,
    total_threads: u16,
    max_geom_threads_per_frame: u16,
    max_raster_threads_per_frame: u16,
    max_frames_in_flight: u16,
    hull_mode: rastcfg.HullMode,
    subpixel_center_map: rastcfg.SubPixelCenterMap,
    save_strategy: rastcfg.SaveStrategy,
    sample: ?texops.TextureSample,
    sample_mode: ?texops.TextureSampleMode,
    pixels_num: [2]u32,
    sub_sample: u8,
    runs: usize,
};

pub fn defaultBenchArgs(
    default_out_dir: []const u8,
    raster_config: rastcfg.RasterConfig,
) BenchArgs {
    return .{
        .out_dir = default_out_dir,
        .render_mode = raster_config.render_mode,
        .total_threads = raster_config.total_threads,
        .max_geom_threads_per_frame = raster_config.max_geom_workers_per_frame,
        .max_raster_threads_per_frame = raster_config.max_raster_workers_per_frame,
        .max_frames_in_flight = raster_config.max_frames_in_flight,
        .hull_mode = raster_config.hull_mode,
        .subpixel_center_map = raster_config.subpixel_center_map,
        .save_strategy = .memory,
        .sample = null,
        .sample_mode = null,
        .pixels_num = .{ 800, 500 },
        .sub_sample = 2,
        .runs = 10,
    };
}

pub fn parseArgs(
    args: anytype,
    default_out_dir: []const u8,
    raster_config: rastcfg.RasterConfig,
) !BenchArgs {
    var bench_args = defaultBenchArgs(
        default_out_dir,
        raster_config,
    );
    var total_threads_overridden = false;
    var max_geom_threads_overridden = false;
    var max_raster_threads_overridden = false;
    var skip_next = false;
    var positional_arg_count: usize = 0;

    for (args[1..], 1..) |raw_arg, ii| {
        if (skip_next) {
            skip_next = false;
            continue;
        }

        const arg = argToSlice(raw_arg);
        if (std.mem.startsWith(u8, arg, "--")) {
            if (ii + 1 >= args.len) {
                return error.MissingArgumentValue;
            }

            const value = argToSlice(args[ii + 1]);
            skip_next = true;

            if (std.mem.eql(u8, arg, "--render-mode")) {
                bench_args.render_mode =
                    try parseEnum(rastcfg.RenderMode, value);
            } else if (std.mem.eql(u8, arg, "--total-threads")) {
                bench_args.total_threads = try parseInt(u16, value);
                total_threads_overridden = true;
            } else if (std.mem.eql(
                u8,
                arg,
                "--max-geom-threads-per-frame",
            )) {
                bench_args.max_geom_threads_per_frame =
                    try parseInt(u16, value);
                max_geom_threads_overridden = true;
            } else if (std.mem.eql(
                u8,
                arg,
                "--max-raster-threads-per-frame",
            )) {
                bench_args.max_raster_threads_per_frame =
                    try parseInt(u16, value);
                max_raster_threads_overridden = true;
            } else if (std.mem.eql(u8, arg, "--max-frames-in-flight")) {
                bench_args.max_frames_in_flight = try parseInt(u16, value);
            } else if (std.mem.eql(u8, arg, "--hull-mode")) {
                bench_args.hull_mode =
                    try parseEnum(rastcfg.HullMode, value);
            } else if (std.mem.eql(u8, arg, "--subpixel-center-map")) {
                bench_args.subpixel_center_map =
                    try parseEnum(rastcfg.SubPixelCenterMap, value);
            } else if (std.mem.eql(u8, arg, "--save-strategy")) {
                bench_args.save_strategy =
                    try parseEnum(rastcfg.SaveStrategy, value);
            } else if (std.mem.eql(u8, arg, "--sample")) {
                bench_args.sample =
                    try parseEnum(texops.TextureSample, value);
            } else if (std.mem.eql(u8, arg, "--sample-mode")) {
                bench_args.sample_mode =
                    try parseEnum(texops.TextureSampleMode, value);
            } else if (std.mem.eql(u8, arg, "--out-dir")) {
                bench_args.out_dir = value;
            } else if (std.mem.eql(u8, arg, "--pixels-x")) {
                bench_args.pixels_num[0] = try parseInt(u32, value);
            } else if (std.mem.eql(u8, arg, "--pixels-y")) {
                bench_args.pixels_num[1] = try parseInt(u32, value);
            } else if (std.mem.eql(u8, arg, "--sub-sample")) {
                bench_args.sub_sample = try parseInt(u8, value);
            } else if (std.mem.eql(u8, arg, "--runs")) {
                bench_args.runs = try parseInt(usize, value);
            } else {
                return error.UnknownArgument;
            }
        } else {
            if (positional_arg_count != 0) {
                return error.UnknownArgument;
            }
            bench_args.total_threads = try parseInt(u16, arg);
            total_threads_overridden = true;
            positional_arg_count += 1;
        }
    }

    if (bench_args.pixels_num[0] == 0 or bench_args.pixels_num[1] == 0) {
        return error.InvalidPixelsNum;
    }
    if (bench_args.sub_sample == 0) {
        return error.InvalidSubSample;
    }
    if (bench_args.runs == 0) {
        return error.InvalidRuns;
    }

    if (total_threads_overridden and !max_geom_threads_overridden) {
        bench_args.max_geom_threads_per_frame = bench_args.total_threads;
    }
    if (total_threads_overridden and !max_raster_threads_overridden) {
        bench_args.max_raster_threads_per_frame =
            bench_args.total_threads;
    }

    return bench_args;
}

pub fn applyRasterConfig(
    base_config: rastcfg.RasterConfig,
    bench_args: BenchArgs,
) rastcfg.RasterConfig {
    var raster_config = base_config;
    raster_config.render_mode = bench_args.render_mode;
    raster_config.total_threads = bench_args.total_threads;
    raster_config.max_geom_workers_per_frame =
        bench_args.max_geom_threads_per_frame;
    raster_config.max_raster_workers_per_frame =
        bench_args.max_raster_threads_per_frame;
    raster_config.max_frames_in_flight =
        bench_args.max_frames_in_flight;
    raster_config.hull_mode = bench_args.hull_mode;
    raster_config.subpixel_center_map =
        bench_args.subpixel_center_map;
    raster_config.save_strategy = bench_args.save_strategy;
    return raster_config;
}

fn parseInt(comptime T: type, value: []const u8) !T {
    return std.fmt.parseInt(T, value, 10);
}

fn parseEnum(comptime T: type, value: []const u8) !T {
    return std.meta.stringToEnum(T, value) orelse error.InvalidEnumValue;
}

fn argToSlice(arg: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(arg))) {
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => arg,
            else => std.mem.span(arg),
        },
        .array => arg[0..],
        else => @compileError("Unsupported command line argument type."),
    };
}

test "parse bench args defaults" {
    const args = [_][]const u8{"bench_geom"};
    const raster_config = rastcfg.RasterConfig{
        .render_mode = .offline,
        .total_threads = 3,
        .max_frames_in_flight = 2,
        .max_geom_workers_per_frame = 2,
        .max_raster_workers_per_frame = 3,
        .hull_mode = .on_convex_fallback,
        .subpixel_center_map = .affine_jac,
    };
    const bench_args = try parseArgs(
        args[0..],
        "out/geom",
        raster_config,
    );

    try std.testing.expectEqual(
        defaultBenchArgs("out/geom", raster_config),
        bench_args,
    );
}

test "parse bench args named options" {
    const args = [_][]const u8{
        "bench_geom",
        "--render-mode",
        "offline",
        "--total-threads",
        "8",
        "--max-geom-threads-per-frame",
        "3",
        "--max-raster-threads-per-frame",
        "5",
        "--max-frames-in-flight",
        "2",
        "--hull-mode",
        "off",
        "--subpixel-center-map",
        "affine_jac",
        "--save-strategy",
        "memory",
        "--sample",
        "linear",
        "--sample-mode",
        "direct",
        "--out-dir",
        "out/custom",
        "--pixels-x",
        "1024",
        "--pixels-y",
        "768",
        "--sub-sample",
        "4",
        "--runs",
        "7",
    };
    const bench_args = try parseArgs(
        args[0..],
        "out/geom",
        rastcfg.RasterConfig{},
    );

    try std.testing.expectEqual(rastcfg.RenderMode.offline, bench_args.render_mode);
    try std.testing.expectEqual(@as(u16, 8), bench_args.total_threads);
    try std.testing.expectEqual(
        @as(u16, 3),
        bench_args.max_geom_threads_per_frame,
    );
    try std.testing.expectEqual(
        @as(u16, 5),
        bench_args.max_raster_threads_per_frame,
    );
    try std.testing.expectEqual(
        @as(u16, 2),
        bench_args.max_frames_in_flight,
    );
    try std.testing.expectEqual(rastcfg.HullMode.off, bench_args.hull_mode);
    try std.testing.expectEqual(
        rastcfg.SubPixelCenterMap.affine_jac,
        bench_args.subpixel_center_map,
    );
    try std.testing.expectEqual(
        rastcfg.SaveStrategy.memory,
        bench_args.save_strategy,
    );
    try std.testing.expectEqual(
        texops.TextureSample.linear,
        bench_args.sample.?,
    );
    try std.testing.expectEqual(
        texops.TextureSampleMode.direct,
        bench_args.sample_mode.?,
    );
    try std.testing.expectEqualStrings("out/custom", bench_args.out_dir);
    try std.testing.expectEqual([2]u32{ 1024, 768 }, bench_args.pixels_num);
    try std.testing.expectEqual(@as(u8, 4), bench_args.sub_sample);
    try std.testing.expectEqual(@as(usize, 7), bench_args.runs);
}

test "parse bench args legacy thread positional" {
    const args = [_][]const u8{ "bench_geom", "6" };
    const bench_args = try parseArgs(
        args[0..],
        "out/geom",
        rastcfg.RasterConfig{},
    );

    try std.testing.expectEqual(@as(u16, 6), bench_args.total_threads);
    try std.testing.expectEqual(
        @as(u16, 6),
        bench_args.max_geom_threads_per_frame,
    );
    try std.testing.expectEqual(
        @as(u16, 6),
        bench_args.max_raster_threads_per_frame,
    );
}
