// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const print = std.debug.print;
const expectEqual = std.testing.expectEqual;
const buildconfig = @import("buildconfig.zig");
const Mat33f = @import("matstack.zig").Mat33f;
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const Rotation = struct {
    alpha_z: F = 0.0,
    beta_y: F = 0.0,
    gamma_x: F = 0.0,
    matrix: Mat33f = undefined,

    const Self = @This();

    // const rows_n: usize = 3;
    // const cols_n: usize = 3;

    pub fn init(alpha_z: F, beta_y: F, gamma_x: F) Rotation {
        var rot = Rotation{ .alpha_z = alpha_z, .beta_y = beta_y, .gamma_x = gamma_x };
        rot.calcRotMat();
        return rot;
    }

    pub fn calcRotMat(self: *Rotation) void {
        // NOTE: this is equivalent to ZYX for intrinsic (one after the other)
        // not zyx which is extrinsic (all rel to global)

        // Row major as in C
        // Row 1
        self.matrix.set(0, 0, @cos(self.alpha_z) * @cos(self.beta_y));
        self.matrix.set(0, 1, @cos(self.alpha_z) * @sin(self.beta_y) *
            @sin(self.gamma_x) - @sin(self.alpha_z) *
            @cos(self.gamma_x));
        self.matrix.set(0, 2, @cos(self.alpha_z) * @sin(self.beta_y) *
            @cos(self.gamma_x) + @sin(self.alpha_z) *
            @sin(self.gamma_x));
        // Row 2
        self.matrix.set(1, 0, @sin(self.alpha_z) * @cos(self.beta_y));
        self.matrix.set(1, 1, @sin(self.alpha_z) * @sin(self.beta_y) *
            @sin(self.gamma_x) + @cos(self.alpha_z) *
            @cos(self.gamma_x));
        self.matrix.set(1, 2, @sin(self.alpha_z) * @sin(self.beta_y) *
            @cos(self.gamma_x) - @cos(self.alpha_z) *
            @sin(self.gamma_x));
        // Row 3
        self.matrix.set(2, 0, -@sin(self.beta_y));
        self.matrix.set(2, 1, @cos(self.beta_y) * @sin(self.gamma_x));
        self.matrix.set(2, 2, @cos(self.beta_y) * @cos(self.gamma_x));
    }

    pub fn matPrint(self: *const Rotation) void {
        self.matrix.matPrint();
    }

    pub fn fromMat33(mat: Mat33f) Rotation {
        const r20 = mat.get(2, 0);
        const r21 = mat.get(2, 1);
        const r22 = mat.get(2, 2);
        const r10 = mat.get(1, 0);
        const r00 = mat.get(0, 0);

        const beta = std.math.asin(-r20);
        const cos_beta = @cos(beta);

        var alpha: F = 0.0;
        var gamma: F = 0.0;

        if (@abs(cos_beta) > 1e-6) {
            alpha = std.math.atan2(r10, r00);
            gamma = std.math.atan2(r21, r22);
        } else {
            gamma = std.math.atan2(-mat.get(0, 1), mat.get(1, 1));
        }

        return Rotation.init(alpha, beta, gamma);
    }
};
