const std = @import("std");
const FeatureConfig = @import("featureconfig.zig").FeatureConfig;
const L = FeatureConfig.simd_lane_width;

pub fn ShadeContextSIMD(comptime N: usize) type {
    return struct {
        frame_index: usize,
        elem_index: usize,
        fields_num: usize,
        actual_fields: usize,
        idx: usize, // Start index in the tile/scratch buffer
        global_subx: @Vector(L, usize),
        global_suby: usize,
        local_buf: *const @import("shaderops.zig").LocalNodeBuffer(N),
    };
}

pub fn InterpDataSIMD(comptime N: usize) type {
    return struct {
        weights: [N]@Vector(L, f64),
        nodes_inv_z: [N]f64,
        sub_pixel_z: @Vector(L, f64),
    };
}
