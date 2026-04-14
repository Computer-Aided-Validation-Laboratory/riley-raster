const std = @import("std");

pub const NDArray = @import("ndarray.zig").NDArray;
const MatSlice = @import("matslice.zig").MatSlice;

const meshio = @import("meshio.zig");
const Coords = meshio.Coords;
const Connect = meshio.Connect;
const Field = meshio.Field;

const uvio = @import("uvio.zig");
const UVMap = uvio.UVMap;

const imageio = @import("imageio.zig");
const ImageFormat = imageio.ImageFormat;

const imageops = @import("imageops.zig");
const ScalingParams = imageops.ScalingParams;
const ScaleStrategy = imageops.ScaleStrategy;

const shaderops = @import("shaderops.zig");
pub const NodalInput = shaderops.NodalInput;
pub const FlatInput = NodalInput;
pub const TexInput = shaderops.TexInput;
pub const ShaderInput = shaderops.ShaderInput;
pub const ShaderPrepared = shaderops.ShaderPrepared;

pub const MeshType = enum {
    tri3,
    tri6,
    quad4ibi,
    quad4newton,
    quad8,
    quad9,

    pub fn getNodesNum(self: MeshType) usize {
        return switch (self) {
            .tri3 => 3,
            .tri6 => 6,
            .quad4ibi, .quad4newton => 4,
            .quad8 => 8,
            .quad9 => 9,
        };
    }
};

pub const MeshInput = struct {
    mesh_type: MeshType,
    coords: Coords,
    connect: Connect,
    disp: ?Field,
    shader: shaderops.ShaderInput,
};

pub const MeshPrepared = struct {
    mesh_type: MeshType,
    coords: NDArray(f64),
    connect: Connect,
    shader: shaderops.ShaderPrepared,
};

pub fn prepareMesh(
    outer_alloc: std.mem.Allocator,
    mesh_input: *const MeshInput,
    coords: *const MatSlice(f64),
    scaling_params: ?ScalingParams,
) !MeshPrepared {
    const wrap_coords = Coords.init(coords.slice, coords.rows_num);
    const elem_coords = try prepareCoords(
        outer_alloc,
        &wrap_coords,
        &mesh_input.connect,
    );

    var mesh_prep = MeshPrepared{
        .mesh_type = mesh_input.mesh_type,
        .coords = elem_coords,
        .connect = mesh_input.connect,
        .shader = undefined,
    };

    switch (mesh_input.shader) {
        .nodal => |*nodal_in| {
            const elem_field = try prepareField(
                outer_alloc,
                &mesh_input.connect,
                &nodal_in.field,
            );

            const factors = if (scaling_params) |sp|
                imageops.getScaleFactors(nodal_in.scaling, nodal_in.bits, sp)
            else
                imageops.ScaleFactors{ .mul = 1.0, .add = 0.0 };

            mesh_prep.shader = .{ .nodal = .{
                .elem_field = elem_field,
                .bits = nodal_in.bits,
                .scaling = nodal_in.scaling,
                .scale_over = nodal_in.scale_over,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = nodal_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex_u8 => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                1,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex_u8 = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .interp_type = tex_in.interp_type,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex_u16 => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                1,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex_u16 = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .interp_type = tex_in.interp_type,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex_rgb_u8 => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                3,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex_rgb_u8 = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .interp_type = tex_in.interp_type,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
        .tex_rgb_u16 => |*tex_in| {
            const elem_uvs = try prepareUVs(
                outer_alloc,
                &tex_in.uvs,
                &mesh_input.connect,
            );
            const params = imageops.getScalingParamsTexture(
                3,
                &tex_in.texture,
                tex_in.scaling,
            );
            const factors = imageops.getScaleFactors(tex_in.scaling, tex_in.bits, params);
            mesh_prep.shader = .{ .tex_rgb_u16 = .{
                .elem_uvs = elem_uvs,
                .texture = tex_in.texture,
                .interp_type = tex_in.interp_type,
                .bits = tex_in.bits,
                .scaling = tex_in.scaling,
                .scale_mul = factors.mul,
                .scale_add = factors.add,
                .normal_type = tex_in.normal_type,
                .elem_normals = null,
            } };
        },
    }

    return mesh_prep;
}

pub fn prepareCoords(
    outer_alloc: std.mem.Allocator,
    coords: *const Coords,
    connect: *const Connect,
) !NDArray(f64) {
    const coord_dims = [_]usize{ connect.getElemsNum(), 3, connect.getNodesPerElem() };
    var elem_coord_arr = try NDArray(f64).initFlat(outer_alloc, coord_dims[0..]);
    @memset(elem_coord_arr.slice, 0.0);

    const dim_elem: usize = 0;
    const dim_field: usize = 1;
    const dim_node: usize = 2;

    var elem_idxs = [_]usize{ 0, 0, 0 };

    for (0..elem_coord_arr.dims[dim_elem]) |ee| {
        elem_idxs[dim_elem] = ee;
        const coord_inds: []usize = connect.getElem(ee);

        for (0..elem_coord_arr.dims[dim_node]) |nn| {
            elem_idxs[dim_node] = nn;

            const node_idx = coord_inds[nn];
            const x = coords.x(node_idx);
            const y = coords.y(node_idx);
            const z = coords.z(node_idx);

            elem_idxs[dim_field] = 0;
            elem_coord_arr.set(elem_idxs[0..], x);
            elem_idxs[dim_field] = 1;
            elem_coord_arr.set(elem_idxs[0..], y);
            elem_idxs[dim_field] = 2;
            elem_coord_arr.set(elem_idxs[0..], z);
        }
    }

    return elem_coord_arr;
}

pub fn prepareField(
    outer_alloc: std.mem.Allocator,
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
    var elem_field_arr = try NDArray(f64).initFlat(outer_alloc, field_dims[0..]);
    @memset(elem_field_arr.slice, 0.0);

    const dim_time: usize = 0;
    const dim_elem: usize = 1;
    const dim_field: usize = 2;
    const dim_node: usize = 3;

    var set_elem_idxs = [_]usize{ 0, 0, 0, 0 }; // dims=(time,elem,field,node)
    var get_field_idxs = [_]usize{ 0, 0, 0 }; // dims=(time,coord,field)

    for (0..elem_field_arr.dims[dim_time]) |tt| {
        get_field_idxs[0] = @min(tt, field.array.dims[0] - 1);
        set_elem_idxs[dim_time] = tt;

        for (0..elem_field_arr.dims[dim_elem]) |ee| {
            set_elem_idxs[dim_elem] = ee;
            const coord_inds: []usize = connect.getElem(ee);

            for (0..elem_field_arr.dims[dim_node]) |nn| {
                set_elem_idxs[dim_node] = nn;
                get_field_idxs[1] = coord_inds[nn];

                for (0..elem_field_arr.dims[dim_field]) |ff| {
                    get_field_idxs[2] = ff;
                    const field_val: f64 = field.array.get(get_field_idxs[0..]);

                    set_elem_idxs[dim_field] = ff;
                    elem_field_arr.set(set_elem_idxs[0..], field_val);
                }
            }
        }
    }

    return elem_field_arr;
}

pub fn prepareUVs(
    outer_alloc: std.mem.Allocator,
    uvs: *const NDArray(f64),
    connect: *const Connect,
) !NDArray(f64) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try NDArray(f64).initFlat(
        outer_alloc,
        &[_]usize{ elems_num, 2, nodes_per_elem },
    );
    @memset(elem_uv_arr.slice, 0.0);

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

pub fn meshInputFromSimDataSlice(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    sim_datas: []const meshio.SimData,
    mesh_types: []const MeshType,
    shader_mode: enum { flat, texture },
    uv_paths: ?[]const []const u8,
    texture_path: ?[]const u8,
    uv_file: ?[]const u8,
) ![]MeshInput {
    var mesh_inputs = try outer_alloc.alloc(MeshInput, sim_datas.len);
    var initialized_count: usize = 0;
    errdefer {
        for (0..initialized_count) |ii| {
            switch (mesh_inputs[ii].shader) {
                .tex_u8 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_u16 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                else => {},
            }
        }
        outer_alloc.free(mesh_inputs);
    }

    const uv_file_name = uv_file orelse "uvs.csv";

    for (sim_datas, 0..) |sim_data, ii| {
        mesh_inputs[ii] = MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = sim_data.disp,
            .shader = undefined,
        };

        if (shader_mode == .flat) {
            if (sim_data.field) |field| {
                mesh_inputs[ii].shader = .{ .nodal = .{
                    .field = field,
                    .bits = 8,
                    .normal_type = .none,
                } };
            } else {
                return error.MissingFieldData;
            }
        } else {
            const paths = uv_paths orelse return error.MissingUVPaths;
            const path_uvs = try std.fmt.allocPrint(
                outer_alloc,
                "{s}{s}",
                .{ paths[ii], uv_file_name },
            );
            defer outer_alloc.free(path_uvs);

            var uvmap = try uvio.loadUVMap(outer_alloc, io, path_uvs);

            const format: ImageFormat = if (std.mem.endsWith(u8, texture_path.?, ".bmp"))
                .bmp
            else
                .tiff;

            const texture = try imageio.loadImage(
                outer_alloc,
                io,
                texture_path.?,
                format,
                u8,
                1,
            );

            mesh_inputs[ii].shader = .{ .tex_u8 = .{
                .uvs = uvmap.array,
                .texture = texture,
                .interp_type = .cubic_lut_lerp,
                .normal_type = .none,
            } };
        }
        initialized_count += 1;
    }
    return mesh_inputs;
}

pub fn findAlignedCentroid(coords: *const Coords) struct {
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

pub fn arrangeMeshSlice(
    meshes: []MeshInput,
    gap: [3]f64,
    max_divs: [3]usize,
) void {
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
