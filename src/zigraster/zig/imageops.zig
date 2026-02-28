const std = @import("std");
const MatSlice = @import("matslice.zig").MatSlice;

pub const ImageFormat = enum {
    csv,
    ppm,
    bmp,
    tiff,
};

pub fn saveImage(io: std.Io,
                 out_dir: std.Io.Dir, 
                 file_name_no_ext: []const u8,
                 image: *const MatSlice(f64),
                 format: ImageFormat,
                 bits: u8,
                 ) !void {
                    
    var name_buff: [1024]u8 = undefined;                
       
    switch (format) {
        .csv => {
            const ext = ".csv";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                       .{ file_name_no_ext, ext });     
            try saveCSV(io,out_dir,file_name_ext,image,bits);
        },
        .ppm => {
            const ext = ".ppm";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try savePPM(io,out_dir,file_name_ext,image,bits);
        },
        .bmp => {
            const ext = ".bmp";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try saveBMP(io,out_dir,file_name_ext,image,bits);
        },
        .tiff => {
            const ext = ".tiff";
            const file_name_ext = try std.fmt.bufPrint(name_buff[0..], 
                                                       "{s}{s}", 
                                                      .{ file_name_no_ext, ext });
            try saveTIFF(io,out_dir,file_name_ext,image,bits);
        },
    }
}

pub fn savePPM(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image: *const MatSlice(f64),
               bits: u8,
               ) !void {

    const ppm_file: std.Io.File = try out_dir.createFile(io, file_name, .{});
    defer ppm_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = ppm_file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const max_val: u32 = (@as(u32, 1) << @as(u5, @intCast(bits))) - 1;
    try writer.print("P3\n{d} {d}\n{d}\n", .{ image.cols_n, image.rows_n, max_val});

    const px_min: f64 = std.mem.min(f64,image.elems);
    const px_max: f64 = std.mem.max(f64,image.elems);
    const px_rng: f64 = if (px_max > px_min) px_max - px_min else 1.0;
    const scale = @as(f64, @floatFromInt(max_val));

    for (0..image.rows_n) |rr| {
        for (0..image.cols_n) |cc| {
            const px_scaled = @as(u32,
                @intFromFloat((image.get(rr,cc) - px_min)/px_rng * scale)
            );  
            try writer.print("{d} {d} {d}\n", .{px_scaled,px_scaled,px_scaled});
        }
    }

    try writer.flush();   
}

pub fn saveCSV(io: std.Io,
               out_dir: std.Io.Dir, 
               file_name: []const u8,
               image: *const MatSlice(f64),
               bits: u8,
               ) !void {
    _ = bits; // CSV ignores bit depth as it saves raw floats
    const csv_file = try out_dir.createFile(io, file_name, .{});
    defer csv_file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = csv_file.writer(io,&write_buf);
    const writer = &file_writer.interface;

    for (0..image.rows_n) |rr| {
        for (0..image.cols_n) |cc| {
            try writer.print("{d},", .{image.get(rr, cc)});
        }
        try writer.print("\n",.{});
    }

    try writer.flush();
}

pub fn saveBMP(io: std.Io, 
               out_dir: std.Io.Dir, 
               file_name: []const u8, 
               image: *const MatSlice(f64), 
               bits: u8) !void {

    _ = bits; // BMP currently only supports 8-bit grayscale (as 24-bit RGB)
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const width = @as(u32, @intCast(image.cols_n));
    const height = @as(u32, @intCast(image.rows_n));
    const row_padding = (4 - (width * 3) % 4) % 4;
    const row_size = width * 3 + row_padding;
    const data_size = row_size * height;
    const offset = 14 + 40;
    const file_size = offset + data_size;

    // Bitmap File Header (14 bytes)
    try writer.writeAll("BM");
    try writer.writeInt(u32, file_size, .little);
    try writer.writeInt(u16, 0, .little); // Reserved 1
    try writer.writeInt(u16, 0, .little); // Reserved 2
    try writer.writeInt(u32, offset, .little);

    // DIB Header (BITMAPINFOHEADER, 40 bytes)
    try writer.writeInt(u32, 40, .little);
    try writer.writeInt(i32, @intCast(width), .little);
    try writer.writeInt(i32, @intCast(height), .little); // Positive = bottom-up
    try writer.writeInt(u16, 1, .little); // Planes
    try writer.writeInt(u16, 24, .little); // Bits per pixel
    try writer.writeInt(u32, 0, .little); // Compression (none)
    try writer.writeInt(u32, data_size, .little);
    try writer.writeInt(i32, 2835, .little); // 72 DPI (ppm)
    try writer.writeInt(i32, 2835, .little); // 72 DPI (ppm)
    try writer.writeInt(u32, 0, .little); // Colors in palette
    try writer.writeInt(u32, 0, .little); // Important colors

    const px_min = std.mem.min(f64, image.elems);
    const px_max = std.mem.max(f64, image.elems);
    const px_rng = if (px_max > px_min) px_max - px_min else 1.0;

    // BMP data is bottom-up
    var r: usize = image.rows_n;
    while (r > 0) {
        r -= 1;
        for (0..image.cols_n) |c| {
            const val = @as(u8, @intFromFloat(((image.get(r, c) - px_min) / px_rng) * 255.0));
            // BGR order
            try writer.writeByte(val); // Blue
            try writer.writeByte(val); // Green
            try writer.writeByte(val); // Red
        }
        for (0..row_padding) |_| try writer.writeByte(0);
    }
    try writer.flush();
}

pub fn saveTIFF(io: std.Io, 
                out_dir: std.Io.Dir, 
                file_name: []const u8, 
                image: *const MatSlice(f64), 
                bits: u8) !void {
                
    const file = try out_dir.createFile(io, file_name, .{});
    defer file.close(io);

    var write_buf: [4096]u8 = undefined;
    var file_writer = file.writer(io, &write_buf);
    const writer = &file_writer.interface;

    const width = @as(u32, @intCast(image.cols_n));
    const height = @as(u32, @intCast(image.rows_n));
    const pixel_data_offset: u32 = 8; // Header is 8 bytes
    const bytes_per_pixel: u32 = if (bits == 16) 2 else 1;
    const pixel_data_size = width * height * bytes_per_pixel;
    const ifd_offset = pixel_data_offset + pixel_data_size;

    // 1. Header (8 bytes)
    try writer.writeAll("II"); // Little Endian
    try writer.writeInt(u16, 42, .little); // Magic number
    try writer.writeInt(u32, ifd_offset, .little);

    // 2. Pixel Data (Grayscale)
    const px_min = std.mem.min(f64, image.elems);
    const px_max = std.mem.max(f64, image.elems);
    const px_rng = if (px_max > px_min) px_max - px_min else 1.0;

    if (bits == 16) {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val_f = ((image.get(r, c) - px_min) / px_rng) * 65535.0;
                const val = @as(u16,@intFromFloat(val_f));
                try writer.writeInt(u16, val, .little);
            }
        }
    } else {
        for (0..image.rows_n) |r| {
            for (0..image.cols_n) |c| {
                const val_f = ((image.get(r, c) - px_min) / px_rng) * 255.0;
                const val = @as(u8, @intFromFloat(val_f));
                try writer.writeByte(val);
            }
        }
    }

    // 3. Image File Directory (IFD)
    // We'll write 10 tags
    const num_tags: u16 = 10;
    try writer.writeInt(u16, num_tags, .little);

    // Helper to write a TIFF tag
    const Tag = struct {
        id: u16, type: u16, count: u32, value: u32,
        fn write(self: @This(), w: anytype) !void {
            try w.writeInt(u16, self.id, .little);
            try w.writeInt(u16, self.type, .little);
            try w.writeInt(u32, self.count, .little);
            try w.writeInt(u32, self.value, .little);
        }
    };

    // ID: 256 (Width), Type: 3 (Short), Count: 1
    try (Tag{ .id = 256, .type = 3, .count = 1, .value = width }).write(writer);
    // ID: 257 (Length/Height), Type: 3 (Short), Count: 1
    try (Tag{ .id = 257, .type = 3, .count = 1, .value = height }).write(writer);
    // ID: 258 (BitsPerSample), Type: 3 (Short), Count: 1
    try (Tag{ .id = 258, .type = 3, .count = 1, .value = bits }).write(writer);
    // ID: 259 (Compression), Type: 3 (Short), Count: 1, Value: 1 (None)
    try (Tag{ .id = 259, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 262 (PhotometricInterpretation), Type: 3 (Short), Count: 1, Value: 1 (BlackIsZero)
    try (Tag{ .id = 262, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 273 (StripOffsets), Type: 4 (Long), Count: 1
    try (Tag{ .id = 273, .type = 4, .count = 1, .value = pixel_data_offset }).write(writer);
    // ID: 277 (SamplesPerPixel), Type: 3 (Short), Count: 1
    try (Tag{ .id = 277, .type = 3, .count = 1, .value = 1 }).write(writer);
    // ID: 278 (RowsPerStrip), Type: 3 (Short), Count: 1
    try (Tag{ .id = 278, .type = 3, .count = 1, .value = height }).write(writer);
    // ID: 279 (StripByteCounts), Type: 4 (Long), Count: 1
    try (Tag{ .id = 279, .type = 4, .count = 1, .value = pixel_data_size }).write(writer);
    // ID: 282 (XResolution), Type: 5 (Rational) - simplified: just use long 72
    // For simplicity, we skip complex rationals and just set min required tags correctly.
    // Let's use ResolutionUnit (296) instead of XRes for minimum compliance.
    try (Tag{ .id = 296, .type = 3, .count = 1, .value = 2 }).write(writer); // Inch

    try writer.writeInt(u32, 0, .little); // End of IFD
    try writer.flush();
}

