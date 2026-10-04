const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const F = buildconfig.F;
const cam = @import("../riley/zig/camera.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const hull = @import("../riley/zig/hull.zig");
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
    try checkControlNearPlane(&camera);
    try checkThreeRootQuad8(&camera);
    try measureThreeRootMatrix(&camera, &factorial);
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
    for (splits) |split| {
        var seed_stats = SeedStats{};
        const ridge: F = if (N == 6)
            1 - @sqrt(1 - split)
        else
            2 * split - 1;
        for (angles) |angle| {
            const c = @cos(angle);
            const s = @sin(angle);
            for ([_]F{ -1, 1 }) |polarity| {
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
                try measureSeedCases(
                    N,
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
};

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
    cells: [5][2][2][2][2][2]FacingCell =
        std.mem.zeroes([5][2][2][2][2][2]FacingCell),

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
    cells: [5][11][3]FrozenCell = std.mem.zeroes([5][11][3]FrozenCell),

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
    cells: [5][2][3][2]FactorialCell =
        std.mem.zeroes([5][2][3][2]FactorialCell),
    frozen: FrozenStats = .{},
    facing: FacingStats = .{},

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

fn recordFactorialRay(
    comptime N: usize,
    kind: FoldKind,
    coords: rops.GatheredElemCoords(N),
    candidate: *const hull.MultiRootHull,
    px: F,
    py: F,
    expected: F,
    stats: *FactorialStats,
) void {
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
    return diag;
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
            recordFactorialRay(N, kind, coords, candidate, px, py, expected, factorial);

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
    for ([_]F{ -0.5, 0, 0.5 }) |ridge| {
        for (angles) |angle| {
            const c = @cos(angle);
            const s = @sin(angle);
            for ([_]F{ -1, 1 }) |polarity| {
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
                        recordFactorialRay(
                            8,
                            .quadratic_saddle,
                            coords,
                            &candidate,
                            px,
                            py,
                            front_depth,
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
    if (expanded_first_front_depth.? > 3) {
        std.debug.print(
            "default D=3 misses valid quad8 front root: " ++
                "old first D={d}, expanded first D={d}\n",
            .{ old_first_front_depth.?, expanded_first_front_depth.? },
        );
        return error.DefaultSeedBankMissesValidFrontRoot;
    }
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
    for ([_]F{ -1, 1 }) |polarity| {
        var stats = SeedStats{};
        var skipped: usize = 0;
        var d3_noearly_nearest: usize = 0;
        var diverse_noearly_nearest: usize = 0;
        for (spreads) |spread| {
            const pair_sum = 3 - spread * spread;
            const product = 1 - spread * spread;
            for (depths) |depth_scale| {
                for (angles) |angle| {
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
                    recordFactorialRay(
                        8,
                        .compound_three_root,
                        coords,
                        &candidate,
                        px,
                        py,
                        expected,
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
