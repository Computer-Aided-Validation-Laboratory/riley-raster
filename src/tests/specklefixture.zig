// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
//! Test-only scenes and image assertions shared by procedural speckle integration tests.
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/cameratypes.zig");
const fieldtypes = @import("../riley/zig/fieldtypes.zig");
const meshtypes = @import("../riley/zig/meshtypes.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const rasterconfig = @import("../riley/zig/rasterconfig.zig");
const rotation = @import("../riley/zig/rotation.zig");
const speckleparams = @import("../riley/zig/speckleparams.zig");
const vecstack = @import("../riley/zig/vecstack.zig");

const F = buildconfig.F;
const frame_pixels = 24 * 32;
pub const disk_params: speckleparams.Disk2DParams = .{
    .seed = 12345,
    .coverage = 0.35,
    .radius = 0.09,
    .occupancy = 0.8,
};

// Every borrowed slice, including array metadata, lives in the caller's arena.
// Unit changes scale all physical lengths; reference selection belongs to the tests.
pub fn initScene(
    arena: *std.heap.ArenaAllocator,
    params: speckleparams.SpeckleParams,
    curved: bool,
    unit_scale: F,
) !struct { camera_input: camera.CameraInput, mesh_input: meshtypes.MeshInput } {
    const alloc = arena.allocator();
    const coords = try alloc.dupe(F, &.{
        -0.65, -0.45, 0, 0.65, -0.45, 0, -0.65, 0.45, 0,
        0,     -0.45, 0, 0,    0,     0, -0.65, 0,    0,
    });
    const connect = try alloc.dupe(usize, &.{ 0, 1, 2, 3, 4, 5 });
    const uv_values = try alloc.dupe(F, &.{ 0, 0, 1, 0, 0, 1, 0.5, 0, 0.5, 0.5, 0, 0.5 });
    const uvs = try ndarray.NDArray(F).init(alloc, uv_values, &.{ 6, 2 });
    var disp = try fieldtypes.Field.initAlloc(alloc, 2, 6, 3);
    for (0..6) |nn| {
        // Frame two shears/translates the patch; curved cases also bend in depth.
        disp.array.set(&.{ 1, nn, 0 }, (0.08 + 0.1 * coords[3 * nn + 1]) * unit_scale);
        disp.array.set(&.{ 1, nn, 1 }, 0.03 * coords[3 * nn] * unit_scale);
        disp.array.set(&.{ 1, nn, 2 }, if (curved and nn >= 3) 0.08 * unit_scale else 0);
    }
    if (curved) {
        coords[3 * 3 + 2] = 0.12;
        coords[3 * 4 + 2] = 0.2;
        coords[3 * 5 + 2] = 0.1;
    }
    for (coords) |*coord| coord.* *= unit_scale;

    var scaled_params = params;
    switch (scaled_params) {
        inline .disk, .gaussian => |*spots, pattern| {
            spots.radius *= unit_scale;
            spots.jitter *= unit_scale;
            if (pattern == .disk) spots.edge_softness *= unit_scale;
        },
        .perlin => |*perlin| perlin.cell_size *= unit_scale,
    }
    return .{
        .camera_input = .{
            .pixels_num = .{ 32, 24 },
            .pixels_size = .{ 0.05 * unit_scale, 0.05 * unit_scale },
            .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 * unit_scale }),
            .rot_world = rotation.Rotation.init(0, 0, 0),
            .roi_cent_world = vecstack.Vec3F.initZeros(),
            .focal_length = 2 * unit_scale,
            .sub_sample = 2,
        },
        .mesh_input = .{
            .mesh_type = .tri6,
            .coords = meshtypes.Coords.init(coords, 6),
            .connect = meshtypes.Connect.init(connect, 1, 6),
            .disp = disp,
            .shaders = .{ .mono_direct = .{ .speckle = .{ .uvs = uvs, .params = scaled_params, .bits = null } } },
        },
    };
}

pub fn rasterConfig(buffer_mode: rasterconfig.BufferMode) rasterconfig.RasterConfig {
    return .{
        .save_strategy = .memory,

        .advanced = .{ .raster = .{
            .buffer_mode = buffer_mode,
            .tile_size_override = 8,
            .global_subpx_tile_size_override = 8,
            .global_subpx_tile_size_min = 8,
            .global_subpx_stripe_size_override = 8,
            .global_subpx_stripe_size_min = 8,
        } },
    };
}

pub fn expectDeformedImages(images: ndarray.NDArray(F)) !void {
    try std.testing.expectEqualSlices(usize, &.{ 1, 2, 1, 24, 32 }, images.dims);
    var dark = [2]usize{ 0, 0 };
    var light = [2]usize{ 0, 0 };
    var covered = [2]usize{ 0, 0 };
    var changed: usize = 0;
    for (images.slice[0..frame_pixels], images.slice[frame_pixels..]) |a, b| {
        if (a != b) changed += 1;
        for ([_]F{ a, b }, 0..) |value, frame| {
            try std.testing.expect(std.math.isFinite(value));
            if (value >= 0) covered[frame] += 1;
            if (value >= 0 and value < 0.4) dark[frame] += 1;
            if (value > 0.6) light[frame] += 1;
        }
    }
    for (dark, light, covered) |d, l, c| {
        try std.testing.expect(d > 5 and l > 5);
        try std.testing.expect(c > 40 and c < frame_pixels);
    }
    try std.testing.expect(changed > 20);
}

pub fn expectImagesWithin(expected: ndarray.NDArray(F), actual: ndarray.NDArray(F), tol: F) !void {
    try std.testing.expectEqualSlices(usize, expected.dims, actual.dims);
    for (expected.slice, actual.slice, 0..) |reference, value, ii| {
        // The <= form rejects NaNs as well as errors outside the tolerance.
        if (!(@abs(reference - value) <= tol)) {
            std.debug.print("frame {d}, pixel {d}: expected {d} +/- {e}, found {d}\n", .{
                ii / frame_pixels, ii % frame_pixels, reference, tol, value,
            });
            return error.TestExpectedEqual;
        }
    }
}
