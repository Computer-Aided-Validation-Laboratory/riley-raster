const std = @import("std");
const Timestamp = std.Io.Clock.Timestamp;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const mr = @import("meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster;
const MeshTransform = mr.MeshTransform;
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;
const Shader = mr.Shader;

const iio = @import("imageio.zig");
const ImageFormat = iio.ImageFormat;
const imageops = @import("imageops.zig");

const geomkerns = @import("geometrykernels.zig");
const shadekerns = @import("shaderkernels.zig");
const rasterengine = @import("rasterengine.zig");

const perf = @import("perf.zig");
const Report = perf.Report;
const Perf = perf.Perf;
const PerfOpts = perf.PerfOpts;

pub const SaveOption = enum {
    disk,
    memory,
    both,
    none,
};

pub const RasterConfig = struct {
    threads_within_image: u16 = 0,
    threads_over_images: u16 = 0,
    save_opt: SaveOption = .disk,
    save_opts: []const iio.ImageSaveOpts = &[_]iio.ImageSaveOpts{
        .{ .format = .tiff, .bits = 8, .scaling = .none },
    },
    tile_size: u16 = 16,
    report: Report = .off,
    perf_opts: PerfOpts = .{},
};

// Represents an overlap of a specific element from a specific mesh onto a tile
pub const OverlapMM = struct {
    mesh_idx: u32,
    elem_idx: u32,
    bbox: BBox,
};

fn applyDispToMesh(
    outer_alloc: std.mem.Allocator,
    tt: usize,
    coords: *const MatSlice(f64),
    disp: *const NDArray(f64),
) !MatSlice(f64) {

    var coords_disp = try MatSlice(f64).initAlloc(
        outer_alloc, coords.rows_num, coords.cols_num
    );
    @memcpy(coords_disp.elems, coords.elems);

    const disp_frame_mem = disp.getSlice(&[_]usize{ tt, 0, 0 }, 0);
    var disp_frame = MatSlice(f64).init(disp_frame_mem, 
                                        disp.dims[1],
                                        disp.dims[2]);

    coords_disp.addInPlace(&disp_frame);

    return coords_disp;
}

pub fn rasterAllFrames(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    meshes: []const MeshRaster,
    config: RasterConfig,
    out_dir: ?std.Io.Dir,
) !?NDArray(f64) {

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const dim_time_pre: usize = 0;
    const dim_field_pre: usize = 2;

    // Work out max time across all meshes
    var num_time: usize = 1;
    for (meshes) |mesh| {
        if (mesh.disp) |field| {
            num_time = @max(num_time, field.array.dims[dim_time_pre]);
        } else if (mesh.shader == .flat) {
            num_time = @max(num_time, mesh.shader.flat.field.array.dims[dim_time_pre]);
        }
    }

    // For now we assume all meshes in scene have SAME number of fields
    var num_fields: usize = 0;
    for (meshes) |mesh| {
        const mesh_fields = switch (mesh.shader) {
            .flat => |f| f.field.array.dims[dim_field_pre],
            .tex_u8, .tex_u16 => 1,
        };
        num_fields = @max(num_fields, mesh_fields);
    }

    // Allocate NDArray if we are returning everything to the user in memory
    var images_arr: ?NDArray(f64) = null;
    if (config.save_opt == .memory or config.save_opt == .both) {
        const dims = [_]usize{
            num_time, num_fields, camera.pixels_num[1], camera.pixels_num[0]
        };
        images_arr = try NDArray(f64).initFlat(outer_alloc, dims[0..]);
    }

    var flat_global_scaling = try outer_alloc.alloc(?imageops.ScalingParams, meshes.len);
    defer outer_alloc.free(flat_global_scaling);
    for (meshes, 0..) |mesh, ii| {
        flat_global_scaling[ii] = null;
        if (mesh.shader == .flat) {
            if (mesh.shader.flat.scale_over == .over_frames) {
                flat_global_scaling[ii] = imageops.getScalingParamsNDArray(
                    &mesh.shader.flat.field.array, null, mesh.shader.flat.scaling
                );
            }
        }
    }

    for (0..num_time) |tt| {
        _ = arena.reset(.free_all);

        // Transform all meshes for this frame
        var transformed_meshes = try arena_alloc.alloc(MeshTransform, meshes.len);
        for (meshes, 0..) |mesh, ii| {
            var coords_to_trans: MatSlice(f64) = undefined;
            if (mesh.disp) |disp| {
                const frame_idx = @min(tt, disp.array.dims[dim_time_pre] - 1);
                coords_to_trans = try applyDispToMesh(
                    arena_alloc, frame_idx, &mesh.coords.mat, &disp.array
                );
            } else {
                coords_to_trans = MatSlice(f64).init(mesh.coords.mat.elems, 
                                                     mesh.coords.mat.rows_num,
                                                     mesh.coords.mat.cols_num);
            }

            var flat_frame_scaling: ?imageops.ScalingParams = null;
            if (mesh.shader == .flat) {
                if (mesh.shader.flat.scale_over == .over_frames) {
                    flat_frame_scaling = flat_global_scaling[ii];
                } else {
                    flat_frame_scaling = imageops.getScalingParamsNDArray(
                        &mesh.shader.flat.field.array, tt, mesh.shader.flat.scaling
                    );
                }
            }
            transformed_meshes[ii] = try mr.transformMesh(
                arena_alloc, &mesh, &coords_to_trans, flat_frame_scaling
            );
        }
        
        var frame_arr: NDArray(f64) = undefined;
        if (images_arr) |*ima| {
            const stride = ima.strides[0];
            const mem = ima.elems[tt * stride .. (tt + 1) * stride];
            frame_arr = try NDArray(f64).init(arena_alloc, mem, ima.dims[1..]);
        } else {
            const dims = [_]usize{ num_fields, camera.pixels_num[1], camera.pixels_num[0] };
            frame_arr = try NDArray(f64).initFlat(arena_alloc, dims[0..]);
        }
        @memset(frame_arr.elems, 0.0);

        var frame_perf: ?perf.Perf = null;
        if (config.report == .perf) {
            frame_perf = try perf.initFramePerf(
                outer_alloc,
                camera.pixels_num,
                config.tile_size,
                camera.sub_sample,
                config.perf_opts,
            );
        }
        defer if (frame_perf) |*fp| fp.deinit(outer_alloc);

        switch (config.report) {
            .off => try rasterSceneInternal(
                arena_alloc, io, camera, tt, transformed_meshes, &frame_arr, 
                config.tile_size, .off, null,
            ),
            .perf => try rasterSceneInternal(
                arena_alloc, io, camera, tt, transformed_meshes, &frame_arr, 
                config.tile_size, .perf, &frame_perf.?,
            ),
        }

        if (frame_perf) |*fp| {
            try fp.saveFrameReport(
                io, outer_alloc, out_dir, tt, camera, config.tile_size, config.perf_opts,
            );
        }

        if (config.save_opt == .disk or config.save_opt == .both) {
            try iio.saveImages(
                io, out_dir, tt, num_fields, camera.pixels_num, &frame_arr, 
                config.save_opts,
            );
        }
    }
    return images_arr;
}

fn rasterSceneInternal(
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    frame_ind: usize,
    meshes: []MeshTransform,
    image_out_arr: *NDArray(f64),
    tile_size: u16,
    comptime report: Report,
    perf_data: ?*Perf,
) !void {
    const raster_start = Timestamp.now(io, .awake);
    const pctx = perf.PerfContext(report){ .perf = if (report == .perf) perf_data.? else {} };
    var pipe_times = perf.PipeTimes{};

    const screen_px_x = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16, @intCast(camera.pixels_num[1]));

    const tiles_num_x: usize = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);
    const tiles_num: usize = tiles_num_x * tiles_num_y;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const time_start_internal = Timestamp.now(io, .awake);

    var raster_hulls = try arena_alloc.alloc(?NDArray(f64), meshes.len);
    for (0..meshes.len) |ii| raster_hulls[ii] = null;

    const time_end_internal = Timestamp.now(io, .awake);
    pipe_times.coord_transform = @floatFromInt(
        time_start_internal.durationTo(time_end_internal).raw.nanoseconds
    );

    const time_start_bbox = Timestamp.now(io, .awake);

    var elem_bboxes_by_mesh = try arena_alloc.alloc([]BBox, meshes.len);
    var elems_in_image_by_mesh = try arena_alloc.alloc(usize, meshes.len);
    var total_elems_in_image: usize = 0;
    var total_elems_num: usize = 0;

    for (meshes, 0..) |*mesh, ii| {
        const elems_num = mesh.coords.dims[0];
        total_elems_num += elems_num;
        elem_bboxes_by_mesh[ii] = try arena_alloc.alloc(BBox, elems_num);
        raster_hulls[ii] = null;
        
        switch (mesh.mesh_type) {
            inline else => |mesh_tag| {
                const GK = comptime switch (mesh_tag) {
                    .tri3 => geomkerns.Tri3Kernel(),
                    .tri3opt => geomkerns.Tri3OptKernel(),
                    .tri6 => geomkerns.Tri6Kernel(),
                    .quad4ibi => geomkerns.Quad4IBIKernel(),
                    .quad4newton => geomkerns.Quad4NewtonKernel(),
                    .quad8 => geomkerns.Quad89Kernel(8),
                    .quad9 => geomkerns.Quad89Kernel(9),
                };
                const N = GK.nodes_num;
                const NH = if (comptime GK.has_hull) GK.hull_nodes_num else 0;
                const dim_elem = 0;

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    try rops.transformElemsRasterSIMD(N, f64, camera, dim_elem, &mesh.coords);
                } else {
                    try rops.transformElemsClipPxLengSIMD(
                        N, f64, camera, dim_elem, &mesh.coords
                    );
                }

                if (comptime GK.has_hull) {
                    raster_hulls[ii] = try NDArray(f64).initFlat(
                        arena_alloc,
                        &[_]usize{ elems_num, 2, NH },
                    );
                    try rops.buildAdaptiveHulls(
                        N, camera, dim_elem, &mesh.coords, &raster_hulls[ii].?
                    );
                }

                if (comptime GK.coord_space == geomkerns.CoordSpace.raster) {
                    elems_in_image_by_mesh[ii] = try rops.countElemsCalcBBoxesTri3(
                        camera, dim_elem, &mesh.coords, elem_bboxes_by_mesh[ii],
                    );
                } else {
                    const rh_ptr = if (raster_hulls[ii]) |*rh| rh else null;
                    elems_in_image_by_mesh[ii] = try rops.countElemsCalcBBoxes(
                        N, NH, camera, dim_elem, &mesh.coords, rh_ptr, elem_bboxes_by_mesh[ii],
                    );
                }
            }
        }
        total_elems_in_image += elems_in_image_by_mesh[ii];
    }

    const time_end_bbox = Timestamp.now(io, .awake);
    pipe_times.bbox_calc = @floatFromInt(
        time_start_bbox.durationTo(time_end_bbox).raw.nanoseconds
    );

    if (comptime report == .perf) {
        pctx.recordGeometry(total_elems_num, total_elems_in_image);
    }

    const time_start_overlap = Timestamp.now(io, .awake);

    const tile_elem_counts = try arena_alloc.alloc(usize, tiles_num);
    @memset(tile_elem_counts, 0);
    const tile_write_inds = try arena_alloc.alloc(usize, tiles_num);

    for (meshes, 0..) |_, ii| {
        _ = try rops.elemTileOverlapCount(
            tile_size,
            tiles_num_x,
            elems_in_image_by_mesh[ii],
            elem_bboxes_by_mesh[ii],
            tile_elem_counts,
            tile_write_inds,
        );
    }
    
    const time_end_overlap = Timestamp.now(io, .awake);
    pipe_times.tile_count = @floatFromInt(
        time_start_overlap.durationTo(time_end_overlap).raw.nanoseconds
    );

    const time_start_store = Timestamp.now(io, .awake);

    const overlap_total: usize = sliceops.sum(usize, tile_elem_counts);
    const overlap_mms = try arena_alloc.alloc(OverlapMM, overlap_total);
    
    var num_active_tiles: usize = 0;
    for (tile_elem_counts) |count| {
        if (count > 0) num_active_tiles += 1;
    }
    const active_tiles = try arena_alloc.alloc(ActiveTile, num_active_tiles);

    try storeActiveTilesMM(
        tile_size,
        tiles_num_x,
        tiles_num_y,
        screen_px_x,
        screen_px_y,
        meshes,
        elems_in_image_by_mesh,
        elem_bboxes_by_mesh,
        tile_elem_counts,
        tile_write_inds,
        overlap_mms,
        active_tiles,
    );

    const time_end_store = Timestamp.now(io, .awake);
    pipe_times.tile_store = @floatFromInt(
        time_start_store.durationTo(time_end_store).raw.nanoseconds
    );

    const time_start_loop = Timestamp.now(io, .awake);

    try rasterengine.rasterScene(
        report,
        pctx,
        arena_alloc,
        io,
        camera,
        frame_ind,
        tile_size,
        active_tiles,
        overlap_mms,
        meshes,
        raster_hulls,
        image_out_arr,
    );
    
    const time_end_loop = Timestamp.now(io, .awake);
    pipe_times.raster_loop = @floatFromInt(
        time_start_loop.durationTo(time_end_loop).raw.nanoseconds
    );

    const raster_end = Timestamp.now(io, .awake);
    pipe_times.total_time = @floatFromInt(
        raster_start.durationTo(raster_end).raw.nanoseconds
    );

    if (report == .perf) {
        perf_data.?.pipe_times = pipe_times;
    }

    if (comptime report == .off) {
        try perf.standardReport(io, camera, pipe_times, total_elems_num);
    }
}

fn storeActiveTilesMM(
    tile_size: u16,
    tiles_num_x: usize,
    tiles_num_y: usize,
    screen_px_x: u16,
    screen_px_y: u16,
    meshes: []const MeshTransform,
    elems_in_image_by_mesh: []const usize,
    elem_bboxes_by_mesh: []const []BBox,
    tile_elem_counts: []const usize,
    tile_write_inds: []usize,
    overlap_mms: []OverlapMM,
    active_tiles: []ActiveTile,
) !void {
    _ = tiles_num_y;
    var current_off: usize = 0;
    for (0..tile_elem_counts.len) |ii| {
        tile_write_inds[ii] = current_off;
        current_off += tile_elem_counts[ii];
    }

    for (meshes, 0..) |_, mesh_idx| {
        for (0..elems_in_image_by_mesh[mesh_idx]) |elem_idx| {
            const bbox = elem_bboxes_by_mesh[mesh_idx][elem_idx];
            
            const tx_start = bbox.x_min / tile_size;
            const tx_end = @min(@as(usize, @intCast(tiles_num_x)), 
                                @as(usize, (bbox.x_max + tile_size - 1) / tile_size));
            const ty_start = bbox.y_min / tile_size;
            const ty_end = @min(@as(usize, @intCast(tile_elem_counts.len / tiles_num_x)), 
                                @as(usize, (bbox.y_max + tile_size - 1) / tile_size));

            for (ty_start..ty_end) |ty| {
                const tile_px_min_y = @as(u16, @intCast(ty * tile_size));
                const tile_px_max_y = @as(u16, @min(
                    @as(u32, tile_px_min_y) + tile_size, screen_px_y
                ));
                const overlap_y_min = @max(bbox.y_min, tile_px_min_y);
                const overlap_y_max = @min(bbox.y_max, tile_px_max_y);

                for (tx_start..tx_end) |tx| {
                    const tile_px_min_x = @as(u16, @intCast(tx * tile_size));
                    const tile_px_max_x = @as(u16, @min(
                        @as(u32, tile_px_min_x) + tile_size, screen_px_x
                    ));

                    const tile_idx = ty * tiles_num_x + tx;
                    const write_idx = tile_write_inds[tile_idx];
                    overlap_mms[write_idx] = .{
                        .mesh_idx = @intCast(mesh_idx),
                        .elem_idx = @intCast(elem_idx),
                        .bbox = BBox{
                            .elem_ind = bbox.elem_ind,
                            .x_min = @max(bbox.x_min, tile_px_min_x),
                            .x_max = @min(bbox.x_max, tile_px_max_x),
                            .y_min = overlap_y_min,
                            .y_max = overlap_y_max,
                        },
                    };
                    tile_write_inds[tile_idx] += 1;
                }
            }
        }
    }

    var active_idx: usize = 0;
    current_off = 0;
    for (0..tile_elem_counts.len) |ii| {
        const count = tile_elem_counts[ii];
        if (count > 0) {
            const tx = ii % tiles_num_x;
            const ty = ii / tiles_num_x;
            active_tiles[active_idx] = .{
                .overlap_start = current_off,
                .overlap_count = count,
                .x_px_min = @intCast(tx * tile_size),
                .y_px_min = @intCast(ty * tile_size),
                .x_px_max = @min(screen_px_x, @as(u16, @intCast((tx + 1) * tile_size))),
                .y_px_max = @min(screen_px_y, @as(u16, @intCast((ty + 1) * tile_size))),
            };
            active_idx += 1;
        }
        current_off += count;
    }
}
