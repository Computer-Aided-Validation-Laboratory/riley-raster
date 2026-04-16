const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const tol = cfg.tolerance;
const lut_size = cfg.interp_lut_size;
const NDArray = @import("ndarray.zig").NDArray;
const csvio = @import("csvio.zig");

// --------------------------------------------------------------------------
// Strategy Map:
//
// PIPELINE ENTRY POINTS (Dispatched by Shader/Kernel):
// │
// ├── PATH 1: sampleScalar (Purely Scalar)
// │   "Used when .simd = .off or as fallback for complex elements (quad4ibi)"
// │   ├── getPx()           (Scalar Load)
// │   ├── sampleLinear()    (Scalar Linear)
// │   └── sampleConv()      (Scalar Convolution)
// │
// ├── PATH 2: sampleWide (Wide SIMD - Parallel over Pixels)
// │   "Each lane is a unique pixel; processes N pixels simultaneously"
// │   ├── getPxWide()       (Wide Load: N pixels)
// │   ├── sampleLinearWide()(Wide Linear: N pixels)
// │   └── sampleConvWide()  (Wide Convolution: N pixels)
// │
// └── PATH 3: sampleLanes (Lane SIMD - Serial over Pixels, SIMD over Taps)
//     "Processes N lanes serially; math inside each lane uses SIMD for taps"
//     └── sampleOneLane()   (Helper: Process 1 lane)
//         ├── getPx()       (Scalar Load: 1 pixel)
//         ├── sampleLinearOneLane() (Scalar Linear: 1 pixel)
//         └── sampleConvOneLane()   (SIMD-Tap Convolution: 1 pixel)
// --------------------------------------------------------------------------

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

pub fn Texture(comptime CH: usize) type {
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
                &[_]usize{ CH, rows, cols },
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
                CH,
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
        return ((((-(1.0 / 12.0) * r + (1.0 / 4.0)) * r + 0.0) * r  - (1.0 / 2.0)) * r 
               + 0.0) * r + (11.0 / 20.0);
    } else if (r <= 2.0) {
        const t = r - 1.0;
        return (((((1.0 / 24.0) * t - (1.0 / 6.0)) * t + (1.0 / 6.0)) * t 
               + (1.0 / 6.0)) * t - (5.0 / 12.0)) * t + (13.0 / 60.0);
    } else {
        const u = r - 2.0;
        return (((((-(1.0 / 120.0) * u + (1.0 / 24.0)) * u - (1.0 / 12.0)) * u +
            (1.0 / 12.0)) * u - (1.0 / 24.0)) * u + (1.0 / 120.0));
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
    comptime CH: usize,
    texture: anytype,
    x: isize,
    y: isize,
) [CH]f64 {
    const tex_cols = @as(isize, @intCast(texture.cols_num));
    const tex_rows = @as(isize, @intCast(texture.rows_num));
    // Clamp to the edges of the tex
    const tex_x_i = @as(usize, @intCast(@max(0, @min(x, tex_cols - 1))));
    const tex_y_i = @as(usize, @intCast(@max(0, @min(y, tex_rows - 1))));

    var samp_res: [CH]f64 = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = texture.getVal(ch, tex_y_i, tex_x_i);
    }
    return samp_res;
}

pub fn sampleLinear(
    comptime CH: usize,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    const p00 = getPx(CH, texture, tex_x_i, tex_y_i);
    const p10 = getPx(CH, texture, tex_x_i + 1, tex_y_i);
    const p01 = getPx(CH, texture, tex_x_i, tex_y_i + 1);
    const p11 = getPx(CH, texture, tex_x_i + 1, tex_y_i + 1);
    var samp_res: [CH]f64 = undefined;
    inline for (0..CH) |ch| {
        samp_res[ch] = (1.0 - tex_x_frac) * (1.0 - tex_y_frac) * p00[ch] +
            tex_x_frac * (1.0 - tex_y_frac) * p10[ch] +
            (1.0 - tex_x_frac) * tex_y_frac * p01[ch] +
            tex_x_frac * tex_y_frac * p11[ch];
    }
    return samp_res;
}

pub fn sampleConv(
    comptime CH: usize,
    comptime TAP: usize,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    samp_coeff_x: [TAP]f64,
    samp_coeff_y: [TAP]f64,
) [CH]f64 {
    const tap_offset = @as(isize, @intCast(TAP)) / 2 - 1;
    var samp_res: [CH]f64 = [_]f64{0.0} ** CH;
    var samp_coeff_sum: f64 = 0.0;

    for (0..TAP) |jj| {
        for (0..TAP) |ii| {
            const tap_samp_coeff = samp_coeff_x[ii] * samp_coeff_y[jj];
            const px = getPx(
                CH,
                texture,
                tex_x_i + @as(isize, @intCast(ii)) - tap_offset,
                tex_y_i + @as(isize, @intCast(jj)) - tap_offset,
            );
            inline for (0..CH) |ch| {
                samp_res[ch] += px[ch] * tap_samp_coeff;
            }
            samp_coeff_sum += tap_samp_coeff;
        }
    }

    const inv_samp_coeff_sum = if (@abs(samp_coeff_sum) < tol.texture.samp_coeff_sum)
        1.0
    else
        1.0 / samp_coeff_sum;

    inline for (0..CH) |ch| {
        samp_res[ch] *= inv_samp_coeff_sum;
    }
    return samp_res;
}

pub fn getLerpSampCoeffs(
    comptime TAP: usize,
    comptime table: [lut_size][TAP]f64,
    t: f64,
) [TAP]f64 {
    const scaled = t * (lut_size - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const frac = scaled - @as(f64, @floatFromInt(idx));
    var lerp_res: [TAP]f64 = undefined;

    const lut0 = table[idx];
    const lut1 = table[@min(idx + 1, lut_size - 1)];

    inline for (0..TAP) |ii| {
        lerp_res[ii] = lut0[ii] * (1.0 - frac) + lut1[ii] * frac;
    }
    return lerp_res;
}

pub fn getLerpSampCoeffsRuntime(
    comptime TAP: usize,
    table: [lut_size][TAP]f64,
    t: f64, // Between 0.0 and 1.0
) [TAP]f64 {
    const scaled = t * (lut_size - 1);
    const idx = @as(usize, @intFromFloat(@floor(scaled)));
    const frac = scaled - @as(f64, @floatFromInt(idx));

    var lerp_res: [TAP]f64 = undefined;
    const lut0 = table[idx];
    const lut1 = table[@min(idx + 1, lut_size - 1)];

    inline for (0..TAP) |ii| {
        lerp_res[ii] = lut0[ii] * (1.0 - frac) + lut1[ii] * frac;
    }

    return lerp_res;
}

fn sampleTex4Tap(
    comptime CH: usize,
    comptime sample: TextureSample,
    comptime mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    const TAP = 4;
    const coeff_fun = switch (sample) {
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
        .direct => blk: {
            const coeffs_x = .{
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
            };
            const coeffs_y = .{
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
            };
            break :blk sampleConv(CH, TAP, texture, tex_x_i, tex_y_i, coeffs_x, coeffs_y);
        },
        .lut => blk: {
            const lut_size_f = @as(f64, @floatFromInt(lut_size - 1));
            const idx_x = @as(usize, @intFromFloat(tex_x_frac * lut_size_f));
            const idx_y = @as(usize, @intFromFloat(tex_y_frac * lut_size_f));
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                lut[idx_x],
                lut[idx_y],
            );
        },
        .lut_lerp => blk: {
            const coeffs_x = getLerpSampCoeffs(TAP, lut, tex_x_frac);
            const coeffs_y = getLerpSampCoeffs(TAP, lut, tex_y_frac);
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                coeffs_x,
                coeffs_y,
            );
        },
    };
}

fn sampleTex4TapRuntime(
    comptime CH: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    const TAP = 4;
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
        .direct => blk: {
            const coeffs_x = .{
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
            };
            const coeffs_y = .{
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
            };
            break :blk sampleConv(CH, TAP, texture, tex_x_i, tex_y_i, coeffs_x, coeffs_y);
        },
        .lut => blk: {
            const lut_size_f = @as(f64, @floatFromInt(lut_size - 1));
            const idx_x = @as(usize, @intFromFloat(tex_x_frac * lut_size_f));
            const idx_y = @as(usize, @intFromFloat(tex_y_frac * lut_size_f));
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                lut[idx_x],
                lut[idx_y],
            );
        },
        .lut_lerp => {
            const coeffs_x = getLerpSampCoeffsRuntime(TAP, lut, tex_x_frac);
            const coeffs_y = getLerpSampCoeffsRuntime(TAP, lut, tex_y_frac);
            return sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                coeffs_x,
                coeffs_y,
            );
        },
    };
}

fn sampleTex6Tap(
    comptime CH: usize,
    comptime sample: TextureSample,
    comptime mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    const TAP = 6;
    const coeff_fun = switch (sample) {
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
        .direct => blk: {
            const coeffs_x = .{
                coeff_fun(tex_x_frac + 2),
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
                coeff_fun(tex_x_frac - 3),
            };
            const coeffs_y = .{
                coeff_fun(tex_y_frac + 2),
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
                coeff_fun(tex_y_frac - 3),
            };
            break :blk sampleConv(CH, TAP, texture, tex_x_i, tex_y_i, coeffs_x, coeffs_y);
        },
        .lut => blk: {
            const lut_size_f = @as(f64, @floatFromInt(lut_size - 1));
            const idx_x = @as(usize, @intFromFloat(tex_x_frac * lut_size_f));
            const idx_y = @as(usize, @intFromFloat(tex_y_frac * lut_size_f));
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                lut[idx_x],
                lut[idx_y],
            );
        },
        .lut_lerp => blk: {
            const coeffs_x = getLerpSampCoeffs(TAP, lut, tex_x_frac);
            const coeffs_y = getLerpSampCoeffs(TAP, lut, tex_y_frac);
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                coeffs_x,
                coeffs_y,
            );
        },
    };
}

fn sampleTex6TapRuntime(
    comptime CH: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    const TAP = 6;
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
        .direct => blk: {
            const coeffs_x = .{
                coeff_fun(tex_x_frac + 2),
                coeff_fun(tex_x_frac + 1),
                coeff_fun(tex_x_frac),
                coeff_fun(tex_x_frac - 1),
                coeff_fun(tex_x_frac - 2),
                coeff_fun(tex_x_frac - 3),
            };
            const coeffs_y = .{
                coeff_fun(tex_y_frac + 2),
                coeff_fun(tex_y_frac + 1),
                coeff_fun(tex_y_frac),
                coeff_fun(tex_y_frac - 1),
                coeff_fun(tex_y_frac - 2),
                coeff_fun(tex_y_frac - 3),
            };
            break :blk sampleConv(CH, TAP, texture, tex_x_i, tex_y_i, coeffs_x, coeffs_y);
        },
        .lut => blk: {
            const lut_size_f = @as(f64, @floatFromInt(lut_size - 1));
            const idx_x = @as(usize, @intFromFloat(tex_x_frac * lut_size_f));
            const idx_y = @as(usize, @intFromFloat(tex_y_frac * lut_size_f));
            break :blk sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                lut[idx_x],
                lut[idx_y],
            );
        },
        .lut_lerp => {
            const coeffs_x = getLerpSampCoeffsRuntime(TAP, lut, tex_x_frac);
            const coeffs_y = getLerpSampCoeffsRuntime(TAP, lut, tex_y_frac);
            return sampleConv(
                CH,
                TAP,
                texture,
                tex_x_i,
                tex_y_i,
                coeffs_x,
                coeffs_y,
            );
        },
    };
}

fn sampleTex4TapDispatchMode(
    comptime CH: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => sampleTex4TapRuntime(
            CH,
            sample,
            mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .runtime_comptime, .comptime_comptime => switch (mode) {
            inline else => |m| sampleTex4Tap(
                CH,
                sample,
                m,
                texture,
                tex_x_i,
                tex_y_i,
                tex_x_frac,
                tex_y_frac,
            ),
        },
    };
}

fn sampleTex6TapDispatchMode(
    comptime CH: usize,
    comptime sample: TextureSample,
    mode: TextureSampleMode,
    texture: anytype,
    tex_x_i: isize,
    tex_y_i: isize,
    tex_x_frac: f64,
    tex_y_frac: f64,
) [CH]f64 {
    return switch (cfg.texture_dispatch_policy) {
        .runtime_runtime => sampleTex6TapRuntime(
            CH,
            sample,
            mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .runtime_comptime, .comptime_comptime => switch (mode) {
            inline else => |m| sampleTex6Tap(
                CH,
                sample,
                m,
                texture,
                tex_x_i,
                tex_y_i,
                tex_x_frac,
                tex_y_frac,
            ),
        },
    };
}

pub fn sampleScalar(
    comptime CH: usize,
    comptime config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
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
            CH,
            texture,
            @as(isize, @intFromFloat(@round(tex_x_f))),
            @as(isize, @intFromFloat(@round(tex_y_f))),
        ),
        .linear => sampleLinear(CH, texture, tex_x_i, tex_y_i, tex_x_frac, tex_y_frac),
        .cubic_catmull_rom => sampleTex4Tap(
            CH,
            .cubic_catmull_rom,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_mitchell_netravali => sampleTex4Tap(
            CH,
            .cubic_mitchell_netravali,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_bspline => sampleTex4Tap(
            CH,
            .cubic_bspline,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .lanczos3 => sampleTex6Tap(
            CH,
            .lanczos3,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .quintic_bspline => sampleTex6Tap(
            CH,
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

pub fn sampleScalarRuntime(
    comptime CH: usize,
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) [CH]f64 {
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
            CH,
            texture,
            @as(isize, @intFromFloat(@round(tex_x_f))),
            @as(isize, @intFromFloat(@round(tex_y_f))),
        ),
        .linear => sampleLinear(CH, texture, tex_x_i, tex_y_i, tex_x_frac, tex_y_frac),
        .cubic_catmull_rom => sampleTex4TapDispatchMode(
            CH,
            .cubic_catmull_rom,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_mitchell_netravali => sampleTex4TapDispatchMode(
            CH,
            .cubic_mitchell_netravali,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .cubic_bspline => sampleTex4TapDispatchMode(
            CH,
            .cubic_bspline,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .lanczos3 => sampleTex6TapDispatchMode(
            CH,
            .lanczos3,
            config.mode,
            texture,
            tex_x_i,
            tex_y_i,
            tex_x_frac,
            tex_y_frac,
        ),
        .quintic_bspline => sampleTex6TapDispatchMode(
            CH,
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
    return sampleScalar(1, config, texture, u, v)[0];
}

pub fn sampleGreyscaleRuntime(
    config: TextureSampleConfig,
    texture: anytype,
    u: f64,
    v: f64,
) f64 {
    return sampleScalarRuntime(1, config, texture, u, v)[0];
}
