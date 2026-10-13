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
const F = buildconfig.F;

pub const HullEdge = struct {
    a: F,
    b: F,
    c: F,

    pub fn init(x0: F, y0: F, x1: F, y1: F, slack: F) @This() {
        const dx = x1 - x0;
        const dy = y1 - y0;
        const left = x1 * y0;
        const right = x0 * y1;
        // The expanded form loses some cancellation accuracy near an edge.
        // Round outward so that a preparation change cannot cull a valid ray.
        const rounding = 16 * std.math.floatEps(F) *
            (@abs(left) + @abs(right) + @abs(x0 * dy) + @abs(y0 * dx));
        return .{
            .a = dy,
            .b = -dx,
            .c = left - right + slack + rounding,
        };
    }

    pub inline fn eval(self: @This(), px: F, py: F) F {
        return self.a * px + self.b * py + self.c;
    }
};

pub fn edgeFun3Slices(
    comptime ind0: usize,
    comptime ind1: usize,
    comptime ind2: usize,
    x: []const F,
    y: []const F,
) F {
    return ((x[ind2] - x[ind0]) * (y[ind1] - y[ind0]) -
        (y[ind2] - y[ind0]) * (x[ind1] - x[ind0]));
}

pub inline fn edgeFun3(x0: F, y0: F, x1: F, y1: F, px: F, py: F) F {
    return (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0);
}

pub inline fn edgeFun3SIMD(
    x0: F,
    y0: F,
    x1: F,
    y1: F,
    v_px: buildconfig.VecSF,
    v_py: buildconfig.VecSF,
) buildconfig.VecSF {
    const v_x0: buildconfig.VecSF = @splat(x0);
    const v_y0: buildconfig.VecSF = @splat(y0);
    const v_x1: buildconfig.VecSF = @splat(x1);
    const v_y1: buildconfig.VecSF = @splat(y1);
    return (v_px - v_x0) * (v_y1 - v_y0) - (v_py - v_y0) * (v_x1 - v_x0);
}
