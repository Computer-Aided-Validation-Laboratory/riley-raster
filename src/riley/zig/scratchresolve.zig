// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cameramodels = @import("cameramodels.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const elemtilebinning = @import("elemtilebinning.zig");
const matslice = @import("matslice.zig");
const ndarray = @import("ndarray.zig");
const scratchresolve_common = @import("scratchresolve_common.zig");
const scratchresolve_scalar = @import("scratchresolve_scalar.zig");
const scratchresolve_simd = @import("scratchresolve_simd.zig");

const cfg = buildconfig.config;
const avg_scratch_impl = if (cfg.simd == .on)
    scratchresolve_simd.avgScratchCoreSIMD
else
    scratchresolve_scalar.avgScratchCore;
const filter_scratch_separable_impl = if (cfg.simd == .on)
    scratchresolve_simd.filterScratchSeparableSIMD
else
    scratchresolve_scalar.filterScratchSeparable;
const filter_scratch_nonseparable_impl = if (cfg.simd == .on)
    scratchresolve_simd.filterScratchNonSeparableSIMD
else
    scratchresolve_scalar.filterScratchNonSeparable;

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn resolveScratchDirect(
    tile: elemtilebinning.ActiveTile,
    scratch_geom: scratchresolve_common.ScratchTileGeometry,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const matslice.MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *ndarray.NDArray(F),
) void {
    scratchresolve_scalar.resolveScratchDirectCore(
        tile,
        scratch_geom,
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

pub fn avgScratch(
    tile: elemtilebinning.ActiveTile,
    scratch_geom: scratchresolve_common.ScratchTileGeometry,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const matslice.MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *ndarray.NDArray(F),
) void {
    avg_scratch_impl(
        tile,
        scratch_geom,
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

pub fn resolveTileWithPSF(
    tile: elemtilebinning.ActiveTile,
    sub_samp: usize,
    spx_stride: usize,
    fields_num: u8,
    background_value: F,
    prep_psf: cameramodels.PreparedPSF,
    scratch_geom: scratchresolve_common.ScratchTileGeometry,
    spx_image_scratch: *matslice.MatSlice(F),
    filter_tmp: *matslice.MatSlice(F),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *ndarray.NDArray(F),
) void {
    scratchresolve_common.resolveTileWithPSF(
        @TypeOf(scratchresolve_scalar.resolveScratchDirectCore),
        @TypeOf(avg_scratch_impl),
        @TypeOf(filter_scratch_separable_impl),
        @TypeOf(filter_scratch_nonseparable_impl),
        scratchresolve_scalar.resolveScratchDirectCore,
        avg_scratch_impl,
        filter_scratch_separable_impl,
        filter_scratch_nonseparable_impl,
        tile,
        sub_samp,
        spx_stride,
        fields_num,
        background_value,
        prep_psf,
        scratch_geom,
        spx_image_scratch,
        filter_tmp,
        touched_min_x,
        touched_max_x,
        image_out_arr,
    );
}
