// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rops = @import("rasterops.zig");
const cam = @import("camera.zig");
const common = @import("scratchfilter_common.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

const cfg = buildconfig.config;
const SimdWidth = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const ScratchLayout = common.ScratchLayout;
const ScratchTileGeometry = common.ScratchTileGeometry;
const MatSlice = common.MatSlice;
const NDArray = common.NDArray;
const FrameImageWriter = common.FrameImageWriter;
const setScratchField = common.setScratchField;
const sampleScratchOrBackground = common.sampleScratchOrBackground;

pub inline fn loadScratchRowSIMD(
    comptime scratch_layout: ScratchLayout,
    src: *const MatSlice(F),
    x: isize,
    y: isize,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    field_idx: usize,
    background_value: F,
) VecSF {
    const cols_num = src.cols_num;
    if (y < 0 or y >= @as(isize, @intCast(scratch_geom.scratch_h_subpx))) {
        return @as(VecSF, @splat(background_value));
    }
    const uy = @as(usize, @intCast(y));

    const chunk_in_bounds = (x >= 0 and
        x + @as(isize, @intCast(SimdWidth)) <=
            @as(isize, @intCast(scratch_geom.scratch_w_subpx)));

    if (chunk_in_bounds) {
        const ux = @as(usize, @intCast(x));
        const flat_idx = uy * spx_stride + ux;
        if (scratch_layout == .field_major) {
            const offset = field_idx * cols_num + flat_idx;
            return @as(*const [SimdWidth]F, @ptrCast(&src.slice[offset])).*;
        }
    }

    var result: [SimdWidth]F = undefined;
    var ii: usize = 0;
    while (ii < SimdWidth) : (ii += 1) {
        result[ii] = sampleScratchOrBackground(
            scratch_layout,
            src,
            x + @as(isize, @intCast(ii)),
            y,
            scratch_geom,
            spx_stride,
            field_idx,
            background_value,
        );
    }
    return result;
}

pub inline fn storeScratchRowSIMD(
    comptime scratch_layout: ScratchLayout,
    dst: *MatSlice(F),
    x: usize,
    y: usize,
    spx_stride: usize,
    field_idx: usize,
    val_vec: VecSF,
) void {
    const cols_num = dst.cols_num;
    const flat_idx = y * spx_stride + x;
    if (scratch_layout == .field_major) {
        const offset = field_idx * cols_num + flat_idx;
        @as(*[SimdWidth]F, @ptrCast(&dst.slice[offset])).* = val_vec;
    } else {
        var ii: usize = 0;
        while (ii < SimdWidth) : (ii += 1) {
            setScratchField(
                scratch_layout,
                dst,
                flat_idx + ii,
                field_idx,
                val_vec[ii],
            );
        }
    }
}

pub fn averageScratchCoreSIMD(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    radius_x: usize,
    radius_y: usize,
    image_out_arr: *NDArray(F),
) void {
    const cols_num = spx_image_scratch.cols_num;
    const sub_samp_f = @as(F, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    const writer = FrameImageWriter.init(image_out_arr);

    var ii: usize = 0;
    while (ii < scratch_geom.core_h_px) : (ii += 1) {
        const image_px_y = tile.y_px_min + ii;
        const spx_start_y = scratch_geom.core_start_y_subpx + sub_samp * ii;

        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;

        const start_y = if (spx_start_y >= radius_y)
            spx_start_y - radius_y
        else
            0;
        const end_y = @min(
            scratch_geom.scratch_h_subpx - 1,
            spx_start_y + sub_samp - 1 + radius_y,
        );

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) {
            continue;
        }

        const active_subpx_min = if (min_x >= radius_x)
            min_x - radius_x
        else
            0;
        const active_subpx_max = max_x + radius_x;

        var tx_start: usize = 0;
        if (active_subpx_min > scratch_geom.core_start_x_subpx) {
            tx_start = (active_subpx_min - scratch_geom.core_start_x_subpx) /
                sub_samp;
        }
        var tx_end: usize = scratch_geom.core_w_px - 1;
        if (active_subpx_max >= scratch_geom.core_start_x_subpx) {
            const calculated_end =
                (active_subpx_max - scratch_geom.core_start_x_subpx) / sub_samp;
            if (calculated_end < tx_end) {
                tx_end = calculated_end;
            }
        } else {
            continue;
        }

        var jj = tx_start;
        while (jj <= tx_end) : (jj += 1) {
            const image_px_x = tile.x_px_min + jj;
            const spx_start_x = scratch_geom.core_start_x_subpx + sub_samp * jj;
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            var ff: usize = 0;
            while (ff < @as(usize, fields_num)) : (ff += 1) {
                var field_sum: F = 0.0;

                if (sub_samp == 8 and SimdWidth == 8) {
                    var sum_vec = @as(VecSF, @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 8) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) *
                            spx_stride;
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [8]F,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else if (sub_samp == 4) {
                    var sum_vec = @as(@Vector(4, F), @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 4) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) *
                            spx_stride;
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [4]F,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else if (sub_samp == 2) {
                    var sum_vec = @as(@Vector(2, F), @splat(0.0));
                    var row_idx: usize = 0;
                    while (row_idx < 2) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) *
                            spx_stride;
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x;
                        const offset = ff * cols_num + scratch_flat_idx;
                        const ptr = @as(
                            *const [2]F,
                            @ptrCast(&spx_image_scratch.slice[offset]),
                        );
                        sum_vec += ptr.*;
                    }
                    field_sum = @reduce(.Add, sum_vec);
                } else {
                    var row_idx: usize = 0;
                    while (row_idx < sub_samp) : (row_idx += 1) {
                        const scratch_row_offset = (spx_start_y + row_idx) *
                            spx_stride;
                        var col_idx: usize = 0;
                        while (col_idx < sub_samp) {
                            if (col_idx + SimdWidth <= sub_samp) {
                                const scratch_flat_idx = scratch_row_offset +
                                    spx_start_x + col_idx;
                                const offset = ff * cols_num + scratch_flat_idx;
                                const val_vec = @as(
                                    VecSF,
                                    @as(
                                        *const [SimdWidth]F,
                                        @ptrCast(
                                            &spx_image_scratch.slice[offset],
                                        ),
                                    ).*,
                                );
                                field_sum += @reduce(.Add, val_vec);
                                col_idx += SimdWidth;
                            } else {
                                field_sum += sampleScratchOrBackground(
                                    scratch_layout,
                                    spx_image_scratch,
                                    @as(isize, @intCast(spx_start_x + col_idx)),
                                    @as(isize, @intCast(spx_start_y + row_idx)),
                                    scratch_geom,
                                    spx_stride,
                                    ff,
                                    0.0,
                                );
                                col_idx += 1;
                            }
                        }
                    }
                }
                writer.slice[ff * writer.field_stride + image_px_base] =
                    field_sum * inv_sub_samp_sq;
            }
        }
    }
}

pub fn filterScratchSeparableSIMD(
    comptime scratch_layout: ScratchLayout,
    fields_num: u8,
    background_value: F,
    psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    src: *const MatSlice(F),
    tmp: *MatSlice(F),
    dst: *MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
) void {
    tmp.fill(background_value);

    const radius_x = psf.radius_x_subpx;
    const radius_y = psf.radius_y_subpx;

    // Horizontal pass
    var yy: usize = 0;
    while (yy < scratch_geom.scratch_h_subpx) : (yy += 1) {
        const min_x = touched_min_x[yy];
        const max_x = touched_max_x[yy];
        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            var xx = xx_start;
            while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                var sum_h_vec = @as(VecSF, @splat(0.0));
                var kk: usize = 0;
                while (kk < psf.weights_x.len) : (kk += 1) {
                    const x_off = @as(
                        isize,
                        @intCast(kk),
                    ) - @as(isize, @intCast(radius_x));
                    const input_vec = loadScratchRowSIMD(
                        scratch_layout,
                        src,
                        @as(isize, @intCast(xx)) + x_off,
                        @as(isize, @intCast(yy)),
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                    sum_h_vec += input_vec * @as(
                        VecSF,
                        @splat(psf.weights_x[kk]),
                    );
                }
                storeScratchRowSIMD(
                    scratch_layout,
                    tmp,
                    xx,
                    yy,
                    spx_stride,
                    ff,
                    sum_h_vec,
                );
            }

            // Scalar tail
            while (xx <= xx_end) : (xx += 1) {
                var sum_h: F = 0.0;
                var kk: usize = 0;
                while (kk < psf.weights_x.len) : (kk += 1) {
                    const x_off = @as(
                        isize,
                        @intCast(kk),
                    ) - @as(isize, @intCast(radius_x));
                    sum_h += psf.weights_x[kk] * sampleScratchOrBackground(
                        scratch_layout,
                        src,
                        @as(isize, @intCast(xx)) + x_off,
                        @as(isize, @intCast(yy)),
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                }
                setScratchField(
                    scratch_layout,
                    tmp,
                    yy * spx_stride + xx,
                    ff,
                    sum_h,
                );
            }
        }
    }

    // Vertical pass
    dst.fill(background_value);
    yy = scratch_geom.core_start_y_subpx;
    const core_end_y = scratch_geom.core_start_y_subpx +
        scratch_geom.core_h_px * sub_samp - 1;
    while (yy <= core_end_y) : (yy += 1) {
        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;
        const start_y = if (yy >= radius_y) yy - radius_y else 0;
        const end_y = @min(scratch_geom.scratch_h_subpx - 1, yy + radius_y);

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            var xx = xx_start;
            while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                var sum_v_vec = @as(VecSF, @splat(0.0));
                var kk: usize = 0;
                while (kk < psf.weights_y.len) : (kk += 1) {
                    const y_off = @as(
                        isize,
                        @intCast(kk),
                    ) - @as(isize, @intCast(radius_y));
                    const input_vec = loadScratchRowSIMD(
                        scratch_layout,
                        tmp,
                        @as(isize, @intCast(xx)),
                        @as(isize, @intCast(yy)) + y_off,
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                    sum_v_vec += input_vec * @as(
                        VecSF,
                        @splat(psf.weights_y[kk]),
                    );
                }
                storeScratchRowSIMD(
                    scratch_layout,
                    dst,
                    xx,
                    yy,
                    spx_stride,
                    ff,
                    sum_v_vec,
                );
            }

            // Scalar tail
            while (xx <= xx_end) : (xx += 1) {
                var sum_v: F = 0.0;
                var kk: usize = 0;
                while (kk < psf.weights_y.len) : (kk += 1) {
                    const y_off = @as(
                        isize,
                        @intCast(kk),
                    ) - @as(isize, @intCast(radius_y));
                    sum_v += psf.weights_y[kk] * sampleScratchOrBackground(
                        scratch_layout,
                        tmp,
                        @as(isize, @intCast(xx)),
                        @as(isize, @intCast(yy)) + y_off,
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                }
                setScratchField(
                    scratch_layout,
                    dst,
                    yy * spx_stride + xx,
                    ff,
                    sum_v,
                );
            }
        }
    }
}

pub fn filterScratchNonSeparableSIMD(
    comptime scratch_layout: ScratchLayout,
    fields_num: u8,
    background_value: F,
    psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    sub_samp: usize,
    spx_stride: usize,
    src: *const MatSlice(F),
    dst: *MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
) void {
    dst.fill(background_value);

    const radius_x = psf.radius_x_subpx;
    const radius_y = psf.radius_y_subpx;
    const kernel_w = 2 * radius_x + 1;

    var yy = scratch_geom.core_start_y_subpx;
    const core_end_y = scratch_geom.core_start_y_subpx +
        scratch_geom.core_h_px * sub_samp - 1;
    while (yy <= core_end_y) : (yy += 1) {
        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;
        const start_y = if (yy >= radius_y) yy - radius_y else 0;
        const end_y = @min(scratch_geom.scratch_h_subpx - 1, yy + radius_y);

        var nn = start_y;
        while (nn <= end_y) : (nn += 1) {
            const r_min = touched_min_x[nn];
            const r_max = touched_max_x[nn];
            if (r_min <= r_max) {
                if (r_min < min_x) min_x = r_min;
                if (r_max > max_x) max_x = r_max;
            }
        }

        if (min_x > max_x) continue;

        const active_min = if (min_x >= radius_x) min_x - radius_x else 0;
        const active_max = max_x + radius_x;

        const xx_start = @max(scratch_geom.core_start_x_subpx, active_min);
        const xx_end = @min(
            scratch_geom.core_start_x_subpx +
                scratch_geom.core_w_px * sub_samp - 1,
            active_max,
        );
        if (xx_start > xx_end) continue;

        var ff: usize = 0;
        while (ff < @as(usize, fields_num)) : (ff += 1) {
            var xx = xx_start;
            while (xx + SimdWidth <= xx_end + 1) : (xx += SimdWidth) {
                var sum_vec = @as(VecSF, @splat(0.0));
                var kk: usize = 0;
                while (kk < psf.weights_2d.len) : (kk += 1) {
                    const ky = kk / kernel_w;
                    const kx = kk % kernel_w;
                    const x_off = @as(
                        isize,
                        @intCast(kx),
                    ) - @as(isize, @intCast(radius_x));
                    const y_off = @as(
                        isize,
                        @intCast(ky),
                    ) - @as(isize, @intCast(radius_y));
                    const input_vec = loadScratchRowSIMD(
                        scratch_layout,
                        src,
                        @as(isize, @intCast(xx)) + x_off,
                        @as(isize, @intCast(yy)) + y_off,
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                    sum_vec += input_vec * @as(
                        VecSF,
                        @splat(psf.weights_2d[kk]),
                    );
                }
                storeScratchRowSIMD(
                    scratch_layout,
                    dst,
                    xx,
                    yy,
                    spx_stride,
                    ff,
                    sum_vec,
                );
            }

            // Scalar tail
            while (xx <= xx_end) : (xx += 1) {
                var sum: F = 0.0;
                var kk: usize = 0;
                while (kk < psf.weights_2d.len) : (kk += 1) {
                    const ky = kk / kernel_w;
                    const kx = kk % kernel_w;
                    const x_off = @as(
                        isize,
                        @intCast(kx),
                    ) - @as(isize, @intCast(radius_x));
                    const y_off = @as(
                        isize,
                        @intCast(ky),
                    ) - @as(isize, @intCast(radius_y));
                    sum += psf.weights_2d[kk] * sampleScratchOrBackground(
                        scratch_layout,
                        src,
                        @as(isize, @intCast(xx)) + x_off,
                        @as(isize, @intCast(yy)) + y_off,
                        scratch_geom,
                        spx_stride,
                        ff,
                        background_value,
                    );
                }
                setScratchField(
                    scratch_layout,
                    dst,
                    yy * spx_stride + xx,
                    ff,
                    sum,
                );
            }
        }
    }
}
