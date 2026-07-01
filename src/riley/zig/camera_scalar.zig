// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const common = @import("camera_common.zig");


// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const CameraPrepared = common.CameraPreparedType(@This());


// --------------------------------------------------------------------------------------
// Public Entry-Point Functions
// --------------------------------------------------------------------------------------

pub fn fillTileIdealCentersPerTile(
    camera: *const CameraPrepared,
    scratch_x_px_min: usize,
    scratch_x_px_max: usize,
    scratch_y_px_min: usize,
    scratch_y_px_max: usize,
    subpx_tile_size: usize,
    ideal_pixel_centers: []F,
) !void {
    const sub_samp: usize = @intCast(camera.sub_sample);
    const ideal_x_plane = common.getIdealXPlaneScratch(ideal_pixel_centers);
    const ideal_y_plane = common.getIdealYPlaneScratch(ideal_pixel_centers);
    const start_x = scratch_x_px_min * sub_samp;
    const start_y = scratch_y_px_min * sub_samp;
    const tile_w = (scratch_x_px_max - scratch_x_px_min) * sub_samp;
    const tile_h = (scratch_y_px_max - scratch_y_px_min) * sub_samp;

    const step = 1.0 / @as(F, @floatFromInt(camera.sub_sample));
    const off = 0.5 / @as(F, @floatFromInt(camera.sub_sample));

    if (common.isNoDistortion(camera.distortion)) {
        for (0..tile_h) |jj| {
            const global_y = start_y + jj;
            const observed_y = @as(F, @floatFromInt(global_y)) * step + off;
            const scratch_row_off = jj * subpx_tile_size;
            @memset(
                ideal_y_plane[scratch_row_off .. scratch_row_off + tile_w],
                observed_y,
            );
        }
        for (0..tile_w) |ii| {
            const global_x = start_x + ii;
            ideal_x_plane[ii] = @as(F, @floatFromInt(global_x)) * step + off;
        }
        for (1..tile_h) |jj| {
            const scratch_row_off = jj * subpx_tile_size;
            @memcpy(
                ideal_x_plane[scratch_row_off .. scratch_row_off + tile_w],
                ideal_x_plane[0..tile_w],
            );
        }
        return;
    }

    for (0..tile_h) |jj| {
        const global_y = start_y + jj;
        const observed_y = @as(F, @floatFromInt(global_y)) * step + off;
        const scratch_row_off = jj * subpx_tile_size;

        for (0..tile_w) |ii| {
            const global_x = start_x + ii;
            const observed_x = @as(F, @floatFromInt(global_x)) *
                step + off;
            const ideal = try camera.calcPinholeRasterPoint(
                observed_x,
                observed_y,
            );
            const scratch_idx = scratch_row_off + ii;
            ideal_x_plane[scratch_idx] = ideal[0];
            ideal_y_plane[scratch_idx] = ideal[1];
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
    ideal_pixel_centers: []F,
) void {
    const sub_samp: usize = @intCast(camera.sub_sample);
    const ideal_x_plane = common.getIdealXPlaneScratch(ideal_pixel_centers);
    const ideal_y_plane = common.getIdealYPlaneScratch(ideal_pixel_centers);
    const jac = &camera.pixel_center_jac;
    const jac_slice = jac.slice;
    const jac_field_stride = jac.strides[2];
    const start_x = scratch_x_px_min * sub_samp;
    const start_y = scratch_y_px_min * sub_samp;
    const tile_w = (scratch_x_px_max - scratch_x_px_min) * sub_samp;
    const tile_h = (scratch_y_px_max - scratch_y_px_min) * sub_samp;

    const step = 1.0 / @as(F, @floatFromInt(camera.sub_sample));
    const off = 0.5 / @as(F, @floatFromInt(camera.sub_sample));

    if (common.isNoDistortion(camera.distortion)) {
        for (0..tile_h) |jj| {
            const global_y = start_y + jj;
            const observed_y = @as(F, @floatFromInt(global_y)) * step + off;
            const scratch_row_off = jj * subpx_tile_size;
            @memset(
                ideal_y_plane[scratch_row_off .. scratch_row_off + tile_w],
                observed_y,
            );
        }
        for (0..tile_w) |ii| {
            const global_x = start_x + ii;
            ideal_x_plane[ii] = @as(F, @floatFromInt(global_x)) * step + off;
        }
        for (1..tile_h) |jj| {
            const scratch_row_off = jj * subpx_tile_size;
            @memcpy(
                ideal_x_plane[scratch_row_off .. scratch_row_off + tile_w],
                ideal_x_plane[0..tile_w],
            );
        }
        return;
    }

    for (0..tile_h) |jj| {
        const global_suby = start_y + jj;
        const pixel_y = global_suby / sub_samp;
        const observed_y = @as(F, @floatFromInt(global_suby)) * step + off;
        const center_y = common.calcPixelCenterCoord(pixel_y);
        const delta_y = observed_y - center_y;
        const scratch_row_off = jj * subpx_tile_size;

        for (0..tile_w) |ii| {
            const global_subx = start_x + ii;
            const pixel_x = global_subx / sub_samp;
            const observed_x = @as(F, @floatFromInt(global_subx)) *
                step + off;
            const center_x = common.calcPixelCenterCoord(pixel_x);
            const delta_x = observed_x - center_x;
            const jac_px_base = jac.subBase2(pixel_y, pixel_x);
            const ideal_x = jac_slice[jac_px_base + 0 * jac_field_stride];
            const ideal_y = jac_slice[jac_px_base + 1 * jac_field_stride];
            const j11 = jac_slice[jac_px_base + 2 * jac_field_stride];
            const j12 = jac_slice[jac_px_base + 3 * jac_field_stride];
            const j21 = jac_slice[jac_px_base + 4 * jac_field_stride];
            const j22 = jac_slice[jac_px_base + 5 * jac_field_stride];
            const scratch_idx = scratch_row_off + ii;
            ideal_x_plane[scratch_idx] =
                ideal_x + j11 * delta_x + j12 * delta_y;
            ideal_y_plane[scratch_idx] =
                ideal_y + j21 * delta_x + j22 * delta_y;
        }
    }
}

pub fn initPixelCenterJac(camera: *CameraPrepared) !void {
    const jac = &camera.pixel_center_jac;
    const jac_slice = jac.slice;
    const jac_field_stride = jac.strides[2];

    if (common.isNoDistortion(camera.distortion)) {
        for (0..camera.pixels_num[1]) |jj| {
            for (0..camera.pixels_num[0]) |ii| {
                const jac_px_base = jac.subBase2(jj, ii);
                jac_slice[jac_px_base + 0 * jac_field_stride] =
                    common.calcPixelCenterCoord(ii);
                jac_slice[jac_px_base + 1 * jac_field_stride] =
                    common.calcPixelCenterCoord(jj);
                jac_slice[jac_px_base + 2 * jac_field_stride] = 1.0;
                jac_slice[jac_px_base + 3 * jac_field_stride] = 0.0;
                jac_slice[jac_px_base + 4 * jac_field_stride] = 0.0;
                jac_slice[jac_px_base + 5 * jac_field_stride] = 1.0;
            }
        }
        return;
    }

    const eps: F = 0.25;
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
            const jac_px_base = jac.subBase2(jj, ii);
            jac_slice[jac_px_base + 0 * jac_field_stride] = center[0];
            jac_slice[jac_px_base + 1 * jac_field_stride] = center[1];
            jac_slice[jac_px_base + 2 * jac_field_stride] =
                (x_p[0] - x_m[0]) * inv_two_eps;
            jac_slice[jac_px_base + 3 * jac_field_stride] =
                (y_p[0] - y_m[0]) * inv_two_eps;
            jac_slice[jac_px_base + 4 * jac_field_stride] =
                (x_p[1] - x_m[1]) * inv_two_eps;
            jac_slice[jac_px_base + 5 * jac_field_stride] =
                (y_p[1] - y_m[1]) * inv_two_eps;
        }
    }
}

pub fn calcPinholeRasterPoint(
    camera: *const CameraPrepared,
    observed_x_px: F,
    observed_y_px: F,
) ![2]F {
    return common.calcPinholeRasterPointScalar(
        camera,
        observed_x_px,
        observed_y_px,
    );
}
