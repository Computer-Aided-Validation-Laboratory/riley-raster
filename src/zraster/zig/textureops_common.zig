const std = @import("std");
const NDArray = @import("ndarray.zig").NDArray;

pub const InterpType = enum {
    linear,
    cubic,
    cubic_lut,
    cubic_lut_lerp,
    quintic,
    quintic_lut,
    quintic_lut_lerp,
};

pub fn Texture(comptime channels: usize) type {
    return struct {
        array: NDArray(f64),
        rows_num: usize,
        cols_num: usize,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            rows: usize,
            cols: usize,
        ) !Self {
            const array = try NDArray(f64).initFlat(
                allocator,
                &[_]usize{ channels, rows, cols },
            );
            return .{
                .array = array,
                .rows_num = rows,
                .cols_num = cols,
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.array.slice);
            self.array.deinit(allocator);
        }

        pub fn setVal(
            self: *Self,
            ch: usize,
            row: usize,
            col: usize,
            val: f64,
        ) void {
            self.array.set(&[_]usize{ ch, row, col }, val);
        }

        pub fn getVal(
            self: *const Self,
            ch: usize,
            row: usize,
            col: usize,
        ) f64 {
            return self.array.get(&[_]usize{ ch, row, col });
        }

        pub fn saveCSV(
            self: *const Self,
            io: std.Io,
            out_dir: std.Io.Dir,
            file_name: []const u8,
        ) !void {
            const csv_file = try out_dir.createFile(io, file_name, .{});
            defer csv_file.close(io);

            var writer = csv_file.writerStreaming(&.{});
            defer writer.deinit();

            for (0..self.rows_num) |rr| {
                for (0..self.cols_num) |cc| {
                    for (0..channels) |ch| {
                        try writer.print("{d}", .{self.getVal(ch, rr, cc)});
                        if (ch < channels - 1) {
                            try writer.writeAll(":");
                        }
                    }
                    try writer.writeAll(",");
                }
                try writer.print("\n", .{});
            }
            try writer.flush();
        }
    };
}

// pub fn getLerpWeights(
//     comptime N: usize,
//     lut: [1024][N]f64,
//     t: f64,
// ) [N]f64 {
//     const scaled = t * @as(f64, @floatFromInt(lut.len - 1));
//     const idx0 = @min(lut.len - 2, @as(usize, @intFromFloat(@floor(scaled))));
//     const frac = scaled - @as(f64, @floatFromInt(idx0));
//     var weights: [N]f64 = undefined;
//     inline for (0..N) |nn| {
//         weights[nn] = lut[idx0][nn] * (1.0 - frac) + lut[idx0 + 1][nn] * frac;
//     }
//     return weights;
// }
