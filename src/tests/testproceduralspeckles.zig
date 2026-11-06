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
const expected_config = @import("expected_speckle_config.zig");
const imageio = @import("../riley/zig/imageio.zig");
const matslice = @import("../riley/zig/matslice.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipeline = @import("../riley/zig/meshpipeline.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const textureops = @import("../riley/zig/textureops.zig");

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
        .{ .pattern = .disk, .evaluator = .classified_indexed },
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

fn expectPreparedResources(
    outer_alloc: std.mem.Allocator,
    base_input: *const meshpipeline.MeshInput,
    params: Params,
    evaluator: Evaluator,
    neighbors: ?speckleconfig.Neighborhood,
) !void {
    const expected = try speckleconfig.resolve(
        true,
        params.pattern,
        evaluator,
        neighbors,
        if (params.edge_softness > 0.0) .soft else .hard,
    );
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
        .direct_fixed => .direct_fixed,
        .mask_1bit, .mask_u8 => .mask,
        .cell_hash, .mock => .none,
    };
    try std.testing.expectEqual(expected_backing, std.meta.activeTag(resources.data));
}
