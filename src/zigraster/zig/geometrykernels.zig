const std = @import("std");
const rops = @import("rasterops.zig");
const newton = @import("newton.zig");
const shapefun = @import("shapefun.zig");
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;

pub const Strategy = enum {
    pointwise,
    incremental,
};

pub fn Tri3Kernel() type {
    return struct {
        const Self = @This();
        const N = 3;
        pub const node_n = N;
        pub const is_parent_space = false;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn getInvElemArea(nodes: Vec3OfSlices(f64)) f64 {
            return 1.0 / rops.edgeFun3(
                nodes.x[0], nodes.y[0],
                nodes.x[1], nodes.y[1],
                nodes.x[2], nodes.y[2],
            );
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), 
                                   px: f64, py: f64, 
                                   x_off: f64, y_off: f64,
                                   inv_area: f64) ?[N]f64 {
            _ = x_off; _ = y_off;
            const tol_edge: f64 = 1e-9;
            var weights: [N]f64 = undefined;
            weights[0] = rops.edgeFun3(nodes.x[1], nodes.y[1], 
                                       nodes.x[2], nodes.y[2], px, py) * inv_area;
            weights[1] = rops.edgeFun3(nodes.x[2], nodes.y[2], 
                                       nodes.x[0], nodes.y[0], px, py) * inv_area;
            weights[2] = rops.edgeFun3(nodes.x[0], nodes.y[0], 
                                       nodes.x[1], nodes.y[1], px, py) * inv_area;

            if (weights[0] >= -tol_edge and weights[1] >= -tol_edge and 
                weights[2] >= -tol_edge) {
                return weights;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var inv_z: f64 = 0.0;
            inline for (0..N) |i| {
                inv_z += weights[i] * (1.0 / nodes.z[i]);
            }
            return inv_z;
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        const N = 3;
        pub const node_n = N;
        pub const is_parent_space = false;
        pub const strategy = .incremental;

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn getDWeightsDx(nodes: Vec3OfSlices(f64), inv_area: f64, 
                                    step: f64) [N]f64 {
            return [_]f64{
                (nodes.y[2] - nodes.y[1]) * step * inv_area,
                (nodes.y[0] - nodes.y[2]) * step * inv_area,
                (nodes.y[1] - nodes.y[0]) * step * inv_area,
            };
        }

        pub inline fn getDWeightsDy(nodes: Vec3OfSlices(f64), inv_area: f64, 
                                    step: f64) [N]f64 {
            return [_]f64{
                (nodes.x[1] - nodes.x[2]) * step * inv_area,
                (nodes.x[2] - nodes.x[0]) * step * inv_area,
                (nodes.x[0] - nodes.x[1]) * step * inv_area,
            };
        }

        pub inline fn getWeightsAt(nodes: Vec3OfSlices(f64), px: f64, py: f64, 
                                   inv_area: f64) [N]f64 {
            return [_]f64{
                rops.edgeFun3(nodes.x[1], nodes.y[1], nodes.x[2], nodes.y[2], 
                              px, py) * inv_area,
                rops.edgeFun3(nodes.x[2], nodes.y[2], nodes.x[0], nodes.y[0], 
                              px, py) * inv_area,
                rops.edgeFun3(nodes.x[0], nodes.y[0], nodes.x[1], nodes.y[1], 
                              px, py) * inv_area,
            };
        }

        pub inline fn isInElement(weights: [N]f64) bool {
            const tol_edge: f64 = 1e-9;
            return weights[0] >= -tol_edge and weights[1] >= -tol_edge and 
                   weights[2] >= -tol_edge;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var inv_z: f64 = 0.0;
            inline for (0..N) |i| {
                inv_z += weights[i] * (1.0 / nodes.z[i]);
            }
            return inv_z;
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        const N = 6;
        pub const node_n = N;
        pub const is_parent_space = true;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), 
                                   px: f64, py: f64, 
                                   x_off: f64, y_off: f64,
                                   state: anytype) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            var converged = false;

            if (getTessellatedGuess(px - x_off, py - y_off, nodes.x, nodes.y, 
                                    nodes.z, &xi, &eta)) {
                converged = newton.solveInverse(N, px - x_off, py - y_off, 
                                                nodes.x, nodes.y, nodes.z, 
                                                xi, eta, &xi, &eta);
            }

            if (!converged) {
                converged = newton.solveInverse(N, px - x_off, py - y_off, 
                                                nodes.x, nodes.y, nodes.z, 
                                                1.0/3.0, 1.0/3.0, &xi, &eta);
            }

            if (converged) {
                var n_vals: [N]f64 = undefined;
                var dNu: [N]f64 = undefined;
                var dNv: [N]f64 = undefined;
                shapefun.shapeFunctions(N, xi, eta, &n_vals, &dNu, &dNv);
                return n_vals;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sw: f64 = 0.0;
            inline for (0..N) |i| {
                sw += weights[i] * nodes.z[i];
            }
            return 1.0 / sw;
        }

        fn getTessellatedGuess(txs: f64, tys: f64, ex: []const f64, ey: []const f64, 
                               ew: []const f64, xi_out: *f64, eta_out: *f64) bool {
            const tol_area: f64 = 1e-12;
            const eps = 1e-5;
            const SubTri = struct {
                n0: u8, n1: u8, n2: u8, xi0: f64, eta0: f64, xi1: f64, eta1: f64, 
                xi2: f64, eta2: f64,
            };
            const subtri_defs = [_]SubTri{
                .{ .n0 = 0, .n1 = 3, .n2 = 5, .xi0 = 0.0, .eta0 = 0.0,
                   .xi1 = 0.5, .eta1 = 0.0, .xi2 = 0.0, .eta2 = 0.5 },
                .{ .n0 = 3, .n1 = 1, .n2 = 4, .xi0 = 0.5, .eta0 = 0.0,
                   .xi1 = 1.0, .eta1 = 0.0, .xi2 = 0.5, .eta2 = 0.5 },
                .{ .n0 = 5, .n1 = 4, .n2 = 2, .xi0 = 0.0, .eta0 = 0.5,
                   .xi1 = 0.5, .eta1 = 0.5, .xi2 = 0.0, .eta2 = 1.0 },
                .{ .n0 = 3, .n1 = 4, .n2 = 5, .xi0 = 0.5, .eta0 = 0.0,
                   .xi1 = 0.5, .eta1 = 0.5, .xi2 = 0.0, .eta2 = 0.5 },
            };
            for (subtri_defs) |st| {
                const x0 = ex[st.n0] / ew[st.n0];
                const y0 = ey[st.n0] / ew[st.n0];
                const x1 = ex[st.n1] / ew[st.n1];
                const y1 = ey[st.n1] / ew[st.n1];
                const x2 = ex[st.n2] / ew[st.n2];
                const y2 = ey[st.n2] / ew[st.n2];
                const area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0);
                if (@abs(area) < tol_area) continue;
                const w0 = ((txs - x0) * (y1 - y0) - (tys - y0) * (x1 - x0)) / area;
                const w1 = ((txs - x1) * (y2 - y1) - (tys - y1) * (x2 - x1)) / area;
                const w2 = ((txs - x2) * (y0 - y2) - (tys - y2) * (x0 - x2)) / area;
                if (w0 >= -eps and w1 >= -eps and w2 >= -eps) {
                    xi_out.* = w0 * st.xi0 + w1 * st.xi1 + w2 * st.xi2;
                    eta_out.* = w0 * st.eta0 + w1 * st.eta1 + w2 * st.eta2;
                    return true;
                }
            }
            return false;
        }
    };
}

pub fn Quad4IBIKernel() type {
    return struct {
        const N = 4;
        pub const node_n = N;
        pub const is_parent_space = true;
        pub const strategy = .pointwise;

        pub const SolverParams = struct {
            ae_x: f64, ae_z: f64, be_x: f64, be_z: f64,
            ce_x: f64, ce_z: f64, de_x: f64, de_z: f64,
            af_x: f64, af_z: f64, bf_x: f64, bf_z: f64,
            cf_x: f64, cf_z: f64, df_x: f64, df_z: f64,
        };

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn getSolverParams(nodes: Vec3OfSlices(f64)) SolverParams {
            return SolverParams{
                .ae_x = nodes.x[0] - nodes.x[1] + nodes.x[2] - nodes.x[3],
                .ae_z = nodes.z[0] - nodes.z[1] + nodes.z[2] - nodes.z[3],
                .be_x = nodes.x[1] - nodes.x[0],
                .be_z = nodes.z[1] - nodes.z[0],
                .ce_x = nodes.x[3] - nodes.x[0],
                .ce_z = nodes.z[3] - nodes.z[0],
                .de_x = nodes.x[0],
                .de_z = nodes.z[0],
                .af_x = nodes.y[0] - nodes.y[1] + nodes.y[2] - nodes.y[3],
                .af_z = nodes.z[0] - nodes.z[1] + nodes.z[2] - nodes.z[3],
                .bf_x = nodes.y[1] - nodes.y[0],
                .bf_z = nodes.z[1] - nodes.z[0],
                .cf_x = nodes.y[3] - nodes.y[0],
                .cf_z = nodes.z[3] - nodes.z[0],
                .df_x = nodes.y[0],
                .df_z = nodes.z[0],
            };
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), 
                                   px: f64, py: f64, 
                                   x_off: f64, y_off: f64,
                                   solver_k: SolverParams) ?[N]f64 {
            _ = nodes;
            const txs = px - x_off;
            const tys = py - y_off;
            const ae = solver_k.ae_x - solver_k.ae_z * txs;
            const be = solver_k.be_x - solver_k.be_z * txs;
            const ce = solver_k.ce_x - solver_k.ce_z * txs;
            const de = solver_k.de_x - solver_k.de_z * txs;
            const af = solver_k.af_x - solver_k.af_z * tys;
            const bf = solver_k.bf_x - solver_k.bf_z * tys;
            const cf = solver_k.cf_x - solver_k.cf_z * tys;
            const df = solver_k.df_x - solver_k.df_z * tys;
            const qA = af * be - ae * bf;
            const qB = af * de - ae * df + be * cf - bf * ce;
            const qC = cf * de - ce * df;
            var u: f64 = -1.0;
            if (solveQuadraticRobust(qA, qB, qC, &u)) {
                const den_e = ae * u + ce;
                const den_f = af * u + cf;
                var v: f64 = -1.0;
                const tol_den = 1e-12;
                if (@abs(den_f) > @abs(den_e)) {
                    if (@abs(den_f) > tol_den) v = -(bf * u + df) / den_f;
                } else {
                    if (@abs(den_e) > tol_den) v = -(be * u + de) / den_e;
                }
                if (v >= -1e-7 and v <= 1.0 + 1e-7) {
                    return [_]f64{ 
                        (1.0 - u) * (1.0 - v), u * (1.0 - v), u * v, (1.0 - u) * v 
                    };
                }
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sw: f64 = 0.0;
            inline for (0..N) |i| {
                sw += weights[i] * nodes.z[i];
            }
            return 1.0 / sw;
        }

        fn solveQuadraticRobust(a: f64, b: f64, c: f64, u_out: *f64) bool {
            const tol_area = 1e-12;
            if (@abs(a) < tol_area) {
                if (@abs(b) < tol_area) return false;
                const u = -c / b;
                if (u >= -1e-7 and u <= 1.0 + 1e-7) {
                    u_out.* = u;
                    return true;
                }
                return false;
            }
            const det = b * b - 4.0 * a * c;
            if (det < 0) return false;
            const sdet = @sqrt(det);
            const q = -0.5 * (b + (if (b >= 0) sdet else -sdet));
            const roots = [2]f64{ q / a, c / q };
            const eps = 1e-7;
            for (roots) |r| {
                if (r >= -eps and r <= 1.0 + eps) {
                    u_out.* = r;
                    return true;
                }
            }
            return false;
        }
    };
}

pub fn Quad4NewtonKernel() type {
    return struct {
        const N = 4;
        pub const node_n = N;
        pub const is_parent_space = true;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), 
                                   px: f64, py: f64, 
                                   x_off: f64, y_off: f64,
                                   state: anytype) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            if (newton.solveInverse(N, px - x_off, py - y_off, nodes.x, nodes.y, 
                                    nodes.z, 0.5, 0.5, &xi, &eta)) {
                var n_vals: [N]f64 = undefined;
                var dNu: [N]f64 = undefined;
                var dNv: [N]f64 = undefined;
                shapefun.shapeFunctions(N, xi, eta, &n_vals, &dNu, &dNv);
                return n_vals;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sw: f64 = 0.0;
            inline for (0..N) |i| {
                sw += weights[i] * nodes.z[i];
            }
            return 1.0 / sw;
        }
    };
}

pub fn HigherOrderKernel(comptime N: usize) type {
    return struct {
        pub const node_n = N;
        pub const is_parent_space = true;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(elem_coord_arr: *const NDArray(f64), 
                                elem_ind: usize) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(N, f64, elem_coord_arr, elem_ind);
        }

        pub inline fn solveWeights(nodes: Vec3OfSlices(f64), 
                                   px: f64, py: f64, 
                                   x_off: f64, y_off: f64,
                                   state: anytype) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            if (newton.solveInverse(N, px - x_off, py - y_off, nodes.x, nodes.y, 
                                    nodes.z, 0.5, 0.5, &xi, &eta)) {
                var n_vals: [N]f64 = undefined;
                var dNu: [N]f64 = undefined;
                var dNv: [N]f64 = undefined;
                shapefun.shapeFunctions(N, xi, eta, &n_vals, &dNu, &dNv);
                return n_vals;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sw: f64 = 0.0;
            inline for (0..N) |i| {
                sw += weights[i] * nodes.z[i];
            }
            return 1.0 / sw;
        }
    };
}
