const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const tol = buildconfig.config.tolerance;
const lut_size = buildconfig.config.interp_lut_size;
const NDArray = @import("ndarray.zig").NDArray;
const csvio = @import("csvio.zig");

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
            const SaveCtx = struct {
                fn getVal(
                    ctx: *const Self,
                    row: usize,
                    col: usize,
                    ch: usize,
                ) f64 {
                    return ctx.getVal(ch, row, col);
                }
            };

            try csvio.savePackedGridCSV(
                io,
                out_dir,
                file_name,
                self.rows_num,
                self.cols_num,
                channels,
                self,
                SaveCtx.getVal,
            );
        }
    };
}

pub fn cubicWeightPoly(x: f64) f64 {
    const abs_x = @abs(x);
    if (abs_x <= 1.0) {
        return ((1.5 * abs_x - 2.5) * abs_x + 0.0) * abs_x + 1.0;
    } else if (abs_x < 2.0) {
        return ((-0.5 * abs_x + 2.5) * abs_x - 4.0) * abs_x + 2.0;
    }
    return 0.0;
}

pub fn quinticWeightSinc(x: f64) f64 {
    const abs_x = @abs(x);
    if (abs_x < tol.texture.quintic_centre_snap) return 1.0;
    if (abs_x >= 3.0) return 0.0;
    const pi_x = std.math.pi * x;
    const pi_x_3 = pi_x / 3.0;
    return (std.math.sin(pi_x) / pi_x) * (std.math.sin(pi_x_3) / pi_x_3);
}

// pub fn quinticWeightPoly(x: f64) f64 {
//     const abs_x = @abs(x);
//     if (abs_x >= 3.0) return 0.0;
//     if (abs_x <= 1.0) {
//         return ((((-0.416666 * abs_x + 1.0) * abs_x + 0.583333) * abs_x - 1.5) *
//             abs_x - 0.083333) * abs_x + 1.0;
//     } else if (abs_x <= 2.0) {
//         const t = abs_x - 1.0;
//         return ((((0.25 * t - 0.833333) * t + 0.416666) * t + 0.5) *
//             t - 0.083333) * t + 0.0;
//     } else {
//         const t = abs_x - 2.0;
//         return ((((-0.008333 * t + 0.083333) * t - 0.041666) * t - 0.083333) *
//             t + 0.041666) * t + 0.0;
//     }
// }

pub fn quinticWeightPoly(x: f64) f64 {
    const r = @abs(x);

    if (r >= 3.0) return 0.0;

    if (r <= 1.0) {
        return ((((-(1.0 / 12.0) * r + (1.0 / 4.0)) * r + 0.0) * r
            - (1.0 / 2.0)) * r + 0.0) * r + (11.0 / 20.0);
    } else if (r <= 2.0) {
        const t = r - 1.0;
        return (((((1.0 / 24.0) * t - (1.0 / 6.0)) * t + (1.0 / 6.0)) * t
            + (1.0 / 6.0)) * t - (5.0 / 12.0)) * t + (13.0 / 60.0);
    } else {
        const u = r - 2.0;
        return (((((-(1.0 / 120.0) * u + (1.0 / 24.0)) * u - (1.0 / 12.0)) * u
            + (1.0 / 12.0)) * u - (1.0 / 24.0)) * u + (1.0 / 120.0));
    }
}

pub const cubic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][4]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) / @as(f64, @floatFromInt(lut_size));
        for (0..4) |jj| {
            const xx = @as(f64, @floatFromInt(jj)) - 1.0 - tt;
            const abs_x = @abs(xx);
            const a = -0.5;
            if (abs_x <= 1.0) {
                table[ii][jj] = (a + 2.0) * abs_x * abs_x * abs_x -
                    (a + 3.0) * abs_x * abs_x + 1.0;
            } else if (abs_x < 2.0) {
                table[ii][jj] = a * abs_x * abs_x * abs_x - 5.0 * a * abs_x * abs_x +
                    8.0 * a * abs_x - 4.0 * a;
            } else {
                table[ii][jj] = 0.0;
            }
        }
    }
    break :blk table;
};

pub const quintic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][6]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) /
            @as(f64, @floatFromInt(lut_size));
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
    comptime table: [lut_size][N]f64,
    t: f64,
) [N]f64 {
    const scaled = t * (lut_size - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const frac = scaled - @as(f64, @floatFromInt(idx));
    var res: [N]f64 = undefined;
    const w0 = table[idx];
    const w1 = table[@min(idx + 1, lut_size - 1)];
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
                    tx * @as(f64, @floatFromInt(lut_size - 1)),
                ))
            ],
            cubic_lut[
                @as(usize, @intFromFloat(
                    ty * @as(f64, @floatFromInt(lut_size - 1)),
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
                tx * @as(f64, @floatFromInt(lut_size - 1)),
            ));
            const idx_ty = @as(usize, @intFromFloat(
                ty * @as(f64, @floatFromInt(lut_size - 1)),
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
