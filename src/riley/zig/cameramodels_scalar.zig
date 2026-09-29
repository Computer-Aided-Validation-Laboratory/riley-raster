// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const common = @import("cameramodels_common.zig");

const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Distortion Unions
// --------------------------------------------------------------------------------------

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn fordDistortModel(
    distort: common.DistortModel,
    x: F,
    y: F,
) common.DistortCoords {
    return switch (distort) {
        .none => .{ .x = x, .y = y },
        .brown_con => |params| common.BrownCon.ford(params, x, y),
        .brown_con_ext => |model| model.ford(x, y),
        .poly => |poly| poly.ford(x, y),
        .brown_con_poly => |chain| chain.ford(x, y),
        .brown_con_ext_poly => |chain| chain.ford(x, y),
    };
}

pub fn invDistortModel(
    distort: common.DistortModel,
    x_d: F,
    y_d: F,
) !common.DistortCoords {
    return switch (distort) {
        .none => .{ .x = x_d, .y = y_d },
        .brown_con => |params| try common.BrownCon.inv(params, x_d, y_d),
        .brown_con_ext => |model| try model.inv(x_d, y_d),
        .poly => |poly| try poly.inv(x_d, y_d),
        .brown_con_poly => |chain| try chain.inv(x_d, y_d),
        .brown_con_ext_poly => |chain| try chain.inv(x_d, y_d),
    };
}
