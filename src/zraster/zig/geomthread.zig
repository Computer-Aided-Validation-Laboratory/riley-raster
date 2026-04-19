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
    workers_num: usize,

    pub fn init(
        self: *GeometryWorkerPool,
        allocator: std.mem.Allocator,
        io: std.Io,
        workers_num: u16,
    ) !void {
        _ = allocator;
        self.* = .{
            .io = io,
            .workers_num = @intCast(workers_num),
        };
    }

    pub fn deinit(
        self: *GeometryWorkerPool,
        allocator: std.mem.Allocator,
    ) void {
        _ = self;
        _ = allocator;
    }

    pub fn runRange(
        self: *GeometryWorkerPool,
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

        const chunks_num = @divFloor(domain_len + chunk_size - 1, chunk_size);
        for (0..chunks_num) |chunk_idx| {
            const range_start = chunk_idx * chunk_size;
            const range_end = @min(domain_len, range_start + chunk_size);
            group.async(
                self.io,
                runChunkTask,
                .{ ctx_ptr, job_func, chunk_idx, range_start, range_end },
            );
        }

        try group.await(self.io);
    }
};

fn runChunkTask(
    ctx_ptr: *anyopaque,
    job_func: RangeFn,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) std.Io.Cancelable!void {
    job_func(ctx_ptr, chunk_idx, range_start, range_end);
}
