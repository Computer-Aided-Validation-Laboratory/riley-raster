// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const camera = @import("camera.zig");
const F = buildconfig.F;

//---------------------------------------------------------------------------------------
// README, KEEP, DO NOT DELETE
//----------------------------------------------------------------------------------------
// Distortion-aware bounds: engineering assumptions and required accuracy.
//
// NOTE: the distortion aware front end is an intentional engineering realism approximation.
// It is not intended to be mathematically exact! It is intended to be performant for 
// realistic distortion fields.
//
// The caller first bounds the projected element in ideal raster coordinates (from
// its vertices or high-order hull). This file samples the CAMERA DISTORTION MAP
// around that ideal-space rectangle; it does not sample the element's coordinate
// map. The separate element/hull bound must already enclose the projected shape.
//
// We assume the camera distortion is locally invertible and varies smoothly and
// slowly at the default one-pixel sampling scale throughout the rendered domain.
// Fixed edge samples are an engineering approximation, not exact extrema for an
// arbitrary polynomial. Reduce edge_spacing_px when a camera model changes
// appreciably within one pixel. That setting controls the forward rectangle
// samples only: the inverse sensor perimeter is sampled at one-pixel intervals
// independently and gets a one-pixel ideal-space margin.
//
// These bounds only select integer pixel ranges for tile/element overlap. The
// raster loop performs the actual subpixel coverage test. Downstream code floors
// sampled minima and ceils sampled maxima, so the practical requirement is to
// retain every pixel containing a potentially covered subpixel sample, not to
// reproduce the exact floating-point extremum. For one sample per pixel, an
// extremum error strictly below 0.5 pixel is a phase-independent sufficient
// margin for that pixel-center grid. With s samples per axis, the corresponding
// margin is strictly below 0.5 / s pixels; 0.5 pixel alone is insufficient for
// supersampled coverage. Test the chosen spacing against that output-pixel
// criterion for the intended camera and supersampling settings.
//---------------------------------------------------------------------------------------

pub const DistortBounds = struct {
    x_min: F,
    x_max: F,
    y_min: F,
    y_max: F,

    pub fn initEmpty() DistortBounds {
        return .{
            .x_min = std.math.inf(F),
            .x_max = -std.math.inf(F),
            .y_min = std.math.inf(F),
            .y_max = -std.math.inf(F),
        };
    }

    pub fn include(self: *DistortBounds, x: F, y: F) !void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) {
            return error.NonFiniteDistortBound;
        }
        self.x_min = @min(self.x_min, x);
        self.x_max = @max(self.x_max, x);
        self.y_min = @min(self.y_min, y);
        self.y_max = @max(self.y_max, y);
    }

    pub fn intersect(self: DistortBounds, other: DistortBounds) ?DistortBounds {
        const result = DistortBounds{
            .x_min = @max(self.x_min, other.x_min),
            .x_max = @min(self.x_max, other.x_max),
            .y_min = @max(self.y_min, other.y_min),
            .y_max = @min(self.y_max, other.y_max),
        };
        if (result.x_min > result.x_max or result.y_min > result.y_max) {
            return null;
        }
        return result;
    }
};

pub fn validateSpacing(spacing_px: F) !void {
    if (!std.math.isFinite(spacing_px) or spacing_px <= 0.0) {
        return error.InvalidDistortEdgeSpacing;
    }
}

pub fn edgeIntervalCount(length: F, spacing_px: F) !usize {
    const raw_count = @ceil(length / spacing_px);
    if (!std.math.isFinite(raw_count) or raw_count > 1_000_000.0) {
        return error.DistortEdgeSampleLimit;
    }
    return @max(1, @as(usize, @intFromFloat(raw_count)));
}

pub fn idealSensorBounds(
    cam: *const camera.CameraPrepared,
    halo_px: u16,
) !DistortBounds {
    var bounds = DistortBounds.initEmpty();
    if (cam.subpixel_center_map == .full_in_mem) {
        const values = cam.ideal_pixel_centers.slice;
        var ii: usize = 0;
        while (ii + 1 < values.len) : (ii += 2) {
            try bounds.include(values[ii], values[ii + 1]);
        }
        if (halo_px == 0) return bounds;
    }

    const halo: F = @floatFromInt(halo_px);
    const width: F = @floatFromInt(cam.pixels_num[0]);
    const height: F = @floatFromInt(cam.pixels_num[1]);
    const observed = [_][4]F{
        .{ -halo, -halo, width + halo, -halo },
        .{ -halo, height + halo, width + halo, height + halo },
        .{ -halo, -halo, -halo, height + halo },
        .{ width + halo, -halo, width + halo, height + halo },
    };
    for (observed) |edge| {
        const length = @max(@abs(edge[2] - edge[0]), @abs(edge[3] - edge[1]));
        const intervals: usize = @intFromFloat(length);
        for (0..intervals + 1) |ii| {
            const t = @as(F, @floatFromInt(ii)) / @as(F, @floatFromInt(intervals));
            const x = edge[0] + t * (edge[2] - edge[0]);
            const y = edge[1] + t * (edge[3] - edge[1]);
            const ideal = try cam.calcPinholeRasterPoint(x, y);
            try bounds.include(ideal[0], ideal[1]);
        }
    }
    bounds.x_min -= 1.0;
    bounds.x_max += 1.0;
    bounds.y_min -= 1.0;
    bounds.y_max += 1.0;
    return bounds;
}

test "fixed edge counts and spacing errors" {
    try std.testing.expectEqual(@as(usize, 1), try edgeIntervalCount(0.0, 1.0));
    try std.testing.expectEqual(@as(usize, 1), try edgeIntervalCount(1.0, 1.0));
    try std.testing.expectEqual(@as(usize, 2), try edgeIntervalCount(1.01, 1.0));
    try std.testing.expectEqual(@as(usize, 7), try edgeIntervalCount(3.1, 0.5));
    try std.testing.expectError(
        error.DistortEdgeSampleLimit,
        edgeIntervalCount(1_000_001.0, 1.0),
    );
    for ([_]F{ 0.0, -1.0, std.math.nan(F), std.math.inf(F) }) |spacing| {
        try std.testing.expectError(
            error.InvalidDistortEdgeSpacing,
            validateSpacing(spacing),
        );
    }
}
