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
const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");

pub const MatSlice = matslice.MatSlice;
pub const NDArray = ndarray.NDArray;

pub const ScratchLayout = enum {
    subpx_major,
    field_major,
};

pub const ScratchTileGeometry = struct {
    core_w_px: usize,
    core_h_px: usize,
    scratch_w_px: usize,
    scratch_h_px: usize,
    scratch_w_subpx: usize,
    scratch_h_subpx: usize,
    core_start_x_subpx: usize,
    core_start_y_subpx: usize,

    pub fn init(tile: rops.ActiveTile, sub_sample: usize) ScratchTileGeometry {
        const core_w_px = @as(usize, tile.x_px_max - tile.x_px_min);
        const core_h_px = @as(usize, tile.y_px_max - tile.y_px_min);
        const scratch_w_px = @as(
            usize,
            tile.scratch_x_px_max - tile.scratch_x_px_min,
        );
        const scratch_h_px = @as(
            usize,
            tile.scratch_y_px_max - tile.scratch_y_px_min,
        );
        return .{
            .core_w_px = core_w_px,
            .core_h_px = core_h_px,
            .scratch_w_px = scratch_w_px,
            .scratch_h_px = scratch_h_px,
            .scratch_w_subpx = scratch_w_px * sub_sample,
            .scratch_h_subpx = scratch_h_px * sub_sample,
            .core_start_x_subpx = (@as(
                usize,
                tile.x_px_min - tile.scratch_x_px_min,
            )) * sub_sample,
            .core_start_y_subpx = (@as(
                usize,
                tile.y_px_min - tile.scratch_y_px_min,
            )) * sub_sample,
        };
    }
};

pub const FrameImageWriter = struct {
    slice: []f64,
    field_stride: usize,
    row_stride: usize,

    pub fn init(image_out_arr: *NDArray(f64)) FrameImageWriter {
        return .{
            .slice = image_out_arr.slice,
            .field_stride = image_out_arr.strides[0],
            .row_stride = image_out_arr.strides[1],
        };
    }

    pub fn set(
        self: *const FrameImageWriter,
        field_idx: usize,
        row_idx: usize,
        col_idx: usize,
        val: f64,
    ) void {
        const offset = field_idx * self.field_stride +
            row_idx * self.row_stride + col_idx;
        self.slice[offset] = val;
    }

    pub fn pixelBase(
        self: *const FrameImageWriter,
        row_idx: usize,
        col_idx: usize,
    ) usize {
        return row_idx * self.row_stride + col_idx;
    }
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

pub inline fn setScratchField(
    comptime scratch_layout: ScratchLayout,
    spx_image_scratch: *MatSlice(f64),
    scratch_flat_idx: usize,
    field_idx: usize,
    val: f64,
) void {
    switch (scratch_layout) {
        .subpx_major => spx_image_scratch.set(
            scratch_flat_idx,
            field_idx,
            val,
        ),
        .field_major => spx_image_scratch.set(
            field_idx,
            scratch_flat_idx,
            val,
        ),
    }
}

pub fn sampleScratchOrBackground(
    comptime scratch_layout: ScratchLayout,
    src: *const MatSlice(f64),
    x: isize,
    y: isize,
    scratch_geom: ScratchTileGeometry,
    spx_stride: usize,
    field_idx: usize,
    background_value: f64,
) f64 {
    if (x < 0 or y < 0 or
        x >= @as(isize, @intCast(scratch_geom.scratch_w_subpx)) or
        y >= @as(isize, @intCast(scratch_geom.scratch_h_subpx)))
    {
        return background_value;
    }
    const flat_idx = @as(usize, @intCast(y)) * spx_stride +
        @as(usize, @intCast(x));
    return getScratchField(scratch_layout, src, flat_idx, field_idx);
}
