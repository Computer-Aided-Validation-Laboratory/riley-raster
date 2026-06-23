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
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const TextureSampleConfig = texops.TextureSampleConfig;
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

pub const fillNodalClip = common.fillNodalClip;
pub const fillNodalPersp = common.fillNodalPersp;

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
    comptime sample_config: TextureSampleConfig,
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
    const sampled_vecs = switch (cfg.simd_texture_interp) {
        .inner => texops.sampleLanes(
            channels,
            sample_config,
            v_mask_active,
            sh.texture,
            v_tex_u,
            v_tex_v,
        ),
        .over_pixels => texops.sampleWide(
            channels,
            sample_config,
            sh.texture,
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
    comptime sample_config: TextureSampleConfig,
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

    const sampled_vecs = switch (cfg.simd_texture_interp) {
        .inner => if (comptime N == 3)
            texops.sampleLanesTri3(
                channels,
                sample_config,
                v_mask_active,
                sh.texture,
                v_tex_u,
                v_tex_v,
            )
        else
            texops.sampleLanes(
                channels,
                sample_config,
                v_mask_active,
                sh.texture,
                v_tex_u,
                v_tex_v,
            ),
        .over_pixels => texops.sampleWide(
            channels,
            sample_config,
            sh.texture,
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
        .parametric => {},
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
        const v_final = common.evalFuncShaderBuiltinScalarSIMD(
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

    const v_vals = common.evalFuncShaderBuiltinRgbSIMD(
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
        .parametric => {},
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
        const v_final = common.evalFuncShaderBuiltinScalarSIMD(
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

    const v_vals = common.evalFuncShaderBuiltinRgbSIMD(
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
