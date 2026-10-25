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
const frontend = @import("rasterfrontend.zig");
const edgeops = @import("hulledge.zig");
const HullEdge = @import("hulledge.zig").HullEdge;
const EdgeFunMode = @import("rasterconfig.zig").EdgeFunMode;
const hullcommon = @import("hullmultiroot_common.zig");
const cam = @import("camera.zig");
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const S = cfg.simd_vec_width;

pub fn prepareEdgesSIMD(x: []const F, y: []const F, edges: []HullEdge) void {
    std.debug.assert(x.len == y.len and x.len == edges.len);

    var start: usize = 0;

    while (start < x.len) : (start += S) {
        var x0: [S]F = @splat(0);
        var y0: [S]F = @splat(0);
        var x1: [S]F = @splat(0);
        var y1: [S]F = @splat(0);
        const count = @min(S, x.len - start);

        for (0..count) |lane| {
            const ii = start + lane;
            const jj = (ii + 1) % x.len;
            x0[lane] = x[ii];
            y0[lane] = y[ii];
            x1[lane] = x[jj];
            y1[lane] = y[jj];
        }

        const vx0: VecSF = x0;
        const vy0: VecSF = y0;
        const vx1: VecSF = x1;
        const vy1: VecSF = y1;
        const dx = vx1 - vx0;
        const dy = vy1 - vy0;

        const left = vx1 * vy0;
        const right = vx0 * vy1;
        const tol_edge: VecSF = @splat(tol.hull.scal_inclusion);

        const round_factor: VecSF = @splat(16 * std.math.floatEps(F));
        const rounding = round_factor *
            (@abs(left) + @abs(right) + @abs(vx0 * dy) + @abs(vy0 * dx));

        const va = dy;
        const vb = -dx;

        const vc = left - right + tol_edge * @sqrt(dx * dx + dy * dy) + rounding;

        const aa: [S]F = va;
        const bb: [S]F = vb;
        const cc: [S]F = vc;

        for (0..count) |lane| {
            edges[start + lane] = .{ .a = aa[lane], .b = bb[lane], .c = cc[lane] };
        }
    }
}

pub fn containsPreCalcSIMD(
    poly: *const hullcommon.HullPolyPreCalc,
    v_px: VecSF,
    v_py: VecSF,
    valid: VecSB,
) VecSB {
    if (poly.count < 3) return @splat(false);
    var inside = valid;
    for (poly.edges[0..poly.count]) |edge| {
        const a: VecSF = @splat(edge.a);
        const b: VecSF = @splat(edge.b);
        const c: VecSF = @splat(edge.c);
        inside &= a * v_px + b * v_py + c >= @as(VecSF, @splat(0));
        if (!@reduce(.Or, inside)) break;
    }
    return inside;
}

pub fn containsOnTheFlySIMD(
    poly: *const hullcommon.HullPolyOnTheFly,
    v_px: VecSF,
    v_py: VecSF,
    valid: VecSB,
) VecSB {
    if (poly.count < 3) return @splat(false);
    var inside = valid;
    for (0..poly.count) |ii| {
        const jj = (ii + 1) % poly.count;
        inside &= edgeops.edgeFun3SIMD(
            poly.x[ii],
            poly.y[ii],
            poly.x[jj],
            poly.y[jj],
            v_px,
            v_py,
        ) >= @as(VecSF, @splat(-poly.tol_edge[ii]));
        if (!@reduce(.Or, inside)) break;
    }
    return inside;
}

pub fn childMaskPreCalcSIMD(
    leaves: []const hullcommon.BezierLeafPreCalc,
    v_px: VecSF,
    v_py: VecSF,
    valid_mask: VecSB,
) [S]u8 {
    var masks: @Vector(S, u8) = @splat(0);
    for (leaves, 0..) |*leaf, ii| {
        const min_x: VecSF = @splat(leaf.bbox[0]);
        const max_x: VecSF = @splat(leaf.bbox[1]);
        const min_y: VecSF = @splat(leaf.bbox[2]);
        const max_y: VecSF = @splat(leaf.bbox[3]);

        const bbox_mask = valid_mask & (v_px >= min_x) & (v_px <= max_x) &
            (v_py >= min_y) & (v_py <= max_y);
        if (!@reduce(.Or, bbox_mask)) continue;

        const hit = containsPreCalcSIMD(
            &leaf.poly,
            v_px,
            v_py,
            bbox_mask,
        );

        const bit: @Vector(S, u8) = @splat(@as(u8, 1) << @as(u3, @intCast(ii)));
        masks |= @select(u8, hit, bit, @as(@Vector(S, u8), @splat(0)));
    }
    return masks;
}

pub fn childMaskOnTheFlySIMD(
    leaves: []const hullcommon.BezierLeafOnTheFly,
    v_px: VecSF,
    v_py: VecSF,
    valid_mask: VecSB,
) [S]u8 {
    var masks: @Vector(S, u8) = @splat(0);
    for (leaves, 0..) |*leaf, ii| {
        const min_x: VecSF = @splat(leaf.bbox[0]);
        const max_x: VecSF = @splat(leaf.bbox[1]);
        const min_y: VecSF = @splat(leaf.bbox[2]);
        const max_y: VecSF = @splat(leaf.bbox[3]);

        const bbox_mask = valid_mask & (v_px >= min_x) & (v_px <= max_x) &
            (v_py >= min_y) & (v_py <= max_y);
        if (!@reduce(.Or, bbox_mask)) continue;

        const hit = containsOnTheFlySIMD(
            &leaf.poly,
            v_px,
            v_py,
            bbox_mask,
        );

        const bit: @Vector(S, u8) = @splat(@as(u8, 1) << @as(u3, @intCast(ii)));
        masks |= @select(u8, hit, bit, @as(@Vector(S, u8), @splat(0)));
    }
    return masks;
}

pub fn prepareFourBezierLeavesPreCalcSIMD(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]hullcommon.BezierLeafPreCalc,
) void {
    hullcommon.prepareFourBezierLeavesPreCalc(
        N,
        prepareEdgesSIMD,
        camera,
        coords,
        output,
    );
}

pub fn prepareFourBezierLeavesOnTheFlySIMD(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: frontend.ElemCoords(N),
    output: *[4]hullcommon.BezierLeafOnTheFly,
) void {
    hullcommon.prepareFourBezierLeavesOnTheFly(
        N,
        camera,
        coords,
        output,
    );
}

test "multi-root SIMD edge preparation and containment match scalar" {
    inline for (.{ 4, 6, 9 }) |count| {
        var x: [count]F = undefined;
        var y: [count]F = undefined;
        for (0..count) |ii| {
            const angle = -2 * std.math.pi *
                @as(F, @floatFromInt(ii)) / @as(F, @floatFromInt(count));
            x[ii] = 50 + 20 * @cos(angle);
            y[ii] = 50 + 20 * @sin(angle);
        }
        var vector_edges: [count]HullEdge = undefined;
        var scalar_edges: [count]HullEdge = undefined;
        var tol_edge: [count]F = undefined;
        prepareEdgesSIMD(&x, &y, &vector_edges);
        hullcommon.prepareEdgesScalar(&x, &y, &scalar_edges);
        hullcommon.calcEdgeTol(&x, &y, &tol_edge);
        for (0..count) |ii| {
            try std.testing.expectApproxEqRel(
                scalar_edges[ii].a,
                vector_edges[ii].a,
                16 * std.math.floatEps(F),
            );
            try std.testing.expectApproxEqRel(
                scalar_edges[ii].b,
                vector_edges[ii].b,
                16 * std.math.floatEps(F),
            );
            try std.testing.expectApproxEqAbs(
                scalar_edges[ii].c,
                vector_edges[ii].c,
                128 * std.math.floatEps(F),
            );
        }
        var px: [S]F = undefined;
        var py: [S]F = undefined;
        var valid: [S]bool = undefined;
        for (0..S) |lane| {
            px[lane] = 25 + 7 * @as(F, @floatFromInt(lane));
            py[lane] = 50;
            valid[lane] = lane + 1 < S;
        }
        const v_px: VecSF = px;
        const v_py: VecSF = py;
        const v_valid: VecSB = valid;

        var poly_pre = hullcommon.HullPolyPreCalc{ .count = @intCast(count) };
        @memcpy(poly_pre.edges[0..count], vector_edges[0..count]);
        var poly_scalar_pre = hullcommon.HullPolyPreCalc{ .count = @intCast(count) };
        @memcpy(poly_scalar_pre.edges[0..count], scalar_edges[0..count]);

        const hits_pre: [S]bool = containsPreCalcSIMD(
            &poly_pre,
            v_px,
            v_py,
            v_valid,
        );
        for (0..S) |lane| {
            const expected = valid[lane] and
                hullcommon.containsPreCalcScalar(&poly_scalar_pre, px[lane], py[lane]);
            try std.testing.expectEqual(expected, hits_pre[lane]);
        }

        var poly_fly = hullcommon.HullPolyOnTheFly{ .count = @intCast(count) };
        @memcpy(poly_fly.x[0..count], x[0..count]);
        @memcpy(poly_fly.y[0..count], y[0..count]);
        @memcpy(poly_fly.tol_edge[0..count], tol_edge[0..count]);

        const hits_fly: [S]bool = containsOnTheFlySIMD(
            &poly_fly,
            v_px,
            v_py,
            v_valid,
        );
        for (0..S) |lane| {
            const expected = valid[lane] and
                hullcommon.containsOnTheFlyScalar(&poly_fly, px[lane], py[lane]);
            try std.testing.expectEqual(expected, hits_fly[lane]);
        }
    }
}

test "multi-root SIMD child masks match scalar with inactive lanes" {
    const x = [_]F{ 0, 0, 100, 100 };
    const y = [_]F{ 0, 100, 100, 0 };
    var leaves_pre: [4]hullcommon.BezierLeafPreCalc = undefined;
    var leaves_fly: [4]hullcommon.BezierLeafOnTheFly = undefined;
    for (0..4) |ii| {
        const inset = 10 * @as(F, @floatFromInt(ii));
        leaves_pre[ii] = .{
            .poly = .{ .count = 4 },
            .bbox = .{ inset, 100 - inset, inset, 100 - inset },
            .parameter_seed = .{ 0, 0 },
        };
        prepareEdgesSIMD(&x, &y, leaves_pre[ii].poly.edges[0..4]);

        leaves_fly[ii] = .{
            .poly = .{ .count = 4 },
            .bbox = .{ inset, 100 - inset, inset, 100 - inset },
            .parameter_seed = .{ 0, 0 },
        };
        @memcpy(leaves_fly[ii].poly.x[0..4], &x);
        @memcpy(leaves_fly[ii].poly.y[0..4], &y);
        hullcommon.calcEdgeTol(&x, &y, leaves_fly[ii].poly.tol_edge[0..4]);
    }
    var px: [S]F = undefined;
    var py: [S]F = undefined;
    var valid: [S]bool = undefined;
    for (0..S) |lane| {
        px[lane] = 5 + 10 * @as(F, @floatFromInt(lane));
        py[lane] = 50;
        valid[lane] = lane + 1 < S;
    }
    const v_px: VecSF = px;
    const v_py: VecSF = py;
    const v_valid: VecSB = valid;

    const masks_pre = childMaskPreCalcSIMD(&leaves_pre, v_px, v_py, v_valid);
    for (0..S) |lane| {
        const expected: u8 = if (valid[lane])
            hullcommon.childMaskPreCalcScalar(&leaves_pre, px[lane], py[lane])
        else
            0;
        try std.testing.expectEqual(expected, masks_pre[lane]);
    }

    const masks_fly = childMaskOnTheFlySIMD(&leaves_fly, v_px, v_py, v_valid);
    for (0..S) |lane| {
        const expected: u8 = if (valid[lane])
            hullcommon.childMaskOnTheFlyScalar(&leaves_fly, px[lane], py[lane])
        else
            0;
        try std.testing.expectEqual(expected, masks_fly[lane]);
    }
}

