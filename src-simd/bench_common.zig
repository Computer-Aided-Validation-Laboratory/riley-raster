const std = @import("std");
const zraster = @import("zigraster/zig/zraster.zig");
const meshio = @import("zigraster/zig/meshio.zig");
const iio = @import("zigraster/zig/imageio.zig");
const uvio = @import("zigraster/zig/uvio.zig");
const mr = @import("zigraster/zig/meshraster.zig");
const rops = @import("zigraster/zig/rasterops.zig");
const rasterengine = @import("zigraster/zig/rasterengine.zig");
const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const Rotation = @import("zigraster/zig/camera.zig").Rotation;
const perf = @import("zigraster/zig/perf.zig");
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;
const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;
const Timestamp = std.Io.Clock.Timestamp;

pub const BenchResult = struct {
    e2e_ms: f64,
    geom_ms: f64,
    raster_ms: f64,
    mops_sec: f64,
    melems_sec: f64,
    fps: f64,
};

pub const BenchStats = struct {
    name: []const u8,
    e2e: MedianMAD,
    geom: MedianMAD,
    raster: MedianMAD,
    mops: MedianMAD,
    melems: MedianMAD,
    fps: MedianMAD,
};

pub const MedianMAD = struct {
    median: f64,
    mad: f64,
};

pub fn getNodesNum(etype: mr.MeshType) usize {
    return switch (etype) {
        .tri3, .tri3opt => 3,
        .tri6 => 6,
        .quad4ibi, .quad4newton => 4,
        .quad8 => 8,
        .quad9 => 9,
    };
}

pub fn calcMedianMAD(allocator: std.mem.Allocator, data: []f64) !MedianMAD {
    if (data.len == 0) return .{ .median = 0, .mad = 0 };
    const data_copy = try allocator.dupe(f64, data);
    defer allocator.free(data_copy);
    std.mem.sort(f64, data_copy, {}, std.sort.asc(f64));
    
    const mid = data_copy.len / 2;
    const median = if (data_copy.len % 2 == 0) 
        (data_copy[mid - 1] + data_copy[mid]) / 2.0 
    else 
        data_copy[mid];

    var abs_devs = try allocator.alloc(f64, data_copy.len);
    defer allocator.free(abs_devs);
    for (data_copy, 0..) |val, ii| {
        abs_devs[ii] = @abs(val - median);
    }
    std.mem.sort(f64, abs_devs, {}, std.sort.asc(f64));
    const mad = if (abs_devs.len % 2 == 0) 
        (abs_devs[mid - 1] + abs_devs[mid]) / 2.0 
    else 
        abs_devs[mid];

    return .{ .median = median, .mad = mad };
}

pub fn getCPUModel(allocator: std.mem.Allocator) []const u8 {
    return allocator.dupe(u8, "BenchCPU") catch "BenchCPU";
}

pub fn getDateString() ![]const u8 {
    return "17-03-2026";
}

pub const ShaderType = enum { flat_grey, flat_rgb, tex8_grey, tex8_rgb, tex8_cubic, tex8_cubic_lut_lerp };

pub fn loadNDArrayFromCSV(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    requested_channels: usize,
    is_time_series: bool,
) !NDArray(f64) {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const lines = try meshio.readCsvToList(aa, io, path);
    if (lines.items.len == 0) return error.EmptyCsv;
    const rows_num = lines.items.len;

    var cols_num: usize = 0;
    var first_line_iter = std.mem.splitScalar(u8, lines.items[0], ',');
    while (first_line_iter.next()) |col_str| {
        if (col_str.len > 0) cols_num += 1;
    }

    var arr: NDArray(f64) = undefined;
    if (is_time_series) {
        arr = try NDArray(f64).initFlat(
            allocator, &[_]usize{ 1, rows_num, requested_channels }
        );
    } else {
        // We need to peek if it has colons to decide if it's (rows, cols, channels) or (nodes, channels)
        var has_colons = false;
        var first_line_peek = std.mem.splitScalar(u8, lines.items[0], ',');
        if (first_line_peek.next()) |first_col| {
            if (std.mem.indexOfScalar(u8, first_col, ':')) |_| {
                has_colons = true;
            }
        }

        if (has_colons) {
            arr = try NDArray(f64).initFlat(
                allocator, &[_]usize{ requested_channels, rows_num, cols_num }
            );
        } else {
            arr = try NDArray(f64).initFlat(
                allocator, &[_]usize{ rows_num, requested_channels }
            );
        }
    }
    errdefer {
        allocator.free(arr.elems);
        arr.deinit(allocator);
    }

    for (lines.items, 0..) |line, rr| {
        var col_iter = std.mem.splitScalar(u8, line, ',');
        var cc: usize = 0;
        while (col_iter.next()) |col_str| {
            if (col_str.len == 0) continue;
            if (is_time_series) {
                // Source data: One node per line, channels in columns
                if (cc < requested_channels) {
                    const val = try std.fmt.parseFloat(f64, std.mem.trim(u8, col_str, " "));
                    arr.set(&[_]usize{ 0, rr, cc }, val);
                }
            } else if (arr.dims.len == 3) {
                // Output data: One image row per line, channels colon-separated
                var chan_iter = std.mem.splitScalar(u8, col_str, ':');
                var ch: usize = 0;
                while (chan_iter.next()) |chan_str| {
                    if (ch < requested_channels) {
                        const val = try std.fmt.parseFloat(
                            f64, std.mem.trim(u8, chan_str, " ")
                        );
                        arr.set(&[_]usize{ ch, rr, cc }, val);
                    }
                    ch += 1;
                }
            } else {
                // Column-based: like UVs or Coords
                if (cc < requested_channels) {
                    const val = try std.fmt.parseFloat(
                        f64, std.mem.trim(u8, col_str, " ")
                    );
                    arr.set(&[_]usize{ rr, cc }, val);
                }
            }
            cc += 1;
        }
    }
    return arr;
}

pub fn runBenchmark(
    allocator: std.mem.Allocator,
    io: std.Io,
    comptime etype: mr.MeshType,
    comptime shader_type: ShaderType,
    data_dir: []const u8,
    out_dir_base: []const u8,
    pixel_num: [2]u32,
    texture_grey: iio.Texture(u8, 1),
    texture_rgb: iio.Texture(u8, 3),
) !BenchResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const coord_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "coords.csv" });
    const conn_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "connect.csv" });
    const field_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "field.csv" });
    const uv_path = try std.fs.path.join(aa, &[_][]const u8{ data_dir, "uvs.csv" });

    const sim_data = try meshio.loadSimData(aa, io, coord_path, conn_path, null, null);
    const field_raw = try loadNDArrayFromCSV(
        aa, io, field_path, if (shader_type == .flat_rgb) 3 else 1, true
    );
    const uvs_raw = try loadNDArrayFromCSV(aa, io, uv_path, 2, false);
    
    var shader: mr.ShaderInput = undefined;
    var num_out_fields: usize = 1;

    switch (shader_type) {
        .flat_grey => {
            num_out_fields = 1;
            shader = .{ .flat = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.elems },
                .scaling = .auto,
            } };
        },
        .flat_rgb => {
            num_out_fields = 3;
            shader = .{ .flat = .{
                .field = .{ .array = field_raw, .array_mem = field_raw.elems },
                .scaling = .auto,
            } };
        },
        .tex8_grey => {
            shader = .{ .tex_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .interp_type = .cubic_lut_lerp,
            } };
        },
        .tex8_rgb => {
            num_out_fields = 3;
            shader = .{ .tex_rgb_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_rgb,
                .interp_type = .cubic_lut_lerp,
            } };
        },
        .tex8_cubic => {
            shader = .{ .tex_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .interp_type = .cubic,
            } };
        },
        .tex8_cubic_lut_lerp => {
            shader = .{ .tex_u8 = .{
                .uvs = uvs_raw,
                .texture = texture_grey,
                .interp_type = .cubic_lut_lerp,
            } };
        },
    }

    const mesh_input = mr.MeshInput{
        .mesh_type = etype,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = shader,
    };

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, 1.0
    );
    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 2);

    const tile_size: u16 = 32;
    const tiles_num_x: usize = try std.math.divCeil(usize, camera.pixels_num[0], tile_size);
    const tiles_num_y: usize = try std.math.divCeil(usize, camera.pixels_num[1], tile_size);

    const mesh_prepform = try mr.prepareMesh(aa, &mesh_input, &sim_data.coords.mat, null);
    var meshes = [_]mr.MeshPrepared{ mesh_prepform };

    var image_out_arr = try NDArray(f64).initFlat(
        aa, &[_]usize{ num_out_fields, pixel_num[1], pixel_num[0] }
    );

    const e2e_start = Timestamp.now(io, .awake);

    // 1. Geometry Prep
    const geom_start = Timestamp.now(io, .awake);
    const elem_bboxes_by_mesh = try aa.alloc([]rops.ElemBBox, 1);
    const elems_in_image_by_mesh = try aa.alloc(usize, 1);
    var total_elems_in_image: usize = 0;
    var total_elems_num: usize = 0;
    const raster_hulls = try aa.alloc(?NDArray(f64), 1);

    try rops.prepareSceneGeometry(
        .off, .{ .perf = {} }, aa, &camera, &meshes, raster_hulls, 
        elem_bboxes_by_mesh, elems_in_image_by_mesh, 
        &total_elems_num, &total_elems_in_image,
    );
    const geom_end = Timestamp.now(io, .awake);

    // 2. Tile Overlap
    const overlap_start = Timestamp.now(io, .awake);
    const tiling = try rops.sceneTileElemOverlap(
        aa, tile_size, tiles_num_x, tiles_num_y,
        @intCast(camera.pixels_num[0]), @intCast(camera.pixels_num[1]),
        1, elems_in_image_by_mesh, elem_bboxes_by_mesh,
    );
    const overlap_end = Timestamp.now(io, .awake);

    // 3. Raster Loop
    const raster_start = Timestamp.now(io, .awake);
    const ctx_rast = rops.RasterContext(.off){
        .ctx_perf = .{ .perf = {} },
        .camera = &camera,
        .frame_ind = 0,
        .tile_size = tile_size,
    };
    try rasterengine.rasterScene(
        .off, ctx_rast, aa, io, tiling, &meshes, raster_hulls, &image_out_arr,
    );
    const raster_end = Timestamp.now(io, .awake);

    // Save one frame for inspection
    const out_name = comptime @tagName(etype) ++ "_" ++ @tagName(shader_type);
    const out_path = try std.fs.path.join(aa, &[_][]const u8{ out_dir_base, out_name });
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_base, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    cwd.createDir(io, out_path, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir_h = try cwd.openDir(io, out_path, .{});
    defer out_dir_h.close(io);

    try iio.saveImages(
        io, out_dir_h, 0, num_out_fields, pixel_num, &image_out_arr,
        &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = num_out_fields },
            .{ .format = .csv, .bits = null, .scaling = .none, .channels = num_out_fields },
        }
    );

    const e2e_end = Timestamp.now(io, .awake);

    const e2e_ms = @as(f64, @floatFromInt(e2e_start.durationTo(e2e_end).raw.nanoseconds)) / 1e6;
    const geom_ms = @as(f64, @floatFromInt(geom_start.durationTo(geom_end).raw.nanoseconds)) / 1e6;
    const overlap_ms = @as(f64, @floatFromInt(overlap_start.durationTo(overlap_end).raw.nanoseconds)) / 1e6;
    const raster_ms = @as(f64, @floatFromInt(raster_start.durationTo(raster_end).raw.nanoseconds)) / 1e6;

    const N = @as(f64, @floatFromInt(getNodesNum(etype)));
    const total_ops = N * @as(f64, @floatFromInt(pixel_num[0] * pixel_num[1] * 4));
    const mops_sec = (total_ops / (raster_ms / 1000.0)) / 1e6;
    const fps = 1000.0 / e2e_ms;

    const total_melems = @as(f64, @floatFromInt(mesh_input.connect.getElemsNum())) / 1e6;
    const melems_sec = total_melems / ((geom_ms + overlap_ms) / 1000.0);

    return .{
        .e2e_ms = e2e_ms,
        .geom_ms = geom_ms + overlap_ms, 
        .raster_ms = raster_ms,
        .mops_sec = mops_sec,
        .melems_sec = melems_sec,
        .fps = fps,
    };
}
