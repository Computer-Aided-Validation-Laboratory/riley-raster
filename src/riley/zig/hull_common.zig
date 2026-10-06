// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const rops = @import("rasterops.zig");
const cam = @import("camera.zig");
const db = @import("distortbounds.zig");
const rastcfg = @import("rasterconfig.zig");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;

const tol = buildconfig.config.tol;

// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn AdaptiveHullPoints(comptime N: usize) type {
    const NH = blk: {
        for (std.enums.values(MeshType)) |mt| {
            if (mt.getNodesNum() == N) {
                if (mt == .tri3) break :blk 0;
                break :blk mt.getNumHullPoints();
            }
        }
        break :blk 0;
    };

    return struct {
        x: [NH]F,
        y: [NH]F,
    };
}

pub const MultiRootHull = struct {
    x: [9]F = undefined,
    y: [9]F = undefined,
    count: u8 = 0,

    pub fn contains(self: *const @This(), px: F, py: F) bool {
        return containsMultiRootHull(
            self.x[0..self.count],
            self.y[0..self.count],
            px,
            py,
        );
    }
};

pub fn containsMultiRootHull(x: []const F, y: []const F, px: F, py: F) bool {
    if (x.len < 3) return false;
    var edge_slack: [9]F = undefined;
    prepareMultiRootEdgeSlack(x, y, edge_slack[0..x.len]);
    return containsMultiRootHullPrepared(x, y, edge_slack[0..x.len], px, py);
}

pub fn prepareMultiRootEdgeSlack(x: []const F, y: []const F, slack: []F) void {
    for (0..x.len) |ii| {
        const jj = (ii + 1) % x.len;
        const dx = x[jj] - x[ii];
        const dy = y[jj] - y[ii];
        slack[ii] = tol.hull.scal_inclusion * @sqrt(dx * dx + dy * dy);
    }
}

pub fn containsMultiRootHullPrepared(
    x: []const F,
    y: []const F,
    slack: []const F,
    px: F,
    py: F,
) bool {
    if (x.len < 3) return false;
    for (0..x.len) |ii| {
        const jj = (ii + 1) % x.len;
        const edge = rops.edgeFun3(
            x[ii],
            y[ii],
            x[jj],
            y[jj],
            px,
            py,
        );
        if (edge < -slack[ii]) {
            return false;
        }
    }
    return true;
}

const HullPoint = struct {
    x: F,
    y: F,
};

fn cross2(a: HullPoint, b: HullPoint, c: HullPoint) F {
    return (b.x - a.x) * (c.y - a.y) -
        (b.y - a.y) * (c.x - a.x);
}

fn sortPoints(points: []HullPoint) void {
    for (1..points.len) |ii| {
        const value = points[ii];
        var jj = ii;
        while (jj > 0 and (points[jj - 1].x > value.x or
            (points[jj - 1].x == value.x and points[jj - 1].y > value.y)))
        {
            points[jj] = points[jj - 1];
            jj -= 1;
        }
        points[jj] = value;
    }
}

fn hullFromPoints(points_in: []const HullPoint) MultiRootHull {
    var points: [9]HullPoint = undefined;
    @memcpy(points[0..points_in.len], points_in);
    sortPoints(points[0..points_in.len]);

    var chain: [18]HullPoint = undefined;
    var count: usize = 0;
    for (points[0..points_in.len]) |point| {
        while (count >= 2 and cross2(chain[count - 2], chain[count - 1], point) <= 0) {
            count -= 1;
        }
        chain[count] = point;
        count += 1;
    }
    const lower_count = count;
    var ii = points_in.len;
    while (ii > 0) {
        ii -= 1;
        const point = points[ii];
        while (count > lower_count and
            cross2(chain[count - 2], chain[count - 1], point) <= 0)
        {
            count -= 1;
        }
        chain[count] = point;
        count += 1;
    }
    if (count > 1) count -= 1;

    var result = MultiRootHull{};
    if (count < 3) {
        const pad: F = 0.5;
        const min_x = points[0].x - pad;
        const max_x = points[points_in.len - 1].x + pad;
        var min_y = points[0].y;
        var max_y = min_y;
        for (points_in) |point| {
            min_y = @min(min_y, point.y);
            max_y = @max(max_y, point.y);
        }
        result.x[0..4].* = .{ min_x, min_x, max_x, max_x };
        result.y[0..4].* = .{ min_y - pad, max_y + pad, max_y + pad, min_y - pad };
        result.count = 4;
        return result;
    }
    // edgeFun3 has the opposite sign to the standard cross product.
    for (0..count) |nn| {
        const point = chain[count - 1 - nn];
        result.x[nn] = point.x;
        result.y[nn] = point.y;
    }
    result.count = @intCast(count);
    return result;
}

fn rectHull(bounds: db.DistortBounds) MultiRootHull {
    return .{
        .x = [_]F{ bounds.x_min, bounds.x_min, bounds.x_max, bounds.x_max } ++
            [_]F{0} ** 5,
        .y = [_]F{ bounds.y_min, bounds.y_max, bounds.y_max, bounds.y_min } ++
            [_]F{0} ** 5,
        .count = 4,
    };
}

fn controlNet(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
) rops.GatheredElemCoords(if (N == 8) 9 else N) {
    const K = if (N == 8) 9 else N;
    var controls: rops.GatheredElemCoords(K) = undefined;
    if (N == 4) {
        controls = coords;
        return controls;
    }
    if (N == 6) {
        controls = coords;
        const edges = [3][3]usize{
            .{ 0, 1, 3 }, .{ 1, 2, 4 }, .{ 2, 0, 5 },
        };
        inline for (edges) |edge| {
            const a = edge[0];
            const b = edge[1];
            const mid = edge[2];
            controls.x[mid] = 2 * coords.x[mid] - 0.5 * (coords.x[a] + coords.x[b]);
            controls.y[mid] = 2 * coords.y[mid] - 0.5 * (coords.y[a] + coords.y[b]);
            controls.z[mid] = 2 * coords.z[mid] - 0.5 * (coords.z[a] + coords.z[b]);
        }
        return controls;
    }

    var nodes: rops.GatheredElemCoords(9) = undefined;
    for (0..N) |nn| {
        nodes.x[nn] = coords.x[nn];
        nodes.y[nn] = coords.y[nn];
        nodes.z[nn] = coords.z[nn];
    }
    if (N == 8) {
        inline for (.{ "x", "y", "z" }) |field| {
            const src = &@field(nodes, field);
            src[8] = 0.5 * (src[4] + src[5] + src[6] + src[7]) -
                0.25 * (src[0] + src[1] + src[2] + src[3]);
        }
    }
    const grid = [3][3]usize{ .{ 0, 4, 1 }, .{ 7, 8, 5 }, .{ 3, 6, 2 } };
    const transform = [3][3]F{
        .{ 1, 0, 0 }, .{ -0.5, 2, -0.5 }, .{ 0, 0, 1 },
    };
    for (0..3) |vv| {
        for (0..3) |uu| {
            const out_idx = grid[vv][uu];
            inline for (.{ "x", "y", "z" }) |field| {
                const src = @field(nodes, field);
                var value: F = 0;
                for (0..3) |jj| {
                    for (0..3) |ii| {
                        value += transform[vv][jj] * transform[uu][ii] *
                            src[grid[jj][ii]];
                    }
                }
                @field(controls, field)[out_idx] = value;
            }
        }
    }
    return controls;
}

pub fn buildMultiRootHullFromClip(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
) MultiRootHull {
    const controls = controlNet(N, coords);
    const K = controls.x.len;
    const x_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[1]));
    var points: [K]HullPoint = undefined;
    var all_positive = true;
    for (0..K) |nn| {
        const z = controls.z[nn];
        if (!std.math.isFinite(z) or
            !std.math.isFinite(controls.x[nn]) or
            !std.math.isFinite(controls.y[nn]))
        {
            const bounds: db.DistortBounds = camera.ideal_sensor_bounds orelse .{
                .x_min = 0,
                .x_max = @as(F, @floatFromInt(camera.pixels_num[0])),
                .y_min = 0,
                .y_max = @as(F, @floatFromInt(camera.pixels_num[1])),
            };
            return rectHull(bounds);
        }
        if (z <= tol.culling.projective_z_min) {
            all_positive = false;
            continue;
        }
        points[nn] = .{
            .x = controls.x[nn] / z + x_off,
            .y = controls.y[nn] / z + y_off,
        };
    }
    if (all_positive) return hullFromPoints(&points);

    // A projective linear-fractional coordinate reaches its extrema on the
    // vertices of the positive-depth control polytope clipped at the near
    // plane. All control pairs include every actual polytope edge.
    const near_z = tol.culling.projective_z_min;
    var bounds = db.DistortBounds.initEmpty();
    var has_point = false;
    for (0..K) |ii| {
        if (controls.z[ii] > near_z) {
            bounds.include(points[ii].x, points[ii].y);
            has_point = true;
        }
        for (ii + 1..K) |jj| {
            const zi = controls.z[ii];
            const zj = controls.z[jj];
            if ((zi > near_z) == (zj > near_z)) continue;
            const t = (near_z - zi) / (zj - zi);
            const x = controls.x[ii] + t * (controls.x[jj] - controls.x[ii]);
            const y = controls.y[ii] + t * (controls.y[jj] - controls.y[ii]);
            bounds.include(x / near_z + x_off, y / near_z + y_off);
            has_point = true;
        }
    }
    if (has_point) return rectHull(bounds);
    const sensor: db.DistortBounds = camera.ideal_sensor_bounds orelse .{
        .x_min = 0,
        .x_max = @as(F, @floatFromInt(camera.pixels_num[0])),
        .y_min = 0,
        .y_max = @as(F, @floatFromInt(camera.pixels_num[1])),
    };
    return rectHull(sensor);
}

fn calcCornerMidsideCosTheta(
    cx: F,
    cy: F,
    px: F,
    py: F,
    nx: F,
    ny: F,
) ?F {
    const ax = px - cx;
    const ay = py - cy;
    const bx = nx - cx;
    const by = ny - cy;

    const a_mag_sq = ax * ax + ay * ay;
    const b_mag_sq = bx * bx + by * by;
    if (a_mag_sq <= 0.0 or b_mag_sq <= 0.0) {
        return null;
    }

    const inv_a_mag = 1.0 / @sqrt(a_mag_sq);
    const inv_b_mag = 1.0 / @sqrt(b_mag_sq);
    return (ax * inv_a_mag) * (bx * inv_b_mag) + (ay * inv_a_mag) * (by * inv_b_mag);
}

fn calcBezierCtrlPoint(
    c0x: F,
    c0y: F,
    c1x: F,
    c1y: F,
    mx: F,
    my: F,
) [2]F {
    return .{
        2.0 * mx - 0.5 * (c0x + c1x),
        2.0 * my - 0.5 * (c0y + c1y),
    };
}

fn buildAdaptiveHullTri6(
    lx: *const [6]F,
    ly: *const [6]F,
) AdaptiveHullPoints(6) {
    const edges = [3][3]usize{
        .{ 0, 1, 3 },
        .{ 1, 2, 4 },
        .{ 2, 0, 5 },
    };

    var hull: AdaptiveHullPoints(6) = undefined;
    inline for (edges, 0..) |edge, ii| {
        const p0 = edge[0];
        const p1 = edge[1];
        const pm = edge[2];
        const edge_val = rops.edgeFun3(lx[p0], ly[p0], lx[p1], ly[p1], lx[pm], ly[pm]);

        hull.x[ii * 2] = lx[p0];
        hull.y[ii * 2] = ly[p0];
        if (edge_val < 0) {
            const ctrl = calcBezierCtrlPoint(lx[p0], ly[p0], lx[p1], ly[p1], lx[pm], ly[pm]);
            hull.x[ii * 2 + 1] = ctrl[0];
            hull.y[ii * 2 + 1] = ctrl[1];
        } else {
            hull.x[ii * 2 + 1] = lx[pm];
            hull.y[ii * 2 + 1] = ly[pm];
        }
    }
    return hull;
}

fn buildAdaptiveHullQuad(
    comptime N: usize,
    lx: *const [N]F,
    ly: *const [N]F,
) AdaptiveHullPoints(N) {
    const edges = [4][3]usize{
        .{ 0, 1, 4 },
        .{ 1, 2, 5 },
        .{ 2, 3, 6 },
        .{ 3, 0, 7 },
    };

    var hull: AdaptiveHullPoints(N) = undefined;
    inline for (edges, 0..) |edge, ii| {
        const p0 = edge[0];
        const p1 = edge[1];
        const pm = edge[2];
        const edge_val = rops.edgeFun3(lx[p0], ly[p0], lx[p1], ly[p1], lx[pm], ly[pm]);

        hull.x[ii * 2] = lx[p0];
        hull.y[ii * 2] = ly[p0];
        if (edge_val < 0) {
            const ctrl = calcBezierCtrlPoint(lx[p0], ly[p0], lx[p1], ly[p1], lx[pm], ly[pm]);
            hull.x[ii * 2 + 1] = ctrl[0];
            hull.y[ii * 2 + 1] = ctrl[1];
        } else {
            hull.x[ii * 2 + 1] = lx[pm];
            hull.y[ii * 2 + 1] = ly[pm];
        }
    }
    return hull;
}

fn convexifyHullInPlace(comptime NH: usize, hull_x: *[NH]F, hull_y: *[NH]F) void {
    var ii: usize = 0;
    while (ii < 10) : (ii += 1) {
        var changed = false;
        for (0..NH) |nn| {
            const pp = (nn + NH - 1) % NH;
            const mm = (nn + 1) % NH;

            // Vis elems are CW. For CW: convex is val < 0, concave is val > 0.
            const val = rops.edgeFun3(
                hull_x[pp],
                hull_y[pp],
                hull_x[mm],
                hull_y[mm],
                hull_x[nn],
                hull_y[nn],
            );
            if (val > 0) {
                hull_x[nn] = 0.5 * (hull_x[pp] + hull_x[mm]);
                hull_y[nn] = 0.5 * (hull_y[pp] + hull_y[mm]);
                changed = true;
            }
        }
        if (!changed) break;
    }
}

pub fn buildAdaptiveHullPointsFromClip(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_elem: rops.GatheredElemCoords(N),
    hull_mode: rastcfg.HullMode,
) AdaptiveHullPoints(N) {
    const x_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[1]));

    var lx: [N]F = undefined;
    var ly: [N]F = undefined;
    for (0..N) |nn| {
        lx[nn] = coords_elem.x[nn] / coords_elem.z[nn] + x_off;
        ly[nn] = coords_elem.y[nn] / coords_elem.z[nn] + y_off;
    }

    if (N == 4) {
        var hull: AdaptiveHullPoints(4) = undefined;
        inline for (0..4) |nn| {
            hull.x[nn] = lx[nn];
            hull.y[nn] = ly[nn];
        }
        return hull;
    }

    const cos_lower = @cos(std.math.degreesToRadians(tol.hull.corner_midside_ang_lower_deg));
    const cos_upper = @cos(std.math.degreesToRadians(tol.hull.corner_midside_ang_upper_deg));

    if (N == 6) {
        var hull = buildAdaptiveHullTri6(&lx, &ly);

        if (hull_mode == .on_convex_fallback) {
            const corner_midsides = [3][2]usize{ .{ 5, 3 }, .{ 3, 4 }, .{ 4, 5 } };
            var trigger = false;

            for (corner_midsides, 0..) |mids, nn| {
                const cos_theta = calcCornerMidsideCosTheta(
                    lx[nn],
                    ly[nn],
                    lx[mids[0]],
                    ly[mids[0]],
                    lx[mids[1]],
                    ly[mids[1]],
                ) orelse -2.0;
                if (cos_theta >= cos_lower or cos_theta <= cos_upper) {
                    trigger = true;
                    break;
                }
            }

            if (trigger) convexifyHullInPlace(6, &hull.x, &hull.y);
        }
        return hull;
    }

    if (N == 8 or N == 9) {
        var hull = buildAdaptiveHullQuad(N, &lx, &ly);

        if (hull_mode == .on_convex_fallback) {
            const corner_midsides = [4][2]usize{ .{ 7, 4 }, .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 } };
            var trigger = false;
            for (corner_midsides, 0..) |mids, nn| {
                const cos_theta = calcCornerMidsideCosTheta(
                    lx[nn],
                    ly[nn],
                    lx[mids[0]],
                    ly[mids[0]],
                    lx[mids[1]],
                    ly[mids[1]],
                ) orelse -2.0;
                if (cos_theta >= cos_lower or cos_theta <= cos_upper) {
                    trigger = true;
                    break;
                }
            }

            if (trigger) convexifyHullInPlace(8, &hull.x, &hull.y);
        }
        return hull;
    }

    unreachable;
}
