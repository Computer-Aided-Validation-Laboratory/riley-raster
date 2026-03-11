const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const ImageFormat = @import("imageio.zig").ImageFormat;
const iio = @import("imageio.zig");
const MatSlice = @import("matslice.zig").MatSlice;

pub const Report = enum { off, perf };

pub const PerfOpts = struct {
    formats: []const ImageFormat = &[_]ImageFormat{.bmp},
    save_iteration_map: bool = true,
    save_tile_timing_map: bool = true,
    save_tile_density_map: bool = true,
    save_tile_occupancy_map: bool = true,
};

pub const Perf = struct {
    // --- Timings (ns) ---
    coord_transform: u64 = 0,
    bbox_calc: u64 = 0,
    tile_count: u64 = 0,
    tile_store: u64 = 0,
    raster_loop: u64 = 0,
    total_time: u64 = 0,

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
        if (self.iteration_map) |*m| m.deinit(allocator);
        if (self.tile_timing_map) |*m| m.deinit(allocator);
        if (self.tile_density_map) |*m| m.deinit(allocator);
        if (self.tile_occupancy_map) |*m| m.deinit(allocator);
    }

    pub fn writeReportToConsole(self: *const Perf, io: std.Io, frame_idx: usize) !void {
        var buffer: [4096]u8 = undefined;
        var stderr_writer = std.Io.File.stderr().writer(io, &buffer);
        const writer = &stderr_writer.interface;
        try self.writeReport(writer, frame_idx);
    }

    pub fn writeReport(self: *const Perf, writer: anytype, frame_idx: usize) !void {
        const total_ms = @as(f64, @floatFromInt(self.total_time)) / 1e6;
        const total_sec = @as(f64, @floatFromInt(self.total_time)) / 1e9;

        const border = "========================================================================\n";
        const line = "------------------------------------------------------------------------\n";

        try writer.print("{s}", .{border});
        try writer.print("SOFTWARE RASTER PERFORMANCE REPORT - FRAME {d}\n", .{frame_idx});
        try writer.print("{s}\n", .{border});

        try writer.print("--- GEOMETRY PIPELINE ---\n", .{});
        try writer.print("Total Elements in Mesh  = {d}\n", .{self.total_elements});
        try writer.print("Elements after Crop     = {d}\n", .{self.visible_elements});
        const cropped = self.total_elements - self.visible_elements;
        const crop_pct = if (self.total_elements > 0)
            @as(f64, @floatFromInt(cropped)) * 100.0 / @as(f64, @floatFromInt(self.total_elements))
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
            @as(f64, @floatFromInt(self.coord_transform)) * conv,
        });
        try writer.print("Elem screen crop & BBox = {d:.6} ms\n", .{
            @as(f64, @floatFromInt(self.bbox_calc)) * conv,
        });
        try writer.print("Elem tile overlap count = {d:.6} ms\n", .{
            @as(f64, @floatFromInt(self.tile_count)) * conv,
        });
        try writer.print("Elem tile overlap store = {d:.6} ms\n", .{
            @as(f64, @floatFromInt(self.tile_store)) * conv,
        });
        try writer.print("Raster loop time        = {d:.6} ms\n", .{
            @as(f64, @floatFromInt(self.raster_loop)) * conv,
        });
        try writer.print("{s}", .{line});
        try writer.print("TOTAL RASTER TIME       = {d:.3} ms\n", .{total_ms});
        try writer.print("{s}", .{line});
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
    if (data.len == 0) return Stats{
        .min = 0,
        .max = 0,
        .median = 0,
        .q1 = 0,
        .q3 = 0,
        .mad = 0,
    };

    var filtered: std.ArrayList(f64) = .{};
    defer filtered.deinit(allocator);
    for (data) |v| {
        if (v > 0) try filtered.append(allocator, v);
    }

    if (filtered.items.len == 0) return Stats{
        .min = 0,
        .max = 0,
        .median = 0,
        .q1 = 0,
        .q3 = 0,
        .mad = 0,
    };

    const slice = filtered.items;
    std.mem.sort(f64, slice, {}, std.sort.asc(f64));

    const min = slice[0];
    const max = slice[slice.len - 1];
    const median = getMedian(slice);
    const q1 = getMedian(slice[0 .. slice.len / 2]);
    const q3 = getMedian(slice[slice.len / 2 ..]);

    var deviations = try allocator.alloc(f64, slice.len);
    defer allocator.free(deviations);
    for (slice, 0..) |v, i| {
        deviations[i] = @abs(v - median);
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
    if (sorted_data.len == 0) return 0;
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
            if (comptime mode == .perf) {
                self.perf.total_elements = total;
                self.perf.visible_elements = visible;
            }
        }

        pub inline fn recordTile(
            self: @This(),
            tile_idx: usize,
            time_ns: u64,
            shaded_px: u64,
            elem_count: usize,
        ) void {
            if (comptime mode == .perf) {
                if (self.perf.tile_timing_map) |*m| m.elems[tile_idx] = @floatFromInt(time_ns);
                if (self.perf.tile_occupancy_map) |*m| m.elems[tile_idx] = @floatFromInt(shaded_px);
                if (self.perf.tile_density_map) |*m| m.elems[tile_idx] = @floatFromInt(elem_count);
                self.perf.total_shaded_pixels += shaded_px;
                if (elem_count > self.perf.max_tile_elements) {
                    self.perf.max_tile_elements = elem_count;
                }
            }
        }

        pub inline fn recordPixel(self: @This(), x: usize, y: usize, iters: u8) void {
            if (comptime mode == .perf) {
                if (self.perf.iteration_map) |*m| {
                    const row_stride = m.strides[0];
                    m.elems[y * row_stride + x] = @floatFromInt(iters);
                }
                self.perf.solver_calls += 1;
                self.perf.total_iters += iters;
            }
        }

        pub inline fn recordDepthTest(self: @This(), failed: bool) void {
            if (comptime mode == .perf) {
                self.perf.total_depth_tests += 1;
                if (failed) self.perf.depth_tests_failed += 1;
            }
        }

        pub inline fn recordSolverDiverged(self: @This()) void {
            if (comptime mode == .perf) {
                self.perf.solver_diverged += 1;
            }
        }
    };
}
