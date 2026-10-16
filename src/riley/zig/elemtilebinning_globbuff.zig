// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const distbounds = @import("distortbounds.zig");
const geomkerns = @import("geometrykernels.zig");
const frontend = @import("rasterfrontend.zig");
const elemtilebin = @import("elemtilebinning.zig");

pub fn binElemsInSceneGlobBuff(
    outer_alloc: std.mem.Allocator,
    tile_size: u16,
    screen_px_x: u16,
    screen_px_y: u16,
    core_y_px_min: u16,
    core_y_px_max: u16,
    halo_px: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []frontend.ElemBBox,
    elem_float_bboxes_by_mesh: []const ?[]distbounds.DistortBounds,
    mesh_types: []const geomkerns.MeshType,
    root_classes_by_mesh: []const []frontend.ElemRootClass,
) !elemtilebin.TileElemOverlaps {
    const tiles_x = try std.math.divCeil(usize, screen_px_x, tile_size);
    std.debug.assert(core_y_px_min < core_y_px_max);
    std.debug.assert(core_y_px_max <= screen_px_y);

    const tiles_y = try std.math.divCeil(
        usize,
        core_y_px_max - core_y_px_min,
        tile_size,
    );

    const tiles_num = tiles_x * tiles_y;
    const tile_i: i32 = @intCast(tile_size);
    const halo_i: i32 = @intCast(halo_px);
    const core_y_min_i: i32 = @intCast(core_y_px_min);
    const core_y_max_i: i32 = @intCast(core_y_px_max);

    // Pass 1: Count overlaps per tile and bin by iterating over elements.
    const tile_elem_counts = try outer_alloc.alloc(
        usize,
        tiles_num * elemtilebin.bin_count,
    );
    defer outer_alloc.free(tile_elem_counts);
    @memset(tile_elem_counts, 0);

    for (elem_bboxes_by_mesh, 0..) |elem_bboxes, mesh_idx| {
        const maybe_float_bboxes = elem_float_bboxes_by_mesh[mesh_idx];
        const count = elems_in_image_by_mesh[mesh_idx];
        const m_type = mesh_types[mesh_idx];
        const r_classes = root_classes_by_mesh[mesh_idx];

        for (elem_bboxes[0..count], 0..) |elem_bbox, ee| {
            const bin_idx = @intFromEnum(elemtilebin.binForElem(
                m_type,
                r_classes,
                elem_bbox.elem_idx,
            ));
            const floating: ?distbounds.DistortBounds = if (maybe_float_bboxes) |fb|
                fb[ee]
            else
                null;

            // Bounding range of tiles this element could touch:
            const raw_tx_min = @divFloor(elem_bbox.x_min - halo_i, tile_i);
            const raw_tx_max = @divFloor(
                elem_bbox.x_max + halo_i + tile_i - 1,
                tile_i,
            );
            const raw_ty_min = @divFloor(
                elem_bbox.y_min - halo_i - core_y_min_i,
                tile_i,
            );
            const raw_ty_max = @divFloor(
                elem_bbox.y_max + halo_i - core_y_min_i + tile_i - 1,
                tile_i,
            );

            const tx_start: usize = @intCast(@max(@as(i32, 0), raw_tx_min));
            const tx_end: usize = @intCast(@min(
                @as(i32, @intCast(tiles_x)),
                @max(@as(i32, 0), raw_tx_max),
            ));
            const ty_start: usize = @intCast(@max(@as(i32, 0), raw_ty_min));
            const ty_end: usize = @intCast(@min(
                @as(i32, @intCast(tiles_y)),
                @max(@as(i32, 0), raw_ty_max),
            ));

            if (tx_start >= tx_end or ty_start >= ty_end) continue;

            for (ty_start..ty_end) |yy| {
                const y_min: u16 = @intCast(core_y_px_min + yy * tile_size);
                const scratch_y_min: i32 = @as(i32, y_min) - if (yy == 0) halo_px else 0;
                const scratch_y_max: i32 = if (yy + 1 == tiles_y)
                    core_y_max_i + halo_i
                else
                    @as(i32, @intCast(core_y_px_min + (yy + 1) * tile_size));

                for (tx_start..tx_end) |xx| {
                    const x_min: u16 = @intCast(xx * tile_size);
                    const scratch_x_min: i32 = @as(i32, x_min) - if (xx == 0) halo_px else 0;
                    const scratch_x_max: i32 = if (xx + 1 == tiles_x)
                        @as(i32, screen_px_x) + halo_i
                    else
                        @as(i32, @intCast((xx + 1) * tile_size));

                    const overlap = elemtilebin.clipElemBBoxToTile(
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
                    const tile_idx = yy * tiles_x + xx;
                    tile_elem_counts[tile_idx * elemtilebin.bin_count + bin_idx] += 1;
                }
            }
        }
    }

    // Pass 2: Prefix sum and single exact allocations.
    var overlap_total: usize = 0;
    var num_active_tiles: usize = 0;
    for (0..tiles_num) |tile_idx| {
        var tile_count: usize = 0;
        for (0..elemtilebin.bin_count) |bb| {
            tile_count += tile_elem_counts[tile_idx * elemtilebin.bin_count + bb];
        }
        overlap_total += tile_count;
        if (tile_count > 0) num_active_tiles += 1;
    }

    const active_tiles = try outer_alloc.alloc(
        elemtilebin.ActiveTile,
        num_active_tiles,
    );
    const overlaps = try outer_alloc.alloc(elemtilebin.OverlapBBox, overlap_total);

    const tile_write_inds = try outer_alloc.alloc(
        usize,
        tiles_num * elemtilebin.bin_count,
    );
    defer outer_alloc.free(tile_write_inds);

    var current_off: usize = 0;
    var active_idx: usize = 0;
    for (0..tiles_y) |yy| {
        const y_min: u16 = @intCast(core_y_px_min + yy * tile_size);
        const y_max = @min(
            core_y_px_max,
            @as(u16, @intCast(core_y_px_min + (yy + 1) * tile_size)),
        );
        const scratch_y_min: i32 = @as(i32, y_min) - if (yy == 0) halo_px else 0;
        const scratch_y_max: i32 = if (yy + 1 == tiles_y)
            core_y_max_i + halo_i
        else
            @as(i32, @intCast(core_y_px_min + (yy + 1) * tile_size));

        for (0..tiles_x) |xx| {
            const x_min: u16 = @intCast(xx * tile_size);
            const x_max = @min(screen_px_x, @as(u16, @intCast((xx + 1) * tile_size)));
            const scratch_x_min: i32 = @as(i32, x_min) - if (xx == 0) halo_px else 0;
            const scratch_x_max: i32 = if (xx + 1 == tiles_x)
                @as(i32, screen_px_x) + halo_i
            else
                @as(i32, @intCast((xx + 1) * tile_size));
            const tile_idx = yy * tiles_x + xx;

            var tile_count: usize = 0;
            var ranges = [_]elemtilebin.ElemBinRange{.{}} ** elemtilebin.bin_count;
            for (0..elemtilebin.bin_count) |bb| {
                const b_count = tile_elem_counts[
                    tile_idx * elemtilebin.bin_count + bb
                ];
                ranges[bb] = .{
                    .start = current_off + tile_count,
                    .count = b_count,
                };
                tile_write_inds[tile_idx * elemtilebin.bin_count + bb] =
                    current_off + tile_count;
                tile_count += b_count;
            }

            if (tile_count > 0) {
                active_tiles[active_idx] = .{
                    .overlap_start = current_off,
                    .overlap_count = tile_count,
                    .bins = ranges,
                    .core_px = .{
                        .x_min = @intCast(x_min),
                        .y_min = @intCast(y_min),
                        .x_max = @intCast(x_max),
                        .y_max = @intCast(y_max),
                    },
                    .scratch_px = .{
                        .x_min = scratch_x_min,
                        .y_min = scratch_y_min,
                        .x_max = scratch_x_max,
                        .y_max = scratch_y_max,
                    },
                };
                active_idx += 1;
            }
            current_off += tile_count;
        }
    }

    // Pass 3: Fill allocated overlaps directly into their exact offsets.
    for (elem_bboxes_by_mesh, 0..) |elem_bboxes, mesh_idx| {
        const maybe_float_bboxes = elem_float_bboxes_by_mesh[mesh_idx];
        const count = elems_in_image_by_mesh[mesh_idx];
        const m_type = mesh_types[mesh_idx];
        const r_classes = root_classes_by_mesh[mesh_idx];

        for (elem_bboxes[0..count], 0..) |elem_bbox, ee| {
            const bin_idx = @intFromEnum(elemtilebin.binForElem(
                m_type,
                r_classes,
                elem_bbox.elem_idx,
            ));
            const floating: ?distbounds.DistortBounds = if (maybe_float_bboxes) |fb|
                fb[ee]
            else
                null;

            const raw_tx_min = @divFloor(elem_bbox.x_min - halo_i, tile_i);
            const raw_tx_max = @divFloor(
                elem_bbox.x_max + halo_i + tile_i - 1,
                tile_i,
            );
            const raw_ty_min = @divFloor(
                elem_bbox.y_min - halo_i - core_y_min_i,
                tile_i,
            );
            const raw_ty_max = @divFloor(
                elem_bbox.y_max + halo_i - core_y_min_i + tile_i - 1,
                tile_i,
            );

            const tx_start: usize = @intCast(@max(@as(i32, 0), raw_tx_min));
            const tx_end: usize = @intCast(@min(
                @as(i32, @intCast(tiles_x)),
                @max(@as(i32, 0), raw_tx_max),
            ));
            const ty_start: usize = @intCast(@max(@as(i32, 0), raw_ty_min));
            const ty_end: usize = @intCast(@min(
                @as(i32, @intCast(tiles_y)),
                @max(@as(i32, 0), raw_ty_max),
            ));

            if (tx_start >= tx_end or ty_start >= ty_end) continue;

            for (ty_start..ty_end) |yy| {
                const y_min: u16 = @intCast(core_y_px_min + yy * tile_size);
                const scratch_y_min: i32 = @as(i32, y_min) - if (yy == 0) halo_px else 0;
                const scratch_y_max: i32 = if (yy + 1 == tiles_y)
                    core_y_max_i + halo_i
                else
                    @as(i32, @intCast(core_y_px_min + (yy + 1) * tile_size));

                for (tx_start..tx_end) |xx| {
                    const x_min: u16 = @intCast(xx * tile_size);
                    const scratch_x_min: i32 = @as(i32, x_min) - if (xx == 0) halo_px else 0;
                    const scratch_x_max: i32 = if (xx + 1 == tiles_x)
                        @as(i32, screen_px_x) + halo_i
                    else
                        @as(i32, @intCast((xx + 1) * tile_size));

                    const overlap = elemtilebin.clipElemBBoxToTile(
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
                    const tile_idx = yy * tiles_x + xx;
                    const write_idx = tile_write_inds[
                        tile_idx * elemtilebin.bin_count + bin_idx
                    ];
                    overlaps[write_idx] = overlap;
                    tile_write_inds[
                        tile_idx * elemtilebin.bin_count + bin_idx
                    ] = write_idx + 1;
                }
            }
        }
    }

    return .{
        .active_tiles = active_tiles,
        .overlaps = overlaps,
    };
}

test "global sub-pixel tiles own disjoint cores and retain halo only at frame edges" {
    var elem_bboxes = [_]frontend.ElemBBox{.{
        .elem_idx = 0,
        .x_min = -2,
        .x_max = 12,
        .y_min = -2,
        .y_max = 11,
    }};
    const elems_in_image = [_]usize{1};
    const elem_bboxes_by_mesh = [_][]frontend.ElemBBox{elem_bboxes[0..]};
    const elem_float_bboxes_by_mesh = [_]?[]distbounds.DistortBounds{null};
    const mesh_types = [_]geomkerns.MeshType{.tri3};
    const root_classes_by_mesh = [_][]frontend.ElemRootClass{&.{}};
    const sub_sample: i32 = 2;
    const halo_px: u16 = 2;
    const screen_w_px: u16 = 10;
    const screen_h_px: u16 = 9;
    const screen_w_subpx: i32 = @as(i32, screen_w_px) * sub_sample;
    const screen_h_subpx: i32 = @as(i32, screen_h_px) * sub_sample;
    const halo_subpx: i32 = @as(i32, halo_px) * sub_sample;

    const tiling = try binElemsInSceneGlobBuff(
        std.testing.allocator,
        4,
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
        const subpx = tile.calcSubpxBounds(sub_sample);
        try std.testing.expectEqual(
            if (subpx.core.x_min == 0) -halo_subpx else subpx.core.x_min,
            subpx.scratch.x_min,
        );
        try std.testing.expectEqual(
            if (subpx.core.x_max == screen_w_subpx)
                screen_w_subpx + halo_subpx
            else
                subpx.core.x_max,
            subpx.scratch.x_max,
        );
        try std.testing.expectEqual(
            if (subpx.core.y_min == 0) -halo_subpx else subpx.core.y_min,
            subpx.scratch.y_min,
        );
        try std.testing.expectEqual(
            if (subpx.core.y_max == screen_h_subpx)
                screen_h_subpx + halo_subpx
            else
                subpx.core.y_max,
            subpx.scratch.y_max,
        );
    }

    for (tiling.active_tiles, 0..) |tile_a, ii| {
        const subpx_a = tile_a.calcSubpxBounds(sub_sample);
        for (tiling.active_tiles[ii + 1 ..]) |tile_b| {
            const subpx_b = tile_b.calcSubpxBounds(sub_sample);
            const overlaps_x = subpx_a.scratch.x_min < subpx_b.scratch.x_max and
                subpx_b.scratch.x_min < subpx_a.scratch.x_max;
            const overlaps_y = subpx_a.scratch.y_min < subpx_b.scratch.y_max and
                subpx_b.scratch.y_min < subpx_a.scratch.y_max;
            try std.testing.expect(!(overlaps_x and overlaps_y));
        }
    }
}
