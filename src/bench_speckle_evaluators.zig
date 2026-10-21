// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
//! One process is one observation. Decode, fixture loading and checksum reduction
//! are excluded. Evaluation prepares static geometry once; full-render uses the
//! production API, including output allocation, frame geometry and assembly.
const std = @import("std");
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const meshio = @import("riley/zig/meshio.zig");
const riley = @import("riley/zig/riley.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const uvio = @import("riley/zig/uvio.zig");
const policy = @import("riley/zig/speckleconfig.zig");
const speckle = @import("riley/zig/speckleops.zig");
const bench = @import("riley/zig/specklebench.zig");
const build = @import("riley/zig/buildconfig.zig");
const timing = @import("riley/zig/benchtiming.zig");
const mo = @import("riley/zig/meshpipeline.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const texops = @import("riley/zig/textureops.zig");
const imageio = @import("riley/zig/imageio.zig");
const F = build.F;

const Options = struct {
    mode: enum { evaluation, @"full-render" } = .evaluation,
    evaluator: ?policy.Evaluator = null,
    texture_material: bool = false,
    threads: u16 = 1,
    plate: bool = true,
    pattern: policy.Pattern = .disk,
    jitter: F = 0.08,
    occupancy: F = 0.7,
    neighbors: ?u8 = null,
    frames: usize = 16,
    width: u32 = 3840,
    height: u32 = 2160,
    cells_u: ?F = null,
    cells_v: ?F = null,
    radius: F = 0.35,
    softness: F = 0,
    perlin_threshold: F = 0,
    perlin_transition: F = 0.12,
    seed: u32 = 0xa511e9b3,
    texture: []const u8 = "texture/speckle_mono.bmp",
    texture_filter: texops.TexSamp = .cubic_catmull_rom,

    fn parse(args: []const []const u8) !Options {
        var out: Options = .{};
        var soft = false;
        var i: usize = 1;
        while (i < args.len) : (i += 2) {
            if (i + 1 == args.len) return error.MissingFlagValue;
            const key = args[i];
            const value = args[i + 1];
            if (std.mem.eql(u8, key, "--mode")) {
                out.mode = std.meta.stringToEnum(@TypeOf(out.mode), value) orelse return error.InvalidMode;
            } else if (std.mem.eql(u8, key, "--evaluator")) {
                out.texture_material = std.mem.eql(u8, value, "texture");
                out.evaluator = if (out.texture_material) null else policy.parseEvaluator(value) orelse return error.InvalidEvaluator;
            } else if (std.mem.eql(u8, key, "--scene")) {
                out.plate = std.mem.eql(u8, value, "plate");
                if (!out.plate and !std.mem.eql(u8, value, "sphere")) return error.InvalidScene;
            } else if (std.mem.eql(u8, key, "--pattern")) {
                soft = std.mem.eql(u8, value, "soft");
                out.pattern = if (soft or std.mem.eql(u8, value, "hard")) .disk else policy.parsePattern(value) orelse return error.InvalidPattern;
            } else if (std.mem.eql(u8, key, "--texture")) {
                out.texture = value;
            } else if (std.mem.eql(u8, key, "--texture-filter")) {
                out.texture_filter = std.meta.stringToEnum(texops.TexSamp, value) orelse return error.InvalidTextureFilter;
                if (out.texture_filter != .nearest and out.texture_filter != .linear and out.texture_filter != .cubic_catmull_rom) return error.InvalidTextureFilter;
            } else if (std.mem.eql(u8, key, "--threads")) {
                out.threads = try std.fmt.parseInt(u16, value, 10);
            } else if (std.mem.eql(u8, key, "--frames")) {
                out.frames = try std.fmt.parseInt(usize, value, 10);
            } else if (std.mem.eql(u8, key, "--width")) {
                out.width = try std.fmt.parseInt(u32, value, 10);
            } else if (std.mem.eql(u8, key, "--height")) {
                out.height = try std.fmt.parseInt(u32, value, 10);
            } else if (std.mem.eql(u8, key, "--neighbors")) {
                out.neighbors = try std.fmt.parseInt(u8, value, 10);
            } else if (std.mem.eql(u8, key, "--seed")) {
                out.seed = try std.fmt.parseInt(u32, value, 0);
            } else if (std.mem.eql(u8, key, "--cells-u")) {
                out.cells_u = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--cells-v")) {
                out.cells_v = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--jitter")) {
                out.jitter = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--occupancy")) {
                out.occupancy = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--radius")) {
                out.radius = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--perlin-threshold")) {
                out.perlin_threshold = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--perlin-transition")) {
                out.perlin_transition = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--softness")) {
                out.softness = try std.fmt.parseFloat(F, value);
            } else return error.UnknownBenchmarkFlag;
        }
        if (soft and out.softness == 0) out.softness = 0.1;
        if (out.threads == 0 or out.frames == 0 or out.width < 2 or out.height < 2 or out.width > std.math.maxInt(u16) or out.height > std.math.maxInt(u16)) return error.InvalidBenchmarkDimensions;
        if (!out.texture_material) try out.params().validate();
        return out;
    }

    fn pixels(self: Options) [2]u32 {
        return .{ self.width, self.height };
    }
    fn params(self: Options) speckle.Speckle2DParams {
        return .{ .evaluator = self.evaluator, .pattern = self.pattern, .edge_softness = self.softness, .perlin_coverage_threshold = self.perlin_threshold, .perlin_coverage_transition_width = self.perlin_transition, .radius_mean = self.radius, .radius_jitter = self.jitter, .occupancy = self.occupancy, .neighbor_count = self.neighbors, .cells_per_uv = .{ self.cells_u orelse (if (self.plate) @as(F, 320) else 256), self.cells_v orelse (if (self.plate) @as(F, 192) else 160) }, .seed = self.seed };
    }
    fn textureConfig(self: Options) texops.TexSampConfig {
        return .{ .sample = self.texture_filter, .mode = if (self.texture_filter == .cubic_catmull_rom) .lut_lerp else .direct };
    }
    fn rasterConfig(self: Options) riley.RasterConfig {
        return .{ .parallel = .{ .threads = self.threads }, .save_strategy = if (self.mode == .evaluation) .none else .memory, .report = .{ .mode = .off } };
    }
};

fn listEvaluators() void {
    std.debug.print("{{\"evaluators\":[", .{});
    inline for (std.enums.values(policy.Evaluator), 0..) |evaluator, i| {
        std.debug.print("{s}\"{s}\"", .{ if (i == 0) "" else ",", policy.evaluatorName(evaluator) });
    }
    std.debug.print(",\"texture\"],\"overrides_enabled\":{},\"configs\":[", .{build.enable_all_evaluators});
    for (policy.generationConfigs(true), 0..) |cfg, i| {
        std.debug.print("{s}{{\"evaluator\":\"{s}\",\"pattern\":\"{s}\",\"neighbors\":{d},\"soft_edges\":{}}}", .{ if (i == 0) "" else ",", policy.evaluatorName(cfg.evaluator), @tagName(cfg.pattern), cfg.neighbor_count, cfg.soft_edges });
    }
    std.debug.print("]}}\n", .{});
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const alloc = arena.allocator();
    const raw_args = init.minimal.args.vector;
    const args = try alloc.alloc([]const u8, raw_args.len);
    for (raw_args, 0..) |arg, n| args[n] = std.mem.span(arg);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list-evaluators")) {
        listEvaluators();
        return;
    }
    const opts = try Options.parse(args);
    var threaded_io = riley.getThreadedIo(alloc, init.minimal, opts.threads);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const scene = try loadScene(alloc, io, opts);
    const params = opts.params();
    const texture = if (opts.texture_material) try imageio.loadImage(u8, 1, alloc, io, opts.texture, .bmp) else null;
    var resource_ns: i96 = 0;
    var render_ns: i96 = 0;
    var combined_ns: i96 = 0;
    var result: bench.Result = .{};
    var image_samples: usize = 0;
    if (opts.mode == .evaluation) {
        const config = opts.rasterConfig();
        const cam = try camera.CameraPrepared.init(alloc, cameraInput(scene.sim, opts));
        const geometry = try bench.Geometry.prepare(alloc, io, &cam, scene.sim.coords, scene.sim.connect, scene.uvs.array, config, opts.threads);
        var evaluation = try bench.Evaluation.init(alloc, io, &cam, &geometry, config, opts.threads);
        const resource_start = std.Io.Timestamp.now(io, .awake);
        var resources = if (texture == null) try speckle.generateResources(init.gpa, params) else speckle.Resources{};
        defer resources.deinit(init.gpa);
        // Production UV gathering; interpolation LUTs are compile-time constants.
        const prepared: ?shaderops.TexPrepared(u8, 1) = if (texture) |tex| .{ .elem_uvs = try mo.prepUVs(alloc, &scene.uvs.array, &scene.sim.connect), .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null } else null;
        resource_ns = resource_start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
        const eval_start = std.Io.Timestamp.now(io, .awake);
        if (prepared) |shader| try evaluation.evaluateTexture(shader, opts.frames) else try evaluation.evaluate(params, resources, opts.frames);
        render_ns = eval_start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
        combined_ns = resource_ns + render_ns;
        result = evaluation.result();
    } else {
        const mesh = try scene.mesh(alloc, opts, texture);
        const cam_input = cameraInput(scene.sim, opts);
        var capture: timing.Capture = .{ .io = io };
        timing.active = &capture;
        defer timing.active = null;
        const start = std.Io.Timestamp.now(io, .awake);
        const output = (try riley.rasterAdvanced(alloc, io, &.{cam_input}, &.{mesh}, opts.rasterConfig(), null, .{ .render_groups = .{ .supplied = &.{.{ .io = io, .workers = opts.threads }} } })).?;
        combined_ns = start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
        resource_ns = capture.resource_ns;
        render_ns = combined_ns - resource_ns;
        image_samples = output.slice.len;
        for (output.slice) |value| {
            if (!std.math.isFinite(value)) return error.NonFiniteRenderOutput;
            result.checksum +%= @as(std.meta.Int(.unsigned, @bitSizeOf(F)), @bitCast(value));
        }
    }
    const resolved = try policy.resolve(build.enable_all_evaluators, if (opts.texture_material) .disk else opts.pattern, if (opts.texture_material) null else opts.evaluator, if (opts.texture_material) null else opts.neighbors, !opts.texture_material and opts.softness > 0);
    const record = .{
        .mode = @tagName(opts.mode),
        .workload_mode = if (opts.mode == .evaluation) bench.workload_mode else "production-raster-advanced-memory-v2",
        .evaluator = if (opts.texture_material) "texture" else policy.evaluatorName(resolved.evaluator),
        .scene = if (opts.plate) "plate" else "sphere",
        .pattern = if (opts.pattern == .disk) (if (opts.softness > 0) "soft" else "hard") else @tagName(opts.pattern),
        .threads = opts.threads,
        .frames = opts.frames,
        .width = opts.width,
        .height = opts.height,
        .cells_u = params.cells_per_uv[0],
        .cells_v = params.cells_per_uv[1],
        .perlin_threshold = opts.perlin_threshold,
        .perlin_transition = opts.perlin_transition,
        .radius = opts.radius,
        .jitter = opts.jitter,
        .occupancy = opts.occupancy,
        .neighbors = if (opts.texture_material) opts.neighbors orelse policy.default_neighbor_count else resolved.neighbor_count,
        .softness = opts.softness,
        .seed = opts.seed,
        .texture = opts.texture,
        .texture_filter = @tagName(opts.texture_filter),
        .texture_mode = @tagName(opts.textureConfig().mode),
        .resource_ns = resource_ns,
        .render_ns = render_ns,
        .combined_ns = combined_ns,

        .checksum = result.checksum,
        .shaded_samples = result.shaded_samples,
        .backface_rejections = result.backface_rejections,
        .evaluation_counters_available = opts.mode == .evaluation,
        .image_samples = image_samples,
        .precision = @typeName(F),
        .simd = @tagName(build.config.simd),
    };
    std.debug.print("BENCH {s}\n", .{try std.json.Stringify.valueAlloc(alloc, record, .{})});
}

fn cameraInput(sim: meshio.SimData, opts: Options) camera.CameraInput {
    const pixel_size: [2]F = .{ 5.3e-6, 5.3e-6 };
    const rotation = @import("riley/zig/rotation.zig").Rotation.init(0, 0, 0);
    return .{ .pixels_num = opts.pixels(), .pixels_size = pixel_size, .pos_world = cameraops.posFillFrameFromRot(&sim.coords, opts.pixels(), pixel_size, 0.05, rotation, 1.15), .rot_world = rotation, .roi_cent_world = sceneops.boundsCenter(&sim.coords), .focal_length = 0.05, .sub_sample = 1, .subpixel_center_map = .per_tile };
}

test "speckle benchmark named options and default gate" {
    const defaults = try Options.parse(&.{"bench"});
    try std.testing.expectEqual([2]u32{ 3840, 2160 }, defaults.pixels());
    try std.testing.expectEqualDeep(texops.TexSampConfig{ .sample = .cubic_catmull_rom, .mode = .lut_lerp }, defaults.textureConfig());
    for ([_][]const u8{ "nearest", "linear", "cubic_catmull_rom" }) |filter| {
        const opts = try Options.parse(&.{ "bench", "--evaluator", "texture", "--texture-filter", filter });
        try std.testing.expectEqualStrings(filter, @tagName(opts.textureConfig().sample));
        try std.testing.expect(opts.textureConfig().isValid());
    }
    try std.testing.expectError(error.InvalidTextureFilter, Options.parse(&.{ "bench", "--texture-filter", "lanczos3" }));
    try std.testing.expectError(error.InvalidPattern, Options.parse(&.{ "bench", "--pattern", "unknown" }));
    try std.testing.expectError(error.InvalidBenchmarkDimensions, Options.parse(&.{ "bench", "--frames", "0" }));
    const args = &.{ "bench", "--evaluator", "cell-hash", "--pattern", "soft", "--height", "32" };
    if (comptime build.enable_all_evaluators) {
        const opts = try Options.parse(args);
        try std.testing.expect(opts.softness > 0);
        try std.testing.expectEqual(policy.Evaluator.cell_hash, opts.evaluator.?);
    } else try std.testing.expectError(error.SpeckleOverridesDisabled, Options.parse(args));
    const candidate = &.{ "bench", "--evaluator", "classified-indexed", "--jitter", "0.08" };
    if (comptime build.enable_all_evaluators) {
        const opts = try Options.parse(candidate);
        try std.testing.expectEqual(policy.Evaluator.classified_indexed, opts.evaluator.?);
        try std.testing.expectEqual(@as(F, 0.08), opts.jitter);
        try std.testing.expectError(error.ClassifiedIndexedRequiresDiskAndNineNeighbors, Options.parse(&.{ "bench", "--evaluator", "classified-indexed", "--neighbors", "4" }));
    } else try std.testing.expectError(error.SpeckleOverridesDisabled, Options.parse(candidate));
}
const Scene = struct {
    sim: meshio.SimData,
    uvs: uvio.UVMap,

    fn mesh(self: Scene, alloc: std.mem.Allocator, opts: Options, texture: ?texops.Tex(u8, 1)) !mo.MeshInput {
        const shader: shaderops.ShaderInput = if (texture) |tex| .{ .tex_u8 = .{ .uvs = self.uvs.array, .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null } } else .{ .speckle = .{ .uvs = self.uvs.array, .params = opts.params(), .bits = null } };
        // Zero displacement preserves production per-frame geometry preparation.
        return .{ .mesh_type = .tri6, .coords = self.sim.coords, .connect = self.sim.connect, .disp = try meshio.Field.initAlloc(alloc, opts.frames, self.sim.coords.mat.rows_num, 3), .shader = shader };
    }
};

fn loadScene(alloc: std.mem.Allocator, io: std.Io, opts: Options) !Scene {
    var sim = try meshio.loadSimData(alloc, io, if (opts.plate) "data/min/tri6_twoelems/coords.csv" else "data/min/tri6_sphere200/coords.csv", if (opts.plate) "data/min/tri6_twoelems/connectivity.csv" else "data/min/tri6_sphere200/connect.csv", null, null);
    var uvs = try uvio.loadUVMap(alloc, io, if (opts.plate) "data/min/tri6_twoelems/uvs.csv" else "data/min/tri6_sphere200/uvs.csv");
    if (opts.plate) {
        // The existing benchmark's perpendicular, straight-sided quadratic plate.
        const xy = [_][2]F{ .{ 1, 1 }, .{ 1, -1 }, .{ -1, -1 }, .{ -1, 1 }, .{ 1, 0 }, .{ 0, 0 }, .{ 0, -1 }, .{ 0, 0 }, .{ 0, 1 }, .{ -1, 0 } };
        for (xy, 0..) |p, n| {
            sim.coords.mat.set(n, 0, p[0]);
            sim.coords.mat.set(n, 1, p[1]);
            sim.coords.mat.set(n, 2, 0);
            uvs.array.set(&.{ n, 0 }, (p[0] + 1) / 2);
            uvs.array.set(&.{ n, 1 }, (p[1] + 1) / 2);
        }
    }
    return .{ .sim = sim, .uvs = uvs };
}

const TestFixture = struct {
    cam: camera.CameraPrepared,
    geometry: bench.Geometry,

    fn init(alloc: std.mem.Allocator, opts: Options, tile_size: u16) !TestFixture {
        const scene = try loadScene(alloc, std.testing.io, opts);
        const cam = try camera.CameraPrepared.init(alloc, cameraInput(scene.sim, opts));
        var config = opts.rasterConfig();
        config.advanced.raster.tile_size_override = tile_size;
        return .{ .cam = cam, .geometry = try bench.Geometry.prepare(alloc, std.testing.io, &cam, scene.sim.coords, scene.sim.connect, scene.uvs.array, config, opts.threads) };
    }

    fn evaluation(self: *const TestFixture, alloc: std.mem.Allocator, threads: u16) !bench.Evaluation {
        return bench.Evaluation.init(alloc, std.testing.io, &self.cam, &self.geometry, .{ .parallel = .{ .threads = threads } }, threads);
    }
};

const smoke: Options = .{ .width = 32, .height = 24, .frames = 2, .cells_u = 4, .cells_v = 3 };

test "speckle benchmark rejects occluded samples but keeps closer depth updates" {
    const NDArray = @import("riley/zig/ndarray.zig").NDArray;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var fixture = try TestFixture.init(alloc, smoke, 64);
    const source = fixture.geometry;
    const overlap = source.tiling.overlaps[source.tiling.active_tiles[0].overlap_start];
    const n = source.coords.dims[2];
    const nh = source.raster_hulls.dims[2];
    fixture.geometry.coords = try NDArray(F).initFlat(alloc, &.{ 2, 3, n });
    fixture.geometry.uvs = try NDArray(F).initFlat(alloc, &.{ 2, 2, n });
    fixture.geometry.raster_hulls = try NDArray(F).initFlat(alloc, &.{ 2, 2, nh });
    // Same projection and UVs at two depths: depth order determines consumption.
    for (0..2) |ee| {
        for (source.coords.slice[overlap.elem_idx * 3 * n ..][0 .. 3 * n], fixture.geometry.coords.slice[ee * 3 * n ..][0 .. 3 * n]) |value, *dest| dest.* = value * @as(F, if (ee == 0) 1 else 2);
        @memcpy(fixture.geometry.uvs.slice[ee * 2 * n ..][0 .. 2 * n], source.uvs.slice[overlap.elem_idx * 2 * n ..][0 .. 2 * n]);
        @memcpy(fixture.geometry.raster_hulls.slice[ee * 2 * nh ..][0 .. 2 * nh], source.raster_hulls.slice[overlap.elem_idx * 2 * nh ..][0 .. 2 * nh]);
    }
    var tiles = [_]@import("riley/zig/elemtilebinning.zig").ActiveTile{source.tiling.active_tiles[0]};
    tiles[0].overlap_start = 0;
    tiles[0].overlap_count = 1;
    tiles[0].bins = @splat(.{});
    const one_root_bin = @intFromEnum(@import("riley/zig/elemtilebinning.zig").ElemBin.tri6_one_root);
    tiles[0].bins[one_root_bin] = .{ .start = 0, .count = 1 };
    var overlaps = [_]@import("riley/zig/elemtilebinning.zig").OverlapBBox{ overlap, overlap };
    overlaps[0].elem_idx = 0;
    overlaps[1].elem_idx = 1;
    fixture.geometry.tiling = .{ .active_tiles = &tiles, .overlaps = &overlaps };
    var evaluation = try fixture.evaluation(alloc, 1);
    var resources = try speckle.generateResources(alloc, smoke.params());
    defer resources.deinit(alloc);
    try evaluation.evaluate(smoke.params(), resources, 1);
    const front_only = evaluation.result();
    try std.testing.expect(front_only.shaded_samples > 0);
    tiles[0].overlap_count = 2;
    tiles[0].bins[one_root_bin].count = 2;
    try evaluation.evaluate(smoke.params(), resources, 1);
    try std.testing.expectEqualDeep(front_only, evaluation.result()); // Near first rejects far.
    std.mem.swap(@TypeOf(overlaps[0]), &overlaps[0], &overlaps[1]);
    try evaluation.evaluate(smoke.params(), resources, 1);
    var both = front_only;
    both.merge(front_only);
    try std.testing.expectEqualDeep(both, evaluation.result()); // Far first shades both.
}

test "speckle benchmark root bins preserve production facing and multi-root slots" {
    const frontend = @import("riley/zig/rasterfrontend.zig");
    const bins = @import("riley/zig/elemtilebinning.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var opts = smoke;
    opts.plate = false;
    const fixture = try TestFixture.init(arena.allocator(), opts, 8);
    for (fixture.geometry.tiling.active_tiles) |tile| {
        inline for (.{ bins.ElemBin.tri6_one_root, bins.ElemBin.tri6_multi_root }) |bin| {
            const range = tile.bins[@intFromEnum(bin)];
            for (fixture.geometry.tiling.overlaps[range.start .. range.start + range.count]) |overlap| {
                const nodes = try frontend.loadElemVec3Slices(6, F, &fixture.geometry.coords, overlap.elem_idx);
                var projected: frontend.RasterCoords2D(6) = undefined;
                const offsets = fixture.cam.calcRasterOffsets();
                for (0..6) |nn| {
                    projected.x[nn] = nodes.x[nn] / nodes.z[nn] + offsets.x_off;
                    projected.y[nn] = nodes.y[nn] / nodes.z[nn] + offsets.y_off;
                }
                const facing = frontend.classifyHighOrdFacing(6, projected);
                try std.testing.expectEqual(bins.binRootClass(bin), facing orelse .one_root);
                if (comptime bin == .tri6_multi_root) {
                    const hulls = fixture.geometry.multiroot_hulls orelse return error.MissingMultiRootData;
                    const slot = hulls.slot_by_visible_elem.get(overlap.elem_idx);
                    try std.testing.expect(slot != std.math.maxInt(u32));
                    try std.testing.expect(@as(usize, slot) * 4 + 4 <= hulls.leaves_pre_calc.len);
                }
            }
        }
    }
}

test "speckle benchmark workers depth resets and texture filters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tex = try imageio.loadImage(u8, 1, alloc, std.testing.io, "texture/speck128_mono_u8.bmp", .bmp);
    for ([_]bool{ true, false }) |plate| {
        var opts = smoke;
        opts.plate = plate;
        const fixture = try TestFixture.init(alloc, opts, 8);
        var single = try fixture.evaluation(alloc, 1);
        var parallel = try fixture.evaluation(alloc, 4);
        const Variant = enum { hard, soft, gaussian, perlin, perlin_mask, nearest, linear, cubic_catmull_rom };
        for (std.enums.values(Variant)) |variant| {
            if (variant == .perlin_mask and !build.enable_all_evaluators) continue;
            var params = opts.params();
            params.pattern = switch (variant) {
                .gaussian => .gaussian,
                .perlin, .perlin_mask => .perlin,
                else => .disk,
            };
            params.edge_softness = if (variant == .soft) 0.1 else 0;
            if (comptime build.enable_all_evaluators) params.evaluator = switch (variant) {
                .perlin => .gradient_lattice,
                .perlin_mask => .mask_u8,
                else => .cell_hash,
            };
            const texture_variant = variant == .nearest or variant == .linear or variant == .cubic_catmull_rom;
            opts.texture_filter = if (texture_variant) std.meta.stringToEnum(texops.TexSamp, @tagName(variant)).? else .linear;
            var resources = if (texture_variant) speckle.Resources{} else try speckle.generateResources(alloc, params);
            defer resources.deinit(alloc);
            var once: bench.Result = undefined;
            for ([_]usize{ 1, 2 }) |frames| {
                if (texture_variant) {
                    const shader: shaderops.TexPrepared(u8, 1) = .{ .elem_uvs = fixture.geometry.uvs, .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null };
                    try single.evaluateTexture(shader, frames);
                    try parallel.evaluateTexture(shader, frames);
                } else {
                    try single.evaluate(params, resources, frames);
                    try parallel.evaluate(params, resources, frames);
                }
                try std.testing.expect(single.result().shaded_samples > 0);
                if (!plate) try std.testing.expect(single.result().backface_rejections > 0);
                try std.testing.expectEqualDeep(single.result(), parallel.result());
                if (frames == 1) once = single.result() else {
                    once.merge(once);
                    try std.testing.expectEqualDeep(once, single.result());
                }
            }
        }
    }
}

test "speckle benchmark production full render memory output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var opts = smoke;
    opts.mode = .@"full-render";
    const scene = try loadScene(alloc, std.testing.io, opts);
    const tex = try imageio.loadImage(u8, 1, alloc, std.testing.io, "texture/speck128_mono_u8.bmp", .bmp);
    for ([_]?texops.Tex(u8, 1){ null, tex }) |texture| {
        const mesh = try scene.mesh(alloc, opts, texture);
        var capture: timing.Capture = .{ .io = std.testing.io };
        timing.active = &capture;
        defer timing.active = null;
        const output = (try riley.rasterAdvanced(alloc, std.testing.io, &.{cameraInput(scene.sim, opts)}, &.{mesh}, opts.rasterConfig(), null, .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = 1 }} } })).?;
        try std.testing.expectEqual(@as(usize, 32 * 24 * 2), output.slice.len);
        try std.testing.expect(capture.resource_ns > 0);
        for (output.slice) |value| try std.testing.expect(std.math.isFinite(value));
    }
}
