const std = @import("std");
const assert = std.debug.assert;
const print = std.debug.print;

pub const InterpType = enum {
    linear,
    cubic,
    cubic_lut,
    cubic_lut_lerp,
    quintic,
    quintic_lut,
    quintic_lut_lerp,
};

pub fn Pixel(comptime T: type, comptime channels: usize) type {
    return struct {
        channels: [channels]T,
    };
}

pub fn Texture(comptime T: type, comptime channels: usize) type {
    return struct {
        const Self = @This();
        const P = Pixel(T, channels);

        pixels: []P,
        rows_num: usize,
        cols_num: usize,

        pub fn init(allocator: std.mem.Allocator, rows: usize, cols: usize) !Self {
            const pixels = try allocator.alloc(P, rows * cols);
            return Self{
                .pixels = pixels,
                .rows_num = rows,
                .cols_num = cols,
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn getPixel(self: Self, row: usize, col: usize) P {
            assert(row < self.rows_num);
            assert(col < self.cols_num);
            return self.pixels[row * self.cols_num + col];
        }

        pub fn setPixel(self: *Self, row: usize, col: usize, pixel: P) void {
            assert(row < self.rows_num);
            assert(col < self.cols_num);
            self.pixels[row * self.cols_num + col] = pixel;
        }

        pub fn saveCSV(self: *const Self,
                       io: std.Io, 
                       out_dir: std.Io.Dir, 
                       file_name: []const u8) !void {
                       
            const csv_file = try out_dir.createFile(io, file_name, .{});
            defer csv_file.close(io);

            var write_buf: [4096]u8 = undefined;
            var file_writer = csv_file.writer(io, &write_buf);
            const writer = &file_writer.interface;

            for (0..self.rows_num) |rr| {
                for (0..self.cols_num) |cc| {
                    const px = self.getPixel(rr, cc);
                    for (0..channels) |ch| {
                        try writer.print("{d}", .{px.channels[ch]});
                        if (ch < channels - 1) {
                            try writer.writeAll(":");
                        }
                    }
                    try writer.writeAll(",");
                }
                try writer.print("\n",.{});
            }
            try writer.flush();
        }
    };
}


fn cubicWeightHorner(x: f64) f64 {
    const ax = @abs(x);
    if (ax <= 1.0) {
        return ((1.5 * ax - 2.5) * ax + 0.0) * ax + 1.0;
    } else if (ax < 2.0) {
        return ((-0.5 * ax + 2.5) * ax - 4.0) * ax + 2.0;
    }
    return 0.0;
}

fn quinticWeight(x: f64) f64 {
    const ax = @abs(x);
    if (ax < 0.0001) return 1.0;
    if (ax >= 3.0) return 0.0;
    const pix = std.math.pi * x;
    const pix3 = pix / 3.0;
    return (std.math.sin(pix) / pix) * (std.math.sin(pix3) / pix3);
}

fn quinticWeightHorner(x: f64) f64 {
    const ax = @abs(x);
    if (ax >= 3.0) return 0.0;
    if (ax <= 1.0) {
        return (((( -0.416666 * ax + 1.0) * ax + 0.583333) * ax - 1.5) *
               ax - 0.083333) * ax + 1.0;
    } else if (ax <= 2.0) {
        const t = ax - 1.0;
        return (((( 0.25 * t - 0.833333) * t + 0.416666) * t + 0.5) *
               t - 0.083333) * t + 0.0;
    } else {
        const t = ax - 2.0;
        return (((( -0.008333 * t + 0.083333) * t - 0.041666) * t - 0.083333) *
               t + 0.041666) * t + 0.0;
    }
}


const LUT_SIZE = 1024;

const cubic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][4]f64 = undefined;
    for (0..LUT_SIZE) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(LUT_SIZE));
        for (0..4) |j| {
            const x = @as(f64, @floatFromInt(j)) - 1.0 - t;
            const ax = @abs(x);
            const a = -0.5;
            if (ax <= 1.0) {
                table[i][j] = (a + 2.0) * ax * ax * ax - (a + 3.0) * ax * ax + 1.0;
            } else if (ax < 2.0) {
                table[i][j] = a * ax * ax * ax - 5.0 * a * ax * ax + 
                              8.0 * a * ax - 4.0 * a;
            } else {
                table[i][j] = 0.0;
            }
        }
    }
    break :blk table;
};

const quintic_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [LUT_SIZE][6]f64 = undefined;
    for (0..LUT_SIZE) |i| {
        const t = @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(LUT_SIZE));
        for (0..6) |j| {
            table[i][j] = quinticWeight(@as(f64, @floatFromInt(j)) - 2.0 - t);
        }
    }
    break :blk table;
};

// --- Internal Helpers ---

fn getPx(comptime channels: usize, texture: anytype, x: isize, y: isize) [channels]f64 {
    const cols = @as(isize, @intCast(texture.cols_num));
    const rows = @as(isize, @intCast(texture.rows_num));
    const ix = @as(usize, @intCast(@max(0, @min(x, cols - 1))));
    const iy = @as(usize, @intCast(@max(0, @min(y, rows - 1))));

    const px = texture.getPixel(iy, ix);
    var res: [channels]f64 = undefined;
    inline for (0..channels) |ch| {
        const val = px.channels[ch];
        const T = @TypeOf(val);
        res[ch] = switch (@typeInfo(T)) {
            .int => @as(f64, @floatFromInt(val)),
            .float => @as(f64, @floatCast(val)),
            else => @compileError("Unsupported texture type"),
        };
    }
    return res;
}

fn sample2D(comptime channels: usize,
            comptime N: usize,
            comptime use_simd: bool,
            texture: anytype,
            x_i: isize,
            y_i: isize,
            wx: [N]f64,
            wy: [N]f64) [channels]f64 {

    const offset = @as(isize, @intCast(N)) / 2 - 1;
    _ = use_simd;
    var res: [channels]f64 = [_]f64{0.0} ** channels;
    var w_sum: f64 = 0.0;

    for (0..N) |jj| {
        for (0..N) |ii| {
            const w = wx[ii] * wy[jj];
            const px = getPx(channels, texture, x_i + @as(isize, @intCast(ii)) - offset,
                             y_i + @as(isize, @intCast(jj)) - offset);
            inline for (0..channels) |ch| {
                res[ch] += px[ch] * w;
            }
            w_sum += w;
        }
    }
    
    const inv_w_sum = if (@abs(w_sum) < 1e-9) 1.0 else 1.0 / w_sum;
    inline for (0..channels) |ch| {
        res[ch] *= inv_w_sum;
    }
    return res;
}

fn getLerpWeights(comptime N: usize, comptime table: [LUT_SIZE][N]f64, t: f64) [N]f64 {
    const scaled = t * (LUT_SIZE - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const f = scaled - @as(f64, @floatFromInt(idx));
    var res: [N]f64 = undefined;
    const w0 = table[idx];
    const w1 = table[@min(idx + 1, LUT_SIZE - 1)];
    inline for (0..N) |i| {
        res[i] = w0[i] * (1.0 - f) + w1[i] * f;
    }
    return res;
}


pub fn sampleGeneric(comptime channels: usize,
                     interp: InterpType,
                     texture: anytype,
                     u: f64,
                     v: f64) [channels]f64 {

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
                res[ch] = (1.0 - tx) * (1.0 - ty) * p00[ch] + tx * (1.0 - ty) * p10[ch] +
                          (1.0 - tx) * ty * p01[ch] + tx * ty * p11[ch];
            }
            return res;
        },
        .cubic => sample2D(channels, 4, true, texture, x_i, y_i,
            .{ cubicWeightHorner(tx+1), cubicWeightHorner(tx),
               cubicWeightHorner(tx-1), cubicWeightHorner(tx-2) },
            .{ cubicWeightHorner(ty+1), cubicWeightHorner(ty),
               cubicWeightHorner(ty-1), cubicWeightHorner(ty-2) }),
        .cubic_lut => sample2D(channels, 4, true, texture, x_i, y_i,
            cubic_lut[@as(usize, @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))))],
            cubic_lut[@as(usize, @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))))]),
        .cubic_lut_lerp => {
            const wx = getLerpWeights(4, cubic_lut, tx);
            const wy = getLerpWeights(4, cubic_lut, ty);
            return sample2D(channels, 4, true, texture, x_i, y_i, wx, wy);
        },
        .quintic => sample2D(channels, 6, true, texture, x_i, y_i,
            .{ quinticWeightHorner(tx+2), quinticWeightHorner(tx+1),
               quinticWeightHorner(tx), quinticWeightHorner(tx-1),
               quinticWeightHorner(tx-2), quinticWeightHorner(tx-3) },
            .{ quinticWeightHorner(ty+2), quinticWeightHorner(ty+1),
               quinticWeightHorner(ty), quinticWeightHorner(ty-1),
               quinticWeightHorner(ty-2), quinticWeightHorner(ty-3) }),
        .quintic_lut => {
            const idx_tx = @as(usize, 
                @intFromFloat(tx * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            const idx_ty = @as(usize, 
                @intFromFloat(ty * @as(f64, @floatFromInt(LUT_SIZE - 1))));
            return sample2D(channels, 6, true, texture, x_i, y_i, 
                quintic_lut[idx_tx], quintic_lut[idx_ty]);
        },

        .quintic_lut_lerp => {
            const wx = getLerpWeights(6, quintic_lut, tx);
            const wy = getLerpWeights(6, quintic_lut, ty);
            return sample2D(channels, 6, true, texture, x_i, y_i, wx, wy);
        },
    };
}

fn v_cubicWeightSIMD(v_x: @Vector(8, f64)) @Vector(8, f64) {
    const v_ax = @abs(v_x);
    const v_1: @Vector(8, f64) = @splat(1.0);
    const v_2: @Vector(8, f64) = @splat(2.0);
    
    const m1 = v_ax <= v_1;
    const m2 = (v_ax < v_2) & !m1;
    
    const v_w1 = ((@as(@Vector(8, f64), @splat(1.5)) * v_ax - @as(@Vector(8, f64), @splat(2.5))) * v_ax + @as(@Vector(8, f64), @splat(0.0))) * v_ax + v_1;
    const v_w2 = ((-@as(@Vector(8, f64), @splat(0.5)) * v_ax + @as(@Vector(8, f64), @splat(2.5))) * v_ax - @as(@Vector(8, f64), @splat(4.0))) * v_ax + v_2;
    
    var res = @select(f64, m1, v_w1, @as(@Vector(8, f64), @splat(0.0)));
    res = @select(f64, m2, v_w2, res);
    return res;
}

fn v_quinticWeightSIMD(v_x: @Vector(8, f64)) @Vector(8, f64) {
    const v_ax = @abs(v_x);
    const v_1: @Vector(8, f64) = @splat(1.0);
    const v_2: @Vector(8, f64) = @splat(2.0);
    const v_3: @Vector(8, f64) = @splat(3.0);
    
    const m1 = v_ax <= v_1;
    const m2 = (v_ax <= v_2) & !m1;
    const m3 = (v_ax < v_3) & !m1 & !m2;
    
    const v_w1 = ((((-@as(@Vector(8, f64), @splat(0.416666)) * v_ax + v_1) * v_ax + @as(@Vector(8, f64), @splat(0.583333))) * v_ax - @as(@Vector(8, f64), @splat(1.5))) * v_ax - @as(@Vector(8, f64), @splat(0.083333))) * v_ax + v_1;
    
    const t2 = v_ax - v_1;
    const v_w2 = ((((@as(@Vector(8, f64), @splat(0.25)) * t2 - @as(@Vector(8, f64), @splat(0.833333))) * t2 + @as(@Vector(8, f64), @splat(0.416666))) * t2 + @as(@Vector(8, f64), @splat(0.5))) * t2 - @as(@Vector(8, f64), @splat(0.083333))) * t2;
    
    const t3 = v_ax - v_2;
    const v_w3 = ((((-@as(@Vector(8, f64), @splat(0.008333)) * t3 + @as(@Vector(8, f64), @splat(0.083333))) * t3 - @as(@Vector(8, f64), @splat(0.041666))) * t3 - @as(@Vector(8, f64), @splat(0.083333))) * t3 + @as(@Vector(8, f64), @splat(0.041666))) * t3;

    var res = @select(f64, m1, v_w1, @as(@Vector(8, f64), @splat(0.0)));
    res = @select(f64, m2, v_w2, res);
    res = @select(f64, m3, v_w3, res);
    return res;
}

pub fn sampleGenericSIMD(comptime channels: usize,
                         interp: InterpType,
                         texture: anytype,
                         v_u: @Vector(8, f64),
                         v_v: @Vector(8, f64)) [channels]@Vector(8, f64) {

    const cols_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.cols_num)) - 1));
    const rows_minus_1_f = @as(f64, @floatFromInt(@as(isize, @intCast(texture.rows_num)) - 1));
    
    const v_xf = v_u * @as(@Vector(8, f64), @splat(cols_minus_1_f));
    const v_yf = v_v * @as(@Vector(8, f64), @splat(rows_minus_1_f));
    
    var v_xi: [8]isize = undefined;
    var v_yi: [8]isize = undefined;
    const xf_arr: [8]f64 = v_xf;
    const yf_arr: [8]f64 = v_yf;

    for (0..8) |ii| {
        v_xi[ii] = @as(isize, @intFromFloat(@floor(xf_arr[ii])));
        v_yi[ii] = @as(isize, @intFromFloat(@floor(yf_arr[ii])));
    }
    
    const v_tx = v_xf - @as(@Vector(8, f64), @floatFromInt(@as(@Vector(8, isize), v_xi)));
    const v_ty = v_yf - @as(@Vector(8, f64), @floatFromInt(@as(@Vector(8, isize), v_yi)));

    return switch (interp) {
        .linear => {
            var p00_arr: [channels][8]f64 = undefined;
            var p10_arr: [channels][8]f64 = undefined;
            var p01_arr: [channels][8]f64 = undefined;
            var p11_arr: [channels][8]f64 = undefined;
            
            for (0..8) |ii| {
                const p00 = getPx(channels, texture, v_xi[ii], v_yi[ii]);
                const p10 = getPx(channels, texture, v_xi[ii] + 1, v_yi[ii]);
                const p01 = getPx(channels, texture, v_xi[ii], v_yi[ii] + 1);
                const p11 = getPx(channels, texture, v_xi[ii] + 1, v_yi[ii] + 1);
                inline for (0..channels) |ch| {
                    p00_arr[ch][ii] = p00[ch];
                    p10_arr[ch][ii] = p10[ch];
                    p01_arr[ch][ii] = p01[ch];
                    p11_arr[ch][ii] = p11[ch];
                }
            }
            
            var res: [channels]@Vector(8, f64) = undefined;
            const v_1: @Vector(8, f64) = @splat(1.0);
            inline for (0..channels) |ch| {
                const v_p00: @Vector(8, f64) = p00_arr[ch];
                const v_p10: @Vector(8, f64) = p10_arr[ch];
                const v_p01: @Vector(8, f64) = p01_arr[ch];
                const v_p11: @Vector(8, f64) = p11_arr[ch];

                res[ch] = (v_1 - v_tx) * (v_1 - v_ty) * v_p00 + 
                          v_tx * (v_1 - v_ty) * v_p10 +
                          (v_1 - v_tx) * v_ty * v_p01 + 
                          v_tx * v_ty * v_p11;
            }
            return res;
        },
        .cubic, .cubic_lut, .cubic_lut_lerp => {
            const K = 4;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;
            
            var v_wx: [K]@Vector(8, f64) = undefined;
            var v_wy: [K]@Vector(8, f64) = undefined;
            
            const tx_arr: [8]f64 = v_tx;
            const ty_arr: [8]f64 = v_ty;

            switch (interp) {
                .cubic => {
                    v_wx[0] = v_cubicWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[1] = v_cubicWeightSIMD(v_tx);
                    v_wx[2] = v_cubicWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[3] = v_cubicWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(2.0)));
                    
                    v_wy[0] = v_cubicWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[1] = v_cubicWeightSIMD(v_ty);
                    v_wy[2] = v_cubicWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[3] = v_cubicWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(2.0)));
                },
                .cubic_lut => {
                    var wx_arr: [4][8]f64 = undefined;
                    var wy_arr: [4][8]f64 = undefined;
                    for (0..8) |ii| {
                        const ix = @as(usize, @intFromFloat(tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        const iy = @as(usize, @intFromFloat(ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        inline for (0..4) |kk| {
                            wx_arr[kk][ii] = cubic_lut[ix][kk];
                            wy_arr[kk][ii] = cubic_lut[iy][kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                .cubic_lut_lerp => {
                    var wx_arr: [4][8]f64 = undefined;
                    var wy_arr: [4][8]f64 = undefined;
                    for (0..8) |ii| {
                        const wx = getLerpWeights(4, cubic_lut, tx_arr[ii]);
                        const wy = getLerpWeights(4, cubic_lut, ty_arr[ii]);
                        inline for (0..4) |kk| {
                            wx_arr[kk][ii] = wx[kk];
                            wy_arr[kk][ii] = wy[kk];
                        }
                    }
                    inline for (0..4) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                else => unreachable,
            }

            var v_res: [channels]@Vector(8, f64) = [_]@Vector(8, f64){ @splat(0.0) } ** channels;
            var v_w_sum: @Vector(8, f64) = @splat(0.0);
            
            // Fully unrolled plane shading implementation
            // Pre-calculate weight planes to avoid redundant math in channels loop
            var v_w_planes: [K * K]@Vector(8, f64) = undefined;
            inline for (0..K) |jj| {
                const v_wy_val = v_wy[jj];
                inline for (0..K) |ii| {
                    const v_w = v_wx[ii] * v_wy_val;
                    v_w_planes[jj * K + ii] = v_w;
                    v_w_sum += v_w;
                }
            }

            inline for (0..K) |jj| {
                inline for (0..K) |ii| {
                    const v_w = v_w_planes[jj * K + ii];
                    var p_arr: [channels][8]f64 = undefined;
                    for (0..8) |ln| {
                        const px = getPx(channels, texture, 
                                         v_xi[ln] + @as(isize, @intCast(ii)) - offset,
                                         v_yi[ln] + @as(isize, @intCast(jj)) - offset);
                        inline for (0..channels) |ch| {
                            p_arr[ch][ln] = px[ch];
                        }
                    }
                    inline for (0..channels) |ch| {
                        const v_px: @Vector(8, f64) = p_arr[ch];
                        v_res[ch] += v_px * v_w;
                    }
                }
            }
            
            const v_1: @Vector(8, f64) = @splat(1.0);
            const v_inv_w_sum = @select(f64, @abs(v_w_sum) < @as(@Vector(8, f64), @splat(1e-9)), v_1, v_1 / v_w_sum);
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
        .quintic, .quintic_lut, .quintic_lut_lerp => {
            const K = 6;
            const offset = @divTrunc(@as(isize, @intCast(K)), 2) - 1;
            
            var v_wx: [K]@Vector(8, f64) = undefined;
            var v_wy: [K]@Vector(8, f64) = undefined;
            
            const tx_arr: [8]f64 = v_tx;
            const ty_arr: [8]f64 = v_ty;

            switch (interp) {
                .quintic => {
                    v_wx[0] = v_quinticWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(2.0)));
                    v_wx[1] = v_quinticWeightSIMD(v_tx + @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[2] = v_quinticWeightSIMD(v_tx);
                    v_wx[3] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(1.0)));
                    v_wx[4] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(2.0)));
                    v_wx[5] = v_quinticWeightSIMD(v_tx - @as(@Vector(8, f64), @splat(3.0)));
                    
                    v_wy[0] = v_quinticWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(2.0)));
                    v_wy[1] = v_quinticWeightSIMD(v_ty + @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[2] = v_quinticWeightSIMD(v_ty);
                    v_wy[3] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(1.0)));
                    v_wy[4] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(2.0)));
                    v_wy[5] = v_quinticWeightSIMD(v_ty - @as(@Vector(8, f64), @splat(3.0)));
                },
                .quintic_lut => {
                    var wx_arr: [6][8]f64 = undefined;
                    var wy_arr: [6][8]f64 = undefined;
                    for (0..8) |ii| {
                        const ix = @as(usize, @intFromFloat(tx_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        const iy = @as(usize, @intFromFloat(ty_arr[ii] * @as(f64, @floatFromInt(LUT_SIZE - 1))));
                        inline for (0..6) |kk| {
                            wx_arr[kk][ii] = quintic_lut[ix][kk];
                            wy_arr[kk][ii] = quintic_lut[iy][kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                .quintic_lut_lerp => {
                    var wx_arr: [6][8]f64 = undefined;
                    var wy_arr: [6][8]f64 = undefined;
                    for (0..8) |ii| {
                        const wx = getLerpWeights(6, quintic_lut, tx_arr[ii]);
                        const wy = getLerpWeights(6, quintic_lut, ty_arr[ii]);
                        inline for (0..6) |kk| {
                            wx_arr[kk][ii] = wx[kk];
                            wy_arr[kk][ii] = wy[kk];
                        }
                    }
                    inline for (0..6) |kk| {
                        v_wx[kk] = wx_arr[kk];
                        v_wy[kk] = wy_arr[kk];
                    }
                },
                else => unreachable,
            }

            var v_res: [channels]@Vector(8, f64) = [_]@Vector(8, f64){ @splat(0.0) } ** channels;
            var v_w_sum: @Vector(8, f64) = @splat(0.0);
            
            // Fully unrolled plane shading implementation
            inline for (0..6) |jj| {
                const v_wy_val = v_wy[jj];
                inline for (0..6) |ii| {
                    const v_wx_val = v_wx[ii];
                    const v_w = v_wx_val * v_wy_val;
                    v_w_sum += v_w;
                    
                    var p_arr: [channels][8]f64 = undefined;
                    for (0..8) |ln| {
                        const px = getPx(channels, texture, 
                                         v_xi[ln] + @as(isize, @intCast(ii)) - offset,
                                         v_yi[ln] + @as(isize, @intCast(jj)) - offset);
                        inline for (0..channels) |ch| {
                            p_arr[ch][ln] = px[ch];
                        }
                    }
                    inline for (0..channels) |ch| {
                        const v_px: @Vector(8, f64) = p_arr[ch];
                        v_res[ch] += v_px * v_w;
                    }
                }
            }
            
            const v_1: @Vector(8, f64) = @splat(1.0);
            const v_inv_w_sum = @select(f64, @abs(v_w_sum) < @as(@Vector(8, f64), @splat(1e-9)), v_1, v_1 / v_w_sum);
            inline for (0..channels) |ch| {
                v_res[ch] *= v_inv_w_sum;
            }
            return v_res;
        },
    };
}

pub fn sampleGreyscale(comptime interp: InterpType,
                       texture: anytype,
                       u: f64,
                       v: f64) f64 {
    return sampleGeneric(1, interp, texture, u, v)[0];
}
