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
const benchstats = @import("common/benchstats.zig");
const common = @import("common/benchcommon.zig");
const tcfg = @import("common/testconfig.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const iio = @import("zraster/zig/imageio.zig");
const texops = @import("zraster/zig/textureops.zig");

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    var base_raster_config = tcfg.getRasterConfig(.bench);
    base_raster_config.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };

    const bench_args = try benchargs.parseArgs(
        init.minimal.args.vector,
        "out/sphere2000",
        base_raster_config,
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

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = [_]common.ShaderType{
        .nodal_grey,
        .nodal_rgb,
        .tex8_grey,
        .tex8_rgb,
    };
    const tex_func_shader_types = [_]common.ShaderType{
        .texfunc_grey,
        .texfunc_rgb,
    };
    const sample_configs = [_]texops.TextureSampleConfig{
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const tex_func_cases = [_]common.TexFuncCase{
        .{ .builtin = .constant, .coord_mode = .param },
        .{ .builtin = .constant, .coord_mode = .uv },
        .{ .builtin = .sinusoidal, .coord_mode = .param },
        .{ .builtin = .sinusoidal, .coord_mode = .uv },
    };

    var stats = try benchstats.BenchStatsCollector.init(
        outer_alloc,
        bench_args.runs,
    );
    defer stats.deinit(outer_alloc);

    std.debug.print(
        "Starting Sphere 2000 Benchmark ({d}x{d}, {d} runs per case, {d} threads)...\n",
        .{
            bench_args.pixels_num[0],
            bench_args.pixels_num[1],
            bench_args.runs,
            bench_args.total_threads,
        },
    );

    const bench_raster_config = benchargs.applyRasterConfig(
        base_raster_config,
        bench_args,
    );
    const actual_tile_size = common.calcActualTileSize(
        bench_raster_config,
        bench_args.pixels_num,
        bench_args.sub_sample,
    );
    try common.writeBenchmarkConfig(
        outer_alloc,
        io,
        bench_args.out_dir,
        "bench_sphere2000.zig",
        init.minimal.args.vector,
        bench_raster_config,
        bench_args.pixels_num,
        bench_args.sub_sample,
        bench_args.runs,
        1.0,
        actual_tile_size,
    );

    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (sample_configs) |sc| {
                const sample_config = if (st == .tex8_grey or st == .tex8_rgb) sc else null;
                const case_name = try common.calcCaseName(
                    outer_alloc,
                    mt,
                    st,
                    sample_config,
                    null,
                    1.0,
                );
                defer outer_alloc.free(case_name);
                std.debug.print("Case: {s}\n", .{case_name});

                var case_samples = try benchstats.CaseSamples.init(
                    outer_alloc,
                    bench_args.runs,
                );
                defer case_samples.deinit(outer_alloc);

                var data_dir_buf: [256]u8 = undefined;
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf,
                    "data/bench/{s}_sphere2000",
                    .{@tagName(mt)},
                );
                for (0..bench_args.runs) |rr| {
                    const run_out_dir_base =
                        switch (bench_args.save_strategy) {
                            .disk, .both => bench_args.out_dir,
                            .memory, .none => "",
                        };
                    const raster_config =
                        benchargs.applyRasterConfig(
                            base_raster_config,
                            bench_args,
                        );

                    var res = try common.runBenchmark(
                        outer_alloc,
                        io,
                        mt,
                        st,
                        sample_config,
                        null,
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

                    try stats.appendRunResult(
                        outer_alloc,
                        rr,
                        case_name,
                        mt,
                        st,
                        sample_config,
                        null,
                        res,
                    );
                    case_samples.record(rr, res);
                }

                try stats.appendCaseStats(
                    outer_alloc,
                    case_name,
                    mt,
                    st,
                    sample_config,
                    null,
                    &case_samples,
                );
            }
        }

        for (tex_func_shader_types) |st| {
            for (tex_func_cases) |tex_func_case| {
                const case_name = try common.calcCaseName(
                    outer_alloc,
                    mt,
                    st,
                    null,
                    tex_func_case,
                    1.0,
                );
                defer outer_alloc.free(case_name);
                std.debug.print("Case: {s}\n", .{case_name});

                var case_samples = try benchstats.CaseSamples.init(
                    outer_alloc,
                    bench_args.runs,
                );
                defer case_samples.deinit(outer_alloc);

                var data_dir_buf: [256]u8 = undefined;
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf,
                    "data/bench/{s}_sphere2000",
                    .{@tagName(mt)},
                );
                for (0..bench_args.runs) |rr| {
                    const run_out_dir_base =
                        switch (bench_args.save_strategy) {
                            .disk, .both => bench_args.out_dir,
                            .memory, .none => "",
                        };
                    const raster_config =
                        benchargs.applyRasterConfig(
                            base_raster_config,
                            bench_args,
                        );

                    var res = try common.runBenchmark(
                        outer_alloc,
                        io,
                        mt,
                        st,
                        null,
                        tex_func_case,
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

                    try stats.appendRunResult(
                        outer_alloc,
                        rr,
                        case_name,
                        mt,
                        st,
                        null,
                        tex_func_case,
                        res,
                    );
                    case_samples.record(rr, res);
                }

                try stats.appendCaseStats(
                    outer_alloc,
                    case_name,
                    mt,
                    st,
                    null,
                    tex_func_case,
                    &case_samples,
                );
            }
        }
    }

    try stats.writeRunCSVs(outer_alloc, io, bench_args.out_dir);
    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "Sphere 2000 Benchmark Results",
        bench_args.out_dir,
        bench_args.pixels_num,
        stats.stats_list.items,
        0,
    );
}
