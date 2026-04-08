const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const tol = buildconfig.config.tolerance;
const rops = @import("rasterops.zig");
const common = @import("hull_common.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3Slices = rops.Vec3Slices;

pub const TessTriangle = struct {
    x: [3]f64,
    y: [3]f64,
    xi: [3]f64,
    eta: [3]f64,
};

pub const HullResultScalar = struct {
    is_in: bool,
    seed_xi: f64,
    seed_eta: f64,
};

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]TessTriangle,

        pub inline fn isInScalar(self: @This(), px: f64, py: f64) HullResultScalar {
            const eps = tol.hull.scalar_inclusion;
            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);
                if (e0 >= -eps and e1 >= -eps and e2 >= -eps) {
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

pub fn getTessellation(
    comptime N: usize,
    comptime NH: usize,
    comptime NT: usize,
    hull_x: []const f64,
    hull_y: []const f64,
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
            [_]f64{ 0.0, 0.5, 1.0, 0.5, 0.0, 0.0 }
        else
            [_]f64{ -1.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0 };

        const node_eta = if (N == 6)
            [_]f64{ 0.0, 0.0, 0.0, 0.5, 1.0, 0.5 }
        else
            [_]f64{ -1.0, -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.0 };

        var cx: f64 = 0;
        var cy: f64 = 0;
        var c_xi: f64 = 0;
        var c_eta: f64 = 0;
        inline for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
            c_xi += node_xi[ii];
            c_eta += node_eta[ii];
        }
        cx /= @as(f64, @floatFromInt(NH));
        cy /= @as(f64, @floatFromInt(NH));
        c_xi /= @as(f64, @floatFromInt(NH));
        c_eta /= @as(f64, @floatFromInt(NH));

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

pub const buildAdaptiveHulls = common.buildAdaptiveHulls;
