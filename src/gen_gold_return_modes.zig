const std = @import("std");

const benchcommon = @import("common/benchcommon.zig");
const orch = @import("common/orchestration.zig");
const tcfg = @import("common/testconfig.zig");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const iio = @import("zraster/zig/imageio.zig");
const meshio = @import("zraster/zig/meshio.zig");
const mo = @import("zraster/zig/meshops.zig");
const NDArray = @import("zraster/zig/ndarray.zig").NDArray;
const zraster = @import("zraster/zig/zraster.zig");

const simd_on = buildconfig.config.simd == .on;
const gold_root = if (simd_on)
    "gold/return_modes-simd"
else
    "gold/return_modes";

fn saveFirstFrameAsF64(
    comptime T: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    file_name_no_ext: []const u8,
    image_arr: *const NDArray(T),
) !void {
    const rows = image_arr.dims[3];
    const cols = image_arr.dims[4];
    var image = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ 1, rows, cols },
    );
    defer {
        allocator.free(image.slice);
        image.deinit(allocator);
    }

    for (0..rows) |rr| {
        for (0..cols) |cc| {
            const val = image_arr.get(&[_]usize{ 0, 0, 0, rr, cc });
            image.set(
                &[_]usize{ 0, rr, cc },
                if (T == f64) val else @as(f64, @floatFromInt(val)),
            );
        }
    }

    const opts = if (T == f64)
        iio.ImageSaveOpts{
            .format = .fimg,
            .bits = null,
            .scaling = .none,
            .channels = 1,
        }
    else
        iio.ImageSaveOpts{
            .format = .csv,
            .bits = null,
            .scaling = .none,
            .channels = 1,
        };
    try iio.saveImage(io, out_dir, file_name_no_ext, &image, 0, opts);
}

fn renderAndSave(
    comptime T: type,
    allocator: std.mem.Allocator,
    io: std.Io,
    camera_input: @import("zraster/zig/camera.zig").CameraInput,
    mesh_input: mo.MeshInput,
    file_name_no_ext: []const u8,
    config: zraster.RasterConfig,
) !void {
    const render_groups = [_]zraster.RenderGroupSpec{
        .{ .io = io, .workers = @max(@as(u16, 1), config.total_threads) },
    };
    const result = (try zraster.rasterAllFrames(
        T,
        allocator,
        &render_groups,
        &[_]@TypeOf(camera_input){camera_input},
        &[_]mo.MeshInput{mesh_input},
        config,
        null,
    )) orelse return error.NoResult;
    defer {
        allocator.free(result.slice);
        var result_mut = result;
        result_mut.deinit(allocator);
    }

    var out_dir = try orch.openDirEnsured(io, gold_root);
    defer out_dir.close(io);
    try saveFirstFrameAsF64(T, allocator, io, out_dir, file_name_no_ext, &result);
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var managed_io = zraster.getThreadedIo(allocator, init.minimal, 1);
    defer managed_io.deinit();
    const io = managed_io.io();

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const data_dir = "data/bench/tri3_sphere200";
    const coord_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "coords.csv" },
    );
    const connect_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "connect.csv" },
    );
    const field_path = try std.fs.path.join(
        aa,
        &[_][]const u8{ data_dir, "field.csv" },
    );

    const sim_data = try meshio.loadSimData(
        aa,
        io,
        coord_path,
        connect_path,
        null,
        null,
    );
    const field_raw = try benchcommon.loadNDArrayFromCSV(
        aa,
        io,
        field_path,
        1,
        true,
    );
    const camera = try orch.initCameraForCoords(
        aa,
        &sim_data.coords,
        .{ 320, 200 },
        1.0,
    );
    defer camera.deinit(aa);

    const mesh_input = mo.MeshInput{
        .mesh_type = .tri3,
        .coords = sim_data.coords,
        .connect = sim_data.connect,
        .disp = null,
        .shader = .{
            .nodal = .{
                .field = .{
                    .array = field_raw,
                    .array_mem = field_raw.slice,
                },
                .scaling = .auto,
            },
        },
    };

    var config = tcfg.getRasterConfig(.gold);
    config.save_strategy = .memory;
    config.report = .off;
    config.memory_image_scaling = .auto;

    try renderAndSave(
        f64,
        aa,
        io,
        @import("zraster/zig/camera.zig").CameraInput{
            .pixels_num = camera.pixels_num,
            .pixels_size = camera.pixels_size,
            .pos_world = camera.pos_world,
            .rot_world = camera.rot_world,
            .roi_cent_world = camera.roi_cent_world,
            .focal_length = camera.focal_length,
            .sub_sample = camera.sub_sample,
            .distortion = camera.distortion,
        },
        mesh_input,
        "tri3_sphere200_f64",
        config,
    );
    try renderAndSave(
        u8,
        aa,
        io,
        @import("zraster/zig/camera.zig").CameraInput{
            .pixels_num = camera.pixels_num,
            .pixels_size = camera.pixels_size,
            .pos_world = camera.pos_world,
            .rot_world = camera.rot_world,
            .roi_cent_world = camera.roi_cent_world,
            .focal_length = camera.focal_length,
            .sub_sample = camera.sub_sample,
            .distortion = camera.distortion,
        },
        mesh_input,
        "tri3_sphere200_u8",
        config,
    );
    try renderAndSave(
        u16,
        aa,
        io,
        @import("zraster/zig/camera.zig").CameraInput{
            .pixels_num = camera.pixels_num,
            .pixels_size = camera.pixels_size,
            .pos_world = camera.pos_world,
            .rot_world = camera.rot_world,
            .roi_cent_world = camera.roi_cent_world,
            .focal_length = camera.focal_length,
            .sub_sample = camera.sub_sample,
            .distortion = camera.distortion,
        },
        mesh_input,
        "tri3_sphere200_u16",
        config,
    );

    std.debug.print("Done. Return mode gold references established.\n", .{});
}
