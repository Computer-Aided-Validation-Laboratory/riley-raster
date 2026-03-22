const std = @import("std");
const zraster = @import("zigraster/zig/zraster.zig");
const shaderops = @import("zigraster/zig/shaderops.zig");
const meshraster = @import("zigraster/zig/meshraster.zig");
const meshio = @import("zigraster/zig/meshio.zig");
const Camera = @import("zigraster/zig/camera.zig").Camera;
const NDArray = @import("zigraster/zig/ndarray.zig").NDArray;

fn loadData(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !meshio.SimData {
    const pc = try std.fmt.allocPrint(allocator, "{s}/coords.csv", .{path});
    defer allocator.free(pc);
    const pn = try std.fmt.allocPrint(allocator, "{s}/connect.csv", .{path});
    defer allocator.free(pn);
    const pf = [_][]const u8{ 
        try std.fmt.allocPrint(allocator, "{s}/field.csv", .{path}),
    };
    defer allocator.free(pf[0]);
    return try meshio.loadSimData(allocator, io, pc, pn, pf[0..], null);
}

test "Nodal Normals Sanity Check - Sphere" {
    const allocator = std.testing.allocator;
    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const Rotation = @import("zigraster/zig/rotation.zig").Rotation;

    // 1. Load sphere200 tri3 data
    const data_path = "data-bench/tri3_sphere200";
    var sim_data = try loadData(allocator, io, data_path);
    defer sim_data.deinit(allocator);

    // 2. Setup camera
    const pixel_num = [_]u32{ 320, 320 };
    const pixel_size = [_]f64{ 0.00625, 0.00625 };
    const focal_leng = 2.0;
    const rot = Rotation.init(0, 0, 0);
    const cam_pos = @import("zigraster/zig/camera.zig").CameraOps.posFillFrameFromRot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, 1.0,
    );
    const roi_cent = @import("zigraster/zig/camera.zig").CameraOps.roiCentFromCoords(&sim_data.coords);

    var camera = Camera.init(
        pixel_num, pixel_size, cam_pos, rot, roi_cent, focal_leng, 2,
    );

    // Normal-to-RGB diagnostic setup
    const mesh_input = meshraster.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{ .normals = .{
            .field = sim_data.field.?,
            .normal_type = .averaged,
        }},
    };

    const iio = @import("zigraster/zig/imageio.zig");

    const config = zraster.RasterConfig{
        .save_opt = .disk,
        .save_opts = &[_]iio.ImageSaveOpts{
            .{ .format = .bmp, .bits = 8, .scaling = .auto, .channels = 3 },
            .{ .format = .csv, .bits = null, .scaling = .none, .channels = 3 },
        },
    };

    const out_dir_path = "out-normals-test";
    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, out_dir_path, .default_dir) catch |err| if (err != error.PathAlreadyExists) return err;
    var out_dir = try cwd.openDir(io, out_dir_path, .{});
    defer out_dir.close(io);

    // 3. Rasterize
    const result = try zraster.rasterAllFrames(
        allocator, io, &camera, &[_]meshraster.MeshInput{mesh_input}, config, out_dir,
    );
    if (result) |r| {
        allocator.free(r.elems);
        var mutable_r = r;
        mutable_r.deinit(allocator);
    }
}
