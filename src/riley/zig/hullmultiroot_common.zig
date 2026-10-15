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
const distbounds = @import("distortbounds.zig");
const geomkerns = @import("geometrykernels.zig");
const rastcfg = @import("rasterconfig.zig");
const frontend = @import("rasterfrontend.zig");
const edgeops = @import("hulledge.zig");
const shapefun = @import("shapefun.zig");
const tol = buildconfig.config.tol;
const vecstack = @import("vecstack.zig");
const Vec2F = vecstack.Vec2F;
const Vec2Ops = vecstack.Vec2Ops;
const HullEdge = @import("hulledge.zig").HullEdge;

pub const Points = struct {
    x: [9]F = undefined,
    y: [9]F = undefined,
    count: u8 = 0,

    pub fn contains(self: *const Points, px: F, py: F) bool {
        if (self.count < 3) return false;
        var tol_edge: [9]F = undefined;
        calcEdgeTol(
            self.x[0..self.count],
            self.y[0..self.count],
            tol_edge[0..self.count],
        );
        return containsOnTheFlyScalar(
            self.x[0..self.count],
            self.y[0..self.count],
            tol_edge[0..self.count],
            px,
            py,
        );
    }
};

pub fn buildPointsFromClip(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
) Points {
    const controls = controlNet(N, coords);
    const K = controls.x.len;

    const x_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(F, @floatFromInt(camera.pixels_num[1]));

    var points: [K]Vec2F = undefined;
    var all_positive = true;

    for (0..K) |nn| {
        const z = controls.z[nn];
        if (z <= tol.culling.projective_z_min) {
            all_positive = false;
            continue;
        }
        points[nn] = vecstack.initVec2(
            F,
            controls.x[nn] / z + x_off,
            controls.y[nn] / z + y_off,
        );
    }

    if (all_positive) return fromPoints(&points);

    // A projective linear-fractional coordinate reaches its extrema on the
    // vertices of the positive-depth control polytope clipped at the near
    // plane. All control pairs include every actual polytope edge.
    const near_z = tol.culling.projective_z_min;
    var bounds = distbounds.DistortBounds.initEmpty();
    var has_point = false;
    for (0..K) |ii| {
        if (controls.z[ii] > near_z) {
            bounds.include(points[ii].x(), points[ii].y());
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

    const halo: F = @floatFromInt(camera.prep_psf.halo_px);
    const sensor: distbounds.DistortBounds = camera.ideal_sensor_bounds orelse .{
        .x_min = -halo,
        .x_max = @as(F, @floatFromInt(camera.pixels_num[0])) + halo,
        .y_min = -halo,
        .y_max = @as(F, @floatFromInt(camera.pixels_num[1])) + halo,
    };

    if (!has_point) return .{};

    return if (bounds.intersect(sensor)) |clipped| rectHull(clipped) else .{};
}

pub fn calcEdgeTol(x: []const F, y: []const F, tol_edge: []F) void {
    for (0..x.len) |ii| {
        const jj = (ii + 1) % x.len;
        const dx = x[jj] - x[ii];
        const dy = y[jj] - y[ii];
        tol_edge[ii] = tol.hull.scal_inclusion * @sqrt(dx * dx + dy * dy);
    }
}

pub const PrepareEdgesFn = *const fn (
    x: []const F,
    y: []const F,
    edges: []HullEdge,
) void;

pub fn prepareEdgesScalar(x: []const F, y: []const F, edges: []HullEdge) void {
    std.debug.assert(x.len == y.len and x.len == edges.len);
    for (0..x.len) |ii| {
        const jj = (ii + 1) % x.len;
        const dx = x[jj] - x[ii];
        const dy = y[jj] - y[ii];
        edges[ii] = HullEdge.init(
            x[ii],
            y[ii],
            x[jj],
            y[jj],
            tol.hull.scal_inclusion * @sqrt(dx * dx + dy * dy),
        );
    }
}

pub fn containsPreCalcScalar(edges: []const HullEdge, px: F, py: F) bool {
    if (edges.len < 3) return false;
    for (edges) |edge| {
        if (edge.eval(px, py) < 0) return false;
    }
    return true;
}

pub fn containsOnTheFlyScalar(
    x: []const F,
    y: []const F,
    tol_edge: []const F,
    px: F,
    py: F,
) bool {
    if (x.len < 3) return false;
    for (0..x.len) |ii| {
        const jj = (ii + 1) % x.len;
        const edge = edgeops.edgeFun3(
            x[ii],
            y[ii],
            x[jj],
            y[jj],
            px,
            py,
        );
        if (edge < -tol_edge[ii]) {
            return false;
        }
    }
    return true;
}

pub const HullPolyPreCalc = struct {
    edges: [9]HullEdge = undefined,
    count: u8 = 0,
};

pub const HullPolyOnTheFly = struct {
    x: [9]F = undefined,
    y: [9]F = undefined,
    tol_edge: [9]F = undefined,
    count: u8 = 0,
};

pub fn childMaskPreCalcScalar(
    leaves: []const BezierLeafPreCalc,
    px: F,
    py: F,
) u8 {
    var mask: u8 = 0;
    for (leaves, 0..) |*leaf, ii| {
        if (px < leaf.bbox[0] or px > leaf.bbox[1] or
            py < leaf.bbox[2] or py > leaf.bbox[3]) continue;

        if (containsPreCalcScalar(leaf.poly.edges[0..leaf.poly.count], px, py)) {
            mask |= @as(u8, 1) << @as(u3, @intCast(ii));
        }
    }
    return mask;
}

pub fn childMaskOnTheFlyScalar(
    leaves: []const BezierLeafOnTheFly,
    px: F,
    py: F,
) u8 {
    var mask: u8 = 0;
    for (leaves, 0..) |*leaf, ii| {
        if (px < leaf.bbox[0] or px > leaf.bbox[1] or
            py < leaf.bbox[2] or py > leaf.bbox[3]) continue;

        if (containsOnTheFlyScalar(
            leaf.poly.x[0..leaf.poly.count],
            leaf.poly.y[0..leaf.poly.count],
            leaf.poly.tol_edge[0..leaf.poly.count],
            px,
            py,
        )) {
            mask |= @as(u8, 1) << @as(u3, @intCast(ii));
        }
    }
    return mask;
}

fn fromPoints(points_in: []const Vec2F) Points {
    var points: [9]Vec2F = undefined;
    @memcpy(points[0..points_in.len], points_in);
    vecstack.insertSortVec2(F, points[0..points_in.len]);

    var chain: [18]Vec2F = undefined;
    var count: usize = 0;
    for (points[0..points_in.len]) |point| {
        while (count >= 2 and
            Vec2Ops.cross3(F, chain[count - 2], chain[count - 1], point) <= 0)
        {
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
            Vec2Ops.cross3(F, chain[count - 2], chain[count - 1], point) <= 0)
        {
            count -= 1;
        }
        chain[count] = point;
        count += 1;
    }
    if (count > 1) count -= 1;

    var result = Points{};
    if (count < 3) {
        // A collapsed projected footprint still covers its nearest pixel
        // centre, including when it falls between sample positions.
        const pad: F = @max(0.5, tol.hull.scal_inclusion);
        const min_x = points[0].x() - pad;
        const max_x = points[points_in.len - 1].x() + pad;
        var min_y = points[0].y();
        var max_y = min_y;
        for (points_in) |point| {
            min_y = @min(min_y, point.y());
            max_y = @max(max_y, point.y());
        }
        result.x[0..4].* = .{ min_x, min_x, max_x, max_x };
        result.y[0..4].* = .{ min_y - pad, max_y + pad, max_y + pad, min_y - pad };
        result.count = 4;
        return result;
    }
    // edgeFun3 has the opposite sign to the standard cross product.
    for (0..count) |nn| {
        const point = chain[count - 1 - nn];
        result.x[nn] = point.x();
        result.y[nn] = point.y();
    }
    result.count = @intCast(count);

    return result;
}

fn rectHull(bounds: distbounds.DistortBounds) Points {
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
    coords: frontend.ElemCoords(N),
) frontend.ElemCoords(if (N == 8) 9 else N) {
    const K = if (N == 8) 9 else N;

    var controls: frontend.ElemCoords(K) = undefined;
    if (comptime N == 4) {
        controls = coords;
        return controls;
    }

    if (comptime N == 6) {
        controls = coords;
        const edges = [3][3]usize{
            .{ 0, 1, 3 }, .{ 1, 2, 4 }, .{ 2, 0, 5 },
        };

        inline for (edges) |edge| {
            const a = edge[0];
            const b = edge[1];
            const mid = edge[2];

            controls.x[mid] = 2 * coords.x[mid] -
                0.5 * (coords.x[a] + coords.x[b]);
            controls.y[mid] = 2 * coords.y[mid] -
                0.5 * (coords.y[a] + coords.y[b]);
            controls.z[mid] = 2 * coords.z[mid] -
                0.5 * (coords.z[a] + coords.z[b]);
        }

        return controls;
    }

    var nodes: frontend.ElemCoords(9) = undefined;
    for (0..N) |nn| {
        nodes.x[nn] = coords.x[nn];
        nodes.y[nn] = coords.y[nn];
        nodes.z[nn] = coords.z[nn];
    }

    if (comptime N == 8) {
        inline for (.{ "x", "y", "z" }) |field| {
            const src = &@field(nodes, field);
            src[8] = 0.5 * (src[4] + src[5] + src[6] + src[7]) -
                0.25 * (src[0] + src[1] + src[2] + src[3]);
        }
    }

    const grid = [3][3]usize{ .{ 0, 4, 1 }, .{ 7, 8, 5 }, .{ 3, 6, 2 } };
    inline for (.{ "x", "y", "z" }) |field| {
        const src = @field(nodes, field);
        const dst = &@field(controls, field);

        const row0 = 2 * src[4] - 0.5 * (src[0] + src[1]);
        const row1 = 2 * src[8] - 0.5 * (src[7] + src[5]);
        const row2 = 2 * src[6] - 0.5 * (src[3] + src[2]);

        dst[grid[0][0]] = src[0];
        dst[grid[0][1]] = row0;
        dst[grid[0][2]] = src[1];
        dst[grid[1][0]] = 2 * src[7] - 0.5 * (src[0] + src[3]);
        dst[grid[1][1]] = 2 * row1 - 0.5 * (row0 + row2);
        dst[grid[1][2]] = 2 * src[5] - 0.5 * (src[1] + src[2]);
        dst[grid[2][0]] = src[3];
        dst[grid[2][1]] = row2;
        dst[grid[2][2]] = src[2];
    }
    
    return controls;
}
pub const BezierLeafPreCalc = struct {
    poly: HullPolyPreCalc = .{},
    bbox: [4]F = undefined,
    parameter_seed: [2]F = undefined,
};

pub const BezierLeafOnTheFly = struct {
    poly: HullPolyOnTheFly = .{},
    bbox: [4]F = undefined,
    parameter_seed: [2]F = undefined,
};

const BezierPatchRegion = struct {
    origin: [2]F,
    axis_u: [2]F,
    axis_v: [2]F,
};

fn mapPointToParentRegion(region: BezierPatchRegion, uv: [2]F) [2]F {
    return .{
        region.origin[0] + region.axis_u[0] * uv[0] +
            region.axis_v[0] * uv[1],
        region.origin[1] + region.axis_u[1] * uv[0] +
            region.axis_v[1] * uv[1],
    };
}

fn fixedChildRegion(
    comptime N: usize,
    child_idx: usize,
) BezierPatchRegion {
    if (comptime N == 6) {
        const local = [4]BezierPatchRegion{
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

fn projectChildPoints(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    region: BezierPatchRegion,
) Points {
    const parents = comptime geomkerns.parentNodeCoords(N);

    var child: frontend.ElemCoords(N) = undefined;

    for (parents, 0..) |node_uv, ii| {
        const uv = mapPointToParentRegion(region, node_uv);
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

    return buildPointsFromClip(N, camera, child);
}

fn calcChildBBox(
    points: *const Points,
    tol_edge: []const F,
) [4]F {
    var bbox: [4]F = .{
        std.math.inf(F),
        -std.math.inf(F),
        std.math.inf(F),
        -std.math.inf(F),
    };
    var max_tol_edge: F = 0;
    for (0..points.count) |ii| {
        bbox[0] = @min(bbox[0], points.x[ii]);
        bbox[1] = @max(bbox[1], points.x[ii]);
        bbox[2] = @min(bbox[2], points.y[ii]);
        bbox[3] = @max(bbox[3], points.y[ii]);
        max_tol_edge = @max(max_tol_edge, tol_edge[ii]);
    }
    bbox[0] -= max_tol_edge;
    bbox[1] += max_tol_edge;
    bbox[2] -= max_tol_edge;
    bbox[3] += max_tol_edge;
    return bbox;
}

fn prepareBezierLeafPreCalc(
    comptime N: usize,
    comptime prepare_edges: PrepareEdgesFn,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    region: BezierPatchRegion,
) BezierLeafPreCalc {
    const projected = projectChildPoints(N, camera, coords, region);
    var tol_edge: [9]F = undefined;
    calcEdgeTol(
        projected.x[0..projected.count],
        projected.y[0..projected.count],
        tol_edge[0..projected.count],
    );

    var leaf = BezierLeafPreCalc{
        .poly = .{ .count = projected.count },
        .bbox = calcChildBBox(&projected, tol_edge[0..projected.count]),
        .parameter_seed = mapPointToParentRegion(
            region,
            if (N == 6) .{ 1.0 / 3.0, 1.0 / 3.0 } else .{ 0, 0 },
        ),
    };

    prepare_edges(
        projected.x[0..projected.count],
        projected.y[0..projected.count],
        leaf.poly.edges[0..projected.count],
    );

    return leaf;
}

fn prepareBezierLeafOnTheFly(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    region: BezierPatchRegion,
) BezierLeafOnTheFly {
    const projected = projectChildPoints(N, camera, coords, region);
    var leaf = BezierLeafOnTheFly{
        .poly = .{ .count = projected.count },
        .parameter_seed = mapPointToParentRegion(
            region,
            if (N == 6) .{ 1.0 / 3.0, 1.0 / 3.0 } else .{ 0, 0 },
        ),
    };

    @memcpy(leaf.poly.x[0..projected.count], projected.x[0..projected.count]);
    @memcpy(leaf.poly.y[0..projected.count], projected.y[0..projected.count]);
    calcEdgeTol(
        projected.x[0..projected.count],
        projected.y[0..projected.count],
        leaf.poly.tol_edge[0..projected.count],
    );
    leaf.bbox = calcChildBBox(&projected, leaf.poly.tol_edge[0..projected.count]);

    return leaf;
}

pub fn prepareFourBezierLeavesPreCalc(
    comptime N: usize,
    comptime prepare_edges: PrepareEdgesFn,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]BezierLeafPreCalc,
) void {
    inline for (0..4) |ii| {
        const region = fixedChildRegion(N, ii);
        output[ii] = prepareBezierLeafPreCalc(
            N,
            prepare_edges,
            camera,
            coords,
            region,
        );
    }
}

pub fn prepareFourBezierLeavesOnTheFly(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]BezierLeafOnTheFly,
) void {
    inline for (0..4) |ii| {
        const region = fixedChildRegion(N, ii);
        output[ii] = prepareBezierLeafOnTheFly(
            N,
            camera,
            coords,
            region,
        );
    }
}

pub fn prepareFourBezierLeavesPreCalcScalar(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]BezierLeafPreCalc,
) void {
    prepareFourBezierLeavesPreCalc(
        N,
        prepareEdgesScalar,
        camera,
        coords,
        output,
    );
}

pub fn prepareFourBezierLeavesOnTheFlyScalar(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]BezierLeafOnTheFly,
) void {
    prepareFourBezierLeavesOnTheFly(
        N,
        camera,
        coords,
        output,
    );
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "quad control net matches the tensor transform" {
    const grid = [3][3]usize{ .{ 0, 4, 1 }, .{ 7, 8, 5 }, .{ 3, 6, 2 } };
    const transform = [3][3]F{
        .{ 1, 0, 0 }, .{ -0.5, 2, -0.5 }, .{ 0, 0, 1 },
    };
    inline for (.{ 8, 9 }) |N| {
        var coords: frontend.ElemCoords(N) = undefined;
        for (0..N) |ii| {
            const v: F = @floatFromInt(ii);
            coords.x[ii] = v * v - 3 * v + 7;
            coords.y[ii] = 0.25 * v * v + v;
            coords.z[ii] = 1 + 0.125 * v;
        }
        const actual = controlNet(N, coords);
        var nodes: frontend.ElemCoords(9) = undefined;
        for (0..N) |ii| {
            nodes.x[ii] = coords.x[ii];
            nodes.y[ii] = coords.y[ii];
            nodes.z[ii] = coords.z[ii];
        }
        if (N == 8) {
            inline for (.{ "x", "y", "z" }) |field| {
                const src = &@field(nodes, field);
                src[8] = 0.5 * (src[4] + src[5] + src[6] + src[7]) -
                    0.25 * (src[0] + src[1] + src[2] + src[3]);
            }
        }
        inline for (.{ "x", "y", "z" }) |field| {
            const src = @field(nodes, field);
            const got = @field(actual, field);
            for (0..3) |vv| for (0..3) |uu| {
                var expected: F = 0;
                for (0..3) |jj| for (0..3) |ii| {
                    expected += transform[vv][jj] * transform[uu][ii] *
                        src[grid[jj][ii]];
                };
                try std.testing.expectApproxEqAbs(expected, got[grid[vv][uu]], 1e-5);
            };
        }
    }
}
