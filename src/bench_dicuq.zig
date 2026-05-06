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
const benchdicuq = @import("common/benchdicuq.zig");
const benchstats = @import("common/benchstats.zig");
const common = @import("common/benchcommon.zig");

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const io = init.io;

    const base_raster_config = benchdicuq.getBaseRasterConfig();

    const bench_args = try benchargs.parseArgs(
        init.minimal.args.vector,
        "out/dicuq",
        base_raster_config,
    );

    const sample_config = try benchdicuq.makeSampleConfig(bench_args);
    //base_raster_config.save_strategy = .disk;
    
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const prepared_benchmark = try benchdicuq.prepareBenchmark(
        aa,
        io,
        bench_args.pixels_num,
        bench_args.sub_sample,
        sample_config,
    );

    const raster_config = benchargs.applyRasterConfig(
        base_raster_config,
        bench_args,
    );
    const actual_tile_size = common.calcActualTileSize(
        raster_config,
        bench_args.pixels_num,
        bench_args.sub_sample,
    );
    try common.writeBenchmarkConfig(
        outer_alloc,
        io,
        bench_args.out_dir,
        "bench_dicuq.zig",
        init.minimal.args.vector,
        raster_config,
        bench_args.pixels_num,
        bench_args.sub_sample,
        bench_args.runs,
        prepared_benchmark.fov_scale,
        actual_tile_size,
    );

    const case_name = try benchdicuq.calcCaseName(outer_alloc, sample_config);
    defer outer_alloc.free(case_name);

    var stats = benchstats.BenchStatsCollector{};
    defer stats.deinit(outer_alloc);

    std.debug.print(
        "Starting DIC UQ Benchmark ({d}x{d}, {d} runs, {d} threads)...\n",
        .{
            bench_args.pixels_num[0],
            bench_args.pixels_num[1],
            bench_args.runs,
            bench_args.total_threads,
        },
    );
    std.debug.print("Case: {s}\n", .{case_name});

    var case_samples = try benchstats.CaseSamples.init(
        outer_alloc,
        bench_args.runs,
    );
    defer case_samples.deinit(outer_alloc);

    for (0..bench_args.runs) |rr| {
        const out_dir_path = switch (bench_args.save_strategy) {
            .disk, .both => bench_args.out_dir,
            .memory, .none => null,
        };
        var result = try benchdicuq.runBenchmark(
            outer_alloc,
            io,
            &prepared_benchmark.camera_inputs,
            prepared_benchmark.mesh_input,
            raster_config,
            out_dir_path,
        );
        defer result.deinit(outer_alloc);
        case_samples.record(rr, result);
    }

    try stats.appendCaseStats(
        outer_alloc,
        case_name,
        .quad8,
        .tex8_grey,
        sample_config,
        null,
        &case_samples,
    );

    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "DIC UQ Benchmark Results",
        bench_args.out_dir,
        bench_args.pixels_num,
        stats.stats_list.items,
        stats.max_name_len,
    );
}
