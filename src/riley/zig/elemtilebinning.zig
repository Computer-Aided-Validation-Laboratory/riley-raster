// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const F = @import("buildconfig.zig").F;
const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const MeshType = @import("geometrykernels.zig").MeshType;
const distbounds = @import("distortbounds.zig");
const frontend = @import("rasterfrontend.zig");
const ElemBBox = frontend.ElemBBox;
const ElemRootClass = frontend.ElemRootClass;

//------------------------------------------------------------------------------------------
// Element Type and Root Class Bins
//------------------------------------------------------------------------------------------

pub const ElemBin = enum(u8) {
    tri3,
    tri3opt,
    tri6_one_root,
    tri6_multi_root,
    quad4_one_root,
    quad4_multi_root,
    quad8_one_root,
    quad8_multi_root,
    quad9_one_root,
    quad9_multi_root,
};

pub const bin_count = std.meta.fields(ElemBin).len;

pub const ElemBinRange = struct {
    start: usize = 0,
    count: usize = 0,
};

pub fn binForElem(
    mesh_type: MeshType,
    classes: []const ElemRootClass,
    elem_idx: usize,
) ElemBin {
    return switch (mesh_type) {
        .tri3 => .tri3,
        .tri3opt => .tri3opt,
        .tri6 => if (classes[elem_idx] == .one_root)
            .tri6_one_root
        else
            .tri6_multi_root,
        .quad4 => if (classes[elem_idx] == .one_root)
            .quad4_one_root
        else
            .quad4_multi_root,
        .quad8 => if (classes[elem_idx] == .one_root)
            .quad8_one_root
        else
            .quad8_multi_root,
        .quad9 => if (classes[elem_idx] == .one_root)
            .quad9_one_root
        else
            .quad9_multi_root,
    };
}

pub fn binMeshType(comptime elem_bin: ElemBin) MeshType {
    return switch (elem_bin) {
        .tri3 => .tri3,
        .tri3opt => .tri3opt,
        .tri6_one_root, .tri6_multi_root => .tri6,
        .quad4_one_root, .quad4_multi_root => .quad4,
        .quad8_one_root, .quad8_multi_root => .quad8,
        .quad9_one_root, .quad9_multi_root => .quad9,
    };
}

pub fn binRootClass(comptime elem_bin: ElemBin) ElemRootClass {
    return switch (elem_bin) {
        .tri6_multi_root,
        .quad4_multi_root,
        .quad8_multi_root,
        .quad9_multi_root,
        => .multi_root,
        else => .one_root,
    };
}

//------------------------------------------------------------------------------------------
// Scene Element-Tile Binning and Overlap Bounding Boxes
//------------------------------------------------------------------------------------------

pub const OverlapBBox = struct {
    mesh_idx: usize,
    elem_idx: usize,
    x_min: i32,
    x_max: i32,
    y_min: i32,
    y_max: i32,
};

pub fn clipElemBBoxToTile(
    elem_bbox: ElemBBox,
    floating: ?distbounds.DistortBounds,
    mesh_idx: usize,
    scratch_x_min: i32,
    scratch_x_max: i32,
    scratch_y_min: i32,
    scratch_y_max: i32,
) OverlapBBox {
    if (floating) |bounds| {
        const clamp_x_min = @max(bounds.x_min, @as(F, @floatFromInt(scratch_x_min)));
        const clamp_x_max = @min(bounds.x_max, @as(F, @floatFromInt(scratch_x_max)));
        const clamp_y_min = @max(bounds.y_min, @as(F, @floatFromInt(scratch_y_min)));
        const clamp_y_max = @min(bounds.y_max, @as(F, @floatFromInt(scratch_y_max)));

        return .{
            .mesh_idx = mesh_idx,
            .elem_idx = elem_bbox.elem_idx,
            .x_min = frontend.boundIndMinSigned(clamp_x_min, scratch_x_min),
            .x_max = frontend.boundIndMaxSigned(clamp_x_max, scratch_x_max),
            .y_min = frontend.boundIndMinSigned(clamp_y_min, scratch_y_min),
            .y_max = frontend.boundIndMaxSigned(clamp_y_max, scratch_y_max),
        };
    }
    return .{
        .mesh_idx = mesh_idx,
        .elem_idx = elem_bbox.elem_idx,
        .x_min = @max(elem_bbox.x_min, scratch_x_min),
        .x_max = @min(elem_bbox.x_max, scratch_x_max),
        .y_min = @max(elem_bbox.y_min, scratch_y_min),
        .y_max = @min(elem_bbox.y_max, scratch_y_max),
    };
}

pub const TileBounds = struct {
    x_min: i32,
    y_min: i32,
    x_max: i32,
    y_max: i32,

    pub fn scale(self: @This(), factor: i32) @This() {
        return .{
            .x_min = self.x_min * factor,
            .y_min = self.y_min * factor,
            .x_max = self.x_max * factor,
            .y_max = self.y_max * factor,
        };
    }
};

pub const ActiveTile = struct {
    overlap_start: usize,
    overlap_count: usize,

    bins: [bin_count]ElemBinRange =
        [_]ElemBinRange{.{}} ** bin_count,

    core_px: TileBounds,
    scratch_px: TileBounds,

    pub fn calcSubpxBounds(
        self: *const @This(),
        sub_samp: i32,
    ) struct { core: TileBounds, scratch: TileBounds } {
        return .{
            .core = self.core_px.scale(sub_samp),
            .scratch = self.scratch_px.scale(sub_samp),
        };
    }
};

pub const TileElemOverlaps = struct {
    overlaps: []OverlapBBox,
    active_tiles: []ActiveTile,
};

pub fn binElemsInSceneTileLoc(
    allocator: std.mem.Allocator,
    chunk_exec: *pce.ParaChunkExecutor,
    workers_num: usize,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    halo_px: u16,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []ElemBBox,
    elem_float_bboxes_by_mesh: []const ?[]distbounds.DistortBounds,
    mesh_types: []const MeshType,
    root_classes_by_mesh: []const []ElemRootClass,
) !TileElemOverlaps {
    const tiles_num = tiles_num_x * tiles_num_y;

    // Stage 1 - Parallel Counting Pass: Determine the number of elem-tile
    // intersections across all meshes.
    const tile_elem_counts = try allocator.alloc(
        std.atomic.Value(usize),
        tiles_num * bin_count,
    );
    defer allocator.free(tile_elem_counts);
    for (tile_elem_counts) |*count| count.* = std.atomic.Value(usize).init(0);

    for (0..elems_in_image_by_mesh.len) |mesh_idx| {
        const elems_num = elems_in_image_by_mesh[mesh_idx];
        if (elems_num == 0) continue;

        var count_stage = TilingCountStage{
            .tile_elem_counts = tile_elem_counts,
            .tile_size = tile_size,
            .tiles_num_x = tiles_num_x,
            .tiles_num_y = tiles_num_y,
            .halo_px = halo_px,
            .elems_num = elems_num,
            .elem_bbox_slice = elem_bboxes_by_mesh[mesh_idx],
            .mesh_type = mesh_types[mesh_idx],
            .root_classes = root_classes_by_mesh[mesh_idx],
        };

        const chunk_size = scalingpolicy.tilingChunkSize(
            elems_num,
            workers_num,
        );

        pce.runStaticRange(
            chunk_exec,
            &count_stage,
            runTilingCount,
            elems_num,
            chunk_size,
        );
    }

    // Stage 2 - Serial Management Pass: Allocate overlap buffs and calc
    // global offsets for each tile.
    var overlap_total: usize = 0;
    var num_active_tiles: usize = 0;
    for (0..tiles_num) |tile_idx| {
        var count: usize = 0;
        for (0..bin_count) |bb| {
            count += tile_elem_counts[tile_idx * bin_count + bb].load(.monotonic);
        }
        overlap_total += count;
        if (count > 0) num_active_tiles += 1;
    }

    const overlaps = try allocator.alloc(OverlapBBox, overlap_total);
    const active_tiles = try allocator.alloc(ActiveTile, num_active_tiles);

    const tile_write_inds = try allocator.alloc(
        std.atomic.Value(usize),
        tiles_num * bin_count,
    );
    defer allocator.free(tile_write_inds);

    var current_off: usize = 0;
    var active_idx: usize = 0;
    for (0..tiles_num) |ii| {
        var count: usize = 0;
        var ranges = [_]ElemBinRange{.{}} ** bin_count;
        for (0..bin_count) |bb| {
            const bin_count_here =
                tile_elem_counts[ii * bin_count + bb].load(.monotonic);
            ranges[bb] = .{ .start = current_off + count, .count = bin_count_here };
            tile_write_inds[ii * bin_count + bb] =
                std.atomic.Value(usize).init(current_off + count);
            count += bin_count_here;
        }

        if (count > 0) {
            const tx: u16 = @intCast(ii % tiles_num_x);
            const ty: u16 = @intCast(ii / tiles_num_x);
            const core_x_min: i32 = @as(i32, @intCast(tx * tile_size));
            const core_y_min: i32 = @as(i32, @intCast(ty * tile_size));
            const core_x_max: i32 = @intCast(@min(
                screen_px_x,
                @as(u16, @intCast((tx + 1) * tile_size)),
            ));
            const core_y_max: i32 = @intCast(@min(
                screen_px_y,
                @as(u16, @intCast((ty + 1) * tile_size)),
            ));
            const halo_signed: i32 = @as(i32, @intCast(halo_px));

            active_tiles[active_idx] = .{
                .overlap_start = current_off,
                .overlap_count = count,
                .bins = ranges,
                .core_px = .{
                    .x_min = core_x_min,
                    .y_min = core_y_min,
                    .x_max = core_x_max,
                    .y_max = core_y_max,
                },
                .scratch_px = .{
                    .x_min = core_x_min - halo_signed,
                    .y_min = core_y_min - halo_signed,
                    .x_max = core_x_max + halo_signed,
                    .y_max = core_y_max + halo_signed,
                },
            };

            active_idx += 1;
        }
        current_off += count;
    }

    // Stage 3 - Parallel Filling Pass: Populate the allocated buffs with
    // elem metadata and clipped bounding boxes.
    for (0..elems_in_image_by_mesh.len) |mesh_idx| {
        const elems_num = elems_in_image_by_mesh[mesh_idx];
        if (elems_num == 0) continue;

        var fill_stage = TilingFillStage{
            .tile_write_inds = tile_write_inds,
            .overlaps = overlaps,
            .tile_size = tile_size,
            .tiles_num_x = tiles_num_x,
            .tiles_num_y = tiles_num_y,
            .screen_px_x = screen_px_x,
            .screen_px_y = screen_px_y,
            .halo_px = halo_px,
            .mesh_idx = mesh_idx,
            .elem_bbox_slice = elem_bboxes_by_mesh[mesh_idx],
            .float_bbox_slice = elem_float_bboxes_by_mesh[mesh_idx],
            .mesh_type = mesh_types[mesh_idx],
            .root_classes = root_classes_by_mesh[mesh_idx],
        };

        const chunk_size = scalingpolicy.tilingChunkSize(
            elems_num,
            workers_num,
        );

        pce.runStaticRange(
            chunk_exec,
            &fill_stage,
            runTilingFill,
            elems_num,
            chunk_size,
        );
    }

    return TileElemOverlaps{ .overlaps = overlaps, .active_tiles = active_tiles };
}

const TilingCountStage = struct {
    tile_elem_counts: []std.atomic.Value(usize),
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    halo_px: u16,
    elems_num: usize,
    elem_bbox_slice: []const ElemBBox,
    mesh_type: MeshType,
    root_classes: []const ElemRootClass,
};

fn runTilingCount(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const tiling: *TilingCountStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const elem_bbox = tiling.elem_bbox_slice[ee];
        const bin_idx = @intFromEnum(binForElem(
            tiling.mesh_type,
            tiling.root_classes,
            elem_bbox.elem_idx,
        ));
        const tile_range = calcElemTileRange(
            elem_bbox,
            tiling.tile_size,
            tiling.halo_px,
            tiling.tiles_num_x,
            tiling.tiles_num_y,
        );
        const tx_start = tile_range.tx_start;
        const tx_end = tile_range.tx_end;
        const ty_start = tile_range.ty_start;
        const ty_end = tile_range.ty_end;

        for (ty_start..ty_end) |yy| {
            const row_off = yy * tiling.tiles_num_x;
            for (tx_start..tx_end) |xx| {
                _ = tiling.tile_elem_counts[
                    (row_off + xx) * bin_count + bin_idx
                ].fetchAdd(1, .monotonic);
            }
        }
    }
}

const TilingFillStage = struct {
    tile_write_inds: []std.atomic.Value(usize),
    overlaps: []OverlapBBox,
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    halo_px: u16,
    mesh_idx: usize,
    elem_bbox_slice: []const ElemBBox,
    float_bbox_slice: ?[]const distbounds.DistortBounds,
    mesh_type: MeshType,
    root_classes: []const ElemRootClass,
};

fn runTilingFill(
    ctx_ptr: *anyopaque,
    chunk_idx: usize,
    range_start: usize,
    range_end: usize,
) void {
    _ = chunk_idx;
    const tiling: *TilingFillStage = @ptrCast(@alignCast(ctx_ptr));

    for (range_start..range_end) |ee| {
        const elem_bbox = tiling.elem_bbox_slice[ee];
        const bin_idx = @intFromEnum(binForElem(
            tiling.mesh_type,
            tiling.root_classes,
            elem_bbox.elem_idx,
        ));
        const floating: ?distbounds.DistortBounds = if (tiling.float_bbox_slice) |float_bboxes|
            float_bboxes[ee]
        else
            null;
        const tile_range = calcElemTileRange(
            elem_bbox,
            tiling.tile_size,
            tiling.halo_px,
            tiling.tiles_num_x,
            tiling.tiles_num_y,
        );
        const tx_start = tile_range.tx_start;
        const tx_end = tile_range.tx_end;
        const ty_start = tile_range.ty_start;
        const ty_end = tile_range.ty_end;

        for (ty_start..ty_end) |yy| {
            const tile_px_min_y = @as(u16, @intCast(yy * tiling.tile_size));
            const tile_px_max_y = @as(
                u16,
                @min(@as(u32, tile_px_min_y) + tiling.tile_size, tiling.screen_px_y),
            );
            const scratch_px_min_y: i32 = @as(i32, tile_px_min_y) - tiling.halo_px;
            const scratch_px_max_y: i32 = @as(i32, tile_px_max_y) + tiling.halo_px;

            for (tx_start..tx_end) |xx| {
                const tile_px_min_x = @as(u16, @intCast(xx * tiling.tile_size));
                const tile_px_max_x = @as(
                    u16,
                    @min(@as(u32, tile_px_min_x) + tiling.tile_size, tiling.screen_px_x),
                );
                const scratch_px_min_x: i32 = @as(i32, tile_px_min_x) - tiling.halo_px;
                const scratch_px_max_x: i32 = @as(i32, tile_px_max_x) + tiling.halo_px;

                const tile_idx = yy * tiling.tiles_num_x + xx;
                const write_idx = tiling.tile_write_inds[
                    tile_idx * bin_count + bin_idx
                ].fetchAdd(1, .monotonic);

                tiling.overlaps[write_idx] = clipElemBBoxToTile(
                    elem_bbox,
                    floating,
                    tiling.mesh_idx,
                    scratch_px_min_x,
                    scratch_px_max_x,
                    scratch_px_min_y,
                    scratch_px_max_y,
                );
            }
        }
    }
}

fn calcElemTileRange(
    elem_bbox: ElemBBox,
    tile_size: u16,
    halo_px: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
) struct { tx_start: usize, tx_end: usize, ty_start: usize, ty_end: usize } {
    const tile_i: i32 = tile_size;
    const halo_i: i32 = halo_px;
    const x_min = @max(@as(i32, 0), @divFloor(elem_bbox.x_min - halo_i, tile_i));
    const y_min = @max(@as(i32, 0), @divFloor(elem_bbox.y_min - halo_i, tile_i));
    const x_max = @min(
        @as(i32, @intCast(tiles_num_x)),
        @divFloor(elem_bbox.x_max + halo_i + tile_i - 1, tile_i),
    );
    const y_max = @min(
        @as(i32, @intCast(tiles_num_y)),
        @divFloor(elem_bbox.y_max + halo_i + tile_i - 1, tile_i),
    );
    return .{
        .tx_start = @intCast(x_min),
        .tx_end = @intCast(x_max),
        .ty_start = @intCast(y_min),
        .ty_end = @intCast(y_max),
    };
}
