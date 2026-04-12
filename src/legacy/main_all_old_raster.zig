const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Timestamp = std.Io.Clock.Timestamp;

const meshio = @import("zraster/zig/meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;
const SimData = meshio.SimData;

const VecStack = @import("zraster/zig/vecstack.zig");
const MatStack = @import("zraster/zig/matstack.zig");

const Rotation = @import("zraster/zig/rotation.zig").Rotation;
const Vec3f = VecStack.Vec3f;
const Mat44f = MatStack.Mat44f;
const Mat44Ops = MatStack.Mat44Ops;

const matslice = @import("zraster/zig/matslice.zig");
const MatSlice = matslice.MatSlice;
const MatSliceOps = matslice.MatSliceOps;

const ndarray = @import("zraster/zig/ndarray.zig");
const NDArray = ndarray.NDArray;

const Camera = @import("zraster/zig/camera.zig").Camera;
const CameraOps = @import("zraster/zig/camera.zig").CameraOps;

const rops = @import("zraster/zig/rasterops.zig");
const raster = @import("zraster/zig/oldraster.zig");

pub fn main() !void {
    const print_break = [_]u8{'-'} ** 80;
    print("{s}\nZig rasteriser\n{s}\n", .{ print_break, print_break });

    //=========================================================================
    // IO
    var single_thread_io: std.Io.Threaded = .init_single_threaded;
    const io = single_thread_io.io();

    var time_start = Timestamp.now(io, .awake);
    var time_end = Timestamp.now(io, .awake);

    //==========================================================================
    // MEMORY ALLOCATORS
    const page_alloc = std.heap.page_allocator;

    //==========================================================================
    // SETUP: load simulation data from file
    const path_data = "data/block/";

    const path_coords = path_data ++ "coords.csv";
    const path_connect = path_data ++ "connectivity.csv";

    const path_fields = [_][]const u8{
        path_data ++ "field_disp_x.csv",
        path_data ++ "field_disp_y.csv",
        path_data ++ "field_disp_z.csv",
    };

    const sim_data = try meshio.loadSimData(
        page_alloc,
        io,
        path_coords,
        path_connect,
        path_fields[0..],
        null,
    );
    //--------------------------------------------------------------------------
    // CHECK FIELD LOADED CORRECTLY
    const field_coord_n = sim_data.field.?.getCoordN();
    const field_time_n = sim_data.field.?.getTimeN();
    const field_fields_n = sim_data.field.?.getFieldsN();

    var fixed_inds = [_]usize{ 8, 0, 0 };
    const field_slice = sim_data.field.?.array.getSlice(fixed_inds[0..], 0);
    const field_mat = MatSlice(f64).init(field_slice, field_coord_n, field_fields_n);

    print("\nfield: time_n = {d}\n", .{field_time_n});
    print("field: coord_n = {d}\n", .{field_coord_n});
    print("field: fields_n = {d}\n\n", .{field_fields_n});
    print("field: mat = \n", .{});
    field_mat.matPrint();

    //==========================================================================
    // Build Camera

    const pixel_num = [_]u32{ 960, 1280 }; //[_]u32{ 960, 1280 };
    const pixel_size = [_]f64{ 5.3e-3, 5.3e-3 };
    const focal_leng: f64 = 50.0;
    const alpha_z: f64 = std.math.degreesToRadians(0.0);
    const beta_y: f64 = std.math.degreesToRadians(-30.0);
    const gamma_x: f64 = std.math.degreesToRadians(-10.0);
    const cam_rot = Rotation.init(alpha_z, beta_y, gamma_x);
    const fov_scale_factor: f64 = 1.1;
    const subsample: u8 = 2;

    print("{s}\n", .{print_break});
    const roi_pos = CameraOps.roiCentFromCoords(&sim_data.coords);

    print("\nROI center position:\n", .{});
    roi_pos.vecPrint();

    const cam_pos = CameraOps.posFillFrameFromRot(
        &sim_data.coords,
        pixel_num,
        pixel_size,
        focal_leng,
        cam_rot,
        fov_scale_factor,
    );

    print("\nCamera position:\n", .{});
    cam_pos.vecPrint();

    const camera = Camera.init(
        pixel_num,
        pixel_size,
        cam_pos,
        cam_rot,
        roi_pos,
        focal_leng,
        subsample,
    );

    print("\nWorld to camera matrix:\n", .{});
    camera.world_to_cam_mat.matPrint();

    print("{s}\n", .{print_break});

    //==========================================================================
    // Raster All Frames

    const cwd: std.Io.Dir = std.Io.Dir.cwd();
    const dir_name = "raster-out";

    cwd.createDir(io, dir_name, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Path exists do nothing
        else => return err, // Propagate any other error
    };

    var out_dir = try cwd.openDir(io, dir_name, .{});
    defer out_dir.close(io);

    time_start = Timestamp.now(io, .awake);

    const image_array = try raster.rasterAllFrames(
        page_alloc,
        io,
        out_dir,
        &sim_data.coords,
        &sim_data.connect,
        &sim_data.field.?,
        &camera,
    );
    time_end = Timestamp.now(io, .awake);
    const time_raster: f64 = @floatFromInt(
        time_start.durationTo(time_end).raw.nanoseconds,
    );
    print("Total raster time = {d:.3}ms\n\n", .{time_raster / time.ns_per_ms});

    // Print diagnostics to console to see if there is an image
    const image_max = std.mem.max(f64, image_array.slice);
    const image_min = std.mem.min(f64, image_array.slice);
    print("Image: [max, min] = [{}, {}]\n\n", .{ image_max, image_min });
} // main, end
