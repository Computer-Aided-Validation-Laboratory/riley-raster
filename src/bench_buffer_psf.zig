// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const riley = @import("riley/zig/riley.zig");
const cam = @import("riley/zig/camera.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const frontend = @import("riley/zig/rasterfrontend.zig");
const report = @import("riley/zig/report.zig");
const orch = @import("dev_support/orchestration.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const F = @import("riley/zig/buildconfig.zig").F;
const Timestamp = std.Io.Clock.Timestamp;

const SceneDensity = enum { dense, sparse };
const PsfKind = enum { none, gaussian_1_0, gaussian_1_5 };

const BenchArgs = struct {
    out_dir: []const u8 = "out/bench_stats_buffer_psf",
    elements_per_type: usize = 24,
    width: u32 = 512,
    height: u32 = 512,
    runs: usize = 5,
    warmup: usize = 1,
    threads: u16 = 4,
    sub_sample: u32 = 2,
    scene_density: SceneDensity = .dense,
    psf: PsfKind = .none,
    buffer_mode: rastcfg.BufferMode = .tile_local,
};

fn argSlice(arg: anytype) []const u8 {
    return switch (@typeInfo(@TypeOf(arg))) {
        .pointer => |info| switch (info.size) {
            .slice => arg,
            else => std.mem.span(arg),
        },
        .array => arg[0..],
        else => @compileError("unsupported argument representation"),
    };
}

fn parseArgs(args: anytype) !BenchArgs {
    var result = BenchArgs{};
    var ii: usize = 1;
    while (ii < args.len) : (ii += 2) {
        if (ii + 1 >= args.len) return error.MissingArgumentValue;
        const key = argSlice(args[ii]);
        const value = argSlice(args[ii + 1]);
        if (std.mem.eql(u8, key, "--out-dir")) {
            result.out_dir = value;
        } else if (std.mem.eql(u8, key, "--elements-per-type")) {
            result.elements_per_type = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--width")) {
            result.width = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "--height")) {
            result.height = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "--runs")) {
            result.runs = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--warmup")) {
            result.warmup = try std.fmt.parseInt(usize, value, 10);
        } else if (std.mem.eql(u8, key, "--threads")) {
            result.threads = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, key, "--sub-sample")) {
            result.sub_sample = try std.fmt.parseInt(u32, value, 10);
        } else if (std.mem.eql(u8, key, "--scene-density")) {
            result.scene_density = std.meta.stringToEnum(
                SceneDensity,
                value,
            ) orelse return error.InvalidSceneDensity;
        } else if (std.mem.eql(u8, key, "--psf")) {
            result.psf = std.meta.stringToEnum(
                PsfKind,
                value,
            ) orelse return error.InvalidPsf;
        } else if (std.mem.eql(u8, key, "--buffer-mode")) {
            result.buffer_mode = std.meta.stringToEnum(
                rastcfg.BufferMode,
                value,
            ) orelse return error.InvalidBufferMode;
        } else {
            return error.UnknownArgument;
        }
    }
    if (result.elements_per_type == 0 or result.width == 0 or
        result.height == 0 or result.runs == 0 or result.threads == 0 or
        result.sub_sample == 0)
    {
        return error.InvalidBenchmarkSize;
    }
    return result;
}

fn fillClipCoords(
    comptime N: usize,
    element_idx: usize,
    group_idx: usize,
    args: BenchArgs,
    output: *[N][3]F,
) void {
    const parents = comptime gk.parentNodeCoords(N);
    const global_idx = group_idx * args.elements_per_type + element_idx;
    const roll = 2 * std.math.pi * @as(F, @floatFromInt(
        (global_idx *% 37) % 101,
    )) / 101;
    const c = @cos(roll);
    const s = @sin(roll);
    const total_elems = 4 * args.elements_per_type;
    const aspect = @as(F, @floatFromInt(args.width)) /
        @as(F, @floatFromInt(args.height));
    const cells_x: usize = @intFromFloat(@ceil(@sqrt(
        @as(F, @floatFromInt(total_elems)) * aspect,
    )));
    const cells_y = std.math.divCeil(usize, total_elems, cells_x) catch
        unreachable;
    const cell_width = @as(F, @floatFromInt(args.width)) /
        @as(F, @floatFromInt(cells_x));
    const cell_height = @as(F, @floatFromInt(args.height)) /
        @as(F, @floatFromInt(cells_y));
    const cell_size = @min(cell_width, cell_height);

    const jitter_scale: F = if (args.scene_density == .dense) 0.05 else 0.2;
    const jitter_x = jitter_scale * cell_width * (@as(F, @floatFromInt(
        (global_idx *% 43) % 103,
    )) / 102 - 0.5);
    const jitter_y = jitter_scale * cell_height * (@as(F, @floatFromInt(
        (global_idx *% 61) % 107,
    )) / 106 - 0.5);

    const shift_x = (@as(F, @floatFromInt(global_idx % cells_x)) + 0.5) *
        cell_width - 0.5 * @as(F, @floatFromInt(args.width)) + jitter_x;
    const shift_y = (@as(F, @floatFromInt(global_idx / cells_x)) + 0.5) *
        cell_height - 0.5 * @as(F, @floatFromInt(args.height)) + jitter_y;

    const flat_scale: F = if (args.scene_density == .dense) 1.25 else 0.35;
    const size = 0.25 * cell_size * flat_scale;

    for (parents, 0..) |parent, nn| {
        const u = if (N == 6) parent[0] - 1.0 / 3.0 else parent[0];
        const v = if (N == 6) parent[1] - 1.0 / 3.0 else parent[1];
        const px = size * (c * u - s * v);
        const py = -size * (s * u + c * v);
        const z: F = 2.2;
        output[nn] = .{
            px + shift_x * z,
            py + shift_y * z,
            z,
        };
    }
}

fn makeMesh(
    comptime N: usize,
    outer_alloc: std.mem.Allocator,
    mesh_type: gk.MeshType,
    group_idx: usize,
    args: BenchArgs,
) !meshpipe.MeshInput {
    const coord_values = try outer_alloc.alloc(
        F,
        args.elements_per_type * N * 3,
    );
    const connect_values = try outer_alloc.alloc(
        usize,
        args.elements_per_type * N,
    );
    for (0..args.elements_per_type) |ee| {
        var clip: [N][3]F = undefined;
        fillClipCoords(N, ee, group_idx, args, &clip);
        var raster = frontend.RasterCoords2D(N){
            .x = undefined,
            .y = undefined,
        };
        for (0..N) |nn| {
            raster.x[nn] = clip[nn][0] / clip[nn][2];
            raster.y[nn] = clip[nn][1] / clip[nn][2];
        }
        if (frontend.classifyHighOrdFacing(N, raster) != .one_root) {
            return error.BaselineNotOneRoot;
        }
        for (0..N) |nn| {
            const node_idx = ee * N + nn;
            coord_values[3 * node_idx] = clip[nn][0];
            coord_values[3 * node_idx + 1] = -clip[nn][1];
            coord_values[3 * node_idx + 2] = -clip[nn][2];
            connect_values[node_idx] = node_idx;
        }
    }
    return .{
        .mesh_type = mesh_type,
        .coords = meshio.Coords.init(
            coord_values,
            args.elements_per_type * N,
        ),
        .connect = meshio.Connect.init(
            connect_values,
            args.elements_per_type,
            N,
        ),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .func = .{
            .coord_mode = .world_reference,
            .builtin = .checker,
            .params = .{
                .coord_scale = .{ 4, 4 },
                .settings = .{ .checker = .{} },
            },
            .scaling = .auto,
        } } },
    };
}

pub fn main(init: std.process.Init) !void {
    const outer_alloc = init.gpa;
    const args = try parseArgs(init.minimal.args.vector);
    var threaded_io = riley.getThreadedIo(
        outer_alloc,
        init.minimal,
        args.threads,
    );
    defer threaded_io.deinit();
    const io = threaded_io.io();
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    const meshes = [_]meshpipe.MeshInput{
        try makeMesh(4, local_alloc, .quad4, 0, args),
        try makeMesh(6, local_alloc, .tri6, 1, args),
        try makeMesh(8, local_alloc, .quad8, 2, args),
        try makeMesh(9, local_alloc, .quad9, 3, args),
    };

    const psf: cam.PointSpreadFunc = switch (args.psf) {
        .none => .{ .pixel_box = .{} },
        .gaussian_1_0 => .{ .gaussian = .{
            .sigma_px = 1.0,
            .supp_rad_px = 3.0,
            .separable = .yes,
        } },
        .gaussian_1_5 => .{ .gaussian = .{
            .sigma_px = 1.5,
            .supp_rad_px = 4.5,
            .separable = .yes,
        } },
    };

    const camera = cam.CameraInput{
        .pixels_num = .{ args.width, args.height },
        .pixels_size = .{ 1, 1 },
        .pos_world = .{ .vec = .{ 0, 0, 0 } },
        .rot_world = Rotation.init(0, 0, 0),
        .roi_cent_world = .{ .vec = .{ 0, 0, -2.2 } },
        .focal_length = 1,
        .sub_sample = args.sub_sample,
        .psf = psf,
    };

    const config = rastcfg.RasterConfig{
        .parallel = .{ .threads = args.threads },
        .save_strategy = .none,
        .report_perf = .bench,
        .advanced = .{
            .raster = .{ .buffer_mode = args.buffer_mode },
        },
    };

    var out_dir = try orch.openDirEnsured(io, args.out_dir);
    defer out_dir.close(io);
    var file = try out_dir.createFile(io, "raw_stats_buffer_psf.csv", .{});
    defer file.close(io);
    var write_buf: [4096]u8 = undefined;
    var buffered = file.writer(io, &write_buf);
    const writer = &buffered.interface;

    try writer.writeAll(
        "scene_density,buffer_mode,psf,sub_sample,threads,run," ++
            "elements,width,height," ++
            "visible,shaded," ++
            "geometry_ms,tile_overlap_ms,buffer_setup_ms,tile_raster_ms," ++
            "resolve_ms,raster_loop_ms,raster_stage_ms,active_ms,e2e_ms," ++
            "stripe_count,active_tile_count,overlap_refs_total," ++
            "melems_s,mpx_s\n",
    );

    for (0..args.warmup + args.runs) |rr| {
        var capture: [1]report.FrameBenchCapture = undefined;
        const started = Timestamp.now(io, .awake);
        try riley.rasterAdvancedInto(
            outer_alloc,
            io,
            &.{camera},
            &meshes,
            config,
            null,
            null,
            .{ .bench_capture = &capture },
        );
        const elapsed_ns = started.durationTo(
            Timestamp.now(io, .awake),
        ).raw.nanoseconds;
        if (rr < args.warmup) continue;

        const log = capture[0].bench_log;
        const times = log.frame_times;
        const e2e_ms = @as(F, @floatFromInt(elapsed_ns)) / 1e6;
        const geom_ms = times.geometry_prep / 1e6;
        const tile_overlap_ms = times.tile_overlap / 1e6;
        const buffer_setup_ms = times.global_subpx_times.buffer_setup / 1e6;
        const tile_raster_ms = times.global_subpx_times.tile_raster / 1e6;
        const resolve_ms = times.global_subpx_times.resolve / 1e6;
        const raster_loop_ms = times.raster_loop / 1e6;
        const raster_stage_ms = report.rasterStageTime(times) / 1e6;
        const active_ms = times.active_time / 1e6;

        var stripe_count: usize = 0;
        var active_tile_count: usize = 0;
        var overlap_refs_total: usize = 0;
        if (times.global_subpx_stats) |stats| {
            stripe_count = stats.stripe_count;
            active_tile_count = stats.active_tile_count;
            overlap_refs_total = stats.overlap_refs_total;
        }

        const mpixels = @as(F, @floatFromInt(args.width)) *
            @as(F, @floatFromInt(args.height)) / 1e6;
        const seconds = e2e_ms / 1e3;

        try writer.print(
            "{s},{s},{s},{d},{d},{d},{d},{d},{d},{d},{d}," ++
                "{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6},{d:.6}," ++
                "{d},{d},{d},{d:.6},{d:.6}\n",
            .{
                @tagName(args.scene_density),
                @tagName(args.buffer_mode),
                @tagName(args.psf),
                args.sub_sample,
                args.threads,
                rr - args.warmup,
                meshes.len * args.elements_per_type,
                args.width,
                args.height,
                log.vis_elems,
                log.total_shaded_px,
                geom_ms,
                tile_overlap_ms,
                buffer_setup_ms,
                tile_raster_ms,
                resolve_ms,
                raster_loop_ms,
                raster_stage_ms,
                active_ms,
                e2e_ms,
                stripe_count,
                active_tile_count,
                overlap_refs_total,
                @as(F, @floatFromInt(log.total_elems)) / seconds / 1e6,
                mpixels / seconds,
            },
        );

        std.debug.print(
            "{s} {s} {s} ssaa={d} run {d}: e2e={d:.3} ms " ++
                "raster_stage={d:.3} ms tile_raster={d:.3} ms\n",
            .{
                @tagName(args.scene_density),
                @tagName(args.buffer_mode),
                @tagName(args.psf),
                args.sub_sample,
                rr - args.warmup,
                e2e_ms,
                raster_stage_ms,
                tile_raster_ms,
            },
        );
    }
    try buffered.flush();
}
