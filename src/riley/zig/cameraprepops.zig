// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cameratypes = @import("cameratypes.zig");
const std = @import("std");
const cameraprojops = @import("cameraprojops.zig");

pub fn prepareCameraSlice(
    allocator: std.mem.Allocator,
    camera_inputs: []const cameratypes.CameraInput,
) ![]cameraprojops.CameraPrepared {
    const cameras = try allocator.alloc(cameraprojops.CameraPrepared, camera_inputs.len);
    for (camera_inputs, 0..) |camera_input, cc| {
        cameras[cc] = cameraprojops.CameraPrepared.init(
            allocator,
            camera_input,
        ) catch |err| {
            for (0..cc) |pp| cameras[pp].deinit(allocator);
            allocator.free(cameras);
            return err;
        };
    }

    return cameras;
}
