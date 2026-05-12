// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const common = @import("benchcommon.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const texops = @import("../zraster/zig/textureops.zig");

pub const CaseSamples = struct {
    e2e_times: []f64,
    geom_times: []f64,
    raster_times: []f64,
    fps_vals: []f64,
    mpx_vals: []f64,
    msubpx_vals: []f64,
    mshades_vals: []f64,
    msubshades_vals: []f64,
    melems_vals: []f64,
    mnodes_vals: []f64,
    mops_vals: []f64,
    geom_prep_times: []f64,
    tile_overlap_times: []f64,
    raster_loop_times: []f64,
    save_frame_times: []f64,

    pub fn init(
        allocator: std.mem.Allocator,
        runs: usize,
    ) !CaseSamples {
        return .{
            .e2e_times = try allocator.alloc(f64, runs),
            .geom_times = try allocator.alloc(f64, runs),
            .raster_times = try allocator.alloc(f64, runs),
            .fps_vals = try allocator.alloc(f64, runs),
            .mpx_vals = try allocator.alloc(f64, runs),
            .msubpx_vals = try allocator.alloc(f64, runs),
            .mshades_vals = try allocator.alloc(f64, runs),
            .msubshades_vals = try allocator.alloc(f64, runs),
            .melems_vals = try allocator.alloc(f64, runs),
            .mnodes_vals = try allocator.alloc(f64, runs),
            .mops_vals = try allocator.alloc(f64, runs),
            .geom_prep_times = try allocator.alloc(f64, runs),
            .tile_overlap_times = try allocator.alloc(f64, runs),
            .raster_loop_times = try allocator.alloc(f64, runs),
            .save_frame_times = try allocator.alloc(f64, runs),
        };
    }

    pub fn deinit(
        self: *const CaseSamples,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.e2e_times);
        allocator.free(self.geom_times);
        allocator.free(self.raster_times);
        allocator.free(self.fps_vals);
        allocator.free(self.mpx_vals);
        allocator.free(self.msubpx_vals);
        allocator.free(self.mshades_vals);
        allocator.free(self.msubshades_vals);
        allocator.free(self.melems_vals);
        allocator.free(self.mnodes_vals);
        allocator.free(self.mops_vals);
        allocator.free(self.geom_prep_times);
        allocator.free(self.tile_overlap_times);
        allocator.free(self.raster_loop_times);
        allocator.free(self.save_frame_times);
    }

    pub fn record(
        self: *CaseSamples,
        rr: usize,
        result: common.BenchResult,
    ) void {
        self.e2e_times[rr] = result.e2e_ms;
        self.geom_times[rr] = result.geom_ms;
        self.raster_times[rr] = result.raster_ms;
        self.fps_vals[rr] = result.fps;

        self.mpx_vals[rr] = result.metrics.mpx_sec;
        self.msubpx_vals[rr] = result.metrics.msubpx_sec;
        self.mshades_vals[rr] = result.metrics.mshades_sec;
        self.msubshades_vals[rr] = result.metrics.msubshades_sec;
        self.melems_vals[rr] = result.metrics.melems_sec;
        self.mnodes_vals[rr] = result.metrics.mnodes_sec;
        self.mops_vals[rr] = result.metrics.mops_sec;

        const conv_ms = 1.0 / 1e6;
        self.geom_prep_times[rr] =
            result.pipeline_times.geometry_prep * conv_ms;
        self.tile_overlap_times[rr] =
            result.pipeline_times.tile_overlap * conv_ms;
        self.raster_loop_times[rr] =
            result.pipeline_times.raster_loop * conv_ms;
        self.save_frame_times[rr] =
            result.pipeline_times.save_frame * conv_ms;
    }

    pub fn toBenchStats(
        self: *const CaseSamples,
        allocator: std.mem.Allocator,
        case_name: []const u8,
        mesh_type: gk.MeshType,
        shader_type: common.ShaderType,
        sample_config: ?texops.TextureSampleConfig,
        tex_func_case: ?common.TexFuncCase,
    ) !common.BenchStats {
        return .{
            .name = try allocator.dupe(u8, case_name),
            .mesh_type = mesh_type,
            .shader_type = shader_type,
            .sample_config = sample_config,
            .tex_func_case = tex_func_case,
            .e2e = try common.calcMedianMAD(allocator, self.e2e_times),
            .geom = try common.calcMedianMAD(allocator, self.geom_times),
            .raster = try common.calcMedianMAD(allocator, self.raster_times),
            .fps = try common.calcMedianMAD(allocator, self.fps_vals),
            .mpx = try common.calcMedianMAD(allocator, self.mpx_vals),
            .msubpx = try common.calcMedianMAD(allocator, self.msubpx_vals),
            .mshades = try common.calcMedianMAD(
                allocator,
                self.mshades_vals,
            ),
            .msubshades = try common.calcMedianMAD(
                allocator,
                self.msubshades_vals,
            ),
            .melems = try common.calcMedianMAD(allocator, self.melems_vals),
            .mnodes = try common.calcMedianMAD(allocator, self.mnodes_vals),
            .mops = try common.calcMedianMAD(allocator, self.mops_vals),
            .geom_prep = try common.calcMedianMAD(
                allocator,
                self.geom_prep_times,
            ),
            .tile_overlap = try common.calcMedianMAD(
                allocator,
                self.tile_overlap_times,
            ),
            .raster_loop = try common.calcMedianMAD(
                allocator,
                self.raster_loop_times,
            ),
            .save_frame = try common.calcMedianMAD(
                allocator,
                self.save_frame_times,
            ),
        };
    }
};

pub const BenchStatsCollector = struct {
    stats_list: std.ArrayList(common.BenchStats) = .empty,
    run_csv_rows: []std.ArrayList(u8) = &.{},

    pub fn init(
        allocator: std.mem.Allocator,
        runs: usize,
    ) !BenchStatsCollector {
        const run_csv_rows = try allocator.alloc(std.ArrayList(u8), runs);
        for (0..runs) |rr| {
            run_csv_rows[rr] = .empty;
            try run_csv_rows[rr].appendSlice(
                allocator,
                common.benchmarkCSVHeader(),
            );
        }
        return .{
            .run_csv_rows = run_csv_rows,
        };
    }

    pub fn deinit(
        self: *BenchStatsCollector,
        allocator: std.mem.Allocator,
    ) void {
        for (self.stats_list.items) |stats| {
            allocator.free(stats.name);
        }
        self.stats_list.deinit(allocator);
        for (self.run_csv_rows) |*rows| {
            rows.deinit(allocator);
        }
        if (self.run_csv_rows.len > 0) {
            allocator.free(self.run_csv_rows);
        }
    }

    pub fn appendRunResult(
        self: *BenchStatsCollector,
        allocator: std.mem.Allocator,
        run_idx: usize,
        case_name: []const u8,
        mesh_type: gk.MeshType,
        shader_type: common.ShaderType,
        sample_config: ?texops.TextureSampleConfig,
        tex_func_case: ?common.TexFuncCase,
        result: common.BenchResult,
    ) !void {
        const row = try common.formatBenchmarkCSVRow(
            allocator,
            case_name,
            mesh_type,
            shader_type,
            sample_config,
            tex_func_case,
            common.calcBenchmarkCSVValuesFromResult(result),
        );
        defer allocator.free(row);
        try self.run_csv_rows[run_idx].appendSlice(allocator, row);
    }

    pub fn appendCaseStats(
        self: *BenchStatsCollector,
        allocator: std.mem.Allocator,
        case_name: []const u8,
        mesh_type: gk.MeshType,
        shader_type: common.ShaderType,
        sample_config: ?texops.TextureSampleConfig,
        tex_func_case: ?common.TexFuncCase,
        case_samples: *const CaseSamples,
    ) !void {
        try self.stats_list.append(
            allocator,
            try case_samples.toBenchStats(
                allocator,
                case_name,
                mesh_type,
                shader_type,
                sample_config,
                tex_func_case,
            ),
        );
    }

    pub fn writeRunCSVs(
        self: *const BenchStatsCollector,
        allocator: std.mem.Allocator,
        io: std.Io,
        out_dir_base: []const u8,
    ) !void {
        const cwd = std.Io.Dir.cwd();
        cwd.createDir(
            io,
            out_dir_base,
            .default_dir,
        ) catch |err| if (err != error.PathAlreadyExists) return err;

        for (self.run_csv_rows, 0..) |rows, rr| {
            const file_name = try std.fmt.allocPrint(
                allocator,
                "bench_run{d}.csv",
                .{rr},
            );
            defer allocator.free(file_name);

            const csv_path = try std.fs.path.join(
                allocator,
                &[_][]const u8{ out_dir_base, file_name },
            );
            defer allocator.free(csv_path);

            var file = try cwd.createFile(io, csv_path, .{});
            defer file.close(io);

            var write_buf: [4096]u8 = undefined;
            var buffered_writer = file.writer(io, &write_buf);
            try buffered_writer.interface.writeAll(rows.items);
            try buffered_writer.interface.flush();
        }
    }
};
