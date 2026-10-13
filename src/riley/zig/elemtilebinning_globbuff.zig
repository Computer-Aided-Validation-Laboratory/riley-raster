// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const db = @import("distortbounds.zig");
const geomkerns = @import("geometrykernels.zig");
const rops = @import("rasterfrontend.zig");
const bin = @import("elemtilebinning.zig");

pub fn binSceneGlobBuff(
    outer_alloc: std.mem.Allocator,
    tile_size: u16,
    sub_sample: u32,
    screen_px_x: u16,
    screen_px_y: u16,
    core_y_px_min: u16,
    core_y_px_max: u16,
    halo_px: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []rops.ElemBBox,
    elem_float_bboxes_by_mesh: []const ?[]db.DistortBounds,
    mesh_types: []const geomkerns.MeshType,
    root_classes_by_mesh: []const []rops.ElemRootClass,
) !bin.TilingOverlaps {
    const tiles_x = try std.math.divCeil(usize, screen_px_x, tile_size);
    std.debug.assert(core_y_px_min < core_y_px_max);
    std.debug.assert(core_y_px_max <= screen_px_y);

    const tiles_y = try std.math.divCeil(
        usize,
        core_y_px_max - core_y_px_min,
        tile_size,
    );

    var tiles: std.ArrayList(bin.ActiveTile) = .empty;
    defer tiles.deinit(outer_alloc);

    var overlaps: std.ArrayList(bin.OverlapBBox) = .empty;
    defer overlaps.deinit(outer_alloc);

    const sub_samp: i32 = @intCast(sub_sample);

    for (0..tiles_y) |ty| {
        const y_min: u16 = @intCast(core_y_px_min + ty * tile_size);
        const y_max = @min(
            core_y_px_max,
            @as(u16, @intCast(core_y_px_min + (ty + 1) * tile_size)),
        );
        for (0..tiles_x) |tx| {
            const x_min: u16 = @intCast(tx * tile_size);
            const x_max = @min(screen_px_x, @as(u16, @intCast((tx + 1) * tile_size)));
            const scratch_x_min: i32 = @as(i32, x_min) - if (tx == 0) halo_px else 0;
            const scratch_x_max: i32 = @as(i32, x_max) +
                if (tx + 1 == tiles_x) halo_px else 0;
            const scratch_y_min: i32 = @as(i32, y_min) - if (ty == 0) halo_px else 0;
            const scratch_y_max: i32 = @as(i32, y_max) +
                if (ty + 1 == tiles_y) halo_px else 0;
            const overlap_start = overlaps.items.len;
            var ranges = [_]bin.ElemBucketRange{.{}} ** bin.bucket_count;

            for (0..bin.bucket_count) |bb| {
                const bucket_start = overlaps.items.len;
                for (elem_bboxes_by_mesh, 0..) |elem_bboxes, mesh_idx| {
                    const maybe_float_bboxes = elem_float_bboxes_by_mesh[mesh_idx];
                    const count = elems_in_image_by_mesh[mesh_idx];
                    for (elem_bboxes[0..count], 0..) |elem_bbox, ee| {
                        if (@intFromEnum(bin.bucketForElem(
                            mesh_types[mesh_idx],
                            root_classes_by_mesh[mesh_idx],
                            elem_bbox.elem_idx,
                        )) != bb) continue;
                        const floating: ?db.DistortBounds = if (maybe_float_bboxes) |fb|
                            fb[ee]
                        else
                            null;
                        const overlap = bin.clipElemBBoxToTile(
                            elem_bbox,
                            floating,
                            mesh_idx,
                            scratch_x_min,
                            scratch_x_max,
                            scratch_y_min,
                            scratch_y_max,
                        );
                        if (overlap.x_min >= overlap.x_max or
                            overlap.y_min >= overlap.y_max)
                        {
                            continue;
                        }
                        try overlaps.append(outer_alloc, overlap);
                    }
                }
                ranges[bb] = .{
                    .start = bucket_start,
                    .count = overlaps.items.len - bucket_start,
                };
            }
            if (overlaps.items.len == overlap_start) continue;
            try tiles.append(outer_alloc, .{
                .overlap_start = overlap_start,
                .overlap_count = overlaps.items.len - overlap_start,
                .buckets = ranges,
                .x_px_min = x_min,
                .y_px_min = y_min,
                .x_px_max = x_max,
                .y_px_max = y_max,
                .scratch_x_px_min = scratch_x_min,
                .scratch_y_px_min = scratch_y_min,
                .scratch_x_px_max = scratch_x_max,
                .scratch_y_px_max = scratch_y_max,
                .core_subx_min = @as(i32, x_min) * sub_samp,
                .core_suby_min = @as(i32, y_min) * sub_samp,
                .core_subx_max = @as(i32, x_max) * sub_samp,
                .core_suby_max = @as(i32, y_max) * sub_samp,
                .scratch_subx_min = scratch_x_min * sub_samp,
                .scratch_suby_min = scratch_y_min * sub_samp,
                .scratch_subx_max = scratch_x_max * sub_samp,
                .scratch_suby_max = scratch_y_max * sub_samp,
            });
        }
    }
    return .{
        .active_tiles = try tiles.toOwnedSlice(outer_alloc),
        .overlaps = try overlaps.toOwnedSlice(outer_alloc),
    };
}

test "global sub-pixel tiles own disjoint cores and retain halo only at frame edges" {
    var elem_bboxes = [_]rops.ElemBBox{.{
        .elem_idx = 0,
        .x_min = -2,
        .x_max = 12,
        .y_min = -2,
        .y_max = 11,
    }};
    const elems_in_image = [_]usize{1};
    const elem_bboxes_by_mesh = [_][]rops.ElemBBox{elem_bboxes[0..]};
    const elem_float_bboxes_by_mesh = [_]?[]db.DistortBounds{null};
    const mesh_types = [_]geomkerns.MeshType{.tri3};
    const root_classes_by_mesh = [_][]rops.ElemRootClass{&.{}};
    const sub_sample: u32 = 2;
    const halo_px: u16 = 2;
    const screen_w_px: u16 = 10;
    const screen_h_px: u16 = 9;
    const screen_w_subpx: i32 = screen_w_px * sub_sample;
    const screen_h_subpx: i32 = screen_h_px * sub_sample;
    const halo_subpx: i32 = halo_px * sub_sample;

    const tiling = try binSceneGlobBuff(
        std.testing.allocator,
        4,
        sub_sample,
        screen_w_px,
        screen_h_px,
        0,
        screen_h_px,
        halo_px,
        elems_in_image[0..],
        elem_bboxes_by_mesh[0..],
        elem_float_bboxes_by_mesh[0..],
        mesh_types[0..],
        root_classes_by_mesh[0..],
    );
    defer std.testing.allocator.free(tiling.active_tiles);
    defer std.testing.allocator.free(tiling.overlaps);

    try std.testing.expectEqual(@as(usize, 9), tiling.active_tiles.len);
    for (tiling.active_tiles) |tile| {
        try std.testing.expectEqual(
            if (tile.core_subx_min == 0) -halo_subpx else tile.core_subx_min,
            tile.scratch_subx_min,
        );
        try std.testing.expectEqual(
            if (tile.core_subx_max == screen_w_subpx)
                screen_w_subpx + halo_subpx
            else
                tile.core_subx_max,
            tile.scratch_subx_max,
        );
        try std.testing.expectEqual(
            if (tile.core_suby_min == 0) -halo_subpx else tile.core_suby_min,
            tile.scratch_suby_min,
        );
        try std.testing.expectEqual(
            if (tile.core_suby_max == screen_h_subpx)
                screen_h_subpx + halo_subpx
            else
                tile.core_suby_max,
            tile.scratch_suby_max,
        );
    }

    for (tiling.active_tiles, 0..) |tile_a, aa| {
        for (tiling.active_tiles[aa + 1 ..]) |tile_b| {
            const overlaps_x = tile_a.scratch_subx_min < tile_b.scratch_subx_max and
                tile_b.scratch_subx_min < tile_a.scratch_subx_max;
            const overlaps_y = tile_a.scratch_suby_min < tile_b.scratch_suby_max and
                tile_b.scratch_suby_min < tile_a.scratch_suby_max;
            try std.testing.expect(!(overlaps_x and overlaps_y));
        }
    }
}
