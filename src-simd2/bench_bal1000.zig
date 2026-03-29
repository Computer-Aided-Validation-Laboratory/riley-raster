const std = @import("std");
const common = @import("bench_common.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const iio = @import("zigraster/zig/imageio.zig");

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

    const out_dir_base = "out-simd2-bench-bal1000";
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

    std.debug.print(
        "Starting Balanced 1000 Benchmark ({d}x{d}, {d} run per case)...\n",
        .{ pixel_num[0], pixel_num[1], runs }
    );

    for (mesh_types) |mt| {
        for (shader_types) |st| {
            var case_name_buf: [256]u8 = undefined;
            const case_name = try std.fmt.bufPrint(
                &case_name_buf, "{s}_{s}", .{ @tagName(mt), @tagName(st) }
            );
            std.debug.print("Case: {s}\n", .{case_name});

            if (case_name.len > max_name_len) max_name_len = case_name.len;

            var e2e_times = try allocator.alloc(f64, runs); defer allocator.free(e2e_times);
            var geom_times = try allocator.alloc(f64, runs); defer allocator.free(geom_times);
            var raster_times = try allocator.alloc(f64, runs); defer allocator.free(raster_times);
            var fps_vals = try allocator.alloc(f64, runs); defer allocator.free(fps_vals);
            
            var mpx_vals = try allocator.alloc(f64, runs); defer allocator.free(mpx_vals);
            var msubpx_vals = try allocator.alloc(f64, runs); defer allocator.free(msubpx_vals);
            var mshades_vals = try allocator.alloc(f64, runs); defer allocator.free(mshades_vals);
            var msubshades_vals = try allocator.alloc(f64, runs); defer allocator.free(msubshades_vals);
            var melems_vals = try allocator.alloc(f64, runs); defer allocator.free(melems_vals);
            var mnodes_vals = try allocator.alloc(f64, runs); defer allocator.free(mnodes_vals);
            var mops_vals = try allocator.alloc(f64, runs); defer allocator.free(mops_vals);

            for (0..runs) |r| {
                var data_dir_buf: [256]u8 = undefined;
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf, "data-bench/{s}_bal1000", .{@tagName(mt)}
                );
                const res = try common.runBenchmark(
                    allocator, io, mt, st, .linear, data_dir,
                    out_dir_base, pixel_num,
                    texture_grey, texture_rgb
                );
                e2e_times[r] = res.e2e_ms;
                geom_times[r] = res.geom_ms;
                raster_times[r] = res.raster_ms;
                fps_vals[r] = res.fps;
                
                mpx_vals[r] = res.metrics.mpx_sec;
                msubpx_vals[r] = res.metrics.msubpx_sec;
                mshades_vals[r] = res.metrics.mshades_sec;
                msubshades_vals[r] = res.metrics.msubshades_sec;
                melems_vals[r] = res.metrics.melems_sec;
                mnodes_vals[r] = res.metrics.mnodes_sec;
                mops_vals[r] = res.metrics.mops_sec;
            }

            try stats_list.append(allocator, .{
                .name = try allocator.dupe(u8, case_name),
                .e2e = try common.calcMedianMAD(allocator, e2e_times),
                .geom = try common.calcMedianMAD(allocator, geom_times),
                .raster = try common.calcMedianMAD(allocator, raster_times),
                .fps = try common.calcMedianMAD(allocator, fps_vals),
                .mpx = try common.calcMedianMAD(allocator, mpx_vals),
                .msubpx = try common.calcMedianMAD(allocator, msubpx_vals),
                .mshades = try common.calcMedianMAD(allocator, mshades_vals),
                .msubshades = try common.calcMedianMAD(allocator, msubshades_vals),
                .melems = try common.calcMedianMAD(allocator, melems_vals),
                .mnodes = try common.calcMedianMAD(allocator, mnodes_vals),
                .mops = try common.calcMedianMAD(allocator, mops_vals),
            });
        }
    }

    try common.writeBenchmarkReport(
        allocator, io, "Balanced 1000 Benchmark Results", out_dir_base, 
        pixel_num, stats_list.items, max_name_len
    );
}
