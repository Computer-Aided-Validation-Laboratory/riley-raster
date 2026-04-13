const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const tol = buildconfig.config.tolerance;
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

pub fn cubicWeightPoly(x: f64) f64 {
    const ax = @abs(x);
    if (ax <= 1.0) {
        return ((1.5 * ax - 2.5) * ax + 0.0) * ax + 1.0;
    } else if (ax < 2.0) {
        return ((-0.5 * ax + 2.5) * ax - 4.0) * ax + 2.0;
    }
    return 0.0;
}

pub fn quinticWeightSinc(x: f64) f64 {
    const ax = @abs(x);
    if (ax < tol.texture.quintic_centre_snap) return 1.0;
    if (ax >= 3.0) return 0.0;
    const pix = std.math.pi * x;
    const pix3 = pix / 3.0;
    return (std.math.sin(pix) / pix) * (std.math.sin(pix3) / pix3);
}

pub fn quinticWeightPoly(x: f64) f64 {
    const ax = @abs(x);
    if (ax >= 3.0) return 0.0;
    if (ax <= 1.0) {
        return ((((-0.416666 * ax + 1.0) * ax + 0.583333) * ax - 1.5) *
            ax - 0.083333) * ax + 1.0;
    } else if (ax <= 2.0) {
        const t = ax - 1.0;
        return ((((0.25 * t - 0.833333) * t + 0.416666) * t + 0.5) *
            t - 0.083333) * t + 0.0;
    } else {
        const t = ax - 2.0;
        return ((((-0.008333 * t + 0.083333) * t - 0.041666) * t - 0.083333) *
            t + 0.041666) * t + 0.0;
    }
}

pub const LUT_SIZE = 1024;

pub const cubic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][4]f64 = undefined;
    for (0..LUT_SIZE) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) /
            @as(f64, @floatFromInt(LUT_SIZE));
        for (0..4) |jj| {
            const xx = @as(f64, @floatFromInt(jj)) - 1.0 - tt;
            const ax = @abs(xx);
            const a = -0.5;
            if (ax <= 1.0) {
                table[ii][jj] = (a + 2.0) * ax * ax * ax -
                    (a + 3.0) * ax * ax + 1.0;
            } else if (ax < 2.0) {
                table[ii][jj] = a * ax * ax * ax - 5.0 * a * ax * ax +
                    8.0 * a * ax - 4.0 * a;
            } else {
                table[ii][jj] = 0.0;
            }
        }
    }
    break :blk table;
};

pub const quintic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][6]f64 = undefined;
    for (0..LUT_SIZE) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) /
            @as(f64, @floatFromInt(LUT_SIZE));
        for (0..6) |jj| {
            table[ii][jj] = quinticWeightSinc(
                @as(f64, @floatFromInt(jj)) - 2.0 - tt,
            );
        }
    }
    break :blk table;
};

pub fn getPx(
    comptime channels: usize,
    texture: anytype,
    x: isize,
    y: isize,
) [channels]f64 {
    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));
    const ix = @as(usize, @intCast(@max(0, @min(x, cols - 1))));
    const iy = @as(usize, @intCast(@max(0, @min(y, rows - 1))));

    var res: [channels]f64 = undefined;
    inline for (0..channels) |ch| {
        res[ch] = texture.getVal(ch, iy, ix);
    }
    return res;
}

pub fn sample2D(
    comptime channels: usize,
    comptime N: usize,
    texture: anytype,
    x_i: isize,
    y_i: isize,
    wx: [N]f64,
    wy: [N]f64,
) [channels]f64 {
    const offset = @as(isize, @intCast(N)) / 2 - 1;
    var res: [channels]f64 = [_]f64{0.0} ** channels;
    var w_sum: f64 = 0.0;

    for (0..N) |jj| {
        for (0..N) |ii| {
            const weight = wx[ii] * wy[jj];
            const px = getPx(
                channels,
                texture,
                x_i + @as(isize, @intCast(ii)) - offset,
                y_i + @as(isize, @intCast(jj)) - offset,
            );
            inline for (0..channels) |ch| {
                res[ch] += px[ch] * weight;
            }
            w_sum += weight;
        }
    }

    const inv_w_sum = if (@abs(w_sum) < tol.texture.weight_sum)
        1.0
    else
        1.0 / w_sum;
    inline for (0..channels) |ch| {
        res[ch] *= inv_w_sum;
    }
    return res;
}

pub fn getLerpWeights(
    comptime N: usize,
    comptime table: [LUT_SIZE][N]f64,
    t: f64,
) [N]f64 {
    const scaled = t * (LUT_SIZE - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const frac = scaled - @as(f64, @floatFromInt(idx));
    var res: [N]f64 = undefined;
    const w0 = table[idx];
    const w1 = table[@min(idx + 1, LUT_SIZE - 1)];
    inline for (0..N) |ii| {
        res[ii] = w0[ii] * (1.0 - frac) + w1[ii] * frac;
    }
    return res;
}

pub fn sampleGeneric(
    comptime channels: usize,
    interp: InterpType,
    texture: anytype,
    u: f64,
    v: f64,
) [channels]f64 {
    const cols_minus_1 = @as(isize, @intCast(texture.cols_num)) - 1;
    const rows_minus_1 = @as(isize, @intCast(texture.rows_num)) - 1;
    const x_f = u * @as(f64, @floatFromInt(cols_minus_1));
    const y_f = v * @as(f64, @floatFromInt(rows_minus_1));
    const x_i = @as(isize, @intFromFloat(@floor(x_f)));
    const y_i = @as(isize, @intFromFloat(@floor(y_f)));
    const tx = x_f - @as(f64, @floatFromInt(x_i));
    const ty = y_f - @as(f64, @floatFromInt(y_i));

    return switch (interp) {
        .linear => {
            const p00 = getPx(channels, texture, x_i, y_i);
            const p10 = getPx(channels, texture, x_i + 1, y_i);
            const p01 = getPx(channels, texture, x_i, y_i + 1);
            const p11 = getPx(channels, texture, x_i + 1, y_i + 1);
            var res: [channels]f64 = undefined;
            inline for (0..channels) |ch| {
                res[ch] = (1.0 - tx) * (1.0 - ty) * p00[ch] +
                    tx * (1.0 - ty) * p10[ch] +
                    (1.0 - tx) * ty * p01[ch] +
                    tx * ty * p11[ch];
            }
            return res;
        },
        .cubic => sample2D(
            channels,
            4,
            texture,
            x_i,
            y_i,
            .{
                cubicWeightPoly(tx + 1),
                cubicWeightPoly(tx),
                cubicWeightPoly(tx - 1),
                cubicWeightPoly(tx - 2),
            },
            .{
                cubicWeightPoly(ty + 1),
                cubicWeightPoly(ty),
                cubicWeightPoly(ty - 1),
                cubicWeightPoly(ty - 2),
            },
        ),
        .cubic_lut => sample2D(
            channels,
            4,
            texture,
            x_i,
            y_i,
            cubic_lut[
                @as(usize, @intFromFloat(
                    tx * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                ))
            ],
            cubic_lut[
                @as(usize, @intFromFloat(
                    ty * @as(f64, @floatFromInt(LUT_SIZE - 1)),
                ))
            ],
        ),
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2D(channels, 4, texture, x_i, y_i, wx, wy);
        },
        .quintic => sample2D(
            channels,
            6,
            texture,
            x_i,
            y_i,
            .{
                quinticWeightPoly(tx + 2),
                quinticWeightPoly(tx + 1),
                quinticWeightPoly(tx),
                quinticWeightPoly(tx - 1),
                quinticWeightPoly(tx - 2),
                quinticWeightPoly(tx - 3),
            },
            .{
                quinticWeightPoly(ty + 2),
                quinticWeightPoly(ty + 1),
                quinticWeightPoly(ty),
                quinticWeightPoly(ty - 1),
                quinticWeightPoly(ty - 2),
                quinticWeightPoly(ty - 3),
            },
        ),
        .quintic_lut => {
            const idx_tx = @as(usize, @intFromFloat(
                tx * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            const idx_ty = @as(usize, @intFromFloat(
                ty * @as(f64, @floatFromInt(LUT_SIZE - 1)),
            ));
            return sample2D(
                channels,
                6,
                texture,
                x_i,
                y_i,
                quintic_lut[idx_tx],
                quintic_lut[idx_ty],
            );
        },
        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2D(channels, 6, texture, x_i, y_i, wx, wy);
        },
    };
}

pub fn sampleGreyscale(
    comptime interp: InterpType,
    texture: anytype,
    u: f64,
    v: f64,
) f64 {
    return sampleGeneric(1, interp, texture, u, v)[0];
}
