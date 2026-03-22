const std = @import("std");
const print = std.debug.print;

const MatSlice = @import("zigraster/zig/matslice.zig").MatSlice;
const meshio = @import("zigraster/zig/meshio.zig");
const SimData = meshio.SimData;

const mr = @import("zigraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshInput = mr.MeshInput;
const MeshPrepared = mr.MeshPrepared;

const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const Rotation = @import("zigraster/zig/rotation.zig").Rotation;

const zraster = @import("zigraster/zig/zraster.zig");
const RasterConfig = zraster.RasterConfig;

const iio = @import("zigraster/zig/imageio.zig");
const uvio = @import("zigraster/zig/uvio.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

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

    print("Loading data...\n", .{});
    const sim_datas = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});
    const texture = try iio.loadImage(aa, io, "texture/speckle-simple.tiff", .tiff, u8, 1);

    const cwd = std.Io.Dir.cwd();
    cwd.createDir(io, "out-bench-multimesh-debug", .default_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // --- Case 1: Just Texture (Bottom Row) ---
    {
        print("Rendering Just Texture Isolation...\n", .{});
        var mesh_inputs = try aa.alloc(MeshInput, 10);
        // Fill all with dummy or same data but only set bottom row to visible texture
        for (0..10) |ii| {
            const data_idx = ii % 5;
            var coords_dup = try MatSlice(f64).initAlloc(
                aa, sim_datas[data_idx].coords.mat.rows_num, sim_datas[data_idx].coords.mat.cols_num
            );
            @memcpy(coords_dup.elems, sim_datas[data_idx].coords.mat.elems);

            if (ii >= 5) {
                const uv_path = try std.fmt.allocPrint(aa, "{s}uvs.csv", .{dir_paths[data_idx]});
                const uvs = try uvio.loadUVMap(aa, io, uv_path);
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
                    .connect = sim_datas[data_idx].connect,
                    .disp = null,
                    .shader = .{ .tex_u8 = .{
                        .uvs = uvs.array,
                        .texture = texture,
                        .interp_type = .cubic_lut_lerp,
                    }},
                };
            } else {
                // Top row empty (Flat shader with no field or just skip)
                // We'll use a flat shader with scaling .none and no field to keep it blank
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
                    .connect = sim_datas[data_idx].connect,
                    .disp = null,
                    .shader = .{ .flat = .{
                        .field = sim_datas[data_idx].field.?,
                        .scaling = .none,
                        .bits = null,
                    }},
                };
                // Actually, let's just make it a very small triangle far away? 
                // No, just render it but ensure field values are zero.
                @memset(mesh_inputs[ii].shader.flat.field.array.elems, 0.0);
            }
        }

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
        const camera = setupCamera(mesh_inputs);
        
        var out_dir = try cwd.openDir(io, "out-bench-multimesh-debug", .{});
        defer out_dir.close(io);
        
        const config = RasterConfig{
            .save_opt = .disk,
            .save_opts = &[_]iio.ImageSaveOpts{ .{ .format = .bmp, .bits = 8, .scaling = .auto } },
            .tile_size = 32,
        };
        _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_inputs, config, out_dir);
        // Rename frame_0_field_0.bmp to texture_only.bmp manually if needed, 
        // but for now it's in debug dir.
    }

    _ = arena.reset(.free_all);
    // Reload sim_datas as we cleared arena and modified field in Test 1
    const sim_datas2 = try meshio.loadMultiSimData(aa, io, &dir_paths, .{});

    // --- Case 2: Just Flat (Top Row) ---
    {
        print("Rendering Just Flat Isolation...\n", .{});
        var mesh_inputs = try aa.alloc(MeshInput, 10);
        for (0..10) |ii| {
            const data_idx = ii % 5;
            var coords_dup = try MatSlice(f64).initAlloc(
                aa, sim_datas2[data_idx].coords.mat.rows_num, sim_datas2[data_idx].coords.mat.cols_num
            );
            @memcpy(coords_dup.elems, sim_datas2[data_idx].coords.mat.elems);

            if (ii < 5) {
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
                    .connect = sim_datas2[data_idx].connect,
                    .disp = null,
                    .shader = .{ .flat = .{
                        .field = sim_datas2[data_idx].field.?,
                        .bits = 8,
                        .scaling = .auto,
                        .scale_over = .within_frames,
                    }},
                };
            } else {
                mesh_inputs[ii] = MeshInput{
                    .mesh_type = mesh_types[data_idx],
                    .coords = meshio.Coords.init(coords_dup.elems, coords_dup.rows_num),
                    .connect = sim_datas2[data_idx].connect,
                    .disp = null,
                    .shader = .{ .flat = .{
                        .field = sim_datas2[data_idx].field.?,
                        .scaling = .none,
                        .bits = null,
                    }},
                };
                @memset(mesh_inputs[ii].shader.flat.field.array.elems, 0.0);
            }
        }

        mr.arrangeMeshSlice(mesh_inputs, .{ 0.15, 0.15, 0.0 }, .{ 5, 2, 1 });
        const camera = setupCamera(mesh_inputs);
        
        var out_dir = try cwd.openDir(io, "out-bench-multimesh-debug", .{});
        defer out_dir.close(io);
        
        const config = RasterConfig{
            .save_opt = .disk,
            .save_opts = &[_]iio.ImageSaveOpts{ .{ .format = .bmp, .bits = 8, .scaling = .auto } },
            .tile_size = 32,
        };
        // This will overwrite frame_0_field_0.bmp if we are not careful. 
        // In this simple script it's fine, we'll see the second run results.
        _ = try zraster.rasterAllFrames(aa, io, &camera, mesh_inputs, config, out_dir);
    }

    print("Done debug isolation.\n", .{});
}

fn setupCamera(meshes: []const MeshInput) Camera {
    const pixel_num = [_]u32{ 1600, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const rot = Rotation.init(0, 0, 0);
    const fov_scale_factor: f64 = 1.2;
    const subsample: u8 = 2;

    const roi_pos = CameraOps.roiCentOverMeshes(meshes);
    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        meshes, pixel_num, pixel_size, focal_leng, rot, fov_scale_factor
    );

    return Camera.init(pixel_num, pixel_size, cam_pos, rot, roi_pos, focal_leng, subsample);
}
