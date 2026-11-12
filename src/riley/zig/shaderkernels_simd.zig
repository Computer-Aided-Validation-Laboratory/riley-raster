// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const eval_branch_quota = buildconfig.comptime_eval_branch_quota;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const scal = @import("shaderkernels_scalar.zig");
const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const report = @import("report.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub const shade = scal.NodalKernel(N).shade;

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.NodalPrepared,
            spx_image_scratch: *MatSlice(F),
        ) void {
            _ = v_xi;
            _ = v_eta;
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        shader_buf,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillNodalPerspSIMD(
                    N,
                    ctx_shade,
                    shader_buf,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodalClipSIMD(
                    N,
                    ctx_shade,
                    shader_buf,
                    v_weights,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}

// --------------------------------------------------------------------------------------
// Texture Shader
// --------------------------------------------------------------------------------------

pub fn TexKernel(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
) type {
    return struct {
        pub const shade = scal.TexKernel(N, T, C).shade;

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.TexPrepared(T, C),
            spx_img_scratch: *MatSlice(F),
        ) void {
            shadeTexSIMD(
                N,
                T,
                C,
                coord_space,
                ctx_shade,
                ctx_report,
                v_mask_active,
                v_weights,
                v_xi,
                v_eta,
                v_nodes_inv_z,
                v_subpx_z,
                shader_buf,
                shader,
                spx_img_scratch,
            );
        }
    };
}

fn shadeTexSIMD(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext,
    ctx_report: anytype,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    spx_img_scratch: *MatSlice(F),
) void {
    _ = v_xi;
    _ = v_eta;
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        if (shader.elem_normals != null) {
            report.recordNormalSIMD(
                N,
                S,
                ctx_report,
                ctx_shade,
                shader_buf,
                v_mask_active,
                v_weights,
            );
        }
    }

    shadeTexSIMDDispatchSample(
        N,
        T,
        C,
        coord_space,
        shader.samp_cfg,
        ctx_shade,
        v_mask_active,
        v_weights,
        v_nodes_inv_z,
        v_subpx_z,
        shader_buf,
        shader,
        spx_img_scratch,
    );
}

inline fn shadeTexSIMDDispatchSample(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    samp_cfg: texops.TexSampConfig,
    ctx_shade: shaderops.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    spx_img_scratch: *MatSlice(F),
) void {
    @setEvalBranchQuota(eval_branch_quota);
    switch (samp_cfg.sample) {
        inline else => |samp_type| shadeTexSIMDDispatchMode(
            N,
            T,
            C,
            coord_space,
            samp_type,
            samp_cfg.mode,
            ctx_shade,
            v_mask_active,
            v_weights,
            v_nodes_inv_z,
            v_subpx_z,
            shader_buf,
            shader,
            spx_img_scratch,
        ),
    }
}

inline fn shadeTexSIMDDispatchMode(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    comptime samp_type: texops.TexSamp,
    mode: texops.TexSampMode,
    ctx_shade: shaderops.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    spx_img_scratch: *MatSlice(F),
) void {
    switch (mode) {
        inline else => |mode_type| {
            const samp_cfg = comptime (texops.TexSampConfig{
                .sample = samp_type,
                .mode = mode_type,
            }).sanitize();

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillTexPerspSIMD(
                    N,
                    T,
                    C,
                    samp_cfg,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader_buf,
                    shader,
                    spx_img_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTexClipSIMD(
                    N,
                    T,
                    C,
                    samp_cfg,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    shader_buf,
                    shader,
                    spx_img_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        },
    }
}

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

pub fn FuncKernel(
    comptime N: usize,
    comptime C: usize,
) type {
    return struct {
        pub const shade = scal.FuncKernel(N, C).shade;

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.FuncPrepared,
            spx_image_scratch: *MatSlice(F),
        ) void {
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        shader_buf,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillFuncPerspSIMD(
                    N,
                    C,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_xi,
                    v_eta,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader_buf,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFuncClipSIMD(
                    N,
                    C,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_xi,
                    v_eta,
                    shader_buf,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}

// --------------------------------------------------------------------------------------
// Speckle Shader
// --------------------------------------------------------------------------------------

pub fn SpeckleKernel(
    comptime N: usize,
    comptime kernel_index: usize,
) type {
    return struct {
        pub const shade = scal.SpeckleKernel(N, kernel_index).shade;

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.SpecklePrepared,
            spx_image_scratch: *MatSlice(F),
        ) void {
            _ = ctx_report;
            _ = v_xi;
            _ = v_eta;
            if (comptime coord_space != .raster and coord_space != .clip_px_leng) {
                @panic("shadeSIMD not implemented for this coord_space");
            }
            shaderops.fillSpeckleSIMD(
                N,
                kernel_index,
                coord_space,
                ctx_shade,
                v_mask_active,
                v_weights,
                v_nodes_inv_z,
                v_subpx_z,
                shader_buf,
                shader,
                spx_image_scratch,
            );
        }
    };
}
