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
const ScratchLayout = common.ScratchLayout;
const ScratchTileGeometry = common.ScratchTileGeometry;
const MatSlice = common.MatSlice;
const NDArray = common.NDArray;
const FrameImageWriter = common.FrameImageWriter;
const getScratchField = common.getScratchField;
const setScratchField = common.setScratchField;
const sampleScratchOrBackground = common.sampleScratchOrBackground;

pub fn resolveScratchDirectCore(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    radius_x: usize,
    radius_y: usize,
    image_out_arr: *NDArray(F),
) void {
    const writer = FrameImageWriter.init(image_out_arr);

    var ii: usize = 0;
    while (ii < scratch_geom.core_h_px) : (ii += 1) {
        const image_px_y = tile.y_px_min + ii;
        const spx_start_y = scratch_geom.core_start_y_subpx + ii;

        var min_x = scratch_geom.scratch_w_subpx;
        var max_x: usize = 0;

        const start_y = if (spx_start_y >= radius_y)
            spx_start_y - radius_y
        else
            0;
        const end_y = @min(
            scratch_geom.scratch_h_subpx - 1,
            spx_start_y + radius_y,
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
            tx_start = active_subpx_min - scratch_geom.core_start_x_subpx;
        }
        var tx_end: usize = scratch_geom.core_w_px - 1;
        if (active_subpx_max >= scratch_geom.core_start_x_subpx) {
            const calculated_end = active_subpx_max -
                scratch_geom.core_start_x_subpx;
            if (calculated_end < tx_end) {
                tx_end = calculated_end;
            }
        } else {
            continue;
        }

        const scratch_row_offset = spx_start_y * spx_stride;

        var jj = tx_start;
        while (jj <= tx_end) : (jj += 1) {
            const image_px_x = tile.x_px_min + jj;
            const scratch_flat_idx = scratch_row_offset +
                scratch_geom.core_start_x_subpx + jj;
            const image_px_base = writer.pixelBase(image_px_y, image_px_x);

            if (fields_num == 1) {
                writer.slice[image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    0,
                );
            } else if (fields_num == 3) {
                writer.slice[image_px_base] = getScratchField(
                    scratch_layout,
                    spx_image_scratch,
                    scratch_flat_idx,
                    0,
                );
                writer.slice[writer.field_stride + image_px_base] =
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        1,
                    );
                writer.slice[2 * writer.field_stride + image_px_base] =
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        2,
                    );
            } else {
                var ff: usize = 0;
                while (ff < @as(usize, fields_num)) : (ff += 1) {
                    writer.slice[ff * writer.field_stride + image_px_base] =
                        getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            ff,
                        );
                }
            }
        }
    }
}

pub fn averageScratchCore(
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

            if (fields_num == 1) {
                var field_sum_0: F = 0.0;
                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) *
                        spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x + col_idx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                    }
                }
                writer.slice[image_px_base] = field_sum_0 * inv_sub_samp_sq;
            } else if (fields_num == 3) {
                var field_sum_0: F = 0.0;
                var field_sum_1: F = 0.0;
                var field_sum_2: F = 0.0;
                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) *
                        spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x + col_idx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                        field_sum_1 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            1,
                        );
                        field_sum_2 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            2,
                        );
                    }
                }
                writer.slice[image_px_base] = field_sum_0 * inv_sub_samp_sq;
                writer.slice[writer.field_stride + image_px_base] =
                    field_sum_1 * inv_sub_samp_sq;
                writer.slice[2 * writer.field_stride + image_px_base] =
                    field_sum_2 * inv_sub_samp_sq;
            } else {
                var field_avg_buff = [_]F{0.0} ** cfg.max_nodal_fields;
                const spx_field_avg = field_avg_buff[0..@as(usize, fields_num)];
                @memset(spx_field_avg, 0.0);

                var row_idx: usize = 0;
                while (row_idx < sub_samp) : (row_idx += 1) {
                    const scratch_row_offset = (spx_start_y + row_idx) *
                        spx_stride;
                    var col_idx: usize = 0;
                    while (col_idx < sub_samp) : (col_idx += 1) {
                        const scratch_flat_idx = scratch_row_offset +
                            spx_start_x + col_idx;
                        var ff: usize = 0;
                        while (ff < @as(usize, fields_num)) : (ff += 1) {
                            spx_field_avg[ff] += getScratchField(
                                scratch_layout,
                                spx_image_scratch,
                                scratch_flat_idx,
                                ff,
                            );
                        }
                    }
                }

                var ff: usize = 0;
                while (ff < @as(usize, fields_num)) : (ff += 1) {
                    writer.slice[ff * writer.field_stride + image_px_base] =
                        spx_field_avg[ff] * inv_sub_samp_sq;
                }
            }
        }
    }
}

pub fn filterScratchSeparable(
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
            // Scalar path
            var xx = xx_start;
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
            // Scalar path
            var xx = xx_start;
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

pub fn filterScratchNonSeparable(
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
            // Scalar path
            var xx = xx_start;
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
