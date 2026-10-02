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
