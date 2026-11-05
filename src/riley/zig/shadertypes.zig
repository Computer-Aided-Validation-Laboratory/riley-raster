// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const shaderfunc = @import("shaderfunc.zig");
const std = @import("std");

const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const F = buildconfig.F;
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;

const ndarray = @import("ndarray.zig");

const imageops = @import("imageops.zig");
const texturetypes = @import("texturetypes.zig");
const fieldtypes = @import("fieldtypes.zig");
const shaderpipe = @import("shaderpipe.zig");
const meshhit = @import("meshhit.zig");

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

/// Shader role independent of output channel count.
pub const RenderRole = std.meta.Tag(RenderFormat);
pub const ActiveShaderRoles = std.EnumSet(RenderRole);

pub const NodalInput = struct {
    field: fieldtypes.Field,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
};

pub fn TexInput(comptime Texture: type) type {
    return struct {
        uvs: ndarray.NDArray(F),
        tex: Texture,
        samp_cfg: texturetypes.TexSampConfig = .{
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
    coord_mode: shaderfunc.FuncCoordMode = .para,
    builtin: shaderfunc.FuncShaderBuiltin,
    params: shaderfunc.FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
};

pub const FuncChannel = struct {
    builtin: shaderfunc.FuncShaderBuiltin,
    params: shaderfunc.FuncShaderParams = .{},
    scaling: imageops.ScaleStrategy = .none,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
};

pub const FuncMultiInput = struct {
    uvs: ?ndarray.NDArray(F) = null,
    coord_mode: shaderfunc.FuncCoordMode = .para,
    channels: []const FuncChannel,
};

pub const ShaderMonoInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(texturetypes.TexDataFix(u8, 1)),
    tex_u16: TexInput(texturetypes.TexDataFix(u16, 1)),
    tex_f: TexInput(texturetypes.TexDataFix(F, 1)),
    func: FuncInput,
};

pub const PipeSourceInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(texturetypes.TexDataFix(u8, 1)),
    tex_u16: TexInput(texturetypes.TexDataFix(u16, 1)),
    tex_f: TexInput(texturetypes.TexDataFix(F, 1)),
    tex_rgb_u8: TexInput(texturetypes.TexDataFix(u8, 3)),
    tex_rgb_u16: TexInput(texturetypes.TexDataFix(u16, 3)),
    tex_rgb_f: TexInput(texturetypes.TexDataFix(F, 3)),
    tex_multi_u8: TexInput(texturetypes.TexDataDyn(u8)),
    tex_multi_u16: TexInput(texturetypes.TexDataDyn(u16)),
    tex_multi_f: TexInput(texturetypes.TexDataDyn(F)),
    func: FuncInput,
    func_rgb: FuncInput,
    func_multi: FuncMultiInput,
};

pub const ShaderPipeStageInput = union(enum) {
    shader: struct { shader: PipeSourceInput, register_dest: shaderpipe.Register },
    grey_to_emissivity: shaderpipe.GreyToEmissivityStage,
    clamp: shaderpipe.ClampStage,
    affine_map: shaderpipe.AffineMapStage,
    lut_map: shaderpipe.LUTMapStage,
    blend: shaderpipe.BlendStage,
    normalise: shaderpipe.NormaliseStage,
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
    field: fieldtypes.Field,
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
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
        tex: if (C) |channels| texturetypes.TexDataFix(T, channels) else texturetypes.TexDataDyn(T),
        samp_cfg: texturetypes.TexSampConfig = .{
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

pub const FuncStatic = struct {
    elem_uvs: ?ndarray.NDArray(F),
    coord_mode: shaderfunc.FuncCoordMode = .para,
    builtin: shaderfunc.FuncShaderBuiltin = .constant,
    params: shaderfunc.FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    needs_normal: bool = false,
    channels: []const FuncChannelPrepared = &.{},
};

pub const ShaderMonoStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_f: TexStatic(F, 1),
    func: FuncStatic,
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
    func: FuncStatic,
    func_rgb: FuncStatic,
    func_multi: FuncStatic,
};

pub const GreyToEmissivityPrepared = struct {
    register_source: shaderpipe.Register,
    register_dest: shaderpipe.Register,
    emissivity_at_black: F,
    emissivity_range: F,
    greylevel_at_black: F,
    greylevel_range: F,

    pub fn init(value: shaderpipe.GreyToEmissivityStage) GreyToEmissivityPrepared {
        return .{
            .register_source = value.register_source,
            .register_dest = value.register_dest,
            .emissivity_at_black = value.emissivity_at_black,
            .emissivity_range = value.emissivity_at_white - value.emissivity_at_black,
            .greylevel_at_black = value.greylevel_at_black,
            .greylevel_range = value.greylevel_at_white - value.greylevel_at_black,
        };
    }
};

pub const BlendPrepared = struct {
    a: shaderpipe.Register,
    b: shaderpipe.Register,
    register_dest: shaderpipe.Register,
    alpha: shaderpipe.BlendWeight,
    fixed_complement: F,

    pub fn init(value: shaderpipe.BlendStage) BlendPrepared {
        return .{
            .a = value.a,
            .b = value.b,
            .register_dest = value.register_dest,
            .alpha = value.alpha,
            .fixed_complement = switch (value.alpha) {
                .fixed => |a| 1 - a,
                .register => 0,
            },
        };
    }

    pub inline fn apply(self: BlendPrepared, outputs: anytype) void {
        const T = @TypeOf(outputs.get(self.a));
        const alpha: T = switch (self.alpha) {
            .fixed => |v| if (T == F) v else @splat(v),
            .register => |register_ref| outputs.get(register_ref),
        };
        const complement: T = switch (self.alpha) {
            .fixed => if (T == F) self.fixed_complement else @splat(self.fixed_complement),
            .register => (if (T == F) @as(F, 1) else @as(T, @splat(1))) - alpha,
        };
        outputs.set(self.register_dest, complement * outputs.get(self.a) + alpha * outputs.get(self.b));
    }
};

pub const LUTMapPrepared = struct {
    register_source: shaderpipe.Register,
    register_dest: shaderpipe.Register,
    lookup: shaderpipe.LookupTablePrepared,

    pub fn init(value: shaderpipe.LUTMapStage) LUTMapPrepared {
        return .{
            .register_source = value.register_source,
            .register_dest = value.register_dest,
            .lookup = shaderpipe.LookupTablePrepared.init(value.lookup),
        };
    }

    pub inline fn apply(self: LUTMapPrepared, outputs: anytype, active: anytype) void {
        const T = @TypeOf(outputs.get(self.register_source));
        if (T == F) {
            outputs.set(self.register_dest, self.lookup.sample(outputs.get(self.register_source)));
        } else {
            outputs.set(self.register_dest, self.lookup.sampleSIMD(
                outputs.get(self.register_source),
                active,
            ));
        }
    }
};

pub const ShaderPipeStageStatic = union(enum) {
    shader: struct {
        shader: PipeSourceStatic,
        register_dest: shaderpipe.Register,
        channels: u8 = 1,
    },
    grey_to_emissivity: GreyToEmissivityPrepared,
    clamp: shaderpipe.ClampStage,
    affine_map: shaderpipe.AffineMapStage,
    lut_map: LUTMapPrepared,
    blend: BlendPrepared,
    normalise: shaderpipe.NormaliseStage,
};

pub const ShaderPipeStatic = struct {
    stages: []const ShaderPipeStageStatic,
    resolver: shaderpipe.ResolverPrepared,
    constants: []const F,
};

pub const ShaderExecutionStatic = union(enum) {
    direct: ShaderMonoStatic,
    pipe: ShaderPipeStatic,
};

pub const MeshShaderSetStatic = struct {
    mono: ?ShaderExecutionStatic = null,
    ir: ?ShaderExecutionStatic = null,
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
        tex: if (C) |channels| texturetypes.TexDataFix(T, channels) else texturetypes.TexDataDyn(T),
        samp_cfg: texturetypes.TexSampConfig = .{
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
    coord_mode: shaderfunc.FuncCoordMode = .para,
    builtin: shaderfunc.FuncShaderBuiltin = .constant,
    params: shaderfunc.FuncShaderParams = .{},
    output_gain: F = 1.0,
    output_offset: F = 0.0,
    scaling: imageops.ScaleStrategy = .none,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    needs_normal: bool = false,
    channels: []const FuncChannelPrepared = &.{},
};

pub const FuncChannelPrepared = struct {
    builtin: shaderfunc.FuncShaderBuiltin,
    params: shaderfunc.FuncShaderParams,
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

pub const PipeSourcePrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_f: TexPrepared(F, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
    tex_rgb_f: TexPrepared(F, 3),
    tex_multi_f: TexMultiPrepared(F),
    func: FuncPrepared,
    func_rgb: FuncPrepared,
    func_multi: FuncPrepared,
};

pub const ShaderPipeStagePrepared = union(enum) {
    shader: struct { shader: PipeSourcePrepared, register_dest: shaderpipe.Register, channels: u8 = 1 },
    grey_to_emissivity: GreyToEmissivityPrepared,
    clamp: shaderpipe.ClampStage,
    affine_map: shaderpipe.AffineMapStage,
    lut_map: LUTMapPrepared,
    blend: BlendPrepared,
    normalise: shaderpipe.NormaliseStage,
};

pub const ShaderPipePrepared = struct {
    stages: []const ShaderPipeStagePrepared,
    resolver: shaderpipe.ResolverPrepared,
    constants: []const F,
    channels: u8,
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
};

pub const ShaderExecutionPrepared = union(enum) {
    direct: ShaderMonoPrepared,
    pipe: ShaderPipePrepared,
};

pub const MeshShaderSetPrepared = struct {
    mono: ?ShaderExecutionPrepared = null,
    ir: ?ShaderExecutionPrepared = null,
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
    // Full-vector stores rewrite inactive lanes; safe only when those lanes are private.
    simd_full_vector_store_safe: bool = true,
};
