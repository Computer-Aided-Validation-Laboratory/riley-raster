// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const rops = @import("rasterops.zig");
const cam = @import("camera.zig");
const buildconfig = @import("buildconfig.zig");

const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;

const tol = buildconfig.config.tolerance;

const FallbackMode = enum {
    none,
    corners,
    bezier_ctrl,
};

const Point2 = struct {
    x: f64,
    y: f64,
};

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
        x: [NH]f64,
        y: [NH]f64,
    };
}

fn calcMajorPolygonSignedArea(
    comptime corners_num: usize,
    corner_points: [corners_num]Point2,
) f64 {
    var signed_area: f64 = 0.0;
    for (0..corners_num) |nn| {
        const mm = (nn + 1) % corners_num;
        signed_area +=
            corner_points[nn].x * corner_points[mm].y -
            corner_points[mm].x * corner_points[nn].y;
    }
    return 0.5 * signed_area;
}

fn reversePointsInPlace(
    comptime points_num: usize,
    points: *[points_num]Point2,
) void {
    for (0..points_num / 2) |nn| {
        const mm = points_num - 1 - nn;
        const temp = points[nn];
        points[nn] = points[mm];
        points[mm] = temp;
    }
}

fn calcCross(o: Point2, a: Point2, b: Point2) f64 {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

fn comparePointLex(lhs: Point2, rhs: Point2) bool {
    if (lhs.x < rhs.x) return true;
    if (lhs.x > rhs.x) return false;
    return lhs.y < rhs.y;
}

fn sortPointsLex(
    comptime points_num: usize,
    points: *[points_num]Point2,
) void {
    for (1..points_num) |ii| {
        const point = points[ii];
        var jj = ii;
        while (jj > 0 and comparePointLex(point, points[jj - 1])) : (jj -= 1) {
            points[jj] = points[jj - 1];
        }
        points[jj] = point;
    }
}

fn matchBasePolygonOrientation(
    comptime corners_num: usize,
    major_corners: [corners_num]Point2,
    base_points: *[corners_num]Point2,
) void {
    const major_area = calcMajorPolygonSignedArea(corners_num, major_corners);
    const base_area = calcMajorPolygonSignedArea(corners_num, base_points.*);
    if (major_area * base_area < 0.0) {
        reversePointsInPlace(corners_num, base_points);
    }
}

fn calcPolygonSignedArea(points: []const Point2) f64 {
    var signed_area: f64 = 0.0;
    for (0..points.len) |nn| {
        const mm = (nn + 1) % points.len;
        signed_area +=
            points[nn].x * points[mm].y -
            points[mm].x * points[nn].y;
    }
    return 0.5 * signed_area;
}

fn reversePointsSlice(points: []Point2) void {
    for (0..points.len / 2) |nn| {
        const mm = points.len - 1 - nn;
        const temp = points[nn];
        points[nn] = points[mm];
        points[mm] = temp;
    }
}

fn matchPolygonOrientationSlice(
    major_corners: []const Point2,
    base_points: []Point2,
) void {
    const major_area = calcPolygonSignedArea(major_corners);
    const base_area = calcPolygonSignedArea(base_points);
    if (major_area * base_area < 0.0) {
        reversePointsSlice(base_points);
    }
}

fn calcConvexHull(
    comptime points_num: usize,
    points_in: [points_num]Point2,
) struct {
    points: [points_num]Point2,
    count: usize,
} {
    var points_sorted = points_in;
    sortPointsLex(points_num, &points_sorted);

    var hull_points: [points_num]Point2 = undefined;
    var hull_count: usize = 0;

    for (0..points_num) |nn| {
        while (hull_count >= 2 and calcCross(
            hull_points[hull_count - 2],
            hull_points[hull_count - 1],
            points_sorted[nn],
        ) <= 0.0) {
            hull_count -= 1;
        }
        hull_points[hull_count] = points_sorted[nn];
        hull_count += 1;
    }

    const lower_count = hull_count;
    var nn = points_num - 1;
    while (true) {
        while (hull_count > lower_count and calcCross(
            hull_points[hull_count - 2],
            hull_points[hull_count - 1],
            points_sorted[nn],
        ) <= 0.0) {
            hull_count -= 1;
        }
        hull_points[hull_count] = points_sorted[nn];
        hull_count += 1;

        if (nn == 0) break;
        nn -= 1;
    }

    if (hull_count > 1) {
        hull_count -= 1;
    }

    return .{
        .points = hull_points,
        .count = hull_count,
    };
}

fn densifyConvexPolygonInPlace(
    comptime max_points: usize,
    target_points_num: usize,
    points: *[max_points]Point2,
    points_num: *usize,
) void {
    while (points_num.* < target_points_num) {
        var insert_after_idx: usize = 0;
        var longest_edge_len_sq: f64 = -1.0;

        for (0..points_num.*) |nn| {
            const mm = (nn + 1) % points_num.*;
            const dx = points[mm].x - points[nn].x;
            const dy = points[mm].y - points[nn].y;
            const edge_len_sq = dx * dx + dy * dy;
            if (edge_len_sq > longest_edge_len_sq) {
                longest_edge_len_sq = edge_len_sq;
                insert_after_idx = nn;
            }
        }

        const insert_idx = insert_after_idx + 1;
        const next_idx = insert_idx % points_num.*;
        const midpoint = Point2{
            .x = 0.5 * (points[insert_after_idx].x + points[next_idx].x),
            .y = 0.5 * (points[insert_after_idx].y + points[next_idx].y),
        };

        var ii = points_num.*;
        while (ii > insert_idx) : (ii -= 1) {
            points[ii] = points[ii - 1];
        }
        points[insert_idx] = midpoint;
        points_num.* += 1;
    }
}

fn fillHullFromBasePolygon(
    comptime N: usize,
    comptime max_points: usize,
    base_points: [max_points]Point2,
    base_points_num: usize,
) AdaptiveHullPoints(N) {
    const NH = comptime blk: {
        for (std.enums.values(MeshType)) |mt| {
            if (mt.getNodesNum() == N) {
                break :blk mt.getNumHullPoints();
            }
        }
        unreachable;
    };
    comptime std.debug.assert(NH <= max_points);

    var hull_points_arr = base_points;
    var points_num = base_points_num;
    densifyConvexPolygonInPlace(max_points, NH, &hull_points_arr, &points_num);

    var hull_points: AdaptiveHullPoints(N) = undefined;
    for (0..NH) |nn| {
        hull_points.x[nn] = hull_points_arr[nn].x;
        hull_points.y[nn] = hull_points_arr[nn].y;
    }

    return hull_points;
}

fn calcCornerMidsideCosTheta(
    corner_point: Point2,
    midside_prev: Point2,
    midside_next: Point2,
) ?f64 {
    const ax = midside_prev.x - corner_point.x;
    const ay = midside_prev.y - corner_point.y;
    const bx = midside_next.x - corner_point.x;
    const by = midside_next.y - corner_point.y;

    const a_mag_sq = ax * ax + ay * ay;
    const b_mag_sq = bx * bx + by * by;
    if (a_mag_sq <= 0.0 or b_mag_sq <= 0.0) {
        return null;
    }

    const inv_a_mag = 1.0 / @sqrt(a_mag_sq);
    const inv_b_mag = 1.0 / @sqrt(b_mag_sq);
    return (ax * inv_a_mag) * (bx * inv_b_mag) +
        (ay * inv_a_mag) * (by * inv_b_mag);
}

fn calcBezierCtrlPoint(
    corner_0: Point2,
    corner_1: Point2,
    midside: Point2,
) Point2 {
    return .{
        .x = 2.0 * midside.x - 0.5 * (corner_0.x + corner_1.x),
        .y = 2.0 * midside.y - 0.5 * (corner_0.y + corner_1.y),
    };
}

fn getTriMajorCorners(lx: *const [6]f64, ly: *const [6]f64) [3]Point2 {
    return .{
        .{ .x = lx[0], .y = ly[0] },
        .{ .x = lx[1], .y = ly[1] },
        .{ .x = lx[2], .y = ly[2] },
    };
}

fn getQuadMajorCorners(comptime N: usize, lx: *const [N]f64, ly: *const [N]f64) [4]Point2 {
    return .{
        .{ .x = lx[0], .y = ly[0] },
        .{ .x = lx[1], .y = ly[1] },
        .{ .x = lx[2], .y = ly[2] },
        .{ .x = lx[3], .y = ly[3] },
    };
}

fn getTriBezierCtrlPoints(lx: *const [6]f64, ly: *const [6]f64) [3]Point2 {
    const major_corners = getTriMajorCorners(lx, ly);
    return .{
        calcBezierCtrlPoint(major_corners[0], major_corners[1], .{
            .x = lx[3],
            .y = ly[3],
        }),
        calcBezierCtrlPoint(major_corners[1], major_corners[2], .{
            .x = lx[4],
            .y = ly[4],
        }),
        calcBezierCtrlPoint(major_corners[2], major_corners[0], .{
            .x = lx[5],
            .y = ly[5],
        }),
    };
}

fn getQuadBezierCtrlPoints(
    comptime N: usize,
    lx: *const [N]f64,
    ly: *const [N]f64,
) [4]Point2 {
    const major_corners = getQuadMajorCorners(N, lx, ly);
    return .{
        calcBezierCtrlPoint(major_corners[0], major_corners[1], .{
            .x = lx[4],
            .y = ly[4],
        }),
        calcBezierCtrlPoint(major_corners[1], major_corners[2], .{
            .x = lx[5],
            .y = ly[5],
        }),
        calcBezierCtrlPoint(major_corners[2], major_corners[3], .{
            .x = lx[6],
            .y = ly[6],
        }),
        calcBezierCtrlPoint(major_corners[3], major_corners[0], .{
            .x = lx[7],
            .y = ly[7],
        }),
    };
}

fn getTriConvexFallbackMode(gx: *const [6]f64, gy: *const [6]f64) FallbackMode {
    const major_corners = getTriMajorCorners(gx, gy);
    const cos_lower = @cos(std.math.degreesToRadians(
        tol.hull.corner_midside_ang_lower_deg,
    ));
    const cos_upper = @cos(std.math.degreesToRadians(
        tol.hull.corner_midside_ang_upper_deg,
    ));

    const corner_midsides = [3][2]usize{
        .{ 5, 3 },
        .{ 3, 4 },
        .{ 4, 5 },
    };

    var lower_trigger_count: usize = 0;
    var upper_trigger_count: usize = 0;
    for (corner_midsides, 0..) |midsides, nn| {
        const cos_theta = calcCornerMidsideCosTheta(
            major_corners[nn],
            .{ .x = gx[midsides[0]], .y = gy[midsides[0]] },
            .{ .x = gx[midsides[1]], .y = gy[midsides[1]] },
        ) orelse return .corners;

        if (cos_theta >= cos_lower) lower_trigger_count += 1;
        if (cos_theta <= cos_upper) upper_trigger_count += 1;
    }

    if (lower_trigger_count >= 1) return .corners;
    if (upper_trigger_count >= 1) return .bezier_ctrl;
    return .none;
}

fn getQuadConvexFallbackMode(
    comptime N: usize,
    gx: *const [N]f64,
    gy: *const [N]f64,
) FallbackMode {
    const major_corners = getQuadMajorCorners(N, gx, gy);
    const cos_lower = @cos(std.math.degreesToRadians(
        tol.hull.corner_midside_ang_lower_deg,
    ));
    const cos_upper = @cos(std.math.degreesToRadians(
        tol.hull.corner_midside_ang_upper_deg,
    ));

    const corner_midsides = [4][2]usize{
        .{ 7, 4 },
        .{ 4, 5 },
        .{ 5, 6 },
        .{ 6, 7 },
    };

    var lower_trigger_count: usize = 0;
    var upper_trigger_count: usize = 0;
    for (corner_midsides, 0..) |midsides, nn| {
        const cos_theta = calcCornerMidsideCosTheta(
            major_corners[nn],
            .{ .x = gx[midsides[0]], .y = gy[midsides[0]] },
            .{ .x = gx[midsides[1]], .y = gy[midsides[1]] },
        ) orelse return .corners;

        if (cos_theta >= cos_lower) lower_trigger_count += 1;
        if (cos_theta <= cos_upper) upper_trigger_count += 1;
    }

    if (lower_trigger_count >= 1) return .corners;
    if (upper_trigger_count >= 1) return .bezier_ctrl;
    return .none;
}

fn buildAdaptiveHullTri6(
    lx: *const [6]f64,
    ly: *const [6]f64,
) AdaptiveHullPoints(6) {
    const edges = [3][3]usize{
        .{ 0, 1, 3 },
        .{ 1, 2, 4 },
        .{ 2, 0, 5 },
    };

    var hull_points: AdaptiveHullPoints(6) = undefined;
    inline for (edges, 0..) |edge, ii| {
        const p0 = edge[0];
        const p1 = edge[1];
        const pm = edge[2];
        const edge_val = rops.edgeFun3(
            lx[p0],
            ly[p0],
            lx[p1],
            ly[p1],
            lx[pm],
            ly[pm],
        );
        hull_points.x[ii * 2] = lx[p0];
        hull_points.y[ii * 2] = ly[p0];
        if (edge_val < 0) {
            hull_points.x[ii * 2 + 1] = 2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
            hull_points.y[ii * 2 + 1] = 2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
        } else {
            hull_points.x[ii * 2 + 1] = lx[pm];
            hull_points.y[ii * 2 + 1] = ly[pm];
        }
    }

    return hull_points;
}

fn buildAdaptiveHullQuad(
    comptime N: usize,
    lx: *const [N]f64,
    ly: *const [N]f64,
) AdaptiveHullPoints(N) {
    const edges = [4][3]usize{
        .{ 0, 1, 4 },
        .{ 1, 2, 5 },
        .{ 2, 3, 6 },
        .{ 3, 0, 7 },
    };

    var hull_points: AdaptiveHullPoints(N) = undefined;
    inline for (edges, 0..) |edge, ii| {
        const p0 = edge[0];
        const p1 = edge[1];
        const pm = edge[2];
        const edge_val = rops.edgeFun3(
            lx[p0],
            ly[p0],
            lx[p1],
            ly[p1],
            lx[pm],
            ly[pm],
        );
        hull_points.x[ii * 2] = lx[p0];
        hull_points.y[ii * 2] = ly[p0];
        if (edge_val < 0) {
            hull_points.x[ii * 2 + 1] = 2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
            hull_points.y[ii * 2 + 1] = 2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
        } else {
            hull_points.x[ii * 2 + 1] = lx[pm];
            hull_points.y[ii * 2 + 1] = ly[pm];
        }
    }

    return hull_points;
}

fn buildConvexHullTri6(
    mode: FallbackMode,
    lx: *const [6]f64,
    ly: *const [6]f64,
) AdaptiveHullPoints(6) {
    const major_corners = getTriMajorCorners(lx, ly);
    var base_points: [6]Point2 = undefined;
    const base_points_num: usize = switch (mode) {
        .corners => blk: {
            @memcpy(base_points[0..3], major_corners[0..]);
            break :blk 3;
        },
        .bezier_ctrl => blk: {
            const bezier_ctrl_points = getTriBezierCtrlPoints(lx, ly);
            @memcpy(base_points[0..3], major_corners[0..]);
            @memcpy(base_points[3..6], bezier_ctrl_points[0..]);
            var convex_hull = calcConvexHull(6, base_points);
            matchPolygonOrientationSlice(
                major_corners[0..],
                convex_hull.points[0..convex_hull.count],
            );
            base_points = convex_hull.points;
            break :blk convex_hull.count;
        },
        .none => unreachable,
    };
    if (mode == .corners) {
        var corners_only = major_corners;
        matchBasePolygonOrientation(3, major_corners, &corners_only);
        @memcpy(base_points[0..3], corners_only[0..]);
    }
    return fillHullFromBasePolygon(6, 6, base_points, base_points_num);
}

fn buildConvexHullQuad(
    comptime N: usize,
    mode: FallbackMode,
    lx: *const [N]f64,
    ly: *const [N]f64,
) AdaptiveHullPoints(N) {
    const major_corners = getQuadMajorCorners(N, lx, ly);
    var base_points: [8]Point2 = undefined;
    const base_points_num: usize = switch (mode) {
        .corners => blk: {
            @memcpy(base_points[0..4], major_corners[0..]);
            break :blk 4;
        },
        .bezier_ctrl => blk: {
            const bezier_ctrl_points = getQuadBezierCtrlPoints(N, lx, ly);
            @memcpy(base_points[0..4], major_corners[0..]);
            @memcpy(base_points[4..8], bezier_ctrl_points[0..]);
            var convex_hull = calcConvexHull(8, base_points);
            matchPolygonOrientationSlice(
                major_corners[0..],
                convex_hull.points[0..convex_hull.count],
            );
            base_points = convex_hull.points;
            break :blk convex_hull.count;
        },
        .none => unreachable,
    };
    if (mode == .corners) {
        var corners_only = major_corners;
        matchBasePolygonOrientation(4, major_corners, &corners_only);
        @memcpy(base_points[0..4], corners_only[0..]);
    }
    return fillHullFromBasePolygon(N, 8, base_points, base_points_num);
}

pub fn buildAdaptiveHullPointsFromClip(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_elem: rops.GatheredElemCoords(N),
    hull_convex_fallback_on: bool,
) AdaptiveHullPoints(N) {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    var lx: [N]f64 = undefined;
    var ly: [N]f64 = undefined;
    var gx: [N]f64 = undefined;
    var gy: [N]f64 = undefined;
    for (0..N) |nn| {
        gx[nn] = coords_elem.x[nn];
        gy[nn] = coords_elem.y[nn];
        lx[nn] = coords_elem.x[nn] / coords_elem.z[nn] + x_off;
        ly[nn] = coords_elem.y[nn] / coords_elem.z[nn] + y_off;
    }

    if (N == 4) {
        var hull_points: AdaptiveHullPoints(4) = undefined;
        inline for (0..4) |nn| {
            hull_points.x[nn] = lx[nn];
            hull_points.y[nn] = ly[nn];
        }
        return hull_points;
    }

    if (N == 6) {
        const fallback_mode = if (hull_convex_fallback_on)
            getTriConvexFallbackMode(&gx, &gy)
        else
            .none;
        return switch (fallback_mode) {
            .none => buildAdaptiveHullTri6(&lx, &ly),
            .corners, .bezier_ctrl => buildConvexHullTri6(
                fallback_mode,
                &lx,
                &ly,
            ),
        };
    }

    if (N == 8 or N == 9) {
        const fallback_mode = if (hull_convex_fallback_on)
            getQuadConvexFallbackMode(N, &gx, &gy)
        else
            .none;
        return switch (fallback_mode) {
            .none => buildAdaptiveHullQuad(N, &lx, &ly),
            .corners, .bezier_ctrl => buildConvexHullQuad(
                N,
                fallback_mode,
                &lx,
                &ly,
            ),
        };
    }

    unreachable;
}
