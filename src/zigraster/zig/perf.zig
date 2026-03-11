const std = @import("std");
const print = std.debug.print;
const NDArray = @import("ndarray.zig").NDArray;
const ImageFormat = @import("imageio.zig").ImageFormat;
const iio = @import("imageio.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const Camera = @import("camera.zig").Camera;

pub const Report = enum { off, perf };

pub const PerfOpts = struct {
    formats: []const ImageFormat = &[_]ImageFormat{.bmp},
    save_iteration_map: bool = true,
    save_tile_timing_map: bool = true,
    save_tile_density_map: bool = true,
    save_tile_occupancy_map: bool = true,
};

pub fn initFramePerf(
    allocator: std.mem.Allocator,
    pixels_num: [2]u32,
    tile_size: u16,
    opts: PerfOpts,
) !Perf {
    var self = Perf{};
    if (opts.save_iteration_map) {
        self.iteration_map = try NDArray(f64).initFlat(
            allocator,
            &[_]usize{ pixels_num[1], pixels_num[0] },
        );
        @memset(self.iteration_map.?.elems, 0);
    }

    const tiles_num_x: usize = try std.math.divCeil(
        usize,
        pixels_num[0],
        tile_size,
    );
    const tiles_num_y: usize = try std.math.divCeil(
        usize,
        pixels_num[1],
        tile_size,
    );
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

pub const PipeTimes = struct {
    coord_transform: f64 = 0,
    bbox_calc: f64 = 0,
    tile_count: f64 = 0,
    tile_store: f64 = 0,
    raster_loop: f64 = 0,
    total_time: f64 = 0,
};

pub const Perf = struct {
    // --- Timings (ns) ---
    pipe_times: PipeTimes = .{},

    // --- Geometry ---
    total_elements: usize = 0,
    visible_elements: usize = 0,

    // --- Solver (Newton) ---
    solver_calls: u64 = 0,
    total_iters: u64 = 0,
    solver_diverged: u64 = 0,

    // --- Rasterization ---
    total_shaded_pixels: u64 = 0,
    total_depth_tests: u64 = 0,
    depth_tests_failed: u64 = 0,
    max_tile_elements: usize = 0,

    // --- Spatial Maps ---
    iteration_map: ?NDArray(f64) = null,
    tile_timing_map: ?NDArray(f64) = null,
    tile_density_map: ?NDArray(f64) = null,
    tile_occupancy_map: ?NDArray(f64) = null,

    pub fn deinit(self: *Perf, allocator: std.mem.Allocator) void {
        if (self.iteration_map) |*imap| {
            imap.deinit(allocator);
        }
        if (self.tile_timing_map) |*tmap| {
            tmap.deinit(allocator);
        }
        if (self.tile_density_map) |*dmap| {
            dmap.deinit(allocator);
        }
        if (self.tile_occupancy_map) |*omap| {
            omap.deinit(allocator);
        }
    }

    pub fn saveFrameReport(
        self: *const Perf,
        io: std.Io,
        out_dir: ?std.Io.Dir,
        frame_idx: usize,
        camera: *const Camera,
        opts: PerfOpts,
    ) !void {
        const save_dir = out_dir orelse return;

        var name_buff: [1024]u8 = undefined;
        const stats_file_name = try std.fmt.bufPrint(
            name_buff[0..],
            "perf_stats_frame{d}.txt",
            .{frame_idx},
        );

        var stats_file = try save_dir.createFile(io, stats_file_name, .{});
        defer stats_file.close(io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = stats_file.writer(io, &write_buf);
        try self.writeReport(&file_writer.interface, frame_idx, camera);
        try self.writeReportToConsole(io, frame_idx, camera);

        if (self.iteration_map) |*m| {
            const mat = MatSlice(f64).init(
                m.elems,
                camera.pixels_num[1],
                camera.pixels_num[0],
            );
            const name = try std.fmt.bufPrint(
                name_buff[0..],
                "frame_{d}_iters",
                .{frame_idx},
            );
            for (opts.formats) |fmt| {
                try iio.saveImage(io, save_dir, name, &mat, fmt, 8);
            }
        }
    }

    pub fn writeReportToConsole(
        self: *const Perf,
        io: std.Io,
        frame_idx: usize,
        camera: *const Camera,
    ) !void {
        var buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &buffer);
        const writer = &stderr_writer.interface;
        try self.writeReport(writer, frame_idx, camera);
    }

    pub fn writeReport(
        self: *const Perf,
        writer: anytype,
        frame_idx: usize,
        camera: *const Camera,
    ) !void {
        const total_ms = self.pipe_times.total_time / 1e6;
        const total_sec = self.pipe_times.total_time / 1e9;

        const border = [_]u8{'='} ** 80 ++ "\n";
        const line = [_]u8{'-'} ** 80 ++ "\n";

        try writer.print("{s}", .{border});
        try writer.print("SOFTWARE RASTER PERFORMANCE REPORT - FRAME {d}\n", .{frame_idx});
        try writer.print("{s}\n", .{border});

        try writer.print("--- GEOMETRY PIPELINE ---\n", .{});
        try writer.print("Total Elements in Mesh  = {d}\n", .{self.total_elements});
        try writer.print("Elements after Crop     = {d}\n", .{self.visible_elements});
        const cropped = self.total_elements - self.visible_elements;
        const crop_pct = if (self.total_elements > 0)
            @as(f64, @floatFromInt(cropped)) * 100.0 /
                @as(f64, @floatFromInt(self.total_elements))
        else
            0.0;
        try writer.print("Elements Cropped        = {d} ({d:.2}%)\n\n", .{cropped, crop_pct});

        try writer.print("--- NEWTON SOLVER STATS ---\n", .{});
        try writer.print("Total Solver Calls      = {d}\n", .{self.solver_calls});
        try writer.print("Total Newton Iterations = {d}\n", .{self.total_iters});
        try writer.print("Solver Diverged/Failed  = {d}\n", .{self.solver_diverged});
        try writer.print("{s}", .{line});

        if (self.iteration_map) |*imap| {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            defer _ = gpa.deinit();
            const allocator = gpa.allocator();

            const stats = try calcStats(allocator, imap.elems);
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
        try writer.print("Total Shaded Pixels     = {d}\n", .{self.total_shaded_pixels});
        try writer.print("Max Elements in a Tile  = {d}\n", .{self.max_tile_elements});
        try writer.print("Total Depth Tests       = {d}\n", .{self.total_depth_tests});
        const d_fail_pct = if (self.total_depth_tests > 0)
            @as(f64, @floatFromInt(self.depth_tests_failed)) * 100.0 /
                @as(f64, @floatFromInt(self.total_depth_tests))
        else
            0.0;
        try writer.print("Depth Tests Failed      = {d} ({d:.2}%)\n", .{
            self.depth_tests_failed,
            d_fail_pct,
        });
        try writer.print("{s}", .{line});
        const mpxs = if (total_sec > 0)
            (@as(f64, @floatFromInt(self.total_shaded_pixels)) / 1e6) / total_sec
        else
            0.0;
        try writer.print("Shaded Performance      = {d:.2} MPx/s\n\n", .{mpxs});

        try writer.print("--- PIPELINE TIMINGS (User Summary) ---\n", .{});
        const conv = 1.0 / 1e6;
        try writer.print("Coord transformation    = {d:.6} ms\n", .{
            self.pipe_times.coord_transform * conv,
        });
        try writer.print("Elem screen crop & BBox = {d:.6} ms\n", .{
            self.pipe_times.bbox_calc * conv,
        });
        try writer.print("Elem tile overlap count = {d:.6} ms\n", .{
            self.pipe_times.tile_count * conv,
        });
        try writer.print("Elem tile overlap store = {d:.6} ms\n", .{
            self.pipe_times.tile_store * conv,
        });
        try writer.print("Raster loop time        = {d:.6} ms\n", .{
            self.pipe_times.raster_loop * conv,
        });
        try writer.print("{s}", .{line});
        try writer.print("TOTAL RASTER TIME       = {d:.3} ms\n", .{total_ms});
        try writer.print("{s}", .{line});

        var total_px: f64 = @as(f64, 
            @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
        const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
        total_px = total_px * sub_samp_f * sub_samp_f;

        const mega_ops_per_sec: f64 = 1.0e3 * total_px / self.pipe_times.total_time;
        const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(self.total_elements)) /
            self.pipe_times.total_time;

        try writer.print("Total Ops               = {d}\n", .{total_px});
        try writer.print("MOps/second             = {d:.2}\n", .{mega_ops_per_sec});
        try writer.print("MTri/second             = {d:.2}\n", .{mega_tris_per_sec});

        try writer.print("{s}", .{border});
        try writer.flush();
    }
};

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
        return Stats{
            .min = 0,
            .max = 0,
            .median = 0,
            .q1 = 0,
            .q3 = 0,
            .mad = 0,
        };
    }

    var filtered: std.ArrayList(f64) = .{};
    defer filtered.deinit(allocator);
    for (data) |val| {
        if (val > 0) {
            try filtered.append(allocator, val);
        }
    }

    if (filtered.items.len == 0) {
        return Stats{
            .min = 0,
            .max = 0,
            .median = 0,
            .q1 = 0,
            .q3 = 0,
            .mad = 0,
        };
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

    return Stats{
        .min = min,
        .max = max,
        .median = median,
        .q1 = q1,
        .q3 = q3,
        .mad = mad,
    };
}

fn getMedian(sorted_data: []const f64) f64 {
    if (sorted_data.len == 0) {
        return 0;
    }
    const mid = sorted_data.len / 2;
    if (sorted_data.len % 2 == 0) {
        return (sorted_data[mid - 1] + sorted_data[mid]) / 2.0;
    } else {
        return sorted_data[mid];
    }
}

pub fn PerfContext(comptime mode: Report) type {
    return struct {
        perf: if (mode == .perf) *Perf else void,

        pub inline fn recordGeometry(self: @This(), total: usize, visible: usize) void {
            self.perf.total_elements = total;
            self.perf.visible_elements = visible;
        }

        pub inline fn recordTile(
            self: @This(),
            tile_idx: usize,
            time_ns: u64,
            shaded_px: u64,
            elem_count: usize,
        ) void {
            if (self.perf.tile_timing_map) |*tmap| {
                tmap.elems[tile_idx] = @floatFromInt(time_ns);
            }
            if (self.perf.tile_occupancy_map) |*omap| {
                omap.elems[tile_idx] = @floatFromInt(shaded_px);
            }
            if (self.perf.tile_density_map) |*dmap| {
                dmap.elems[tile_idx] = @floatFromInt(elem_count);
            }
            self.perf.total_shaded_pixels += shaded_px;
            if (elem_count > self.perf.max_tile_elements) {
                self.perf.max_tile_elements = elem_count;
            }
        }

        pub inline fn recordPixel(self: @This(), x: usize, y: usize, iters: u8) void {
            if (self.perf.iteration_map) |*imap| {
                const row_stride = imap.strides[0];
                imap.elems[y * row_stride + x] = @floatFromInt(iters);
            }
            self.perf.solver_calls += 1;
            self.perf.total_iters += iters;
        }

        pub inline fn recordDepthTest(self: @This(), failed: bool) void {
            self.perf.total_depth_tests += 1;
            if (failed) {
                self.perf.depth_tests_failed += 1;
            }
        }

        pub inline fn recordSolverDiverged(self: @This()) void {
            self.perf.solver_diverged += 1;
        }
    };
}

pub fn standardReport(
    io: std.Io,
    camera: *const Camera,
    pipe_times: PipeTimes,
    elems_num: usize,
) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &buffer);
    const writer = &stdout_writer.interface;

    var total_px: f64 = @as(f64, @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    total_px = total_px * sub_samp_f * sub_samp_f;

    const mega_ops_per_sec: f64 = 1.0e3 * total_px / pipe_times.total_time;
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(elems_num)) /
        pipe_times.total_time;

    const conv_units: f64 = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;

    try writer.print("\n{s}\nSoftware Raster Times\n{s}\n", 
        .{ print_break, print_break });
    try writer.print("Coord transformation    = {d:.6} ms\n", 
        .{ pipe_times.coord_transform * conv_units });
    try writer.print("Elem screen crop & BBox = {d:.6} ms\n", 
        .{ pipe_times.bbox_calc * conv_units });
    try writer.print("Elem tile overlap count = {d:.6} ms\n", 
        .{ pipe_times.tile_count * conv_units });
    try writer.print("Elem tile overlap store = {d:.6} ms\n", 
        .{ pipe_times.tile_store * conv_units });
    try writer.print("Raster loop time        = {d:.6} ms\n", 
        .{ pipe_times.raster_loop * conv_units });
    try writer.print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n", .{
        print_break,
        pipe_times.total_time * conv_units,
    });
    try writer.print("{s}\n", .{print_break});
    try writer.print("Total Ops   = {d}\n", .{total_px});
    try writer.print("MOps/second = {d:.2}\n", .{mega_ops_per_sec});
    try writer.print("MTri/second = {d:.2}\n", .{mega_tris_per_sec});
    try writer.print("{s}\n", .{print_break});
    try writer.flush();
}
