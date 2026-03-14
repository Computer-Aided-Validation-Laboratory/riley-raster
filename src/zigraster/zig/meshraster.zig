const std = @import("std");

pub const NDArray = @import("ndarray.zig").NDArray;
const MatSlice = @import("matslice.zig").MatSlice;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;

const uvio = @import("uvio.zig");
const UVMap = uvio.UVMap;

const shaderops = @import("shaderops.zig");
pub const FlatShader = shaderops.FlatShader;
pub const TexShader = shaderops.TexShader;
pub const Shader = shaderops.Shader;

pub const MeshType = enum {
    tri3,
    tri3opt,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,
};

pub const MeshRaster = struct {
    mesh_type: MeshType,
    coords: Coords,
    connect: Connect,
    disp: ?Field,
    shader: Shader,
};

pub const MeshTransform = struct {
    mesh_type: MeshType,
    coords: NDArray(f64),
    shader: Shader,
};

pub fn transformMesh(outer_alloc: std.mem.Allocator, 
                     mesh_raster: *const MeshRaster,
                     coords_disp: *const MatSlice(f64),) !MeshTransform {

    const wrap_coords = Coords.init(coords_disp.elems, coords_disp.rows_num);
    const elem_coords = try transformCoords(outer_alloc,
                                            &wrap_coords,
                                            &mesh_raster.connect);


    var mesh_trans = MeshTransform{
        .mesh_type = mesh_raster.mesh_type,
        .coords = elem_coords,
        .shader = undefined,    
    };

    switch (mesh_raster.shader) {
        .flat => |*flat_shader| {
            const elem_field = try transformField(outer_alloc,
                                                  &mesh_raster.connect,
                                                  &flat_shader.field);
            
            mesh_trans.shader = .{ .flat = .{
                .field = Field{
                    .array = elem_field,
                    .array_mem = elem_field.elems,
                },    
            }};
        },
        .texture => |*texture_shader| {
            const elem_uvs = try transformUVs(outer_alloc, 
                                              &texture_shader.uvs, 
                                              &mesh_raster.connect);
                    
            mesh_trans.shader = .{ .texture = .{
                .uvs = elem_uvs,
                .texture = texture_shader.texture,
                .interp_type = texture_shader.interp_type,
            }};
        },
    }
    
    return mesh_trans;
}

pub fn transformCoords(
    outer_alloc: std.mem.Allocator,
    coords: *const Coords,
    connect: *const Connect,
) !NDArray(f64) {
    // dims=(elems_num,coord[x,y,z],nodes_per_elem)
    const coord_dims = [_]usize{ connect.getElemsNum(), 3, connect.getNodesPerElem() };
    var elem_coord_arr = try NDArray(f64).initFlat(outer_alloc, coord_dims[0..]);
    @memset(elem_coord_arr.elems, 0.0);

    const dim_elem: usize = 0;
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    var elem_inds = [_]usize{ 0, 0, 0 };

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        elem_inds[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_coord_arr.dims[dim_node]) |nn| {
            elem_inds[dim_node] = nn;

            elem_inds[dim_field] = 0;
            elem_coord_arr.set(elem_inds[0..], coords.x(coord_inds[nn]));
            elem_inds[dim_field] = 1;
            elem_coord_arr.set(elem_inds[0..], coords.y(coord_inds[nn]));
            elem_inds[dim_field] = 2;
            elem_coord_arr.set(elem_inds[0..], coords.z(coord_inds[nn]));
        }
    }

    return elem_coord_arr;
}

pub fn transformField(
    allocator: std.mem.Allocator,
    connect: *const Connect,
    field: *const Field,
) !NDArray(f64) {
    // dims=(times_num,elems_num,fields_num,nodes_per_elem)
    const field_dims = [_]usize{
        field.getTimeN(),
        connect.getElemsNum(),
        field.getFieldsN(),
        connect.getNodesPerElem(),
    };
    var elem_field_arr = try NDArray(f64).initFlat(allocator, field_dims[0..]);
    @memset(elem_field_arr.elems, 0.0);

    const dim_time: usize = 0;
    const dim_elem: usize = 1;
    const dim_field: usize = 2;
    const dim_node: usize = 3;

    var set_elem_inds = [_]usize{ 0, 0, 0, 0 }; // dims=(time,elem,field,node)
    var get_field_inds = [_]usize{ 0, 0, 0 }; // dims=(time,coord,field)

    for (0..elem_field_arr.dims[dim_time]) |tt| {
        get_field_inds[0] = tt;
        set_elem_inds[dim_time] = tt;

        for (0..elem_field_arr.dims[dim_elem]) |ee| {
            set_elem_inds[dim_elem] = ee;
            const coord_inds: []usize = connect.getElem(ee);

            for (0..elem_field_arr.dims[dim_node]) |nn| {
                set_elem_inds[dim_node] = nn;
                get_field_inds[1] = coord_inds[nn];

                for (0..elem_field_arr.dims[dim_field]) |ff| {
                    get_field_inds[2] = ff;
                    const field_val: f64 = field.array.get(get_field_inds[0..]);

                    set_elem_inds[dim_field] = ff;
                    elem_field_arr.set(set_elem_inds[0..], field_val);
                }
            }
        }
    }

    return elem_field_arr;
}

pub fn transformUVs(
    allocator: std.mem.Allocator,
    uvs: *const NDArray(f64),
    connect: *const Connect,
) !NDArray(f64) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try NDArray(f64).initFlat(
        allocator,
        &[_]usize{ elems_num, 2, nodes_per_elem },
    );
    @memset(elem_uv_arr.elems, 0.0);

    for (0..elems_num) |ee| {
        const coord_inds = connect.getElem(ee);
        for (0..nodes_per_elem) |nn| {
            for (0..2) |uu| {
                const val = uvs.get(&[_]usize{ coord_inds[nn], uu });
                elem_uv_arr.set(&[_]usize{ ee, uu, nn }, val);
            }
        }
    }

    return elem_uv_arr;
}

pub fn meshRasterFromSimDataSlice(allocator: std.mem.Allocator,
                                   io: std.Io,
                                   sim_datas: []const meshio.SimData,
                                   mesh_types: []const MeshType,
                                   shader_mode: enum { flat, texture },
                                   uv_paths: ?[]const []const u8,
                                   texture_path: ?[]const u8,
                                   uv_file: ?[]const u8) ![]MeshRaster {
    var mesh_rasters = try allocator.alloc(MeshRaster, sim_datas.len);
    var initialized_count: usize = 0;
    errdefer {
        // Only need to free things if we allocated them here
        // uvs and texture in TexShader are allocated.
        for (0..initialized_count) |ii| {
            switch (mesh_rasters[ii].shader) {
                .texture => |tex| {
                    allocator.free(tex.uvs.elems);
                },
                else => {},
            }
        }
        allocator.free(mesh_rasters);
    }

    const uv_file_name = uv_file orelse "uvs.csv";

    for (sim_datas, 0..) |sim_data, ii| {
        mesh_rasters[ii] = MeshRaster{
            .mesh_type = mesh_types[ii],
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = sim_data.disp,
            .shader = undefined,
        };

        if (shader_mode == .flat) {
            if (sim_data.field) |field| {
                mesh_rasters[ii].shader = .{ .flat = .{
                    .field = field,
                    .bits = 8,
                }};
            } else {
                return error.MissingFieldData;
            }
        } else {
            const paths = uv_paths orelse return error.MissingUVPaths;
            const path_uvs = try std.fmt.allocPrint(
                allocator, "{s}{s}", .{paths[ii], uv_file_name}
            );
            defer allocator.free(path_uvs);
            
            var uvmap = try uvio.loadUVMap(allocator, io, path_uvs);
            
            const texture = try @import("imageio.zig").loadImage(
                allocator, io, texture_path.?, .tiff, u8, 1
            );
            
            mesh_rasters[ii].shader = .{ .texture = .{
                .uvs = uvmap.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
            }};
        }
        initialized_count += 1;
    }
    return mesh_rasters;
}

fn findAlignedCentroid(coords: *const Coords) struct {
    centroid: [3]f64,
    extent: [3]f64,
} {
    var min = [3]f64{
        std.math.inf(f64),
        std.math.inf(f64),
        std.math.inf(f64),
    };
    var max = [3]f64{
        -std.math.inf(f64),
        -std.math.inf(f64),
        -std.math.inf(f64),
    };

    for (0..coords.mat.rows_num) |ii| {
        const x = coords.mat.get(ii, 0);
        const y = coords.mat.get(ii, 1);
        const z = coords.mat.get(ii, 2);

        if (x < min[0]) min[0] = x;
        if (x > max[0]) max[0] = x;
        if (y < min[1]) min[1] = y;
        if (y > max[1]) max[1] = y;
        if (z < min[2]) min[2] = z;
        if (z > max[2]) max[2] = z;
    }

    return .{
        .centroid = .{
            (min[0] + max[0]) * 0.5,
            (min[1] + max[1]) * 0.5,
            (min[2] + max[2]) * 0.5,
        },
        .extent = .{
            max[0] - min[0],
            max[1] - min[1],
            max[2] - min[2],
        },
    };
}

pub fn arrangeMeshSlice(meshes: []MeshRaster,
                       gap: [3]f64,
                       max_divs: [3]usize) void {
    var max_extent = [3]f64{ 0, 0, 0 };

    // First pass: find the maximum extent among all individual meshes
    for (meshes) |mesh| {
        const bounds = findAlignedCentroid(&mesh.coords);
        for (0..3) |ii| {
            if (bounds.extent[ii] > max_extent[ii]) {
                max_extent[ii] = bounds.extent[ii];
            }
        }
    }

    const stride = [3]f64{
        max_extent[0] + gap[0],
        max_extent[1] + gap[1],
        max_extent[2] + gap[2],
    };

    // Second pass: arrange meshes in a regular grid
    for (meshes, 0..) |mesh, nn| {
        // Calculate grid indices based on max divisions per axis
        const ix = nn % max_divs[0];
        const iy = (nn / max_divs[0]) % max_divs[1];
        const iz = nn / (max_divs[0] * max_divs[1]);

        const target_center = [3]f64{
            @as(f64, @floatFromInt(ix)) * stride[0],
            @as(f64, @floatFromInt(iy)) * stride[1],
            @as(f64, @floatFromInt(iz)) * stride[2],
        };

        const bounds = findAlignedCentroid(&mesh.coords);

        const translation = [3]f64{
            target_center[0] - bounds.centroid[0],
            target_center[1] - bounds.centroid[1],
            target_center[2] - bounds.centroid[2],
        };

        var mat = mesh.coords.mat;

        // Apply translation in-place to the coordinate matrix
        for (0..mesh.coords.mat.rows_num) |ii| {
            const x = mat.get(ii, 0);
            const y = mat.get(ii, 1);
            const z = mat.get(ii, 2);

            mat.set(ii, 0, x + translation[0]);
            mat.set(ii, 1, y + translation[1]);
            mat.set(ii, 2, z + translation[2]);
        }
    }
}
