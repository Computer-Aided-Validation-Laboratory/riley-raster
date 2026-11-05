// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const riley = @import("riley");
const maths = riley.maths;
const datio = riley.dataio;
const ops = riley.ops;

pub fn main(init: std.process.Init) !void {
    // -------------------------------------------------------------------------
    // 1. Create the mesh geometry and shaders
    // -------------------------------------------------------------------------
    var coord_values = [_]maths.F{
        -1.0, -1.0, 0.0,
        1.0,  -1.0, 0.0,
        0.0,  1.0,  0.0,
    };
    var connect_values = [_]usize{ 0, 1, 2 };
    const coords = riley.Coords.init(&coord_values, 3);
    const connect = riley.Connect.init(&connect_values, 1, 3);

    const checker: riley.PipeSourceInput = .{
        .func = .{
            .coord_mode = .world_reference,
            .builtin = .checker,
            .params = .{
                .coord_scale = .{ 4.0, 4.0 },
                .settings = .{ .checker = .{} },
            },
            .scaling = .auto,
        },
    };

    const linear_source: riley.PipeSourceInput = .{
        .func = .{
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
    };

    const channel = riley.Register{ .kind = .channel, .index = 0 };
    const parameter = riley.Register{ .kind = .parameter, .index = 0 };

    const stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = checker,
                .register_dest = channel,
            },
        },
        .{
            .shader = .{
                .shader = linear_source,
                .register_dest = parameter,
            },
        },
    };
    const sources = [_]riley.Register{channel};
    const pipe_shader: riley.ShaderPipeInput = .{
        .stages = &stages,
        .resolver = .{
            .modulate = .{
                .register_sources = &sources,
                .factor = parameter,
            },
        },
    };

    const mesh = riley.MeshInput{
        .mesh_type = .tri3opt,
        .coords = coords,
        .connect = connect,
        .disp = null,
        .shaders = .{ .mono_pipe = pipe_shader },
    };

    // -------------------------------------------------------------------------
    // 2. Configure and frame the direct and lit cameras
    // -------------------------------------------------------------------------
    const pixels_num = [2]u32{ 512, 512 };
    const pixels_size = [2]maths.F{ 0.02, 0.02 };
    const target = ops.boundsCenter(&coords);
    const rotation = maths.Rotation.init(0.0, 0.0, 0.0);
    const position = ops.posFillFrameFromRotAndTarg(
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
        .output_name_format = "demo07_cam{camera}_frame{frame}_field{field}",
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
        "./out/demo07_shaderpipe_quickstart",
    );

    if (images) |image| {
        init.gpa.free(image.slice);
        image.deinit(init.gpa);
    }
}
