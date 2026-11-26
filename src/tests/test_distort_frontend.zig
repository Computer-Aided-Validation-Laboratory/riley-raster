// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");
const riley = @import("../riley/zig/api.zig");
const F = riley.maths.F;

test "distorted tri3 interior reaches scalar or SIMD raster in both map modes" {
    const outer_alloc = std.testing.allocator;
    var xyz = [_]F{
        0.1, 0.5,  0.0,
        0.1, -0.5, 0.0,
        0.2, 0.0,  0.0,
    };
    var node_indices = [_]usize{ 0, 1, 2 };
    const mesh = riley.MeshInput{
        .mesh_type = .tri3,
        .coords = riley.Coords.init(&xyz, 3),
        .connect = riley.Connect.init(&node_indices, 1, 3),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .func = .{
            .builtin = .constant,
            .params = .{ .settings = .{ .constant = .{ .value = 1.0 } } },
            .scaling = .none,
        } } },
    };
    const modes = [_]riley.SubPixelCenterMap{ .full_in_mem, .per_tile };
    const buffers = [_]riley.BufferMode{ .tile_local, .global_subpx_full };
    const samples = [_]u32{ 1, 2, 4 };

    for (modes) |mode| {
        for (buffers) |buffer_mode| {
            for (samples) |sub_sample| {
                const camera_input = riley.CameraInput{
                    .pixels_num = .{ 200, 200 },
                    .pixels_size = .{ 0.01, 0.01 },
                    .pos_world = riley.maths.Vec3F.initSlice(&.{ 0.0, 0.0, 1.0 }),
                    .rot_world = riley.maths.Rotation.init(0.0, 0.0, 0.0),
                    .roi_cent_world = riley.maths.Vec3F.initZeros(),
                    .focal_length = 1.0,
                    .sub_sample = sub_sample,
                    .background_value = 0.0,
                    .subpixel_center_map = mode,
                    .distort = .{ .brown_con = .{ .k1 = 1.0 } },
                };
                const config = riley.RasterConfig{
                    .parallel = .serial,
                    .save_strategy = .memory,
                    .advanced = .{
                        .raster = .{ .buffer_mode = buffer_mode },
                        .distortion = .{ .edge_spacing_px = 1.0 },
                    },
                };
                const result = try riley.raster(
                    outer_alloc,
                    std.testing.io,
                    &.{camera_input},
                    &.{mesh},
                    config,
                    null,
                );
                const image = result orelse return error.NoResult;
                defer {
                    outer_alloc.free(image.slice);
                    image.deinit(outer_alloc);
                }

                // At this row the curved edge reaches x = 110.1, left of the
                // distorted vertices at x = 112.6. A vertex-only box misses pixel 110.
                try std.testing.expect(image.get(&.{ 0, 0, 0, 100, 110 }) > 0.5);
                try std.testing.expectEqual(@as(F, 0.0), image.get(&.{ 0, 0, 0, 100, 105 }));
            }
        }
    }
}
