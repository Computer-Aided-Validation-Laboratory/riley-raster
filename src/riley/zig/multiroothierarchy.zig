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

pub const max_depth: u8 = 3;
pub const max_leaves: usize = 64;

pub const Leaf = struct {
    hull_x: [9]F,
    hull_y: [9]F,
    edge_slack: [9]F,
    bbox: [4]F,
    seed: [2]F,
    region_origin: [2]F,
    region_axis_u: [2]F,
    region_axis_v: [2]F,
    hull_count: u8,
    depth: u8,

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

    pub fn containsParent(self: *const @This(), comptime N: usize, xi: F, eta: F) bool {
        const du = xi - self.region_origin[0];
        const dv = eta - self.region_origin[1];
        const det = self.region_axis_u[0] * self.region_axis_v[1] -
            self.region_axis_u[1] * self.region_axis_v[0];
        const u = (du * self.region_axis_v[1] - dv * self.region_axis_v[0]) / det;
        const v = (dv * self.region_axis_u[0] - du * self.region_axis_u[1]) / det;
        const slack: F = 1e-10;
        if (N == 6) {
            return u >= -slack and v >= -slack and u + v <= 1 + slack;
        }
        return @abs(u) <= 1 + slack and @abs(v) <= 1 + slack;
    }
};

pub const Mode = enum {
    fixed4,
    fixed16,
    adaptive,
};

pub const SeedMethod = enum {
    center,
    front_near,
    front_strong,
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
    parent: Region,
    child_idx: usize,
) Region {
    if (comptime N == 6) {
        const local = [4]Region{
            .{ .origin = .{ 0, 0 }, .axis_u = .{ 0.5, 0 }, .axis_v = .{ 0, 0.5 } },
            .{ .origin = .{ 0.5, 0 }, .axis_u = .{ 0.5, 0 }, .axis_v = .{ 0, 0.5 } },
            .{ .origin = .{ 0, 0.5 }, .axis_u = .{ 0.5, 0 }, .axis_v = .{ 0, 0.5 } },
            .{ .origin = .{ 0.5, 0 }, .axis_u = .{ 0, 0.5 }, .axis_v = .{ -0.5, 0.5 } },
        };
        const region = local[child_idx];
        const origin = mapped(parent, region.origin);
        return .{
            .origin = origin,
            .axis_u = .{
                parent.axis_u[0] * region.axis_u[0] +
                    parent.axis_v[0] * region.axis_u[1],
                parent.axis_u[1] * region.axis_u[0] +
                    parent.axis_v[1] * region.axis_u[1],
            },
            .axis_v = .{
                parent.axis_u[0] * region.axis_v[0] +
                    parent.axis_v[0] * region.axis_v[1],
                parent.axis_u[1] * region.axis_v[0] +
                    parent.axis_v[1] * region.axis_v[1],
            },
        };
    }
    const u: F = if (child_idx % 2 == 0) -0.5 else 0.5;
    const v: F = if (child_idx < 2) -0.5 else 0.5;
    return .{
        .origin = mapped(parent, .{ u, v }),
        .axis_u = .{ parent.axis_u[0] * 0.5, parent.axis_u[1] * 0.5 },
        .axis_v = .{ parent.axis_v[0] * 0.5, parent.axis_v[1] * 0.5 },
    };
}

fn makeLeaf(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    region: Region,
    depth: u8,
    seed_method: SeedMethod,
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
        .bbox = .{ std.math.inf(F), -std.math.inf(F), std.math.inf(F), -std.math.inf(F) },
        .seed = mapped(
            region,
            if (N == 6) .{ 1.0 / 3.0, 1.0 / 3.0 } else .{ 0, 0 },
        ),
        .region_origin = region.origin,
        .region_axis_u = region.axis_u,
        .region_axis_v = region.axis_v,
        .hull_count = projected.count,
        .depth = depth,
    };
    if (seed_method != .center) {
        const local_samples = if (N == 6)
            [9][2]F{
                .{ 1.0 / 3.0, 1.0 / 3.0 },
                .{ 0.03, 0.485 },
                .{ 0.485, 0.03 },
                .{ 0.485, 0.485 },
                .{ 0.03, 0.03 },
                .{ 0.94, 0.03 },
                .{ 0.03, 0.94 },
                .{ 0.25, 0.25 },
                .{ 0.5, 0.25 },
            }
        else
            [9][2]F{
                .{ 0, 0 },
                .{ -0.9, -0.9 },
                .{ 0.9, -0.9 },
                .{ 0.9, 0.9 },
                .{ -0.9, 0.9 },
                .{ 0, -0.9 },
                .{ 0.9, 0 },
                .{ 0, 0.9 },
                .{ -0.9, 0 },
            };
        var local_coords = coords;
        const nodes = rops.Vec3Slices(F){
            .x = &local_coords.x,
            .y = &local_coords.y,
            .z = &local_coords.z,
        };
        var best_score = -std.math.inf(F);
        for (local_samples) |local_uv| {
            const uv = mapped(region, local_uv);
            const facing = rops.projectedJacDetPhysical(
                N,
                nodes,
                uv[0],
                uv[1],
            );
            if (!std.math.isFinite(facing) or facing >=
                -buildconfig.config.tol.culling.projected_jacobian_abs)
            {
                continue;
            }
            const score = if (seed_method == .front_strong)
                -facing
            else blk: {
                var weights: [N]F = undefined;
                var du: [N]F = undefined;
                var dv: [N]F = undefined;
                shapefun.shapeFunc(N, uv[0], uv[1], &weights, &du, &dv);
                var z: F = 0;
                for (0..N) |nn| z += weights[nn] * coords.z[nn];
                break :blk if (std.math.isFinite(z) and z > 0)
                    -z
                else
                    -std.math.inf(F);
            };
            if (score <= best_score) continue;
            best_score = score;
            leaf.seed = uv;
        }
    }
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

fn appendLeaves(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    region: Region,
    depth: u8,
    mode: Mode,
    adaptive_depth: u8,
    stop_px: F,
    seed_method: SeedMethod,
    output: []Leaf,
    count: *usize,
) void {
    const target_depth: u8 = switch (mode) {
        .fixed4 => 1,
        .fixed16 => 2,
        .adaptive => adaptive_depth,
    };
    const need_leaf = mode == .adaptive or depth == target_depth;
    const leaf = if (need_leaf)
        makeLeaf(N, camera, coords, region, depth, seed_method)
    else
        undefined;
    const stop_adaptive = mode == .adaptive and depth >= 1 and
        @max(leaf.bbox[1] - leaf.bbox[0], leaf.bbox[3] - leaf.bbox[2]) <= stop_px;
    if (depth == target_depth or stop_adaptive) {
        std.debug.assert(count.* < output.len);
        output[count.*] = leaf;
        count.* += 1;
        return;
    }
    for (0..4) |ii| {
        appendLeaves(
            N,
            camera,
            coords,
            childRegion(N, region, ii),
            depth + 1,
            mode,
            adaptive_depth,
            stop_px,
            seed_method,
            output,
            count,
        );
    }
}

/// Exact FE restriction under affine parent-space subdivision; the child
/// control-net hulls enclose their projected patches for positive depth.
pub fn prepare(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    mode: Mode,
    adaptive_depth: u8,
    stop_px: F,
    output: []Leaf,
) usize {
    return prepareWithSeedMethod(
        N,
        camera,
        coords,
        mode,
        adaptive_depth,
        stop_px,
        .center,
        output,
    );
}

pub fn prepareWithSeedMethod(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    mode: Mode,
    adaptive_depth: u8,
    stop_px: F,
    seed_method: SeedMethod,
    output: []Leaf,
) usize {
    std.debug.assert(adaptive_depth >= 1 and adaptive_depth <= max_depth);
    var count: usize = 0;
    appendLeaves(
        N,
        camera,
        coords,
        .{ .origin = .{ 0, 0 }, .axis_u = .{ 1, 0 }, .axis_v = .{ 0, 1 } },
        0,
        mode,
        adaptive_depth,
        stop_px,
        seed_method,
        output,
        &count,
    );
    return count;
}
