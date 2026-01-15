// --- Raster Loop Pass 3 ---
    
    // 1. Allocate a single tile-sized scratchpad for AA resolve
    // tile_size = 16, sub_samples = 4 -> 64x64 grid
    const aa_rate: usize = 4;
    const sub_tile_size = tile_size * aa_rate;
    const sub_tile_total = sub_tile_size * sub_tile_size;
    
    // Scratchpads for depth and color (Reuse these for every tile)
    const sub_depth_buffer = try arena_alloc.alloc(f32, sub_tile_total);
    const sub_color_buffer = try arena_alloc.alloc(f64, sub_tile_total);

    for (active_tiles) |tile| {
        // Clear local scratchpads for this tile
        @memset(sub_depth_buffer, std.math.inf(f32));
        @memset(sub_color_buffer, 0.0);

        const overlaps = overlap_bboxes[tile.overlap_start .. 
                                        tile.overlap_start + tile.overlap_count];

        for (overlaps) |ovl| {
            // Pull the actual 3D vertex data for this element
            // Since we stored elem_ind in the overlap box, we can look it up
            const coords_raster: Vec3SIMD(N, f64) = try vsd.loadVec3FromElemArray(N, f64,
                                                         &elem_coord_arr, ovl.elem_ind);

            // Calculate Edge Equations for the element (e.g., Triangle)
            // Edge = (px - x0) * (y1 - y0) - (py - y0) * (x1 - x0)
            const edges = rops.setupEdgeEquations(coords_raster);

            // CORNER CHECK: Scale the overlap box coordinates to SUB-PIXEL space
            const sub_ovl_x_min = (ovl.x_min - tile.x_px_min) * @as(u16, @intCast(aa_rate));
            const sub_ovl_x_max = (ovl.x_max - tile.x_px_min) * @as(u16, @intCast(aa_rate));
            const sub_ovl_y_min = (ovl.y_min - tile.y_px_min) * @as(u16, @intCast(aa_rate));
            const sub_ovl_y_max = (ovl.y_max - tile.y_px_min) * @as(u16, @intCast(aa_rate));

            // Iterate through the sub-pixel grid of the overlap area
            var sy = sub_ovl_y_min;
            while (sy < sub_ovl_y_max) : (sy += 1) {
                const row_off = sy * sub_tile_size;
                var sx = sub_ovl_x_min;
                while (sx < sub_ovl_x_max) : (sx += 1) {
                    
                    // The coordinate in GLOBAL sub-pixel space
                    const px = @as(f64, @floatFromInt(tile.x_px_min)) 
                               + (@as(f64, @floatFromInt(sx)) 
                               / @as(f64, @floatFromInt(aa_rate)));
                    const py = @as(f64, @floatFromInt(tile.y_px_min)) 
                               + (@as(f64, @floatFromInt(sy)) 
                               / @as(f64, @floatFromInt(aa_rate)));

                    if (rops.isInside(edges, px, py)) {
                        const depth = rops.interpolateDepth(edges, coords_raster, px, py);
                        const idx = row_off + sx;
                        if (depth < sub_depth_buffer[idx]) {
                            sub_depth_buffer[idx] = depth;
                            sub_color_buffer[idx] = 1.0; // Or fetch from Field data
                        }
                    }
                }
            }
        }

        // --- AA RESOLVE & WRITE BACK ---
        // Average the sub-pixels back into the final image_out_arr
        for (0..tile_size) |py| {
            for (0..tile_size) |px| {
                var sum: f64 = 0;
                for (0..aa_rate) |ay| {
                    for (0..aa_rate) |ax| {
                        sum += sub_color_buffer[(py * aa_rate + ay) 
                               * sub_tile_size + (px * aa_rate + ax)];
                    }
                }
                const avg_color = sum / @as(f64, @floatFromInt(aa_rate * aa_rate));
                
                // Index into your Tiled Framebuffer or final image
                const out_x = tile.x_px_min + @as(u16, @intCast(px));
                const out_y = tile.y_px_min + @as(u16, @intCast(py));
                // Note: NDArray set using [y, x]
                try image_out_arr.set(&[_]usize{out_y, out_x}, avg_color);
            }
        }
    }
