// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cameramodels = @import("cameramodels.zig");
const cfg = buildconfig.config;
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;
const VecSU = buildconfig.VecSU;
const common = @import("camera_common.zig");

pub const CameraPrepared = common.CameraPreparedType(@This());

fn calcActiveMask(lane_count: usize) VecSB {
    const v_lane_idx: VecSU = std.simd.iota(usize, S);
    return v_lane_idx < @as(VecSU, @splat(lane_count));
}

fn storeIdealPairs(
    ideal_pixel_centers: []f64,
    scratch_base: usize,
    lane_count: usize,
    v_x: VecSF,
    v_y: VecSF,
) void {
    const x_arr: [S]f64 = v_x;
    const y_arr: [S]f64 = v_y;
    for (0..lane_count) |ll| {
        common.storeIdealPairScratch(
            ideal_pixel_centers,
            scratch_base + ll,
            x_arr[ll],
            y_arr[ll],
        );
    }
}

fn calcObservedXVector(
    global_subx_start: usize,
    step: f64,
    off: f64,
) VecSF {
    const v_start: VecSF = @splat(@as(f64, @floatFromInt(global_subx_start)));
    const v_lane: VecSF = @floatFromInt(std.simd.iota(usize, S));
    return (v_start + v_lane) * @as(VecSF, @splat(step)) +
        @as(VecSF, @splat(off));
}

pub fn calcPinholeRasterPointSIMD(
    camera: *const CameraPrepared,
    v_observed_x_px: VecSF,
    v_observed_y_px: VecSF,
    v_lane_active: VecSB,
) !struct { x: VecSF, y: VecSF } {
    if (common.isNoDistortion(camera.distortion)) {
        return .{ .x = v_observed_x_px, .y = v_observed_y_px };
    }

    const focal_px = camera.calcFocalPx();
    const offsets = camera.calcRasterOffsets();
    const v_x_dist = (v_observed_x_px - @as(VecSF, @splat(offsets.x_off))) /
        @as(VecSF, @splat(focal_px.fx));
    const v_y_dist = (v_observed_y_px - @as(VecSF, @splat(offsets.y_off))) /
        @as(VecSF, @splat(focal_px.fy));

    const solved = switch (camera.distortion) {
        .brown_conrady => |bc| try cameramodels.inverseDistortionSIMD(
            @TypeOf(bc),
            bc,
            v_x_dist,
            v_y_dist,
            v_lane_active,
        ),
        .brown_conrady_ext => |bc_ext| try cameramodels.inverseDistortionSIMD(
            @TypeOf(bc_ext),
            bc_ext,
            v_x_dist,
            v_y_dist,
            v_lane_active,
        ),
        .none => unreachable,
    };
    return .{
        .x = solved.x * @as(VecSF, @splat(focal_px.fx)) +
            @as(VecSF, @splat(offsets.x_off)),
        .y = solved.y * @as(VecSF, @splat(focal_px.fy)) +
            @as(VecSF, @splat(offsets.y_off)),
    };
}

pub fn fillTileIdealCentersPerTile(
    camera: *const CameraPrepared,
    scratch_x_px_min: usize,
    scratch_x_px_max: usize,
    scratch_y_px_min: usize,
    scratch_y_px_max: usize,
    subpx_tile_size: usize,
    ideal_pixel_centers: []f64,
) !void {
    const sub_samp: usize = @intCast(camera.sub_sample);
    const start_x = scratch_x_px_min * sub_samp;
    const start_y = scratch_y_px_min * sub_samp;
    const tile_w = (scratch_x_px_max - scratch_x_px_min) * sub_samp;
    const tile_h = (scratch_y_px_max - scratch_y_px_min) * sub_samp;

    const step = 1.0 / @as(f64, @floatFromInt(camera.sub_sample));
    const off = 0.5 / @as(f64, @floatFromInt(camera.sub_sample));

    for (0..tile_h) |jj| {
        const global_y = start_y + jj;
        const observed_y = @as(f64, @floatFromInt(global_y)) * step + off;
        const v_observed_y: VecSF = @splat(observed_y);
        const scratch_row_off = jj * subpx_tile_size;

        var ii: usize = 0;
        while (ii < tile_w) : (ii += S) {
            const lane_count = @min(S, tile_w - ii);
            const v_active = calcActiveMask(lane_count);
            const global_x_start = start_x + ii;
            const v_observed_x = calcObservedXVector(
                global_x_start,
                step,
                off,
            );

            if (common.isNoDistortion(camera.distortion)) {
                storeIdealPairs(
                    ideal_pixel_centers,
                    scratch_row_off + ii,
                    lane_count,
                    v_observed_x,
                    v_observed_y,
                );
            } else {
                const ideal = try calcPinholeRasterPointSIMD(
                    camera,
                    v_observed_x,
                    v_observed_y,
                    v_active,
                );
                storeIdealPairs(
                    ideal_pixel_centers,
                    scratch_row_off + ii,
                    lane_count,
                    ideal.x,
                    ideal.y,
                );
            }
        }
    }
}

pub fn fillTileIdealCentersAffineJac(
    camera: *const CameraPrepared,
    scratch_x_px_min: usize,
    scratch_x_px_max: usize,
    scratch_y_px_min: usize,
    scratch_y_px_max: usize,
    subpx_tile_size: usize,
    ideal_pixel_centers: []f64,
) void {
    const sub_samp: usize = @intCast(camera.sub_sample);
    const jac = &camera.pixel_center_jac;
    const start_x = scratch_x_px_min * sub_samp;
    const start_y = scratch_y_px_min * sub_samp;
    const tile_w = (scratch_x_px_max - scratch_x_px_min) * sub_samp;
    const tile_h = (scratch_y_px_max - scratch_y_px_min) * sub_samp;

    const step = 1.0 / @as(f64, @floatFromInt(camera.sub_sample));
    const off = 0.5 / @as(f64, @floatFromInt(camera.sub_sample));

    for (0..tile_h) |jj| {
        const global_suby = start_y + jj;
        const pixel_y = global_suby / sub_samp;
        const observed_y = @as(f64, @floatFromInt(global_suby)) * step + off;
        const v_observed_y: VecSF = @splat(observed_y);
        const center_y = common.calcPixelCenterCoord(pixel_y);
        const scratch_row_off = jj * subpx_tile_size;

        var ii: usize = 0;
        while (ii < tile_w) : (ii += S) {
            const lane_count = @min(S, tile_w - ii);
            const global_x_start = start_x + ii;
            const v_observed_x = calcObservedXVector(
                global_x_start,
                step,
                off,
            );

            if (common.isNoDistortion(camera.distortion)) {
                storeIdealPairs(
                    ideal_pixel_centers,
                    scratch_row_off + ii,
                    lane_count,
                    v_observed_x,
                    v_observed_y,
                );
                continue;
            }

            var ideal_x_arr: [S]f64 = undefined;
            var ideal_y_arr: [S]f64 = undefined;
            var j11_arr: [S]f64 = undefined;
            var j12_arr: [S]f64 = undefined;
            var j21_arr: [S]f64 = undefined;
            var j22_arr: [S]f64 = undefined;
            var delta_x_arr: [S]f64 = undefined;

            for (0..lane_count) |ll| {
                const global_subx = global_x_start + ll;
                const pixel_x = global_subx / sub_samp;
                const observed_x = @as(f64, @floatFromInt(global_subx)) *
                    step + off;
                const center_x = common.calcPixelCenterCoord(pixel_x);
                ideal_x_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 0 });
                ideal_y_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 1 });
                j11_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 2 });
                j12_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 3 });
                j21_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 4 });
                j22_arr[ll] = jac.get(&[_]usize{ pixel_y, pixel_x, 5 });
                delta_x_arr[ll] = observed_x - center_x;
            }
            for (lane_count..S) |ll| {
                ideal_x_arr[ll] = 0.0;
                ideal_y_arr[ll] = 0.0;
                j11_arr[ll] = 0.0;
                j12_arr[ll] = 0.0;
                j21_arr[ll] = 0.0;
                j22_arr[ll] = 0.0;
                delta_x_arr[ll] = 0.0;
            }

            const v_delta_x: VecSF = delta_x_arr;
            const v_delta_y: VecSF = @splat(observed_y - center_y);
            const v_ideal_x: VecSF = ideal_x_arr;
            const v_ideal_y: VecSF = ideal_y_arr;
            const v_j11: VecSF = j11_arr;
            const v_j12: VecSF = j12_arr;
            const v_j21: VecSF = j21_arr;
            const v_j22: VecSF = j22_arr;

            storeIdealPairs(
                ideal_pixel_centers,
                scratch_row_off + ii,
                lane_count,
                v_ideal_x + v_j11 * v_delta_x + v_j12 * v_delta_y,
                v_ideal_y + v_j21 * v_delta_x + v_j22 * v_delta_y,
            );
        }
    }
}

pub fn initPixelCenterJac(camera: *CameraPrepared) !void {
    const eps: f64 = 0.25;
    for (0..camera.pixels_num[1]) |jj| {
        const y_c = common.calcPixelCenterCoord(jj);
        const v_center_y: VecSF = @splat(y_c);
        const v_y_plus: VecSF = @splat(y_c + eps);
        const v_y_minus: VecSF = @splat(y_c - eps);

        var ii: usize = 0;
        while (ii < camera.pixels_num[0]) : (ii += S) {
            const lane_count = @min(S, @as(usize, camera.pixels_num[0]) - ii);
            const v_active = calcActiveMask(lane_count);

            var x_center_arr: [S]f64 = undefined;
            for (0..lane_count) |ll| {
                x_center_arr[ll] = common.calcPixelCenterCoord(ii + ll);
            }
            for (lane_count..S) |ll| x_center_arr[ll] = 0.0;
            const v_center_x: VecSF = x_center_arr;
            const v_x_plus = v_center_x + @as(VecSF, @splat(eps));
            const v_x_minus = v_center_x - @as(VecSF, @splat(eps));

            if (common.isNoDistortion(camera.distortion)) {
                const center_arr: [S]f64 = v_center_x;
                for (0..lane_count) |ll| {
                    const px = ii + ll;
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 0 }, center_arr[ll]);
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 1 }, y_c);
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 2 }, 1.0);
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 3 }, 0.0);
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 4 }, 0.0);
                    camera.pixel_center_jac.set(&[_]usize{ jj, px, 5 }, 1.0);
                }
                continue;
            }

            const center = try calcPinholeRasterPointSIMD(
                camera,
                v_center_x,
                v_center_y,
                v_active,
            );
            const x_p = try calcPinholeRasterPointSIMD(
                camera,
                v_x_plus,
                v_center_y,
                v_active,
            );
            const x_m = try calcPinholeRasterPointSIMD(
                camera,
                v_x_minus,
                v_center_y,
                v_active,
            );
            const y_p = try calcPinholeRasterPointSIMD(
                camera,
                v_center_x,
                v_y_plus,
                v_active,
            );
            const y_m = try calcPinholeRasterPointSIMD(
                camera,
                v_center_x,
                v_y_minus,
                v_active,
            );
            const inv_two_eps: VecSF = @splat(0.5 / eps);

            const center_x_arr: [S]f64 = center.x;
            const center_y_arr: [S]f64 = center.y;
            const j11_arr: [S]f64 = (x_p.x - x_m.x) * inv_two_eps;
            const j12_arr: [S]f64 = (y_p.x - y_m.x) * inv_two_eps;
            const j21_arr: [S]f64 = (x_p.y - x_m.y) * inv_two_eps;
            const j22_arr: [S]f64 = (y_p.y - y_m.y) * inv_two_eps;
            for (0..lane_count) |ll| {
                const px = ii + ll;
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 0 }, center_x_arr[ll]);
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 1 }, center_y_arr[ll]);
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 2 }, j11_arr[ll]);
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 3 }, j12_arr[ll]);
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 4 }, j21_arr[ll]);
                camera.pixel_center_jac.set(&[_]usize{ jj, px, 5 }, j22_arr[ll]);
            }
        }
    }
}

pub fn calcPinholeRasterPoint(
    camera: *const CameraPrepared,
    observed_x_px: f64,
    observed_y_px: f64,
) ![2]f64 {
    return common.calcPinholeRasterPointScalar(
        camera,
        observed_x_px,
        observed_y_px,
    );
}
