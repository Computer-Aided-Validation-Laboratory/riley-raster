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
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSI = buildconfig.VecSI;
const VecSF = buildconfig.VecSF;

const MatSlice = @import("matslice.zig").MatSlice;
const maths_simd = @import("maths_simd.zig");
const texops = @import("textureops.zig");
const TexSampleConfig = texops.TexSampleConfig;
const common = @import("shaderops_common.zig");
const simdops = @import("simdops.zig");

inline fn storeMaskedVecSF(
    scratch_vals: []F,
    start_u: usize,
    v_mask_active: VecSB,
    v_vals: VecSF,
) void {
    const v_old_vals = simdops.loadVecSF(scratch_vals, start_u);

    const v_new_vals = @select(
        F,
        v_mask_active,
        v_vals,
        v_old_vals,
    );

    simdops.storeVecSF(scratch_vals, start_u, v_new_vals);
}

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const fillNodalClip = common.fillNodalClip;
pub const fillNodalPersp = common.fillNodalPersp;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub inline fn evalFuncShaderGreySIMD(
    builtin: common.FuncShaderBuiltin,
    coord: common.FuncCoordSIMD,
    params: common.FuncShaderParams,
) VecSF {
    const eval_coord = common.applyFuncShaderCoordParamsSIMD(coord, params);
    const v_value = switch (builtin) {
        .constant => blk: {
            const p = if (params.settings == .constant)
                params.settings.constant
            else
                common.ConstantParams{};
            break :blk @as(VecSF, @splat(p.value));
        },
        .linear => blk: {
            const p = if (params.settings == .linear)
                params.settings.linear
            else
                common.LinearParams{};
            break :blk @as(VecSF, @splat(p.coeffs[0])) +
                @as(VecSF, @splat(p.coeffs[1])) * eval_coord.coord_0 +
                @as(VecSF, @splat(p.coeffs[2])) * eval_coord.coord_1;
        },
        .quadratic => blk: {
            const p = if (params.settings == .quadratic)
                params.settings.quadratic
            else
                common.QuadraticParams{};
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
            const p = if (params.settings == .sinusoidal)
                params.settings.sinusoidal
            else
                common.SinusoidalParams{};
            break :blk @as(VecSF, @splat(p.bias)) +
                @as(VecSF, @splat(p.amplitudes[0])) *
                    @sin(@as(VecSF, @splat(p.wave_num_scalar[0])) *
                        eval_coord.coord_0) +
                @as(VecSF, @splat(p.amplitudes[1])) *
                    @cos(@as(VecSF, @splat(p.wave_num_scalar[1])) *
                        eval_coord.coord_1);
        },
        .sinusoidal_approx => blk: {
            const p = if (params.settings == .sinusoidal_approx)
                params.settings.sinusoidal_approx
            else
                common.SinusoidalParams{};
            break :blk @as(VecSF, @splat(p.bias)) +
                @as(VecSF, @splat(p.amplitudes[0])) *
                    maths_simd.sinApproxSIMD(
                        buildconfig.SimdWidth,
                        F,
                        @as(VecSF, @splat(p.wave_num_scalar[0])) *
                            eval_coord.coord_0,
                    ) +
                @as(VecSF, @splat(p.amplitudes[1])) *
                    maths_simd.cosApproxSIMD(
                        buildconfig.SimdWidth,
                        F,
                        @as(VecSF, @splat(p.wave_num_scalar[1])) *
                            eval_coord.coord_1,
                    );
        },
        .checker => blk: {
            const p = if (params.settings == .checker)
                params.settings.checker
            else
                common.CheckerParams{};
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
            const p = if (params.settings == .checker_smooth)
                params.settings.checker_smooth
            else
                common.CheckerSmoothParams{};
            const v_phase_x = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(p.frequency * std.math.pi)) *
                            eval_coord.coord_0,
                    );
            const v_phase_y = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(p.frequency * std.math.pi)) *
                            eval_coord.coord_1,
                    );
            break :blk common.cubicSmoothStepSIMD(v_phase_x * v_phase_y);
        },
        .lambertian_normal_z => blk: {
            const p = if (params.settings == .lambertian_normal_z)
                params.settings.lambertian_normal_z
            else
                common.LambertianParams{};
            break :blk @as(VecSF, @splat(p.coeffs[0])) +
                @as(VecSF, @splat(p.coeffs[1])) * eval_coord.normal_z;
        },
        .eggbox => blk: {
            const p = if (params.settings == .eggbox)
                params.settings.eggbox
            else
                common.EggboxParams{};
            const v_phase_x = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_0 +
                    @as(VecSF, @splat(p.phase[0]))) /
                @as(VecSF, @splat(p.pitch[0]));
            const v_phase_y = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_1 +
                    @as(VecSF, @splat(p.phase[1]))) /
                @as(VecSF, @splat(p.pitch[1]));
            break :blk @as(VecSF, @splat(p.mean)) +
                @as(VecSF, @splat(0.5 * p.contrast)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_x)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_y)) -
                @as(VecSF, @splat(p.contrast));
        },
    };
    return common.applyFuncShaderOutputParamsSIMD(v_value, params);
}

pub inline fn evalFuncShaderRGBSIMD(
    builtin: common.FuncShaderBuiltin,
    coord: common.FuncCoordSIMD,
    params: common.FuncShaderParams,
) [3]VecSF {
    const eval_coord = common.applyFuncShaderCoordParamsSIMD(coord, params);
    const v_vals = switch (builtin) {
        .constant => blk: {
            const p = if (params.settings == .constant)
                params.settings.constant
            else
                common.ConstantParams{};
            break :blk .{
                @as(VecSF, @splat(p.value_rgb[0])),
                @as(VecSF, @splat(p.value_rgb[1])),
                @as(VecSF, @splat(p.value_rgb[2])),
            };
        },
        .linear => blk: {
            const p = if (params.settings == .linear)
                params.settings.linear
            else
                common.LinearParams{};
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
            const p = if (params.settings == .quadratic)
                params.settings.quadratic
            else
                common.QuadraticParams{};
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
            const p = if (params.settings == .sinusoidal)
                params.settings.sinusoidal
            else
                common.SinusoidalParams{};
            break :blk .{
                @as(VecSF, @splat(p.bias_rgb[0])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[0])) *
                        @sin(@as(VecSF, @splat(p.wave_num_rgb[0])) *
                            eval_coord.coord_0),
                @as(VecSF, @splat(p.bias_rgb[1])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[1])) *
                        @cos(@as(VecSF, @splat(p.wave_num_rgb[1])) *
                            eval_coord.coord_1),
                @as(VecSF, @splat(p.bias_rgb[2])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[2])) *
                        @sin(
                            @as(VecSF, @splat(p.wave_num_rgb[2])) *
                                (eval_coord.coord_0 + eval_coord.coord_1),
                        ),
            };
        },
        .sinusoidal_approx => blk: {
            const p = if (params.settings == .sinusoidal_approx)
                params.settings.sinusoidal_approx
            else
                common.SinusoidalParams{};
            break :blk .{
                @as(VecSF, @splat(p.bias_rgb[0])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[0])) *
                        maths_simd.sinApproxSIMD(
                            buildconfig.SimdWidth,
                            F,
                            @as(VecSF, @splat(p.wave_num_rgb[0])) *
                                eval_coord.coord_0,
                        ),
                @as(VecSF, @splat(p.bias_rgb[1])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[1])) *
                        maths_simd.cosApproxSIMD(
                            buildconfig.SimdWidth,
                            F,
                            @as(VecSF, @splat(p.wave_num_rgb[1])) *
                                eval_coord.coord_1,
                        ),
                @as(VecSF, @splat(p.bias_rgb[2])) +
                    @as(VecSF, @splat(p.amplitudes_rgb[2])) *
                        maths_simd.sinApproxSIMD(
                            buildconfig.SimdWidth,
                            F,
                            @as(VecSF, @splat(p.wave_num_rgb[2])) *
                                (eval_coord.coord_0 + eval_coord.coord_1),
                        ),
            };
        },
        .checker => blk: {
            const p = if (params.settings == .checker)
                params.settings.checker
            else
                common.CheckerParams{};
            const v_cell_x: VecSI = @intFromFloat(@floor(eval_coord.coord_0));
            const v_cell_y: VecSI = @intFromFloat(@floor(eval_coord.coord_1));
            const v_parity = @mod(
                v_cell_x + v_cell_y,
                @as(VecSI, @splat(2)),
            ) == @as(VecSI, @splat(0));
            const v_value = @select(
                F,
                @as(VecSB, v_parity),
                @as(VecSF, @splat(p.levels[0])),
                @as(VecSF, @splat(p.levels[1])),
            );
            break :blk .{ v_value, v_value, v_value };
        },
        .checker_smooth => blk: {
            const p = if (params.settings == .checker_smooth)
                params.settings.checker_smooth
            else
                common.CheckerSmoothParams{};
            const v_phase_x = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(p.frequency * std.math.pi)) *
                            eval_coord.coord_0,
                    );
            const v_phase_y = @as(VecSF, @splat(0.5)) +
                @as(VecSF, @splat(0.5)) *
                    @sin(
                        @as(VecSF, @splat(p.frequency * std.math.pi)) *
                            eval_coord.coord_1,
                    );
            const v_base = common.cubicSmoothStepSIMD(v_phase_x * v_phase_y);
            break :blk .{
                v_base,
                common.cubicSmoothStepSIMD(
                    @as(VecSF, @splat(1.0)) - v_base,
                ),
                @as(VecSF, @splat(0.5)) +
                    @as(VecSF, @splat(0.5)) *
                        @sin(@as(VecSF, @splat(2.0 * std.math.pi)) * v_base),
            };
        },
        .lambertian_normal_z => blk: {
            const p = if (params.settings == .lambertian_normal_z)
                params.settings.lambertian_normal_z
            else
                common.LambertianParams{};
            break :blk .{
                @as(VecSF, @splat(p.coeffs_rgb[0][0])) +
                    @as(VecSF, @splat(p.coeffs_rgb[0][1])) *
                        eval_coord.normal_z,
                @as(VecSF, @splat(p.coeffs_rgb[1][0])) +
                    @as(VecSF, @splat(p.coeffs_rgb[1][1])) *
                        eval_coord.normal_z,
                @as(VecSF, @splat(p.coeffs_rgb[2][0])) +
                    @as(VecSF, @splat(p.coeffs_rgb[2][1])) *
                        eval_coord.normal_z,
            };
        },
        .eggbox => blk: {
            const p = if (params.settings == .eggbox)
                params.settings.eggbox
            else
                common.EggboxParams{};
            const v_phase_x = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_0 +
                    @as(VecSF, @splat(p.phase[0]))) /
                @as(VecSF, @splat(p.pitch[0]));
            const v_phase_y = @as(VecSF, @splat(2.0 * std.math.pi)) *
                (eval_coord.coord_1 +
                    @as(VecSF, @splat(p.phase[1]))) /
                @as(VecSF, @splat(p.pitch[1]));
            const v_value = @as(VecSF, @splat(p.mean)) +
                @as(VecSF, @splat(0.5 * p.contrast)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_x)) *
                    (@as(VecSF, @splat(1.0)) + @cos(v_phase_y)) -
                @as(VecSF, @splat(p.contrast));
            break :blk .{ v_value, v_value, v_value };
        },
    };
    return .{
        common.applyFuncShaderOutputParamsSIMD(v_vals[0], params),
        common.applyFuncShaderOutputParamsSIMD(v_vals[1], params),
        common.applyFuncShaderOutputParamsSIMD(v_vals[2], params),
    };
}

pub inline fn fillNodalClipSIMD(
    comptime N: usize,
    ctx_shade: common.ShadeContext(N),
    v_weights: [N]VecSF,
    sh: *const common.NodalPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(sh.scale_mul);
    const v_splat_add: VecSF = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..cfg.max_nodal_fields) |ff| {
        if (ff >= @as(usize, ctx_shade.actual_fields)) break;

        const base = ff * N;
        var v_weighted_sum: VecSF = @splat(0.0);
        inline for (0..N) |nn| {
            v_weighted_sum += v_weights[nn] *
                @as(VecSF, @splat(ctx_shade.shader_buf.data[base + nn]));
        }

        const v_final = v_weighted_sum * v_splat_mul + v_splat_add;
        const flat_idx = ff * px_stride + ctx_shade.scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade.v_mask_active.?,
            v_final,
        );
    }
}

pub inline fn fillNodalPerspSIMD(
    comptime N: usize,
    ctx_shade: common.ShadeContext(N),
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    sh: *const common.NodalPrepared,
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(sh.scale_mul);
    const v_splat_add: VecSF = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    inline for (0..cfg.max_nodal_fields) |ff| {
        if (ff >= @as(usize, ctx_shade.actual_fields)) break;

        const base = ff * N;
        var v_weighted_sum: VecSF = @splat(0.0);
        inline for (0..N) |nn| {
            v_weighted_sum += v_weights[nn] * v_nodes_inv_z[nn] *
                @as(VecSF, @splat(ctx_shade.shader_buf.data[base + nn]));
        }

        const v_final = (v_weighted_sum * v_subpx_z) * v_splat_mul + v_splat_add;
        const flat_idx = ff * px_stride + ctx_shade.scratch_idx;

        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            ctx_shade.v_mask_active.?,
            v_final,
        );
    }
}

pub const fillTexClip = common.fillTexClip;
pub const fillTexPersp = common.fillTexPersp;
pub const fillFuncClip = common.fillFuncClip;
pub const fillFuncPersp = common.fillFuncPersp;

fn texSimdInterpMode(
    comptime channels: comptime_int,
    comptime sample_config: TexSampleConfig,
) buildconfig.SimdTexInterpMode {
    return buildconfig.TexSIMDPolicy.resolve(
        channels,
        sample_config.sample == .linear,
        sample_config.mode == .lut or sample_config.mode == .lut_lerp,
    );
}

fn calcNormalLaneVecs(
    comptime N: usize,
    ctx_shade: common.ShadeContext(N),
    v_weights: [N]VecSF,
) [3]VecSF {
    var normal_vecs = [3]VecSF{
        @splat(0.0),
        @splat(0.0),
        @splat(0.0),
    };

    if (!ctx_shade.shader_buf.has_normals) {
        normal_vecs[2] = @splat(1.0);
        return normal_vecs;
    }

    inline for (0..N) |nn| {
        normal_vecs[0] += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.normals[0 * N + nn]));
        normal_vecs[1] += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.normals[1 * N + nn]));
        normal_vecs[2] += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.normals[2 * N + nn]));
    }

    return normal_vecs;
}

pub inline fn fillTexClipSIMD(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime sample_config: TexSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    sh: *const common.TexPrepared(T, channels),
    spx_image_scratch: *MatSlice(F),
) void {
    var v_tex_u: VecSF = @splat(0.0);
    var v_tex_v: VecSF = @splat(0.0);
    inline for (0..N) |nn| {
        v_tex_u += v_weights[nn] * @as(VecSF, @splat(ctx_shade.shader_buf.data[nn]));
        v_tex_v += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.data[N + nn]));
    }

    const px_stride = spx_image_scratch.cols_num;
    const sampled_vecs = switch (comptime texSimdInterpMode(
        channels,
        sample_config,
    )) {
        .inner => texops.sampleLanes(
            channels,
            sample_config,
            v_mask_active,
            sh.tex,
            v_tex_u,
            v_tex_v,
        ),
        .over_pixels => texops.sampleWide(
            channels,
            sample_config,
            sh.tex,
            v_tex_u,
            v_tex_v,
        ),
    };

    inline for (0..channels) |ch| {
        const v_final = sampled_vecs[ch] *
            @as(VecSF, @splat(sh.scale_mul)) +
            @as(VecSF, @splat(sh.scale_add));
        const flat_idx = ch * px_stride + ctx_shade.scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
    }
}

pub inline fn fillTexPerspSIMD(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime sample_config: TexSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    sh: *const common.TexPrepared(T, channels),
    spx_image_scratch: *MatSlice(F),
) void {
    const v_splat_mul: VecSF = @splat(sh.scale_mul);
    const v_splat_add: VecSF = @splat(sh.scale_add);
    const px_stride = spx_image_scratch.cols_num;

    var v_tex_u: VecSF = @splat(0.0);
    var v_tex_v: VecSF = @splat(0.0);
    inline for (0..N) |nn| {
        const v_inv_z = v_nodes_inv_z[nn];
        v_tex_u += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.data[nn])) * v_inv_z;
        v_tex_v += v_weights[nn] *
            @as(VecSF, @splat(ctx_shade.shader_buf.data[N + nn])) * v_inv_z;
    }

    v_tex_u *= v_subpx_z;
    v_tex_v *= v_subpx_z;

    const sampled_vecs = switch (comptime texSimdInterpMode(
        channels,
        sample_config,
    )) {
        .inner => if (comptime N == 3)
            texops.sampleLanesTri3(
                channels,
                sample_config,
                v_mask_active,
                sh.tex,
                v_tex_u,
                v_tex_v,
            )
        else
            texops.sampleLanes(
                channels,
                sample_config,
                v_mask_active,
                sh.tex,
                v_tex_u,
                v_tex_v,
            ),
        .over_pixels => texops.sampleWide(
            channels,
            sample_config,
            sh.tex,
            v_tex_u,
            v_tex_v,
        ),
    };

    inline for (0..channels) |ch| {
        const v_final = sampled_vecs[ch] * v_splat_mul + v_splat_add;
        const flat_idx = ch * px_stride + ctx_shade.scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
    }
}

pub inline fn fillFuncClipSIMD(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    sh: *const common.FuncPrepared(channels),
    spx_image_scratch: *MatSlice(F),
) void {
    var v_coord_0: VecSF = v_xi;
    var v_coord_1: VecSF = v_eta;

    switch (sh.coord_mode) {
        .uv, .world_reference, .world_deformed => {
            v_coord_0 = @splat(0.0);
            v_coord_1 = @splat(0.0);
            inline for (0..N) |nn| {
                v_coord_0 += v_weights[nn] *
                    @as(VecSF, @splat(ctx_shade.shader_buf.func_coords[nn]));
                v_coord_1 += v_weights[nn] *
                    @as(VecSF, @splat(ctx_shade.shader_buf.func_coords[N + nn]));
            }
        },
        .para => {},
    }

    const normal_vecs = calcNormalLaneVecs(N, ctx_shade, v_weights);
    const px_stride = spx_image_scratch.cols_num;
    const scratch_idx = ctx_shade.scratch_idx;
    const coord = common.FuncCoordSIMD{
        .coord_0 = v_coord_0,
        .coord_1 = v_coord_1,
        .normal_x = normal_vecs[0],
        .normal_y = normal_vecs[1],
        .normal_z = normal_vecs[2],
    };

    if (comptime channels == 1) {
        const v_final = evalFuncShaderGreySIMD(
            sh.builtin,
            coord,
            sh.params,
        ) * @as(VecSF, @splat(sh.scale_mul)) +
            @as(VecSF, @splat(sh.scale_add));
        const flat_idx = scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
        return;
    }

    const v_vals = evalFuncShaderRGBSIMD(
        sh.builtin,
        coord,
        sh.params,
    );
    inline for (0..channels) |ch| {
        const v_final = v_vals[ch] * @as(VecSF, @splat(sh.scale_mul)) +
            @as(VecSF, @splat(sh.scale_add));
        const flat_idx = ch * px_stride + scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
    }
}

pub inline fn fillFuncPerspSIMD(
    comptime N: usize,
    comptime channels: usize,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    sh: *const common.FuncPrepared(channels),
    spx_image_scratch: *MatSlice(F),
) void {
    var v_coord_0: VecSF = v_xi;
    var v_coord_1: VecSF = v_eta;

    switch (sh.coord_mode) {
        .uv, .world_reference, .world_deformed => {
            v_coord_0 = @splat(0.0);
            v_coord_1 = @splat(0.0);
            inline for (0..N) |nn| {
                const v_inv_z = v_nodes_inv_z[nn];
                v_coord_0 += v_weights[nn] *
                    @as(VecSF, @splat(ctx_shade.shader_buf.func_coords[nn])) * v_inv_z;
                v_coord_1 += v_weights[nn] *
                    @as(VecSF, @splat(ctx_shade.shader_buf.func_coords[N + nn])) * v_inv_z;
            }
            v_coord_0 *= v_subpx_z;
            v_coord_1 *= v_subpx_z;
        },
        .para => {},
    }

    const normal_vecs = calcNormalLaneVecs(N, ctx_shade, v_weights);
    const px_stride = spx_image_scratch.cols_num;
    const scratch_idx = ctx_shade.scratch_idx;
    const coord = common.FuncCoordSIMD{
        .coord_0 = v_coord_0,
        .coord_1 = v_coord_1,
        .normal_x = normal_vecs[0],
        .normal_y = normal_vecs[1],
        .normal_z = normal_vecs[2],
    };

    if (comptime channels == 1) {
        const v_final = evalFuncShaderGreySIMD(
            sh.builtin,
            coord,
            sh.params,
        ) * @as(VecSF, @splat(sh.scale_mul)) +
            @as(VecSF, @splat(sh.scale_add));
        const flat_idx = scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
        return;
    }

    const v_vals = evalFuncShaderRGBSIMD(
        sh.builtin,
        coord,
        sh.params,
    );
    inline for (0..channels) |ch| {
        const v_final = v_vals[ch] * @as(VecSF, @splat(sh.scale_mul)) +
            @as(VecSF, @splat(sh.scale_add));
        const flat_idx = ch * px_stride + scratch_idx;
        storeMaskedVecSF(
            spx_image_scratch.slice,
            flat_idx,
            v_mask_active,
            v_final,
        );
    }
}
