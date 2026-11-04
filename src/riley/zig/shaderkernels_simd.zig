// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const matslice = @import("matslice.zig");
const geometrykernels = @import("geometrykernels.zig");
const shadertypes = @import("shadertypes.zig");

const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const max_channels = buildconfig.config.max_image_channels;
const eval_branch_quota = buildconfig.comptime_eval_branch_quota;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const shaderkernels_common = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const texturetypes = @import("texturetypes.zig");

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub const LocalBuff = shadertypes.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.NodalPrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            shaderkernels_common.shadeNodalScalComm(
                N,
                coord_space,
                ctx_shade,
                interp,
                shader_buf,
                shader,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.NodalPrepared,
            sink: anytype,
        ) void {
            _ = v_xi;
            _ = v_eta;
            _ = v_mask_active;

            if (comptime coord_space == geometrykernels.CoordSpace.raster) {
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
            } else if (comptime coord_space == geometrykernels.CoordSpace.clip_px_leng) {
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
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.NodalPrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_image_scratch };

            shadeSIMDTo(
                coord_space,
                ctx_shade,
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
        pub const LocalBuff = shadertypes.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexPrepared(T, C),
            spx_img_scratch: *matslice.MatSlice(F),
        ) void {
            shaderkernels_common.shadeTexScalComm(
                N,
                T,
                C,
                coord_space,
                ctx_shade,
                interp,
                shader_buf,
                shader,
                spx_img_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexPrepared(T, C),
            sink: anytype,
        ) void {
            shadeTexSIMD(
                N,
                T,
                C,
                coord_space,
                ctx_shade,
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
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexPrepared(T, C),
            spx_img_scratch: *matslice.MatSlice(F),
        ) void {
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_img_scratch };
            shadeSIMDTo(
                coord_space,
                ctx_shade,
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
        pub const LocalBuff = shadertypes.LocalShaderBuff(N);
        pub const Hit = meshhit.RasterHit(N);

        pub inline fn shade(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            interp: meshhit.RasterHit(N),
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexMultiPrepared(T),
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            inline for (1..max_channels + 1) |C| {
                if (shader.tex.array.dims[0] == C) {
                    const concrete = shadertypes.concreteTexture(T, C, shader);
                    TexKernel(N, T, C).shade(
                        coord_space,
                        ctx_shade,
                        interp,
                        shader_buf,
                        &concrete,
                        spx_image_scratch,
                    );
                    return;
                }
            }
            // Preparation validates the runtime channel count against max_channels.
            unreachable;
        }

        pub inline fn shadeSIMDTo(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexMultiPrepared(T),
            sink: anytype,
        ) void {
            inline for (1..max_channels + 1) |C| {
                if (shader.tex.array.dims[0] == C) {
                    const concrete = shadertypes.concreteTexture(T, C, shader);
                    TexKernel(N, T, C).shadeSIMDTo(
                        coord_space,
                        ctx_shade,
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
            // Preparation validates the runtime channel count against max_channels.
            unreachable;
        }

        pub inline fn shadeSIMD(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.TexMultiPrepared(T),
            spx_img_scratch: *matslice.MatSlice(F),
        ) void {
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_img_scratch };
            shadeSIMDTo(
                coord_space,
                ctx_shade,
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
    comptime coord_space: geometrykernels.CoordSpace,
    ctx_shade: shadertypes.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shadertypes.LocalShaderBuff(N),
    shader: *const shadertypes.TexPrepared(T, C),
    sink: anytype,
) void {
    _ = v_xi;
    _ = v_eta;

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
    comptime coord_space: geometrykernels.CoordSpace,
    samp_cfg: texturetypes.TexSampConfig,
    ctx_shade: shadertypes.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shadertypes.LocalShaderBuff(N),
    shader: *const shadertypes.TexPrepared(T, C),
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
    comptime coord_space: geometrykernels.CoordSpace,
    comptime samp_type: texturetypes.TexSamp,
    mode: texturetypes.TexSampMode,
    ctx_shade: shadertypes.ShadeContext,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader_buf: *const shadertypes.LocalShaderBuff(N),
    shader: *const shadertypes.TexPrepared(T, C),
    sink: anytype,
) void {
    switch (mode) {
        inline else => |mode_type| {
            const samp_cfg = comptime (texturetypes.TexSampConfig{
                .sample = samp_type,
                .mode = mode_type,
            }).sanitise();

            if (comptime coord_space == geometrykernels.CoordSpace.raster) {
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
            } else if (comptime coord_space == geometrykernels.CoordSpace.clip_px_leng) {
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
        pub const LocalBuff = shadertypes.LocalShaderBuff(N);
        pub const Hit = meshhit.MeshHit(N);

        pub inline fn shade(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            interp: meshhit.MeshHit(N),
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.FuncPrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            const hit = shaderkernels_common.completeFuncHit(N, coord_space, interp, shader_buf, shader);
            shaderkernels_common.shadeFuncScalComm(
                N,
                C,
                coord_space,
                ctx_shade,
                hit,
                shader_buf,
                shader,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMDTo(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.FuncPrepared,
            sink: anytype,
        ) void {
            const hit = shaderkernels_common.completeFuncHitSIMD(
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
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            hit: meshhit.MeshHitGeomSIMD,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.FuncPrepared,
            sink: anytype,
        ) void {
            if (comptime coord_space == geometrykernels.CoordSpace.raster) {
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
            } else if (comptime coord_space == geometrykernels.CoordSpace.clip_px_leng) {
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
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader_buf: *const shadertypes.LocalShaderBuff(N),
            shader: *const shadertypes.FuncPrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            var sink = shaderops.ImageSink{ .ctx = ctx_shade, .scratch = spx_image_scratch };
            shadeSIMDTo(
                coord_space,
                ctx_shade,
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
