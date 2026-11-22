// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");
const builtin = @import("builtin");

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
const uvio = @import("../riley/zig/uvio.zig");

const F = buildconfig.F;
const default_coverage = 0.5;

pub const DemoSpec = struct {
    command_name: []const u8,
    output_default: []const u8,
    pixels_num_default: [2]u32,
    length_default: F = 0.25,
    length_units: []const u8 = "reference-mesh units",
    dimensions: Dimensions = .exposed_and_reported,
    comparison: ?Comparison = null,

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
    params: riley.SpeckleParams,
    out_dir: []const u8,
    pixels_num: [2]u32,
};

pub const StaticTri6Scene = struct {
    coords_path: []const u8,
    connect_path: []const u8,
    uvs_path: []const u8,
    v_offset: F = 0,
    rotation: rotation.Rotation,
    fov_scale: F,
    title: []const u8,
    image_label: []const u8,
};

/// Run a single-frame tri6 demo using the process arena and a bounded render I/O pool.
pub fn runStaticTri6Demo(
    comptime spec: DemoSpec,
    init: std.process.Init,
    scene: StaticTri6Scene,
) !void {
    const local_alloc = init.arena.allocator();
    const raw_args = try init.minimal.args.toSlice(local_alloc);
    const args = (try parseDemoArgs(raw_args, spec)) orelse return;
    const workers: u16 = 4;
    const config = rastcfg.RasterConfig{
        .save_strategy = .disk,
        .parallel = .{ .threads = workers },
        .output = .{
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            },
        },
        .report = .{ .mode = .bench },
    };
    var threaded_io = riley.getThreadedIo(init.gpa, init.minimal, workers);
    defer threaded_io.deinit();
    const io = threaded_io.io();

    std.debug.print("{s}\n", .{scene.title});
    printProceduralConfig(args.params, args.pixels_num, spec);

    const sim_data = try meshio.loadSimData(
        local_alloc,
        io,
        scene.coords_path,
        scene.connect_path,
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(local_alloc, io, scene.uvs_path);
    if (scene.v_offset != 0) {
        for (0..uvs.array.dims[0]) |nn| uvs.getUV(nn)[1] += scene.v_offset;
    }
    const mesh_input = meshpipeline.MeshInput{
        .mesh_type = .tri6,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .speckle = .{
            .uvs = uvs.array,
            .params = args.params,
            .scaling = .auto,
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
    const render_groups = [_]riley.RenderGroup{
        .{ .io = io, .workers = workers },
    };
    _ = try riley.rasterAdvanced(
        init.gpa,
        io,
        &[_]camera.CameraInput{camera_input},
        &[_]meshpipeline.MeshInput{mesh_input},
        config,
        args.out_dir,
        .{ .render_groups = .{ .supplied = &render_groups } },
    );

    std.debug.print("{s} image saved under {s}/\n", .{ scene.image_label, args.out_dir });
}

/// Parse physical controls before callers load meshes or prepare resources.
pub fn parseDemoArgs(raw_args: []const []const u8, comptime spec: DemoSpec) !?DemoArgs {
    var option: []const u8 = "speckle parameters";
    errdefer if (!builtin.is_test) {
        std.debug.print("Invalid demo arguments at {s}\n", .{option});
        printUsage(spec);
    };
    var out_dir = spec.output_default;
    var pixels_num = spec.pixels_num_default;
    var pattern: std.meta.Tag(riley.SpeckleParams) = .disk;
    var physical: riley.Speckle2DParams = .{
        .coverage = default_coverage,
        .radius = spec.length_default,
    };
    var perlin: riley.Perlin2DParams = .{ .cell_size = spec.length_default };
    var physical_controls = false;
    var perlin_controls = false;
    var arg_idx: usize = 1;
    while (arg_idx < raw_args.len) : (arg_idx += 2) {
        const arg = raw_args[arg_idx];
        option = arg;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            if (!builtin.is_test) printUsage(spec);
            return null;
        }
        if (arg_idx + 1 >= raw_args.len) return error.MissingArgumentValue;
        const value = raw_args[arg_idx + 1];
        if (std.mem.eql(u8, arg, "--pattern")) {
            pattern = std.meta.stringToEnum(@TypeOf(pattern), value) orelse
                return error.InvalidSpecklePattern;
        } else if (std.mem.eql(u8, arg, "--coverage")) {
            physical_controls = true;
            physical.coverage = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--radius")) {
            physical_controls = true;
            physical.radius = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--occupancy")) {
            physical_controls = true;
            physical.occupancy = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--jitter")) {
            physical_controls = true;
            physical.jitter = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--softness")) {
            physical_controls = true;
            physical.edge_softness = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--cell-size")) {
            perlin_controls = true;
            perlin.cell_size = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--threshold")) {
            perlin_controls = true;
            perlin.threshold = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--transition")) {
            perlin_controls = true;
            perlin.transition_width = try std.fmt.parseFloat(F, value);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            physical.seed = try std.fmt.parseInt(u32, value, 0);
            perlin.seed = physical.seed;
        } else if (spec.dimensions == .exposed_and_reported and std.mem.eql(u8, arg, "--width")) {
            pixels_num[0] = try parsePositiveU32(value);
        } else if (spec.dimensions == .exposed_and_reported and std.mem.eql(u8, arg, "--height")) {
            pixels_num[1] = try parsePositiveU32(value);
        } else if (std.mem.eql(u8, arg, "--output")) {
            out_dir = value;
        } else return error.UnknownArgument;
    }
    option = if (pattern == .perlin)
        "--coverage/--radius/--occupancy/--jitter/--softness"
    else
        "--cell-size/--threshold/--transition";
    if ((pattern == .perlin and physical_controls) or (pattern != .perlin and perlin_controls))
        return error.PatternSpecificOption;
    const params: riley.SpeckleParams = switch (pattern) {
        .disk => .{ .disk = physical },
        .gaussian => .{ .gaussian = physical },
        .perlin => .{ .perlin = perlin },
    };
    params.validate() catch |err| {
        option = switch (err) {
            error.InvalidSpeckleCoverage, error.UnattainableSpeckleCoverage => "--coverage/--occupancy",
            error.InvalidSpeckleRadius => "--radius",
            error.InvalidSpeckleOccupancy => "--occupancy",
            error.InvalidSpeckleJitter => "--jitter (must be between 0 and radius/2)",
            error.InvalidSpeckleEdgeSoftness, error.SpeckleEdgeSoftnessRequiresDisk => "--softness",
            error.UnsupportedSpeckleSupport => "--coverage/--occupancy/--jitter/--softness",
            error.InvalidSpeckleCellSize => "--cell-size",
            error.InvalidSpecklePerlinThreshold => "--threshold",
            error.InvalidSpecklePerlinTransitionWidth => "--transition",
            else => "speckle parameters",
        };
        return err;
    };
    return .{ .params = params, .out_dir = out_dir, .pixels_num = pixels_num };
}

pub fn printProceduralConfig(
    params: riley.SpeckleParams,
    pixels_num: [2]u32,
    comptime spec: DemoSpec,
) void {
    if (spec.comparison) |comparison| {
        std.debug.print(
            "  texture baseline: zig build {s} -Dsimd=off\n" ++
                "  procedural: zig build {s} -Dsimd=off\n",
            .{ comparison.texture_command, comparison.procedural_command },
        );
    }
    if (spec.dimensions == .exposed_and_reported) {
        std.debug.print("  image dimensions: {d} x {d} pixels\n", .{ pixels_num[0], pixels_num[1] });
    }
    std.debug.print("  pattern: {s}; automatic production evaluator\n", .{@tagName(params)});
    switch (params) {
        .disk, .gaussian => |p| std.debug.print(
            "  nominal coverage: {d}; radius: {d}; jitter: {d}; softness: {d} ({s})\n" ++
                "  occupancy: {d}; seed: {d}\n",
            .{ p.coverage, p.radius, p.jitter, p.edge_softness, spec.length_units, p.occupancy, p.seed },
        ),
        .perlin => |p| std.debug.print(
            "  Perlin cell size: {d} ({s}); threshold: {d}; transition: {d}; seed: {d}\n",
            .{ p.cell_size, spec.length_units, p.threshold, p.transition_width, p.seed },
        ),
    }
}

fn parsePositiveU32(value: []const u8) !u32 {
    const parsed = try std.fmt.parseInt(u32, value, 10);
    if (parsed == 0) return error.InvalidPixelDimension;
    return parsed;
}

fn printUsage(comptime spec: DemoSpec) void {
    const physical: riley.Speckle2DParams = .{
        .coverage = default_coverage,
        .radius = spec.length_default,
    };
    const perlin: riley.Perlin2DParams = .{ .cell_size = spec.length_default };
    std.debug.print(
        "Usage: zig build {s} -- [options]\n" ++
            "  --pattern disk|gaussian|perlin (default disk)\n" ++
            "  --coverage <fraction>  Nominal disk/Gaussian union coverage (default {d})\n" ++
            "  --radius <length>      Physical radius, Gaussian 3-sigma support (default {d})\n" ++
            "  --jitter <length>      Radius half-range, 0 <= jitter <= radius/2 (default {d})\n" ++
            "  --softness <length>    Physical disk boundary half-width (default {d})\n" ++
            "  --occupancy <fraction> Active-cell probability (default {d})\n" ++
            "  --cell-size <length>   Perlin lattice spacing (default {d})\n" ++
            "  --threshold <value>    Perlin-only threshold (default {d})\n" ++
            "  --transition <value>   Perlin-only transition width (default {d})\n" ++
            "  --seed <uint32>        Default 0x{x}\n" ++
            "  --output <path>        Default {s}\n",
        .{
            spec.command_name, physical.coverage,      physical.radius,
            physical.jitter,   physical.edge_softness, physical.occupancy,
            perlin.cell_size,  perlin.threshold,       perlin.transition_width,
            physical.seed,     spec.output_default,
        },
    );
    if (spec.dimensions == .exposed_and_reported) std.debug.print(
        "  --width <n> --height <n> (default {d} x {d})\n",
        .{ spec.pixels_num_default[0], spec.pixels_num_default[1] },
    );
    std.debug.print(
        "  --help, -h             Show help\n" ++
            "Lengths use {s}.\n" ++
            "Jitter/softness do not change nominal density. Unsupported support is rejected.\n",
        .{spec.length_units},
    );
}

const test_spec: DemoSpec = .{ .command_name = "demo", .output_default = "out", .pixels_num_default = .{ 32, 32 } };

test "demo physical arguments and defaults" {
    const defaults = (try parseDemoArgs(&[_][]const u8{"demo"}, test_spec)).?;

    try std.testing.expectEqual(@as(F, 0.5), defaults.params.disk.coverage);
    try std.testing.expectEqual(@as(F, 0.25), defaults.params.disk.radius);
    try std.testing.expectEqual(@as(F, 1), defaults.params.disk.occupancy);
    try std.testing.expectEqual(@as(F, 0), defaults.params.disk.jitter);
    const args = (try parseDemoArgs(&[_][]const u8{ "demo", "--pattern", "gaussian", "--coverage", "0.4", "--radius", "0.2", "--jitter", "0.01", "--width", "13" }, test_spec)).?;
    try std.testing.expectEqual(@as(F, 0.4), args.params.gaussian.coverage);
    try std.testing.expectEqual(@as(F, 0.2), args.params.gaussian.radius);
    try std.testing.expectEqual(@as(F, 0.01), args.params.gaussian.jitter);
    try std.testing.expectEqual(@as(u32, 13), args.pixels_num[0]);
}

test "demo Perlin options are separate and order independent" {
    const args = (try parseDemoArgs(&.{
        "demo", "--cell-size", "0.125", "--pattern", "perlin", "--threshold", "0.1",
    }, test_spec)).?;
    try std.testing.expectEqual(@as(F, 0.125), args.params.perlin.cell_size);
    try std.testing.expectEqual(@as(F, 0.1), args.params.perlin.threshold);
    try std.testing.expectError(error.InvalidSpeckleCellSize, parseDemoArgs(&.{
        "demo", "--pattern", "perlin", "--cell-size", "0",
    }, test_spec));
}

test "demo rejects incompatible controls and malformed arguments" {
    try std.testing.expectError(error.PatternSpecificOption, parseDemoArgs(&.{
        "demo", "--cell-size", "0.125",
    }, test_spec));
    try std.testing.expectError(error.PatternSpecificOption, parseDemoArgs(&[_][]const u8{ "demo", "--pattern", "perlin", "--radius", "0.2" }, test_spec));
    try std.testing.expectError(error.InvalidSpeckleRadius, parseDemoArgs(&[_][]const u8{ "demo", "--radius", "nan" }, test_spec));
    try std.testing.expectError(error.InvalidSpeckleOccupancy, parseDemoArgs(&[_][]const u8{ "demo", "--occupancy", "0" }, test_spec));
    try std.testing.expectError(error.InvalidPixelDimension, parseDemoArgs(&[_][]const u8{ "demo", "--width", "0" }, test_spec));
    try std.testing.expectError(error.MissingArgumentValue, parseDemoArgs(&[_][]const u8{ "demo", "--pattern" }, test_spec));
    try std.testing.expectError(error.InvalidSpecklePattern, parseDemoArgs(&[_][]const u8{ "demo", "--pattern", "unknown" }, test_spec));
    try std.testing.expectError(error.InvalidCharacter, parseDemoArgs(&[_][]const u8{ "demo", "--radius", "not-a-number" }, test_spec));
    try std.testing.expectError(error.Overflow, parseDemoArgs(&[_][]const u8{ "demo", "--seed", "4294967296" }, test_spec));
    for ([_][]const u8{ "0", "1" }) |coverage| {
        try std.testing.expectError(error.InvalidSpeckleCoverage, parseDemoArgs(&[_][]const u8{ "demo", "--coverage", coverage }, test_spec));
    }
    try std.testing.expectError(error.UnsupportedSpeckleSupport, parseDemoArgs(&[_][]const u8{ "demo", "--softness", "1" }, test_spec));
}

test "demo mesh length defaults and seed apply across patterns" {
    const mesh_spec = DemoSpec{
        .command_name = "mesh-demo",
        .output_default = "out",
        .pixels_num_default = .{ 512, 512 },
        .length_default = 0.005,
    };
    const defaults = (try parseDemoArgs(&[_][]const u8{"mesh-demo"}, mesh_spec)).?;
    try std.testing.expectEqual(@as(F, 0.005), defaults.params.disk.radius);
    const gaussian = (try parseDemoArgs(&[_][]const u8{ "mesh-demo", "--seed", "42", "--pattern", "gaussian" }, mesh_spec)).?;
    try std.testing.expectEqual(@as(F, 0.005), gaussian.params.gaussian.radius);
    try std.testing.expectEqual(@as(u32, 42), gaussian.params.gaussian.seed);
    const perlin = (try parseDemoArgs(&[_][]const u8{ "mesh-demo", "--seed", "42", "--pattern", "perlin" }, mesh_spec)).?;
    try std.testing.expectEqual(@as(u32, 42), perlin.params.perlin.seed);
    try std.testing.expectEqual(@as(F, 0.005), perlin.params.perlin.cell_size);
}

test "demo jitter half-radius boundary decodes and rejects larger values upstream" {
    for ([_][]const u8{ "disk", "gaussian" }) |pattern| {
        const args = (try parseDemoArgs(&[_][]const u8{
            "demo", "--pattern", pattern, "--radius", "0.25", "--jitter", "0.125",
        }, test_spec)).?;
        const p = switch (args.params) {
            .disk, .gaussian => |p| p,
            .perlin => unreachable,
        };
        try std.testing.expectEqual(p.radius / 2, p.jitter);

        try std.testing.expectError(error.InvalidSpeckleJitter, parseDemoArgs(&[_][]const u8{
            "demo", "--pattern", pattern, "--radius", "0.25", "--jitter", "0.126",
        }, test_spec));
    }
}

test "demo parser returns no run arguments for help flags" {
    try std.testing.expectEqual(@as(?DemoArgs, null), try parseDemoArgs(&[_][]const u8{ "demo", "--help" }, test_spec));
    try std.testing.expectEqual(@as(?DemoArgs, null), try parseDemoArgs(&[_][]const u8{ "demo", "-h" }, test_spec));
}
