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
const expected_config = @import("expected_speckle_config.zig");
const imageio = @import("../riley/zig/imageio.zig");
const matslice = @import("../riley/zig/matslice.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipeline = @import("../riley/zig/meshpipeline.zig");
const riley = @import("../riley/zig/riley.zig");
const rotation = @import("../riley/zig/rotation.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const textureops = @import("../riley/zig/textureops.zig");
const vecstack = @import("../riley/zig/vecstack.zig");

const F = buildconfig.F;
const Params = speckleops.Speckle2DParams;
const Pattern = speckleconfig.Pattern;
const Evaluator = speckleconfig.Evaluator;
const fixture_params: Params = .{
    .seed = 12345,
    .cells_per_uv = .{ 4.0, 3.0 },
    .occupancy = 0.8,
    .radius_mean = 0.3,
};

test "speckle BMP matches an independently calculated mock gradient" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params: Params = .{ .evaluator = .mock };
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
            var params: Params = .{
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
        .shader = .{ .speckle = .{ .uvs = uvs } },
    };
    const automatic = [_]struct {
        pattern: Pattern,
        softness: F = 0.0,
        evaluator: Evaluator,
    }{
        .{ .pattern = .disk, .evaluator = .classified_binned },
        .{ .pattern = .disk, .softness = 0.03, .evaluator = .cell_binned },
        .{ .pattern = .gaussian, .evaluator = .cell_binned },
        .{ .pattern = .perlin, .evaluator = .gradient_lattice },
    };
    for (automatic) |case| {
        var params = fixture_params;
        params.pattern = case.pattern;
        params.edge_softness = case.softness;
        try expectPreparedResources(std.testing.allocator, &mesh_input, params, case.evaluator, if (case.pattern == .perlin) null else .nine);
    }

    if (comptime !buildconfig.enable_all_evaluators) return;
    for (speckleconfig.generationConfigs(true)) |config| {
        var params = fixture_params;
        params.pattern = config.pattern() orelse .disk;
        params.edge_softness = if (config.edges() == .soft) 0.03 else 0.0;
        params.evaluator = std.meta.activeTag(config);
        params.neighbor_count = config.neighborhood();
        try expectPreparedResources(
            std.testing.allocator,
            &mesh_input,
            params,
            std.meta.activeTag(config),
            config.neighborhood(),
        );
    }
    var direct = fixture_params;
    direct.evaluator = .direct_fixed;
    try expectPreparedResources(std.testing.allocator, &mesh_input, direct, .direct_fixed, .one);
}

test "production default speckle renders cover fields deformation buffers and worker counts without overrides" {
    // This is integration/determinism coverage, not an independent field oracle. The
    // independent default field oracles live in speckleops; cross-evaluator E2E stays gated.
    try expectAnalyticRenders(false);
}

test "analytic speckle renders agree across evaluators buffers and serial or parallel execution" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    try expectAnalyticRenders(true);
}

fn expectAnalyticRenders(comptime compare_evaluators: bool) !void {
    const Case = struct {
        pattern: Pattern,
        jitter: F,
        curved: bool,
        radius: F = fixture_params.radius_mean,
        occupancy: F = fixture_params.occupancy,
        softness: F = 0,
        perlin_transition: F = 0.12,
        neighbors: ?speckleconfig.Neighborhood = null,
    };
    const cases: []const Case = if (compare_evaluators) &.{
        .{ .pattern = .disk, .jitter = 0, .curved = false, .softness = 0.06 },
        .{ .pattern = .disk, .jitter = 0.25, .curved = true, .softness = 0.06 },
        .{ .pattern = .disk, .jitter = 0, .curved = true },
        .{ .pattern = .disk, .jitter = 0.25, .curved = false },
        .{ .pattern = .disk, .jitter = 0, .curved = false, .radius = 0.425, .occupancy = 1 },
        .{ .pattern = .disk, .jitter = 0, .curved = true, .radius = 0.425, .occupancy = 1 },
        .{ .pattern = .gaussian, .jitter = 0, .curved = true },
        .{ .pattern = .gaussian, .jitter = 0.25, .curved = false },
        .{ .pattern = .perlin, .jitter = 0, .curved = false, .perlin_transition = 0 },
        .{ .pattern = .perlin, .jitter = 0, .curved = true },
        // One-neighbor support (radius + jitter + softness) must stay <= 0.5.
        // Four-neighbor centers use a different generation domain; compare each
        // against a naive list generated with the same stencil, not the nine default.
        .{ .pattern = .disk, .neighbors = .one, .jitter = 0.1, .curved = false },
        .{ .pattern = .disk, .neighbors = .one, .jitter = 0.1, .curved = true },
        .{ .pattern = .disk, .neighbors = .four, .jitter = 0.25, .radius = 0.425, .curved = false },
        .{ .pattern = .disk, .neighbors = .four, .jitter = 0.25, .radius = 0.425, .curved = true },
        .{ .pattern = .disk, .neighbors = .one, .jitter = 0.1, .softness = 0.06, .curved = false },
        .{ .pattern = .disk, .neighbors = .one, .jitter = 0.1, .softness = 0.06, .curved = true },
        .{ .pattern = .disk, .neighbors = .four, .jitter = 0.25, .softness = 0.06, .curved = false },
        .{ .pattern = .disk, .neighbors = .four, .jitter = 0.25, .softness = 0.06, .curved = true },
        .{ .pattern = .gaussian, .neighbors = .one, .jitter = 0.1, .curved = false },
        .{ .pattern = .gaussian, .neighbors = .one, .jitter = 0.1, .curved = true },
        .{ .pattern = .gaussian, .neighbors = .four, .jitter = 0.25, .radius = 0.425, .curved = false },
        .{ .pattern = .gaussian, .neighbors = .four, .jitter = 0.25, .radius = 0.425, .curved = true },
    } else &.{
        .{ .pattern = .disk, .jitter = 0, .curved = true, .radius = 0.425, .occupancy = 1 },
        .{ .pattern = .disk, .jitter = 0.25, .curved = false, .softness = 0.06 },
        .{ .pattern = .gaussian, .jitter = 0.25, .curved = true },
        .{ .pattern = .perlin, .jitter = 0, .curved = false },
    };
    const camera_input: camera.CameraInput = .{
        .pixels_num = .{ 32, 24 },
        .pixels_size = .{ 0.05, 0.05 },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 2,
        .sub_sample = 2,
    };
    var connect = [_]usize{ 0, 1, 2, 3, 4, 5 };
    var uv_values = [_]F{ 0, 0, 1, 0, 0, 1, 0.5, 0, 0.5, 0.5, 0, 0.5 };
    const uvs = try ndarray.NDArray(F).init(std.testing.allocator, &uv_values, &.{ 6, 2 });
    defer uvs.deinit(std.testing.allocator);
    var disp = try meshio.Field.initAlloc(std.testing.allocator, 2, 6, 3);
    defer disp.deinit(std.testing.allocator);

    for (cases, 0..) |case, case_idx| {
        var coords = [_]F{
            -0.65, -0.45, 0, 0.65, -0.45, 0, -0.65, 0.45, 0,
            0,     -0.45, 0, 0,    0,     0, -0.65, 0,    0,
        };
        for (0..6) |nn| {
            // The second frame shears/translates the patch; curved cases also bend in depth.
            disp.array.set(&.{ 1, nn, 0 }, 0.08 + 0.1 * coords[3 * nn + 1]);
            disp.array.set(&.{ 1, nn, 1 }, 0.03 * coords[3 * nn]);
            disp.array.set(&.{ 1, nn, 2 }, if (case.curved and nn >= 3) 0.08 else 0);
        }
        if (case.curved) {
            coords[3 * 3 + 2] = 0.12;
            coords[3 * 4 + 2] = 0.2;
            coords[3 * 5 + 2] = 0.1;
        }
        var params = fixture_params;
        params.pattern = case.pattern;
        params.edge_softness = case.softness;
        params.perlin_coverage_transition_width = case.perlin_transition;
        params.radius_jitter = case.jitter;
        params.radius_mean = case.radius;
        params.occupancy = case.occupancy;
        params.neighbor_count = case.neighbors;
        try params.validate();
        var mesh: meshpipeline.MeshInput = .{
            .mesh_type = .tri6,
            .coords = meshio.Coords.init(&coords, 6),
            .connect = meshio.Connect.init(&connect, 1, 6),
            .disp = disp,
            .shader = .{ .speckle = .{
                .uvs = uvs,
                .params = params,
                .bits = null,
                .scaling = .none,
            } },
        };
        for ([_]riley.BufferMode{ .tile_local, .global_subpx_full, .global_subpx_stripe }) |buffer_mode| {
            const config: riley.RasterConfig = .{
                .save_strategy = .memory,
                .report = .{ .mode = .off },
                .background_value = -1,
                .advanced = .{ .raster = .{
                    .buffer_mode = buffer_mode,
                    .tile_size_override = 8,
                    .global_subpx_tile_size_min = 8,
                    .global_subpx_tile_size_override = 8,
                    .global_subpx_stripe_size_min = 8,
                    .global_subpx_stripe_size_override = 8,
                } },
            };
            errdefer std.debug.print("render equality case {d}: {s}, radius={d}, occupancy={d}, jitter={d}, neighbors={any}, curved={}, buffer={s}\n", .{
                case_idx, @tagName(case.pattern), case.radius, case.occupancy, case.jitter, case.neighbors, case.curved, @tagName(buffer_mode),
            });
            // Only experimental builds compare against production reference evaluators.
            // Default smoke tests compare the 1-worker omitted-override baseline with 4 workers.
            mesh.shader.speckle.params.evaluator = if (comptime compare_evaluators)
                if (case.pattern == .perlin) .cell_hash else .list_naive
            else
                null;
            var expected = (try riley.rasterAdvanced(
                std.testing.allocator,
                std.testing.io,
                &.{camera_input},
                &.{mesh},
                config,
                null,
                .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = 1 }} } },
            )) orelse return error.NoResult;
            defer {
                std.testing.allocator.free(expected.slice);
                expected.deinit(std.testing.allocator);
            }
            try std.testing.expectEqualSlices(usize, &.{ 1, 2, 1, 24, 32 }, expected.dims);
            const frame_pixels = 24 * 32;
            for (0..2) |ff| {
                const frame = expected.slice[ff * frame_pixels ..][0..frame_pixels];
                var covered: usize = 0;
                var dark: usize = 0;
                var light: usize = 0;
                for (frame) |value| {
                    try std.testing.expect(std.math.isFinite(value));
                    if (value >= 0) {
                        covered += 1;
                        if (value < 0.4) dark += 1;
                        if (value > 0.6) light += 1;
                    }
                }
                try std.testing.expect(covered > 40 and covered < frame_pixels);
                try std.testing.expect(dark > 5 and light > 5);
            }
            var changed: usize = 0;
            for (expected.slice[0..frame_pixels], expected.slice[frame_pixels..]) |a, b| {
                if (a != b) changed += 1;
            }
            try std.testing.expect(changed > 20);

            // A null evaluator exercises automatic resolution; reduced stencils still
            // require their experimental neighborhood override. Only smoke cases omit both.
            // The gated reference shares generation, not the accelerated sampling structures.
            // Masks approximate the field and deliberately do not participate in exact equality.
            const evaluators: []const ?Evaluator = if (!compare_evaluators)
                &.{null}
            else if (case.neighbors != null)
                &.{ null, .list_indexed }
            else if (case.pattern == .perlin)
                &.{ null, .gradient_lattice, .cell_hash }
            else if (case.pattern == .disk and case.softness == 0)
                &.{ null, .classified_binned, .classified_indexed, .cell_binned, .list_indexed, .list_naive, .cell_hash }
            else
                &.{ null, .cell_binned, .list_indexed, .list_naive, .cell_hash };
            const worker_counts: []const u16 = if (compare_evaluators) &.{ 1, 4 } else &.{4};
            for (evaluators) |evaluator| {
                for (worker_counts) |workers| {
                    mesh.shader.speckle.params.evaluator = evaluator;
                    var actual = (try riley.rasterAdvanced(
                        std.testing.allocator,
                        std.testing.io,
                        &.{camera_input},
                        &.{mesh},
                        config,
                        null,
                        .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = workers }} } },
                    )) orelse return error.NoResult;
                    defer {
                        std.testing.allocator.free(actual.slice);
                        actual.deinit(std.testing.allocator);
                    }
                    try std.testing.expectEqualSlices(usize, expected.dims, actual.dims);
                    for (expected.slice, actual.slice, 0..) |reference, value, ii| {
                        // Numeric equality intentionally accepts opposite signs of zero.
                        if (reference != value) {
                            std.debug.print("{s}, {d} workers: frame {d}, pixel {d}: expected {d}, found {d}\n", .{
                                if (evaluator) |selected| @tagName(selected) else "default", workers, ii / frame_pixels, ii % frame_pixels, reference, value,
                            });
                            return error.TestExpectedEqual;
                        }
                    }
                }
            }
        }
    }
}

fn expectPreparedResources(
    outer_alloc: std.mem.Allocator,
    base_input: *const meshpipeline.MeshInput,
    params: Params,
    evaluator: Evaluator,
    neighbors: ?speckleconfig.Neighborhood,
) !void {
    const expected = try params.resolve();
    try std.testing.expectEqual(evaluator, std.meta.activeTag(expected));
    try std.testing.expectEqual(neighbors, expected.neighborhood());
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    var mesh_input = base_input.*;
    mesh_input.shader.speckle.params = params;
    const mesh_static = try meshpipeline.initMeshStatic(arena.allocator(), &mesh_input);
    const resources = switch (mesh_static.shader) {
        .speckle => |*shader| &shader.resources,
        else => return error.UnexpectedShaderVariant,
    };
    try std.testing.expect(resources.kernel_index != null);
    try std.testing.expectEqualDeep(
        speckleconfig.canonicalizeSampleConfig(expected),
        speckleops.kernel_configs[resources.kernel_index.?],
    );
    const expected_backing: std.meta.Tag(speckleops.Backing) = switch (evaluator) {
        .gradient_lattice => .perlin,
        .list_naive => .list,
        .list_indexed => .strip_list,
        .cell_binned => .cell_binned,
        .classified_indexed => .classified,
        .classified_binned => .classified_binned,
        .direct_fixed => .direct_fixed,
        .mask_1bit, .mask_u8 => .mask,
        .cell_hash, .mock => .none,
    };
    try std.testing.expectEqual(expected_backing, std.meta.activeTag(resources.data));
}
