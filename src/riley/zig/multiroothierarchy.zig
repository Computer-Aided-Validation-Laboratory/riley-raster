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
const cam = @import("camera.zig");
const gk = @import("geometrykernels.zig");
const hull = @import("hull.zig");
const rops = @import("rasterops.zig");
const shapefun = @import("shapefun.zig");

pub const Leaf = struct {
    hull_x: [9]F,
    hull_y: [9]F,
    edge_slack: [9]F,
    bbox: [4]F,
    seed: [2]F,
    hull_count: u8,

    pub fn contains(self: *const @This(), px: F, py: F) bool {
        if (px < self.bbox[0] or px > self.bbox[1] or
            py < self.bbox[2] or py > self.bbox[3]) return false;
        return hull.containsMultiRootHullPrepared(
            self.hull_x[0..self.hull_count],
            self.hull_y[0..self.hull_count],
            self.edge_slack[0..self.hull_count],
            px,
            py,
        );
    }
};

const Region = struct {
    origin: [2]F,
    axis_u: [2]F,
    axis_v: [2]F,
};

fn mapped(region: Region, uv: [2]F) [2]F {
    return .{
        region.origin[0] + region.axis_u[0] * uv[0] +
            region.axis_v[0] * uv[1],
        region.origin[1] + region.axis_u[1] * uv[0] +
            region.axis_v[1] * uv[1],
    };
}

fn childRegion(
    comptime N: usize,
    child_idx: usize,
) Region {
    if (comptime N == 6) {
        const local = [4]Region{
            .{
                .origin = .{ 0, 0 },
                .axis_u = .{ 0.5, 0 },
                .axis_v = .{ 0, 0.5 },
            },
            .{
                .origin = .{ 0.5, 0 },
                .axis_u = .{ 0.5, 0 },
                .axis_v = .{ 0, 0.5 },
            },
            .{
                .origin = .{ 0, 0.5 },
                .axis_u = .{ 0.5, 0 },
                .axis_v = .{ 0, 0.5 },
            },
            .{
                .origin = .{ 0.5, 0 },
                .axis_u = .{ 0, 0.5 },
                .axis_v = .{ -0.5, 0.5 },
            },
        };
        return local[child_idx];
    }
    const u: F = if (child_idx % 2 == 0) -0.5 else 0.5;
    const v: F = if (child_idx < 2) -0.5 else 0.5;
    return .{
        .origin = .{ u, v },
        .axis_u = .{ 0.5, 0 },
        .axis_v = .{ 0, 0.5 },
    };
}

fn makeLeaf(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    region: Region,
) Leaf {
    const parents = comptime gk.parentNodeCoords(N);
    var child: rops.GatheredElemCoords(N) = undefined;
    for (parents, 0..) |node_uv, ii| {
        const uv = mapped(region, node_uv);
        var weights: [N]F = undefined;
        var du: [N]F = undefined;
        var dv: [N]F = undefined;
        shapefun.shapeFunc(N, uv[0], uv[1], &weights, &du, &dv);
        child.x[ii] = 0;
        child.y[ii] = 0;
        child.z[ii] = 0;
        for (0..N) |nn| {
            child.x[ii] += weights[nn] * coords.x[nn];
            child.y[ii] += weights[nn] * coords.y[nn];
            child.z[ii] += weights[nn] * coords.z[nn];
        }
    }
    const projected = hull.buildMultiRootHullFromClip(N, camera, child);
    var leaf = Leaf{
        .hull_x = projected.x,
        .hull_y = projected.y,
        .edge_slack = undefined,
        .bbox = .{
            std.math.inf(F),
            -std.math.inf(F),
            std.math.inf(F),
            -std.math.inf(F),
        },
        .seed = mapped(
            region,
            if (N == 6) .{ 1.0 / 3.0, 1.0 / 3.0 } else .{ 0, 0 },
        ),
        .hull_count = projected.count,
    };
    hull.prepareMultiRootEdgeSlack(
        leaf.hull_x[0..leaf.hull_count],
        leaf.hull_y[0..leaf.hull_count],
        leaf.edge_slack[0..leaf.hull_count],
    );
    var max_slack: F = 0;
    for (0..leaf.hull_count) |ii| {
        leaf.bbox[0] = @min(leaf.bbox[0], leaf.hull_x[ii]);
        leaf.bbox[1] = @max(leaf.bbox[1], leaf.hull_x[ii]);
        leaf.bbox[2] = @min(leaf.bbox[2], leaf.hull_y[ii]);
        leaf.bbox[3] = @max(leaf.bbox[3], leaf.hull_y[ii]);
        max_slack = @max(max_slack, leaf.edge_slack[ii]);
    }
    leaf.bbox[0] -= max_slack;
    leaf.bbox[1] += max_slack;
    leaf.bbox[2] -= max_slack;
    leaf.bbox[3] += max_slack;
    return leaf;
}

pub fn prepareFixed4(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    output: *[4]Leaf,
) void {
    for (0..4) |ii| {
        const region = childRegion(N, ii);
        output[ii] = makeLeaf(N, camera, coords, region);
    }
}
