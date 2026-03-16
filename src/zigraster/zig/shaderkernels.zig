const std = @import("std");
const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const InterpType = texops.InterpType;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub fn FlatKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            shader: *const shaderops.FlatShader,
            perf_ctx: anytype,
        ) void {
            if (@TypeOf(perf_ctx).mode == .perf) {
                perf_ctx.recordDepth(
                    ctx.global_subx, ctx.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFlat(
                    N,
                    ctx.frame_index,
                    ctx.elem_index,
                    ctx.actual_fields,
                    ctx.fields_num,
                    interp.weights,
                    shader,
                    ctx.idx,
                    ctx.spx_image_scratch,
                );
            } else {
                shaderops.fillFlatPerspective(
                    N,
                    ctx.frame_index,
                    ctx.elem_index,
                    ctx.actual_fields,
                    ctx.fields_num,
                    interp.weights,
                    interp.nodes_inv_z,
                    interp.sub_pixel_z,
                    shader,
                    ctx.idx,
                    ctx.spx_image_scratch,
                );
            }           
        }
    };
}

pub fn TexKernel(comptime N: usize, comptime T: type, comptime interp_type: InterpType) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexShader(T),
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
                    interp_type,
                    ctx.elem_index,
                    ctx.fields_num,
                    interp.weights,
                    shader,
                    ctx.idx,
                    ctx.spx_image_scratch,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    T,
                    interp_type,
                    ctx.elem_index,
                    ctx.fields_num,
                    interp.weights,
                    interp.nodes_inv_z,
                    interp.sub_pixel_z,
                    shader,
                    ctx.idx,
                    ctx.spx_image_scratch,
                );
            }
        }
    };
}
