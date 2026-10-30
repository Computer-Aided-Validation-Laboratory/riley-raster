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
const cfg = buildconfig.config;
const F = buildconfig.F;
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

const imageops = @import("imageops.zig");
const texops = @import("textureops.zig");
const meshio = @import("meshio.zig");
const shaderpipe = @import("shaderpipe.zig");
const meshhit = @import("meshhit.zig");
pub const shaderfunc = @import("shaderfunc.zig");

// --------------------------------------------------------------------------------------
// Common Enums & Shared Pipe Stages
// --------------------------------------------------------------------------------------

const ScaleOver = shadertypes.ScaleOver;
const RenderFormat = shadertypes.RenderFormat;
const GreyToEmissivityStage = shadertypes.GreyToEmissivityStage;
const ClampStage = shadertypes.ClampStage;
const AffineMapStage = shadertypes.AffineMapStage;
const LUTMapStage = shadertypes.LUTMapStage;
const BlendStage = shadertypes.BlendStage;
const NormaliseStage = shadertypes.NormaliseStage;
const FuncCoordMode = shadertypes.FuncCoordMode;
const FuncShaderBuiltin = shadertypes.FuncShaderBuiltin;
const FuncCoord = shadertypes.FuncCoord;
const FuncCoordSIMD = shadertypes.FuncCoordSIMD;
const ConstantParams = shadertypes.ConstantParams;
const LinearParams = shadertypes.LinearParams;
const QuadraticParams = shadertypes.QuadraticParams;
const SinusoidalParams = shadertypes.SinusoidalParams;
const CheckerParams = shadertypes.CheckerParams;
const CheckerSmoothParams = shadertypes.CheckerSmoothParams;
const LambertianParams = shadertypes.LambertianParams;
const EggboxParams = shadertypes.EggboxParams;
const FuncShaderParams = shadertypes.FuncShaderParams;
const normFuncShaderParams = shadertypes.normFuncShaderParams;
const applyFuncShaderCoordParams = shadertypes.applyFuncShaderCoordParams;
const applyFuncShaderCoordParamsSIMD = shadertypes.applyFuncShaderCoordParamsSIMD;
const cubicSmoothStep = shadertypes.cubicSmoothStep;
const cubicSmoothStepSIMD = shadertypes.cubicSmoothStepSIMD;
const evalFuncShaderBuiltinGreyNorm = shadertypes.evalFuncShaderBuiltinGreyNorm;
const evalFuncShaderBuiltinRGBNorm = shadertypes.evalFuncShaderBuiltinRGBNorm;

// --------------------------------------------------------------------------------------
// Stage 1: Input
// --------------------------------------------------------------------------------------
// Input: Raw user shader data for all frames.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Node-order [total_nodes, 2]

const NodalInput = shadertypes.NodalInput;
const TexInput = shadertypes.TexInput;
const FuncInput = shadertypes.FuncInput;
const FuncChannel = shadertypes.FuncChannel;
const FuncMultiInput = shadertypes.FuncMultiInput;
const ShaderMonoInput = shadertypes.ShaderMonoInput;
const FuncSourceInput = shadertypes.FuncSourceInput;
const PipeSourceInput = shadertypes.PipeSourceInput;
const ShaderPipeStageInput = shadertypes.ShaderPipeStageInput;
const ShaderPipeInput = shadertypes.ShaderPipeInput;
const MeshShaderSetInput = shadertypes.MeshShaderSetInput;

pub fn stageSource(source: PipeSourceInput) ShaderPipeStageInput {
    return .{
        .source = .{
            .shader = source,
            .destination = .{ .kind = .channel, .index = 0 },
        },
    };
}

pub fn identityRGB(
    source: PipeSourceInput,
    stage_buf: *[1]ShaderPipeStageInput,
) ShaderPipeInput {
    stage_buf[0] = stageSource(source);
    return .{
        .stages = stage_buf,
        .resolver = .{ .identity = shaderpipe.identity_channels_3 },
    };
}

pub fn identityMulti(
    channels: u8,
    source: PipeSourceInput,
    stage_buf: *[1]ShaderPipeStageInput,
) ShaderPipeInput {
    stage_buf[0] = stageSource(source);
    return .{
        .stages = stage_buf,
        .resolver = .{ .identity = shaderpipe.identitySlots(channels) },
    };
}

pub fn monoToPipeSource(mono: ShaderMonoInput) PipeSourceInput {
    return switch (mono) {
        .tex_u8 => |t| .{ .tex_u8 = t },
        .tex_u16 => |t| .{ .tex_u16 = t },
        .tex_f => |t| .{ .tex_f = t },
        .nodal => |n| .{ .nodal = n },
        .func => |f| .{ .func = .{ .mono = f } },
    };
}

pub fn pipeSourceToMono(source: PipeSourceInput) !ShaderMonoInput {
    return switch (source) {
        .tex_u8 => |t| .{ .tex_u8 = t },
        .tex_u16 => |t| .{ .tex_u16 = t },
        .tex_f => |t| .{ .tex_f = t },
        .nodal => |n| .{ .nodal = n },
        .func => |f| switch (f) {
            .mono => |m| .{ .func = m },
            .rgb => error.DirectMonoFuncRequiresMono,
        },
        else => error.DirectMonoShaderExpectedMono,
    };
}

// --------------------------------------------------------------------------------------
// Stage 2: Static
// --------------------------------------------------------------------------------------
// Static: Persistent multi-frame shader resources in engine memory.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Elem-order [total_elems, 2, nodes_per_elem]

const NodalStatic = shadertypes.NodalStatic;
const TexStatic = shadertypes.TexStatic;
const TexMultiStatic = shadertypes.TexMultiStatic;
const FuncStatic = shadertypes.FuncStatic;
const ShaderMonoStatic = shadertypes.ShaderMonoStatic;
const FuncSourceStatic = shadertypes.FuncSourceStatic;
const PipeSourceStatic = shadertypes.PipeSourceStatic;
const ShaderPipeStageStatic = shadertypes.ShaderPipeStageStatic;
const ShaderPipeStatic = shadertypes.ShaderPipeStatic;
const ShaderMonoExecutionStatic = shadertypes.ShaderMonoExecutionStatic;
const ShaderExecutionStatic = shadertypes.ShaderExecutionStatic;
const MeshShaderSetStatic = shadertypes.MeshShaderSetStatic;

// --------------------------------------------------------------------------------------
// Stage 3: Prepared
// --------------------------------------------------------------------------------------
// Prep: Culled and expanded shader data for a SINGLE frame.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
// Nodal Fields: Elem-order [vis_elems, num_fields, nodes_per_elem]
// UVs: Elem-order [vis_elems, 2, nodes_per_elem]

const NodalPrepared = shadertypes.NodalPrepared;
const TexPrepared = shadertypes.TexPrepared;
const TexMultiPrepared = shadertypes.TexMultiPrepared;
const concreteTexture = shadertypes.concreteTexture;
const FuncPrepared = shadertypes.FuncPrepared;
const FuncChannelPrepared = shadertypes.FuncChannelPrepared;
const ShaderMonoPrepared = shadertypes.ShaderMonoPrepared;
const FuncSourcePrepared = shadertypes.FuncSourcePrepared;
const PipeSourcePrepared = shadertypes.PipeSourcePrepared;
const ShaderPipeStagePrepared = shadertypes.ShaderPipeStagePrepared;
const ShaderPipePrepared = shadertypes.ShaderPipePrepared;
const ShaderMonoExecutionPrepared = shadertypes.ShaderMonoExecutionPrepared;
const ShaderExecutionPrepared = shadertypes.ShaderExecutionPrepared;
const MeshShaderSetPrepared = shadertypes.MeshShaderSetPrepared;

// --------------------------------------------------------------------------------------
// MeshShaderSet Operations & Camera Selection
// --------------------------------------------------------------------------------------

const SelectedShader = shadertypes.SelectedShader;

pub fn hasShader(shaders: anytype, format: RenderFormat) bool {
    if (comptime @TypeOf(shaders) == MeshShaderSetInput) {
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
    format: RenderFormat,
) ?SelectedShader(Direct, Pipe) {
    if (comptime @TypeOf(shaders.*) == MeshShaderSetInput) {
        return switch (format) {
            .mono => if (shaders.mono_direct) |*shader| .{ .direct = shader } else if (shaders.mono_pipe) |*pipe| .{ .pipe = pipe } else null,
            .ir => if (shaders.ir_direct) |*shader| .{ .direct = shader } else if (shaders.ir_pipe) |*pipe| .{ .pipe = pipe } else null,
            .rgb => if (shaders.rgb_pipe) |*pipe| .{ .pipe = pipe } else null,
            .multifield => if (shaders.multifield_pipe) |*pipe| .{ .pipe = pipe } else null,
        };
    }
    return switch (format) {
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
const LocalShaderBuff = shadertypes.LocalShaderBuff;
const ShadeContext = shadertypes.ShadeContext;

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

const testing = std.testing;

test "texture input defaults to direct evaluation mode" {
    const ti_cfg = (TexInput(texops.TexDataFix(u8, 1)){
        .uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try testing.expectEqual(texops.TexSampMode.direct, ti_cfg.mode);

    const ts_cfg = (TexStatic(u8, 1){
        .elem_uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try testing.expectEqual(texops.TexSampMode.direct, ts_cfg.mode);

    const tp_cfg = (TexPrepared(u8, 1){
        .elem_uvs = undefined,
        .tex = undefined,
    }).samp_cfg;
    try testing.expectEqual(texops.TexSampMode.direct, tp_cfg.mode);
}
