const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const F = buildconfig.F;
const cam = @import("../riley/zig/camera.zig");
const coherentseed = @import("../riley/zig/coherentseed.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const hull = @import("../riley/zig/hull.zig");
const multiroot = @import("../riley/zig/multiroothierarchy.zig");
const newton = @import("../riley/zig/newton.zig");
const rops = @import("../riley/zig/rasterops.zig");
const rotation = @import("../riley/zig/rotation.zig");
const shapefun = @import("../riley/zig/shapefun.zig");

const SeedStats = struct {
    rays: usize = 0,
    overlap: usize = 0,
    visible: usize = 0,
    visible_overlap: usize = 0,
    first_front: usize = 0,
    first_nearest: usize = 0,
    overlap_first_front: usize = 0,
    d3_found: usize = 0,
    d3_nearest: usize = 0,
    overlap_d3_found: usize = 0,
    diverse_found: usize = 0,
    diverse_nearest: usize = 0,
    overlap_diverse_found: usize = 0,
    full_found: usize = 0,
    full_nearest: usize = 0,
    overlap_full_found: usize = 0,
    expanded_d3_found: usize = 0,
    expanded_d3_nearest: usize = 0,
    expanded_full_found: usize = 0,
    expanded_full_nearest: usize = 0,
    half_d3_found: usize = 0,
    half_d3_nearest: usize = 0,
    printed_full_misses: usize = 0,

    fn print(self: @This(), comptime N: usize, split: F) void {
        std.debug.print(
            "multi-root seeds N={d} split={d:.2}: rays={d} overlap={d} " ++
                "visible={d} visible_overlap={d} first_front={d} " ++
                "first_nearest={d} overlap_first={d} D3_found={d} " ++
                "D3_nearest={d} overlap_D3={d} diverse_found={d} " ++
                "diverse_nearest={d} overlap_diverse={d} full_found={d} " ++
                "full_nearest={d} overlap_full={d} " ++
                "expanded_D3={d}/{d} expanded_full={d}/{d} " ++
                "half_D3={d}/{d}\n",
            .{
                N,
                split,
                self.rays,
                self.overlap,
                self.visible,
                self.visible_overlap,
                self.first_front,
                self.first_nearest,
                self.overlap_first_front,
                self.d3_found,
                self.d3_nearest,
                self.overlap_d3_found,
                self.diverse_found,
                self.diverse_nearest,
                self.overlap_diverse_found,
                self.full_found,
                self.full_nearest,
                self.overlap_full_found,
                self.expanded_d3_found,
                self.expanded_d3_nearest,
                self.expanded_full_found,
                self.expanded_full_nearest,
                self.half_d3_found,
                self.half_d3_nearest,
            },
        );
    }
};

/// A smooth parabolic cylinder. Its physical x-z tangent never vanishes,
/// but its pinhole projection folds, giving two intersections on one ray.
pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    _ = io;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const local_alloc = arena.allocator();
    const camera = try cam.CameraPrepared.init(local_alloc, .{
        .pixels_num = .{ 100, 100 },
        .pixels_size = .{ 5.3e-6, 5.3e-6 },
        .pos_world = .{ .vec = .{ 0, 0, -1 } },
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = .{ .vec = .{ 0, 0, 0 } },
        .focal_length = 5.0e-2,
        .sub_sample = 1,
    });
    inline for (.{ 4, 6, 8, 9 }) |N| {
        const parents = comptime gk.parentNodeCoords(N);
        const center = [2]F{
            if (N == 6) 1.0 / 3.0 else 0,
            if (N == 6) 1.0 / 3.0 else 0,
        };
        const expected_count: usize = if (N == 9) 17 else 2 * N + 1;
        try std.testing.expectEqual(expected_count, gk.multiRootSeedCount(N));
        for (0..N) |nn| {
            const node = gk.multiRootSeedCoords(N, @intCast(nn));
            try std.testing.expectEqualDeep(parents[nn], node);
            if (N == 9 and nn == 8) continue;
            const midpoint = gk.multiRootSeedCoords(N, @intCast(N + nn));
            try std.testing.expectApproxEqAbs(
                0.5 * (center[0] + node[0]),
                midpoint[0],
                1e-14,
            );
            try std.testing.expectApproxEqAbs(
                0.5 * (center[1] + node[1]),
                midpoint[1],
                1e-14,
            );
        }
        if (N != 9) {
            try std.testing.expectEqualDeep(
                center,
                gk.multiRootSeedCoords(N, @intCast(2 * N)),
            );
        }
    }

    const xi_nodes = [_]F{ -1, 1, 1, -1, 0, 1, 0, -1, 0 };
    const eta_nodes = [_]F{ -1, -1, 1, 1, -1, 0, 1, 0, 0 };
    var coords: rops.GatheredElemCoords(9) = undefined;
    var projected: rops.RasterCoords2D(9) = undefined;
    for (0..9) |nn| {
        const xi = xi_nodes[nn];
        coords.x[nn] = 100 * (xi - 0.8 * xi * xi);
        coords.y[nn] = -100 * eta_nodes[nn];
        coords.z[nn] = 1 + 0.2 * xi;
        projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
        projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
    }
    try std.testing.expectEqual(
        rops.RootClass.multi_root,
        rops.classifyHighOrdFacing(9, projected).?,
    );

    const target_x: F = 0.2;
    const discriminant = @sqrt(0.96 * 0.96 - 4 * 0.8 * 0.2);
    const near_xi = (0.96 - discriminant) / 1.6;
    const far_xi = (0.96 + discriminant) / 1.6;
    const nodes = rops.Vec3Slices(F){
        .x = &coords.x,
        .y = &coords.y,
        .z = &coords.z,
    };
    const GK = gk.Quad89Kernel(9);
    const near = GK.solveWeightsNewton(
        nodes,
        50 + 100 * target_x,
        50,
        50,
        50,
        near_xi * 0.9,
        0,
    );
    const far = GK.solveWeightsNewton(
        nodes,
        50 + 100 * target_x,
        50,
        50,
        50,
        far_xi * 0.9,
        0,
    );
    try std.testing.expect(near.weights != null);
    try std.testing.expect(far.weights != null);
    try std.testing.expectApproxEqAbs(near_xi, near.xi_out, 1e-8);
    try std.testing.expectApproxEqAbs(far_xi, far.xi_out, 1e-8);
    try std.testing.expect(rops.projectedJacDetPhysical(
        9,
        nodes,
        near.xi_out,
        0,
    ) < 0);
    try std.testing.expect(rops.projectedJacDetPhysical(
        9,
        nodes,
        far.xi_out,
        0,
    ) > 0);
    try std.testing.expect(GK.calcInvZ(nodes, near.weights.?) >
        GK.calcInvZ(nodes, far.weights.?));

    const candidate = hull.buildMultiRootHullFromClip(9, &camera, coords);
    try std.testing.expect(candidate.contains(50 + 100 * target_x, 50));

    var factorial = FactorialStats{};
    inline for (.{ 4, 6, 8, 9 }) |N| {
        try checkFoldedMatrix(N, &camera, &factorial);
    }
    try measureQuadraticSaddle(&camera, &factorial);
    inline for (.{ 6, 8, 9 }) |N| {
        try measureOutwardCurvedMatrix(N, .outward_cylinder_3d, &camera, &factorial);
        try measureOutwardCurvedMatrix(N, .outward_sphere, &camera, &factorial);
    }
    try checkControlNearPlane(&camera);
    try checkParentOnlyHierarchyMisses(&camera);
    try checkThreeRootQuad8(&camera);
    try measureThreeRootMatrix(&camera, &factorial);
    for (factorial.curved_chain) |by_kind| {
        for (by_kind) |cell_stats| {
            try std.testing.expect(cell_stats.rays > 0);
            try std.testing.expect(cell_stats.overlap_rays > 0);
            try std.testing.expectEqual(cell_stats.rays, cell_stats.front);
            try std.testing.expectEqual(cell_stats.rays, cell_stats.nearest);
        }
    }
    for (factorial.curved_miss) |by_kind| {
        for (by_kind) |cell_stats| {
            try std.testing.expect(cell_stats.outside_hull > 0);
            try std.testing.expect(cell_stats.inside_hull > 0);
            try std.testing.expectEqual(
                3 * cell_stats.inside_hull,
                cell_stats.d3_starts,
            );
            try std.testing.expect(
                cell_stats.chain_starts >= cell_stats.full_starts,
            );
        }
    }
    const saddle_d3 = factorial.facing.cell(
        .quadratic_saddle,
        .nodes_half_center,
        .front_first,
        .near_middle_far,
        .first_three,
        0,
    );
    try std.testing.expect(saddle_d3.front * 100 >= saddle_d3.rays * 95);
    factorial.print();
    try checkDefaultBankFixture();
}

fn checkFoldedMatrix(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    factorial: *FactorialStats,
) !void {
    const parents = comptime gk.parentNodeCoords(N);
    const splits = [_]F{ 0.1, 0.25, 0.5, 0.75, 0.9 };
    const angles = [_]F{ 0, std.math.pi / 4.0, std.math.pi / 2.0, 3.0 * std.math.pi / 4.0 };
    for (splits, 0..) |split, split_idx| {
        var seed_stats = SeedStats{};
        const ridge: F = if (N == 6)
            1 - @sqrt(1 - split)
        else
            2 * split - 1;
        for (angles, 0..) |angle, angle_idx| {
            const c = @cos(angle);
            const s = @sin(angle);
            for ([_]F{ -1, 1 }, 0..) |polarity, polarity_idx| {
                var coords: rops.GatheredElemCoords(N) = undefined;
                var projected: rops.RasterCoords2D(N) = undefined;
                for (parents, 0..) |parent, nn| {
                    const u = parent[0];
                    const v = parent[1];
                    const x = if (N == 4)
                        20 * u * (v - ridge)
                    else
                        20 * (u - ridge) * (u - ridge);
                    const y = polarity * -20 * v;
                    coords.x[nn] = c * x - s * y;
                    coords.y[nn] = s * x + c * y;
                    coords.z[nn] = 1 + (if (N == 4) @as(F, 0.1) else 0.2) * u;
                    projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                    projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                }
                try std.testing.expectEqual(
                    rops.RootClass.multi_root,
                    rops.classifyHighOrdFacing(N, projected).?,
                );
                const candidate = hull.buildMultiRootHullFromClip(N, camera, coords);
                measureCoherentPatch(
                    N,
                    if (N == 4) .bilinear_saddle else if (polarity < 0)
                        .outward_cylinder
                    else
                        .inward_cylinder,
                    split_idx * 8 + angle_idx * 2 + polarity_idx,
                    camera,
                    coords,
                    .{
                        .ridge = ridge,
                        .c = c,
                        .s = s,
                        .polarity = polarity,
                    },
                );
                try measureSeedCases(
                    N,
                    camera,
                    coords,
                    &candidate,
                    ridge,
                    c,
                    s,
                    polarity,
                    &seed_stats,
                    factorial,
                );
                if (comptime N != 4) {
                    const GK = if (N == 6)
                        gk.Tri6Kernel()
                    else
                        gk.Quad89Kernel(N);
                    const low: F = if (N == 6) 0 else -1;
                    const high: F = 1;
                    const delta = 0.2 * @min(ridge - low, high - ridge);
                    const u_near = ridge - delta;
                    const z_near = 1 + 0.2 * u_near;
                    const ray_x = 20 * delta * delta / z_near;
                    const u_far = 2 * ridge + 0.2 * ray_x / 20 - u_near;
                    const z_far = 1 + 0.2 * u_far;
                    const v_near: F = if (N == 6) 0.02 else 0;
                    const v_far = v_near * z_far / z_near;
                    const ray_y = polarity * -20 * v_near / z_near;
                    const px = c * ray_x - s * ray_y + 50;
                    const py = s * ray_x + c * ray_y + 50;
                    const nodes = rops.Vec3Slices(F){
                        .x = &coords.x,
                        .y = &coords.y,
                        .z = &coords.z,
                    };
                    const near = GK.solveWeightsNewton(
                        nodes,
                        px,
                        py,
                        50,
                        50,
                        u_near,
                        v_near,
                    );
                    const far = GK.solveWeightsNewton(
                        nodes,
                        px,
                        py,
                        50,
                        50,
                        u_far,
                        v_far,
                    );
                    try std.testing.expect(near.weights != null);
                    try std.testing.expect(far.weights != null);
                    try std.testing.expectApproxEqAbs(u_near, near.xi_out, 1e-7);
                    try std.testing.expectApproxEqAbs(u_far, far.xi_out, 1e-7);
                    const near_jac = rops.projectedJacDetPhysical(
                        N,
                        nodes,
                        near.xi_out,
                        near.eta_out,
                    );
                    const far_jac = rops.projectedJacDetPhysical(
                        N,
                        nodes,
                        far.xi_out,
                        far.eta_out,
                    );
                    try std.testing.expect(near_jac * far_jac < 0);
                    try std.testing.expect(GK.calcInvZ(nodes, near.weights.?) >
                        GK.calcInvZ(nodes, far.weights.?));
                    try std.testing.expect(candidate.contains(px, py));
                }
                for (0..11) |ui| {
                    for (0..11) |vi| {
                        const u: F = if (N == 6)
                            @as(F, @floatFromInt(ui)) / 10
                        else
                            2 * @as(F, @floatFromInt(ui)) / 10 - 1;
                        const v: F = if (N == 6)
                            (1 - u) * @as(F, @floatFromInt(vi)) / 10
                        else
                            2 * @as(F, @floatFromInt(vi)) / 10 - 1;
                        const x = if (N == 4)
                            20 * u * (v - ridge)
                        else
                            20 * (u - ridge) * (u - ridge);
                        const y = polarity * -20 * v;
                        const z = 1 + (if (N == 4) @as(F, 0.1) else 0.2) * u;
                        const px = (c * x - s * y) / z + 50;
                        const py = (s * x + c * y) / z + 50;
                        try std.testing.expect(candidate.contains(px, py));
                    }
                }
            }
        }
        seed_stats.print(N, split);
    }
}

const BankSeed = struct {
    uv: [2]F,
    z: F,
    index: u8,
};

const FoldKind = enum {
    bilinear_saddle,
    quadratic_saddle,
    outward_cylinder,
    inward_cylinder,
    compound_three_root,
    outward_cylinder_3d,
    outward_sphere,
};

const fold_kind_count = @typeInfo(FoldKind).@"enum".fields.len;

const BankOrder = enum {
    center_near_far,
    depth,
    oscillating,
};

const SeedOutcome = union(enum) {
    no_weights,
    outside,
    residual,
    back_face,
    invalid_depth,
    front: F,
};

const FactorialCell = struct {
    rays: usize = 0,
    newton_starts: usize = 0,
    front_hit: usize = 0,
    nearest_hit: usize = 0,
    hull_reject: usize = 0,
    newton_no_weights: usize = 0,
    newton_rejected: usize = 0,
    back_only: usize = 0,
    wrong_nearest_early: usize = 0,
    wrong_nearest_bank: usize = 0,
};

const FacingPool = enum { nodes_center, nodes_half_center };
const FacingPriority = enum { none, front_first };
const FacingOrder = enum { depth, near_middle_far };
const FacingLimit = enum { first_three, full };

const FacingCell = struct {
    rays: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    starts: usize = 0,
    hull_reject: usize = 0,
    front_gained: usize = 0,
    front_lost: usize = 0,
    nearest_gained: usize = 0,
    nearest_lost: usize = 0,
};

const FacingStats = struct {
    cells: [fold_kind_count][2][2][2][2][2]FacingCell =
        std.mem.zeroes([fold_kind_count][2][2][2][2][2]FacingCell),

    fn cell(
        self: *@This(),
        kind: FoldKind,
        pool: FacingPool,
        priority: FacingPriority,
        order: FacingOrder,
        limit: FacingLimit,
        early_idx: usize,
    ) *FacingCell {
        const by_kind = &self.cells[@intFromEnum(kind)];
        const by_pool = &by_kind[@intFromEnum(pool)];
        const by_priority = &by_pool[@intFromEnum(priority)];
        return &by_priority[@intFromEnum(order)][@intFromEnum(limit)][early_idx];
    }

    fn print(self: *const @This()) void {
        for (std.enums.values(FoldKind)) |kind| {
            for (std.enums.values(FacingPool)) |pool| {
                for (std.enums.values(FacingPriority)) |priority| {
                    for (std.enums.values(FacingOrder)) |order| {
                        for (std.enums.values(FacingLimit)) |limit| {
                            for (0..2) |early_idx| {
                                const by_kind = &self.cells[@intFromEnum(kind)];
                                const by_pool = &by_kind[@intFromEnum(pool)];
                                const by_priority = &by_pool[@intFromEnum(priority)];
                                const by_order = &by_priority[@intFromEnum(order)];
                                const cell_stats = by_order[@intFromEnum(limit)][early_idx];
                                std.debug.print(
                                    "facingmatrix kind={s} pool={s} " ++
                                        "priority={s} order={s} limit={s} " ++
                                        "early={s} rays={d} front={d} " ++
                                        "nearest={d} starts={d} hull={d} " ++
                                        "front_gain={d} front_loss={d} " ++
                                        "nearest_gain={d} nearest_loss={d}\n",
                                    .{
                                        @tagName(kind),
                                        @tagName(pool),
                                        @tagName(priority),
                                        @tagName(order),
                                        @tagName(limit),
                                        if (early_idx == 0) "on" else "off",
                                        cell_stats.rays,
                                        cell_stats.front,
                                        cell_stats.nearest,
                                        cell_stats.starts,
                                        cell_stats.hull_reject,
                                        cell_stats.front_gained,
                                        cell_stats.front_lost,
                                        cell_stats.nearest_gained,
                                        cell_stats.nearest_lost,
                                    },
                                );
                            }
                        }
                    }
                }
            }
        }
    }
};

const CurvedChainCell = struct {
    rays: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    starts: usize = 0,
    expanded_fallbacks: usize = 0,
    edge_fallbacks: usize = 0,
    edge_recovered: usize = 0,
    overlap_rays: usize = 0,
};

const CurvedMissCell = struct {
    outside_hull: usize = 0,
    inside_hull: usize = 0,
    d3_starts: usize = 0,
    full_starts: usize = 0,
    chain_starts: usize = 0,
};

const HierarchyVariant = enum { plain, frozen, legacy_fallback };
const HierarchyMode = enum { fixed4, fixed16, adaptive };

const HierarchyCell = struct {
    hit_rays: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    false_child_reject: usize = 0,
    hit_starts: usize = 0,
    hit_iters: usize = 0,
    miss_rays: usize = 0,
    miss_rejected: usize = 0,
    miss_starts: usize = 0,
    miss_iters: usize = 0,
    child_aabb_tests: usize = 0,
    child_hull_tests: usize = 0,
    candidate_hist: [5]usize = .{ 0, 0, 0, 0, 0 },
};

const HierarchySeedCell = struct {
    rays: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    starts: usize = 0,
};

const HierarchyFixture = struct {
    leaves: [3][multiroot.max_leaves]multiroot.Leaf = undefined,
    counts: [3]u8 = undefined,

    fn init(
        comptime N: usize,
        camera: *const cam.CameraPrepared,
        coords: rops.GatheredElemCoords(N),
    ) @This() {
        return initWithSeedMethod(N, camera, coords, .center);
    }

    fn initWithSeedMethod(
        comptime N: usize,
        camera: *const cam.CameraPrepared,
        coords: rops.GatheredElemCoords(N),
        seed_method: multiroot.SeedMethod,
    ) @This() {
        var fixture: @This() = .{};
        inline for (std.enums.values(HierarchyMode)) |mode| {
            const hierarchy_mode: multiroot.Mode = switch (mode) {
                .fixed4 => .fixed4,
                .fixed16 => .fixed16,
                .adaptive => .adaptive,
            };
            const mode_idx = @intFromEnum(mode);
            fixture.counts[mode_idx] = @intCast(multiroot.prepareWithSeedMethod(
                N,
                camera,
                coords,
                hierarchy_mode,
                3,
                8,
                seed_method,
                &fixture.leaves[mode_idx],
            ));
        }
        return fixture;
    }
};

const FrozenVariant = enum {
    none,
    single,
    multi2_tol10,
    multi2_tol100,
    multi2_tol1000,
    multi3_tol10,
    multi3_tol100,
    multi3_tol1000,
    multi4_tol10,
    multi4_tol100,
    multi4_tol1000,

    fn config(self: @This()) ?newton.FrozenJacConfig {
        return switch (self) {
            .none => null,
            .single => .{ .max_iters = 1, .handoff_tol_mult = 0 },
            .multi2_tol10 => .{ .max_iters = 2, .handoff_tol_mult = 10 },
            .multi2_tol100 => .{ .max_iters = 2, .handoff_tol_mult = 100 },
            .multi2_tol1000 => .{ .max_iters = 2, .handoff_tol_mult = 1000 },
            .multi3_tol10 => .{ .max_iters = 3, .handoff_tol_mult = 10 },
            .multi3_tol100 => .{ .max_iters = 3, .handoff_tol_mult = 100 },
            .multi3_tol1000 => .{ .max_iters = 3, .handoff_tol_mult = 1000 },
            .multi4_tol10 => .{ .max_iters = 4, .handoff_tol_mult = 10 },
            .multi4_tol100 => .{ .max_iters = 4, .handoff_tol_mult = 100 },
            .multi4_tol1000 => .{ .max_iters = 4, .handoff_tol_mult = 1000 },
        };
    }
};

const FrozenBank = enum { center3, depth3, full_depth };

const FrozenCell = struct {
    rays: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    starts: usize = 0,
    frozen_iters: usize = 0,
    full_iters: usize = 0,
    full_solves: usize = 0,
    residual_evals: usize = 0,
    jacobian_evals: usize = 0,
    fallback_count: usize = 0,
    retry_count: usize = 0,
    gained_rays: usize = 0,
    lost_rays: usize = 0,
};

const FrozenStats = struct {
    cells: [fold_kind_count][11][3]FrozenCell =
        std.mem.zeroes([fold_kind_count][11][3]FrozenCell),

    fn cell(
        self: *@This(),
        kind: FoldKind,
        variant: FrozenVariant,
        bank: FrozenBank,
    ) *FrozenCell {
        return &self.cells[@intFromEnum(kind)][@intFromEnum(variant)][@intFromEnum(bank)];
    }

    fn print(self: *const @This()) void {
        for ([_]FoldKind{
            .bilinear_saddle,
            .quadratic_saddle,
            .outward_cylinder,
        }) |kind| {
            for (std.enums.values(FrozenVariant)) |variant| {
                for (std.enums.values(FrozenBank)) |bank| {
                    const cell_stats = self.cells[
                        @intFromEnum(kind)
                    ][@intFromEnum(variant)][@intFromEnum(bank)];
                    std.debug.print(
                        "frozenmatrix kind={s} variant={s} bank={s} " ++
                            "rays={d} front={d} nearest={d} starts={d} " ++
                            "frozen_iters={d} full_iters={d} full_solves={d} " ++
                            "resid_evals={d} jac_evals={d} fallback={d} " ++
                            "retries={d} gained={d} lost={d}\n",
                        .{
                            @tagName(kind),
                            @tagName(variant),
                            @tagName(bank),
                            cell_stats.rays,
                            cell_stats.front,
                            cell_stats.nearest,
                            cell_stats.starts,
                            cell_stats.frozen_iters,
                            cell_stats.full_iters,
                            cell_stats.full_solves,
                            cell_stats.residual_evals,
                            cell_stats.jacobian_evals,
                            cell_stats.fallback_count,
                            cell_stats.retry_count,
                            cell_stats.gained_rays,
                            cell_stats.lost_rays,
                        },
                    );
                }
            }
        }
    }
};

const FactorialStats = struct {
    cells: [fold_kind_count][2][3][2]FactorialCell =
        std.mem.zeroes([fold_kind_count][2][3][2]FactorialCell),
    frozen: FrozenStats = .{},
    facing: FacingStats = .{},
    curved_chain: [2][3]CurvedChainCell =
        std.mem.zeroes([2][3]CurvedChainCell),
    curved_miss: [2][3]CurvedMissCell =
        std.mem.zeroes([2][3]CurvedMissCell),
    hierarchy: [fold_kind_count][3][3]HierarchyCell =
        std.mem.zeroes([fold_kind_count][3][3]HierarchyCell),
    hierarchy_seed: [2][3][3]HierarchySeedCell =
        std.mem.zeroes([2][3][3]HierarchySeedCell),

    fn cell(
        self: *@This(),
        kind: FoldKind,
        scale_idx: usize,
        order: BankOrder,
        early_idx: usize,
    ) *FactorialCell {
        return &self.cells[@intFromEnum(kind)][scale_idx][@intFromEnum(order)][early_idx];
    }

    fn print(self: *const @This()) void {
        for (std.enums.values(FoldKind)) |kind| {
            for (0..2) |scale_idx| {
                for (std.enums.values(BankOrder)) |order| {
                    for (0..2) |early_idx| {
                        const cell_stats = self.cells[
                            @intFromEnum(kind)
                        ][scale_idx][@intFromEnum(order)][early_idx];
                        if (cell_stats.rays == 0) continue;
                        std.debug.print(
                            "seedmatrix kind={s} scale={s} order={s} " ++
                                "early={s} rays={d} starts={d} " ++
                                "front={d} nearest={d} " ++
                                "hull={d} no_weights={d} rejected={d} " ++
                                "back_only={d} early_loss={d} bank_loss={d}\n",
                            .{
                                @tagName(kind),
                                if (scale_idx == 0) "1.00" else "0.95",
                                @tagName(order),
                                if (early_idx == 0) "on" else "off",
                                cell_stats.rays,
                                cell_stats.newton_starts,
                                cell_stats.front_hit,
                                cell_stats.nearest_hit,
                                cell_stats.hull_reject,
                                cell_stats.newton_no_weights,
                                cell_stats.newton_rejected,
                                cell_stats.back_only,
                                cell_stats.wrong_nearest_early,
                                cell_stats.wrong_nearest_bank,
                            },
                        );
                    }
                }
            }
        }
        self.frozen.print();
        self.facing.print();
        for (self.curved_chain, 0..) |by_kind, kind_idx| {
            for (by_kind, 0..) |cell_stats, type_idx| {
                std.debug.print(
                    "curvedchain kind={s} N={d} rays={d} front={d} " ++
                        "nearest={d} starts={d} expanded_fallbacks={d} " ++
                        "edge_fallbacks={d} edge_recovered={d} " ++
                        "overlap_rays={d}\n",
                    .{
                        if (kind_idx == 0) "outward_cylinder_3d" else "outward_sphere",
                        switch (type_idx) {
                            0 => @as(usize, 6),
                            1 => 8,
                            else => 9,
                        },
                        cell_stats.rays,
                        cell_stats.front,
                        cell_stats.nearest,
                        cell_stats.starts,
                        cell_stats.expanded_fallbacks,
                        cell_stats.edge_fallbacks,
                        cell_stats.edge_recovered,
                        cell_stats.overlap_rays,
                    },
                );
            }
        }
        for (self.curved_miss, 0..) |by_kind, kind_idx| {
            for (by_kind, 0..) |cell_stats, type_idx| {
                const nodes_num: usize = switch (type_idx) {
                    0 => 6,
                    1 => 8,
                    else => 9,
                };
                std.debug.print(
                    "curvedmiss kind={s} N={d} outside_hull={d} " ++
                        "inside_hull={d} d3_starts={d} full_starts={d} " ++
                        "chain_starts={d}\n",
                    .{
                        if (kind_idx == 0) "outward_cylinder_3d" else "outward_sphere",
                        nodes_num,
                        cell_stats.outside_hull,
                        cell_stats.inside_hull,
                        cell_stats.d3_starts,
                        cell_stats.full_starts,
                        cell_stats.chain_starts,
                    },
                );
            }
        }
        for (self.hierarchy, 0..) |by_mode, kind_idx| {
            for (by_mode, 0..) |by_variant, mode_idx| {
                for (by_variant, 0..) |cell_stats, variant_idx| {
                    if (cell_stats.hit_rays == 0 and cell_stats.miss_rays == 0) continue;
                    std.debug.print(
                        "hierarchymatrix kind={s} mode={s} variant={s} " ++
                            "hits={d} front={d} nearest={d} false_reject={d} " ++
                            "hit_starts={d} hit_iters={d} misses={d} " ++
                            "miss_rejected={d} miss_starts={d} miss_iters={d} " ++
                            "child_aabb_tests={d} child_hull_tests={d} " ++
                            "candidates={d},{d},{d},{d},{d}\n",
                        .{
                            @tagName(@as(FoldKind, @enumFromInt(kind_idx))),
                            @tagName(@as(HierarchyMode, @enumFromInt(mode_idx))),
                            @tagName(@as(HierarchyVariant, @enumFromInt(variant_idx))),
                            cell_stats.hit_rays,
                            cell_stats.front,
                            cell_stats.nearest,
                            cell_stats.false_child_reject,
                            cell_stats.hit_starts,
                            cell_stats.hit_iters,
                            cell_stats.miss_rays,
                            cell_stats.miss_rejected,
                            cell_stats.miss_starts,
                            cell_stats.miss_iters,
                            cell_stats.child_aabb_tests,
                            cell_stats.child_hull_tests,
                            cell_stats.candidate_hist[0],
                            cell_stats.candidate_hist[1],
                            cell_stats.candidate_hist[2],
                            cell_stats.candidate_hist[3],
                            cell_stats.candidate_hist[4],
                        },
                    );
                }
            }
        }
        for (self.hierarchy_seed, 0..) |by_mode, kind_idx| {
            for (by_mode, 0..) |by_seed, mode_idx| {
                for (by_seed, 0..) |cell_stats, seed_idx| {
                    std.debug.print(
                        "hierarchyseed kind={s} mode={s} seed={s} " ++
                            "rays={d} front={d} nearest={d} starts={d}\n",
                        .{
                            if (kind_idx == 0) "outward_cylinder_3d" else "outward_sphere",
                            @tagName(@as(HierarchyMode, @enumFromInt(mode_idx))),
                            @tagName(@as(multiroot.SeedMethod, @enumFromInt(seed_idx))),
                            cell_stats.rays,
                            cell_stats.front,
                            cell_stats.nearest,
                            cell_stats.starts,
                        },
                    );
                }
            }
        }
    }
};

fn centerNearFarBank(comptime N: usize, sorted: []const BankSeed) [3]BankSeed {
    const center_idx: u8 = if (N == 9) 8 else 2 * N;
    var center: ?BankSeed = null;
    var near: ?BankSeed = null;
    var far: ?BankSeed = null;
    for (sorted) |seed| {
        if (seed.index == center_idx) {
            center = seed;
            continue;
        }
        if (near == null) near = seed;
        far = seed;
    }
    return .{ center.?, near.?, far.? };
}

fn oscillatingBank(
    comptime N: usize,
    sorted: [gk.multiRootSeedCount(N)]BankSeed,
) [gk.multiRootSeedCount(N)]BankSeed {
    const count = comptime gk.multiRootSeedCount(N);
    var ordered: [count]BankSeed = undefined;
    var used = [_]bool{false} ** count;
    for (0..count) |ii| {
        const remaining = count - ii;
        const rank = switch (ii % 3) {
            0 => @as(usize, 0),
            1 => remaining - 1,
            else => remaining / 2,
        };
        var seen: usize = 0;
        for (0..count) |jj| {
            if (used[jj]) continue;
            if (seen == rank) {
                ordered[ii] = sorted[jj];
                used[jj] = true;
                break;
            }
            seen += 1;
        }
    }
    return ordered;
}

const OrderEval = struct {
    best: ?F = null,
    attempts: usize = 0,
    saw_back: bool = false,
    saw_rejected: bool = false,
    saw_no_weights: bool = false,
};

fn evalBank(
    comptime N: usize,
    outcomes: *const [gk.multiRootSeedCount(N)]SeedOutcome,
    ordered: []const BankSeed,
    early_out: bool,
) OrderEval {
    var eval = OrderEval{};
    for (ordered, 0..) |seed, pass| {
        eval.attempts += 1;
        switch (outcomes[seed.index]) {
            .front => |inv_z| {
                eval.best = @max(eval.best orelse -std.math.inf(F), inv_z);
                if (pass == 0 and early_out) break;
            },
            .back_face => eval.saw_back = true,
            .no_weights => eval.saw_no_weights = true,
            .outside, .residual, .invalid_depth => eval.saw_rejected = true,
        }
    }
    return eval;
}

fn appendFacingTier(
    comptime N: usize,
    order: FacingOrder,
    tier: []const BankSeed,
    output: []BankSeed,
) void {
    if (order == .depth) {
        @memcpy(output, tier);
        return;
    }
    var used = [_]bool{false} ** gk.multiRootSeedCount(N);
    for (0..tier.len) |ii| {
        const remaining = tier.len - ii;
        const rank = switch (ii % 3) {
            0 => @as(usize, 0),
            1 => remaining / 2,
            else => remaining - 1,
        };
        var seen: usize = 0;
        for (tier, 0..) |seed, jj| {
            if (used[jj]) continue;
            if (seen == rank) {
                output[ii] = seed;
                used[jj] = true;
                break;
            }
            seen += 1;
        }
    }
}

fn facingOrderedBank(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
    depth_bank: []const BankSeed,
    pool: FacingPool,
    priority: FacingPriority,
    order: FacingOrder,
    output: *[gk.multiRootSeedCount(N)]BankSeed,
) usize {
    const count = comptime gk.multiRootSeedCount(N);
    const center_idx: u8 = if (N == 9) 8 else 2 * N;
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    var front: [count]BankSeed = undefined;
    var other: [count]BankSeed = undefined;
    var front_len: usize = 0;
    var other_len: usize = 0;
    for (depth_bank) |seed| {
        if (pool == .nodes_center and seed.index >= N and
            seed.index != center_idx)
        {
            continue;
        }
        const facing = rops.projectedJacDetPhysical(
            N,
            nodes,
            seed.uv[0],
            seed.uv[1],
        );
        if (priority == .none or std.math.isFinite(facing) and facing <
            -buildconfig.config.tol.culling.projected_jacobian_abs)
        {
            front[front_len] = seed;
            front_len += 1;
        } else {
            other[other_len] = seed;
            other_len += 1;
        }
    }
    appendFacingTier(N, order, front[0..front_len], output[0..front_len]);
    appendFacingTier(
        N,
        order,
        other[0..other_len],
        output[front_len .. front_len + other_len],
    );
    return front_len + other_len;
}

fn recordFacingRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    depth_bank: []const BankSeed,
    outcomes: *const [gk.multiRootSeedCount(N)]SeedOutcome,
    hull_hit: bool,
    expected: F,
    stats: *FacingStats,
) void {
    inline for (std.enums.values(FacingPool)) |pool| {
        var baseline_front = std.mem.zeroes([2][2][2]bool);
        var baseline_nearest = std.mem.zeroes([2][2][2]bool);
        inline for (std.enums.values(FacingPriority)) |priority| {
            inline for (std.enums.values(FacingOrder)) |order| {
                var bank: [gk.multiRootSeedCount(N)]BankSeed = undefined;
                const bank_len = facingOrderedBank(
                    N,
                    coords,
                    depth_bank,
                    pool,
                    priority,
                    order,
                    &bank,
                );
                inline for (std.enums.values(FacingLimit)) |limit| {
                    const use_len = if (limit == .first_three) @min(3, bank_len) else bank_len;
                    const ordered = bank[0..use_len];
                    inline for (0..2) |early_idx| {
                        const cell_stats = stats.cell(
                            kind,
                            pool,
                            priority,
                            order,
                            limit,
                            early_idx,
                        );
                        cell_stats.rays += 1;
                        var found_front = false;
                        var found_nearest = false;
                        if (!hull_hit) {
                            cell_stats.hull_reject += 1;
                        } else {
                            const eval = evalBank(
                                N,
                                outcomes,
                                ordered,
                                early_idx == 0,
                            );
                            cell_stats.starts += eval.attempts;
                            if (eval.best) |best| {
                                found_front = true;
                                cell_stats.front += 1;
                                if (@abs(best - expected) < 1e-7) {
                                    found_nearest = true;
                                    cell_stats.nearest += 1;
                                }
                            }
                        }
                        const ord_idx = @intFromEnum(order);
                        const lim_idx = @intFromEnum(limit);
                        if (priority == .none) {
                            baseline_front[ord_idx][lim_idx][early_idx] = found_front;
                            baseline_nearest[ord_idx][lim_idx][early_idx] =
                                found_nearest;
                        } else {
                            if (found_front and
                                !baseline_front[ord_idx][lim_idx][early_idx])
                            {
                                cell_stats.front_gained += 1;
                            } else if (!found_front and
                                baseline_front[ord_idx][lim_idx][early_idx])
                            {
                                cell_stats.front_lost += 1;
                            }
                            if (found_nearest and
                                !baseline_nearest[ord_idx][lim_idx][early_idx])
                            {
                                cell_stats.nearest_gained += 1;
                            } else if (!found_nearest and
                                baseline_nearest[ord_idx][lim_idx][early_idx])
                            {
                                cell_stats.nearest_lost += 1;
                            }
                        }
                    }
                }
            }
        }
    }
}

fn tri6EdgeInsetBank(coords: rops.GatheredElemCoords(6)) [6]BankSeed {
    const epsilon: F = 0.03;
    const fractions = [_]F{ 0.38, 0.62 };
    const Candidate = struct { seed: BankSeed, front: bool };
    var candidates: [6]Candidate = undefined;
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    for (fractions, 0..) |fraction, ii| {
        const rest = (1 - epsilon) * fraction;
        const opposite = (1 - epsilon) * (1 - fraction);
        const positions = [3][2]F{
            .{ rest, epsilon },
            .{ epsilon, rest },
            .{ rest, opposite },
        };
        for (positions, 0..) |uv, jj| {
            const idx = 3 * ii + jj;
            var weights: [6]F = undefined;
            var du: [6]F = undefined;
            var dv: [6]F = undefined;
            shapefun.shapeFunc(6, uv[0], uv[1], &weights, &du, &dv);
            var z: F = 0;
            for (0..6) |nn| z += weights[nn] * coords.z[nn];
            const facing = rops.projectedJacDetPhysical(
                6,
                nodes,
                uv[0],
                uv[1],
            );
            candidates[idx] = .{
                .seed = .{ .uv = uv, .z = z, .index = @intCast(idx) },
                .front = std.math.isFinite(facing) and facing <
                    -buildconfig.config.tol.culling.projected_jacobian_abs,
            };
        }
    }
    for (1..candidates.len) |ii| {
        const candidate = candidates[ii];
        var jj = ii;
        while (jj > 0 and
            ((candidate.front and !candidates[jj - 1].front) or
                (candidate.front == candidates[jj - 1].front and
                    candidate.seed.z < candidates[jj - 1].seed.z)))
        {
            candidates[jj] = candidates[jj - 1];
            jj -= 1;
        }
        candidates[jj] = candidate;
    }
    var bank: [6]BankSeed = undefined;
    for (candidates, 0..) |candidate, ii| bank[ii] = candidate.seed;
    return bank;
}

fn recordCurvedChainRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    depth_bank: []const BankSeed,
    outcomes: *const [gk.multiRootSeedCount(N)]SeedOutcome,
    hull_hit: bool,
    expected: F,
    stats: *FactorialStats,
) void {
    const kind_idx: usize = if (kind == .outward_cylinder_3d) 0 else 1;
    const type_idx: usize = switch (N) {
        6 => 0,
        8 => 1,
        9 => 2,
        else => @compileError("curved chain requires tri6, quad8, or quad9"),
    };
    const cell_stats = &stats.curved_chain[kind_idx][type_idx];
    cell_stats.rays += 1;
    if (!hull_hit) return;
    var saw_front = false;
    var saw_back = false;
    for (outcomes) |outcome| {
        switch (outcome) {
            .front => saw_front = true,
            .back_face => saw_back = true,
            else => {},
        }
    }
    if (saw_front and saw_back) cell_stats.overlap_rays += 1;
    var bank: [gk.multiRootSeedCount(N)]BankSeed = undefined;
    const bank_len = facingOrderedBank(
        N,
        coords,
        depth_bank,
        .nodes_half_center,
        .front_first,
        .near_middle_far,
        &bank,
    );
    const first = evalBank(N, outcomes, bank[0..3], true);
    cell_stats.starts += first.attempts;
    var best = first.best;
    if (best == null) {
        cell_stats.expanded_fallbacks += 1;
        for (bank[3..bank_len]) |seed| {
            cell_stats.starts += 1;
            switch (outcomes[seed.index]) {
                .front => |inv_z| {
                    best = inv_z;
                    break;
                },
                else => {},
            }
        }
    }
    if (comptime N == 6) {
        if (best == null) {
            cell_stats.edge_fallbacks += 1;
            const edge_bank = tri6EdgeInsetBank(coords);
            for (edge_bank) |seed| {
                cell_stats.starts += 1;
                const inv_z = seedResult(N, nodes, px, py, seed) orelse continue;
                best = inv_z;
                cell_stats.edge_recovered += 1;
                break;
            }
        }
    }
    if (best) |inv_z| {
        cell_stats.front += 1;
        if (@abs(inv_z - expected) < 1e-7) cell_stats.nearest += 1;
    }
}

fn buildSubpatchHull(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    origin: [2]F,
    axis_u: [2]F,
    axis_v: [2]F,
) hull.MultiRootHull {
    const parents = comptime gk.parentNodeCoords(N);
    var child: rops.GatheredElemCoords(N) = undefined;
    for (parents, 0..) |parent, ii| {
        const u = origin[0] + axis_u[0] * parent[0] +
            axis_v[0] * parent[1];
        const v = origin[1] + axis_u[1] * parent[0] +
            axis_v[1] * parent[1];
        var weights: [N]F = undefined;
        var du: [N]F = undefined;
        var dv: [N]F = undefined;
        shapefun.shapeFunc(N, u, v, &weights, &du, &dv);
        child.x[ii] = 0;
        child.y[ii] = 0;
        child.z[ii] = 0;
        for (0..N) |nn| {
            child.x[ii] += weights[nn] * coords.x[nn];
            child.y[ii] += weights[nn] * coords.y[nn];
            child.z[ii] += weights[nn] * coords.z[nn];
        }
    }
    return hull.buildMultiRootHullFromClip(N, camera, child);
}

fn buildSubpatchHulls(
    comptime N: usize,
    comptime parts_num: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
) [parts_num * parts_num]hull.MultiRootHull {
    // Affine restriction preserves the tri6/quad8/quad9 polynomial space.
    // Each projected Bezier control-net hull therefore encloses its child
    // surface, independently of whether Newton finds an intersection.
    const step: F = 1 / @as(F, @floatFromInt(parts_num));
    var subpatches: [parts_num * parts_num]hull.MultiRootHull = undefined;
    var count: usize = 0;
    if (comptime N == 6) {
        for (0..parts_num) |row| {
            for (0..parts_num - row) |col| {
                const x = @as(F, @floatFromInt(col)) * step;
                const y = @as(F, @floatFromInt(row)) * step;
                subpatches[count] = buildSubpatchHull(
                    N,
                    camera,
                    coords,
                    .{ x, y },
                    .{ step, 0 },
                    .{ 0, step },
                );
                count += 1;
                if (col + row + 1 < parts_num) {
                    subpatches[count] = buildSubpatchHull(
                        N,
                        camera,
                        coords,
                        .{ x + step, y },
                        .{ 0, step },
                        .{ -step, step },
                    );
                    count += 1;
                }
            }
        }
    } else {
        for (0..parts_num) |row| {
            for (0..parts_num) |col| {
                const x = -1 + step * (1 +
                    2 * @as(F, @floatFromInt(col)));
                const y = -1 + step * (1 +
                    2 * @as(F, @floatFromInt(row)));
                subpatches[count] = buildSubpatchHull(
                    N,
                    camera,
                    coords,
                    .{ x, y },
                    .{ step, 0 },
                    .{ 0, step },
                );
                count += 1;
            }
        }
    }
    std.debug.assert(count == subpatches.len);
    return subpatches;
}

fn containsSubpatch(
    subpatches: anytype,
    px: F,
    py: F,
) bool {
    for (subpatches) |*subpatch| {
        if (subpatch.contains(px, py)) return true;
    }
    return false;
}

fn measureCurvedMissRays(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    candidate: *const hull.MultiRootHull,
    subpatches: *const [64]hull.MultiRootHull,
    hierarchy_fixture: *const HierarchyFixture,
    stats: *FactorialStats,
) !void {
    const kind_idx: usize = if (kind == .outward_cylinder_3d) 0 else 1;
    const type_idx: usize = switch (N) {
        6 => 0,
        8 => 1,
        9 => 2,
        else => @compileError("curved miss rays require tri6, quad8, or quad9"),
    };
    const cell_stats = &stats.curved_miss[kind_idx][type_idx];
    var min_x = std.math.inf(F);
    var min_y = std.math.inf(F);
    var max_x = -std.math.inf(F);
    var max_y = -std.math.inf(F);
    for (0..candidate.count) |ii| {
        min_x = @min(min_x, candidate.x[ii]);
        min_y = @min(min_y, candidate.y[ii]);
        max_x = @max(max_x, candidate.x[ii]);
        max_y = @max(max_y, candidate.y[ii]);
    }
    min_x = @max(0, min_x - 3);
    min_y = @max(0, min_y - 3);
    max_x = @min(100, max_x + 3);
    max_y = @min(100, max_y + 3);
    const depth_bank = expandedBank(N, coords);
    var ordered: [gk.multiRootSeedCount(N)]BankSeed = undefined;
    const bank_len = facingOrderedBank(
        N,
        coords,
        &depth_bank,
        .nodes_half_center,
        .front_first,
        .near_middle_far,
        &ordered,
    );
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    for (0..15) |yy| {
        for (0..15) |xx| {
            const px = min_x + (max_x - min_x) *
                (@as(F, @floatFromInt(xx)) + 0.5) / 15;
            const py = min_y + (max_y - min_y) *
                (@as(F, @floatFromInt(yy)) + 0.5) / 15;
            // Each child hull encloses its entire FE subpatch. A ray outside
            // every child hull is a certified miss, independent of Newton.
            if (containsSubpatch(subpatches, px, py)) continue;
            if (!candidate.contains(px, py)) {
                cell_stats.outside_hull += 1;
                continue;
            }
            cell_stats.inside_hull += 1;
            try recordHierarchyRay(
                N,
                kind,
                coords,
                px,
                py,
                null,
                hierarchy_fixture,
                stats,
            );
            var outcomes: [gk.multiRootSeedCount(N)]SeedOutcome = undefined;
            for (depth_bank) |seed| {
                outcomes[seed.index] = seedOutcome(N, nodes, px, py, seed);
            }
            const d3 = evalBank(N, &outcomes, ordered[0..3], true);
            const full = evalBank(N, &outcomes, ordered[0..bank_len], true);
            try std.testing.expect(d3.best == null);
            try std.testing.expect(full.best == null);
            cell_stats.d3_starts += d3.attempts;
            cell_stats.full_starts += full.attempts;
            cell_stats.chain_starts += full.attempts;
            if (comptime N == 6) {
                const edge_bank = tri6EdgeInsetBank(coords);
                for (edge_bank) |seed| {
                    cell_stats.chain_starts += 1;
                    try std.testing.expect(
                        seedResult(N, nodes, px, py, seed) == null,
                    );
                }
            }
        }
    }
}

fn recordHierarchyRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    px: F,
    py: F,
    expected: ?F,
    fixture: *const HierarchyFixture,
    stats: *FactorialStats,
) !void {
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    const depth_bank = expandedBank(N, coords);
    var legacy_bank: [gk.multiRootSeedCount(N)]BankSeed = undefined;
    _ = facingOrderedBank(
        N,
        coords,
        &depth_bank,
        .nodes_half_center,
        .front_first,
        .near_middle_far,
        &legacy_bank,
    );
    inline for (std.enums.values(HierarchyMode)) |mode| {
        const mode_idx = @intFromEnum(mode);
        const leaves = fixture.leaves[mode_idx][0..fixture.counts[mode_idx]];
        var candidates: [multiroot.max_leaves]u8 = undefined;
        var candidate_count: usize = 0;
        var hull_tests: usize = 0;
        for (leaves, 0..) |*leaf, ii| {
            if (px < leaf.bbox[0] or px > leaf.bbox[1] or
                py < leaf.bbox[2] or py > leaf.bbox[3]) continue;
            hull_tests += 1;
            if (!leaf.contains(px, py)) continue;
            candidates[candidate_count] = @intCast(ii);
            candidate_count += 1;
        }
        inline for (std.enums.values(HierarchyVariant)) |variant| {
            const cell_stats = &stats.hierarchy[
                @intFromEnum(kind)
            ][mode_idx][@intFromEnum(variant)];
            if (expected != null) {
                cell_stats.hit_rays += 1;
                if (candidate_count == 0) cell_stats.false_child_reject += 1;
            } else {
                cell_stats.miss_rays += 1;
                if (candidate_count == 0) cell_stats.miss_rejected += 1;
            }
            cell_stats.candidate_hist[@min(candidate_count, 4)] += 1;
            cell_stats.child_aabb_tests += leaves.len;
            cell_stats.child_hull_tests += hull_tests;
            var best: ?F = null;
            for (candidates[0..candidate_count]) |leaf_idx| {
                const seed = leaves[leaf_idx].seed;
                const diag = solveSeedVariant(
                    N,
                    nodes,
                    px,
                    py,
                    .{ .uv = seed, .z = 0, .index = 0 },
                    if (variant == .frozen)
                        newton.FrozenJacConfig{
                            .max_iters = 1,
                            .handoff_tol_mult = 0,
                        }
                    else
                        null,
                );
                if (expected != null) {
                    cell_stats.hit_starts += diag.full_solves;
                    cell_stats.hit_iters += diag.newton_iters;
                } else {
                    cell_stats.miss_starts += diag.full_solves;
                    cell_stats.miss_iters += diag.newton_iters;
                }
                switch (diag.outcome) {
                    .front => |inv_z| best = @max(
                        best orelse -std.math.inf(F),
                        inv_z,
                    ),
                    else => {},
                }
            }
            if (variant == .legacy_fallback and candidate_count > 0 and
                best == null)
            {
                for (legacy_bank[0..3], 0..) |seed, pass| {
                    const diag = solveSeedVariant(N, nodes, px, py, seed, null);
                    if (expected != null) {
                        cell_stats.hit_starts += diag.full_solves;
                        cell_stats.hit_iters += diag.newton_iters;
                    } else {
                        cell_stats.miss_starts += diag.full_solves;
                        cell_stats.miss_iters += diag.newton_iters;
                    }
                    switch (diag.outcome) {
                        .front => |inv_z| {
                            best = @max(best orelse -std.math.inf(F), inv_z);
                            if (pass == 0) break;
                        },
                        else => {},
                    }
                }
            }
            if (expected) |front_depth| {
                if (best) |inv_z| {
                    cell_stats.front += 1;
                    if (@abs(inv_z - front_depth) < 1e-7) {
                        cell_stats.nearest += 1;
                    }
                }
            } else {
                try std.testing.expect(best == null);
            }
        }
    }
}

fn recordHierarchySeedSweepRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    px: F,
    py: F,
    expected: F,
    fixtures: *const [3]HierarchyFixture,
    stats: *FactorialStats,
) void {
    const kind_idx: usize = if (kind == .outward_cylinder_3d) 0 else 1;
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    inline for (std.enums.values(multiroot.SeedMethod)) |seed_method| {
        const fixture = &fixtures[@intFromEnum(seed_method)];
        inline for (std.enums.values(HierarchyMode)) |mode| {
            const mode_idx = @intFromEnum(mode);
            const cell_stats = &stats.hierarchy_seed[
                kind_idx
            ][mode_idx][@intFromEnum(seed_method)];
            cell_stats.rays += 1;
            var best: ?F = null;
            for (fixture.leaves[mode_idx][0..fixture.counts[mode_idx]]) |*leaf| {
                if (!leaf.contains(px, py)) continue;
                const diag = solveSeedAt(
                    N,
                    nodes,
                    px,
                    py,
                    .{ .xi = leaf.seed[0], .eta = leaf.seed[1] },
                );
                cell_stats.starts += 1;
                switch (diag.outcome) {
                    .front => |inv_z| best = @max(
                        best orelse -std.math.inf(F),
                        inv_z,
                    ),
                    else => {},
                }
            }
            if (best) |found| {
                cell_stats.front += 1;
                if (@abs(found - expected) < 1e-7) {
                    cell_stats.nearest += 1;
                }
            }
        }
    }
}

fn recordFactorialRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    candidate: *const hull.MultiRootHull,
    px: F,
    py: F,
    expected: F,
    hierarchy_fixture: *const HierarchyFixture,
    stats: *FactorialStats,
) !void {
    try recordHierarchyRay(
        N,
        kind,
        coords,
        px,
        py,
        expected,
        hierarchy_fixture,
        stats,
    );
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    const hull_hit = candidate.contains(px, py);
    inline for (.{ @as(F, 1), @as(F, 0.95) }, 0..) |node_scale, scale_idx| {
        const depth_bank = expandedBankWithNodeScale(N, coords, node_scale);
        const center_bank = centerNearFarBank(N, &depth_bank);
        const oscillating_bank = oscillatingBank(N, depth_bank);
        var outcomes: [gk.multiRootSeedCount(N)]SeedOutcome = undefined;
        for (depth_bank) |seed| {
            outcomes[seed.index] = seedOutcome(N, nodes, px, py, seed);
        }
        if (scale_idx == 0) {
            recordFacingRay(
                N,
                kind,
                coords,
                &depth_bank,
                &outcomes,
                hull_hit,
                expected,
                &stats.facing,
            );
            if (comptime N != 4) {
                if (kind == .outward_cylinder_3d or kind == .outward_sphere) {
                    recordCurvedChainRay(
                        N,
                        kind,
                        coords,
                        nodes,
                        px,
                        py,
                        &depth_bank,
                        &outcomes,
                        hull_hit,
                        expected,
                        stats,
                    );
                }
            }
        }
        inline for (std.enums.values(BankOrder)) |order| {
            const ordered: []const BankSeed = switch (order) {
                .center_near_far => &center_bank,
                .depth => &depth_bank,
                .oscillating => &oscillating_bank,
            };
            const full_eval = evalBank(N, &outcomes, ordered, false);
            inline for (0..2) |early_idx| {
                const eval = if (early_idx == 0)
                    evalBank(N, &outcomes, ordered, true)
                else
                    full_eval;
                const cell_stats = stats.cell(kind, scale_idx, order, early_idx);
                cell_stats.rays += 1;
                if (!hull_hit) {
                    cell_stats.hull_reject += 1;
                } else {
                    cell_stats.newton_starts += eval.attempts;
                    if (eval.best) |best| {
                        cell_stats.front_hit += 1;
                        if (@abs(best - expected) < 1e-7) {
                            cell_stats.nearest_hit += 1;
                        } else if (early_idx == 0 and full_eval.best != null and
                            @abs(full_eval.best.? - expected) < 1e-7)
                        {
                            cell_stats.wrong_nearest_early += 1;
                        } else {
                            cell_stats.wrong_nearest_bank += 1;
                        }
                    } else if (eval.saw_back) {
                        cell_stats.back_only += 1;
                    } else if (eval.saw_rejected) {
                        cell_stats.newton_rejected += 1;
                    } else {
                        cell_stats.newton_no_weights += 1;
                    }
                }
            }
        }
    }
    if (kind == .bilinear_saddle or kind == .quadratic_saddle or
        kind == .outward_cylinder)
    {
        recordFrozenRay(N, kind, coords, hull_hit, px, py, expected, &stats.frozen);
    }
}

fn recordFrozenRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    hull_hit: bool,
    px: F,
    py: F,
    expected: F,
    stats: *FrozenStats,
) void {
    var local_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &local_coords.x,
        .y = &local_coords.y,
        .z = &local_coords.z,
    };
    const depth_bank = expandedBank(N, coords);
    const center_bank = centerNearFarBank(N, &depth_bank);
    var baseline_front = [_]bool{false} ** 3;
    inline for (std.enums.values(FrozenVariant)) |variant| {
        inline for (std.enums.values(FrozenBank)) |bank| {
            const ordered: []const BankSeed = switch (bank) {
                .center3 => &center_bank,
                .depth3 => depth_bank[0..3],
                .full_depth => &depth_bank,
            };
            const cell_stats = stats.cell(kind, variant, bank);
            cell_stats.rays += 1;
            if (hull_hit) {
                var best: ?F = null;
                for (ordered, 0..) |seed, pass| {
                    const diag = solveSeedVariant(
                        N,
                        nodes,
                        px,
                        py,
                        seed,
                        variant.config(),
                    );
                    cell_stats.starts += 1;
                    cell_stats.frozen_iters += diag.frozen_iters;
                    cell_stats.full_iters += diag.newton_iters;
                    cell_stats.full_solves += diag.full_solves;
                    cell_stats.residual_evals += diag.frozen_residual_evals +
                        diag.newton_iters;
                    cell_stats.jacobian_evals += diag.frozen_jacobian_evals +
                        diag.newton_iters;
                    if (diag.frozen_fallback) cell_stats.fallback_count += 1;
                    if (diag.baseline_retry) cell_stats.retry_count += 1;
                    switch (diag.outcome) {
                        .front => |inv_z| {
                            best = @max(best orelse -std.math.inf(F), inv_z);
                            if (pass == 0) break;
                        },
                        else => {},
                    }
                }
                if (best) |inv_z| {
                    cell_stats.front += 1;
                    if (@abs(inv_z - expected) < 1e-7) {
                        cell_stats.nearest += 1;
                    }
                }
                const bank_idx = @intFromEnum(bank);
                if (variant == .none) {
                    baseline_front[bank_idx] = best != null;
                } else if (best != null and !baseline_front[bank_idx]) {
                    cell_stats.gained_rays += 1;
                } else if (best == null and baseline_front[bank_idx]) {
                    cell_stats.lost_rays += 1;
                }
            }
        }
    }
}

fn expandedBank(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
) [gk.multiRootSeedCount(N)]BankSeed {
    return expandedBankWithNodeScale(N, coords, 1);
}

fn expandedBankWithNodeScale(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
    node_scale: F,
) [gk.multiRootSeedCount(N)]BankSeed {
    const count = comptime gk.multiRootSeedCount(N);
    var bank: [count]BankSeed = undefined;
    for (0..count) |ii| {
        var uv = gk.multiRootSeedCoords(N, @intCast(ii));
        if (ii < N and !(N == 9 and ii == 8)) {
            const center: F = if (N == 6) 1.0 / 3.0 else 0;
            uv[0] = center + node_scale * (uv[0] - center);
            uv[1] = center + node_scale * (uv[1] - center);
        }
        var weights: [N]F = undefined;
        var du: [N]F = undefined;
        var dv: [N]F = undefined;
        shapefun.shapeFunc(N, uv[0], uv[1], &weights, &du, &dv);
        var z: F = 0;
        for (0..N) |nn| z += weights[nn] * coords.z[nn];
        bank[ii] = .{ .uv = uv, .z = z, .index = @intCast(ii) };
    }
    for (1..count) |ii| {
        const seed = bank[ii];
        var jj = ii;
        while (jj > 0 and (bank[jj - 1].z > seed.z or
            (bank[jj - 1].z == seed.z and
                bank[jj - 1].index > seed.index)))
        {
            bank[jj] = bank[jj - 1];
            jj -= 1;
        }
        bank[jj] = seed;
    }
    return bank;
}

fn halfDiverseBank(
    comptime N: usize,
    bank: []const BankSeed,
) [3]BankSeed {
    var near_half: ?BankSeed = null;
    var far_half: ?BankSeed = null;
    var center: ?BankSeed = null;
    for (bank) |seed| {
        if (seed.index >= N and seed.index < 2 * N) {
            if (near_half == null) near_half = seed;
            far_half = seed;
        }
        if (seed.index == (if (N == 9) @as(u8, 8) else @as(u8, 2 * N))) {
            center = seed;
        }
    }
    return .{ near_half.?, center.?, far_half.? };
}

fn seedResult(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    seed: BankSeed,
) ?F {
    return switch (seedOutcome(N, nodes, px, py, seed)) {
        .front => |inv_z| inv_z,
        else => null,
    };
}

fn seedOutcome(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    seed: BankSeed,
) SeedOutcome {
    return solveSeedVariant(N, nodes, px, py, seed, null).outcome;
}

const SeedSolveDiag = struct {
    outcome: SeedOutcome,
    uv: [2]F = .{ 0, 0 },
    newton_iters: u16,
    full_solves: u8 = 1,
    frozen_iters: u8,
    frozen_residual_evals: u16,
    frozen_jacobian_evals: u16,
    frozen_fallback: bool,
    baseline_retry: bool = false,
};

fn solveSeedVariant(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    seed: BankSeed,
    frozen_config: ?newton.FrozenJacConfig,
) SeedSolveDiag {
    const original = newton.NewtonSeed{
        .xi = seed.uv[0],
        .eta = seed.uv[1],
    };
    const refined = if (frozen_config) |config|
        newton.refineSeedFrozenScal(
            N,
            px - 50,
            py - 50,
            nodes.x,
            nodes.y,
            nodes.z,
            original,
            config,
        )
    else
        newton.FrozenJacResult{ .seed = original };
    var diag = solveSeedAt(N, nodes, px, py, refined.seed);
    diag.frozen_iters = refined.frozen_iters;
    diag.frozen_residual_evals = refined.residual_evals;
    diag.frozen_jacobian_evals = refined.jacobian_evals;
    diag.frozen_fallback = refined.fell_back;
    if (diag.outcome == .front or refined.seed.xi == original.xi and
        refined.seed.eta == original.eta)
    {
        return diag;
    }
    const baseline = solveSeedAt(N, nodes, px, py, original);
    diag.newton_iters += baseline.newton_iters;
    diag.full_solves += 1;
    diag.baseline_retry = true;
    if (baseline.outcome == .front) diag.outcome = baseline.outcome;
    return diag;
}

fn solveSeedAt(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    seed: newton.NewtonSeed,
) SeedSolveDiag {
    const GK = switch (N) {
        4 => gk.Quad4Kernel(),
        6 => gk.Tri6Kernel(),
        8, 9 => gk.Quad89Kernel(N),
        else => @compileError("unsupported folded fixture"),
    };
    const result = GK.solveWeightsNewton(
        nodes,
        px,
        py,
        50,
        50,
        seed.xi,
        seed.eta,
    );
    var diag = SeedSolveDiag{
        .outcome = .no_weights,
        .newton_iters = result.iters,
        .frozen_iters = 0,
        .frozen_residual_evals = 0,
        .frozen_jacobian_evals = 0,
        .frozen_fallback = false,
    };
    const weights = result.weights orelse return diag;
    if (!std.math.isFinite(result.xi_out) or
        !std.math.isFinite(result.eta_out) or
        GK.domViolation(result.xi_out, result.eta_out) > 0)
    {
        diag.outcome = .outside;
        return diag;
    }
    const state = newton.evaluateSolveState(
        N,
        px - 50,
        py - 50,
        nodes.x,
        nodes.y,
        nodes.z,
        result.xi_out,
        result.eta_out,
    );
    if (!std.math.isFinite(state.norm_resid_mag) or
        state.norm_resid_mag > buildconfig.config.tol.newton.norm_resid)
    {
        diag.outcome = .residual;
        return diag;
    }
    const facing = rops.projectedJacDetPhysical(
        N,
        nodes,
        result.xi_out,
        result.eta_out,
    );
    if (!std.math.isFinite(facing) or
        facing >= -buildconfig.config.tol.culling.projected_jacobian_abs)
    {
        diag.outcome = .back_face;
        return diag;
    }
    const inv_z = GK.calcInvZ(nodes, weights);
    if (!std.math.isFinite(inv_z) or inv_z <= 0) {
        diag.outcome = .invalid_depth;
        return diag;
    }
    diag.outcome = .{ .front = inv_z };
    diag.uv = .{ result.xi_out, result.eta_out };
    return diag;
}

const CoherentPolicy = enum {
    center,
    fixed4_center_d3,
    fixed4_reuse_column,
    fixed4_reuse_nearest_2d,
    fixed4_reuse_interp_2d,
    fixed4_reuse_affine_2d,
    fixed4_center_reuse_column,
    fixed4_center_reuse_nearest_2d,
    fixed4_center_reuse_interp_2d,
    fixed4_center_reuse_affine_2d,
    reuse,
    reuse_bank,
    extrapolate,
    extrapolate_bank,
    all_seeds,
};

fn experimentReuseMethod(
    policy: CoherentPolicy,
) ?coherentseed.ReuseMethod {
    return switch (policy) {
        .fixed4_reuse_column, .fixed4_center_reuse_column => .column,
        .fixed4_reuse_nearest_2d,
        .fixed4_center_reuse_nearest_2d,
        => .nearest_2d,
        .fixed4_reuse_interp_2d,
        .fixed4_center_reuse_interp_2d,
        => .interp_2d,
        .fixed4_reuse_affine_2d,
        .fixed4_center_reuse_affine_2d,
        => .affine_2d,
        else => null,
    };
}

fn isReusePrimary(policy: CoherentPolicy) bool {
    return switch (policy) {
        .fixed4_reuse_column,
        .fixed4_reuse_nearest_2d,
        .fixed4_reuse_interp_2d,
        .fixed4_reuse_affine_2d,
        => true,
        else => false,
    };
}

fn isCentreReuse(policy: CoherentPolicy) bool {
    return switch (policy) {
        .fixed4_center_reuse_column,
        .fixed4_center_reuse_nearest_2d,
        .fixed4_center_reuse_interp_2d,
        .fixed4_center_reuse_affine_2d,
        => true,
        else => false,
    };
}

const CoherentCell = struct {
    rays: usize = 0,
    oracle_hits: usize = 0,
    front: usize = 0,
    nearest: usize = 0,
    stage1_attempted: usize = 0,
    stage1_miss: usize = 0,
    stage1_wrong: usize = 0,
    stage2_miss: usize = 0,
    stage2_wrong: usize = 0,
    bank_recovered: usize = 0,
    bank_improved: usize = 0,
    false_front: usize = 0,
    hull_missed_hits: usize = 0,
    child_missed_hits: usize = 0,
    child_rejected_misses: usize = 0,
    newton_starts: usize = 0,
    newton_iters: usize = 0,
    newton_failures: usize = 0,
    center_iters: usize = 0,
    reuse_iters: usize = 0,
    d3_iters: usize = 0,
    reuse_eligible: usize = 0,
    reuse_attempts: usize = 0,
    reuse_successes: usize = 0,
    center_attempts: usize = 0,
    center_successes: usize = 0,
    center_failures: usize = 0,
    reuse_recoveries: usize = 0,
    d3_invocations: usize = 0,
    d3_recoveries: usize = 0,
};

fn sameDepth(a: F, b: F) bool {
    return @abs(a - b) <= 1e-8 * @max(@as(F, 1), @abs(b));
}

const AnalyticFold2D = struct {
    ridge: F,
    c: F,
    s: F,
    polarity: F,
};

fn evalCubic(coeffs: [4]F, u: F) F {
    return ((coeffs[3] * u + coeffs[2]) * u + coeffs[1]) * u +
        coeffs[0];
}

fn addAnalyticRoot(roots: *[3]F, count: *usize, root: F) void {
    if (!std.math.isFinite(root) or root < -1 - 1e-10 or
        root > 1 + 1e-10) return;
    for (roots[0..count.*]) |known| {
        if (@abs(root - known) < 1e-8) return;
    }
    std.debug.assert(count.* < roots.len);
    roots[count.*] = @max(-1, @min(1, root));
    count.* += 1;
}

fn quadraticRealRoots(a: F, b: F, c: F, roots: *[2]F) usize {
    const scale = @max(@as(F, 1), @max(@abs(a), @max(@abs(b), @abs(c))));
    if (@abs(a) <= 1e-14 * scale) {
        if (@abs(b) <= 1e-14 * scale) return 0;
        roots[0] = -c / b;
        return 1;
    }
    const discriminant = b * b - 4 * a * c;
    if (discriminant < -1e-12 * scale * scale) return 0;
    const sqrt_disc = @sqrt(@max(@as(F, 0), discriminant));
    roots[0] = (-b - sqrt_disc) / (2 * a);
    roots[1] = (-b + sqrt_disc) / (2 * a);
    return if (sqrt_disc <= 1e-13 * scale) 1 else 2;
}

/// The ray equation for these fixtures is a polynomial of degree at most
/// three. Split the unit interval at every derivative root, then bisect each
/// monotone segment. This finds all real roots, including tangent roots at a
/// stationary point, without consulting the Newton seed bank.
fn analyticUnitRoots(coeffs: [4]F) struct { values: [3]F, len: usize } {
    const scale = @max(@as(F, 1), @max(
        @abs(coeffs[0]),
        @max(@abs(coeffs[1]), @max(@abs(coeffs[2]), @abs(coeffs[3]))),
    ));
    var degree: usize = 3;
    while (degree > 0 and @abs(coeffs[degree]) <= 1e-14 * scale) {
        degree -= 1;
    }
    var stationary: [2]F = undefined;
    const stationary_count = switch (degree) {
        3 => quadraticRealRoots(
            3 * coeffs[3],
            2 * coeffs[2],
            coeffs[1],
            &stationary,
        ),
        2 => blk: {
            stationary[0] = -coeffs[1] / (2 * coeffs[2]);
            break :blk @as(usize, 1);
        },
        else => 0,
    };
    if (stationary_count == 2 and stationary[0] > stationary[1]) {
        std.mem.swap(F, &stationary[0], &stationary[1]);
    }
    var cuts: [4]F = undefined;
    cuts[0] = -1;
    var cut_count: usize = 1;
    for (stationary[0..stationary_count]) |root| {
        if (root <= -1 or root >= 1) continue;
        cuts[cut_count] = root;
        cut_count += 1;
    }
    cuts[cut_count] = 1;
    cut_count += 1;
    var roots: [3]F = undefined;
    var root_count: usize = 0;
    const zero_tol = 1e-12 * scale;
    for (0..cut_count - 1) |ii| {
        var lo = cuts[ii];
        var hi = cuts[ii + 1];
        var lo_value = evalCubic(coeffs, lo);
        const hi_value = evalCubic(coeffs, hi);
        const lo_is_root = @abs(lo_value) <= zero_tol;
        const hi_is_root = @abs(hi_value) <= zero_tol;
        if (lo_is_root) {
            addAnalyticRoot(&roots, &root_count, lo);
        }
        if (hi_is_root) {
            addAnalyticRoot(&roots, &root_count, hi);
        }
        if (lo_is_root or hi_is_root) continue;
        if ((lo_value > 0) == (hi_value > 0)) continue;
        for (0..60) |_| {
            const mid = 0.5 * (lo + hi);
            const mid_value = evalCubic(coeffs, mid);
            if ((mid_value > 0) == (lo_value > 0)) {
                lo = mid;
                lo_value = mid_value;
            } else {
                hi = mid;
            }
        }
        addAnalyticRoot(&roots, &root_count, 0.5 * (lo + hi));
    }
    return .{ .values = roots, .len = root_count };
}

fn analyticFoldDepth(
    comptime N: usize,
    kind: FoldKind,
    params: AnalyticFold2D,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
) F {
    const dx = px - 50;
    const dy = py - 50;
    const qx = params.c * dx + params.s * dy;
    const qy = -params.s * dx + params.c * dy;
    const y_scale = -20 * params.polarity;
    const w = qy / y_scale;
    const ridge = params.ridge;
    const coeffs: [4]F = switch (kind) {
        .bilinear_saddle => .{
            -qx / 20,
            w - ridge - 0.1 * qx / 20,
            0.1 * w,
            0,
        },
        .outward_cylinder, .inward_cylinder => .{
            20 * ridge * ridge - qx,
            -40 * ridge - 0.2 * qx,
            20,
            0,
        },
        .quadratic_saddle => .{
            20 * ridge * ridge - 30 * w - qx,
            -40 * ridge - 6 * w - 0.2 * qx,
            20 + 30 * w,
            6 * w,
        },
        else => unreachable,
    };
    const roots = analyticUnitRoots(coeffs);
    const z_slope: F = if (N == 4) 0.1 else 0.2;
    var best: F = 0;
    for (roots.values[0..roots.len]) |u| {
        const z = 1 + z_slope * u;
        const v = w * z;
        if (z <= 0 or !isInParent(N, u, v)) continue;
        const facing = rops.projectedJacDetPhysical(N, nodes, u, v);
        if (std.math.isFinite(facing) and facing <
            -buildconfig.config.tol.culling.projected_jacobian_abs)
        {
            best = @max(best, 1 / z);
        }
    }
    return best;
}

const OraclePoly = [9]F;
const OracleSurface = [3][3]OraclePoly;

const OracleRoots = struct {
    values: [8]F = undefined,
    len: usize = 0,

    fn add(self: *@This(), value: F) void {
        if (!std.math.isFinite(value)) return;
        for (self.values[0..self.len]) |known| {
            if (@abs(known - value) <= 1e-8) return;
        }
        std.debug.assert(self.len < self.values.len);
        self.values[self.len] = value;
        self.len += 1;
    }
};

fn oracleTerms(comptime N: usize) [N][2]u8 {
    return switch (N) {
        6 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 },
            .{ 2, 0 }, .{ 1, 1 }, .{ 0, 2 },
        },
        8 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 2, 0 },
            .{ 1, 1 }, .{ 0, 2 }, .{ 2, 1 }, .{ 1, 2 },
        },
        9 => .{
            .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 2, 0 },
            .{ 1, 1 }, .{ 0, 2 }, .{ 2, 1 }, .{ 1, 2 },
            .{ 2, 2 },
        },
        else => @compileError("oracle requires a high-order element"),
    };
}

fn oraclePower(value: F, exponent: u8) F {
    return switch (exponent) {
        0 => 1,
        1 => value,
        2 => value * value,
        else => @panic("oracle exponent exceeds quadratic basis"),
    };
}

/// Interpolate the actual FE surface into a monomial basis independently of
/// Riley's shape-function implementation. The three trailing columns of the
/// elimination matrix are the physical x, y, and z coordinates.
fn oracleSurface(
    comptime N: usize,
    coords: rops.GatheredElemCoords(N),
) OracleSurface {
    const parents = comptime gk.parentNodeCoords(N);
    const terms = comptime oracleTerms(N);
    var matrix: [N][N + 3]F = undefined;
    for (parents, 0..) |parent, row| {
        for (terms, 0..) |term, col| {
            matrix[row][col] = oraclePower(parent[0], term[0]) *
                oraclePower(parent[1], term[1]);
        }
        matrix[row][N] = coords.x[row];
        matrix[row][N + 1] = coords.y[row];
        matrix[row][N + 2] = coords.z[row];
    }
    for (0..N) |col| {
        var pivot = col;
        for (col + 1..N) |row| {
            if (@abs(matrix[row][col]) > @abs(matrix[pivot][col])) {
                pivot = row;
            }
        }
        std.debug.assert(@abs(matrix[pivot][col]) > 1e-12);
        if (pivot != col) std.mem.swap([N + 3]F, &matrix[pivot], &matrix[col]);
        const inv_pivot = 1 / matrix[col][col];
        for (col..N + 3) |jj| matrix[col][jj] *= inv_pivot;
        for (0..N) |row| {
            if (row == col) continue;
            const factor = matrix[row][col];
            for (col..N + 3) |jj| {
                matrix[row][jj] -= factor * matrix[col][jj];
            }
        }
    }
    var surface = std.mem.zeroes(OracleSurface);
    for (terms, 0..) |term, row| {
        for (0..3) |axis| {
            surface[axis][term[1]][term[0]] = matrix[row][N + axis];
        }
    }
    return surface;
}

fn oraclePolyEval(poly: OraclePoly, degree: usize, value: F) F {
    var result = poly[degree];
    var ii = degree;
    while (ii > 0) {
        ii -= 1;
        result = result * value + poly[ii];
    }
    return result;
}

fn oraclePolyMul(a: OraclePoly, b: OraclePoly) OraclePoly {
    var result = [_]F{0} ** 9;
    for (0..9) |ii| {
        if (a[ii] == 0) continue;
        for (0..9 - ii) |jj| result[ii + jj] += a[ii] * b[jj];
    }
    return result;
}

fn oraclePolySub(a: OraclePoly, b: OraclePoly) OraclePoly {
    var result: OraclePoly = undefined;
    for (0..9) |ii| result[ii] = a[ii] - b[ii];
    return result;
}

fn oracleRealRoots(
    poly: OraclePoly,
    max_degree: usize,
    lo: F,
    hi: F,
) OracleRoots {
    var scale: F = 0;
    for (poly[0 .. max_degree + 1]) |value| scale = @max(scale, @abs(value));
    if (scale == 0) return .{};
    var normalized: OraclePoly = undefined;
    for (0..9) |ii| normalized[ii] = poly[ii] / scale;
    var degree = max_degree;
    while (degree > 0 and @abs(normalized[degree]) <= 1e-13) degree -= 1;
    var result = OracleRoots{};
    if (degree == 0) return result;
    if (degree == 1) {
        const root = -normalized[0] / normalized[1];
        if (root >= lo - 1e-10 and root <= hi + 1e-10) {
            result.add(@max(lo, @min(hi, root)));
        }
        return result;
    }
    var derivative = [_]F{0} ** 9;
    for (1..degree + 1) |ii| {
        derivative[ii - 1] = @as(F, @floatFromInt(ii)) * normalized[ii];
    }
    const stationary = oracleRealRoots(derivative, degree - 1, lo, hi);
    var cuts: [9]F = undefined;
    cuts[0] = lo;
    var count: usize = 1;
    for (stationary.values[0..stationary.len]) |root| {
        if (root <= lo + 1e-10 or root >= hi - 1e-10) continue;
        cuts[count] = root;
        count += 1;
    }
    cuts[count] = hi;
    count += 1;
    for (0..count - 1) |ii| {
        var lower = cuts[ii];
        var upper = cuts[ii + 1];
        var lower_value = oraclePolyEval(normalized, degree, lower);
        const upper_value = oraclePolyEval(normalized, degree, upper);
        const lower_is_root = @abs(lower_value) <= 1e-11;
        const upper_is_root = @abs(upper_value) <= 1e-11;
        if (lower_is_root) result.add(lower);
        if (upper_is_root) result.add(upper);
        if (lower_is_root or upper_is_root) continue;
        if ((lower_value > 0) == (upper_value > 0)) continue;
        for (0..60) |_| {
            const middle = 0.5 * (lower + upper);
            const middle_value = oraclePolyEval(normalized, degree, middle);
            if ((middle_value > 0) == (lower_value > 0)) {
                lower = middle;
                lower_value = middle_value;
            } else {
                upper = middle;
            }
        }
        result.add(0.5 * (lower + upper));
    }
    return result;
}

fn oracleFeDepth(
    comptime N: usize,
    surface: OracleSurface,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
) F {
    var ray: [2][3]OraclePoly = undefined;
    for (0..3) |vv| {
        for (0..9) |uu| {
            ray[0][vv][uu] = surface[0][vv][uu] -
                (px - 50) * surface[2][vv][uu];
            ray[1][vv][uu] = surface[1][vv][uu] -
                (py - 50) * surface[2][vv][uu];
        }
    }
    const a = ray[0][2];
    const b = ray[0][1];
    const c = ray[0][0];
    const d = ray[1][2];
    const e = ray[1][1];
    const h = ray[1][0];
    var max_quadratic: F = 0;
    for (a, d) |av, dv| {
        max_quadratic = @max(max_quadratic, @max(@abs(av), @abs(dv)));
    }
    const resultant = if (max_quadratic < 1e-12)
        oraclePolySub(oraclePolyMul(b, h), oraclePolyMul(c, e))
    else blk: {
        const ah_cd = oraclePolySub(oraclePolyMul(a, h), oraclePolyMul(c, d));
        const ae_bd = oraclePolySub(oraclePolyMul(a, e), oraclePolyMul(b, d));
        const bh_ce = oraclePolySub(oraclePolyMul(b, h), oraclePolyMul(c, e));
        break :blk oraclePolySub(
            oraclePolyMul(ah_cd, ah_cd),
            oraclePolyMul(ae_bd, bh_ce),
        );
    };
    const u_lo: F = if (N == 6) 0 else -1;
    const u_roots = oracleRealRoots(resultant, 8, u_lo, 1);
    var best: F = 0;
    for (u_roots.values[0..u_roots.len]) |u| {
        const av = oraclePolyEval(a, 2, u);
        const bv = oraclePolyEval(b, 2, u);
        const cv = oraclePolyEval(c, 2, u);
        const dv = oraclePolyEval(d, 2, u);
        const ev = oraclePolyEval(e, 2, u);
        const hv = oraclePolyEval(h, 2, u);
        const denom = dv * bv - av * ev;
        var v_candidates: [2]F = undefined;
        const v_count: usize = if (@abs(denom) > 1e-9) blk: {
            v_candidates[0] = (av * hv - dv * cv) / denom;
            break :blk 1;
        } else if (@abs(av) > 1e-10 or @abs(bv) > 1e-10) blk: {
            break :blk quadraticRealRoots(av, bv, cv, &v_candidates);
        } else blk: {
            break :blk quadraticRealRoots(dv, ev, hv, &v_candidates);
        };
        for (v_candidates[0..v_count]) |v| {
            if (!isInParent(N, u, v)) continue;
            const f_residual = (av * v + bv) * v + cv;
            const g_residual = (dv * v + ev) * v + hv;
            const ray_scale = @max(@as(F, 1), @max(
                @abs(av) + @abs(bv) + @abs(cv),
                @abs(dv) + @abs(ev) + @abs(hv),
            ));
            if (@abs(f_residual) > 1e-7 * ray_scale or
                @abs(g_residual) > 1e-7 * ray_scale) continue;
            var z: F = 0;
            for (0..3) |vv| {
                const v_power = oraclePower(v, @intCast(vv));
                z += oraclePolyEval(surface[2][vv], 2, u) * v_power;
            }
            if (z <= 0) continue;
            const facing = rops.projectedJacDetPhysical(N, nodes, u, v);
            if (std.math.isFinite(facing) and facing <
                -buildconfig.config.tol.culling.projected_jacobian_abs)
            {
                best = @max(best, 1 / z);
            }
        }
    }
    return best;
}

/// Compare each coherent policy against an analytic ray equation when one is
/// available, otherwise against the diagnostic full seed bank. Stage 1 is
/// reuse, stage 2 is the patch center, and stage 3 is the bank.
fn measureCoherentPatch(
    comptime N: usize,
    kind: FoldKind,
    variant: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    analytic: ?AnalyticFold2D,
) void {
    const policies = comptime std.enums.values(CoherentPolicy);
    const patch = HierarchyFixture.init(N, camera, coords);
    const leaves = patch.leaves[0][0..patch.counts[0]];
    const candidate = hull.buildMultiRootHullFromClip(N, camera, coords);
    const bank = expandedBank(N, coords);
    var ordered_bank: [gk.multiRootSeedCount(N)]BankSeed = undefined;
    _ = facingOrderedBank(
        N,
        coords,
        &bank,
        .nodes_half_center,
        .front_first,
        .near_middle_far,
        &ordered_bank,
    );
    var mutable_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &mutable_coords.x,
        .y = &mutable_coords.y,
        .z = &mutable_coords.z,
    };
    const fe_surface: ?OracleSurface = if (N == 4)
        null
    else if (kind == .outward_cylinder_3d or kind == .outward_sphere or
        kind == .compound_three_root)
        oracleSurface(N, coords)
    else
        null;
    var caches: [policies.len][4][100]coherentseed.Cache =
        std.mem.zeroes([policies.len][4][100]coherentseed.Cache);
    var cells = [_]CoherentCell{.{}} ** policies.len;
    var hit_mask = [_]u8{0} ** 1250;
    var hit_depth_bits: [10000]u64 = undefined;
    for (0..100) |yy| {
        const py: F = @as(F, @floatFromInt(yy)) + 0.5;
        for (0..100) |xx| {
            const px: F = @as(F, @floatFromInt(xx)) + 0.5;
            const candidate_hit = candidate.contains(px, py);
            const exact_depth: ?F = if (analytic) |params|
                analyticFoldDepth(N, kind, params, nodes, px, py)
            else if (fe_surface) |surface|
                if (candidate_hit) oracleFeDepth(
                    N,
                    surface,
                    nodes,
                    px,
                    py,
                ) else null
            else
                null;
            if (exact_depth) |depth| {
                if (depth > 0) {
                    const pixel = yy * 100 + xx;
                    hit_mask[pixel / 8] |= @as(u8, 1) << @intCast(pixel % 8);
                    hit_depth_bits[pixel] = @bitCast(depth);
                }
            }
            if (!candidate_hit) {
                if (exact_depth) |depth| {
                    if (depth > 0) for (&cells) |*cell| {
                        cell.hull_missed_hits += 1;
                    };
                }
                continue;
            }
            var has_child = false;
            for (leaves) |leaf| {
                if (leaf.contains(px, py)) {
                    has_child = true;
                    break;
                }
            }
            if (!has_child) {
                if (exact_depth) |depth| {
                    if (depth > 0) for (&cells) |*cell| {
                        cell.child_missed_hits += 1;
                    };
                } else {
                    for (&cells) |*cell| {
                        cell.child_rejected_misses += 1;
                    }
                }
                continue;
            }

            var reference = exact_depth orelse 0;
            if (analytic == null and fe_surface == null) {
                for (bank) |seed| {
                    const diag = solveSeedAt(N, nodes, px, py, .{
                        .xi = seed.uv[0],
                        .eta = seed.uv[1],
                    });
                    if (diag.outcome == .front) {
                        reference = @max(reference, diag.outcome.front);
                    }
                }
            }
            for (policies, 0..) |policy, pp| {
                const cell = &cells[pp];
                cell.rays += 1;
                if (reference > 0) cell.oracle_hits += 1;
                var best: F = 0;
                var stage1: F = 0;
                var stage1_attempted = false;
                for (leaves, 0..) |leaf, ll| {
                    if (!leaf.contains(px, py)) continue;
                    const cache = &caches[pp][ll][xx];
                    const reuse_method = experimentReuseMethod(policy);
                    const use_cache = policy != .center and
                        policy != .fixed4_center_d3 and
                        !isCentreReuse(policy);
                    const extrapolate = policy == .extrapolate or
                        policy == .extrapolate_bank;
                    var choice = if (use_cache)
                        if (reuse_method) |mode|
                            coherentseed.chooseLocal(
                                &caches[pp][ll],
                                xx,
                                yy,
                                1,
                                mode,
                                leaf.seed,
                            )
                        else
                            cache.choose(yy, 1, extrapolate, leaf.seed)
                    else
                        coherentseed.Choice{
                            .uv = leaf.seed,
                            .kind = .center,
                        };
                    if (isReusePrimary(policy) and
                        choice.kind != .center and
                        !leaf.containsParent(N, choice.uv[0], choice.uv[1]))
                    {
                        choice = .{ .uv = leaf.seed, .kind = .center };
                    }
                    var local = false;
                    if (choice.kind != .center and
                        leaf.containsParent(N, choice.uv[0], choice.uv[1]))
                    {
                        stage1_attempted = true;
                        cell.reuse_eligible += 1;
                        cell.reuse_attempts += 1;
                        const diag = solveSeedAt(N, nodes, px, py, .{
                            .xi = choice.uv[0],
                            .eta = choice.uv[1],
                        });
                        cell.newton_starts += 1;
                        cell.newton_iters += diag.newton_iters;
                        cell.reuse_iters += diag.newton_iters;
                        if (diag.outcome != .front) cell.newton_failures += 1;
                        if (diag.outcome == .front) {
                            const inv_z = diag.outcome.front;
                            best = @max(best, inv_z);
                            stage1 = @max(stage1, inv_z);
                            local = leaf.containsParent(N, diag.uv[0], diag.uv[1]);
                            if (local) {
                                cache.update(yy, diag.uv, inv_z);
                                cell.reuse_successes += 1;
                            }
                        }
                    }
                    if (choice.kind == .center or
                        (!local and !isReusePrimary(policy)) or
                        policy == .all_seeds)
                    {
                        cell.center_attempts += 1;
                        const diag = solveSeedAt(N, nodes, px, py, .{
                            .xi = leaf.seed[0],
                            .eta = leaf.seed[1],
                        });
                        cell.newton_starts += 1;
                        cell.newton_iters += diag.newton_iters;
                        cell.center_iters += diag.newton_iters;
                        if (diag.outcome != .front) cell.newton_failures += 1;
                        if (diag.outcome == .front) {
                            cell.center_successes += 1;
                            const inv_z = diag.outcome.front;
                            best = @max(best, inv_z);
                            if (leaf.containsParent(N, diag.uv[0], diag.uv[1])) {
                                cache.update(yy, diag.uv, inv_z);
                                local = true;
                            }
                        }
                    }
                    if (isCentreReuse(policy) and !local) {
                        cell.center_failures += 1;
                        const mode = reuse_method.?;
                        const retry = coherentseed.chooseLocal(
                            &caches[pp][ll],
                            xx,
                            yy,
                            1,
                            mode,
                            leaf.seed,
                        );
                        if (retry.kind != .center and
                            leaf.containsParent(N, retry.uv[0], retry.uv[1]))
                        {
                            cell.reuse_eligible += 1;
                            cell.reuse_attempts += 1;
                            const diag = solveSeedAt(N, nodes, px, py, .{
                                .xi = retry.uv[0],
                                .eta = retry.uv[1],
                            });
                            cell.newton_starts += 1;
                            cell.newton_iters += diag.newton_iters;
                            cell.reuse_iters += diag.newton_iters;
                            if (diag.outcome != .front) {
                                cell.newton_failures += 1;
                            }
                            if (diag.outcome == .front) {
                                const inv_z = diag.outcome.front;
                                best = @max(best, inv_z);
                                if (leaf.containsParent(
                                    N,
                                    diag.uv[0],
                                    diag.uv[1],
                                )) {
                                    cache.update(yy, diag.uv, inv_z);
                                    cell.reuse_successes += 1;
                                    cell.reuse_recoveries += 1;
                                }
                            }
                        }
                    }
                }
                if (stage1_attempted) cell.stage1_attempted += 1;
                if (reference > 0) {
                    if (stage1_attempted and stage1 == 0) {
                        cell.stage1_miss += 1;
                    }
                    if (stage1_attempted and stage1 > 0 and
                        !sameDepth(stage1, reference))
                    {
                        cell.stage1_wrong += 1;
                    }
                    if (best == 0) cell.stage2_miss += 1;
                    if (best > 0 and !sameDepth(best, reference)) {
                        cell.stage2_wrong += 1;
                    }
                }
                const stage2 = best;
                if (((policy == .reuse_bank or
                    policy == .fixed4_center_d3 or
                    policy == .extrapolate_bank) and best == 0) or
                    policy == .all_seeds)
                {
                    if (policy == .fixed4_center_d3) cell.d3_invocations += 1;
                    const bank_count: usize = if (policy == .all_seeds)
                        bank.len
                    else
                        @min(3, bank.len);
                    for (ordered_bank[0..bank_count]) |seed| {
                        const diag = solveSeedAt(N, nodes, px, py, .{
                            .xi = seed.uv[0],
                            .eta = seed.uv[1],
                        });
                        cell.newton_starts += 1;
                        cell.newton_iters += diag.newton_iters;
                        cell.d3_iters += diag.newton_iters;
                        if (diag.outcome != .front) cell.newton_failures += 1;
                        if (diag.outcome == .front) {
                            best = @max(best, diag.outcome.front);
                        }
                    }
                }
                if (stage2 == 0 and best > 0) cell.bank_recovered += 1;
                if (policy == .fixed4_center_d3 and stage2 == 0 and
                    best > 0) cell.d3_recoveries += 1;
                if (stage2 > 0 and best > stage2 and
                    !sameDepth(best, stage2))
                {
                    cell.bank_improved += 1;
                }
                if (best > 0) cell.front += 1;
                if (reference == 0 and best > 0) cell.false_front += 1;
                if (reference > 0 and sameDepth(best, reference)) {
                    cell.nearest += 1;
                }
            }
        }
    }
    if ((analytic != null or fe_surface != null) and
        std.c.getenv("RILEY_ORACLE_HIT_LIST") != null)
    {
        const digits = "0123456789abcdef";
        var mask_hex: [2500]u8 = undefined;
        var depth_hex: [160000]u8 = undefined;
        var depth_len: usize = 0;
        for (hit_mask, 0..) |byte, ii| {
            mask_hex[2 * ii] = digits[byte >> 4];
            mask_hex[2 * ii + 1] = digits[byte & 15];
        }
        for (0..10000) |pixel| {
            if ((hit_mask[pixel / 8] &
                (@as(u8, 1) << @intCast(pixel % 8))) == 0) continue;
            const bits = hit_depth_bits[pixel];
            for (0..16) |digit_idx| {
                const shift: u6 = @intCast((15 - digit_idx) * 4);
                depth_hex[depth_len] = digits[@intCast((bits >> shift) & 15)];
                depth_len += 1;
            }
        }
        std.debug.print(
            "coherenthitmask reference={s} kind={s} N={d} " ++
                "variant={d} width=100 height=100 bits={s} depths={s}\n",
            .{
                if (analytic != null) "analytic" else "analytic_fe",
                @tagName(kind),
                N,
                variant,
                &mask_hex,
                depth_hex[0..depth_len],
            },
        );
    }
    for (policies, cells) |policy, cell| {
        std.debug.print(
            "coherentmatrix reference={s} kind={s} N={d} " ++
                "variant={d} " ++
                "policy={s} rays={d} " ++
                "oracle_hits={d} front={d} nearest={d} " ++
                "stage1_attempted={d} stage1_miss={d} stage1_wrong={d} " ++
                "stage2_miss={d} stage2_wrong={d} " ++
                "bank_recovered={d} bank_improved={d} " ++
                "false_front={d} hull_missed={d} child_missed={d} " ++
                "child_rejected_misses={d} starts={d} iters={d} ",
            .{
                if (analytic != null) "analytic" else if (fe_surface != null)
                    "analytic_fe"
                else
                    "full_bank",
                @tagName(kind),
                N,
                variant,
                @tagName(policy),
                cell.rays,
                cell.oracle_hits,
                cell.front,
                cell.nearest,
                cell.stage1_attempted,
                cell.stage1_miss,
                cell.stage1_wrong,
                cell.stage2_miss,
                cell.stage2_wrong,
                cell.bank_recovered,
                cell.bank_improved,
                cell.false_front,
                cell.hull_missed_hits,
                cell.child_missed_hits,
                cell.child_rejected_misses,
                cell.newton_starts,
                cell.newton_iters,
            },
        );
        std.debug.print(
            "newton_failures={d} center_iters={d} " ++
                "reuse_iters={d} d3_iters={d} reuse_eligible={d} " ++
                "reuse_attempts={d} reuse_successes={d} " ++
                "center_attempts={d} center_successes={d} " ++
                "center_failures={d} reuse_recoveries={d} " ++
                "d3_invocations={d} d3_recoveries={d}\n",
            .{
                cell.newton_failures,
                cell.center_iters,
                cell.reuse_iters,
                cell.d3_iters,
                cell.reuse_eligible,
                cell.reuse_attempts,
                cell.reuse_successes,
                cell.center_attempts,
                cell.center_successes,
                cell.center_failures,
                cell.reuse_recoveries,
                cell.d3_invocations,
                cell.d3_recoveries,
            },
        );
    }
}

/// A regular 3D quadratic surface can project to a multiply covered,
/// non-convex image. Exercise the cheap parent-pass/child-reject miss path.
fn checkParentOnlyHierarchyMisses(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(9);
    var coords: rops.GatheredElemCoords(9) = undefined;
    var projected: rops.RasterCoords2D(9) = undefined;
    for (parents, 0..) |uv, nn| {
        const u = uv[0];
        const v = uv[1];
        coords.x[nn] = 35 * (u * u + 0.25 * v);
        coords.y[nn] = -35 * (v * v + 0.25 * u);
        coords.z[nn] = 1 + 0.2 * u;
        projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
        projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
    }
    try std.testing.expectEqual(
        rops.RootClass.multi_root,
        rops.classifyHighOrdFacing(9, projected).?,
    );
    const parent = hull.buildMultiRootHullFromClip(9, camera, coords);
    const fixture = HierarchyFixture.init(9, camera, coords);
    const leaves = fixture.leaves[0][0..fixture.counts[0]];
    const surface = oracleSurface(9, coords);
    const nodes = rops.Vec3Slices(F){
        .x = &coords.x,
        .y = &coords.y,
        .z = &coords.z,
    };
    var rejected_misses: usize = 0;
    for (0..100) |yy| {
        const py: F = @as(F, @floatFromInt(yy)) + 0.5;
        for (0..100) |xx| {
            const px: F = @as(F, @floatFromInt(xx)) + 0.5;
            if (!parent.contains(px, py)) continue;
            var child_admits = false;
            for (leaves) |leaf| {
                if (leaf.contains(px, py)) {
                    child_admits = true;
                    break;
                }
            }
            if (child_admits) continue;
            if (rejected_misses < 16) {
                try std.testing.expect(oracleFeDepth(
                    9,
                    surface,
                    nodes,
                    px,
                    py,
                ) == 0);
            }
            rejected_misses += 1;
        }
    }
    try std.testing.expect(rejected_misses > 0);
    std.debug.print(
        "hierarchyparentmiss N=9 parent_pass_child_reject={d}\n",
        .{rejected_misses},
    );
}

fn bestSeedResult(
    comptime N: usize,
    nodes: rops.Vec3Slices(F),
    px: F,
    py: F,
    seeds: []const BankSeed,
    first_early_out: bool,
) ?F {
    var best: ?F = null;
    for (seeds, 0..) |seed, pass| {
        const inv_z = seedResult(N, nodes, px, py, seed) orelse continue;
        if (best == null or inv_z > best.?) best = inv_z;
        if (pass == 0 and first_early_out) break;
    }
    return best;
}

fn isInParent(comptime N: usize, u: F, v: F) bool {
    const eps: F = 1e-9;
    return if (N == 6)
        u >= -eps and v >= -eps and u + v <= 1 + eps
    else
        @abs(u) <= 1 + eps and @abs(v) <= 1 + eps;
}

fn measureSeedCases(
    comptime N: usize,
    camera: *const cam.CameraPrepared,
    coords: rops.GatheredElemCoords(N),
    candidate: *const hull.MultiRootHull,
    ridge: F,
    c: F,
    s: F,
    polarity: F,
    stats: *SeedStats,
    factorial: *FactorialStats,
) !void {
    // Diagnostic comparison only: the diverse bank is not used by the engine.
    // Midpoint rays avoid nodal-only tests and sample interiors of all folds.
    const parents = comptime gk.parentNodeCoords(N);
    const hierarchy_fixture = HierarchyFixture.init(N, camera, coords);
    var node_coords = coords;
    const nodes = rops.Vec3Slices(F){
        .x = &node_coords.x,
        .y = &node_coords.y,
        .z = &node_coords.z,
    };
    const center = [2]F{
        if (N == 6) 1.0 / 3.0 else 0,
        if (N == 6) 1.0 / 3.0 else 0,
    };
    const count = N + @as(usize, if (N == 9) 0 else 1);
    var bank: [N + 1]BankSeed = undefined;
    for (parents, 0..) |parent, nn| {
        bank[nn] = .{
            .uv = parent,
            .z = coords.z[nn],
            .index = @intCast(nn),
        };
    }
    if (N != 9) {
        bank[N] = .{
            .uv = center,
            .z = 1 + (if (N == 4) @as(F, 0.1) else 0.2) * center[0],
            .index = N,
        };
    }
    for (1..count) |ii| {
        const seed = bank[ii];
        var jj = ii;
        while (jj > 0 and (bank[jj - 1].z > seed.z or
            (bank[jj - 1].z == seed.z and
                bank[jj - 1].index > seed.index)))
        {
            bank[jj] = bank[jj - 1];
            jj -= 1;
        }
        bank[jj] = seed;
    }

    const deepest_z = bank[count - 1].z;
    var deep = bank[count - 1];
    var deep_centr_dist = std.math.inf(F);
    var center_seed = bank[0];
    for (bank[0..count]) |seed| {
        const du = seed.uv[0] - center[0];
        const dv = seed.uv[1] - center[1];
        const dist = du * du + dv * dv;
        if (seed.z == deepest_z and dist < deep_centr_dist) {
            deep = seed;
            deep_centr_dist = dist;
        }
        if (seed.index == (if (N == 9) @as(u8, 8) else @as(u8, N))) {
            center_seed = seed;
        }
    }
    const diverse = [3]BankSeed{ bank[0], deep, center_seed };
    const expanded = expandedBank(N, coords);
    const half_diverse = halfDiverseBank(N, &expanded);
    const y_scale = polarity * -20;
    const z_slope: F = if (N == 4) 0.1 else 0.2;
    for (0..9) |ui| {
        for (0..9) |vi| {
            const u_fraction = (@as(F, @floatFromInt(ui)) + 0.5) / 9;
            const v_fraction = (@as(F, @floatFromInt(vi)) + 0.5) / 9;
            const u = if (N == 6) u_fraction else 2 * u_fraction - 1;
            const v = if (N == 6)
                (1 - u) * v_fraction
            else
                2 * v_fraction - 1;
            const z = 1 + z_slope * u;
            const x = if (N == 4)
                20 * u * (v - ridge)
            else
                20 * (u - ridge) * (u - ridge);
            const qx = x / z;
            const qy = y_scale * v / z;
            const px = c * qx - s * qy + 50;
            const py = s * qx + c * qy + 50;
            if (px < 0 or px >= 100 or py < 0 or py >= 100) continue;
            stats.rays += 1;

            const u_other = if (N == 4) blk: {
                const w = v / z;
                const a = 0.1 * w;
                if (@abs(a) < 1e-12) break :blk std.math.nan(F);
                const q = qx / 20;
                const b = w - ridge - 0.1 * q;
                break :blk -b / a - u;
            } else blk: {
                const q = qx / 20;
                break :blk 2 * ridge + 0.2 * q - u;
            };
            const z_other = 1 + z_slope * u_other;
            const v_other = v * z_other / z;
            const has_other = std.math.isFinite(u_other) and
                @abs(u_other - u) > 1e-6 and
                isInParent(N, u_other, v_other);
            if (has_other) stats.overlap += 1;
            if (has_other) {
                const other_x = if (N == 4)
                    20 * u_other * (v_other - ridge)
                else
                    20 * (u_other - ridge) * (u_other - ridge);
                const other_y = y_scale * v_other;
                const other_px = (c * other_x - s * other_y) / z_other + 50;
                const other_py = (s * other_x + c * other_y) / z_other + 50;
                try std.testing.expectApproxEqAbs(px, other_px, 1e-7);
                try std.testing.expectApproxEqAbs(py, other_py, 1e-7);
            }

            var oracle_best: ?F = null;
            const facing = rops.projectedJacDetPhysical(N, nodes, u, v);
            if (facing < -buildconfig.config.tol.culling.projected_jacobian_abs) {
                oracle_best = 1 / z;
            }
            if (has_other) {
                const other_facing = rops.projectedJacDetPhysical(
                    N,
                    nodes,
                    u_other,
                    v_other,
                );
                if (other_facing <
                    -buildconfig.config.tol.culling.projected_jacobian_abs)
                {
                    oracle_best = @max(oracle_best orelse 0, 1 / z_other);
                }
            }
            const expected = oracle_best orelse continue;
            stats.visible += 1;
            if (has_other) stats.visible_overlap += 1;
            const kind: FoldKind = if (N == 4)
                .bilinear_saddle
            else if (polarity < 0)
                .outward_cylinder
            else
                .inward_cylinder;
            try recordFactorialRay(
                N,
                kind,
                coords,
                candidate,
                px,
                py,
                expected,
                &hierarchy_fixture,
                factorial,
            );

            const first = seedResult(N, nodes, px, py, bank[0]);
            if (first) |found| {
                stats.first_front += 1;
                if (has_other) stats.overlap_first_front += 1;
                if (@abs(found - expected) < 1e-7) stats.first_nearest += 1;
            }
            const d3 = bestSeedResult(
                N,
                nodes,
                px,
                py,
                bank[0..3],
                true,
            );
            if (d3) |found| {
                stats.d3_found += 1;
                if (has_other) stats.overlap_d3_found += 1;
                if (@abs(found - expected) < 1e-7) stats.d3_nearest += 1;
            }
            const diverse_result = bestSeedResult(
                N,
                nodes,
                px,
                py,
                &diverse,
                true,
            );
            if (diverse_result) |found| {
                stats.diverse_found += 1;
                if (has_other) stats.overlap_diverse_found += 1;
                if (@abs(found - expected) < 1e-7) stats.diverse_nearest += 1;
            }
            const full = bestSeedResult(
                N,
                nodes,
                px,
                py,
                bank[0..count],
                false,
            );
            if (full) |found| {
                stats.full_found += 1;
                if (has_other) stats.overlap_full_found += 1;
                if (@abs(found - expected) < 1e-7) stats.full_nearest += 1;
            } else if (comptime N == 6) {
                if (stats.printed_full_misses < 3) {
                    std.debug.print(
                        "tri6 full-bank miss ridge={d:.6} " ++
                            "uv=({d:.6},{d:.6}) other=({d:.6},{d:.6}) " ++
                            "facing={d:.6} pixel=({d:.6},{d:.6})\n",
                        .{
                            ridge, u, v, u_other, v_other, facing, px, py,
                        },
                    );
                    stats.printed_full_misses += 1;
                }
            }
            const expanded_d3 = bestSeedResult(
                N,
                nodes,
                px,
                py,
                expanded[0..3],
                true,
            );
            if (expanded_d3) |found| {
                stats.expanded_d3_found += 1;
                if (@abs(found - expected) < 1e-7) {
                    stats.expanded_d3_nearest += 1;
                }
            }
            const expanded_full = bestSeedResult(
                N,
                nodes,
                px,
                py,
                &expanded,
                false,
            );
            try std.testing.expect(expanded_full != null);
            try std.testing.expectApproxEqAbs(expected, expanded_full.?, 1e-7);
            if (expanded_full) |found| {
                stats.expanded_full_found += 1;
                if (@abs(found - expected) < 1e-7) {
                    stats.expanded_full_nearest += 1;
                }
            }
            const half_d3 = bestSeedResult(
                N,
                nodes,
                px,
                py,
                &half_diverse,
                true,
            );
            if (half_d3) |found| {
                stats.half_d3_found += 1;
                if (@abs(found - expected) < 1e-7) {
                    stats.half_d3_nearest += 1;
                }
            }
        }
    }
}

fn checkControlNearPlane(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(8);
    var coords: rops.GatheredElemCoords(8) = undefined;
    for (parents, 0..) |parent, nn| {
        const u = parent[0];
        const v = parent[1];
        coords.x[nn] = 20 * u * u;
        coords.y[nn] = -20 * v;
        coords.z[nn] = 0.1 + 0.9 * u * u;
    }
    // All physical points have positive depth, although quadratic elevation
    // puts some control points behind the near plane.
    const candidate = hull.buildMultiRootHullFromClip(8, camera, coords);
    for (0..21) |ui| {
        for (0..21) |vi| {
            const u = @as(F, @floatFromInt(ui)) / 10 - 1;
            const v = @as(F, @floatFromInt(vi)) / 10 - 1;
            const z = 0.1 + 0.9 * u * u;
            try std.testing.expect(candidate.contains(20 * u * u / z + 50, -20 * v / z + 50));
        }
    }
}

fn saddleRayResidual(
    u: F,
    qx: F,
    qy: F,
    ridge: F,
    y_scale: F,
) F {
    const z = 1 + 0.2 * u;
    const v = qy * z / y_scale;
    const x = 20 * (u - ridge) * (u - ridge) +
        30 * v * (u * u - 1);
    return x / z - qx;
}

fn measureOutwardCurvedMatrix(
    comptime N: usize,
    kind: FoldKind,
    camera: *const cam.CameraPrepared,
    factorial: *FactorialStats,
) !void {
    std.debug.assert(kind == .outward_cylinder_3d or kind == .outward_sphere);
    const parents = comptime gk.parentNodeCoords(N);
    const theta_centers = [_]F{ -1.0, -0.7, 0.7, 1.0 };
    const secondary_values = [_]F{ -0.55, 0, 0.55 };
    const rolls = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    const image_scale: F = 30;
    const center_z: F = 2.2;
    const angular_span: F = if (N == 6) 1.2 else 0.6;
    const d3_before = factorial.facing.cell(
        kind,
        .nodes_center,
        .front_first,
        .depth,
        .first_three,
        0,
    ).front;
    var patch_count: usize = 0;
    var ray_count: usize = 0;
    var theta_seen = [_]bool{false} ** theta_centers.len;
    var secondary_seen = [_]bool{false} ** secondary_values.len;
    var roll_seen = [_]bool{false} ** rolls.len;

    for (theta_centers, 0..) |theta_center, theta_idx| {
        for (secondary_values, 0..) |secondary, secondary_idx| {
            for (rolls, 0..) |roll, roll_idx| {
                const c = @cos(roll);
                const s = @sin(roll);
                const ct = @cos(secondary);
                const st = @sin(secondary);
                var coords: rops.GatheredElemCoords(N) = undefined;
                var projected: rops.RasterCoords2D(N) = undefined;
                for (parents, 0..) |parent, nn| {
                    const u = if (N == 6) parent[0] - 1.0 / 3.0 else parent[0];
                    const v = if (N == 6) parent[1] - 1.0 / 3.0 else parent[1];
                    const theta = theta_center + angular_span * u;
                    const local_x = @sin(theta);
                    const local_y: F = if (kind == .outward_sphere)
                        @sin(secondary - angular_span * v)
                    else
                        -0.45 * v * ct + @cos(theta) * st;
                    const local_z: F = if (kind == .outward_sphere)
                        -@cos(theta) * @cos(secondary - angular_span * v)
                    else
                        -0.45 * v * st - @cos(theta) * ct;
                    const sphere_x = if (kind == .outward_sphere)
                        local_x * @cos(secondary - angular_span * v)
                    else
                        local_x;
                    coords.x[nn] = image_scale *
                        (c * sphere_x - s * local_y);
                    coords.y[nn] = image_scale *
                        (s * sphere_x + c * local_y);
                    coords.z[nn] = center_z + local_z;
                    projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                    projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                }
                if (rops.classifyHighOrdFacing(N, projected) != .multi_root) {
                    continue;
                }
                patch_count += 1;
                var patch_rays: usize = 0;
                const candidate = hull.buildMultiRootHullFromClip(
                    N,
                    camera,
                    coords,
                );
                var hierarchy_fixtures: [3]HierarchyFixture = undefined;
                inline for (std.enums.values(multiroot.SeedMethod)) |method| {
                    hierarchy_fixtures[@intFromEnum(method)] =
                        HierarchyFixture.initWithSeedMethod(
                            N,
                            camera,
                            coords,
                            method,
                        );
                }
                const hierarchy_fixture = &hierarchy_fixtures[0];
                measureCoherentPatch(
                    N,
                    kind,
                    theta_idx * 12 + secondary_idx * 4 + roll_idx,
                    camera,
                    coords,
                    null,
                );
                const fe_surface = oracleSurface(N, coords);
                const subpatches = buildSubpatchHulls(N, 4, camera, coords);
                const oracle_subpatches = buildSubpatchHulls(
                    N,
                    8,
                    camera,
                    coords,
                );
                for (0..7) |ui| {
                    for (0..7) |vi| {
                        const u_frac = (@as(F, @floatFromInt(ui)) + 0.5) / 7;
                        const v_frac = (@as(F, @floatFromInt(vi)) + 0.5) / 7;
                        const u = if (N == 6) u_frac else 2 * u_frac - 1;
                        const v = if (N == 6)
                            (1 - u) * v_frac
                        else
                            2 * v_frac - 1;
                        var weights: [N]F = undefined;
                        var du: [N]F = undefined;
                        var dv: [N]F = undefined;
                        shapefun.shapeFunc(N, u, v, &weights, &du, &dv);
                        var pos = [_]F{0} ** 3;
                        var tang_u = [_]F{0} ** 3;
                        var tang_v = [_]F{0} ** 3;
                        for (0..N) |nn| {
                            const node = [3]F{
                                coords.x[nn] / image_scale,
                                coords.y[nn] / image_scale,
                                coords.z[nn] - center_z,
                            };
                            for (0..3) |axis| {
                                pos[axis] += weights[nn] * node[axis];
                                tang_u[axis] += du[nn] * node[axis];
                                tang_v[axis] += dv[nn] * node[axis];
                            }
                        }
                        const normal = [3]F{
                            tang_u[1] * tang_v[2] - tang_u[2] * tang_v[1],
                            tang_u[2] * tang_v[0] - tang_u[0] * tang_v[2],
                            tang_u[0] * tang_v[1] - tang_u[1] * tang_v[0],
                        };
                        var radial = pos;
                        if (kind == .outward_cylinder_3d) {
                            const axis = [3]F{ -s * ct, c * ct, st };
                            const axial = pos[0] * axis[0] +
                                pos[1] * axis[1] + pos[2] * axis[2];
                            for (0..3) |ii| {
                                radial[ii] -= axial * axis[ii];
                            }
                        }
                        const outward = normal[0] * radial[0] +
                            normal[1] * radial[1] + normal[2] * radial[2];
                        try std.testing.expect(outward > 0);
                        const px = image_scale * pos[0] /
                            (center_z + pos[2]) + 50;
                        const py = image_scale * pos[1] /
                            (center_z + pos[2]) + 50;
                        if (px < 0 or px >= 100 or py < 0 or py >= 100) {
                            continue;
                        }
                        var local_coords = coords;
                        const nodes = rops.Vec3Slices(F){
                            .x = &local_coords.x,
                            .y = &local_coords.y,
                            .z = &local_coords.z,
                        };
                        const facing = rops.projectedJacDetPhysical(
                            N,
                            nodes,
                            u,
                            v,
                        );
                        if (!std.math.isFinite(facing) or facing >=
                            -buildconfig.config.tol.culling.projected_jacobian_abs)
                        {
                            continue;
                        }
                        const exact_depth = oracleFeDepth(
                            N,
                            fe_surface,
                            nodes,
                            px,
                            py,
                        );
                        try std.testing.expect(
                            exact_depth + 1e-7 >= 1 / (center_z + pos[2]),
                        );
                        try std.testing.expect(candidate.contains(px, py));
                        try std.testing.expect(
                            containsSubpatch(&subpatches, px, py),
                        );
                        try std.testing.expect(
                            containsSubpatch(&oracle_subpatches, px, py),
                        );
                        try recordFactorialRay(
                            N,
                            kind,
                            coords,
                            &candidate,
                            px,
                            py,
                            exact_depth,
                            hierarchy_fixture,
                            factorial,
                        );
                        recordHierarchySeedSweepRay(
                            N,
                            kind,
                            coords,
                            px,
                            py,
                            exact_depth,
                            &hierarchy_fixtures,
                            factorial,
                        );
                        patch_rays += 1;
                        ray_count += 1;
                    }
                }
                try measureCurvedMissRays(
                    N,
                    kind,
                    coords,
                    &candidate,
                    &oracle_subpatches,
                    hierarchy_fixture,
                    factorial,
                );
                if (patch_rays > 0) {
                    theta_seen[theta_idx] = true;
                    secondary_seen[secondary_idx] = true;
                    roll_seen[roll_idx] = true;
                }
            }
        }
    }
    for (theta_seen) |seen| try std.testing.expect(seen);
    for (secondary_seen) |seen| try std.testing.expect(seen);
    for (roll_seen) |seen| try std.testing.expect(seen);
    try std.testing.expect(patch_count >= 12);
    try std.testing.expect(ray_count >= 100);
    std.debug.print(
        "outward curved N={d} kind={s} patches={d} rays={d} " ++
            "node_d3_front={d}\n",
        .{
            N,
            @tagName(kind),
            patch_count,
            ray_count,
            factorial.facing.cell(
                kind,
                .nodes_center,
                .front_first,
                .depth,
                .first_three,
                0,
            ).front - d3_before,
        },
    );
}

fn measureQuadraticSaddle(
    camera: *const cam.CameraPrepared,
    factorial: *FactorialStats,
) !void {
    // At v=-1 the u-edge has x-curvature -10; at v=+1 it has +50.
    // The physical cross product retains a nonzero x component because
    // y_v is nonzero and z_u=0.2, even where the projection folds.
    const parents = comptime gk.parentNodeCoords(8);
    const angles = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    var sampled: usize = 0;
    for ([_]F{ -0.5, 0, 0.5 }, 0..) |ridge, ridge_idx| {
        for (angles, 0..) |angle, angle_idx| {
            const c = @cos(angle);
            const s = @sin(angle);
            for ([_]F{ -1, 1 }, 0..) |polarity, polarity_idx| {
                const y_scale = polarity * -20;
                var coords: rops.GatheredElemCoords(8) = undefined;
                for (parents, 0..) |parent, nn| {
                    const u = parent[0];
                    const v = parent[1];
                    const x = 20 * (u - ridge) * (u - ridge) +
                        30 * v * (u * u - 1);
                    const y = y_scale * v;
                    coords.x[nn] = c * x - s * y;
                    coords.y[nn] = s * x + c * y;
                    coords.z[nn] = 1 + 0.2 * u;
                }
                var weights: [8]F = undefined;
                var du: [8]F = undefined;
                var dv: [8]F = undefined;
                const check_u: F = 0.37;
                const check_v: F = -0.28;
                shapefun.shapeFunc(8, check_u, check_v, &weights, &du, &dv);
                var check_x: F = 0;
                var check_y: F = 0;
                var check_z: F = 0;
                for (0..8) |nn| {
                    check_x += weights[nn] * coords.x[nn];
                    check_y += weights[nn] * coords.y[nn];
                    check_z += weights[nn] * coords.z[nn];
                }
                const analytic_x = 20 * (check_u - ridge) *
                    (check_u - ridge) +
                    30 * check_v * (check_u * check_u - 1);
                const analytic_y = y_scale * check_v;
                try std.testing.expectApproxEqAbs(
                    c * analytic_x - s * analytic_y,
                    check_x,
                    1e-10,
                );
                try std.testing.expectApproxEqAbs(
                    s * analytic_x + c * analytic_y,
                    check_y,
                    1e-10,
                );
                try std.testing.expectApproxEqAbs(
                    1 + 0.2 * check_u,
                    check_z,
                    1e-10,
                );
                const candidate = hull.buildMultiRootHullFromClip(
                    8,
                    camera,
                    coords,
                );
                const hierarchy_fixture = HierarchyFixture.init(8, camera, coords);
                measureCoherentPatch(
                    8,
                    .quadratic_saddle,
                    ridge_idx * 8 + angle_idx * 2 + polarity_idx,
                    camera,
                    coords,
                    .{
                        .ridge = ridge,
                        .c = c,
                        .s = s,
                        .polarity = polarity,
                    },
                );
                const nodes = rops.Vec3Slices(F){
                    .x = &coords.x,
                    .y = &coords.y,
                    .z = &coords.z,
                };
                for (0..11) |ui| {
                    for (0..11) |vi| {
                        const source_u = 2 *
                            (@as(F, @floatFromInt(ui)) + 0.5) / 11 - 1;
                        const source_v = 2 *
                            (@as(F, @floatFromInt(vi)) + 0.5) / 11 - 1;
                        const z0 = 1 + 0.2 * source_u;
                        const x0 = 20 * (source_u - ridge) *
                            (source_u - ridge) +
                            30 * source_v * (source_u * source_u - 1);
                        const qx = x0 / z0;
                        const qy = y_scale * source_v / z0;
                        const px = c * qx - s * qy + 50;
                        const py = s * qx + c * qy + 50;
                        if (px < 0 or px >= 100 or py < 0 or py >= 100) continue;
                        var roots: [4]F = undefined;
                        roots[0] = source_u;
                        var root_count: usize = 1;
                        var prev_u: F = -1;
                        var prev_f = saddleRayResidual(
                            prev_u,
                            qx,
                            qy,
                            ridge,
                            y_scale,
                        );
                        for (1..1025) |ii| {
                            const next_u = -1 +
                                2 * @as(F, @floatFromInt(ii)) / 1024;
                            const next_f = saddleRayResidual(
                                next_u,
                                qx,
                                qy,
                                ridge,
                                y_scale,
                            );
                            if (prev_f * next_f <= 0) {
                                var lo = prev_u;
                                var hi = next_u;
                                const lo_positive = prev_f > 0;
                                for (0..45) |_| {
                                    const mid = 0.5 * (lo + hi);
                                    const mid_f = saddleRayResidual(
                                        mid,
                                        qx,
                                        qy,
                                        ridge,
                                        y_scale,
                                    );
                                    if ((mid_f > 0) == lo_positive) {
                                        lo = mid;
                                    } else {
                                        hi = mid;
                                    }
                                }
                                const root = 0.5 * (lo + hi);
                                var duplicate = false;
                                for (roots[0..root_count]) |known| {
                                    if (@abs(known - root) < 1e-5) {
                                        duplicate = true;
                                        break;
                                    }
                                }
                                if (!duplicate and root_count < roots.len) {
                                    roots[root_count] = root;
                                    root_count += 1;
                                }
                            }
                            prev_u = next_u;
                            prev_f = next_f;
                        }
                        if (root_count < 2) continue;
                        var expected: ?F = null;
                        for (roots[0..root_count]) |u| {
                            const z = 1 + 0.2 * u;
                            const v = qy * z / y_scale;
                            if (!isInParent(8, u, v)) continue;
                            const facing = rops.projectedJacDetPhysical(
                                8,
                                nodes,
                                u,
                                v,
                            );
                            if (facing < -buildconfig.config.tol.culling.projected_jacobian_abs) {
                                expected = @max(expected orelse 0, 1 / z);
                            }
                        }
                        const front_depth = expected orelse continue;
                        sampled += 1;
                        try recordFactorialRay(
                            8,
                            .quadratic_saddle,
                            coords,
                            &candidate,
                            px,
                            py,
                            front_depth,
                            &hierarchy_fixture,
                            factorial,
                        );
                    }
                }
            }
        }
    }
    try std.testing.expect(sampled > 100);
}

fn checkDefaultBankFixture() !void {
    // The physical tangents have cross product (4, 0, -800(u - 0.8)),
    // so this fold has a nonzero physical Jacobian everywhere.
    const parents = comptime gk.parentNodeCoords(8);
    var coords: rops.GatheredElemCoords(8) = undefined;
    for (parents, 0..) |parent, nn| {
        const u = parent[0];
        coords.x[nn] = 20 * (u - 0.8) * (u - 0.8);
        coords.y[nn] = -20 * parent[1];
        coords.z[nn] = 1 + 0.2 * u;
    }
    const nodes = rops.Vec3Slices(F){
        .x = &coords.x,
        .y = &coords.y,
        .z = &coords.z,
    };
    const GK = gk.Quad89Kernel(8);
    const near_u: F = 0.76;
    const ray_x = 20 * (near_u - 0.8) * (near_u - 0.8) /
        (1 + 0.2 * near_u);
    var old_first_front_depth: ?usize = null;
    // Stable camera-depth order: three u=-1 nodes, three u=0 seeds
    // (including the virtual centre), then three u=1 nodes.
    const bank = [_]usize{ 0, 3, 7, 4, 6, 8, 1, 2, 5 };
    for (bank, 0..) |nn, pass| {
        const seed = if (nn == 8)
            [2]F{ 0, 0 }
        else
            parents[nn];
        const result = GK.solveWeightsNewton(
            nodes,
            50 + ray_x,
            50,
            50,
            50,
            seed[0],
            seed[1],
        );
        if (result.weights == null) continue;
        if (GK.domViolation(result.xi_out, result.eta_out) > 0) continue;
        const facing = rops.projectedJacDetPhysical(
            8,
            nodes,
            result.xi_out,
            result.eta_out,
        );
        if (facing < 0 and old_first_front_depth == null) {
            old_first_front_depth = pass + 1;
        }
    }
    const expanded = expandedBank(8, coords);
    var expanded_first_front_depth: ?usize = null;
    for (expanded, 0..) |seed, pass| {
        if (seedResult(8, nodes, 50 + ray_x, 50, seed) == null) continue;
        expanded_first_front_depth = pass + 1;
        break;
    }
    try std.testing.expect(old_first_front_depth != null);
    try std.testing.expect(expanded_first_front_depth != null);
    // This is a known limitation of shallow seed banks, not a regression in
    // the hierarchy: preserve the counterexample as an explicit diagnostic.
    try std.testing.expect(expanded_first_front_depth.? > 3);
    std.debug.print(
        "known shallow-bank miss: old first D={d}, expanded first D={d}\n",
        .{ old_first_front_depth.?, expanded_first_front_depth.? },
    );
}

fn checkThreeRootQuad8(camera: *const cam.CameraPrepared) !void {
    const parents = comptime gk.parentNodeCoords(8);
    var coords: rops.GatheredElemCoords(8) = undefined;
    var projected: rops.RasterCoords2D(8) = undefined;
    for (parents, 0..) |parent, nn| {
        const u = 1 + 0.2 * parent[0];
        const v = 1 + 0.2 * parent[1];
        const q = u * u * v - 3 * u * u + 2.9775 * u - 0.9775;
        coords.x[nn] = u;
        coords.y[nn] = v;
        coords.z[nn] = u + 0.5 * q;
        projected.x[nn] = u / coords.z[nn] + 50;
        projected.y[nn] = v / coords.z[nn] + 50;
    }
    try std.testing.expectEqual(
        rops.RootClass.multi_root,
        rops.classifyHighOrdFacing(8, projected).?,
    );
    const candidate = hull.buildMultiRootHullFromClip(8, camera, coords);
    try std.testing.expect(candidate.contains(51, 51));

    // On the ray (x/z, y/z)=(1,1), q(s,s) factors as
    // (s-0.85)(s-1)(s-1.15). The physical Jacobian is nonsingular since
    // its cross-product z component is 0.04 throughout the parent square.
    const GK = gk.Quad89Kernel(8);
    const nodes = rops.Vec3Slices(F){
        .x = &coords.x,
        .y = &coords.y,
        .z = &coords.z,
    };
    const roots = [_]F{ -0.75, 0, 0.75 };
    var facing: [3]F = undefined;
    for (roots, 0..) |seed, ii| {
        const result = GK.solveWeightsNewton(
            nodes,
            51,
            51,
            50,
            50,
            seed,
            seed,
        );
        try std.testing.expect(result.weights != null);
        try std.testing.expectApproxEqAbs(seed, result.xi_out, 1e-7);
        try std.testing.expectApproxEqAbs(seed, result.eta_out, 1e-7);
        facing[ii] = rops.projectedJacDetPhysical(
            8,
            nodes,
            result.xi_out,
            result.eta_out,
        );
    }
    try std.testing.expect(facing[0] * facing[1] < 0);
    try std.testing.expect(facing[1] * facing[2] < 0);
    try std.testing.expect(facing[0] < 0 and facing[2] < 0);
}

fn measureThreeRootMatrix(
    camera: *const cam.CameraPrepared,
    factorial: *FactorialStats,
) !void {
    const parents = comptime gk.parentNodeCoords(8);
    const spreads = [_]F{ 0.1, 0.15, 0.18 };
    const depths = [_]F{ 0.25, 0.5, 1.0 };
    const angles = [_]F{
        0,
        std.math.pi / 4.0,
        std.math.pi / 2.0,
        3.0 * std.math.pi / 4.0,
    };
    for ([_]F{ -1, 1 }, 0..) |polarity, polarity_idx| {
        var stats = SeedStats{};
        var skipped: usize = 0;
        var d3_noearly_nearest: usize = 0;
        var diverse_noearly_nearest: usize = 0;
        for (spreads, 0..) |spread, spread_idx| {
            const pair_sum = 3 - spread * spread;
            const product = 1 - spread * spread;
            for (depths, 0..) |depth_scale, depth_idx| {
                for (angles, 0..) |angle, angle_idx| {
                    const c = @cos(angle);
                    const s = @sin(angle);
                    var coords: rops.GatheredElemCoords(8) = undefined;
                    var projected: rops.RasterCoords2D(8) = undefined;
                    for (parents, 0..) |parent, nn| {
                        const u = 1 + 0.2 * parent[0];
                        const v = 1 + 0.2 * parent[1];
                        const q = u * u * v - 3 * u * u +
                            pair_sum * u - product;
                        const x = 20 * u;
                        const y = polarity * 20 * v;
                        coords.x[nn] = c * x - s * y;
                        coords.y[nn] = s * x + c * y;
                        coords.z[nn] = u + depth_scale * q;
                        projected.x[nn] = coords.x[nn] / coords.z[nn] + 50;
                        projected.y[nn] = coords.y[nn] / coords.z[nn] + 50;
                    }
                    try std.testing.expectEqual(
                        rops.RootClass.multi_root,
                        rops.classifyHighOrdFacing(8, projected).?,
                    );
                    const px = 20 * (c - s * polarity) + 50;
                    const py = 20 * (s + c * polarity) + 50;
                    const candidate = hull.buildMultiRootHullFromClip(
                        8,
                        camera,
                        coords,
                    );
                    const hierarchy_fixture = HierarchyFixture.init(8, camera, coords);
                    measureCoherentPatch(
                        8,
                        .compound_three_root,
                        spread_idx * 24 + depth_idx * 8 +
                            angle_idx * 2 + polarity_idx,
                        camera,
                        coords,
                        null,
                    );
                    try std.testing.expect(candidate.contains(px, py));
                    const nodes = rops.Vec3Slices(F){
                        .x = &coords.x,
                        .y = &coords.y,
                        .z = &coords.z,
                    };
                    var oracle_best: ?F = null;
                    for ([_]F{ -spread / 0.2, 0, spread / 0.2 }) |root| {
                        const facing = rops.projectedJacDetPhysical(
                            8,
                            nodes,
                            root,
                            root,
                        );
                        if (facing <
                            -buildconfig.config.tol.culling.projected_jacobian_abs)
                        {
                            const inv_z = 1 / (1 + 0.2 * root);
                            oracle_best = @max(oracle_best orelse 0, inv_z);
                        }
                    }
                    const expected = oracle_best orelse {
                        skipped += 1;
                        continue;
                    };
                    try std.testing.expectApproxEqAbs(
                        expected,
                        oracleFeDepth(
                            8,
                            oracleSurface(8, coords),
                            nodes,
                            px,
                            py,
                        ),
                        1e-7,
                    );
                    try recordFactorialRay(
                        8,
                        .compound_three_root,
                        coords,
                        &candidate,
                        px,
                        py,
                        expected,
                        &hierarchy_fixture,
                        factorial,
                    );
                    var bank: [9]BankSeed = undefined;
                    for (parents, 0..) |parent, nn| {
                        bank[nn] = .{
                            .uv = parent,
                            .z = coords.z[nn],
                            .index = @intCast(nn),
                        };
                    }
                    bank[8] = .{
                        .uv = .{ 0, 0 },
                        .z = 1,
                        .index = 8,
                    };
                    for (1..9) |ii| {
                        const seed = bank[ii];
                        var jj = ii;
                        while (jj > 0 and (bank[jj - 1].z > seed.z or
                            (bank[jj - 1].z == seed.z and
                                bank[jj - 1].index > seed.index)))
                        {
                            bank[jj] = bank[jj - 1];
                            jj -= 1;
                        }
                        bank[jj] = seed;
                    }
                    var deep = bank[8];
                    var best_dist = std.math.inf(F);
                    for (bank) |seed| {
                        const dist = seed.uv[0] * seed.uv[0] +
                            seed.uv[1] * seed.uv[1];
                        if (seed.z == bank[8].z and dist < best_dist) {
                            deep = seed;
                            best_dist = dist;
                        }
                    }
                    const diverse = [3]BankSeed{
                        bank[0], deep, .{ .uv = .{ 0, 0 }, .z = 1, .index = 8 },
                    };
                    const expanded = expandedBank(8, coords);
                    const half_diverse = halfDiverseBank(8, &expanded);
                    stats.rays += 1;
                    stats.visible += 1;
                    const first = seedResult(8, nodes, px, py, bank[0]);
                    if (first) |found| {
                        stats.first_front += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.first_nearest += 1;
                        }
                    }
                    const d3 = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        bank[0..3],
                        true,
                    );
                    if (d3) |found| {
                        stats.d3_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.d3_nearest += 1;
                        }
                    }
                    const d3_noearly = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        bank[0..3],
                        false,
                    );
                    if (d3_noearly) |found| {
                        if (@abs(found - expected) < 1e-7) {
                            d3_noearly_nearest += 1;
                        }
                    }
                    const diverse_result = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        &diverse,
                        true,
                    );
                    if (diverse_result) |found| {
                        stats.diverse_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.diverse_nearest += 1;
                        }
                    }
                    const diverse_noearly = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        &diverse,
                        false,
                    );
                    if (diverse_noearly) |found| {
                        if (@abs(found - expected) < 1e-7) {
                            diverse_noearly_nearest += 1;
                        }
                    }
                    const full = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        &bank,
                        false,
                    );
                    if (full) |found| {
                        stats.full_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.full_nearest += 1;
                        }
                    }
                    const expanded_d3 = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        expanded[0..3],
                        true,
                    );
                    if (expanded_d3) |found| {
                        stats.expanded_d3_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.expanded_d3_nearest += 1;
                        }
                    }
                    const expanded_full = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        &expanded,
                        false,
                    );
                    try std.testing.expect(expanded_full != null);
                    try std.testing.expectApproxEqAbs(
                        expected,
                        expanded_full.?,
                        1e-7,
                    );
                    if (expanded_full) |found| {
                        stats.expanded_full_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.expanded_full_nearest += 1;
                        }
                    }
                    const half_d3 = bestSeedResult(
                        8,
                        nodes,
                        px,
                        py,
                        &half_diverse,
                        true,
                    );
                    if (half_d3) |found| {
                        stats.half_d3_found += 1;
                        if (@abs(found - expected) < 1e-7) {
                            stats.half_d3_nearest += 1;
                        }
                    }
                }
            }
        }
        std.debug.print(
            "three-root quad8 polarity={d}: rays={d} first_front={d} " ++
                "first_nearest={d} D3_found={d} D3_nearest={d} " ++
                "D3_noearly_nearest={d} diverse_found={d} " ++
                "diverse_nearest={d} diverse_noearly_nearest={d} " ++
                "full_found={d} full_nearest={d} " ++
                "expanded_D3={d}/{d} expanded_full={d}/{d} " ++
                "half_D3={d}/{d} skipped={d}\n",
            .{
                polarity,
                stats.rays,
                stats.first_front,
                stats.first_nearest,
                stats.d3_found,
                stats.d3_nearest,
                d3_noearly_nearest,
                stats.diverse_found,
                stats.diverse_nearest,
                diverse_noearly_nearest,
                stats.full_found,
                stats.full_nearest,
                stats.expanded_d3_found,
                stats.expanded_d3_nearest,
                stats.expanded_full_found,
                stats.expanded_full_nearest,
                stats.half_d3_found,
                stats.half_d3_nearest,
                skipped,
            },
        );
    }
}
