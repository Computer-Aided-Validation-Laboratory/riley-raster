// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const NDArray = @import("ndarray.zig").NDArray;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const Field = struct {
    array: NDArray(F),
    array_mem: []F,

    const Self = @This();

    pub fn initAlloc(
        outer_alloc: std.mem.Allocator,
        time_n: usize,
        coord_n: usize,
        fields_n: u8,
    ) !Self {
        const mem_array = try outer_alloc.alloc(F, time_n * coord_n * fields_n);
        @memset(mem_array, 0.0);

        const mem_dims = [3]usize{ time_n, coord_n, @as(usize, fields_n) };
        const arr = try NDArray(F).init(outer_alloc, mem_array, mem_dims[0..]);

        return .{
            .array = arr,
            .array_mem = mem_array,
        };
    }

    pub inline fn getTimeN(self: *const Self) usize {
        return self.array.dims[0];
    }
    pub inline fn getCoordN(self: *const Self) usize {
        return self.array.dims[1];
    }
    pub inline fn getFieldsN(self: *const Self) u8 {
        std.debug.assert(self.array.dims[2] <= std.math.maxInt(u8));
        return @intCast(self.array.dims[2]);
    }

    pub fn deinit(self: *Self, outer_alloc: std.mem.Allocator) void {
        outer_alloc.free(self.array_mem);
        self.array.deinit(outer_alloc);
    }
};
