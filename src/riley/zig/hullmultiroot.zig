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
const simd_impl = @import("hullmultiroot_simd.zig");

pub const HullMultiRoot = struct {
    pub const HullEdge = @import("hulledge.zig").HullEdge;
    pub const Points = common.Points;
    pub const BezierLeaf = common.BezierLeaf;
    pub const PrepareEdgesFn = common.PrepareEdgesFn;
    pub const buildPointsFromClip = common.buildPointsFromClip;
    pub const prepareEdgeSlack = common.prepareEdgeSlack;

    pub const prepareEdgesScalar = common.prepareEdgesScalar;
    pub const prepareEdgesSIMD = simd_impl.prepareEdgesSIMD;
    pub const prepareEdges = if (cfg.simd == .on)
        simd_impl.prepareEdgesSIMD
    else
        common.prepareEdgesScalar;

    pub const prepareFourBezierLeavesScalar = common.prepareFourBezierLeavesScalar;
    pub const prepareFourBezierLeavesSIMD = simd_impl.prepareFourBezierLeavesSIMD;
    pub const prepareFourBezierLeaves = if (cfg.simd == .on)
        simd_impl.prepareFourBezierLeavesSIMD
    else
        common.prepareFourBezierLeavesScalar;

    pub const containsPreCalc = common.containsPreCalc;
    pub const containsOnTheFly = common.containsOnTheFly;
    pub const containsScalar = common.containsScalar;
    pub const containsSIMD = simd_impl.containsSIMD;

    pub const childMaskScalar = common.childMaskScalar;
    pub const childMaskSIMD = simd_impl.childMaskSIMD;
};
