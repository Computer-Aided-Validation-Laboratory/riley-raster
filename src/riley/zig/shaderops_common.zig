// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const VecSF = buildconfig.VecSF;
const VecSI = buildconfig.VecSI;
const VecSB = buildconfig.VecSB;

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

const imageops = @import("imageops.zig");
const iio = @import("imageio.zig");
const texops = @import("textureops.zig");
const meshio = @import("meshio.zig");

pub const ScaleOver = enum { within_frames, over_frames };
pub const NormalType = enum { none, exact, averaged };
pub const FuncCoordMode = enum {
    uv,
    parametric,
    world_reference,
    world_deformed,
};

pub const FuncShaderBuiltin = enum {
    constant,
    linear,
    quadratic,
    sinusoidal,
    checker,
    checker_smooth,
    lambertian_normal_z,
    eggbox,
};

pub const FuncShaderParams = struct {
    coord_scale: [2]F = .{ 1.0, 1.0 },
    coord_offset: [2]F = .{ 0.0, 0.0 },
    output_scale: F = 1.0,
    output_offset: F = 0.0,
    wave_num_scalar: [2]F = .{ 6.0, 5.0 },
    wave_num_rgb: [3]F = .{ 6.0, 6.0, 4.0 },
    eggbox_mean: F = 0.5,
    eggbox_contrast: F = 0.4,
    eggbox_pitch: [2]F = .{ 1.0, 1.0 },
    eggbox_phase: [2]F = .{ 0.0, 0.0 },
    extra: [4]F = .{ 0.0, 0.0, 0.0, 0.0 },
};

pub const FuncCoordSIMD = struct {
    coord_0: VecSF,
    coord_1: VecSF,
    normal_x: VecSF,
    normal_y: VecSF,
    normal_z: VecSF,
};

pub fn LocalShaderBuffer(comptime N: usize) type {
    return struct {
        data: [buildconfig.config.max_nodal_fields * N]F = undefined,
        func_coords: [3 * N]F = undefined,
        normals: [3 * N]F = undefined,
        actual_fields: u8 = 0,
        actual_func_coords: u8 = 0,
        has_normals: bool = false,
        has_func_coords: bool = false,

        const Self = @This();

        pub inline fn load(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
            fields_num: u8,
        ) void {
            std.debug.assert(fields_num <= buildconfig.config.max_nodal_fields);
            self.actual_fields = fields_num;
            const count = @as(usize, fields_num) * N;
            @memcpy(self.data[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn loadNormals(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
        ) void {
            self.has_normals = true;
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
            self.has_func_coords = true;
            self.actual_func_coords = coords_num;
            const count = @as(usize, coords_num) * N;
            @memcpy(
                self.func_coords[0..count],
                array.slice[start_idx .. start_idx + count],
            );
        }

        pub inline fn interpolate(
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

        pub inline fn interpolateNormal(
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

        pub inline fn interpolateFuncCoord(
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

pub fn TexInput(comptime T: type, comptime channels: usize) type {
    return struct {
        uvs: ndarray.NDArray(F),
        texture: iio.Texture(T, channels),
        sample_config: texops.TextureSampleConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub fn FuncInput(comptime channels: usize) type {
    _ = channels;
    return struct {
        uvs: ?ndarray.NDArray(F) = null,
        coord_mode: FuncCoordMode = .parametric,
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const ShaderInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(u8, 1),
    tex_u16: TexInput(u16, 1),
    tex_rgb_u8: TexInput(u8, 3),
    tex_rgb_u16: TexInput(u16, 3),
    func: FuncInput(1),
    func_rgb: FuncInput(3),
};

// Static: Persistent multi-frame shader resources in engine memory.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Element-order [total_elems, 2, nodes_per_elem]
pub const NodalStatic = struct {
    field: meshio.Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub fn TexStatic(comptime T: type, comptime channels: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        texture: iio.Texture(T, channels),
        sample_config: texops.TextureSampleConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub fn FuncStatic(comptime channels: usize) type {
    _ = channels;
    return struct {
        elem_uvs: ?ndarray.NDArray(F),
        coord_mode: FuncCoordMode = .parametric,
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const ShaderStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_rgb_u8: TexStatic(u8, 3),
    tex_rgb_u16: TexStatic(u16, 3),
    func: FuncStatic(1),
    func_rgb: FuncStatic(3),
};

// Prepared: Culled and expanded shader data for a SINGLE frame.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
// Nodal Fields: Element-order [visible_elems, num_fields, nodes_per_elem]
// UVs: Element-order [visible_elems, 2, nodes_per_elem]
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

pub fn TexPrepared(comptime T: type, comptime channels: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        texture: iio.Texture(T, channels),
        sample_config: texops.TextureSampleConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: F = 1.0,
        scale_add: F = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(F) = null,
    };
}

pub fn FuncPrepared(comptime channels: usize) type {
    _ = channels;
    return struct {
        elem_uvs: ?ndarray.NDArray(F),
        elem_world_ref: ?ndarray.NDArray(F) = null,
        elem_world_def: ?ndarray.NDArray(F) = null,
        coord_mode: FuncCoordMode = .parametric,
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: F = 1.0,
        scale_add: F = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(F) = null,
    };
}

pub const ShaderPrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
    func: FuncPrepared(1),
    func_rgb: FuncPrepared(3),
};

pub fn ShadeContext(comptime N: usize) type {
    return struct {
        frame_idx: usize,
        elem_idx: usize,
        fields_num: u8,
        actual_fields: u8,
        scratch_idx: usize,
        global_subx: usize,
        global_suby: usize,
        shader_buf: *const LocalShaderBuffer(N),
        v_mask_active: ?buildconfig.VecSB = null,
    };
}

pub fn InterpData(comptime N: usize) type {
    return struct {
        weights: [N]F,
        nodes_inv_z: [N]F,
        sub_pixel_z: F,
        xi: F,
        eta: F,
    };
}

pub const FuncCoord = struct {
    coord_0: F,
    coord_1: F,
    normal_x: F,
    normal_y: F,
    normal_z: F,
};

inline fn cubicSmoothStep(val: F) F {
    const clamped = @max(0.0, @min(1.0, val));
    return clamped * clamped * (3.0 - 2.0 * clamped);
}

inline fn cubicSmoothStepSIMD(v_val: VecSF) VecSF {
    const v_zero: VecSF = @splat(0.0);
    const v_one: VecSF = @splat(1.0);
    const clamped = @max(v_zero, @min(v_one, v_val));
    return clamped * clamped * (@as(VecSF, @splat(3.0)) -
        @as(VecSF, @splat(2.0)) * clamped);
}

inline fn applyFuncShaderCoordParams(
    coord: FuncCoord,
    params: FuncShaderParams,
) FuncCoord {
    var out = coord;
    out.coord_0 = params.coord_scale[0] * coord.coord_0 + params.coord_offset[0];
    out.coord_1 = params.coord_scale[1] * coord.coord_1 + params.coord_offset[1];
    return out;
}

inline fn applyFuncShaderCoordParamsSIMD(
    coord: FuncCoordSIMD,
    params: FuncShaderParams,
) FuncCoordSIMD {
    var out = coord;
    out.coord_0 = @as(VecSF, @splat(params.coord_scale[0])) * coord.coord_0 +
        @as(VecSF, @splat(params.coord_offset[0]));
    out.coord_1 = @as(VecSF, @splat(params.coord_scale[1])) * coord.coord_1 +
        @as(VecSF, @splat(params.coord_offset[1]));
    return out;
}

inline fn applyFuncShaderOutputParams(value: F, params: FuncShaderParams) F {
    return value * params.output_scale + params.output_offset;
}

inline fn applyFuncShaderOutputParamsSIMD(
    v_value: VecSF,
    params: FuncShaderParams,
) VecSF {
    return v_value * @as(VecSF, @splat(params.output_scale)) +
        @as(VecSF, @splat(params.output_offset));
}

pub inline fn evalFuncShaderBuiltinScalar(
    builtin: FuncShaderBuiltin,
    coord: FuncCoord,
    params: FuncShaderParams,
) F {
    const eval_coord = applyFuncShaderCoordParams(coord, params);
    const value = switch (builtin) {
        .constant => 0.5,
        .linear => 0.5 + 0.25 * eval_coord.coord_0 + 0.2 * eval_coord.coord_1,
        .quadratic => 0.35 +
            0.2 * eval_coord.coord_0 +
            0.15 * eval_coord.coord_1 +
            0.1 * eval_coord.coord_0 * eval_coord.coord_0 -
            0.08 * eval_coord.coord_0 * eval_coord.coord_1 +
            0.06 * eval_coord.coord_1 * eval_coord.coord_1,
        .sinusoidal => 0.5 +
            0.25 * @sin(params.wave_num_scalar[0] * eval_coord.coord_0) +
            0.2 * @cos(params.wave_num_scalar[1] * eval_coord.coord_1),
        .checker => blk: {
            const cell_x: i64 = @intFromFloat(@floor(eval_coord.coord_0));
            const cell_y: i64 = @intFromFloat(@floor(eval_coord.coord_1));
            break :blk if (@mod(cell_x + cell_y, 2) == 0)
                @as(F, 0.0)
            else
                @as(F, 1.0);
        },
        .checker_smooth => blk: {
            const phase_x = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_0);
            const phase_y = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_1);
            const prod = phase_x * phase_y;
            break :blk cubicSmoothStep(prod);
        },
        .lambertian_normal_z => 0.5 + 0.5 * eval_coord.normal_z,
        .eggbox => blk: {
            const phase_x = 2.0 * std.math.pi *
                (eval_coord.coord_0 + params.eggbox_phase[0]) /
                params.eggbox_pitch[0];
            const phase_y = 2.0 * std.math.pi *
                (eval_coord.coord_1 + params.eggbox_phase[1]) /
                params.eggbox_pitch[1];
            break :blk params.eggbox_mean +
                0.5 * params.eggbox_contrast * (1.0 + @cos(phase_x)) *
                    (1.0 + @cos(phase_y)) -
                params.eggbox_contrast;
        },
    };
    return applyFuncShaderOutputParams(value, params);
}

pub inline fn evalFuncShaderBuiltinRgb(
    builtin: FuncShaderBuiltin,
    coord: FuncCoord,
    params: FuncShaderParams,
) [3]F {
    const eval_coord = applyFuncShaderCoordParams(coord, params);
    const values = switch (builtin) {
        .constant => .{ 0.2, 0.5, 0.8 },
        .linear => .{
            0.5 + 0.25 * eval_coord.coord_0,
            0.5 + 0.25 * eval_coord.coord_1,
            0.5 + 0.15 * eval_coord.coord_0 - 0.15 * eval_coord.coord_1,
        },
        .quadratic => .{
            0.3 + 0.2 * eval_coord.coord_0 * eval_coord.coord_0,
            0.3 + 0.2 * eval_coord.coord_1 * eval_coord.coord_1,
            0.3 + 0.12 * eval_coord.coord_0 * eval_coord.coord_1,
        },
        .sinusoidal => .{
            0.5 + 0.25 * @sin(params.wave_num_rgb[0] * eval_coord.coord_0),
            0.5 + 0.25 * @cos(params.wave_num_rgb[1] * eval_coord.coord_1),
            0.5 + 0.2 * @sin(params.wave_num_rgb[2] * (eval_coord.coord_0 + eval_coord.coord_1)),
        },
        .checker => blk: {
            const cell_x: i64 = @intFromFloat(@floor(eval_coord.coord_0));
            const cell_y: i64 = @intFromFloat(@floor(eval_coord.coord_1));
            const value = if (@mod(cell_x + cell_y, 2) == 0)
                @as(F, 0.0)
            else
                @as(F, 1.0);
            break :blk .{ value, value, value };
        },
        .checker_smooth => blk: {
            const phase_x = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_0);
            const phase_y = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_1);
            const base = cubicSmoothStep(phase_x * phase_y);
            break :blk .{
                base,
                cubicSmoothStep(1.0 - base),
                0.5 + 0.5 * @sin(2.0 * std.math.pi * base),
            };
        },
        .lambertian_normal_z => blk: {
            const lambert = 0.5 + 0.5 * eval_coord.normal_z;
            break :blk .{
                lambert,
                0.75 * lambert,
                0.5 * lambert,
            };
        },
        .eggbox => blk: {
            const phase_x = 2.0 * std.math.pi *
                (eval_coord.coord_0 + params.eggbox_phase[0]) /
                params.eggbox_pitch[0];
            const phase_y = 2.0 * std.math.pi *
                (eval_coord.coord_1 + params.eggbox_phase[1]) /
                params.eggbox_pitch[1];
            const value = params.eggbox_mean +
                0.5 * params.eggbox_contrast * (1.0 + @cos(phase_x)) *
                    (1.0 + @cos(phase_y)) -
                params.eggbox_contrast;
            break :blk .{ value, value, value };
        },
    };
    return .{
        applyFuncShaderOutputParams(values[0], params),
        applyFuncShaderOutputParams(values[1], params),
        applyFuncShaderOutputParams(values[2], params),
    };
}

pub inline fn evalFuncShaderBuiltinScalarSIMD(
    builtin: FuncShaderBuiltin,
    coord: FuncCoordSIMD,
    params: FuncShaderParams,
) VecSF {
    const eval_coord = applyFuncShaderCoordParamsSIMD(coord, params);
    const v_value = switch (builtin) {
        .constant => @as(VecSF, @splat(0.5)),
        .linear => @as(VecSF, @splat(0.5)) +
            @as(VecSF, @splat(0.25)) * eval_coord.coord_0 +
            @as(VecSF, @splat(0.2)) * eval_coord.coord_1,
        .quadratic => @as(VecSF, @splat(0.35)) +
            @as(VecSF, @splat(0.2)) * eval_coord.coord_0 +
            @as(VecSF, @splat(0.15)) * eval_coord.coord_1 +
            @as(VecSF, @splat(0.1)) * eval_coord.coord_0 * eval_coord.coord_0 -
            @as(VecSF, @splat(0.08)) * eval_coord.coord_0 * eval_coord.coord_1 +
            @as(VecSF, @splat(0.06)) * eval_coord.coord_1 * eval_coord.coord_1,
        .sinusoidal => @as(VecSF, @splat(0.5)) +
            @as(VecSF, @splat(0.25)) *
                @sin(@as(VecSF, @splat(params.wave_num_scalar[0])) *
                    eval_coord.coord_0) +
            @as(VecSF, @splat(0.2)) *
                @cos(@as(VecSF, @splat(params.wave_num_scalar[1])) *
                    eval_coord.coord_1),
        .checker => blk: {
            const v_cell_x: VecSI = @intFromFloat(@floor(eval_coord.coord_0));
            const v_cell_y: VecSI = @intFromFloat(@floor(eval_coord.coord_1));
            const v_parity = @mod(
                v_cell_x + v_cell_y,
                @as(VecSI, @splat(2)),
            ) == @as(VecSI, @splat(0));
            break :blk @select(
                F,
                @as(VecSB, v_parity),
                @as(VecSF, @splat(0.0)),
                @as(VecSF, @splat(1.0)),
            );
        },
        .checker_smooth => blk: {
            const v_phase_x = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(8.0 * std.math.pi)) *
                            eval_coord.coord_0,
                    );
            const v_phase_y = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(8.0 * std.math.pi)) *
                            eval_coord.coord_1,
                    );
            break :blk cubicSmoothStepSIMD(v_phase_x * v_phase_y);
        },
        .lambertian_normal_z => @as(VecSF, @splat(0.5)) +
            @as(VecSF, @splat(0.5)) * eval_coord.normal_z,
        .eggbox => blk: {
            const v_phase_x = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_0 +
                    @as(VecSF, @splat(params.eggbox_phase[0]))) /
                @as(VecSF, @splat(params.eggbox_pitch[0]));
            const v_phase_y = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_1 +
                    @as(VecSF, @splat(params.eggbox_phase[1]))) /
                @as(VecSF, @splat(params.eggbox_pitch[1]));
            break :blk @as(VecSF, @splat(params.eggbox_mean)) +
                @as(VecSF, @splat(0.5 * params.eggbox_contrast)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_x)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_y)) -
                @as(VecSF, @splat(params.eggbox_contrast));
        },
    };
    return applyFuncShaderOutputParamsSIMD(v_value, params);
}

pub inline fn evalFuncShaderBuiltinRgbSIMD(
    builtin: FuncShaderBuiltin,
    coord: FuncCoordSIMD,
    params: FuncShaderParams,
) [3]VecSF {
    const eval_coord = applyFuncShaderCoordParamsSIMD(coord, params);
    const v_values = switch (builtin) {
        .constant => .{
            @as(VecSF, @splat(0.2)),
            @as(VecSF, @splat(0.5)),
            @as(VecSF, @splat(0.8)),
        },
        .linear => .{
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.25)) * eval_coord.coord_0,
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.25)) * eval_coord.coord_1,
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.15)) * eval_coord.coord_0 -
                @as(VecSF, @splat(0.15)) * eval_coord.coord_1,
        },
        .quadratic => .{
            @as(VecSF, @splat(0.3)) +
                @as(VecSF, @splat(0.2)) * eval_coord.coord_0 *
                    eval_coord.coord_0,
            @as(VecSF, @splat(0.3)) +
                @as(VecSF, @splat(0.2)) * eval_coord.coord_1 *
                    eval_coord.coord_1,
            @as(VecSF, @splat(0.3)) +
                @as(VecSF, @splat(0.12)) * eval_coord.coord_0 *
                    eval_coord.coord_1,
        },
        .sinusoidal => .{
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.25)) *
                    @sin(@as(VecSF, @splat(params.wave_num_rgb[0])) *
                        eval_coord.coord_0),
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.25)) *
                    @cos(@as(VecSF, @splat(params.wave_num_rgb[1])) *
                        eval_coord.coord_1),
            @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.2)) *
                    @sin(
                        @as(VecSF, @splat(params.wave_num_rgb[2])) *
                            (eval_coord.coord_0 + eval_coord.coord_1),
                    ),
        },
        .checker => blk: {
            const v_cell_x: VecSI = @intFromFloat(@floor(eval_coord.coord_0));
            const v_cell_y: VecSI = @intFromFloat(@floor(eval_coord.coord_1));
            const v_parity = @mod(
                v_cell_x + v_cell_y,
                @as(VecSI, @splat(2)),
            ) == @as(VecSI, @splat(0));
            const v_value = @select(
                F,
                @as(VecSB, v_parity),
                @as(VecSF, @splat(0.0)),
                @as(VecSF, @splat(1.0)),
            );
            break :blk .{ v_value, v_value, v_value };
        },
        .checker_smooth => blk: {
            const v_phase_x = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(8.0 * std.math.pi)) *
                            eval_coord.coord_0,
                    );
            const v_phase_y = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(8.0 * std.math.pi)) *
                            eval_coord.coord_1,
                    );
            const v_base = cubicSmoothStepSIMD(v_phase_x * v_phase_y);
            break :blk .{
                v_base,
                cubicSmoothStepSIMD(@as(VecSF, @splat(1.0)) - v_base),
                @as(VecSF, @splat(0.5)) +
                    @as(VecSF, @splat(0.5)) *
                        @sin(@as(VecSF, @splat(2.0 * std.math.pi)) * v_base),
            };
        },
        .lambertian_normal_z => blk: {
            const v_lambert = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) * eval_coord.normal_z;
            break :blk .{
                v_lambert,
                @as(VecSF, @splat(0.75)) * v_lambert,
                @as(VecSF, @splat(0.5)) * v_lambert,
            };
        },
        .eggbox => blk: {
            const v_phase_x = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_0 +
                    @as(VecSF, @splat(params.eggbox_phase[0]))) /
                @as(VecSF, @splat(params.eggbox_pitch[0]));
            const v_phase_y = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_1 +
                    @as(VecSF, @splat(params.eggbox_phase[1]))) /
                @as(VecSF, @splat(params.eggbox_pitch[1]));
            const v_value = @as(VecSF, @splat(params.eggbox_mean)) +
                @as(VecSF, @splat(0.5 * params.eggbox_contrast)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_x)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_y)) -
                @as(VecSF, @splat(params.eggbox_contrast));
            break :blk .{ v_value, v_value, v_value };
        },
    };
    return .{
        applyFuncShaderOutputParamsSIMD(v_values[0], params),
        applyFuncShaderOutputParamsSIMD(v_values[1], params),
        applyFuncShaderOutputParamsSIMD(v_values[2], params),
    };
}

inline fn getFuncCoord(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    elem_normals: ?ndarray.MappedNDArray(F),
) FuncCoord {
    if (elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        return .{
            .coord_0 = 0.0,
            .coord_1 = 0.0,
            .normal_x = normal[0],
            .normal_y = normal[1],
            .normal_z = normal[2],
        };
    }

    return .{
        .coord_0 = 0.0,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
}

inline fn setCoordValues(
    coord: *FuncCoord,
    coord_0: F,
    coord_1: F,
) void {
    coord.coord_0 = coord_0;
    coord.coord_1 = coord_1;
}

inline fn resolveFuncCoordsClip(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FuncPrepared(channels),
) struct { coord_0: F, coord_1: F } {
    return switch (sh.coord_mode) {
        .uv => .{
            .coord_0 = ctx_shade.shader_buf.interpolateFuncCoord(0, interp.weights),
            .coord_1 = ctx_shade.shader_buf.interpolateFuncCoord(1, interp.weights),
        },
        .parametric => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
        .world_reference, .world_deformed => .{
            .coord_0 = ctx_shade.shader_buf.interpolateFuncCoord(0, interp.weights),
            .coord_1 = ctx_shade.shader_buf.interpolateFuncCoord(1, interp.weights),
        },
    };
}

inline fn resolveFuncCoordsPersp(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FuncPrepared(channels),
) struct { coord_0: F, coord_1: F } {
    return switch (sh.coord_mode) {
        .uv, .world_reference, .world_deformed => blk: {
            var coord_0: F = 0.0;
            var coord_1: F = 0.0;
            inline for (0..N) |nn| {
                const inv_z = interp.nodes_inv_z[nn];
                coord_0 += interp.weights[nn] *
                    ctx_shade.shader_buf.func_coords[nn] *
                    inv_z;
                coord_1 += interp.weights[nn] *
                    ctx_shade.shader_buf.func_coords[N + nn] *
                    inv_z;
            }
            break :blk .{
                .coord_0 = coord_0 * interp.sub_pixel_z,
                .coord_1 = coord_1 * interp.sub_pixel_z,
            };
        },
        .parametric => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
    };
}

pub inline fn fillNodalClip(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const NodalPrepared,
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const value = ctx_shade.shader_buf.interpolate(ff, interp.weights);
        spx_image_scratch.slice[ff * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
            value * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillNodalPersp(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const NodalPrepared,
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const base = ff * N;
        var value: F = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            value += interp.weights[nn] *
                ctx_shade.shader_buf.data[base + nn] *
                inv_z;
        }

        const final_val = value * interp.sub_pixel_z;
        spx_image_scratch.slice[ff * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
            final_val * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexClip(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime sample_config: texops.TextureSampleConfig,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(T, channels),
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        tex_u += interp.weights[nn] * ctx_shade.shader_buf.data[nn];
        tex_v += interp.weights[nn] * ctx_shade.shader_buf.data[N + nn];
    }

    const sampled = texops.sampleScalar(
        channels,
        sample_config,
        sh.texture,
        tex_u,
        tex_v,
    );

    inline for (0..channels) |ch| {
        spx_image_scratch.slice[ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillTexPersp(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime sample_config: texops.TextureSampleConfig,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(T, channels),
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        tex_u += interp.weights[nn] * ctx_shade.shader_buf.data[nn] * inv_z;
        tex_v += interp.weights[nn] *
            ctx_shade.shader_buf.data[N + nn] *
            inv_z;
    }

    const sampled = texops.sampleScalar(
        channels,
        sample_config,
        sh.texture,
        tex_u * interp.sub_pixel_z,
        tex_v * interp.sub_pixel_z,
    );

    inline for (0..channels) |ch| {
        spx_image_scratch.slice[ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
            sampled[ch] * sh.scale_mul + sh.scale_add;
    }
}

pub inline fn fillFuncClip(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FuncPrepared(channels),
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    var coord = getFuncCoord(N, ctx_shade, interp, sh.elem_normals);
    const coords = resolveFuncCoordsClip(N, channels, ctx_shade, interp, sh);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);

    if (comptime channels == 1) {
        const value = evalFuncShaderBuiltinScalar(sh.builtin, coord, sh.params);
        spx_image_scratch.slice[ctx_shade.scratch_idx] =
            value * sh.scale_mul + sh.scale_add;
    } else {
        const values = evalFuncShaderBuiltinRgb(sh.builtin, coord, sh.params);
        inline for (0..channels) |ch| {
            spx_image_scratch.slice[ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
                values[ch] * sh.scale_mul + sh.scale_add;
        }
    }
}

pub inline fn fillFuncPersp(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const FuncPrepared(channels),
    spx_image_scratch: *matslice.MatSlice(F),
) void {
    var coord = getFuncCoord(N, ctx_shade, interp, sh.elem_normals);
    const coords = resolveFuncCoordsPersp(N, channels, ctx_shade, interp, sh);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);

    if (comptime channels == 1) {
        const value = evalFuncShaderBuiltinScalar(sh.builtin, coord, sh.params);
        spx_image_scratch.slice[ctx_shade.scratch_idx] =
            value * sh.scale_mul + sh.scale_add;
    } else {
        const values = evalFuncShaderBuiltinRgb(sh.builtin, coord, sh.params);
        inline for (0..channels) |ch| {
            spx_image_scratch.slice[ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx] =
                values[ch] * sh.scale_mul + sh.scale_add;
        }
    }
}

const testing = std.testing;

test "FuncShaderParams defaults preserve constant shader" {
    const coord = FuncCoord{
        .coord_0 = 0.25,
        .coord_1 = -0.5,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const value = evalFuncShaderBuiltinScalar(.constant, coord, .{});
    try testing.expectApproxEqAbs(@as(F, 0.5), value, unit_tol);
}

test "FuncShaderParams control sinusoidal frequency and output scaling" {
    const coord = FuncCoord{
        .coord_0 = 0.25,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const base = evalFuncShaderBuiltinScalar(.sinusoidal, coord, .{});
    const shifted = evalFuncShaderBuiltinScalar(.sinusoidal, coord, .{
        .coord_scale = .{ 2.0, 1.0 },
        .output_scale = 2.0,
        .output_offset = -0.25,
    });
    const expected_base = 0.5 + 0.25 * @sin(6.0 * 0.25) + 0.2 * @cos(0.0);
    const expected_shifted = (0.5 + 0.25 * @sin(6.0 * 0.5) + 0.2 * @cos(0.0)) * 2.0 - 0.25;
    try testing.expectApproxEqAbs(expected_base, base, unit_tol);
    try testing.expectApproxEqAbs(expected_shifted, shifted, unit_tol);
}

test "checker texfunc creates hard black white cells from coord scale" {
    const coord_black = FuncCoord{
        .coord_0 = 0.01,
        .coord_1 = 0.01,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const coord_white = FuncCoord{
        .coord_0 = 0.05,
        .coord_1 = 0.01,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const params = FuncShaderParams{
        .coord_scale = .{ 36.0, 36.0 },
    };

    const value_black = evalFuncShaderBuiltinScalar(.checker, coord_black, params);
    const value_white = evalFuncShaderBuiltinScalar(.checker, coord_white, params);

    try testing.expectEqual(@as(F, 0.0), value_black);
    try testing.expectEqual(@as(F, 1.0), value_white);
}

test "eggbox reaches mean plus contrast at cell center" {
    const coord = FuncCoord{
        .coord_0 = 0.0,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const params = FuncShaderParams{
        .eggbox_mean = 0.5,
        .eggbox_contrast = 0.4,
        .eggbox_pitch = .{ 1.0, 1.0 },
    };
    const value = evalFuncShaderBuiltinScalar(.eggbox, coord, params);
    try testing.expectApproxEqAbs(@as(F, 0.9), value, unit_tol);
}

test "eggbox reaches mean minus contrast on grid line" {
    const coord = FuncCoord{
        .coord_0 = 0.5,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const params = FuncShaderParams{
        .eggbox_mean = 0.5,
        .eggbox_contrast = 0.4,
        .eggbox_pitch = .{ 1.0, 1.0 },
    };
    const value = evalFuncShaderBuiltinScalar(.eggbox, coord, params);
    try testing.expectApproxEqAbs(@as(F, 0.1), value, unit_tol);
}

test "SIMD func builtin matches scalar builtin per lane" {
    const coord_scalar = [_]FuncCoord{
        .{
            .coord_0 = 0.1,
            .coord_1 = -0.2,
            .normal_x = 0.0,
            .normal_y = 0.0,
            .normal_z = 1.0,
        },
        .{
            .coord_0 = 0.35,
            .coord_1 = 0.125,
            .normal_x = 0.1,
            .normal_y = -0.2,
            .normal_z = 0.7,
        },
        .{
            .coord_0 = -0.45,
            .coord_1 = 0.8,
            .normal_x = -0.3,
            .normal_y = 0.2,
            .normal_z = 0.4,
        },
        .{
            .coord_0 = 1.2,
            .coord_1 = -0.9,
            .normal_x = 0.0,
            .normal_y = 0.0,
            .normal_z = 0.25,
        },
    };
    const coord_simd = FuncCoordSIMD{
        .coord_0 = .{
            coord_scalar[0].coord_0,
            coord_scalar[1].coord_0,
            coord_scalar[2].coord_0,
            coord_scalar[3].coord_0,
        } ++ [_]F{0.0} ** (buildconfig.SimdWidth - 4),
        .coord_1 = .{
            coord_scalar[0].coord_1,
            coord_scalar[1].coord_1,
            coord_scalar[2].coord_1,
            coord_scalar[3].coord_1,
        } ++ [_]F{0.0} ** (buildconfig.SimdWidth - 4),
        .normal_x = .{
            coord_scalar[0].normal_x,
            coord_scalar[1].normal_x,
            coord_scalar[2].normal_x,
            coord_scalar[3].normal_x,
        } ++ [_]F{0.0} ** (buildconfig.SimdWidth - 4),
        .normal_y = .{
            coord_scalar[0].normal_y,
            coord_scalar[1].normal_y,
            coord_scalar[2].normal_y,
            coord_scalar[3].normal_y,
        } ++ [_]F{0.0} ** (buildconfig.SimdWidth - 4),
        .normal_z = .{
            coord_scalar[0].normal_z,
            coord_scalar[1].normal_z,
            coord_scalar[2].normal_z,
            coord_scalar[3].normal_z,
        } ++ [_]F{0.0} ** (buildconfig.SimdWidth - 4),
    };
    const params = FuncShaderParams{
        .coord_scale = .{ 1.7, 0.8 },
        .coord_offset = .{ -0.1, 0.3 },
        .output_scale = 1.25,
        .output_offset = -0.05,
        .wave_num_scalar = .{ 5.0, 7.0 },
        .wave_num_rgb = .{ 4.0, 6.0, 3.0 },
        .eggbox_mean = 0.45,
        .eggbox_contrast = 0.3,
        .eggbox_pitch = .{ 0.9, 1.1 },
        .eggbox_phase = .{ 0.2, -0.15 },
    };

    const scalar_builtins = [_]FuncShaderBuiltin{
        .constant,
        .linear,
        .quadratic,
        .sinusoidal,
        .checker,
        .checker_smooth,
        .lambertian_normal_z,
        .eggbox,
    };
    for (scalar_builtins) |builtin| {
        const v_vals = evalFuncShaderBuiltinScalarSIMD(
            builtin,
            coord_simd,
            params,
        );
        const vals_arr: [buildconfig.SimdWidth]F = v_vals;
        for (coord_scalar, 0..) |coord, ll| {
            const expected = evalFuncShaderBuiltinScalar(
                builtin,
                coord,
                params,
            );
            try testing.expectApproxEqAbs(expected, vals_arr[ll], unit_tol);
        }

        const v_rgb = evalFuncShaderBuiltinRgbSIMD(
            builtin,
            coord_simd,
            params,
        );
        inline for (0..3) |ch| {
            const vals_rgb_arr: [buildconfig.SimdWidth]F = v_rgb[ch];
            for (coord_scalar, 0..) |coord, ll| {
                const expected = evalFuncShaderBuiltinRgb(
                    builtin,
                    coord,
                    params,
                )[ch];
                try testing.expectApproxEqAbs(
                    expected,
                    vals_rgb_arr[ll],
                    unit_tol,
                );
            }
        }
    }
}

const unit_tol: F = if (F == f32) 1e-5 else 1e-12;
