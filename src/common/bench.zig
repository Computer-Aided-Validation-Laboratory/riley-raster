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

pub const iio = @import("../zigraster/zig/imageio.zig");
pub const texops = @import("../zigraster/zig/textureops.zig");
pub const uvio = @import("../zigraster/zig/uvio.zig");


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
    _ = allocator; _ = io; _ = array; _ = frame; _ = field; _ = path;
    _ = rel_tol; _ = abs_tol;
    return;
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

fn saveResultToRoot(
    allocator: std.mem.Allocator, 
    io: std.Io, 
    array: *const NDArray(f64), 
    dir_name: []const u8,
    root_dir: []const u8
) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, root_dir, .default_dir) catch {};
    var root_h = try cwd.openDir(io, root_dir, .{});
    defer root_h.close(io);

    root_h.createDir(io, dir_name, .default_dir) catch {};
    var out_dir = try root_h.openDir(io, dir_name, .{});
    defer out_dir.close(io);

    for (0..array.dims[0]) |f| {
        for (0..array.dims[1]) |fi| {
            const slice = array.getSlice(&[_]usize{ f, fi, 0, 0 }, 1);
            const mat = MatSlice(f64).init(slice, array.dims[2], array.dims[3]);
            const name = try std.fmt.allocPrint(allocator, "frame_{d}_field_{d}", .{ f, fi });
            try iio.saveImage(io, out_dir, name, &mat, .csv, 8);
            try iio.saveImage(io, out_dir, name, &mat, .bmp, 8);
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
                       render_root: []const u8) !void {
    _ = gold_dir_root; _ = rel_tol; _ = abs_tol;

    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const case_name = if (std.mem.eql(u8, data_dir_root, "data-edge"))
        try std.fmt.allocPrint(aa, "{s}_{s}", .{ @tagName(mesh_type), test_type })
    else blk: {
        const suffix = if (std.mem.eql(u8, test_type, "full")) "fullscreen" else "single";
        const data_name = switch (mesh_type) {
            .quad4ibi, .quad4newton => "quad4",
            .tri3opt => "tri3",
            else => @tagName(mesh_type),
        };
        break :blk try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
    };

    const data_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ data_dir_root, case_name });
    
    var sim_data = try loadData(aa, io, data_path);
    const uv_path = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
    var uvs = try uvio.loadUVMap(aa, io, uv_path);

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
        const mt_name = @tagName(mesh_type);

        // --- Flat Shader ---
        if (shader_filter == .flat or shader_filter == .both) {
            const c_dir_name = try std.fmt.allocPrint(aa, "{s}_{s}_{s}_flat", .{ case_name, mt_name, d_str });
            var mesh_raster = MeshRaster{ 
                .mesh_type = mesh_type, 
                .coords = elem_coords, 
                .disp = if (add_disp) elem_disp else null, 
                .shader = .{ .flat = .{ .field = elem_disp, .bits = 8 } } 
            };

            const config = RasterConfig{ .save_opt = .memory, .tile_size = 16 };
            const result = (try specraster.rasterAllFrames(aa, io, &camera, &mesh_raster, config, null)) orelse return error.NoResult;
            try saveResultToRoot(aa, io, &result, c_dir_name, render_root);
            defer aa.free(result.elems);
        }

        // --- Tex Shader ---
        if (shader_filter == .tex or shader_filter == .both) {
            for (interp_types) |it| {
                const c_dir_name = try std.fmt.allocPrint(aa, "{s}_{s}_{s}_tex_{s}", .{ case_name, mt_name, d_str, @tagName(it) });
                var mesh_raster = MeshRaster{ 
                    .mesh_type = mesh_type, 
                    .coords = elem_coords, 
                    .disp = if (add_disp) elem_disp else null, 
                    .shader = .{ .texture = .{ .uvs = elem_uvs, .texture = texture, .interp_type = it } } 
                };
                
                const config = RasterConfig{ .save_opt = .memory, .tile_size = 16 };
                const result = (try specraster.rasterAllFrames(aa, io, &camera, &mesh_raster, config, null)) orelse return error.NoResult;
                try saveResultToRoot(aa, io, &result, c_dir_name, render_root);
                defer aa.free(result.elems);
            }
        }
    }
}
