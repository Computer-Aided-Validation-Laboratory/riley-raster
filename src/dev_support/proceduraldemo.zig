// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/camera.zig");
const cameraops = @import("../riley/zig/cameraops.zig");
const iio = @import("../riley/zig/imageio.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipeline = @import("../riley/zig/meshpipeline.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const riley = @import("../riley/zig/riley.zig");
const rotation = @import("../riley/zig/rotation.zig");
const sceneops = @import("../riley/zig/sceneops.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const uvio = @import("../riley/zig/uvio.zig");

const F = buildconfig.F;

pub const DemoSpec = struct {
    command_name: []const u8,
    output_default: []const u8,
    pixels_num_default: [2]u32,
    dimensions: Dimensions = .exposed_and_reported,
    comparison: ?Comparison = null,
    mask_report_label: []const u8,

    pub const Dimensions = enum {
        hidden,
        exposed_and_reported,
    };

    pub const Comparison = struct {
        texture_command: []const u8,
        procedural_command: []const u8,
    };
};

pub const DemoArgs = struct {
    params: speckleops.Speckle2DParams = .{},
    out_dir: []const u8,
    pixels_num: [2]u32,
};

pub const StaticTri6Scene = struct {
    coords_path: []const u8,
    connect_path: []const u8,
    uvs_path: []const u8,
    rotation: rotation.Rotation,
    fov_scale: F,
    title: []const u8,
    image_label: []const u8,
};

/// Run a single-frame tri6 demo, owning its temporary arena and render I/O pool.
pub fn runStaticTri6Demo(
    comptime spec: DemoSpec,
    outer_alloc: std.mem.Allocator,
    minimal: std.process.Init.Minimal,
    scene: StaticTri6Scene,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    const args = (try parseDemoArgs(minimal.args.vector, spec)) orelse return;
    const config = rastcfg.RasterConfig{
        .save_strategy = .disk,
        .total_threads = 4,
        .max_raster_workers_per_job = 4,
        .image_save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto },
        },
        .report = .bench,
    };
    var threaded_io = riley.getThreadedIo(local_alloc, minimal, config.total_threads);
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.debug.print("{s}\n", .{scene.title});
    try printProceduralConfig(args.params, args.pixels_num, spec);

    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        scene.coords_path,
        scene.connect_path,
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(local_alloc, io, scene.uvs_path);
    const mesh_input = meshpipeline.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .func = .{
            .uvs = uvs.array,
            .coord_mode = .uv,
            .builtin = .speckle,
            .params = .{ .settings = .{ .speckle = args.params } },
            .bits = 8,
            .scaling = .auto,
            .normal_type = .none,
        } },
    };

    const pixel_size: [2]F = .{ 5.3e-6, 5.3e-6 };
    const focal_length: F = 50.0e-3;
    const camera_input = camera.CameraInput{
        .pixels_num = args.pixels_num,
        .pixels_size = pixel_size,
        .pos_world = cameraops.posFillFrameFromRot(
            &sim_data.coords,
            args.pixels_num,
            pixel_size,
            focal_length,
            scene.rotation,
            scene.fov_scale,
        ),
        .rot_world = scene.rotation,
        .roi_cent_world = sceneops.boundsCenter(&sim_data.coords),
        .focal_length = focal_length,
        .sub_sample = 2,
    };
    const render_groups = [_]riley.RenderGroupSpec{
        .{ .io = io, .workers = config.total_threads },
    };
    const images = try riley.raster(
        local_alloc,
        &render_groups,
        &[_]camera.CameraInput{camera_input},
        &[_]meshpipeline.MeshInput{mesh_input},
        config,
        args.out_dir,
    );
    if (images) |img_const| {
        var img = img_const;
        local_alloc.free(img.slice);
        img.deinit(local_alloc);
    }

    std.debug.print("{s} image saved under {s}/\n", .{ scene.image_label, args.out_dir });
}

/// Parse and validate runtime settings before callers load meshes or prepare resources.
pub fn parseDemoArgs(raw_args: anytype, comptime spec: DemoSpec) !?DemoArgs {
    var args = DemoArgs{
        .out_dir = spec.output_default,
        .pixels_num = spec.pixels_num_default,
    };
    var arg_idx: usize = 1;
    while (arg_idx < raw_args.len) {
        const arg = std.mem.span(raw_args[arg_idx]);
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage(spec);
            return null;
        }
        if (arg_idx + 1 >= raw_args.len) {
            std.debug.print("Missing value for {s}\n\n", .{arg});
            printUsage(spec);
            return error.MissingArgumentValue;
        }

        const value = std.mem.span(raw_args[arg_idx + 1]);
        if (std.mem.eql(u8, arg, "--pattern")) {
            args.params.pattern = speckleconfig.parsePattern(value) orelse
                return error.InvalidSpecklePattern;
        } else if (std.mem.eql(u8, arg, "--evaluator")) {
            args.params.evaluator = speckleconfig.parseEvaluator(value) orelse
                return error.InvalidSpeckleEvaluator;
        } else if (std.mem.eql(u8, arg, "--neighbors")) {
            args.params.neighbor_count = try std.fmt.parseInt(u8, value, 10);
        } else if (std.mem.eql(u8, arg, "--size")) {
            args.params.radius_mean = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--occupancy")) {
            args.params.occupancy = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--cells-u")) {
            args.params.cells_per_uv[0] = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--cells-v")) {
            args.params.cells_per_uv[1] = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--jitter")) {
            args.params.radius_jitter = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--softness")) {
            args.params.edge_softness = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--threshold")) {
            args.params.perlin_coverage_threshold = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--transition")) {
            args.params.perlin_coverage_transition_width = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            args.params.seed = try std.fmt.parseInt(u32, value, 0);
        } else if (spec.dimensions == .exposed_and_reported and std.mem.eql(u8, arg, "--width")) {
            args.pixels_num[0] = try parsePositiveU32(value);
        } else if (spec.dimensions == .exposed_and_reported and std.mem.eql(u8, arg, "--height")) {
            args.pixels_num[1] = try parsePositiveU32(value);
        } else if (std.mem.eql(u8, arg, "--output")) {
            args.out_dir = value;
        } else {
            std.debug.print("Unknown option: {s}\n\n", .{arg});
            printUsage(spec);
            return error.UnknownArgument;
        }
        arg_idx += 2;
    }
    try args.params.validate();
    return args;
}

pub fn printProceduralConfig(
    params: speckleops.Speckle2DParams,
    pixels_num: [2]u32,
    comptime spec: DemoSpec,
) !void {
    const resolved = try params.resolve();
    if (spec.comparison) |comparison| {
        std.debug.print(
            "  texture baseline: zig build {s} -Dsimd=off\n",
            .{comparison.texture_command},
        );
    }
    if (spec.dimensions == .exposed_and_reported) {
        std.debug.print(
            "  image dimensions: {d} x {d} pixels\n",
            .{ pixels_num[0], pixels_num[1] },
        );
    }

    const perlin_note = if (resolved.pattern == .perlin)
        " (not used by Perlin)"
    else
        "";

    std.debug.print(
        "  evaluator (resolved): {s}\n",
        .{speckleconfig.evaluatorName(resolved.evaluator)},
    );
    std.debug.print("  pattern (runtime): {s}\n", .{@tagName(resolved.pattern)});
    std.debug.print(
        "  neighbor count (resolved): {d}{s}\n",
        .{ resolved.neighbor_count, perlin_note },
    );
    std.debug.print(
        "  boundary half-width: {d} cell units\n",
        .{params.edge_softness},
    );
    std.debug.print("  seed: {d} (0x{x})\n", .{ params.seed, params.seed });
    std.debug.print(
        "  cells per UV: {d} x {d}\n",
        .{ params.cells_per_uv[0], params.cells_per_uv[1] },
    );

    switch (resolved.pattern) {
        .perlin => {
            std.debug.print(
                "  coverage threshold: {d}\n",
                .{params.perlin_coverage_threshold},
            );
            std.debug.print(
                "  coverage transition width: {d}\n",
                .{params.perlin_coverage_transition_width},
            );
        },
        .disk, .gaussian => {
            if (resolved.evaluator == .direct_fixed) {
                std.debug.print("  fixed radius: {d} cell units\n", .{params.radius_mean});
                std.debug.print("  radius jitter: zero (required by direct-fixed)\n", .{});
            } else {
                std.debug.print("  nominal radius: {d} cell units\n", .{params.radius_mean});
                std.debug.print("  radius jitter: {d} cell units\n", .{params.radius_jitter});
            }
            std.debug.print("  occupancy: {d}\n", .{params.occupancy});
        },
    }

    if (resolved.evaluator == .classified_indexed) {
        const samples: F = @floatFromInt(buildconfig.speckle_mask_samples_per_cell);
        const classification_dims = [2]F{
            @ceil(params.cells_per_uv[0] * samples),
            @ceil(params.cells_per_uv[1] * samples),
        };
        std.debug.print("  classifier: precomputed static 2-bit classification\n", .{});
        std.debug.print(
            "  classification resolution: {d} x {d} microcells ({d} samples/cell)\n",
            .{
                classification_dims[0],
                classification_dims[1],
                buildconfig.speckle_mask_samples_per_cell,
            },
        );
    }

    if (resolved.evaluator == .mask_1bit or resolved.evaluator == .mask_u8) {
        const samples: F = @floatFromInt(buildconfig.speckle_mask_samples_per_cell);
        const mask_dims = [2]F{
            @ceil(params.cells_per_uv[0] * samples) + 1.0,
            @ceil(params.cells_per_uv[1] * samples) + 1.0,
        };
        const storage = if (resolved.evaluator == .mask_1bit)
            "packed 1-bit coverage"
        else
            "8-bit coverage";
        std.debug.print("  {s}: {s}\n", .{ spec.mask_report_label, storage });
        std.debug.print(
            "  mask resolution: {d} x {d} texels ({d} samples/cell)\n",
            .{ mask_dims[0], mask_dims[1], buildconfig.speckle_mask_samples_per_cell },
        );
    }
}

fn parsePositiveU32(value: []const u8) !u32 {
    const parsed = try std.fmt.parseInt(u32, value, 10);
    if (parsed == 0) return error.InvalidPixelDimension;
    return parsed;
}

fn printUsage(comptime spec: DemoSpec) void {
    std.debug.print(
        "Usage:\n  zig build {s} -Dsimd=off -- [options]\n\n",
        .{spec.command_name},
    );
    if (spec.comparison) |comparison| {
        std.debug.print(
            "Direct comparison:\n  Texture:    zig build {s} -Dsimd=off\n  Procedural: zig build {s} -Dsimd=off\n\n",
            .{ comparison.texture_command, comparison.procedural_command },
        );
    }
    std.debug.print(
        \\Options:
        \\  --pattern <name>      disk, gaussian, or perlin (default: disk)
        \\  --size <value>        Mean radius in cell units (Gaussian: 3-sigma support)
        \\  --occupancy <value>   Active-cell probability (disk/Gaussian)
        \\  --cells-u <value>     Procedural cell count across U
        \\  --cells-v <value>     Procedural cell count across V
        \\  --jitter <value>      Radius half-range in cell units (disk/Gaussian)
        \\  --softness <value>    Boundary half-width in cell units (disk only; default: 0)
        \\  --threshold <value>   Coverage threshold (Perlin only)
        \\  --transition <value>  Coverage transition width (Perlin only)
        \\  --seed <integer>      Deterministic unsigned 32-bit seed
        \\
    , .{});
    if (spec.dimensions == .exposed_and_reported) {
        std.debug.print(
            "  --width <integer>     Image width in pixels (default: {d})\n" ++
                "  --height <integer>    Image height in pixels (default: {d})\n",
            .{ spec.pixels_num_default[0], spec.pixels_num_default[1] },
        );
    }
    std.debug.print(
        \\  --output <path>       Output directory
        \\  --help                Show this help
        \\
        \\Experimental native overrides (require -Denable-all-evaluators=true):
        \\  --evaluator <name>    cell-hash, list-naive, list-indexed, classified-indexed,
        \\                        direct-fixed, mask-1bit, or mask-u8
        \\  --neighbors <count>   1, 4, or 9 (not allowed for Perlin)
        \\  Omit both overrides for automatic selection; default builds reject either.
        \\  An omitted neighbor count is 9, or 1 for an explicit direct-fixed evaluator.
        \\
        \\Value constraints:
        \\  Cell counts must be positive and finite; seed is an unsigned 32-bit integer.
        \\  Disk/Gaussian: size > 0, 0 <= jitter <= size, 0 <= occupancy <= 1 (all finite).
        \\  Size + jitter + softness <= 0.5 for one neighbor, or <= 1 otherwise.
        \\  Hard disks exclude their circumference; zero-radius draws are empty.
        \\  Softness must be finite and nonnegative; positive values enable soft disks.
        \\  Gaussian/Perlin and classified-indexed/direct-fixed/mask-1bit require softness 0.
        \\  classified-indexed requires disk/9 neighbors; direct-fixed requires disk/1,
        \\  zero jitter and hard edges; mask-1bit requires hard disks.
        \\  Perlin requires mask-u8; threshold is finite and transition is finite and >= 0.
        \\  Transition 0 selects a hard threshold. Perlin ignores size, jitter and occupancy.
        \\
    , .{});
}

const test_spec: DemoSpec = .{
    .command_name = "demo-procedural-speckles",
    .output_default = "out",
    .pixels_num_default = .{ 32, 32 },
    .mask_report_label = "mask",
};

test "demo arguments select runtime patterns without experimental overrides" {
    const names = [_][*:0]const u8{ "disk", "gaussian", "perlin" };
    for (names) |name| {
        const raw = [_][*:0]const u8{ "demo", "--pattern", name, "--cells-u", "3.25" };
        const parsed = (try parseDemoArgs(&raw, test_spec)).?;
        try std.testing.expectEqual(
            speckleconfig.parsePattern(std.mem.span(name)).?,
            parsed.params.pattern,
        );
        try std.testing.expectEqual(@as(F, 3.25), parsed.params.cells_per_uv[0]);
        try std.testing.expect(parsed.params.evaluator == null);
        try std.testing.expect(parsed.params.neighbor_count == null);
    }
}

test "demo arguments reject malformed and invalid runtime settings" {
    const cases = [_]struct { args: []const [*:0]const u8, err: anyerror }{
        .{ .args = &.{ "demo", "--pattern", "unknown" }, .err = error.InvalidSpecklePattern },
        .{ .args = &.{ "demo", "--evaluator", "unknown" }, .err = error.InvalidSpeckleEvaluator },
        .{ .args = &.{ "demo", "--cells-v", "nan" }, .err = error.InvalidSpeckleCellsPerUV },
        .{ .args = &.{ "demo", "--width", "0" }, .err = error.InvalidPixelDimension },
        .{ .args = &.{ "demo", "--unknown", "value" }, .err = error.UnknownArgument },
        .{ .args = &.{ "demo", "--pattern" }, .err = error.MissingArgumentValue },
    };
    for (cases) |case| {
        try std.testing.expectError(case.err, parseDemoArgs(case.args, test_spec));
    }
}

test "demo experimental overrides preserve explicit values and enforce availability" {
    const evaluator = [_][*:0]const u8{ "demo", "--evaluator", "classified-indexed" };
    const neighbors = [_][*:0]const u8{ "demo", "--neighbors", "9" };
    if (comptime buildconfig.enable_all_evaluators) {
        const selected = (try parseDemoArgs(&evaluator, test_spec)).?;
        try std.testing.expectEqual(
            speckleconfig.Evaluator.classified_indexed,
            selected.params.evaluator.?,
        );
        const counted = (try parseDemoArgs(&neighbors, test_spec)).?;
        try std.testing.expectEqual(@as(u8, 9), counted.params.neighbor_count.?);
        const perlin = [_][*:0]const u8{ "demo", "--pattern", "perlin", "--neighbors", "9" };
        try std.testing.expectError(
            error.SpecklePerlinDoesNotUseNeighbors,
            parseDemoArgs(&perlin, test_spec),
        );
    } else {
        try std.testing.expectError(
            error.SpeckleOverridesDisabled,
            parseDemoArgs(&evaluator, test_spec),
        );
        try std.testing.expectError(
            error.SpeckleOverridesDisabled,
            parseDemoArgs(&neighbors, test_spec),
        );
    }
}
