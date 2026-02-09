// UPDATE: consistent with winding in existing rasteriser

// --- Raster Loop Pass 3: Consistent with (V2-V0) cross (V1-V0) winding ---

const aa_rate: usize = 4;
const sub_tile_size = tile_size * aa_rate;
const sub_tile_total = sub_tile_size * sub_tile_size;
const sub_step = 1.0 / @as(f64, @floatFromInt(aa_rate));

const sub_depth_buffer = try arena_alloc.alloc(f32, sub_tile_total);
const sub_color_buffer = try arena_alloc.alloc(f64, sub_tile_total);

for (active_tiles) |tile| {
    @memset(sub_depth_buffer, std.math.inf(f32));
    @memset(sub_color_buffer, 0.0);

    const overlaps = overlap_bboxes[tile.overlap_start .. tile.overlap_start + tile.overlap_count];

    for (overlaps) |ovl| {
        const coords = try vsd.loadVec3FromElemArray(3, f64, &elem_coord_arr, ovl.elem_ind);
        
        const x0 = coords.x[0]; const y0 = coords.y[0]; const z0 = coords.z[0];
        const x1 = coords.x[1]; const y1 = coords.y[1]; const z1 = coords.z[1];
        const x2 = coords.x[2]; const y2 = coords.y[2]; const z2 = coords.z[2];

        // --- BARYCENTRIC SETUP (Your Winding) ---
        // Area = (x2-x0)(y1-y0) - (y2-y0)(x1-x0)
        const area = (x2 - x0) * (y1 - y0) - (y2 - y0) * (x1 - x0);
        if (@abs(area) < 1e-9) continue; 
        const inv_area = 1.0 / area;

        // Steps derived from your winding:
        // w1 (weight for V1) follows the (V2-V0) edge
        const w1_step_x = (y0 - y2) * inv_area;
        const w1_step_y = (x2 - x0) * inv_area;
        // w2 (weight for V2) follows the (V1-V0) edge
        const w2_step_x = (y1 - y0) * inv_area;
        const w2_step_y = (x0 - x1) * inv_area;

        // Depth gradients
        const z_step_x = w1_step_x * (z1 - z0) + w2_step_x * (z2 - z0);
        const z_step_y = w1_step_y * (z1 - z0) + w2_step_y * (z2 - z0);

        // Evaluate starting values at the top-left sub-pixel center of the overlap box
        const start_px = @as(f64, @floatFromInt(ovl.x_min)) + (0.5 * sub_step);
        const start_py = @as(f64, @floatFromInt(ovl.y_min)) + (0.5 * sub_step);

        const w1_start = ((start_px - x0) * (y0 - y2) - (start_py - y0) * (x0 - x2)) * inv_area;
        const w2_start = ((start_px - x0) * (y1 - y0) - (start_py - y0) * (x1 - x0)) * inv_area;
        const z_start  = z0 + w1_start * (z1 - z0) + w2_start * (z2 - z0);

        // --- SUB-PIXEL SCANLINE LOOP ---
        const sub_rows = (ovl.y_max - ovl.y_min) * aa_rate;
        const sub_cols = (ovl.x_max - ovl.x_min) * aa_rate;
        const is_full_tile = (ovl.x_max - ovl.x_min == tile_size) and (ovl.y_max - ovl.y_min == tile_size);

        var sy: usize = 0;
        while (sy < sub_rows) : (sy += 1) {
            const row_f = @as(f64, @floatFromInt(sy));
            
            var cur_w1 = w1_start + (row_f * w1_step_y * sub_step);
            var cur_w2 = w2_start + (row_f * w2_step_y * sub_step);
            var cur_z  = z_start  + (row_f * z_step_y  * sub_step);

            const local_y = (ovl.y_min - tile.y_px_min) * @as(u16, @intCast(aa_rate)) + @as(u16, @intCast(sy));
            const row_idx = @as(usize, local_y) * sub_tile_size;

            var sx: usize = 0;
            while (sx < sub_cols) : (sx += 1) {
                const cur_w0 = 1.0 - cur_w1 - cur_w2;

                // Inside check: w>=0 for all weights
                if (is_full_tile or (cur_w0 >= -1e-9 and cur_w1 >= -1e-9 and cur_w2 >= -1e-9)) {
                    const local_x = (ovl.x_min - tile.x_px_min) * @as(u16, @intCast(aa_rate)) + @as(u16, @intCast(sx));
                    const idx = row_idx + local_x;

                    if (cur_z < sub_depth_buffer[idx]) {
                        sub_depth_buffer[idx] = @floatCast(cur_z);
                        sub_color_buffer[idx] = 1.0; 
                    }
                }

                cur_w1 += (w1_step_x * sub_step);
                cur_w2 += (w2_step_x * sub_step);
                cur_z  += (z_step_x  * sub_step);
            }
        }
    }

    // --- AA RESOLVE ---
    for (0..tile_size) |py| {
        const out_y = tile.y_px_min + @as(u16, @intCast(py));
        if (out_y >= screen_px_y) continue;

        for (0..tile_size) |px| {
            const out_x = tile.x_px_min + @as(u16, @intCast(px));
            if (out_x >= screen_px_x) continue;

            var color_sum: f64 = 0;
            for (0..aa_rate) |ay| {
                const row_off = (py * aa_rate + ay) * sub_tile_size;
                for (0..aa_rate) |ax| {
                    color_sum += sub_color_buffer[row_off + (px * aa_rate + ax)];
                }
            }

            const final_color = color_sum / @as(f64, @floatFromInt(aa_rate * aa_rate));
            try image_out_arr.set(&[_]usize{out_y, out_x}, final_color);
        }
    }
}


//---------------------------------------------------------------------------------------------
// --- BARYCENTRIC PRE-CALCULATION (Per Element) ---
// ... (keep your dw_dx, dw_dy, dz_dx, dz_dy calculations from before) ...
// --- BARYCENTRIC PRE-CALCULATION (Per Element) ---
const area = edgeFun3(x0, y0, x1, y1, x2, y2);
if (area <= 1e-9) continue;
const inv_area = 1.0 / area;

// Normalized Step Constants (Change per sub-pixel in X and Y)
const s_step = subpx_cent_step;
const n_inv_area = inv_area * s_step;

// Weight steps (pre-multiplied by sub-pixel step and inv_area)
const dw0_dx = (y1 - y2) * n_inv_area;
const dw0_dy = (x2 - x1) * n_inv_area;
const dw1_dx = (y2 - y0) * n_inv_area;
const dw1_dy = (x0 - x2) * n_inv_area;
const dw2_dx = (y0 - y1) * n_inv_area;
const dw2_dy = (x1 - x0) * n_inv_area;

// Depth gradient (pre-multiplied for 1/z interpolation)
const dz_dx = (dw0_dx * inv_z[0] + dw1_dx * inv_z[1] + dw2_dx * inv_z[2]);
const dz_dy = (dw0_dy * inv_z[0] + dw1_dy * inv_z[1] + dw2_dy * inv_z[2]);

// Initial values at the first sub-pixel center (start_px, start_py)
const start_px = @as(f64, @floatFromInt(overlap.x_min)) + subpx_cent_offset;
const start_py = @as(f64, @floatFromInt(overlap.y_min)) + subpx_cent_offset;

var w0_row = edgeFun3(x1, y1, x2, y2, start_px, start_py) * inv_area;
var w1_row = edgeFun3(x2, y2, x0, y0, start_px, start_py) * inv_area;
var w2_row = edgeFun3(x0, y0, x1, y1, start_px, start_py) * inv_area;
var z_row  = (w0_row * inv_z[0] + w1_row * inv_z[1] + w2_row * inv_z[2]);

// INITIALIZE DEPTH BUFFER DIFFERENTLY
// Before the tile loop:
// @memset(subpx_depth_scratch, 0.0); 

// --- THE HOT LOOP ---
var sy = scratch_start_ind_y;
while (sy < scratch_end_ind_y) : (sy += 1) {
    var curr_w0 = w0_row;
    var curr_w1 = w1_row;
    var curr_w2 = w2_row;
    var curr_z_inv = z_row;

    const row_off = sy * subpx_tile_size;

    var sx = scratch_start_ind_x;
    while (sx < scratch_end_ind_x) : (sx += 1) {
        
        // 1. Inside check
        if (curr_w0 >= 0 and curr_w1 >= 0 and curr_w2 >= 0) {
            const scratch_idx = row_off + sx;

            // 2. Inverse Depth Test: LARGER is CLOSER
            if (curr_z_inv > subpx_depth_scratch[scratch_idx]) {
                subpx_depth_scratch[scratch_idx] = curr_z_inv;
                
                // If you just need the depth map, store the inverse.
                // If you need actual Z for shading later, you can divide 
                // in the resolve pass, not here.
                subpx_image_scratch[scratch_idx] = curr_z_inv; 
            }
        }

        // 3. Increments (The only math in the loop)
        curr_w0 += dw0_dx;
        curr_w1 += dw1_dx;
        curr_w2 += dw2_dx;
        curr_z_inv += dz_dx;
    }

    w0_row += dw0_dy;
    w1_row += dw1_dy;
    w2_row += dw2_dy;
    z_row  += dz_dy;
}
