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
    pub const HullPolyPreCalc = common.HullPolyPreCalc;
    pub const HullPolyOnTheFly = common.HullPolyOnTheFly;
    pub const BezierLeafPreCalc = common.BezierLeafPreCalc;
    pub const BezierLeafOnTheFly = common.BezierLeafOnTheFly;
    pub const PrepareEdgesFn = common.PrepareEdgesFn;
    pub const buildPointsFromClip = common.buildPointsFromClip;
    pub const calcEdgeTol = common.calcEdgeTol;

    pub const prepareEdgesScalar = common.prepareEdgesScalar;
    pub const prepareEdgesSIMD = simd_impl.prepareEdgesSIMD;
    pub const prepareEdges = if (cfg.simd == .on)
        simd_impl.prepareEdgesSIMD
    else
        common.prepareEdgesScalar;

    pub const prepareFourBezierLeavesPreCalcScalar =
        common.prepareFourBezierLeavesPreCalcScalar;
    pub const prepareFourBezierLeavesPreCalcSIMD =
        simd_impl.prepareFourBezierLeavesPreCalcSIMD;
    pub const prepareFourBezierLeavesPreCalc = if (cfg.simd == .on)
        simd_impl.prepareFourBezierLeavesPreCalcSIMD
    else
        common.prepareFourBezierLeavesPreCalcScalar;

    pub const prepareFourBezierLeavesOnTheFlyScalar =
        common.prepareFourBezierLeavesOnTheFlyScalar;
    pub const prepareFourBezierLeavesOnTheFlySIMD =
        simd_impl.prepareFourBezierLeavesOnTheFlySIMD;
    pub const prepareFourBezierLeavesOnTheFly = if (cfg.simd == .on)
        simd_impl.prepareFourBezierLeavesOnTheFlySIMD
    else
        common.prepareFourBezierLeavesOnTheFlyScalar;

    pub const containsPreCalcScalar = common.containsPreCalcScalar;
    pub const containsPreCalcSIMD = simd_impl.containsPreCalcSIMD;

    pub const containsOnTheFlyScalar = common.containsOnTheFlyScalar;
    pub const containsOnTheFlySIMD = simd_impl.containsOnTheFlySIMD;

    pub const childMaskPreCalcScalar = common.childMaskPreCalcScalar;
    pub const childMaskPreCalcSIMD = simd_impl.childMaskPreCalcSIMD;

    pub const childMaskOnTheFlyScalar = common.childMaskOnTheFlyScalar;
    pub const childMaskOnTheFlySIMD = simd_impl.childMaskOnTheFlySIMD;
};
