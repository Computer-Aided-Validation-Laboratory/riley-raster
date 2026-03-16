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
            frame_index: usize,
            element_index: usize,
            _actual_fields: usize,
            fields_num: usize,
            weights: [N]f64,
            nodes_inv_z: [N]f64,
            sub_pixel_z: f64,
            shader: *const shaderops.FlatShader,
            index: usize,
            spx_image_scratch: *MatSlice(f64),
            perf_ctx: anytype,
            global_subx: usize,
            global_suby: usize,
        ) void {
            _ = _actual_fields;
            if (@TypeOf(perf_ctx).mode == .perf) {
                perf_ctx.recordDepth(global_subx, global_suby, 1.0 / sub_pixel_z);
            }
            
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillFlat(
                    N,
                    frame_index,
                    element_index,
                    fields_num,
                    fields_num,
                    weights,
                    shader,
                    index,
                    spx_image_scratch,
                );
            } else {
                shaderops.fillFlatPerspective(
                    N,
                    frame_index,
                    element_index,
                    fields_num,
                    fields_num,
                    weights,
                    nodes_inv_z,
                    sub_pixel_z,
                    shader,
                    index,
                    spx_image_scratch,
                );
            }           
        }
    };
}

pub fn TexKernel(comptime N: usize, comptime T: type, comptime interp_type: InterpType) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            frame_index: usize,
            element_index: usize,
            actual_fields: usize,
            fields_num: usize,
            weights: [N]f64,
            nodes_inv_z: [N]f64,
            sub_pixel_z: f64,
            shader: *const shaderops.TexShader(T),
            index: usize,
            spx_image_scratch: *MatSlice(f64),
            perf_ctx: anytype,
            global_subx: usize,
            global_suby: usize,
        ) void {
            if (@TypeOf(perf_ctx).mode == .perf) {
                perf_ctx.recordDepth(global_subx, global_suby, 1.0 / sub_pixel_z);
            }
            _ = frame_index;
            _ = actual_fields;
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    T,
                    interp_type,
                    element_index,
                    fields_num,
                    weights,
                    shader,
                    index,
                    spx_image_scratch,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    T,
                    interp_type,
                    element_index,
                    fields_num,
                    weights,
                    nodes_inv_z,
                    sub_pixel_z,
                    shader,
                    index,
                    spx_image_scratch,
                );
            }
        }
    };
}
