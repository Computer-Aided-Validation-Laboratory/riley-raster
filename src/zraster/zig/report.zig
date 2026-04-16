// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const ImageFormat = @import("imageio.zig").ImageFormat;
const iio = @import("imageio.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const Camera = @import("camera.zig").Camera;

pub const ReportMode = enum {
    off,
    bench,
    full_stats,
};

pub const OffLog = struct {};

pub const FullStatsOpts = struct {
    formats: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
        .{ .format = .csv, .bits = null, .scaling = .none },
    },
    save_iteration_map: bool = true,
    save_tile_timing_map: bool = true,
    save_tile_density_map: bool = true,
    save_tile_occupancy_map: bool = true,
    save_depth_map: bool = true,
    save_earlyout_map: bool = true,
    save_pixel_occupancy_map: bool = true,
    save_normals_map: bool = false,
};

pub const PipeTimes = struct {
    geometry_prep: f64 = 0,
    tile_overlap: f64 = 0,
    raster_loop: f64 = 0,
    total_time: f64 = 0,
};

pub const BenchLog = struct {
    pipe_times: PipeTimes = .{},
    total_elements: usize = 0,
    visible_elements: usize = 0,
    solver_calls: u64 = 0,
    total_solver_iters: u64 = 0,
    solver_diverged: u64 = 0,
    tess_checks: u64 = 0,
    tess_passes: u64 = 0,
    total_shaded_pixels: u64 = 0,
    total_depth_tests: u64 = 0,
    depth_tests_failed: u64 = 0,
    max_tile_elements: usize = 0,
};

pub const FullStatsLog = struct {
    bench: BenchLog = .{},
    iteration_map: ?NDArray(f64) = null,
    pixel_occupancy_map: ?NDArray(f64) = null,
    depth_map: ?NDArray(f64) = null,
    normals_map: ?NDArray(f64) = null,
    earlyout_map: ?NDArray(f64) = null,
    tile_timing_map: ?NDArray(f64) = null,
    tile_density_map: ?NDArray(f64) = null,
    tile_occupancy_map: ?NDArray(f64) = null,

    pub fn deinit(self: *FullStatsLog, allocator: std.mem.Allocator) void {
        if (self.iteration_map) |*imap| imap.deinit(allocator);
        if (self.pixel_occupancy_map) |*pomap| pomap.deinit(allocator);
        if (self.depth_map) |*dmap| dmap.deinit(allocator);
        if (self.normals_map) |*nmap| nmap.deinit(allocator);
        if (self.earlyout_map) |*emap| emap.deinit(allocator);
        if (self.tile_timing_map) |*tmap| tmap.deinit(allocator);
        if (self.tile_density_map) |*dmap| dmap.deinit(allocator);
        if (self.tile_occupancy_map) |*omap| omap.deinit(allocator);
    }

    fn saveTileMapAsImage(
        io: std.Io,
        allocator: std.mem.Allocator,
        save_dir: std.Io.Dir,
        camera: *const Camera,
        tile_size: u16,
        tile_data: []const f64,
        name_prefix: []const u8,
        opts: FullStatsOpts,
    ) !void {
        const px_x = camera.pixels_num[0];
        const px_y = camera.pixels_num[1];
        const tiles_x = try std.math.divCeil(u32, px_x, tile_size);

        var expanded = try NDArray(f64).initFlat(allocator, &[_]usize{ px_y, px_x });
        defer expanded.deinit(allocator);

        for (0..px_y) |yy| {
            const tile_y = yy / tile_size;
            for (0..px_x) |xx| {
                const tile_x = xx / tile_size;
                const tile_idx = tile_y * tiles_x + tile_x;
                expanded.slice[yy * px_x + xx] = tile_data[tile_idx];
            }
        }

        const mat = MatSlice(f64).init(expanded.slice, px_y, px_x);
        for (opts.formats) |opt| {
            try iio.saveMatAsImage(io, save_dir, name_prefix, &mat, opt);
        }
    }

    pub fn saveFrameReport(
        self: *const FullStatsLog,
        io: std.Io,
        allocator: std.mem.Allocator,
        out_dir: ?std.Io.Dir,
        frame_idx: usize,
        camera: *const Camera,
        tile_size: u16,
        opts: FullStatsOpts,
        nodes_per_elem: f64,
    ) !void {
        const save_dir = out_dir orelse return;

        var name_buff: [1024]u8 = undefined;
        const stats_file_name = try std.fmt.bufPrint(
            name_buff[0..],
            "report_stats_frame{d}.txt",
            .{frame_idx},
        );

        var stats_file = try save_dir.createFile(io, stats_file_name, .{});
        defer stats_file.close(io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = stats_file.writer(io, &write_buf);
        try self.writeReport(&file_writer.interface, frame_idx, camera, nodes_per_elem);
        try self.fullReport(io, frame_idx, camera, nodes_per_elem);

        if (self.iteration_map) |*m| {
            const sub_samp: usize = @intCast(camera.sub_sample);
            const mat = MatSlice(f64).init(
                m.slice,
                camera.pixels_num[1] * sub_samp,
                camera.pixels_num[0] * sub_samp,
            );
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_iters",
                .{frame_idx},
            );
            for (opts.formats) |opt| {
                try iio.saveMatAsImage(io, save_dir, name, &mat, opt);
            }
        }

        if (self.pixel_occupancy_map) |*m| {
            const mat = MatSlice(f64).init(
                m.slice,
                camera.pixels_num[1],
                camera.pixels_num[0],
            );
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_occupancy",
                .{frame_idx},
            );
            for (opts.formats) |opt| {
                try iio.saveMatAsImage(io, save_dir, name, &mat, opt);
            }
        }

        if (self.depth_map) |*m| {
            const sub_samp: usize = @intCast(camera.sub_sample);
            const mat = MatSlice(f64).init(
                m.slice,
                camera.pixels_num[1] * sub_samp,
                camera.pixels_num[0] * sub_samp,
            );
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_depth",
                .{frame_idx},
            );
            for (opts.formats) |opt| {
                try iio.saveMatAsImage(io, save_dir, name, &mat, opt);
            }
        }

        if (self.normals_map) |*m| {
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_normals",
                .{frame_idx},
            );
            for (opts.formats) |opt| {
                var save_opt = opt;
                save_opt.channels = 3;
                try iio.saveImage(io, save_dir, name, m, 0, save_opt);
            }
        }

        if (self.earlyout_map) |*m| {
            const sub_samp: usize = @intCast(camera.sub_sample);
            const mat = MatSlice(f64).init(
                m.slice,
                camera.pixels_num[1] * sub_samp,
                camera.pixels_num[0] * sub_samp,
            );
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_earlyout",
                .{frame_idx},
            );
            for (opts.formats) |opt| {
                try iio.saveMatAsImage(io, save_dir, name, &mat, opt);
            }
        }

        if (self.tile_timing_map) |*m| {
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_tile_timing",
                .{frame_idx},
            );
            try saveTileMapAsImage(
                io,
                allocator,
                save_dir,
                camera,
                tile_size,
                m.slice,
                name,
                opts,
            );
        }

        if (self.tile_density_map) |*m| {
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_tile_density",
                .{frame_idx},
            );
            try saveTileMapAsImage(
                io,
                allocator,
                save_dir,
                camera,
                tile_size,
                m.slice,
                name,
                opts,
            );
        }

        if (self.tile_occupancy_map) |*m| {
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "diag_frame_{d}_tile_occupancy",
                .{frame_idx},
            );
            try saveTileMapAsImage(
                io,
                allocator,
                save_dir,
                camera,
                tile_size,
                m.slice,
                name,
                opts,
            );
        }
    }

    pub fn fullReport(
        self: *const FullStatsLog,
        io: std.Io,
        frame_idx: usize,
        camera: *const Camera,
        nodes_per_elem: f64,
    ) !void {
        var buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &buffer);
        const writer = &stderr_writer.interface;
        try self.writeReport(writer, frame_idx, camera, nodes_per_elem);
    }

    pub fn writeReport(
        self: *const FullStatsLog,
        writer: anytype,
        frame_idx: usize,
        camera: *const Camera,
        nodes_per_elem: f64,
    ) !void {
        const total_ms = self.bench.pipe_times.total_time / 1e6;
        const total_sec = self.bench.pipe_times.total_time / 1e9;
        const raster_sec = self.bench.pipe_times.raster_loop / 1e9;
        const geom_tiling_sec =
            (self.bench.pipe_times.geometry_prep + self.bench.pipe_times.tile_overlap) /
            1e9;

        const border = [_]u8{'='} ** 80 ++ "\n";
        const line = [_]u8{'-'} ** 80 ++ "\n";

        try writer.print("{s}", .{border});
        try writer.print("SOFTWARE RASTER REPORT - FRAME {d}\n", .{frame_idx});
        try writer.print("{s}\n", .{border});

        try writer.print("--- GEOMETRY PIPELINE ---\n", .{});
        try writer.print("Total Elements in Mesh  = {d}\n", .{self.bench.total_elements});
        try writer.print(
            "Elements after Crop     = {d}\n",
            .{self.bench.visible_elements},
        );
        const cropped = self.bench.total_elements - self.bench.visible_elements;
        const crop_pct = if (self.bench.total_elements > 0)
            @as(f64, @floatFromInt(cropped)) * 100.0 /
                @as(f64, @floatFromInt(self.bench.total_elements))
        else
            0.0;
        try writer.print(
            "Elements Cropped        = {d} ({d:.2}%)\n\n",
            .{ cropped, crop_pct },
        );

        const solver_calls_f = @as(f64, @floatFromInt(self.bench.solver_calls));
        const solver_diverged_f = @as(f64, @floatFromInt(self.bench.solver_diverged));
        const solver_converged = self.bench.solver_calls - self.bench.solver_diverged;
        const solver_converged_f = @as(f64, @floatFromInt(solver_converged));
        const solver_converged_pct = if (self.bench.solver_calls > 0)
            solver_converged_f * 100.0 / solver_calls_f
        else
            0.0;
        const solver_diverged_pct = if (self.bench.solver_calls > 0)
            solver_diverged_f * 100.0 / solver_calls_f
        else
            0.0;
        const avg_iters_per_call = if (self.bench.solver_calls > 0)
            @as(f64, @floatFromInt(self.bench.total_solver_iters)) / solver_calls_f
        else
            0.0;

        const px_x = @as(f64, @floatFromInt(camera.pixels_num[0]));
        const px_y = @as(f64, @floatFromInt(camera.pixels_num[1]));
        const sub_samp_f = @as(f64, @floatFromInt(camera.sub_sample));
        const total_px = px_x * px_y;
        const total_subpx = total_px * sub_samp_f * sub_samp_f;

        const tess_checks_f = @as(f64, @floatFromInt(self.bench.tess_checks));
        const tess_passes_f = @as(f64, @floatFromInt(self.bench.tess_passes));
        const solver_coverage_pct = if (total_subpx > 0)
            solver_calls_f * 100.0 / total_subpx
        else
            0.0;
        const tess_coverage_pct = if (total_subpx > 0)
            tess_checks_f * 100.0 / total_subpx
        else
            0.0;
        const tess_pass_pct = if (self.bench.tess_checks > 0)
            tess_passes_f * 100.0 / tess_checks_f
        else
            0.0;

        try writer.print("--- SOLVER & TESSELLATION STATS ---\n", .{});
        try writer.print("Total Solver Calls      = {d}\n", .{self.bench.solver_calls});
        try writer.print("Avg Iters / Solver Call = {d:.2}\n", .{avg_iters_per_call});
        try writer.print("Converged %             = {d:.2}%\n", .{solver_converged_pct});
        try writer.print("Diverged/Failed %       = {d:.2}%\n", .{solver_diverged_pct});
        try writer.print(
            "Solver Diverged/Failed  = {d}\n",
            .{self.bench.solver_diverged},
        );
        try writer.print("Solver Coverage %       = {d:.2}%\n", .{solver_coverage_pct});
        try writer.print("Tessellation Checks     = {d}\n", .{self.bench.tess_checks});
        try writer.print("Tessellation Coverage % = {d:.2}%\n", .{tess_coverage_pct});
        try writer.print("Tessellation Pass %     = {d:.2}%\n", .{tess_pass_pct});
        try writer.print("{s}", .{line});

        if (self.iteration_map) |*imap| {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const stats = try calcStats(allocator, imap.slice);
            try writer.print("Min Iterations          = {d}\n", .{stats.min});
            try writer.print("Max Iterations          = {d}\n", .{stats.max});
            try writer.print("Median Iterations       = {d:.2}\n", .{stats.median});
            try writer.print("Lower Quartile (Q1)     = {d:.2}\n", .{stats.q1});
            try writer.print("Upper Quartile (Q3)     = {d:.2}\n", .{stats.q3});
            try writer.print("Median Abs. Dev (MAD)   = {d:.2}\n\n", .{stats.mad});
        } else {
            try writer.print("No iteration map data available.\n\n", .{});
        }

        try writer.print("--- TILING & RASTERIZATION ---\n", .{});
        try writer.print(
            "Total Shaded Pixels     = {d}\n",
            .{self.bench.total_shaded_pixels},
        );
        try writer.print(
            "Max Elements in a Tile  = {d}\n",
            .{self.bench.max_tile_elements},
        );
        try writer.print(
            "Total Depth Tests       = {d}\n",
            .{self.bench.total_depth_tests},
        );
        const d_fail_pct = if (self.bench.total_depth_tests > 0)
            @as(f64, @floatFromInt(self.bench.depth_tests_failed)) * 100.0 /
                @as(f64, @floatFromInt(self.bench.total_depth_tests))
        else
            0.0;
        try writer.print("Depth Tests Failed      = {d} ({d:.2}%)\n", .{
            self.bench.depth_tests_failed,
            d_fail_pct,
        });
        try writer.print("{s}", .{line});

        const vis_elems_f = @as(f64, @floatFromInt(self.bench.visible_elements));
        const total_elems_f = @as(f64, @floatFromInt(self.bench.total_elements));
        const vis_pct = if (self.bench.total_elements > 0)
            (vis_elems_f * 100.0 / total_elems_f)
        else
            0;
        const shaded_subpx = @as(f64, @floatFromInt(self.bench.total_shaded_pixels));
        const shaded_pct = if (total_subpx > 0)
            (shaded_subpx * 100.0 / total_subpx)
        else
            0;

        try writer.print(
            "Visible Elems           = {d}\n",
            .{self.bench.visible_elements},
        );
        try writer.print("Total Elems             = {d}\n", .{self.bench.total_elements});
        try writer.print("Visible %               = {d:.2}%\n", .{vis_pct});
        try writer.print("Total SubPx             = {d:.0}\n", .{total_subpx});
        try writer.print("Shaded SubPx            = {d:.0}\n", .{shaded_subpx});
        try writer.print("Shaded %                = {d:.2}%\n\n", .{shaded_pct});

        try writer.print("--- PIPELINE TIMINGS (User Summary) ---\n", .{});
        const conv = 1.0 / 1e6;
        try writer.print("Geometry Preparation    = {d:.6} ms\n", .{
            self.bench.pipe_times.geometry_prep * conv,
        });
        try writer.print("Elem/Tile Overlap       = {d:.6} ms\n", .{
            self.bench.pipe_times.tile_overlap * conv,
        });
        try writer.print("Raster loop time        = {d:.6} ms\n", .{
            self.bench.pipe_times.raster_loop * conv,
        });
        try writer.print("{s}", .{line});
        try writer.print("TOTAL RASTER TIME       = {d:.3} ms\n", .{total_ms});
        try writer.print("{s}", .{line});

        const melems_sec = if (geom_tiling_sec > 0)
            (@as(f64, @floatFromInt(self.bench.total_elements)) / (geom_tiling_sec * 1e6))
        else
            0;
        const mpx_sec = if (raster_sec > 0) (total_px / (raster_sec * 1e6)) else 0;
        const msubpx_sec = if (raster_sec > 0) (total_subpx / (raster_sec * 1e6)) else 0;
        const mops_sec = if (total_sec > 0)
            (nodes_per_elem * total_subpx / (total_sec * 1e6))
        else
            0;

        try writer.print("MElem/second            = {d:.2}\n", .{melems_sec});
        try writer.print("MPx/second              = {d:.2}\n", .{mpx_sec});
        try writer.print("MsubPx/second           = {d:.2}\n", .{msubpx_sec});
        try writer.print("MOps/second             = {d:.2}\n", .{mops_sec});
        try writer.print("{s}", .{border});
        try writer.flush();
    }
};

pub const ReportLog = union(ReportMode) {
    off: OffLog,
    bench: BenchLog,
    full_stats: FullStatsLog,
};

pub fn LogType(comptime mode: ReportMode) type {
    return switch (mode) {
        .off => OffLog,
        .bench => BenchLog,
        .full_stats => FullStatsLog,
    };
}

pub fn getBenchLog(
    comptime mode: ReportMode,
    log: *LogType(mode),
) ?*BenchLog {
    return switch (mode) {
        .off => null,
        .bench => log,
        .full_stats => &log.bench,
    };
}

pub fn initFullStatsLog(
    allocator: std.mem.Allocator,
    pixels_num: [2]u32,
    tile_size: u16,
    sub_sample: u8,
    opts: FullStatsOpts,
) !FullStatsLog {
    var self = FullStatsLog{};
    const sub_samp: usize = @intCast(sub_sample);
    const sub_pixels_num = [_]usize{ pixels_num[1] * sub_samp, pixels_num[0] * sub_samp };

    if (opts.save_iteration_map) {
        self.iteration_map = try NDArray(f64).initFlat(allocator, &sub_pixels_num);
        @memset(self.iteration_map.?.slice, 0);
    }

    if (opts.save_pixel_occupancy_map) {
        self.pixel_occupancy_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{ pixels_num[1], pixels_num[0] },
        );
        @memset(self.pixel_occupancy_map.?.slice, 0);
    }

    if (opts.save_depth_map) {
        self.depth_map = try NDArray(f64).initFlat(allocator, &sub_pixels_num);
        @memset(self.depth_map.?.slice, 0);
    }

    if (opts.save_normals_map) {
        self.normals_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{ 3, sub_pixels_num[0], sub_pixels_num[1] },
        );
        @memset(self.normals_map.?.slice, 0);
    }

    if (opts.save_earlyout_map) {
        self.earlyout_map = try NDArray(f64).initFlat(allocator, &sub_pixels_num);
        @memset(self.earlyout_map.?.slice, 0);
    }

    const tiles_num_x = try std.math.divCeil(usize, pixels_num[0], tile_size);
    const tiles_num_y = try std.math.divCeil(usize, pixels_num[1], tile_size);
    const tiles_num = tiles_num_x * tiles_num_y;

    if (opts.save_tile_timing_map) {
        self.tile_timing_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{tiles_num},
        );
    }
    if (opts.save_tile_density_map) {
        self.tile_density_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{tiles_num},
        );
    }
    if (opts.save_tile_occupancy_map) {
        self.tile_occupancy_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{tiles_num},
        );
    }

    return self;
}

pub const Stats = struct {
    min: f64,
    max: f64,
    median: f64,
    q1: f64,
    q3: f64,
    mad: f64,
};

pub fn calcStats(allocator: std.mem.Allocator, data: []const f64) !Stats {
    if (data.len == 0) {
        return .{ .min = 0, .max = 0, .median = 0, .q1 = 0, .q3 = 0, .mad = 0 };
    }

    var filtered: std.ArrayList(f64) = .{};
    defer filtered.deinit(allocator);
    for (data) |val| {
        if (val > 0) try filtered.append(allocator, val);
    }

    if (filtered.items.len == 0) {
        return .{ .min = 0, .max = 0, .median = 0, .q1 = 0, .q3 = 0, .mad = 0 };
    }

    const slice = filtered.items;
    std.mem.sort(f64, slice, {}, std.sort.asc(f64));

    const min = slice[0];
    const max = slice[slice.len - 1];
    const median = getMedian(slice);
    const q1 = getMedian(slice[0 .. slice.len / 2]);
    const q3 = getMedian(slice[slice.len / 2 ..]);

    var deviations = try allocator.alloc(f64, slice.len);
    defer allocator.free(deviations);
    for (slice, 0..) |val, ii| {
        deviations[ii] = @abs(val - median);
    }
    std.mem.sort(f64, deviations, {}, std.sort.asc(f64));
    const mad = getMedian(deviations);

    return .{
        .min = min,
        .max = max,
        .median = median,
        .q1 = q1,
        .q3 = q3,
        .mad = mad,
    };
}

fn getMedian(sorted_data: []const f64) f64 {
    if (sorted_data.len == 0) return 0;
    const mid = sorted_data.len / 2;
    if (sorted_data.len % 2 == 0) {
        return (sorted_data[mid - 1] + sorted_data[mid]) / 2.0;
    } else {
        return sorted_data[mid];
    }
}

pub fn ReportContext(comptime mode: ReportMode) type {
    return struct {
        log: *LogType(mode),

        inline fn bench(self: @This()) ?*BenchLog {
            return getBenchLog(mode, self.log);
        }

        pub const mode_tag = mode;

        pub inline fn recordGeometry(self: @This(), total: usize, visible: usize) void {
            if (self.bench()) |bench_log| {
                bench_log.total_elements = total;
                bench_log.visible_elements = visible;
            }
        }

        pub inline fn recordTile(
            self: @This(),
            tile_idx: usize,
            time_ns: u64,
            shaded_px: u64,
            elem_count: usize,
        ) void {
            if (mode == .full_stats) {
                if (self.log.tile_timing_map) |*tmap| {
                    tmap.slice[tile_idx] = @floatFromInt(time_ns);
                }
                if (self.log.tile_occupancy_map) |*omap| {
                    omap.slice[tile_idx] = @floatFromInt(shaded_px);
                }
                if (self.log.tile_density_map) |*dmap| {
                    dmap.slice[tile_idx] = @floatFromInt(elem_count);
                }
            }

            if (self.bench()) |bench_log| {
                bench_log.total_shaded_pixels += shaded_px;
                if (elem_count > bench_log.max_tile_elements) {
                    bench_log.max_tile_elements = elem_count;
                }
            }
        }

        pub inline fn recordSolverCalls(self: @This(), solver_calls: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_calls += solver_calls;
            }
        }

        pub inline fn recordSolverIters(self: @This(), solver_iters: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.total_solver_iters += solver_iters;
            }
        }

        pub inline fn recordSolverStats(
            self: @This(),
            solver_calls: u64,
            solver_iters: u64,
        ) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_calls += solver_calls;
                bench_log.total_solver_iters += solver_iters;
            }
        }

        pub inline fn recordTessChecks(self: @This(), tess_checks: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.tess_checks += tess_checks;
            }
        }

        pub inline fn recordTessPasses(self: @This(), tess_passes: u64) void {
            if (self.bench()) |bench_log| {
                bench_log.tess_passes += tess_passes;
            }
        }

        pub inline fn recordPixelIters(
            self: @This(),
            global_subx: usize,
            global_suby: usize,
            iters: u8,
        ) void {
            if (mode == .full_stats) {
                if (self.log.iteration_map) |*imap| {
                    const row_stride = imap.strides[0];
                    imap.slice[global_suby * row_stride + global_subx] =
                        @floatFromInt(iters);
                }
            }
        }

        pub inline fn recordPixelOccupancy(
            self: @This(),
            x: usize,
            y: usize,
        ) void {
            if (mode == .full_stats) {
                if (self.log.pixel_occupancy_map) |*pomap| {
                    const row_stride = pomap.strides[0];
                    pomap.slice[y * row_stride + x] += 1.0;
                }
            }
        }

        pub inline fn recordDepth(
            self: @This(),
            global_subx: usize,
            global_suby: usize,
            inv_z: f64,
        ) void {
            if (mode == .full_stats) {
                if (self.log.depth_map) |*dmap| {
                    const row_stride = dmap.strides[0];
                    dmap.slice[global_suby * row_stride + global_subx] = inv_z;
                }
            }
        }

        pub inline fn recordNormal(
            self: @This(),
            global_subx: usize,
            global_suby: usize,
            nx: f64,
            ny: f64,
            nz: f64,
        ) void {
            if (mode == .full_stats) {
                if (self.log.normals_map) |*nmap| {
                    const chan_stride = nmap.strides[0];
                    const row_stride = nmap.strides[1];
                    const col_idx = global_suby * row_stride + global_subx;

                    nmap.slice[0 * chan_stride + col_idx] = 0.5 * nx + 0.5;
                    nmap.slice[1 * chan_stride + col_idx] = 0.5 * ny + 0.5;
                    nmap.slice[2 * chan_stride + col_idx] = 0.5 * nz + 0.5;
                }
            }
        }

        pub inline fn recordEarlyOut(
            self: @This(),
            global_subx: usize,
            global_suby: usize,
            early: bool,
        ) void {
            if (mode == .full_stats) {
                if (self.log.earlyout_map) |*emap| {
                    const row_stride = emap.strides[0];
                    emap.slice[global_suby * row_stride + global_subx] =
                        if (early) 1.0 else 0.0;
                }
            }
        }

        pub inline fn recordDepthTest(self: @This(), failed: bool) void {
            if (self.bench()) |bench_log| {
                bench_log.total_depth_tests += 1;
                if (failed) {
                    bench_log.depth_tests_failed += 1;
                }
            }
        }

        pub inline fn recordSolverDiverged(self: @This()) void {
            if (self.bench()) |bench_log| {
                bench_log.solver_diverged += 1;
            }
        }
    };
}

pub inline fn recordNormalSIMD(
    comptime nodes_num: usize,
    comptime lane_num: usize,
    ctx_report: anytype,
    ctx_shade: anytype,
    v_mask_active: @Vector(lane_num, bool),
    v_weights: [nodes_num]@Vector(lane_num, f64),
) void {
    const lane_mask: [lane_num]bool = v_mask_active;
    inline for (0..lane_num) |ll| {
        if (lane_mask[ll]) {
            var normal = [3]f64{ 0.0, 0.0, 0.0 };
            inline for (0..nodes_num) |nn| {
                normal[0] += v_weights[nn][ll] *
                    ctx_shade.shader_buf.normals[0 * nodes_num + nn];
                normal[1] += v_weights[nn][ll] *
                    ctx_shade.shader_buf.normals[1 * nodes_num + nn];
                normal[2] += v_weights[nn][ll] *
                    ctx_shade.shader_buf.normals[2 * nodes_num + nn];
            }

            ctx_report.recordNormal(
                ctx_shade.global_subx + ll,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }
}

pub fn standardReport(
    io: std.Io,
    camera: *const Camera,
    pipe_times: PipeTimes,
    total_elems: usize,
    visible_elems: usize,
    nodes_per_elem: f64,
    bench_log: *const BenchLog,
) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buffer);
    const writer = &stdout_writer.interface;

    const px_x = @as(f64, @floatFromInt(camera.pixels_num[0]));
    const px_y = @as(f64, @floatFromInt(camera.pixels_num[1]));
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));

    const total_subpx = px_x * px_y * sub_samp_f * sub_samp_f;
    const total_px = px_x * px_y;

    const raster_sec = pipe_times.raster_loop / 1e9;
    const total_sec = pipe_times.total_time / 1e9;
    const geom_tiling_sec = (pipe_times.geometry_prep + pipe_times.tile_overlap) / 1e9;

    const melems_sec = if (geom_tiling_sec > 0)
        (@as(f64, @floatFromInt(total_elems)) / (geom_tiling_sec * 1e6))
    else
        0;
    const mpx_sec = if (raster_sec > 0) (total_px / (raster_sec * 1e6)) else 0;
    const msubpx_sec = if (raster_sec > 0) (total_subpx / (raster_sec * 1e6)) else 0;
    const mops_sec = if (total_sec > 0)
        (nodes_per_elem * total_subpx / (total_sec * 1e6))
    else
        0;

    const conv_units: f64 = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;

    try writer.print("\n{s}\nSoftware Raster Times\n{s}\n", .{
        print_break,
        print_break,
    });
    try writer.print("Geometry Preparation    = {d:.6} ms\n", .{
        pipe_times.geometry_prep * conv_units,
    });
    try writer.print("Elem/Tile Overlap       = {d:.6} ms\n", .{
        pipe_times.tile_overlap * conv_units,
    });
    try writer.print("Raster loop time        = {d:.6} ms\n", .{
        pipe_times.raster_loop * conv_units,
    });

    try writer.print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n", .{
        print_break,
        pipe_times.total_time * conv_units,
    });
    try writer.print("{s}\n", .{print_break});

    const shaded_subpx = @as(f64, @floatFromInt(bench_log.total_shaded_pixels));
    const shaded_pct = if (total_subpx > 0)
        (shaded_subpx * 100.0 / total_subpx)
    else
        0;
    const vis_elems_f = @as(f64, @floatFromInt(visible_elems));
    const total_elems_f = @as(f64, @floatFromInt(total_elems));
    const vis_pct = if (total_elems > 0) (vis_elems_f * 100.0 / total_elems_f) else 0;

    try writer.print("Visible Elems = {d}\n", .{visible_elems});
    try writer.print("Total Elems   = {d}\n", .{total_elems});
    try writer.print("Visible %     = {d:.2}%\n", .{vis_pct});
    try writer.print("Total SubPx   = {d:.0}\n", .{total_subpx});
    try writer.print("Shaded SubPx  = {d:.0}\n", .{shaded_subpx});
    try writer.print("Shaded %      = {d:.2}%\n", .{shaded_pct});
    try writer.print("{s}\n", .{print_break});

    try writer.print("MElem/second  = {d:.2}\n", .{melems_sec});
    try writer.print("MPx/second    = {d:.2}\n", .{mpx_sec});
    try writer.print("MsubPx/second = {d:.2}\n", .{msubpx_sec});
    try writer.print("MOps/second   = {d:.2}\n", .{mops_sec});
    try writer.print("{s}\n", .{print_break});
    try writer.flush();
}
