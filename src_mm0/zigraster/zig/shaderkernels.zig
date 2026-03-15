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
            
            if (global_subx == 100 and global_suby == 100) {
                std.debug.print("shade: element={d}, space={s}\n", .{element_index, @tagName(coord_space)});
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
            
            if (spx_image_scratch.elems[index * fields_num] != 0.0) {
                // std.debug.print("shade: WRITE SUCCESS! val={d:.3}\n", .{spx_image_scratch.elems[index * fields_num]});
            }
        }
    };
}

pub fn TexKernel(comptime N: usize, comptime interp_type: InterpType) type {
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
            shader: *const shaderops.TexShader,
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
            _ = fields_num;
            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTex(
                    N,
                    interp_type,
                    element_index,
                    weights,
                    shader,
                    index,
                    spx_image_scratch,
                );
            } else {
                shaderops.fillTexPerspective(
                    N,
                    interp_type,
                    element_index,
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
