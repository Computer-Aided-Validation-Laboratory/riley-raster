const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const cfg = buildconfig.config;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;
const report = @import("report.zig");
const ReportMode = report.ReportMode;
const Timestamp = std.Io.Clock.Timestamp;
const rops = @import("rasterops.zig");
const mr = @import("meshraster.zig");
const MeshPrepared = mr.MeshPrepared;
const shaderops = @import("shaderops.zig");
const NodalPrepared = shaderops.NodalPrepared;
const TexPrepared = shaderops.TexPrepared;
const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");

pub const OverlapTarget = struct {
    tile: rops.ActiveTile,
    overlap: rops.OverlapBBox,
};

pub const SubpxDomain = struct {
    step: f64,
    offset: f64,
    tile_size: usize,
    x_off: f64,
    y_off: f64,
};

pub const RasterBounds = struct {
    start_x_u: usize,
    end_x_u: usize,
    start_y_u: usize,
    end_y_u: usize,
    x_min_f: f64,
    y_min_f: f64,
};

pub const ScratchLayout = enum {
    subpx_major,
    field_major,
};

pub fn rasterSceneCommon(
    comptime Backend: type,
    comptime report_mode: ReportMode,
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    ctx_rast: rops.RasterContext,
    ctx_report: report.ReportContext(report_mode),
    tiling: rops.TilingOverlaps,
    meshes: []const MeshPrepared,
    raster_hulls: []const ?NDArray(f64),
    image_out_arr: *NDArray(f64),
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    std.debug.assert(image_out_arr.dims[0] <= std.math.maxInt(u8));
    const fields_num: u8 = @intCast(image_out_arr.dims[0]);

    const sub_samp: usize = @intCast(ctx_rast.camera.sub_sample);
    const subpx_tile_size: usize = @as(usize, @intCast(ctx_rast.tile_size)) * sub_samp;
    var subpx_scratch = try Backend.initSubpxScratch(
        arena_alloc,
        fields_num,
        subpx_tile_size,
    );

    for (tiling.active_tiles) |tile| {
        const tile_start = if (comptime report_mode == .full_stats)
            Timestamp.now(io, .awake)
        else {};

        var shaded_px: u64 = 0;
        Backend.resetSubpxScratch(&subpx_scratch, subpx_tile_size);

        const overlap_start = tile.overlap_start;
        const overlap_end = overlap_start + tile.overlap_count;
        const overlaps = tiling.overlaps[overlap_start..overlap_end];

        for (overlaps) |ov| {
            const mesh_ptr = &meshes[ov.mesh_idx];
            const targ_overlap = OverlapTarget{ .tile = tile, .overlap = ov };

            std.debug.assert(ov.mesh_idx < raster_hulls.len);
            const mesh_in = rops.MeshInput{
                .coords = &mesh_ptr.coords,
                .hull = if (raster_hulls[ov.mesh_idx]) |*h| h else null,
            };

            switch (mesh_ptr.mesh_type) {
                inline else => |geom_tag| {
                    const GK = comptime switch (geom_tag) {
                        .tri3 => geomkerns.Tri3Kernel(),
                        .tri6 => geomkerns.Tri6Kernel(),
                        .quad4ibi => geomkerns.Quad4IBIKernel(),
                        .quad4newton => geomkerns.Quad4NewtonKernel(),
                        .quad8 => geomkerns.Quad89Kernel(8),
                        .quad9 => geomkerns.Quad89Kernel(9),
                    };
                    const N = GK.nodes_num;

                    const mesh_fields_num: u8 = switch (mesh_ptr.shader) {
                        .nodal => |s| @intCast(s.elem_field.dims[2]),
                        .tex_u8, .tex_u16 => 1,
                        .tex_rgb_u8, .tex_rgb_u16 => 3,
                    };

                    switch (mesh_ptr.shader) {
                        .nodal => |*shader| {
                            const SK = shadekerns.NodalKernel(N);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};

                            const tt = @min(
                                ctx_rast.frame_idx,
                                shader.elem_field.dims[0] - 1,
                            );
                            const start_idx = shader.elem_field.getFlatInd(
                                &[_]usize{ tt, targ_overlap.overlap.elem_idx, 0, 0 },
                            );

                            local_shader_buf.load(
                                shader.elem_field,
                                start_idx,
                                mesh_fields_num,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }

                            shaded_px += try Backend.RasterPass(
                                GK,
                                SK,
                                NodalPrepared,
                            ).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                &subpx_scratch,
                            );
                        },
                        .tex_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 1);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }

                            shaded_px += try Backend.RasterPass(
                                GK,
                                SK,
                                TexPrepared(u8, 1),
                            ).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                &subpx_scratch,
                            );
                        },
                        .tex_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 1);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }

                            shaded_px += try Backend.RasterPass(
                                GK,
                                SK,
                                TexPrepared(u16, 1),
                            ).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                &subpx_scratch,
                            );
                        },
                        .tex_rgb_u8 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u8, 3);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }

                            shaded_px += try Backend.RasterPass(
                                GK,
                                SK,
                                TexPrepared(u8, 3),
                            ).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                &subpx_scratch,
                            );
                        },
                        .tex_rgb_u16 => |*shader| {
                            const SK = shadekerns.TexKernel(N, u16, 3);
                            var local_shader_buf: shaderops.LocalShaderBuffer(N) = .{};
                            local_shader_buf.load(
                                shader.elem_uvs,
                                targ_overlap.overlap.elem_idx * 2 * N,
                                2,
                            );
                            if (shader.elem_normals) |en| {
                                const prep_idx = en.map[targ_overlap.overlap.elem_idx];
                                local_shader_buf.loadNormals(en.array, prep_idx * 3 * N);
                            }

                            shaded_px += try Backend.RasterPass(
                                GK,
                                SK,
                                TexPrepared(u16, 3),
                            ).render(
                                report_mode,
                                ctx_rast,
                                ctx_report,
                                targ_overlap,
                                mesh_in,
                                shader,
                                &local_shader_buf,
                                &subpx_scratch,
                            );
                        },
                    }
                },
            }
        }

        if (sub_samp > 1) {
            averageScratch(
                Backend.scratch_layout,
                tile,
                @intCast(sub_samp),
                subpx_tile_size,
                fields_num,
                &subpx_scratch.image,
                subpx_scratch.touched_min_x,
                subpx_scratch.touched_max_x,
                image_out_arr,
            );
        } else {
            resolveScratchDirect(
                Backend.scratch_layout,
                tile,
                subpx_tile_size,
                fields_num,
                &subpx_scratch.image,
                image_out_arr,
            );
        }

        const tile_end = if (comptime report_mode == .full_stats)
            Timestamp.now(io, .awake)
        else {};
        const tile_duration_ns = if (comptime report_mode == .full_stats)
            tile_start.durationTo(tile_end).raw.nanoseconds
        else
            0;
        const screen_px_x = @as(u16, @intCast(ctx_rast.camera.pixels_num[0]));
        const tiles_x = (screen_px_x + ctx_rast.tile_size - 1) / ctx_rast.tile_size;
        const spatial_idx = (tile.y_px_min / ctx_rast.tile_size) * tiles_x +
            (tile.x_px_min / ctx_rast.tile_size);
        ctx_report.recordTile(
            spatial_idx,
            @intCast(tile_duration_ns),
            shaded_px,
            overlaps.len,
        );
    }
}

pub inline fn getScratchField(
    comptime scratch_layout: ScratchLayout,
    spx_image_scratch: *const MatSlice(f64),
    scratch_flat_idx: usize,
    field_idx: usize,
) f64 {
    return switch (scratch_layout) {
        .subpx_major => spx_image_scratch.get(scratch_flat_idx, field_idx),
        .field_major => spx_image_scratch.get(field_idx, scratch_flat_idx),
    };
}

pub fn resolveScratchDirect(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const scratch_row_offset = ty * spx_tile_size;

        for (0..curr_tile_size_x) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const scratch_flat_idx = scratch_row_offset + tx;

            if (fields_num == 1) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
            } else if (fields_num == 3) {
                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        0,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        1,
                    ),
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    getScratchField(
                        scratch_layout,
                        spx_image_scratch,
                        scratch_flat_idx,
                        2,
                    ),
                );
            } else {
                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            ff,
                        ),
                    );
                }
            }
        }
    }
}

pub fn averageScratch(
    comptime scratch_layout: ScratchLayout,
    tile: rops.ActiveTile,
    sub_samp: usize,
    spx_tile_size: usize,
    fields_num: u8,
    spx_image_scratch: *const MatSlice(f64),
    touched_min_x: []const usize,
    touched_max_x: []const usize,
    image_out_arr: *NDArray(f64),
) void {
    const curr_tile_size_x: usize = tile.x_px_max - tile.x_px_min;
    const curr_tile_size_y: usize = tile.y_px_max - tile.y_px_min;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const inv_sub_samp_sq = 1.0 / (sub_samp_f * sub_samp_f);
    var field_avg_buff = [_]f64{0.0} ** cfg.max_nodal_fields;
    const spx_field_avg = field_avg_buff[0..@as(usize, fields_num)];

    for (0..curr_tile_size_y) |ty| {
        const image_px_y: usize = tile.y_px_min + ty;
        const spx_start_y: usize = sub_samp * ty;
        var touched_min_px_x = curr_tile_size_x;
        var touched_max_px_x: usize = 0;

        for (0..sub_samp) |sy| {
            const scratch_y = spx_start_y + sy;
            const row_min_x = touched_min_x[scratch_y];
            const row_max_x = touched_max_x[scratch_y];

            if (row_min_x <= row_max_x) {
                const row_min_px_x = row_min_x / sub_samp;
                const row_max_px_x = row_max_x / sub_samp;
                if (row_min_px_x < touched_min_px_x) {
                    touched_min_px_x = row_min_px_x;
                }
                if (row_max_px_x > touched_max_px_x) {
                    touched_max_px_x = row_max_px_x;
                }
            }
        }

        if (touched_min_px_x > touched_max_px_x) {
            continue;
        }

        for (touched_min_px_x..@min(curr_tile_size_x, touched_max_px_x + 1)) |tx| {
            const image_px_x: usize = tile.x_px_min + tx;
            const spx_start_x: usize = sub_samp * tx;

            if (fields_num == 1) {
                var field_sum_0: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                    }
                }

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
            } else if (fields_num == 3) {
                var field_sum_0: f64 = 0.0;
                var field_sum_1: f64 = 0.0;
                var field_sum_2: f64 = 0.0;

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;
                        field_sum_0 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            0,
                        );
                        field_sum_1 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            1,
                        );
                        field_sum_2 += getScratchField(
                            scratch_layout,
                            spx_image_scratch,
                            scratch_flat_idx,
                            2,
                        );
                    }
                }

                image_out_arr.set(
                    &[_]usize{ 0, image_px_y, image_px_x },
                    field_sum_0 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 1, image_px_y, image_px_x },
                    field_sum_1 * inv_sub_samp_sq,
                );
                image_out_arr.set(
                    &[_]usize{ 2, image_px_y, image_px_x },
                    field_sum_2 * inv_sub_samp_sq,
                );
            } else {
                @memset(spx_field_avg, 0.0);

                for (0..sub_samp) |sy| {
                    const scratch_row_offset: usize = (spx_start_y + sy) * spx_tile_size;

                    for (0..sub_samp) |sx| {
                        const scratch_flat_idx: usize =
                            scratch_row_offset + spx_start_x + sx;

                        for (0..@as(usize, fields_num)) |ff| {
                            spx_field_avg[ff] += getScratchField(
                                scratch_layout,
                                spx_image_scratch,
                                scratch_flat_idx,
                                ff,
                            );
                        }
                    }
                }

                for (0..@as(usize, fields_num)) |ff| {
                    image_out_arr.set(
                        &[_]usize{ ff, image_px_y, image_px_x },
                        spx_field_avg[ff] * inv_sub_samp_sq,
                    );
                }
            }
        }
    }
}
