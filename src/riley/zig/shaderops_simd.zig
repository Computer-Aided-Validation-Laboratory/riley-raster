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
const cfg = @import("buildconfig.zig").config;
const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSI = buildconfig.VecSI;
const VecSF = buildconfig.VecSF;

const MatSlice = @import("matslice.zig").MatSlice;
const maths_simd = @import("maths_simd.zig");
const texops = @import("textureops.zig");
const TexSampConfig = texops.TexSampConfig;
const comm = @import("shaderops_common.zig");
const speckle = @import("speckleops.zig");
const simdops = @import("simdops.zig");
const scal = if (@import("builtin").is_test)
    @import("shaderops_scalar.zig")
else
    struct {};

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const FuncCoordSIMD = struct {
    coord_0: VecSF,
    coord_1: VecSF,
    normal_x: VecSF,
    normal_y: VecSF,
    normal_z: VecSF,
};

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

inline fn storeShadeSIMD(
    subpx_vals: []F,
    start_u: usize,
    ctx_shade: comm.ShadeContext,
    v_mask_active: VecSB,
    v_vals: VecSF,
) void {
    if (!ctx_shade.exclusive_subpx_target) {
        simdops.storeMaskedVecSF(
            subpx_vals,
            start_u,
            v_mask_active,
            v_vals,
        );
        return;
    }

    const mask_arr: [S]bool = v_mask_active;
    const vals_arr: [S]F = v_vals;
    inline for (0..S) |lane| {
        if (mask_arr[lane]) {
            subpx_vals[start_u + lane] = vals_arr[lane];
        }
    }
}

pub inline fn fillNodalClipSIMD(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    shader_buf: *const comm.LocalShaderBuff(N),
    v_weights: [N]VecSF,
    shader: *const comm.NodalPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(shader.scale_mul);
    const v_splat_add: VecSF = @splat(shader.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..cfg.max_nodal_fields) |ff| {
        if (ff >= @as(usize, ctx_shade.actual_fields)) break;

        const base = ff * N;
        var v_weighted_sum: VecSF = @splat(0.0);
        inline for (0..N) |nn| {
            v_weighted_sum += v_weights[nn] *
                @as(VecSF, @splat(shader_buf.data[base + nn]));
        }

        const v_final = v_weighted_sum * v_splat_mul + v_splat_add;
        const flat_idx = ff * px_stride + ctx_shade.scratch_idx;
        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            ctx_shade.v_mask_active.?,
            v_final,
        );
    }
}

pub inline fn fillNodalPerspSIMD(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    shader_buf: *const comm.LocalShaderBuff(N),
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader: *const comm.NodalPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(shader.scale_mul);
    const v_splat_add: VecSF = @splat(shader.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..cfg.max_nodal_fields) |ff| {
        if (ff >= @as(usize, ctx_shade.actual_fields)) break;

        const base = ff * N;
        var v_weighted_sum: VecSF = @splat(0.0);
        inline for (0..N) |nn| {
            v_weighted_sum += v_weights[nn] * v_nodes_inv_z[nn] *
                @as(VecSF, @splat(shader_buf.data[base + nn]));
        }

        const v_final = (v_weighted_sum * v_subpx_z) * v_splat_mul + v_splat_add;
        const flat_idx = ff * px_stride + ctx_shade.scratch_idx;

        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            ctx_shade.v_mask_active.?,
            v_final,
        );
    }
}

// --------------------------------------------------------------------------------------
// Texture Shader
// --------------------------------------------------------------------------------------

fn texSimdInterpMode(
    comptime C: comptime_int,
    comptime samp_cfg: TexSampConfig,
) buildconfig.SimdTexInterpMode {
    return buildconfig.TexSIMDPolicy.resolve(
        C,
        samp_cfg.sample == .linear,
        samp_cfg.mode == .lut or samp_cfg.mode == .lut_lerp,
    );
}

pub inline fn fillTexClipSIMD(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: TexSampConfig,
    ctx_shade: comm.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_image_scratch: *MatSlice(F),
) void {
    var v_tex_u: VecSF = @splat(0.0);
    var v_tex_v: VecSF = @splat(0.0);
    inline for (0..N) |nn| {
        v_tex_u += v_weights[nn] * @as(VecSF, @splat(shader_buf.data[nn]));
        v_tex_v += v_weights[nn] * @as(VecSF, @splat(shader_buf.data[N + nn]));
    }

    const px_stride = spx_image_scratch.cols_num;
    const sampled_vecs = switch (comptime texSimdInterpMode(C, samp_cfg)) {
        .inner => texops.sampLanes(
            C,
            samp_cfg,
            v_mask_active,
            shader.tex,
            v_tex_u,
            v_tex_v,
        ),
        .over_pixels => texops.sampWide(
            C,
            samp_cfg,
            shader.tex,
            v_tex_u,
            v_tex_v,
        ),
    };

    inline for (0..C) |ch| {
        const v_final = sampled_vecs[ch] *
            @as(VecSF, @splat(shader.scale_mul)) +
            @as(VecSF, @splat(shader.scale_add));

        const flat_idx = ch * px_stride + ctx_shade.scratch_idx;

        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
    }
}

pub inline fn fillTexPerspSIMD(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: TexSampConfig,
    ctx_shade: comm.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(shader.scale_mul);
    const v_splat_add: VecSF = @splat(shader.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    var v_tex_u: VecSF = @splat(0.0);
    var v_tex_v: VecSF = @splat(0.0);
    inline for (0..N) |nn| {
        const v_inv_z = v_nodes_inv_z[nn];
        v_tex_u += v_weights[nn] *
            @as(VecSF, @splat(shader_buf.data[nn])) * v_inv_z;
        v_tex_v += v_weights[nn] *
            @as(VecSF, @splat(shader_buf.data[N + nn])) * v_inv_z;
    }

    v_tex_u *= v_subpx_z;
    v_tex_v *= v_subpx_z;

    const sampled_vecs = switch (comptime texSimdInterpMode(
        C,
        samp_cfg,
    )) {
        .inner => if (comptime N == 3)
            texops.sampLanesTri3(
                C,
                samp_cfg,
                v_mask_active,
                shader.tex,
                v_tex_u,
                v_tex_v,
            )
        else
            texops.sampLanes(
                C,
                samp_cfg,
                v_mask_active,
                shader.tex,
                v_tex_u,
                v_tex_v,
            ),
        .over_pixels => texops.sampWide(
            C,
            samp_cfg,
            shader.tex,
            v_tex_u,
            v_tex_v,
        ),
    };

    inline for (0..C) |ch| {
        const v_final = sampled_vecs[ch] * v_splat_mul + v_splat_add;
        const flat_idx = ch * px_stride + ctx_shade.scratch_idx;
        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
    }
}

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

pub inline fn evalFuncShaderGreyNormSIMD(
    builtin: comm.FuncShaderBuiltin,
    coord: FuncCoordSIMD,
    params: comm.FuncShaderParams,
) VecSF {
    if (builtin == .speckle) {
        const value = speckle.sampleSIMD(
            coord.coord_0,
            coord.coord_1,
            @splat(true),
            params.settings.speckle,
            &.{},
        );
        return applyFuncShaderOutputParamsSIMD(value, params);
    }
    return evalNonSpeckleGreyNormSIMD(builtin, coord, params);
}

// Keep the raw API's runtime speckle fallback out of production shader kernels.
inline fn evalNonSpeckleGreyNormSIMD(
    builtin: comm.FuncShaderBuiltin,
    coord: FuncCoordSIMD,
    params: comm.FuncShaderParams,
) VecSF {
    const eval_coord = applyFuncShaderCoordParamsSIMD(coord, params);
    const v_value = switch (builtin) {
        .constant => blk: {
            const p = params.settings.constant;
            break :blk @as(VecSF, @splat(p.value));
        },
        .linear => blk: {
            const p = params.settings.linear;
            break :blk @as(VecSF, @splat(p.coeffs[0])) +
                @as(VecSF, @splat(p.coeffs[1])) * eval_coord.coord_0 +
                @as(VecSF, @splat(p.coeffs[2])) * eval_coord.coord_1;
        },
        .quadratic => blk: {
            const p = params.settings.quadratic;
            const coord_u = eval_coord.coord_0;
            const coord_v = eval_coord.coord_1;
            const c = p.coeffs;
            const term_u = coord_u * (@as(VecSF, @splat(c[1])) +
                @as(VecSF, @splat(c[3])) * coord_u);
            const term_v = coord_v * (@as(VecSF, @splat(c[2])) +
                @as(VecSF, @splat(c[4])) * coord_u +
                @as(VecSF, @splat(c[5])) * coord_v);
            break :blk @as(VecSF, @splat(c[0])) + term_u + term_v;
        },
        .sinusoidal => blk: {
            const p = params.settings.sinusoidal;
            const v_bias: VecSF = @splat(p.bias);
            const v_amp_0: VecSF = @splat(p.amplitudes[0]);
            const v_amp_1: VecSF = @splat(p.amplitudes[1]);
            const v_wave_num_0: VecSF = @splat(p.wave_num_scalar[0]);
            const v_wave_num_1: VecSF = @splat(p.wave_num_scalar[1]);
            break :blk v_bias +
                v_amp_0 * @sin(v_wave_num_0 * eval_coord.coord_0) +
                v_amp_1 * @cos(v_wave_num_1 * eval_coord.coord_1);
        },
        .sinusoidal_approx => blk: {
            const p = params.settings.sinusoidal_approx;
            const v_bias: VecSF = @splat(p.bias);
            const v_amp_0: VecSF = @splat(p.amplitudes[0]);
            const v_amp_1: VecSF = @splat(p.amplitudes[1]);
            const v_wave_num_0: VecSF = @splat(p.wave_num_scalar[0]);
            const v_wave_num_1: VecSF = @splat(p.wave_num_scalar[1]);
            break :blk v_bias +
                v_amp_0 * maths_simd.sinApproxSIMD(
                    S,
                    F,
                    v_wave_num_0 * eval_coord.coord_0,
                ) +
                v_amp_1 * maths_simd.cosApproxSIMD(
                    S,
                    F,
                    v_wave_num_1 * eval_coord.coord_1,
                );
        },
        .checker => blk: {
            const p = params.settings.checker;
            const v_cell_x: VecSI = @intFromFloat(@floor(eval_coord.coord_0));
            const v_cell_y: VecSI = @intFromFloat(@floor(eval_coord.coord_1));
            const v_parity = @mod(
                v_cell_x + v_cell_y,
                @as(VecSI, @splat(2)),
            ) == @as(VecSI, @splat(0));
            break :blk @select(
                F,
                @as(VecSB, v_parity),
                @as(VecSF, @splat(p.levels[0])),
                @as(VecSF, @splat(p.levels[1])),
            );
        },
        .checker_smooth => blk: {
            const p = params.settings.checker_smooth;
            const v_half: VecSF = @splat(0.5);
            const v_freq_pi: VecSF = @splat(p.frequency * std.math.pi);
            const v_phase_x = v_half +
                v_half * @sin(v_freq_pi * eval_coord.coord_0);
            const v_phase_y = v_half +
                v_half * @sin(v_freq_pi * eval_coord.coord_1);
            break :blk cubicSmoothStepSIMD(v_phase_x * v_phase_y);
        },
        .lambertian_normal_z => blk: {
            const p = params.settings.lambertian_normal_z;
            break :blk @as(VecSF, @splat(p.coeffs[0])) +
                @as(VecSF, @splat(p.coeffs[1])) * eval_coord.normal_z;
        },
        .eggbox => blk: {
            const p = params.settings.eggbox;
            const v_two_pi: VecSF = @splat(2.0 * std.math.pi);
            const v_phase_0: VecSF = @splat(p.phase[0]);
            const v_phase_1: VecSF = @splat(p.phase[1]);
            const v_pitch_0: VecSF = @splat(p.pitch[0]);
            const v_pitch_1: VecSF = @splat(p.pitch[1]);
            const v_mean: VecSF = @splat(p.mean);
            const v_half_contrast: VecSF = @splat(0.5 * p.contrast);
            const v_contrast: VecSF = @splat(p.contrast);
            const v_one: VecSF = @splat(1.0);
            const v_phase_x = v_two_pi * (eval_coord.coord_0 + v_phase_0) / v_pitch_0;
            const v_phase_y = v_two_pi * (eval_coord.coord_1 + v_phase_1) / v_pitch_1;
            break :blk v_mean + v_half_contrast * (v_one + @cos(v_phase_x)) *
                (v_one + @cos(v_phase_y)) - v_contrast;
        },
        .speckle => unreachable,
    };
    return applyFuncShaderOutputParamsSIMD(v_value, params);
}

fn evalFuncShaderGreyPreparedSIMD(
    comptime speckle_kernel: ?usize,
    shader: *const comm.FuncPrepared,
    coord: FuncCoordSIMD,
    v_mask_active: VecSB,
) VecSF {
    if (comptime speckle_kernel != null) {
        const v_value = speckle.Kernel(speckle_kernel.?).sampleSIMD(
            coord.coord_0,
            coord.coord_1,
            v_mask_active,
            shader.params.settings.speckle,
            &shader.speckle_resources,
        );
        return applyFuncShaderOutputParamsSIMD(v_value, shader.params);
    } else {
        return evalNonSpeckleGreyNormSIMD(shader.builtin, coord, shader.params);
    }
}

pub inline fn evalFuncShaderRGBNormSIMD(
    builtin: comm.FuncShaderBuiltin,
    coord: FuncCoordSIMD,
    params: comm.FuncShaderParams,
) [3]VecSF {
    const eval_coord = applyFuncShaderCoordParamsSIMD(coord, params);

    const v_vals = switch (builtin) {
        .constant => blk: {
            const p = params.settings.constant;
            break :blk .{
                @as(VecSF, @splat(p.value_rgb[0])),
                @as(VecSF, @splat(p.value_rgb[1])),
                @as(VecSF, @splat(p.value_rgb[2])),
            };
        },
        .linear => blk: {
            const p = params.settings.linear;
            const c = p.coeffs_rgb;
            break :blk .{
                @as(VecSF, @splat(c[0][0])) +
                    @as(VecSF, @splat(c[0][1])) * eval_coord.coord_0 +
                    @as(VecSF, @splat(c[0][2])) * eval_coord.coord_1,
                @as(VecSF, @splat(c[1][0])) +
                    @as(VecSF, @splat(c[1][1])) * eval_coord.coord_0 +
                    @as(VecSF, @splat(c[1][2])) * eval_coord.coord_1,
                @as(VecSF, @splat(c[2][0])) +
                    @as(VecSF, @splat(c[2][1])) * eval_coord.coord_0 +
                    @as(VecSF, @splat(c[2][2])) * eval_coord.coord_1,
            };
        },
        .quadratic => blk: {
            const p = params.settings.quadratic;
            const coord_u = eval_coord.coord_0;
            const coord_v = eval_coord.coord_1;
            const c = p.coeffs_rgb;

            const val_r = @as(VecSF, @splat(c[0][0])) +
                coord_u * (@as(VecSF, @splat(c[0][1])) +
                    @as(VecSF, @splat(c[0][3])) * coord_u) +
                coord_v * (@as(VecSF, @splat(c[0][2])) +
                    @as(VecSF, @splat(c[0][4])) * coord_u +
                    @as(VecSF, @splat(c[0][5])) * coord_v);
            const val_g = @as(VecSF, @splat(c[1][0])) +
                coord_u * (@as(VecSF, @splat(c[1][1])) +
                    @as(VecSF, @splat(c[1][3])) * coord_u) +
                coord_v * (@as(VecSF, @splat(c[1][2])) +
                    @as(VecSF, @splat(c[1][4])) * coord_u +
                    @as(VecSF, @splat(c[1][5])) * coord_v);
            const val_b = @as(VecSF, @splat(c[2][0])) +
                coord_u * (@as(VecSF, @splat(c[2][1])) +
                    @as(VecSF, @splat(c[2][3])) * coord_u) +
                coord_v * (@as(VecSF, @splat(c[2][2])) +
                    @as(VecSF, @splat(c[2][4])) * coord_u +
                    @as(VecSF, @splat(c[2][5])) * coord_v);

            break :blk .{ val_r, val_g, val_b };
        },
        .sinusoidal => blk: {
            const p = params.settings.sinusoidal;
            const v_bias_0: VecSF = @splat(p.bias_rgb[0]);
            const v_bias_1: VecSF = @splat(p.bias_rgb[1]);
            const v_bias_2: VecSF = @splat(p.bias_rgb[2]);
            const v_amp_0: VecSF = @splat(p.amplitudes_rgb[0]);
            const v_amp_1: VecSF = @splat(p.amplitudes_rgb[1]);
            const v_amp_2: VecSF = @splat(p.amplitudes_rgb[2]);
            const v_wave_num_0: VecSF = @splat(p.wave_num_rgb[0]);
            const v_wave_num_1: VecSF = @splat(p.wave_num_rgb[1]);
            const v_wave_num_2: VecSF = @splat(p.wave_num_rgb[2]);
            const v_coord_sum = eval_coord.coord_0 + eval_coord.coord_1;

            break :blk .{
                v_bias_0 + v_amp_0 * @sin(v_wave_num_0 * eval_coord.coord_0),
                v_bias_1 + v_amp_1 * @cos(v_wave_num_1 * eval_coord.coord_1),
                v_bias_2 + v_amp_2 * @sin(v_wave_num_2 * v_coord_sum),
            };
        },
        .sinusoidal_approx => blk: {
            const p = params.settings.sinusoidal_approx;
            const v_bias_0: VecSF = @splat(p.bias_rgb[0]);
            const v_bias_1: VecSF = @splat(p.bias_rgb[1]);
            const v_bias_2: VecSF = @splat(p.bias_rgb[2]);

            const v_amp_0: VecSF = @splat(p.amplitudes_rgb[0]);
            const v_amp_1: VecSF = @splat(p.amplitudes_rgb[1]);
            const v_amp_2: VecSF = @splat(p.amplitudes_rgb[2]);

            const v_wave_num_0: VecSF = @splat(p.wave_num_rgb[0]);
            const v_wave_num_1: VecSF = @splat(p.wave_num_rgb[1]);
            const v_wave_num_2: VecSF = @splat(p.wave_num_rgb[2]);

            const v_coord_sum = eval_coord.coord_0 + eval_coord.coord_1;

            const v_wc0 = v_wave_num_0 * eval_coord.coord_0;
            const v_wc1 = v_wave_num_1 * eval_coord.coord_1;
            const v_wc2 = v_wave_num_2 * v_coord_sum;

            break :blk .{
                v_bias_0 + v_amp_0 * maths_simd.sinApproxSIMD(S, F, v_wc0),
                v_bias_1 + v_amp_1 * maths_simd.cosApproxSIMD(S, F, v_wc1),
                v_bias_2 + v_amp_2 * maths_simd.sinApproxSIMD(S, F, v_wc2),
            };
        },
        .checker => blk: {
            const p = params.settings.checker;
            const v_cell_x: VecSI = @intFromFloat(@floor(eval_coord.coord_0));
            const v_cell_y: VecSI = @intFromFloat(@floor(eval_coord.coord_1));

            const v_0: VecSI = @splat(0);
            const v_2: VecSI = @splat(2);

            const v_parity = @as(VecSB, @mod(v_cell_x + v_cell_y, v_2) == v_0);
            const v_r0 = @as(VecSF, @splat(p.levels_rgb[0][0]));
            const v_r1 = @as(VecSF, @splat(p.levels_rgb[1][0]));
            const v_g0 = @as(VecSF, @splat(p.levels_rgb[0][1]));
            const v_g1 = @as(VecSF, @splat(p.levels_rgb[1][1]));
            const v_b0 = @as(VecSF, @splat(p.levels_rgb[0][2]));
            const v_b1 = @as(VecSF, @splat(p.levels_rgb[1][2]));

            break :blk .{
                @select(F, v_parity, v_r0, v_r1),
                @select(F, v_parity, v_g0, v_g1),
                @select(F, v_parity, v_b0, v_b1),
            };
        },
        .checker_smooth => blk: {
            const p = params.settings.checker_smooth;

            const v_half: VecSF = @splat(0.5);
            const v_one: VecSF = @splat(1.0);
            const v_two_pi: VecSF = @splat(2.0 * std.math.pi);
            const v_freq_pi: VecSF = @splat(p.frequency * std.math.pi);

            const v_phase_x = v_half + v_half * @sin(v_freq_pi * eval_coord.coord_0);
            const v_phase_y = v_half + v_half * @sin(v_freq_pi * eval_coord.coord_1);
            const v_base = cubicSmoothStepSIMD(v_phase_x * v_phase_y);

            break :blk .{
                v_base,
                cubicSmoothStepSIMD(v_one - v_base),
                v_half + v_half * @sin(v_two_pi * v_base),
            };
        },
        .lambertian_normal_z => blk: {
            const p = params.settings.lambertian_normal_z;
            const v_c00: VecSF = @as(VecSF, @splat(p.coeffs_rgb[0][0]));
            const v_c01: VecSF = @as(VecSF, @splat(p.coeffs_rgb[0][1]));
            const v_c10: VecSF = @as(VecSF, @splat(p.coeffs_rgb[1][0]));
            const v_c11: VecSF = @as(VecSF, @splat(p.coeffs_rgb[1][1]));
            const v_c20: VecSF = @as(VecSF, @splat(p.coeffs_rgb[2][0]));
            const v_c21: VecSF = @as(VecSF, @splat(p.coeffs_rgb[2][1]));

            break :blk .{
                v_c00 + v_c01 * eval_coord.normal_z,
                v_c10 + v_c11 * eval_coord.normal_z,
                v_c20 + v_c21 * eval_coord.normal_z,
            };
        },
        .eggbox => blk: {
            const p = params.settings.eggbox;
            const v_two_pi: VecSF = @splat(2.0 * std.math.pi);

            const v_phase_0: VecSF = @splat(p.phase[0]);
            const v_phase_1: VecSF = @splat(p.phase[1]);
            const v_pitch_0: VecSF = @splat(p.pitch[0]);
            const v_pitch_1: VecSF = @splat(p.pitch[1]);

            const v_mean: VecSF = @splat(p.mean);
            const v_half_contrast: VecSF = @splat(0.5 * p.contrast);
            const v_contrast: VecSF = @splat(p.contrast);
            const v_one: VecSF = @splat(1.0);

            const v_phase_x = v_two_pi * (eval_coord.coord_0 + v_phase_0) / v_pitch_0;
            const v_phase_y = v_two_pi * (eval_coord.coord_1 + v_phase_1) / v_pitch_1;

            const v_value = v_mean + v_half_contrast * (v_one + @cos(v_phase_x)) *
                (v_one + @cos(v_phase_y)) - v_contrast;

            break :blk .{ v_value, v_value, v_value };
        },
        .speckle => unreachable,
    };
    return .{
        applyFuncShaderOutputParamsSIMD(v_vals[0], params),
        applyFuncShaderOutputParamsSIMD(v_vals[1], params),
        applyFuncShaderOutputParamsSIMD(v_vals[2], params),
    };
}

inline fn applyFuncShaderCoordParamsSIMD(
    coord: FuncCoordSIMD,
    params: comm.FuncShaderParams,
) FuncCoordSIMD {
    var out = coord;
    out.coord_0 = @as(VecSF, @splat(params.coord_scale[0])) * coord.coord_0 +
        @as(VecSF, @splat(params.coord_offset[0]));
    out.coord_1 = @as(VecSF, @splat(params.coord_scale[1])) * coord.coord_1 +
        @as(VecSF, @splat(params.coord_offset[1]));
    return out;
}

inline fn applyFuncShaderOutputParamsSIMD(
    v_value: VecSF,
    params: comm.FuncShaderParams,
) VecSF {
    return v_value * @as(VecSF, @splat(params.output_scale)) +
        @as(VecSF, @splat(params.output_offset));
}

inline fn cubicSmoothStepSIMD(v_val: VecSF) VecSF {
    const v_zero: VecSF = @splat(0.0);
    const v_one: VecSF = @splat(1.0);
    const clamped = @max(v_zero, @min(v_one, v_val));
    return clamped * clamped * (@as(VecSF, @splat(3.0)) -
        @as(VecSF, @splat(2.0)) * clamped);
}

fn calcNormalLaneVecs(
    comptime N: usize,
    has_normals: bool,
    shader_buf: *const comm.LocalShaderBuff(N),
    v_weights: [N]VecSF,
) [3]VecSF {
    var normal_vecs = [3]VecSF{ @splat(0.0), @splat(0.0), @splat(0.0) };

    if (!has_normals) {
        normal_vecs[2] = @splat(1.0);
        return normal_vecs;
    }

    inline for (0..N) |nn| {
        const v_norm0 = @as(VecSF, @splat(shader_buf.normals[0 * N + nn]));
        const v_norm1 = @as(VecSF, @splat(shader_buf.normals[1 * N + nn]));
        const v_norm2 = @as(VecSF, @splat(shader_buf.normals[2 * N + nn]));

        normal_vecs[0] += v_weights[nn] * v_norm0;
        normal_vecs[1] += v_weights[nn] * v_norm1;
        normal_vecs[2] += v_weights[nn] * v_norm2;
    }

    return normal_vecs;
}

pub inline fn fillFuncClipSIMD(
    comptime N: usize,
    comptime C: usize,
    comptime speckle_kernel: ?usize,
    ctx_shade: comm.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    var v_coord_0: VecSF = v_xi;
    var v_coord_1: VecSF = v_eta;

    switch (shader.coord_mode) {
        .uv, .world_reference, .world_deformed => {
            v_coord_0 = @splat(0.0);
            v_coord_1 = @splat(0.0);

            inline for (0..N) |nn| {
                const v_fc0 = @as(VecSF, @splat(shader_buf.func_coords[nn]));
                const v_fc1 = @as(VecSF, @splat(shader_buf.func_coords[N + nn]));
                v_coord_0 += v_weights[nn] * v_fc0;
                v_coord_1 += v_weights[nn] * v_fc1;
            }
        },
        .para => {},
    }

    const normal_vecs = if (comptime speckle_kernel != null)
        [3]VecSF{ @splat(0.0), @splat(0.0), @splat(1.0) }
    else
        calcNormalLaneVecs(
            N,
            shader.elem_normals != null,
            shader_buf,
            v_weights,
        );

    const px_stride = spx_image_scratch.cols_num;
    const scratch_idx = ctx_shade.scratch_idx;

    const coord = FuncCoordSIMD{
        .coord_0 = v_coord_0,
        .coord_1 = v_coord_1,
        .normal_x = normal_vecs[0],
        .normal_y = normal_vecs[1],
        .normal_z = normal_vecs[2],
    };
    const params = shader.params;

    if (comptime C == 1) {
        const v_eval = evalFuncShaderGreyPreparedSIMD(speckle_kernel, shader, coord, v_mask_active);
        const v_mul = @as(VecSF, @splat(shader.scale_mul));
        const v_add = @as(VecSF, @splat(shader.scale_add));
        const v_final = v_eval * v_mul + v_add;

        const flat_idx = scratch_idx;

        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
        return;
    }

    const v_vals = evalFuncShaderRGBNormSIMD(
        shader.builtin,
        coord,
        params,
    );

    inline for (0..C) |ch| {
        const v_mul = @as(VecSF, @splat(shader.scale_mul));
        const v_add = @as(VecSF, @splat(shader.scale_add));
        const v_final = v_vals[ch] * v_mul + v_add;
        const flat_idx = ch * px_stride + scratch_idx;

        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
    }
}

pub inline fn fillFuncPerspSIMD(
    comptime N: usize,
    comptime C: usize,
    comptime speckle_kernel: ?usize,
    ctx_shade: comm.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    var v_coord_0: VecSF = v_xi;
    var v_coord_1: VecSF = v_eta;

    switch (shader.coord_mode) {
        .uv, .world_reference, .world_deformed => {
            v_coord_0 = @splat(0.0);
            v_coord_1 = @splat(0.0);

            inline for (0..N) |nn| {
                const v_inv_z = v_nodes_inv_z[nn];
                const v_fc0 = @as(VecSF, @splat(shader_buf.func_coords[nn]));
                const v_fc1 = @as(VecSF, @splat(shader_buf.func_coords[N + nn]));

                v_coord_0 += v_weights[nn] * v_fc0 * v_inv_z;
                v_coord_1 += v_weights[nn] * v_fc1 * v_inv_z;
            }

            v_coord_0 *= v_subpx_z;
            v_coord_1 *= v_subpx_z;
        },
        .para => {},
    }

    const normal_vecs = if (comptime speckle_kernel != null)
        [3]VecSF{ @splat(0.0), @splat(0.0), @splat(1.0) }
    else
        calcNormalLaneVecs(
            N,
            shader.elem_normals != null,
            shader_buf,
            v_weights,
        );

    const px_stride = spx_image_scratch.cols_num;
    const scratch_idx = ctx_shade.scratch_idx;
    const coord = FuncCoordSIMD{
        .coord_0 = v_coord_0,
        .coord_1 = v_coord_1,
        .normal_x = normal_vecs[0],
        .normal_y = normal_vecs[1],
        .normal_z = normal_vecs[2],
    };
    const params = shader.params;

    if (comptime C == 1) {
        const v_eval = evalFuncShaderGreyPreparedSIMD(speckle_kernel, shader, coord, v_mask_active);
        const v_mul = @as(VecSF, @splat(shader.scale_mul));
        const v_add = @as(VecSF, @splat(shader.scale_add));
        const v_final = v_eval * v_mul + v_add;

        const flat_idx = scratch_idx;
        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
        return;
    }

    const v_vals = evalFuncShaderRGBNormSIMD(
        shader.builtin,
        coord,
        params,
    );
    inline for (0..C) |ch| {
        const v_mul = @as(VecSF, @splat(shader.scale_mul));
        const v_add = @as(VecSF, @splat(shader.scale_add));
        const v_final = v_vals[ch] * v_mul + v_add;
        const flat_idx = ch * px_stride + scratch_idx;
        storeShadeSIMD(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade,
            v_mask_active,
            v_final,
        );
    }
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "ordinary prepared functions retain scalar and SIMD output scaling" {
    const params = comm.normFuncShaderParams(.linear, .{
        .output_scale = 1.75,
        .output_offset = -0.125,
    });
    const shader: comm.FuncPrepared = .{
        .elem_uvs = null,
        .builtin = .linear,
        .params = params,
    };
    const coord: scal.FuncCoord = .{
        .coord_0 = 0.25,
        .coord_1 = 0.5,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
    const expected = scal.evalFuncShaderBuiltinGreyNorm(.linear, coord, params);
    const tol: F = if (F == f32) 1e-5 else 1e-12;
    try std.testing.expectApproxEqAbs(
        expected,
        scal.evalFuncShaderGreyPreparedScal(null, &shader, coord),
        tol,
    );
    const actual: [S]F = evalFuncShaderGreyPreparedSIMD(null, &shader, .{
        .coord_0 = @splat(coord.coord_0),
        .coord_1 = @splat(coord.coord_1),
        .normal_x = @splat(0.0),
        .normal_y = @splat(0.0),
        .normal_z = @splat(1.0),
    }, @splat(true));
    for (actual) |value| try std.testing.expectApproxEqAbs(expected, value, tol);
}

test "specialized speckle routing scaling and masked stores across patterns" {
    // Experimental builds inline all 25 kernels and their SIMD lane stores.
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
    const defaults = [_]speckle.Speckle2DParams{
        .{},
        .{ .edge_softness = 0.04 },
        .{ .pattern = .gaussian },
        .{ .pattern = .perlin },
    };
    const experiments = if (buildconfig.enable_all_evaluators)
        [_]speckle.Speckle2DParams{
            .{ .evaluator = .cell_hash, .neighbor_count = 4 },
            .{ .evaluator = .list_naive, .neighbor_count = 1 },
            .{ .evaluator = .direct_fixed },
            .{ .evaluator = .mask_1bit },
            .{ .evaluator = .mask_u8, .edge_softness = 0.04 },
        }
    else
        [_]speckle.Speckle2DParams{};
    const cases = defaults ++ experiments;
    const samples = [_]struct { uv: [2]F, active: bool = true }{
        .{ .uv = .{ -0.5, 0.0 } },
        .{ .uv = .{ 0.25, 0.625 }, .active = false },
        .{ .uv = .{ 0.0, 1.0 } },
        .{ .uv = .{ 1.0, 0.0 } },
        .{ .uv = .{ 0.25, 0.625 } },
        .{ .uv = .{ 1.25, -0.5 } },
    };
    const tol: F = if (F == f32) 1e-5 else 1e-12;
    const sentinel: F = -123.0;
    var shader_buf: comm.LocalShaderBuff(3) = .{};
    shader_buf.func_coords = .{ 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0 };
    shader_buf.actual_func_coords = 2;
    const ctx: comm.ShadeContext = .{
        .frame_idx = 0,
        .elem_idx = 0,
        .fields_num = 1,
        .actual_fields = 1,
        .scratch_idx = 1,
        .global_subx = 0,
        .global_suby = 0,
        .exclusive_subpx_target = true,
    };
    for (cases) |case| {
        var p = case;
        p.cells_per_uv = .{ 3.0, 2.0 };
        p.radius_mean = 0.25;
        p.foreground = 0.2;
        p.background = 0.8;
        var resources = try speckle.generateResources(std.testing.allocator, p);
        defer resources.deinit(std.testing.allocator);
        const params: comm.FuncShaderParams = .{
            .output_scale = 1.75,
            .output_offset = -0.125,
            .settings = .{ .speckle = p },
        };
        const shader: comm.FuncPrepared = .{
            .elem_uvs = null,
            .coord_mode = .uv,
            .speckle_resources = resources,
            .builtin = .speckle,
            .params = params,
            .scale_mul = 2.0,
            .scale_add = 0.375,
        };
        switch (resources.kernel_index.?) {
            inline 0...speckle.kernel_configs.len - 1 => |kernel_index| {
                for (0..(samples.len + S - 1) / S) |batch| {
                    var u: [S]F = undefined;
                    var v: [S]F = undefined;
                    var active: [S]bool = undefined;
                    for (0..S) |lane| {
                        const sample = samples[(batch * S + lane) % samples.len];
                        u[lane] = sample.uv[0];
                        v[lane] = sample.uv[1];
                        active[lane] = sample.active;
                    }

                    const v_u: VecSF = u;
                    const v_v: VecSF = v;
                    const weights = [3]VecSF{ @as(VecSF, @splat(1.0)) - v_u - v_v, v_u, v_v };
                    var clip_storage = [_]F{sentinel} ** (S + 2);
                    var persp_storage = clip_storage;
                    var clip = MatSlice(F).init(&clip_storage, 1, S + 2);
                    var persp = MatSlice(F).init(&persp_storage, 1, S + 2);
                    fillFuncClipSIMD(
                        3,
                        1,
                        kernel_index,
                        ctx,
                        active,
                        weights,
                        @splat(0.0),
                        @splat(0.0),
                        &shader_buf,
                        &shader,
                        &clip,
                    );
                    fillFuncPerspSIMD(
                        3,
                        1,
                        kernel_index,
                        ctx,
                        active,
                        weights,
                        @splat(0.0),
                        @splat(0.0),
                        .{ @splat(2.0), @splat(2.0), @splat(2.0) },
                        @splat(0.5),
                        &shader_buf,
                        &shader,
                        &persp,
                    );
                    for (0..S) |lane| {
                        const raw = speckle.sampleScal(u[lane], v[lane], p, &resources);
                        const expected = (raw * params.output_scale + params.output_offset) *
                            shader.scale_mul + shader.scale_add;
                        const interp: comm.InterpData(3) = .{
                            .weights = .{ 1.0 - u[lane] - v[lane], u[lane], v[lane] },
                            .nodes_inv_z = .{ 2.0, 2.0, 2.0 },
                            .sub_pixel_z = 0.5,
                            .xi = 0.0,
                            .eta = 0.0,
                        };
                        inline for (.{ scal.fillFuncClipScal, scal.fillFuncPerspScal }) |fill| {
                            var scalar_storage = [_]F{sentinel} ** 3;
                            var scalar = MatSlice(F).init(&scalar_storage, 1, 3);
                            fill(
                                3,
                                1,
                                kernel_index,
                                ctx,
                                interp,
                                &shader_buf,
                                &shader,
                                &scalar,
                            );
                            try std.testing.expectApproxEqAbs(expected, scalar_storage[1], tol);
                        }
                        const stored = if (active[lane]) expected else sentinel;
                        try std.testing.expectApproxEqAbs(stored, clip_storage[1 + lane], tol);
                        try std.testing.expectApproxEqAbs(stored, persp_storage[1 + lane], tol);
                    }
                    try std.testing.expectEqual(sentinel, clip_storage[0]);
                    try std.testing.expectEqual(sentinel, clip_storage[S + 1]);
                    try std.testing.expectEqual(sentinel, persp_storage[0]);
                    try std.testing.expectEqual(sentinel, persp_storage[S + 1]);
                }
            },
            else => return error.InvalidPreparedSpeckleKernel,
        }
    }
}
