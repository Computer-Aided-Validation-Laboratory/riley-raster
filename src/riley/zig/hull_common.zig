// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const F = @import("buildconfig.zig").F;

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
