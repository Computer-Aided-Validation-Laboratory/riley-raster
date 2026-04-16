const std = @import("std");

const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSI = buildconfig.VecSI;
const VecSU = buildconfig.VecSU;
const lut_size = cfg.interp_lut_size;
const tol = cfg.tolerance;

const common = @import("textureops_common.zig");
pub const TextureSample = common.TextureSample;
pub const TextureSampleMode = common.TextureSampleMode;
pub const TextureSampleConfig = common.TextureSampleConfig;
pub const Texture = common.Texture;

const catmull_rom_lut = common.catmull_rom_lut;
const mitchell_netravali_lut = common.mitchell_netravali_lut;
const cubic_bspline_lut = common.cubic_bspline_lut;
const lanczos3_lut = common.lanczos3_lut;
const quintic_bspline_lut = common.quintic_bspline_lut;
const cubicCoeffCatmullRom = common.cubicCoeffCatmullRom;
const cubicCoeffMitchellNetravali = common.cubicCoeffMitchellNetravali;
const cubicBSplineCoeff = common.cubicBSplineCoeff;
const lanczos3Coeff = common.lanczos3Coeff;
const quinticBSplineCoeff = common.quinticBSplineCoeff;
const getLerpSampCoeffs = common.getLerpSampCoeffs;
const getLerpSampCoeffsRuntime = common.getLerpSampCoeffsRuntime;
const getPx = common.getPx;

pub const sampleGeneric = common.sampleGeneric;
pub const sampleGreyscale = common.sampleGreyscale;

fn v_getPxSIMD(
    comptime CH: usize,
    texture: anytype,
    v_tex_x_i: VecSI,
    v_tex_y_i: VecSI,
) [CH]VecSF {
    const tex_cols = @as(isize, @intCast(texture.cols_num));
    const tex_rows = @as(isize, @intCast(texture.rows_num));

    const v_splat_zero: VecSI = @splat(0);
    const v_tex_cols_m1: VecSI = @splat(tex_cols - 1);
    const v_tex_rows_m1: VecSI = @splat(tex_rows - 1);

    const v_xu = @as(
        VecSU,
        @intCast(@max(v_splat_zero, @min(v_tex_x_i, v_tex_cols_m1))),
    );
    const v_yu = @as(
        VecSU,
        @intCast(@max(v_splat_zero, @min(v_tex_y_i, v_tex_rows_m1))),
    );

    var samp_res: [CH]VecSF = undefined;
    const stride_y = texture.array.strides[1];

    inline for (0..CH) |ch| {
        const base_slice = texture.array.getPlaneSlice(ch);
        const v_tap_offsets = v_yu * @as(VecSU, @splat(stride_y)) + v_xu;

        const first_off = v_tap_offsets[0];
        const v_expected = @as(VecSU, @splat(first_off)) + std.simd.iota(usize, S);
        const is_contiguous = @reduce(.And, v_tap_offsets == v_expected);

        if (is_contiguous) {
            samp_res[ch] = base_slice[first_off..][0..S].*;
        } else {
            var px_res: [S]f64 = undefined;
            const tap_offsets_arr: [S]usize = v_tap_offsets;
            for (0..S) |ii| {
                px_res[ii] = base_slice[tap_offsets_arr[ii]];
            }
            samp_res[ch] = px_res;
        }
    }
    return samp_res;
}

fn sample2DInnerSIMD(
    comptime CH: usize,
    comptime TAP: usize,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    samp_coeff_x: [TAP]f64,
    samp_coeff_y: [TAP]f64,
) [CH]f64 {
    const tap_offset = @as(isize, @intCast(TAP)) / 2 - 1;
    const tex_start_x = tex_x_i - tap_offset;
    const tex_start_y = tex_y_i - tap_offset;

    const tex_cols = @as(isize, @intCast(texture.cols_num));
    const tex_rows = @as(isize, @intCast(texture.rows_num));

    var samp_res: [CH]f64 = [_]f64{0.0} ** CH;

    if (tex_start_x >= 0 and tex_start_x + @as(isize, @intCast(TAP)) <= tex_cols and
        tex_start_y >= 0 and tex_start_y + @as(isize, @intCast(TAP)) <= tex_rows)
    {
        const v_samp_coeff_x: @Vector(TAP, f64) = samp_coeff_x;
        const v_samp_coeff_y: @Vector(TAP, f64) = samp_coeff_y;
        const stride_y = texture.array.strides[1];

        const samp_coeff_sum = @reduce(.Add, v_samp_coeff_x) *
            @reduce(.Add, v_samp_coeff_y);
        const inv_samp_coeff_sum = if (@abs(samp_coeff_sum) > tol.texture.samp_coeff_sum)
            1.0 / samp_coeff_sum
        else
            1.0;

        inline for (0..TAP) |jj| {
            const row_off =
                @as(usize, @intCast(tex_start_y + @as(isize, @intCast(jj)))) * stride_y +
                @as(usize, @intCast(tex_start_x));
            const wy_val = v_samp_coeff_y[jj];

            inline for (0..CH) |ch| {
                const plane_slice = texture.array.getPlaneSlice(ch);
                const v_row: @Vector(TAP, f64) = plane_slice[row_off..][0..TAP].*;
                samp_res[ch] += @reduce(.Add, v_row * v_samp_coeff_x) * wy_val;
            }
        }

        inline for (0..CH) |ch| {
            samp_res[ch] *= inv_samp_coeff_sum;
        }
    } else {
        var samp_coeff_sum: f64 = 0.0;
        for (0..TAP) |jj| {
            for (0..TAP) |ii| {
                const w = samp_coeff_x[ii] * samp_coeff_y[jj];
                const px = getPx(
                    CH,
                    texture,
                    tex_start_x + @as(isize, @intCast(ii)),
                    tex_start_y + @as(isize, @intCast(jj)),
                );
                inline for (0..CH) |ch| {
                    samp_res[ch] += px[ch] * w;
                }
                samp_coeff_sum += w;
            }
        }
        if (@abs(samp_coeff_sum) > tol.texture.samp_coeff_sum) {
            inline for (0..CH) |ch| {
                samp_res[ch] /= samp_coeff_sum;
            }
        }
    }

    return samp_res;
}

fn v_cubicCoeffCatmullRomSIMD(v_x: VecSF) VecSF {
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

    var samp_res = @select(
        f64,
        v_mask_inner,
        v_w1,
        @as(VecSF, @splat(0.0)),
    );
    samp_res = @select(f64, v_mask_outer, v_w2, samp_res);
    return samp_res;
}

fn v_cubicCoeffMitchellNetravaliSIMD(v_x: VecSF) VecSF {
    const v_r = @abs(v_x);
    const B = 1.0 / 3.0;
    const C = 1.0 / 3.0;
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);

    const v_mask_inner = v_r < v_splat_one;
    const v_mask_outer = (v_r < v_splat_two) & !v_mask_inner;

    const v_w1 = ((@as(VecSF, @splat(12.0 - 9.0 * B - 6.0 * C)) * v_r * v_r * v_r +
        @as(VecSF, @splat(-18.0 + 12.0 * B + 6.0 * C)) * v_r * v_r +
        @as(VecSF, @splat(6.0 - 2.0 * B))) / @as(VecSF, @splat(6.0)));

    const v_w2 = ((@as(VecSF, @splat(-B - 6.0 * C)) * v_r * v_r * v_r +
        @as(VecSF, @splat(6.0 * B + 30.0 * C)) * v_r * v_r +
        @as(VecSF, @splat(-12.0 * B - 48.0 * C)) * v_r +
        @as(VecSF, @splat(8.0 * B + 24.0 * C))) / @as(VecSF, @splat(6.0)));

    var samp_res = @select(f64, v_mask_inner, v_w1, @as(VecSF, @splat(0.0)));
    samp_res = @select(f64, v_mask_outer, v_w2, samp_res);
    return samp_res;
}

fn v_cubicBSplineCoeffSIMD(v_x: VecSF) VecSF {
    const v_r = @abs(v_x);
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);

    const v_mask_inner = v_r < v_splat_one;
    const v_mask_outer = (v_r < v_splat_two) & !v_mask_inner;

    const v_w1 = (@as(VecSF, @splat(3.0)) * v_r * v_r * v_r -
        @as(VecSF, @splat(6.0)) * v_r * v_r + @as(VecSF, @splat(4.0))) / @as(VecSF, @splat(6.0));

    const v_t = v_splat_two - v_r;
    const v_w2 = v_t * v_t * v_t / @as(VecSF, @splat(6.0));

    var samp_res = @select(f64, v_mask_inner, v_w1, @as(VecSF, @splat(0.0)));
    samp_res = @select(f64, v_mask_outer, v_w2, samp_res);
    return samp_res;
}

fn v_lanczos3CoeffSIMD(v_x: VecSF) VecSF {
    const v_ax = @abs(v_x);
    var samp_res_arr: [S]f64 = undefined;
    const ax_arr: [S]f64 = v_ax;
    for (0..S) |ii| {
        samp_res_arr[ii] = lanczos3Coeff(ax_arr[ii]);
    }
    return samp_res_arr;
}

fn v_quinticBSplineCoeffSIMD(v_x: VecSF) VecSF {
    const v_r = @abs(v_x);
    const v_splat_zero: VecSF = @splat(0.0);
    const v_splat_one: VecSF = @splat(1.0);
    const v_splat_two: VecSF = @splat(2.0);
    const v_splat_three: VecSF = @splat(3.0);

    const v_mask_inner = v_r <= v_splat_one;
    const v_mask_middle = (v_r <= v_splat_two) & !v_mask_inner;
    const v_mask_outer = (v_r < v_splat_three) & !v_mask_inner & !v_mask_middle;

    const v_w1 = ((((-@as(VecSF, @splat(1.0 / 12.0)) * v_r + @as(VecSF, @splat(1.0 / 4.0))) *
        v_r + v_splat_zero) * v_r - @as(VecSF, @splat(1.0 / 2.0))) * v_r +
        v_splat_zero) * v_r + @as(VecSF, @splat(11.0 / 20.0));

    const v_t = v_r - v_splat_one;
    const v_w2 = (((((@as(VecSF, @splat(1.0 / 24.0)) * v_t - @as(VecSF, @splat(1.0 / 6.0))) *
        v_t + @as(VecSF, @splat(1.0 / 6.0))) * v_t + @as(VecSF, @splat(1.0 / 6.0))) * v_t -
        @as(VecSF, @splat(5.0 / 12.0))) * v_t + @as(VecSF, @splat(13.0 / 60.0)));

    const v_u = v_r - v_splat_two;
    const v_w3 = (((((@as(VecSF, @splat(-1.0 / 120.0)) * v_u +
        @as(VecSF, @splat(1.0 / 24.0))) * v_u - @as(VecSF, @splat(1.0 / 12.0))) * v_u +
        @as(VecSF, @splat(1.0 / 12.0))) * v_u - @as(VecSF, @splat(1.0 / 24.0))) *
        v_u + @as(VecSF, @splat(1.0 / 120.0)));

    var samp_res = @select(f64, v_mask_inner, v_w1, @as(VecSF, @splat(0.0)));
    samp_res = @select(f64, v_mask_middle, v_w2, samp_res);
    samp_res = @select(f64, v_mask_outer, v_w3, samp_res);
    return samp_res;
}

pub fn sampleOverPixelsSIMD(
    comptime CH: usize,
    comptime config: TextureSampleConfig,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    std.debug.assert(config.isValid());
    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

    const v_tex_x_f = v_u * @as(VecSF, @splat(tex_cols_minus_1_f));
    const v_tex_y_f = v_v * @as(VecSF, @splat(tex_rows_minus_1_f));

    var v_tex_x_i: [S]isize = undefined;
    var v_tex_y_i: [S]isize = undefined;
    const tex_x_f_arr: [S]f64 = v_tex_x_f;
    const tex_y_f_arr: [S]f64 = v_tex_y_f;

    for (0..S) |ii| {
        v_tex_x_i[ii] = @as(isize, @intFromFloat(@floor(tex_x_f_arr[ii])));
        v_tex_y_i[ii] = @as(isize, @intFromFloat(@floor(tex_y_f_arr[ii])));
    }

    const v_tex_x_frac = v_tex_x_f - @as(VecSF, @floatFromInt(@as(VecSI, v_tex_x_i)));
    const v_tex_y_frac = v_tex_y_f - @as(VecSF, @floatFromInt(@as(VecSI, v_tex_y_i)));

    return switch (config.sample) {
        .nearest => v_getPxSIMD(
            CH,
            texture,
            @as(VecSI, @intFromFloat(@round(v_tex_x_f))),
            @as(VecSI, @intFromFloat(@round(v_tex_y_f))),
        ),
        .linear => {
            const v_p00 = v_getPxSIMD(CH, texture, v_tex_x_i, v_tex_y_i);
            const v_p10 = v_getPxSIMD(
                CH,
                texture,
                v_tex_x_i + @as(VecSI, @splat(1)),
                v_tex_y_i,
            );
            const v_p01 = v_getPxSIMD(
                CH,
                texture,
                v_tex_x_i,
                v_tex_y_i + @as(VecSI, @splat(1)),
            );
            const v_p11 = v_getPxSIMD(
                CH,
                texture,
                v_tex_x_i + @as(VecSI, @splat(1)),
                v_tex_y_i + @as(VecSI, @splat(1)),
            );

            var samp_res: [CH]VecSF = undefined;
            const v_splat_one: VecSF = @splat(1.0);
            inline for (0..CH) |ch| {
                samp_res[ch] = (v_splat_one - v_tex_x_frac) * (v_splat_one - v_tex_y_frac) *
                    v_p00[ch] +
                    v_tex_x_frac * (v_splat_one - v_tex_y_frac) * v_p10[ch] +
                    (v_splat_one - v_tex_x_frac) * v_tex_y_frac * v_p01[ch] +
                    v_tex_x_frac * v_tex_y_frac * v_p11[ch];
            }
            return samp_res;
        },
        .cubic_catmull_rom, .cubic_mitchell_netravali, .cubic_bspline => {
            const TAP = 4;
            const tap_offset = @divTrunc(@as(isize, @intCast(TAP)), 2) - 1;

            var v_samp_coeff_x: [TAP]VecSF = undefined;
            var v_samp_coeff_y: [TAP]VecSF = undefined;

            const tex_x_frac_arr: [S]f64 = v_tex_x_frac;
            const tex_y_frac_arr: [S]f64 = v_tex_y_frac;

            const lut = switch (config.sample) {
                .cubic_catmull_rom => catmull_rom_lut,
                .cubic_mitchell_netravali => mitchell_netravali_lut,
                .cubic_bspline => cubic_bspline_lut,
                else => unreachable,
            };

            switch (config.mode) {
                .direct => {
                    const v_kernel: *const fn (VecSF) VecSF = switch (config.sample) {
                        .cubic_catmull_rom => v_cubicCoeffCatmullRomSIMD,
                        .cubic_mitchell_netravali => v_cubicCoeffMitchellNetravaliSIMD,
                        .cubic_bspline => v_cubicBSplineCoeffSIMD,
                        else => unreachable,
                    };
                    v_samp_coeff_x[0] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[1] = v_kernel(v_tex_x_frac);
                    v_samp_coeff_x[2] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[3] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(2.0)));

                    v_samp_coeff_y[0] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[1] = v_kernel(v_tex_y_frac);
                    v_samp_coeff_y[2] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[3] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(2.0)));
                },
                .lut => {
                    var samp_coeff_x_arr: [4][S]f64 = undefined;
                    var samp_coeff_y_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tex_x_frac_arr[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            tex_y_frac_arr[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        inline for (0..4) |kk| {
                            samp_coeff_x_arr[kk][ii] = lut[ix][kk];
                            samp_coeff_y_arr[kk][ii] = lut[iy][kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
                .lut_lerp => {
                    var samp_coeff_x_arr: [4][S]f64 = undefined;
                    var samp_coeff_y_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
                        const samp_coeff_x = getLerpSampCoeffs(
                            4,
                            lut,
                            tex_x_frac_arr[ii],
                        );
                        const samp_coeff_y = getLerpSampCoeffs(
                            4,
                            lut,
                            tex_y_frac_arr[ii],
                        );
                        inline for (0..4) |kk| {
                            samp_coeff_x_arr[kk][ii] = samp_coeff_x[kk];
                            samp_coeff_y_arr[kk][ii] = samp_coeff_y[kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
            }

            var samp_res: [CH]VecSF = [_]VecSF{@splat(0.0)} ** CH;
            var v_samp_coeff_sum: VecSF = @splat(0.0);

            var v_tap_samp_coeff_planes: [TAP * TAP]VecSF = undefined;
            inline for (0..TAP) |jj| {
                const v_samp_coeff_y_val = v_samp_coeff_y[jj];
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_samp_coeff_x[ii] * v_samp_coeff_y_val;
                    v_tap_samp_coeff_planes[jj * TAP + ii] = v_tap_samp_coeff;
                    v_samp_coeff_sum += v_tap_samp_coeff;
                }
            }

            inline for (0..TAP) |jj| {
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_tap_samp_coeff_planes[jj * TAP + ii];
                    const v_px_vecs = v_getPxSIMD(
                        CH,
                        texture,
                        v_tex_x_i + @as(
                            VecSI,
                            @splat(@as(isize, @intCast(ii)) - tap_offset),
                        ),
                        v_tex_y_i + @as(
                            VecSI,
                            @splat(@as(isize, @intCast(jj)) - tap_offset),
                        ),
                    );

                    inline for (0..CH) |ch| {
                        samp_res[ch] += v_px_vecs[ch] * v_tap_samp_coeff;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_samp_coeff_sum) < @as(
                    VecSF,
                    @splat(tol.texture.samp_coeff_sum),
                ),
                v_splat_one,
                v_splat_one / v_samp_coeff_sum,
            );
            inline for (0..CH) |ch| {
                samp_res[ch] *= v_inv_w_sum;
            }
            return samp_res;
        },
        .lanczos3, .quintic_bspline => {
            const TAP = 6;
            const tap_offset = @divTrunc(@as(isize, @intCast(TAP)), 2) - 1;

            var v_samp_coeff_x: [TAP]VecSF = undefined;
            var v_samp_coeff_y: [TAP]VecSF = undefined;

            const tex_x_frac_arr: [S]f64 = v_tex_x_frac;
            const tex_y_frac_arr: [S]f64 = v_tex_y_frac;

            const lut = switch (config.sample) {
                .lanczos3 => lanczos3_lut,
                .quintic_bspline => quintic_bspline_lut,
                else => unreachable,
            };

            switch (config.mode) {
                .direct => {
                    const v_kernel: *const fn (VecSF) VecSF = switch (config.sample) {
                        .lanczos3 => v_lanczos3CoeffSIMD,
                        .quintic_bspline => v_quinticBSplineCoeffSIMD,
                        else => unreachable,
                    };
                    v_samp_coeff_x[0] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(2.0)));
                    v_samp_coeff_x[1] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[2] = v_kernel(v_tex_x_frac);
                    v_samp_coeff_x[3] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[4] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(2.0)));
                    v_samp_coeff_x[5] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(3.0)));

                    v_samp_coeff_y[0] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(2.0)));
                    v_samp_coeff_y[1] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[2] = v_kernel(v_tex_y_frac);
                    v_samp_coeff_y[3] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[4] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(2.0)));
                    v_samp_coeff_y[5] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(3.0)));
                },
                .lut => {
                    var samp_coeff_x_arr: [6][S]f64 = undefined;
                    var samp_coeff_y_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tex_x_frac_arr[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            tex_y_frac_arr[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        inline for (0..6) |kk| {
                            samp_coeff_x_arr[kk][ii] = lut[ix][kk];
                            samp_coeff_y_arr[kk][ii] = lut[iy][kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
                .lut_lerp => {
                    var samp_coeff_x_arr: [6][S]f64 = undefined;
                    var samp_coeff_y_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
                        const samp_coeff_x = getLerpSampCoeffs(
                            6,
                            lut,
                            tex_x_frac_arr[ii],
                        );
                        const samp_coeff_y = getLerpSampCoeffs(
                            6,
                            lut,
                            tex_y_frac_arr[ii],
                        );
                        inline for (0..6) |kk| {
                            samp_coeff_x_arr[kk][ii] = samp_coeff_x[kk];
                            samp_coeff_y_arr[kk][ii] = samp_coeff_y[kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
            }

            var samp_res: [CH]VecSF = [_]VecSF{@splat(0.0)} ** CH;
            var v_samp_coeff_sum: VecSF = @splat(0.0);

            var v_tap_samp_coeff_planes: [TAP * TAP]VecSF = undefined;
            inline for (0..TAP) |jj| {
                const v_samp_coeff_y_val = v_samp_coeff_y[jj];
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_samp_coeff_x[ii] * v_samp_coeff_y_val;
                    v_tap_samp_coeff_planes[jj * TAP + ii] = v_tap_samp_coeff;
                    v_samp_coeff_sum += v_tap_samp_coeff;
                }
            }

            inline for (0..TAP) |jj| {
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_tap_samp_coeff_planes[jj * TAP + ii];
                    const v_px_vecs = v_getPxSIMD(
                        CH,
                        texture,
                        v_tex_x_i + @as(
                            VecSI,
                            @splat(@as(isize, @intCast(ii)) - tap_offset),
                        ),
                        v_tex_y_i + @as(
                            VecSI,
                            @splat(@as(isize, @intCast(jj)) - tap_offset),
                        ),
                    );

                    inline for (0..CH) |ch| {
                        samp_res[ch] += v_px_vecs[ch] * v_tap_samp_coeff;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_samp_coeff_sum) < @as(
                    VecSF,
                    @splat(tol.texture.samp_coeff_sum),
                ),
                v_splat_one,
                v_splat_one / v_samp_coeff_sum,
            );
            inline for (0..CH) |ch| {
                samp_res[ch] *= v_inv_w_sum;
            }
            return samp_res;
        },
    };
}

pub fn samplePerPixelInnerSIMD(
    comptime CH: usize,
    comptime config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

    const xf = u * tex_cols_minus_1_f;
    const yf = v * tex_rows_minus_1_f;

    const tex_x_i = @as(isize, @intFromFloat(@floor(xf)));
    const tex_y_i = @as(isize, @intFromFloat(@floor(yf)));

    const tex_x_frac = xf - @as(f64, @floatFromInt(tex_x_i));
    const tex_y_frac = yf - @as(f64, @floatFromInt(tex_y_i));

    return switch (config.sample) {
        .nearest => getPx(
            CH,
            texture,
            @as(isize, @intFromFloat(@round(xf))),
            @as(isize, @intFromFloat(@round(yf))),
        ),
        .linear => {
            const samp_coeff_x = [2]f64{ 1.0 - tex_x_frac, tex_x_frac };
            const samp_coeff_y = [2]f64{ 1.0 - tex_y_frac, tex_y_frac };
            return sample2DInnerSIMD(
                CH,
                2,
                texture,
                tex_x_i,
                tex_y_i,
                samp_coeff_x,
                samp_coeff_y,
            );
        },
        .cubic_catmull_rom, .cubic_mitchell_netravali, .cubic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .cubic_catmull_rom => cubicCoeffCatmullRom,
                .cubic_mitchell_netravali => cubicCoeffMitchellNetravali,
                .cubic_bspline => cubicBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .cubic_catmull_rom => catmull_rom_lut,
                .cubic_mitchell_netravali => mitchell_netravali_lut,
                .cubic_bspline => cubic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2DInnerSIMD(
                    CH,
                    4,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                    },
                    .{
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                    },
                ),
                .lut => {
                    const idx_tex_x_frac = @as(usize, @intFromFloat(
                        tex_x_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    const idx_tex_y_frac = @as(usize, @intFromFloat(
                        tex_y_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    return sample2DInnerSIMD(
                        CH,
                        4,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        lut[idx_tex_x_frac],
                        lut[idx_tex_y_frac],
                    );
                },
                .lut_lerp => {
                    const samp_coeff_x = getLerpSampCoeffs(4, lut, tex_x_frac);
                    const samp_coeff_y = getLerpSampCoeffs(4, lut, tex_y_frac);
                    return sample2DInnerSIMD(
                        CH,
                        4,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        samp_coeff_x,
                        samp_coeff_y,
                    );
                },
            };
        },
        .lanczos3, .quintic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .lanczos3 => lanczos3Coeff,
                .quintic_bspline => quinticBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .lanczos3 => lanczos3_lut,
                .quintic_bspline => quintic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2DInnerSIMD(
                    CH,
                    6,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 2),
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                        coeff_fun(tex_x_frac - 3),
                    },
                    .{
                        coeff_fun(tex_y_frac + 2),
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                        coeff_fun(tex_y_frac - 3),
                    },
                ),
                .lut => {
                    const idx_tex_x_frac = @as(usize, @intFromFloat(
                        tex_x_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    const idx_tex_y_frac = @as(usize, @intFromFloat(
                        tex_y_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    return sample2DInnerSIMD(
                        CH,
                        6,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        lut[idx_tex_x_frac],
                        lut[idx_tex_y_frac],
                    );
                },
                .lut_lerp => {
                    const samp_coeff_x = getLerpSampCoeffs(6, lut, tex_x_frac);
                    const samp_coeff_y = getLerpSampCoeffs(6, lut, tex_y_frac);
                    return sample2DInnerSIMD(
                        CH,
                        6,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        samp_coeff_x,
                        samp_coeff_y,
                    );
                },
            };
        },
    };
}

pub fn samplePerLaneInnerSIMD(
    comptime CH: usize,
    comptime config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    var samp_res_arr: [CH][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** CH;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    for (0..S) |ii| {
        if (mask_arr[ii]) {
            const sampled = samplePerPixelInnerSIMD(
                CH,
                config,
                texture,
                u_arr[ii],
                v_arr[ii],
            );
            inline for (0..CH) |ch| {
                samp_res_arr[ch][ii] = sampled[ch];
            }
        }
    }

    var samp_res: [CH]VecSF = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = samp_res_arr[ch];
    }

    return samp_res;
}

pub fn samplePerLaneTri3SIMD(
    comptime CH: usize,
    comptime config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    var samp_res_arr: [CH][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** CH;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    var active_lanes: [S]usize = undefined;
    var active_count: usize = 0;

    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );
    const tex_cols_minus_1_i = @as(isize, @intCast(texture.cols_num)) - 1;
    const tex_rows_minus_1_i = @as(isize, @intCast(texture.rows_num)) - 1;

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
            const xf = u_arr[lane] * tex_cols_minus_1_f;
            const yf = v_arr[lane] * tex_rows_minus_1_f;
            const tex_x_i = @as(isize, @intFromFloat(@floor(xf)));
            const tex_y_i = @as(isize, @intFromFloat(@floor(yf)));
            const x_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(tex_x_i, tex_cols_minus_1_i))),
            );
            const y_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(tex_y_i, tex_rows_minus_1_i))),
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
            CH,
            config,
            texture,
            u_arr[lane],
            v_arr[lane],
        );
        inline for (0..CH) |ch| {
            samp_res_arr[ch][lane] = sampled[ch];
        }
    }

    var samp_res: [CH]VecSF = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = samp_res_arr[ch];
    }

    return samp_res;
}

fn sampleOverPixelsSIMDRuntimeImpl(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    std.debug.assert(config.isValid());
    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

    const v_tex_x_f = v_u * @as(VecSF, @splat(tex_cols_minus_1_f));
    const v_tex_y_f = v_v * @as(VecSF, @splat(tex_rows_minus_1_f));

    var v_tex_x_i_arr: [S]isize = undefined;
    var v_tex_y_i_arr: [S]isize = undefined;
    const tex_x_f_arr: [S]f64 = v_tex_x_f;
    const tex_y_f_arr: [S]f64 = v_tex_y_f;

    for (0..S) |ii| {
        v_tex_x_i_arr[ii] = @as(isize, @intFromFloat(@floor(tex_x_f_arr[ii])));
        v_tex_y_i_arr[ii] = @as(isize, @intFromFloat(@floor(tex_y_f_arr[ii])));
    }

    const v_tex_x_i: VecSI = v_tex_x_i_arr;
    const v_tex_y_i: VecSI = v_tex_y_i_arr;
    const v_tex_x_frac = v_tex_x_f - @as(VecSF, @floatFromInt(v_tex_x_i));
    const v_tex_y_frac = v_tex_y_f - @as(VecSF, @floatFromInt(v_tex_y_i));

    return switch (config.sample) {
        .nearest => v_getPxSIMD(
            CH,
            texture,
            @as(VecSI, @intFromFloat(@round(v_tex_x_f))),
            @as(VecSI, @intFromFloat(@round(v_tex_y_f))),
        ),
        .linear => {
            const v_p00 = v_getPxSIMD(CH, texture, v_tex_x_i, v_tex_y_i);
            const v_p10 = v_getPxSIMD(CH, texture, v_tex_x_i + @as(VecSI, @splat(1)), v_tex_y_i);
            const v_p01 = v_getPxSIMD(CH, texture, v_tex_x_i, v_tex_y_i + @as(VecSI, @splat(1)));
            const v_p11 = v_getPxSIMD(
                CH,
                texture,
                v_tex_x_i + @as(VecSI, @splat(1)),
                v_tex_y_i + @as(VecSI, @splat(1)),
            );

            var samp_res: [CH]VecSF = undefined;
            const v_splat_one: VecSF = @splat(1.0);
            inline for (0..CH) |ch| {
                samp_res[ch] = (v_splat_one - v_tex_x_frac) * (v_splat_one - v_tex_y_frac) *
                    v_p00[ch] +
                    v_tex_x_frac * (v_splat_one - v_tex_y_frac) * v_p10[ch] +
                    (v_splat_one - v_tex_x_frac) * v_tex_y_frac * v_p01[ch] +
                    v_tex_x_frac * v_tex_y_frac * v_p11[ch];
            }
            return samp_res;
        },
        .cubic_catmull_rom, .cubic_mitchell_netravali, .cubic_bspline => {
            const TAP = 4;
            const tap_offset = @divTrunc(@as(isize, @intCast(TAP)), 2) - 1;

            var v_samp_coeff_x: [TAP]VecSF = undefined;
            var v_samp_coeff_y: [TAP]VecSF = undefined;

            const tex_x_frac_arr2: [S]f64 = v_tex_x_frac;
            const tex_y_frac_arr2: [S]f64 = v_tex_y_frac;

            const lut = switch (config.sample) {
                .cubic_catmull_rom => catmull_rom_lut,
                .cubic_mitchell_netravali => mitchell_netravali_lut,
                .cubic_bspline => cubic_bspline_lut,
                else => unreachable,
            };

            switch (config.mode) {
                .direct => {
                    const v_kernel: *const fn (VecSF) VecSF = switch (config.sample) {
                        .cubic_catmull_rom => v_cubicCoeffCatmullRomSIMD,
                        .cubic_mitchell_netravali => v_cubicCoeffMitchellNetravaliSIMD,
                        .cubic_bspline => v_cubicBSplineCoeffSIMD,
                        else => unreachable,
                    };
                    v_samp_coeff_x[0] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[1] = v_kernel(v_tex_x_frac);
                    v_samp_coeff_x[2] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[3] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(2.0)));

                    v_samp_coeff_y[0] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[1] = v_kernel(v_tex_y_frac);
                    v_samp_coeff_y[2] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[3] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(2.0)));
                },
                .lut => {
                    var samp_coeff_x_arr: [4][S]f64 = undefined;
                    var samp_coeff_y_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tex_x_frac_arr2[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            tex_y_frac_arr2[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        inline for (0..4) |kk| {
                            samp_coeff_x_arr[kk][ii] = lut[ix][kk];
                            samp_coeff_y_arr[kk][ii] = lut[iy][kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
                .lut_lerp => {
                    var samp_coeff_x_arr: [4][S]f64 = undefined;
                    var samp_coeff_y_arr: [4][S]f64 = undefined;
                    for (0..S) |ii| {
                        const sx = getLerpSampCoeffsRuntime(4, lut, tex_x_frac_arr2[ii]);
                        const sy = getLerpSampCoeffsRuntime(4, lut, tex_y_frac_arr2[ii]);
                        inline for (0..4) |kk| {
                            samp_coeff_x_arr[kk][ii] = sx[kk];
                            samp_coeff_y_arr[kk][ii] = sy[kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
            }

            var samp_res: [CH]VecSF = [_]VecSF{@splat(0.0)} ** CH;
            var v_samp_coeff_sum: VecSF = @splat(0.0);

            var v_tap_samp_coeff_planes: [TAP * TAP]VecSF = undefined;
            inline for (0..TAP) |jj| {
                const v_samp_coeff_y_val = v_samp_coeff_y[jj];
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_samp_coeff_x[ii] * v_samp_coeff_y_val;
                    v_tap_samp_coeff_planes[jj * TAP + ii] = v_tap_samp_coeff;
                    v_samp_coeff_sum += v_tap_samp_coeff;
                }
            }

            inline for (0..TAP) |jj| {
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_tap_samp_coeff_planes[jj * TAP + ii];
                    const v_px_vecs = v_getPxSIMD(
                        CH,
                        texture,
                        v_tex_x_i + @as(VecSI, @splat(@as(isize, @intCast(ii)) - tap_offset)),
                        v_tex_y_i + @as(VecSI, @splat(@as(isize, @intCast(jj)) - tap_offset)),
                    );
                    inline for (0..CH) |ch| {
                        samp_res[ch] += v_px_vecs[ch] * v_tap_samp_coeff;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_samp_coeff_sum) < @as(VecSF, @splat(tol.texture.samp_coeff_sum)),
                v_splat_one,
                v_splat_one / v_samp_coeff_sum,
            );
            inline for (0..CH) |ch| {
                samp_res[ch] *= v_inv_w_sum;
            }
            return samp_res;
        },
        .lanczos3, .quintic_bspline => {
            const TAP = 6;
            const tap_offset = @divTrunc(@as(isize, @intCast(TAP)), 2) - 1;

            var v_samp_coeff_x: [TAP]VecSF = undefined;
            var v_samp_coeff_y: [TAP]VecSF = undefined;

            const tex_x_frac_arr2: [S]f64 = v_tex_x_frac;
            const tex_y_frac_arr2: [S]f64 = v_tex_y_frac;

            const lut = switch (config.sample) {
                .lanczos3 => lanczos3_lut,
                .quintic_bspline => quintic_bspline_lut,
                else => unreachable,
            };

            switch (config.mode) {
                .direct => {
                    const v_kernel: *const fn (VecSF) VecSF = switch (config.sample) {
                        .lanczos3 => v_lanczos3CoeffSIMD,
                        .quintic_bspline => v_quinticBSplineCoeffSIMD,
                        else => unreachable,
                    };
                    v_samp_coeff_x[0] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(2.0)));
                    v_samp_coeff_x[1] = v_kernel(v_tex_x_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[2] = v_kernel(v_tex_x_frac);
                    v_samp_coeff_x[3] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_x[4] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(2.0)));
                    v_samp_coeff_x[5] = v_kernel(v_tex_x_frac - @as(VecSF, @splat(3.0)));

                    v_samp_coeff_y[0] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(2.0)));
                    v_samp_coeff_y[1] = v_kernel(v_tex_y_frac + @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[2] = v_kernel(v_tex_y_frac);
                    v_samp_coeff_y[3] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(1.0)));
                    v_samp_coeff_y[4] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(2.0)));
                    v_samp_coeff_y[5] = v_kernel(v_tex_y_frac - @as(VecSF, @splat(3.0)));
                },
                .lut => {
                    var samp_coeff_x_arr: [6][S]f64 = undefined;
                    var samp_coeff_y_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
                        const ix = @as(usize, @intFromFloat(
                            tex_x_frac_arr2[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        const iy = @as(usize, @intFromFloat(
                            tex_y_frac_arr2[ii] * @as(f64, @floatFromInt(lut_size - 1)),
                        ));
                        inline for (0..6) |kk| {
                            samp_coeff_x_arr[kk][ii] = lut[ix][kk];
                            samp_coeff_y_arr[kk][ii] = lut[iy][kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
                .lut_lerp => {
                    var samp_coeff_x_arr: [6][S]f64 = undefined;
                    var samp_coeff_y_arr: [6][S]f64 = undefined;
                    for (0..S) |ii| {
                        const sx = getLerpSampCoeffsRuntime(6, lut, tex_x_frac_arr2[ii]);
                        const sy = getLerpSampCoeffsRuntime(6, lut, tex_y_frac_arr2[ii]);
                        inline for (0..6) |kk| {
                            samp_coeff_x_arr[kk][ii] = sx[kk];
                            samp_coeff_y_arr[kk][ii] = sy[kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_samp_coeff_x[kk] = samp_coeff_x_arr[kk];
                        v_samp_coeff_y[kk] = samp_coeff_y_arr[kk];
                    }
                },
            }

            var samp_res: [CH]VecSF = [_]VecSF{@splat(0.0)} ** CH;
            var v_samp_coeff_sum: VecSF = @splat(0.0);

            var v_tap_samp_coeff_planes: [TAP * TAP]VecSF = undefined;
            inline for (0..TAP) |jj| {
                const v_samp_coeff_y_val = v_samp_coeff_y[jj];
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_samp_coeff_x[ii] * v_samp_coeff_y_val;
                    v_tap_samp_coeff_planes[jj * TAP + ii] = v_tap_samp_coeff;
                    v_samp_coeff_sum += v_tap_samp_coeff;
                }
            }

            inline for (0..TAP) |jj| {
                inline for (0..TAP) |ii| {
                    const v_tap_samp_coeff = v_tap_samp_coeff_planes[jj * TAP + ii];
                    const v_px_vecs = v_getPxSIMD(
                        CH,
                        texture,
                        v_tex_x_i + @as(VecSI, @splat(@as(isize, @intCast(ii)) - tap_offset)),
                        v_tex_y_i + @as(VecSI, @splat(@as(isize, @intCast(jj)) - tap_offset)),
                    );
                    inline for (0..CH) |ch| {
                        samp_res[ch] += v_px_vecs[ch] * v_tap_samp_coeff;
                    }
                }
            }

            const v_splat_one: VecSF = @splat(1.0);
            const v_inv_w_sum = @select(
                f64,
                @abs(v_samp_coeff_sum) < @as(VecSF, @splat(tol.texture.samp_coeff_sum)),
                v_splat_one,
                v_splat_one / v_samp_coeff_sum,
            );
            inline for (0..CH) |ch| {
                samp_res[ch] *= v_inv_w_sum;
            }
            return samp_res;
        },
    };
}

fn samplePerPixelInnerSIMDRuntimeImpl(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
    std.debug.assert(config.isValid());

    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );

    const xf = u * tex_cols_minus_1_f;
    const yf = v * tex_rows_minus_1_f;

    const tex_x_i = @as(isize, @intFromFloat(@floor(xf)));
    const tex_y_i = @as(isize, @intFromFloat(@floor(yf)));

    const tex_x_frac = xf - @as(f64, @floatFromInt(tex_x_i));
    const tex_y_frac = yf - @as(f64, @floatFromInt(tex_y_i));

    return switch (config.sample) {
        .nearest => getPx(
            CH,
            texture,
            @as(isize, @intFromFloat(@round(xf))),
            @as(isize, @intFromFloat(@round(yf))),
        ),
        .linear => {
            const samp_coeff_x = [2]f64{ 1.0 - tex_x_frac, tex_x_frac };
            const samp_coeff_y = [2]f64{ 1.0 - tex_y_frac, tex_y_frac };
            return sample2DInnerSIMD(
                CH,
                2,
                texture,
                tex_x_i,
                tex_y_i,
                samp_coeff_x,
                samp_coeff_y,
            );
        },
        .cubic_catmull_rom, .cubic_mitchell_netravali, .cubic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .cubic_catmull_rom => cubicCoeffCatmullRom,
                .cubic_mitchell_netravali => cubicCoeffMitchellNetravali,
                .cubic_bspline => cubicBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .cubic_catmull_rom => catmull_rom_lut,
                .cubic_mitchell_netravali => mitchell_netravali_lut,
                .cubic_bspline => cubic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2DInnerSIMD(
                    CH,
                    4,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                    },
                    .{
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                    },
                ),
                .lut => {
                    const ix = @as(usize, @intFromFloat(
                        tex_x_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    const iy = @as(usize, @intFromFloat(
                        tex_y_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    return sample2DInnerSIMD(
                        CH,
                        4,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        lut[ix],
                        lut[iy],
                    );
                },
                .lut_lerp => {
                    const sx = getLerpSampCoeffsRuntime(4, lut, tex_x_frac);
                    const sy = getLerpSampCoeffsRuntime(4, lut, tex_y_frac);
                    return sample2DInnerSIMD(
                        CH,
                        4,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        sx,
                        sy,
                    );
                },
            };
        },
        .lanczos3, .quintic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .lanczos3 => lanczos3Coeff,
                .quintic_bspline => quinticBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .lanczos3 => lanczos3_lut,
                .quintic_bspline => quintic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2DInnerSIMD(
                    CH,
                    6,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 2),
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                        coeff_fun(tex_x_frac - 3),
                    },
                    .{
                        coeff_fun(tex_y_frac + 2),
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                        coeff_fun(tex_y_frac - 3),
                    },
                ),
                .lut => {
                    const ix = @as(usize, @intFromFloat(
                        tex_x_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    const iy = @as(usize, @intFromFloat(
                        tex_y_frac * @as(f64, @floatFromInt(lut_size - 1)),
                    ));
                    return sample2DInnerSIMD(
                        CH,
                        6,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        lut[ix],
                        lut[iy],
                    );
                },
                .lut_lerp => {
                    const sx = getLerpSampCoeffsRuntime(6, lut, tex_x_frac);
                    const sy = getLerpSampCoeffsRuntime(6, lut, tex_y_frac);
                    return sample2DInnerSIMD(
                        CH,
                        6,
                        texture,
                        tex_x_i,
                        tex_y_i,
                        sx,
                        sy,
                    );
                },
            };
        },
    };
}

fn samplePerLaneInnerSIMDRuntimeImpl(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    var samp_res_arr: [CH][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** CH;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    for (0..S) |ii| {
        if (mask_arr[ii]) {
            const sampled = samplePerPixelInnerSIMDRuntimeImpl(
                CH,
                config,
                texture,
                u_arr[ii],
                v_arr[ii],
            );
            inline for (0..CH) |ch| {
                samp_res_arr[ch][ii] = sampled[ch];
            }
        }
    }

    var samp_res: [CH]VecSF = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = samp_res_arr[ch];
    }

    return samp_res;
}

fn samplePerLaneTri3SIMDRuntimeImpl(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    var samp_res_arr: [CH][S]f64 = [_][S]f64{[_]f64{0.0} ** S} ** CH;
    const mask_arr: [S]bool = v_mask_active;
    const u_arr: [S]f64 = v_u;
    const v_arr: [S]f64 = v_v;

    var active_lanes: [S]usize = undefined;
    var active_count: usize = 0;

    const tex_cols_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1),
    );
    const tex_rows_minus_1_f = @as(
        f64,
        @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1),
    );
    const tex_cols_minus_1_i = @as(isize, @intCast(texture.cols_num)) - 1;
    const tex_rows_minus_1_i = @as(isize, @intCast(texture.rows_num)) - 1;

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
            const xf = u_arr[lane] * tex_cols_minus_1_f;
            const yf = v_arr[lane] * tex_rows_minus_1_f;
            const tex_x_i = @as(isize, @intFromFloat(@floor(xf)));
            const tex_y_i = @as(isize, @intFromFloat(@floor(yf)));
            const x_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(tex_x_i, tex_cols_minus_1_i))),
            );
            const y_key = @as(
                usize,
                @intCast(@max(@as(isize, 0), @min(tex_y_i, tex_rows_minus_1_i))),
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
        const sampled = samplePerPixelInnerSIMDRuntimeImpl(
            CH,
            config,
            texture,
            u_arr[lane],
            v_arr[lane],
        );
        inline for (0..CH) |ch| {
            samp_res_arr[ch][lane] = sampled[ch];
        }
    }

    var samp_res: [CH]VecSF = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = samp_res_arr[ch];
    }

    return samp_res;
}

fn sampleOverPixelsSIMDDispatch(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    std.debug.assert(config.isValid());

    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => sampleOverPixelsSIMDRuntimeImpl(CH, config, texture, v_u, v_v),
        .runtime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk sampleOverPixelsSIMD(
                            CH,
                            comptime_config,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
        .comptime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk sampleOverPixelsSIMD(
                            CH,
                            comptime_config,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
    };
}

fn samplePerPixelInnerSIMDDispatch(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
    std.debug.assert(config.isValid());

    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => samplePerPixelInnerSIMDRuntimeImpl(CH, config, texture, u, v),
        .runtime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerPixelInnerSIMD(
                            CH,
                            comptime_config,
                            texture,
                            u,
                            v,
                        );
                    }
                    unreachable;
                },
            },
        },
        .comptime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerPixelInnerSIMD(
                            CH,
                            comptime_config,
                            texture,
                            u,
                            v,
                        );
                    }
                    unreachable;
                },
            },
        },
    };
}

fn samplePerLaneInnerSIMDDispatch(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    std.debug.assert(config.isValid());

    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => samplePerLaneInnerSIMDRuntimeImpl(
            CH,
            config,
            v_mask_active,
            texture,
            v_u,
            v_v,
        ),
        .runtime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerLaneInnerSIMD(
                            CH,
                            comptime_config,
                            v_mask_active,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
        .comptime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerLaneInnerSIMD(
                            CH,
                            comptime_config,
                            v_mask_active,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
    };
}

fn samplePerLaneTri3SIMDDispatch(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    std.debug.assert(config.isValid());

    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => samplePerLaneTri3SIMDRuntimeImpl(
            CH,
            config,
            v_mask_active,
            texture,
            v_u,
            v_v,
        ),
        .runtime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerLaneTri3SIMD(
                            CH,
                            comptime_config,
                            v_mask_active,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
        .comptime_comptime => switch (config.sample) {
            inline else => |sample_type| switch (config.mode) {
                inline else => |mode_type| blk: {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample_type,
                        .mode = mode_type,
                    };
                    if (comptime comptime_config.isValid()) {
                        break :blk samplePerLaneTri3SIMD(
                            CH,
                            comptime_config,
                            v_mask_active,
                            texture,
                            v_u,
                            v_v,
                        );
                    }
                    unreachable;
                },
            },
        },
    };
}

pub fn sampleOverPixelsSIMDRuntime(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    return sampleOverPixelsSIMDDispatch(CH, config, texture, v_u, v_v);
}

pub fn samplePerPixelInnerSIMDRuntime(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
    return samplePerPixelInnerSIMDDispatch(CH, config, texture, u, v);
}

pub fn samplePerLaneInnerSIMDRuntime(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    return samplePerLaneInnerSIMDDispatch(CH, config, v_mask_active, texture, v_u, v_v);
}

pub fn samplePerLaneTri3SIMDRuntime(
    comptime CH: usize,
    config: TextureSampleConfig,
    v_mask_active: VecSB,
    texture: anytype,
    v_u: VecSF,
    v_v: VecSF,
) [CH]VecSF {
    return samplePerLaneTri3SIMDDispatch(CH, config, v_mask_active, texture, v_u, v_v);
}
