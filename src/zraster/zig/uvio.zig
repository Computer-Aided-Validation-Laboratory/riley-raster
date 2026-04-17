// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const assert = std.debug.assert;
const NDArray = @import("ndarray.zig").NDArray;
const csvio = @import("csvio.zig");

pub const UVMap = struct {
    array: NDArray(f64),
    buffer: []f64,

    const Self = @This();

    pub fn init(outer_alloc: std.mem.Allocator, nodes_num: usize) !Self {
        const buffer = try outer_alloc.alloc(f64, nodes_num * 2);
        @memset(buffer, 0.0);

        const dims = [_]usize{ nodes_num, 2 }; // u, v

        const array = try NDArray(f64).init(outer_alloc, buffer, dims[0..]);

        return .{
            .array = array,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *Self, outer_alloc: std.mem.Allocator) void {
        self.array.deinit(outer_alloc);
        outer_alloc.free(self.buffer);
    }

    pub fn getU(self: *const Self, node_idx: usize) f64 {
        assert(node_idx < self.array.dims[0]);
        return self.array.get(&[_]usize{ node_idx, 0 });
    }

    pub fn getV(self: *const Self, node_idx: usize) f64 {
        assert(node_idx < self.array.dims[0]);
        return self.array.get(&[_]usize{ node_idx, 1 });
    }

    pub fn getUV(self: *const Self, node_idx: usize) []f64 {
        assert(node_idx < self.array.dims[0]);
        const start = node_idx * 2;
        return self.buffer[start .. start + 2];
    }

    pub fn setUV(self: *Self, node_idx: usize, u: f64, v: f64) void {
        assert(node_idx < self.array.dims[0]);
        self.array.set(&[_]usize{ node_idx, 0 }, u);
        self.array.set(&[_]usize{ node_idx, 1 }, v);
    }
};

pub fn loadUVs(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) !NDArray(f64) {
    const uv_arr = try csvio.loadScalarCsv2D(outer_alloc, io, path);

    if (uv_arr.dims.len != 2 or uv_arr.dims[1] != 2) {
        outer_alloc.free(uv_arr.slice);
        var tmp = uv_arr;
        tmp.deinit(outer_alloc);
        return error.InvalidCsvFormat;
    }

    return uv_arr;
}

pub fn loadUVMap(outer_alloc: std.mem.Allocator, io: std.Io, path: []const u8) !UVMap {
    const uv_arr = try loadUVs(outer_alloc, io, path);
    return UVMap{
        .array = uv_arr,
        .buffer = uv_arr.slice,
    };
}

const testing = std.testing;

test "Load UVMap from tri3_fullscreen/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri3_fullscreen/uvs.csv";
    var uv_map = try loadUVMap(allocator, io, path);
    defer uv_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 4), uv_map.array.dims[0]);

    // First row: 0.4, 0.4
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv_map.getU(0), 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv_map.getV(0), 1e-8);

    // Last row: 0.4, 0.6
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv_map.getU(3), 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.6), uv_map.getV(3), 1e-8);

    const uv = uv_map.getUV(0);
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv[0], 1e-8);
    try testing.expectApproxEqAbs(@as(f64, 0.4), uv[1], 1e-8);
}

test "Load UVMap from tri6_fullscreen/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri6_fullscreen/uvs.csv";
    var uv_map = try loadUVMap(allocator, io, path);
    defer uv_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 9), uv_map.array.dims[0]);
}

test "Load UVMap from tri3_single/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri3_single/uvs.csv";
    var uv_map = try loadUVMap(allocator, io, path);
    defer uv_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 3), uv_map.array.dims[0]);
}

test "Load UVMap from tri6_single/uvs.csv" {
    const allocator = testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const path = "data-simple/tri6_single/uvs.csv";
    var uv_map = try loadUVMap(allocator, io, path);
    defer uv_map.deinit(allocator);

    try testing.expectEqual(@as(usize, 6), uv_map.array.dims[0]);
}
