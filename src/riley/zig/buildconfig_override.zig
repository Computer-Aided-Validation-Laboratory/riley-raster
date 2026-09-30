const speckleconfig = @import("speckleconfig.zig");

pub const enabled = false;
pub const precision = "f64";
pub const simd = "on";
pub const newton_solver = "fast";
pub const simd_vector_width: comptime_int = 0;
pub const speckle_neighbor_count: comptime_int = speckleconfig.default_neighbor_count;
pub const speckle_evaluator = speckleconfig.default_evaluator;
pub const speckle_shape = speckleconfig.default_shape;
pub const speckle_mask_samples_per_cell: comptime_int = speckleconfig.default_mask_samples_per_cell;
