// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! One process is one observation. Fixture loading and texture decode are excluded.
//! Evaluation measures resource preparation and the static-geometry loop; its final
//! reduction is excluded. Full-render times the production memory API, including
//! UV gathering/calibration, output allocation, frame geometry and assembly.
//! The full-render image hash is computed after timing.
const std = @import("std");
const builtin = @import("builtin");
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
const physical = @import("riley/zig/speckleparams.zig");

const F = build.F;
const grid_defaults: speckle.GridParams = .{};

// Use resolved feature bits, not the model's defaults: -mcpu can add/remove features.
// Names follow the target's feature enum order, which is deterministic.
const cpu_features = blk: {
    @setEvalBranchQuota(100000);
    const all = builtin.cpu.arch.allFeaturesList();
    var count: usize = 0;
    for (all, 0..) |_, index| {
        if (builtin.cpu.features.isEnabled(@intCast(index))) count += 1;
    }
    var names: [count][]const u8 = undefined;
    var next: usize = 0;
    for (all, 0..) |feature, index| {
        if (builtin.cpu.features.isEnabled(@intCast(index))) {
            names[next] = feature.name;
            next += 1;
        }
    }
    break :blk names;
};

const BuildIdentity = struct {
    precision: []const u8,
    simd: []const u8,
    simd_vector_width: usize,
    newton_solver: []const u8,
    enable_all_evaluators: bool,
    speckle_mask_samples_per_cell: usize,
    optimize: []const u8,
    strip: bool,
    zig_version: []const u8,
    target_arch: []const u8,
    cpu_model: []const u8,
    cpu_features: []const []const u8,
};

fn buildIdentity() BuildIdentity {
    return .{
        .precision = @typeName(F),
        .simd = @tagName(build.config.simd),
        .simd_vector_width = build.SimdWidth,
        .newton_solver = @tagName(build.NewtonMode),
        .enable_all_evaluators = build.enable_all_evaluators,
        .speckle_mask_samples_per_cell = build.speckle_mask_samples_per_cell,
        .optimize = @tagName(builtin.mode),
        .strip = builtin.strip_debug_info,
        .zig_version = builtin.zig_version_string,
        .target_arch = @tagName(builtin.cpu.arch),
        .cpu_model = builtin.cpu.model.name,
        .cpu_features = &cpu_features,
    };
}

const workload_modes = .{ .evaluation = bench.workload_mode, .@"full-render" = "production-raster-advanced-memory-v5" };

const Options = struct {
    mode: enum { evaluation, @"full-render" } = .evaluation,
    evaluator: ?policy.Evaluator = null,
    texture_material: bool = false,
    threads: u16 = 1,
    plate: bool = true,
    pattern: policy.Pattern = .disk,
    jitter: ?F = null,
    occupancy: ?F = null,
    neighbors: ?policy.Neighborhood = null,
    frames: usize = 16,
    width: u32 = 3840,
    height: u32 = 2160,
    cells_u: ?F = null,
    cells_v: ?F = null,
    radius: ?F = null,
    coverage: ?F = null,
    cell_size: ?F = null,
    soft: bool = false,
    softness: F = 0,
    perlin_threshold: F = grid_defaults.perlin_coverage_threshold,
    perlin_transition: F = grid_defaults.perlin_coverage_transition_width,
    seed: u32 = grid_defaults.seed,
    texture: []const u8 = "texture/speckle_mono.bmp",
    texture_filter: texops.TexSamp = .cubic_catmull_rom,

    fn parse(args: []const []const u8) !Options {
        var out: Options = .{};
        var explicit_seed = false;
        var physical_controls = false;
        var perlin_controls = false;
        var i: usize = 1;
        while (i < args.len) : (i += 2) {
            if (i + 1 == args.len) return error.MissingFlagValue;
            const key = args[i];
            const value = args[i + 1];
            if (std.mem.eql(u8, key, "--mode")) {
                out.mode = std.meta.stringToEnum(@TypeOf(out.mode), value) orelse return error.InvalidMode;
            } else if (std.mem.eql(u8, key, "--evaluator")) {
                out.texture_material = std.mem.eql(u8, value, "texture");
                out.evaluator = if (out.texture_material or std.mem.eql(u8, value, "auto")) null else policy.parseEvaluator(value) orelse return error.InvalidEvaluator;
            } else if (std.mem.eql(u8, key, "--scene")) {
                out.plate = std.mem.eql(u8, value, "plate");
                if (!out.plate and !std.mem.eql(u8, value, "sphere")) return error.InvalidScene;
            } else if (std.mem.eql(u8, key, "--pattern")) {
                out.soft = std.mem.eql(u8, value, "soft");
                out.pattern = if (out.soft or std.mem.eql(u8, value, "hard")) .disk else policy.parsePattern(value) orelse return error.InvalidPattern;
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
                const count = try std.fmt.parseInt(u8, value, 10);
                out.neighbors = std.enums.fromInt(policy.Neighborhood, count) orelse return error.InvalidSpeckleNeighborCount;
            } else if (std.mem.eql(u8, key, "--seed")) {
                explicit_seed = true;
                out.seed = try std.fmt.parseInt(u32, value, 0);
            } else if (std.mem.eql(u8, key, "--cells-u")) {
                out.cells_u = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--cells-v")) {
                out.cells_v = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--coverage")) {
                physical_controls = true;
                out.coverage = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--cell-size")) {
                perlin_controls = true;
                out.cell_size = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--jitter")) {
                physical_controls = true;
                out.jitter = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--occupancy")) {
                physical_controls = true;
                out.occupancy = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--radius")) {
                physical_controls = true;
                out.radius = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--perlin-threshold")) {
                perlin_controls = true;
                out.perlin_threshold = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--perlin-transition")) {
                perlin_controls = true;
                out.perlin_transition = try std.fmt.parseFloat(F, value);
            } else if (std.mem.eql(u8, key, "--softness")) {
                physical_controls = true;
                out.softness = try std.fmt.parseFloat(F, value);
            } else return error.UnknownBenchmarkFlag;
        }
        if (out.threads == 0 or out.frames == 0 or out.width < 2 or out.height < 2 or
            out.width > std.math.maxInt(u16) or out.height > std.math.maxInt(u16))
            return error.InvalidBenchmarkDimensions;
        const cell_controls = out.cells_u != null or out.cells_v != null;
        if (out.texture_material) {
            if (physical_controls or perlin_controls or cell_controls or out.neighbors != null or explicit_seed)
                return error.TextureControlsNotApplicable;
            return out;
        }
        if (out.mode == .evaluation) {
            if (out.coverage != null or out.cell_size != null)
                return error.PhysicalControlsRequireFullRender;
            // Match the runner's raw soft-disk default for direct CLI runs.
            if (out.soft and out.softness == 0) out.softness = 0.04;
            try out.params().validate();
        } else {
            if (out.neighbors != null or out.evaluator != null)
                return error.FullRenderRequiresProductionDefaults;
            if (cell_controls) return error.GridControlsRequireEvaluation;
            if ((out.pattern == .perlin and physical_controls) or
                (out.pattern != .perlin and perlin_controls)) return error.InactivePatternControls;
            if (out.soft != (out.softness > 0)) return error.InvalidBenchmarkSoftness;
        }
        return out;
    }

    fn pixels(self: Options) [2]u32 {
        return .{ self.width, self.height };
    }
    fn params(self: Options) speckle.GridParams {
        // Fallbacks for direct CLI runs and tests; the A/B runner sends explicit case values.
        return .{
            .evaluator = self.evaluator,
            .pattern = self.pattern,
            .edge_softness = self.softness,
            .perlin_coverage_threshold = self.perlin_threshold,
            .perlin_coverage_transition_width = self.perlin_transition,
            .radius_mean = self.radius orelse 0.35,
            .radius_jitter = self.jitter orelse 0.08,
            .occupancy = self.occupancy orelse 0.7,
            .neighbor_count = self.neighbors,
            .cells_per_uv = .{
                self.cells_u orelse (if (self.plate) @as(F, 320) else 256),
                self.cells_v orelse (if (self.plate) @as(F, 192) else 160),
            },
            .seed = self.seed,
        };
    }
    fn friendlyParams(self: Options) !physical.SpeckleParams {
        if (self.pattern == .perlin) return .{ .perlin = .{
            .cell_size = self.cell_size orelse return error.MissingPerlinCellSize,
            .threshold = self.perlin_threshold,
            .transition_width = self.perlin_transition,
            .seed = self.seed,
        } };
        const input: physical.Speckle2DParams = .{
            .coverage = self.coverage orelse return error.MissingPhysicalSpeckleInputs,
            .radius = self.radius orelse return error.MissingPhysicalSpeckleInputs,
            .jitter = self.jitter orelse 0,
            .occupancy = self.occupancy orelse 1,
            .edge_softness = self.softness,
            .seed = self.seed,
        };
        return if (self.pattern == .disk) .{ .disk = input } else .{ .gaussian = input };
    }
    fn textureConfig(self: Options) texops.TexSampConfig {
        return .{ .sample = self.texture_filter, .mode = if (self.texture_filter == .cubic_catmull_rom) .lut_lerp else .direct };
    }
    fn rasterConfig(self: Options) riley.RasterConfig {
        return .{ .parallel = .{ .threads = self.threads }, .save_strategy = if (self.mode == .evaluation) .none else .memory, .report = .{ .mode = .off } };
    }
};

const EvaluatorRecord = struct {
    evaluator: []const u8,
    pattern: ?[]const u8,
    neighbors: ?u8,
    soft_edges: ?bool,
};
const GenerationRecord = struct {
    evaluator: []const u8,
    pattern: ?[]const u8,
    neighbors: ?u8,
    soft_edges: ?bool,
    sampling_index: u8,
};
const EvaluatorCatalogue = struct {
    evaluators: [std.enums.values(policy.Evaluator).len + 1][]const u8,
    overrides_enabled: bool,
    configs: [policy.generationConfigs(build.enable_all_evaluators).len]GenerationRecord,
    production_configs: [4]EvaluatorRecord,
    sampling_configs: [speckle.kernel_configs.len]EvaluatorRecord,
    build_identity: @TypeOf(buildIdentity()),
    workload_modes: @TypeOf(workload_modes),
    defaults: struct {
        seed: u32 = grid_defaults.seed,
        perlin_threshold: F = grid_defaults.perlin_coverage_threshold,
        perlin_transition: F = grid_defaults.perlin_coverage_transition_width,
    },
};

fn evaluatorRecord(cfg: policy.Config) EvaluatorRecord {
    return .{
        .evaluator = policy.evaluatorName(std.meta.activeTag(cfg)),
        .pattern = if (cfg.pattern()) |pattern| @tagName(pattern) else null,
        .neighbors = if (cfg.neighborhood()) |neighbors| @intFromEnum(neighbors) else null,
        .soft_edges = if (cfg.edges()) |edges| edges == .soft else null,
    };
}

/// Catalogue consumers need no evaluator-specific copies of canonicalization rules.
fn evaluatorCatalogue() EvaluatorCatalogue {
    var out: EvaluatorCatalogue = undefined;
    for (std.enums.values(policy.Evaluator), 0..) |evaluator, i| out.evaluators[i] = policy.evaluatorName(evaluator);
    out.evaluators[out.evaluators.len - 1] = "texture";
    out.overrides_enabled = build.enable_all_evaluators;
    out.build_identity = buildIdentity();
    out.workload_modes = workload_modes;
    out.defaults = .{};
    inline for ([_]policy.Pattern{ .disk, .disk, .gaussian, .perlin }, .{ .hard, .soft, .hard, .hard }, 0..) |pattern, edges, i| {
        out.production_configs[i] = evaluatorRecord(policy.resolve(build.enable_all_evaluators, pattern, null, null, edges) catch unreachable);
    }
    for (speckle.kernel_configs, 0..) |config, i| out.sampling_configs[i] = evaluatorRecord(config);
    for (policy.generationConfigs(build.enable_all_evaluators), 0..) |config, i| {
        const generation = evaluatorRecord(config);
        const index = policy.sampleConfigIndex(build.enable_all_evaluators, config);
        out.configs[i] = .{ .evaluator = generation.evaluator, .pattern = generation.pattern, .neighbors = generation.neighbors, .soft_edges = generation.soft_edges, .sampling_index = index };
    }

    return out;
}

const PreparedIdentity = struct {
    generation_evaluator: ?[]const u8 = null,
    sampling_evaluator: ?[]const u8 = null,
    sampling_index: ?u8 = null,
    backing: []const u8 = "none",
};

/// Stored generation controls and actual dispatch are deliberately separate identities.
fn preparedIdentity(resources: *const speckle.Resources) PreparedIdentity {
    var out: PreparedIdentity = .{ .sampling_index = resources.kernel_index, .backing = @tagName(std.meta.activeTag(resources.data)) };
    if (resources.kernel_index) |index| out.sampling_evaluator = policy.evaluatorName(std.meta.activeTag(speckle.kernel_configs[index]));
    const stored: ?speckle.GridParams = switch (resources.data) {
        .none => null,
        .classified => |data| data.speckles.params,
        inline .cell_binned, .classified_binned, .direct_fixed, .mask, .perlin, .list, .strip_list => |data| data.params,
    };
    if (stored) |params| {
        // These immutable parameters already passed the preparation boundary.
        const generation = params.resolve() catch unreachable;
        out.generation_evaluator = policy.evaluatorName(std.meta.activeTag(generation));
        std.debug.assert(resources.kernel_index == policy.sampleConfigIndex(build.enable_all_evaluators, generation));
    }
    return out;
}

const ResourceMetrics = struct {
    // Null means not collected, rather than a measured zero.
    resource_bytes: ?usize = null,
    duplicated_disk_records: ?usize = null,
    record_capacity: ?usize = null,
};

/// Call only after timed sampling: summing counts must not warm the evaluator's storage.
fn resourceMetrics(resources: *const speckle.Resources) ResourceMetrics {
    var out: ResourceMetrics = .{};
    switch (resources.data) {
        .cell_binned => |data| {
            out.resource_bytes = data.byteSize();
            out.duplicated_disk_records = data.recordCount();
        },
        .strip_list => |data| out.resource_bytes = data.centers.len * @sizeOf([2]F) + data.disks.len * @sizeOf(speckle.SpeckleDisk2D),
        .classified => |data| out.resource_bytes = data.states.len * @sizeOf(u16) + data.speckles.centers.len * @sizeOf([2]F) + data.speckles.disks.len * @sizeOf(speckle.SpeckleDisk2D),
        .classified_binned => |data| {
            out.resource_bytes = data.byteSize();
            var live: usize = 0;
            for (data.counts) |count| live += count;
            out.duplicated_disk_records = live;
            out.record_capacity = data.slots;
        },
        else => {},
    }
    return out;
}

fn listEvaluators(allocator: std.mem.Allocator) !void {
    std.debug.print("{s}\n", .{try std.json.Stringify.valueAlloc(allocator, evaluatorCatalogue(), .{})});
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);
    if (args.len == 2 and std.mem.eql(u8, args[1], "--list-evaluators")) {
        try listEvaluators(alloc);
        return;
    }
    const opts = try Options.parse(args);
    const raw = opts.mode == .evaluation;
    const friendly = if (raw or opts.texture_material) null else try opts.friendlyParams();
    const params = if (raw and !opts.texture_material) opts.params() else null;
    var threaded_io = riley.getThreadedIo(alloc, init.minimal, opts.threads);
    defer threaded_io.deinit();
    const io = threaded_io.io();
    const scene = try loadScene(alloc, io, opts);

    const texture = if (opts.texture_material) try imageio.loadImage(u8, 1, alloc, io, opts.texture, .bmp) else null;
    var resource_ns: i96 = 0;
    var render_ns: i96 = 0;
    var combined_ns: i96 = 0;
    var result: bench.Result = .{};
    var image_samples: usize = 0;
    var image_hash: ?[64]u8 = null;
    var resource_metrics: ResourceMetrics = .{};
    var prepared_identity: ?PreparedIdentity = null;
    if (opts.mode == .evaluation) {
        const config = opts.rasterConfig();
        const cam = try camera.CameraPrepared.init(alloc, cameraInput(scene.sim, opts));
        const geometry = try bench.Geometry.prepare(alloc, io, &cam, scene.sim.coords, scene.sim.connect, scene.uvs.array, config, opts.threads);
        var evaluation = try bench.Evaluation.init(alloc, io, &cam, &geometry, config, opts.threads);
        const resource_start = std.Io.Timestamp.now(io, .awake);
        var resources = if (texture == null) try speckle.Resources.init(init.gpa, params.?) else speckle.Resources{};
        defer resources.deinit(init.gpa);
        // Production UV gathering; interpolation LUTs are compile-time constants.
        const prepared: ?shaderops.TexPrepared(u8, 1) = if (texture) |tex| .{ .elem_uvs = try mo.prepUVs(alloc, &scene.uvs.array, &scene.sim.connect), .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null } else null;
        resource_ns = resource_start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
        const eval_start = std.Io.Timestamp.now(io, .awake);
        if (prepared) |shader| try evaluation.evaluateTexture(shader, opts.frames) else try evaluation.evaluate(params.?, &resources, opts.frames);
        render_ns = eval_start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
        // Inspect backing storage only after sampling, without warming one evaluator's counts.
        resource_metrics = resourceMetrics(&resources);
        combined_ns = resource_ns + render_ns;
        result = evaluation.result();
        prepared_identity = preparedIdentity(&resources); // After both timers and reduction.
    } else {
        const mesh = try scene.mesh(alloc, opts, friendly, texture);
        const cam_input = cameraInput(scene.sim, opts);
        var capture: timing.Capture = .{ .io = io };
        const output = blk: {
            timing.active = &capture;
            defer timing.active = null;
            const start = std.Io.Timestamp.now(io, .awake);
            const output = (try riley.rasterAdvanced(alloc, io, &.{cam_input}, &.{mesh}, opts.rasterConfig(), null, .{ .render_groups = .{ .supplied = &.{.{ .io = io, .workers = opts.threads }} } })).?;
            combined_ns = start.durationTo(std.Io.Timestamp.now(io, .awake)).nanoseconds;
            break :blk output;
        };
        resource_ns = capture.resource_ns;
        render_ns = combined_ns - resource_ns;
        image_samples = output.slice.len;
        image_hash = try hashRenderOutput(output.slice);
    }
    const resolved = if (params) |grid| try grid.resolve() else null;
    const generation_policy = if (friendly != null)
        evaluatorRecord(try policy.resolve(
            build.enable_all_evaluators,
            opts.pattern,
            null,
            null,
            if (opts.soft) .soft else .hard,
        ))
    else
        null;
    const record = .{
        .mode = @tagName(opts.mode),
        .workload_mode = switch (opts.mode) {
            inline else => |mode| @field(workload_modes, @tagName(mode)),
        },
        .evaluator = if (opts.texture_material) "texture" else if (resolved) |cfg|
            policy.evaluatorName(std.meta.activeTag(cfg))
        else
            "auto",
        .scene = if (opts.plate) "plate" else "sphere",
        .pattern = if (opts.pattern == .disk)
            (if (if (params != null) opts.softness > 0 else opts.soft) "soft" else "hard")
        else
            @tagName(opts.pattern),
        .threads = opts.threads,
        .frames = opts.frames,
        .width = opts.width,
        .height = opts.height,
        .physical_params = friendly,
        // Production owns resolution/resources; timing capture does not expose them.
        .resolved_grid = params,
        .resolved_generation = if (resolved) |cfg| evaluatorRecord(cfg) else @as(?EvaluatorRecord, null),
        .generation_policy = generation_policy,
        .texture = opts.texture,
        .texture_filter = @tagName(opts.texture_filter),
        .texture_mode = @tagName(opts.textureConfig().mode),
        .resource_bytes = resource_metrics.resource_bytes,
        .duplicated_disk_records = resource_metrics.duplicated_disk_records,
        .record_capacity = resource_metrics.record_capacity,
        .prepared_identity = prepared_identity,
        .resource_ns = resource_ns,
        .render_ns = render_ns,
        .combined_ns = combined_ns,
        .checksum = if (raw) @as(?u64, result.checksum) else null,
        .image_hash = if (image_hash) |*hex| @as(?[]const u8, hex) else null,
        .shaded_samples = result.shaded_samples,
        .backface_rejections = result.backface_rejections,
        .evaluation_counters_available = opts.mode == .evaluation,
        .image_samples = image_samples,
        .precision = @typeName(F),
        .simd = @tagName(build.config.simd),
        .build_identity = buildIdentity(),
    };
    std.debug.print("BENCH {s}\n", .{try std.json.Stringify.valueAlloc(alloc, record, .{})});
}

fn hashRenderOutput(values: []const F) ![64]u8 {
    for (values) |value| {
        if (!std.math.isFinite(value)) return error.NonFiniteRenderOutput;
    }
    const Blake3 = std.crypto.hash.Blake3;
    var digest: [Blake3.digest_length]u8 = undefined;
    Blake3.hash(std.mem.sliceAsBytes(values), &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

fn cameraInput(sim: meshio.SimData, opts: Options) camera.CameraInput {
    const pixel_size: [2]F = .{ 5.3e-6, 5.3e-6 };
    const rotation = @import("riley/zig/rotation.zig").Rotation.init(0, 0, 0);
    return .{ .pixels_num = opts.pixels(), .pixels_size = pixel_size, .pos_world = cameraops.posFillFrameFromRot(&sim.coords, opts.pixels(), pixel_size, 0.05, rotation, 1.15), .rot_world = rotation, .roi_cent_world = sceneops.boundsCenter(&sim.coords), .focal_length = 0.05, .sub_sample = 1, .subpixel_center_map = .per_tile };
}

test "speckle benchmark catalogue follows the current build policy" {
    const catalogue = evaluatorCatalogue();
    try std.testing.expectEqual(build.enable_all_evaluators, catalogue.overrides_enabled);
    var reached: [catalogue.sampling_configs.len]bool = @splat(false);
    for (policy.generationConfigs(build.enable_all_evaluators), catalogue.configs, 0..) |config, row, i| {
        try std.testing.expectEqualStrings(policy.evaluatorName(std.meta.activeTag(config)), row.evaluator);
        const canonical = evaluatorRecord(policy.canonicalizeSampleConfig(config));
        try std.testing.expectEqualDeep(canonical, catalogue.sampling_configs[row.sampling_index]);
        reached[row.sampling_index] = true;
        for (catalogue.configs[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, row.evaluator, other.evaluator) or
                !std.mem.eql(u8, row.pattern orelse "", other.pattern orelse "") or
                row.neighbors != other.neighbors or row.soft_edges != other.soft_edges);
        }
    }
    for (reached) |sampled| try std.testing.expect(sampled);
    if (comptime !build.enable_all_evaluators) {
        const expected = [_]EvaluatorRecord{
            .{ .evaluator = "classified-binned", .pattern = "disk", .neighbors = 9, .soft_edges = false },
            .{ .evaluator = "cell-binned", .pattern = "disk", .neighbors = 9, .soft_edges = true },
            .{ .evaluator = "cell-binned", .pattern = "gaussian", .neighbors = 9, .soft_edges = null },
            .{ .evaluator = "gradient-lattice", .pattern = "perlin", .neighbors = null, .soft_edges = null },
        };
        try std.testing.expectEqualDeep(expected, catalogue.sampling_configs);
    }
}

test "speckle benchmark default options prepare production evaluator identities" {
    for ([_][]const u8{ "hard", "soft", "gaussian", "perlin" }, [_][]const u8{ "classified-binned", "cell-binned", "cell-binned", "gradient-lattice" }) |pattern, evaluator| {
        var opts = try Options.parse(&.{ "bench", "--pattern", pattern });
        opts.cells_u = 4;
        opts.cells_v = 3;
        try std.testing.expectEqual(null, opts.evaluator);
        try std.testing.expectEqual(null, opts.neighbors);
        var resources = try speckle.Resources.init(std.testing.allocator, opts.params());
        defer resources.deinit(std.testing.allocator);
        const identity = preparedIdentity(&resources);
        try std.testing.expectEqualStrings(evaluator, identity.generation_evaluator.?);
        try std.testing.expectEqualStrings(evaluator, identity.sampling_evaluator.?);
        try std.testing.expectEqualStrings(if (std.mem.eql(u8, pattern, "hard")) "classified_binned" else if (std.mem.eql(u8, pattern, "perlin")) "perlin" else "cell_binned", identity.backing);
    }
}

test "speckle benchmark CPU feature identity covers exactly the resolved target" {
    const identity = buildIdentity();
    const all = builtin.cpu.arch.allFeaturesList();
    var enabled: usize = 0;
    for (all, 0..) |feature, index| {
        var occurrences: usize = 0;
        for (identity.cpu_features) |name| {
            if (std.mem.eql(u8, name, feature.name)) occurrences += 1;
        }
        const expected: usize = if (builtin.cpu.features.isEnabled(@intCast(index))) 1 else 0;
        try std.testing.expectEqual(expected, occurrences);
        enabled += expected;
    }
    try std.testing.expectEqual(enabled, identity.cpu_features.len);
}

test "speckle benchmark resource metrics distinguish live records from capacity" {
    const uncollected = resourceMetrics(&.{});
    try std.testing.expectEqualDeep(ResourceMetrics{}, uncollected);
    const coordinates: [36]F = @splat(0);
    const resources: speckle.Resources = .{ .data = .{ .classified_binned = .{
        .params = .{},
        .dims = .{ 16, 4 },
        .cell_dims = .{ 2, 1 },
        .coordinates = &coordinates,
        .slots = 18,
        .headers = &.{ 0, 0 },
        .counts = &.{ 1, 3 },
        .offsets = &.{},
    } } };
    const metrics = resourceMetrics(&resources);
    try std.testing.expectEqual(@as(?usize, 4), metrics.duplicated_disk_records);
    try std.testing.expectEqual(@as(?usize, 18), metrics.record_capacity);
    try std.testing.expectEqual(@as(?usize, 16 + 36 * @sizeOf(F) + 2), metrics.resource_bytes);
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
    try std.testing.expectError(error.InvalidSpeckleRadiusRange, Options.parse(&.{ "bench", "--radius", "0.05" }));
    try std.testing.expectError(error.InvalidSpeckleNeighborhoodRadius, Options.parse(&.{ "bench", "--radius", "1.1" }));
    const args = &.{ "bench", "--evaluator", "cell-hash", "--pattern", "soft", "--height", "32" };
    if (comptime build.enable_all_evaluators) {
        const opts = try Options.parse(args);
        try std.testing.expectEqual(@as(F, 0.04), opts.softness);
        try std.testing.expectEqual(policy.Evaluator.cell_hash, opts.evaluator.?);
    } else try std.testing.expectError(error.SpeckleOverridesDisabled, Options.parse(args));
    inline for (.{ policy.Evaluator.classified_indexed, policy.Evaluator.classified_binned }) |evaluator| {
        const name = policy.evaluatorName(evaluator);
        const args_classified = &.{ "bench", "--evaluator", name, "--jitter", "0.08" };
        if (comptime build.enable_all_evaluators) {
            const opts = try Options.parse(args_classified);
            try std.testing.expectEqual(evaluator, opts.evaluator.?);
            try std.testing.expectEqual(@as(?F, 0.08), opts.jitter);
            var params = opts.params();
            params.cells_per_uv = .{ 3.17, 2.31 };
            var resources = try speckle.Resources.init(std.testing.allocator, params);
            defer resources.deinit(std.testing.allocator);
            const identity = preparedIdentity(&resources);
            try std.testing.expectEqualStrings(name, identity.generation_evaluator.?);
            try std.testing.expectEqualStrings(name, identity.sampling_evaluator.?);
            try std.testing.expectEqualStrings(if (evaluator == .classified_indexed) "classified" else "classified_binned", identity.backing);
            try std.testing.expectError(if (evaluator == .classified_indexed) error.ClassifiedIndexedRequiresDiskAndNineNeighbors else error.ClassifiedBinnedRequiresDiskAndNineNeighbors, Options.parse(&.{ "bench", "--evaluator", name, "--neighbors", "4" }));
        } else try std.testing.expectError(error.SpeckleOverridesDisabled, Options.parse(args_classified));
    }
}
const Scene = struct {
    sim: meshio.SimData,
    uvs: uvio.UVMap,

    fn mesh(self: Scene, alloc: std.mem.Allocator, opts: Options, params: ?physical.SpeckleParams, texture: ?texops.Tex(u8, 1)) !mo.MeshInput {
        const shader: shaderops.ShaderInput = if (texture) |tex|
            .{ .tex_u8 = .{ .uvs = self.uvs.array, .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null } }
        else
            .{ .speckle = .{ .uvs = self.uvs.array, .params = params.?, .bits = null } };
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
    var resources = try speckle.Resources.init(alloc, smoke.params());
    defer resources.deinit(alloc);
    try evaluation.evaluate(smoke.params(), &resources, 1);
    const front_only = evaluation.result();
    try std.testing.expect(front_only.shaded_samples > 0);
    tiles[0].overlap_count = 2;
    tiles[0].bins[one_root_bin].count = 2;
    try evaluation.evaluate(smoke.params(), &resources, 1);
    try std.testing.expectEqualDeep(front_only, evaluation.result()); // Near first rejects far.
    std.mem.swap(@TypeOf(overlaps[0]), &overlaps[0], &overlaps[1]);
    try evaluation.evaluate(smoke.params(), &resources, 1);
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
        const Variant = enum { hard, soft, gaussian, perlin, hash_hard, hash_soft, hash_gaussian, perlin_mask, nearest, linear, cubic_catmull_rom };
        for (std.enums.values(Variant)) |variant| {
            const experimental = variant == .perlin_mask or variant == .hash_hard or variant == .hash_soft or variant == .hash_gaussian;
            if (experimental and !build.enable_all_evaluators) continue;
            var params = opts.params();
            params.pattern = switch (variant) {
                .gaussian, .hash_gaussian => .gaussian,
                .perlin, .perlin_mask => .perlin,
                else => .disk,
            };
            params.edge_softness = if (variant == .soft or variant == .hash_soft) 0.1 else 0;
            if (experimental) params.evaluator = if (variant == .perlin_mask) .mask_u8 else .cell_hash;
            const texture_variant = variant == .nearest or variant == .linear or variant == .cubic_catmull_rom;
            opts.texture_filter = if (texture_variant) std.meta.stringToEnum(texops.TexSamp, @tagName(variant)).? else .linear;
            var resources = if (texture_variant) speckle.Resources{} else try speckle.Resources.init(alloc, params);
            defer resources.deinit(alloc);
            var once: bench.Result = undefined;
            for ([_]usize{ 1, 2 }) |frames| {
                if (texture_variant) {
                    const shader: shaderops.TexPrepared(u8, 1) = .{ .elem_uvs = fixture.geometry.uvs, .tex = tex, .samp_cfg = opts.textureConfig(), .bits = null };
                    try single.evaluateTexture(shader, frames);
                    try parallel.evaluateTexture(shader, frames);
                } else {
                    try single.evaluate(params, &resources, frames);
                    try parallel.evaluate(params, &resources, frames);
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

test "speckle benchmark textures accept labels but reject procedural controls in both modes" {
    const controls = [_][2][]const u8{
        .{ "--coverage", "0.5" },  .{ "--radius", "0.25" },         .{ "--jitter", "0" },
        .{ "--occupancy", "1" },   .{ "--softness", "0" },          .{ "--neighbors", "9" },
        .{ "--cell-size", "0.1" }, .{ "--perlin-transition", "0" }, .{ "--perlin-threshold", "0" },
        .{ "--seed", "42" },       .{ "--cells-u", "8" },           .{ "--cells-v", "4" },
    };
    for ([_][]const u8{ "evaluation", "full-render" }) |mode| {
        const opts = try Options.parse(&.{
            "bench", "--mode", mode, "--evaluator", "texture", "--pattern", "soft",
        });
        try std.testing.expect(opts.texture_material and opts.soft);
        try std.testing.expectEqual(@as(F, 0), opts.softness);
        for (controls) |control| {
            try std.testing.expectError(error.TextureControlsNotApplicable, Options.parse(&.{
                "bench", "--mode", mode, "--evaluator", "texture", control[0], control[1],
            }));
        }
    }
}

test "speckle benchmark full-render fingerprint rejects nonfinite samples" {
    try std.testing.expectError(error.NonFiniteRenderOutput, hashRenderOutput(&.{std.math.nan(F)}));
}

test "speckle benchmark full render uses direct physical inputs and memory output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tex = try imageio.loadImage(u8, 1, alloc, std.testing.io, "texture/speck128_mono_u8.bmp", .bmp);
    for ([_][]const u8{ "hard", "soft", "gaussian", "perlin", "texture" }) |pattern| {
        const perlin = std.mem.eql(u8, pattern, "perlin");
        const texture = std.mem.eql(u8, pattern, "texture");
        var opts = if (texture)
            try Options.parse(&.{ "bench", "--mode", "full-render", "--evaluator", "texture" })
        else if (perlin)
            try Options.parse(&.{ "bench", "--mode", "full-render", "--pattern", pattern, "--cell-size", "0.25", "--perlin-threshold", "0.1", "--perlin-transition", "0", "--seed", "42" })
        else
            try Options.parse(&.{ "bench", "--mode", "full-render", "--pattern", pattern, "--coverage", "0.4", "--radius", "0.3", "--jitter", "0.01", "--occupancy", "0.7", "--softness", if (std.mem.eql(u8, pattern, "soft")) "0.02" else "0", "--seed", "42" });
        opts.width = 32;
        opts.height = 24;
        opts.frames = 2;
        const scene = try loadScene(alloc, std.testing.io, opts);
        const params = if (texture) null else try opts.friendlyParams();
        const mesh = try scene.mesh(alloc, opts, params, if (texture) tex else null);
        if (!texture) {
            const body: physical.Speckle2DParams = .{ .coverage = 0.4, .radius = 0.3, .jitter = 0.01, .occupancy = 0.7, .edge_softness = if (std.mem.eql(u8, pattern, "soft")) 0.02 else 0, .seed = 42 };
            const expected: physical.SpeckleParams = if (perlin)
                .{ .perlin = .{ .cell_size = 0.25, .threshold = 0.1, .transition_width = 0, .seed = 42 } }
            else if (std.mem.eql(u8, pattern, "gaussian")) .{ .gaussian = body } else .{ .disk = body };
            try std.testing.expectEqualDeep(expected, mesh.shader.speckle.params);
        }
        var capture: timing.Capture = .{ .io = std.testing.io };
        timing.active = &capture;
        defer timing.active = null;
        const output = (try riley.rasterAdvanced(alloc, std.testing.io, &.{cameraInput(scene.sim, opts)}, &.{mesh}, opts.rasterConfig(), null, .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = 1 }} } })).?;
        try std.testing.expectEqual(@as(usize, 32 * 24 * 2), output.slice.len);
        try std.testing.expect(capture.resource_ns > 0);
        for (output.slice) |value| try std.testing.expect(std.math.isFinite(value));
    }
    for ([_][]const u8{ "cell-hash", "classified-binned" }) |evaluator| {
        try std.testing.expectError(error.FullRenderRequiresProductionDefaults, Options.parse(&.{ "bench", "--mode", "full-render", "--evaluator", evaluator }));
    }
    try std.testing.expectError(error.FullRenderRequiresProductionDefaults, Options.parse(&.{ "bench", "--mode", "full-render", "--neighbors", "9" }));
    const disk = try Options.parse(&.{ "bench", "--mode", "full-render" });
    try std.testing.expectError(error.MissingPhysicalSpeckleInputs, disk.friendlyParams());
    const perlin = try Options.parse(&.{ "bench", "--mode", "full-render", "--pattern", "perlin" });
    try std.testing.expectError(error.MissingPerlinCellSize, perlin.friendlyParams());
    try std.testing.expectError(error.GridControlsRequireEvaluation, Options.parse(&.{ "bench", "--mode", "full-render", "--cells-u", "8" }));
    try std.testing.expectError(error.InactivePatternControls, Options.parse(&.{ "bench", "--mode", "full-render", "--pattern", "perlin", "--radius", "1" }));
    try std.testing.expectError(error.InactivePatternControls, Options.parse(&.{ "bench", "--mode", "full-render", "--cell-size", "0.1" }));
    try std.testing.expectError(error.PhysicalControlsRequireFullRender, Options.parse(&.{ "bench", "--coverage", "0.5" }));
}
