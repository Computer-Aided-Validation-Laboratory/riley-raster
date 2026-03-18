const std = @import("std");

pub const NDArray = @import("../zigraster/zig/ndarray.zig").NDArray;
pub const MatSlice = @import("../zigraster/zig/matslice.zig").MatSlice; 

pub const meshio = @import("../zigraster/zig/meshio.zig");
pub const SimData = meshio.SimData;

pub const mr = @import("../zigraster/zig/meshraster.zig");
pub const MeshType = mr.MeshType;
pub const MeshRaster = mr.MeshRaster;

pub const Rotation = @import("../zigraster/zig/rotation.zig").Rotation;
pub const Camera = @import("../zigraster/zig/camera.zig").Camera;
pub const CameraOps = @import("../zigraster/zig/camera.zig").CameraOps;

pub const zraster = @import("../zigraster/zig/zraster.zig");
pub const RasterConfig = zraster.RasterConfig;

pub const iio = @import("../zigraster/zig/imageio.zig");
pub const texops = @import("../zigraster/zig/textureops.zig");
pub const uvio = @import("../zigraster/zig/uvio.zig");


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

pub fn compareNDArrayToCSV(allocator: std.mem.Allocator, 
                           io: std.Io, array: *const NDArray(f64), 
                           frame: usize, field: usize, 
                           path: []const u8, 
                           rel_tol: f64,
                           abs_tol: f64) !void {
                           
    var lines = try meshio.readCsvToList(allocator, io, path);
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    const rows = array.dims[2];
    const cols = array.dims[3];
    
    if (lines.items.len != rows) {
        std.debug.print(
            "Row count mismatch: CSV has {d}, array expects {d} (path: {s})\n", 
            .{lines.items.len, rows, path}
        );
        return error.CSVRowsMismatch;
    }

    for (lines.items, 0..) |line, r| {
        var iter = std.mem.splitScalar(u8, line, ',');
        for (0..cols) |c| {
            const val_str = iter.next() orelse {
                std.debug.print(
                    "Column count mismatch at row {d}: missing value (path: {s})\n", 
                    .{r, path}
                );
                return error.CSVColsMismatch;
            };
            const gold_val = try std.fmt.parseFloat(f64, std.mem.trim(u8, val_str, " \r\n\t"));
            const actual_val = array.get(&[_]usize{ frame, field, r, c });
            
            if (!isApproxEqual(gold_val, actual_val, rel_tol, abs_tol)) {
                const abs_gold = @abs(gold_val);
                const abs_act = @abs(actual_val);
                const largest = if (abs_gold > abs_act) abs_gold else abs_act;

                const diff = @abs(gold_val - actual_val);
                const rel_diff = if (largest < abs_tol) diff else diff / largest;

                std.debug.print(
                    "\n\nMismatch at:\n frame {d},\n field {d},\n pixel ({d}, {d}): " ++
                    "\n gold={d},\n actual={d},\n rel_diff={e}\n (path: {s})\n\n", 
                    .{ frame, field, r, c, gold_val, actual_val, rel_diff, path }
                );
                return error.PixelMismatch;
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

fn saveResultToFails(
    allocator: std.mem.Allocator, 
    io: std.Io, 
    array: *const NDArray(f64), 
    dir_name: []const u8
) !void {
    const cwd = std.Io.Dir.cwd();
    const fails_root = "fails";
    cwd.createDir(io, fails_root, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var fails_dir = try cwd.openDir(io, fails_root, .{});
    defer fails_dir.close(io);

    fails_dir.createDir(io, dir_name, .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    var out_dir = try fails_dir.openDir(io, dir_name, .{});
    defer out_dir.close(io);

    for (0..array.dims[0]) |f| {
        for (0..array.dims[1]) |fi| {
            const slice = array.getSlice(&[_]usize{ f, fi, 0, 0 }, 1);
            const mat = MatSlice(f64).init(slice, array.dims[2], array.dims[3]);
            const name = try std.fmt.allocPrint(allocator, "frame_{d}_field_{d}", .{ f, fi });
            try iio.saveMatAsImage(io, out_dir, name, &mat, 
                .{ .format = .csv, .bits = null, .scaling = .none });
            try iio.saveMatAsImage(io, out_dir, name, &mat, 
                .{ .format = .bmp, .bits = 8, .scaling = .auto });
        }
    }
}

pub const ShaderFilter = enum { flat, tex, both };

pub fn runTestInternal(allocator: std.mem.Allocator,
                       io: std.Io,
                       test_type: []const u8,
                       mesh_type: MeshType,
                       fov_scale: f64,
                       texture: iio.Texture(u8, 1),
                       pixel_num: [2]u32,
                       interp_types: []const texops.InterpType,
                       gold_dir_root: []const u8,
                       data_dir_root: []const u8,
                       rel_tol: f64,
                       abs_tol: f64,
                       shader_filter: ShaderFilter,
                       report_perf: bool) !void {

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
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
        .tri3opt => "tri3",
        else => @tagName(mesh_type),
    };
    const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
    const data_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ data_dir_root, case_name });
    
    var sim_data = try loadData(aa, io, data_path);
    const uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
    var uvs = try uvio.loadUVMap(aa, io, uv_path);

    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, fov_scale,
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, 
        CameraOps.roiCentFromCoords(&sim_data.coords), focal_leng, 2,
    );

    const disps = [_]bool{ true, false };
    for (disps) |add_disp| {
        const d_str = if (add_disp) "dispon" else "dispoff";
        
        // --- Flat Shader ---
        if (shader_filter == .flat or shader_filter == .both) {

            const mt_name = @tagName(mesh_type);
            const case_dir_name = try std.fmt.allocPrint(
                aa, "{s}_{s}_{s}_flat", .{ test_type, mt_name, d_str }
            );

            const flat_dir = try std.fmt.allocPrint(
                aa, "{s}/{s}", .{ gold_dir_root, case_dir_name }
            );

            const mesh_raster = MeshRaster{ 
                .mesh_type = mesh_type, 
                .coords = sim_data.coords, 
                .connect = sim_data.connect,
                .disp = if (add_disp) sim_data.field else null, 
                .shader = .{ .flat = .{ .field = sim_data.field.?, .bits = 8 } } 
            };


            const config = RasterConfig{ 
                .save_opt = .memory, 
                .save_opts = &[_]iio.ImageSaveOpts{
                    .{ .format = .csv, .bits = null, .scaling = .none },
                },
                .tile_size = 16,
                .report = if (report_perf) .perf else .off
            };

            const result = (try zraster.rasterAllFrames(
                aa, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
            )) orelse return error.NoResult;

            defer aa.free(result.elems);

            for (0..result.dims[0]) |f| {

                const fname = try std.fmt.allocPrint(
                    aa, "{s}/frame_{d}_field_0.csv", .{ flat_dir, f }
                );
                
                compareNDArrayToCSV(aa, io, &result, f, 0, fname, rel_tol, abs_tol) 
                    catch |err| {
                        try saveResultToFails(aa, io, &result, case_dir_name);
                        return err;
                };
            }
        }

        // --- Tex Shader ---
        if (shader_filter == .tex or shader_filter == .both) {
            for (interp_types) |it| {
                const mt_name = @tagName(mesh_type);
                const case_dir_name = try std.fmt.allocPrint(
                    aa, "{s}_{s}_{s}_tex_{s}", 
                    .{ test_type, mt_name, d_str, @tagName(it) }
                );
                
                const tex_dir = try std.fmt.allocPrint(
                    aa, "{s}/{s}", .{ gold_dir_root, case_dir_name }
                );
                
                const mesh_raster = MeshRaster{ 
                    .mesh_type = mesh_type, 
                    .coords = sim_data.coords, 
                    .connect = sim_data.connect,
                    .disp = if (add_disp) sim_data.field else null, 
                    .shader = .{ 
                        .tex_u8 = .{ 
                            .uvs = uvs.array, .texture = texture, .interp_type = it 
                        } 
                    } 
                };
                
                const config = RasterConfig{ 
                    .save_opt = .memory, 
                    .save_opts = &[_]iio.ImageSaveOpts{
                        .{ .format = .csv, .bits = null, .scaling = .none },
                    },
                    .tile_size = 16,
                    .report = if (report_perf) .perf else .off
                };

                const result = (try zraster.rasterAllFrames(
                    aa, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
                )) orelse return error.NoResult;

                defer aa.free(result.elems);

                for (0..result.dims[0]) |f| {
                    const fname = try std.fmt.allocPrint(
                        aa, "{s}/frame_{d}_field_0.csv", .{ tex_dir, f }
                    );
                    
                    compareNDArrayToCSV(aa, io, &result, f, 0, fname, rel_tol, abs_tol) 
                        catch |err| {
                            try saveResultToFails(aa, io, &result, case_dir_name);
                            return err;
                    };
                }
            }
        }
    }
}

pub fn runMultimeshTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
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

        const mesh_rasters = if (mode == .flat)
            try mr.meshRasterFromSimDataSlice(
                aa, io, sim_datas, &mesh_types, .flat, null, null, null
            )
        else
            try mr.meshRasterFromSimDataSlice(
                aa, io, sim_datas, &mesh_types, .texture, &dir_paths, 
                "texture/speckle-simple.tiff", null
            );

        mr.arrangeMeshSlice(mesh_rasters, .{ 0.1, 0.1, 0.0 }, .{ 3, 2, 1 });

        const pixel_num = [_]u32{ 1200, 800 };
        const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
        const focal_leng: f64 = 50.0e-3;
        const rot = Rotation.init(0, 0, 0);
        const fov_scale_factor: f64 = 1.1;

        const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
        const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
            mesh_rasters, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor,
        );
        const camera = Camera.init(
            pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 2
        );

        const config = RasterConfig{
            .save_opt = .memory,
            .save_opts = &[_]iio.ImageSaveOpts{
                .{ .format = .csv, .bits = null, .scaling = .none },
            },
            .tile_size = 32,
        };

        const result = (try zraster.rasterAllFrames(aa, io, &camera, mesh_rasters, config, null)) 
            orelse return error.NoResult;

        const gold_dir = if (mode == .flat)
            "gold-multimesh/allelem_flat"
        else
            "gold-multimesh/allelem_tex_cubic_lut_lerp";

        for (0..result.dims[0]) |f| {
            const fname = try std.fmt.allocPrint(aa, "{s}/frame_{d}_field_0.csv", .{ gold_dir, f });
            compareNDArrayToCSV(aa, io, &result, f, 0, fname, rel_tol, abs_tol) catch |err| {
                const case_name = if (mode == .flat) "multimesh_allelem_flat" 
                                  else "multimesh_allelem_tex";
                try saveResultToFails(aa, io, &result, case_name);
                return err;
            };
        }
    }
}

pub fn runMultimeshMixedTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    try runMultimeshMixedTestExt(
        allocator, io, "gold-multimesh/allelem_allshade", rel_tol, abs_tol
    );
}

pub fn runMultimeshMixedTestExt(
    allocator: std.mem.Allocator,
    io: std.Io,
    gold_dir: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
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
        aa, io, "texture/speckle-simple.tiff", .tiff, u8, 1
    );

    var mesh_rasters = try aa.alloc(MeshRaster, 10);

    // Top Row (0-4): Flat Shading
    for (0..5) |ii| {
        var coords_dup = try MatSlice(f64).initAlloc(
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .flat = .{
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
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii + 5] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_rasters, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1600, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_rasters, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 2
    );

    const config = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 32,
    };

    const result = (try zraster.rasterAllFrames(aa, io, &camera, mesh_rasters, config, null)) 
        orelse return error.NoResult;

    for (0..result.dims[0]) |f| {
        const fname = try std.fmt.allocPrint(aa, "{s}/frame_{d}_field_0.csv", .{ gold_dir, f });
        compareNDArrayToCSV(aa, io, &result, f, 0, fname, rel_tol, abs_tol) catch |err| {
            try saveResultToFails(aa, io, &result, "multimesh_allelem_allshade");
            return err;
        };
    }
}

pub fn runMultimeshMixedRGBTest(
    allocator: std.mem.Allocator,
    io: std.Io,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    try runMultimeshMixedRGBTestExt(
        allocator, io, "gold-multimesh/allelem_allshade_rgb", rel_tol, abs_tol
    );
}

pub fn runMultimeshMixedRGBTestExt(
    allocator: std.mem.Allocator,
    io: std.Io,
    gold_dir: []const u8,
    rel_tol: f64,
    abs_tol: f64,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
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
        aa, io, "texture/speckle_rgb.bmp", .bmp, u8, 3
    );

    var mesh_rasters = try aa.alloc(MeshRaster, 10);

    // Top Row (0-4): Texture RGB Shading
    for (0..5) |ii| {
        const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[ii]});
        const uvs = try uvio.loadUVMap(aa, io, uv_path);

        var coords_dup = try MatSlice(f64).initAlloc(
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .tex_rgb_u8 = .{
                .uvs = uvs.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
                .bits = 8,
                .scaling = .none,
            } },
        };
    }

    // Bottom Row (5-9): Flat RGB Shading with Gradient
    for (0..5) |ii| {
        const field = sim_datas[ii].field.?;
        const num_coords = sim_datas[ii].coords.mat.rows_num;
        var rgb_field_arr = try zraster.NDArray(f64).initFlat(
            aa, &[_]usize{ field.array.dims[0], num_coords, 3 }
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
            .array_mem = rgb_field_arr.elems,
        };

        var coords_dup = try MatSlice(f64).initAlloc(
            aa, sim_datas[ii].coords.mat.rows_num, sim_datas[ii].coords.mat.cols_num
        );
        @memcpy(coords_dup.elems, sim_datas[ii].coords.mat.elems);

        mesh_rasters[ii + 5] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
            .connect = sim_datas[ii].connect,
            .disp = sim_datas[ii].field,
            .shader = .{ .flat = .{
                .field = rgb_field,
                .bits = 8,
                .scaling = .auto,
                .scale_over = .within_frames,
            } },
        };
    }

    mr.arrangeMeshSlice(mesh_rasters, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });

    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.1;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_rasters, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, 3
    );

    const config_rgb = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none, .channels = 3 },
        },
        .tile_size = 32,
    };

    const result = (try zraster.rasterAllFrames(aa, io, &camera, mesh_rasters, config_rgb, null))
        orelse return error.NoResult;

    for (0..result.dims[0]) |f| {
        const fname = try std.fmt.allocPrint(aa, "{s}/frame_{d}_field_0_2.csv", .{ gold_dir, f });
        compareNDArrayToCSV(aa, io, &result, f, 0, fname, rel_tol, abs_tol) catch |err| {
            try saveResultToFails(aa, io, &result, "multimesh_allelem_allshade_rgb");
            return err;
        };
    }
}


test "Flat Shader Scaling Options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const data_path = "data-simple/tri3_twoelems";
    var sim_data = try loadData(allocator, io, data_path);

    const pixel_num = [_]u32{ 16, 16 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, 1.1,
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, 
        CameraOps.roiCentFromCoords(&sim_data.coords), focal_leng, 1,
    );

    const config = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 16,
    };

    // Test 1: Auto Scaling, bits = null (maps to 0.0 - 1.0)
    var mesh_raster = MeshRaster{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .flat = .{ 
            .field = sim_data.field.?, 
            .bits = null, 
            .scaling = .auto, 
            .scale_over = .over_frames 
        } }
    };
    
    var result_auto_float = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_auto_float.elems);

    for (result_auto_float.elems) |v| {
        if (!(v >= 0.0 and v <= 1.0) and v != 0.0) {
            std.debug.print("FAIL Test 1: v = {d}\n", .{v});
        }
        try std.testing.expect(v >= 0.0 and v <= 1.0);
    }

    // Test 2: Auto Scaling, bits = 8 (maps to 0 - 255)
    mesh_raster.shader.flat.bits = 8;
    var result_auto_int = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_auto_int.elems);
    for (result_auto_int.elems) |v| {
        if (!(v >= 0.0 and v <= 255.0) and v != 0.0) {
            std.debug.print("FAIL Test 2: v = {d}\n", .{v});
        }
        try std.testing.expect(v >= 0.0 and v <= 255.0);
    }

    // Test 3: Frac Scaling [0.4, 0.6], bits = 8
    mesh_raster.shader.flat.scaling = .{ .frac = .{ 0.4, 0.6 } };
    var result_frac_int = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_frac_int.elems);
    for (result_frac_int.elems) |v| {
        if (v != 0.0) { // ignoring background which defaults to 0.0
            if (!(v >= 102.0 and v <= 153.0)) {
                std.debug.print("FAIL Test 3: v = {d}\n", .{v});
            }
            try std.testing.expect(v >= 102.0 and v <= 153.0);
        }
    }
}

test "Tex Shader Scaling Options" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa_alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa_alloc);
    defer arena.deinit();
    const allocator = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const data_path = "data-simple/tri3_twoelems";
    var sim_data = try loadData(allocator, io, data_path);

    const uv_path = "data-simple/tri3_twoelems/uvs.csv";
    var uvs = try uvio.loadUVMap(allocator, io, uv_path);

    // Create a simple dummy texture where all pixels are 100
    var texture = try iio.Texture(u8, 1).init(allocator, 10, 10);
    for (0..10) |r| {
        for (0..10) |c| {
            texture.setPixel(r, c, .{ .channels = [_]u8{100} });
        }
    }

    const pixel_num = [_]u32{ 16, 16 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, 1.1,
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, 
        CameraOps.roiCentFromCoords(&sim_data.coords), focal_leng, 1,
    );

    const config = RasterConfig{
        .save_opt = .memory,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .csv, .bits = null, .scaling = .none },
        },
        .tile_size = 16,
    };

    // Test 1: Auto Scaling, bits = null (maps to 0.0 - 1.0)
    // Wait, since all pixels are 100, min=100, max=100. Range=1.0. 
    // Normalized value = (100 - 100)/1 = 0.0.
    // Let's modify the texture to have min 0 and max 200.
    texture.setPixel(0, 0, .{ .channels = [_]u8{0} });
    texture.setPixel(0, 1, .{ .channels = [_]u8{200} });

    var mesh_raster = MeshRaster{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .tex_u8 = .{ 
            .uvs = uvs.array,
            .texture = texture,
            .bits = null, 
            .scaling = .auto, 
        } }
    };
    
    var result_auto_float = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_auto_float.elems);

    for (result_auto_float.elems) |v| {
        try std.testing.expect(v >= 0.0 and v <= 1.0);
    }

    // Test 2: Auto Scaling, bits = 8 (maps to 0 - 255)
    mesh_raster.shader.tex_u8.bits = 8;
    var result_auto_int = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_auto_int.elems);
    for (result_auto_int.elems) |v| {
        try std.testing.expect(v >= 0.0 and v <= 255.0);
    }

    // Test 3: Frac Scaling [0.4, 0.6], bits = 8
    mesh_raster.shader.tex_u8.scaling = .{ .frac = .{ 0.4, 0.6 } };
    var result_frac_int = (try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]MeshRaster{mesh_raster}, config, null
    )).?;
    defer allocator.free(result_frac_int.elems);
    for (result_frac_int.elems) |v| {
        if (v != 0.0) { // ignoring background
            try std.testing.expect(v >= 102.0 and v <= 153.0);
        }
    }
}
