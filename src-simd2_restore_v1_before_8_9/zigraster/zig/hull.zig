const std = @import("std");
const rops = @import("rasterops.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;

pub const TessTriangle = struct {
    x: [3]f64,
    y: [3]f64,
    xi: [3]f64,
    eta: [3]f64,
};

pub const HullResult = struct {
    isIn: bool,
    guess_xi: f64,
    guess_eta: f64,
};

pub const HullResultSIMD = struct {
    isIn: @Vector(8, bool),
    guess_xi: @Vector(8, f64),
    guess_eta: @Vector(8, f64),
};

pub fn Tessellation(comptime NT: usize) type {
    return struct {
        triangles: [NT]TessTriangle,

        pub inline fn isIn(self: @This(), px: f64, py: f64) HullResult {
            const eps: f64 = 1.0e-4;
            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], px, py);
                const e1 = rops.edgeFun3(tri.x[1], tri.y[1], tri.x[2], tri.y[2], px, py);
                const e2 = rops.edgeFun3(tri.x[2], tri.y[2], tri.x[0], tri.y[0], px, py);
                if (e0 >= -eps and e1 >= -eps and e2 >= -eps) {
                    // Simple barycentric coordinates for the guess
                    const area = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], tri.x[2], tri.y[2]);
                    const inv_area = 1.0 / area;
                    const w0 = e1 * inv_area;
                    const w1 = e2 * inv_area;
                    const w2 = e0 * inv_area;
                    return .{
                        .isIn = true,
                        .guess_xi = w0 * tri.xi[0] + w1 * tri.xi[1] + w2 * tri.xi[2],
                        .guess_eta = w0 * tri.eta[0] + w1 * tri.eta[1] + w2 * tri.eta[2],
                    };
                }
            }
            return .{ .isIn = false, .guess_xi = 0, .guess_eta = 0 };
        }

        pub inline fn isInSIMD(self: @This(), v_px: @Vector(8, f64), v_py: @Vector(8, f64)) HullResultSIMD {
            const eps: f64 = 1.0e-4;
            const v_m_eps: @Vector(8, f64) = @splat(-eps);
            var v_isIn: @Vector(8, bool) = @splat(false);
            var v_guess_xi: @Vector(8, f64) = @splat(0.0);
            var v_guess_eta: @Vector(8, f64) = @splat(0.0);
            
            inline for (self.triangles) |tri| {
                const e0 = rops.edgeFun3SIMD(tri.x[0], tri.y[0], tri.x[1], tri.y[1], v_px, v_py);
                const e1 = rops.edgeFun3SIMD(tri.x[1], tri.y[1], tri.x[2], tri.y[2], v_px, v_py);
                const e2 = rops.edgeFun3SIMD(tri.x[2], tri.y[2], tri.x[0], tri.y[0], v_px, v_py);
                
                const v_in_tri = (e0 >= v_m_eps) & (e1 >= v_m_eps) & (e2 >= v_m_eps);
                
                if (@reduce(.Or, v_in_tri)) {
                    const area = rops.edgeFun3(tri.x[0], tri.y[0], tri.x[1], tri.y[1], tri.x[2], tri.y[2]);
                    const v_inv_area: @Vector(8, f64) = @splat(1.0 / area);
                    const v_w0 = e1 * v_inv_area;
                    const v_w1 = e2 * v_inv_area;
                    const v_w2 = e0 * v_inv_area;
                    
                    const v_tri_xi0: @Vector(8, f64) = @splat(tri.xi[0]);
                    const v_tri_xi1: @Vector(8, f64) = @splat(tri.xi[1]);
                    const v_tri_xi2: @Vector(8, f64) = @splat(tri.xi[2]);
                    const v_tri_eta0: @Vector(8, f64) = @splat(tri.eta[0]);
                    const v_tri_eta1: @Vector(8, f64) = @splat(tri.eta[1]);
                    const v_tri_eta2: @Vector(8, f64) = @splat(tri.eta[2]);

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
) Tessellation(if (N == 4) 2 else if (N == 6) 6 else 8) {
    const NT = if (N == 4) 2 else if (N == 6) 6 else 8;
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
        const NH = if (N == 6) 6 else 8;
        var cx: f64 = 0;
        var cy: f64 = 0;
        var c_xi: f64 = 0;
        var c_eta: f64 = 0;

        // Define parametric centers and boundary node coordinates
        // Tri6: boundary nodes in order are 0,3,1,4,2,5
        // Quad8/9: boundary nodes in order are 0,4,1,5,2,6,3,7
        const node_xi = if (N == 6) 
            [_]f64{ 0.0, 0.5, 1.0, 0.5, 0.0, 0.0 }
        else 
            [_]f64{ -1.0, 0.0, 1.0, 1.0, 1.0, 0.0, -1.0, -1.0 };

        const node_eta = if (N == 6) 
            [_]f64{ 0.0, 0.0, 0.0, 0.5, 1.0, 0.5 }
        else 
            [_]f64{ -1.0, -1.0, -1.0, 0.0, 1.0, 1.0, 1.0, 0.0 };

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
