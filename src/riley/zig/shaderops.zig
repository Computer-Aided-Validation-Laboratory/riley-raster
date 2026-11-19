// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const shadertypes = @import("shadertypes.zig");

const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;

const texturetypes = @import("texturetypes.zig");
const shaderpipe = @import("shaderpipe.zig");

// --------------------------------------------------------------------------------------
// Stage 1: Input
// --------------------------------------------------------------------------------------
// Input: Raw user shader data for all frames.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Node-order [total_nodes, 2]

pub fn stageSource(source: shadertypes.PipeSourceInput) shadertypes.ShaderPipeStageInput {
    return .{
        .shader = .{
            .shader = source,
            .register_dest = .{ .kind = .channel, .index = 0 },
        },
    };
}

pub fn identityRGB(
    source: shadertypes.PipeSourceInput,
    stage_buf: *[1]shadertypes.ShaderPipeStageInput,
) shadertypes.ShaderPipeInput {
    stage_buf[0] = stageSource(source);
    return .{
        .stages = stage_buf,
        .resolver = .{ .identity = shaderpipe.identity_channels_3 },
    };
}

pub fn identityMulti(
    channels: u8,
    source: shadertypes.PipeSourceInput,
    stage_buf: *[1]shadertypes.ShaderPipeStageInput,
) shadertypes.ShaderPipeInput {
    stage_buf[0] = stageSource(source);
    return .{
        .stages = stage_buf,
        .resolver = .{ .identity = shaderpipe.identityRegisters(channels) },
    };
}

pub fn monoToPipeSource(mono: shadertypes.ShaderMonoInput) shadertypes.PipeSourceInput {
    return switch (mono) {
        .tex_u8 => |t| .{ .tex_u8 = t },
        .tex_u16 => |t| .{ .tex_u16 = t },
        .tex_f => |t| .{ .tex_f = t },
        .nodal => |n| .{ .nodal = n },
        .func => |f| .{ .func = f },
    };
}

pub fn pipeSourceToMono(source: shadertypes.PipeSourceInput) !shadertypes.ShaderMonoInput {
    return switch (source) {
        .tex_u8 => |t| .{ .tex_u8 = t },
        .tex_u16 => |t| .{ .tex_u16 = t },
        .tex_f => |t| .{ .tex_f = t },
        .nodal => |n| .{ .nodal = n },
        .func => |f| .{ .func = f },
        .func_rgb => error.DirectMonoFuncRequiresMono,
        .func_multi => error.DirectMonoFuncRequiresMono,
        else => error.DirectMonoShaderExpectedMono,
    };
}

pub fn hasShader(shaders: anytype, format: shadertypes.RenderFormat) bool {
    if (comptime @TypeOf(shaders) == shadertypes.MeshShaderSetInput) {
        return switch (format) {
            .mono => shaders.mono_direct != null or shaders.mono_pipe != null,
            .ir => shaders.ir_direct != null or shaders.ir_pipe != null,
            .rgb => shaders.rgb_pipe != null,
            .multifield => shaders.multifield_pipe != null,
        };
    }
    return switch (format) {
        .mono => shaders.mono != null,
        .ir => shaders.ir != null,
        .rgb => shaders.rgb != null,
        .multifield => shaders.multifield != null,
    };
}

pub fn selectShader(
    comptime Direct: type,
    comptime Pipe: type,
    shaders: anytype,
    role: shadertypes.RenderRole,
) ?shadertypes.SelectedShader(Direct, Pipe) {
    if (comptime @TypeOf(shaders.*) == shadertypes.MeshShaderSetInput) {
        return switch (role) {
            .mono => if (shaders.mono_direct) |*shader| .{ .direct = shader } else if (shaders.mono_pipe) |*pipe| .{ .pipe = pipe } else null,
            .ir => if (shaders.ir_direct) |*shader| .{ .direct = shader } else if (shaders.ir_pipe) |*pipe| .{ .pipe = pipe } else null,
            .rgb => if (shaders.rgb_pipe) |*pipe| .{ .pipe = pipe } else null,
            .multifield => if (shaders.multifield_pipe) |*pipe| .{ .pipe = pipe } else null,
        };
    }
    return switch (role) {
        .mono => if (shaders.mono) |*exec| switch (exec.*) {
            .direct => |*shader| .{ .direct = shader },
            .pipe => |*pipe| .{ .pipe = pipe },
        } else null,
        .ir => if (shaders.ir) |*exec| switch (exec.*) {
            .direct => |*shader| .{ .direct = shader },
            .pipe => |*pipe| .{ .pipe = pipe },
        } else null,
        .rgb => if (shaders.rgb) |*pipe|
            .{ .pipe = pipe }
        else
            null,
        .multifield => if (shaders.multifield) |*pipe|
            .{ .pipe = pipe }
        else
            null,
    };
}

// --------------------------------------------------------------------------------------
// Rasterisation Runtime Context & Buffers
// --------------------------------------------------------------------------------------

// Local buffer for hoisting element shader data into cache once per element before we
// enter the sub-pixel raster loop.

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "texture input defaults to direct evaluation mode" {
    const ti_cfg = (shadertypes.TexInput(texturetypes.TexDataFix(u8, 1)){
        .uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try std.testing.expectEqual(texturetypes.TexSampMode.direct, ti_cfg.mode);

    const ts_cfg = (shadertypes.TexStatic(u8, 1){
        .elem_uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try std.testing.expectEqual(texturetypes.TexSampMode.direct, ts_cfg.mode);

    const tp_cfg = (shadertypes.TexPrepared(u8, 1){
        .elem_uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try std.testing.expectEqual(texturetypes.TexSampMode.direct, tp_cfg.mode);
}
