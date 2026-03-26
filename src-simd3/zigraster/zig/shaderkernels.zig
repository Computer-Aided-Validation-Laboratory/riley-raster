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

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            v_mask: @Vector(8, bool),
            v_weights: [N]@Vector(8, f64),
            v_nodes_inv_z: [N]@Vector(8, f64),
            v_subpx_z: @Vector(8, f64),
            shader: *const shaderops.FlatPrepared,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = v_mask;
            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillFlatPerspectiveSIMD(
                    N, ctx_shade, v_weights, v_nodes_inv_z, v_subpx_z, shader, spx_image_scratch,
                );
            } else {
                // TODO: implement non-perspective SIMD if needed
                @panic("shadeSIMD not implemented for this coord_space");
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

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            v_mask: @Vector(8, bool),
            v_weights: [N]@Vector(8, f64),
            v_nodes_inv_z: [N]@Vector(8, f64),
            v_subpx_z: @Vector(8, f64),
            shader: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = coord_space; _ = v_nodes_inv_z; _ = v_subpx_z; _ = shader;
            const px_stride = spx_image_scratch.cols_num;

            // Vectorized Normal Interpolation
            var v_norm = [_]@Vector(8, f64){ @splat(0.0), @splat(0.0), @splat(0.0) };
            inline for (0..N) |nn| {
                v_norm[0] += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.normals[0 * N + nn]));
                v_norm[1] += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.normals[1 * N + nn]));
                v_norm[2] += v_weights[nn] * @as(@Vector(8, f64), @splat(ctx_shade.local_buf.normals[2 * N + nn]));
            }

            inline for (0..3) |ch| {
                const v_final = v_norm[ch] * @as(@Vector(8, f64), @splat(0.5)) + @as(@Vector(8, f64), @splat(0.5));
                const flat_idx = ch * px_stride + ctx_shade.idx;
                const ptr_out: *align(8) @Vector(8, f64) = @ptrCast(&spx_image_scratch.elems[flat_idx]);
                const v_old_val = ptr_out.*;
                ptr_out.* = @select(f64, v_mask, v_final, v_old_val);
            }
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

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            v_mask: @Vector(8, bool),
            v_weights: [N]@Vector(8, f64),
            v_nodes_inv_z: [N]@Vector(8, f64),
            v_subpx_z: @Vector(8, f64),
            shader: *const shaderops.TexPrepared(T, channels),
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillTexPerspectiveSIMD(
                    N, T, channels, shader.interp_type, ctx_shade, v_mask, v_weights, v_nodes_inv_z, v_subpx_z, shader, spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}
