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
const common = @import("distortbounds_common.zig");
const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const DistortBounds = common.DistortBounds;

pub fn sampleRect(
    cam: *const camera.CameraPrepared,
    rect: DistortBounds,
    spacing_px: F,
) !DistortBounds {
    try common.validateSpacing(spacing_px);
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
        const intervals = try common.edgeIntervalCount(length, spacing_px);
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
