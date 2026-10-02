// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

pub const RenderGroupSpec = struct {
    io: std.Io,
    save_frame_io: ?std.Io = null,
    workers: u16,
};

pub const RenderGroupOptions = struct {
    /// Includes each group's caller thread; excludes disk-save overlap threads.
    thread_budget: u16,
    /// Limit concurrent groups (for available jobs or memory). Defaults to budget.
    max_groups: ?u16 = null,
};

/// Owns render-group specs and their backing I/O instances. Do not copy the
/// owner or resize its storage. Specs and I/O handles expire on deinit.
/// The allocator must support concurrent allocation when rendering in parallel;
/// it and the supplied process environment must outlive this owner.
/// Deinit requires the same allocator passed to init.
pub const ManagedRenderGroups = struct {
    managed_ios: []std.Io.Threaded,
    specs: []RenderGroupSpec,

    /// Groups-first allocation: cap the group count, then distribute all workers
    /// evenly, assigning one extra to the first remainder groups. Pass null for
    /// process metadata when embedding Riley without a Zig process.Init.
    pub fn init(
        outer_alloc: std.mem.Allocator,
        minimal: ?std.process.Init.Minimal,
        options: RenderGroupOptions,
    ) !ManagedRenderGroups {
        const layout = try Layout.init(options);
        const managed_ios = try outer_alloc.alloc(std.Io.Threaded, layout.groups);
        errdefer outer_alloc.free(managed_ios);
        const specs = try outer_alloc.alloc(RenderGroupSpec, layout.groups);
        errdefer outer_alloc.free(specs);

        for (managed_ios, specs, 0..) |*managed_io, *spec, index| {
            const workers = layout.getWorkers(index);
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
        return .{ .managed_ios = managed_ios, .specs = specs };
    }

    /// Finish all rendering before deinit; pass the same allocator used by init.
    pub fn deinit(self: *ManagedRenderGroups, outer_alloc: std.mem.Allocator) void {
        for (self.managed_ios) |*managed_io| {
            managed_io.deinit();
        }
        outer_alloc.free(self.specs);
        outer_alloc.free(self.managed_ios);
        self.* = undefined;
    }
};

const Layout = struct {
    groups: u16,
    base_workers: u16,
    remainder: u16,

    fn init(options: RenderGroupOptions) !Layout {
        if (options.thread_budget == 0) return error.InvalidThreadBudget;
        const cap = options.max_groups orelse options.thread_budget;
        if (cap == 0) return error.InvalidMaxGroups;
        const groups = @min(options.thread_budget, cap);
        return .{
            .groups = groups,
            .base_workers = options.thread_budget / groups,
            .remainder = options.thread_budget % groups,
        };
    }

    fn getWorkers(self: Layout, index: usize) u16 {
        return self.base_workers + @as(u16, @intFromBool(index < self.remainder));
    }
};

fn allocationFailureProbe(local_alloc: std.mem.Allocator) !void {
    var groups = try ManagedRenderGroups.init(local_alloc, null, .{
        .thread_budget = 7,
        .max_groups = 3,
    });
    defer groups.deinit(local_alloc);
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

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
        var groups = try ManagedRenderGroups.init(std.testing.allocator, null, .{
            .thread_budget = case.budget,
            .max_groups = case.cap,
        });
        defer groups.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.expected.len, groups.specs.len);
        var total: usize = 0;
        for (groups.specs, groups.managed_ios, case.expected) |spec, *managed_io, workers| {
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
        ManagedRenderGroups.init(std.testing.allocator, null, .{ .thread_budget = 0 }),
    );
    try std.testing.expectError(
        error.InvalidMaxGroups,
        ManagedRenderGroups.init(std.testing.allocator, null, .{
            .thread_budget = 1,
            .max_groups = 0,
        }),
    );
}

test "render groups clean up either allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailureProbe, .{});
}
