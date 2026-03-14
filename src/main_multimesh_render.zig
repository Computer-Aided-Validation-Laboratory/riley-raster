const std = @import("std");
const print = std.debug.print;

const meshio = @import("zigraster/zig/meshio.zig");
const SimData = meshio.SimData;

const mr = @import("zigraster/zig/meshraster.zig");
const MeshType = mr.MeshType;
const MeshRaster = mr.MeshRaster; 

pub fn main() !void {
    const print_break = [_]u8{'-'} ** 80;
    print("{s}\nMulti-Mesh Software Rasteriser Test\n{s}\n", .{ print_break, print_break });    

    const page_alloc = std.heap.page_allocator;

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
    const sim_datas = try meshio.loadMultiSimData(page_alloc, io, &dir_paths, .{});
    defer {
        for (sim_datas) |*sim_data| sim_data.deinit(page_alloc);
        page_alloc.free(sim_datas);
    }

    //-----------------------------------------------------------------------------------------
    // Create Multi MeshRaster (Flat Shading for now)
    print("Creating multi-mesh rasters...\n", .{});
    const mesh_rasters = try mr.meshRasterFromSimDataSlice(
        page_alloc, 
        io, 
        sim_datas, 
        &mesh_types, 
        .flat, 
        null,
        null,
        null
    );
    // Note: in a real scenario we'd need to deinit mesh_rasters properly if they allocated 
    // internal shader data like textures/uvs.
    defer page_alloc.free(mesh_rasters);

    print("Successfully loaded {d} meshes.\n", .{mesh_rasters.len});
    for (mesh_rasters, 0..) |m, ii| {
        print("Mesh {d}: type={s}, elems={d}, nodes_per_elem={d}\n", .{
            ii, 
            @tagName(m.mesh_type), 
            m.connect.getElemsNum(), 
            m.connect.getNodesPerElem()
        });
    }

    print("{s}\nReady for multimesh refactor.\n{s}\n", .{print_break, print_break});
}
