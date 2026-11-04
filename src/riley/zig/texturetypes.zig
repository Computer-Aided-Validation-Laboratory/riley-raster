// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;

pub const TexSamp = enum {
    nearest,
    linear,
    cubic_catmull_rom,
    cubic_mitchell_netravali,
    lanczos3,
    cubic_bspline,
    quintic_bspline,
    lanczos2,
};

pub const TexSampMode = enum {
    direct,
    lut,
    lut_lerp,
};

pub const TexSampConfig = struct {
    sample: TexSamp,
    mode: TexSampMode = .direct,

    pub fn isValid(self: TexSampConfig) bool {
        return switch (self.sample) {
            .nearest, .linear => self.mode == .direct,
            else => true,
        };
    }

    pub fn sanitise(self: TexSampConfig) TexSampConfig {
        return switch (self.sample) {
            .nearest, .linear => .{ .sample = self.sample, .mode = .direct },
            else => self,
        };
    }
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn TexDataFix(comptime T: type, comptime C: usize) type {
    if (C == 0) @compileError("Use TexDataDyn for runtime channel counts");
    return texDataType(T, C);
}

pub fn TexDataDyn(comptime T: type) type {
    return texDataType(T, null);
}

fn texDataType(comptime T: type, comptime C: ?usize) type {
    return struct {
        array: NDArray(T),
        rows_num: usize,
        cols_num: usize,

        const Self = @This();

        pub const init = if (C == null) initDynamic else initFixed;

        fn initFixed(allocator: std.mem.Allocator, rows: usize, cols: usize) !Self {
            const dims = &[_]usize{ C orelse unreachable, rows, cols };
            const array = try NDArray(T).initFlat(allocator, dims);
            return .{ .array = array, .rows_num = rows, .cols_num = cols };
        }

        fn initDynamic(allocator: std.mem.Allocator, channels: usize, rows: usize, cols: usize) !Self {
            const array = try NDArray(T).initFlat(allocator, &.{ channels, rows, cols });
            return .{ .array = array, .rows_num = rows, .cols_num = cols };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.array.slice);
            self.array.deinit(allocator);
        }

        pub fn setVal(self: *Self, ch: usize, row: usize, col: usize, val: T) void {
            const tex_flat_idx = self.array.subBase2(ch, row) + col;
            self.array.setFlat(tex_flat_idx, val);
        }

        pub fn getVal(self: *const Self, ch: usize, row: usize, col: usize) T {
            const tex_flat_idx = self.array.subBase2(ch, row) + col;
            return self.array.getFlat(tex_flat_idx);
        }
    };
}
