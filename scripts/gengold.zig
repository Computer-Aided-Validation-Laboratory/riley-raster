const std = @import("std");

pub const meshio = @import("zigraster/meshio.zig");
pub const SimData = meshio.SimData;
pub const mr = @import("zigraster/meshraster.zig");
pub const MeshType = mr.MeshType;
pub const MeshRaster = mr.MeshRaster;
pub const Rotation = @import("zigraster/rotation.zig").Rotation;
pub const Camera = @import("zigraster/camera.zig").Camera;
pub const CameraOps = @import("zigraster/camera.zig").CameraOps;
pub const unifiedraster = @import("zigraster/unifiedraster.zig");
pub const RasterConfig = unifiedraster.RasterConfig;
pub const texio = @import("zigraster/textureio.zig");
pub const textureinterp = @import("zigraster/textureinterp.zig");
pub const iops = @import("zigraster/imageops.zig");
pub const uvio = @import("zigraster/uvio.zig");

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

pub fn renderAndSave(allocator: std.mem.Allocator, io: std.Io, camera: *const Camera, 
                      mt: MeshType, coords: mr.NDArray(f64), disp: ?mr.NDArray(f64), 
                      shader: mr.FieldShader, dir: []const u8, add_disp: bool) !void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, dir, .default_dir) catch |err| if (err != error.PathAlreadyExists) return err;
    var out_dir = try cwd.openDir(io, dir, .{});
    defer out_dir.close(io);

    var mesh_raster = MeshRaster{ 
        .mesh_type = mt, 
        .coords = coords, 
        .disp = if (add_disp) disp else null, 
        .shader = shader 
    };
    const config = RasterConfig{ 
        .save_opt = .disk, 
        .save_formats = &[_]iops.ImageFormat{ .csv, .bmp }, 
        .tile_size = 32 
    };
    
    _ = try unifiedraster.rasterAllFrames(allocator, io, camera, &mesh_raster, config, out_dir);
}

pub fn runGenerationExt(allocator: std.mem.Allocator, 
                         io: std.Io, 
                         test_type: []const u8, 
                         mesh_types: []const MeshType,
                         fov_scale: f64,
                         texture: texio.Texture(u8, 1),
                         pixel_num: [2]u32,
                         interp_types: []const textureinterp.InterpolationType,
                         gold_dir_root: []const u8,
                         data_dir_root: []const u8) !void {
    
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const suffix = if (std.mem.eql(u8, test_type, "full")) "fullscreen" else "single";
    for (mesh_types) |mt| {
        _ = arena.reset(.free_all);
        const data_name = switch (mt) {
            .quad4ibi, .quad4newton => "quad4",
            else => @tagName(mt),
        };
        const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
        const data_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ data_dir_root, case_name });
        
        var sim_data = loadData(aa, io, data_path) catch |err| {
            std.debug.print("Failed to load data for {s}: {any}\n", .{case_name, err});
            continue;
        };
        var uvs = try uvio.loadTexMap(aa, io, try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path}));

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
            
            // Flat Shader
            const flat_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_flat", .{ gold_dir_root, test_type, @tagName(mt), d_str });
            try renderAndSave(aa, io, &camera, mt, elem_coords, elem_disp, 
                .{ .flat = .{ .field = elem_disp, .bits = 8 } }, flat_dir, add_disp);

            // Tex Shader
            for (interp_types) |it| {
                const tex_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_tex_{s}", .{ gold_dir_root, test_type, @tagName(mt), d_str, @tagName(it) });
                try renderAndSave(aa, io, &camera, mt, elem_coords, elem_disp, 
                    .{ .texture = .{ .uvs = elem_uvs, .texture = texture, .interp_type = it } }, tex_dir, add_disp);
            }
        }
    }
}

pub fn runGeneration(allocator: std.mem.Allocator, 
                      io: std.Io, 
                      test_type: []const u8, 
                      mesh_types: []const MeshType,
                      fov_scale: f64,
                      texture: texio.Texture(u8, 1)) !void {
    const interp_types = [_]textureinterp.InterpolationType{ .cubic_lut_lerp };
    const pixel_num = [_]u32{ 320, 200 };
    return runGenerationExt(allocator, io, test_type, mesh_types, fov_scale, texture, pixel_num, &interp_types, "gold-simple", "data-simple");
}
