// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Copyright (c) 2026 James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const comm = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
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
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
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

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

pub fn FuncKernel(
    comptime N: usize,
    comptime C: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.FuncPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            comm.shadeFuncScalComm(
                N,
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

// --------------------------------------------------------------------------------------
// Speckle Shader
// --------------------------------------------------------------------------------------

pub fn SpeckleKernel(
    comptime N: usize,
    comptime kernel_index: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            shader_buf: *const shaderops.LocalShaderBuff(N),
            shader: *const shaderops.SpecklePrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                ctx_report.recordDepth(
                    ctx_shade.global_subx,
                    ctx_shade.global_suby,
                    1.0 / interp.sub_pixel_z,
                );
            }
            shaderops.fillSpeckleScal(
                N,
                kernel_index,
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
