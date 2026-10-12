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
const cfg = buildconfig.config;
const tol = cfg.tol;
const rops = @import("rasterops.zig");
const HullEdge = @import("hulledge.zig").HullEdge;
const EdgeFunMode = @import("rasterconfig.zig").EdgeFunMode;
const MultiRootHull = @import("multiroothull_common.zig").MultiRootHull;
const cam = @import("camera.zig");

pub fn prepareEdges(x: []const F, y: []const F, edges: []HullEdge) void {
    MultiRootHull.prepareEdges(x, y, edges);
}

pub fn containsOuter(
    x: []const F,
    y: []const F,
    edges: []const HullEdge,
    slack: []const F,
    px: F,
    py: F,
    mode: EdgeFunMode,
) bool {
    return if (mode == .pre_calc)
        MultiRootHull.containsEdges(edges, px, py)
    else
        MultiRootHull.containsPrepared(x, y, slack, px, py);
}

pub fn childMask(leaves: anytype, px: F, py: F, mode: EdgeFunMode) u8 {
    var mask: u8 = 0;
    for (leaves, 0..) |*leaf, ii| {
        if (px < leaf.bbox[0] or px > leaf.bbox[1] or
            py < leaf.bbox[2] or py > leaf.bbox[3]) continue;
        const count = leaf.vertex_count;

        if (containsOuter(
            leaf.hull_x[0..count],
            leaf.hull_y[0..count],
            leaf.prepared_edges[0..count],
            leaf.edge_slack[0..count],
            px,
            py,
            mode,
        )) mask |= @as(u8, 1) << @as(u3, @intCast(ii));
    }

    return mask;
}

pub fn prepareFourBezierLeaves(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    output: *[4]MultiRootHull.BezierLeaf,
    edge_fun_mode: EdgeFunMode,
) void {
    MultiRootHull.prepareFourBezierLeaves(
        N,
        camera,
        coords,
        output,
        edge_fun_mode,
        prepareEdges,
    );
}
