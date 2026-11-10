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

fn createFuncShaderLinearSource(x: maths.F, y: maths.F) riley.PipeSourceInput {
    return .{
        .func = .{
            .builtin = .linear,
            .coord_mode = .world_reference,
            .params = .{
                .settings = .{
                    .linear = .{ .coeffs = .{ 0.5, x, y } },
                },
            },

            .scaling = .none,
        },
    };
}

fn render(
    allocator: std.mem.Allocator,
    io: std.Io,
    mesh: riley.MeshInput,
    base_camera: riley.CameraInput,
    role: riley.RenderFormat,
    path: []const u8,
) !void {
    var selected_camera = base_camera;
    selected_camera.render_format = role;

    const save_opts = if (role == .rgb)
        datio.ImageSaveOpts{
            .format = .bmp,
            .file_bits = 8,
            .scaling = .{ .fixed = .{ 0.0, 1.0 } },
        }
    else
        datio.ImageSaveOpts{
            .format = .tiff,
            .file_bits = 16,
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
    var coord_values = [_]maths.F{
        -1.0, -1.0, 0.0,
        1.0,  -1.0, 0.0,
        0.0,  1.0,  0.0,
    };
    var connect_values = [_]usize{ 0, 1, 2 };
    const coords = riley.Coords.init(&coord_values, 3);
    const connect = riley.Connect.init(&connect_values, 1, 3);

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

    const base_camera = riley.CameraInput{
        .pixels_num = pixels_num,
        .pixels_size = pixels_size,
        .pos_world = position,
        .rot_world = rotation,
        .roi_cent_world = target,
        .focal_length = 1.0,
        .sub_sample = 4,
        .render_format = .mono,
    };

    const ch0 = riley.Register{ .kind = .channel, .index = 0 };
    const ch1 = riley.Register{ .kind = .channel, .index = 1 };
    const ch2 = riley.Register{ .kind = .channel, .index = 2 };
    const param0 = riley.Register{ .kind = .parameter, .index = 0 };
    const field0 = riley.Register{ .kind = .field, .index = 0 };
    const field1 = riley.Register{ .kind = .field, .index = 1 };

    const checker: riley.PipeSourceInput = .{
        .func = .{
            .builtin = .checker,
            .coord_mode = .world_reference,
            .params = .{
                .coord_scale = .{ 4.0, 4.0 },
                .settings = .{ .checker = .{} },
            },

            .scaling = .none,
        },
    };

    const mod_linear_source: riley.PipeSourceInput = .{
        .func = .{
            .builtin = .linear,
            .coord_mode = .world_reference,
            .params = .{
                .settings = .{
                    .linear = .{ .coeffs = .{ 0.625, 0.375, 0.0 } },
                },
            },

            .scaling = .none,
        },
    };

    // -------------------------------------------------------------------------
    // 2. Composition A: Spatially modulated illumination
    // -------------------------------------------------------------------------
    const mod_stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = checker,
                .register_dest = ch0,
            },
        },
        .{
            .shader = .{
                .shader = mod_linear_source,
                .register_dest = param0,
            },
        },
    };
    const mod_sources = [_]riley.Register{ch0};
    const mod_pipe: riley.ShaderPipeInput = .{
        .stages = &mod_stages,
        .resolver = .{
            .modulate = .{
                .register_sources = &mod_sources,
                .factor = param0,
            },
        },
    };

    var mesh = riley.MeshInput{
        .mesh_type = .tri3opt,
        .coords = coords,
        .connect = connect,
        .disp = null,
        .shaders = .{ .mono_pipe = mod_pipe },
    };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo08_shaderpipe_gallery/a_modulation",
    );

    // -------------------------------------------------------------------------
    // 3. Composition B: Multi-channel RGB gradient composition
    // -------------------------------------------------------------------------
    const rgb_stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = createFuncShaderLinearSource(0.5, 0.0),
                .register_dest = ch0,
            },
        },
        .{
            .shader = .{
                .shader = createFuncShaderLinearSource(0.0, 0.5),
                .register_dest = ch1,
            },
        },
        .{
            .shader = .{
                .shader = createFuncShaderLinearSource(0.25, -0.25),
                .register_dest = ch2,
            },
        },
    };
    const rgb_slots = [_]riley.Register{ ch0, ch1, ch2 };
    const rgb_pipe: riley.ShaderPipeInput = .{
        .stages = &rgb_stages,
        .resolver = .{ .identity = &rgb_slots },
    };
    mesh.shaders = .{ .rgb_pipe = rgb_pipe };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .rgb,
        "./out/demo08_shaderpipe_gallery/b_rgb",
    );

    // -------------------------------------------------------------------------
    // 4. Composition C: Bounded expression blend
    // -------------------------------------------------------------------------
    const expr_stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = createFuncShaderLinearSource(0.5, 0.0),
                .register_dest = field0,
            },
        },
        .{
            .shader = .{
                .shader = createFuncShaderLinearSource(0.0, 0.5),
                .register_dest = field1,
            },
        },
    };

    const expr_ops = [_]riley.ResolverOp{
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

    const expr_pipe: riley.ShaderPipeInput = .{
        .stages = &expr_stages,
        .resolver = .{
            .expression = .{
                .operations = &expr_ops,
                .constants = &.{ 0.65, 0.35 },
            },
        },
    };

    mesh.shaders = .{ .mono_pipe = expr_pipe };

    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo08_shaderpipe_gallery/c_expression",
    );

    // -------------------------------------------------------------------------
    // 5. Composition D: Emissivity material parameter mapping
    // -------------------------------------------------------------------------
    const emissivity_stages = [_]riley.ShaderPipeStageInput{
        .{
            .shader = .{
                .shader = checker,
                .register_dest = ch0,
            },
        },
        .{
            .grey_to_emissivity = .{
                .register_source = ch0,
                .register_dest = param0,
                .emissivity_at_black = 0.96,
                .emissivity_at_white = 0.90,
            },
        },
    };

    const emissivity_ops = [_]riley.ResolverOp{
        .{ .load = param0 },
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .subtract,
        .{ .load = .{ .kind = .constant, .index = 1 } },
        .multiply,
        .clamp01,
        .{ .store = 0 },
    };

    const emissivity_pipe: riley.ShaderPipeInput = .{
        .stages = &emissivity_stages,
        .resolver = .{
            .expression = .{
                .operations = &emissivity_ops,
                .constants = &.{ 0.90, 1.0 / 0.06 },
            },
        },
    };

    mesh.shaders = .{ .mono_pipe = emissivity_pipe };

    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .mono,
        "./out/demo08_shaderpipe_gallery/d_emissivity_visualisation",
    );
    // -------------------------------------------------------------------------
    // 6. Composition E: RGB expression with one result per colour channel
    // -------------------------------------------------------------------------
    const rgb_expression_ops = [_]riley.ResolverOp{
        // R = clamp(0.65 * field0 + 0.35 * field1, 0, 1)
        .{ .load = field0 },
        .{ .load = .{ .kind = .constant, .index = 0 } },
        .multiply,
        .{ .load = field1 },
        .{ .load = .{ .kind = .constant, .index = 1 } },
        .multiply,
        .add,
        .clamp01,
        .{ .store = 0 },

        // G = clamp(field0 * field1, 0, 1)
        .{ .load = field0 },
        .{ .load = field1 },
        .multiply,
        .clamp01,
        .{ .store = 1 },

        // B = clamp(1 - field0, 0, 1)
        .{ .load = .{ .kind = .constant, .index = 2 } },
        .{ .load = field0 },
        .subtract,
        .clamp01,
        .{ .store = 2 },
    };
    const rgb_expression_pipe: riley.ShaderPipeInput = .{
        .stages = &expr_stages,
        .resolver = .{
            .expression = .{
                .operations = &rgb_expression_ops,
                .constants = &.{ 0.65, 0.35, 1.0 },
            },
        },
    };
    mesh.shaders = .{ .rgb_pipe = rgb_expression_pipe };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .rgb,
        "./out/demo08_shaderpipe_gallery/e_rgb_expression",
    );

    // -------------------------------------------------------------------------
    // 7. Composition F: Four-field expression outputs
    // -------------------------------------------------------------------------
    const multifield_expression_ops = [_]riley.ResolverOp{
        // Output 0: horizontal gradient
        .{ .load = field0 },
        .{ .store = 0 },

        // Output 1: vertical gradient
        .{ .load = field1 },
        .{ .store = 1 },

        // Output 2: product of the gradients
        .{ .load = field0 },
        .{ .load = field1 },
        .multiply,
        .{ .store = 2 },

        // Output 3: squared difference of the gradients
        .{ .load = field0 },
        .{ .load = field1 },
        .subtract,
        .{ .load = field0 },
        .{ .load = field1 },
        .subtract,
        .multiply,
        .{ .store = 3 },
    };
    const multifield_expression_pipe: riley.ShaderPipeInput = .{
        .stages = &expr_stages,
        .resolver = .{
            .expression = .{
                .operations = &multifield_expression_ops,
            },
        },
    };
    mesh.shaders = .{ .multifield_pipe = multifield_expression_pipe };
    try render(
        init.gpa,
        init.io,
        mesh,
        base_camera,
        .{ .multifield = 4 },
        "./out/demo08_shaderpipe_gallery/f_multifield_expression",
    );
}
