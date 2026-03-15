const std = @import("std");
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

pub const ScaleStrategy = union(enum) {
    none,
    auto,
    fixed: [2]f64, // [min, max]
    frac: [2]f64,  // [min_frac, max_frac]
};

pub const ScalingParams = struct { min: f64, range: f64 };

pub fn getScaleMax(bits: ?u8) f64 {
    if (bits) |b| {
        const max_u32 = (@as(u32, 1) << @as(u5, @intCast(b))) - 1;
        return @as(f64, @floatFromInt(max_u32));
    }
    return 1.0;
}

pub fn getScalingParams(
    image: *const MatSlice(f64), 
    strategy: ScaleStrategy
) ScalingParams {
    switch (strategy) {
        .none => return .{ .min = 0.0, .range = 1.0 },
        .auto, .frac => {
            const px_min = std.mem.min(f64, image.elems);
            const px_max = std.mem.max(f64, image.elems);
            const px_rng = if (px_max > px_min) px_max - px_min else 1.0;
            return .{ .min = px_min, .range = px_rng };
        },
        .fixed => |range| {
            const px_rng = if (range[1] > range[0]) range[1] - range[0] else 1.0;
            return .{ .min = range[0], .range = px_rng };
        },
    }
}

pub fn getScalingParamsNDArray(
    array: *const NDArray(f64),
    frame_idx: ?usize,
    strategy: ScaleStrategy
) ScalingParams {
    switch (strategy) {
        .none => return .{ .min = 0.0, .range = 1.0 },
        .auto, .frac => {
            var px_min: f64 = std.math.inf(f64);
            var px_max: f64 = -std.math.inf(f64);

            if (frame_idx) |fi| {
                const stride = array.strides[0];
                const frame_mem = array.elems[fi * stride .. (fi + 1) * stride];
                px_min = std.mem.min(f64, frame_mem);
                px_max = std.mem.max(f64, frame_mem);
            } else {
                px_min = std.mem.min(f64, array.elems);
                px_max = std.mem.max(f64, array.elems);
            }

            const px_rng = if (px_max > px_min) px_max - px_min else 1.0;
            return .{ .min = px_min, .range = px_rng };
        },
        .fixed => |range| {
            const px_rng = if (range[1] > range[0]) range[1] - range[0] else 1.0;
            return .{ .min = range[0], .range = px_rng };
        },
    }
}

pub fn applyScaling(
    val: f64, 
    strategy: ScaleStrategy, 
    bits: ?u8, 
    params: ScalingParams
) f64 {
    const norm = switch (strategy) {
        .none => return val,
        .auto, .fixed => (val - params.min) / params.range,
        .frac => |f| f[0] + ((val - params.min) / params.range) * (f[1] - f[0]),
    };

    if (bits) |b| {
        return norm * getScaleMax(b);
    }
    return norm;
}

pub fn applyClamping(val: f64, bits: ?u8) f64 {
    if (bits) |b| {
        const max_v = getScaleMax(b);
        return @round(@max(0.0, @min(max_v, val)));
    }
    return val;
}
