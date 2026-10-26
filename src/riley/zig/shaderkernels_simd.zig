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
const eval_branch_quota = buildconfig.comptime_eval_branch_quota;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const comm = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub const LocalBuff = shaderops.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.NodalPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            comm.shadeNodalScalComm(
                N,
                coord_space,
                ctx_shade,
                interp,
                shader_buf,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
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
            sink: anytype,
        ) void {
            _ = v_xi;
            _ = v_eta;
            _ = v_mask_active;
            _ = ctx_report;

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillNodalPerspSIMD(
                    N,
                    ctx_shade,
                    shader_buf,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    sink,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodalClipSIMD(
                    N,
                    ctx_shade,
                    shader_buf,
                    v_weights,
                    shader,
                    sink,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }

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
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_image_scratch };
            shadeSIMDTo(
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
                &sink,
            );
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
        pub const LocalBuff = shaderops.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.TexPrepared(T, C),
            ctx_report: anytype,
            spx_img_scratch: *MatSlice(F),
        ) void {
            comm.shadeTexScalComm(
                N,
                T,
                C,
                coord_space,
                ctx_shade,
                interp,
                shader_buf,
                shader,
                ctx_report,
                spx_img_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
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
            sink: anytype,
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
                sink,
            );
        }

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
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_img_scratch };
            shadeSIMDTo(
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
                &sink,
            );
        }
    };
}

pub fn TexMultiKernel(comptime N: usize, comptime T: type) type {
    return struct {
        pub const LocalBuff = shaderops.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.TexPrepared(T, 0),
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            inline for (1..9) |C| {
                if (shader.tex.array.dims[0] == C) {
                    const concrete = shaderops.concreteTexture(T, C, shader);
                    TexKernel(N, T, C).shade(
                        coord_space,
                        ctx_shade,
                        interp,
                        shader_buf,
                        &concrete,
                        ctx_report,
                        spx_image_scratch,
                    );
                    return;
                }
            }
            unreachable;
        }

        pub inline fn shadeSIMDTo(
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
            shader: *const shaderops.TexPrepared(T, 0),
            sink: anytype,
        ) void {
            inline for (1..9) |C| {
                if (shader.tex.array.dims[0] == C) {
                    const concrete = shaderops.concreteTexture(T, C, shader);
                    TexKernel(N, T, C).shadeSIMDTo(
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
                        &concrete,
                        sink,
                    );
                    return;
                }
            }
            unreachable;
        }

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
            shader: *const shaderops.TexPrepared(T, 0),
            spx_img_scratch: *MatSlice(F),
        ) void {
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_img_scratch };
            shadeSIMDTo(
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
                &sink,
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
    sink: anytype,
) void {
    _ = v_xi;
    _ = v_eta;
    _ = ctx_report;

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
        sink,
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
    sink: anytype,
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
            sink,
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
    sink: anytype,
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
                    sink,
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
                    sink,
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
        pub const LocalBuff = shaderops.LocalShaderBuff(N);
        pub const Hit = meshhit.MeshHit(N);

        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: meshhit.MeshHit(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.FuncPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            const hit = comm.completeFuncHit(N, coord_space, interp, shader_buf, shader);
            comm.shadeFuncScalComm(
                N,
                C,
                coord_space,
                ctx_shade,
                hit,
                shader_buf,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
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
            sink: anytype,
        ) void {
            const hit = comm.completeFuncHitSIMD(
                N,
                coord_space,
                v_mask_active,
                v_weights,
                v_nodes_inv_z,
                v_subpx_z,
                shader_buf,
                shader,
            );
            shadeSIMDToHit(
                coord_space,
                ctx_shade,
                ctx_report,
                v_mask_active,
                v_weights,
                v_xi,
                v_eta,
                v_nodes_inv_z,
                v_subpx_z,
                hit,
                shader_buf,
                shader,
                sink,
            );
        }

        pub inline fn shadeSIMDToHit(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            hit: meshhit.MeshHitGeomSIMD,
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.FuncPrepared,
            sink: anytype,
        ) void {
            _ = ctx_report;

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
                    hit,
                    shader_buf,
                    shader,
                    sink,
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
                    hit,
                    shader_buf,
                    shader,
                    sink,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }

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
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_image_scratch };
            shadeSIMDTo(
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
                &sink,
            );
        }
    };
}
