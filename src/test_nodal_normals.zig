// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const meshraster = @import("zraster/zig/meshraster.zig");
const meshio = @import("zraster/zig/meshio.zig");
const report = @import("zraster/zig/report.zig");
const rops = @import("zraster/zig/rasterops.zig");
const shaderops = @import("zraster/zig/shaderops.zig");
const Camera = @import("zraster/zig/camera.zig").Camera;
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

    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_cent,
        focal_leng,
        2,
    );

    const mesh_input = meshraster.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .nodal = .{
            .field = sim_data.field.?,
            .normal_type = .averaged,
        } },
    };

    var prep_meshes = [_]meshraster.MeshPrepared{
        try meshraster.prepareMesh(
            arena_alloc,
            &mesh_input,
            &sim_data.coords.mat,
            null,
        ),
    };

    var off_log = report.OffLog{};
    const ctx_perf = report.ReportContext(.off){
        .log = &off_log,
    };

    var raster_hulls = [_]?NDArray(f64){null};
    const elem_bboxes_by_mesh = try arena_alloc.alloc([]rops.ElemBBox, 1);
    const elems_in_image_by_mesh = try arena_alloc.alloc(usize, 1);
    var total_elems_num: usize = 0;
    var total_elems_in_image: usize = 0;

    try rops.prepareSceneGeometry(
        .off,
        ctx_perf,
        arena_alloc,
        &camera,
        prep_meshes[0..],
        raster_hulls[0..],
        elem_bboxes_by_mesh,
        elems_in_image_by_mesh,
        &total_elems_num,
        &total_elems_in_image,
    );

    try std.testing.expect(total_elems_num > 0);
    try std.testing.expect(total_elems_in_image > 0);

    switch (prep_meshes[0].shader) {
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
