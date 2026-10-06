// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const F = @import("buildconfig.zig").F;

/// Diagnostics only: ignore roundoff-sized depth changes at the same root.
pub fn distinctDepthGain(before: F, after: F) bool {
    return after - before >
        1e-8 * @max(@as(F, 1), @abs(before));
}

pub const SeedKind = enum { center, reuse, extrapolate };

pub const Choice = struct {
    uv: [2]F,
    kind: SeedKind,
};

pub const ReuseMethod = enum {
    column,
    nearest_2d,
    interp_2d,
    affine_2d,
};

const Neighbour = struct {
    x: F,
    y: F,
    uv: [2]F,
    dist_sq: F,
};

/// Read only earlier raster rows. The slice belongs to one fixed4 child and
/// has one cache per column; the SIMD and scalar paths use the same stencil.
pub fn chooseLocal(
    caches: []const Cache,
    column: usize,
    row: usize,
    radius: usize,
    method: ReuseMethod,
    center: [2]F,
) Choice {
    if (method == .column) {
        return caches[column].choose(row, radius, false, center);
    }
    var neighbours: [4]Neighbour = undefined;
    var count: usize = 0;
    const first = if (column == 0) 0 else column - 1;
    const end = @min(column + 2, caches.len);
    for (first..end) |xx| {
        const cache = caches[xx];
        const use_prev = cache.last_valid and cache.last_y == row;
        const valid = if (use_prev) cache.prev_valid else cache.last_valid;
        const old_y = if (use_prev) cache.prev_y else cache.last_y;
        const old_uv = if (use_prev) cache.prev_uv else cache.last_uv;
        if (!valid or row <= old_y or row - old_y > radius) continue;
        const dx: F = @floatFromInt(@max(xx, column) - @min(xx, column));
        const dy: F = @floatFromInt(row - old_y);
        neighbours[count] = .{
            .x = @floatFromInt(xx),
            .y = @floatFromInt(old_y),
            .uv = old_uv,
            .dist_sq = dx * dx + dy * dy,
        };
        count += 1;
    }
    const same = caches[column];
    if (method == .affine_2d and same.prev_valid and
        row > same.prev_y and row - same.prev_y <= @max(radius, 2))
    {
        const dy: F = @floatFromInt(row - same.prev_y);
        neighbours[count] = .{
            .x = @floatFromInt(column),
            .y = @floatFromInt(same.prev_y),
            .uv = same.prev_uv,
            .dist_sq = dy * dy,
        };
        count += 1;
    }
    if (count == 0) return .{ .uv = center, .kind = .center };

    var nearest: usize = 0;
    for (1..count) |ii| {
        if (neighbours[ii].dist_sq < neighbours[nearest].dist_sq) {
            nearest = ii;
        }
    }
    const direct = Choice{ .uv = neighbours[nearest].uv, .kind = .reuse };
    if (method == .nearest_2d or count == 1) return direct;

    if (method == .interp_2d) {
        var left: ?Neighbour = null;
        var right: ?Neighbour = null;
        for (neighbours[0..count]) |candidate| {
            if (candidate.x < @as(F, @floatFromInt(column))) left = candidate;
            if (candidate.x > @as(F, @floatFromInt(column))) right = candidate;
        }
        if (left != null and right != null and left.?.y == right.?.y) {
            const a = left.?;
            const b = right.?;
            const t = (@as(F, @floatFromInt(column)) - a.x) / (b.x - a.x);
            return .{
                .uv = .{
                    a.uv[0] + t * (b.uv[0] - a.uv[0]),
                    a.uv[1] + t * (b.uv[1] - a.uv[1]),
                },
                .kind = .reuse,
            };
        }
    }

    if (method == .affine_2d and count >= 3) {
        const target_x: F = @floatFromInt(column);
        const target_y: F = @floatFromInt(row);
        for (0..count - 2) |aa| {
            for (aa + 1..count - 1) |bb| {
                for (bb + 1..count) |cc| {
                    const a = neighbours[aa];
                    const b = neighbours[bb];
                    const c = neighbours[cc];
                    const dx_b = b.x - a.x;
                    const dy_b = b.y - a.y;
                    const dx_c = c.x - a.x;
                    const dy_c = c.y - a.y;
                    const det = dx_b * dy_c - dy_b * dx_c;
                    if (@abs(det) < 0.25) continue;
                    const dx = target_x - a.x;
                    const dy = target_y - a.y;
                    const wb = (dx * dy_c - dy * dx_c) / det;
                    const wc = (dx_b * dy - dy_b * dx) / det;
                    const wa = 1 - wb - wc;
                    return .{
                        .uv = .{
                            wa * a.uv[0] + wb * b.uv[0] + wc * c.uv[0],
                            wa * a.uv[1] + wb * b.uv[1] + wc * c.uv[1],
                        },
                        .kind = .reuse,
                    };
                }
            }
        }
    }
    if (count < 2) return direct;
    var second: usize = if (nearest == 0) 1 else 0;
    for (0..count) |ii| {
        if (ii != nearest and
            neighbours[ii].dist_sq < neighbours[second].dist_sq)
        {
            second = ii;
        }
    }
    const a = neighbours[nearest];
    const b = neighbours[second];
    const wa = 1 / a.dist_sq;
    const wb = 1 / b.dist_sq;
    const sum = wa + wb;
    return .{
        .uv = .{
            (wa * a.uv[0] + wb * b.uv[0]) / sum,
            (wa * a.uv[1] + wb * b.uv[1]) / sum,
        },
        .kind = .reuse,
    };
}

/// One independent raster column of one fixed4 child patch. The caller resets
/// this tile-local state for each element; no state crosses workers or frames.
pub const Cache = struct {
    last_y: usize = 0,
    prev_y: usize = 0,
    last_uv: [2]F = .{ 0, 0 },
    last_inv_z: F = -1,
    prev_uv: [2]F = .{ 0, 0 },
    last_valid: bool = false,
    prev_valid: bool = false,

    pub fn choose(
        self: *const @This(),
        row: usize,
        radius: usize,
        extrapolate: bool,
        center: [2]F,
    ) Choice {
        if (!self.last_valid or row <= self.last_y or
            row - self.last_y > radius)
        {
            return .{ .uv = center, .kind = .center };
        }
        if (extrapolate and self.prev_valid and
            self.last_y > self.prev_y and
            self.last_y - self.prev_y <= radius)
        {
            const scale: F = @as(F, @floatFromInt(row - self.last_y)) /
                @as(F, @floatFromInt(self.last_y - self.prev_y));
            return .{
                .uv = .{
                    self.last_uv[0] + scale * (self.last_uv[0] - self.prev_uv[0]),
                    self.last_uv[1] + scale * (self.last_uv[1] - self.prev_uv[1]),
                },
                .kind = .extrapolate,
            };
        }
        return .{ .uv = self.last_uv, .kind = .reuse };
    }

    pub fn update(self: *@This(), row: usize, uv: [2]F, inv_z: F) void {
        if (self.last_valid and row == self.last_y) {
            if (inv_z > self.last_inv_z) {
                self.last_uv = uv;
                self.last_inv_z = inv_z;
            }
            return;
        }
        self.prev_valid = self.last_valid;
        self.prev_y = self.last_y;
        self.prev_uv = self.last_uv;
        self.last_valid = true;
        self.last_y = row;
        self.last_uv = uv;
        self.last_inv_z = inv_z;
    }
};

test "cache uses only local previous rows" {
    var cache = Cache{};
    const center = [2]F{ 0, 0 };
    try std.testing.expectEqual(SeedKind.center, cache.choose(1, 1, true, center).kind);
    cache.update(1, .{ 0.1, 0.2 }, 1);
    try std.testing.expectEqual(SeedKind.reuse, cache.choose(2, 1, true, center).kind);
    cache.update(2, .{ 0.2, 0.3 }, 1);
    const predicted = cache.choose(3, 1, true, center);
    try std.testing.expectEqual(SeedKind.extrapolate, predicted.kind);
    try std.testing.expectApproxEqAbs(@as(F, 0.3), predicted.uv[0], 1e-12);
    try std.testing.expectEqual(SeedKind.center, cache.choose(4, 1, true, center).kind);
}

test "distinct depth gain ignores numerical ties" {
    try std.testing.expect(!distinctDepthGain(0.5, 0.5 + 1e-10));
    try std.testing.expect(distinctDepthGain(0.5, 0.6));
}

test "local predictors use earlier child rows only" {
    var caches = [_]Cache{.{}} ** 3;
    const center = [2]F{ 0, 0 };
    caches[0].update(1, .{ 0, 0 }, 1);
    caches[1].update(0, .{ 1, -1 }, 1);
    caches[1].update(1, .{ 1, 0 }, 1);
    caches[2].update(1, .{ 2, 0 }, 1);
    try std.testing.expectEqual(
        SeedKind.reuse,
        chooseLocal(&caches, 1, 2, 1, .nearest_2d, center).kind,
    );
    const interp = chooseLocal(&caches, 1, 2, 1, .interp_2d, center);
    try std.testing.expectApproxEqAbs(@as(F, 1), interp.uv[0], 1e-12);
    const affine = chooseLocal(&caches, 1, 2, 1, .affine_2d, center);
    try std.testing.expectApproxEqAbs(@as(F, 1), affine.uv[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(F, 1), affine.uv[1], 1e-12);
    try std.testing.expectEqual(
        SeedKind.center,
        chooseLocal(&caches, 1, 4, 1, .nearest_2d, center).kind,
    );
}
