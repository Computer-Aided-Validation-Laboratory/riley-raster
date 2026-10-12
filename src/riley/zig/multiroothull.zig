// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const cfg = @import("buildconfig.zig").config;
const common = @import("multiroothull_common.zig");
const impl = if (cfg.simd == .on)
    @import("multiroothull_simd.zig")
else
    @import("multiroothull_scalar.zig");
const simd_impl = @import("multiroothull_simd.zig");

pub const MultiRootHull = struct {
    pub const Points = common.Points;
    pub const BezierLeaf = common.MultiRootHull.BezierLeaf;
    pub const buildPointsFromClip = common.MultiRootHull.buildPointsFromClip;
    pub const prepareEdgeSlack = common.MultiRootHull.prepareEdgeSlack;
    pub const contains = common.MultiRootHull.contains;
    pub const containsPrepared = common.MultiRootHull.containsPrepared;
    pub const containsEdges = common.MultiRootHull.containsEdges;
    pub const prepareEdges = impl.prepareEdges;
    pub const prepareFourBezierLeaves = impl.prepareFourBezierLeaves;
    pub const containsOuter = impl.containsOuter;
    pub const childMask = impl.childMask;
    pub const containsOuterSIMD = simd_impl.containsOuterSIMD;
    pub const childMasksSIMD = simd_impl.childMasksSIMD;
};
