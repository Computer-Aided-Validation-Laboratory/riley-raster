const std = @import("std");
const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const InterpType = texops.InterpType;

pub fn FlatKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime is_parent_space: bool,
            frame_ind: usize,
            elem_ind: usize,
            actual_fields: usize,
            fields_num: usize,
            weights: [N]f64,
            nodes_inv_z: [N]f64,
            sub_pixel_z: f64,
            shader: *const shaderops.FlatShader,
            idx: usize,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime is_parent_space) {
                shaderops.fillFlat(
                    N, frame_ind, elem_ind, actual_fields, fields_num, 
                    weights, shader, idx, spx_image_scratch
                );
            } else {
                shaderops.fillFlatPerspective(
                    N, frame_ind, elem_ind, actual_fields, fields_num, 
                    weights, nodes_inv_z, sub_pixel_z, shader, idx, spx_image_scratch
                );
            }
        }
    };
}

pub fn TexKernel(comptime N: usize, comptime interp_type: InterpType) type {
    return struct {
        pub inline fn shade(
            comptime is_parent_space: bool,
            frame_ind: usize,
            elem_ind: usize,
            actual_fields: usize,
            fields_num: usize,
            weights: [N]f64,
            nodes_inv_z: [N]f64,
            sub_pixel_z: f64,
            shader: *const shaderops.TexShader,
            idx: usize,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = frame_ind;
            _ = actual_fields;
            _ = fields_num;
            if (comptime is_parent_space) {
                shaderops.fillTex(
                    N, interp_type, elem_ind, weights, shader, idx, spx_image_scratch
                );
            } else {
                shaderops.fillTexPerspective(
                    N, interp_type, elem_ind, weights, nodes_inv_z, 
                    sub_pixel_z, shader, idx, spx_image_scratch
                );
            }
        }
    };
}
