// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const benchargs = @import("dev_support/benchargs.zig");
const benchstats = @import("dev_support/benchstats.zig");
const tcfg = @import("dev_support/testconfig.zig");
const common = @import("dev_support/benchcommon.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const riley = @import("riley/zig/riley.zig");
const cam = @import("riley/zig/camera.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const texops = @import("riley/zig/textureops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const F = buildconfig.F;

const config = common.BenchConfig{ .run = .all };

const DEFAULT_OUT_DIR = "out/bench_stats_tiltraster";
const DEFAULT_IMAGE_OUT_DIR = "out/bench_images_tiltraster";
const DEFAULT_DATA_DIR_SUFFIX = "fullraster";
const DEFAULT_PIXELS_NUM = [2]u32{ 1600, 1000 };
const DEFAULT_SUB_SAMPLE: u32 = 2;
const DEFAULT_FOCAL_LENG: F = @floatCast(50.0e-3);
const DEFAULT_PIXELS_SIZE = [2]F{
    @floatCast(5.3e-6),
    @floatCast(5.3e-6),
};
const DEFAULT_FOV_SCALE: F = 1.0;
const DEFAULT_TEX_GREY_PATH = "texture/speckle_mono.bmp";
const DEFAULT_TEX_RGB_PATH = "texture/speckle_rgb.bmp";
const DEFAULT_ROT = Rotation.init(0, 0, 0);
const texture_shader_types = [_]common.ShaderType{
    .tex8_grey,
    .tex8_rgb,
};

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    var base_raster_config = tcfg.getRasterConfig(.bench);
    base_raster_config.output.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };
    base_raster_config.save_strategy = .memory;
    var default_bench_args = benchargs.defaultBenchArgs(
        DEFAULT_OUT_DIR,
        base_raster_config,
    );
    default_bench_args.image_out_dir = DEFAULT_IMAGE_OUT_DIR;
    default_bench_args.pixels_num = DEFAULT_PIXELS_NUM;
    default_bench_args.sub_sample = DEFAULT_SUB_SAMPLE;

    const bench_args = try benchargs.parseArgsWithDefaults(
        init.minimal.args.vector,
        default_bench_args,
    );
    var threaded_io = riley.getThreadedIo(
        outer_alloc,
        init.minimal,
        bench_args.total_threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const distort_model: cam.DistortParams = switch (bench_args.distort) {
        .none => .none,
        .brown => .{
            .brown_con = .{
                .k1 = -0.08,
                .k2 = 0.01,
                .k3 = -0.002,
                .p1 = 0.0004,
                .p2 = -0.0007,
            },
        },
        .brownext => .{
            .brown_con_ext = .{
                .k1 = -0.09,
                .k2 = 0.012,
                .k3 = -0.0015,
                .k4 = 0.004,
                .k5 = -0.0008,
                .k6 = 0.00015,
                .p1 = 0.0005,
                .p2 = -0.0006,
                .s1 = 0.0,
                .s2 = 0.0,
                .s3 = 0.0,
                .s4 = 0.0,
                .tau_x = 0.0,
                .tau_y = 0.0,
            },
        },
    };

    const render_defaults = common.BenchRenderDefaults{
        .pixels_num = bench_args.pixels_num,
        .sub_sample = bench_args.sub_sample,
        .focal_leng = DEFAULT_FOCAL_LENG,
        .pixels_size = DEFAULT_PIXELS_SIZE,
        .fov_scale = DEFAULT_FOV_SCALE,
        .rot = DEFAULT_ROT,
        .distort = distort_model,
    };

    const mesh_types = comptime std.enums.values(gk.MeshType);
    const shader_types = [_]common.ShaderType{
        .nodal_grey,
        .nodal_rgb,
        .tex8_grey,
        .tex8_rgb,
    };
    const tex_func_shader_types = [_]common.ShaderType{
        .func,
        .func_rgb,
    };
    const samp_cfgs = [_]texops.TextureSampleConfig{
        .{ .sample = .linear, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .direct },
        .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
        .{ .sample = .cubic_mitchell_netravali, .mode = .direct },
        .{ .sample = .cubic_mitchell_netravali, .mode = .lut_lerp },
        .{ .sample = .lanczos3, .mode = .direct },
        .{ .sample = .lanczos3, .mode = .lut_lerp },
        .{ .sample = .cubic_bspline, .mode = .direct },
        .{ .sample = .cubic_bspline, .mode = .lut_lerp },
        .{ .sample = .quintic_bspline, .mode = .direct },
        .{ .sample = .quintic_bspline, .mode = .lut_lerp },
    };
    const tex_func_cases = [_]common.TexFuncCase{
        .{ .builtin = .constant, .coord_mode = .param },
        .{ .builtin = .constant, .coord_mode = .uv },
        .{ .builtin = .linear, .coord_mode = .param },
        .{ .builtin = .linear, .coord_mode = .uv },
        .{ .builtin = .quadratic, .coord_mode = .param },
        .{ .builtin = .quadratic, .coord_mode = .uv },
        .{ .builtin = .sinusoidal, .coord_mode = .param },
        .{ .builtin = .sinusoidal, .coord_mode = .uv },
        .{ .builtin = .sinusoidal_approx, .coord_mode = .param },
        .{ .builtin = .sinusoidal_approx, .coord_mode = .uv },
    };
    const shaderpipe_func_cases = [_]common.TexFuncCase{
        .{ .builtin = .checker, .coord_mode = .param },
    };
    const multisource_func_cases = [_]common.TexFuncCase{
        .{ .builtin = .checker, .coord_mode = .world_reference },
    };

    var stats = try benchstats.BenchStatsCollector.init(
        outer_alloc,
        bench_args.runs,
    );
    defer stats.deinit(outer_alloc);

    std.debug.print(
        "Starting Tilt Raster Benchmark ({d}x{d}, {d} run per case, {d} threads)...\n",
        .{
            bench_args.pixels_num[0],
            bench_args.pixels_num[1],
            bench_args.runs,
            bench_args.total_threads,
        },
    );

    const bench_raster_config = benchargs.applyRasterConfig(
        base_raster_config,
        bench_args,
    );
    const actual_tile_size = common.calcActualTileSize(
        bench_raster_config,
        bench_args.pixels_num,
        bench_args.sub_sample,
        0,
    );
    const render_group_workers = [_]u16{bench_args.total_threads};
    try common.writeBenchmarkConfig(
        outer_alloc,
        io,
        bench_args.out_dir,
        bench_args.image_out_dir,
        "bench_tiltraster.zig",
        init.minimal.args.vector,
        bench_args.subpixel_center_map,
        bench_raster_config,
        render_group_workers[0..],
        bench_args.pixels_num,
        bench_args.sub_sample,
        bench_args.runs,
        DEFAULT_FOV_SCALE,
        actual_tile_size,
    );
    try writeStudyMetadata(
        outer_alloc,
        io,
        bench_args.out_dir,
        bench_args,
    );

    switch (bench_args.texture_storage) {
        .u8 => try runBenchmarksForTextureType(
            u8,
            outer_alloc,
            io,
            &stats,
            bench_args,
            base_raster_config,
            render_defaults,
            mesh_types[0..],
            shader_types[0..],
            tex_func_shader_types[0..],
            samp_cfgs[0..],
            if (bench_args.shader_subset == .shaderpipe_multisource)
                multisource_func_cases[0..]
            else if (bench_args.shader_subset == .shaderpipe_baseline or
                bench_args.shader_subset == .shaderpipe_compare)
                shaderpipe_func_cases[0..]
            else
                tex_func_cases[0..],
        ),
        .u16 => try runBenchmarksForTextureType(
            u16,
            outer_alloc,
            io,
            &stats,
            bench_args,
            base_raster_config,
            render_defaults,
            mesh_types[0..],
            shader_types[0..],
            tex_func_shader_types[0..],
            samp_cfgs[0..],
            if (bench_args.shader_subset == .shaderpipe_multisource)
                multisource_func_cases[0..]
            else if (bench_args.shader_subset == .shaderpipe_baseline or
                bench_args.shader_subset == .shaderpipe_compare)
                shaderpipe_func_cases[0..]
            else
                tex_func_cases[0..],
        ),
    }

    try stats.writeRunCSVs(outer_alloc, io, bench_args.out_dir);
    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "Tilt Raster Benchmark Results",
        bench_args.out_dir,
        bench_args.pixels_num,
        stats.stats_list.items,
        0,
    );
}

fn runBenchmarksForTextureType(
    comptime T: type,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    stats: *benchstats.BenchStatsCollector,
    bench_args: benchargs.BenchArgs,
    base_raster_config: rastcfg.RasterConfig,
    render_defaults: common.BenchRenderDefaults,
    mesh_types: []const gk.MeshType,
    shader_types: []const common.ShaderType,
    tex_func_shader_types: []const common.ShaderType,
    samp_cfgs: []const texops.TextureSampleConfig,
    tex_func_cases: []const common.TexFuncCase,
) !void {
    const texture_grey = try loadBenchmarkTexture(
        T,
        1,
        outer_alloc,
        io,
        DEFAULT_TEX_GREY_PATH,
    );
    defer texture_grey.deinit(outer_alloc);
    const texture_rgb = try loadBenchmarkTexture(
        T,
        3,
        outer_alloc,
        io,
        DEFAULT_TEX_RGB_PATH,
    );
    defer texture_rgb.deinit(outer_alloc);

    for (mesh_types) |mt| {
        if (!shouldRunMeshType(bench_args.mesh_subset, mt)) {
            continue;
        }
        if (mt == .tri3opt and !cam.isNoDistort(render_defaults.distort)) {
            continue;
        }
        const selected_shader_types = if (bench_args.shader_subset == .texture)
            texture_shader_types[0..]
        else
            shader_types;
        for (selected_shader_types) |st| {
            if (bench_args.shader_subset == .shaderpipe_multisource) continue;
            for (samp_cfgs) |sc| {
                if (bench_args.shader_subset == .shaderpipe_baseline or
                    bench_args.shader_subset == .shaderpipe_compare)
                {
                    if (st != .nodal_grey and st != .tex8_grey) continue;
                    if (st == .tex8_grey and
                        (sc.mode != .direct or
                            (sc.sample != .linear and sc.sample != .cubic_catmull_rom)))
                    {
                        continue;
                    }
                }
                var data_dir_buf: [256]u8 = undefined;
                const folder_name = if (mt == .tri3opt) "tri3" else @tagName(mt);
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf,
                    "data/tilt/{s}_{s}",
                    .{ folder_name, DEFAULT_DATA_DIR_SUFFIX },
                );

                if (common.shouldRun(config, mt, st, sc, data_dir)) {
                    const samp_cfg = if (st == .tex8_grey or st == .tex8_rgb)
                        sc
                    else
                        null;
                    try runShaderCase(
                        T,
                        outer_alloc,
                        io,
                        stats,
                        bench_args,
                        base_raster_config,
                        render_defaults,
                        texture_grey,
                        texture_rgb,
                        mt,
                        st,
                        samp_cfg,
                        null,
                        data_dir,
                    );
                }
            }
        }

        if (bench_args.shader_subset == .texture) {
            continue;
        }

        for (tex_func_shader_types) |st| {
            for (tex_func_cases) |tex_func_case| {
                if (bench_args.shader_subset == .shaderpipe_multisource and
                    (st != .func or tex_func_case.builtin != .checker or
                        tex_func_case.coord_mode != .world_reference))
                {
                    continue;
                }
                if ((bench_args.shader_subset == .shaderpipe_baseline or
                    bench_args.shader_subset == .shaderpipe_compare) and
                    (st != .func or tex_func_case.builtin != .checker or
                        tex_func_case.coord_mode != .param))
                {
                    continue;
                }
                var data_dir_buf: [256]u8 = undefined;
                const folder_name = if (mt == .tri3opt) "tri3" else @tagName(mt);
                const data_dir = try std.fmt.bufPrint(
                    &data_dir_buf,
                    "data/tilt/{s}_{s}",
                    .{ folder_name, DEFAULT_DATA_DIR_SUFFIX },
                );
                try runShaderCase(
                    T,
                    outer_alloc,
                    io,
                    stats,
                    bench_args,
                    base_raster_config,
                    render_defaults,
                    texture_grey,
                    texture_rgb,
                    mt,
                    st,
                    null,
                    tex_func_case,
                    data_dir,
                );
            }
        }
    }
}

fn runShaderCase(
    comptime T: type,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    stats: *benchstats.BenchStatsCollector,
    bench_args: benchargs.BenchArgs,
    base_raster_config: rastcfg.RasterConfig,
    render_defaults: common.BenchRenderDefaults,
    texture_grey: texops.Tex(T, 1),
    texture_rgb: texops.Tex(T, 3),
    mt: gk.MeshType,
    st: common.ShaderType,
    samp_cfg: ?texops.TextureSampleConfig,
    tex_func_case: ?common.TexFuncCase,
    data_dir: []const u8,
) !void {
    const multisource = bench_args.shader_subset == .shaderpipe_multisource;
    const compare = bench_args.shader_subset == .shaderpipe_compare or multisource;
    const paths: []const common.BenchShaderPath = if (compare)
        if (multisource)
            &.{ .direct, .multi_source_pipe }
        else
            &.{ .direct, .one_stage_pipe }
    else
        &.{.direct};
    const base_name = try common.calcCaseName(
        outer_alloc,
        mt,
        st,
        samp_cfg,
        tex_func_case,
        1.0,
    );
    defer outer_alloc.free(base_name);
    const direct_name = if (compare)
        try std.fmt.allocPrint(outer_alloc, "{s}_direct", .{base_name})
    else
        base_name;
    defer if (compare) outer_alloc.free(direct_name);
    const pipe_name = if (multisource)
        try std.fmt.allocPrint(outer_alloc, "{s}_multi_source_pipe", .{base_name})
    else if (compare)
        try std.fmt.allocPrint(outer_alloc, "{s}_one_stage_pipe", .{base_name})
    else
        "";
    defer if (compare) outer_alloc.free(pipe_name);
    const names = [_][]const u8{ direct_name, pipe_name };

    var samples = [_]benchstats.CaseSamples{
        try benchstats.CaseSamples.init(outer_alloc, bench_args.runs),
        try benchstats.CaseSamples.init(outer_alloc, bench_args.runs),
    };
    defer for (&samples) |*sample| sample.deinit(outer_alloc);

    const note_str = if (multisource)
        " (direct / three-source pipe)"
    else if (compare)
        " (direct / one-stage pipe)"
    else
        "";
    std.debug.print("Case: {s}{s}\n", .{ base_name, note_str });
    const run_out_dir_base = if (bench_args.save_strategy == .disk or
        bench_args.save_strategy == .both)
        bench_args.out_dir
    else
        "";
    const raster_config = benchargs.applyRasterConfig(base_raster_config, bench_args);

    for (0..bench_args.runs) |rr| {
        for (0..paths.len) |ii| {
            const path_idx = if (rr % 2 == 0) ii else paths.len - 1 - ii;
            var case_defaults = render_defaults;
            case_defaults.shader_path = paths[path_idx];
            var res = try common.runBenchmarkWithImageOut(
                T,
                outer_alloc,
                io,
                mt,
                st,
                samp_cfg,
                tex_func_case,
                data_dir,
                case_defaults,
                texture_grey,
                texture_rgb,
                raster_config,
                run_out_dir_base,
                bench_args.image_out_dir,
            );
            defer res.deinit(outer_alloc);
            try stats.appendRunResult(
                outer_alloc,
                rr,
                names[path_idx],
                mt,
                st,
                samp_cfg,
                tex_func_case,
                res,
            );
            samples[path_idx].record(rr, res);
        }
        try stats.writeRunCSV(outer_alloc, io, bench_args.out_dir, rr);
    }

    for (paths, 0..) |_, idx| {
        try stats.appendCaseStats(
            outer_alloc,
            names[idx],
            mt,
            st,
            samp_cfg,
            tex_func_case,
            &samples[idx],
        );
    }
}

fn shouldRunMeshType(
    mesh_subset: benchargs.MeshSubset,
    mesh_type: gk.MeshType,
) bool {
    return switch (mesh_subset) {
        .all => true,
        .tri3 => mesh_type == .tri3,
        .tri3opt => mesh_type == .tri3opt,
        .tri3_compare => mesh_type == .tri3 or mesh_type == .tri3opt,
    };
}

fn writeStudyMetadata(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    out_dir: []const u8,
    bench_args: benchargs.BenchArgs,
) !void {
    const meta_path = try std.fs.path.join(
        outer_alloc,
        &[_][]const u8{ out_dir, "study_meta.txt" },
    );
    defer outer_alloc.free(meta_path);

    const cwd = std.Io.Dir.cwd();
    var file = try cwd.createFile(io, meta_path, .{});
    defer file.close(io);

    var write_buf: [1024]u8 = undefined;
    var buffered_writer = file.writer(io, &write_buf);
    const writer = &buffered_writer.interface;

    try writer.print("texture_storage={s}\n", .{
        @tagName(bench_args.texture_storage),
    });
    try writer.print("shader_subset={s}\n", .{
        @tagName(bench_args.shader_subset),
    });
    try writer.print("mesh_subset={s}\n", .{
        @tagName(bench_args.mesh_subset),
    });
    try writer.print("distort={s}\n", .{
        @tagName(bench_args.distort),
    });
    try buffered_writer.flush();
}

fn loadBenchmarkTexture(
    comptime T: type,
    comptime channels: usize,
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !texops.Tex(T, channels) {
    if (T == u8) {
        return iio.loadImage(
            u8,
            channels,
            allocator,
            io,
            path,
            .bmp,
        );
    }
    if (T == u16) {
        return scaleTexture8To16(
            channels,
            allocator,
            try iio.loadImage(
                u8,
                channels,
                allocator,
                io,
                path,
                .bmp,
            ),
        );
    }
    @compileError("Unsupported benchmark texture storage type.");
}

fn scaleTexture8To16(
    comptime channels: usize,
    allocator: std.mem.Allocator,
    texture_u8: texops.Tex(u8, channels),
) !texops.Tex(u16, channels) {
    defer texture_u8.deinit(allocator);

    var texture_u16 = try texops.Tex(u16, channels).init(
        allocator,
        texture_u8.rows_num,
        texture_u8.cols_num,
    );
    errdefer texture_u16.deinit(allocator);

    for (0..channels) |ch| {
        for (0..texture_u8.rows_num) |rr| {
            for (0..texture_u8.cols_num) |cc| {
                const px_u8 = texture_u8.getVal(ch, rr, cc);
                const px_u16 = @as(u16, px_u8) * 257;
                texture_u16.setVal(ch, rr, cc, px_u16);
            }
        }
    }

    return texture_u16;
}
