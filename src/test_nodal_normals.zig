// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const mo = @import("zraster/zig/meshops.zig");
const meshio = @import("zraster/zig/meshio.zig");
const report = @import("zraster/zig/report.zig");
const rops = @import("zraster/zig/rasterops.zig");
const shaderops = @import("zraster/zig/shaderops.zig");
const CameraPrepared = @import("zraster/zig/camera.zig").CameraPrepared;
const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const NDArray = @import("zraster/zig/ndarray.zig").NDArray;

fn loadData(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !meshio.SimData {
    const path_coords = try std.fmt.allocPrint(allocator, "{s}/coords.csv", .{path});
    defer allocator.free(path_coords);
    const path_connect = try std.fmt.allocPrint(allocator, "{s}/connect.csv", .{path});
    defer allocator.free(path_connect);
    const path_field = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/field.csv", .{path}),
    };
    defer allocator.free(path_field[0]);

    return try meshio.loadSimData(
        allocator,
        io,
        path_coords,
        path_connect,
        path_field[0..],
        null,
    );
}

test "Nodal normals are prepared when requested" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const io = std.testing.io;

    var sim_data = try loadData(arena_alloc, io, "data-bench/tri3_sphere200");

    const pixel_num = [_]u32{ 320, 320 };
    const pixel_size = [_]f64{ 0.00625, 0.00625 };
    const focal_leng = 2.0;
    const rot = Rotation.init(0, 0, 0);
    const cam_pos = @import("zraster/zig/camera.zig").CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        1.0,
    );
    const roi_cent = @import("zraster/zig/camera.zig").CameraOps.roiCentFromCoords(
        &sim_data.coords,
    );

    const camera = try CameraPrepared.init(
        arena_alloc,
        .{
            .pixels_num = pixel_num,
            .pixels_size = pixel_size,
            .pos_world = cam_pos,
            .rot_world = rot,
            .roi_cent_world = roi_cent,
            .focal_length = focal_leng,
            .sub_sample = 2,
        },
    );
    defer camera.deinit(arena_alloc);

    const mesh_input = mo.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .nodal = .{
            .field = sim_data.field.?,
            .normal_type = .averaged,
        } },
    };

    const mesh_static = try mo.initStatic(arena_alloc, &mesh_input);

    const frame_mesh = try mo.prepareMeshFrame(
        arena_alloc,
        null,
        1,
        &camera,
        &mesh_static,
        0,
        null,
    );

    try std.testing.expect(frame_mesh.total_elems_num > 0);
    try std.testing.expect(frame_mesh.elems_in_image > 0);

    switch (frame_mesh.mesh.shader) {
        .nodal => |shader| {
            try std.testing.expectEqual(
                shaderops.NormalType.averaged,
                shader.normal_type,
            );
            try std.testing.expect(shader.elem_normals != null);
        },
        else => return error.UnexpectedShaderVariant,
    }
}
