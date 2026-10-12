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

const Triangle = struct {
    x: [3]F,
    y: [3]F,
    xi: [3]F,
    eta: [3]F,
    edges: [3]HullEdge = undefined,
};

pub const CandidateScalar = struct {
    is_in: bool,
    seed_xi: F,
    seed_eta: F,
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
                        tol.hull.scal_inclusion,
                    );
                }
            }
        }

        pub inline fn isInScalar(
            self: @This(),
            px: F,
            py: F,
            mode: EdgeFunMode,
        ) CandidateScalar {
            return self.evaluateScalar(px, py, mode, true);
        }

        pub inline fn containsScalar(
            self: @This(),
            px: F,
            py: F,
            mode: EdgeFunMode,
        ) bool {
            return self.evaluateScalar(px, py, mode, false).is_in;
        }

        inline fn evaluateScalar(
            self: @This(),
            px: F,
            py: F,
            mode: EdgeFunMode,
            comptime with_seed: bool,
        ) CandidateScalar {
            const eps = tol.hull.scal_inclusion;

            inline for (self.triangles) |tri| {
                const in_tri = if (mode == .pre_calc)
                    tri.edges[0].eval(px, py) >= 0 and
                        tri.edges[1].eval(px, py) >= 0 and
                        tri.edges[2].eval(px, py) >= 0
                else blk: {
                    const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                    const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                    const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);
                    break :blk e0 >= -eps and e1 >= -eps and e2 >= -eps;
                };

                if (in_tri) {
                    if (!with_seed) return .{ .is_in = true, .seed_xi = 0, .seed_eta = 0 };
                    const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                    const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                    const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);

                    const area = rops.edgeFun3(
                        tri.x[0],
                        tri.y[0],
                        tri.x[1],
                        tri.y[1],
                        tri.x[2],
                        tri.y[2],
                    );

                    const inv_area = 1.0 / area;
                    const w0 = e1 * inv_area;
                    const w1 = e2 * inv_area;
                    const w2 = e0 * inv_area;

                    return .{
                        .is_in = true,
                        .seed_xi = w0 * tri.xi[0] + w1 * tri.xi[1] + w2 * tri.xi[2],
                        .seed_eta = w0 * tri.eta[0] + w1 * tri.eta[1] + w2 * tri.eta[2],
                    };
                }
            }

            return .{
                .is_in = false,
                .seed_xi = 0.0,
                .seed_eta = 0.0,
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
        inline for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
            c_xi += node_xi[ii];
            c_eta += node_eta[ii];
        }
        cx /= @as(F, @floatFromInt(NH));
        cy /= @as(F, @floatFromInt(NH));
        c_xi /= @as(F, @floatFromInt(NH));
        c_eta /= @as(F, @floatFromInt(NH));

        inline for (0..NH) |ii| {
            const jj = (ii + 1) % NH;
            tess.triangles[ii] = .{
                .x = .{ cx, hull_x[ii], hull_x[jj] },
                .y = .{ cy, hull_y[ii], hull_y[jj] },
                .xi = .{ c_xi, node_xi[ii], node_xi[jj] },
                .eta = .{ c_eta, node_eta[ii], node_eta[jj] },
            };
        }
    }
    return tess;
}

test "prepared tessellation edges preserve scalar containment" {
    const x = [_]F{ 4, 4, 80, 80 };
    const y = [_]F{ 4, 80, 80, 4 };
    var tess = makeTessellation(4, 4, 2, &x, &y);
    tess.prepareEdges();
    for (0..100) |yy| {
        const py: F = @as(F, @floatFromInt(yy)) + 0.5;
        for (0..100) |xx| {
            const px: F = @as(F, @floatFromInt(xx)) + 0.5;
            const old = tess.isInScalar(px, py, .on_the_fly);
            const new = tess.isInScalar(px, py, .pre_calc);
            try std.testing.expectEqual(old.is_in, new.is_in);
            try std.testing.expectEqual(old.is_in, tess.containsScalar(px, py, .on_the_fly));
            try std.testing.expectEqual(new.is_in, tess.containsScalar(px, py, .pre_calc));
        }
    }
}
