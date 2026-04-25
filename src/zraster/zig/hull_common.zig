// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const CameraPrepared = @import("camera.zig").CameraPrepared;
const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;
const rops = @import("rasterops.zig");
const Vec3Slices = rops.Vec3Slices;
const cam = @import("camera.zig");

const geomkerns = @import("geometrykernels.zig");
const MeshType = geomkerns.MeshType;

pub fn AdaptiveHullPoints(comptime N: usize) type {
    const NH = blk: {
        for (std.enums.values(MeshType)) |mt| {
            if (mt.getNodesNum() == N) {
                // Special case for tri3 as it doesn't use this path but we need a valid NH
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

pub fn GatheredElemCoords(comptime N: usize) type {
    return struct {
        x: [N]f64,
        y: [N]f64,
        z: [N]f64,
    };
}

pub fn buildAdaptiveHullPoints(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords_elem: GatheredElemCoords(N),
) AdaptiveHullPoints(N) {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    var lx: [N]f64 = undefined;
    var ly: [N]f64 = undefined;
    for (0..N) |nn| {
        lx[nn] = coords_elem.x[nn] / coords_elem.z[nn] + x_off;
        ly[nn] = coords_elem.y[nn] / coords_elem.z[nn] + y_off;
    }

    var hull_points: AdaptiveHullPoints(N) = undefined;
    if (N == 4) {
        inline for (0..4) |nn| {
            hull_points.x[nn] = lx[nn];
            hull_points.y[nn] = ly[nn];
        }
    } else if (N == 6) {
        const edges = [3][3]usize{
            .{ 0, 1, 3 },
            .{ 1, 2, 4 },
            .{ 2, 0, 5 },
        };

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
            hull_points.x[ii * 2 + 0] = lx[p0];
            hull_points.y[ii * 2 + 0] = ly[p0];
            if (edge_val < 0) {
                hull_points.x[ii * 2 + 1] = 2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
                hull_points.y[ii * 2 + 1] = 2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
            } else {
                hull_points.x[ii * 2 + 1] = lx[pm];
                hull_points.y[ii * 2 + 1] = ly[pm];
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
            hull_points.x[ii * 2 + 0] = lx[p0];
            hull_points.y[ii * 2 + 0] = ly[p0];
            if (edge_val < 0) {
                hull_points.x[ii * 2 + 1] = 2.0 * lx[pm] - 0.5 * (lx[p0] + lx[p1]);
                hull_points.y[ii * 2 + 1] = 2.0 * ly[pm] - 0.5 * (ly[p0] + ly[p1]);
            } else {
                hull_points.x[ii * 2 + 1] = lx[pm];
                hull_points.y[ii * 2 + 1] = ly[pm];
            }
        }
    }

    return hull_points;
}

pub fn buildAdaptiveHulls(
    comptime N: usize,
    camera: *const CameraPrepared,
    dim_elem: usize,
    elem_coord_arr: *NDArray(f64),
    raster_hull: *NDArray(f64),
) !void {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cr: Vec3Slices(f64) = try rops.loadElemVec3Slices(
            N,
            f64,
            elem_coord_arr,
            ee,
        );

        // Hull is formed in screen/raster space coords so we do the perspective divide
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
                const edge_val = rops.edgeFun3(
                    lx[p1],
                    ly[p1],
                    lx[p2],
                    ly[p2],
                    lx[pm],
                    ly[pm],
                );
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
                const edge_val = rops.edgeFun3(
                    lx[p1],
                    ly[p1],
                    lx[p2],
                    ly[p2],
                    lx[pm],
                    ly[pm],
                );
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
