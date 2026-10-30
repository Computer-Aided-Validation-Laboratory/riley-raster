// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

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

pub const ScaleOver = enum { within_frames, over_frames };
pub const RenderFormat = union(enum) {
    mono,
    rgb,
    ir,
    multifield: u8,

    pub fn channels(self: @This()) u8 {
        return switch (self) {
            .mono, .ir => 1,
            .rgb => 3,
            .multifield => |count| count,
        };
    }
};

pub const GreyToEmissivityStage = shaderpipe.GreyToEmissivityStage;
pub const ClampStage = shaderpipe.ClampStage;
pub const AffineMapStage = shaderpipe.AffineMapStage;
pub const LUTMapStage = shaderpipe.LUTMapStage;
pub const BlendStage = shaderpipe.BlendStage;
pub const NormaliseStage = shaderpipe.NormaliseStage;

// Re-exports of function shader types and evaluation helpers from shaderfunc.zig
pub const FuncCoordMode = shaderfunc.FuncCoordMode;
pub const FuncShaderBuiltin = shaderfunc.FuncShaderBuiltin;
pub const FuncCoord = shaderfunc.FuncCoord;
pub const FuncCoordSIMD = shaderfunc.FuncCoordSIMD;
pub const ConstantParams = shaderfunc.ConstantParams;
pub const LinearParams = shaderfunc.LinearParams;
pub const QuadraticParams = shaderfunc.QuadraticParams;
pub const SinusoidalParams = shaderfunc.SinusoidalParams;
pub const CheckerParams = shaderfunc.CheckerParams;
pub const CheckerSmoothParams = shaderfunc.CheckerSmoothParams;
pub const LambertianParams = shaderfunc.LambertianParams;
pub const EggboxParams = shaderfunc.EggboxParams;
pub const FuncShaderParams = shaderfunc.FuncShaderParams;
pub const normFuncShaderParams = shaderfunc.normFuncShaderParams;
pub const applyFuncShaderCoordParams = shaderfunc.applyFuncShaderCoordParams;
pub const applyFuncShaderCoordParamsSIMD = shaderfunc.applyFuncShaderCoordParamsSIMD;
pub const cubicSmoothStep = shaderfunc.cubicSmoothStep;
pub const cubicSmoothStepSIMD = shaderfunc.cubicSmoothStepSIMD;
pub const evalFuncShaderBuiltinGreyNorm = shaderfunc.evalFuncShaderBuiltinGreyNorm;
pub const evalFuncShaderBuiltinRGBNorm = shaderfunc.evalFuncShaderBuiltinRGBNorm;

pub const NodalInput = struct {
    field: meshio.Field,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
};

pub fn TexInput(comptime Texture: type) type {
    return struct {
        uvs: ndarray.NDArray(F),
        tex: Texture,
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        output_gain: F = 1.0,
        output_offset: F = 0.0,
        scaling: imageops.ScaleStrategy = .none,
    };
}

pub const FuncInput = struct {
    uvs: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
};

pub const FuncChannel = struct {
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    scaling: imageops.ScaleStrategy = .none,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
};

pub const FuncMultiInput = struct {
    uvs: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    channels: []const FuncChannel,
};

pub const ShaderMonoInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(texops.TexDataFix(u8, 1)),
    tex_u16: TexInput(texops.TexDataFix(u16, 1)),
    tex_f: TexInput(texops.TexDataFix(F, 1)),
    func: FuncInput,
};

pub const FuncSourceInput = union(enum) {
    mono: FuncInput,
    rgb: FuncInput,
    multi: FuncMultiInput,
};

pub const PipeSourceInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(texops.TexDataFix(u8, 1)),
    tex_u16: TexInput(texops.TexDataFix(u16, 1)),
    tex_f: TexInput(texops.TexDataFix(F, 1)),
    tex_rgb_u8: TexInput(texops.TexDataFix(u8, 3)),
    tex_rgb_u16: TexInput(texops.TexDataFix(u16, 3)),
    tex_rgb_f: TexInput(texops.TexDataFix(F, 3)),
    tex_multi_u8: TexInput(texops.TexDataDyn(u8)),
    tex_multi_u16: TexInput(texops.TexDataDyn(u16)),
    tex_multi_f: TexInput(texops.TexDataDyn(F)),
    func: FuncSourceInput,
};

pub const ShaderPipeStageInput = union(enum) {
    source: struct { shader: PipeSourceInput, destination: shaderpipe.Slot },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
    affine_map: AffineMapStage,
    lut_map: LUTMapStage,
    blend: BlendStage,
    normalise: NormaliseStage,
};

pub const ShaderPipeInput = struct {
    stages: []const ShaderPipeStageInput,
    resolver: shaderpipe.Resolver,
    constants: []const F = &.{},
};

pub const MeshShaderSetInput = struct {
    mono_direct: ?ShaderMonoInput = null,
    mono_pipe: ?ShaderPipeInput = null,
    ir_direct: ?ShaderMonoInput = null,
    ir_pipe: ?ShaderPipeInput = null,
    rgb_pipe: ?ShaderPipeInput = null,
    multifield_pipe: ?ShaderPipeInput = null,
};

pub const NodalStatic = struct {
    field: meshio.Field,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    global_scaling: ?imageops.ScalingParams = null,
};

pub fn TexStatic(comptime T: type, comptime C: usize) type {
    return texStaticType(T, C);
}

pub fn TexMultiStatic(comptime T: type) type {
    return texStaticType(T, null);
}

fn texStaticType(comptime T: type, comptime C: ?usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: if (C) |channels| texops.TexDataFix(T, channels) else texops.TexDataDyn(T),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        output_gain: F = 1.0,
        output_offset: F = 0.0,
        scaling: imageops.ScaleStrategy = .none,
    };
}

pub const FuncStatic = struct {
    elem_uvs: ?ndarray.NDArray(F),
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin = .constant,
    params: FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    channels: []const FuncChannel = &.{},
};

pub const ShaderMonoStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_f: TexStatic(F, 1),
    func: FuncStatic,
};

pub const FuncSourceStatic = union(enum) {
    mono: FuncStatic,
    rgb: FuncStatic,
    multi: FuncStatic,
};

pub const PipeSourceStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_f: TexStatic(F, 1),
    tex_rgb_u8: TexStatic(u8, 3),
    tex_rgb_u16: TexStatic(u16, 3),
    tex_rgb_f: TexStatic(F, 3),
    tex_multi_f: TexMultiStatic(F),
    func: FuncSourceStatic,
};

pub const ShaderPipeStageStatic = union(enum) {
    source: struct {
        shader: PipeSourceStatic,
        destination: shaderpipe.Slot,
        global_scaling: ?imageops.ScalingParams = null,
    },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
    affine_map: AffineMapStage,
    lut_map: LUTMapStage,
    blend: BlendStage,
    normalise: NormaliseStage,
};

pub const ShaderPipeStatic = struct {
    stages: []const ShaderPipeStageStatic,
    resolver: shaderpipe.Resolver,
    constants: []const F,
};

pub const ShaderMonoExecutionStatic = union(enum) {
    direct: ShaderMonoStatic,
    pipe: ShaderPipeStatic,
};

pub const ShaderExecutionStatic = ShaderMonoExecutionStatic;

pub const MeshShaderSetStatic = struct {
    mono: ?ShaderMonoExecutionStatic = null,
    ir: ?ShaderMonoExecutionStatic = null,
    rgb: ?ShaderPipeStatic = null,
    multifield: ?ShaderPipeStatic = null,
};

pub const NodalPrepared = struct {
    elem_field: ndarray.NDArray(F),
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
};

pub fn TexPrepared(comptime T: type, comptime C: usize) type {
    return texPreparedType(T, C);
}

pub fn TexMultiPrepared(comptime T: type) type {
    return texPreparedType(T, null);
}

fn texPreparedType(comptime T: type, comptime C: ?usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: if (C) |channels| texops.TexDataFix(T, channels) else texops.TexDataDyn(T),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        output_gain: F = 1.0,
        output_offset: F = 0.0,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: F = 1.0,
        scale_add: F = 0.0,
    };
}

pub fn concreteTexture(
    comptime T: type,
    comptime C: usize,
    dynamic: *const TexMultiPrepared(T),
) TexPrepared(T, C) {
    return .{
        .elem_uvs = dynamic.elem_uvs,
        .tex = .{
            .array = dynamic.tex.array,
            .rows_num = dynamic.tex.rows_num,
            .cols_num = dynamic.tex.cols_num,
        },
        .samp_cfg = dynamic.samp_cfg,
        .output_gain = dynamic.output_gain,
        .output_offset = dynamic.output_offset,
        .scaling = dynamic.scaling,
        .scale_mul = dynamic.scale_mul,
        .scale_add = dynamic.scale_add,
    };
}

pub const FuncPrepared = struct {
    elem_uvs: ?ndarray.NDArray(F),
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin = .constant,
    params: FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    needs_normal: bool = false,
    channels: []const FuncChannelPrepared = &.{},
};

pub const FuncChannelPrepared = struct {
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams,
    scale_mul: F,
    scale_add: F,
};

pub const ShaderMonoPrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_f: TexPrepared(F, 1),
    func: FuncPrepared,
};

pub const FuncSourcePrepared = union(enum) {
    mono: FuncPrepared,
    rgb: FuncPrepared,
    multi: FuncPrepared,
};

pub const PipeSourcePrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_f: TexPrepared(F, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
    tex_rgb_f: TexPrepared(F, 3),
    tex_multi_f: TexMultiPrepared(F),
    func: FuncSourcePrepared,
};

pub const ShaderPipeStagePrepared = union(enum) {
    source: struct { shader: PipeSourcePrepared, destination: shaderpipe.Slot },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
    affine_map: AffineMapStage,
    lut_map: LUTMapStage,
    blend: BlendStage,
    normalise: NormaliseStage,
};

pub const ShaderPipePrepared = struct {
    stages: []const ShaderPipeStagePrepared,
    resolver: shaderpipe.Resolver,
    constants: []const F,
    channels: u8,
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
};

pub const ShaderMonoExecutionPrepared = union(enum) {
    direct: ShaderMonoPrepared,
    pipe: ShaderPipePrepared,
};

pub const ShaderExecutionPrepared = ShaderMonoExecutionPrepared;

pub const MeshShaderSetPrepared = struct {
    mono: ?ShaderMonoExecutionPrepared = null,
    ir: ?ShaderMonoExecutionPrepared = null,
    rgb: ?ShaderPipePrepared = null,
    multifield: ?ShaderPipePrepared = null,
};

pub fn SelectedShader(comptime Direct: type, comptime Pipe: type) type {
    return union(enum) {
        direct: *const Direct,
        pipe: *const Pipe,
    };
}

pub fn LocalShaderBuff(comptime N: usize) type {
    return struct {
        data: [cfg.max_nodal_fields * N]F = undefined,
        func_coords: [3 * N]F = undefined,
        normals: [3 * N]F = undefined,
        actual_fields: u8 = 0,
        actual_func_coords: u8 = 0,

        const Self = @This();

        pub inline fn load(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
            fields_num: u8,
        ) void {
            std.debug.assert(fields_num <= cfg.max_nodal_fields);
            self.actual_fields = fields_num;
            const count = @as(usize, fields_num) * N;
            @memcpy(self.data[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn loadNormals(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
        ) void {
            const count = 3 * N;
            @memcpy(self.normals[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn loadFuncCoords(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
            coords_num: u8,
        ) void {
            std.debug.assert(coords_num <= 3);
            self.actual_func_coords = coords_num;
            const count = @as(usize, coords_num) * N;
            @memcpy(
                self.func_coords[0..count],
                array.slice[start_idx .. start_idx + count],
            );
        }

        pub inline fn interp(
            self: *const Self,
            field_idx: usize,
            weights: [N]F,
        ) F {
            const base = field_idx * N;
            var sum: F = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.data[base + nn];
            }
            return sum;
        }

        pub inline fn interpNormal(
            self: *const Self,
            weights: [N]F,
        ) [3]F {
            var norm = [3]F{ 0.0, 0.0, 0.0 };
            inline for (0..N) |nn| {
                norm[0] += weights[nn] * self.normals[0 * N + nn];
                norm[1] += weights[nn] * self.normals[1 * N + nn];
                norm[2] += weights[nn] * self.normals[2 * N + nn];
            }
            return norm;
        }

        pub inline fn interpFuncCoord(
            self: *const Self,
            coord_idx: usize,
            weights: [N]F,
        ) F {
            const base = coord_idx * N;
            var sum: F = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.func_coords[base + nn];
            }
            return sum;
        }
    };
}

pub const ShadeContext = struct {
    frame_idx: usize,
    elem_idx: usize,
    fields_num: u8,
    actual_fields: u8,
    scratch_idx: usize,
    global_subx: usize,
    global_suby: usize,
    v_mask_active: ?VecSB = null,
    exclusive_subpx_target: bool = false,
};
