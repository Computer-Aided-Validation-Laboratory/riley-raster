const std = @import("std");
const common = @import("common/benchcommon.zig");
const mr = @import("zraster/zig/meshraster.zig");
const iio = @import("zraster/zig/imageio.zig");

const config = common.BenchConfig{ .run = .all };

pub fn main() !void {
    const outer_alloc = std.heap.page_allocator;

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

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

    const out_dir_base = "out-bench-geom";
    const pixel_num = [_]u32{ 800, 500 };
    const runs = 10;

    const mesh_types = comptime std.enums.values(mr.MeshType);
    const shader_types = comptime std.enums.values(common.ShaderType);
    const interp_types = [_]common.InterpType{
        .linear, .cubic, .cubic_lut_lerp, .quintic, .quintic_lut_lerp,
    };

    var stats_list: std.ArrayList(common.BenchStats) = .{};
    defer {
        for (stats_list.items) |s| outer_alloc.free(s.name);
        stats_list.deinit(outer_alloc);
    }

    var max_name_len: usize = 0;

    std.debug.print("Starting Geom Raster Benchmark ({d}x{d}, {d} run per case)...\n", .{
        pixel_num[0], pixel_num[1], runs,
    });

    for (mesh_types) |mt| {
        for (shader_types) |st| {
            for (interp_types) |it| {
                var data_dir_buf: [256]u8 = undefined;
                const data_dir = try std.fmt.bufPrint(&data_dir_buf, "data-bench/{s}_geom", .{@tagName(mt)});

                if (common.shouldRun(config, mt, st, it, data_dir)) {
                    var case_name_buf: [256]u8 = undefined;
                    const case_name = if (st == .tex8_grey or st == .tex8_rgb)
                        try std.fmt.bufPrint(&case_name_buf, "{s}_{s}_{s}", .{ @tagName(mt), @tagName(st), @tagName(it) })
                    else
                        try std.fmt.bufPrint(&case_name_buf, "{s}_{s}", .{ @tagName(mt), @tagName(st) });

                    std.debug.print("Case: {s}\n", .{case_name});

                    if (case_name.len > max_name_len) max_name_len = case_name.len;

                    var e2e_times = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(e2e_times);
                    var geom_times = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(geom_times);
                    var raster_times = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(raster_times);
                    var fps_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(fps_vals);

                    var mpx_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(mpx_vals);
                    var msubpx_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(msubpx_vals);
                    var mshades_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(mshades_vals);
                    var msubshades_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(msubshades_vals);
                    var melems_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(melems_vals);
                    var mnodes_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(mnodes_vals);
                    var mops_vals = try outer_alloc.alloc(f64, runs);
                    defer outer_alloc.free(mops_vals);

                    for (0..runs) |r| {
                        const res = try common.runBenchmark(
                            outer_alloc,
                            io,
                            mt,
                            st,
                            it,
                            data_dir,
                            out_dir_base,
                            pixel_num,
                            texture_grey,
                            texture_rgb,
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

                    try stats_list.append(outer_alloc, .{
                        .name = try outer_alloc.dupe(u8, case_name),
                        .e2e = try common.calcMedianMAD(outer_alloc, e2e_times),
                        .geom = try common.calcMedianMAD(outer_alloc, geom_times),
                        .raster = try common.calcMedianMAD(outer_alloc, raster_times),
                        .fps = try common.calcMedianMAD(outer_alloc, fps_vals),
                        .mpx = try common.calcMedianMAD(outer_alloc, mpx_vals),
                        .msubpx = try common.calcMedianMAD(outer_alloc, msubpx_vals),
                        .mshades = try common.calcMedianMAD(outer_alloc, mshades_vals),
                        .msubshades = try common.calcMedianMAD(outer_alloc, msubshades_vals),
                        .melems = try common.calcMedianMAD(outer_alloc, melems_vals),
                        .mnodes = try common.calcMedianMAD(outer_alloc, mnodes_vals),
                        .mops = try common.calcMedianMAD(outer_alloc, mops_vals),
                    });
                }
            }
        }
    }

    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "Geom Raster Benchmark Results",
        out_dir_base,
        pixel_num,
        stats_list.items,
        max_name_len,
    );
}
