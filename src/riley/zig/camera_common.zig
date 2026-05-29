// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

pub inline fn isNoDistortion(distortion: anytype) bool {
    return switch (distortion) {
        .none => true,
        else => false,
    };
}

pub inline fn calcSubpixelStep(sub_sample: u8) f64 {
    return 1.0 / @as(f64, @floatFromInt(sub_sample));
}

pub inline fn calcSubpixelOffset(sub_sample: u8) f64 {
    return 0.5 / @as(f64, @floatFromInt(sub_sample));
}

pub inline fn calcObservedSubpixelCoord(global_subpx: usize, sub_sample: u8) f64 {
    const step = calcSubpixelStep(sub_sample);
    const off = calcSubpixelOffset(sub_sample);
    return @as(f64, @floatFromInt(global_subpx)) * step + off;
}

pub inline fn calcPixelCenterCoord(pixel: usize) f64 {
    return @as(f64, @floatFromInt(pixel)) + 0.5;
}

pub inline fn storeIdealPairScratch(
    ideal_pixel_centers: []f64,
    scratch_idx: usize,
    ideal_x: f64,
    ideal_y: f64,
) void {
    ideal_pixel_centers[scratch_idx * 2 + 0] = ideal_x;
    ideal_pixel_centers[scratch_idx * 2 + 1] = ideal_y;
}
