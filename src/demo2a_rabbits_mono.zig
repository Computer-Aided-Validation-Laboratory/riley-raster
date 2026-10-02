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
const cammod = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const gk = @import("riley/zig/geometrykernels.zig");
const iio = @import("riley/zig/imageio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const rastcfg = @import("riley/zig/rasterconfig.zig");
const riley = @import("riley/zig/riley.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const sceneops = @import("riley/zig/sceneops.zig");
const buildconfig = @import("riley/zig/buildconfig.zig");

const CameraInput = cammod.CameraInput;
const F = buildconfig.F;

const common = @import("demo_rabbits_common.zig");

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const local_alloc = arena.allocator();

    const io = init.io;

    // -------------------------------------------------------------------------
    // 1. Setup paths, texture, and meshes
    // -------------------------------------------------------------------------
    const rabbit_mesh_types = [_]gk.MeshType{ .tri3, .tri6, .quad4, .quad8, .quad9 };
    const overlap_frac_xy = [2]F{ 0.85, 0.8 };
    const checker_squares_per_axis: F = 36.0;
    const texture = try iio.loadImage(
        u8,
        1,
        local_alloc,
        io,
        "texture/speckle_mono.bmp",
        .bmp,
    );

    const mesh_inputs = try common.buildRabbitPairScene(1, local_alloc, io, texture, .{
        .mesh_types = &rabbit_mesh_types,
        .overlap_frac_xy = overlap_frac_xy,
        .checker_squares_per_axis = checker_squares_per_axis,
        .gap = .{ 0.18, 0.28, 0.0 },
        .max_divs = .{ 3, 2, 1 },
    });

    // -------------------------------------------------------------------------
    // 2. Position and configure camera
    // -------------------------------------------------------------------------
    const pixel_num = [2]u32{ 1600, 800 };
    const fov_scale: F = 1.01;
    // Canonical rabbit winding exposes the opposite side from the legacy data.
    const rot = Rotation.init(0.0, 0.0, 0.0);
    const roi_pos = sceneops.boundsCenterOverMeshes(mesh_inputs);
    const cam_pos = cameraops.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        orch.default_pixel_size,
        orch.default_focal_length,
        rot,
        fov_scale,
    );
    const camera_input = CameraInput{
        .pixels_num = pixel_num,
        .pixels_size = orch.default_pixel_size,
        .pos_world = cam_pos,
        .rot_world = rot,
        .roi_cent_world = roi_pos,
        .focal_length = orch.default_focal_length,
        .sub_sample = 2,
    };

    // -------------------------------------------------------------------------
    // 3. Configure raster engine
    // -------------------------------------------------------------------------
    const background_value: F = 0.5 * @as(F, std.math.maxInt(u8));
    const config = rastcfg.RasterConfig{
        .parallel = .{ .threads = 4 },
        .save_strategy = .disk,
        .background_value = background_value,
        .output = .{
            .image_save_mode = .grey,
            .image_save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .bmp, .bits = 8, .scaling = .none },
            },
        },
    };

    // -------------------------------------------------------------------------
    // 4. Render rabbit multi-mesh scene
    // -------------------------------------------------------------------------
    const out_dir_root = "./out/demo2a_rabbits_mono";
    const images = try riley.raster(
        init.gpa,
        io,
        &[_]CameraInput{camera_input},
        mesh_inputs,
        config,
        out_dir_root,
    );

    if (images) |img| {
        init.gpa.free(img.slice);
        img.deinit(init.gpa);
    }
}
