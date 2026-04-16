const std = @import("std");

const buildconfig = @import("buildconfig.zig");
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
    scratch_vals: []f64,
    start_u: usize,
    v_mask_active: VecSB,
    v_vals: VecSF,
) void {
    const v_old_vals = simdops.loadVecSF(scratch_vals, start_u);

    const v_new_vals = @select(
        f64,
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
    spx_image_scratch: *MatSlice(f64),
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
    spx_image_scratch: *MatSlice(f64),
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
pub const fillTexClipRuntime = common.fillTexClipRuntime;
pub const fillTexPerspRuntime = common.fillTexPerspRuntime;

pub inline fn fillTexClipSIMD(
    comptime N: usize,
    comptime channels: usize,
    comptime sample_config: TextureSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    sh: *const common.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
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

pub inline fn fillTexClipSIMDRuntime(
    comptime N: usize,
    comptime channels: usize,
    sample_config: TextureSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    sh: *const common.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
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
        .inner => texops.sampleLanesRuntime(
            channels,
            sample_config,
            v_mask_active,
            sh.texture,
            v_tex_u,
            v_tex_v,
        ),
        .over_pixels => texops.sampleWideRuntime(
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
    comptime channels: usize,
    comptime sample_config: TextureSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    sh: *const common.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
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

pub inline fn fillTexPerspSIMDRuntime(
    comptime N: usize,
    comptime channels: usize,
    sample_config: TextureSampleConfig,
    ctx_shade: common.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    sh: *const common.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
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
            texops.sampleLanesTri3Runtime(
                channels,
                sample_config,
                v_mask_active,
                sh.texture,
                v_tex_u,
                v_tex_v,
            )
        else
            texops.sampleLanesRuntime(
                channels,
                sample_config,
                v_mask_active,
                sh.texture,
                v_tex_u,
                v_tex_v,
            ),
        .over_pixels => texops.sampleWideRuntime(
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
