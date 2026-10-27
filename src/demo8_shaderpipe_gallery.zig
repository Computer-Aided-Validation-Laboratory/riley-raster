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
const camera = @import("riley/zig/camera.zig");
const cameraops = @import("riley/zig/cameraops.zig");
const iio = @import("riley/zig/imageio.zig");
const sceneops = @import("riley/zig/sceneops.zig");
const Rotation = @import("riley/zig/rotation.zig").Rotation;
const buildconfig = @import("riley/zig/buildconfig.zig");
const F = buildconfig.F;

fn linear(x: F, y: F) shaderops.PipeSourceInput {
    return .{
        .func = .{
            .mono = .{
                .builtin = .linear,
                .coord_mode = .world_reference,
                .params = .{
                    .settings = .{
                        .linear = .{ .coeffs = .{ 0.5, x, y } },
                    },
                },

                .scaling = .none,
            },
        },
    };
}

fn render(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh: meshpipe.MeshInput,
    base_camera: camera.CameraInput,
    role: shaderops.RenderFormat,
    path: []const u8,
) !void {
    var selected_camera = base_camera;
    selected_camera.render_format = role;
    const save_opts = if (role == .rgb)
        iio.ImageSaveOpts{
            .format = .bmp,
            .bits = 8,
            .scaling = .{ .fixed = .{ 0.0, 1.0 } },
        }
    else
        iio.ImageSaveOpts{
            .format = .tiff,
            .bits = 16,
            .scaling = .{ .fixed = .{ 0.0, 1.0 } },
        };
    selected_camera.output_files = &.{save_opts};
    const config = riley.RasterConfig{
        .save_strategy = .disk,
    };
    const result = try riley.raster(
        allocator,
        io,
        &.{selected_camera},
        &.{mesh},
        config,
        path,
    );
    if (result) |image| {
        allocator.free(image.slice);
        image.deinit(allocator);
    }
}

pub fn main(init: std.process.Init) !void {
    // -------------------------------------------------------------------------
    // 1. Create base mesh and shared camera
    // -------------------------------------------------------------------------
    var coord_values = [_]F{
        -1.0, -1.0, 0.0,
        1.0,  -1.0, 0.0,
        0.0,  1.0,  0.0,
    };
    var connect_values = [_]usize{ 0, 1, 2 };
    const coords = meshio.Coords.init(&coord_values, 3);
    const connect = meshio.Connect.init(&connect_values, 1, 3);

    var mesh = meshpipe.MeshInput{
        .mesh_type = .tri3opt,
        .coords = coords,
        .connect = connect,
        .disp = null,
        .shaders = .{},
    };

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

    const base_camera = camera.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = position,
        .rot_world = rotation,
        .roi_cent_world = target,
        .focal_length = 1.0,
        .sub_sample = 4,
    };

    const ch0 = shaderpipe.Slot{ .kind = .channel, .index = 0 };
    const ch1 = shaderpipe.Slot{ .kind = .channel, .index = 1 };
    const ch2 = shaderpipe.Slot{ .kind = .channel, .index = 2 };
    const param0 = shaderpipe.Slot{ .kind = .parameter, .index = 0 };
    const field0 = shaderpipe.Slot{ .kind = .field, .index = 0 };
    const field1 = shaderpipe.Slot{ .kind = .field, .index = 1 };

    const checker: shaderops.PipeSourceInput = .{
        .func = .{
            .mono = .{
                .builtin = .checker,
                .coord_mode = .world_reference,
                .params = .{
                    .coord_scale = .{ 4.0, 4.0 },
                    .settings = .{ .checker = .{} },
                },

                .scaling = .none,
            },
        },
    };

    // -------------------------------------------------------------------------
    // 2. Composition A: Spatially modulated illumination
    // -------------------------------------------------------------------------
    const mod_stages = [_]shaderops.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = checker,
                .destination = ch0,
            },
        },
        .{
            .source = .{
                .shader = .{
                    .func = .{
                        .mono = .{
                            .builtin = .linear,
                            .coord_mode = .world_reference,
                            .params = .{
                                .settings = .{
                                    .linear = .{ .coeffs = .{ 0.625, 0.375, 0.0 } },
                                },
                            },

                            .scaling = .none,
                        },
                    },
                },
                .destination = param0,
            },
        },
    };
    const mod_sources = [_]shaderpipe.Slot{ch0};
    mesh.shaders = .{
        .mono = .{ .pipe = .{
            .stages = &mod_stages,
            .resolver = .{
                .modulate = .{
                    .sources = &mod_sources,
                    .factor = param0,
                },
            },
        } },
    };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo8_shaderpipe_gallery/a_modulation",
    );

    // -------------------------------------------------------------------------
    // 3. Composition B: Multi-channel RGB gradient composition
    // -------------------------------------------------------------------------
    const rgb_stages = [_]shaderops.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = linear(0.5, 0.0),
                .destination = ch0,
            },
        },
        .{
            .source = .{
                .shader = linear(0.0, 0.5),
                .destination = ch1,
            },
        },
        .{
            .source = .{
                .shader = linear(0.25, -0.25),
                .destination = ch2,
            },
        },
    };
    const rgb_slots = [_]shaderpipe.Slot{ ch0, ch1, ch2 };
    mesh.shaders = .{
        .rgb = .{
            .stages = &rgb_stages,
            .resolver = .{ .identity = &rgb_slots },
        },
    };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .rgb,
        "./out/demo8_shaderpipe_gallery/b_rgb",
    );

    // -------------------------------------------------------------------------
    // 4. Composition C: Bounded expression blend
    // -------------------------------------------------------------------------
    const expr_stages = [_]shaderops.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = linear(0.5, 0.0),
                .destination = field0,
            },
        },
        .{
            .source = .{
                .shader = linear(0.0, 0.5),
                .destination = field1,
            },
        },
    };
    const expr_ops = [_]shaderpipe.Op{
        .{ .load = field0 },
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .multiply,
        .{ .load = field1 },
        .{ .load = .{ .kind = .constant, .index = 1 } },
        .multiply,
        .add,
        .clamp01,
        .{ .store = 0 },
    };
    mesh.shaders = .{
        .mono = .{ .pipe = .{
            .stages = &expr_stages,
            .resolver = .{
                .expression = .{
                    .operations = &expr_ops,
                    .constants = &.{ 0.65, 0.35 },
                },
            },
        } },
    };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo8_shaderpipe_gallery/c_expression",
    );

    // -------------------------------------------------------------------------
    // 5. Composition D: Emissivity material parameter mapping
    // -------------------------------------------------------------------------
    const emissivity_stages = [_]shaderops.ShaderPipeStageInput{
        .{
            .source = .{
                .shader = checker,
                .destination = ch0,
            },
        },
        .{
            .grey_to_emissivity = .{
                .source = ch0,
                .destination = param0,
                .black = 0.96,
                .white = 0.90,
            },
        },
    };
    const emissivity_ops = [_]shaderpipe.Op{
        .{ .load = param0 },
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .subtract,
        .{ .load = .{ .kind = .constant, .index = 1 } },
        .multiply,
        .clamp01,
        .{ .store = 0 },
    };
    mesh.shaders = .{
        .mono = .{ .pipe = .{
            .stages = &emissivity_stages,
            .resolver = .{
                .expression = .{
                    .operations = &emissivity_ops,
                    .constants = &.{ 0.90, 1.0 / 0.06 },
                },
            },
        } },
    };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo8_shaderpipe_gallery/d_emissivity_visualisation",
    );
}
