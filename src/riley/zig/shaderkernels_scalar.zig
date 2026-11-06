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
const shaderkernels_common = @import("shaderkernels_common.zig");
const meshhit = @import("meshhit.zig");

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
            spx_image_scratch: *matslice.MatSlice(F),
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
                spx_image_scratch,
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
    };
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
    };
}
