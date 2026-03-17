const std = @import("std");
pub const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const InterpType = texops.InterpType;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub fn FlatKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.FlatShader,
            perf_ctx: anytype,
        ) void {
            _ = shader;
            if (@TypeOf(perf_ctx).mode == .perf) {
                perf_ctx.recordDepth(
                    ctx.global_subx, ctx.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFlat(
                    N,
                    ctx,
                    interp,
                );
            } else {
                shaderops.fillFlatPerspective(
                    N,
                    ctx,
                    interp,
                );
            }

        }
    };
}

pub fn TexKernel(
    comptime N: usize, 
    comptime T: type, 
    comptime channels: usize,
    comptime interp_type: InterpType
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexShader(T, channels),
            perf_ctx: anytype,
        ) void {
            if (@TypeOf(perf_ctx).mode == .perf) {
                perf_ctx.recordDepth(
                    ctx.global_subx, ctx.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    T,
                    channels,
                    interp_type,
                    ctx,
                    interp,
                    shader,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    T,
                    channels,
                    interp_type,
                    ctx,
                    interp,
                    shader,
                );
            }
        }
    };
}
