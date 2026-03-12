const std = @import("std");
const rops = @import("rasterops.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;

pub const HullEdge = struct {
    a: f64,
    b: f64,
    c: f64,
};

pub fn getHullEdges(
    comptime NH: usize,
    hull_x: []const f64,
    hull_y: []const f64,
    edges: *[NH]HullEdge,
) void {
    inline for (0..NH) |ii| {
        const jj = (ii + 1) % NH;
        const x0 = hull_x[ii];
        const y0 = hull_y[ii];
        const x1 = hull_x[jj];
        const y1 = hull_y[jj];

        edges[ii] = .{
            .a = y1 - y0,
            .b = x0 - x1,
            .c = x1 * y0 - x0 * y1,
        };
    }
}

pub inline fn isInHull(
    comptime NH: usize,
    edges: [NH]HullEdge,
    px: f64,
    py: f64,
) bool {
    const eps: f64 = 1e-2;
    inline for (0..NH) |ii| {
        if (edges[ii].a * px + edges[ii].b * py + edges[ii].c < -eps) return false;
    }
    return true;
}

pub const TessTriangle = struct {
    x: [3]f64,
    y: [3]f64,
};

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]TessTriangle,

        pub inline fn isIn(self: @This(), px: f64, py: f64) bool {
            const eps: f64 = 1.0;
            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);
                if (e0 >= -eps and e1 >= -eps and e2 >= -eps) return true;
            }
            return false;
        }
    };
}

pub fn getTessellation(
    comptime N: usize,
    hull_x: []const f64,
    hull_y: []const f64,
) Tessellation(if (N == 4) 2 else if (N == 6) 6 else 8) {
    const NT = if (N == 4) 2 else if (N == 6) 6 else 8;
    var tess = Tessellation(NT){ .triangles = undefined };

    if (N == 4) {
        // Quad4 hull: C0, C1, C2, C3
        tess.triangles[0] = .{
            .x = .{ hull_x[0], hull_x[1], hull_x[2] },
            .y = .{ hull_y[0], hull_y[1], hull_y[2] },
        };
        tess.triangles[1] = .{
            .x = .{ hull_x[0], hull_x[2], hull_x[3] },
            .y = .{ hull_y[0], hull_y[2], hull_y[3] },
        };
    } else if (N == 6 or N == 8 or N == 9) { 
        const NH = if (N == 6) 6 else 8;
        var cx: f64 = 0;
        var cy: f64 = 0;
        inline for (0..NH) |ii| {
            cx += hull_x[ii];
            cy += hull_y[ii];
        }
        cx /= @as(f64, @floatFromInt(NH));
        cy /= @as(f64, @floatFromInt(NH));

        inline for (0..NH) |ii| {
            const jj = (ii + 1) % NH;
            tess.triangles[ii] = .{
                .x = .{ cx, hull_x[ii], hull_x[jj] },
                .y = .{ cy, hull_y[ii], hull_y[jj] },
            };
        }
    }
    return tess;
}

pub fn buildAdaptiveHulls(comptime N: usize,
                             camera: *const Camera,
                             dim_elem: usize,
                             elem_coord_arr: *NDArray(f64),
                             raster_hull: *NDArray(f64)) !void {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
        );

        var lx: [N]f64 = undefined;
        var ly: [N]f64 = undefined;
        for (0..N) |ii| {
            lx[ii] = cr.x[ii] / cr.z[ii] + x_off;
            ly[ii] = cr.y[ii] / cr.z[ii] + y_off;
        }

        if (N == 4) {
            inline for (0..4) |ii| {
                raster_hull.set(&[_]usize{ ee, 0, ii }, lx[ii]);
                raster_hull.set(&[_]usize{ ee, 1, ii }, ly[ii]);
            }
        } else if (N == 6) {
            const edges = [3][3]usize{
                .{ 0, 1, 3 },
                .{ 1, 2, 4 },
                .{ 2, 0, 5 },
            };

            inline for (edges, 0..) |edge, ii| {
                const p1 = edge[0];
                const p2 = edge[1];
                const pm = edge[2];
                const edge_val = rops.edgeFun3(lx[p1], ly[p1], lx[p2], ly[p2], lx[pm], ly[pm]);
                raster_hull.set(&[_]usize{ ee, 0, ii * 2 }, lx[p1]);
                raster_hull.set(&[_]usize{ ee, 1, ii * 2 }, ly[p1]);
                if (edge_val < 0) {
                    const cx_node = 2.0 * lx[pm] - 0.5 * (lx[p1] + lx[p2]);
                    const cy_node = 2.0 * ly[pm] - 0.5 * (ly[p1] + ly[p2]);
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, cx_node);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, cy_node);
                } else {
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, lx[pm]);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, ly[pm]);
                }
            }
        } else if (N == 8 or N == 9) {
            const edges = [4][3]usize{
                .{ 0, 1, 4 },
                .{ 1, 2, 5 },
                .{ 2, 3, 6 },
                .{ 3, 0, 7 },
            };

            inline for (edges, 0..) |edge, ii| {
                const p1 = edge[0];
                const p2 = edge[1];
                const pm = edge[2];
                const edge_val = rops.edgeFun3(lx[p1], ly[p1], lx[p2], ly[p2], lx[pm], ly[pm]);
                raster_hull.set(&[_]usize{ ee, 0, ii * 2 }, lx[p1]);
                raster_hull.set(&[_]usize{ ee, 1, ii * 2 }, ly[p1]);
                if (edge_val < 0) {
                    const cx_node = 2.0 * lx[pm] - 0.5 * (lx[p1] + lx[p2]);
                    const cy_node = 2.0 * ly[pm] - 0.5 * (ly[p1] + ly[p2]);
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, cx_node);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, cy_node);
                } else {
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, lx[pm]);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, ly[pm]);
                }
            }
        }
    }
}
