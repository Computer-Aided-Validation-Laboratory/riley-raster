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
pub const ScaleFactors = struct { mul: f64, add: f64 };

pub fn getScaleMax(bits: ?u8) f64 {
    if (bits) |b| {
        const max_u32 = (@as(u32, 1) << @as(u5, @intCast(b))) - 1;
        return @as(f64, @floatFromInt(max_u32));
    }
    return 1.0;
}

pub fn getScaleFactors(strategy: ScaleStrategy, bits: ?u8, params: ScalingParams) ScaleFactors {
    if (strategy == .none) return .{ .mul = 1.0, .add = 0.0 };
    var mul = 1.0 / params.range;
    var add = -params.min / params.range;
    switch (strategy) {
        .frac => |f| {
            mul = (f[1] - f[0]) / params.range;
            add = f[0] - params.min * (f[1] - f[0]) / params.range;
        },
        else => {},
    }
    if (bits) |b| {
        const m = getScaleMax(b);
        mul *= m;
        add *= m;
    }
    return .{ .mul = mul, .add = add };
}

pub fn getScalingParamsTexture(
    comptime T: type,
    comptime channels: usize,
    texture: *const @import("textureops.zig").Texture(T, channels),
    strategy: ScaleStrategy
) ScalingParams {
    switch (strategy) {
        .none => return .{ .min = 0.0, .range = 1.0 },
        .auto, .frac => {
            var px_min: f64 = std.math.inf(f64);
            var px_max: f64 = -std.math.inf(f64);
            for (texture.pixels) |px| {
                inline for (0..channels) |ch| {
                    const val = switch (@typeInfo(T)) {
                        .int => @as(f64, @floatFromInt(px.channels[ch])),
                        .float => @as(f64, px.channels[ch]),
                        else => @compileError("Unsupported type"),
                    };
                    if (val < px_min) px_min = val;
                    if (val > px_max) px_max = val;
                }
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
                const safe_fi = @min(fi, array.dims[0] - 1);
                const stride = array.strides[0];
                const frame_mem = array.elems[safe_fi * stride .. (safe_fi + 1) * stride];
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

pub fn averageImage(image_subpx: *const MatSlice(f64), 
                    sub_samp: u8, 
                    image_avg: *MatSlice(f64)) void {
                    
    const num_px_x: usize = (image_subpx.cols_n) / @as(usize, sub_samp);
    const num_px_y: usize = (image_subpx.rows_n) / @as(usize, sub_samp);
    const sub_samp_us: usize = @as(usize, sub_samp);
    const sub_samp_f: f64 = @as(f64, @floatFromInt(sub_samp));
    const subpx_per_px: f64 = sub_samp_f * sub_samp_f;

    var px_sum: f64 = 0.0;

    for (0..num_px_y) |iy| {
        for (0..num_px_x) |ix| {
            px_sum = 0.0;
            for (0..sub_samp_us) |sy| {
                for (0..sub_samp_us) |sx| {
                    px_sum += image_subpx.get(sub_samp_us * iy + sy, 
                                              sub_samp_us * ix + sx);
                }
            }
            image_avg.set(iy, ix, px_sum / subpx_per_px);
        }
    }
}
