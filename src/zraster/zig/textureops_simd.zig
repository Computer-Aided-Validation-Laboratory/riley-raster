const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSI = buildconfig.VecSI;
const VecSU = buildconfig.VecSU;
const tol = buildconfig.config.tolerance;
const common = @import("textureops_common.zig");

pub const InterpType = common.InterpType;
pub const Texture = common.Texture;
const LUT_SIZE = common.LUT_SIZE;
const cubic_lut = common.cubic_lut;
const quintic_lut = common.quintic_lut;
const cubicWeightPoly = common.cubicWeightPoly;
const quinticWeightPoly = common.quinticWeightPoly;
const getLerpWeights = common.getLerpWeights;
const getPx = common.getPx;

pub const sampleGeneric = common.sampleGeneric;
pub const sampleGreyscale = common.sampleGreyscale;

// --- Internal Helpers ---

fn v_getPxSIMD(
    comptime channels: usize,
    texture: anytype,
    v_xi: VecSI,
    v_yi: VecSI,
) [channels]VecSF {
    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));

    const v_splat_zero: VecSI = @splat(0);
    const v_cols_m1: VecSI = @splat(cols - 1);
    const v_rows_m1: VecSI = @splat(rows - 1);

    const v_ix = @as(
        VecSU,
        @intCast(@max(v_splat_zero, @min(v_xi, v_cols_m1))),
    );
    const v_iy = @as(
        VecSU,
        @intCast(@max(v_splat_zero, @min(v_yi, v_rows_m1))),
    );

    var res: [channels]VecSF = undefined;
    const stride_y = texture.array.strides[1];

    inline for (0..channels) |ch| {
        const base_ptr = texture.array.getPlanePtr(ch);
        const v_offsets = v_iy * @as(VecSU, @splat(stride_y)) + v_ix;

        // Fast path for contiguous horizontal reads
        const first_off = v_offsets[0];
        const v_expected = @as(VecSU, @splat(first_off)) + std.simd.iota(usize, S);
        const is_contiguous = @reduce(.And, v_offsets == v_expected);

        if (is_contiguous) {
            res[ch] = @as(*const [S]f64, @ptrCast(@alignCast(&base_ptr[first_off]))).*;
        } else {
            // Gather (scalar loop for now, hardware gather can be added later)
            var lane_res: [S]f64 = undefined;
            const offsets_arr: [S]usize = v_offsets;
            for (0..S) |ii| {
                lane_res[ii] = base_ptr[offsets_arr[ii]];
            }
            res[ch] = lane_res;
        }
    }
    return res;
}

fn sample2DInnerSIMD(
    comptime channels: usize,
    comptime N: usize,
    texture: anytype,
    x_i: isize,
    y_i: isize,
    wx: [N]f64,
    wy: [N]f64,
) [channels]f64 {
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
        const inv_w_sum = if (@abs(w_sum) > tol.texture.weight_sum)
            1.0 / w_sum
        else
            1.0;

        inline for (0..N) |jj| {
            const row_off =
                @as(usize, @intCast(start_y + @as(isize, @intCast(jj)))) * stride_y +
                @as(usize, @intCast(start_x));
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
                const px = getPx(
                    channels,
                    texture,
                    start_x + @as(isize, @intCast(ii)),
                    start_y + @as(isize, @intCast(jj)),
                );
                inline for (0..channels) |ch| {
                    res[ch] += px[ch] * w;
                }
                w_sum += w;
            }
        }
        if (@abs(w_sum) > tol.texture.weight_sum) {
            inline for (0..channels) |ch| {
                res[ch] /= w_sum;
            }
        }
    }

    return res;
}

fn v_cubicWeightSIMD(v_x: VecSF) VecSF {
    const v_ax = @abs(v_x);
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);

    const v_mask_inner = v_ax <= v_splat_one;
    const v_mask_outer = (v_ax < v_splat_two) & !v_mask_inner;

    const v_w1 =
        ((@as(VecSF, @splat(1.5)) * v_ax -
            @as(VecSF, @splat(2.5))) * v_ax +
            @as(VecSF, @splat(0.0))) * v_ax +
        v_splat_one;
    const v_w2 =
        ((-@as(VecSF, @splat(0.5)) * v_ax +
            @as(VecSF, @splat(2.5))) * v_ax -
            @as(VecSF, @splat(4.0))) * v_ax +
        v_splat_two;

    var res = @select(
        f64,
        v_mask_inner,
        v_w1,
        @as(VecSF, @splat(0.0)),
    );
    res = @select(f64, v_mask_outer, v_w2, res);
    return res;
}

fn v_quinticWeightSIMD(v_x: VecSF) VecSF {
    const v_ax = @abs(v_x);
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);
    const v_splat_three: VecSF = @splat(3.0);

    const v_mask_inner = v_ax <= v_splat_one;
    const v_mask_middle = (v_ax <= v_splat_two) & !v_mask_inner;
    const v_mask_outer =
        (v_ax < v_splat_three) & !v_mask_inner & !v_mask_middle;

    const v_w1 =
        ((((-@as(VecSF, @splat(0.416666)) * v_ax + v_splat_one) *
            v_ax +
            @as(VecSF, @splat(0.583333))) * v_ax -
            @as(VecSF, @splat(1.5))) * v_ax -
            @as(VecSF, @splat(0.083333))) * v_ax +
        v_splat_one;

    const v_shift_two = v_ax - v_splat_one;
    const v_w2 =
        ((((@as(VecSF, @splat(0.25)) * v_shift_two -
            @as(VecSF, @splat(0.833333))) * v_shift_two +
            @as(VecSF, @splat(0.416666))) * v_shift_two +
            @as(VecSF, @splat(0.5))) * v_shift_two -
            @as(VecSF, @splat(0.083333))) * v_shift_two;

    const v_shift_three = v_ax - v_splat_two;
    const v_w3 =
        ((((-@as(VecSF, @splat(0.008333)) * v_shift_three +
            @as(VecSF, @splat(0.083333))) * v_shift_three -
            @as(VecSF, @splat(0.041666))) * v_shift_three -
            @as(VecSF, @splat(0.083333))) * v_shift_three +
            @as(VecSF, @splat(0.041666))) * v_shift_three;

    var res = @select(
        f64,
        v_mask_inner,
        v_w1,
        @as(VecSF, @splat(0.0)),
    );
    res = @select(f64, v_mask_middle, v_w2, res);
    res = @select(f64, v_mask_outer, v_w3, res);
    return res;
}

pub fn sampleOverPixelsSIMD(
    comptime channels: usize,
    interp: InterpType,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [channels]VecSF {
    const cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

    const v_xf = v_u * @as(VecSF, @splat(cols_minus_1_f));
    const v_yf = v_v * @as(VecSF, @splat(rows_minus_1_f));

    var v_xi: [S]isize = undefined;
    var v_yi: [S]isize = undefined;
    const xf_arr: [S]f64 = v_xf;
    const yf_arr: [S]f64 = v_yf;

    for (0..S) |ii| {
        v_xi[ii] = @as(isize, @intFromFloat(@floor(xf_arr[ii])));
        v_yi[ii] = @as(isize, @intFromFloat(@floor(yf_arr[ii])));
    }

    const v_tx = v_xf - @as(VecSF, @floatFromInt(@as(VecSI, v_xi)));
    const v_ty = v_yf - @as(VecSF, @floatFromInt(@as(VecSI, v_yi)));

    return switch (interp) {
        .linear => {
            const v_p00 = v_getPxSIMD(channels, texture, v_xi, v_yi);
            const v_p10 = v_getPxSIMD(
                channels,
                texture,
                v_xi + @as(VecSI, @splat(1)),
                v_yi,
            );
            const v_p01 = v_getPxSIMD(
                channels,
                texture,
                v_xi,
                v_yi + @as(VecSI, @splat(1)),
            );
            const v_p11 = v_getPxSIMD(
                channels,
                texture,
                v_xi + @as(VecSI, @splat(1)),
                v_yi + @as(VecSI, @splat(1)),
            );

            var res: [channels]VecSF = undefined;
            const v_splat_one: VecSF = @splat(1.0);
            inline for (0..channels) |ch| {
                res[ch] = (v_splat_one - v_tx) * (v_splat_one - v_ty) *
                    v_p00[ch] +
                    v_tx * (v_splat_one - v_ty) * v_p10[ch] +
                    (v_splat_one - v_tx) * v_ty * v_p01[ch] +
                    v_tx * v_ty * v_p11[ch];
            }
            return res;
        },
        .cubic, .cubic_lut, .cubic_lut_lerp => {
            const K = 4;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;

            var v_wx: [K]VecSF = undefined;
            var v_wy: [K]VecSF = undefined;

            const tx_arr: [S]f64 = v_tx;
            const ty_arr: [S]f64 = v_ty;

            switch (interp) {
                .cubic => {
                    v_wx[0] = v_cubicWeightSIMD(v_tx + @as(VecSF, @splat(1.0)));
                    v_wx[1] = v_cubicWeightSIMD(v_tx);
                    v_wx[2] = v_cubicWeightSIMD(v_tx - @as(VecSF, @splat(1.0)));
                    v_wx[3] = v_cubicWeightSIMD(v_tx - @as(VecSF, @splat(2.0)));

                    v_wy[0] = v_cubicWeightSIMD(v_ty + @as(VecSF, @splat(1.0)));
                    v_wy[1] = v_cubicWeightSIMD(v_ty);
                    v_wy[2] = v_cubicWeightSIMD(v_ty - @as(VecSF, @splat(1.0)));
                    v_wy[3] = v_cubicWeightSIMD(v_ty - @as(VecSF, @splat(2.0)));
                },
                .cubic_lut => {
                    var wx_arr: [4][S]f64 = undefined;
                    var wy_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                        ));
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
                    var wx_arr: [4][S]f64 = undefined;
                    var wy_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
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

            var v_res: [channels]VecSF = [_]VecSF{@splat(0.0)} ** channels;
            var v_w_sum: VecSF = @splat(0.0);

            // Pre-calculate weight planes
            var v_w_planes: [K * K]VecSF = undefined;
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
                    const v_px_vecs = v_getPxSIMD(
                        channels,
                        texture,
                        v_xi + @as(VecSI, @splat(@as(isize, @intCast(ii)) - offset)),
                        v_yi + @as(VecSI, @splat(@as(isize, @intCast(jj)) - offset)),
                    );

                    inline for (0..channels) |ch| {
                        v_res[ch] += v_px_vecs[ch] * v_w;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_w_sum) < @as(
                    VecSF,
                    @splat(tol.texture.weight_sum),
                ),
                v_splat_one,
                v_splat_one / v_w_sum,
            );
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
        .quintic, .quintic_lut, .quintic_lut_lerp => {
            const K = 6;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;

            var v_wx: [K]VecSF = undefined;
            var v_wy: [K]VecSF = undefined;

            const tx_arr: [S]f64 = v_tx;
            const ty_arr: [S]f64 = v_ty;

            switch (interp) {
                .quintic => {
                    v_wx[0] = v_quinticWeightSIMD(v_tx + @as(VecSF, @splat(2.0)));
                    v_wx[1] = v_quinticWeightSIMD(v_tx + @as(VecSF, @splat(1.0)));
                    v_wx[2] = v_quinticWeightSIMD(v_tx);
                    v_wx[3] = v_quinticWeightSIMD(v_tx - @as(VecSF, @splat(1.0)));
                    v_wx[4] = v_quinticWeightSIMD(v_tx - @as(VecSF, @splat(2.0)));
                    v_wx[5] = v_quinticWeightSIMD(v_tx - @as(VecSF, @splat(3.0)));

                    v_wy[0] = v_quinticWeightSIMD(v_ty + @as(VecSF, @splat(2.0)));
                    v_wy[1] = v_quinticWeightSIMD(v_ty + @as(VecSF, @splat(1.0)));
                    v_wy[2] = v_quinticWeightSIMD(v_ty);
                    v_wy[3] = v_quinticWeightSIMD(v_ty - @as(VecSF, @splat(1.0)));
                    v_wy[4] = v_quinticWeightSIMD(v_ty - @as(VecSF, @splat(2.0)));
                    v_wy[5] = v_quinticWeightSIMD(v_ty - @as(VecSF, @splat(3.0)));
                },
                .quintic_lut => {
                    var wx_arr: [6][S]f64 = undefined;
                    var wy_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                        ));
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
                    var wx_arr: [6][S]f64 = undefined;
                    var wy_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
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

            var v_res: [channels]VecSF = [_]VecSF{@splat(0.0)} ** channels;
            var v_w_sum: VecSF = @splat(0.0);

            // Pre-calculate weight planes
            var v_w_planes: [K * K]VecSF = undefined;
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
                    const v_px_vecs = v_getPxSIMD(
                        channels,
                        texture,
                        v_xi + @as(VecSI, @splat(@as(isize, @intCast(ii)) - offset)),
                        v_yi + @as(VecSI, @splat(@as(isize, @intCast(jj)) - offset)),
                    );

                    inline for (0..channels) |ch| {
                        v_res[ch] += v_px_vecs[ch] * v_w;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_w_sum) < @as(
                    VecSF,
                    @splat(tol.texture.weight_sum),
                ),
                v_splat_one,
                v_splat_one / v_w_sum,
            );
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
    };
}

pub fn samplePerPixelInnerSIMD(
    comptime channels: usize,
    interp: InterpType,
    texture: anytype,
    u: f64,
    v: f64,
) [channels]f64 {
    const cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

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
            const wx = [4]f64{
                cubicWeightPoly(tx + 1),
                cubicWeightPoly(tx),
                cubicWeightPoly(tx - 1),
                cubicWeightPoly(tx - 2),
            };
            const wy = [4]f64{
                cubicWeightPoly(ty + 1),
                cubicWeightPoly(ty),
                cubicWeightPoly(ty - 1),
                cubicWeightPoly(ty - 2),
            };
            return sample2DInnerSIMD(channels, 4, texture, x_i, y_i, wx, wy);
        },
        .cubic_lut => {
            const idx_tx = @as(usize, @intFromFloat(
                tx * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            const idx_ty = @as(usize, @intFromFloat(
                ty * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            return sample2DInnerSIMD(
                channels,
                4,
                texture,
                x_i,
                y_i,
                cubic_lut[idx_tx],
                cubic_lut[idx_ty],
            );
        },
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2DInnerSIMD(channels, 4, texture, x_i, y_i, wx, wy);
        },
        .quintic => {
            const wx = [6]f64{
                quinticWeightPoly(tx + 2),
                quinticWeightPoly(tx + 1),
                quinticWeightPoly(tx),
                quinticWeightPoly(tx - 1),
                quinticWeightPoly(tx - 2),
                quinticWeightPoly(tx - 3),
            };
            const wy = [6]f64{
                quinticWeightPoly(ty + 2),
                quinticWeightPoly(ty + 1),
                quinticWeightPoly(ty),
                quinticWeightPoly(ty - 1),
                quinticWeightPoly(ty - 2),
                quinticWeightPoly(ty - 3),
            };
            return sample2DInnerSIMD(channels, 6, texture, x_i, y_i, wx, wy);
        },
        .quintic_lut => {
            const idx_tx = @as(usize, @intFromFloat(
                tx * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            const idx_ty = @as(usize, @intFromFloat(
                ty * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            return sample2DInnerSIMD(
                channels,
                6,
                texture,
                x_i,
                y_i,
                quintic_lut[idx_tx],
                quintic_lut[idx_ty],
            );
        },
        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2DInnerSIMD(channels, 6, texture, x_i, y_i, wx, wy);
        },
    };
}

pub fn samplePerLaneInnerSIMD(
    comptime channels: usize,
    interp: InterpType,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [channels]VecSF {
    var res_arr: [channels][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** channels;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    // Process each active lane in the SIMD front
    for (0..S) |ii| {
        if (mask_arr[ii]) {
            const sampled = samplePerPixelInnerSIMD(
                channels,
                interp,
                texture,
                u_arr[ii],
                v_arr[ii],
            );
            inline for (0..channels) |ch| {
                res_arr[ch][ii] = sampled[ch];
            }
        }
    }

    var res: [channels]VecSF = undefined;
    inline for (0..channels) |ch| {
        res[ch] = res_arr[ch];
    }

    return res;
}

pub fn samplePerLaneTri3SIMD(
    comptime channels: usize,
    interp: InterpType,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [channels]VecSF {
    var res_arr: [channels][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** channels;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    var active_lanes: [S]usize = undefined;
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

    for (0..S) |ii| {
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
        const sampled = samplePerPixelInnerSIMD(
            channels,
            interp,
            texture,
            u_arr[lane],
            v_arr[lane],
        );
        inline for (0..channels) |ch| {
            res_arr[ch][lane] = sampled[ch];
        }
    }

    var res: [channels]VecSF = undefined;
    inline for (0..channels) |ch| {
        res[ch] = res_arr[ch];
    }

    return res;
}
