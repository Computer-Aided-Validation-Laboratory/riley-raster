// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const riley = @import("../riley/zig/riley.zig");
const meshio = @import("../riley/zig/meshio.zig");
const meshpipe = @import("../riley/zig/meshpipeline.zig");
const cam = @import("../riley/zig/camera.zig");
const vecstack = @import("../riley/zig/vecstack.zig");
const rotation = @import("../riley/zig/rotation.zig");
const F = @import("../riley/zig/buildconfig.zig").F;

test "distorted tri3 interior reaches scalar or SIMD raster in both map modes" {
    const outer_alloc = std.testing.allocator;
    const io = std.testing.io;
    var coords = try meshio.Coords.initAlloc(outer_alloc, 3);
    defer outer_alloc.free(coords.mem);
    const xyz = [_][3]F{
        .{ 0.1, 0.5, 0.0 },
        .{ 0.1, -0.5, 0.0 },
        .{ 0.2, 0.0, 0.0 },
    };
    for (xyz, 0..) |point, nn| {
        for (0..3) |cc| coords.mat.set(nn, cc, point[cc]);
    }
    var connect = try meshio.Connect.initAlloc(outer_alloc, 1, 3);
    defer connect.deinit(outer_alloc);
    connect.table_mem[0] = 0;
    connect.table_mem[1] = 1;
    connect.table_mem[2] = 2;

    const mesh = meshpipe.MeshInput{
        .mesh_type = .tri3,
        .coords = coords,
        .connect = connect,
        .disp = null,
        .shader = .{ .func = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value = 1.0 } } },
            .bits = 8,
            .scaling = .none,
        } },
    };
    const modes = [_]cam.SubPixelCenterMap{ .full_in_mem, .per_tile };
    const buffers = [_]riley.BufferMode{ .tile_local, .global_subpx_full };
    const samples = [_]u32{ 1, 2, 4 };

    for (modes) |mode| {
        for (buffers) |buffer_mode| {
            for (samples) |sub_sample| {
                const camera_input = cam.CameraInput{
                    .pixels_num = .{ 200, 200 },
                    .pixels_size = .{ 0.01, 0.01 },
                    .pos_world = vecstack.Vec3f.initSlice(&.{ 0.0, 0.0, 1.0 }),
                    .rot_world = rotation.Rotation.init(0.0, 0.0, 0.0),
                    .roi_cent_world = vecstack.Vec3f.initZeros(),
                    .focal_length = 1.0,
                    .sub_sample = sub_sample,
                    .subpixel_center_map = mode,
                    .distort = .{ .brown_con = .{ .k1 = 1.0 } },
                };
                const config = riley.RasterConfig{
                    .save_strategy = .memory,
                    .report = .{ .mode = .off },
                    .background_value = 0.0,
                    .advanced = .{
                        .raster = .{ .buffer_mode = buffer_mode },
                        .distortion = .{ .edge_spacing_px = 1.0 },
                    },
                };
                const result = try riley.raster(
                    outer_alloc,
                    io,
                    &.{camera_input},
                    &.{mesh},
                    config,
                    null,
                );
                var image = result orelse return error.NoResult;
                defer {
                    outer_alloc.free(image.slice);
                    image.deinit(outer_alloc);
                }
                try std.testing.expect(image.get(&[_]usize{ 0, 0, 0, 100, 110 }) > 0.5);
                try std.testing.expectEqual(
                    @as(F, 0.0),
                    image.get(&[_]usize{ 0, 0, 0, 100, 105 }),
                );
            }
        }
    }
}
