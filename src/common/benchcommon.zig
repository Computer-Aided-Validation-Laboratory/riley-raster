// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const riley = @import("../riley/zig/riley.zig");
const meshio = @import("../riley/zig/meshio.zig");
const iio = @import("../riley/zig/imageio.zig");
const uvio = @import("../riley/zig/uvio.zig");
const csvio = @import("../riley/zig/csvio.zig");
const mo = @import("../riley/zig/meshops.zig");
const so = @import("../riley/zig/shaderops.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const CameraPrepared = @import("../riley/zig/camera.zig").CameraPrepared;
const CameraInput = @import("../riley/zig/camera.zig").CameraInput;
const cameraops = @import("../riley/zig/cameraops.zig");
const Rotation = @import("../riley/zig/rotation.zig").Rotation;
const report = @import("../riley/zig/report.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const scalingpolicy = @import("../riley/zig/scalingpolicy.zig");
const NDArray = @import("../riley/zig/ndarray.zig").NDArray;
const tcfg = @import("testconfig.zig");
const Timestamp = std.Io.Clock.Timestamp;
const orch = @import("orchestration.zig");

pub const CalculatedMetrics = struct {
    raster_tpx_mpx_s: f64,
    frame_tpx_mpx_s: f64,
    e2e_tpx_mpx_s: f64,
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
    cam_ms: f64,
    resolve_ms: f64,
    fps: f64,
    total_elems: usize,
    vis_elems: usize,
    total_px: u64,
    shaded_px: u64,
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
        .nodal_rgb, .tex8_rgb, .func_rgb => 3,
        else => 1,
    };
}

pub const BenchStats = struct {
    name: []const u8,
    mesh_type: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,

    total_elems: MedianMAD,
    vis_elems: MedianMAD,
    total_px: MedianMAD,
    shaded_px: MedianMAD,
    e2e: MedianMAD,
    geom: MedianMAD,
    raster: MedianMAD,
    cam_invert: MedianMAD,
    elem_loop: MedianMAD,
    scratch_resolve: MedianMAD,
    save: MedianMAD,
    frame: MedianMAD,
    geom_tpx: MedianMAD,
    raster_tpx: MedianMAD,
    frame_tpx: MedianMAD,
    e2e_tpx: MedianMAD,
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
    min: f64,
    max: f64,
};

pub fn calcMetrics(
    etype: gk.MeshType,
    pixel_num: [2]u32,
    sub_samp: u8,
    e2e_ms: f64,
    frame_times: report.FrameTimes,
    bench_log: report.BenchLog,
) CalculatedMetrics {
    const raster_sec = frame_times.raster_loop / 1e9;
    const geom_tiling_sec = (frame_times.geometry_prep + frame_times.tile_overlap) / 1e9;
    const active_sec = frame_times.active_time / 1e9;

    const nodes_per_elem = @as(f64, @floatFromInt(etype.getNodesNum()));
    const pixels_x = @as(f64, @floatFromInt(pixel_num[0]));
    const pixels_y = @as(f64, @floatFromInt(pixel_num[1]));
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));

    const total_px = pixels_x * pixels_y;
    const total_subpx = total_px * sub_samp_f * sub_samp_f;

    // 1. MPx/s
    const raster_tpx_mpx_s = if (raster_sec > 0)
        (total_px / (raster_sec * 1e6))
    else
        0;

    const frame_tpx_mpx_s = if (active_sec > 0)
        (total_px / (active_sec * 1e6))
    else
        0;

    const e2e_tpx_mpx_s = if (e2e_ms > 0.0)
        total_px / ((e2e_ms / 1e3) * 1e6)
    else
        0;

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
    const mops_sec = if (active_sec > 0)
        (nodes_per_elem * total_subpx / (active_sec * 1e6))
    else
        0;

    return .{
        .raster_tpx_mpx_s = raster_tpx_mpx_s,
        .frame_tpx_mpx_s = frame_tpx_mpx_s,
        .e2e_tpx_mpx_s = e2e_tpx_mpx_s,
        .msubpx_sec = msubpx_sec,
        .mshades_sec = mshades_sec,
        .msubshades_sec = msubshades_sec,
        .melems_sec = melems_sec,
        .mnodes_sec = mnodes_sec,
        .mops_sec = mops_sec,
    };
}

pub fn calcMedianMAD(outer_alloc: std.mem.Allocator, data: []f64) !MedianMAD {
    if (data.len == 0) {
        return .{
            .median = 0,
            .mad = 0,
            .min = 0,
            .max = 0,
        };
    }
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

    return .{
        .median = median,
        .mad = mad,
        .min = data_copy[0],
        .max = data_copy[data_copy.len - 1],
    };
}

pub fn getCPUModel(outer_alloc: std.mem.Allocator) []const u8 {
    return outer_alloc.dupe(u8, "BenchCPU") catch "BenchCPU";
}

pub fn getDateString() ![]const u8 {
    return "17-03-2026";
}

pub fn calcActualTileSize(
    config: rastcfg.RasterConfig,
    pixel_num: [2]u32,
    sub_sample: u8,
    halo_px: u16,
) u16 {
    return scalingpolicy.tileSize(
        config.tile_size_override,
        config.tile_size_min,
        config.tile_size_max,
        pixel_num,
        sub_sample,
        halo_px,
    );
}

fn calcActiveThreadsTotal(
    render_group_workers: []const u16,
) u32 {
    var total: u32 = 0;
    for (render_group_workers) |workers| {
        total += workers;
    }
    return total;
}

fn calcActiveThreadsRaster(
    render_group_workers: []const u16,
    max_raster_workers_per_job: u16,
) u32 {
    var total: u32 = 0;
    const per_job_cap = @max(@as(u16, 1), max_raster_workers_per_job);
    for (render_group_workers) |workers| {
        total += @min(workers, per_job_cap);
    }
    return total;
}

fn calcActiveThreadsGeomSpread(
    render_group_workers: []const u16,
    max_geom_jobs_in_flight_per_group: u16,
    max_geom_workers_per_job: u16,
) u32 {
    var total: u32 = 0;
    const jobs_cap = @max(@as(u16, 1), max_geom_jobs_in_flight_per_group);
    const workers_cap = @max(@as(u16, 1), max_geom_workers_per_job);
    for (render_group_workers) |workers| {
        total += @min(workers, jobs_cap * workers_cap);
    }
    return total;
}

fn calcActiveThreadsGeomPack(
    render_group_workers: []const u16,
    max_geom_workers_per_job: u16,
) u32 {
    var total: u32 = 0;
    const workers_cap = @max(@as(u16, 1), max_geom_workers_per_job);
    for (render_group_workers) |workers| {
        total += @min(workers, workers_cap);
    }
    return total;
}

pub fn writeBenchmarkConfig(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    stats_out_dir_base: []const u8,
    image_out_dir_base: []const u8,
    benchmark_name: []const u8,
    argv: anytype,
    subpixel_center_map: @import("../riley/zig/camera.zig").SubPixelCenterMap,
    config: rastcfg.RasterConfig,
    render_group_workers: []const u16,
    pixel_num: [2]u32,
    sub_sample: u8,
    runs: usize,
    fov_scale: f64,
    actual_tile_size: u16,
) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(
        io,
        stats_out_dir_base,
        .default_dir,
    ) catch |err| if (err != error.PathAlreadyExists) return err;

    const config_path = try std.fs.path.join(
        outer_alloc,
        &[_][]const u8{ stats_out_dir_base, "config.txt" },
    );
    defer outer_alloc.free(config_path);

    var file = try cwd.createFile(io, config_path, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var buffered_writer = file.writer(io, &write_buf);
    const writer = &buffered_writer.interface;

    try writer.print("benchmark={s}\n", .{benchmark_name});
    try writer.print("stats_out_dir={s}\n", .{stats_out_dir_base});
    try writer.print("image_out_dir={s}\n", .{image_out_dir_base});
    try writer.print("render_mode={s}\n", .{@tagName(config.render_mode)});
    try writer.print("render_group_count={d}\n", .{render_group_workers.len});
    for (render_group_workers, 0..) |workers, ii| {
        try writer.print(
            "render_group_{d}_workers={d}\n",
            .{ ii, workers },
        );
    }
    const active_threads_total = calcActiveThreadsTotal(
        render_group_workers,
    );
    const active_threads_raster = calcActiveThreadsRaster(
        render_group_workers,
        config.max_raster_workers_per_job,
    );
    const active_threads_geom_spread = calcActiveThreadsGeomSpread(
        render_group_workers,
        config.max_geom_jobs_in_flight_per_group,
        config.max_geom_workers_per_job,
    );
    const active_threads_geom_pack = calcActiveThreadsGeomPack(
        render_group_workers,
        config.max_geom_workers_per_job,
    );
    const active_threads_geom_effective = switch (config.geom_scheduling_mode) {
        .spread => active_threads_geom_spread,
        .pack => active_threads_geom_pack,
        .auto => 0,
    };
    try writer.print("total_threads={d}\n", .{config.total_threads});
    try writer.print(
        "active_threads_total_max={d}\n",
        .{active_threads_total},
    );
    try writer.print(
        "active_threads_raster_max={d}\n",
        .{active_threads_raster},
    );
    try writer.print(
        "active_threads_geom_spread_max={d}\n",
        .{active_threads_geom_spread},
    );
    try writer.print(
        "active_threads_geom_pack_max={d}\n",
        .{active_threads_geom_pack},
    );
    try writer.print(
        "active_threads_geom_effective_max={d}\n",
        .{active_threads_geom_effective},
    );
    try writer.print(
        "frame_batch_size_per_group={d}\n",
        .{config.frame_batch_size_per_group},
    );
    try writer.print(
        "max_geom_jobs_in_flight_per_group={d}\n",
        .{config.max_geom_jobs_in_flight_per_group},
    );
    try writer.print(
        "max_geom_workers_per_job={d}\n",
        .{config.max_geom_workers_per_job},
    );
    try writer.print(
        "geom_scheduling_mode={s}\n",
        .{@tagName(config.geom_scheduling_mode)},
    );
    if (config.geom_scheduling_mode == .auto) {
        try writer.writeAll(
            "geom_scheduling_mode_auto_note=spread if total_scene_elems < 100000 else pack\n",
        );
    }
    try writer.print(
        "max_raster_workers_per_job={d}\n",
        .{config.max_raster_workers_per_job},
    );
    try writer.print("hull_mode={s}\n", .{@tagName(config.hull_mode)});
    try writer.print(
        "subpixel_center_map={s}\n",
        .{@tagName(subpixel_center_map)},
    );
    try writer.print("save_strategy={s}\n", .{@tagName(config.save_strategy)});
    try writer.print("pixels_x={d}\n", .{pixel_num[0]});
    try writer.print("pixels_y={d}\n", .{pixel_num[1]});
    try writer.print("sub_sample={d}\n", .{sub_sample});
    try writer.print("runs={d}\n", .{runs});
    try writer.print("fov_scale={d:.6}\n", .{fov_scale});
    try writer.print("tile_size_min={d}\n", .{config.tile_size_min});
    try writer.print("tile_size_max={d}\n", .{config.tile_size_max});
    try writer.print("actual_tile_size={d}\n", .{actual_tile_size});
    try writer.print("build_simd={s}\n", .{
        @tagName(buildconfig.config.simd),
    });
    try writer.print("build_simd_texture_interp={s}\n", .{
        @tagName(buildconfig.config.simd_texture_interp),
    });
    try writer.print("build_resolve_scratch_simd={s}\n", .{
        @tagName(buildconfig.config.resolve_scratch_simd),
    });
    try writer.print("build_simd_vector_width={d}\n", .{
        buildconfig.config.simd_vector_width,
    });
    try writer.print("build_max_nodal_fields={d}\n", .{
        buildconfig.config.max_nodal_fields,
    });
    try writer.print("build_max_image_channels={d}\n", .{
        buildconfig.config.max_image_channels,
    });
    try writer.print("build_raster_newton_iter_max={d}\n", .{
        buildconfig.config.raster_newton_iter_max,
    });
    try writer.print("build_distortion_newton_iter_max={d}\n", .{
        buildconfig.config.distortion_newton_iter_max,
    });
    try writer.print("build_interp_lut_size={d}\n", .{
        buildconfig.config.interp_lut_size,
    });
    try writer.print("build_precision={s}\n", .{
        @typeName(buildconfig.config.precision),
    });
    try writer.writeAll("argv_begin\n");
    for (argv, 0..) |arg, aa| {
        try writer.print(
            "argv_{d}={s}\n",
            .{ aa, argToSlice(arg) },
        );
    }
    try writer.writeAll("argv_end\n");
    try buffered_writer.flush();
}

pub const ShaderType = enum {
    nodal_grey,
    nodal_rgb,
    tex8_grey,
    tex8_rgb,
    func,
    func_rgb,
};
const TextureSampleConfig = @import("../riley/zig/textureops.zig").TextureSampleConfig;
pub const TexFuncCoordMode = enum { uv, param };
pub const TexFuncCase = struct {
    builtin: so.TexFuncBuiltin,
    coord_mode: TexFuncCoordMode,
};

pub const BenchRenderDefaults = struct {
    pixels_num: [2]u32,
    sub_sample: u8,
    focal_leng: f64,
    pixels_size: [2]f64,
    fov_scale: f64,
    rot: Rotation,
};

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

pub fn calcCaseName(
    allocator: std.mem.Allocator,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    fov_scale: f64,
) ![]const u8 {
    const name = if (shader_type == .tex8_grey or shader_type == .tex8_rgb)
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}_{s}",
            .{
                @tagName(etype),
                @tagName(shader_type),
                @tagName(sample_config.?.sample),
                @tagName(sample_config.?.mode),
            },
        )
    else if (shader_type == .func or shader_type == .func_rgb)
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}_{s}_{s}",
            .{
                @tagName(etype),
                @tagName(shader_type),
                @tagName(tex_func_case.?.coord_mode),
                @tagName(tex_func_case.?.builtin),
            },
        )
    else
        try std.fmt.allocPrint(
            allocator,
            "{s}_{s}",
            .{ @tagName(etype), @tagName(shader_type) },
        );
    defer allocator.free(name);

    if (fov_scale < 0.99) {
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
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
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
    var shader: so.ShaderInput = undefined;
    switch (shader_type) {
        .nodal_grey, .nodal_rgb => {
            const field_raw = try loadNDArrayFromCSV(
                allocator,
                io,
                field_path,
                calcOutputChannels(shader_type),
                true,
            );
            shader = .{ .nodal = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.slice },
                .scaling = .none,
            } };
        },
        .tex8_grey => {
            const uvs_raw = try loadNDArrayFromCSV(
                allocator,
                io,
                uv_path,
                2,
                false,
            );
            shader = .{ .tex = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .sample_config = sample_config.?,
            } };
        },
        .tex8_rgb => {
            const uvs_raw = try loadNDArrayFromCSV(
                allocator,
                io,
                uv_path,
                2,
                false,
            );
            shader = .{ .tex_rgb = .{
                .uvs = uvs_raw,
                .texture = texture_rgb,
                .sample_config = sample_config.?,
            } };
        },
        .func => {
            const tex_case = tex_func_case.?;
            const tex_func_uvs = if (tex_case.coord_mode == .uv)
                try loadNDArrayFromCSV(
                    allocator,
                    io,
                    uv_path,
                    2,
                    false,
                )
            else
                null;
            shader = .{ .func = .{
                .uvs = tex_func_uvs,
                .builtin = tex_case.builtin,
                .params = calcTexFuncParams(tex_case),
                .bits = 8,
                .scaling = .none,
                .normal_type = .none,
            } };
        },
        .func_rgb => {
            const tex_case = tex_func_case.?;
            const tex_func_uvs = if (tex_case.coord_mode == .uv)
                try loadNDArrayFromCSV(
                    allocator,
                    io,
                    uv_path,
                    2,
                    false,
                )
            else
                null;
            shader = .{ .func_rgb = .{
                .uvs = tex_func_uvs,
                .builtin = tex_case.builtin,
                .params = calcTexFuncParams(tex_case),
                .bits = 8,
                .scaling = .none,
                .normal_type = .none,
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
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    data_dir: []const u8,
    render_defaults: BenchRenderDefaults,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    config: rastcfg.RasterConfig,
    out_dir_base: []const u8,
) !BenchResult {
    return runBenchmarkWithImageOut(
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        tex_func_case,
        data_dir,
        render_defaults,
        texture_grey,
        texture_rgb,
        config,
        out_dir_base,
        "",
    );
}

pub fn runBenchmarkWithImageOut(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    data_dir: []const u8,
    render_defaults: BenchRenderDefaults,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    config: rastcfg.RasterConfig,
    stats_out_dir_base: []const u8,
    image_out_dir_base: []const u8,
) !BenchResult {
    return runBenchmarkInternal(
        .bench,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        tex_func_case,
        data_dir,
        render_defaults,
        texture_grey,
        texture_rgb,
        config,
        stats_out_dir_base,
        image_out_dir_base,
    );
}

pub fn runBenchmarkQuiet(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    data_dir: []const u8,
    render_defaults: BenchRenderDefaults,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    config: rastcfg.RasterConfig,
    out_dir_base: []const u8,
) !BenchResult {
    return runBenchmarkQuietWithImageOut(
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        tex_func_case,
        data_dir,
        render_defaults,
        texture_grey,
        texture_rgb,
        config,
        out_dir_base,
        "",
    );
}

pub fn runBenchmarkQuietWithImageOut(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    data_dir: []const u8,
    render_defaults: BenchRenderDefaults,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    config: rastcfg.RasterConfig,
    stats_out_dir_base: []const u8,
    image_out_dir_base: []const u8,
) !BenchResult {
    return runBenchmarkInternal(
        .off,
        outer_alloc,
        io,
        etype,
        shader_type,
        sample_config,
        tex_func_case,
        data_dir,
        render_defaults,
        texture_grey,
        texture_rgb,
        config,
        stats_out_dir_base,
        image_out_dir_base,
    );
}

fn runBenchmarkInternal(
    comptime report_mode: rastcfg.ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    etype: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    data_dir: []const u8,
    render_defaults: BenchRenderDefaults,
    texture_grey: iio.Texture(1),
    texture_rgb: iio.Texture(3),
    config: rastcfg.RasterConfig,
    stats_out_dir_base: []const u8,
    image_out_dir_base: []const u8,
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
        tex_func_case,
        data_dir,
        texture_grey,
        texture_rgb,
    );
    _ = calcOutputChannels(shader_type);

    const roi_pos = cameraops.roiCentFromCoords(&mesh_input.coords);
    const cam_pos = cameraops.posFillFrameFromRot(
        &mesh_input.coords,
        render_defaults.pixels_num,
        render_defaults.pixels_size,
        render_defaults.focal_leng,
        render_defaults.rot,
        render_defaults.fov_scale,
    );
    const camera = try CameraPrepared.init(
        aa,
        .{
            .pixels_num = render_defaults.pixels_num,
            .pixels_size = render_defaults.pixels_size,
            .pos_world = cam_pos,
            .rot_world = render_defaults.rot,
            .roi_cent_world = roi_pos,
            .focal_length = render_defaults.focal_leng,
            .sub_sample = render_defaults.sub_sample,
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

    var config_run = config;
    config_run.report = report_mode;

    if (stats_out_dir_base.len > 0) {
        var out_dir = try orch.openDirEnsured(io, stats_out_dir_base);
        out_dir.close(io);
    }

    const case_name = try calcCaseName(
        aa,
        etype,
        shader_type,
        sample_config,
        tex_func_case,
        render_defaults.fov_scale,
    );
    const out_path = if (image_out_dir_base.len > 0)
        image_out_dir_base
    else if (stats_out_dir_base.len > 0)
        try std.fs.path.join(
            aa,
            &[_][]const u8{ stats_out_dir_base, case_name },
        )
    else
        null;

    if (out_path) |case_out_path| {
        var case_out_dir = try orch.openDirEnsured(io, case_out_path);
        case_out_dir.close(io);
    }

    var bench_capture_storage: [1]report.FrameBenchCapture = undefined;
    const bench_capture = if (report_mode == .bench)
        bench_capture_storage[0..]
    else
        null;

    const e2e_start = Timestamp.now(io, .awake);
    const render_groups = [_]riley.RenderGroupSpec{
        .{ .io = io, .workers = @max(@as(u16, 1), config_run.total_threads) },
    };
    var image_arr = try riley.rasterAllFramesReport(
        outer_alloc,
        &render_groups,
        &[_]CameraInput{camera_input},
        &[_]mo.MeshInput{mesh_input},
        config_run,
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
    const metrics = if (report_mode == .bench)
        calcMetrics(
            etype,
            camera.pixels_num,
            camera.sub_sample,
            e2e_ms,
            bench_capture_storage[0].bench_log.frame_times,
            bench_capture_storage[0].bench_log,
        )
    else
        CalculatedMetrics{
            .raster_tpx_mpx_s = 0.0,
            .frame_tpx_mpx_s = 0.0,
            .e2e_tpx_mpx_s = 0.0,
            .msubpx_sec = 0.0,
            .mshades_sec = 0.0,
            .msubshades_sec = 0.0,
            .melems_sec = 0.0,
            .mnodes_sec = 0.0,
            .mops_sec = 0.0,
        };

    const return_image = (config.save_strategy == .memory or config.save_strategy == .both);

    const image_final = if (return_image) blk: {
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
        .cam_ms = if (report_mode == .bench)
            pipeline_times.cam_invert / 1e6
        else
            0.0,
        .resolve_ms = if (report_mode == .bench)
            pipeline_times.scratch_resolve / 1e6
        else
            0.0,
        .fps = if (e2e_ms > 0.0) 1000.0 / e2e_ms else 0.0,
        .total_elems = if (report_mode == .bench)
            bench_capture_storage[0].bench_log.total_elements
        else
            0,
        .vis_elems = if (report_mode == .bench)
            bench_capture_storage[0].bench_log.visible_elements
        else
            0,
        .total_px = @as(u64, camera.pixels_num[0]) *
            @as(u64, camera.pixels_num[1]),
        .shaded_px = if (report_mode == .bench)
            bench_capture_storage[0].bench_log.total_shaded_pixels
        else
            0,
        .metrics = metrics,
        .pipeline_times = pipeline_times,
        .image = image_final,
    };
}

fn argToSlice(arg: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(arg))) {
        .pointer => |pointer_info| switch (pointer_info.size) {
            .slice => arg,
            else => std.mem.span(arg),
        },
        .array => arg[0..],
        else => @compileError("Unsupported command line argument type."),
    };
}

fn printPaddedSafe(writer: anytype, text: []const u8, width: usize) !void {
    try writer.writeAll(text);
    for (text.len..width) |_| {
        try writer.writeByte(' ');
    }
}

fn calcTexFuncParams(tex_func_case: TexFuncCase) so.TexFuncParams {
    const pi: f64 = std.math.pi;
    const oscillations: f64 = if (tex_func_case.coord_mode == .param)
        2.0
    else
        6.0;
    const wave_num = 2.0 * pi * oscillations;

    return switch (tex_func_case.builtin) {
        .sinusoidal => .{
            .wave_num_scalar = .{ wave_num, wave_num },
            .wave_num_rgb = .{ wave_num, wave_num, wave_num },
        },
        else => .{},
    };
}

fn calcVariantName(
    stats: BenchStats,
) []const u8 {
    if (stats.sample_config) |sample_config| {
        return @tagName(sample_config.sample);
    }
    if (stats.tex_func_case) |tex_func_case| {
        return @tagName(tex_func_case.builtin);
    }
    return "nodal";
}

pub const BenchmarkCSVKind = enum {
    median,
    min,
    max,
    mad,
    cov,
};

pub const BenchmarkCSVValues = struct {
    total_elems: f64,
    vis_elems: f64,
    total_px: f64,
    shaded_px: f64,
    geom: f64,
    cam_invert: f64,
    elem_loop: f64,
    scratch_resolve: f64,
    raster: f64,
    save_frame: f64,
    frame: f64,
    e2e: f64,
    geom_tpx: f64,
    raster_tpx: f64,
    frame_tpx: f64,
    e2e_tpx: f64,
};

pub fn benchmarkCSVHeader() []const u8 {
    return "Case,Element,Shader,Interpolator," ++
        "Total Elems,Vis Elems,Total Px,Shaded Px," ++
        "Geom Time [ms]," ++
        "Cam Inv Time [ms],Elem Loop Time [ms]," ++
        "Resolve Time [ms],Raster Time [ms]," ++
        "Save Time [ms],Frame Time [ms]," ++
        "E2E Time [ms],Geom TP [MElem/s],Raster TP [MPx/s]," ++
        "Frame TP [MPx/s],E2E TP [MPx/s]\n";
}

fn calcCoVPercent(stats: MedianMAD) f64 {
    if (stats.median == 0.0) {
        return 0.0;
    }
    return stats.mad / stats.median * 100.0;
}

fn selectStatValue(
    stats: MedianMAD,
    kind: BenchmarkCSVKind,
) f64 {
    return switch (kind) {
        .median => stats.median,
        .min => stats.min,
        .max => stats.max,
        .mad => stats.mad,
        .cov => calcCoVPercent(stats),
    };
}

pub fn calcBenchmarkCSVValuesFromStats(
    stats: BenchStats,
    kind: BenchmarkCSVKind,
) BenchmarkCSVValues {
    return .{
        .total_elems = selectStatValue(stats.total_elems, kind),
        .vis_elems = selectStatValue(stats.vis_elems, kind),
        .total_px = selectStatValue(stats.total_px, kind),
        .shaded_px = selectStatValue(stats.shaded_px, kind),
        .geom = selectStatValue(stats.geom, kind),
        .cam_invert = selectStatValue(stats.cam_invert, kind),
        .elem_loop = selectStatValue(stats.elem_loop, kind),
        .scratch_resolve = selectStatValue(
            stats.scratch_resolve,
            kind,
        ),
        .raster = selectStatValue(stats.raster, kind),
        .save_frame = selectStatValue(stats.save, kind),
        .frame = selectStatValue(stats.frame, kind),
        .e2e = selectStatValue(stats.e2e, kind),
        .geom_tpx = selectStatValue(stats.geom_tpx, kind),
        .raster_tpx = selectStatValue(
            stats.raster_tpx,
            kind,
        ),
        .frame_tpx = selectStatValue(stats.frame_tpx, kind),
        .e2e_tpx = selectStatValue(stats.e2e_tpx, kind),
    };
}

pub fn calcBenchmarkCSVValuesFromResult(
    result: BenchResult,
) BenchmarkCSVValues {
    const conv_ms = 1.0 / 1e6;
    const cam_inv_ms = result.cam_ms;
    const resolve_ms = result.resolve_ms;
    const elem_loop_ms = result.raster_ms - cam_inv_ms - resolve_ms;
    return .{
        .total_elems = @floatFromInt(result.total_elems),
        .vis_elems = @floatFromInt(result.vis_elems),
        .total_px = @floatFromInt(result.total_px),
        .shaded_px = @floatFromInt(result.shaded_px),
        .geom = result.geom_ms,
        .cam_invert = cam_inv_ms,
        .elem_loop = elem_loop_ms,
        .scratch_resolve = resolve_ms,
        .raster = result.raster_ms,
        .save_frame = result.pipeline_times.save_frame * conv_ms,
        .frame = result.pipeline_times.active_time * conv_ms,
        .e2e = result.e2e_ms,
        .geom_tpx = result.metrics.melems_sec,
        .raster_tpx = result.metrics.raster_tpx_mpx_s,
        .frame_tpx = result.metrics.frame_tpx_mpx_s,
        .e2e_tpx = result.metrics.e2e_tpx_mpx_s,
    };
}

pub fn formatBenchmarkCSVRow(
    allocator: std.mem.Allocator,
    case_name: []const u8,
    mesh_type: gk.MeshType,
    shader_type: ShaderType,
    sample_config: ?TextureSampleConfig,
    tex_func_case: ?TexFuncCase,
    values: BenchmarkCSVValues,
) ![]u8 {
    const variant_name = if (sample_config) |sc|
        @tagName(sc.sample)
    else if (tex_func_case) |tf|
        @tagName(tf.builtin)
    else
        "nodal";

    return std.fmt.allocPrint(
        allocator,
        "{s},{s},{s},{s}," ++
            "{d:.6},{d:.6},{d:.6},{d:.6}," ++
            "{d:.6},{d:.6},{d:.6},{d:.6}," ++
            "{d:.6},{d:.6},{d:.6}," ++
            "{d:.6},{d:.6},{d:.6},{d:.6},{d:.6}\n",
        .{
            case_name,
            @tagName(mesh_type),
            @tagName(shader_type),
            variant_name,
            values.total_elems,
            values.vis_elems,
            values.total_px,
            values.shaded_px,
            values.geom,
            values.cam_invert,
            values.elem_loop,
            values.scratch_resolve,
            values.raster,
            values.save_frame,
            values.frame,
            values.e2e,
            values.geom_tpx,
            values.raster_tpx,
            values.frame_tpx,
            values.e2e_tpx,
        },
    );
}

fn writeBenchmarkStatsCSV(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    out_dir_base: []const u8,
    stats_list: []const BenchStats,
    kind: BenchmarkCSVKind,
    file_name: []const u8,
) !void {
    const csv_name = try std.fs.path.join(
        outer_alloc,
        &[_][]const u8{ out_dir_base, file_name },
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

    try writer.writeAll(benchmarkCSVHeader());

    for (stats_list) |s| {
        const row = try formatBenchmarkCSVRow(
            outer_alloc,
            s.name,
            s.mesh_type,
            s.shader_type,
            s.sample_config,
            s.tex_func_case,
            calcBenchmarkCSVValuesFromStats(s, kind),
        );
        defer outer_alloc.free(row);
        try writer.writeAll(row);
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
    _ = title;
    _ = pixel_num;
    _ = max_name_len;

    try writeBenchmarkStatsCSV(
        outer_alloc,
        io,
        out_dir_base,
        stats_list,
        .median,
        "bench_stats_median.csv",
    );
    try writeBenchmarkStatsCSV(
        outer_alloc,
        io,
        out_dir_base,
        stats_list,
        .min,
        "bench_stats_min.csv",
    );
    try writeBenchmarkStatsCSV(
        outer_alloc,
        io,
        out_dir_base,
        stats_list,
        .max,
        "bench_stats_max.csv",
    );
    try writeBenchmarkStatsCSV(
        outer_alloc,
        io,
        out_dir_base,
        stats_list,
        .mad,
        "bench_stats_mad.csv",
    );
    try writeBenchmarkStatsCSV(
        outer_alloc,
        io,
        out_dir_base,
        stats_list,
        .cov,
        "bench_stats_cov.csv",
    );
}
