const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const tol = buildconfig.config.tolerance;
const lut_size = buildconfig.config.interp_lut_size;
const NDArray = @import("ndarray.zig").NDArray;
const csvio = @import("csvio.zig");

pub const TextureSample = enum {
    nearest,
    linear,
    cubic_catmull_rom,
    cubic_mitchell_netravali,
    lanczos3,
    cubic_bspline,
    quintic_bspline,
};

pub const TextureSampleMode = enum {
    direct,
    lut,
    lut_lerp,
};

pub const TextureSampleConfig = struct {
    sample: TextureSample,
    mode: TextureSampleMode = .direct,

    pub fn isValid(self: TextureSampleConfig) bool {
        return switch (self.sample) {
            .nearest, .linear => self.mode == .direct,
            else => true,
        };
    }
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

pub fn cubicCoeffCatmullRom(x: f64) f64 {
    const abs_x = @abs(x);
    if (abs_x <= 1.0) {
        return ((1.5 * abs_x - 2.5) * abs_x + 0.0) * abs_x + 1.0;
    } else if (abs_x < 2.0) {
        return ((-0.5 * abs_x + 2.5) * abs_x - 4.0) * abs_x + 2.0;
    }
    return 0.0;
}

pub fn cubicCoeffMitchellNetravali(x: f64) f64 {
    const r = @abs(x);
    const B = 1.0 / 3.0;
    const C = 1.0 / 3.0;
    if (r < 1.0) {
        return ((12.0 - 9.0 * B - 6.0 * C) * r * r * r +
            (-18.0 + 12.0 * B + 6.0 * C) * r * r +
            (6.0 - 2.0 * B)) / 6.0;
    } else if (r < 2.0) {
        return ((-B - 6.0 * C) * r * r * r +
            (6.0 * B + 30.0 * C) * r * r +
            (-12.0 * B - 48.0 * C) * r +
            (8.0 * B + 24.0 * C)) / 6.0;
    }
    return 0.0;
}

pub fn cubicBSplineCoeff(x: f64) f64 {
    const r = @abs(x);
    if (r < 1.0) {
        return (3.0 * r * r * r - 6.0 * r * r + 4.0) / 6.0;
    } else if (r < 2.0) {
        const t = 2.0 - r;
        return t * t * t / 6.0;
    }
    return 0.0;
}

pub fn lanczos3Coeff(x: f64) f64 {
    const abs_x = @abs(x);
    if (abs_x < tol.texture.lancsoz_centre_snap) return 1.0;
    if (abs_x >= 3.0) return 0.0;
    const pi_x = std.math.pi * x;
    const pi_x_3 = pi_x / 3.0;
    return (std.math.sin(pi_x) / pi_x) * (std.math.sin(pi_x_3) / pi_x_3);
}

pub fn quinticBSplineCoeff(x: f64) f64 {
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

pub const catmull_rom_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][4]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) / @as(f64, @floatFromInt(lut_size));
        for (0..4) |jj| {
            const xx = @as(f64, @floatFromInt(jj)) - 1.0 - tt;
            table[ii][jj] = cubicCoeffCatmullRom(xx);
        }
    }
    break :blk table;
};

pub const mitchell_netravali_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][4]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) / @as(f64, @floatFromInt(lut_size));
        for (0..4) |jj| {
            const xx = @as(f64, @floatFromInt(jj)) - 1.0 - tt;
            table[ii][jj] = cubicCoeffMitchellNetravali(xx);
        }
    }
    break :blk table;
};

pub const cubic_bspline_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][4]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) / @as(f64, @floatFromInt(lut_size));
        for (0..4) |jj| {
            const xx = @as(f64, @floatFromInt(jj)) - 1.0 - tt;
            table[ii][jj] = cubicBSplineCoeff(xx);
        }
    }
    break :blk table;
};

pub const lanczos3_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][6]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) /
            @as(f64, @floatFromInt(lut_size));
        for (0..6) |jj| {
            table[ii][jj] = lanczos3Coeff(
                @as(f64, @floatFromInt(jj)) - 2.0 - tt,
            );
        }
    }
    break :blk table;
};

pub const quintic_bspline_lut = blk: {
    @setEvalBranchQuota(100000);
    var table: [lut_size][6]f64 = undefined;
    for (0..lut_size) |ii| {
        const tt = @as(f64, @floatFromInt(ii)) /
            @as(f64, @floatFromInt(lut_size));
        for (0..6) |jj| {
            table[ii][jj] = quinticBSplineCoeff(
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
    // Clamp to texture edges so we don't try and access anything that doesn't exist
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
    tex_x_i: isize,
    tex_y_i: isize,
    samp_coeff_x: [N]f64,
    samp_coeff_y: [N]f64,
) [channels]f64 {
    const offset = @as(isize, @intCast(N)) / 2 - 1;
    var res: [channels]f64 = [_]f64{0.0} ** channels;
    var samp_coeff_sum: f64 = 0.0;

    for (0..N) |jj| {
        for (0..N) |ii| {
            const tap_samp_coeff = samp_coeff_x[ii] * samp_coeff_y[jj];
            const px = getPx(
                channels,
                texture,
                tex_x_i + @as(isize, @intCast(ii)) - offset,
                tex_y_i + @as(isize, @intCast(jj)) - offset,
            );
            inline for (0..channels) |ch| {
                res[ch] += px[ch] * tap_samp_coeff;
            }
            samp_coeff_sum += tap_samp_coeff;
        }
    }

    const inv_samp_coeff_sum = if (@abs(samp_coeff_sum) < tol.texture.samp_coeff_sum)
        1.0
    else
        1.0 / samp_coeff_sum;

    inline for (0..channels) |ch| {
        res[ch] *= inv_samp_coeff_sum;
    }
    return res;
}

pub fn getLerpSampCoeffs(
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
    comptime config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [channels]f64 {
    std.debug.assert(config.isValid());
    const cols_minus_1 = @as(isize, @intCast(texture.cols_num)) - 1;
    const rows_minus_1 = @as(isize, @intCast(texture.rows_num)) - 1;
    const tex_x_f = u * @as(f64, @floatFromInt(cols_minus_1));
    const tex_y_f = v * @as(f64, @floatFromInt(rows_minus_1));
    const tex_x_i = @as(isize, @intFromFloat(@floor(tex_x_f)));
    const tex_y_i = @as(isize, @intFromFloat(@floor(tex_y_f)));
    const tex_x_frac = tex_x_f - @as(f64, @floatFromInt(tex_x_i));
    const tex_y_frac = tex_y_f - @as(f64, @floatFromInt(tex_y_i));

    return switch (config.sample) {
        .nearest => getPx(
            channels,
            texture,
            @as(isize, @intFromFloat(@round(tex_x_f))),
            @as(isize, @intFromFloat(@round(tex_y_f))),
        ),
        .linear => {
            const p00 = getPx(channels, texture, tex_x_i, tex_y_i);
            const p10 = getPx(channels, texture, tex_x_i + 1, tex_y_i);
            const p01 = getPx(channels, texture, tex_x_i, tex_y_i + 1);
            const p11 = getPx(channels, texture, tex_x_i + 1, tex_y_i + 1);
            var res: [channels]f64 = undefined;
            inline for (0..channels) |ch| {
                res[ch] = (1.0 - tex_x_frac) * (1.0 - tex_y_frac) * p00[ch] +
                    tex_x_frac * (1.0 - tex_y_frac) * p10[ch] +
                    (1.0 - tex_x_frac) * tex_y_frac * p01[ch] +
                    tex_x_frac * tex_y_frac * p11[ch];
            }
            return res;
        },
        .cubic_catmull_rom, .cubic_mitchell_netravali, .cubic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .cubic_catmull_rom => cubicCoeffCatmullRom,
                .cubic_mitchell_netravali => cubicCoeffMitchellNetravali,
                .cubic_bspline => cubicBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .cubic_catmull_rom => catmull_rom_lut,
                .cubic_mitchell_netravali => mitchell_netravali_lut,
                .cubic_bspline => cubic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2D(
                    channels,
                    4,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                    },
                    .{
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                    },
                ),
                .lut => sample2D(
                    channels,
                    4,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    lut[@as(usize, @intFromFloat(tex_x_frac * @as(f64, @floatFromInt(lut_size - 1))))],
                    lut[@as(usize, @intFromFloat(tex_y_frac * @as(f64, @floatFromInt(lut_size - 1))))],
                ),
                .lut_lerp => {
                    const samp_coeff_x = getLerpSampCoeffs(4, lut, tex_x_frac);
                    const samp_coeff_y = getLerpSampCoeffs(4, lut, tex_y_frac);
                    return sample2D(channels, 4, texture, tex_x_i, tex_y_i, samp_coeff_x, samp_coeff_y);
                },
            };
        },
        .lanczos3, .quintic_bspline => {
            const coeff_fun: *const fn (f64) f64 = switch (config.sample) {
                .lanczos3 => lanczos3Coeff,
                .quintic_bspline => quinticBSplineCoeff,
                else => unreachable,
            };
            const lut = switch (config.sample) {
                .lanczos3 => lanczos3_lut,
                .quintic_bspline => quintic_bspline_lut,
                else => unreachable,
            };
            return switch (config.mode) {
                .direct => sample2D(
                    channels,
                    6,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    .{
                        coeff_fun(tex_x_frac + 2),
                        coeff_fun(tex_x_frac + 1),
                        coeff_fun(tex_x_frac),
                        coeff_fun(tex_x_frac - 1),
                        coeff_fun(tex_x_frac - 2),
                        coeff_fun(tex_x_frac - 3),
                    },
                    .{
                        coeff_fun(tex_y_frac + 2),
                        coeff_fun(tex_y_frac + 1),
                        coeff_fun(tex_y_frac),
                        coeff_fun(tex_y_frac - 1),
                        coeff_fun(tex_y_frac - 2),
                        coeff_fun(tex_y_frac - 3),
                    },
                ),
                .lut => sample2D(
                    channels,
                    6,
                    texture,
                    tex_x_i,
                    tex_y_i,
                    lut[@as(usize, @intFromFloat(tex_x_frac * @as(f64, @floatFromInt(lut_size - 1))))],
                    lut[@as(usize, @intFromFloat(tex_y_frac * @as(f64, @floatFromInt(lut_size - 1))))],
                ),
                .lut_lerp => {
                    const samp_coeff_x = getLerpSampCoeffs(6, lut, tex_x_frac);
                    const samp_coeff_y = getLerpSampCoeffs(6, lut, tex_y_frac);
                    return sample2D(channels, 6, texture, tex_x_i, tex_y_i, samp_coeff_x, samp_coeff_y);
                },
            };
        },
    };
}

fn sampleGenericCubicRuntimeMode(
    comptime channels: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [channels]f64 {
    const coeff_fun: *const fn (f64) f64 = switch (sample) {
        .cubic_catmull_rom => cubicCoeffCatmullRom,
        .cubic_mitchell_netravali => cubicCoeffMitchellNetravali,
        .cubic_bspline => cubicBSplineCoeff,
        else => unreachable,
    };
    const lut = switch (sample) {
        .cubic_catmull_rom => catmull_rom_lut,
        .cubic_mitchell_netravali => mitchell_netravali_lut,
        .cubic_bspline => cubic_bspline_lut,
        else => unreachable,
    };

    return switch (mode) {
        .direct => sample2D(
            channels,
            4,
            texture,
            tex_x_i,
            tex_y_i,
            .{
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
            },
            .{
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
            },
        ),
        .lut => sample2D(
            channels,
            4,
            texture,
            tex_x_i,
            tex_y_i,
            lut[
                @as(
                    usize,
                    @intFromFloat(tex_x_frac * @as(f64, @floatFromInt(lut_size - 1))),
                )
            ],
            lut[
                @as(
                    usize,
                    @intFromFloat(tex_y_frac * @as(f64, @floatFromInt(lut_size - 1))),
                )
            ],
        ),
        .lut_lerp => {
            const samp_coeff_x = getLerpSampCoeffs(4, lut, tex_x_frac);
            const samp_coeff_y = getLerpSampCoeffs(4, lut, tex_y_frac);
            return sample2D(channels, 4, texture, tex_x_i, tex_y_i, samp_coeff_x, samp_coeff_y);
        },
    };
}

fn sampleGenericWideRuntimeMode(
    comptime channels: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [channels]f64 {
    const coeff_fun: *const fn (f64) f64 = switch (sample) {
        .lanczos3 => lanczos3Coeff,
        .quintic_bspline => quinticBSplineCoeff,
        else => unreachable,
    };
    const lut = switch (sample) {
        .lanczos3 => lanczos3_lut,
        .quintic_bspline => quintic_bspline_lut,
        else => unreachable,
    };

    return switch (mode) {
        .direct => sample2D(
            channels,
            6,
            texture,
            tex_x_i,
            tex_y_i,
            .{
                coeff_fun(tex_x_frac + 2),
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
                coeff_fun(tex_x_frac - 3),
            },
            .{
                coeff_fun(tex_y_frac + 2),
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
                coeff_fun(tex_y_frac - 3),
            },
        ),
        .lut => sample2D(
            channels,
            6,
            texture,
            tex_x_i,
            tex_y_i,
            lut[
                @as(
                    usize,
                    @intFromFloat(tex_x_frac * @as(f64, @floatFromInt(lut_size - 1))),
                )
            ],
            lut[
                @as(
                    usize,
                    @intFromFloat(tex_y_frac * @as(f64, @floatFromInt(lut_size - 1))),
                )
            ],
        ),
        .lut_lerp => {
            const samp_coeff_x = getLerpSampCoeffs(6, lut, tex_x_frac);
            const samp_coeff_y = getLerpSampCoeffs(6, lut, tex_y_frac);
            return sample2D(channels, 6, texture, tex_x_i, tex_y_i, samp_coeff_x, samp_coeff_y);
        },
    };
}

fn sampleGenericCubicModeDispatch(
    comptime channels: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [channels]f64 {
    switch (buildconfig.config.texture_sample_mode_dispatch) {
        .run_time => {
            return sampleGenericCubicRuntimeMode(
                channels,
                sample,
                mode,
                texture,
                tex_x_i,
                tex_y_i,
                tex_x_frac,
                tex_y_frac,
            );
        },
        .comp_time => {
            inline for (.{ .direct, .lut, .lut_lerp }) |mode_type| {
                if (mode == mode_type) {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample,
                        .mode = mode_type,
                    };
                    return sampleGeneric(
                        channels,
                        comptime_config,
                        texture,
                        (tex_x_frac + @as(f64, @floatFromInt(tex_x_i))) /
                            @as(f64, @floatFromInt(
                                @as(isize, @intCast(texture.cols_num)) - 1,
                            )),
                        (tex_y_frac + @as(f64, @floatFromInt(tex_y_i))) /
                            @as(f64, @floatFromInt(
                                @as(isize, @intCast(texture.rows_num)) - 1,
                            )),
                    );
                }
            }
        },
    }
    unreachable;
}

fn sampleGenericWideModeDispatch(
    comptime channels: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [channels]f64 {
    switch (buildconfig.config.texture_sample_mode_dispatch) {
        .run_time => {
            return sampleGenericWideRuntimeMode(
                channels,
                sample,
                mode,
                texture,
                tex_x_i,
                tex_y_i,
                tex_x_frac,
                tex_y_frac,
            );
        },
        .comp_time => {
            inline for (.{ .direct, .lut, .lut_lerp }) |mode_type| {
                if (mode == mode_type) {
                    const comptime_config = TextureSampleConfig{
                        .sample = sample,
                        .mode = mode_type,
                    };
                    return sampleGeneric(
                        channels,
                        comptime_config,
                        texture,
                        (tex_x_frac + @as(f64, @floatFromInt(tex_x_i))) /
                            @as(f64, @floatFromInt(
                                @as(isize, @intCast(texture.cols_num)) - 1,
                            )),
                        (tex_y_frac + @as(f64, @floatFromInt(tex_y_i))) /
                            @as(f64, @floatFromInt(
                                @as(isize, @intCast(texture.rows_num)) - 1,
                            )),
                    );
                }
            }
        },
    }
    unreachable;
}

pub fn sampleGenericRuntime(
    comptime channels: usize,
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [channels]f64 {
    std.debug.assert(config.isValid());
    const cols_minus_1 = @as(isize, @intCast(texture.cols_num)) - 1;
    const rows_minus_1 = @as(isize, @intCast(texture.rows_num)) - 1;
    const tex_x_f = u * @as(f64, @floatFromInt(cols_minus_1));
    const tex_y_f = v * @as(f64, @floatFromInt(rows_minus_1));
    const tex_x_i = @as(isize, @intFromFloat(@floor(tex_x_f)));
    const tex_y_i = @as(isize, @intFromFloat(@floor(tex_y_f)));
    const tex_x_frac = tex_x_f - @as(f64, @floatFromInt(tex_x_i));
    const tex_y_frac = tex_y_f - @as(f64, @floatFromInt(tex_y_i));

    return switch (config.sample) {
        .nearest => getPx(
            channels,
            texture,
            @as(isize, @intFromFloat(@round(tex_x_f))),
            @as(isize, @intFromFloat(@round(tex_y_f))),
        ),
        .linear => {
            const p00 = getPx(channels, texture, tex_x_i, tex_y_i);
            const p10 = getPx(channels, texture, tex_x_i + 1, tex_y_i);
            const p01 = getPx(channels, texture, tex_x_i, tex_y_i + 1);
            const p11 = getPx(channels, texture, tex_x_i + 1, tex_y_i + 1);
            var res: [channels]f64 = undefined;
            inline for (0..channels) |ch| {
                res[ch] = (1.0 - tex_x_frac) * (1.0 - tex_y_frac) * p00[ch] +
                    tex_x_frac * (1.0 - tex_y_frac) * p10[ch] +
                    (1.0 - tex_x_frac) * tex_y_frac * p01[ch] +
                    tex_x_frac * tex_y_frac * p11[ch];
            }
            return res;
        },
        .cubic_catmull_rom => sampleGenericCubicModeDispatch(
            channels,
            .cubic_catmull_rom,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_mitchell_netravali => sampleGenericCubicModeDispatch(
            channels,
            .cubic_mitchell_netravali,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_bspline => sampleGenericCubicModeDispatch(
            channels,
            .cubic_bspline,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .lanczos3 => sampleGenericWideModeDispatch(
            channels,
            .lanczos3,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .quintic_bspline => sampleGenericWideModeDispatch(
            channels,
            .quintic_bspline,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
    };
}

pub fn sampleGreyscale(
    comptime config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) f64 {
    return sampleGeneric(1, config, texture, u, v)[0];
}

pub fn sampleGreyscaleRuntime(
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) f64 {
    return sampleGenericRuntime(1, config, texture, u, v)[0];
}
