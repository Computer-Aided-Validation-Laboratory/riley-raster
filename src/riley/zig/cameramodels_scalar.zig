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
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn forwardDistortionModel(
    distortion: common.DistortionModel,
    x: F,
    y: F,
) [2]F {
    return switch (distortion) {
        .none => .{ x, y },
        .brown_conrady => |bc| bc.forward(x, y),
        .brown_conrady_ext => |bc_ext| bc_ext.forward(x, y),
        .polynomial => |poly| poly.forward(x, y),
        .brown_conrady_polynomial => |chain| chain.forward(x, y),
        .brown_conrady_ext_polynomial => |chain| chain.forward(x, y),
    };
}

pub fn inverseDistortionModel(
    distortion: common.DistortionModel,
    x_d: F,
    y_d: F,
) !common.DistortionInverseResult {
    return switch (distortion) {
        .none => .{ .x = x_d, .y = y_d },
        .brown_conrady => |bc| try bc.inverse(x_d, y_d),
        .brown_conrady_ext => |bc_ext| try bc_ext.inverse(x_d, y_d),
        .polynomial => |poly| try poly.inverse(x_d, y_d),
        .brown_conrady_polynomial => |chain| try chain.inverse(x_d, y_d),
        .brown_conrady_ext_polynomial => |chain| try chain.inverse(x_d, y_d),
    };
}
