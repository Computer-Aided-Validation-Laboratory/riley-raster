// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const hullmultiroot_common = @import("hullmultiroot_common.zig");
const hullmultiroot_simd = @import("hullmultiroot_simd.zig");

pub const HullMultiRoot = struct {
    pub const HullEdge = @import("hulledge.zig").HullEdge;
    pub const Points = hullmultiroot_common.Points;
    pub const HullPolyPreCalc = hullmultiroot_common.HullPolyPreCalc;
    pub const HullPolyOnTheFly = hullmultiroot_common.HullPolyOnTheFly;
    pub const BezierLeafPreCalc = hullmultiroot_common.BezierLeafPreCalc;
    pub const BezierLeafOnTheFly = hullmultiroot_common.BezierLeafOnTheFly;
    pub const PrepareEdgesFn = hullmultiroot_common.PrepareEdgesFn;
    pub const buildPointsFromClip = hullmultiroot_common.buildPointsFromClip;
    pub const calcEdgeTol = hullmultiroot_common.calcEdgeTol;

    pub const prepareEdgesScalar = hullmultiroot_common.prepareEdgesScalar;
    pub const prepareEdgesSIMD = hullmultiroot_simd.prepareEdgesSIMD;
    pub const prepareEdges = if (cfg.simd == .on)
        hullmultiroot_simd.prepareEdgesSIMD
    else
        hullmultiroot_common.prepareEdgesScalar;

    pub const prepareFourBezierLeavesPreCalcScalar =
        hullmultiroot_common.prepareFourBezierLeavesPreCalcScalar;
    pub const prepareFourBezierLeavesPreCalcSIMD =
        hullmultiroot_simd.prepareFourBezierLeavesPreCalcSIMD;
    pub const prepareFourBezierLeavesPreCalc = if (cfg.simd == .on)
        hullmultiroot_simd.prepareFourBezierLeavesPreCalcSIMD
    else
        hullmultiroot_common.prepareFourBezierLeavesPreCalcScalar;

    pub const prepareFourBezierLeavesOnTheFlyScalar =
        hullmultiroot_common.prepareFourBezierLeavesOnTheFlyScalar;
    pub const prepareFourBezierLeavesOnTheFlySIMD =
        hullmultiroot_simd.prepareFourBezierLeavesOnTheFlySIMD;
    pub const prepareFourBezierLeavesOnTheFly = if (cfg.simd == .on)
        hullmultiroot_simd.prepareFourBezierLeavesOnTheFlySIMD
    else
        hullmultiroot_common.prepareFourBezierLeavesOnTheFlyScalar;

    pub const containsPreCalcScalar = hullmultiroot_common.containsPreCalcScalar;
    pub const containsPreCalcSIMD = hullmultiroot_simd.containsPreCalcSIMD;

    pub const containsOnTheFlyScalar = hullmultiroot_common.containsOnTheFlyScalar;
    pub const containsOnTheFlySIMD = hullmultiroot_simd.containsOnTheFlySIMD;

    pub const childMaskPreCalcScalar = hullmultiroot_common.childMaskPreCalcScalar;
    pub const childMaskPreCalcSIMD = hullmultiroot_simd.childMaskPreCalcSIMD;

    pub const childMaskOnTheFlyScalar = hullmultiroot_common.childMaskOnTheFlyScalar;
    pub const childMaskOnTheFlySIMD = hullmultiroot_simd.childMaskOnTheFlySIMD;
};
