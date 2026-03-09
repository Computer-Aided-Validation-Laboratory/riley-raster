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
            actual_fields: usize,
            fields_num: usize,
            weights: [N]f64,
            nodes_inv_z: [N]f64,
            sub_pixel_z: f64,
            shader: *const shaderops.FlatShader,
            index: usize,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime coord_space == CoordSpace.camera) {
                shaderops.fillFlat(
                    N,
                    frame_index,
                    element_index,
                    actual_fields,
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
                    actual_fields,
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
        ) void {
            _ = frame_index;
            _ = actual_fields;
            _ = fields_num;
            if (comptime coord_space == CoordSpace.camera) {
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
