const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const tol = buildconfig.config.tolerance;
const rops = @import("rasterops.zig");
const common = @import("hull_common.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;
const S = cfg.simd_vector_width;

pub const TessTriangle = struct {
    x: [3]f64,
    y: [3]f64,
    xi: [3]f64,
    eta: [3]f64,
};

pub const HullResultSIMD = struct {
    isIn: @Vector(S, bool),
    guess_xi: @Vector(S, f64),
    guess_eta: @Vector(S, f64),
};

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]TessTriangle,

        pub inline fn isInSIMD(
            self: @This(),
            v_px: @Vector(S, f64),
            v_py: @Vector(S, f64),
        ) HullResultSIMD {
            const eps = tol.hull.simd_inclusion;
            const v_m_eps: @Vector(S, f64) = @splat(-eps);
            var v_isIn: @Vector(S, bool) = @splat(false);
            var v_guess_xi: @Vector(S, f64) = @splat(0.0);
            var v_guess_eta: @Vector(S, f64) = @splat(0.0);

            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3SIMD(
                    tri.x[0],
                    tri.y[0],
                    tri.x[1],
                    tri.y[1],
                    v_px,
                    v_py,
                );
                const e1 = rops.edgeFun3SIMD(
                    tri.x[1],
                    tri.y[1],
                    tri.x[2],
                    tri.y[2],
                    v_px,
                    v_py,
                );
                const e2 = rops.edgeFun3SIMD(
                    tri.x[2],
                    tri.y[2],
                    tri.x[0],
                    tri.y[0],
                    v_px,
                    v_py,
                );

                const v_in_tri = (e0 >= v_m_eps) & (e1 >= v_m_eps) & (e2 >= v_m_eps);

                if (@reduce(.Or, v_in_tri)) {
                    const area = rops.edgeFun3(
                        tri.x[0],
                        tri.y[0],
                        tri.x[1],
                        tri.y[1],
                        tri.x[2],
                        tri.y[2],
                    );
                    const v_inv_area: @Vector(S, f64) = @splat(1.0 / area);
                    const v_w0 = e1 * v_inv_area;
                    const v_w1 = e2 * v_inv_area;
                    const v_w2 = e0 * v_inv_area;

                    const v_tri_xi0: @Vector(S, f64) = @splat(tri.xi[0]);
                    const v_tri_xi1: @Vector(S, f64) = @splat(tri.xi[1]);
                    const v_tri_xi2: @Vector(S, f64) = @splat(tri.xi[2]);
                    const v_tri_eta0: @Vector(S, f64) = @splat(tri.eta[0]);
                    const v_tri_eta1: @Vector(S, f64) = @splat(tri.eta[1]);
                    const v_tri_eta2: @Vector(S, f64) = @splat(tri.eta[2]);

                    const v_curr_xi = v_w0 * v_tri_xi0 + v_w1 * v_tri_xi1 + v_w2 * v_tri_xi2;
                    const v_curr_eta = v_w0 * v_tri_eta0 + v_w1 * v_tri_eta1 + v_w2 * v_tri_eta2;

                    v_guess_xi = @select(f64, v_in_tri, v_curr_xi, v_guess_xi);
                    v_guess_eta = @select(f64, v_in_tri, v_curr_eta, v_guess_eta);
                    v_isIn = v_isIn | v_in_tri;
                }
            }
            return .{ .isIn = v_isIn, .guess_xi = v_guess_xi, .guess_eta = v_guess_eta };
        }
    };
}

pub fn getTessellation(
    comptime N: usize,
    hull_x: []const f64,
    hull_y: []const f64,
) Tessellation(common.tessTrianglesNum(N)) {
    const NT: comptime_int = common.tessTrianglesNum(N);
    var tess = Tessellation(NT){ .triangles = undefined };

    if (N == 4) {
        // Quad4 hull: C0, C1, C2, C3
        // Local parametric coords: (-1,-1), (1,-1), (1,1), (-1,1)
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
            [_]f64{ 0.0, 0.5, 1.0, 0.5, 0.0, 0.0 }
        else
            [_]f64{ -1.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0 };

        const node_eta = if (N == 6)
            [_]f64{ 0.0, 0.0, 0.0, 0.5, 1.0, 0.5 }
        else
            [_]f64{ -1.0, -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.0 };

        const NH = common.hullNodesNum(N);
        var cx: f64 = 0;
        var cy: f64 = 0;
        var c_xi: f64 = 0;
        var c_eta: f64 = 0;

        for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
            c_xi += node_xi[ii];
            c_eta += node_eta[ii];
        }
        cx /= @as(f64, @floatFromInt(NH));
        cy /= @as(f64, @floatFromInt(NH));
        c_xi /= @as(f64, @floatFromInt(NH));
        c_eta /= @as(f64, @floatFromInt(NH));

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

pub const buildAdaptiveHulls = common.buildAdaptiveHulls;
