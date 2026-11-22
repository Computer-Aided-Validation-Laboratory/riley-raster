// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/camera.zig");
const specklefixture = @import("../riley/zig/specklefixture.zig");
const expected_config = @import("expected_speckle_config.zig");
const imageio = @import("../riley/zig/imageio.zig");
const matslice = @import("../riley/zig/matslice.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipeline = @import("../riley/zig/meshpipeline.zig");
const riley = @import("../riley/zig/riley.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const textureops = @import("../riley/zig/textureops.zig");
const rotation = @import("../riley/zig/rotation.zig");
const vecstack = @import("../riley/zig/vecstack.zig");

const F = buildconfig.F;
const GridParams = speckleops.GridParams;
const Params = riley.SpeckleParams;
const Pattern = speckleconfig.Pattern;

const fixture_params = specklefixture.physical_params;

test "speckle BMP matches an independently calculated mock gradient" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params: GridParams = .{ .evaluator = .mock };
    var resources = try speckleops.Resources.init(std.testing.allocator, params);
    defer resources.deinit(std.testing.allocator);
    const rows = 7;
    const cols = 13;
    var pixels: [rows * cols]F = undefined;
    const image = matslice.MatSlice(F).init(&pixels, rows, cols);
    speckleops.fillImage(image, params, &resources);
    try imageio.saveMatAsImage(std.testing.io, tmp.dir, "mock", &image, .{
        .format = .bmp,
        .bits = 8,
        .scaling = .{ .fixed = .{ 0, 1 } },
    });

    const stride = (cols * 3 + 3) & ~@as(usize, 3);
    const file_size = 54 + rows * stride;
    var buffer: [file_size + 1]u8 = undefined;
    const bmp = try tmp.dir.readFile(std.testing.io, "mock.bmp", &buffer);
    try std.testing.expectEqual(file_size, bmp.len);
    try std.testing.expectEqualStrings("BM", bmp[0..2]);
    try std.testing.expectEqual(file_size, std.mem.readInt(u32, bmp[2..6], .little));
    try std.testing.expectEqual(54, std.mem.readInt(u32, bmp[10..14], .little));
    try std.testing.expectEqual(cols, std.mem.readInt(i32, bmp[18..22], .little));
    try std.testing.expectEqual(rows, std.mem.readInt(i32, bmp[22..26], .little));
    try std.testing.expectEqual(24, std.mem.readInt(u16, bmp[28..30], .little));
    for (0..rows) |rr| {
        // Positive BMP heights store the bottom row first.
        const row = bmp[54 + (rows - 1 - rr) * stride ..][0..stride];
        for (0..cols) |cc| {
            const u = (@as(f64, @floatFromInt(cc)) + 0.5) / cols;
            const v = (@as(f64, @floatFromInt(rr)) + 0.5) / rows;
            const expected: u8 = @intFromFloat(@round(255.0 * 0.5 * (u + v)));
            try std.testing.expectEqualSlices(u8, &.{ expected, expected, expected }, row[cc * 3 ..][0..3]);
        }
        for (row[cols * 3 ..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "constant low-level speckles match a uniform texture across evaluator configurations" {
    const cases = [_]struct { occupancy: F = 0.9, foreground: F, background: F }{
        .{ .foreground = 0, .background = 0 },
        .{ .foreground = 0.375, .background = 0.375 },
        .{ .foreground = 1, .background = 1 },
        .{ .occupancy = 0, .foreground = 1, .background = 0 },
        .{ .occupancy = 0, .foreground = 0, .background = 0.375 },
        .{ .occupancy = 0, .foreground = 0, .background = 1 },
    };
    var texture = try textureops.Tex(F, 1).init(std.testing.allocator, 2, 3);
    defer texture.deinit(std.testing.allocator);
    for (speckleconfig.generationConfigs(buildconfig.enable_all_evaluators)) |config| {
        const evaluator = std.meta.activeTag(config);
        if (evaluator == .mock) continue; // Mock ignores colors and returns a UV gradient.
        for (cases) |case| {
            if (case.occupancy == 0 and config.pattern() == .perlin) continue;
            @memset(texture.array.slice, case.background);
            var params: GridParams = .{
                .pattern = config.pattern() orelse .disk,
                .cells_per_uv = .{ 3.25, 2.5 },
                .occupancy = case.occupancy,
                .edge_softness = if (config.edges() == .soft) 0.035 else 0,
                .foreground = case.foreground,
                .background = case.background,
            };
            if (buildconfig.enable_all_evaluators) {
                params.evaluator = evaluator;
                params.neighbor_count = config.neighborhood();
            }
            var resources = try speckleops.Resources.init(std.testing.allocator, params);
            defer resources.deinit(std.testing.allocator);
            for ([_]F{ -0.25, 0, 0.37, 1, 1.25 }) |u| {
                const v = 1 - u;
                const texel = textureops.sampScal(1, .{ .sample = .nearest }, &texture, u, v)[0];
                try std.testing.expectEqual(case.background, texel);
                try std.testing.expectEqual(texel, speckleops.sampleScal(u, v, params, &resources));
                const values: [buildconfig.SimdWidth]F = speckleops.sampleSIMD(@splat(u), @splat(v), @splat(true), params, &resources);
                for (values) |value| try std.testing.expectEqual(texel, value);
            }
        }
    }
}

test "runtime speckle patterns prepare their production resources" {
    try std.testing.expectEqual(
        expected_config.enable_all_evaluators,
        buildconfig.enable_all_evaluators,
    );
    try std.testing.expectEqual(
        expected_config.speckle_mask_samples_per_cell,
        buildconfig.speckle_mask_samples_per_cell,
    );
    var coords = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    var connect = [_]usize{ 0, 1, 2 };
    var uv_values = [_]F{ 0, 0, 1, 0, 0, 1 };
    const uvs = try ndarray.NDArray(F).init(std.testing.allocator, &uv_values, &.{ 3, 2 });
    defer uvs.deinit(std.testing.allocator);
    const mesh_input = meshpipeline.MeshInput{
        .mesh_type = .tri3,
        .coords = meshio.Coords.init(&coords, 3),
        .connect = meshio.Connect.init(&connect, 1, 3),
        .disp = null,
        .shader = .{ .speckle = .{ .uvs = uvs, .params = .{ .disk = fixture_params } } },
    };
    const automatic = [_]struct {
        pattern: Pattern,
        softness: F = 0.0,
        config: speckleconfig.Config,
    }{
        .{ .pattern = .disk, .config = .classified_binned },
        .{ .pattern = .disk, .softness = 0.03, .config = .{ .cell_binned = .{ .disk = .{ .neighborhood = .nine, .edges = .soft } } } },
        .{ .pattern = .gaussian, .config = .{ .cell_binned = .{ .gaussian = .nine } } },
        .{ .pattern = .perlin, .config = .gradient_lattice },
    };
    for (automatic) |case| {
        var physical = fixture_params;
        physical.edge_softness = case.softness;
        const params: Params = switch (case.pattern) {
            .disk => .{ .disk = physical },
            .gaussian => .{ .gaussian = physical },
            .perlin => .{ .perlin = .{ .cell_size = 0.25, .seed = fixture_params.seed } },
        };
        try expectPreparedResources(std.testing.allocator, &mesh_input, params, case.config);
    }
}

test "physical default speckles lower friendly inputs and render deformed fields" {
    // riley.zig owns buffer/worker comparisons and experimental independent references.
    // Here the public entry point lowers hard/soft disks, Gaussian and Perlin inputs.
    const Case = struct {
        pattern: Pattern,
        jitter: F = 0,
        curved: bool = false,
        coverage: F = fixture_params.coverage,
        occupancy: F = fixture_params.occupancy,
        softness: F = 0,
    };
    const cases = [_]Case{
        .{ .pattern = .disk, .coverage = 0.5, .occupancy = 1 },
        .{ .pattern = .disk, .curved = true, .coverage = 0.5, .occupancy = 1 },
        .{ .pattern = .disk, .jitter = 0.02, .softness = 0.015 },
        .{ .pattern = .gaussian, .curved = true, .jitter = 0.02 },
        .{ .pattern = .perlin, .curved = true },
    };

    for (cases, 0..) |case, case_idx| {
        var physical = fixture_params;
        physical.coverage = case.coverage;
        physical.occupancy = case.occupancy;
        physical.jitter = case.jitter;
        physical.edge_softness = case.softness;
        const params: Params = switch (case.pattern) {
            .disk => .{ .disk = physical },
            .gaussian => .{ .gaussian = physical },
            .perlin => .{ .perlin = .{
                .cell_size = 0.3,
                .seed = fixture_params.seed,
            } },
        };
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const scene = try specklefixture.initScene(&arena, params, case.curved, 1);

        errdefer std.debug.print("physical render case {d}: {s}, curved={}\n", .{
            case_idx, @tagName(case.pattern), case.curved,
        });
        const alloc = arena.allocator();
        const expected = try renderSpeckleMesh(alloc, scene.camera_input, scene.mesh_input);
        try specklefixture.expectDeformedImages(expected);

        // A unit change must preserve the soft, jittered disk and the physical Perlin period.
        if (case.softness > 0 or case.pattern == .perlin) {
            const scaled = try specklefixture.initScene(&arena, params, case.curved, 8);
            const actual = try renderSpeckleMesh(alloc, scaled.camera_input, scaled.mesh_input);
            try specklefixture.expectImagesWithin(expected, actual, 0);
        }
    }
}

test "public physical disk render recovers nominal coverage and reference scale" {
    const cols = 768;
    const rows = 512;
    const pixel_size = 1.0 / 128.0;
    const radius: F = 1.0 / 64.0;
    // Front-facing 6 by 4 view inside a larger orthogonal plate: no silhouette or UV
    // boundary pixels contribute. At z = 0, focal length equals camera distance.
    const cam_input: camera.CameraInput = .{
        .pixels_num = .{ cols, rows },
        .pixels_size = .{ pixel_size, pixel_size },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 2,
        .sub_sample = 1,
    };
    var coords = [_]F{ -3.25, -2.25, 0, 3.25, -2.25, 0, 3.25, 2.25, 0, -3.25, 2.25, 0 };
    var connect = [_]usize{ 0, 1, 2, 3 };
    var uv_values = [_]F{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const alloc = std.testing.allocator;
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_values, &.{ 4, 2 });
    defer uvs.deinit(alloc);

    const cases = [_]struct { occupancy: F, coverage: F, jitter: F = 0, expected: f64, tol: f64 }{
        .{ .occupancy = 0.3, .coverage = 0.1, .expected = 0.1, .tol = 0.005 },
        // Independent numerical coverage for uniform J = R/2 at nominal C = 0.5.
        // Allow more finite-area sampling variation for this denser field.
        .{ .occupancy = 1, .coverage = 0.5, .jitter = radius / 2, .expected = 0.5254, .tol = 0.01 },
    };
    for (cases) |case| {
        errdefer std.debug.print("disk coverage {d}, occupancy {d}, jitter {d}\n", .{
            case.coverage, case.occupancy, case.jitter,
        });
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const image = try renderSpeckleMesh(arena.allocator(), cam_input, .{
            .mesh_type = .quad4,
            .coords = meshio.Coords.init(&coords, 4),
            .connect = meshio.Connect.init(&connect, 1, 4),
            .disp = null,
            .shader = .{ .speckle = .{ .uvs = uvs, .params = .{ .disk = .{
                .seed = fixture_params.seed,
                .radius = radius,
                .occupancy = case.occupancy,
                .coverage = case.coverage,
                .jitter = case.jitter,
            } }, .bits = null } },
        });
        try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1, rows, cols }, image.dims);
        var covered: usize = 0;
        var row_transitions: usize = 0;
        var col_transitions: usize = 0;
        for (image.slice, 0..) |value, index| {
            if (value == 0) covered += 1 else try std.testing.expectEqual(@as(F, 1), value);
            if (index % cols != 0 and value != image.slice[index - 1]) row_transitions += 1;
            if (index >= cols and value != image.slice[index - cols]) col_transitions += 1;
        }
        const fraction = @as(f64, @floatFromInt(covered)) / (rows * cols);
        // Resolution, centre quantization, and correlated finite-area sampling all matter.
        try std.testing.expectApproxEqAbs(case.expected, fraction, case.tol);
        if (case.coverage < 0.2) {
            // Isolated circles have 4/(pi*R) crossings per scanline length per unit
            // coverage. Overlap and pixel sampling reduce that ratio in this scene.
            const isolated = 4 * fraction / (std.math.pi * @as(f64, radius));
            for ([_]usize{ row_transitions, col_transitions }, [_]f64{ rows * (cols - 1), cols * (rows - 1) }) |transitions, pixel_intervals| {
                const crossings_per_length = @as(f64, @floatFromInt(transitions)) /
                    (pixel_intervals * pixel_size);
                try std.testing.expectApproxEqAbs(@as(f64, 0.95), crossings_per_length / isolated, 0.057);
            }
        }
    }
}

fn renderSpeckleMesh(
    outer_alloc: std.mem.Allocator,
    camera_input: camera.CameraInput,
    mesh_input: meshpipeline.MeshInput,
) !ndarray.NDArray(F) {
    return (try riley.rasterAdvanced(
        outer_alloc,
        std.testing.io,
        &.{camera_input},
        &.{mesh_input},
        specklefixture.rasterConfig(.tile_local),
        null,
        .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = 1 }} } },
    )) orelse error.NoResult;
}

fn expectPreparedResources(
    outer_alloc: std.mem.Allocator,
    base_input: *const meshpipeline.MeshInput,
    params: Params,
    expected: speckleconfig.Config,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    var mesh_input = base_input.*;
    mesh_input.shader.speckle.params = params;
    const mesh_static = try meshpipeline.initMeshStatic(arena.allocator(), &mesh_input);
    const resources = switch (mesh_static.shader) {
        .speckle => |*shader| &shader.resources,
        else => return error.UnexpectedShaderVariant,
    };
    const actual = try mesh_static.shader.speckle.params.resolve();
    try std.testing.expectEqualDeep(expected, actual);
    try std.testing.expectEqual(expected.neighborhood(), actual.neighborhood());
    try std.testing.expect(resources.kernel_index != null);
    try std.testing.expectEqualDeep(
        speckleconfig.canonicalizeSampleConfig(expected),
        speckleops.kernel_configs[resources.kernel_index.?],
    );
    const expected_backing: std.meta.Tag(speckleops.Backing) = switch (expected) {
        .gradient_lattice => .perlin,
        .cell_binned => .cell_binned,
        .classified_binned => .classified_binned,
        else => unreachable,
    };
    try std.testing.expectEqual(expected_backing, std.meta.activeTag(resources.data));
}
