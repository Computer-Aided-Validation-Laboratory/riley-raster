const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const rops = @import("rasterops.zig");
const Vec3OfSlices = rops.Vec3OfSlices;

pub fn buildAdaptiveHulls(
    comptime N: usize,
    camera: *const Camera,
    dim_elem: usize,
    elem_coord_arr: *NDArray(f64),
    raster_hull: *NDArray(f64),
) !void {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N,
            f64,
            elem_coord_arr,
            ee,
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
