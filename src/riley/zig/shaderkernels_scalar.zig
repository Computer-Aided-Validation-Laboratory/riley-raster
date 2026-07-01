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
const common = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;


// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.NodalPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            common.shadeNodalScalarCommon(
                N,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }
    };
}

pub fn TexKernel(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexPrepared(T, channels),
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            common.shadeTexScalarCommon(
                N,
                T,
                channels,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }
    };
}

pub fn FuncKernel(
    comptime N: usize,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.FuncPrepared(channels),
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            common.shadeFuncScalarCommon(
                N,
                channels,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }
    };
}
