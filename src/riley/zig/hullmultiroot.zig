// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("hullmultiroot_common.zig");
const impl = if (cfg.simd == .on)
    @import("hullmultiroot_simd.zig")
else
    @import("hullmultiroot_scalar.zig");
const simd_impl = @import("hullmultiroot_simd.zig");

pub const HullMultiRoot = struct {
    pub const HullEdge = @import("hulledge.zig").HullEdge;
    pub const Points = common.Points;
    pub const BezierLeaf = common.BezierLeaf;
    pub const buildPointsFromClip = common.buildPointsFromClip;
    pub const prepareEdgeSlack = common.prepareEdgeSlack;
    pub const contains = common.containsPolygon;
    pub const containsPrepared = common.containsPrepared;
    pub const containsEdges = common.containsEdges;
    pub const prepareEdges = impl.prepareEdges;
    pub const prepareFourBezierLeaves = impl.prepareFourBezierLeaves;
    pub const containsOuter = impl.containsOuter;
    pub const childMask = impl.childMask;
    pub const containsOuterSIMD = simd_impl.containsOuterSIMD;
    pub const childMasksSIMD = simd_impl.childMasksSIMD;
};
