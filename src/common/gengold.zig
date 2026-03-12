const std = @import("std");

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

pub fn renderAndSave(
    allocator: std.mem.Allocator,
    io: std.Io,
    camera: *const Camera,
    mt: MeshType,
    coords: mr.NDArray(f64),
    disp: ?mr.NDArray(f64),
    sh: mr.FieldShader,
    dir: []const u8,
    add_disp: bool,
    config: RasterConfig,
) !void {
    const cwd = std.Io.Dir.cwd();
    // Manual recursive directory creation since makePath isn't in std.Io.Dir
    var iter = std.mem.splitScalar(u8, dir, '/');
    var path_buf: [256]u8 = undefined;
    var path_len: usize = 0;
    while (iter.next()) |part| {
        if (path_len > 0) {
            path_buf[path_len] = '/';
            path_len += 1;
        }
        std.mem.copyForwards(u8, path_buf[path_len..], part);
        path_len += part.len;
        cwd.createDir(io, path_buf[0..path_len], .default_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }
    var out_dir = try cwd.openDir(io, dir, .{});
    defer out_dir.close(io);

    var mesh_raster = MeshRaster{
        .mesh_type = mt,
        .coords = coords,
        .disp = if (add_disp) disp else null,
        .shader = sh,
    };

    _ = try specraster.rasterAllFrames(allocator, io, camera, &mesh_raster, config, out_dir);
}

pub fn runGenerationExt(
    allocator: std.mem.Allocator,
    io: std.Io,
    test_type: []const u8,
    mesh_types: []const MeshType,
    fov_scale: f64,
    texture: iio.Texture(u8, 1),
    pixel_num: [2]u32,
    interp_types: []const texops.InterpType,
    gold_dir_root: []const u8,
    data_dir_root: []const u8,
    config: RasterConfig,
) !void {
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const suffix = if (std.mem.eql(u8, test_type, "full"))
        "fullscreen"
    else if (std.mem.eql(u8, test_type, "single"))
        "single"
    else
        test_type;
    for (mesh_types) |mt| {
        _ = arena.reset(.free_all);
        const data_name = switch (mt) {
            .quad4ibi, .quad4newton => "quad4",
            .tri3opt => "tri3",
            else => @tagName(mt),
        };
        const case_name = try std.fmt.allocPrint(aa, "{s}_{s}", .{ data_name, suffix });
        const data_path = try std.fmt.allocPrint(aa, "{s}/{s}", .{ data_dir_root, case_name });

        var sim_data = loadData(aa, io, data_path) catch |err| {
            std.debug.print("Failed to load data for {s}: {any}\n", .{ case_name, err });
            continue;
        };
        const uv_p = try std.fmt.allocPrint(aa, "{s}/uvs.csv", .{data_path});
        var uvs = try uvio.loadUVMap(aa, io, uv_p);

        const elem_coords = try mr.transformCoords(aa, &sim_data.coords, &sim_data.connect);
        const elem_disp = try mr.transformField(aa, &sim_data.connect, &sim_data.field);
        const elem_uvs = try mr.transformUVs(aa, &uvs, &sim_data.connect);

        const cam_pos = CameraOps.pos_fill_frame_from_rot(
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
            CameraOps.roi_cent_from_coords(&sim_data.coords),
            focal_leng,
            2,
        );

        const disps = [_]bool{ true, false };
        for (disps) |add_disp| {
            const d_str = if (add_disp) "dispon" else "dispoff";

            // Flat Shader
            const flat_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_flat", .{
                gold_dir_root,
                test_type,
                @tagName(mt),
                d_str,
            });
            try renderAndSave(aa, io, &camera, mt, elem_coords, elem_disp, .{
                .flat = .{ .field = elem_disp, .bits = 8 },
            }, flat_dir, add_disp, config);

            // Tex Shader
            for (interp_types) |it| {
                const tex_dir = try std.fmt.allocPrint(aa, "{s}/{s}_{s}_{s}_tex_{s}", .{
                    gold_dir_root,
                    test_type,
                    @tagName(mt),
                    d_str,
                    @tagName(it),
                });
                try renderAndSave(aa, io, &camera, mt, elem_coords, elem_disp, .{
                    .texture = .{
                        .uvs = elem_uvs,
                        .texture = texture,
                        .interp_type = it,
                    },
                }, tex_dir, add_disp, config);
            }
        }
    }
}

pub fn runGeneration(
    allocator: std.mem.Allocator,
    io: std.Io,
    test_type: []const u8,
    mesh_types: []const MeshType,
    fov_scale: f64,
    texture: iio.Texture(u8, 1),
) !void {
    const interp_types = [_]texops.InterpType{.cubic_lut_lerp};
    const pixel_num = [_]u32{ 320, 200 };
    const config = RasterConfig{
        .save_opt = .disk,
        .save_formats = &[_]iio.ImageFormat{ .csv, .bmp },
        .tile_size = 16,
    };
    return runGenerationExt(
        allocator,
        io,
        test_type,
        mesh_types,
        fov_scale,
        texture,
        pixel_num,
        &interp_types,
        "gold-simple",
        "data-simple",
        config,
    );
}
