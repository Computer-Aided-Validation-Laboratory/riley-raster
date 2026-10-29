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
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const S = cfg.simd_vec_width;

const Triangle = struct {
    x: [3]F,
    y: [3]F,
    xi: [3]F,
    eta: [3]F,
    edges: [3]HullEdge = undefined,
};

pub const CandidateSeedSIMD = struct {
    v_is_in: VecSB,
    v_seed_xi: VecSF,
    v_seed_eta: VecSF,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]Triangle,

        pub fn prepareEdges(self: *@This()) void {
            for (&self.triangles) |*tri| {
                for (0..3) |ii| {
                    const jj = (ii + 1) % 3;
                    tri.edges[ii] = HullEdge.init(
                        tri.x[ii],
                        tri.y[ii],
                        tri.x[jj],
                        tri.y[jj],
                        tol.hull.simd_inclusion,
                    );
                }
            }
        }

        pub inline fn isInSIMD(
            self: @This(),
            v_px: VecSF,
            v_py: VecSF,
            mode: EdgeFunMode,
        ) CandidateSeedSIMD {
            return self.evaluateSIMD(v_px, v_py, mode, true);
        }

        pub inline fn containsSIMD(
            self: @This(),
            v_px: VecSF,
            v_py: VecSF,
            mode: EdgeFunMode,
        ) VecSB {
            return self.evaluateSIMD(v_px, v_py, mode, false).v_is_in;
        }

        inline fn evaluateSIMD(
            self: @This(),
            v_px: VecSF,
            v_py: VecSF,
            mode: EdgeFunMode,
            comptime with_seed: bool,
        ) CandidateSeedSIMD {
            const eps = tol.hull.simd_inclusion;

            const v_m_eps: VecSF = @splat(-eps);
            var v_is_in: VecSB = @splat(false);
            var v_seed_xi: VecSF = @splat(0.0);
            var v_seed_eta: VecSF = @splat(0.0);

            inline for (self.triangles) |tri| {
                const v_test0: VecSF = if (mode == .pre_calc) blk: {
                    const a0: VecSF = @splat(tri.edges[0].a);
                    const b0: VecSF = @splat(tri.edges[0].b);
                    const c0: VecSF = @splat(tri.edges[0].c);
                    break :blk a0 * v_px + b0 * v_py + c0;
                } else edgeops.edgeFun3SIMD(tri.x[0], tri.y[0], tri.x[1], tri.y[1], v_px, v_py);

                const v_test1: VecSF = if (mode == .pre_calc) blk: {
                    const a1: VecSF = @splat(tri.edges[1].a);
                    const b1: VecSF = @splat(tri.edges[1].b);
                    const c1: VecSF = @splat(tri.edges[1].c);
                    break :blk a1 * v_px + b1 * v_py + c1;
                } else edgeops.edgeFun3SIMD(tri.x[1], tri.y[1], tri.x[2], tri.y[2], v_px, v_py);

                const v_test2: VecSF = if (mode == .pre_calc) blk: {
                    const a2: VecSF = @splat(tri.edges[2].a);
                    const b2: VecSF = @splat(tri.edges[2].b);
                    const c2: VecSF = @splat(tri.edges[2].c);
                    break :blk a2 * v_px + b2 * v_py + c2;
                } else edgeops.edgeFun3SIMD(tri.x[2], tri.y[2], tri.x[0], tri.y[0], v_px, v_py);

                const threshold: VecSF = if (mode == .pre_calc) @splat(0) else v_m_eps;

                const v_in_tri = (v_test0 >= threshold) &
                    (v_test1 >= threshold) &
                    (v_test2 >= threshold);

                if (with_seed and @reduce(.Or, v_in_tri)) {
                    const v_e0 = if (mode == .pre_calc)
                        edgeops.edgeFun3SIMD(tri.x[0], tri.y[0], tri.x[1], tri.y[1], v_px, v_py)
                    else
                        v_test0;

                    const v_e1 = if (mode == .pre_calc)
                        edgeops.edgeFun3SIMD(tri.x[1], tri.y[1], tri.x[2], tri.y[2], v_px, v_py)
                    else
                        v_test1;

                    const v_e2 = if (mode == .pre_calc)
                        edgeops.edgeFun3SIMD(tri.x[2], tri.y[2], tri.x[0], tri.y[0], v_px, v_py)
                    else
                        v_test2;

                    const area = edgeops.edgeFun3(
                        tri.x[0],
                        tri.y[0],
                        tri.x[1],
                        tri.y[1],
                        tri.x[2],
                        tri.y[2],
                    );

                    const v_inv_area: VecSF = @splat(1.0 / area);
                    const v_w0 = v_e1 * v_inv_area;
                    const v_w1 = v_e2 * v_inv_area;
                    const v_w2 = v_e0 * v_inv_area;

                    const v_tri_xi0: VecSF = @splat(tri.xi[0]);
                    const v_tri_xi1: VecSF = @splat(tri.xi[1]);
                    const v_tri_xi2: VecSF = @splat(tri.xi[2]);
                    const v_tri_eta0: VecSF = @splat(tri.eta[0]);
                    const v_tri_eta1: VecSF = @splat(tri.eta[1]);
                    const v_tri_eta2: VecSF = @splat(tri.eta[2]);

                    const v_curr_xi =
                        v_w0 * v_tri_xi0 + v_w1 * v_tri_xi1 + v_w2 * v_tri_xi2;
                    const v_curr_eta =
                        v_w0 * v_tri_eta0 + v_w1 * v_tri_eta1 + v_w2 * v_tri_eta2;

                    v_seed_xi = @select(F, v_in_tri, v_curr_xi, v_seed_xi);
                    v_seed_eta = @select(F, v_in_tri, v_curr_eta, v_seed_eta);
                }
                v_is_in = v_is_in | v_in_tri;
            }
            return .{
                .v_is_in = v_is_in,
                .v_seed_xi = v_seed_xi,
                .v_seed_eta = v_seed_eta,
            };
        }
    };
}

pub fn makeTessellation(
    comptime N: usize,
    comptime NH: usize,
    comptime NT: usize,
    hull_x: []const F,
    hull_y: []const F,
) Tessellation(NT) {
    var tess = Tessellation(NT){ .triangles = undefined };

    if (N == 4) {
        // Quad4 hull: C0, C1, C2, C3
        // Local para coords: (-1,-1), (1,-1), (1,1), (-1,1)
        tess.triangles[0] = .{
            .x = .{ hull_x[0], hull_x[1], hull_x[2] },
            .y = .{ hull_y[0], hull_y[1], hull_y[2] },
            .xi = .{ -1.0, 1.0, 1.0 },
            .eta = .{ -1.0, -1.0, 1.0 },
        };
        tess.triangles[1] = .{
            .x = .{ hull_x[0], hull_x[2], hull_x[3] },
            .y = .{ hull_y[0], hull_y[2], hull_y[3] },
            .xi = .{ -1.0, 1.0, -1.0 },
            .eta = .{ -1.0, 1.0, 1.0 },
        };
    } else if (N == 6 or N == 8 or N == 9) {
        const node_xi = if (N == 6)
            [_]F{ 0.0, 0.5, 1.0, 0.5, 0.0, 0.0 }
        else
            [_]F{ -1.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0 };

        const node_eta = if (N == 6)
            [_]F{ 0.0, 0.0, 0.0, 0.5, 1.0, 0.5 }
        else
            [_]F{ -1.0, -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.0 };

        var cx: F = 0;
        var cy: F = 0;
        var c_xi: F = 0;
        var c_eta: F = 0;

        for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
            c_xi += node_xi[ii];
            c_eta += node_eta[ii];
        }
        cx /= @as(F, @floatFromInt(NH));
        cy /= @as(F, @floatFromInt(NH));
        c_xi /= @as(F, @floatFromInt(NH));
        c_eta /= @as(F, @floatFromInt(NH));

        for (0..NH) |ii| {
            const next = (ii + 1) % NH;
            tess.triangles[ii] = .{
                .x = .{ cx, hull_x[ii], hull_x[next] },
                .y = .{ cy, hull_y[ii], hull_y[next] },
                .xi = .{ c_xi, node_xi[ii], node_xi[next] },
                .eta = .{ c_eta, node_eta[ii], node_eta[next] },
            };
        }
    }

    return tess;
}

test "prepared tessellation edges preserve SIMD containment" {
    const x = [_]F{ 4, 4, 80, 80 };
    const y = [_]F{ 4, 80, 80, 4 };
    var tess = makeTessellation(4, 4, 2, &x, &y);
    tess.prepareEdges();
    for (0..100) |yy| {
        const py: VecSF = @splat(@as(F, @floatFromInt(yy)) + 0.5);
        for (0..100) |xx| {
            const px: VecSF = @splat(@as(F, @floatFromInt(xx)) + 0.5);
            const old = tess.isInSIMD(px, py, .on_the_fly);
            const new = tess.isInSIMD(px, py, .pre_calc);
            try std.testing.expectEqualDeep(old.v_is_in, new.v_is_in);
            try std.testing.expectEqualDeep(old.v_is_in, tess.containsSIMD(px, py, .on_the_fly));
            try std.testing.expectEqualDeep(new.v_is_in, tess.containsSIMD(px, py, .pre_calc));
        }
    }
}
