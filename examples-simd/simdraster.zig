const std = @import("std");
const print = std.debug.print;
const time = std.time;

const vecstack = @import("vecstack.zig");
const Vec3T = @import("vecstack.zig").Vec3T;
const Vec3SliceOps = @import("vecstack.zig").Vec3SliceOps;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

pub fn countElemsCalcBBoxes(camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            elem_bboxes: []BBox) !usize {
    const N: usize = 3;
    const area_tol: f64 = 1e-9;
    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_rast: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
        );

        const x_max = std.mem.max(f64, coords_rast.x);
        const x_min = std.mem.min(f64, coords_rast.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        const y_max = std.mem.max(f64, coords_rast.y);
        const y_min = std.mem.min(f64, coords_rast.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }

        const area = rops.edgeFun3Slices(0, 1, 2, coords_rast.x, coords_rast.y);
        if (area < area_tol) continue;

        elem_bboxes[elems_in_image] = BBox{
            .elem_ind = ee,
            .x_min = rops.boundIndMin(u16, x_min),
            .x_max = rops.boundIndMax(u16, x_max, @intCast(camera.pixels_num[0])),
            .y_min = rops.boundIndMin(u16, y_min),
            .y_max = rops.boundIndMax(u16, y_max, @intCast(camera.pixels_num[1])),
        };
        elems_in_image += 1;
    }
    return elems_in_image;
}

pub fn rasterElems(allocator: std.mem.Allocator,
                   camera: *const Camera,
                   tile_size: u16,
                   active_tiles: []ActiveTile,
                   overlap_bboxes: []BBox,
                   elem_coord_arr: *const NDArray(f64),
                   elem_field_arr: *const NDArray(f64),
                   image_out_arr: *NDArray(f64)) !void {

    @setFloatMode(.optimized);
    const N: usize = 3;
    const fields_num = elem_field_arr.dims[1];
    const sub_samp = @as(usize, @intCast(camera.sub_sample));
    const spx_tile_size = tile_size * sub_samp;
    const spx_tile_total = spx_tile_size * spx_tile_size;
    const sub_samp_f = @as(f64, @floatFromInt(sub_samp));
    const spx_step = 1.0 / sub_samp_f;
    const spx_offset = 1.0 / (2.0 * sub_samp_f);

    const v_len = 8;
    const spx_inv_z_scratch = try allocator.alignedAlloc(
        f64, std.mem.Alignment.fromByteUnits(64), spx_tile_total,
    );
    const spx_image_scratch_mem = try allocator.alignedAlloc(
        f64, std.mem.Alignment.fromByteUnits(64), fields_num * spx_tile_total,
    );
    const f_inv_z_scaled_buffer = try allocator.alignedAlloc(
        f64, std.mem.Alignment.fromByteUnits(64), fields_num * N,
    );
    const field_node_term_splats = try allocator.alloc(@Vector(v_len, f64), fields_num * N);

    const v_zero = @as(@Vector(v_len, f64), @splat(0.0));
    const v_one = @as(@Vector(v_len, f64), @splat(1.0));
    const v_offsets = @Vector(v_len, f64){ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0 };

    const screen_w = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_h = @as(u16, @intCast(camera.pixels_num[1]));
    const img_stride_field = image_out_arr.strides[0];
    const img_stride_y = image_out_arr.strides[1];

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch_mem, 0.0);

        const overlaps = overlap_bboxes[
            tile.overlap_start .. tile.overlap_start + tile.overlap_count
        ];
        var nodes_inv_z: [N]f64 = undefined;
        
        for (overlaps) |overlap| {
            const nodes_rast = try rops.loadVec3SlicesFromElemArray(
                N, f64, elem_coord_arr, overlap.elem_ind,
            );
            inline for (0..N) |nn| nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            const inv_area = 1.0 / rops.edgeFun3(
                nodes_rast.x[0], nodes_rast.y[0], 
                nodes_rast.x[1], nodes_rast.y[1], 
                nodes_rast.x[2], nodes_rast.y[2],
            );

            for (0..fields_num) |ff| {
                const b_off = ff * N;
                inline for (0..N) |nn| {
                    const inds = [_]usize{ overlap.elem_ind, ff, nn };
                    const term = elem_field_arr.get(inds[0..]) * nodes_inv_z[nn] * inv_area;
                    f_inv_z_scaled_buffer[b_off + nn] = term;
                    field_node_term_splats[b_off + nn] = @as(
                        @Vector(v_len, f64), @splat(term),
                    );
                }
            }

            const s_idx_x = sub_samp * (@as(usize, overlap.x_min) - tile.x_px_min);  
            const e_idx_x = sub_samp * (@as(usize, overlap.x_max) - tile.x_px_min);
            const s_idx_y = sub_samp * (@as(usize, overlap.y_min) - tile.y_px_min);  
            const e_idx_y = sub_samp * (@as(usize, overlap.y_max) - tile.y_px_min);

            const start_x = @as(f64, @floatFromInt(overlap.x_min)) + spx_offset;
            const start_y = @as(f64, @floatFromInt(overlap.y_min)) + spx_offset;

            const dw0_dy = (nodes_rast.x[1] - nodes_rast.x[2]) * spx_step;
            const dw1_dy = (nodes_rast.x[2] - nodes_rast.x[0]) * spx_step;
            const dw2_dy = (nodes_rast.x[0] - nodes_rast.x[1]) * spx_step;

            const dw0_dx = (nodes_rast.y[2] - nodes_rast.y[1]) * spx_step;
            const dw1_dx = (nodes_rast.y[0] - nodes_rast.y[2]) * spx_step;
            const dw2_dx = (nodes_rast.y[1] - nodes_rast.y[0]) * spx_step;

            var w0_row = rops.edgeFun3(nodes_rast.x[1], nodes_rast.y[1], 
                                       nodes_rast.x[2], nodes_rast.y[2], start_x, start_y);
            var w1_row = rops.edgeFun3(nodes_rast.x[2], nodes_rast.y[2], 
                                       nodes_rast.x[0], nodes_rast.y[0], start_x, start_y);
            var w2_row = rops.edgeFun3(nodes_rast.x[0], nodes_rast.y[0], 
                                       nodes_rast.x[1], nodes_rast.y[1], start_x, start_y);

            const v_dw0_dx_v = @as(@Vector(v_len, f64), @splat(dw0_dx)) * v_offsets;
            const v_dw1_dx_v = @as(@Vector(v_len, f64), @splat(dw1_dx)) * v_offsets;
            const v_dw2_dx_v = @as(@Vector(v_len, f64), @splat(dw2_dx)) * v_offsets;

            const v_dw0_step = @as(
                @Vector(v_len, f64), @splat(dw0_dx * @as(f64, @floatFromInt(v_len))),
            );
            const v_dw1_step = @as(
                @Vector(v_len, f64), @splat(dw1_dx * @as(f64, @floatFromInt(v_len))),
            );
            const v_dw2_step = @as(
                @Vector(v_len, f64), @splat(dw2_dx * @as(f64, @floatFromInt(v_len))),
            );
            
            const v_n_inv_z0 = @as(@Vector(v_len, f64), @splat(nodes_inv_z[0] * inv_area));
            const v_n_inv_z1 = @as(@Vector(v_len, f64), @splat(nodes_inv_z[1] * inv_area));
            const v_n_inv_z2 = @as(@Vector(v_len, f64), @splat(nodes_inv_z[2] * inv_area));

            for (s_idx_y..e_idx_y) |yy| {
                const row_off = yy * spx_tile_size;
                var v_w0 = @as(@Vector(v_len, f64), @splat(w0_row)) + v_dw0_dx_v;
                var v_w1 = @as(@Vector(v_len, f64), @splat(w1_row)) + v_dw1_dx_v;
                var v_w2 = @as(@Vector(v_len, f64), @splat(w2_row)) + v_dw2_dx_v;
                
                var xx = s_idx_x;
                while (xx + v_len <= e_idx_x) : (xx += v_len) {
                    const mask = (v_w0 >= v_zero) & (v_w1 >= v_zero) & (v_w2 >= v_zero);
                    if (@reduce(.Or, mask)) {
                        const v_inv_z = v_w0 * v_n_inv_z0 + 
                                        v_w1 * v_n_inv_z1 + 
                                        v_w2 * v_n_inv_z2;
                        const v_old_z = @as(
                            @Vector(v_len, f64),
                            spx_inv_z_scratch[row_off + xx ..][0..v_len].*,
                        );
                        const final_mask = mask & (v_inv_z > v_old_z);

                        if (@reduce(.Or, final_mask)) {
                            spx_inv_z_scratch[row_off + xx ..][0..v_len].* = @select(
                                f64, final_mask, v_inv_z, v_old_z,
                            );
                            const v_spx_z = v_one / v_inv_z;
                            for (0..fields_num) |ff| {
                                const b_off = ff * N;
                                var v_f = v_w0 * field_node_term_splats[b_off + 0];
                                v_f += v_w1 * field_node_term_splats[b_off + 1];
                                v_f += v_w2 * field_node_term_splats[b_off + 2];
                                v_f *= v_spx_z;

                                const f_off = ff * spx_tile_total + row_off + xx;
                                const v_old_f = @as(
                                    @Vector(v_len, f64),
                                    spx_image_scratch_mem[f_off ..][0..v_len].*,
                                );
                                spx_image_scratch_mem[f_off ..][0..v_len].* = @select(
                                    f64, final_mask, v_f, v_old_f,
                                );
                            }
                        }
                    }
                    v_w0 += v_dw0_step; v_w1 += v_dw1_step; v_w2 += v_dw2_step;
                }
                var w0 = v_w0[0]; var w1 = v_w1[0]; var w2 = v_w2[0];
                const node_inv_z0_area = nodes_inv_z[0] * inv_area;
                const node_inv_z1_area = nodes_inv_z[1] * inv_area;
                const node_inv_z2_area = nodes_inv_z[2] * inv_area;
                while (xx < e_idx_x) : (xx += 1) {
                    if (w0 >= 0.0 and w1 >= 0.0 and w2 >= 0.0) {
                        const inv_z = w0 * node_inv_z0_area + 
                                      w1 * node_inv_z1_area + 
                                      w2 * node_inv_z2_area;
                        if (inv_z > spx_inv_z_scratch[row_off + xx]) {
                            spx_inv_z_scratch[row_off + xx] = inv_z;
                            const z = 1.0 / inv_z;
                            for (0..fields_num) |ff| {
                                const b_off = ff * N;
                                const f_val = (w0 * f_inv_z_scaled_buffer[b_off + 0] + 
                                               w1 * f_inv_z_scaled_buffer[b_off + 1] + 
                                               w2 * f_inv_z_scaled_buffer[b_off + 2]) * z;
                                spx_image_scratch_mem[
                                    ff * spx_tile_total + row_off + xx
                                ] = f_val;
                            }
                        }
                    }
                    w0 += dw0_dx; w1 += dw1_dx; w2 += dw2_dx;
                }
                w0_row += dw0_dy; w1_row += dw1_dy; w2_row += dw2_dy;
            }
        }

        const spx_image_scratch = MatSlice(f64).init(spx_image_scratch_mem, 
                                                     spx_tile_total, fields_num);
        const spx_field_avg = try allocator.alloc(f64, fields_num);
        defer allocator.free(spx_field_avg);
        
        rops.averageScratch(tile, tile_size, screen_w, screen_h, sub_samp, 
                            spx_tile_size, fields_num, 
                            &spx_image_scratch, spx_field_avg, image_out_arr);
    }   
}

pub fn rasterFrame(allocator: std.mem.Allocator,
                   io: std.Io,
                   frame_ind: usize,
                   coords: *const Coords,
                   connect: *const Connect,
                   field: *const Field,
                   camera: *const Camera,
                   image_out_arr: *NDArray(f64)) !void {

    const raster_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_start = std.Io.Clock.Timestamp.now(io, .awake);
    var time_end = std.Io.Clock.Timestamp.now(io, .awake);

    //-----------------------------------------------------------------------------------------
    // CONSTANTS
    const N: usize = 3;
    const elems_num = connect.elem_n;
    const nodes_per_elem = connect.nodes_per_elem;
    const coords_num: usize = 3;
    const fields_num = field.getFieldsN();

    const dim_elem: usize = 0;
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    const screen_px_x = @as(u16, @intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16, @intCast(camera.pixels_num[1]));

    const tile_size: u16 = 32;
    const tiles_num_x = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const tiles_num_y = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);
    const tiles_num = tiles_num_x * tiles_num_y;

    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // 0. Element Data Pre-Transform
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    var elem_coord_arr = try rops.initElemArray(f64, arena_alloc, elems_num, 
                                                coords_num, nodes_per_elem);
    var elem_field_arr = try rops.initElemArray(f64, arena_alloc, elems_num, 
                                                fields_num, nodes_per_elem);

    rops.fillElemCoords(coords, connect, dim_elem, dim_node, dim_field, &elem_coord_arr);
    rops.fillElemFields(connect, field, frame_ind, dim_elem, dim_node, dim_field, 
                        &elem_field_arr);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time0_data_transform: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tilin Raster Step 1: World to Camera/Raster Coords - SIMD
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    try rops.transformElemsToRasterSIMD(N, f64, camera, dim_elem, &elem_coord_arr);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time1_world_to_raster: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 2: Calculate Element Bounding Boxes
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const elem_bboxes = try arena_alloc.alloc(BBox, elems_num);
    const elems_in_image = try countElemsCalcBBoxes(camera, dim_elem, &elem_coord_arr, 
                                                    elem_bboxes);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time2_elem_bboxes_crop: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 3: Element Tile Overlap - COUNT only
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const tile_elem_counts = try arena_alloc.alloc(usize, tiles_num);
    @memset(tile_elem_counts, 0);
    const tile_write_inds = try arena_alloc.alloc(usize, tiles_num);

    const num_active_tiles = try rops.elemTileOverlapCount(tile_size, tiles_num_x, 
        elems_in_image, elem_bboxes, tile_elem_counts, tile_write_inds);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time3_elem_tile_overlap_count: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 4: Element Tile Overlap Store overlap boxes for ACTIVE tiles
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    const overlap_total = sliceops.sum(usize, tile_elem_counts);
    const overlap_bboxes = try arena_alloc.alloc(BBox, overlap_total);
    const active_tiles = try arena_alloc.alloc(ActiveTile, num_active_tiles);

    rops.storeActiveTiles(tile_size, tiles_num_x, tiles_num_y, screen_px_x, screen_px_y, 
        elems_in_image, elem_bboxes, tile_elem_counts, tile_write_inds, overlap_bboxes, 
        active_tiles);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time4_elem_tile_overlap_store: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    // Tiling Raster Step 5: Main Raster Loop
    time_start = std.Io.Clock.Timestamp.now(io, .awake);

    try rasterElems(arena_alloc, camera, tile_size, active_tiles, overlap_bboxes, 
                    &elem_coord_arr, &elem_field_arr, image_out_arr);

    time_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time5_raster_loop: f64 = @floatFromInt(time_start.durationTo(time_end).raw.nanoseconds);

    //-----------------------------------------------------------------------------------------
    const raster_end = std.Io.Clock.Timestamp.now(io, .awake);
    const time_raster_all: f64 = @floatFromInt(raster_start.durationTo(raster_end).raw.nanoseconds);

    var total_px: f64 = @as(f64, @floatFromInt(camera.pixels_num[0] * camera.pixels_num[1]));
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    total_px = total_px * sub_samp_f * sub_samp_f;
    const mega_ops_per_sec: f64 = 1.0e3 * total_px / time_raster_all;
    const mega_tris_per_sec: f64 = 1.0e3 * @as(f64, @floatFromInt(connect.elem_n)) / 
                                   time_raster_all;

    const conv_units: f64 = 1.0 / 1.0e6;
    const print_break = [_]u8{'='} ** 80;
    print("\n{s}\nSoftware Raster Times\n{s}\n", .{ print_break, print_break });
    print("Data transform          = {d:.6} ms\n", .{ time0_data_transform * conv_units });
    print("World to raster         = {d:.6} ms\n", .{ time1_world_to_raster * conv_units });
    print("Elem bbox crop          = {d:.6} ms\n", .{ time2_elem_bboxes_crop * conv_units });
    print("Elem tile overlap count = {d:.6} ms\n", .{ time3_elem_tile_overlap_count * conv_units });
    print("Elem tile overlap store = {d:.6} ms\n", .{ time4_elem_tile_overlap_store * conv_units });
    print("Raster loop time        = {d:.6} ms\n", .{ time5_raster_loop * conv_units });
    print("{s}\nTOTAL RASTER TIME  = {d:.3} ms\n", .{ print_break, time_raster_all * conv_units });
    print("{s}\n", .{ print_break });
    print("Total Ops   = {d}\n", .{ total_px });
    print("MOps/second = {d:.2}\n", .{ mega_ops_per_sec });
    print("MTri/second = {d:.2}\n", .{ mega_tris_per_sec });
    print("{s}\n", .{ print_break });
}
