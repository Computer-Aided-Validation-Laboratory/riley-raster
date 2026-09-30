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
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;

pub const Bounds = struct {
    x_min: F,
    x_max: F,
    y_min: F,
    y_max: F,

    pub fn initEmpty() Bounds {
        return .{
            .x_min = std.math.inf(F),
            .x_max = -std.math.inf(F),
            .y_min = std.math.inf(F),
            .y_max = -std.math.inf(F),
        };
    }

    pub fn include(self: *Bounds, x: F, y: F) !void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) {
            return error.NonFiniteDistortBound;
        }
        self.x_min = @min(self.x_min, x);
        self.x_max = @max(self.x_max, x);
        self.y_min = @min(self.y_min, y);
        self.y_max = @max(self.y_max, y);
    }

    pub fn intersect(self: Bounds, other: Bounds) ?Bounds {
        const result = Bounds{
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

fn edgeIntervalCount(length: F, spacing_px: F) !usize {
    const raw_count = @ceil(length / spacing_px);
    if (!std.math.isFinite(raw_count) or raw_count > 1_000_000.0) {
        return error.DistortEdgeSampleLimit;
    }
    return @max(1, @as(usize, @intFromFloat(raw_count)));
}

pub fn sampleRectScalar(
    cam: *const camera.CameraPrepared,
    rect: Bounds,
    spacing_px: F,
) !Bounds {
    try validateSpacing(spacing_px);
    var result = Bounds.initEmpty();
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
        const intervals = try edgeIntervalCount(length, spacing_px);
        for (0..intervals + 1) |ii| {
            const t = @as(F, @floatFromInt(ii)) / @as(F, @floatFromInt(intervals));
            const ideal_x = edge[0] + t * (edge[2] - edge[0]);
            const ideal_y = edge[1] + t * (edge[3] - edge[1]);
            const norm_x = (ideal_x - offsets.x_off) / focal.fx;
            const norm_y = (ideal_y - offsets.y_off) / focal.fy;
            if (!std.math.isFinite(norm_x) or !std.math.isFinite(norm_y)) {
                return error.NonFiniteDistortBound;
            }
            const mapped = camera.fordDistortModelScal(cam.distort, norm_x, norm_y);
            try result.include(
                mapped.x * focal.fx + offsets.x_off,
                mapped.y * focal.fy + offsets.y_off,
            );
        }
    }
    return result;
}

pub fn sampleRectSIMD(
    cam: *const camera.CameraPrepared,
    rect: Bounds,
    spacing_px: F,
) !Bounds {
    try validateSpacing(spacing_px);
    var result = Bounds.initEmpty();
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
        const intervals = try edgeIntervalCount(length, spacing_px);
        var ii: usize = 0;
        while (ii <= intervals) : (ii += S) {
            const count = @min(S, intervals + 1 - ii);
            var norm_x_arr: [S]F = undefined;
            var norm_y_arr: [S]F = undefined;
            for (0..S) |lane| {
                const sample_idx = ii + @min(lane, count - 1);
                const t = @as(F, @floatFromInt(sample_idx)) /
                    @as(F, @floatFromInt(intervals));
                const ideal_x = edge[0] + t * (edge[2] - edge[0]);
                const ideal_y = edge[1] + t * (edge[3] - edge[1]);
                norm_x_arr[lane] = (ideal_x - offsets.x_off) / focal.fx;
                norm_y_arr[lane] = (ideal_y - offsets.y_off) / focal.fy;
                if (!std.math.isFinite(norm_x_arr[lane]) or
                    !std.math.isFinite(norm_y_arr[lane]))
                {
                    return error.NonFiniteDistortBound;
                }
            }
            const mapped = camera.fordDistortModelSIMD(
                cam.distort,
                @as(VecSF, @bitCast(norm_x_arr)),
                @as(VecSF, @bitCast(norm_y_arr)),
            );
            const mapped_x: [S]F = @bitCast(mapped.x);
            const mapped_y: [S]F = @bitCast(mapped.y);
            for (0..count) |lane| {
                try result.include(
                    mapped_x[lane] * focal.fx + offsets.x_off,
                    mapped_y[lane] * focal.fy + offsets.y_off,
                );
            }
        }
    }
    return result;
}

pub fn sampleRect(
    cam: *const camera.CameraPrepared,
    rect: Bounds,
    spacing_px: F,
) !Bounds {
    if (comptime buildconfig.config.simd == .on) {
        return sampleRectSIMD(cam, rect, spacing_px);
    }
    return sampleRectScalar(cam, rect, spacing_px);
}

pub fn idealSensorBounds(
    cam: *const camera.CameraPrepared,
    halo_px: u16,
) !Bounds {
    var bounds = Bounds.initEmpty();
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
    try std.testing.expectError(error.DistortEdgeSampleLimit, edgeIntervalCount(1_000_001.0, 1.0));
    for ([_]F{ 0.0, -1.0, std.math.nan(F), std.math.inf(F) }) |spacing| {
        try std.testing.expectError(error.InvalidDistortEdgeSpacing, validateSpacing(spacing));
    }
}
