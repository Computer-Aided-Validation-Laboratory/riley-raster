// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const benchargs = @import("common/benchargs.zig");
const common = @import("common/benchcommon.zig");
const tcfg = @import("common/testconfig.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;
    const bench_args = try benchargs.parseArgs(
        init.minimal.args.vector,
    );

    const texture_grey = try iio.loadImage(
        u8,
        1,
        outer_alloc,
        io,
        "texture/speckle.bmp",
        .bmp,
    );
    defer texture_grey.deinit(outer_alloc);
    const texture_rgb = try iio.loadImage(
        u8,
        3,
        outer_alloc,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );
    defer texture_rgb.deinit(outer_alloc);

    const out_dir_base = "out/sphere2000";

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };

    var stats_list: std.ArrayList(common.BenchStats) = .empty;
    defer {
        for (stats_list.items) |s| outer_alloc.free(s.name);
        stats_list.deinit(outer_alloc);
    }

    var max_name_len: usize = 0;

    std.debug.print(
        "Starting Sphere 2000 Benchmark ({d}x{d}, {d} runs per case, {d} threads)...\n",
        .{
            bench_args.pixels_num[0],
            bench_args.pixels_num[1],
            bench_args.runs,
            bench_args.total_threads,
        },
    );

    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (sample_configs) |sc| {
                var case_name_buf: [256]u8 = undefined;
                const case_name =
                    if (st == .tex8_grey or st == .tex8_rgb)
                        try std.fmt.bufPrint(
                            &case_name_buf,
                            "{s}_{s}_{s}_{s}",
                            .{
                                @tagName(mt),
                                @tagName(st),
                                @tagName(sc.sample),
                                @tagName(sc.mode),
                            },
                        )
                    else
                        try std.fmt.bufPrint(
                            &case_name_buf,
                            "{s}_{s}",
                            .{ @tagName(mt), @tagName(st) },
                        );
                std.debug.print("Case: {s}\n", .{case_name});

                if (case_name.len > max_name_len) {
                    max_name_len = case_name.len;
                }

                var e2e_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(e2e_times);
                var geom_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(geom_times);
                var raster_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(raster_times);
                var fps_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(fps_vals);

                var mpx_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(mpx_vals);
                var msubpx_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(msubpx_vals);
                var mshades_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(mshades_vals);
                var msubshades_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(msubshades_vals);
                var melems_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(melems_vals);
                var mnodes_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(mnodes_vals);
                var mops_vals = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(mops_vals);

                var geom_prep_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(geom_prep_times);
                var tile_overlap_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(tile_overlap_times);
                var raster_loop_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(raster_loop_times);
                var save_frame_times = try outer_alloc.alloc(
                    f64,
                    bench_args.runs,
                );
                defer outer_alloc.free(save_frame_times);

                var data_dir_buf: [256]u8 = undefined;
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf,
                    "data/bench/{s}_sphere2000",
                    .{@tagName(mt)},
                );
                for (0..bench_args.runs) |rr| {
                    const run_out_dir_base =
                        switch (bench_args.save_strategy) {
                            .disk, .both => out_dir_base,
                            .memory, .none => "",
                        };
                    const raster_config =
                        benchargs.applyRasterConfig(
                            tcfg.getRasterConfig(.bench),
                            bench_args,
                        );

                    var res = try common.runBenchmark(
                        outer_alloc,
                        io,
                        mt,
                        st,
                        sc,
                        data_dir,
                        bench_args.pixels_num,
                        bench_args.sub_sample,
                        texture_grey,
                        texture_rgb,
                        raster_config,
                        run_out_dir_base,
                        1.0,
                    );
                    defer res.deinit(outer_alloc);

                    e2e_times[rr] = res.e2e_ms;
                    geom_times[rr] = res.geom_ms;
                    raster_times[rr] = res.raster_ms;
                    fps_vals[rr] = res.fps;

                    mpx_vals[rr] = res.metrics.mpx_sec;
                    msubpx_vals[rr] = res.metrics.msubpx_sec;
                    mshades_vals[rr] = res.metrics.mshades_sec;
                    msubshades_vals[rr] = res.metrics.msubshades_sec;
                    melems_vals[rr] = res.metrics.melems_sec;
                    mnodes_vals[rr] = res.metrics.mnodes_sec;
                    mops_vals[rr] = res.metrics.mops_sec;

                    const conv_ms = 1.0 / 1e6;
                    geom_prep_times[rr] =
                        res.pipeline_times.geometry_prep * conv_ms;
                    tile_overlap_times[rr] =
                        res.pipeline_times.tile_overlap * conv_ms;
                    raster_loop_times[rr] =
                        res.pipeline_times.raster_loop * conv_ms;
                    save_frame_times[rr] =
                        res.pipeline_times.save_frame * conv_ms;
                }

                try stats_list.append(outer_alloc, .{
                    .name = try outer_alloc.dupe(u8, case_name),
                    .mesh_type = mt,
                    .shader_type = st,
                    .sample_config = sc,
                    .e2e = try common.calcMedianMAD(outer_alloc, e2e_times),
                    .geom = try common.calcMedianMAD(outer_alloc, geom_times),
                    .raster = try common.calcMedianMAD(outer_alloc, raster_times),
                    .fps = try common.calcMedianMAD(outer_alloc, fps_vals),
                    .mpx = try common.calcMedianMAD(outer_alloc, mpx_vals),
                    .msubpx = try common.calcMedianMAD(outer_alloc, msubpx_vals),
                    .mshades = try common.calcMedianMAD(outer_alloc, mshades_vals),
                    .msubshades = try common.calcMedianMAD(
                        outer_alloc,
                        msubshades_vals,
                    ),
                    .melems = try common.calcMedianMAD(outer_alloc, melems_vals),
                    .mnodes = try common.calcMedianMAD(outer_alloc, mnodes_vals),
                    .mops = try common.calcMedianMAD(outer_alloc, mops_vals),
                    .geom_prep = try common.calcMedianMAD(
                        outer_alloc,
                        geom_prep_times,
                    ),
                    .tile_overlap = try common.calcMedianMAD(
                        outer_alloc,
                        tile_overlap_times,
                    ),
                    .raster_loop = try common.calcMedianMAD(
                        outer_alloc,
                        raster_loop_times,
                    ),
                    .save_frame = try common.calcMedianMAD(
                        outer_alloc,
                        save_frame_times,
                    ),
                });
            }
        }
    }

    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "Sphere 2000 Benchmark Results",
        out_dir_base,
        bench_args.pixels_num,
        stats_list.items,
        max_name_len,
    );
}
