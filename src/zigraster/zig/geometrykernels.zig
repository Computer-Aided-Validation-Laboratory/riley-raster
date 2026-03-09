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

pub const CoordSpace = enum {
    raster,
    camera,
};

pub fn Tri3Kernel() type {
    return struct {
        const Self = @This();
        const N = 3;
        pub const node_n = N;
        pub const coord_space = CoordSpace.raster;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
        }

        pub inline fn getInvElemArea(nodes: Vec3OfSlices(f64)) f64 {
            return 1.0 / rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
            );
        }

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            inverse_area: f64,
        ) ?[N]f64 {
            _ = x_offset;
            _ = y_offset;
            const tolerance_edge: f64 = 1e-9;
            var weights: [N]f64 = undefined;
            weights[0] = rops.edgeFun3(
                nodes.x[1],
                nodes.y[1],
                nodes.x[2],
                nodes.y[2],
                pixel_x,
                pixel_y,
            ) * inverse_area;
            weights[1] = rops.edgeFun3(
                nodes.x[2],
                nodes.y[2],
                nodes.x[0],
                nodes.y[0],
                pixel_x,
                pixel_y,
            ) * inverse_area;
            weights[2] = rops.edgeFun3(
                nodes.x[0],
                nodes.y[0],
                nodes.x[1],
                nodes.y[1],
                pixel_x,
                pixel_y,
            ) * inverse_area;

            if (weights[0] >= -tolerance_edge and
                weights[1] >= -tolerance_edge and
                weights[2] >= -tolerance_edge)
            {
                return weights;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var inverse_z: f64 = 0.0;
            inline for (0..N) |index| {
                inverse_z += weights[index] * (1.0 / nodes.z[index]);
            }
            return inverse_z;
        }
    };
}

pub fn Tri3OptKernel() type {
    return struct {
        const N = 3;
        pub const node_n = N;
        pub const coord_space = CoordSpace.raster;
        pub const strategy = .incremental;

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
        }

        pub inline fn getDWeightsDx(
            nodes: Vec3OfSlices(f64),
            inverse_area: f64,
            step_size: f64,
        ) [N]f64 {
            return [_]f64{
                (nodes.y[2] - nodes.y[1]) * step_size * inverse_area,
                (nodes.y[0] - nodes.y[2]) * step_size * inverse_area,
                (nodes.y[1] - nodes.y[0]) * step_size * inverse_area,
            };
        }

        pub inline fn getDWeightsDy(
            nodes: Vec3OfSlices(f64),
            inverse_area: f64,
            step_size: f64,
        ) [N]f64 {
            return [_]f64{
                (nodes.x[1] - nodes.x[2]) * step_size * inverse_area,
                (nodes.x[2] - nodes.x[0]) * step_size * inverse_area,
                (nodes.x[0] - nodes.x[1]) * step_size * inverse_area,
            };
        }

        pub inline fn getWeightsAt(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            inverse_area: f64,
        ) [N]f64 {
            return [_]f64{
                rops.edgeFun3(
                    nodes.x[1],
                    nodes.y[1],
                    nodes.x[2],
                    nodes.y[2],
                    pixel_x,
                    pixel_y,
                ) * inverse_area,
                rops.edgeFun3(
                    nodes.x[2],
                    nodes.y[2],
                    nodes.x[0],
                    nodes.y[0],
                    pixel_x,
                    pixel_y,
                ) * inverse_area,
                rops.edgeFun3(
                    nodes.x[0],
                    nodes.y[0],
                    nodes.x[1],
                    nodes.y[1],
                    pixel_x,
                    pixel_y,
                ) * inverse_area,
            };
        }

        pub inline fn isInElement(weights: [N]f64) bool {
            const tolerance_edge: f64 = 1e-9;
            return weights[0] >= -tolerance_edge and
                weights[1] >= -tolerance_edge and
                weights[2] >= -tolerance_edge;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var inverse_z: f64 = 0.0;
            inline for (0..N) |index| {
                inverse_z += weights[index] * (1.0 / nodes.z[index]);
            }
            return inverse_z;
        }
    };
}

pub fn Tri6Kernel() type {
    return struct {
        const N = 6;
        pub const node_n = N;
        pub const coord_space = CoordSpace.camera;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
        }

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            var converged = false;

            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;

            if (getTessellatedGuess(
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                &xi,
                &eta,
            )) {
                converged = newton.solveInverse(
                    N,
                    target_x,
                    target_y,
                    nodes.x,
                    nodes.y,
                    nodes.z,
                    xi,
                    eta,
                    &xi,
                    &eta,
                );
            }

            if (!converged) {
                converged = newton.solveInverse(
                    N,
                    target_x,
                    target_y,
                    nodes.x,
                    nodes.y,
                    nodes.z,
                    1.0 / 3.0,
                    1.0 / 3.0,
                    &xi,
                    &eta,
                );
            }

            if (converged) {
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;
                shapefun.shapeFunctions(
                    N,
                    xi,
                    eta,
                    &node_values,
                    &deriv_nu,
                    &deriv_nv,
                );
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sum_weighted_z: f64 = 0.0;
            inline for (0..N) |index| {
                sum_weighted_z += weights[index] * nodes.z[index];
            }
            return 1.0 / sum_weighted_z;
        }

        fn getTessellatedGuess(
            target_x: f64,
            target_y: f64,
            element_x: []const f64,
            element_y: []const f64,
            element_w: []const f64,
            xi_out: *f64,
            eta_out: *f64,
        ) bool {
            const tolerance_area: f64 = 1e-12;
            const epsilon = 1e-5;
            const SubTriangle = struct {
                node0: u8,
                node1: u8,
                node2: u8,
                xi0: f64,
                eta0: f64,
                xi1: f64,
                eta1: f64,
                xi2: f64,
                eta2: f64,
            };
            const sub_triangle_definitions = [_]SubTriangle{
                .{
                    .node0 = 0,
                    .node1 = 3,
                    .node2 = 5,
                    .xi0 = 0.0,
                    .eta0 = 0.0,
                    .xi1 = 0.5,
                    .eta1 = 0.0,
                    .xi2 = 0.0,
                    .eta2 = 0.5,
                },
                .{
                    .node0 = 3,
                    .node1 = 1,
                    .node2 = 4,
                    .xi0 = 0.5,
                    .eta0 = 0.0,
                    .xi1 = 1.0,
                    .eta1 = 0.0,
                    .xi2 = 0.5,
                    .eta2 = 0.5,
                },
                .{
                    .node0 = 5,
                    .node1 = 4,
                    .node2 = 2,
                    .xi0 = 0.0,
                    .eta0 = 0.5,
                    .xi1 = 0.5,
                    .eta1 = 0.5,
                    .xi2 = 0.0,
                    .eta2 = 1.0,
                },
                .{
                    .node0 = 3,
                    .node1 = 4,
                    .node2 = 5,
                    .xi0 = 0.5,
                    .eta0 = 0.0,
                    .xi1 = 0.5,
                    .eta1 = 0.5,
                    .xi2 = 0.0,
                    .eta2 = 0.5,
                },
            };
            for (sub_triangle_definitions) |sub_tri| {
                const x0 = element_x[sub_tri.node0] / element_w[sub_tri.node0];
                const y0 = element_y[sub_tri.node0] / element_w[sub_tri.node0];
                const x1 = element_x[sub_tri.node1] / element_w[sub_tri.node1];
                const y1 = element_y[sub_tri.node1] / element_w[sub_tri.node1];
                const x2 = element_x[sub_tri.node2] / element_w[sub_tri.node2];
                const y2 = element_y[sub_tri.node2] / element_w[sub_tri.node2];
                const area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0);
                if (@abs(area) < tolerance_area) {
                    continue;
                }
                const weight0 = ((target_x - x0) * (y1 - y0) - (target_y - y0) * (x1 - x0)) / area;
                const weight1 = ((target_x - x1) * (y2 - y1) - (target_y - y1) * (x2 - x1)) / area;
                const weight2 = ((target_x - x2) * (y0 - y2) - (target_y - y2) * (x0 - x2)) / area;
                if (weight0 >= -epsilon and weight1 >= -epsilon and weight2 >= -epsilon) {
                    xi_out.* = weight0 * sub_tri.xi0 + weight1 * sub_tri.xi1 + weight2 * sub_tri.xi2;
                    eta_out.* = weight0 * sub_tri.eta0 + weight1 * sub_tri.eta1 + weight2 * sub_tri.eta2;
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
        pub const coord_space = CoordSpace.camera;
        pub const strategy = .pointwise;

        pub const SolverParams = struct {
            ae_x: f64,
            ae_z: f64,
            be_x: f64,
            be_z: f64,
            ce_x: f64,
            ce_z: f64,
            de_x: f64,
            de_z: f64,
            af_x: f64,
            af_z: f64,
            bf_x: f64,
            bf_z: f64,
            cf_x: f64,
            cf_z: f64,
            df_x: f64,
            df_z: f64,
        };

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
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

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            solver_params: SolverParams,
        ) ?[N]f64 {
            _ = nodes;
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;
            const ae = solver_params.ae_x - solver_params.ae_z * target_x;
            const be = solver_params.be_x - solver_params.be_z * target_x;
            const ce = solver_params.ce_x - solver_params.ce_z * target_x;
            const de = solver_params.de_x - solver_params.de_z * target_x;
            const af = solver_params.af_x - solver_params.af_z * target_y;
            const bf = solver_params.bf_x - solver_params.bf_z * target_y;
            const cf = solver_params.cf_x - solver_params.cf_z * target_y;
            const df = solver_params.df_x - solver_params.df_z * target_y;
            const quad_a = af * be - ae * bf;
            const quad_b = af * de - ae * df + be * cf - bf * ce;
            const quad_c = cf * de - ce * df;
            var coordinate_u: f64 = -1.0;
            if (solveQuadraticRobust(quad_a, quad_b, quad_c, &coordinate_u)) {
                const denominator_e = ae * coordinate_u + ce;
                const denominator_f = af * coordinate_u + cf;
                var coordinate_v: f64 = -1.0;
                const tolerance_denominator = 1e-12;
                if (@abs(denominator_f) > @abs(denominator_e)) {
                    if (@abs(denominator_f) > tolerance_denominator) {
                        coordinate_v = -(bf * coordinate_u + df) / denominator_f;
                    }
                } else {
                    if (@abs(denominator_e) > tolerance_denominator) {
                        coordinate_v = -(be * coordinate_u + de) / denominator_e;
                    }
                }
                if (coordinate_v >= -1e-7 and coordinate_v <= 1.0 + 1e-7) {
                    return [_]f64{
                        (1.0 - coordinate_u) * (1.0 - coordinate_v),
                        coordinate_u * (1.0 - coordinate_v),
                        coordinate_u * coordinate_v,
                        (1.0 - coordinate_u) * coordinate_v,
                    };
                }
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sum_weighted_z: f64 = 0.0;
            inline for (0..N) |index| {
                sum_weighted_z += weights[index] * nodes.z[index];
            }
            return 1.0 / sum_weighted_z;
        }

        fn solveQuadraticRobust(
            a_coefficient: f64,
            b_coefficient: f64,
            c_coefficient: f64,
            root_output: *f64,
        ) bool {
            const tolerance_area = 1e-12;
            if (@abs(a_coefficient) < tolerance_area) {
                if (@abs(b_coefficient) < tolerance_area) {
                    return false;
                }
                const root = -c_coefficient / b_coefficient;
                if (root >= -1e-7 and root <= 1.0 + 1e-7) {
                    root_output.* = root;
                    return true;
                }
                return false;
            }
            const discriminant = b_coefficient * b_coefficient - 4.0 * a_coefficient * c_coefficient;
            if (discriminant < 0) {
                return false;
            }
            const sqrt_discriminant = @sqrt(discriminant);
            const intermediate_q = -0.5 * (b_coefficient + (if (b_coefficient >= 0)
                sqrt_discriminant
            else
                -sqrt_discriminant));
            const roots = [2]f64{
                intermediate_q / a_coefficient,
                c_coefficient / intermediate_q,
            };
            const epsilon = 1e-7;
            for (roots) |root| {
                if (root >= -epsilon and root <= 1.0 + epsilon) {
                    root_output.* = root;
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
        pub const coord_space = CoordSpace.camera;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
        }

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;
            if (newton.solveInverse(
                N,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                0.5,
                0.5,
                &xi,
                &eta,
            )) {
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;
                shapefun.shapeFunctions(
                    N,
                    xi,
                    eta,
                    &node_values,
                    &deriv_nu,
                    &deriv_nv,
                );
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sum_weighted_z: f64 = 0.0;
            inline for (0..N) |index| {
                sum_weighted_z += weights[index] * nodes.z[index];
            }
            return 1.0 / sum_weighted_z;
        }
    };
}

pub fn HigherOrderKernel(comptime N: usize) type {
    return struct {
        pub const node_n = N;
        pub const coord_space = CoordSpace.camera;
        pub const strategy = .pointwise;

        pub inline fn loadNodes(
            element_coordinate_array: *const NDArray(f64),
            element_index: usize,
        ) !Vec3OfSlices(f64) {
            return try rops.loadVec3SlicesFromElemArray(
                N,
                f64,
                element_coordinate_array,
                element_index,
            );
        }

        pub inline fn solveWeights(
            nodes: Vec3OfSlices(f64),
            pixel_x: f64,
            pixel_y: f64,
            x_offset: f64,
            y_offset: f64,
            state: anytype,
        ) ?[N]f64 {
            _ = state;
            var xi: f64 = 0.0;
            var eta: f64 = 0.0;
            const target_x = pixel_x - x_offset;
            const target_y = pixel_y - y_offset;
            if (newton.solveInverse(
                N,
                target_x,
                target_y,
                nodes.x,
                nodes.y,
                nodes.z,
                0.5,
                0.5,
                &xi,
                &eta,
            )) {
                var node_values: [N]f64 = undefined;
                var deriv_nu: [N]f64 = undefined;
                var deriv_nv: [N]f64 = undefined;
                shapefun.shapeFunctions(
                    N,
                    xi,
                    eta,
                    &node_values,
                    &deriv_nu,
                    &deriv_nv,
                );
                return node_values;
            }
            return null;
        }

        pub inline fn calcInvZ(nodes: Vec3OfSlices(f64), weights: [N]f64) f64 {
            var sum_weighted_z: f64 = 0.0;
            inline for (0..N) |index| {
                sum_weighted_z += weights[index] * nodes.z[index];
            }
            return 1.0 / sum_weighted_z;
        }
    };
}
