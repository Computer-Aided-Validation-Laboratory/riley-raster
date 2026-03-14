const std = @import("std");
const print = std.debug.print;

const meshio = @import("zigraster/zig/meshio.zig");
const SimData = meshio.SimData;

const mr = @import("zigraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster; 

const Camera = @import("zigraster/zig/camera.zig").Camera;
const CameraOps = @import("zigraster/zig/camera.zig").CameraOps;
const Rotation = @import("zigraster/zig/rotation.zig").Rotation;
const VecStack = @import("zigraster/zig/vecstack.zig");
const Vec3f = VecStack.Vec3f;

pub fn main() !void {
    const print_break = [_]u8{'-'} ** 80;
    print("{s}\nMulti-Mesh Software Rasteriser Test\n{s}\n", .{ print_break, print_break });    

    const page_alloc = std.heap.page_allocator;
    var arena = std.heap.ArenaAllocator.init(page_alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    var single_thread_io: std.Io.Threaded = .init_single_threaded;
    const io = single_thread_io.io();

    //-----------------------------------------------------------------------------------------
    // Define paths for twoelems cases
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

    //-----------------------------------------------------------------------------------------
    // Load Multi SimData
    print("Loading multi-mesh sim data...\n", .{});
    const sim_datas = try meshio.loadMultiSimData(arena_alloc, io, &dir_paths, .{});

    //-----------------------------------------------------------------------------------------
    // Create Multi MeshRaster (Flat Shading for now)
    print("Creating multi-mesh rasters...\n", .{});
    const mesh_rasters = try mr.meshRasterFromSimDataSlice(
        arena_alloc, 
        io, 
        sim_datas, 
        &mesh_types, 
        .flat, 
        null,
        null,
        null
    );

    //-----------------------------------------------------------------------------------------
    // Arrange meshes in a grid
    print("Arranging meshes in a grid...\n", .{});
    mr.arrangeMeshSlice(mesh_rasters, .{ 0.1, 0.1, 0.0 }, .{ 3, 2, 1 });

    print("Successfully loaded and arranged {d} meshes.\n", .{mesh_rasters.len});
    for (mesh_rasters, 0..) |m, ii| {
        print("Mesh {d}: type={s}, elems={d}, nodes_per_elem={d}\n", .{
            ii, 
            @tagName(m.mesh_type), 
            m.connect.getElemsNum(), 
            m.connect.getNodesPerElem()
        });
    }

    //-----------------------------------------------------------------------------------------
    // Build Camera
    print("\nBuilding multi-mesh camera...\n", .{});
    const pixel_num = [_]u32{ 1200, 800 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const alpha_z: f64 = std.math.degreesToRadians(0.0);
    const beta_y: f64 = std.math.degreesToRadians(0.0);
    const gamma_x: f64 = std.math.degreesToRadians(0.0);
    const cam_rot = Rotation.init(alpha_z, beta_y, gamma_x);
    const fov_scale_factor: f64 = 1.1;
    const subsample: u8 = 2;

    const roi_pos = CameraOps.roiCentOverMeshes(mesh_rasters);
    print("\nROI center position:\n", .{});
    roi_pos.vecPrint();

    const cam_pos = CameraOps.posFillFrameFromRotOverMeshes(
        mesh_rasters, 
        pixel_num, 
        pixel_size, 
        focal_leng, 
        cam_rot, 
        fov_scale_factor
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
        subsample
    );
    print("\nWorld to camera matrix:\n", .{});
    camera.world_to_cam_mat.matPrint();

    print("{s}\nReady for multimesh refactor.\n{s}\n", .{print_break, print_break});
}
