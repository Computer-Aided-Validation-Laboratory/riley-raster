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
const expected_config = @import("expected_speckle_config.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipeline = @import("../riley/zig/meshpipeline.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const ndarray = @import("../riley/zig/ndarray.zig");

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
        .shader = .{ .func = .{
            .uvs = uvs,
            .coord_mode = .uv,
            .builtin = .speckle,
        } },
    };
    const automatic = [_]struct {
        pattern: Pattern,
        softness: F = 0.0,
        evaluator: Evaluator,
    }{
        .{ .pattern = .disk, .evaluator = .classified_indexed },
        .{ .pattern = .disk, .softness = 0.03, .evaluator = .list_indexed },
        .{ .pattern = .gaussian, .evaluator = .list_indexed },
        .{ .pattern = .perlin, .evaluator = .mask_u8 },
    };
    for (automatic) |case| {
        var params = fixture_params;
        params.pattern = case.pattern;
        params.edge_softness = case.softness;
        try expectPreparedResources(std.testing.allocator, &mesh_input, params, case.evaluator, 9);
    }

    if (comptime !buildconfig.enable_all_evaluators) return;
    for (speckleconfig.generationConfigs(true)) |config| {
        var params = fixture_params;
        params.pattern = config.pattern;
        params.edge_softness = if (config.soft_edges) 0.03 else 0.0;
        params.evaluator = config.evaluator;
        params.neighbor_count = if (config.pattern == .perlin) null else config.neighbor_count;
        try expectPreparedResources(
            std.testing.allocator,
            &mesh_input,
            params,
            config.evaluator,
            config.neighbor_count,
        );
    }
    var direct = fixture_params;
    direct.evaluator = .direct_fixed;
    try expectPreparedResources(std.testing.allocator, &mesh_input, direct, .direct_fixed, 1);
}

fn expectPreparedResources(
    outer_alloc: std.mem.Allocator,
    base_input: *const meshpipeline.MeshInput,
    params: Params,
    evaluator: Evaluator,
    neighbors: u8,
) !void {
    const expected: speckleconfig.Config = .{
        .pattern = params.pattern,
        .evaluator = evaluator,
        .neighbor_count = neighbors,
        .soft_edges = params.edge_softness > 0.0,
    };
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    var mesh_input = base_input.*;
    mesh_input.shader.func.params = .{ .settings = .{ .speckle = params } };
    const mesh_static = try meshpipeline.initMeshStatic(arena.allocator(), &mesh_input);
    const resources = switch (mesh_static.shader) {
        .func => |func| func.speckle_resources,
        else => return error.UnexpectedShaderVariant,
    };
    try std.testing.expect(resources.kernel_index != null);
    try std.testing.expectEqualDeep(
        speckleconfig.canonicalizeSampleConfig(expected),
        speckleops.kernel_configs[resources.kernel_index.?],
    );
    try std.testing.expectEqual(
        evaluator == .list_naive or evaluator == .list_indexed,
        resources.list != null,
    );
    try std.testing.expectEqual(evaluator == .classified_indexed, resources.classified != null);
    try std.testing.expectEqual(evaluator == .direct_fixed, resources.direct_fixed != null);
    try std.testing.expectEqual(
        evaluator == .mask_1bit or evaluator == .mask_u8,
        resources.mask != null,
    );
}
