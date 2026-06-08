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

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

const imageops = @import("imageops.zig");
const iio = @import("imageio.zig");
const texops = @import("textureops.zig");
const meshio = @import("meshio.zig");

pub const ScaleOver = enum { within_frames, over_frames };
pub const NormalType = enum { none, exact, averaged };

pub const FuncShaderBuiltin = enum {
    constant,
    linear,
    quadratic,
    sinusoidal,
    checker,
    checker_smooth,
    lambertian_normal_z,
};

pub const FuncShaderParams = struct {
    coord_scale: [2]f64 = .{ 1.0, 1.0 },
    coord_offset: [2]f64 = .{ 0.0, 0.0 },
    output_scale: f64 = 1.0,
    output_offset: f64 = 0.0,
    wave_num_scalar: [2]f64 = .{ 6.0, 5.0 },
    wave_num_rgb: [3]f64 = .{ 6.0, 6.0, 4.0 },
    extra: [4]f64 = .{ 0.0, 0.0, 0.0, 0.0 },
};


pub fn LocalShaderBuffer(comptime N: usize) type {
    return struct {
        data: [buildconfig.config.max_nodal_fields * N]f64 = undefined,
        normals: [3 * N]f64 = undefined,
        actual_fields: u8 = 0,
        has_normals: bool = false,

        const Self = @This();

        pub inline fn load(
            self: *Self,
            array: ndarray.NDArray(f64),
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
            array: ndarray.NDArray(f64),
            start_idx: usize,
        ) void {
            self.has_normals = true;
            const count = 3 * N;
            @memcpy(self.normals[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn interpolate(
            self: *const Self,
            field_idx: usize,
            weights: [N]f64,
        ) f64 {
            const base = field_idx * N;
            var sum: f64 = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.data[base + nn];
            }
            return sum;
        }

        pub inline fn interpolateNormal(
            self: *const Self,
            weights: [N]f64,
        ) [3]f64 {
            var norm = [3]f64{ 0.0, 0.0, 0.0 };
            inline for (0..N) |nn| {
                norm[0] += weights[nn] * self.normals[0 * N + nn];
                norm[1] += weights[nn] * self.normals[1 * N + nn];
                norm[2] += weights[nn] * self.normals[2 * N + nn];
            }
            return norm;
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

pub fn TexInput(comptime channels: usize) type {
    return struct {
        uvs: ndarray.NDArray(f64),
        texture: iio.Texture(channels),
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
        uvs: ?ndarray.NDArray(f64) = null,
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const ShaderInput = union(enum) {
    nodal: NodalInput,
    tex: TexInput(1),
    tex_rgb: TexInput(3),
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

pub fn TexStatic(comptime channels: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(f64),
        texture: iio.Texture(channels),
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
        elem_uvs: ?ndarray.NDArray(f64),
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const ShaderStatic = union(enum) {
    nodal: NodalStatic,
    tex: TexStatic(1),
    tex_rgb: TexStatic(3),
    func: FuncStatic(1),
    func_rgb: FuncStatic(3),
};

// Prepared: Culled and expanded shader data for a SINGLE frame.
// Prepared means culled element-order ndarray.NDArray data ready for the raster loop.
// Nodal Fields: Element-order [visible_elems, num_fields, nodes_per_elem]
// UVs: Element-order [visible_elems, 2, nodes_per_elem]
pub const NodalPrepared = struct {
    elem_field: ndarray.NDArray(f64),
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: f64 = 1.0,
    scale_add: f64 = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?ndarray.MappedNDArray(f64) = null,
};

pub fn TexPrepared(comptime channels: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(f64),
        texture: iio.Texture(channels),
        sample_config: texops.TextureSampleConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: f64 = 1.0,
        scale_add: f64 = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(f64) = null,
    };
}

pub fn FuncPrepared(comptime channels: usize) type {
    _ = channels;
    return struct {
        elem_uvs: ?ndarray.NDArray(f64),
        builtin: FuncShaderBuiltin,
        params: FuncShaderParams = .{},
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: f64 = 1.0,
        scale_add: f64 = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(f64) = null,
    };
}

pub const ShaderPrepared = union(enum) {
    nodal: NodalPrepared,
    tex: TexPrepared(1),
    tex_rgb: TexPrepared(3),
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
        weights: [N]f64,
        nodes_inv_z: [N]f64,
        sub_pixel_z: f64,
        xi: f64,
        eta: f64,
    };
}

pub const FuncCoord = struct {
    coord_0: f64,
    coord_1: f64,
    normal_x: f64,
    normal_y: f64,
    normal_z: f64,
};


inline fn cubicSmoothStep(val: f64) f64 {
    const clamped = @max(0.0, @min(1.0, val));
    return clamped * clamped * (3.0 - 2.0 * clamped);
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

inline fn applyFuncShaderOutputParams(value: f64, params: FuncShaderParams) f64 {
    return value * params.output_scale + params.output_offset;
}

pub inline fn evalFuncShaderBuiltinScalar(
    builtin: FuncShaderBuiltin,
    coord: FuncCoord,
    params: FuncShaderParams,
) f64 {
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
                @as(f64, 0.0)
            else
                @as(f64, 1.0);
        },
        .checker_smooth => blk: {
            const phase_x = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_0);
            const phase_y = 0.5 + 0.5 * @sin(8.0 * std.math.pi * eval_coord.coord_1);
            const prod = phase_x * phase_y;
            break :blk cubicSmoothStep(prod);
        },
        .lambertian_normal_z => 0.5 + 0.5 * eval_coord.normal_z,
    };
    return applyFuncShaderOutputParams(value, params);
}

pub inline fn evalFuncShaderBuiltinRgb(
    builtin: FuncShaderBuiltin,
    coord: FuncCoord,
    params: FuncShaderParams,
) [3]f64 {
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
                @as(f64, 0.0)
            else
                @as(f64, 1.0);
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
    };
    return .{
        applyFuncShaderOutputParams(values[0], params),
        applyFuncShaderOutputParams(values[1], params),
        applyFuncShaderOutputParams(values[2], params),
    };
}

inline fn getFuncCoord(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    elem_normals: ?ndarray.MappedNDArray(f64),
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
    coord_0: f64,
    coord_1: f64,
) void {
    coord.coord_0 = coord_0;
    coord.coord_1 = coord_1;
}

pub inline fn fillNodalClip(
    comptime N: usize,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const NodalPrepared,
    spx_image_scratch: *matslice.MatSlice(f64),
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
    spx_image_scratch: *matslice.MatSlice(f64),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const base = ff * N;
        var value: f64 = 0.0;
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
    comptime channels: usize,
    comptime sample_config: texops.TextureSampleConfig,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(channels),
    spx_image_scratch: *matslice.MatSlice(f64),
) void {
    var tex_u: f64 = 0.0;
    var tex_v: f64 = 0.0;
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
    comptime channels: usize,
    comptime sample_config: texops.TextureSampleConfig,
    ctx_shade: ShadeContext(N),
    interp: InterpData(N),
    sh: *const TexPrepared(channels),
    spx_image_scratch: *matslice.MatSlice(f64),
) void {
    var tex_u: f64 = 0.0;
    var tex_v: f64 = 0.0;
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
    spx_image_scratch: *matslice.MatSlice(f64),
) void {
    var coord = getFuncCoord(N, ctx_shade, interp, sh.elem_normals);

    if (sh.elem_uvs != null) {
        var tex_u: f64 = 0.0;
        var tex_v: f64 = 0.0;
        inline for (0..N) |nn| {
            tex_u += interp.weights[nn] * ctx_shade.shader_buf.data[nn];
            tex_v += interp.weights[nn] * ctx_shade.shader_buf.data[N + nn];
        }
        setCoordValues(&coord, tex_u, tex_v);
    } else {
        setCoordValues(&coord, interp.xi, interp.eta);
    }

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
    spx_image_scratch: *matslice.MatSlice(f64),
) void {
    var coord = getFuncCoord(N, ctx_shade, interp, sh.elem_normals);

    if (sh.elem_uvs != null) {
        var tex_u: f64 = 0.0;
        var tex_v: f64 = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            tex_u += interp.weights[nn] * ctx_shade.shader_buf.data[nn] * inv_z;
            tex_v += interp.weights[nn] *
                ctx_shade.shader_buf.data[N + nn] *
                inv_z;
        }
        setCoordValues(&coord, tex_u * interp.sub_pixel_z, tex_v * interp.sub_pixel_z);
    } else {
        setCoordValues(&coord, interp.xi, interp.eta);
    }

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
    try testing.expectApproxEqAbs(@as(f64, 0.5), value, 1e-12);
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
    try testing.expectApproxEqAbs(expected_base, base, 1e-12);
    try testing.expectApproxEqAbs(expected_shifted, shifted, 1e-12);
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

    try testing.expectEqual(@as(f64, 0.0), value_black);
    try testing.expectEqual(@as(f64, 1.0), value_white);
}
