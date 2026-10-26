// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const comm = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
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
            spx_image_scratch: *MatSlice(F),
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
                spx_image_scratch,
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
    };
}
