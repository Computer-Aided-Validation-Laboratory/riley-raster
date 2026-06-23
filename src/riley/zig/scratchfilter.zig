// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const rops = @import("rasterops.zig");
const cam = @import("camera.zig");
const common = @import("scratchfilter_common.zig");
const scalar = @import("scratchfilter_scalar.zig");
const simd = @import("scratchfilter_simd.zig");

const cfg = buildconfig.config;

pub const ScratchTileGeometry = common.ScratchTileGeometry;
pub const MatSlice = common.MatSlice;
pub const NDArray = common.NDArray;

pub fn resolveScratchDirect(
    tile: rops.ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(F),
) void {
    const dummy_geom = ScratchTileGeometry{
        .scratch_w_px = tile.x_px_max - tile.x_px_min,
        .scratch_h_px = tile.y_px_max - tile.y_px_min,
        .scratch_w_subpx = tile.x_px_max - tile.x_px_min,
        .scratch_h_subpx = tile.y_px_max - tile.y_px_min,
        .core_w_px = tile.x_px_max - tile.x_px_min,
        .core_h_px = tile.y_px_max - tile.y_px_min,
        .core_start_x_subpx = 0,
        .core_start_y_subpx = 0,
    };
    resolveScratchDirectCore(
        tile,
        dummy_geom,
        spx_tile_size,
        fields_num,
        spx_image_scratch,
        touched_min_x,
        touched_max_x,
        0,
        0,
        image_out_arr,
    );
}

pub fn resolveScratchDirectCore(
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
    scalar.resolveScratchDirectCore(
        tile,
        scratch_geom,
        spx_stride,
        fields_num,
        spx_image_scratch,
        touched_min_x,
        touched_max_x,
        radius_x,
        radius_y,
        image_out_arr,
    );
}

pub fn averageScratch(
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(F),
) void {
    const dummy_geom = ScratchTileGeometry{
        .scratch_w_px = tile.x_px_max - tile.x_px_min,
        .scratch_h_px = tile.y_px_max - tile.y_px_min,
        .scratch_w_subpx = (tile.x_px_max - tile.x_px_min) * sub_samp,
        .scratch_h_subpx = (tile.y_px_max - tile.y_px_min) * sub_samp,
        .core_w_px = tile.x_px_max - tile.x_px_min,
        .core_h_px = tile.y_px_max - tile.y_px_min,
        .core_start_x_subpx = 0,
        .core_start_y_subpx = 0,
    };
    averageScratchCore(
        tile,
        dummy_geom,
        sub_samp,
        spx_tile_size,
        fields_num,
        spx_image_scratch,
        touched_min_x,
        touched_max_x,
        0,
        0,
        image_out_arr,
    );
}

pub fn averageScratchCore(
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
    if (cfg.simd == .on) {
        simd.averageScratchCoreSIMD(
            tile,
            scratch_geom,
            sub_samp,
            spx_stride,
            fields_num,
            spx_image_scratch,
            touched_min_x,
            touched_max_x,
            radius_x,
            radius_y,
            image_out_arr,
        );
    } else {
        scalar.averageScratchCore(
            tile,
            scratch_geom,
            sub_samp,
            spx_stride,
            fields_num,
            spx_image_scratch,
            touched_min_x,
            touched_max_x,
            radius_x,
            radius_y,
            image_out_arr,
        );
    }
}

pub fn filterScratchSeparable(
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
    if (cfg.simd == .on) {
        simd.filterScratchSeparableSIMD(
            fields_num,
            background_value,
            psf,
            scratch_geom,
            sub_samp,
            spx_stride,
            src,
            tmp,
            dst,
            touched_min_x,
            touched_max_x,
        );
    } else {
        scalar.filterScratchSeparable(
            fields_num,
            background_value,
            psf,
            scratch_geom,
            sub_samp,
            spx_stride,
            src,
            tmp,
            dst,
            touched_min_x,
            touched_max_x,
        );
    }
}

pub fn filterScratchNonSeparable(
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
    if (cfg.simd == .on) {
        simd.filterScratchNonSeparableSIMD(
            fields_num,
            background_value,
            psf,
            scratch_geom,
            sub_samp,
            spx_stride,
            src,
            dst,
            touched_min_x,
            touched_max_x,
        );
    } else {
        scalar.filterScratchNonSeparable(
            fields_num,
            background_value,
            psf,
            scratch_geom,
            sub_samp,
            spx_stride,
            src,
            dst,
            touched_min_x,
            touched_max_x,
        );
    }
}

pub fn resolveTileWithPSF(
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    background_value: F,
    prepared_psf: cam.PreparedPSF,
    scratch_geom: ScratchTileGeometry,
    spx_image_scratch: *MatSlice(F),
    filter_tmp: *MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(F),
) void {
    switch (prepared_psf.mode) {
        .identity_fast => {
            if (sub_samp > 1) {
                averageScratchCore(
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    0,
                    0,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    0,
                    0,
                    image_out_arr,
                );
            }
        },
        .separable => {
            filterScratchSeparable(
                fields_num,
                background_value,
                prepared_psf,
                scratch_geom,
                sub_samp,
                spx_stride,
                spx_image_scratch,
                filter_tmp,
                spx_image_scratch,
                touched_min_x,
                touched_max_x,
            );
            if (sub_samp > 1) {
                averageScratchCore(
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    spx_image_scratch,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            }
        },
        .nonseparable => {
            filterScratchNonSeparable(
                fields_num,
                background_value,
                prepared_psf,
                scratch_geom,
                sub_samp,
                spx_stride,
                spx_image_scratch,
                filter_tmp,
                touched_min_x,
                touched_max_x,
            );
            if (sub_samp > 1) {
                averageScratchCore(
                    tile,
                    scratch_geom,
                    sub_samp,
                    spx_stride,
                    fields_num,
                    filter_tmp,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            } else {
                resolveScratchDirectCore(
                    tile,
                    scratch_geom,
                    spx_stride,
                    fields_num,
                    filter_tmp,
                    touched_min_x,
                    touched_max_x,
                    prepared_psf.radius_x_subpx,
                    prepared_psf.radius_y_subpx,
                    image_out_arr,
                );
            }
        },
    }
}
