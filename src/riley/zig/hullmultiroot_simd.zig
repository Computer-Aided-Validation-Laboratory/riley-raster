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
const rops = @import("rasterfrontend.zig");
const edgeops = @import("hulledge.zig");
const HullEdge = @import("hulledge.zig").HullEdge;
const EdgeFunMode = @import("rasterconfig.zig").EdgeFunMode;
const hullcommon = @import("hullmultiroot_common.zig");
const cam = @import("camera.zig");
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const S = cfg.simd_vec_width;

pub fn prepareEdges(x: []const F, y: []const F, edges: []HullEdge) void {
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
        const slack: VecSF = @splat(tol.hull.scal_inclusion);

        const round_factor: VecSF = @splat(16 * std.math.floatEps(F));
        const rounding = round_factor *
            (@abs(left) + @abs(right) + @abs(vx0 * dy) + @abs(vy0 * dx));

        const va = dy;
        const vb = -dx;

        const vc = left - right + slack * @sqrt(dx * dx + dy * dy) + rounding;

        const aa: [S]F = va;
        const bb: [S]F = vb;
        const cc: [S]F = vc;

        for (0..count) |lane| {
            edges[start + lane] = .{ .a = aa[lane], .b = bb[lane], .c = cc[lane] };
        }
    }
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
        hullcommon.containsEdges(edges, px, py)
    else
        hullcommon.containsPrepared(x, y, slack, px, py);
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

pub fn containsOuterSIMD(
    x: []const F,
    y: []const F,
    edges: []const HullEdge,
    slack: []const F,
    v_px: VecSF,
    v_py: VecSF,
    valid: VecSB,
    mode: EdgeFunMode,
) VecSB {
    if (x.len < 3) return @splat(false);
    var inside = valid;
    if (mode == .pre_calc) {
        for (edges) |edge| {
            const a: VecSF = @splat(edge.a);
            const b: VecSF = @splat(edge.b);
            const c: VecSF = @splat(edge.c);
            inside &= a * v_px + b * v_py + c >= @as(VecSF, @splat(0));
            if (!@reduce(.Or, inside)) break;
        }
    } else {
        for (0..x.len) |ii| {
            const jj = (ii + 1) % x.len;
            inside &= edgeops.edgeFun3SIMD(
                x[ii],
                y[ii],
                x[jj],
                y[jj],
                v_px,
                v_py,
            ) >= @as(VecSF, @splat(-slack[ii]));
            if (!@reduce(.Or, inside)) break;
        }
    }
    return inside;
}

pub fn childMasksSIMD(
    leaves: anytype,
    v_px: VecSF,
    v_py: VecSF,
    outer_mask: VecSB,
    mode: EdgeFunMode,
) [S]u8 {
    var masks: @Vector(S, u8) = @splat(0);
    for (leaves, 0..) |*leaf, ii| {
        const min_x: VecSF = @splat(leaf.bbox[0]);
        const max_x: VecSF = @splat(leaf.bbox[1]);
        const min_y: VecSF = @splat(leaf.bbox[2]);
        const max_y: VecSF = @splat(leaf.bbox[3]);
        const bbox_mask = outer_mask & (v_px >= min_x) & (v_px <= max_x) &
            (v_py >= min_y) & (v_py <= max_y);
        if (!@reduce(.Or, bbox_mask)) continue;
        const count = leaf.vertex_count;
        const hit = containsOuterSIMD(
            leaf.hull_x[0..count],
            leaf.hull_y[0..count],
            leaf.prepared_edges[0..count],
            leaf.edge_slack[0..count],
            v_px,
            v_py,
            bbox_mask,
            mode,
        );
        const bit: @Vector(S, u8) = @splat(@as(u8, 1) << @as(u3, @intCast(ii)));
        masks |= @select(u8, hit, bit, @as(@Vector(S, u8), @splat(0)));
    }
    return masks;
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
        var slack: [count]F = undefined;
        prepareEdges(&x, &y, &vector_edges);
        hullcommon.prepareEdges(&x, &y, &scalar_edges);
        hullcommon.prepareEdgeSlack(&x, &y, &slack);
        for (0..count) |ii| {
            try std.testing.expectApproxEqRel(scalar_edges[ii].a, vector_edges[ii].a, 16 * std.math.floatEps(F));
            try std.testing.expectApproxEqRel(scalar_edges[ii].b, vector_edges[ii].b, 16 * std.math.floatEps(F));
            try std.testing.expectApproxEqAbs(scalar_edges[ii].c, vector_edges[ii].c, 128 * std.math.floatEps(F));
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
        inline for (.{ .on_the_fly, .pre_calc }) |mode| {
            const hits: [S]bool = containsOuterSIMD(
                &x,
                &y,
                &vector_edges,
                &slack,
                v_px,
                v_py,
                v_valid,
                mode,
            );
            for (0..S) |lane| {
                const expected = valid[lane] and (if (mode == .pre_calc)
                    hullcommon.containsEdges(&scalar_edges, px[lane], py[lane])
                else
                    hullcommon.containsPrepared(&x, &y, &slack, px[lane], py[lane]));
                try std.testing.expectEqual(expected, hits[lane]);
            }
        }
    }
}

test "multi-root SIMD child masks match scalar with inactive lanes" {
    const BezierLeaf = hullcommon.BezierLeaf;
    const x = [_]F{ 0, 0, 100, 100 };
    const y = [_]F{ 0, 100, 100, 0 };
    var leaves: [4]BezierLeaf = undefined;
    for (&leaves, 0..) |*leaf, ii| {
        const inset = 10 * @as(F, @floatFromInt(ii));
        leaf.* = .{
            .hull_x = x ++ [_]F{0} ** 5,
            .hull_y = y ++ [_]F{0} ** 5,
            .edge_slack = undefined,
            .prepared_edges = undefined,
            .bbox = .{ inset, 100 - inset, inset, 100 - inset },
            .parameter_seed = .{ 0, 0 },
            .vertex_count = 4,
        };
        hullcommon.prepareEdgeSlack(&x, &y, leaf.edge_slack[0..4]);
        prepareEdges(&x, &y, leaf.prepared_edges[0..4]);
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
    inline for (.{ .on_the_fly, .pre_calc }) |mode| {
        const masks = childMasksSIMD(&leaves, v_px, v_py, v_valid, mode);
        for (0..S) |lane| {
            const expected: u8 = if (valid[lane])
                childMask(&leaves, px[lane], py[lane], mode)
            else
                0;
            try std.testing.expectEqual(expected, masks[lane]);
        }
    }
}

pub fn prepareFourBezierLeaves(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    output: *[4]hullcommon.BezierLeaf,
    edge_fun_mode: EdgeFunMode,
) void {
    hullcommon.prepareFourBezierLeaves(
        N,
        camera,
        coords,
        output,
        edge_fun_mode,
        prepareEdges,
    );
}
