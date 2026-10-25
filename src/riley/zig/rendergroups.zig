// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

pub const RenderGroup = struct {
    io: std.Io,
    save_frame_io: ?std.Io = null,
    workers: u16,
};

/// Owns render-group groups and their backing I/O instances. Do not copy the
/// owner or resize its storage. groups and I/O handles expire on deinit.
/// The allocator must support concurrent allocation when rendering in parallel;
/// it and the supplied process environment must outlive this owner.
/// Deinit requires the same allocator passed to init.
pub const ManagedRenderGroups = struct {
    managed_ios: []std.Io.Threaded,
    groups: []RenderGroup,

    /// The budget includes callers but excludes disk-save overlap threads.
    /// Pass null for `max_groups` to allow one group per budgeted thread, or
    /// null for `minimal` when embedding without a Zig process.Init.
    /// Workers are distributed evenly, with extras in the first groups.
    pub fn init(
        outer_alloc: std.mem.Allocator,
        minimal: ?std.process.Init.Minimal,
        thread_budget: u16,
        max_groups: ?u16,
    ) !ManagedRenderGroups {
        if (thread_budget == 0) return error.InvalidThreadBudget;
        const cap = max_groups orelse thread_budget;
        if (cap == 0) return error.InvalidMaxGroups;
        const group_count = @min(thread_budget, cap);
        const base_workers = thread_budget / group_count;
        const remainder = thread_budget % group_count;

        const managed_ios = try outer_alloc.alloc(std.Io.Threaded, group_count);
        errdefer outer_alloc.free(managed_ios);
        const groups = try outer_alloc.alloc(RenderGroup, group_count);
        errdefer outer_alloc.free(groups);

        for (managed_ios, groups, 0..) |*managed_io, *spec, index| {
            const workers = base_workers + @as(u16, @intFromBool(index < remainder));
            const limit: std.Io.Limit = if (workers == 1)
                .nothing
            else
                .limited(workers - 1);
            managed_io.* = std.Io.Threaded.init(outer_alloc, .{
                .argv0 = if (minimal) |process| .init(process.args) else .empty,
                .environ = if (minimal) |process| process.environ else .empty,
                .async_limit = limit,
                .concurrent_limit = limit,
            });
            spec.* = .{ .io = managed_io.io(), .workers = workers };
        }
        return .{ .managed_ios = managed_ios, .groups = groups };
    }

    /// Finish all rendering before deinit; pass the same allocator used by init.
    pub fn deinit(self: *ManagedRenderGroups, outer_alloc: std.mem.Allocator) void {
        for (self.managed_ios) |*managed_io| {
            managed_io.deinit();
        }
        outer_alloc.free(self.groups);
        outer_alloc.free(self.managed_ios);
        self.* = undefined;
    }
};

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------
fn allocationFailureProbe(local_alloc: std.mem.Allocator) !void {
    var groups = try ManagedRenderGroups.init(local_alloc, null, 7, 3);
    defer groups.deinit(local_alloc);
}

test "render group budgets use all workers and distribute remainders evenly" {
    const cases = [_]struct {
        budget: u16,
        cap: ?u16,
        expected: []const u16,
    }{
        .{ .budget = 1, .cap = null, .expected = &.{1} },
        .{ .budget = 8, .cap = null, .expected = &.{ 1, 1, 1, 1, 1, 1, 1, 1 } },
        .{ .budget = 12, .cap = 3, .expected = &.{ 4, 4, 4 } },
        .{ .budget = 12, .cap = 5, .expected = &.{ 3, 3, 2, 2, 2 } },
        .{ .budget = 7, .cap = 3, .expected = &.{ 3, 2, 2 } },
        .{ .budget = 3, .cap = 8, .expected = &.{ 1, 1, 1 } },
        .{ .budget = 65535, .cap = 2, .expected = &.{ 32768, 32767 } },
    };
    for (cases) |case| {
        var groups = try ManagedRenderGroups.init(
            std.testing.allocator,
            null,
            case.budget,
            case.cap,
        );
        defer groups.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.expected.len, groups.groups.len);
        var total: usize = 0;
        for (groups.groups, groups.managed_ios, case.expected) |spec, *managed_io, workers| {
            try std.testing.expectEqual(workers, spec.workers);
            try std.testing.expectEqual(managed_io.io().userdata, spec.io.userdata);
            const concurrent_limit = @intFromEnum(managed_io.concurrent_limit);
            try std.testing.expectEqual(@as(usize, workers - 1), concurrent_limit);
            try std.testing.expectEqual(managed_io.async_limit, managed_io.concurrent_limit);
            total += spec.workers;
        }
        try std.testing.expectEqual(@as(usize, case.budget), total);
    }
}

test "render group budgets reject zero budget and zero cap" {
    try std.testing.expectError(
        error.InvalidThreadBudget,
        ManagedRenderGroups.init(std.testing.allocator, null, 0, null),
    );
    try std.testing.expectError(
        error.InvalidMaxGroups,
        ManagedRenderGroups.init(std.testing.allocator, null, 1, 0),
    );
}

test "render groups clean up either allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailureProbe, .{});
}
