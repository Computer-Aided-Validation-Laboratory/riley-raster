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

    var e2e_rows_by_run = try outer_alloc.alloc(
        []benchdicuq.DicuqE2ERow,
        bench_args.runs,
    );
    var e2e_rows_filled: usize = 0;
    defer {
        for (0..e2e_rows_filled) |rr| {
            outer_alloc.free(e2e_rows_by_run[rr]);
        }
        outer_alloc.free(e2e_rows_by_run);
    }

    for (0..bench_args.runs) |rr| {
        const out_dir_path = switch (bench_args.save_strategy) {
            .disk, .both => bench_args.out_dir,
            .memory, .none => null,
        };
        var run_result = try benchdicuq.runBenchmark(
            outer_alloc,
            io,
            &prepared_benchmark.camera_inputs,
            prepared_benchmark.mesh_input,
            raster_config,
            out_dir_path,
        );
        defer run_result.deinit(outer_alloc);

        for (run_result.frame_rows) |*frame_row| {
            frame_row.run_idx = rr;
        }
        for (run_result.e2e_rows) |*e2e_row| {
            e2e_row.run_idx = rr;
        }

        try benchdicuq.writeRunCSVs(
            outer_alloc,
            io,
            bench_args.out_dir,
            case_name,
            rr,
            prepared_benchmark.camera_inputs.len,
            run_result,
        );
        e2e_rows_by_run[rr] = try outer_alloc.dupe(
            benchdicuq.DicuqE2ERow,
            run_result.e2e_rows,
        );
        e2e_rows_filled += 1;
    }

    try benchdicuq.writeE2EOverRunsCSVs(
        outer_alloc,
        io,
        bench_args.out_dir,
        case_name,
        prepared_benchmark.camera_inputs.len,
        e2e_rows_by_run,
    );
}
