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
const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const texops = @import("textureops.zig");
const comm = @import("shaderops_common.zig");
const maths_simd = @import("maths_simd.zig");
const speckle = @import("speckleops.zig");
const simd_impl = if (@import("builtin").is_test)
    @import("shaderops_simd.zig")
else
    struct {};

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const FuncCoord = struct {
    coord_0: F,
    coord_1: F,
    normal_x: F,
    normal_y: F,
    normal_z: F,
};

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub inline fn fillNodalClipScal(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.NodalPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const value = shader_buf.interp(ff, interp.weights);
        const idx = ff * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = value * shader.scale_mul + shader.scale_add;
    }
}

pub inline fn fillNodalPerspScal(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.NodalPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const base = ff * N;

        var value: F = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            value += interp.weights[nn] * shader_buf.data[base + nn] * inv_z;
        }

        const final_val = value * interp.sub_pixel_z;
        const idx = ff * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = final_val * shader.scale_mul + shader.scale_add;
    }
}

// --------------------------------------------------------------------------------------
// Texture Shader
// --------------------------------------------------------------------------------------

pub inline fn fillTexClipScal(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: texops.TexSampConfig,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        tex_u += interp.weights[nn] * shader_buf.data[nn];
        tex_v += interp.weights[nn] * shader_buf.data[N + nn];
    }

    const sampled = texops.sampScal(
        C,
        samp_cfg,
        shader.tex,
        tex_u,
        tex_v,
    );

    inline for (0..C) |ch| {
        const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = sampled[ch] * shader.scale_mul + shader.scale_add;
    }
}

pub inline fn fillTexPerspScal(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: texops.TexSampConfig,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        tex_u += interp.weights[nn] * shader_buf.data[nn] * inv_z;
        tex_v += interp.weights[nn] * shader_buf.data[N + nn] * inv_z;
    }

    const sampled = texops.sampScal(
        C,
        samp_cfg,
        shader.tex,
        tex_u * interp.sub_pixel_z,
        tex_v * interp.sub_pixel_z,
    );

    inline for (0..C) |ch| {
        const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = sampled[ch] * shader.scale_mul + shader.scale_add;
    }
}

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

inline fn getFuncCoord(
    comptime N: usize,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    elem_normals: ?ndarray.MappedNDArray(F),
) FuncCoord {
    if (elem_normals != null) {
        const normal = shader_buf.interpNormal(interp.weights);
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
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
) struct { coord_0: F, coord_1: F } {
    return switch (shader.coord_mode) {
        .uv => .{
            .coord_0 = shader_buf.interpFuncCoord(0, interp.weights),
            .coord_1 = shader_buf.interpFuncCoord(1, interp.weights),
        },
        .para => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
        .world_reference, .world_deformed => .{
            .coord_0 = shader_buf.interpFuncCoord(0, interp.weights),
            .coord_1 = shader_buf.interpFuncCoord(1, interp.weights),
        },
    };
}

inline fn resolveFuncCoordsPersp(
    comptime N: usize,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
) struct { coord_0: F, coord_1: F } {
    return switch (shader.coord_mode) {
        .uv, .world_reference, .world_deformed => blk: {
            var coord_0: F = 0.0;
            var coord_1: F = 0.0;

            inline for (0..N) |nn| {
                const inv_z = interp.nodes_inv_z[nn];
                coord_0 += interp.weights[nn] * shader_buf.func_coords[nn] * inv_z;
                coord_1 += interp.weights[nn] * shader_buf.func_coords[N + nn] * inv_z;
            }

            break :blk .{
                .coord_0 = coord_0 * interp.sub_pixel_z,
                .coord_1 = coord_1 * interp.sub_pixel_z,
            };
        },
        .para => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
    };
}

pub inline fn evalFuncShaderGreyPreparedScal(
    shader: *const comm.FuncPrepared,
    coord: FuncCoord,
) F {
    if (shader.builtin == .speckle) {
        const params = shader.params;
        return speckle.sampleScal(
            coord.coord_0,
            coord.coord_1,
            params.settings.speckle,
            &shader.speckle_resources,
        ) * params.output_scale + params.output_offset;
    }

    return evalFuncShaderBuiltinGreyNorm(
        shader.builtin,
        coord,
        shader.params,
    );
}

pub inline fn fillFuncClipScal(
    comptime N: usize,
    comptime C: usize,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    const coords = resolveFuncCoordsClip(N, interp, shader_buf, shader);
    var coord = getFuncCoord(N, interp, shader_buf, shader.elem_normals);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);
    const params = shader.params;

    if (comptime C == 1) {
        const value = evalFuncShaderGreyPreparedScal(shader, coord);
        spx_img_scratch.slice[ctx_shade.scratch_idx] =
            value * shader.scale_mul + shader.scale_add;
    } else {
        const vals = evalFuncShaderBuiltinRGBNorm(
            shader.builtin,
            coord,
            params,
        );

        inline for (0..C) |ch| {
            const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
            spx_img_scratch.slice[idx] = vals[ch] * shader.scale_mul + shader.scale_add;
        }
    }
}

pub inline fn fillFuncPerspScal(
    comptime N: usize,
    comptime C: usize,
    ctx_shade: comm.ShadeContext,
    interp: comm.InterpData(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    const coords = resolveFuncCoordsPersp(N, interp, shader_buf, shader);
    var coord = getFuncCoord(N, interp, shader_buf, shader.elem_normals);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);
    const params = shader.params;

    if (comptime C == 1) {
        const value = evalFuncShaderGreyPreparedScal(shader, coord);
        spx_img_scratch.slice[ctx_shade.scratch_idx] =
            value * shader.scale_mul + shader.scale_add;
    } else {
        const vals = evalFuncShaderBuiltinRGBNorm(
            shader.builtin,
            coord,
            params,
        );

        inline for (0..C) |ch| {
            const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
            spx_img_scratch.slice[idx] = vals[ch] * shader.scale_mul + shader.scale_add;
        }
    }
}

pub inline fn evalFuncShaderBuiltinGreyNorm(
    builtin: comm.FuncShaderBuiltin,
    coord: FuncCoord,
    params: comm.FuncShaderParams,
) F {
    const eval_coord = applyFuncShaderCoordParams(coord, params);
    const value = switch (builtin) {
        .constant => blk: {
            const p = params.settings.constant;
            break :blk p.value;
        },
        .linear => blk: {
            const p = params.settings.linear;
            break :blk p.coeffs[0] +
                p.coeffs[1] * eval_coord.coord_0 +
                p.coeffs[2] * eval_coord.coord_1;
        },
        .quadratic => blk: {
            const p = params.settings.quadratic;
            const coord_u = eval_coord.coord_0;
            const coord_v = eval_coord.coord_1;
            const c = p.coeffs;
            const term_u = coord_u * (c[1] + c[3] * coord_u);
            const term_v = coord_v * (c[2] + c[4] * coord_u + c[5] * coord_v);
            break :blk c[0] + term_u + term_v;
        },
        .sinusoidal => blk: {
            const p = params.settings.sinusoidal;
            break :blk p.bias +
                p.amplitudes[0] * @sin(p.wave_num_scalar[0] * eval_coord.coord_0) +
                p.amplitudes[1] * @cos(p.wave_num_scalar[1] * eval_coord.coord_1);
        },
        .sinusoidal_approx => blk: {
            const p = params.settings.sinusoidal_approx;
            break :blk p.bias +
                p.amplitudes[0] *
                    sinApproxScalar(p.wave_num_scalar[0] * eval_coord.coord_0) +
                p.amplitudes[1] *
                    cosApproxScalar(p.wave_num_scalar[1] * eval_coord.coord_1);
        },
        .checker => blk: {
            const p = params.settings.checker;
            const cell_x: i64 = @intFromFloat(@floor(eval_coord.coord_0));
            const cell_y: i64 = @intFromFloat(@floor(eval_coord.coord_1));
            break :blk if (@mod(cell_x + cell_y, 2) == 0)
                p.levels[0]
            else
                p.levels[1];
        },
        .checker_smooth => blk: {
            const p = params.settings.checker_smooth;
            const phase_x = 0.5 + 0.5 * @sin(
                p.frequency * std.math.pi * eval_coord.coord_0,
            );
            const phase_y = 0.5 + 0.5 * @sin(
                p.frequency * std.math.pi * eval_coord.coord_1,
            );
            const prod = phase_x * phase_y;
            break :blk cubicSmoothStep(prod);
        },
        .lambertian_normal_z => blk: {
            const p = params.settings.lambertian_normal_z;
            break :blk p.coeffs[0] + p.coeffs[1] * eval_coord.normal_z;
        },
        .eggbox => blk: {
            const p = params.settings.eggbox;
            const phase_x = 2.0 * std.math.pi *
                (eval_coord.coord_0 + p.phase[0]) / p.pitch[0];
            const phase_y = 2.0 * std.math.pi *
                (eval_coord.coord_1 + p.phase[1]) / p.pitch[1];
            break :blk p.mean +
                0.5 * p.contrast * (1.0 + @cos(phase_x)) * (1.0 + @cos(phase_y)) -
                p.contrast;
        },
        .speckle => speckle.sampleScal(
            coord.coord_0,
            coord.coord_1,
            params.settings.speckle,
            &.{},
        ),
    };
    return applyFuncShaderOutputParams(value, params);
}

pub inline fn evalFuncShaderBuiltinRGBNorm(
    builtin: comm.FuncShaderBuiltin,
    coord: FuncCoord,
    params: comm.FuncShaderParams,
) [3]F {
    const eval_coord = applyFuncShaderCoordParams(coord, params);
    const vals = switch (builtin) {
        .constant => blk: {
            const p = params.settings.constant;
            break :blk p.value_rgb;
        },
        .linear => blk: {
            const p = params.settings.linear;
            const c = p.coeffs_rgb;
            break :blk .{
                c[0][0] + c[0][1] * eval_coord.coord_0 + c[0][2] * eval_coord.coord_1,
                c[1][0] + c[1][1] * eval_coord.coord_0 + c[1][2] * eval_coord.coord_1,
                c[2][0] + c[2][1] * eval_coord.coord_0 + c[2][2] * eval_coord.coord_1,
            };
        },
        .quadratic => blk: {
            const p = params.settings.quadratic;
            const coord_u = eval_coord.coord_0;
            const coord_v = eval_coord.coord_1;
            const c = p.coeffs_rgb;

            const val_r = c[0][0] + coord_u * (c[0][1] + c[0][3] * coord_u) +
                coord_v * (c[0][2] + c[0][4] * coord_u + c[0][5] * coord_v);
            const val_g = c[1][0] + coord_u * (c[1][1] + c[1][3] * coord_u) +
                coord_v * (c[1][2] + c[1][4] * coord_u + c[1][5] * coord_v);
            const val_b = c[2][0] + coord_u * (c[2][1] + c[2][3] * coord_u) +
                coord_v * (c[2][2] + c[2][4] * coord_u + c[2][5] * coord_v);
            break :blk .{ val_r, val_g, val_b };
        },
        .sinusoidal => blk: {
            const p = params.settings.sinusoidal;
            break :blk .{
                p.bias_rgb[0] + p.amplitudes_rgb[0] *
                    @sin(p.wave_num_rgb[0] * eval_coord.coord_0),
                p.bias_rgb[1] + p.amplitudes_rgb[1] *
                    @cos(p.wave_num_rgb[1] * eval_coord.coord_1),
                p.bias_rgb[2] + p.amplitudes_rgb[2] *
                    @sin(p.wave_num_rgb[2] * (eval_coord.coord_0 + eval_coord.coord_1)),
            };
        },
        .sinusoidal_approx => blk: {
            const p = params.settings.sinusoidal_approx;
            break :blk .{
                p.bias_rgb[0] + p.amplitudes_rgb[0] *
                    sinApproxScalar(p.wave_num_rgb[0] * eval_coord.coord_0),
                p.bias_rgb[1] + p.amplitudes_rgb[1] *
                    cosApproxScalar(p.wave_num_rgb[1] * eval_coord.coord_1),
                p.bias_rgb[2] + p.amplitudes_rgb[2] *
                    sinApproxScalar(
                        p.wave_num_rgb[2] *
                            (eval_coord.coord_0 + eval_coord.coord_1),
                    ),
            };
        },
        .checker => blk: {
            const p = params.settings.checker;
            const cell_x: i64 = @intFromFloat(@floor(eval_coord.coord_0));
            const cell_y: i64 = @intFromFloat(@floor(eval_coord.coord_1));
            break :blk if (@mod(cell_x + cell_y, 2) == 0)
                p.levels_rgb[0]
            else
                p.levels_rgb[1];
        },
        .checker_smooth => blk: {
            const p = params.settings.checker_smooth;
            const phase_x = 0.5 + 0.5 * @sin(
                p.frequency * std.math.pi * eval_coord.coord_0,
            );
            const phase_y = 0.5 + 0.5 * @sin(
                p.frequency * std.math.pi * eval_coord.coord_1,
            );
            const base = cubicSmoothStep(phase_x * phase_y);
            break :blk .{
                base,
                cubicSmoothStep(1.0 - base),
                0.5 + 0.5 * @sin(2.0 * std.math.pi * base),
            };
        },
        .lambertian_normal_z => blk: {
            const p = params.settings.lambertian_normal_z;
            break :blk .{
                p.coeffs_rgb[0][0] + p.coeffs_rgb[0][1] * eval_coord.normal_z,
                p.coeffs_rgb[1][0] + p.coeffs_rgb[1][1] * eval_coord.normal_z,
                p.coeffs_rgb[2][0] + p.coeffs_rgb[2][1] * eval_coord.normal_z,
            };
        },
        .eggbox => blk: {
            const p = params.settings.eggbox;
            const phase_x = 2.0 * std.math.pi *
                (eval_coord.coord_0 + p.phase[0]) / p.pitch[0];
            const phase_y = 2.0 * std.math.pi *
                (eval_coord.coord_1 + p.phase[1]) / p.pitch[1];
            const value = p.mean +
                0.5 * p.contrast * (1.0 + @cos(phase_x)) * (1.0 + @cos(phase_y)) -
                p.contrast;
            break :blk .{ value, value, value };
        },
        .speckle => unreachable,
    };
    return .{
        applyFuncShaderOutputParams(vals[0], params),
        applyFuncShaderOutputParams(vals[1], params),
        applyFuncShaderOutputParams(vals[2], params),
    };
}

inline fn applyFuncShaderCoordParams(
    coord: FuncCoord,
    params: comm.FuncShaderParams,
) FuncCoord {
    var out = coord;
    out.coord_0 = params.coord_scale[0] * coord.coord_0 + params.coord_offset[0];
    out.coord_1 = params.coord_scale[1] * coord.coord_1 + params.coord_offset[1];
    return out;
}

inline fn applyFuncShaderOutputParams(value: F, params: comm.FuncShaderParams) F {
    return value * params.output_scale + params.output_offset;
}

inline fn cubicSmoothStep(val: F) F {
    const clamped = @max(0.0, @min(1.0, val));
    return clamped * clamped * (3.0 - 2.0 * clamped);
}

inline fn sinApproxScalar(val: F) F {
    const vals: [1]F = maths_simd.sinApproxSIMD(1, F, .{val});
    return vals[0];
}

inline fn cosApproxScalar(val: F) F {
    const vals: [1]F = maths_simd.cosApproxSIMD(1, F, .{val});
    return vals[0];
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

const testing = std.testing;
const unit_tol: F = if (F == f32) 1e-5 else 1e-12;

test "FuncShaderParams defaults preserve constant shader" {
    const coord = FuncCoord{
        .coord_0 = 0.25,
        .coord_1 = -0.5,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const value = evalFuncShaderBuiltinGreyNorm(
        .constant,
        coord,
        comm.normFuncShaderParams(.constant, .{}),
    );
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
    const base = evalFuncShaderBuiltinGreyNorm(
        .sinusoidal,
        coord,
        comm.normFuncShaderParams(.sinusoidal, .{}),
    );
    const shifted = evalFuncShaderBuiltinGreyNorm(
        .sinusoidal,
        coord,
        comm.normFuncShaderParams(.sinusoidal, .{
            .coord_scale = .{ 2.0, 1.0 },
            .output_scale = 2.0,
            .output_offset = -0.25,
        }),
    );
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
    const params = comm.FuncShaderParams{
        .coord_scale = .{ 36.0, 36.0 },
    };

    const value_black = evalFuncShaderBuiltinGreyNorm(
        .checker,
        coord_black,
        comm.normFuncShaderParams(.checker, params),
    );
    const value_white = evalFuncShaderBuiltinGreyNorm(
        .checker,
        coord_white,
        comm.normFuncShaderParams(.checker, params),
    );

    try testing.expectEqual(@as(F, 0.0), value_black);
    try testing.expectEqual(@as(F, 1.0), value_white);
}

test "RGB checker preserves distinct channel levels in scalar and SIMD" {
    const levels: [2][3]F = .{ .{ 0.1, 0.3, 0.7 }, .{ 0.9, 0.6, 0.2 } };
    const params: comm.FuncShaderParams = .{
        .settings = .{ .checker = .{ .levels_rgb = levels } },
    };
    for (levels, 0..) |expected, ii| {
        const u: F = @as(F, @floatFromInt(ii)) + 0.25;
        const scalar = evalFuncShaderBuiltinRGBNorm(.checker, .{
            .coord_0 = u,
            .coord_1 = 0.25,
            .normal_x = 0.0,
            .normal_y = 0.0,
            .normal_z = 1.0,
        }, params);
        try testing.expectEqual(expected, scalar);
        const vector = simd_impl.evalFuncShaderRGBNormSIMD(.checker, .{
            .coord_0 = @splat(u),
            .coord_1 = @splat(0.25),
            .normal_x = @splat(0.0),
            .normal_y = @splat(0.0),
            .normal_z = @splat(1.0),
        }, params);
        inline for (0..3) |ch| {
            const lanes: [S]F = vector[ch];
            for (lanes) |value| try testing.expectEqual(expected[ch], value);
        }
    }
}

test "eggbox reaches mean plus contrast at cell center" {
    const coord = FuncCoord{
        .coord_0 = 0.0,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const params = comm.FuncShaderParams{
        .settings = .{
            .eggbox = .{
                .mean = 0.5,
                .contrast = 0.4,
                .pitch = .{ 1.0, 1.0 },
            },
        },
    };
    const value = evalFuncShaderBuiltinGreyNorm(
        .eggbox,
        coord,
        comm.normFuncShaderParams(.eggbox, params),
    );
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
    const params = comm.FuncShaderParams{
        .settings = .{
            .eggbox = .{
                .mean = 0.5,
                .contrast = 0.4,
                .pitch = .{ 1.0, 1.0 },
            },
        },
    };
    const value = evalFuncShaderBuiltinGreyNorm(
        .eggbox,
        coord,
        comm.normFuncShaderParams(.eggbox, params),
    );
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
    const coord_simd = simd_impl.FuncCoordSIMD{
        .coord_0 = .{
            coord_scalar[0].coord_0,
            coord_scalar[1].coord_0,
            coord_scalar[2].coord_0,
            coord_scalar[3].coord_0,
        } ++ [_]F{0.0} ** (S - 4),
        .coord_1 = .{
            coord_scalar[0].coord_1,
            coord_scalar[1].coord_1,
            coord_scalar[2].coord_1,
            coord_scalar[3].coord_1,
        } ++ [_]F{0.0} ** (S - 4),
        .normal_x = .{
            coord_scalar[0].normal_x,
            coord_scalar[1].normal_x,
            coord_scalar[2].normal_x,
            coord_scalar[3].normal_x,
        } ++ [_]F{0.0} ** (S - 4),
        .normal_y = .{
            coord_scalar[0].normal_y,
            coord_scalar[1].normal_y,
            coord_scalar[2].normal_y,
            coord_scalar[3].normal_y,
        } ++ [_]F{0.0} ** (S - 4),
        .normal_z = .{
            coord_scalar[0].normal_z,
            coord_scalar[1].normal_z,
            coord_scalar[2].normal_z,
            coord_scalar[3].normal_z,
        } ++ [_]F{0.0} ** (S - 4),
    };
    const params = comm.FuncShaderParams{
        .coord_scale = .{ 1.7, 0.8 },
        .coord_offset = .{ -0.1, 0.3 },
        .output_scale = 1.25,
        .output_offset = -0.05,
    };

    const scalar_builtins = [_]comm.FuncShaderBuiltin{
        .constant,
        .linear,
        .quadratic,
        .sinusoidal,
        .sinusoidal_approx,
        .checker,
        .checker_smooth,
        .lambertian_normal_z,
        .eggbox,
    };
    for (scalar_builtins) |builtin| {
        const v_vals = simd_impl.evalFuncShaderGreyNormSIMD(
            builtin,
            coord_simd,
            comm.normFuncShaderParams(builtin, params),
        );
        const vals_arr: [S]F = v_vals;
        for (coord_scalar, 0..) |coord, ll| {
            const expected = evalFuncShaderBuiltinGreyNorm(
                builtin,
                coord,
                comm.normFuncShaderParams(builtin, params),
            );
            try testing.expectApproxEqAbs(expected, vals_arr[ll], unit_tol);
        }

        const v_rgb = simd_impl.evalFuncShaderRGBNormSIMD(
            builtin,
            coord_simd,
            comm.normFuncShaderParams(builtin, params),
        );
        inline for (0..3) |ch| {
            const vals_rgb_arr: [S]F = v_rgb[ch];
            for (coord_scalar, 0..) |coord, ll| {
                const expected = evalFuncShaderBuiltinRGBNorm(
                    builtin,
                    coord,
                    comm.normFuncShaderParams(builtin, params),
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

test "direct fixed scalar handles active inactive nonfinite and scaling" {
    if (comptime buildconfig.speckle_evaluator != .direct_fixed) return;

    const inactive: speckle.DirectFixedSpeckleCell2D = 0;
    const cells = [_]speckle.DirectFixedSpeckleCell2D{
        0x0000_8000_8000_0001,
        inactive,
        inactive,
        inactive,
        inactive,
        inactive,
    };
    const speckle_params: speckle.Speckle2DParams = .{
        .cells_per_uv = .{ 2.0, 1.0 },
        .occupancy = 0.5,
        .radius_mean = 0.25,
        .foreground = 0.2,
        .background = 0.8,
    };
    const direct: speckle.DirectFixedSpeckle2D = .{
        .params = speckle_params,
        .cells = &cells,
        .cell_origin = .{ 0, 0 },
        .cell_dims = .{ 3, 2 },
        .radius2 = 0.25 * 0.25,
    };
    const shader: comm.FuncPrepared = .{
        .elem_uvs = null,
        .speckle_resources = .{ .direct_fixed = direct },
        .builtin = .speckle,
        .params = .{
            .output_scale = 1.75,
            .output_offset = -0.125,
            .settings = .{ .speckle = speckle_params },
        },
    };
    const foreground = speckle_params.foreground * shader.params.output_scale +
        shader.params.output_offset;
    const background = speckle_params.background * shader.params.output_scale +
        shader.params.output_offset;
    const coords = [_][2]F{
        .{ 0.25, 0.5 },
        .{ 0.1, 0.5 },
        .{ 0.75, 0.5 },
        .{ std.math.nan(F), 0.5 },
        .{ 0.25, std.math.inf(F) },
    };
    for (coords, 0..) |uv, index| {
        const actual = evalFuncShaderGreyPreparedScal(&shader, .{
            .coord_0 = uv[0],
            .coord_1 = uv[1],
            .normal_x = 0.0,
            .normal_y = 0.0,
            .normal_z = 0.0,
        });
        try std.testing.expectEqual(if (index == 0) foreground else background, actual);
    }
}

test "u8 speckle mask scalar sampling handles scaling and nonfinite UVs" {
    if (comptime buildconfig.speckle_evaluator != .mask_u8) return;

    const bits = [_]u8{ 0, 64, 128, 255 };
    const mask_params: speckle.Speckle2DParams = .{
        .foreground = 0.8,
        .background = 0.2,
    };
    const mask: speckle.SpeckleMask2D = .{
        .bits = &bits,
        .dims = .{ 2, 2 },
        .row_stride = 2,
        .uv_to_texel = .{ 1.0, 1.0 },
        .params = mask_params,
    };
    const params: comm.FuncShaderParams = .{
        .output_scale = 1.75,
        .output_offset = -0.125,
        .settings = .{ .speckle = mask_params },
    };
    const shader: comm.FuncPrepared = .{
        .elem_uvs = null,
        .speckle_resources = .{ .mask = mask },
        .builtin = .speckle,
        .params = params,
    };

    const coverage: F = 64.0 / 255.0;
    const expected = (mask_params.background +
        coverage * (mask_params.foreground - mask_params.background)) *
        params.output_scale + params.output_offset;
    const expected_background = mask_params.background * params.output_scale +
        params.output_offset;
    const coords = [_][2]F{
        .{ 1.0, 0.0 },
        .{ std.math.nan(F), 0.0 },
        .{ 0.0, std.math.inf(F) },
    };
    const expected_values = [_]F{ expected, expected_background, expected_background };
    for (coords, expected_values) |uv, expected_value| {
        const actual = evalFuncShaderGreyPreparedScal(&shader, .{
            .coord_0 = uv[0],
            .coord_1 = uv[1],
            .normal_x = 0.0,
            .normal_y = 0.0,
            .normal_z = 0.0,
        });
        try std.testing.expectEqual(expected_value, actual);
    }
}
