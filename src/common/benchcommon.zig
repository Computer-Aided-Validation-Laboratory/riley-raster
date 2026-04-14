const std = @import("std");
const zraster = @import("../zraster/zig/zraster.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const iio = @import("../zraster/zig/imageio.zig");
const uvio = @import("../zraster/zig/uvio.zig");
const csvio = @import("../zraster/zig/csvio.zig");
const mr = @import("../zraster/zig/meshraster.zig");
const rops = @import("../zraster/zig/rasterops.zig");
const rasterengine = @import("../zraster/zig/rasterengine.zig");
const Camera = @import("../zraster/zig/camera.zig").Camera;
const CameraOps = @import("../zraster/zig/camera.zig").CameraOps;
const Rotation = @import("../zraster/zig/camera.zig").Rotation;
const report = @import("../zraster/zig/report.zig");
const NDArray = @import("../zraster/zig/ndarray.zig").NDArray;
const MatSlice = @import("../zraster/zig/matslice.zig").MatSlice;
const Timestamp = std.Io.Clock.Timestamp;

pub const CalculatedMetrics = struct {
    mpx_sec: f64,
    msubpx_sec: f64,
    mshades_sec: f64,
    msubshades_sec: f64,
    melems_sec: f64,
    mnodes_sec: f64,
    mops_sec: f64,
};

pub const BenchResult = struct {
    e2e_ms: f64,
    geom_ms: f64,
    raster_ms: f64,
    fps: f64,
    metrics: CalculatedMetrics,
};

pub const BenchStats = struct {
    name: []const u8,
    e2e: MedianMAD,
    geom: MedianMAD,
    raster: MedianMAD,
    fps: MedianMAD,
    mpx: MedianMAD,
    msubpx: MedianMAD,
    mshades: MedianMAD,
    msubshades: MedianMAD,
    melems: MedianMAD,
    mnodes: MedianMAD,
    mops: MedianMAD,
};

pub const MedianMAD = struct {
    median: f64,
    mad: f64,
};

pub fn calcMetrics(
    etype: mr.MeshType,
    pixel_num: [2]u32,
    sub_samp: u8,
    pipe_times: report.PipeTimes,
    bench_log: report.BenchLog,
) CalculatedMetrics {
    const raster_sec = pipe_times.raster_loop / 1e9;
    const geom_tiling_sec = (pipe_times.geometry_prep + pipe_times.tile_overlap) / 1e9;
    const total_sec = pipe_times.total_time / 1e9;

    const nodes_per_elem = @as(f64, @floatFromInt(etype.getNodesNum()));
    const pixels_x = @as(f64, @floatFromInt(pixel_num[0]));
    const pixels_y = @as(f64, @floatFromInt(pixel_num[1]));
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));

    const total_px = pixels_x * pixels_y;
    const total_subpx = total_px * sub_samp_f * sub_samp_f;

    // 1. MPx/s
    const mpx_sec = if (raster_sec > 0) (total_px / (raster_sec * 1e6)) else 0;

    // 2. MsubPx/s
    const msubpx_sec = if (raster_sec > 0) (total_subpx / (raster_sec * 1e6)) else 0;

    // 3. MShades/s (Approximated)
    const shaded_subpx = @as(f64, @floatFromInt(bench_log.total_shaded_pixels));
    const est_shaded_px = shaded_subpx / (sub_samp_f * sub_samp_f);
    const mshades_sec = if (raster_sec > 0) (est_shaded_px / (raster_sec * 1e6)) else 0;

    // 4. MsubShades/s
    const msubshades_sec = if (raster_sec > 0) (shaded_subpx / (raster_sec * 1e6)) else 0;

    // 5. MElems/s
    const total_elems = @as(f64, @floatFromInt(bench_log.total_elements));
    const melems_sec = if (geom_tiling_sec > 0)
        (total_elems / (geom_tiling_sec * 1e6))
    else
        0;

    // 6. MNodes/s
    const mnodes_sec = if (geom_tiling_sec > 0)
        (total_elems * nodes_per_elem / (geom_tiling_sec * 1e6))
    else
        0;

    // 7. MOps/s
    const mops_sec = if (total_sec > 0)
        (nodes_per_elem * total_subpx / (total_sec * 1e6))
    else
        0;

    return .{
        .mpx_sec = mpx_sec,
        .msubpx_sec = msubpx_sec,
        .mshades_sec = mshades_sec,
        .msubshades_sec = msubshades_sec,
        .melems_sec = melems_sec,
        .mnodes_sec = mnodes_sec,
        .mops_sec = mops_sec,
    };
}

pub fn calcMedianMAD(outer_alloc: std.mem.Allocator, data: []f64) !MedianMAD {
    if (data.len == 0) return .{ .median = 0, .mad = 0 };
    const data_copy = try outer_alloc.dupe(f64, data);
    defer outer_alloc.free(data_copy);
    std.mem.sort(f64, data_copy, {}, std.sort.asc(f64));

    const mid = data_copy.len / 2;
    const median = if (data_copy.len % 2 == 0)
        (data_copy[mid - 1] + data_copy[mid]) / 2.0
    else
        data_copy[mid];

    var abs_devs = try outer_alloc.alloc(f64, data_copy.len);
    defer outer_alloc.free(abs_devs);
    for (data_copy, 0..) |val, ii| {
        abs_devs[ii] = @abs(val - median);
    }
    std.mem.sort(f64, abs_devs, {}, std.sort.asc(f64));
    const mad = if (abs_devs.len % 2 == 0)
        (abs_devs[mid - 1] + abs_devs[mid]) / 2.0
    else
        abs_devs[mid];

    return .{ .median = median, .mad = mad };
}

pub fn getCPUModel(outer_alloc: std.mem.Allocator) []const u8 {
    return outer_alloc.dupe(u8, "BenchCPU") catch "BenchCPU";
}

pub fn getDateString() ![]const u8 {
    return "17-03-2026";
}

pub const ShaderType = enum { flat_grey, flat_rgb, tex8_grey, tex8_rgb };
pub const TextureSampleConfig = @import("../zraster/zig/textureops.zig").TextureSampleConfig;

pub const RunMode = enum { all, element, texture, interpolator };
pub const BenchConfig = struct {
    run: RunMode = .all,
    element_type: mr.MeshType = .tri3,
    texture_type: ShaderType = .tex8_grey,
    sample_config: TextureSampleConfig = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
    skip_quad4ibi_sphere: bool = false,
};

pub fn shouldRun(
    config: BenchConfig,
    mt: mr.MeshType,
    st: ShaderType,
    sc: TextureSampleConfig,
    data_dir: []const u8,
) bool {
    const is_tex = (st == .tex8_grey or st == .tex8_rgb);
    if (!is_tex and (sc.sample != .linear or sc.mode != .direct)) return false;

    if (config.skip_quad4ibi_sphere and mt == .quad4ibi) {
        if (std.mem.indexOf(u8, data_dir, "sphere200") != null or
            std.mem.indexOf(u8, data_dir, "sphere2000") != null)
        {
            return false;
        }
    }

    return switch (config.run) {
        .all => true,
        .element => mt == config.element_type,
        .texture => st == config.texture_type,
        .interpolator => is_tex and
            sc.sample == config.sample_config.sample and
            sc.mode == config.sample_config.mode,
    };
}

pub fn loadNDArray(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    requested_channels: usize,
    is_time_series: bool,
) !NDArray(f64) {
    if (std.mem.endsWith(u8, path, ".fimg")) {
        const array = try iio.loadFIMG(outer_alloc, io, path);
        if (array.dims[0] != requested_channels) {
            return error.ChannelMismatch;
        }
        return array;
    }
    return try loadNDArrayFromCSV(outer_alloc, io, path, requested_channels, is_time_series);
}

pub fn loadNDArrayFromCSV(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    requested_channels: usize,
    is_time_series: bool,
) !NDArray(f64) {
    if (is_time_series) {
        var base = try csvio.loadScalarCsv2D(outer_alloc, io, path);
        defer {
            outer_alloc.free(base.slice);
            base.deinit(outer_alloc);
        }

        var arr = try NDArray(f64).initFlat(
            outer_alloc,
            &[_]usize{ 1, base.dims[0], requested_channels },
        );
        errdefer {
            outer_alloc.free(arr.slice);
            arr.deinit(outer_alloc);
        }

        for (0..base.dims[0]) |rr| {
            for (0..requested_channels) |cc| {
                arr.set(&[_]usize{ 0, rr, cc }, base.get(&[_]usize{ rr, cc }));
            }
        }
        return arr;
    }

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();
    const lines = try csvio.readCsvToList(aa, io, path);

    if (csvio.hasPackedChannels(lines.items[0])) {
        return csvio.loadPackedCsv2DFromLines(
            outer_alloc,
            lines.items,
            requested_channels,
        );
    }

    return csvio.loadScalarCsv2DFromLines(outer_alloc, lines.items);
}

pub fn runBenchmark(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: mr.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    out_dir_base: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) !BenchResult {
    return runBenchmarkInternal(
        .bench,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        out_dir_base,
        pixel_num,
        texture_grey,
        texture_rgb,
    );
}

pub fn runBenchmarkQuiet(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: mr.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    out_dir_base: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) !BenchResult {
    return runBenchmarkInternal(
        .off,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        out_dir_base,
        pixel_num,
        texture_grey,
        texture_rgb,
    );
}

fn runBenchmarkInternal(
    comptime report_mode: report.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: mr.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    out_dir_base: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) !BenchResult {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const coord_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "coords.csv" });
    const conn_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "connect.csv" });
    const field_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "field.csv" });
    const uv_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "uvs.csv" });

    const sim_data = try meshio.loadSimData(aa, io, coord_path, conn_path, null, null);
    const field_raw = try loadNDArrayFromCSV(
        aa,
        io,
        field_path,
        if (shader_type == .flat_rgb) 3 else 1,
        true,
    );
    const uvs_raw = try loadNDArrayFromCSV(aa, io, uv_path, 2, false);

    var shader: mr.ShaderInput = undefined;
    var num_out_fields: u8 = 1;

    switch (shader_type) {
        .flat_grey => {
            num_out_fields = 1;
            shader = .{ .nodal = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.slice },
                .scaling = .auto,
            } };
        },
        .flat_rgb => {
            num_out_fields = 3;
            shader = .{ .nodal = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.slice },
                .scaling = .auto,
            } };
        },
        .tex8_grey => {
            shader = .{ .tex_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .sample_config = sample_config,
            } };
        },
        .tex8_rgb => {
            num_out_fields = 3;
            shader = .{ .tex_rgb_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_rgb,
                .sample_config = sample_config,
            } };
        },
    }

    const mesh_input = mr.MeshInput{
        .mesh_type = etype,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = shader,
    };

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        1.0,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );

    const config = zraster.RasterConfig{
        .report = report_mode,
    };
    const transformed_mesh = try mr.prepareMesh(
        aa,
        &mesh_input,
        &sim_data.coords.mat,
        null,
    );

    var image_out_arr = try NDArray(f64).initFlat(
        aa,
        &[_]usize{ num_out_fields, pixel_num[1], pixel_num[0] },
    );

    var report_log: report.LogType(report_mode) = switch (report_mode) {
        .off => .{},
        .bench => .{},
        .full_stats => unreachable,
    };

    const e2e_start = Timestamp.now(io, .awake);
    var meshes = [_]mr.MeshPrepared{transformed_mesh};
    try zraster.rasterSceneInternal(
        aa,
        io,
        &camera,
        0,
        &meshes,
        &image_out_arr,
        config.tile_size,
        report_mode,
        &report_log,
    );
    const e2e_end = Timestamp.now(io, .awake);

    const bench_log = report.getBenchLog(report_mode, &report_log);
    const e2e_ms = @as(f64, @floatFromInt(
        e2e_start.durationTo(e2e_end).raw.nanoseconds,
    )) / 1e6;
    const geom_ms = if (bench_log) |bl|
        (bl.pipe_times.geometry_prep + bl.pipe_times.tile_overlap) / 1e6
    else
        0.0;
    const raster_ms = if (bench_log) |bl|
        bl.pipe_times.raster_loop / 1e6
    else
        0.0;
    const fps = 1000.0 / e2e_ms;

    const metrics = if (bench_log) |bl|
        calcMetrics(
            etype,
            pixel_num,
            camera.sub_sample,
            bl.pipe_times,
            bl.*,
        )
    else
        CalculatedMetrics{
            .mpx_sec = 0.0,
            .msubpx_sec = 0.0,
            .mshades_sec = 0.0,
            .msubshades_sec = 0.0,
            .melems_sec = 0.0,
            .mnodes_sec = 0.0,
            .mops_sec = 0.0,
        };

    // Save one frame for inspection
    const out_name = if (shader_type == .tex8_grey or shader_type == .tex8_rgb)
        try std.fmt.allocPrint(
            aa,
            "{s}_{s}_{s}_{s}",
            .{ @tagName(etype), @tagName(shader_type), @tagName(sample_config.sample), @tagName(sample_config.mode) },
        )
    else
        try std.fmt.allocPrint(
            aa,
            "{s}_{s}",
            .{ @tagName(etype), @tagName(shader_type) },
        );
    const out_path = try std.fs.path.join(aa, &[_][]const u8{ out_dir_base, out_name });
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_base, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    cwd.createDir(io, out_path, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir_h = try cwd.openDir(io, out_path, .{});
    defer out_dir_h.close(io);

    try iio.saveImages(
        io,
        out_dir_h,
        0,
        num_out_fields,
        pixel_num,
        &image_out_arr,
        &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = num_out_fields },
            .{ .format = .fimg, .bits = null, .scaling = .none, .channels = num_out_fields },
        },
    );

    return .{
        .e2e_ms = e2e_ms,
        .geom_ms = geom_ms,
        .raster_ms = raster_ms,
        .fps = fps,
        .metrics = metrics,
    };
}

fn printPaddedSafe(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    var ii: usize = text.len;
    while (ii < width) : (ii += 1) {
        try writer.writeByte(' ');
    }
}

pub fn writeBenchmarkReport(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    title: []const u8,
    out_dir_base: []const u8,
    pixel_num: [2]u32,
    stats_list: []const BenchStats,
    max_name_len: usize,
) !void {
    const report_name = try std.fs.path.join(
        outer_alloc,
        &[_][]const u8{ out_dir_base, "benchmark.md" },
    );
    defer outer_alloc.free(report_name);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(
        io,
        out_dir_base,
        .default_dir,
    ) catch |err| if (err != error.PathAlreadyExists) return err;
    const file = try cwd.createFile(io, report_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const date = try getDateString();
    try writer.print("# {s}\n", .{title});
    try writer.print("Date: {s} | Res: {d}x{d}\n\n", .{
        date,
        pixel_num[0],
        pixel_num[1],
    });

    const col_w = @max(max_name_len, 16);
    const shader_types = comptime std.enums.values(ShaderType);

    inline for (shader_types) |st| {
        try writer.print("## Shader Type: {s}\n\n", .{@tagName(st)});

        // Header
        try writer.writeAll("| ");
        try printPaddedSafe(writer, "Case", col_w);
        try writer.print(
            " | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |\n",
            .{},
        );

        // Separator
        try writer.writeByte('|');
        {
            var ii: usize = 0;
            while (ii < col_w + 2) : (ii += 1) try writer.writeByte('-');
        }
        try writer.print(
            "| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |\n",
            .{},
        );

        for (stats_list) |s| {
            if (std.mem.indexOf(u8, s.name, @tagName(st)) != null) {
                try writer.writeAll("| ");
                try printPaddedSafe(writer, s.name, col_w);
                try writer.print(
                    " | {d:^7.2} | {d:^4.2} | {d:^6.2} | {d:^5.2} | {d:^8.2} | {d:^9.2} | {d:^12.2} | {d:^8.2} | {d:^3.2} | {d:^6.2} |\n",
                    .{
                        s.e2e.median,
                        s.geom.median,
                        s.raster.median,
                        s.mpx.median,
                        s.msubpx.median,
                        s.mshades.median,
                        s.msubshades.median,
                        s.melems.median,
                        s.fps.median,
                        s.mops.median,
                    },
                );
            }
        }
        try writer.print("\n", .{});
    }
    try writer.flush();
}
