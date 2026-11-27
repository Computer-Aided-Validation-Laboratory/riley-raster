// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const ndarray = @import("ndarray.zig");
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

// NOTE: this has to be in a separate file from meshtypes to avoid a circular dependency
// as shadertypes need access as well.
/// Nodal values indexed `[frame][node][component]`. The consumer defines
/// component meanings and ordering.
/// The field owns its data and array metadata; release both with `deinit`.
pub const Field = struct {
    /// Array metadata and view over `array_mem`.
    array: ndarray.NDArray(F),
    /// Owned, contiguous element storage. Components of one node are adjacent.
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
        const arr = try ndarray.NDArray(F).init(outer_alloc, mem_array, mem_dims[0..]);

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
