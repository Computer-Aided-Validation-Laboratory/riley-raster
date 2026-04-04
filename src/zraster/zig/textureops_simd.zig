const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;
const buildconfig = @import("buildconfig.zig");
const common = @import("textureops_common.zig");

const NDArray = @import("ndarray.zig").NDArray;

pub const InterpType = common.InterpType;
pub const Pixel = common.Pixel;
pub const Texture = common.Texture;

fn cubicWeight(x: f64) f64 {
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
    if (ax < buildconfig.config.tolerance.texture.quintic_centre_snap) return 1.0;
    if (ax >= 3.0) return 0.0;
    const pix = std.math.pi * x;
    const pix3 = pix / 3.0;
    return (std.math.sin(pix) / pix) * (std.math.sin(pix3) / pix3);
}

fn quinticWeightPoly(x: f64) f64 {
    const ax = @abs(x);
    if (ax >= 3.0) return 0.0;
    if (ax <= 1.0) {
        return ((((-0.416666 * ax + 1.0) * ax + 0.583333) * ax - 1.5) *
            ax - 0.083333) * ax + 1.0;
    } else if (ax <= 2.0) {
        const t = ax - 1.0;
        return ((((0.25 * t - 0.833333) * t + 0.416666) * t + 0.5) *
            t - 0.083333) * t + 0.0;
    } else {
        const t = ax - 2.0;
        return ((((-0.008333 * t + 0.083333) * t - 0.041666) * t - 0.083333) *
            t + 0.041666) * t + 0.0;
    }
}

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

fn getPx(comptime channels: usize, texture: anytype, x: isize, y: isize) [channels]f64 {
    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));
    const ix = @as(usize, @intCast(@max(0, @min(x, cols - 1))));
    const iy = @as(usize, @intCast(@max(0, @min(y, rows - 1))));

    var res: [channels]f64 = undefined;
    inline for (0..channels) |ch| {
        res[ch] = texture.getVal(ch, iy, ix);
    }
    return res;
}

fn v_getPxSIMD(comptime channels: usize, texture: anytype, v_xi: @Vector(8, isize), v_yi: @Vector(8, isize)) [channels]@Vector(8, f64) {
    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));

    const v_0: @Vector(8, isize) = @splat(0);
    const v_cols_m1: @Vector(8, isize) = @splat(cols - 1);
    const v_rows_m1: @Vector(8, isize) = @splat(rows - 1);

    const v_ix = @as(@Vector(8, usize), @intCast(@max(v_0, @min(v_xi, v_cols_m1))));
    const v_iy = @as(@Vector(8, usize), @intCast(@max(v_0, @min(v_yi, v_rows_m1))));

    var res: [channels]@Vector(8, f64) = undefined;
    const stride_y = texture.array.strides[1];

    inline for (0..channels) |ch| {
        const base_ptr = texture.array.getPlanePtr(ch);
        const v_offsets = v_iy * @as(@Vector(8, usize), @splat(stride_y)) + v_ix;

        // Fast path for contiguous horizontal reads
        const first_off = v_offsets[0];
        const v_expected = @as(@Vector(8, usize), @splat(first_off)) + @Vector(8, usize){ 0, 1, 2, 3, 4, 5, 6, 7 };
        const is_contiguous = @reduce(.And, v_offsets == v_expected);

        if (is_contiguous) {
            res[ch] = @as(*const [8]f64, @ptrCast(@alignCast(&base_ptr[first_off]))).*;
        } else {
            // Gather (scalar loop for now, hardware gather can be added later)
            var lane_res: [8]f64 = undefined;
            const offsets_arr: [8]usize = v_offsets;
            for (0..8) |ii| {
                lane_res[ii] = base_ptr[offsets_arr[ii]];
            }
            res[ch] = lane_res;
        }
    }
    return res;
}

fn sample2DInnerSIMD(comptime channels: usize, comptime N: usize, texture: anytype, x_i: isize, y_i: isize, wx: [N]f64, wy: [N]f64) [channels]f64 {
    const offset = @as(isize, @intCast(N)) / 2 - 1;
    const start_x = x_i - offset;
    const start_y = y_i - offset;

    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));

    var res: [channels]f64 = [_]f64{0.0} ** channels;

    // Check if the entire NxN footprint is within bounds for fast vector access
    if (start_x >= 0 and start_x + @as(isize, @intCast(N)) <= cols and
        start_y >= 0 and start_y + @as(isize, @intCast(N)) <= rows)
    {
        const v_wx: @Vector(N, f64) = wx;
        const v_wy: @Vector(N, f64) = wy;
        const stride_y = texture.array.strides[1];

        const w_sum = @reduce(.Add, v_wx) * @reduce(.Add, v_wy);
        const inv_w_sum = if (
            @abs(w_sum) > buildconfig.config.tolerance.texture.weight_sum
        )
            1.0 / w_sum
        else
            1.0;

        inline for (0..N) |jj| {
            const row_off = @as(usize, @intCast(start_y + @as(isize, @intCast(jj)))) * stride_y + @as(usize, @intCast(start_x));
            const wy_val = v_wy[jj];

            inline for (0..channels) |ch| {
                const plane_ptr = texture.array.getPlanePtr(ch);
                const v_row: @Vector(N, f64) = plane_ptr[row_off..][0..N].*;
                res[ch] += @reduce(.Add, v_row * v_wx) * wy_val;
            }
        }

        inline for (0..channels) |ch| {
            res[ch] *= inv_w_sum;
        }
    } else {
        // Fallback to scalar sampling for edges
        var w_sum: f64 = 0.0;
        for (0..N) |jj| {
            for (0..N) |ii| {
                const w = wx[ii] * wy[jj];
                const px = getPx(channels, texture, start_x + @as(isize, @intCast(ii)), start_y + @as(isize, @intCast(jj)));
                inline for (0..channels) |ch| {
                    res[ch] += px[ch] * w;
                }
                w_sum += w;
            }
        }
        if (@abs(w_sum) > buildconfig.config.tolerance.texture.weight_sum) {
            inline for (0..channels) |ch| {
                res[ch] /= w_sum;
            }
        }
    }

    return res;
}

fn sample2D(comptime channels: usize, comptime N: usize, comptime use_simd: bool, texture: anytype, x_i: isize, y_i: isize, wx: [N]f64, wy: [N]f64) [channels]f64 {
    const offset = @as(isize, @intCast(N)) / 2 - 1;
    _ = use_simd;
    var res: [channels]f64 = [_]f64{0.0} ** channels;
    var w_sum: f64 = 0.0;

    for (0..N) |jj| {
        for (0..N) |ii| {
            const w = wx[ii] * wy[jj];
            const px = getPx(channels, texture, x_i + @as(isize, @intCast(ii)) - offset, y_i + @as(isize, @intCast(jj)) - offset);
            inline for (0..channels) |ch| {
                res[ch] += px[ch] * w;
            }
            w_sum += w;
        }
    }

    const inv_w_sum = if (@abs(w_sum) < buildconfig.config.tolerance.texture.weight_sum)
        1.0
    else
        1.0 / w_sum;
    inline for (0..channels) |ch| {
        res[ch] *= inv_w_sum;
    }
    return res;
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

pub fn sampleGeneric(comptime channels: usize, interp: InterpType, texture: anytype, u: f64, v: f64) [channels]f64 {
    const cols_minus_1 = @as(isize, @intCast(texture.cols_num)) - 1;
    const rows_minus_1 = @as(isize, @intCast(texture.rows_num)) - 1;
    const x_f = u * @as(f64, @floatFromInt(cols_minus_1));
    const y_f = v * @as(f64, @floatFromInt(rows_minus_1));
    const x_i = @as(isize, @intFromFloat(@floor(x_f)));
    const y_i = @as(isize, @intFromFloat(@floor(y_f)));
    const tx = x_f - @as(f64, @floatFromInt(x_i));
    const ty = y_f - @as(f64, @floatFromInt(y_i));

    return switch (interp) {
        .linear => {
            const p00 = getPx(channels, texture, x_i, y_i);
            const p10 = getPx(channels, texture, x_i + 1, y_i);
            const p01 = getPx(channels, texture, x_i, y_i + 1);
            const p11 = getPx(channels, texture, x_i + 1, y_i + 1);
            var res: [channels]f64 = undefined;
            inline for (0..channels) |ch| {
                res[ch] = (1.0 - tx) * (1.0 - ty) * p00[ch] + tx * (1.0 - ty) * p10[ch] +
                    (1.0 - tx) * ty * p01[ch] + tx * ty * p11[ch];
            }
            return res;
        },
        .cubic => sample2D(channels, 4, true, texture, x_i, y_i, .{ cubicWeight(tx + 1), cubicWeight(tx), cubicWeight(tx - 1), cubicWeight(tx - 2) }, .{ cubicWeight(ty + 1), cubicWeight(ty), cubicWeight(ty - 1), cubicWeight(ty - 2) }),
        .cubic_lut => sample2D(channels, 4, true, texture, x_i, y_i, cubic_lut[@as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))))], cubic_lut[@as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))))]),
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2D(channels, 4, true, texture, x_i, y_i, wx, wy);
        },
        .quintic => sample2D(channels, 6, true, texture, x_i, y_i, .{ quinticWeightPoly(tx + 2), quinticWeightPoly(tx + 1), quinticWeightPoly(tx), quinticWeightPoly(tx - 1), quinticWeightPoly(tx - 2), quinticWeightPoly(tx - 3) }, .{ quinticWeightPoly(ty + 2), quinticWeightPoly(ty + 1), quinticWeightPoly(ty), quinticWeightPoly(ty - 1), quinticWeightPoly(ty - 2), quinticWeightPoly(ty - 3) }),
        .quintic_lut => {
            const idx_tx = @as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            const idx_ty = @as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            return sample2D(channels, 6, true, texture, x_i, y_i, quintic_lut[idx_tx], quintic_lut[idx_ty]);
        },

        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2D(channels, 6, true, texture, x_i, y_i, wx, wy);
        },
    };
}

fn v_cubicWeightSIMD(v_x: @Vector(8, f64)) @Vector(8, f64) {
    const v_ax = @abs(v_x);
    const v_1: @Vector(8, f64) = @splat(1.0);
    const v_2: @Vector(8, f64) = @splat(2.0);

    const m1 = v_ax <= v_1;
    const m2 = (v_ax < v_2) & !m1;

    const v_w1 = ((@as(@Vector(8, f64), @splat(1.5)) * v_ax - @as(@Vector(8, f64), @splat(2.5))) * v_ax + @as(@Vector(8, f64), @splat(0.0))) * v_ax + v_1;
    const v_w2 = ((-@as(@Vector(8, f64), @splat(0.5)) * v_ax + @as(@Vector(8, f64), @splat(2.5))) * v_ax - @as(@Vector(8, f64), @splat(4.0))) * v_ax + v_2;

    var res = @select(f64, m1, v_w1, @as(@Vector(8, f64), @splat(0.0)));
    res = @select(f64, m2, v_w2, res);
    return res;
}

fn v_quinticWeightSIMD(v_x: @Vector(8, f64)) @Vector(8, f64) {
    const v_ax = @abs(v_x);
    const v_1: @Vector(8, f64) = @splat(1.0);
    const v_2: @Vector(8, f64) = @splat(2.0);
    const v_3: @Vector(8, f64) = @splat(3.0);

    const m1 = v_ax <= v_1;
    const m2 = (v_ax <= v_2) & !m1;
    const m3 = (v_ax < v_3) & !m1 & !m2;

    const v_w1 = ((((-@as(@Vector(8, f64), @splat(0.416666)) * v_ax + v_1) * v_ax + @as(@Vector(8, f64), @splat(0.583333))) * v_ax - @as(@Vector(8, f64), @splat(1.5))) * v_ax - @as(@Vector(8, f64), @splat(0.083333))) * v_ax + v_1;

    const t2 = v_ax - v_1;
    const v_w2 = ((((@as(@Vector(8, f64), @splat(0.25)) * t2 - @as(@Vector(8, f64), @splat(0.833333))) * t2 + @as(@Vector(8, f64), @splat(0.416666))) * t2 + @as(@Vector(8, f64), @splat(0.5))) * t2 - @as(@Vector(8, f64), @splat(0.083333))) * t2;

    const t3 = v_ax - v_2;
    const v_w3 = ((((-@as(@Vector(8, f64), @splat(0.008333)) * t3 + @as(@Vector(8, f64), @splat(0.083333))) * t3 - @as(@Vector(8, f64), @splat(0.041666))) * t3 - @as(@Vector(8, f64), @splat(0.083333))) * t3 + @as(@Vector(8, f64), @splat(0.041666))) * t3;

    var res = @select(f64, m1, v_w1, @as(@Vector(8, f64), @splat(0.0)));
    res = @select(f64, m2, v_w2, res);
    res = @select(f64, m3, v_w3, res);
    return res;
}

pub fn sampleGenericSIMD(comptime channels: usize, interp: InterpType, texture: anytype, v_u: @Vector(8, f64), v_v: @Vector(8, f64)) [channels]@Vector(8, f64) {
    const cols_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1));
    const rows_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1));

    const v_xf = v_u * @as(@Vector(8, f64), @splat(cols_minus_1_f));
    const v_yf = v_v * @as(@Vector(8, f64), @splat(rows_minus_1_f));

    var v_xi: [8]isize = undefined;
    var v_yi: [8]isize = undefined;
    const xf_arr: [8]f64 = v_xf;
    const yf_arr: [8]f64 = v_yf;

    for (0..8) |ii| {
        v_xi[ii] = @as(isize, @intFromFloat(@floor(xf_arr[ii])));
        v_yi[ii] = @as(isize, @intFromFloat(@floor(yf_arr[ii])));
    }

    const v_tx = v_xf - @as(@Vector(8, f64), @floatFromInt(@as(@Vector(8, isize), v_xi)));
    const v_ty = v_yf - @as(@Vector(8, f64), @floatFromInt(@as(@Vector(8, isize), v_yi)));

    return switch (interp) {
        .linear => {
            const v_p00 = v_getPxSIMD(channels, texture, v_xi, v_yi);
            const v_p10 = v_getPxSIMD(channels, texture, v_xi + @as(@Vector(8, isize), @splat(1)), v_yi);
            const v_p01 = v_getPxSIMD(channels, texture, v_xi, v_yi + @as(@Vector(8, isize), @splat(1)));
            const v_p11 = v_getPxSIMD(channels, texture, v_xi + @as(@Vector(8, isize), @splat(1)), v_yi + @as(@Vector(8, isize), @splat(1)));

            var res: [channels]@Vector(8, f64) = undefined;
            const v_1: @Vector(8, f64) = @splat(1.0);
            inline for (0..channels) |ch| {
                res[ch] = (v_1 - v_tx) * (v_1 - v_ty) * v_p00[ch] +
                    v_tx * (v_1 - v_ty) * v_p10[ch] +
                    (v_1 - v_tx) * v_ty * v_p01[ch] +
                    v_tx * v_ty * v_p11[ch];
            }
            return res;
        },
        .cubic, .cubic_lut, .cubic_lut_lerp => {
            const K = 4;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;

            var v_wx: [K]@Vector(8, f64) = undefined;
            var v_wy: [K]@Vector(8, f64) = undefined;

            const tx_arr: [8]f64 = v_tx;
            const ty_arr: [8]f64 = v_ty;

            switch (interp) {
                .cubic => {
                    v_wx[0] = v_cubicWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[1] = v_cubicWeightSIMD(v_tx);
                    v_wx[2] = v_cubicWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[3] = v_cubicWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(2.0)));

                    v_wy[0] = v_cubicWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[1] = v_cubicWeightSIMD(v_ty);
                    v_wy[2] = v_cubicWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[3] = v_cubicWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(2.0)));
                },
                .cubic_lut => {
                    var wx_arr: [4][8]f64 = undefined;
                    var wy_arr: [4][8]f64 = undefined;
                    for (0..8) |ii| {
                        const ix = @as(usize, @intFromFloat(tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        const iy = @as(usize, @intFromFloat(ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        inline for (0..4) |kk| {
                            wx_arr[kk][ii] = cubic_lut[ix][kk];
                            wy_arr[kk][ii] = cubic_lut[iy][kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                .cubic_lut_lerp => {
                    var wx_arr: [4][8]f64 = undefined;
                    var wy_arr: [4][8]f64 = undefined;
                    for (0..8) |ii| {
                        const wx = getLerpWeights(4, cubic_lut, tx_arr[ii]);
                        const wy = getLerpWeights(4, cubic_lut, ty_arr[ii]);
                        inline for (0..4) |kk| {
                            wx_arr[kk][ii] = wx[kk];
                            wy_arr[kk][ii] = wy[kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                else => unreachable,
            }

            var v_res: [channels]@Vector(8, f64) = [_]@Vector(8, f64){@splat(0.0)} ** channels;
            var v_w_sum: @Vector(8, f64) = @splat(0.0);

            // Pre-calculate weight planes
            var v_w_planes: [K * K]@Vector(8, f64) = undefined;
            inline for (0..K) |jj| {
                const v_wy_val = v_wy[jj];
                inline for (0..K) |ii| {
                    const v_w = v_wx[ii] * v_wy_val;
                    v_w_planes[jj * K + ii] = v_w;
                    v_w_sum += v_w;
                }
            }

            inline for (0..K) |jj| {
                inline for (0..K) |ii| {
                    const v_w = v_w_planes[jj * K + ii];
                    const v_px_vecs = v_getPxSIMD(channels, texture, v_xi + @as(@Vector(8, isize), @splat(@as(isize, @intCast(ii)) - offset)), v_yi + @as(@Vector(8, isize), @splat(@as(isize, @intCast(jj)) - offset)));

                    inline for (0..channels) |ch| {
                        v_res[ch] += v_px_vecs[ch] * v_w;
                    }
                }
            }

            const v_1: @Vector(8, f64) = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_w_sum) < @as(
                    @Vector(8, f64),
                    @splat(buildconfig.config.tolerance.texture.weight_sum),
                ),
                v_1,
                v_1 / v_w_sum,
            );
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
        .quintic, .quintic_lut, .quintic_lut_lerp => {
            const K = 6;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;

            var v_wx: [K]@Vector(8, f64) = undefined;
            var v_wy: [K]@Vector(8, f64) = undefined;

            const tx_arr: [8]f64 = v_tx;
            const ty_arr: [8]f64 = v_ty;

            switch (interp) {
                .quintic => {
                    v_wx[0] = v_quinticWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(2.0)));
                    v_wx[1] = v_quinticWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[2] = v_quinticWeightSIMD(v_tx);
                    v_wx[3] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[4] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(2.0)));
                    v_wx[5] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(3.0)));

                    v_wy[0] = v_quinticWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(2.0)));
                    v_wy[1] = v_quinticWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[2] = v_quinticWeightSIMD(v_ty);
                    v_wy[3] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[4] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(2.0)));
                    v_wy[5] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(3.0)));
                },
                .quintic_lut => {
                    var wx_arr: [6][8]f64 = undefined;
                    var wy_arr: [6][8]f64 = undefined;
                    for (0..8) |ii| {
                        const ix = @as(usize, @intFromFloat(tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        const iy = @as(usize, @intFromFloat(ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        inline for (0..6) |kk| {
                            wx_arr[kk][ii] = quintic_lut[ix][kk];
                            wy_arr[kk][ii] = quintic_lut[iy][kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                .quintic_lut_lerp => {
                    var wx_arr: [6][8]f64 = undefined;
                    var wy_arr: [6][8]f64 = undefined;
                    for (0..8) |ii| {
                        const wx = getLerpWeights(6, quintic_lut, tx_arr[ii]);
                        const wy = getLerpWeights(6, quintic_lut, ty_arr[ii]);
                        inline for (0..6) |kk| {
                            wx_arr[kk][ii] = wx[kk];
                            wy_arr[kk][ii] = wy[kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                else => unreachable,
            }

            var v_res: [channels]@Vector(8, f64) = [_]@Vector(8, f64){@splat(0.0)} ** channels;
            var v_w_sum: @Vector(8, f64) = @splat(0.0);

            // Pre-calculate weight planes
            var v_w_planes: [K * K]@Vector(8, f64) = undefined;
            inline for (0..K) |jj| {
                const v_wy_val = v_wy[jj];
                inline for (0..K) |ii| {
                    const v_w = v_wx[ii] * v_wy_val;
                    v_w_planes[jj * K + ii] = v_w;
                    v_w_sum += v_w;
                }
            }

            inline for (0..K) |jj| {
                inline for (0..K) |ii| {
                    const v_w = v_w_planes[jj * K + ii];
                    const v_px_vecs = v_getPxSIMD(channels, texture, v_xi + @as(@Vector(8, isize), @splat(@as(isize, @intCast(ii)) - offset)), v_yi + @as(@Vector(8, isize), @splat(@as(isize, @intCast(jj)) - offset)));

                    inline for (0..channels) |ch| {
                        v_res[ch] += v_px_vecs[ch] * v_w;
                    }
                }
            }

            const v_1: @Vector(8, f64) = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_w_sum) < @as(
                    @Vector(8, f64),
                    @splat(buildconfig.config.tolerance.texture.weight_sum),
                ),
                v_1,
                v_1 / v_w_sum,
            );
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
    };
}

pub fn sampleGenericInnerSIMD(comptime channels: usize, interp: InterpType, texture: anytype, u: f64, v: f64) [channels]f64 {
    const cols_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1));
    const rows_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1));

    const xf = u * cols_minus_1_f;
    const yf = v * rows_minus_1_f;

    const x_i = @as(isize, @intFromFloat(@floor(xf)));
    const y_i = @as(isize, @intFromFloat(@floor(yf)));

    const tx = xf - @as(f64, @floatFromInt(x_i));
    const ty = yf - @as(f64, @floatFromInt(y_i));

    return switch (interp) {
        .linear => {
            const wx = [2]f64{ 1.0 - tx, tx };
            const wy = [2]f64{ 1.0 - ty, ty };
            return sample2DInnerSIMD(channels, 2, texture, x_i, y_i, wx, wy);
        },
        .cubic => {
            const wx = [4]f64{ cubicWeight(tx + 1), cubicWeight(tx), cubicWeight(tx - 1), cubicWeight(tx - 2) };
            const wy = [4]f64{ cubicWeight(ty + 1), cubicWeight(ty), cubicWeight(ty - 1), cubicWeight(ty - 2) };
            return sample2DInnerSIMD(channels, 4, texture, x_i, y_i, wx, wy);
        },
        .cubic_lut => {
            const idx_tx = @as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            const idx_ty = @as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            return sample2DInnerSIMD(channels, 4, texture, x_i, y_i, cubic_lut[idx_tx], cubic_lut[idx_ty]);
        },
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2DInnerSIMD(channels, 4, texture, x_i, y_i, wx, wy);
        },
        .quintic => {
            const wx = [6]f64{ quinticWeightPoly(tx + 2), quinticWeightPoly(tx + 1), quinticWeightPoly(tx), quinticWeightPoly(tx - 1), quinticWeightPoly(tx - 2), quinticWeightPoly(tx - 3) };
            const wy = [6]f64{ quinticWeightPoly(ty + 2), quinticWeightPoly(ty + 1), quinticWeightPoly(ty), quinticWeightPoly(ty - 1), quinticWeightPoly(ty - 2), quinticWeightPoly(ty - 3) };
            return sample2DInnerSIMD(channels, 6, texture, x_i, y_i, wx, wy);
        },
        .quintic_lut => {
            const idx_tx = @as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            const idx_ty = @as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            return sample2DInnerSIMD(channels, 6, texture, x_i, y_i, quintic_lut[idx_tx], quintic_lut[idx_ty]);
        },
        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2DInnerSIMD(channels, 6, texture, x_i, y_i, wx, wy);
        },
    };
}

pub fn sampleGenericHybrid(comptime channels: usize, interp: InterpType, v_mask: @Vector(8, bool), texture: anytype, v_u: @Vector(8, f64), v_v: @Vector(8, f64)) [channels]@Vector(8, f64) {
    var res_arr: [channels][8]f64 = [_][8]f64{[_]f64{0.0} ** 8} ** channels;
    const mask_arr: [8]bool = v_mask;
    const u_arr: [8]f64 = v_u;
    const v_arr: [8]f64 = v_v;

    // Process each active lane in the SIMD front
    for (0..8) |ii| {
        if (mask_arr[ii]) {
            const sampled = sampleGenericInnerSIMD(channels, interp, texture, u_arr[ii], v_arr[ii]);
            inline for (0..channels) |ch| {
                res_arr[ch][ii] = sampled[ch];
            }
        }
    }

    var res: [channels]@Vector(8, f64) = undefined;
    inline for (0..channels) |ch| {
        res[ch] = res_arr[ch];
    }

    return res;
}

pub fn sampleGenericHybridTri3Local(comptime channels: usize, interp: InterpType, v_mask: @Vector(8, bool), texture: anytype, v_u: @Vector(8, f64), v_v: @Vector(8, f64)) [channels]@Vector(8, f64) {
    var res_arr: [channels][8]f64 = [_][8]f64{[_]f64{0.0} ** 8} ** channels;
    const mask_arr: [8]bool = v_mask;
    const u_arr: [8]f64 = v_u;
    const v_arr: [8]f64 = v_v;

    var active_lanes: [8]usize = undefined;
    var active_count: usize = 0;

    const cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );
    const cols_minus_1_i = @as(isize, @intCast(texture.cols_num)) - 1;
    const rows_minus_1_i = @as(isize, @intCast(texture.rows_num)) - 1;

    for (0..8) |ii| {
        if (mask_arr[ii]) {
            active_lanes[active_count] = ii;
            active_count += 1;
        }
    }

    if (active_count > 1) {
        var lane_keys: [8]u64 = undefined;
        for (0..active_count) |ii| {
            const lane = active_lanes[ii];
            const xf = u_arr[lane] * cols_minus_1_f;
            const yf = v_arr[lane] * rows_minus_1_f;
            const x_i = @as(isize, @intFromFloat(@floor(xf)));
            const y_i = @as(isize, @intFromFloat(@floor(yf)));
            const x_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(x_i, cols_minus_1_i))),
            );
            const y_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(y_i, rows_minus_1_i))),
            );
            lane_keys[ii] = (@as(u64, @intCast(y_key)) << 32) | @as(u64, @intCast(x_key));
        }

        for (1..active_count) |ii| {
            const lane = active_lanes[ii];
            const lane_key = lane_keys[ii];
            var jj = ii;
            while (jj > 0 and lane_key < lane_keys[jj - 1]) : (jj -= 1) {
                lane_keys[jj] = lane_keys[jj - 1];
                active_lanes[jj] = active_lanes[jj - 1];
            }
            lane_keys[jj] = lane_key;
            active_lanes[jj] = lane;
        }
    }

    for (0..active_count) |ii| {
        const lane = active_lanes[ii];
        const sampled = sampleGenericInnerSIMD(channels, interp, texture, u_arr[lane], v_arr[lane]);
        inline for (0..channels) |ch| {
            res_arr[ch][lane] = sampled[ch];
        }
    }

    var res: [channels]@Vector(8, f64) = undefined;
    inline for (0..channels) |ch| {
        res[ch] = res_arr[ch];
    }

    return res;
}

pub fn sampleGreyscale(comptime interp: InterpType, texture: anytype, u: f64, v: f64) f64 {
    return sampleGeneric(1, interp, texture, u, v)[0];
}
