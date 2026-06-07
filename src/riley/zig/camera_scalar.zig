// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const common = @import("camera_common.zig");

pub const CameraPrepared = common.CameraPreparedType(@This());

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

    if (common.isNoDistortion(camera.distortion)) {
        for (0..tile_h) |jj| {
            const global_y = start_y + jj;
            const observed_y = @as(f64, @floatFromInt(global_y)) * step + off;
            const scratch_row_off = jj * subpx_tile_size;

            for (0..tile_w) |ii| {
                const global_x = start_x + ii;
                const observed_x = @as(f64, @floatFromInt(global_x)) *
                    step + off;
                common.storeIdealPairScratch(
                    ideal_pixel_centers,
                    scratch_row_off + ii,
                    observed_x,
                    observed_y,
                );
            }
        }
        return;
    }

    for (0..tile_h) |jj| {
        const global_y = start_y + jj;
        const observed_y = @as(f64, @floatFromInt(global_y)) * step + off;
        const scratch_row_off = jj * subpx_tile_size;

        for (0..tile_w) |ii| {
            const global_x = start_x + ii;
            const observed_x = @as(f64, @floatFromInt(global_x)) *
                step + off;
            const ideal = try camera.calcPinholeRasterPoint(
                observed_x,
                observed_y,
            );
            common.storeIdealPairScratch(
                ideal_pixel_centers,
                scratch_row_off + ii,
                ideal[0],
                ideal[1],
            );
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

    if (common.isNoDistortion(camera.distortion)) {
        for (0..tile_h) |jj| {
            const global_y = start_y + jj;
            const observed_y = @as(f64, @floatFromInt(global_y)) * step + off;
            const scratch_row_off = jj * subpx_tile_size;

            for (0..tile_w) |ii| {
                const global_x = start_x + ii;
                const observed_x = @as(f64, @floatFromInt(global_x)) *
                    step + off;
                common.storeIdealPairScratch(
                    ideal_pixel_centers,
                    scratch_row_off + ii,
                    observed_x,
                    observed_y,
                );
            }
        }
        return;
    }

    for (0..tile_h) |jj| {
        const global_suby = start_y + jj;
        const pixel_y = global_suby / sub_samp;
        const observed_y = @as(f64, @floatFromInt(global_suby)) * step + off;
        const center_y = common.calcPixelCenterCoord(pixel_y);
        const delta_y = observed_y - center_y;
        const scratch_row_off = jj * subpx_tile_size;

        for (0..tile_w) |ii| {
            const global_subx = start_x + ii;
            const pixel_x = global_subx / sub_samp;
            const observed_x = @as(f64, @floatFromInt(global_subx)) *
                step + off;
            const center_x = common.calcPixelCenterCoord(pixel_x);
            const delta_x = observed_x - center_x;
            const ideal_x = jac.get(&[_]usize{ pixel_y, pixel_x, 0 });
            const ideal_y = jac.get(&[_]usize{ pixel_y, pixel_x, 1 });
            const j11 = jac.get(&[_]usize{ pixel_y, pixel_x, 2 });
            const j12 = jac.get(&[_]usize{ pixel_y, pixel_x, 3 });
            const j21 = jac.get(&[_]usize{ pixel_y, pixel_x, 4 });
            const j22 = jac.get(&[_]usize{ pixel_y, pixel_x, 5 });
            common.storeIdealPairScratch(
                ideal_pixel_centers,
                scratch_row_off + ii,
                ideal_x + j11 * delta_x + j12 * delta_y,
                ideal_y + j21 * delta_x + j22 * delta_y,
            );
        }
    }
}

pub fn initPixelCenterJac(camera: *CameraPrepared) !void {
    if (common.isNoDistortion(camera.distortion)) {
        for (0..camera.pixels_num[1]) |jj| {
            for (0..camera.pixels_num[0]) |ii| {
                camera.pixel_center_jac.set(
                    &[_]usize{ jj, ii, 0 },
                    common.calcPixelCenterCoord(ii),
                );
                camera.pixel_center_jac.set(
                    &[_]usize{ jj, ii, 1 },
                    common.calcPixelCenterCoord(jj),
                );
                camera.pixel_center_jac.set(&[_]usize{ jj, ii, 2 }, 1.0);
                camera.pixel_center_jac.set(&[_]usize{ jj, ii, 3 }, 0.0);
                camera.pixel_center_jac.set(&[_]usize{ jj, ii, 4 }, 0.0);
                camera.pixel_center_jac.set(&[_]usize{ jj, ii, 5 }, 1.0);
            }
        }
        return;
    }

    const eps: f64 = 0.25;
    for (0..camera.pixels_num[1]) |jj| {
        for (0..camera.pixels_num[0]) |ii| {
            const x_c = common.calcPixelCenterCoord(ii);
            const y_c = common.calcPixelCenterCoord(jj);
            const center = try camera.calcPinholeRasterPoint(x_c, y_c);
            const x_p = try camera.calcPinholeRasterPoint(x_c + eps, y_c);
            const x_m = try camera.calcPinholeRasterPoint(x_c - eps, y_c);
            const y_p = try camera.calcPinholeRasterPoint(x_c, y_c + eps);
            const y_m = try camera.calcPinholeRasterPoint(x_c, y_c - eps);
            const inv_two_eps = 0.5 / eps;
            camera.pixel_center_jac.set(&[_]usize{ jj, ii, 0 }, center[0]);
            camera.pixel_center_jac.set(&[_]usize{ jj, ii, 1 }, center[1]);
            camera.pixel_center_jac.set(
                &[_]usize{ jj, ii, 2 },
                (x_p[0] - x_m[0]) * inv_two_eps,
            );
            camera.pixel_center_jac.set(
                &[_]usize{ jj, ii, 3 },
                (y_p[0] - y_m[0]) * inv_two_eps,
            );
            camera.pixel_center_jac.set(
                &[_]usize{ jj, ii, 4 },
                (x_p[1] - x_m[1]) * inv_two_eps,
            );
            camera.pixel_center_jac.set(
                &[_]usize{ jj, ii, 5 },
                (y_p[1] - y_m[1]) * inv_two_eps,
            );
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
