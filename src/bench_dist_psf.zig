// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const benchstats = @import("dev_support/benchstats.zig");
const tcfg = @import("dev_support/testconfig.zig");
const common = @import("dev_support/benchcommon.zig");
const orch = @import("dev_support/orchestration.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const riley = @import("riley/zig/riley.zig");
const cam = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const report = @import("riley/zig/report.zig");
const NDArray = @import("riley/zig/ndarray.zig").NDArray;
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const F = buildconfig.F;
const Timestamp = std.Io.Clock.Timestamp;

const DEFAULT_OUT_DIR = "out/bench_stats_dist_psf";
const DEFAULT_IMAGE_OUT_DIR = "out/bench_images_dist_psf";
const DEFAULT_PIXELS_NUM = [2]u32{ 800, 500 };
const DEFAULT_SUB_SAMPLE: u32 = 2;
const DEFAULT_FOCAL_LENG: F = 50.0e-3;
const DEFAULT_PIXEL_SIZE = [2]F{ 5.0e-6, 5.0e-6 };
const DEFAULT_ROT = Rotation.init(0, 0, 0);

pub const DistortCase = enum {
    all,
    none,
    brown_zero,
    brown_ext_zero,
    brown_pincushion,
    brown_ext_pincushion,
    poly_zero,
    poly_deg3_pincushion,
    poly_deg5_pincushion,
    poly_deg7_pincushion,
};

pub const PSFCase = enum {
    all,
    pixel_box,
    gaussian_0p5,
    gaussian_1p5,
    aniso_gaussian_0p5_0p25,
    aniso_gaussian_1p5_0p5,
};

pub const MeshDensity = enum {
    all,
    fullraster,
    @"1e2",
    @"1e3",
    @"1e4",
    @"1e5",
};

pub const MeshSubset = enum {
    all,
    tri3,
    tri6,
    quad4,
    quad8,
    quad9,
};

const poly_zero_coeffs = [_]F{0} ** 6;

// Degree 1: 3 terms -> 6 coeffs
const poly_deg1_pincushion_coeffs = [_]F{
    0, 0, // 1
    -0.05, 0, // x
    0, -0.05, // y
};

// Degree 3: 10 terms -> 20 coeffs
// Terms: 1, x, y, x², xy, y², x³, x²y, xy², y³
const poly_deg3_pincushion_coeffs = [_]F{
    0, 0, // 1
    0, 0, // x
    0, 0, // y
    0, 0, // x²
    0, 0, // xy
    0, 0, // y²
    -50.0, 0.0, // x³
    0.0, -50.0, // x²y
    -50.0, 0.0, // xy²
    0.0, -50.0, // y³
};

// Degree 5: 21 terms -> 42 coeffs
const poly_deg5_pincushion_coeffs = [_]F{
    0, 0, // 1
    0, 0, // x
    0, 0, // y
    0, 0, // x²
    0, 0, // xy
    0, 0, // y²
    -50.0, 0.0, // x³
    0.0, -50.0, // x²y
    -50.0, 0.0, // xy²
    0.0, -50.0, // y³
    0, 0, // x⁴
    0, 0, // x³y
    0, 0, // x²y²
    0, 0, // xy³
    0, 0, // y⁴
    5000.0, 0.0, // x⁵
    0.0, 5000.0, // x⁴y
    10000.0, 0.0, // x³y²
    0.0, 10000.0, // x²y³
    5000.0, 0.0, // xy⁴
    0.0, 5000.0, // y⁵
};

// Degree 7: 36 terms -> 72 coeffs
const poly_deg7_pincushion_coeffs = [_]F{
    0, 0, // 1
    0, 0, // x
    0, 0, // y
    0, 0, // x²
    0, 0, // xy
    0, 0, // y²
    -50.0, 0.0, // x³
    0.0, -50.0, // x²y
    -50.0, 0.0, // xy²
    0.0, -50.0, // y³
    0, 0, // x⁴
    0, 0, // x³y
    0, 0, // x²y²
    0, 0, // xy³
    0, 0, // y⁴
    5000.0, 0.0, // x⁵
    0.0, 5000.0, // x⁴y
    10000.0, 0.0, // x³y²
    0.0, 10000.0, // x²y³
    5000.0, 0.0, // xy⁴
    0.0, 5000.0, // y⁵
    0, 0, // x⁶
    0, 0, // x⁵y
    0, 0, // x⁴y²
    0, 0, // x³y³
    0, 0, // x²y⁴
    0, 0, // xy⁵
    0, 0, // y⁶
    0, 0, // x⁷
    0, 0, // x⁶y
    0, 0, // x⁵y²
    0, 0, // x⁴y³
    0, 0, // x³y⁴
    0, 0, // x²y⁵
    0, 0, // xy⁶
    0, 0, // y⁷
};

pub const BenchDistPsfArgs = struct {
    out_dir: []const u8 = DEFAULT_OUT_DIR,
    image_out_dir: []const u8 = "",
    mesh_subset: MeshSubset = .all,
    mesh_density: MeshDensity = .all,
    distort_case: DistortCase = .all,
    psf_case: PSFCase = .all,
    runs: usize = 10,
    frames: usize = 2,
    total_threads: u16 = 1,
    max_raster_workers_per_job: u16 = 1,
    hull_mode: rastcfg.HullMode = .on_convex_fallback,
    subpixel_center_map: cam.SubPixelCenterMap = .per_tile,
    save_strategy: rastcfg.SaveStrategy = .memory,
};

fn printUsage() void {
    std.debug.print(
        \\Usage: bench_dist_psf [options]
        \\
        \\Options:
        \\  --out-dir <dir>                    Output directory for CSV stats
        \\  --image-out-dir <dir>              Output directory for rendered images
        \\  --mesh-subset <name>               Mesh subset (all, tri3, tri6,
        \\                                     quad4, quad8, quad9)
        \\  --mesh-density <name>              Mesh density (all, fullraster,
        \\                                     1e2, 1e3, 1e4, 1e5)
        \\  --distort <name>                   Distortion case (all, none,
        \\                                     brown_zero, brown_ext_zero,
        \\                                     brown_pincushion,
        \\                                     brown_ext_pincushion, poly_zero,
        \\                                     poly_deg1_pincushion,
        \\                                     poly_deg3_pincushion,
        \\                                     poly_deg5_pincushion,
        \\                                     poly_deg7_pincushion)
        \\  --psf <name>                       PSF case (all, pixel_box,
        \\                                     gaussian_0p5, gaussian_1p5,
        \\                                     aniso_gaussian_0p5_0p25,
        \\                                     aniso_gaussian_1p5_0p5)
        \\  --runs <N>                         Number of benchmark runs (default: 10)
        \\  --frames <N>                       Number of frames per run (default: 2)
        \\  --total-threads <N>                Total threads (default: 1)
        \\  --max-raster-workers-per-job <N>   Max raster workers (default: 1)
        \\  --hull-mode <mode>                 Hull mode (default: on_convex_fallback)
        \\  --subpixel-center-map <mode>       Subpixel center map (default: per_tile)
        \\  --save-strategy <mode>             Save strategy (default: memory)
        \\  -h, --help                         Show this help message
        \\
    , .{});
}

fn parseDistPsfArgs(args: anytype) !BenchDistPsfArgs {
    var result = BenchDistPsfArgs{};
    var skip_next = false;

    for (args[1..], 1..) |raw_arg, ii| {
        if (skip_next) {
            skip_next = false;
            continue;
        }
        const arg = std.mem.sliceTo(raw_arg, 0);
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            std.process.exit(0);
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (ii + 1 >= args.len) {
                return error.MissingArgumentValue;
            }
            const val = std.mem.sliceTo(args[ii + 1], 0);
            skip_next = true;

            if (std.mem.eql(u8, arg, "--out-dir")) {
                result.out_dir = val;
            } else if (std.mem.eql(u8, arg, "--image-out-dir")) {
                result.image_out_dir = val;
            } else if (std.mem.eql(u8, arg, "--mesh-subset")) {
                result.mesh_subset = std.meta.stringToEnum(MeshSubset, val) orelse
                    return error.InvalidMeshSubset;
            } else if (std.mem.eql(u8, arg, "--mesh-density")) {
                result.mesh_density = std.meta.stringToEnum(MeshDensity, val) orelse
                    return error.InvalidMeshDensity;
            } else if (std.mem.eql(u8, arg, "--distort")) {
                result.distort_case = std.meta.stringToEnum(DistortCase, val) orelse
                    return error.InvalidDistortCase;
            } else if (std.mem.eql(u8, arg, "--psf")) {
                result.psf_case = std.meta.stringToEnum(PSFCase, val) orelse
                    return error.InvalidPSFCase;
            } else if (std.mem.eql(u8, arg, "--runs")) {
                result.runs = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "--frames")) {
                result.frames = try std.fmt.parseInt(usize, val, 10);
            } else if (std.mem.eql(u8, arg, "--total-threads")) {
                result.total_threads = try std.fmt.parseInt(u16, val, 10);
            } else if (std.mem.eql(u8, arg, "--max-raster-workers-per-job")) {
                result.max_raster_workers_per_job = try std.fmt.parseInt(u16, val, 10);
            } else if (std.mem.eql(u8, arg, "--hull-mode")) {
                result.hull_mode = std.meta.stringToEnum(rastcfg.HullMode, val) orelse
                    return error.InvalidHullMode;
            } else if (std.mem.eql(u8, arg, "--subpixel-center-map")) {
                if (std.mem.eql(u8, val, "in_mem") or std.mem.eql(u8, val, "full_in_mem")) {
                    result.subpixel_center_map = .full_in_mem;
                } else if (std.mem.eql(u8, val, "per_tile")) {
                    result.subpixel_center_map = .per_tile;
                } else {
                    result.subpixel_center_map = std.meta.stringToEnum(
                        cam.SubPixelCenterMap,
                        val,
                    ) orelse return error.InvalidSubpixelCenterMap;
                }
            } else if (std.mem.eql(u8, arg, "--save-strategy")) {
                result.save_strategy = std.meta.stringToEnum(rastcfg.SaveStrategy, val) orelse
                    return error.InvalidSaveStrategy;
            }
        }
    }
    return result;
}

fn createDistortModel(case: DistortCase) cam.DistortParams {
    return switch (case) {
        .none, .all => .none,
        .brown_zero => .{ .brown_con = .{
            .k1 = 0.0,
            .k2 = 0.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 0.0,
        } },
        .brown_ext_zero => .{ .brown_con_ext = .{
            .k1 = 0.0,
            .k2 = 0.0,
            .k3 = 0.0,
            .k4 = 0.0,
            .k5 = 0.0,
            .k6 = 0.0,
            .p1 = 0.0,
            .p2 = 0.0,
            .s1 = 0.0,
            .s2 = 0.0,
            .s3 = 0.0,
            .s4 = 0.0,
            .tau_x = 0.0,
            .tau_y = 0.0,
        } },
        .brown_pincushion => .{ .brown_con = .{
            .k1 = -50.0,
            .k2 = 5000.0,
            .k3 = 0.0,
            .p1 = 0.0,
            .p2 = 0.0,
        } },
        .brown_ext_pincushion => .{ .brown_con_ext = .{
            .k1 = -50.0,
            .k2 = 5000.0,
            .k3 = 0.0,
            .k4 = -50.0,
            .k5 = 2000.0,
            .k6 = 0.0,
            .p1 = 0.005,
            .p2 = -0.003,
            .s1 = 0.0001,
            .s2 = -0.00002,
            .s3 = 0.0,
            .s4 = 0.0,
            .tau_x = 0.002,
            .tau_y = -0.001,
        } },
        .poly_zero => .{ .poly = .{
            .degree = 1,
            .mode = .displacement,
            .coeffs = &poly_zero_coeffs,
        } },
        .poly_deg3_pincushion => .{ .poly = .{
            .degree = 3,
            .mode = .displacement,
            .coeffs = &poly_deg3_pincushion_coeffs,
        } },
        .poly_deg5_pincushion => .{ .poly = .{
            .degree = 5,
            .mode = .displacement,
            .coeffs = &poly_deg5_pincushion_coeffs,
        } },
        .poly_deg7_pincushion => .{ .poly = .{
            .degree = 7,
            .mode = .displacement,
            .coeffs = &poly_deg7_pincushion_coeffs,
        } },
    };
}

fn createPSF(case: PSFCase) cam.PointSpreadFunc {
    return switch (case) {
        .pixel_box, .all => .{ .pixel_box = .{} },
        .gaussian_0p5 => .{ .gaussian = .{
            .sigma_px = 0.5,
            .supp_rad_px = 1.5,
            .separable = .yes,
        } },
        .gaussian_1p5 => .{ .gaussian = .{
            .sigma_px = 1.5,
            .supp_rad_px = 4.5,
            .separable = .yes,
        } },
        .aniso_gaussian_0p5_0p25 => .{ .anisotropic_gaussian = .{
            .sigma_x_px = 0.5,
            .sigma_y_px = 0.25,
            .theta_rad = 0.0,
            .supp_rad_px = 1.5,
            .separable = .yes,
        } },
        .aniso_gaussian_1p5_0p5 => .{ .anisotropic_gaussian = .{
            .sigma_x_px = 1.5,
            .sigma_y_px = 0.5,
            .theta_rad = 0.35,
            .supp_rad_px = 4.5,
            .separable = .no,
        } },
    };
}

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;

    const bench_args = try parseDistPsfArgs(init.minimal.args.vector);

    var threaded_io = riley.getThreadedIo(
        outer_alloc,
        init.minimal,
        bench_args.total_threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();

    var base_raster_config = tcfg.getRasterConfig(.bench);
    base_raster_config.parallel = .{ .threads = bench_args.total_threads };
    base_raster_config.advanced.solver.hull_mode = bench_args.hull_mode;
    base_raster_config.save_strategy = bench_args.save_strategy;
    base_raster_config.output.image_save_opts = &[_]iio.ImageSaveOpts{
        .{ .format = .bmp, .bits = 8, .scaling = .auto },
    };

    var groups = try riley.ManagedRenderGroups.init(
        outer_alloc,
        init.minimal,
        bench_args.total_threads,
        1,
    );
    defer groups.deinit(outer_alloc);

    const active_mesh_types = switch (bench_args.mesh_subset) {
        .all => &[_]gk.MeshType{ .tri3, .tri6, .quad4, .quad8, .quad9 },
        .tri3 => &[_]gk.MeshType{.tri3},
        .tri6 => &[_]gk.MeshType{.tri6},
        .quad4 => &[_]gk.MeshType{.quad4},
        .quad8 => &[_]gk.MeshType{.quad8},
        .quad9 => &[_]gk.MeshType{.quad9},
    };

    const active_densities = switch (bench_args.mesh_density) {
        .all => &[_]MeshDensity{ .fullraster, .@"1e2", .@"1e3", .@"1e4", .@"1e5" },
        .fullraster => &[_]MeshDensity{.fullraster},
        .@"1e2" => &[_]MeshDensity{.@"1e2"},
        .@"1e3" => &[_]MeshDensity{.@"1e3"},
        .@"1e4" => &[_]MeshDensity{.@"1e4"},
        .@"1e5" => &[_]MeshDensity{.@"1e5"},
    };

    const active_distort_cases = switch (bench_args.distort_case) {
        .all => &[_]DistortCase{
            .none,
            .brown_zero,
            .brown_ext_zero,
            .brown_pincushion,
            .brown_ext_pincushion,
            .poly_zero,
            .poly_deg3_pincushion,
            .poly_deg5_pincushion,
            .poly_deg7_pincushion,
        },
        inline else => |dc| &[_]DistortCase{dc},
    };

    const active_psf_cases = switch (bench_args.psf_case) {
        .all => &[_]PSFCase{
            .pixel_box,
            .gaussian_0p5,
            .gaussian_1p5,
            .aniso_gaussian_0p5_0p25,
            .aniso_gaussian_1p5_0p5,
        },
        inline else => |pc| &[_]PSFCase{pc},
    };

    var stats = try benchstats.BenchStatsCollector.init(
        outer_alloc,
        bench_args.runs,
    );
    defer stats.deinit(outer_alloc);

    if (bench_args.out_dir.len > 0) {
        var out_dir_handle = try orch.openDirEnsured(io, bench_args.out_dir);
        out_dir_handle.close(io);
    }

    std.debug.print(
        "Starting Distortion & PSF Benchmark ({d}x{d}, SSAA={d}, {d} runs, {d} threads)...\n",
        .{
            DEFAULT_PIXELS_NUM[0],
            DEFAULT_PIXELS_NUM[1],
            DEFAULT_SUB_SAMPLE,
            bench_args.runs,
            bench_args.total_threads,
        },
    );

    for (active_mesh_types) |mt| {
        for (active_densities) |density| {
            for (active_distort_cases) |distort_case| {
                for (active_psf_cases) |psf_case| {
                    var arena = std.heap.ArenaAllocator.init(outer_alloc);
                    defer arena.deinit();
                    const local_alloc = arena.allocator();

                    var data_dir_buf: [256]u8 = undefined;
                    const density_str = @tagName(density);
                    const data_dir = if (density == .fullraster)
                        try std.fmt.bufPrint(
                            &data_dir_buf,
                            "data/bench/{s}_fullraster",
                            .{@tagName(mt)},
                        )
                    else
                        try std.fmt.bufPrint(
                            &data_dir_buf,
                            "data/bench/{s}_geom_{s}",
                            .{ @tagName(mt), density_str },
                        );

                    const coords_path = try std.fs.path.join(
                        local_alloc,
                        &.{ data_dir, "coords.csv" },
                    );
                    const connect_path = try std.fs.path.join(
                        local_alloc,
                        &.{ data_dir, "connect.csv" },
                    );

                    const sim_data = meshio.loadSimData(
                        local_alloc,
                        io,
                        coords_path,
                        connect_path,
                        null,
                        null,
                    ) catch |err| {
                        std.debug.print(
                            "Warning: could not load {s}: {}\n",
                            .{ data_dir, err },
                        );
                        continue;
                    };

                    const case_name = try std.fmt.allocPrint(
                        local_alloc,
                        "{s}_{s}_{s}_{s}",
                        .{
                            @tagName(mt),
                            density_str,
                            @tagName(distort_case),
                            @tagName(psf_case),
                        },
                    );

                    std.debug.print("Running case: {s}\n", .{case_name});

                    const roi_pos = sceneops.boundsCenter(&sim_data.coords);
                    const cam_pos = cameraops.posFillFrameFromRot(
                        &sim_data.coords,
                        DEFAULT_PIXELS_NUM,
                        DEFAULT_PIXEL_SIZE,
                        DEFAULT_FOCAL_LENG,
                        DEFAULT_ROT,
                        1.0,
                    );

                    const distort_params = createDistortModel(distort_case);
                    const psf_params = createPSF(psf_case);

                    const cam_input = cam.CameraInput{
                        .pixels_num = DEFAULT_PIXELS_NUM,
                        .pixels_size = DEFAULT_PIXEL_SIZE,
                        .pos_world = cam_pos,
                        .rot_world = DEFAULT_ROT,
                        .roi_cent_world = roi_pos,
                        .focal_length = DEFAULT_FOCAL_LENG,
                        .sub_sample = DEFAULT_SUB_SAMPLE,
                        .distort = distort_params,
                        .psf = psf_params,
                        .subpixel_center_map = bench_args.subpixel_center_map,
                    };

                    // Function shader: eggbox grid with 5 pixels per period (0.1 world units)
                    const shader_input = shaderops.ShaderInput{
                        .func = .{
                            .builtin = .eggbox,
                            .coord_mode = .world_reference,
                            .params = .{
                                .settings = .{
                                    .eggbox = .{
                                        .mean = 0.5,
                                        .contrast = 0.4,
                                        .pitch = .{ 0.1, 0.1 },
                                        .phase = .{ 0.0, 0.0 },
                                    },
                                },
                            },
                            .bits = 8,
                            .scaling = .none,
                        },
                    };

                    var disp_field: ?meshio.Field = null;
                    if (bench_args.frames > 1) {
                        disp_field = try meshio.Field.initAlloc(
                            local_alloc,
                            bench_args.frames,
                            sim_data.coords.mat.rows_num,
                            3,
                        );
                    }
                    defer if (disp_field) |*df| df.deinit(local_alloc);

                    const mesh_input = meshpipe.MeshInput{
                        .mesh_type = mt,
                        .coords = sim_data.coords,
                        .connect = sim_data.connect,
                        .disp = disp_field,
                        .shader = shader_input,
                    };

                    const needs_images_arr = base_raster_config.save_strategy == .memory or
                        base_raster_config.save_strategy == .both;
                    var image_arr: ?NDArray(F) = null;
                    if (needs_images_arr) {
                        const dims = try riley.calcAllFramesImageDims(
                            &[_]cam.CameraInput{cam_input},
                            &[_]meshpipe.MeshInput{mesh_input},
                            base_raster_config,
                        );
                        image_arr = try NDArray(F).initFlat(
                            local_alloc,
                            dims[0..],
                        );
                    }
                    defer if (image_arr) |*arr| arr.deinit(local_alloc);

                    const frame_case_samples = try outer_alloc.alloc(
                        benchstats.CaseSamples,
                        bench_args.frames,
                    );
                    defer {
                        for (frame_case_samples) |*cs| cs.deinit(outer_alloc);
                        outer_alloc.free(frame_case_samples);
                    }
                    for (0..bench_args.frames) |ff| {
                        frame_case_samples[ff] = try benchstats.CaseSamples.init(
                            outer_alloc,
                            bench_args.runs,
                        );
                    }

                    for (0..bench_args.runs) |rr| {
                        const bench_capture = try local_alloc.alloc(
                            report.FrameBenchCapture,
                            bench_args.frames,
                        );
                        defer local_alloc.free(bench_capture);
                        @memset(bench_capture, std.mem.zeroes(report.FrameBenchCapture));

                        const out_img_path = if (bench_args.image_out_dir.len > 0)
                            try std.fs.path.join(
                                local_alloc,
                                &.{ bench_args.image_out_dir, case_name },
                            )
                        else
                            null;

                        if (out_img_path) |p| {
                            var d = try orch.openDirEnsured(io, p);
                            d.close(io);
                        }

                        const e2e_start = Timestamp.now(io, .awake);
                        try riley.rasterAdvancedInto(
                            local_alloc,
                            io,
                            &[_]cam.CameraInput{cam_input},
                            &[_]meshpipe.MeshInput{mesh_input},
                            base_raster_config,
                            out_img_path,
                            if (image_arr) |*arr| arr else null,
                            .{
                                .render_groups = .{ .supplied = groups.specs },
                                .bench_capture = bench_capture,
                            },
                        );
                        const e2e_end = Timestamp.now(io, .awake);

                        const e2e_ms = @as(F, @floatFromInt(
                            e2e_start.durationTo(e2e_end).raw.nanoseconds,
                        )) / 1e6;

                        for (bench_capture, 0..) |capture, ff| {
                            const frame_times = capture.bench_log.frame_times;
                            const geom_ms = (frame_times.geometry_prep +
                                frame_times.tile_overlap) / 1e6;
                            const raster_ms = report.rasterStageTime(frame_times) / 1e6;
                            const frame_active_ms = frame_times.active_time / 1e6;
                            const frame_e2e_ms = if (bench_args.frames == 1)
                                e2e_ms
                            else
                                frame_active_ms;

                            const total_elems = sim_data.connect.getElemsNum();
                            const vis_elems = total_elems;
                            const total_px = @as(u64, DEFAULT_PIXELS_NUM[0]) *
                                @as(u64, DEFAULT_PIXELS_NUM[1]);
                            const shaded_px = total_px;

                            const metrics = common.calcMetrics(
                                mt,
                                DEFAULT_PIXELS_NUM,
                                DEFAULT_SUB_SAMPLE,
                                frame_e2e_ms,
                                frame_times,
                                capture.bench_log,
                            );

                            const bench_res = common.BenchResult{
                                .e2e_ms = frame_e2e_ms,
                                .geom_ms = geom_ms,
                                .raster_ms = raster_ms,
                                .cam_ms = frame_times.cam_invert / 1e6,
                                .resolve_ms = frame_times.scratch_resolve / 1e6,
                                .fps = if (frame_e2e_ms > 0)
                                    1000.0 / frame_e2e_ms
                                else
                                    0,
                                .total_elems = total_elems,
                                .vis_elems = vis_elems,
                                .total_px = total_px,
                                .shaded_px = shaded_px,
                                .metrics = metrics,
                                .pipeline_times = frame_times,
                                .image = null,
                            };

                            const frame_case_name = if (bench_args.frames > 1)
                                try std.fmt.allocPrint(
                                    local_alloc,
                                    "{s}_f{d}",
                                    .{ case_name, ff },
                                )
                            else
                                case_name;
                            defer if (bench_args.frames > 1) {
                                local_alloc.free(frame_case_name);
                            };

                            try stats.appendRunResult(
                                outer_alloc,
                                rr,
                                frame_case_name,
                                mt,
                                .func,
                                null,
                                null,
                                bench_res,
                            );
                            frame_case_samples[ff].record(rr, bench_res);
                        }

                        try stats.writeRunCSV(
                            outer_alloc,
                            io,
                            bench_args.out_dir,
                            rr,
                        );
                    }

                    for (0..bench_args.frames) |ff| {
                        const frame_case_name = if (bench_args.frames > 1)
                            try std.fmt.allocPrint(
                                local_alloc,
                                "{s}_f{d}",
                                .{ case_name, ff },
                            )
                        else
                            case_name;
                        defer if (bench_args.frames > 1) {
                            local_alloc.free(frame_case_name);
                        };

                        try stats.appendCaseStats(
                            outer_alloc,
                            frame_case_name,
                            mt,
                            .func,
                            null,
                            null,
                            &frame_case_samples[ff],
                        );
                    }
                }
            }
        }
    }

    try stats.writeRunCSVs(outer_alloc, io, bench_args.out_dir);
    try common.writeBenchmarkReport(
        outer_alloc,
        io,
        "Distortion & PSF Benchmark",
        bench_args.out_dir,
        DEFAULT_PIXELS_NUM,
        stats.stats_list.items,
        32,
    );
    std.debug.print("Benchmark complete. Results written to {s}/\n", .{bench_args.out_dir});
}
