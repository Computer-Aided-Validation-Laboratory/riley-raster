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

pub const specraster = @import("../zigraster/zig/specraster.zig");
pub const RasterConfig = specraster.RasterConfig;

pub const texio = @import("../zigraster/zig/textureio.zig");
pub const textureinterp = @import("../zigraster/zig/textureinterp.zig");
pub const iops = @import("../zigraster/zig/imageops.zig");
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
    return try meshio.load_sim_data(allocator, io, pc, pn, pf[0..]);
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
            try iops.saveImage(io, out_dir, name, &mat, .csv, 8);
            try iops.saveImage(io, out_dir, name, &mat, .bmp, 8);
        }
    }
}

pub const ShaderFilter = enum { flat, tex, both };

pub fn runTestInternal(allocator: std.mem.Allocator,
                       io: std.Io,
                       test_type: []const u8,
                       mesh_type: MeshType,
                       fov_scale: f64,
                       texture: texio.Texture(u8, 1),
                       pixel_num: [2]u32,
                       interp_types: []const textureinterp.InterpType,
                       gold_dir_root: []const u8,
                       data_dir_root: []const u8,
                       rel_tol: f64,
                       abs_tol: f64,
                       shader_filter: ShaderFilter) !void {

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const suffix = if (std.mem.eql(u8, test_type, "full")) "fullscreen" else "single";
    
    const data_name = switch (mesh_type) {
        .quad4ibi, .quad4newton => "quad4",
        else => @tagName(mesh_type),
    };
    const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
    const data_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ data_dir_root, case_name });
    
    var sim_data = try loadData(aa, io, data_path);
    const uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
    var uvs = try uvio.loadTexMap(aa, io, uv_path);

    const elem_coords = try mr.transformCoords(aa, &sim_data.coords, &sim_data.connect);
    const elem_disp = try mr.transformField(aa, &sim_data.connect, &sim_data.field);
    const elem_uvs = try mr.transformUVs(aa, &uvs, &sim_data.connect);

    const cam_pos = CameraOps.pos_fill_frame_from_rot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, fov_scale,
    );
    const camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, 
        CameraOps.roi_cent_from_coords(&sim_data.coords), focal_leng, 2,
    );

    const disps = [_]bool{ true, false };
    for (disps) |add_disp| {
        const d_str = if (add_disp) "dispon" else "dispoff";
        
        // --- Flat Shader ---
        if (shader_filter == .flat or shader_filter == .both) {

            const case_dir_name = try std.fmt.allocPrint(
                aa, "{s}_{s}_{s}_flat", .{ test_type, @tagName(mesh_type), d_str }
            );

            const flat_dir = try std.fmt.allocPrint(
                aa, "{s}/{s}", .{ gold_dir_root, case_dir_name }
            );

            var mesh_raster = MeshRaster{ 
                .mesh_type = mesh_type, 
                .coords = elem_coords, 
                .disp = if (add_disp) elem_disp else null, 
                .shader = .{ .flat = .{ .field = elem_disp, .bits = 8 } } 
            };

            const config = RasterConfig{ .save_opt = .memory, .tile_size = 32 };

            const result = (try specraster.rasterAllFrames(
                aa, io, &camera, &mesh_raster, config, null
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
                const case_dir_name = try std.fmt.allocPrint(
                    aa, "{s}_{s}_{s}_tex_{s}", 
                    .{ test_type, @tagName(mesh_type), d_str, @tagName(it) }
                );
                
                const tex_dir = try std.fmt.allocPrint(
                    aa, "{s}/{s}", .{ gold_dir_root, case_dir_name }
                );
                
                var mesh_raster = MeshRaster{ 
                    .mesh_type = mesh_type, 
                    .coords = elem_coords, 
                    .disp = if (add_disp) elem_disp else null, 
                    .shader = .{ 
                        .texture = .{ 
                            .uvs = elem_uvs, .texture = texture, .interp_type = it 
                        } 
                    } 
                };
                
                const config = RasterConfig{ .save_opt = .memory, .tile_size = 32 };

                const result = (try specraster.rasterAllFrames(
                    aa, io, &camera, &mesh_raster, config, null
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
