const std = @import("std");
const print = std.debug.print;
const time = std.time;

const Camera = @import("camera.zig").Camera;

const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const rops = @import("rasterops.zig");
const BBox = rops.BBox;
const ActiveTile = rops.ActiveTile;
const Vec3OfSlices = rops.Vec3OfSlices;

const ti = @import("textureinterp.zig");
const mr = @import("meshraster.zig");
const FlatShader = mr.FlatShader;
const TexShader = mr.TexShader;

pub fn transformElemsToRasterSIMD(comptime N: usize,
                                  comptime T: type,
                                  camera: *const Camera, 
                                  dim_elem: usize,  
                                  elem_coord_arr: *NDArray(T)) !void {

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_world: Vec3SIMD(N,T) = try vsd.loadVec3SIMDFromElemArray(
            N,T,elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,T) = rops.worldToRasterSIMD(
            N,T,coords_world,camera); 

        try vsd.saveVec3SIMDToElemArray(N,T,elem_coord_arr,ee,coords_raster);
    }
}

pub fn countElemsCalcBBoxes(camera: *const Camera,
                            dim_elem: usize,
                            elem_coord_arr: *const NDArray(f64),
                            elem_bboxes: []BBox) !usize {

    const N: usize = 3;
    const area_tol: f64 = -1e-9;
    
    var elems_in_image: usize = 0;

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const coords_raster: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N,f64,elem_coord_arr,ee
        );

        // Width (X) on screen check and crop
        const x_max: f64 = std.mem.max(f64,coords_raster.x);
        const x_min: f64 = std.mem.min(f64,coords_raster.x);
        if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
            continue;
        }

        // Height (Y) on on screen check and crop
        const y_max: f64 = std.mem.max(f64,coords_raster.y);
        const y_min: f64 = std.mem.min(f64,coords_raster.y);
        if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
            continue;
        }

        // Backface culling, negative area = crop for linear triangles
        const elem_area: f64 = rops.edgeFun3Slices(0,1,2,coords_raster.x,coords_raster.y);
        
        if (elem_area < area_tol) {
            continue;
        }
        
        const x_min_i: u16 = rops.boundIndMin(u16,x_min);
        const x_max_i: u16 = rops.boundIndMax(u16,
                                              x_max, 
                                              @intCast(camera.pixels_num[0]));
        const y_min_i: u16 = rops.boundIndMin(u16,y_min);
        const y_max_i: u16 = rops.boundIndMax(u16,
                                              y_max, 
                                              @intCast(camera.pixels_num[1]));

        elem_bboxes[elems_in_image] = BBox{
            .elem_ind = ee,
            .x_min = x_min_i,
            .x_max = x_max_i,
            .y_min = y_min_i,
            .y_max = y_max_i,
        };
        elems_in_image += 1;
    }

    return elems_in_image;
}

pub fn rasterElemsFlat(allocator: std.mem.Allocator,
                       camera: *const Camera,
                       frame_ind: usize,
                       tile_size: u16,
                       active_tiles: []ActiveTile,
                       overlap_bboxes: []BBox,
                       elem_coord_arr: *const NDArray(f64),
                       shader: *const FlatShader,
                       image_out_arr: *NDArray(f64),) !void {

    @setFloatMode(.optimized);

    const N: usize = 3;
    const F: usize = 3;

    const elem_field_arr = shader.field;
    const fields_num: usize = elem_field_arr.dims[2];

    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = tile_size * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;
    
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    
    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_total);
    defer allocator.free(spx_inv_z_scratch);

    const spx_image_scratch_mem = try allocator.alloc(f64, spx_tile_total*fields_num); 
    defer allocator.free(spx_image_scratch_mem);
    var spx_image_scratch = MatSlice(f64).init(spx_image_scratch_mem,
                                               spx_tile_total,
                                               fields_num);

    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
                                                tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        
        for (overlaps) |ol| {
            const nodes_rast: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N,f64,elem_coord_arr,ol.elem_ind
            );

            for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            }

            const area = rops.edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
                                       nodes_rast.x[1],nodes_rast.y[1],
                                       nodes_rast.x[2],nodes_rast.y[2]);
            if (@abs(area) < 1e-12) continue;
            const inv_elem_area: f64 = 1.0 / area;

            const s_start_x = sub_samp * (@as(usize,ol.x_min) - tile.x_px_min);  
            const s_end_x   = sub_samp * (@as(usize,ol.x_max) - tile.x_px_min);
            const s_start_y = sub_samp * (@as(usize,ol.y_min) - tile.y_px_min);  
            const s_end_y   = sub_samp * (@as(usize,ol.y_max) - tile.y_px_min);

            const start_x = @as(f64, @floatFromInt(tile.x_px_min)) + 
                            (@as(f64, @floatFromInt(s_start_x)) + 0.5) * spx_step;
            const start_y = @as(f64, @floatFromInt(tile.y_px_min)) + 
                            (@as(f64, @floatFromInt(s_start_y)) + 0.5) * spx_step;

            const dw0_dx = (nodes_rast.y[2] - nodes_rast.y[1]) * spx_step * inv_elem_area;
            const dw1_dx = (nodes_rast.y[0] - nodes_rast.y[2]) * spx_step * inv_elem_area;
            const dw2_dx = (nodes_rast.y[1] - nodes_rast.y[0]) * spx_step * inv_elem_area;

            const dw0_dy = (nodes_rast.x[1] - nodes_rast.x[2]) * spx_step * inv_elem_area;
            const dw1_dy = (nodes_rast.x[2] - nodes_rast.x[0]) * spx_step * inv_elem_area;
            const dw2_dy = (nodes_rast.x[0] - nodes_rast.x[1]) * spx_step * inv_elem_area;

            var w0_row = rops.edgeFun3(nodes_rast.x[1], nodes_rast.y[1], 
                                       nodes_rast.x[2], nodes_rast.y[2], 
                                       start_x, start_y) * inv_elem_area;
            var w1_row = rops.edgeFun3(nodes_rast.x[2], nodes_rast.y[2], 
                                       nodes_rast.x[0], nodes_rast.y[0], 
                                       start_x, start_y) * inv_elem_area;
            var w2_row = rops.edgeFun3(nodes_rast.x[0], nodes_rast.y[0], 
                                       nodes_rast.x[1], nodes_rast.y[1], 
                                       start_x, start_y) * inv_elem_area;

            // Index into the NDArray manually for speed
            const elem_field_stride = elem_field_arr.strides[1];
            const ff_stride = elem_field_arr.strides[2];
            const frame_offset = frame_ind * elem_field_arr.strides[0];
            const elem_offset = frame_offset + ol.elem_ind * elem_field_stride;

            // Hoisted the nodal field values into a small array to keep in cache
            var field_div_z = [F][N]f64{ undefined, undefined, undefined }; // [field][node]
            const actual_fields = @min(fields_num, F);
            for (0..actual_fields) |ff| {
                const ff_offset = elem_offset + ff * ff_stride;
                inline for (0..N) |nn| {
                    field_div_z[ff][nn] = elem_field_arr.elems[ff_offset + nn] 
                                          * nodes_inv_z[nn];
                }
            }

            //--------------------------------------------------------------------------------
            // RASTER HOT LOOP
            for (s_start_y .. s_end_y) |yy| {
                const row_off = yy * spx_tile_size;
                var w0 = w0_row;
                var w1 = w1_row;
                var w2 = w2_row;
                
                for (s_start_x .. s_end_x) |xx| {
                    const eps = 1e-9;
                    if (w0 >= -eps and w1 >= -eps and w2 >= -eps) {
                        const idx = row_off + xx;
                        const inv_z = w0 * nodes_inv_z[0] 
                                    + w1 * nodes_inv_z[1] 
                                    + w2 * nodes_inv_z[2];

                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            const z = 1.0 / inv_z;
                            for (0..actual_fields) |ff| {
                                const val = (w0 * field_div_z[ff][0] 
                                           + w1 * field_div_z[ff][1] 
                                           + w2 * field_div_z[ff][2]) * z;
                                spx_image_scratch.set(idx, ff, val);
                            }                                
                        }
                    } 
                    w0 += dw0_dx;
                    w1 += dw1_dx;
                    w2 += dw2_dx;
                }
                w0_row += dw0_dy;
                w1_row += dw1_dy;
                w2_row += dw2_dy;
            } // LOOP subpx y    
        } // LOOP overlapping elems / boxes

        // Average scratch and push into main image buffer
        rops.averageScratch(tile, 
                            tile_size, 
                            screen_px_x, 
                            screen_px_y, 
                            sub_samp, 
                            spx_tile_size, 
                            fields_num, 
                            &spx_image_scratch, 
                            spx_field_avg, 
                            image_out_arr);    
    } // LOOP active tiles   
}

pub fn rasterElemsTex(comptime interp_type: ti.InterpType,
                      allocator: std.mem.Allocator,
                      camera: *const Camera,
                      tile_size: u16,
                      active_tiles: []ActiveTile,
                      overlap_bboxes: []BBox,
                      elem_coord_arr: *const NDArray(f64),
                      shader: *const TexShader,
                      image_out_arr: *NDArray(f64)) !void {

    @setFloatMode(.optimized);

    const N: usize = 3;
    const U: usize = 2;
    const fields_num: usize = 1;

    const screen_px_x = @as(u16,@intCast(camera.pixels_num[0]));
    const screen_px_y = @as(u16,@intCast(camera.pixels_num[1]));

    const sub_samp: usize = @intCast(camera.sub_sample);
    const spx_tile_size: usize = tile_size * sub_samp;
    const spx_tile_total: usize = spx_tile_size * spx_tile_size;
    
    const sub_samp_f: f64 = @as(f64, @floatFromInt(camera.sub_sample));
    const spx_step: f64 = 1.0 / sub_samp_f;
    
    const spx_inv_z_scratch = try allocator.alloc(f64, spx_tile_total);
    defer allocator.free(spx_inv_z_scratch);

    const spx_image_scratch_mem = try allocator.alloc(f64, spx_tile_total*fields_num); 
    defer allocator.free(spx_image_scratch_mem);
    var spx_image_scratch = MatSlice(f64).init(spx_image_scratch_mem,
                                               spx_tile_total,
                                               fields_num);

    const spx_field_avg = try allocator.alloc(f64, fields_num);
    defer allocator.free(spx_field_avg);

    for (active_tiles) |tile| {
        @memset(spx_inv_z_scratch, 0.0);
        @memset(spx_image_scratch.elems, 0.0);

        const overlaps: []BBox = overlap_bboxes[tile.overlap_start.. 
                                                tile.overlap_start + tile.overlap_count];

        var nodes_inv_z: [N]f64 = undefined;
        
        for (overlaps) |ol| {
            const nodes_rast: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
                N,f64,elem_coord_arr,ol.elem_ind
            );

            for (0..N) |nn| {
                nodes_inv_z[nn] = 1.0 / nodes_rast.z[nn];
            }

            const area = rops.edgeFun3(nodes_rast.x[0],nodes_rast.y[0],
                                       nodes_rast.x[1],nodes_rast.y[1],
                                       nodes_rast.x[2],nodes_rast.y[2]);
            if (@abs(area) < 1e-12) continue;
            const inv_elem_area: f64 = 1.0 / area;

            // Hoisted the nodal uv values into a small array to keep in cache
            const elem_uv_stride = shader.uvs.strides[0];
            const comp_uv_stride = shader.uvs.strides[1];
            const elem_uv_off = ol.elem_ind * elem_uv_stride;

            var uv_div_z = [U][N]f64{ undefined, undefined };
            inline for (0..U) |uu| {
                const uv_off = elem_uv_off + uu * comp_uv_stride;
                inline for (0..N) |nn| {
                    uv_div_z[uu][nn] = shader.uvs.elems[uv_off + nn] * nodes_inv_z[nn];
                }
            }

            const s_start_x = sub_samp * (@as(usize,ol.x_min) - tile.x_px_min);  
            const s_end_x   = sub_samp * (@as(usize,ol.x_max) - tile.x_px_min);
            const s_start_y = sub_samp * (@as(usize,ol.y_min) - tile.y_px_min);  
            const s_end_y   = sub_samp * (@as(usize,ol.y_max) - tile.y_px_min);

            const start_x = @as(f64, @floatFromInt(tile.x_px_min)) + 
                            (@as(f64, @floatFromInt(s_start_x)) + 0.5) * spx_step;
            const start_y = @as(f64, @floatFromInt(tile.y_px_min)) + 
                            (@as(f64, @floatFromInt(s_start_y)) + 0.5) * spx_step;

            const dw0_dx = (nodes_rast.y[2] - nodes_rast.y[1]) * spx_step * inv_elem_area;
            const dw1_dx = (nodes_rast.y[0] - nodes_rast.y[2]) * spx_step * inv_elem_area;
            const dw2_dx = (nodes_rast.y[1] - nodes_rast.y[0]) * spx_step * inv_elem_area;

            const dw0_dy = (nodes_rast.x[1] - nodes_rast.x[2]) * spx_step * inv_elem_area;
            const dw1_dy = (nodes_rast.x[2] - nodes_rast.x[0]) * spx_step * inv_elem_area;
            const dw2_dy = (nodes_rast.x[0] - nodes_rast.x[1]) * spx_step * inv_elem_area;

            var w0_row = rops.edgeFun3(nodes_rast.x[1], nodes_rast.y[1], 
                                       nodes_rast.x[2], nodes_rast.y[2], 
                                       start_x, start_y) * inv_elem_area;
            var w1_row = rops.edgeFun3(nodes_rast.x[2], nodes_rast.y[2], 
                                       nodes_rast.x[0], nodes_rast.y[0], 
                                       start_x, start_y) * inv_elem_area;
            var w2_row = rops.edgeFun3(nodes_rast.x[0], nodes_rast.y[0], 
                                       nodes_rast.x[1], nodes_rast.y[1], 
                                       start_x, start_y) * inv_elem_area;

            //--------------------------------------------------------------------------------
            // RASTER HOT LOOP
            for (s_start_y .. s_end_y) |yy| {
                const row_off = yy * spx_tile_size;
                var w0 = w0_row;
                var w1 = w1_row;
                var w2 = w2_row;
                
                for (s_start_x .. s_end_x) |xx| {
                    const eps = 1e-9;
                    if (w0 >= -eps and w1 >= -eps and w2 >= -eps) {
                        const idx = row_off + xx;
                        const inv_z = w0 * nodes_inv_z[0] 
                                    + w1 * nodes_inv_z[1] 
                                    + w2 * nodes_inv_z[2];

                        if (inv_z > spx_inv_z_scratch[idx]) {
                            spx_inv_z_scratch[idx] = inv_z;
                            const z = 1.0 / inv_z;
                            
                            const u_at = (w0 * uv_div_z[0][0] + 
                                          w1 * uv_div_z[0][1] + 
                                          w2 * uv_div_z[0][2]) * z;
                            const v_at = (w0 * uv_div_z[1][0] + 
                                          w1 * uv_div_z[1][1] + 
                                          w2 * uv_div_z[1][2]) * z;

                            const tex_at_spx = ti.sampleGreyscale(
                                interp_type, shader.texture, u_at, v_at,
                            );

                            spx_image_scratch.set(idx, 0, tex_at_spx);
                        }
                    } 
                    w0 += dw0_dx;
                    w1 += dw1_dx;
                    w2 += dw2_dx;
                }
                w0_row += dw0_dy;
                w1_row += dw1_dy;
                w2_row += dw2_dy;
            } // LOOP subpx y    
        } // LOOP overlapping elems / boxes

        // Average scratch and push into main image buffer
        rops.averageScratch(tile, 
                            tile_size, 
                            screen_px_x, 
                            screen_px_y, 
                            sub_samp, 
                            spx_tile_size, 
                            fields_num, 
                            &spx_image_scratch, 
                            spx_field_avg, 
                            image_out_arr);    
    } // LOOP active tiles   
}
