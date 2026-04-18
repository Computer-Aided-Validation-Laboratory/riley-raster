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

pub const GeometryWorkerPool = struct {
    io: std.Io,
    threads: []std.Thread,
    mutex: std.Io.Mutex = .init,
    start_cond: std.Io.Condition = .init,
    done_cond: std.Io.Condition = .init,
    next_chunk_idx: std.atomic.Value(usize) = .init(0),
    domain_len: usize = 0,
    chunk_size: usize = 1,
    chunks_num: usize = 0,
    workers_done: usize = 0,
    generation: usize = 0,
    stop_requested: bool = false,
    active_job: bool = false,
    job_ctx_ptr: *anyopaque = undefined,
    job_func: RangeFn = undefined,

    pub fn init(
        self: *GeometryWorkerPool,
        allocator: std.mem.Allocator,
        io: std.Io,
        workers_num: u16,
    ) !void {
        const workers_len: usize = @intCast(workers_num);
        self.* = .{
            .io = io,
            .threads = try allocator.alloc(std.Thread, workers_len),
        };
        errdefer allocator.free(self.threads);

        for (0..workers_len) |worker_idx| {
            self.threads[worker_idx] = try std.Thread.spawn(
                .{},
                workerMain,
                .{ self, worker_idx },
            );
        }
    }

    pub fn deinit(
        self: *GeometryWorkerPool,
        allocator: std.mem.Allocator,
    ) void {
        self.mutex.lockUncancelable(self.io);
        self.stop_requested = true;
        self.start_cond.broadcast(self.io);
        self.mutex.unlock(self.io);

        for (self.threads) |thread| {
            thread.join();
        }
        allocator.free(self.threads);
    }

    pub fn runRange(
        self: *GeometryWorkerPool,
        ctx_ptr: *anyopaque,
        job_func: RangeFn,
        domain_len: usize,
        chunk_size: usize,
    ) void {
        if (domain_len == 0) {
            return;
        }

        std.debug.assert(chunk_size > 0);

        self.mutex.lockUncancelable(self.io);
        self.job_ctx_ptr = ctx_ptr;
        self.job_func = job_func;
        self.domain_len = domain_len;
        self.chunk_size = chunk_size;
        self.chunks_num = (domain_len + chunk_size - 1) / chunk_size;
        self.workers_done = 0;
        self.next_chunk_idx.store(0, .monotonic);
        self.active_job = true;
        self.generation += 1;
        self.start_cond.broadcast(self.io);

        while (self.active_job) {
            self.done_cond.waitUncancelable(self.io, &self.mutex);
        }
        self.mutex.unlock(self.io);
    }
};

fn workerMain(
    pool: *GeometryWorkerPool,
    worker_idx: usize,
) void {
    _ = worker_idx;
    var generation_seen: usize = 0;

    pool.mutex.lockUncancelable(pool.io);
    defer pool.mutex.unlock(pool.io);

    while (true) {
        while (!pool.stop_requested and generation_seen == pool.generation) {
            pool.start_cond.waitUncancelable(pool.io, &pool.mutex);
        }

        if (pool.stop_requested) {
            return;
        }

        generation_seen = pool.generation;
        const job_ctx_ptr = pool.job_ctx_ptr;
        const job_func = pool.job_func;
        const domain_len = pool.domain_len;
        const chunk_size = pool.chunk_size;
        const chunks_num = pool.chunks_num;
        pool.mutex.unlock(pool.io);

        while (true) {
            const chunk_idx = pool.next_chunk_idx.fetchAdd(1, .monotonic);
            if (chunk_idx >= chunks_num) {
                break;
            }

            const range_start = chunk_idx * chunk_size;
            const range_end = @min(domain_len, range_start + chunk_size);
            job_func(job_ctx_ptr, chunk_idx, range_start, range_end);
        }

        pool.mutex.lockUncancelable(pool.io);
        pool.workers_done += 1;
        if (pool.workers_done == pool.threads.len) {
            pool.active_job = false;
            pool.done_cond.signal(pool.io);
        }
    }
}
