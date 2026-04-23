// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

pub const RangeFn = *const fn (
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void;

pub const ParaChunkExecutor = struct {
    io: std.Io,
    workers_num: usize,

    pub fn init(
        io: std.Io,
        workers_num: u16,
    ) ParaChunkExecutor {
        return .{
            .io = io,
            .workers_num = @intCast(workers_num),
        };
    }

    pub fn runStaticRange(
        self: *ParaChunkExecutor,
        ctx_ptr: *anyopaque,
        job_func: RangeFn,
        domain_len: usize,
        chunk_size: usize,
    ) !void {
        if (domain_len == 0) {
            return;
        }

        std.debug.assert(chunk_size > 0);

        var group: std.Io.Group = .init;
        errdefer group.cancel(self.io);

        const chunks_num = getChunksNum(domain_len, chunk_size);
        for (0..chunks_num) |chunk_idx| {
            const range_start = chunk_idx * chunk_size;
            const range_end = @min(domain_len, range_start + chunk_size);
            try group.concurrent(
                self.io,
                runStaticChunkTask,
                .{ ctx_ptr, job_func, chunk_idx, range_start, range_end },
            );
        }

        try group.await(self.io);
    }

    pub fn runDynamicRange(
        self: *ParaChunkExecutor,
        ctx_ptr: *anyopaque,
        job_func: RangeFn,
        domain_len: usize,
        grain_size: usize,
    ) !void {
        if (domain_len == 0) {
            return;
        }

        std.debug.assert(grain_size > 0);

        var next_start = std.atomic.Value(usize).init(0);
        var group: std.Io.Group = .init;
        errdefer group.cancel(self.io);

        for (0..self.workers_num) |_| {
            try group.concurrent(
                self.io,
                runDynamicChunkTask,
                .{
                    ctx_ptr,
                    job_func,
                    &next_start,
                    domain_len,
                    grain_size,
                },
            );
        }

        try group.await(self.io);
    }
};

pub fn getChunkSize(domain_len: usize, workers_num: usize) usize {
    if (domain_len == 0) {
        return 1;
    }

    const chunk_count = @max(@as(usize, 1), workers_num * 4);
    return @max(@as(usize, 1), (domain_len + chunk_count - 1) / chunk_count);
}

pub fn getChunksNum(domain_len: usize, chunk_size: usize) usize {
    if (domain_len == 0) {
        return 0;
    }
    return (domain_len + chunk_size - 1) / chunk_size;
}

pub fn getWorkerCount(chunk_exec: ?*ParaChunkExecutor) usize {
    if (chunk_exec) |executor| {
        return executor.workers_num;
    }
    return 1;
}

pub fn runStaticRangeMaybe(
    chunk_exec: ?*ParaChunkExecutor,
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    domain_len: usize,
    chunk_size: usize,
) void {
    if (domain_len == 0) {
        return;
    }

    if (chunk_exec) |executor| {
        executor.runStaticRange(
            ctx_ptr,
            job_func,
            domain_len,
            chunk_size,
        ) catch |err| switch (err) {
            error.ConcurrencyUnavailable => runStaticRangeSerial(
                ctx_ptr,
                job_func,
                domain_len,
                chunk_size,
            ),
            else => unreachable,
        };
        return;
    }

    runStaticRangeSerial(
        ctx_ptr,
        job_func,
        domain_len,
        chunk_size,
    );
}

pub fn runDynamicRangeMaybe(
    chunk_exec: ?*ParaChunkExecutor,
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    domain_len: usize,
    grain_size: usize,
) void {
    if (domain_len == 0) {
        return;
    }

    if (chunk_exec) |executor| {
        executor.runDynamicRange(
            ctx_ptr,
            job_func,
            domain_len,
            grain_size,
        ) catch |err| switch (err) {
            error.ConcurrencyUnavailable => runDynamicRangeSerial(
                ctx_ptr,
                job_func,
                domain_len,
                grain_size,
            ),
            else => unreachable,
        };
        return;
    }

    runDynamicRangeSerial(
        ctx_ptr,
        job_func,
        domain_len,
        grain_size,
    );
}

fn runStaticRangeSerial(
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    domain_len: usize,
    chunk_size: usize,
) void {
    const chunks_num = getChunksNum(domain_len, chunk_size);
    for (0..chunks_num) |chunk_idx| {
        const range_start = chunk_idx * chunk_size;
        const range_end = @min(domain_len, range_start + chunk_size);
        job_func(ctx_ptr, chunk_idx, range_start, range_end);
    }
}

fn runDynamicRangeSerial(
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    domain_len: usize,
    grain_size: usize,
) void {
    var range_start: usize = 0;
    while (range_start < domain_len) : (range_start += grain_size) {
        const range_end = @min(domain_len, range_start + grain_size);
        job_func(ctx_ptr, 0, range_start, range_end);
    }
}

fn runStaticChunkTask(
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) std.Io.Cancelable!void {
    job_func(ctx_ptr, chunk_idx, range_start, range_end);
}

fn runDynamicChunkTask(
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    next_start: *std.atomic.Value(usize),
    domain_len: usize,
    grain_size: usize,
) std.Io.Cancelable!void {
    while (true) {
        const range_start = next_start.fetchAdd(grain_size, .monotonic);
        if (range_start >= domain_len) {
            return;
        }
        const range_end = @min(domain_len, range_start + grain_size);
        job_func(ctx_ptr, 0, range_start, range_end);
    }
}
