// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const ndarray = @import("ndarray.zig");
const rops = @import("rasterfrontend.zig");
const bin = @import("elemtilebinning.zig");
const report = @import("report.zig");
const backend = @import("rasterengine_simd.zig");
const mo = @import("meshpipeline.zig");
const subpxframe = @import("subpxframe_globbuff.zig");

const GlobalSubpxScratchBuffs = struct {
    pub const exclusive_subpx_target = true;

    stride_subpx: usize,
    inv_z: []align(64) F,
    image: @import("matslice.zig").MatSlice(F),
    filter_tmp: @import("matslice.zig").MatSlice(F),
    simd_chunks: []backend.SubpxSimdChunk,
    multi_root_candidate_indices: []u32,
    multi_root_child_masks: []u8,
    mask: []align(64) bool,
    xi: []align(64) F,
    eta: []align(64) F,
    touched_min_x: []usize,
    touched_max_x: []usize,
    ideal_pix_cent: []align(64) F,
    target_stride_subpx: usize = 0,
    target_subx_min: i32 = 0,
    target_suby_min: i32 = 0,
    tile_subx_min: i32 = 0,
    tile_suby_min: i32 = 0,
    tile_origin_idx: usize = 0,

    pub inline fn imageIndex(
        self: *const GlobalSubpxScratchBuffs,
        local_idx: usize,
    ) usize {
        const local_subx = local_idx % self.stride_subpx;
        const local_suby = local_idx / self.stride_subpx;
        return self.imageIndexCoord(local_subx, local_suby, local_idx);
    }

    pub inline fn imageIndexCoord(
        self: *const GlobalSubpxScratchBuffs,
        local_subx: usize,
        local_suby: usize,
        _: usize,
    ) usize {
        return self.tile_origin_idx +
            local_suby * self.target_stride_subpx + local_subx;
    }
};

pub const GlobalBackend = struct {
    pub const SubpxScratchBuffs = GlobalSubpxScratchBuffs;

    pub fn initSubpxScratch(
        arena_alloc: std.mem.Allocator,
        fields_num: u8,
        subpx_tile_size: usize,
    ) !GlobalSubpxScratchBuffs {
        const local = try backend.initSubpxScratch(
            arena_alloc,
            fields_num,
            subpx_tile_size,
        );
        return .{
            .stride_subpx = local.stride_subpx,
            .inv_z = local.inv_z,
            .image = local.image,
            .filter_tmp = local.filter_tmp,
            .simd_chunks = local.simd_chunks,
            .multi_root_candidate_indices = local.multi_root_candidate_indices,
            .multi_root_child_masks = local.multi_root_child_masks,
            .mask = local.mask,
            .xi = local.xi,
            .eta = local.eta,
            .touched_min_x = local.touched_min_x,
            .touched_max_x = local.touched_max_x,
            .ideal_pix_cent = local.ideal_pix_cent,
        };
    }

    pub fn resetSubpxScratch(
        scratch: *GlobalSubpxScratchBuffs,
        subpx_tile_size: usize,
        _: F,
    ) void {
        @memset(scratch.inv_z, -std.math.inf(F));
        @memset(scratch.touched_min_x, subpx_tile_size);
        @memset(scratch.touched_max_x, 0);
    }

    pub fn configureTarget(
        scratch: *GlobalSubpxScratchBuffs,
        target: *subpxframe.SubpxTarget,
        tile: bin.ActiveTile,
    ) void {
        scratch.image = target.image;
        scratch.target_stride_subpx = target.domain.storage_w_subpx;
        scratch.target_subx_min = target.global_subx_min;
        scratch.target_suby_min = target.global_suby_min;
        scratch.tile_subx_min = tile.scratch_subx_min;
        scratch.tile_suby_min = tile.scratch_suby_min;

        const origin_x = tile.scratch_subx_min - target.global_subx_min;
        const origin_y = tile.scratch_suby_min - target.global_suby_min;
        scratch.tile_origin_idx = @as(usize, @intCast(origin_y)) *
            scratch.target_stride_subpx + @as(usize, @intCast(origin_x));
    }

    pub fn RasterEngine(
        comptime Geom: type,
        comptime ShaderKern: type,
        comptime ShaderData: type,
        comptime root_class: rops.ElemRootClass,
    ) type {
        return backend.RasterEngine(
            GlobalSubpxScratchBuffs,
            Geom,
            ShaderKern,
            ShaderData,
            root_class,
        );
    }
};
