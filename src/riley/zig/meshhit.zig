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
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;
const ndarray = @import("ndarray.zig");

pub const MeshHitField = enum { coords_ref, coords_def, surf_norm };
pub const MeshHitSelection = std.EnumSet(MeshHitField);

// Culled element-node geometry shared by every shader selected for a mesh frame.
pub const MeshHitGeomPrepared = struct {
    selection: MeshHitSelection = MeshHitSelection.initEmpty(),
    coords_ref: ?ndarray.NDArray(F) = null,
    coords_def: ?ndarray.NDArray(F) = null,
    surf_norm: ?ndarray.MappedNDArray(F) = null,
};

// The data every shader needs to interpolate its own nodal fields or UVs.
pub fn RasterHit(comptime N: usize) type {
    return struct {
        weights: [N]F,
        nodes_inv_z: [N]F,
        sub_pixel_z: F,
        xi: F,
        eta: F,
    };
}

// A raster hit with optional mesh geometry for function shaders and pipes.
pub fn MeshHit(comptime N: usize) type {
    return struct {
        weights: [N]F,
        nodes_inv_z: [N]F,
        sub_pixel_z: F,
        xi: F,
        eta: F,
        coords_ref: ?[3]F = null,
        coords_def: ?[3]F = null,
        surf_norm: ?[3]F = null,

        pub inline fn core(self: @This()) RasterHit(N) {
            return .{
                .weights = self.weights,
                .nodes_inv_z = self.nodes_inv_z,
                .sub_pixel_z = self.sub_pixel_z,
                .xi = self.xi,
                .eta = self.eta,
            };
        }
    };
}

// Optional geometry across SIMD sample lanes; core SIMD data stays in raster vectors.
pub const MeshHitGeomSIMD = struct {
    coords_ref: ?[3]VecSF = null,
    coords_def: ?[3]VecSF = null,
    surf_norm: ?[3]VecSF = null,
};

pub inline fn interpCoordsSIMD(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    values: *const [3 * N]F,
    mask: VecSB,
    weights: [N]VecSF,
    nodes_inv_z: [N]VecSF,
    subpx_z: VecSF,
) [3]VecSF {
    const zero: VecSF = @splat(0);
    var result: [3]VecSF = @splat(zero);
    inline for (0..3) |cc| {
        inline for (0..N) |nn| {
            const weight = @select(F, mask, weights[nn], zero);
            const value: VecSF = @splat(values[cc * N + nn]);
            result[cc] += if (comptime coord_space == .raster)
                weight * value * @select(F, mask, nodes_inv_z[nn], zero)
            else
                weight * value;
        }
        if (comptime coord_space == .raster) {
            result[cc] *= @select(F, mask, subpx_z, zero);
        }
    }
    return result;
}

pub inline fn interpCoords(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    values: *const [3 * N]F,
    hit: MeshHit(N),
) [3]F {
    var result: [3]F = @splat(0);
    inline for (0..3) |cc| {
        inline for (0..N) |nn| {
            const value = values[cc * N + nn];
            result[cc] += if (comptime coord_space == .raster)
                hit.weights[nn] * value * hit.nodes_inv_z[nn]
            else
                hit.weights[nn] * value;
        }
        if (comptime coord_space == .raster) result[cc] *= hit.sub_pixel_z;
    }
    return result;
}
