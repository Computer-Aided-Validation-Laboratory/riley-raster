const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");

fn printPaddedSafe(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    var ii: usize = text.len;
    while (ii < width) : (ii += 1) {
        try writer.writeByte(' ');
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const texture_grey = try iio.loadImage(allocator, io, "texture/speckle.bmp", .bmp, u8, 1);
    defer texture_grey.deinit(allocator);
    const texture_rgb = try iio.loadImage(allocator, io, "texture/speckle_rgb.bmp", .bmp, u8, 3);
    defer texture_rgb.deinit(allocator);

    const out_dir_base = "out-bench-bal1000";
    const pixel_num = [_]u32{ 800, 500 };
    const runs = 5;

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);

    var stats_list: std.ArrayList(common.BenchStats) = .{};
    defer {
        for (stats_list.items) |s| allocator.free(s.name);
        stats_list.deinit(allocator);
    }

    var max_name_len: usize = 0;

    std.debug.print("Starting Balanced 1000 Benchmark ({d}x{d}, {d} run per case)...\n", 
                    .{pixel_num[0], pixel_num[1], runs});

    inline for (mesh_types) |mt| {
        inline for (shader_types) |st| {
            const case_name = comptime @tagName(mt) ++ "_" ++ @tagName(st);
            std.debug.print("Case: {s}\n", .{case_name});
            
            if (case_name.len > max_name_len) max_name_len = case_name.len;

            var e2e_times = try allocator.alloc(f64, runs);
            defer allocator.free(e2e_times);
            var geom_times = try allocator.alloc(f64, runs);
            defer allocator.free(geom_times);
            var raster_times = try allocator.alloc(f64, runs);
            defer allocator.free(raster_times);
            var mops_vals = try allocator.alloc(f64, runs);
            defer allocator.free(mops_vals);
            var melems_vals = try allocator.alloc(f64, runs);
            defer allocator.free(melems_vals);
            var fps_vals = try allocator.alloc(f64, runs);
            defer allocator.free(fps_vals);

            for (0..runs) |r| {
                const data_dir = comptime "data-bench/" ++ @tagName(mt) ++ "_bal1000";
                const res = try common.runBenchmark(allocator, io, mt, st, data_dir, 
                                                    out_dir_base, pixel_num, 
                                                    texture_grey, texture_rgb);
                e2e_times[r] = res.e2e_ms;
                geom_times[r] = res.geom_ms;
                raster_times[r] = res.raster_ms;
                mops_vals[r] = res.mops_sec;
                melems_vals[r] = res.melems_sec;
                fps_vals[r] = res.fps;
            }

            try stats_list.append(allocator, .{
                .name = try allocator.dupe(u8, case_name),
                .e2e = try common.calcMedianMAD(allocator, e2e_times),
                .geom = try common.calcMedianMAD(allocator, geom_times),
                .raster = try common.calcMedianMAD(allocator, raster_times),
                .mops = try common.calcMedianMAD(allocator, mops_vals),
                .melems = try common.calcMedianMAD(allocator, melems_vals),
                .fps = try common.calcMedianMAD(allocator, fps_vals),
            });
        }
    }

    const date = try common.getDateString();
    const report_name = try std.fmt.allocPrint(allocator, 
                                               "out-bench-bal1000/bench_{s}.md", 
                                               .{date});
    defer allocator.free(report_name);
    
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "out-bench-bal1000", .default_dir) catch |err| 
        if (err != error.PathAlreadyExists) return err;
    const file = try cwd.createFile(io, report_name, .{});
    defer file.close(io);
    
    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    try writer.print("# Balanced 1000 Benchmark Results\n", .{});
    try writer.print("Date: {s} | Res: {d}x{d}\n\n", .{date, pixel_num[0], pixel_num[1]});

    const col_w = @max(max_name_len, 16);

    inline for (shader_types) |st| {
        try writer.print("## ShaderInput Type: {s}\n\n", .{@tagName(st)});
        
        // Header
        try writer.writeAll("| ");
        try printPaddedSafe(writer, "Case", col_w);
        try writer.print(" | E2E Med (ms) | E2E MAD | Geom (ms) | Raster (ms) | MOps/s | FPS    |\n", .{});
        
        // Separator
        try writer.writeByte('|');
        { var ii: usize = 0; while (ii < col_w + 2) : (ii += 1) try writer.writeByte('-'); }
        try writer.print("| :----------: | :-----: | :-------: | :---------: | :----: | :-----: |\n", .{});
        
        for (stats_list.items) |s| {
            if (std.mem.endsWith(u8, s.name, @tagName(st))) {
                try writer.writeAll("| ");
                try printPaddedSafe(writer, s.name, col_w);
                try writer.print(" | {d:^12.2} | {d:^7.2} | {d:^9.2} | {d:^11.2} | {d:^6.2} | {d:^6.2} |\n", 
                    .{s.e2e.median, s.e2e.mad, s.geom.median, s.raster.median, 
                      s.mops.median, s.fps.median});
            }
        }
        try writer.print("\n", .{});
    }
    try writer.flush();
}
