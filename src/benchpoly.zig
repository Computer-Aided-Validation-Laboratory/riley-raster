const std = @import("std");
const cm = @import("riley/zig/cameramodels.zig");
const bc = @import("riley/zig/buildconfig.zig");
const F = bc.F;
const VecSF = bc.VecSF;
const S = bc.SimdWidth;
const Op = enum { scalar_ford, scalar_jac, scalar_inv, simd_ford, simd_jac, simd_inv };

pub fn main(init: std.process.Init) !void {
    var coeffs = [_]F{0} ** 72;
    for (&coeffs, 0..) |*value, ii| {
        value.* = @as(F, @floatFromInt(ii % 5)) * 0.0002;
    }
    std.debug.print("precision={s}, width={d}, PolyMap={d}, DistortModel={d}\n", .{
        @typeName(F), S, @sizeOf(cm.PolyMap), @sizeOf(cm.DistortModel),
    });
    for ([_]u8{ 1, 3, 5, 7 }) |degree| {
        for ([_]cm.PolyMode{ .displacement, .coordinate }) |mode| {
            coeffs[2] = if (mode == .coordinate) 1.0004 else 0.0004;
            coeffs[5] = if (mode == .coordinate) 1 else 0;
            const poly = try cm.PolyMap.init(
                degree,
                mode,
                coeffs[0 .. 2 * cm.polyTermCount(degree)],
            );
            var xs: [128]VecSF = undefined;
            var ys: [128]VecSF = undefined;
            var observed_xs: [128]VecSF = undefined;
            var observed_ys: [128]VecSF = undefined;
            for (0..xs.len) |ii| {
                var x: [S]F = undefined;
                var y: [S]F = undefined;
                for (0..S) |lane| {
                    x[lane] = @as(F, @floatFromInt((ii * S + lane) % 101)) / 100 - 0.5;
                    y[lane] = @as(F, @floatFromInt((ii * S + lane) % 79)) / 100 - 0.4;
                }
                xs[ii] = x;
                ys[ii] = y;
                const observed = cm.PolyMapSIMD.ford(poly, xs[ii], ys[ii]);
                observed_xs[ii] = observed.x;
                observed_ys[ii] = observed.y;
            }
            for (std.enums.values(Op)) |op| {
                // Trial zero warms the code/data; report four measured trials.
                for (0..5) |trial| {
                    var checksum: F = 0;
                    const start = std.Io.Clock.Timestamp.now(init.io, .awake);
                    for (0..100_000) |ii| {
                        const index = ii % xs.len;
                        const x = xs[index];
                        const y = ys[index];
                        switch (op) {
                            .scalar_ford => {
                                const result = poly.ford(x[0], y[0]);
                                checksum += result.x + result.y;
                            },
                            .scalar_jac => {
                                const result = poly.fordWithJac(x[0], y[0]);
                                checksum += result.coords.x + result.coords.y +
                                    result.jac.get(0, 0) + result.jac.get(0, 1) +
                                    result.jac.get(1, 0) + result.jac.get(1, 1);
                            },
                            .scalar_inv => {
                                const result = try poly.inv(
                                    observed_xs[index][0],
                                    observed_ys[index][0],
                                );
                                checksum += result.x + result.y;
                            },
                            .simd_ford => {
                                const result = cm.PolyMapSIMD.ford(poly, x, y);
                                checksum += @reduce(.Add, result.x + result.y);
                            },
                            .simd_jac => {
                                const result = cm.PolyMapSIMD.fordWithJac(poly, x, y);
                                checksum += @reduce(.Add, result.coords.x + result.coords.y +
                                    result.jac.xx + result.jac.xy + result.jac.yx + result.jac.yy);
                            },
                            .simd_inv => {
                                const result = try cm.PolyMapSIMD.inv(
                                    poly,
                                    observed_xs[index],
                                    observed_ys[index],
                                    @splat(true),
                                );
                                checksum += @reduce(.Add, result.x + result.y);
                            },
                        }
                    }
                    const end = std.Io.Clock.Timestamp.now(init.io, .awake);
                    if (trial == 0) continue;
                    const ns: f64 = @floatFromInt(start.durationTo(end).raw.nanoseconds);
                    std.debug.print(
                        "degree={d},mode={s},op={s},trial={d},ns/batch={d:.2},checksum={e}\n",
                        .{ degree, @tagName(mode), @tagName(op), trial, ns / 100_000, checksum },
                    );
                }
            }
        }
    }
}
