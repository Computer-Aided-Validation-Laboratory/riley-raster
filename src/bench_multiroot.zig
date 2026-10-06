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
const rastops = @import("riley/zig/rasterops.zig");
const report = @import("riley/zig/report.zig");
const orch = @import("dev_support/orchestration.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const F = @import("riley/zig/buildconfig.zig").F;
const Timestamp = std.Io.Clock.Timestamp;

const SceneKind = enum { multi_root, one_root };

const BenchArgs = struct {
    out_dir: []const u8 = "out/bench_stats_multiroot",
    elements_per_type: usize = 24,
    width: u32 = 512,
    height: u32 = 512,
    runs: usize = 5,
    warmup: usize = 1,
    threads: u16 = 1,
    sub_sample: u32 = 1,
    scene: SceneKind = .multi_root,
    flat_scale: F = 1,
    method: rastcfg.MultiRootMethod = .legacy_front,
    child_seed: rastcfg.MultiRootChildSeed = .center,
    seed_bank_depth: u8 = 3,
    reuse_radius_rows: u8 = 1,
    reuse_method: @import("riley/zig/coherentseed.zig").ReuseMethod = .column,
    legacy_fallback: bool = false,
    single_frozen_jac: bool = false,
    adaptive_max_depth: u8 = 3,
    adaptive_stop_px: F = 8,
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
        } else if (std.mem.eql(u8, key, "--scene")) {
            result.scene = std.meta.stringToEnum(SceneKind, value) orelse
                return error.InvalidScene;
        } else if (std.mem.eql(u8, key, "--flat-scale")) {
            result.flat_scale = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, key, "--method")) {
            result.method = std.meta.stringToEnum(
                rastcfg.MultiRootMethod,
                value,
            ) orelse return error.InvalidMethod;
        } else if (std.mem.eql(u8, key, "--child-seed")) {
            result.child_seed = std.meta.stringToEnum(
                rastcfg.MultiRootChildSeed,
                value,
            ) orelse return error.InvalidChildSeed;
        } else if (std.mem.eql(u8, key, "--seed-bank-depth")) {
            result.seed_bank_depth = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, key, "--reuse-radius-rows")) {
            result.reuse_radius_rows = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, key, "--reuse-method")) {
            result.reuse_method = std.meta.stringToEnum(
                @TypeOf(result.reuse_method),
                value,
            ) orelse return error.InvalidReuseMethod;
        } else if (std.mem.eql(u8, key, "--legacy-fallback")) {
            result.legacy_fallback = try parseBool(value);
        } else if (std.mem.eql(u8, key, "--single-frozen-jac")) {
            result.single_frozen_jac = try parseBool(value);
        } else if (std.mem.eql(u8, key, "--adaptive-max-depth")) {
            result.adaptive_max_depth = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, key, "--adaptive-stop-px")) {
            result.adaptive_stop_px = try std.fmt.parseFloat(F, value);
        } else {
            return error.UnknownArgument;
        }
    }
    if (result.elements_per_type == 0 or result.width == 0 or
        result.height == 0 or result.runs == 0 or result.threads == 0 or
        result.sub_sample == 0 or !std.math.isFinite(result.flat_scale) or
        result.flat_scale <= 0)
    {
        return error.InvalidBenchmarkSize;
    }
    return result;
}

fn parseBool(value: []const u8) !bool {
    if (std.mem.eql(u8, value, "on") or
        std.mem.eql(u8, value, "true")) return true;
    if (std.mem.eql(u8, value, "off") or
        std.mem.eql(u8, value, "false")) return false;
    return error.InvalidBoolean;
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
    const theta_centers = [_]F{ -1, -0.7, 0.7, 1 };
    const secondary_values = [_]F{ -0.55, 0, 0.55 };
    const rolls = [_]F{
        0, std.math.pi / 4.0, std.math.pi / 2.0, 3 * std.math.pi / 4.0,
    };
    const theta_center = theta_centers[element_idx % theta_centers.len];
    const secondary = secondary_values[
        (element_idx / theta_centers.len) % secondary_values.len
    ];
    const roll = if (args.scene == .one_root)
        2 * std.math.pi * @as(F, @floatFromInt(
            (global_idx *% 37) % 101,
        )) / 101
    else
        rolls[(element_idx / 3) % rolls.len];
    const c = @cos(roll);
    const s = @sin(roll);
    const ct = @cos(secondary);
    const st = @sin(secondary);
    const span: F = if (N == 6) 1.2 else 0.6;
    const curved_kind = if (N == 4)
        @as(usize, 2)
    else if (N == 8)
        element_idx % 3
    else
        element_idx % 2;
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
    const jitter_x = if (args.scene == .one_root)
        0.2 * cell_width * (@as(F, @floatFromInt(
            (global_idx *% 43) % 103,
        )) / 102 - 0.5)
    else
        0;
    const jitter_y = if (args.scene == .one_root)
        0.2 * cell_height * (@as(F, @floatFromInt(
            (global_idx *% 61) % 107,
        )) / 106 - 0.5)
    else
        0;
    const shift_x = (@as(F, @floatFromInt(global_idx % cells_x)) + 0.5) *
        cell_width - 0.5 * @as(F, @floatFromInt(args.width)) + jitter_x;
    const shift_y = (@as(F, @floatFromInt(global_idx / cells_x)) + 0.5) *
        cell_height - 0.5 * @as(F, @floatFromInt(args.height)) + jitter_y;
    for (parents, 0..) |parent, nn| {
        const u = if (N == 6) parent[0] - 1.0 / 3.0 else parent[0];
        const v = if (N == 6) parent[1] - 1.0 / 3.0 else parent[1];
        var px: F = undefined;
        var py: F = undefined;
        var z: F = undefined;
        if (args.scene == .one_root) {
            const size = 0.25 * cell_size * args.flat_scale;
            px = size * (c * u - s * v);
            py = -size * (s * u + c * v);
            z = 2.2;
        } else if (curved_kind < 2) {
            const theta = theta_center + span * u;
            const local_x = @sin(theta);
            const local_y: F = if (curved_kind == 1)
                @sin(secondary - span * v)
            else
                -0.45 * v * ct + @cos(theta) * st;
            const local_z: F = if (curved_kind == 1)
                -@cos(theta) * @cos(secondary - span * v)
            else
                -0.45 * v * st - @cos(theta) * ct;
            const sphere_x = if (curved_kind == 1)
                local_x * @cos(secondary - span * v)
            else
                local_x;
            px = 30 * (c * sphere_x - s * local_y);
            py = 30 * (s * sphere_x + c * local_y);
            z = 2.2 + local_z;
        } else if (N == 4) {
            const ridge: F = if (element_idx % 2 == 0) -0.5 else 0.5;
            const x = 20 * u * (v - ridge);
            const y = -20 * v;
            px = c * x - s * y;
            py = s * x + c * y;
            z = 1 + 0.1 * u;
        } else {
            const ridge: F = if (element_idx % 2 == 0) -0.5 else 0;
            const x = 20 * (u - ridge) * (u - ridge) +
                30 * v * (u * u - 1);
            const y = -20 * v;
            px = c * x - s * y;
            py = s * x + c * y;
            z = 1 + 0.2 * u;
        }
        const footprint_scale = cell_size / 80;
        output[nn] = .{
            px * (if (args.scene == .one_root) 1 else footprint_scale) +
                shift_x * z,
            py * (if (args.scene == .one_root) 1 else footprint_scale) +
                shift_y * z,
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
    const coord_values = try outer_alloc.alloc(F, args.elements_per_type * N * 3);
    const connect_values = try outer_alloc.alloc(
        usize,
        args.elements_per_type * N,
    );
    for (0..args.elements_per_type) |ee| {
        var clip: [N][3]F = undefined;
        fillClipCoords(N, ee, group_idx, args, &clip);
        if (args.scene == .one_root) {
            var raster = rastops.RasterCoords2D(N){
                .x = undefined,
                .y = undefined,
            };
            for (0..N) |nn| {
                raster.x[nn] = clip[nn][0] / clip[nn][2];
                raster.y[nn] = clip[nn][1] / clip[nn][2];
            }
            if (rastops.classifyHighOrdFacing(N, raster) != .one_root) {
                return error.BaselineNotOneRoot;
            }
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
        .shader = .{ .func = .{
            .coord_mode = .world_reference,
            .builtin = .checker,
            .params = .{
                .coord_scale = .{ 4, 4 },
                .settings = .{ .checker = .{} },
            },
            .scaling = .auto,
        } },
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
    const camera = cam.CameraInput{
        .pixels_num = .{ args.width, args.height },
        .pixels_size = .{ 1, 1 },
        .pos_world = .{ .vec = .{ 0, 0, 0 } },
        .rot_world = Rotation.init(0, 0, 0),
        .roi_cent_world = .{ .vec = .{ 0, 0, -2.2 } },
        .focal_length = 1,
        .sub_sample = args.sub_sample,
    };
    const config = rastcfg.RasterConfig{
        .parallel = .{ .threads = args.threads },
        .save_strategy = .none,
        .report = .{ .mode = .bench },
        .advanced = .{
            .solver = .{
                .multi_root = .{
                    .method = args.method,
                    .seed_bank_depth = args.seed_bank_depth,
                    .reuse_radius_rows = args.reuse_radius_rows,
                    .reuse_method = args.reuse_method,
                    .legacy_fallback = args.legacy_fallback,
                    .single_frozen_jac = args.single_frozen_jac,
                    .child_seed = args.child_seed,
                    .adaptive_max_depth = args.adaptive_max_depth,
                    .adaptive_stop_px = args.adaptive_stop_px,
                },
            },
        },
    };
    var out_dir = try orch.openDirEnsured(io, args.out_dir);
    defer out_dir.close(io);
    var file = try out_dir.createFile(io, "raw_stats_multiroot.csv", .{});
    defer file.close(io);
    var write_buf: [4096]u8 = undefined;
    var buffered = file.writer(io, &write_buf);
    const writer = &buffered.interface;
    try writer.writeAll(
        "scene,flat_scale,method,child_seed,legacy_fallback," ++
            "single_frozen_jac,adaptive_max_depth,adaptive_stop_px," ++
            "reuse_radius_rows,reuse_method,run,elements,width,height,sub_sample," ++
            "visible,shaded,solver_calls,solver_iters,solver_diverged," ++
            "geometry_ms,prepare_ms,raster_ms,active_ms,e2e_ms," ++
            "melems_s,mpx_s,candidate_children,cache_eligible," ++
            "cache_attempts,cache_successes,cache_failures," ++
            "extrap_attempts,extrap_successes,center_attempts," ++
            "center_successes,bank_fallbacks,bank_fallback_successes," ++
            "bank_improved,bank_recovered,bank_numerical_ties," ++
            "cross_child,center_failures,reuse_recoveries\n",
    );
    for (0..args.warmup + args.runs) |rr| {
        var capture: [1]report.FrameBenchCapture = undefined;
        const started = Timestamp.now(io, .awake);
        try riley.rasterReportInto(
            outer_alloc,
            io,
            &.{camera},
            &meshes,
            config,
            null,
            null,
            &capture,
        );
        const elapsed_ns = started.durationTo(
            Timestamp.now(io, .awake),
        ).raw.nanoseconds;
        if (rr < args.warmup) continue;
        const log = capture[0].bench_log;
        const times = log.frame_times;
        const e2e_ms = @as(F, @floatFromInt(elapsed_ns)) / 1e6;
        const geom_ms = (times.geometry_prep + times.tile_overlap) / 1e6;
        const raster_ms = report.rasterStageTime(times) / 1e6;
        const mpixels = @as(F, @floatFromInt(args.width)) *
            @as(F, @floatFromInt(args.height)) / 1e6;
        const seconds = e2e_ms / 1e3;
        try writer.print(
            "{s},{d:.6},{s},{s},{},{},{d},{d:.3},{d}," ++
                "{s},{d},{d},{d},{d},{d}," ++
                "{d},{d},{d},{d},{d},{d:.6},{d:.6},{d:.6}," ++
                "{d:.6},{d:.6},{d:.6},{d:.6}",
            .{
                @tagName(args.scene),
                args.flat_scale,
                @tagName(args.method),
                @tagName(args.child_seed),
                args.legacy_fallback,
                args.single_frozen_jac,
                args.adaptive_max_depth,
                args.adaptive_stop_px,
                args.reuse_radius_rows,
                @tagName(args.reuse_method),
                rr - args.warmup,
                meshes.len * args.elements_per_type,
                args.width,
                args.height,
                args.sub_sample,
                log.vis_elems,
                log.total_shaded_px,
                log.solver_calls,
                log.total_solver_iters,
                log.solver_diverged,
                geom_ms,
                times.geom_prep_hulls_shaders / 1e6,
                raster_ms,
                times.active_time / 1e6,
                e2e_ms,
                @as(F, @floatFromInt(log.total_elems)) / seconds / 1e6,
                mpixels / seconds,
            },
        );
        const cs = log.coherent;
        try writer.print(
            ",{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}," ++
                "{d},{d},{d},{d},{d},{d}\n",
            .{
                cs.candidate_children,
                cs.cache_eligible,
                cs.cache_attempts,
                cs.cache_successes,
                cs.cache_failures,
                cs.extrap_attempts,
                cs.extrap_successes,
                cs.center_attempts,
                cs.center_successes,
                cs.bank_fallbacks,
                cs.bank_fallback_successes,
                cs.bank_improved,
                cs.bank_recovered,
                cs.bank_numerical_ties,
                cs.cross_child,
                cs.center_failures,
                cs.reuse_recoveries,
            },
        );
        std.debug.print(
            "{s} bench {s}/{s} run {d}: e2e={d:.3} ms " ++
                "raster={d:.3} ms Newton={d}\n",
            .{
                @tagName(args.scene),
                @tagName(args.method),
                @tagName(args.child_seed),
                rr - args.warmup,
                e2e_ms,
                raster_ms,
                log.solver_calls,
            },
        );
    }
    try buffered.flush();
}
