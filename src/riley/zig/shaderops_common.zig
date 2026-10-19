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
const VecSB = buildconfig.VecSB;

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

const imageops = @import("imageops.zig");
const texops = @import("textureops.zig");
const meshio = @import("meshio.zig");
const shaderpipe = @import("shaderpipe.zig");
pub const shaderfunc = @import("shaderfunc.zig");

// --------------------------------------------------------------------------------------
// Common Enums & Shared Pipe Stages
// --------------------------------------------------------------------------------------

pub const ScaleOver = enum { within_frames, over_frames };
pub const NormalType = enum { none, exact, avg };
pub const ShaderSelection = enum(u8) { direct, mono, rgb, ir, multifield };

pub const GreyToEmissivityStage = shaderpipe.GreyToEmissivityStage;
pub const ClampStage = shaderpipe.ClampStage;

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
pub const applyFuncShaderOutputParams = shaderfunc.applyFuncShaderOutputParams;
pub const applyFuncShaderOutputParamsSIMD = shaderfunc.applyFuncShaderOutputParamsSIMD;
pub const cubicSmoothStep = shaderfunc.cubicSmoothStep;
pub const cubicSmoothStepSIMD = shaderfunc.cubicSmoothStepSIMD;
pub const evalFuncShaderBuiltinGreyNorm = shaderfunc.evalFuncShaderBuiltinGreyNorm;
pub const evalFuncShaderBuiltinRGBNorm = shaderfunc.evalFuncShaderBuiltinRGBNorm;

// --------------------------------------------------------------------------------------
// Stage 1: Input
// --------------------------------------------------------------------------------------

// Input: Raw user shader data for all frames.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Node-order [total_nodes, 2]
pub const NodalInput = struct {
    field: meshio.Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub fn TexInput(comptime T: type, comptime C: usize) type {
    return struct {
        uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const FuncInput = struct {
    uvs: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    normal_type: NormalType = .none,
};

pub const ShaderDirectInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(u8, 1),
    tex_u16: TexInput(u16, 1),
    tex_f: TexInput(F, 1),
    tex_rgb_u8: TexInput(u8, 3),
    tex_rgb_u16: TexInput(u16, 3),
    tex_rgb_f: TexInput(F, 3),
    func: FuncInput,
    func_rgb: FuncInput,
};

pub const ShaderPipeStageInput = union(enum) {
    source: struct { shader: ShaderDirectInput, destination: shaderpipe.Slot },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
};

pub const ShaderPipeInput = struct {
    stages: []const ShaderPipeStageInput,
    resolver: shaderpipe.Resolver,
    constants: []const F = &.{},
    channels: u8 = 0,
};

pub const ShaderSetInput = struct {
    direct: ?ShaderDirectInput = null,
    mono: ?ShaderPipeInput = null,
    rgb: ?ShaderPipeInput = null,
    ir: ?ShaderPipeInput = null,
    multifield: ?ShaderPipeInput = null,
};

// --------------------------------------------------------------------------------------
// Stage 2: Static
// --------------------------------------------------------------------------------------

// Static: Persistent multi-frame shader resources in engine memory.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Elem-order [total_elems, 2, nodes_per_elem]
pub const NodalStatic = struct {
    field: meshio.Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub fn TexStatic(comptime T: type, comptime C: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const FuncStatic = struct {
    elem_uvs: ?ndarray.NDArray(F),
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub const ShaderDirectStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_f: TexStatic(F, 1),
    tex_rgb_u8: TexStatic(u8, 3),
    tex_rgb_u16: TexStatic(u16, 3),
    tex_rgb_f: TexStatic(F, 3),
    func: FuncStatic,
    func_rgb: FuncStatic,
};

pub const ShaderPipeStageStatic = union(enum) {
    source: struct {
        shader: ShaderDirectStatic,
        destination: shaderpipe.Slot,
        global_scaling: ?imageops.ScalingParams = null,
    },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
};

pub const ShaderPipeStatic = struct {
    stages: []const ShaderPipeStageStatic,
    resolver: shaderpipe.Resolver,
    constants: []const F,
    channels: u8,
};

pub const ShaderSetStatic = struct {
    direct: ?ShaderDirectStatic = null,
    mono: ?ShaderPipeStatic = null,
    rgb: ?ShaderPipeStatic = null,
    ir: ?ShaderPipeStatic = null,
    multifield: ?ShaderPipeStatic = null,
};

// --------------------------------------------------------------------------------------
// Stage 3: Prepared
// --------------------------------------------------------------------------------------

// Prep: Culled and expanded shader data for a SINGLE frame.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
// Nodal Fields: Elem-order [vis_elems, num_fields, nodes_per_elem]
// UVs: Elem-order [vis_elems, 2, nodes_per_elem]
pub const NodalPrepared = struct {
    elem_field: ndarray.NDArray(F),
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?ndarray.MappedNDArray(F) = null,
};

pub fn TexPrepared(comptime T: type, comptime C: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .direct,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: F = 1.0,
        scale_add: F = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(F) = null,
    };
}

pub const FuncPrepared = struct {
    elem_uvs: ?ndarray.NDArray(F),
    elem_world_ref: ?ndarray.NDArray(F) = null,
    elem_world_def: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?ndarray.MappedNDArray(F) = null,
};

pub const ShaderDirectPrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_f: TexPrepared(F, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
    tex_rgb_f: TexPrepared(F, 3),
    func: FuncPrepared,
    func_rgb: FuncPrepared,
};

pub const ShaderPipeStagePrepared = union(enum) {
    source: struct { shader: ShaderDirectPrepared, destination: shaderpipe.Slot },
    grey_to_emissivity: GreyToEmissivityStage,
    clamp: ClampStage,
};

pub const ShaderPipePrepared = struct {
    stages: []const ShaderPipeStagePrepared,
    resolver: shaderpipe.Resolver,
    constants: []const F,
    channels: u8,
};

pub const ShaderSetPrepared = struct {
    direct: ?ShaderDirectPrepared = null,
    mono: ?ShaderPipePrepared = null,
    rgb: ?ShaderPipePrepared = null,
    ir: ?ShaderPipePrepared = null,
    multifield: ?ShaderPipePrepared = null,
};

// --------------------------------------------------------------------------------------
// ShaderSet Operations & Selection
// --------------------------------------------------------------------------------------

pub fn SelectedShader(comptime Direct: type, comptime Pipe: type) type {
    return union(enum) {
        direct: *const Direct,
        pipe: *const Pipe,
    };
}

pub fn hasShader(shaders: anytype, selection: ShaderSelection) bool {
    return switch (selection) {
        .direct => shaders.direct != null,
        .mono => shaders.mono != null,
        .rgb => shaders.rgb != null,
        .ir => shaders.ir != null,
        .multifield => shaders.multifield != null,
    };
}

pub fn selectShader(
    comptime Direct: type,
    comptime Pipe: type,
    shaders: anytype,
    selection: ShaderSelection,
) ?SelectedShader(Direct, Pipe) {
    return switch (selection) {
        .direct => if (shaders.direct) |*shader| .{ .direct = shader } else null,
        .mono => if (shaders.mono) |*pipe| .{ .pipe = pipe } else null,
        .rgb => if (shaders.rgb) |*pipe| .{ .pipe = pipe } else null,
        .ir => if (shaders.ir) |*pipe| .{ .pipe = pipe } else null,
        .multifield => if (shaders.multifield) |*pipe| .{ .pipe = pipe } else null,
    };
}

// --------------------------------------------------------------------------------------
// Rasterisation Runtime Context & Buffers
// --------------------------------------------------------------------------------------

// Local buffer for hoisting element shader data into cache once per element before we 
// enter the sub-pixel raster loop.
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

pub fn InterpData(comptime N: usize) type {
    return struct {
        weights: [N]F,
        nodes_inv_z: [N]F,
        sub_pixel_z: F,
        xi: F,
        eta: F,
    };
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

const testing = std.testing;

test "texture input defaults to direct evaluation mode" {
    const ti_cfg = (TexInput(u8, 1){
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
