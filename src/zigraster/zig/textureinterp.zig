const std = @import("std");
const assert = std.debug.assert;
const iio = @import("imageio.zig");

pub const InterpType = enum {
    linear,
    cubic,
    cubic_lut,
    cubic_lut_lerp,
    quintic,
    quintic_lut,
    quintic_lut_lerp,
};

// --- Weighting Functions ---

fn cubicWeightHorner(x: f64) f64 {
    const ax = @abs(x);
    if (ax <= 1.0) {
        return ((1.5 * ax - 2.5) * ax + 0.0) * ax + 1.0;
    } else if (ax < 2.0) {
        return ((-0.5 * ax + 2.5) * ax - 4.0) * ax + 2.0;
    }
    return 0.0;
}

fn quinticWeight(x: f64) f64 {
    const ax = @abs(x);
    if (ax < 0.0001) return 1.0;
    if (ax >= 3.0) return 0.0;
    const pix = std.math.pi * x;
    const pix3 = pix / 3.0;
    return (std.math.sin(pix) / pix) * (std.math.sin(pix3) / pix3);
}

fn quinticWeightHorner(x: f64) f64 {
    const ax = @abs(x);
    if (ax >= 3.0) return 0.0;
    if (ax <= 1.0) {
        return (((( -0.416666 * ax + 1.0) * ax + 0.583333) * ax - 1.5) *
               ax - 0.083333) * ax + 1.0;
    } else if (ax <= 2.0) {
        const t = ax - 1.0;
        return (((( 0.25 * t - 0.833333) * t + 0.416666) * t + 0.5) *
               t - 0.083333) * t + 0.0;
    } else {
        const t = ax - 2.0;
        return (((( -0.008333 * t + 0.083333) * t - 0.041666) * t - 0.083333) *
               t + 0.041666) * t + 0.0;
    }
}

// --- LUT Generation (Comptime) ---

const LUT_SIZE = 1024;

const cubic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][4]f64 = undefined;
    for (0..LUT_SIZE) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(LUT_SIZE));
        for (0..4) |j| {
            const x = @as(f64, @floatFromInt(j)) - 1.0 - t;
            const ax = @abs(x);
            const a = -0.5;
            if (ax <= 1.0) {
                table[i][j] = (a + 2.0) * ax * ax * ax - (a + 3.0) * ax * ax + 1.0;
            } else if (ax < 2.0) {
                table[i][j] = a * ax * ax * ax - 5.0 * a * ax * ax + 
                              8.0 * a * ax - 4.0 * a;
            } else {
                table[i][j] = 0.0;
            }
        }
    }
    break :blk table;
};

const quintic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][6]f64 = undefined;
    for (0..LUT_SIZE) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(LUT_SIZE));
        for (0..6) |j| {
            table[i][j] = quinticWeight(@as(f64, @floatFromInt(j)) - 2.0 - t);
        }
    }
    break :blk table;
};

// --- Internal Helpers ---

fn getPx1(texture: anytype, x: isize, y: isize) f64 {
    const cols = @as(isize, @intCast(texture.cols_n));
    const rows = @as(isize, @intCast(texture.rows_n));
    const ix = @as(usize, @intCast(@max(0, @min(x, cols - 1))));
    const iy = @as(usize, @intCast(@max(0, @min(y, rows - 1))));
    
    const px = texture.getPixel(iy, ix);
    const val = px.channels[0];
    const T = @TypeOf(val);
    return switch (@typeInfo(T)) {
        .int => @as(f64, @floatFromInt(val)),
        .float => @as(f64, @floatCast(val)),
        else => @compileError("Unsupported texture type"),
    };
}

fn sample2D(comptime N: usize,
            comptime use_simd: bool,
            texture: anytype,
            x_i: isize,
            y_i: isize,
            wx: [N]f64,
            wy: [N]f64) f64 {

    const offset = @as(isize, @intCast(N)) / 2 - 1;
    if (comptime use_simd) {
        const vwx: @Vector(N, f64) = wx;
        var res_v: @Vector(N, f64) = @splat(0.0);
        var w_sum_v: @Vector(N, f64) = @splat(0.0);
        for (0..N) |j| {
            const vwy: @Vector(N, f64) = @splat(wy[j]);
            var p: [N]f64 = undefined;
            inline for (0..N) |i| {
                p[i] = getPx1(texture, x_i + @as(isize, @intCast(i)) - offset,
                              y_i + @as(isize, @intCast(j)) - offset);
            }
            const vp: @Vector(N, f64) = p;
            const vw = vwx * vwy;
            res_v += vp * vw;
            w_sum_v += vw;
        }
        const w_sum = @reduce(.Add, w_sum_v);
        return @reduce(.Add, res_v) / (if (@abs(w_sum) < 1e-9) 1.0 else w_sum);
    } else {
        var res: f64 = 0.0;
        var w_sum: f64 = 0.0;
        for (0..N) |j| {
            for (0..N) |i| {
                const w = wx[i] * wy[j];
                res += getPx1(texture, x_i + @as(isize, @intCast(i)) - offset,
                              y_i + @as(isize, @intCast(j)) - offset) * w;
                w_sum += w;
            }
        }
        return res / (if (@abs(w_sum) < 1e-9) 1.0 else w_sum);
    }
}

fn getLerpWeights(comptime N: usize, comptime table: [LUT_SIZE][N]f64, t: f64) [N]f64 {
    const scaled = t * (LUT_SIZE - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const f = scaled - @as(f64, @floatFromInt(idx));
    var res: [N]f64 = undefined;
    const w0 = table[idx];
    const w1 = table[@min(idx + 1, LUT_SIZE - 1)];
    inline for (0..N) |i| {
        res[i] = w0[i] * (1.0 - f) + w1[i] * f;
    }
    return res;
}

// --- Public Sampling Functions ---

pub fn sampleGreyscale(comptime interp: InterpType,
                       texture: anytype,
                       u: f64,
                       v: f64) f64 {
    const cols_minus_1 = @as(isize, @intCast(texture.cols_n)) - 1;
    const rows_minus_1 = @as(isize, @intCast(texture.rows_n)) - 1;
    const x_f = u * @as(f64, @floatFromInt(cols_minus_1));
    const y_f = v * @as(f64, @floatFromInt(rows_minus_1));
    const x_i = @as(isize, @intFromFloat(@floor(x_f)));
    const y_i = @as(isize, @intFromFloat(@floor(y_f)));
    const tx = x_f - @as(f64, @floatFromInt(x_i));
    const ty = y_f - @as(f64, @floatFromInt(y_i));

    return switch (interp) {
        .linear => {
            const p00 = getPx1(texture, x_i, y_i);
            const p10 = getPx1(texture, x_i + 1, y_i);
            const p01 = getPx1(texture, x_i, y_i + 1);
            const p11 = getPx1(texture, x_i + 1, y_i + 1);
            return (1.0 - tx) * (1.0 - ty) * p00 + tx * (1.0 - ty) * p10 +
                   (1.0 - tx) * ty * p01 + tx * ty * p11;
        },
        .cubic => sample2D(4, true, texture, x_i, y_i,
            .{ cubicWeightHorner(tx+1), cubicWeightHorner(tx),
               cubicWeightHorner(tx-1), cubicWeightHorner(tx-2) },
            .{ cubicWeightHorner(ty+1), cubicWeightHorner(ty),
               cubicWeightHorner(ty-1), cubicWeightHorner(ty-2) }),
        .cubic_lut => sample2D(4, true, texture, x_i, y_i,
            cubic_lut[@as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))))],
            cubic_lut[@as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))))]),
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2D(4, true, texture, x_i, y_i, wx, wy);
        },
        .quintic => sample2D(6, true, texture, x_i, y_i,
            .{ quinticWeightHorner(tx+2), quinticWeightHorner(tx+1),
               quinticWeightHorner(tx), quinticWeightHorner(tx-1),
               quinticWeightHorner(tx-2), quinticWeightHorner(tx-3) },
            .{ quinticWeightHorner(ty+2), quinticWeightHorner(ty+1),
               quinticWeightHorner(ty), quinticWeightHorner(ty-1),
               quinticWeightHorner(ty-2), quinticWeightHorner(ty-3) }),
        .quintic_lut => sample2D(6, true, texture, x_i, y_i,
            quintic_lut[@as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))))],
            quintic_lut[@as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))))]),
        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2D(6, true, texture, x_i, y_i, wx, wy);
        },
    };
}
