const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const rops = @import("rasterops.zig");

pub const OverlapTarget = struct {
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
};

pub const SubpxDomain = struct {
    step: f64,
    offset: f64,
    tile_size: usize,
    x_off: f64,
    y_off: f64,
};

pub const RasterBounds = struct {
    start_x_u: usize,
    end_x_u: usize,
    start_y_u: usize,
    end_y_u: usize,
    x_min_f: f64,
    y_min_f: f64,
};

pub const ScratchLayout = enum {
    subpx_major,
    field_major,
};

pub inline fn getScratchField(
    comptime scratch_layout: ScratchLayout,
    spx_image_scratch: *const MatSlice(f64),
    scratch_flat_idx: usize,
    field_idx: usize,
) f64 {
    return switch (scratch_layout) {
        .subpx_major => spx_image_scratch.get(scratch_flat_idx, field_idx),
        .field_major => spx_image_scratch.get(field_idx, scratch_flat_idx),
    };
}

pub fn resolveScratchDirect(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const scratch_row_offset = ty * spx_tile_size;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const scratch_flat_idx = scratch_row_offset + tx;

            if (fields_num == 1) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
            } else if (fields_num == 3) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        1,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        2,
                    ),
                );
            } else {
                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            ff,
                        ),
                    );
                }
            }
        }
    }
}

pub fn averageScratch(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    var field_avg_buff = [_]f64{0.0} ** cfg.max_nodal_fields;
    const spx_field_avg = field_avg_buff[0..@as(usize, fields_num)];

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;
        var touched_min_px_x = curr_tile_size_x;
        var touched_max_px_x: usize = 0;

        for (0..sub_samp) |sy| {
            const scratch_y = spx_start_y + sy;
            const row_min_x = touched_min_x[scratch_y];
            const row_max_x = touched_max_x[scratch_y];

            if (row_min_x <= row_max_x) {
                const row_min_px_x = row_min_x / sub_samp;
                const row_max_px_x = row_max_x / sub_samp;
                if (row_min_px_x < touched_min_px_x) {
                    touched_min_px_x = row_min_px_x;
                }
                if (row_max_px_x > touched_max_px_x) {
                    touched_max_px_x = row_max_px_x;
                }
            }
        }

        if (touched_min_px_x > touched_max_px_x) {
            continue;
        }

        for (touched_min_px_x..@min(curr_tile_size_x, touched_max_px_x + 1)) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            if (fields_num == 1) {
                var field_sum_0: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                    }
                }

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
            } else if (fields_num == 3) {
                var field_sum_0: f64 = 0.0;
                var field_sum_1: f64 = 0.0;
                var field_sum_2: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;
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

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    field_sum_1 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    field_sum_2 * inv_sub_samp_sq,
                );
            } else {
                @memset(spx_field_avg, 0.0);

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize = scratch_row_offset + spx_start_x + sx;

                        for (0..@as(usize, fields_num)) |ff| {
                            spx_field_avg[ff] += getScratchField(
                                scratch_layout,
                                spx_image_scratch,
                                scratch_flat_idx,
                                ff,
                            );
                        }
                    }
                }

                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        spx_field_avg[ff] * inv_sub_samp_sq,
                    );
                }
            }
        }
    }
}
