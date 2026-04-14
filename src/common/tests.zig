const std = @import("std");

pub const NDArray = @import("../zraster/zig/ndarray.zig").NDArray;
pub const MatSlice = @import("../zraster/zig/matslice.zig").MatSlice;

pub const meshio = @import("../zraster/zig/meshio.zig");
pub const SimData = meshio.SimData;

pub const mr = @import("../zraster/zig/meshraster.zig");
pub const MeshType = mr.MeshType;
pub const MeshInput = mr.MeshInput;

pub const Rotation = @import("../zraster/zig/camera.zig").Rotation;
pub const Camera = @import("../zraster/zig/camera.zig").Camera;
pub const CameraOps = @import("../zraster/zig/camera.zig").CameraOps;

pub const zraster = @import("../zraster/zig/zraster.zig");
pub const RasterConfig = zraster.RasterConfig;

pub const iio = @import("../zraster/zig/imageio.zig");
pub const texops = @import("../zraster/zig/textureops.zig");
pub const uvio = @import("../zraster/zig/uvio.zig");
pub const buildconfig = @import("../zraster/zig/buildconfig.zig");
pub const csvio = @import("../zraster/zig/csvio.zig");

const default_fails_root = "fails";
const impl_suffix = if (buildconfig.config.simd == .on) "_simd" else "_scalar";

// Default tolerances: for scientific accuracy and DIC
// f64: rel= 1e-11, abs= 1e-11
// f32: rel= 1e-5, abs= 1e-4
pub fn isApproxEqual(v1: f64, v2: f64, rel_tol: f64, abs_tol: f64) bool {
    if (v1 == v2) return true;

    const diff = @abs(v1 - v2);

    if (diff <= abs_tol) return true;

    const abs_v1 = @abs(v1);
    const abs_v2 = @abs(v2);
    const largest = if (abs_v1 > abs_v2) abs_v1 else abs_v2;

    return (diff / largest) <= rel_tol;
}

pub fn compareNDArrayToGold(
    allocator: std.mem.Allocator,
    io: std.Io,
    array: *const NDArray(f64),
    frame: usize,
    field_start: usize,
    channels: usize,
    path: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var gold = if (std.mem.endsWith(u8, path, ".fimg")) blk: {
        const gold_array = try iio.loadFIMG(allocator, io, path);
        break :blk gold_array;
    } else if (channels == 1)
        try csvio.loadScalarCsv2D(allocator, io, path)
    else
        try csvio.loadPackedCsv2D(allocator, io, path, channels);

    defer {
        allocator.free(gold.slice);
        gold.deinit(allocator);
    }

    // Handle different dimension layouts:
    // .fimg: [chans, rows, cols]
    // .csv (scalar): [rows, cols]
    // .csv (packed): [rows, cols, chans]
    const gold_rows = if (gold.dims.len == 3 and std.mem.endsWith(u8, path, ".fimg"))
        gold.dims[1]
    else
        gold.dims[0];
    const gold_cols = if (gold.dims.len == 3 and std.mem.endsWith(u8, path, ".fimg"))
        gold.dims[2]
    else
        gold.dims[1];

    const rows = array.dims[2];
    const cols = array.dims[3];

    if (gold_rows != rows) {
        std.debug.print(
            "Row count mismatch: Gold has {d}, array expects {d} (path: {s})\n",
            .{ gold_rows, rows, path },
        );
        return error.GoldRowsMismatch;
    }

    if (gold_cols != cols) return error.GoldColsMismatch;

    for (0..rows) |r| {
        for (0..cols) |c| {
            for (0..channels) |ch| {
                const gold_val = if (std.mem.endsWith(u8, path, ".fimg"))
                    gold.get(&[_]usize{ ch, r, c })
                else if (channels == 1)
                    gold.get(&[_]usize{ r, c })
                else
                    gold.get(&[_]usize{ r, c, ch });

                const actual_val = array.get(&[_]usize{ frame, field_start + ch, r, c });

                if (!isApproxEqual(gold_val, actual_val, rel_tol, abs_tol)) {
                    const abs_gold = @abs(gold_val);
                    const abs_act = @abs(actual_val);
                    const largest = if (abs_gold > abs_act) abs_gold else abs_act;

                    const diff = @abs(gold_val - actual_val);
                    const rel_diff = if (largest < abs_tol) diff else diff / largest;

                    std.debug.print(
                        "\n\nMismatch at:\n frame {d},\n field {d},\n " ++
                            "pixel ({d}, {d}): " ++
                            "\n gold={d},\n actual={d},\n rel_diff={e}\n (path: {s})\n\n",
                        .{
                            frame,
                            field_start + ch,
                            r,
                            c,
                            gold_val,
                            actual_val,
                            rel_diff,
                            path,
                        },
                    );
                    return error.PixelMismatch;
                }
            }
        }
    }
}

pub fn compareNDArrayToCSV(
    allocator: std.mem.Allocator,
    io: std.Io,
    array: *const NDArray(f64),
    frame: usize,
    field: usize,
    path: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var gold = try csvio.loadScalarCsv2D(allocator, io, path);
    defer {
        allocator.free(gold.slice);
        gold.deinit(allocator);
    }

    const rows = array.dims[2];
    const cols = array.dims[3];

    if (gold.dims[0] != rows) {
        std.debug.print(
            "Row count mismatch: CSV has {d}, array expects {d} (path: {s})\n",
            .{ gold.dims[0], rows, path },
        );
        return error.CSVRowsMismatch;
    }

    if (gold.dims[1] != cols) return error.CSVColsMismatch;

    for (0..rows) |r| {
        for (0..cols) |c| {
            const gold_val = gold.get(&[_]usize{ r, c });
            const actual_val = array.get(&[_]usize{ frame, field, r, c });

            if (!isApproxEqual(gold_val, actual_val, rel_tol, abs_tol)) {
                const abs_gold = @abs(gold_val);
                const abs_act = @abs(actual_val);
                const largest = if (abs_gold > abs_act) abs_gold else abs_act;

                const diff = @abs(gold_val - actual_val);
                const rel_diff = if (largest < abs_tol) diff else diff / largest;

                std.debug.print(
                    "\n\nMismatch at:\n frame {d},\n field {d},\n " ++
                        "pixel ({d}, {d}): " ++
                        "\n gold={d},\n actual={d},\n rel_diff={e}\n (path: {s})\n\n",
                    .{ frame, field, r, c, gold_val, actual_val, rel_diff, path },
                );
                return error.PixelMismatch;
            }
        }
    }
}

pub fn compareNDArrayToCSVRGB(
    allocator: std.mem.Allocator,
    io: std.Io,
    array: *const NDArray(f64),
    frame: usize,
    field_start: usize,
    path: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var gold = try csvio.loadPackedCsv2D(allocator, io, path, 3);
    defer {
        allocator.free(gold.slice);
        gold.deinit(allocator);
    }

    const rows = array.dims[2];
    const cols = array.dims[3];

    if (gold.dims[0] != rows) {
        std.debug.print(
            "Row count mismatch: CSV has {d}, array expects {d} (path: {s})\n",
            .{ gold.dims[0], rows, path },
        );
        return error.CSVRowsMismatch;
    }

    if (gold.dims[1] != cols) return error.CSVColsMismatch;

    for (0..rows) |r| {
        for (0..cols) |c| {
            for (0..3) |cc| {
                const gold_val = gold.get(&[_]usize{ r, c, cc });
                const actual_val = array.get(&[_]usize{ frame, field_start + cc, r, c });

                if (!isApproxEqual(gold_val, actual_val, rel_tol, abs_tol)) {
                    const abs_gold = @abs(gold_val);
                    const abs_act = @abs(actual_val);
                    const largest = if (abs_gold > abs_act) abs_gold else abs_act;

                    const diff = @abs(gold_val - actual_val);
                    const rel_diff = if (largest < abs_tol) diff else diff / largest;

                    std.debug.print(
                        "\n\nMismatch at:\n frame {d},\n field {d},\n " ++
                            "pixel ({d}, {d}): " ++
                            "\n gold={d},\n actual={d},\n rel_diff={e}\n (path: {s})\n\n",
                        .{
                            frame,
                            field_start + cc,
                            r,
                            c,
                            gold_val,
                            actual_val,
                            rel_diff,
                            path,
                        },
                    );
                    return error.PixelMismatch;
                }
            }
        }
    }
}

pub fn loadData(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !SimData {
    const pc = try std.fmt.allocPrint(allocator, "{s}/coords.csv", .{path});
    const pn = try std.fmt.allocPrint(allocator, "{s}/connectivity.csv", .{path});
    const pf = [_][]const u8{
        try std.fmt.allocPrint(allocator, "{s}/field_disp_x.csv", .{path}),
        try std.fmt.allocPrint(allocator, "{s}/field_disp_y.csv", .{path}),
        try std.fmt.allocPrint(allocator, "{s}/field_disp_z.csv", .{path}),
    };
    return try meshio.loadSimData(allocator, io, pc, pn, pf[0..], null);
}

fn openFailsSubDir(
    io: std.Io,
    fails_root: []const u8,
    dir_name: []const u8,
) !std.Io.Dir {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, fails_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var fails_dir = try cwd.openDir(io, fails_root, .{});
    fails_dir.createDir(io, dir_name, .default_dir) catch |err| {
        fails_dir.close(io);
        if (err != error.PathAlreadyExists) return err;
    };
    defer fails_dir.close(io);
    return try fails_dir.openDir(io, dir_name, .{});
}

fn saveResultToFails(
    allocator: std.mem.Allocator,
    io: std.Io,
    fails_root: []const u8,
    array: *const NDArray(f64),
    dir_name: []const u8,
) !void {
    var out_dir = try openFailsSubDir(io, fails_root, dir_name);
    defer out_dir.close(io);

    for (0..array.dims[0]) |f| {
        for (0..array.dims[1]) |fi| {
            const slice = array.getSlice(&[_]usize{ f, fi, 0, 0 }, 1);
            const mat = MatSlice(f64).init(slice, array.dims[2], array.dims[3]);
            const name = try std.fmt.allocPrint(
                allocator,
                "frame_{d}_field_{d}",
                .{ f, fi },
            );
            try iio.saveMatAsImage(
                io,
                out_dir,
                name,
                &mat,
                .{ .format = .csv, .bits = null, .scaling = .none },
            );
            try iio.saveMatAsImage(
                io,
                out_dir,
                name,
                &mat,
                .{ .format = .bmp, .bits = 8, .scaling = .auto },
            );
        }
    }
}

fn extractFrameImage(
    allocator: std.mem.Allocator,
    array: *const NDArray(f64),
    frame: usize,
    field_start: usize,
    channels: usize,
) !NDArray(f64) {
    const rows = array.dims[2];
    const cols = array.dims[3];
    var image = try NDArray(f64).initFlat(allocator, &[_]usize{ rows, cols, channels });

    for (0..rows) |rr| {
        for (0..cols) |cc| {
            for (0..channels) |ch| {
                image.set(
                    &[_]usize{ rr, cc, ch },
                    array.get(&[_]usize{ frame, field_start + ch, rr, cc }),
                );
            }
        }
    }

    return image;
}

pub fn findGoldPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,
    frame: usize,
    field: usize,
    is_rgb: bool,
) ![]const u8 {
    const base_name = if (is_rgb)
        try std.fmt.allocPrint(allocator, "{s}/frame_{d}_field_{d}_rgb", .{ dir, frame, field })
    else
        try std.fmt.allocPrint(allocator, "{s}/frame_{d}_field_{d}", .{ dir, frame, field });
    defer allocator.free(base_name);

    const fimg_path = try std.fmt.allocPrint(allocator, "{s}.fimg", .{base_name});
    errdefer allocator.free(fimg_path);

    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, fimg_path, .{})) |_| {
        return fimg_path;
    } else |_| {
        allocator.free(fimg_path);
        return try std.fmt.allocPrint(allocator, "{s}.csv", .{base_name});
    }
}

fn loadNDArrayFromGold(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    channels: usize,
) !NDArray(f64) {
    if (std.mem.endsWith(u8, path, ".fimg")) {
        const array = try iio.loadFIMG(allocator, io, path);
        if (array.dims[0] != channels) {
            return error.ChannelMismatch;
        }
        return array;
    }
    return csvio.loadPackedCsv2D(allocator, io, path, channels);
}

fn loadImageFromCSV(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
    channels: usize,
) !NDArray(f64) {
    return csvio.loadPackedCsv2D(allocator, io, path, channels);
}

pub fn calculateDiffImage(
    allocator: std.mem.Allocator,
    actual: *const NDArray(f64),
    gold: *const NDArray(f64),
) !NDArray(f64) {
    var diff = try NDArray(f64).initFlat(allocator, actual.dims);
    for (0..actual.slice.len) |ii| {
        diff.slice[ii] = @abs(actual.slice[ii] - gold.slice[ii]);
    }
    return diff;
}

fn saveImageCSV(
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    image: *const NDArray(f64),
) !void {
    const rows = image.dims[0];
    const cols = image.dims[1];
    const channels = image.dims[2];

    const SaveCtx = struct {
        fn getVal(
            ctx: *const NDArray(f64),
            row: usize,
            col: usize,
            ch: usize,
        ) f64 {
            return ctx.get(&[_]usize{ row, col, ch });
        }
    };

    try csvio.savePackedGridCSV(
        io,
        dir,
        path,
        rows,
        cols,
        channels,
        image,
        SaveCtx.getVal,
    );
}

fn makeBMPImageArray(
    allocator: std.mem.Allocator,
    image: *const NDArray(f64),
) !NDArray(f64) {
    const rows = image.dims[0];
    const cols = image.dims[1];
    const channels = image.dims[2];
    var bmp_image = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ channels, rows, cols },
    );

    for (0..rows) |rr| {
        for (0..cols) |cc| {
            for (0..channels) |ch| {
                bmp_image.set(
                    &[_]usize{ ch, rr, cc },
                    image.get(&[_]usize{ rr, cc, ch }),
                );
            }
        }
    }

    return bmp_image;
}

fn saveImageArtifacts(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    base_name: []const u8,
    image: *const NDArray(f64),
) !void {
    const csv_name = try std.fmt.allocPrint(allocator, "{s}.csv", .{base_name});
    defer allocator.free(csv_name);
    try saveImageCSV(io, dir, csv_name, image);

    const bmp_name = try std.fmt.allocPrint(allocator, "{s}.bmp", .{base_name});
    defer allocator.free(bmp_name);
    var bmp_image = try makeBMPImageArray(allocator, image);
    defer {
        allocator.free(bmp_image.slice);
        bmp_image.deinit(allocator);
    }
    try iio.saveBMP(io, dir, bmp_name, &bmp_image, 0, .{
        .format = .bmp,
        .bits = 8,
        .scaling = .auto,
        .channels = bmp_image.dims[0],
    });
}

pub fn saveComparisonArtifactsFromResult(
    allocator: std.mem.Allocator,
    io: std.Io,
    fails_root: []const u8,
    dir_name: []const u8,
    result: *const NDArray(f64),
    frame: usize,
    field_start: usize,
    gold_csv_path: []const u8,
    channels: usize,
) !void {
    var out_dir = try openFailsSubDir(io, fails_root, dir_name);
    defer out_dir.close(io);

    var actual = try extractFrameImage(allocator, result, frame, field_start, channels);
    defer {
        allocator.free(actual.slice);
        actual.deinit(allocator);
    }

    var gold = try loadNDArrayFromGold(allocator, io, gold_csv_path, channels);
    defer {
        allocator.free(gold.slice);
        gold.deinit(allocator);
    }

    var diff = try calculateDiffImage(allocator, &actual, &gold);
    defer {
        allocator.free(diff.slice);
        diff.deinit(allocator);
    }

    const base_name = try std.fmt.allocPrint(
        allocator,
        "frame_{d}_field_{d}",
        .{ frame, field_start },
    );
    defer allocator.free(base_name);

    try saveImageArtifacts(allocator, io, out_dir, base_name, &actual);

    const diff_name = try std.fmt.allocPrint(allocator, "{s}_diff", .{base_name});
    defer allocator.free(diff_name);
    try saveImageArtifacts(allocator, io, out_dir, diff_name, &diff);
}

pub fn saveComparisonArtifactsFromImages(
    allocator: std.mem.Allocator,
    io: std.Io,
    fails_root: []const u8,
    dir_name: []const u8,
    actual: *const NDArray(f64),
    gold: *const NDArray(f64),
) !void {
    var out_dir = try openFailsSubDir(io, fails_root, dir_name);
    defer out_dir.close(io);

    var diff = try calculateDiffImage(allocator, actual, gold);
    defer {
        allocator.free(diff.slice);
        diff.deinit(allocator);
    }

    try saveImageArtifacts(allocator, io, out_dir, "frame_0_field_0", actual);
    try saveImageArtifacts(allocator, io, out_dir, "frame_0_field_0_diff", &diff);
}

pub const ShaderFilter = enum { flat, tex, both };

pub fn runTestInternal(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    test_type: []const u8,
    mesh_type: MeshType,
    fov_scale: f64,
    texture: iio.Texture(1),
    pixel_num: [2]u32,
    sample_configs: []const texops.TextureSampleConfig,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    rel_tol: f64,
    abs_tol: f64,
    shader_filter: ShaderFilter,
    report_perf: bool,
) !void {
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const suffix = if (std.mem.eql(u8, test_type, "full"))
        "fullscreen"
    else if (std.mem.eql(u8, test_type, "twoelems"))
        "twoelems"
    else if (std.mem.eql(u8, test_type, "single"))
        "single"
    else
        test_type;

    const data_name = switch (mesh_type) {
        .quad4ibi, .quad4newton => "quad4",
        else => @tagName(mesh_type),
    };

    const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
    const data_path = try std.fmt.allocPrint(
        aa,
        "{s}/{s}",
        .{ data_dir_root, case_name },
    );

    var sim_data = try loadData(aa, io, data_path);
    const uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
    var uvs = try uvio.loadUVMap(aa, io, uv_path);

    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        CameraOps.roiCentFromCoords(&sim_data.coords),
        focal_leng,
        2,
    );

    const disps = [_]bool{ true, false };
    for (disps) |add_disp| {
        const d_str = if (add_disp) "dispon" else "dispoff";

        // --- Flat ShaderInput ---
        if (shader_filter == .flat or shader_filter == .both) {
            const mt_name = @tagName(mesh_type);
            const case_dir_name = try std.fmt.allocPrint(
                aa,
                "{s}_{s}_{s}_flat",
                .{ test_type, mt_name, d_str },
            );

            const flat_dir = try std.fmt.allocPrint(
                aa,
                "{s}/{s}",
                .{ gold_dir_root, case_dir_name },
            );

            const mesh_input = MeshInput{
                .mesh_type = mesh_type,
                .coords = sim_data.coords,
                .connect = sim_data.connect,
                .disp = if (add_disp) sim_data.field else null,
                .shader = .{ .nodal = .{ .field = sim_data.field.?, .bits = 8 } },
            };

            const config = RasterConfig{
                .save_opt = .memory,
                .save_opts = &[_]iio.ImageSaveOpts{
                    .{ .format = .csv, .bits = null, .scaling = .none },
                },
                .report = if (report_perf) .full_stats else .off,
            };

            const result = (try zraster.rasterAllFrames(
                aa,
                io,
                &camera,
                &[_]MeshInput{mesh_input},
                config,
                null,
            )) orelse return error.NoResult;

            defer aa.free(result.slice);

            for (0..result.dims[0]) |f| {
                const fname = try findGoldPath(aa, io, flat_dir, f, 0, false);

                compareNDArrayToGold(
                    aa,
                    io,
                    &result,
                    f,
                    0,
                    1,
                    fname,
                    rel_tol,
                    abs_tol,
                ) catch |err| {
                    const fail_dir_name = try std.fmt.allocPrint(
                        aa,
                        "all_{s}{s}",
                        .{ case_dir_name, impl_suffix },
                    );
                    try saveComparisonArtifactsFromResult(
                        aa,
                        io,
                        default_fails_root,
                        fail_dir_name,
                        &result,
                        f,
                        0,
                        fname,
                        1,
                    );
                    return err;
                };
            }
        }

        // --- Tex ShaderInput ---
        if (shader_filter == .tex or shader_filter == .both) {
            for (sample_configs) |sc| {
                const mt_name = @tagName(mesh_type);
                const case_dir_name = try std.fmt.allocPrint(
                    aa,
                    "{s}_{s}_{s}_tex_{s}_{s}",
                    .{ test_type, mt_name, d_str, @tagName(sc.sample), @tagName(sc.mode) },
                );

                const tex_dir = try std.fmt.allocPrint(
                    aa,
                    "{s}/{s}",
                    .{ gold_dir_root, case_dir_name },
                );

                const mesh_input = MeshInput{
                    .mesh_type = mesh_type,
                    .coords = sim_data.coords,
                    .connect = sim_data.connect,
                    .disp = if (add_disp) sim_data.field else null,
                    .shader = .{
                        .tex_u8 = .{
                            .uvs = uvs.array,
                            .texture = texture,
                            .sample_config = sc,
                        },
                    },
                };

                const config = RasterConfig{
                    .save_opt = .memory,
                    .save_opts = &[_]iio.ImageSaveOpts{
                        .{ .format = .csv, .bits = null, .scaling = .none },
                    },
                    .report = if (report_perf) .full_stats else .off,
                };

                const result = (try zraster.rasterAllFrames(
                    aa,
                    io,
                    &camera,
                    &[_]MeshInput{mesh_input},
                    config,
                    null,
                )) orelse return error.NoResult;

                defer aa.free(result.slice);

                for (0..result.dims[0]) |f| {
                    const fname = try findGoldPath(aa, io, tex_dir, f, 0, false);

                    compareNDArrayToGold(
                        aa,
                        io,
                        &result,
                        f,
                        0,
                        1,
                        fname,
                        rel_tol,
                        abs_tol,
                    ) catch |err| {
                        const fail_dir_name = try std.fmt.allocPrint(
                            aa,
                            "all_{s}{s}",
                            .{ case_dir_name, impl_suffix },
                        );
                        try saveComparisonArtifactsFromResult(
                            aa,
                            io,
                            default_fails_root,
                            fail_dir_name,
                            &result,
                            f,
                            0,
                            fname,
                            1,
                        );
                        return err;
                    };
                }
            }
        }
    }
}

pub fn runMultimeshTest(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const shader_modes = [_]enum { flat, texture }{ .flat, .texture };

    for (shader_modes) |mode| {
        _ = arena.reset(.free_all);
        const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});

        const mesh_inputs = if (mode == .flat)
            try mr.meshInputFromSimDataSlice(
                aa,
                io,
                sim_datas,
                &mesh_types,
                .flat,
                null,
                null,
                null,
            )
        else
            try mr.meshInputFromSimDataSlice(
                aa,
                io,
                sim_datas,
                &mesh_types,
                .texture,
                &dir_paths,
                "texture/speckle-simple.tiff",
                null,
            );

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.1, 0.1, 0.0 }, .{ 3, 2, 1 });

        const pixel_num = [_]u32{ 1200, 800 };
        const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
        const focal_leng: f64 = 50.0e-3;
        const rot = Rotation.init(0, 0, 0);
        const fov_scale_factor: f64 = 1.1;

        const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
        const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
            mesh_inputs,
            pixel_num,
            pixel_size,
            focal_leng,
            rot,
            fov_scale_factor,
        );
        const camera = Camera.init(
            pixel_num,
            pixel_size,
            cam_pos,
            rot,
            roi_pos,
            focal_leng,
            2,
        );

        const config = RasterConfig{
            .save_opt = .memory,
            .save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .csv, .bits = null, .scaling = .none },
            },
            .report = .off,
        };

        const result = (try zraster.rasterAllFrames(
            aa,
            io,
            &camera,
            mesh_inputs,
            config,
            null,
        )) orelse return error.NoResult;

        const gold_dir = if (mode == .flat)
            "gold-multimesh/allelem_flat"
        else
            "gold-multimesh/allelem_tex_cubic_lut_lerp";

        for (0..result.dims[0]) |f| {
            const fname = try findGoldPath(aa, io, gold_dir, f, 0, false);
            compareNDArrayToGold(
                aa,
                io,
                &result,
                f,
                0,
                1,
                fname,
                rel_tol,
                abs_tol,
            ) catch |err| {
                const case_name = if (mode == .flat)
                    "multimesh_allelem_flat"
                else
                    "multimesh_allelem_tex";
                const fail_dir_name = try std.fmt.allocPrint(
                    aa,
                    "all_{s}{s}",
                    .{ case_name, impl_suffix },
                );
                try saveComparisonArtifactsFromResult(
                    aa,
                    io,
                    default_fails_root,
                    fail_dir_name,
                    &result,
                    f,
                    0,
                    fname,
                    1,
                );
                return err;
            };
        }
    }
}

pub fn runMultimeshMixedTest(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    try runMultimeshMixedTestExt(
        outer_alloc,
        io,
        "gold-multimesh/allelem_allshade",
        rel_tol,
        abs_tol,
    );
}

pub fn runMultimeshMixedTestExt(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    gold_dir: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});
    const texture = try iio.loadImage(
        aa,
        io,
        "texture/speckle-simple.tiff",
        .tiff,
        u8,
        1,
    );

    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Flat Shading
    for (0..5) |ii| {
        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = sim_datas[ii].field.?,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    // Bottom Row (5-9): Texture Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .sample_config = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1600, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );

    const config = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .report = .off,
    };
    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &camera,
        mesh_inputs,
        config,
        null,
    )) orelse return error.NoResult;

    for (0..result.dims[0]) |f| {
        const fname = try findGoldPath(aa, io, gold_dir, f, 0, false);
        compareNDArrayToGold(aa, io, &result, f, 0, 1, fname, rel_tol, abs_tol) catch |err| {
            try saveComparisonArtifactsFromResult(
                aa,
                io,
                default_fails_root,
                "all_multimesh_allelem_allshade" ++ impl_suffix,
                &result,
                f,
                0,
                fname,
                1,
            );
            return err;
        };
    }
}

pub fn runMultimeshMixedRGBTest(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    try runMultimeshMixedRGBTestExt(
        outer_alloc,
        io,
        "gold-multimesh/allelem_allshade_rgb",
        rel_tol,
        abs_tol,
    );
}

pub fn runMultimeshMixedRGBTestExt(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    gold_dir: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(outer_alloc);
    defer arena.deinit();
    const aa = arena.allocator();

    const dir_paths = [_][]const u8{
        "data-simple/tri3_twoelems/",
        "data-simple/tri6_twoelems/",
        "data-simple/quad4_twoelems/",
        "data-simple/quad8_twoelems/",
        "data-simple/quad9_twoelems/",
    };

    const mesh_types = [_]MeshType{
        .tri3,
        .tri6,
        .quad4ibi,
        .quad8,
        .quad9,
    };

    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});
    const texture = try iio.loadImage(
        aa,
        io,
        "texture/speckle_rgb.bmp",
        .bmp,
        u8,
        3,
    );

    var mesh_inputs = try aa.alloc(MeshInput, 10);

    // Top Row (0-4): Texture RGB Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_rgb_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .sample_config = .{ .sample = .cubic_catmull_rom, .mode = .lut_lerp },
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    // Bottom Row (5-9): Flat RGB Shading with Gradient
    for (0..5) |ii| {
        const field = sim_datas[ii].field.?;
        const num_coords = sim_datas[ii].coords.mat.rows_num;
        var rgb_field_arr = try NDArray(f64).initFlat(
            aa,
            &[_]usize{ field.array.dims[0], num_coords, 3 },
        );

        const coords = sim_datas[ii].coords;
        var min_x: f64 = std.math.inf(f64);
        var max_x: f64 = -std.math.inf(f64);
        for (0..num_coords) |nn| {
            const x_val = coords.x(nn);
            if (x_val < min_x) min_x = x_val;
            if (x_val > max_x) max_x = x_val;
        }
        const range_x = max_x - min_x;

        for (0..field.array.dims[0]) |tt| {
            for (0..num_coords) |nn| {
                const x_val = coords.x(nn);
                const t = if (range_x > 0) (x_val - min_x) / range_x else 0.5;

                var rr: f64 = 0;
                var gg: f64 = 0;
                var bb: f64 = 0;

                if (t < 0.5) {
                    const t_scaled = t * 2.0;
                    rr = 1.0 - t_scaled;
                    gg = t_scaled;
                    bb = 0.0;
                } else {
                    const t_scaled = (t - 0.5) * 2.0;
                    rr = 0.0;
                    gg = 1.0 - t_scaled;
                    bb = t_scaled;
                }

                rgb_field_arr.set(&[_]usize{ tt, nn, 0 }, rr);
                rgb_field_arr.set(&[_]usize{ tt, nn, 1 }, gg);
                rgb_field_arr.set(&[_]usize{ tt, nn, 2 }, bb);
            }
        }

        const rgb_field = meshio.Field{
            .array = rgb_field_arr,
            .array_mem = rgb_field_arr.slice,
        };

        var coords_dup = try MatSlice(f64).initAlloc(
            aa,
            sim_datas[ii].coords.mat.rows_num,
            sim_datas[ii].coords.mat.cols_num,
        );
        @memcpy(coords_dup.slice, sim_datas[ii].coords.mat.slice);

        mesh_inputs[ii + 5] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.slice, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .nodal = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.1;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_inputs);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_inputs,
        pixel_num,
        pixel_size,
        focal_leng,
        rot,
        fov_scale_factor,
    );
    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        rot,
        roi_pos,
        focal_leng,
        2,
    );

    const config_rgb = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none, .channels = 3 },
        },
        .report = .off,
    };

    const result = (try zraster.rasterAllFrames(
        aa,
        io,
        &camera,
        mesh_inputs,
        config_rgb,
        null,
    )) orelse return error.NoResult;

    for (0..result.dims[0]) |f| {
        const fname = try findGoldPath(aa, io, gold_dir, f, 0, true);
        compareNDArrayToGold(
            aa,
            io,
            &result,
            f,
            0,
            3,
            fname,
            rel_tol,
            abs_tol,
        ) catch |err| {
            try saveComparisonArtifactsFromResult(
                aa,
                io,
                default_fails_root,
                "all_multimesh_allelem_allshade_rgb" ++ impl_suffix,
                &result,
                f,
                0,
                fname,
                3,
            );
            return err;
        };
    }
}
