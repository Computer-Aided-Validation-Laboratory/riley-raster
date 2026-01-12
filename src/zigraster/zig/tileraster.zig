const std = @import("std");
const print = std.debug.print;
const time = std.time;
const Instant = time.Instant;

const vecstack = @import("vecstack.zig");
const Vec3T = @import("vecstack.zig").Vec3T;
const Vec3SliceOps = @import("vecstack.zig").Vec3SliceOps;

const Mat44Ops = @import("matstack.zig").Mat44Ops;

const VecSlice = @import("vecslice.zig").VecSlice;
const MatSlice = @import("matslice.zig").MatSlice;
const NDArray = @import("ndarray.zig").NDArray;

const sliceops = @import("sliceops.zig");

const Coords = @import("meshio.zig").Coords;
const Connect = @import("meshio.zig").Connect;
const Field = @import("meshio.zig").Field;

const Camera = @import("camera.zig").Camera;

const rops = @import("rasterops.zig");
const vsd = @import("vecsimd.zig");
const Vec3SIMD = vsd.Vec3SIMD;

const ElemBoxes = struct {
    elem_inds: []usize,
    x_min: []u16,
    x_max: []u16,
    y_min: []u16,
    y_max: []u16,
};

fn calcSizePad(N: usize, size: usize) usize {
    const remainder = size % N;
    const padding = if (remainder == 0) 0 else (N - remainder);
    return size+padding;
}

pub fn RasterMesh(comptime T: type) type {
    return struct {
        // dims = (nodes_per_elem, elems_num)
        x: []T, // Need to pad these to be SIMD friendly
        y: []T, 
        z: []T,
        nodes_per_elem: usize,
        elems_num: usize,

        const Self = @This();
        
        pub fn init(x: []T, y: []T, z: []T, nodes_per_elem: usize, elems_num: usize) Self {
            return .{
              .x = x,
              .y = y,
              .z = z,
              .nodes_per_elem = nodes_per_elem,
              .elems_num = elems_num,  
            };
        }

        pub fn flatInd(self: Self, node: usize, elem: usize) usize {
            return (node*self.elems_num) + elem;
        }

        pub fn getVec3(self: Self, node: usize, elem: usize) Vec3T(T) {
            const flat_ind = self.flatInd(node,elem);
            return vecstack.initVec3(T,self.x[flat_ind],self.y[flat_ind],self.z[flat_ind]);
        }

        pub fn getVec3SIMD(self: Self, comptime N: usize, batch_start: usize) Vec3SIMD(N,T) {
            const x_slice = self.x[batch_start..batch_start+N];
            const y_slice = self.y[batch_start..batch_start+N];
            const z_slice = self.z[batch_start..batch_start+N];
            return Vec3SIMD(N,T).init(x_slice,y_slice,z_slice);
        } 

    };
}

pub fn rasterOneFrame(allocator: std.mem.Allocator, 
                      frame_ind: usize, 
                      coords: *const Coords, 
                      connect: *const Connect, 
                      field: *const Field, 
                      camera: *const Camera, 
                      image_out_arr: *NDArray(f64),
                      ) !void {
    const N: usize = 3; // Set to nodes per elem 

    @memset(image_out_arr.elems,0.0);
    print("DEBUG\n",.{});

    var time_start = try Instant.now();
    var time_end = try Instant.now();
    
    //-----------------------------------------------------------------------------------------
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    //-----------------------------------------------------------------------------------------
    // **ELEMENT WISE PRE-TRANSFORM**
    
    const elems_num: usize = connect.elem_n;
    const nodes_per_elem: usize = connect.nodes_per_elem;
    const coords_num: usize = 3;
    const fields_num: usize = field.getFieldsN();

    const dim_elem: usize = 0; 
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    var elem_coord_arr_dims = [_]usize{elems_num,coords_num,nodes_per_elem};
    const elem_coord_arr_size: usize = elems_num*nodes_per_elem*coords_num;
    const elem_coord_arr_mem = try arena_alloc.alloc(f64, elem_coord_arr_size);
    @memset(elem_coord_arr_mem,0.0);
    var elem_coord_arr = try NDArray(f64).init(allocator, 
                                                elem_coord_arr_mem, 
                                                elem_coord_arr_dims[0..]);

    // dims=(elems_num,fields_num,nodes_per_elem)
    var elems_field_arr_dims = [_]usize{elems_num,fields_num,nodes_per_elem};
    const elems_field_arr_size: usize = elems_num*nodes_per_elem*fields_num;
    const elems_field_arr_mem = try arena_alloc.alloc(f64, elems_field_arr_size);
    @memset(elems_field_arr_mem,0.0);
    var elems_field_arr = try NDArray(f64).init(allocator, 
                                                elems_field_arr_mem, 
                                                elems_field_arr_dims[0..]);
    // dims=(elems_num,coord[x,y,z],nodes_per_elem,)    
    var elem_inds = [_]usize{0,0,0};
    // dims=(times_num,nodes_num,field_num)
    var field_inds = [_]usize{frame_ind,0,0}; 

    elem_inds = .{0,0,0};
    field_inds =.{frame_ind,0,0};
    for (0..elems_num) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..connect.nodes_per_elem) |nn| {
            elem_inds[dim_node] = nn;
            field_inds[1] = coord_inds[nn];
                                
            elem_inds[dim_field] = 0;            
            try elem_coord_arr.set(elem_inds[0..],coords.x[coord_inds[nn]]);
            elem_inds[dim_field] = 1;            
            try elem_coord_arr.set(elem_inds[0..],coords.y[coord_inds[nn]]);
            elem_inds[dim_field] = 2;            
            try elem_coord_arr.set(elem_inds[0..],coords.z[coord_inds[nn]]);
            
            for (0..fields_num) |ff| {
                elem_inds[dim_field] = ff;
                field_inds[2] = ff;
                const field_val = try field.array.get(field_inds[0..]);
                try elems_field_arr.set(elem_inds[0..],field_val);
            }
        } 
    }

    print("\n",.{});
    print("elem_coord_arr:\n",.{});
    print("    dims=[{d},{d},{d}]\n",
          .{elem_coord_arr.dims[0],elem_coord_arr.dims[1],elem_coord_arr.dims[2]});
    print("    strides=[{d},{d},{d}]\n",
          .{elem_coord_arr.strides[0],elem_coord_arr.strides[1],elem_coord_arr.strides[2]});
    print("\n",.{});

    //-----------------------------------------------------------------------------------------
    // World to Raster Coords - No SIMD
    elem_inds = .{0,0,0}; 

    time_start = try Instant.now();    
    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        
        for (0..elem_coord_arr.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;

            elem_inds[dim_field] = 0;
            const x_val = try elem_coord_arr.get(elem_inds[0..]); 
            elem_inds[dim_field] = 1;
            const y_val = try elem_coord_arr.get(elem_inds[0..]);
            elem_inds[dim_field] = 2;
            const z_val = try elem_coord_arr.get(elem_inds[0..]);
            
            const coord_world = vecstack.initVec3(f64,x_val,y_val,z_val);
            const coord_raster = rops.worldToRasterCoords(coord_world,camera);
                
            elem_inds[dim_field] = 0;
            try elem_coord_arr.set(elem_inds[0..],coord_raster.x());
            elem_inds[dim_field] = 1;
            try elem_coord_arr.set(elem_inds[0..],coord_raster.y());
            elem_inds[dim_field] = 2;
            try elem_coord_arr.set(elem_inds[0..],coord_raster.z());
        
            // print("ee={d}, nn={d}\n",.{ee,nn});
            // print("coord_world=[{d},{d},{d}]\n",
            //       .{coord_world.x(),coord_world.y(),coord_world.z()});
            // print("coord_raster=[{d:.3},{d:.3},{d:.3}]\n",
            //       .{coord_raster.x(),coord_raster.y(),coord_raster.z()});
            // print("\n",.{});   
        }        
    }
    time_end = try Instant.now();
    const time_no_simd: f64 = @floatFromInt(time_end.since(time_start));

    //-----------------------------------------------------------------------------------------
    // RESET TO WORLD COORDS
    elem_inds = .{0,0,0};
    field_inds =.{frame_ind,0,0};
    for (0..elems_num) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..connect.nodes_per_elem) |nn| {
            elem_inds[dim_node] = nn;
            field_inds[1] = coord_inds[nn];
                                
            elem_inds[dim_field] = 0;            
            try elem_coord_arr.set(elem_inds[0..],coords.x[coord_inds[nn]]);
            elem_inds[dim_field] = 1;            
            try elem_coord_arr.set(elem_inds[0..],coords.y[coord_inds[nn]]);
            elem_inds[dim_field] = 2;            
            try elem_coord_arr.set(elem_inds[0..],coords.z[coord_inds[nn]]);
            
            for (0..fields_num) |ff| {
                elem_inds[dim_field] = ff;
                field_inds[2] = ff;
                const field_val = try field.array.get(field_inds[0..]);
                try elems_field_arr.set(elem_inds[0..],field_val);
            }
        } 
    }

    //-----------------------------------------------------------------------------------------
    // World to Raster Coords - SIMD
        
    time_start = try Instant.now();
    for (0..elems_num) |ee| {
        const coords_world: Vec3SIMD(N,f64) = try vsd.loadVec3FromElemArray(
            N,f64,&elem_coord_arr,ee);

        const coords_raster: Vec3SIMD(N,f64) = rops.worldToRasterSIMD(
            N,f64,coords_world,camera); 

        try vsd.saveVec3ToElemArray(N,f64,&elem_coord_arr,ee,coords_raster);
        // print("bb={}, N={}, batch_start={}\n",.{bb,N,batch_start});
        // print("coords_world.x = {}\n",.{coords_world.x});
        // print("coords_world.y = {}\n",.{coords_world.y});
        // print("coords_world.z = {}\n",.{coords_world.z});
        // print("\n",.{});
    }
    time_end = try Instant.now();
    const time_simd: f64 = @floatFromInt(time_end.since(time_start));

    elem_inds = .{0,0,0};

    // SIMD: print transformed coords to console
    for (0..elems_num) |ee| {
        elem_inds[dim_elem] = ee;
        print("Element: {d}\n",.{ee});
        for (0..nodes_per_elem) |nn| {
            elem_inds[dim_node] = nn;
            print("Node={d}, [",.{nn});
            for (0..coords_num) |cc| {
                elem_inds[dim_field] = cc;
                const val = try elem_coord_arr.get(elem_inds[0..]);
                
                print("{d},",.{val});
            
            }
            print("]\n",.{});
        }
        print("\n",.{});
    }
    print("\nTIME SIMD WORLD TO RASTER = {d}ns\n",.{time_simd});
    
    const print_break = [_]u8{'='} ** 80;
    print("{s}\n",.{print_break});
    print("World to coords time:\n",.{});
    print("No SIMD = {d:.3}\n",.{time_no_simd});
    print("SIMD    = {d:.3}\n",.{time_simd});
    print("{s}\n",.{print_break});
    //-----------------------------------------------------------------------------------------
    // Element Bounding Boxes
//     elem_inds = .{0,0,0}; 
//         
//     for (0..elem_coord_arr.dims[0]) |ee| {
//         elem_inds[0] = ee;
//         const elem_flat = try elem_coord_arr.getFlatInd(elem_inds[0..]);
// 
//         const elem_end = elem_flat+elem_coord_arr.strides[0];
//         const elem_slice = elem_coord_arr.elems[elem_flat..elem_end];
// 
//         var x_min = elem_slice[0];
//         var x_max = elem_slice[0];
//         var y_min = elem_slice[1];
//         var y_max = elem_slice[1];
// 
//         // nodes_per_elem = elem_coord_arr.dims[1]
//         for (1..nodes_per_elem) |nn| {
//             // x min and x max in raster coords
//             if (elem_slice[nn*3] < x_min) {
//                 x_min = elem_slice[nn*3];    
//             } else if (elem_slice[nn*3] > x_max) {
//                 x_max = elem_slice[nn*3];                 
//             }
// 
//             // y min and y max in raster coords
//             if (elem_slice[nn*3+1] < y_min) {
//                 y_min = elem_slice[nn*3+1];    
//             } else if (elem_slice[nn*3+1] > y_max) {
//                 y_max = elem_slice[nn*3+1];                 
//             } 
//         }
// 
//         print("elem_slice=\n",.{});
//         for (0..elem_slice.len) |ii| {
//             print("{d:.3},",.{elem_slice[ii]});
//         }
//         print("\n",.{});
//         print("x_min={d:.3},x_max={d:.3}\n",.{x_min,x_max});
//         print("y_min={d:.3},y_max={d:.3}\n",.{y_min,y_max});
//         print("\n\n",.{});    
//     }
// 
// 
//     elem_inds = .{0,0,0}; 
//    
//     const elem_boxes = try arena_alloc.alloc(ElemBox,elem_coord_arr.dims[0]);
//     var elems_in_image: usize = 0;
//         
//     for (0..elem_coord_arr.dims[0]) |ee| {
//         const coords_raster: Vec3SIMD(N,f64) = try vsd.loadVec3FromElemArray(
//             N,f64,&elem_coord_arr,ee);
// 
//         const x_max: f64 = @reduce(.Max,coords_raster.x);
//         const x_min: f64 = @reduce(.Min,coords_raster.x);
//         if ((x_min > @as(f64, @floatFromInt(camera.pixels_num[0] - 1))) or (x_max < 0.0)) {
//             continue;
//         }
// 
//         const y_max: f64 = @reduce(.Max,coords_raster.y);
//         const y_min: f64 = @reduce(.Min,coords_raster.y);
//         if ((y_min > @as(f64, @floatFromInt(camera.pixels_num[1] - 1))) or (y_max < 0.0)) {
//             continue;
//         }
// 
//         const x_min_i: u16 = rops.boundIndMin(u16,x_min);
//         const x_max_i: u16 = rops.boundIndMax(u16,
//                                               x_max, 
//                                               @intCast(camera.pixels_num[0]));
//         const y_min_i: u16 = rops.boundIndMin(u16,y_min);
//         const y_max_i: u16 = rops.boundIndMax(u16,
//                                               y_max, 
//                                               @intCast(camera.pixels_num[1]));
// 
//         elem_boxes[elems_in_image] = ElemBox{
//             .elem_ind=ee,
//             .x_max=x_max_i,
//             .x_min=x_min_i,
//             .y_max=y_max_i,
//             .y_min=y_min_i,
//         };
//         elems_in_image += 1;
//     }

    //-----------------------------------------------------------------------------------------
//     // Element Tile Overlap Sort: Pass 1, How many element in each tile?
// 
//     const tile_size: usize = 16;
//     const tiles_num_x: usize = try std.math.divCeil(usize,sub_px_num_x,tile_size);
//     const tiles_num_y: usize = try std.math.divCeil(usize,sub_px_num_y,tile_size);
//     const tiles_num: usize = tiles_num_x*tiles_num_y;    
// 
//      print("Tiles:\n    tile_size={d}, tiles_num_x={d}, tiles_num_y={d}, tiles_num={}\n",
//           .{tile_size,tiles_num_x,tiles_num_y,tiles_num});
// 
//     // - Loop over elements
//     //  - If not on screen, CONTINUE
//     //  - If on screen work out which tile it overlaps and increment the count for that tile
//     // Need to allocate a slice of memory to store the `tile_counts`
// 
//     // Needs to be allocate because we could have a high res camera with 1000s of tiles
//     const tile_elem_counts: []usize = try alloc.alloc(usize,tiles_num); 

    //-----------------------------------------------------------------------------------------
    // **TILE SPLIT**

    // TODO
    // - **BACK FACE CULLING**
    // - Project all elements onto screen space
    // - Work out which elements are in which tile and allocate a buffer to store this
    // - Need bounding boxes of all elements, bounding boxes of all tiles

    const sub_px_num_x: usize = camera.pixels_num[0]*camera.sub_sample; 
    const sub_px_num_y: usize = camera.pixels_num[1]*camera.sub_sample;

    print("\n",.{});
    print("Camera:\n    pixels_x={d}, pixels_y={d}\n",
          .{camera.pixels_num[0],camera.pixels_num[1]});
    print("    sub_sample={}, sub_pixels_x={d}, sub_pixels_y={d}\n\n",
          .{camera.sub_sample,sub_px_num_x,sub_px_num_y});

    // **LOOP** over elements, calculate raster coords and crop
    //const cam_px_x_f = @as(f64, @floatFromInt(camera.pixels_num[0] - 1));
    //const cam_px_y_f = @as(f64, @floatFromInt(camera.pixels_num[1] - 1));
}
                      
