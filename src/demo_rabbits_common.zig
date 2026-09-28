// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const orch = @import("dev_support/orchestration.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const shaderops = @import("riley/zig/shaderops_common.zig");
const texops = @import("riley/zig/textureops.zig");
const uvio = @import("riley/zig/uvio.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");

const MeshInput = meshpipe.MeshInput;
const FuncShaderBuiltin = shaderops.FuncShaderBuiltin;
const FuncShaderParams = shaderops.FuncShaderParams;
const F = buildconfig.F;

pub const SceneOptions = struct {
    mesh_types: []const gk.MeshType,
    overlap_frac_xy: [2]F,
    checker_squares_per_axis: F,
    gap: [3]F,
    max_divs: [3]usize,
};

/// Build arena-owned mesh inputs sharing the caller's texture. Keep the arena and
/// texture alive until rendering finishes; release scene storage with that arena.
pub fn buildRabbitPairScene(
    comptime C: usize,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    texture: texops.Tex(u8, C),
    options: SceneOptions,
) ![]MeshInput {
    // -------------------------------------------------------------------------
    // 1. Build and overlap rabbit mesh pairs
    // -------------------------------------------------------------------------
    var mesh_list = std.ArrayList(MeshInput).empty;
    defer mesh_list.deinit(outer_alloc);
    var group_list = std.ArrayList(sceneops.MeshGroup).empty;
    defer group_list.deinit(outer_alloc);

    for (options.mesh_types) |mesh_type| {
        const pair_start = mesh_list.items.len;
        const front_mode = shaderModeForMeshIndex(pair_start);
        const back_mode = shaderModeForMeshIndex(pair_start + 1);
        try mesh_list.append(outer_alloc, try makeMeshInput(
            C,
            outer_alloc,
            io,
            "riley",
            mesh_type,
            front_mode,
            texture,
            options.checker_squares_per_axis,
        ));
        try mesh_list.append(outer_alloc, try makeMeshInput(
            C,
            outer_alloc,
            io,
            "feebs",
            mesh_type,
            back_mode,
            texture,
            options.checker_squares_per_axis,
        ));

        const front_group = sceneops.meshGroupSingle(pair_start);
        const back_group = sceneops.meshGroupSingle(pair_start + 1);
        sceneops.overlapMeshGroupBounds(
            mesh_list.items,
            front_group,
            back_group,
            .{
                .overlap_frac = .{
                    options.overlap_frac_xy[0],
                    options.overlap_frac_xy[1],
                    0.0,
                },
                .enabled_axes = .{ true, true, false },
                .direction = .{ .positive, .negative, .current },
            },
        );

        try group_list.append(outer_alloc, sceneops.meshGroupSpan(pair_start, 2));
    }

    // -------------------------------------------------------------------------
    // 2. Arrange rabbit groups in grid layout
    // -------------------------------------------------------------------------
    sceneops.arrangeMeshGroupsGrid(
        mesh_list.items,
        group_list.items,
        .{
            .gap = options.gap,
            .max_divs = options.max_divs,
        },
    );
    return try mesh_list.toOwnedSlice(outer_alloc);
}

const ShaderMode = enum {
    tex,
    nodal,
    func,
};

fn shaderModeForMeshIndex(mesh_idx: usize) ShaderMode {
    return switch (@mod(mesh_idx, 3)) {
        0 => .tex,
        1 => .nodal,
        else => .func,
    };
}

fn buildRabbitDir(
    outer_alloc: std.mem.Allocator,
    rabbit_name: []const u8,
    mesh_type: gk.MeshType,
) ![]const u8 {
    return try std.fmt.allocPrint(
        outer_alloc,
        "data/rabbits/{s}_{s}",
        .{ rabbit_name, orch.meshDataName(mesh_type) },
    );
}

fn loadStaticMesh(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
) !meshio.SimData {
    const coords_path = try std.fmt.allocPrint(
        outer_alloc,
        "{s}/coords.csv",
        .{data_dir},
    );
    defer outer_alloc.free(coords_path);
    const connect_path = try std.fmt.allocPrint(
        outer_alloc,
        "{s}/connectivity.csv",
        .{data_dir},
    );
    defer outer_alloc.free(connect_path);
    return try meshio.loadSimData(
        outer_alloc,
        io,
        coords_path,
        connect_path,
        null,
        null,
    );
}

fn loadRabbitUvMap(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    data_dir: []const u8,
) !uvio.UVMap {
    const uv_path = try std.fmt.allocPrint(
        outer_alloc,
        "{s}/uvs.csv",
        .{data_dir},
    );
    defer outer_alloc.free(uv_path);
    return try uvio.loadUVMap(outer_alloc, io, uv_path);
}

fn buildUvField(
    comptime C: usize,
    outer_alloc: std.mem.Allocator,
    uvs: uvio.UVMap,
) !meshio.Field {
    const node_num = uvs.array.dims[0];
    var field = try meshio.Field.initAlloc(outer_alloc, 1, node_num, C);

    for (0..node_num) |nn| {
        const uu = uvs.array.get(&[_]usize{ nn, 0 });
        const vv = uvs.array.get(&[_]usize{ nn, 1 });
        if (C == 1) {
            field.array.set(&.{ 0, nn, 0 }, 0.5 * (uu + vv));
        } else {
            field.array.set(&.{ 0, nn, 0 }, uu);
            field.array.set(&.{ 0, nn, 1 }, vv);
            field.array.set(&.{ 0, nn, 2 }, 0.5 * (uu + vv));
        }
    }

    return field;
}

fn makeMeshInput(
    comptime C: usize,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    rabbit_name: []const u8,
    mesh_type: gk.MeshType,
    shader_mode: ShaderMode,
    texture: texops.Tex(u8, C),
    checker_squares_per_axis: F,
) !MeshInput {
    const data_dir = try buildRabbitDir(outer_alloc, rabbit_name, mesh_type);
    defer outer_alloc.free(data_dir);
    const sim_data = try loadStaticMesh(outer_alloc, io, data_dir);
    const uvs = try loadRabbitUvMap(outer_alloc, io, data_dir);

    const shader: shaderops.ShaderInput = switch (shader_mode) {
        .tex => blk: {
            const input = shaderops.TexInput(u8, C){
                .uvs = uvs.array,
                .tex = texture,
                .samp_cfg = .{
                    .sample = .cubic_catmull_rom,
                    .mode = .lut_lerp,
                },
                .bits = 8,
                .scaling = .none,
                .normal_type = .none,
            };
            break :blk if (C == 1) .{ .tex_u8 = input } else .{ .tex_rgb_u8 = input };
        },
        .nodal => .{ .nodal = .{
            .field = try buildUvField(C, outer_alloc, uvs),
            .bits = 8,
            .scaling = .auto,
            .scale_over = .over_frames,
            .normal_type = .none,
        } },
        .func => blk: {
            const input = shaderops.FuncInput{
                .uvs = uvs.array,
                .coord_mode = .uv,
                .builtin = FuncShaderBuiltin.checker,
                .params = FuncShaderParams{
                    .coord_scale = .{
                        checker_squares_per_axis,
                        checker_squares_per_axis,
                    },
                    .settings = .{ .checker = .{} },
                },
                .bits = 8,
                .scaling = .auto,
                .normal_type = .none,
            };
            break :blk if (C == 1) .{ .func = input } else .{ .func_rgb = input };
        },
    };

    return .{
        .mesh_type = mesh_type,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = shader,
    };
}

test "rabbit UV fields preserve mono and RGB channel values" {
    const alloc = std.testing.allocator;
    var uvs = try uvio.UVMap.init(alloc, 1);
    defer uvs.deinit(alloc);
    uvs.array.set(&.{ 0, 0 }, 0.2);
    uvs.array.set(&.{ 0, 1 }, 0.6);
    var mono = try buildUvField(1, alloc, uvs);
    defer mono.deinit(alloc);
    var rgb = try buildUvField(3, alloc, uvs);
    defer rgb.deinit(alloc);
    try std.testing.expectApproxEqAbs(@as(F, 0.4), mono.array.get(&.{ 0, 0, 0 }), 1e-6);
    try std.testing.expectApproxEqAbs(@as(F, 0.2), rgb.array.get(&.{ 0, 0, 0 }), 1e-6);
    try std.testing.expectApproxEqAbs(@as(F, 0.6), rgb.array.get(&.{ 0, 0, 1 }), 1e-6);
    try std.testing.expectApproxEqAbs(@as(F, 0.4), rgb.array.get(&.{ 0, 0, 2 }), 1e-6);
}

test "rabbit shaders cycle across texture nodal and function modes" {
    try std.testing.expectEqual(ShaderMode.tex, shaderModeForMeshIndex(0));
    try std.testing.expectEqual(ShaderMode.nodal, shaderModeForMeshIndex(1));
    try std.testing.expectEqual(ShaderMode.func, shaderModeForMeshIndex(2));
    try std.testing.expectEqual(ShaderMode.tex, shaderModeForMeshIndex(3));
}
