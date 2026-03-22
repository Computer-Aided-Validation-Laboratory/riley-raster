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
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.FlatPrepared,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFlat(N, ctx_shade, interp, shader, spx_image_scratch);
            } else {
                shaderops.fillFlatPerspective(N, ctx_shade, interp, shader, spx_image_scratch);
            }

        }
    };
}

pub fn NormalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: anytype,
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = shader;
            _ = coord_space;
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            
            const n = ctx_shade.local_buf.interpolateNormal(interp.weights);
            
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 0] = n[0] * 0.5 + 0.5;
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 1] = n[1] * 0.5 + 0.5;
            spx_image_scratch.elems[ctx_shade.idx * ctx_shade.fields_num + 2] = n[2] * 0.5 + 0.5;
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
            ctx_perf: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (@TypeOf(ctx_perf).mode == .perf) {
                ctx_perf.recordDepth(
                    ctx_shade.global_subx, ctx_shade.global_suby, 1.0 / interp.sub_pixel_z,
                );
            }
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    T,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    T,
                    channels,
                    shader.interp_type,
                    ctx_shade,
                    interp,
                    shader,
                    spx_image_scratch,
                );
            }
        }
    };
}
