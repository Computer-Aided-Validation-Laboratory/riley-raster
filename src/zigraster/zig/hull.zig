const std = @import("std");
const rops = @import("rasterops.zig");
const Camera = @import("camera.zig").Camera;
const NDArray = @import("ndarray.zig").NDArray;
const Vec3OfSlices = rops.Vec3OfSlices;

pub fn buildAdaptiveHulls(comptime N: usize,
                             camera: *const Camera,
                             dim_elem: usize,
                             elem_coord_arr: *NDArray(f64),
                             raster_hull: *NDArray(f64)) !void {
    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        const cr: Vec3OfSlices(f64) = try rops.loadVec3SlicesFromElemArray(
            N, f64, elem_coord_arr, ee,
        );

        // 1. Perspective divide into local buffers
        var lx: [N]f64 = undefined;
        var ly: [N]f64 = undefined;
        for (0..N) |ii| {
            lx[ii] = cr.x[ii] / cr.z[ii] + x_off;
            ly[ii] = cr.y[ii] / cr.z[ii] + y_off;
        }

        // 2. Build Hull in loop order: Corner, Adaptive Node, Corner...
        if (N == 4) { // Quad4: Corners 0,1,2,3
            inline for (0..4) |ii| {
                raster_hull.set(&[_]usize{ ee, 0, ii }, lx[ii]);
                raster_hull.set(&[_]usize{ ee, 1, ii }, ly[ii]);
            }
        } else if (N == 6) { // Tri6: Corners 0,1,2. Midsides 3,4,5. 
            // Hull: (0, 3, 1, 4, 2, 5)
            const edges = [3][3]usize{
                .{ 0, 1, 3 }, // edge 0: corner 0 -> corner 1, mid 3
                .{ 1, 2, 4 }, // edge 1: corner 1 -> corner 2, mid 4
                .{ 2, 0, 5 }, // edge 2: corner 2 -> corner 0, mid 5
            };

            inline for (edges, 0..) |edge, ii| {
                const p1 = edge[0];
                const p2 = edge[1];
                const pm = edge[2];

                // Use the shared edge function for consistency
                const edge_val = rops.edgeFun3(lx[p1], ly[p1], lx[p2], ly[p2], lx[pm], ly[pm]);

                // Store Corner
                raster_hull.set(&[_]usize{ ee, 0, ii * 2 }, lx[p1]);
                raster_hull.set(&[_]usize{ ee, 1, ii * 2 }, ly[p1]);

                // Store Adaptive Node (Midside or Bezier Control Point)
                // Bulge OUT means edge_val < 0 for CW winding.
                if (edge_val < 0) {
                    const cx = 2.0 * lx[pm] - 0.5 * (lx[p1] + lx[p2]);
                    const cy = 2.0 * ly[pm] - 0.5 * (ly[p1] + ly[p2]);
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, cx);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, cy);
                } else {
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, lx[pm]);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, ly[pm]);
                }
            }
        } else if (N == 8 or N == 9) { // Quad8/9: Corners 0,1,2,3. Midsides 4,5,6,7.
            // Hull: (0, 4, 1, 5, 2, 6, 3, 7)
            const edges = [4][3]usize{
                .{ 0, 1, 4 }, // edge 0: 0->1, mid 4
                .{ 1, 2, 5 }, // edge 1: 1->2, mid 5
                .{ 2, 3, 6 }, // edge 2: 2->3, mid 6
                .{ 3, 0, 7 }, // edge 3: 3->0, mid 7
            };

            inline for (edges, 0..) |edge, ii| {
                const p1 = edge[0];
                const p2 = edge[1];
                const pm = edge[2];

                const edge_val = rops.edgeFun3(lx[p1], ly[p1], lx[p2], ly[p2], lx[pm], ly[pm]);

                raster_hull.set(&[_]usize{ ee, 0, ii * 2 }, lx[p1]);
                raster_hull.set(&[_]usize{ ee, 1, ii * 2 }, ly[p1]);

                // Bulge OUT means edge_val < 0 for CW winding.
                if (edge_val < 0) {
                    const cx = 2.0 * lx[pm] - 0.5 * (lx[p1] + lx[p2]);
                    const cy = 2.0 * ly[pm] - 0.5 * (ly[p1] + ly[p2]);
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, cx);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, cy);
                } else {
                    raster_hull.set(&[_]usize{ ee, 0, ii * 2 + 1 }, lx[pm]);
                    raster_hull.set(&[_]usize{ ee, 1, ii * 2 + 1 }, ly[pm]);
                }
            }
        }
    }
}

test "Adaptive Hull Tri6 Bulge Out (Convex)" {
    const allocator = std.testing.allocator;
    const meshio = @import("meshio.zig");
    const mr = @import("meshraster.zig");
    const camera_mod = @import("camera.zig");
    const CameraOps = camera_mod.CameraOps;

    // 1. Load Data
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const data_path = "data-edge/tri6_bulgeout_rot";
    const coord_path = try std.fmt.allocPrint(aa, "{s}/coords.csv", .{data_path});
    const connect_path = try std.fmt.allocPrint(aa, "{s}/connectivity.csv", .{data_path});
    const field_paths = [_][]const u8{
        try std.fmt.allocPrint(aa, "{s}/field_disp_x.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_y.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_z.csv", .{data_path}),
    };
    var sim_data = try meshio.load_sim_data(aa, io, coord_path, connect_path, &field_paths);

    // 2. Transform to Elem Array
    var elem_coords = try mr.transformCoords(aa, &sim_data.coords, &sim_data.connect);

    // 3. Setup Camera (matched to generation params)
    const pixel_num = [_]u32{ 800, 500 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const fov_scale = 1.1;

    const rot = @import("rotation.zig").Rotation.init(0, 0, 0);
    const cam_pos = CameraOps.pos_fill_frame_from_rot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, fov_scale,
    );
    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, @import("vecstack.zig").Vec3f.initZeros(), focal_leng, 2);

    // 4. Transform to Camera Space
    try rops.transformElemsClipPxLengSIMD(6, f64, &camera, 0, &elem_coords);

    // 5. Build Hull
    var raster_hull = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, 6 });
    try buildAdaptiveHulls(6, &camera, 0, &elem_coords, &raster_hull);

    // 6. Verify
    const hx = raster_hull.getSlice(&[_]usize{ 0, 0, 0 }, 1);
    const hy = raster_hull.getSlice(&[_]usize{ 0, 1, 0 }, 1);

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    
    // Check edge 0 (0-1, mid 3)
    const p1 = 0; const p2 = 1; const pm = 3;
    const lx_pm = elem_coords.get(&[_]usize{ 0, 2, pm }) / elem_coords.get(&[_]usize{ 0, 2, pm }); // dummy to bypass unused
    _ = lx_pm;
    
    const node_x_pm = elem_coords.get(&[_]usize{ 0, 0, pm }) / elem_coords.get(&[_]usize{ 0, 2, pm }) + x_off;
    const node_y_pm = elem_coords.get(&[_]usize{ 0, 1, pm }) / elem_coords.get(&[_]usize{ 0, 2, pm }) + y_off;
    const node_x_p1 = elem_coords.get(&[_]usize{ 0, 0, p1 }) / elem_coords.get(&[_]usize{ 0, 2, p1 }) + x_off;
    const node_y_p1 = elem_coords.get(&[_]usize{ 0, 1, p1 }) / elem_coords.get(&[_]usize{ 0, 2, p1 }) + y_off;
    const node_x_p2 = elem_coords.get(&[_]usize{ 0, 0, p2 }) / elem_coords.get(&[_]usize{ 0, 2, p2 }) + x_off;
    const node_y_p2 = elem_coords.get(&[_]usize{ 0, 1, p2 }) / elem_coords.get(&[_]usize{ 0, 2, p2 }) + y_off;

    const edge_val = rops.edgeFun3(node_x_p1, node_y_p1, node_x_p2, node_y_p2, node_x_pm, node_y_pm);
    // Bulge OUT (Convex) should have negative bulge in raster space (CW winding)
    try std.testing.expect(edge_val < 0);

    // The hull point at index 1 should be the Bezier point
    const cx = 2.0 * node_x_pm - 0.5 * (node_x_p1 + node_x_p2);
    const cy = 2.0 * node_y_pm - 0.5 * (node_y_p1 + node_y_p2);

    try std.testing.expectApproxEqAbs(cx, hx[1], 1e-9);
    try std.testing.expectApproxEqAbs(cy, hy[1], 1e-9);
}

test "Adaptive Hull Tri6 Bulge In (Concave)" {
    const allocator = std.testing.allocator;
    const meshio = @import("meshio.zig");
    const mr = @import("meshraster.zig");
    const camera_mod = @import("camera.zig");
    const CameraOps = camera_mod.CameraOps;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    var io_threaded = std.Io.Threaded.init_single_threaded;
    const io = io_threaded.io();

    const data_path = "data-edge/tri6_bulgein_rot";
    const coord_path = try std.fmt.allocPrint(aa, "{s}/coords.csv", .{data_path});
    const connect_path = try std.fmt.allocPrint(aa, "{s}/connectivity.csv", .{data_path});
    const field_paths = [_][]const u8{
        try std.fmt.allocPrint(aa, "{s}/field_disp_x.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_y.csv", .{data_path}),
        try std.fmt.allocPrint(aa, "{s}/field_disp_z.csv", .{data_path}),
    };
    var sim_data = try meshio.load_sim_data(aa, io, coord_path, connect_path, &field_paths);

    var elem_coords = try mr.transformCoords(aa, &sim_data.coords, &sim_data.connect);

    const pixel_num = [_]u32{ 800, 500 };
    const pixel_size = [_]f64{ 5.3e-6, 5.3e-6 };
    const focal_leng: f64 = 50.0e-3;
    const fov_scale = 1.1;

    const rot = @import("rotation.zig").Rotation.init(0, 0, 0);
    const cam_pos = CameraOps.pos_fill_frame_from_rot(
        &sim_data.coords, pixel_num, pixel_size, focal_leng, rot, fov_scale,
    );
    const camera = Camera.init(pixel_num, pixel_size, cam_pos, rot, @import("vecstack.zig").Vec3f.initZeros(), focal_leng, 2);

    try rops.transformElemsClipPxLengSIMD(6, f64, &camera, 0, &elem_coords);

    var raster_hull = try NDArray(f64).initFlat(aa, &[_]usize{ 1, 2, 6 });
    try buildAdaptiveHulls(6, &camera, 0, &elem_coords, &raster_hull);

    const hx = raster_hull.getSlice(&[_]usize{ 0, 0, 0 }, 1);
    const hy = raster_hull.getSlice(&[_]usize{ 0, 1, 0 }, 1);

    const x_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[0]));
    const y_off = 0.5 * @as(f64, @floatFromInt(camera.pixels_num[1]));
    
    // Check edge 0 (0-1, mid 3)
    const p1 = 0; const p2 = 1; const pm = 3;
    const node_x_pm = elem_coords.get(&[_]usize{ 0, 0, pm }) / elem_coords.get(&[_]usize{ 0, 2, pm }) + x_off;
    const node_y_pm = elem_coords.get(&[_]usize{ 0, 1, pm }) / elem_coords.get(&[_]usize{ 0, 2, pm }) + y_off;
    const node_x_p1 = elem_coords.get(&[_]usize{ 0, 0, p1 }) / elem_coords.get(&[_]usize{ 0, 2, p1 }) + x_off;
    const node_y_p1 = elem_coords.get(&[_]usize{ 0, 1, p1 }) / elem_coords.get(&[_]usize{ 0, 2, p1 }) + y_off;
    const node_x_p2 = elem_coords.get(&[_]usize{ 0, 0, p2 }) / elem_coords.get(&[_]usize{ 0, 2, p2 }) + x_off;
    const node_y_p2 = elem_coords.get(&[_]usize{ 0, 1, p2 }) / elem_coords.get(&[_]usize{ 0, 2, p2 }) + y_off;

    const edge_val = rops.edgeFun3(node_x_p1, node_y_p1, node_x_p2, node_y_p2, node_x_pm, node_y_pm);
    // Bulge IN (Concave) should have positive bulge in raster space (CW winding)
    try std.testing.expect(edge_val > 0);

    // The hull point at index 1 should be the original midside node
    try std.testing.expectApproxEqAbs(node_x_pm, hx[1], 1e-9);
    try std.testing.expectApproxEqAbs(node_y_pm, hy[1], 1e-9);
}
