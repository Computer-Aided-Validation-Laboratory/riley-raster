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

const cfg = buildconfig.config;
const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;

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

const sensor_distort_bound_tol_px: F = 1.0;

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

    pub inline fn fromCoords2D(comptime N: usize, coords: anytype) DistortBounds {
        var min_x = coords.x[0];
        var max_x = coords.x[0];
        var min_y = coords.y[0];
        var max_y = coords.y[0];
        inline for (1..N) |nn| {
            min_x = @min(min_x, coords.x[nn]);
            max_x = @max(max_x, coords.x[nn]);
            min_y = @min(min_y, coords.y[nn]);
            max_y = @max(max_y, coords.y[nn]);
        }
        return .{
            .x_min = min_x,
            .x_max = max_x,
            .y_min = min_y,
            .y_max = max_y,
        };
    }

    pub inline fn include(self: *DistortBounds, x: F, y: F) void {
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

pub inline fn edgeIntervalCount(length: F, spacing_px: F) usize {
    const raw_count = @ceil(length / spacing_px);
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
            bounds.include(values[ii], values[ii + 1]);
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
            bounds.include(ideal[0], ideal[1]);
        }

    }

    bounds.x_min -= sensor_distort_bound_tol_px;
    bounds.x_max += sensor_distort_bound_tol_px;
    bounds.y_min -= sensor_distort_bound_tol_px;
    bounds.y_max += sensor_distort_bound_tol_px;

    return bounds;
}

inline fn sampleEdgePointScalar(
    cam: *const camera.CameraPrepared,
    focal: anytype,
    offsets: anytype,
    edge: [4]F,
    sample_idx: usize,
    intervals: usize,
    result: *DistortBounds,
) void {
    const t = @as(F, @floatFromInt(sample_idx)) / @as(F, @floatFromInt(intervals));
    const ideal_x = edge[0] + t * (edge[2] - edge[0]);
    const ideal_y = edge[1] + t * (edge[3] - edge[1]);
    const norm_x = (ideal_x - offsets.x_off) / focal.fx;
    const norm_y = (ideal_y - offsets.y_off) / focal.fy;
    const mapped = camera.fordDistortModelScal(cam.distort, norm_x, norm_y);
    result.include(
        mapped.x * focal.fx + offsets.x_off,
        mapped.y * focal.fy + offsets.y_off,
    );
}

pub fn sampleRectEdgesScalar(
    cam: *const camera.CameraPrepared,
    rect: DistortBounds,
    spacing_px: F,
) DistortBounds {
    std.debug.assert(std.math.isFinite(spacing_px) and spacing_px > 0.0);

    var result = DistortBounds.initEmpty();

    const corners = [_][4]F{
        .{ rect.x_min, rect.y_min, rect.x_max, rect.y_min },
        .{ rect.x_min, rect.y_max, rect.x_max, rect.y_max },
        .{ rect.x_min, rect.y_min, rect.x_min, rect.y_max },
        .{ rect.x_max, rect.y_min, rect.x_max, rect.y_max },
    };

    const focal = cam.calcFocalPx();
    const offsets = cam.calcRasterOffsets();

    for (corners) |edge| {
        const length = @max(@abs(edge[2] - edge[0]), @abs(edge[3] - edge[1]));
        const intervals = edgeIntervalCount(length, spacing_px);

        for (0..intervals + 1) |ii| {
            sampleEdgePointScalar(
                cam,
                focal,
                offsets,
                edge,
                ii,
                intervals,
                &result,
            );
        }
    }
    return result;
}

pub fn sampleRectEdgesSIMD(
    cam: *const camera.CameraPrepared,
    rect: DistortBounds,
    spacing_px: F,
) DistortBounds {
    std.debug.assert(std.math.isFinite(spacing_px) and spacing_px > 0.0);
    var result = DistortBounds.initEmpty();
    const corners = [_][4]F{
        .{ rect.x_min, rect.y_min, rect.x_max, rect.y_min },
        .{ rect.x_min, rect.y_max, rect.x_max, rect.y_max },
        .{ rect.x_min, rect.y_min, rect.x_min, rect.y_max },
        .{ rect.x_max, rect.y_min, rect.x_max, rect.y_max },
    };
    const focal = cam.calcFocalPx();
    const offsets = cam.calcRasterOffsets();

    for (corners) |edge| {
        const length = @max(@abs(edge[2] - edge[0]), @abs(edge[3] - edge[1]));
        const intervals = edgeIntervalCount(length, spacing_px);
        const total_samples = intervals + 1;

        if (total_samples < S) {
            for (0..total_samples) |ii| {
                sampleEdgePointScalar(
                    cam,
                    focal,
                    offsets,
                    edge,
                    ii,
                    intervals,
                    &result,
                );
            }
        } else {
            var ii: usize = 0;
            while (ii + S <= total_samples) : (ii += S) {
                var norm_x_arr: [S]F = undefined;
                var norm_y_arr: [S]F = undefined;
                for (0..S) |lane| {
                    const sample_idx = ii + lane;
                    const t = @as(F, @floatFromInt(sample_idx)) /
                        @as(F, @floatFromInt(intervals));
                    const ideal_x = edge[0] + t * (edge[2] - edge[0]);
                    const ideal_y = edge[1] + t * (edge[3] - edge[1]);
                    norm_x_arr[lane] = (ideal_x - offsets.x_off) / focal.fx;
                    norm_y_arr[lane] = (ideal_y - offsets.y_off) / focal.fy;
                }
                const mapped = camera.fordDistortModelSIMD(
                    cam.distort,
                    @as(VecSF, @bitCast(norm_x_arr)),
                    @as(VecSF, @bitCast(norm_y_arr)),
                );
                const mapped_x: [S]F = @bitCast(mapped.x);
                const mapped_y: [S]F = @bitCast(mapped.y);
                for (0..S) |lane| {
                    result.include(
                        mapped_x[lane] * focal.fx + offsets.x_off,
                        mapped_y[lane] * focal.fy + offsets.y_off,
                    );
                }
            }
            while (ii < total_samples) : (ii += 1) {
                sampleEdgePointScalar(
                    cam,
                    focal,
                    offsets,
                    edge,
                    ii,
                    intervals,
                    &result,
                );
            }
        }
    }
    return result;
}

pub fn sampleRectEdges(
    cam: *const camera.CameraPrepared,
    rect: DistortBounds,
    spacing_px: F,
) DistortBounds {
    if (comptime cfg.simd == .on) {
        return sampleRectEdgesSIMD(cam, rect, spacing_px);
    } else {
        return sampleRectEdgesScalar(cam, rect, spacing_px);
    }
}

test "fixed edge counts" {
    try std.testing.expectEqual(@as(usize, 1), edgeIntervalCount(0.0, 1.0));
    try std.testing.expectEqual(@as(usize, 1), edgeIntervalCount(1.0, 1.0));
    try std.testing.expectEqual(@as(usize, 2), edgeIntervalCount(1.01, 1.0));
    try std.testing.expectEqual(@as(usize, 7), edgeIntervalCount(3.1, 0.5));
    try std.testing.expectEqual(
        @as(usize, 1_000_001),
        edgeIntervalCount(1_000_001.0, 1.0),
    );
}
