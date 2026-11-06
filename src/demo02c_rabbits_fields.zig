// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const riley = @import("riley/zig/api.zig");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;
const common = @import("demo_rabbits_common.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    const io = init.io;

    // -------------------------------------------------------------------------
    // 1. Setup paths, texture, and meshes
    // -------------------------------------------------------------------------
    const rabbit_mesh_types = [_]riley.MeshType{ .tri3, .tri6, .quad4, .quad8, .quad9 };
    const overlap_frac_xy = [2]maths.F{ 0.85, 0.8 };
    const checker_squares_per_axis: maths.F = 36.0;

    const texture = try datio.loadImage(
        u8,
        3,
        local_alloc,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
    );

    const mesh_inputs = try common.buildRabbitPairScene(3, local_alloc, io, texture, .{
        .mesh_types = &rabbit_mesh_types,
        .overlap_frac_xy = overlap_frac_xy,
        .checker_squares_per_axis = checker_squares_per_axis,
        .gap = .{ 0.18, 0.28, 0.0 },
        .max_divs = .{ 3, 2, 1 },
        .render_as_multifield = true,
    });

    // -------------------------------------------------------------------------
    // 2. Position and configure camera
    // -------------------------------------------------------------------------
    const default_pixel_size = [2]maths.F{ 5.3e-6, 5.3e-6 };
    const default_focal_length: maths.F = 50.0e-3;

    const pixel_num = [2]u32{ 1600, 800 };
    const fov_scale: maths.F = 1.01;
    const rot = maths.Rotation.init(0.0, 0.0, 0.0);

    const roi_pos = ops.boundsCenterOverMeshes(mesh_inputs);
    const cam_pos = ops.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        default_pixel_size,
        default_focal_length,
        rot,
        fov_scale,
    );
    var camera_input = riley.CameraInput{
        .render_format = .{ .multifield = 3 },
        .pixels_num = pixel_num,
        .pixels_size = default_pixel_size,
        .pos_world = cam_pos,
        .rot_world = rot,
        .roi_cent_world = roi_pos,
        .focal_length = default_focal_length,
        .sub_sample = 4,
    };

    // -------------------------------------------------------------------------
    // 3. Configure raster engine
    // -------------------------------------------------------------------------
    const background_value: maths.F = 0.5 * @as(maths.F, std.math.maxInt(u8));

    camera_input.background_value = background_value;
    const config = riley.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
    };

    // -------------------------------------------------------------------------
    // 4. Render rabbit multi-mesh scene
    // -------------------------------------------------------------------------
    const out_dir_root = "./out/demo02c_rabbits_fields";

    const images = try riley.raster(
        init.gpa,
        io,
        &.{camera_input},
        mesh_inputs,
        config,
        out_dir_root,
    );

    if (images) |img| {
        init.gpa.free(img.slice);
        img.deinit(init.gpa);
    }
}
