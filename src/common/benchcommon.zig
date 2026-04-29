// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const zraster = @import("../zraster/zig/zraster.zig");
const meshio = @import("../zraster/zig/meshio.zig");
const iio = @import("../zraster/zig/imageio.zig");
const uvio = @import("../zraster/zig/uvio.zig");
const csvio = @import("../zraster/zig/csvio.zig");
const mo = @import("../zraster/zig/meshops.zig");
const so = @import("../zraster/zig/shaderops.zig");
const gk = @import("../zraster/zig/geometrykernels.zig");
const CameraPrepared = @import("../zraster/zig/camera.zig").CameraPrepared;
const CameraInput = @import("../zraster/zig/camera.zig").CameraInput;
const CameraOps = @import("../zraster/zig/camera.zig").CameraOps;
const Rotation = @import("../zraster/zig/rotation.zig").Rotation;
const report = @import("../zraster/zig/report.zig");
const rastcfg = @import("../zraster/zig/rasterconfig.zig");
const NDArray = @import("../zraster/zig/ndarray.zig").NDArray;
const tcfg = @import("testconfig.zig");
const Timestamp = std.Io.Clock.Timestamp;
const orch = @import("orchestration.zig");

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
    pipeline_times: report.FrameTimes,
    image: ?NDArray(f64) = null,

    pub fn deinit(self: *BenchResult, allocator: std.mem.Allocator) void {
        if (self.image) |img| {
            allocator.free(img.slice);
            img.deinit(allocator);
        }
    }
};

pub fn calcOutputChannels(shader_type: ShaderType) u8 {
    return switch (shader_type) {
        .nodal_rgb, .tex8_rgb => 3,
        else => 1,
    };
}

pub const BenchStats = struct {
    name: []const u8,
    mesh_type: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,

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

    geom_prep: MedianMAD,
    tile_overlap: MedianMAD,
    raster_loop: MedianMAD,
    save_frame: MedianMAD,
};

pub const MedianMAD = struct {
    median: f64,
    mad: f64,
};

pub fn calcMetrics(
    etype: gk.MeshType,
    pixel_num: [2]u32,
    sub_samp: u8,
    frame_times: report.FrameTimes,
    bench_log: report.BenchLog,
) CalculatedMetrics {
    const raster_sec = frame_times.raster_loop / 1e9;
    const geom_tiling_sec = (frame_times.geometry_prep + frame_times.tile_overlap) / 1e9;
    const total_sec = frame_times.total_time / 1e9;

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

pub const ShaderType = enum { nodal_grey, nodal_rgb, tex8_grey, tex8_rgb };
const TextureSampleConfig = @import("../zraster/zig/textureops.zig").TextureSampleConfig;

pub const RunMode = enum { all, element, texture, interpolator };
pub const BenchConfig = struct {
    run: RunMode = .all,
    element_type: gk.MeshType = .tri3,
    texture_type: ShaderType = .tex8_grey,
    sample_config: TextureSampleConfig = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
    skip_quad4ibi_sphere: bool = false,
};

pub fn shouldRun(
    config: BenchConfig,
    mt: gk.MeshType,
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
        }

        var arr = try NDArray(f64).initFlat(
            outer_alloc,
            &[_]usize{ 1, base.dims[0], requested_channels },
        );
        errdefer {
            outer_alloc.free(arr.slice);
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

pub const BenchOptions = struct {
    out_dir_base: []const u8 = "",
    save_opts: ?[]const iio.ImageSaveOpts = null,
    return_image: bool = false,
    fov_scale: f64 = 1.0,
    threads: ?u16 = null,
    threads_per_frame: ?u16 = null,
    hull_mode: rastcfg.HullMode = tcfg.HULL_MODE,
};

fn calcSaveStrategy(options: BenchOptions) rastcfg.SaveStrategy {
    if (options.out_dir_base.len > 0 and options.return_image) {
        return .both;
    }
    if (options.out_dir_base.len > 0) {
        return .disk;
    }
    if (options.return_image) {
        return .memory;
    }
    return .none;
}

pub fn calcCaseName(
    allocator: std.mem.Allocator,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    options: BenchOptions,
) ![]const u8 {
    const name = if (shader_type == .tex8_grey or shader_type == .tex8_rgb)
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}_{s}",
            .{
                @tagName(etype),
                @tagName(shader_type),
                @tagName(sample_config.sample),
                @tagName(sample_config.mode),
            },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ @tagName(etype), @tagName(shader_type) },
        );
    defer allocator.free(name);

    if (options.fov_scale < 0.99) {
        return std.fmt.allocPrint(allocator, "{s}_zoom", .{name});
    }
    return allocator.dupe(u8, name);
}

pub fn extractFirstFrameImage(
    allocator: std.mem.Allocator,
    image_arr: *const NDArray(f64),
) !NDArray(f64) {
    std.debug.assert(image_arr.dims.len == 5);
    const num_fields = image_arr.dims[2];
    const rows = image_arr.dims[3];
    const cols = image_arr.dims[4];
    var image = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ num_fields, rows, cols },
    );

    for (0..num_fields) |ff| {
        for (0..rows) |rr| {
            for (0..cols) |cc| {
                image.set(
                    &[_]usize{ ff, rr, cc },
                    image_arr.get(&[_]usize{ 0, 0, ff, rr, cc }),
                );
            }
        }
    }

    return image;
}

pub fn loadBenchmarkMeshInput(
    allocator: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
) !mo.MeshInput {
    const coord_path = try std.fs.path.join(allocator, &[_][]const u8{
        data_dir,
        "coords.csv",
    });
    const conn_path = try std.fs.path.join(allocator, &[_][]const u8{
        data_dir,
        "connect.csv",
    });
    const field_path = try std.fs.path.join(allocator, &[_][]const u8{
        data_dir,
        "field.csv",
    });
    const uv_path = try std.fs.path.join(allocator, &[_][]const u8{
        data_dir,
        "uvs.csv",
    });

    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        coord_path,
        conn_path,
        null,
        null,
    );
    const field_raw = try loadNDArrayFromCSV(
        allocator,
        io,
        field_path,
        calcOutputChannels(shader_type),
        true,
    );
    const uvs_raw = try loadNDArrayFromCSV(allocator, io, uv_path, 2, false);

    var shader: so.ShaderInput = undefined;
    switch (shader_type) {
        .nodal_grey, .nodal_rgb => {
            shader = .{ .nodal = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.slice },
                .scaling = .none,
            } };
        },
        .tex8_grey => {
            shader = .{ .tex = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .sample_config = sample_config,
            } };
        },
        .tex8_rgb => {
            shader = .{ .tex_rgb = .{
                .uvs = uvs_raw,
                .texture = texture_rgb,
                .sample_config = sample_config,
            } };
        },
    }

    return .{
        .mesh_type = etype,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = shader,
    };
}

pub fn runBenchmark(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    options: BenchOptions,
) !BenchResult {
    return runBenchmarkInternal(
        .bench,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        pixel_num,
        texture_grey,
        texture_rgb,
        options,
    );
}

pub fn runBenchmarkQuiet(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    options: BenchOptions,
) !BenchResult {
    return runBenchmarkInternal(
        .off,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        pixel_num,
        texture_grey,
        texture_rgb,
        options,
    );
}

fn runBenchmarkInternal(
    comptime report_mode: rastcfg.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: TextureSampleConfig,
    data_dir: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    options: BenchOptions,
) !BenchResult {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const mesh_input = try loadBenchmarkMeshInput(
        aa,
        io,
        etype,
        shader_type,
        sample_config,
        data_dir,
        texture_grey,
        texture_rgb,
    );
    const num_out_fields = calcOutputChannels(shader_type);

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const roi_pos = CameraOps.roiCentFromCoords(&mesh_input.coords);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &mesh_input.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        options.fov_scale,
    );
    const camera = try CameraPrepared.init(
        aa,
        .{
            .pixels_num = pixel_num,
            .pixels_size = pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = roi_pos,
            .focal_length = focal_leng,
            .sub_sample = 2,
        },
    );
    defer camera.deinit(aa);
    const camera_input = CameraInput{
        .pixels_num = camera.pixels_num,
        .pixels_size = camera.pixels_size,
        .pos_world = camera.pos_world,
        .rot_world = camera.rot_world,
        .roi_cent_world = camera.roi_cent_world,
        .focal_length = camera.focal_length,
        .sub_sample = camera.sub_sample,
        .distortion = camera.distortion,
    };

    const total_threads = options.threads orelse tcfg.TOTAL_THREADS;
    const threads_per_frame = options.threads_per_frame orelse
        @min(total_threads, tcfg.MAX_RASTER_THREADS_PER_FRAME);

    const config = rastcfg.RasterConfig{
        .render_mode = tcfg.RENDER_MODE,
        .total_threads = total_threads,
        .max_frames_in_flight = tcfg.MAX_FRAMES_IN_FLIGHT,
        .max_geom_threads_per_frame = threads_per_frame,
        .max_raster_threads_per_frame = threads_per_frame,
        .save_strategy = calcSaveStrategy(options),
        .image_save_opts = options.save_opts orelse &[_]iio.ImageSaveOpts{
            .{
                .format = .bmp,
                .bits = 8,
                .scaling = .auto,
                .channels = num_out_fields,
            },
            .{
                .format = .fimg,
                .bits = null,
                .scaling = .none,
                .channels = num_out_fields,
            },
        },
        .hull_mode = options.hull_mode,
        .report = report_mode,
    };

    if (options.out_dir_base.len > 0) {
        var out_dir = try orch.openDirEnsured(io, options.out_dir_base);
        out_dir.close(io);
    }

    const case_name = try calcCaseName(aa, etype, shader_type, sample_config, options);
    const out_path = if (options.out_dir_base.len > 0)
        try std.fs.path.join(
            aa,
            &[_][]const u8{ options.out_dir_base, case_name },
        )
    else
        null;

    var bench_capture_storage: [1]report.FrameBenchCapture = undefined;
    const bench_capture = if (report_mode == .bench)
        bench_capture_storage[0..]
    else
        null;

    const e2e_start = Timestamp.now(io, .awake);
    var image_arr = try zraster.rasterAllFrames(
        outer_alloc,
        io,
        &[_]CameraInput{camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        out_path,
        bench_capture,
    );
    const e2e_end = Timestamp.now(io, .awake);

    const e2e_ms = @as(f64, @floatFromInt(
        e2e_start.durationTo(e2e_end).raw.nanoseconds,
    )) / 1e6;
    const geom_ms = if (report_mode == .bench)
        (bench_capture_storage[0].bench_log.frame_times.geometry_prep +
            bench_capture_storage[0].bench_log.frame_times.tile_overlap) / 1e6
    else
        0.0;
    const raster_ms = if (report_mode == .bench)
        bench_capture_storage[0].bench_log.frame_times.raster_loop / 1e6
    else
        0.0;
    const fps = 1000.0 / e2e_ms;

    const metrics = if (report_mode == .bench)
        calcMetrics(
            etype,
            pixel_num,
            camera.sub_sample,
            bench_capture_storage[0].bench_log.frame_times,
            bench_capture_storage[0].bench_log,
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
    const image_final = if (options.return_image) blk: {
        var images = image_arr orelse return error.NoResult;
        image_arr = null;
        defer {
            outer_alloc.free(images.slice);
            images.deinit(outer_alloc);
        }
        break :blk try extractFirstFrameImage(outer_alloc, &images);
    } else null;

    if (image_arr) |images| {
        outer_alloc.free(images.slice);
        var images_mut = images;
        images_mut.deinit(outer_alloc);
    }

    const pipeline_times = if (report_mode == .bench)
        bench_capture_storage[0].bench_log.frame_times
    else
        report.FrameTimes{};

    return .{
        .e2e_ms = e2e_ms,
        .geom_ms = geom_ms,
        .raster_ms = raster_ms,
        .fps = fps,
        .metrics = metrics,
        .pipeline_times = pipeline_times,
        .image = image_final,
    };
}

fn printPaddedSafe(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    var ii: usize = text.len;
    while (ii < width) : (ii += 1) {
        try writer.writeByte(' ');
    }
}

pub fn writeBenchmarkCSV(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    out_dir_base: []const u8,
    stats_list: []const BenchStats,
) !void {
    const csv_name = try std.fs.path.join(
        outer_alloc,
        &[_][]const u8{ out_dir_base, "benchmark.csv" },
    );
    defer outer_alloc.free(csv_name);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(
        io,
        out_dir_base,
        .default_dir,
    ) catch |err| if (err != error.PathAlreadyExists) return err;

    var file = try cwd.createFile(io, csv_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var buffered_writer = file.writer(io, &write_buf);
    const writer = &buffered_writer.interface;

    // Header
    try writer.writeAll("Case,Element,Shader,Interpolator," ++
        "E2E_ms,Geom_ms,Raster_ms,FPS," ++
        "MPx/s,MsubPx/s,MShades/s,MsubShades/s,MElems/s,MNodes/s,MOps/s," ++
        "GeomPrep_ms,TileOverlap_ms,RasterLoop_ms,SaveFrame_ms\n");

    for (stats_list) |s| {
        const interp_name = if (s.sample_config) |sc|
            @tagName(sc.sample)
        else
            "nodal";

        try writer.print("{s},{s},{s},{s},", .{
            s.name,
            @tagName(s.mesh_type),
            @tagName(s.shader_type),
            interp_name,
        });

        // Main times and FPS
        try writer.print("{d:.6},{d:.6},{d:.6},{d:.6},", .{
            s.e2e.median,
            s.geom.median,
            s.raster.median,
            s.fps.median,
        });

        // Metrics
        try writer.print("{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},", .{
            s.mpx.median,
            s.msubpx.median,
            s.mshades.median,
            s.msubshades.median,
            s.melems.median,
            s.mnodes.median,
            s.mops.median,
        });

        // Pipeline times
        try writer.print("{d:.6},{d:.6},{d:.6},{d:.6}\n", .{
            s.geom_prep.median,
            s.tile_overlap.median,
            s.raster_loop.median,
            s.save_frame.median,
        });
    }

    try buffered_writer.flush();
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
    try writeBenchmarkCSV(outer_alloc, io, out_dir_base, stats_list);

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
