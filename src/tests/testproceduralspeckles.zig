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
const speckleops = @import("../riley/zig/speckleops.zig");
const uvio = @import("../riley/zig/uvio.zig");

test "selected speckle evaluator prepares its production resources" {
    try std.testing.expectEqualStrings(
        expected_config.evaluator,
        buildconfig.speckle_evaluator_name,
    );
    try std.testing.expectEqualStrings(
        expected_config.shape,
        @tagName(buildconfig.speckle_shape),
    );

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const io = std.testing.io;

    const data_dir = "data/min/tri3_sphere200/";
    const sim_data = try meshio.loadSimData(
        allocator,
        io,
        data_dir ++ "coords.csv",
        data_dir ++ "connect.csv",
        null,
        null,
    );
    const uvs = try uvio.loadUVMap(allocator, io, data_dir ++ "uvs.csv");
    const evaluator = buildconfig.speckle_evaluator;
    const params = speckleops.Speckle2DParams{
        .seed = 12345,
        .cells_per_uv = .{ 24.0, 20.0 },
        .occupancy = 0.8,
        .radius_mean = 0.42,
        .radius_jitter = switch (comptime evaluator) {
            .classified_indexed, .direct_fixed => 0.0,
            else => 0.06,
        },
        .edge_softness = if (buildconfig.speckle_shape == .disk) switch (evaluator) {
            .cell_hash, .list_naive, .list_indexed, .mask_u8 => 0.03,
            else => 0.0,
        } else 0.0,
    };
    const mesh_input = meshpipeline.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .func = .{
            .uvs = uvs.array,
            .coord_mode = .uv,
            .builtin = .speckle,
            .params = .{ .settings = .{ .speckle = params } },
            .bits = 8,
            .scaling = .auto,
            .normal_type = .none,
        } },
    };
    const mesh_static = try meshpipeline.initMeshStatic(allocator, &mesh_input);
    const func_static = switch (mesh_static.shader) {
        .func => |func| func,
        else => return error.UnexpectedShaderVariant,
    };

    try std.testing.expectEqual(
        evaluator == .list_naive or evaluator == .list_indexed,
        func_static.speckle_resources.list != null,
    );
    try std.testing.expectEqual(
        evaluator == .classified_indexed,
        func_static.speckle_resources.classified != null,
    );
    try std.testing.expectEqual(
        evaluator == .direct_fixed,
        func_static.speckle_resources.direct_fixed != null,
    );
    try std.testing.expectEqual(
        evaluator == .mask_1bit or evaluator == .mask_u8,
        func_static.speckle_resources.mask != null,
    );
}
