// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const riley = @import("riley/zig/riley.zig");
const meshio = @import("riley/zig/meshio.zig");
const meshpipe = @import("riley/zig/meshpipeline.zig");
const shaderops = @import("riley/zig/shaderops.zig");
const shaderpipe = @import("riley/zig/shaderpipe.zig");
const camera = @import("riley/zig/cameraprojops.zig");
const cameraops = @import("riley/zig/cameraframops.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const buildconfig = @import("riley/zig/buildconfig.zig");
const F = buildconfig.F;

pub fn main(init: std.process.Init) !void {
    // -------------------------------------------------------------------------
    // 1. Create the mesh geometry and shaders
    // -------------------------------------------------------------------------
    var coord_values = [_]F{
        -1.0, -1.0, 0.0,
        1.0,  -1.0, 0.0,
        0.0,  1.0,  0.0,
    };
    var connect_values = [_]usize{ 0, 1, 2 };
    const coords = meshio.Coords.init(&coord_values, 3);
    const connect = meshio.Connect.init(&connect_values, 1, 3);

    const checker: riley.PipeSourceInput = .{
        .func = .{
            .mono = .{
                .coord_mode = .world_reference,
                .builtin = .checker,
                .params = .{
                    .coord_scale = .{ 4.0, 4.0 },
                    .settings = .{ .checker = .{} },
                },
                .scaling = .auto,
            },
        },
    };

    const channel = shaderpipe.Slot{ .kind = .channel, .index = 0 };
    const parameter = shaderpipe.Slot{ .kind = .parameter, .index = 0 };

    const stages = [_]riley.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = checker,
                .destination = channel,
            },
        },
        .{
            .source = .{
                .shader = .{
                    .func = .{
                        .mono = .{
                            .coord_mode = .world_reference,
                            .builtin = .linear,
                            // x in [-1,1]: illumination rises from 0.25 to 1.0.
                            .params = .{
                                .settings = .{
                                    .linear = .{ .coeffs = .{ 0.625, 0.375, 0.0 } },
                                },
                            },

                            .scaling = .none,
                        },
                    },
                },
                .destination = parameter,
            },
        },
    };
    const sources = [_]shaderpipe.Slot{channel};

    const mesh = riley.MeshInput{
        .mesh_type = .tri3opt,
        .coords = coords,
        .connect = connect,
        .disp = null,
        .shaders = .{
            .mono_pipe = .{
                .stages = &stages,
                .resolver = .{
                    .modulate = .{
                        .sources = &sources,
                        .factor = parameter,
                    },
                },
            },
        },
    };

    // -------------------------------------------------------------------------
    // 2. Configure and frame the direct and lit cameras
    // -------------------------------------------------------------------------
    const pixels_num = [2]u32{ 512, 512 };
    const pixels_size = [2]F{ 0.02, 0.02 };
    const target = sceneops.boundsCenter(&coords);
    const rotation = Rotation.init(0.0, 0.0, 0.0);
    const position = cameraops.posFillFrameFromRotAndTarg(
        &coords,
        target,
        pixels_num,
        pixels_size,
        1.0,
        rotation,
        1.0,
    );

    const direct_camera = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = position,
        .rot_world = rotation,
        .roi_cent_world = target,
        .focal_length = 1.0,
        .sub_sample = 4,
        .render_format = .mono,
        .output_files = &.{.{ .format = .bmp, .file_bits = 8, .scaling = .{ .fixed = .{ 0, 1 } } }},
    };

    var lit_camera = direct_camera;
    lit_camera.render_format = .mono;

    // -------------------------------------------------------------------------
    // 3. Configure the raster engine and output path
    // -------------------------------------------------------------------------
    const config = riley.RasterConfig{
        .save_strategy = .disk,
        .output_name_format = "demo7_cam{camera}_frame{frame}_field{field}",
    };

    // -------------------------------------------------------------------------
    // 4. Render the scene
    // -------------------------------------------------------------------------
    const images = try riley.raster(
        init.gpa,
        init.io,
        &.{ direct_camera, lit_camera },
        &.{mesh},
        config,
        "./out/demo7_shaderpipe_quickstart",
    );

    if (images) |image| {
        init.gpa.free(image.slice);
        image.deinit(init.gpa);
    }
}
