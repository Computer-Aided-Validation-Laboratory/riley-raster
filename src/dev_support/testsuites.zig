// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");

const SuiteCounts = struct {
    comparisons: usize,
    suites: usize,
};

const FailureCounts = struct {
    comparisons: std.atomic.Value(usize) = .init(0),
    suites: std.atomic.Value(usize) = .init(0),

    fn reset(self: *FailureCounts) void {
        self.comparisons.store(0, .monotonic);
        self.suites.store(0, .monotonic);
    }

    fn snapshot(self: *const FailureCounts) SuiteCounts {
        return .{
            .comparisons = self.comparisons.load(.monotonic),
            .suites = self.suites.load(.monotonic),
        };
    }

    fn recordGoldFailure(self: *FailureCounts, err: anyerror) !void {
        switch (err) {
            error.PixelMismatch, error.GoldRowsMismatch, error.GoldColsMismatch => {
                _ = self.comparisons.fetchAdd(1, .monotonic);
            },
            else => return err,
        }
    }
};

var failures = FailureCounts{};

pub fn beginSuiteRun() void {
    failures.reset();
}

/// Continue after gold differences, but do not hide rendering or I/O errors.
pub fn recordGoldFailure(err: anyerror) !void {
    try failures.recordGoldFailure(err);
}

pub fn finishSuiteRun(io: std.Io) !void {
    const counts = failures.snapshot();
    try printStatus(
        io,
        "Suite result: {d} gold comparison failures, {d} other suite failures.\n",
        .{ counts.comparisons, counts.suites },
    );
    if (counts.comparisons != 0 or counts.suites != 0) {
        return error.TestSuiteFailures;
    }
}

/// Flush each status message so long-running suites show progress immediately.
/// Suite build targets use the terminal runner: stdout is not a protocol stream.
pub fn printStatus(io: std.Io, comptime format: []const u8, args: anytype) !void {
    var buffer: [1024]u8 = undefined;
    // Streaming preserves the current file offset when stdout is redirected;
    // a fresh positional writer would overwrite previous messages at offset 0.
    var stdout_writer = std.Io.File.stdout().writerStreaming(io, &buffer);
    try stdout_writer.interface.print(format, args);
    try stdout_writer.interface.flush();
}

pub fn durationToSeconds(start: std.Io.Clock.Timestamp, end: std.Io.Clock.Timestamp) f64 {
    const elapsed_ns = start.durationTo(end).raw.nanoseconds;
    return @as(f64, @floatFromInt(elapsed_ns)) / 1.0e9;
}

pub fn runSuite(
    name: []const u8,
    local_alloc: std.mem.Allocator,
    io: std.Io,
    run: *const fn (std.mem.Allocator, std.Io) anyerror!void,
) !void {
    try printStatus(io, "Running {s} suite...\n", .{name});
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    run(local_alloc, io) catch |err| {
        _ = failures.suites.fetchAdd(1, .monotonic);
        try printStatus(io, "{s} suite failed: {s}\n", .{ name, @errorName(err) });
    };
    const end = std.Io.Clock.Timestamp.now(io, .awake);
    const elapsed_s = durationToSeconds(start, end);
    try printStatus(io, "{s} suite took {d:.3} seconds.\n", .{ name, elapsed_s });
}

pub fn runCase(
    name: []const u8,
    local_alloc: std.mem.Allocator,
    io: std.Io,
    run: *const fn (std.mem.Allocator, std.Io) anyerror!void,
) !void {
    try printStatus(io, "Running verification case: {s}...\n", .{name});
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    run(local_alloc, io) catch |err| {
        _ = failures.suites.fetchAdd(1, .monotonic);
        try printStatus(io, "Verification case {s} failed: {s}\n", .{ name, @errorName(err) });
    };
    const end = std.Io.Clock.Timestamp.now(io, .awake);
    const elapsed_s = durationToSeconds(start, end);
    try printStatus(io, "Verification case {s} took {d:.3} seconds.\n", .{ name, elapsed_s });
}

test "gold comparison failure counter resets without printing status" {
    var local = FailureCounts{};
    try local.recordGoldFailure(error.PixelMismatch);
    try std.testing.expectEqual(@as(usize, 1), local.snapshot().comparisons);
    local.reset();
    try std.testing.expectEqual(@as(usize, 0), local.snapshot().comparisons);
    try std.testing.expectEqual(@as(usize, 0), local.snapshot().suites);
    try std.testing.expectError(
        error.OutOfMemory,
        local.recordGoldFailure(error.OutOfMemory),
    );
}
