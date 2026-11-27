// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const matstack = @import("matstack.zig");
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

/// Intrinsic Z-Y-X Euler rotation in radians, with a cached 3×3 matrix
/// `Rz(alpha_z) * Ry(beta_y) * Rx(gamma_x)`. Use `init` to initialise
/// the matrix, and call `calcRotMat` after changing the angles.
pub const Rotation = struct {
    /// First rotation, about Z, in radians.
    alpha_z: F = 0.0,
    /// Second rotation, about the rotated Y axis, in radians.
    beta_y: F = 0.0,
    /// Third rotation, about the rotated X axis, in radians.
    gamma_x: F = 0.0,
    /// Row-major matrix that applies the rotation by multiplying a column vector.
    matrix: matstack.Mat33F = undefined,

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

    pub fn fromMat33(mat: matstack.Mat33F) Rotation {
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
