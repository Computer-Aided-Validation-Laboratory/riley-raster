// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");

// Parallel Chunk Executioner
//---------------------------------------------------------------------------
// Execution helper for "parallel for" type work by breaking the range of the loop into
// chunks and executing these chunks on a pool of threads.
// runStaticRange:  Each thread executes a statically assigned chunk (no work stealing)
// runDynamicRange: Each thread takes a "grain" of the range and can work steal using an
//                  atomic counter.

pub const RangeFn = *const fn (
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void;

pub const RangeWorkerFnError = *const fn (
    ctx_ptr: *anyopaque,
    worker_idx: usize,
    range_start: usize,
    range_end: usize,
) anyerror!void;

const WorkerErrorState = struct {
    mutex: std.atomic.Mutex = .unlocked,
    first_err: ?anyerror = null,

    fn setFirst(
        self: *WorkerErrorState,
        err: anyerror,
    ) void {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        if (self.first_err == null) {
            self.first_err = err;
        }
    }

    fn getFirst(self: *WorkerErrorState) ?anyerror {
        while (!self.mutex.tryLock()) {
            std.atomic.spinLoopHint();
        }
        defer self.mutex.unlock();
        return self.first_err;
    }
};

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
            group.async(
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
            group.async(
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

    pub fn runDynamicRangeWithWorkerError(
        self: *ParaChunkExecutor,
        ctx_ptr: *anyopaque,
        job_func: RangeWorkerFnError,
        domain_len: usize,
        grain_size: usize,
    ) !void {
        if (domain_len == 0) {
            return;
        }

        std.debug.assert(grain_size > 0);

        var next_start = std.atomic.Value(usize).init(0);
        var err_state = WorkerErrorState{};
        var group: std.Io.Group = .init;
        errdefer group.cancel(self.io);

        for (0..self.workers_num) |worker_idx| {
            group.async(
                self.io,
                runDynamicChunkTaskWithWorkerError,
                .{
                    ctx_ptr,
                    job_func,
                    worker_idx,
                    &err_state,
                    &next_start,
                    domain_len,
                    grain_size,
                },
            );
        }

        try group.await(self.io);
        if (err_state.getFirst()) |err| {
            return err;
        }
    }
};

//------------------------------------------------------------------------------------------
// Work chunking helpers
//------------------------------------------------------------------------------------------

pub fn getChunksNum(domain_len: usize, chunk_size: usize) usize {
    if (domain_len == 0) {
        return 0;
    }
    return (domain_len + chunk_size - 1) / chunk_size;
}

//------------------------------------------------------------------------------------------
// Internal helpers for running the chunk executor
//------------------------------------------------------------------------------------------
// Static  = fixed static allocation of chunks to a worker
// Dynamic = dynamic allocation of grains allowing work stealing
// WithWorker = access per worker state that is initialised once like buffers and allocators

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
    const grains_num = getChunksNum(domain_len, grain_size);
    for (0..grains_num) |grain_idx| {
        const range_start = grain_idx * grain_size;
        const range_end = @min(domain_len, range_start + grain_size);
        job_func(ctx_ptr, 0, range_start, range_end);
    }
}

fn runDynamicRangeWithWorkerErrorSerial(
    ctx_ptr: *anyopaque,
    job_func: RangeWorkerFnError,
    domain_len: usize,
    grain_size: usize,
) !void {
    const grains_num = getChunksNum(domain_len, grain_size);
    for (0..grains_num) |grain_idx| {
        const range_start = grain_idx * grain_size;
        const range_end = @min(domain_len, range_start + grain_size);
        try job_func(ctx_ptr, 0, range_start, range_end);
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

fn runDynamicChunkTaskWithWorkerError(
    ctx_ptr: *anyopaque,
    job_func: RangeWorkerFnError,
    worker_idx: usize,
    err_state: *WorkerErrorState,
    next_start: *std.atomic.Value(usize),
    domain_len: usize,
    grain_size: usize,
) std.Io.Cancelable!void {
    while (true) {
        if (err_state.getFirst() != null) {
            return;
        }
        const range_start = next_start.fetchAdd(grain_size, .monotonic);
        if (range_start >= domain_len) {
            return;
        }
        const range_end = @min(domain_len, range_start + grain_size);
        job_func(ctx_ptr, worker_idx, range_start, range_end) catch |err| {
            err_state.setFirst(err);
            return;
        };
    }
}

//------------------------------------------------------------------------------------------
// External API for running the chunk executor
//------------------------------------------------------------------------------------------
// Static  = fixed static allocation of chunks to a worker
// Dynamic = dynamic allocation of grains allowing work stealing

pub fn runStaticRange(
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
        ) catch unreachable;
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
        ) catch unreachable;
        return;
    }

    runDynamicRangeSerial(
        ctx_ptr,
        job_func,
        domain_len,
        grain_size,
    );
}

pub fn runDynamicRangeWithWorkerErrorMaybe(
    chunk_exec: ?*ParaChunkExecutor,
    ctx_ptr: *anyopaque,
    job_func: RangeWorkerFnError,
    domain_len: usize,
    grain_size: usize,
) !void {
    if (domain_len == 0) {
        return;
    }

    if (chunk_exec) |executor| {
        try executor.runDynamicRangeWithWorkerError(
            ctx_ptr,
            job_func,
            domain_len,
            grain_size,
        );
        return;
    }

    try runDynamicRangeWithWorkerErrorSerial(
        ctx_ptr,
        job_func,
        domain_len,
        grain_size,
    );
}
