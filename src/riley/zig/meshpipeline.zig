// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const vecslice = @import("vecslice.zig");
const shapefun = @import("shapefun.zig");

const meshio = @import("meshio.zig");
const uvio = @import("uvio.zig");
const imageio = @import("imageio.zig");

const rastcfg = @import("rasterconfig.zig");
const imageops = @import("imageops.zig");
const cam = @import("camera.zig");
const pce = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const frontend = @import("rasterfrontend.zig");
const sceneops = @import("sceneops.zig");
const texops = @import("textureops.zig");
const Timestamp = std.Io.Clock.Timestamp;

const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const normals = @import("normals.zig");
const geomkerns = @import("geometrykernels.zig");
const HullMultiRoot = @import("hullmultiroot.zig").HullMultiRoot;
const distbounds = @import("distortbounds.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

// Input: Raw user data for all frames.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// meshio.Connect: Connectivity table links nodes to elems.
pub const MeshInput = struct {
    mesh_type: geomkerns.MeshType,
    normal_type: normals.NormalType = .exact,
    coords: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shaders: shaderops.MeshShaderSetInput,
};

// Static: Persistent multi-frame resources in the engine's memory.
// meshio.Coords/Fields: Node-order [total_nodes, ...]
// Shader UVs: Elem-order (gathered during static init as they are usually static).
pub const MeshStatic = struct {
    scene_mesh_idx: usize = 0,
    mesh_type: geomkerns.MeshType,
    normal_type: normals.NormalType = .exact,
    coords_orig: meshio.Coords,
    connect: meshio.Connect,
    disp: ?meshio.Field,
    shaders: shaderops.MeshShaderSetStatic,
};

pub const MultiRootHulls = struct {
    indices: matslice.MatSlice(u8),
    valid_depth: vecslice.VecSlice(u8),
    slot_by_visible_elem: vecslice.VecSlice(u32),
    leaves_pre_calc: []HullMultiRoot.BezierLeafPreCalc = &.{},
    leaves_on_the_fly: []HullMultiRoot.BezierLeafOnTheFly = &.{},
};

pub const MeshHulls = struct {
    // Dims: [mesh_idex][elems_in_image,2(x,y),NH(num_hull_pts)]
    hull_adaptive_by_mesh: []const ?ndarray.NDArray(F),
    // Dims: [mesh_idx][slot_by_visible_elem LUT]
    hull_multiroot_by_mesh: []const ?MultiRootHulls,
};

// Workspace: Temporary node-order working area for the geometry pipeline.
// meshio.Coords: Node-order [total_nodes, 3]. Holds coords for a single frame after
// displacement.
pub const MeshFrameWorkspace = struct {
    coords_nodes: meshio.Coords,
    coords_nodes_def_world: ?meshio.Coords,
    vis_orig_elem_inds: []usize,
    elem_bboxes: []frontend.ElemBBox,
    root_classes: []frontend.ElemRootClass,
    elem_float_bboxes: ?[]distbounds.DistortBounds = null,
    elems_in_image: usize,
    hull_adaptive: ?ndarray.NDArray(F),
    hull_multiroot: ?MultiRootHulls,
    vis_counts_by_chunk: []usize,
    vis_offsets_by_chunk: []usize,
};

// Frame: Wraps the Prep payload with per-frame spatial metadata.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
pub const MeshFrame = struct {
    mesh: MeshPrepared,
    elem_bboxes: []frontend.ElemBBox,
    root_classes: []frontend.ElemRootClass,
    elem_float_bboxes: ?[]distbounds.DistortBounds = null,
    elems_in_image: usize,
    total_elems_num: usize,
    hull_adaptive: ?ndarray.NDArray(F),
    hull_multiroot: ?MultiRootHulls,
    frame_workspace: MeshFrameWorkspace,
};

// Prep: Data culled and gathered for the raster loop for a SINGLE frame.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
// Elem-order [vis_elems, field, nodes_per_elem]
pub const MeshPrepared = struct {
    scene_mesh_idx: usize = 0,
    mesh_type: geomkerns.MeshType,
    coords: ndarray.NDArray(F),
    hit_geometry: meshhit.MeshHitGeomPrepared = .{},
    shaders: shaderops.MeshShaderSetPrepared,
};

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn calcNodesPerElem(meshes: []const MeshPrepared) F {
    var nodes_sum: usize = 0;
    for (meshes) |mesh| {
        nodes_sum += mesh.mesh_type.getNodesNum();
    }
    return @as(F, @floatFromInt(nodes_sum)) / @as(F, @floatFromInt(meshes.len));
}

pub fn countFrames(meshes: []const MeshInput, cameras: []const cam.CameraInput) usize {
    const dim_time_pre: usize = 0;
    var num_time: usize = 1;

    for (meshes) |mesh| {
        var selected = false;
        for (cameras) |camera| {
            if (shaderops.hasShader(mesh.shaders, camera.render_format)) {
                selected = true;
            }
        }

        if (!selected) continue;

        if (mesh.disp) |field| {
            num_time = @max(num_time, field.array.dims[dim_time_pre]);
        }

        for (cameras) |camera| {
            const selected_shader = shaderops.selectShader(
                shaderops.ShaderDirectInput,
                shaderops.ShaderPipeInput,
                &mesh.shaders,
                camera.render_format,
            ) orelse continue;

            switch (selected_shader) {
                .direct => |shader| switch (shader.*) {
                    .nodal => |nodal| {
                        num_time = @max(
                            num_time,
                            nodal.field.array.dims[dim_time_pre],
                        );
                    },
                    else => {},
                },
                .pipe => |pipe| {
                    for (pipe.stages) |stage| {
                        switch (stage) {
                            .source => |src| switch (src.shader) {
                                .nodal => |nodal| {
                                    num_time = @max(
                                        num_time,
                                        nodal.field.array.dims[dim_time_pre],
                                    );
                                },
                                else => {},
                            },
                            else => {},
                        }
                    }
                },
            }
        }
    }

    return num_time;
}

pub fn countOutputFields(meshes: []const MeshInput, cameras: []const cam.CameraInput) u8 {
    var num_fields: u8 = 0;
    for (meshes) |mesh| {
        for (cameras) |camera| {
            const selected_shader = shaderops.selectShader(
                shaderops.ShaderDirectInput,
                shaderops.ShaderPipeInput,
                &mesh.shaders,
                camera.render_format,
            ) orelse continue;
            _ = selected_shader;
            const mesh_fields = camera.render_format.channels();
            num_fields = @max(num_fields, mesh_fields);
        }
    }
    return num_fields;
}

pub fn countStaticMeshElems(mesh_static: []const MeshStatic) usize {
    var total: usize = 0;
    for (mesh_static) |mesh| {
        total += mesh.connect.table.rows_num;
    }
    return total;
}

pub fn countMeshInputElems(meshes: []const MeshInput) usize {
    var total: usize = 0;
    for (meshes) |mesh| {
        total += mesh.connect.table.rows_num;
    }
    return total;
}

pub fn countStaticMeshNodes(mesh_static: []const MeshStatic) usize {
    var total: usize = 0;
    for (mesh_static) |mesh| {
        total += mesh.coords_orig.mat.rows_num;
    }
    return total;
}

// External helper to turn a SimData struct into a MeshInput with associted shader data for
// rendering
pub fn meshInputFromSimDataSlice(
    outer_alloc: std.mem.Allocator,
    io: std.Io,
    sim_datas: []const meshio.SimData,
    mesh_types: []const geomkerns.MeshType,
    shader_mode: enum { nodal, tex },
    uv_paths: ?[]const []const u8,
    tex_path: ?[]const u8,
    uv_file: ?[]const u8,
) ![]MeshInput {
    var mesh_inputs = try outer_alloc.alloc(MeshInput, sim_datas.len);
    var initialized_count: usize = 0;
    errdefer {
        for (0..initialized_count) |ii| {
            switch (mesh_inputs[ii].shaders.mono.?.direct) {
                .tex_u8 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_u16 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_f => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_rgb_u8 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_rgb_u16 => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .tex_rgb_f => |tex| {
                    outer_alloc.free(tex.uvs.slice);
                },
                .func => |tex_func| {
                    if (tex_func.uvs) |uvs| outer_alloc.free(uvs.slice);
                },
                .func_rgb, .func_multi => |tex_func| {
                    if (tex_func.uvs) |uvs| outer_alloc.free(uvs.slice);
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
            .shaders = .{},
        };

        if (shader_mode == .nodal) {
            if (sim_data.field) |field| {
                mesh_inputs[ii].shaders.mono = .{ .direct = .{ .nodal = .{
                    .field = field,
                } } };
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

            const uvmap = try uvio.loadUVMap(outer_alloc, io, path_uvs);

            const format: imageio.ImageFormat = if (std.mem.endsWith(u8, tex_path.?, ".bmp"))
                .bmp
            else
                .tiff;

            const tex = try imageio.loadImage(
                u8,
                1,
                outer_alloc,
                io,
                tex_path.?,
                format,
            );

            mesh_inputs[ii].shaders.mono = .{ .direct = .{ .tex_u8 = .{
                .uvs = uvmap.array,
                .tex = tex,
                .samp_cfg = .{ .sample = .cubic_catmull_rom, .mode = .direct },
            } } };
        }
        initialized_count += 1;
    }
    return mesh_inputs;
}

// -----------------------------------------------------------------------------------------
// Mesh Initialisation: Initial mesh and coordinate preparation
// -----------------------------------------------------------------------------------------

pub fn initMeshStatic(
    allocator: std.mem.Allocator,
    mesh_input: *const MeshInput,
) !MeshStatic {
    const coords_orig = try sceneops.duplicateCoords(
        allocator,
        mesh_input.coords,
    );

    var shaders: shaderops.MeshShaderSetStatic = .{};
    if (mesh_input.shaders.mono) |execution|
        shaders.mono = try createExecutionStatic(allocator, execution, &mesh_input.connect);
    if (mesh_input.shaders.rgb) |execution|
        shaders.rgb = try createExecutionStatic(allocator, execution, &mesh_input.connect);
    if (mesh_input.shaders.ir) |execution|
        shaders.ir = try createExecutionStatic(allocator, execution, &mesh_input.connect);
    if (mesh_input.shaders.multifield) |execution|
        shaders.multifield = try createExecutionStatic(allocator, execution, &mesh_input.connect);

    return .{
        .mesh_type = mesh_input.mesh_type,
        .normal_type = mesh_input.normal_type,
        .coords_orig = coords_orig,
        .connect = mesh_input.connect,
        .disp = mesh_input.disp,
        .shaders = shaders,
    };
}

fn createExecutionStatic(
    allocator: std.mem.Allocator,
    execution: shaderops.ShaderExecutionInput,
    connect: *const meshio.Connect,
) !shaderops.ShaderExecutionStatic {
    return switch (execution) {
        .direct => |shader| .{ .direct = try createShaderDirectStatic(allocator, shader, connect) },
        .pipe => |pipe| .{ .pipe = try createShaderPipeStatic(allocator, pipe, connect) },
    };
}

fn createShaderPipeStatic(
    allocator: std.mem.Allocator,
    pipe: shaderops.ShaderPipeInput,
    connect: *const meshio.Connect,
) !shaderops.ShaderPipeStatic {
    const stages = try allocator.alloc(shaderops.ShaderPipeStageStatic, pipe.stages.len);

    for (pipe.stages, 0..) |stage, si| {
        stages[si] = switch (stage) {
            .source => |src| .{ .source = .{
                .shader = try createShaderDirectStatic(allocator, src.shader, connect),
                .destination = src.destination,
                .global_scaling = switch (src.shader) {
                    .nodal => |n| if (n.scale_over == .over_frames)
                        imageops.getScalingParamsNDArray(&n.field.array, null, n.scaling)
                    else
                        null,
                    else => null,
                },
            } },
            .grey_to_emissivity => |m| .{ .grey_to_emissivity = m },
            .clamp => |c| .{ .clamp = c },
            .affine_map => |m| .{ .affine_map = m },
            .lut_map => |m| .{ .lut_map = m },
            .blend => |m| .{ .blend = m },
            .normalise => |m| .{ .normalise = m },
        };
    }

    return .{
        .stages = stages,
        .resolver = pipe.resolver,
        .constants = pipe.constants,
    };
}

fn createShaderDirectStatic(
    allocator: std.mem.Allocator,
    shader_in: shaderops.ShaderDirectInput,
    connect: *const meshio.Connect,
) !shaderops.ShaderDirectStatic {
    var shader_static: shaderops.ShaderDirectStatic = undefined;
    switch (shader_in) {
        .nodal => |nodal_in| {
            shader_static = .{ .nodal = .{
                .field = nodal_in.field,
                .output_gain = nodal_in.output_gain,
                .output_offset = nodal_in.output_offset,
                .scaling = nodal_in.scaling,
                .scale_over = nodal_in.scale_over,
                .global_scaling = if (nodal_in.scale_over == .over_frames)
                    imageops.getScalingParamsNDArray(&nodal_in.field.array, null, nodal_in.scaling)
                else
                    null,
            } };
        },
        .tex_multi_u8 => |tex_in| {
            shader_static = try createTextureMultiStatic(u8, allocator, tex_in, connect);
        },
        .tex_multi_u16 => |tex_in| {
            shader_static = try createTextureMultiStatic(u16, allocator, tex_in, connect);
        },
        .tex_multi_f => |tex_in| {
            shader_static = try createTextureMultiStatic(F, allocator, tex_in, connect);
        },
        .tex_u8 => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_u8 = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .tex_u16 => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_u16 = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .tex_f => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_f = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .tex_rgb_u8 => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_rgb_u8 = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .tex_rgb_u16 => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_rgb_u16 = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .tex_rgb_f => |tex_in| {
            const elem_uvs = try prepUVs(
                allocator,
                &tex_in.uvs,
                connect,
            );
            shader_static = .{ .tex_rgb_f = .{
                .elem_uvs = elem_uvs,
                .tex = tex_in.tex,
                .samp_cfg = tex_in.samp_cfg,
                .output_gain = tex_in.output_gain,
                .output_offset = tex_in.output_offset,
                .scaling = tex_in.scaling,
            } };
        },
        .func => |tex_func_in| {
            const elem_uvs = if (tex_func_in.uvs) |uvs|
                try prepUVs(
                    allocator,
                    &uvs,
                    connect,
                )
            else
                null;
            shader_static = .{ .func = .{
                .elem_uvs = elem_uvs,
                .coord_mode = tex_func_in.coord_mode,
                .builtin = tex_func_in.builtin,
                .params = shaderops.normFuncShaderParams(
                    tex_func_in.builtin,
                    tex_func_in.params,
                ),
                .output_gain = tex_func_in.output_gain,
                .output_offset = tex_func_in.output_offset,
                .scaling = tex_func_in.scaling,
            } };
        },
        .func_multi => |multi_in| {
            const elem_uvs = if (multi_in.uvs) |uvs|
                try prepUVs(allocator, &uvs, connect)
            else
                null;
            shader_static = .{ .func_multi = .{
                .elem_uvs = elem_uvs,
                .coord_mode = multi_in.coord_mode,
                .channels = multi_in.channels,
            } };
        },
        .func_rgb => |tex_func_in| {
            const elem_uvs = if (tex_func_in.uvs) |uvs|
                try prepUVs(
                    allocator,
                    &uvs,
                    connect,
                )
            else
                null;
            shader_static = .{ .func_rgb = .{
                .elem_uvs = elem_uvs,
                .coord_mode = tex_func_in.coord_mode,
                .builtin = tex_func_in.builtin,
                .params = shaderops.normFuncShaderParams(
                    tex_func_in.builtin,
                    tex_func_in.params,
                ),
                .output_gain = tex_func_in.output_gain,
                .output_offset = tex_func_in.output_offset,
                .scaling = tex_func_in.scaling,
            } };
        },
    }

    return shader_static;
}

fn createTextureMultiStatic(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: shaderops.TexInput(texops.TexDataDyn(T)),
    connect: *const meshio.Connect,
) !shaderops.ShaderDirectStatic {
    const elem_uvs = try prepUVs(allocator, &input.uvs, connect);
    const float_tex: texops.TexDataDyn(F) = if (comptime T == F) input.tex else blk: {
        const values = try ndarray.NDArray(F).initFlat(allocator, input.tex.array.dims);
        for (input.tex.array.slice, values.slice) |source, *destination| {
            destination.* = @floatFromInt(source);
        }
        break :blk .{
            .array = values,
            .rows_num = input.tex.rows_num,
            .cols_num = input.tex.cols_num,
        };
    };
    return .{ .tex_multi_f = .{
        .elem_uvs = elem_uvs,
        .tex = float_tex,
        .samp_cfg = input.samp_cfg,
        .output_gain = input.output_gain,
        .output_offset = input.output_offset,
        .scaling = input.scaling,
    } };
}

pub const GeomTimes = struct {
    coord_ops: u64 = 0,
    cull_ops: u64 = 0,
    prep_hulls_shaders: u64 = 0,
    remap_inds: u64 = 0,
};

// -----------------------------------------------------------------------------------------
// Mesh Pipeline: Main entry point into the mesh frame pipeline
// -----------------------------------------------------------------------------------------

pub fn prepMeshFrames(
    arena_alloc: std.mem.Allocator,
    chunk_exec: *pce.ParaChunkExecutor,
    workers_num: usize,
    camera: *const cam.CameraPrepared,
    config: rastcfg.RasterConfig,
    frame_idx: usize,
    static_meshes: []const MeshStatic,
    nodal_global_scaling: []const ?imageops.ScalingParams,
    frame_meshes: []MeshFrame,
    timing: *GeomTimes,
) !FrameGeomResult {
    _ = nodal_global_scaling;
    var res = FrameGeomResult{
        .total_elems_num = 0,
        .total_elems_in_image = 0,
    };

    for (static_meshes, 0..) |*mesh_static, ii| {
        // Only needed for nodal interpolation shading and only if not .none. If .none we
        // directly render float fields unscaled.
        var nodal_frame_scaling: ?imageops.ScalingParams = null;
        const selected = shaderops.selectShader(
            shaderops.ShaderDirectStatic,
            shaderops.ShaderPipeStatic,
            &mesh_static.shaders,
            camera.render_format,
        );
        if (selected) |execution| switch (execution) {
            .direct => |shader| switch (shader.*) {
                .nodal => |s| {
                    if (s.scale_over == .over_frames) {
                        nodal_frame_scaling = s.global_scaling;
                    } else { // .within_frames
                        nodal_frame_scaling = imageops.getScalingParamsNDArray(
                            &s.field.array,
                            frame_idx,
                            s.scaling,
                        );
                    }
                },
                else => {},
            },
            .pipe => {},
        };

        // Prepares meshes for each frame including coord transforms to camera space and
        // data reshaping to elem order for a given frame.
        frame_meshes[ii] = try prepMeshFrame(
            arena_alloc,
            chunk_exec,
            workers_num,
            camera,
            config,
            mesh_static,
            frame_idx,
            nodal_frame_scaling,
            timing,
        );
        res.total_elems_num += frame_meshes[ii].total_elems_num;
        res.total_elems_in_image += frame_meshes[ii].elems_in_image;
    }

    return res;
}

pub fn prepMeshFrame(
    outer_alloc: std.mem.Allocator,
    chunk_exec: *pce.ParaChunkExecutor,
    workers_num: usize,
    camera: *const cam.CameraPrepared,
    config: rastcfg.RasterConfig,
    mesh_static: *const MeshStatic,
    frame_idx: usize,
    scaling_params: ?imageops.ScalingParams,
    timing: *GeomTimes,
) !MeshFrame {
    return switch (mesh_static.mesh_type) {
        inline else => |MT| {
            var pipeline = try FrameMeshPipeline(MT).init(
                outer_alloc,
                camera,
                mesh_static,
                frame_idx,
                config.advanced.solver.oneroot.hull_mode,
                config.advanced.solver.multiroot.mode,
                config.advanced.solver.multiroot.edge_fun_mode,
                config.advanced.distortion.edge_spacing_px,
                scaling_params,
                chunk_exec,
                workers_num,
            );
            return try pipeline.run(outer_alloc, timing);
        },
    };
}

pub const FrameGeomResult = struct {
    total_elems_num: usize,
    total_elems_in_image: usize,
};

// Outside of pipeline because these are static - we gather these into an NDarray once
// for all frames and cameras
fn prepUVs(
    outer_alloc: std.mem.Allocator,
    uvs: *const ndarray.NDArray(F),
    connect: *const meshio.Connect,
) !ndarray.NDArray(F) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try ndarray.NDArray(F).initFlat(
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

fn initMeshFrameWorkspace(
    allocator: std.mem.Allocator,
    mesh_static: *const MeshStatic,
    selection: shaderops.RenderFormat,
) !MeshFrameWorkspace {
    return .{
        .coords_nodes = try meshio.Coords.initAlloc(
            allocator,
            mesh_static.coords_orig.mat.rows_num,
        ),
        .coords_nodes_def_world = if (shaderSetNeedsDeformedWorld(mesh_static.shaders, selection))
            try meshio.Coords.initAlloc(
                allocator,
                mesh_static.coords_orig.mat.rows_num,
            )
        else
            null,
        .vis_orig_elem_inds = &.{},
        .elem_bboxes = &.{},
        .root_classes = &.{},
        .elem_float_bboxes = null,
        .elems_in_image = 0,
        .hull_adaptive = null,
        .hull_multiroot = null,
        .vis_counts_by_chunk = &.{},
        .vis_offsets_by_chunk = &.{},
    };
}

fn shaderNeedsDeformedWorld(shader: shaderops.ShaderDirectStatic) bool {
    return switch (shader) {
        .func => |func_static| func_static.coord_mode == .world_deformed,
        .func_rgb, .func_multi => |func_static| func_static.coord_mode == .world_deformed,
        else => false,
    };
}

fn shaderHitSelection(
    shader: shaderops.ShaderDirectStatic,
    normal_type: normals.NormalType,
) meshhit.MeshHitSelection {
    var selection = meshhit.MeshHitSelection.initEmpty();
    switch (shader) {
        .func, .func_rgb, .func_multi => |s| {
            switch (s.coord_mode) {
                .world_reference => selection.insert(.coords_ref),
                .world_deformed => selection.insert(.coords_def),
                else => {},
            }
            if ((s.builtin == .lambertian_normal_z or
                for (s.channels) |ch| {
                    if (ch.builtin == .lambertian_normal_z) break true;
                } else false) and normal_type != .none)
            {
                selection.insert(.surf_norm);
            }
        },
        else => {},
    }
    return selection;
}

fn shaderSetHitSelection(
    shaders: shaderops.MeshShaderSetStatic,
    role: shaderops.RenderFormat,
    normal_type: normals.NormalType,
) meshhit.MeshHitSelection {
    var selection = meshhit.MeshHitSelection.initEmpty();
    const selected = shaderops.selectShader(
        shaderops.ShaderDirectStatic,
        shaderops.ShaderPipeStatic,
        &shaders,
        role,
    ) orelse return selection;
    switch (selected) {
        .direct => |shader| return shaderHitSelection(shader.*, normal_type),
        .pipe => |pipe| {
            for (pipe.stages) |stage| switch (stage) {
                .source => |src| selection.setUnion(shaderHitSelection(src.shader, normal_type)),
                else => {},
            };
        },
    }
    return selection;
}

test "MeshHit requirements follow the selected camera role" {
    const stages = [_]shaderops.ShaderPipeStageStatic{
        .{ .source = .{
            .shader = .{ .func = .{
                .elem_uvs = null,
                .coord_mode = .world_reference,
                .builtin = .linear,
            } },
            .destination = .{ .kind = .channel, .index = 0 },
        } },
        .{ .source = .{
            .shader = .{ .func = .{
                .elem_uvs = null,
                .coord_mode = .world_deformed,
                .builtin = .lambertian_normal_z,
            } },
            .destination = .{ .kind = .channel, .index = 0 },
        } },
    };
    const shaders = shaderops.MeshShaderSetStatic{
        .mono = .{ .direct = .{ .nodal = .{ .field = undefined } } },
        .ir = .{ .pipe = .{
            .stages = &stages,
            .resolver = undefined,
            .constants = &.{},
        } },
    };
    const direct = shaderSetHitSelection(shaders, .mono, .exact);
    try std.testing.expect(direct.count() == 0);
    try std.testing.expect(!shaderSetNeedsDeformedWorld(shaders, .mono));

    const pipe = shaderSetHitSelection(shaders, .ir, .exact);
    try std.testing.expect(pipe.contains(.coords_ref));
    try std.testing.expect(pipe.contains(.coords_def));
    try std.testing.expect(pipe.contains(.surf_norm));
    try std.testing.expect(shaderSetNeedsDeformedWorld(shaders, .ir));

    const no_norm = shaderSetHitSelection(shaders, .ir, .none);
    try std.testing.expect(!no_norm.contains(.surf_norm));
}

fn shaderSetNeedsDeformedWorld(
    shaders: shaderops.MeshShaderSetStatic,
    selection: shaderops.RenderFormat,
) bool {
    const selected = shaderops.selectShader(
        shaderops.ShaderDirectStatic,
        shaderops.ShaderPipeStatic,
        &shaders,
        selection,
    ) orelse return false;
    switch (selected) {
        .direct => |shader| return shaderNeedsDeformedWorld(shader.*),
        .pipe => |pipe| {
            for (pipe.stages) |stage| switch (stage) {
                .source => |src| if (shaderNeedsDeformedWorld(src.shader)) return true,
                else => {},
            };
            return false;
        },
    }
}

//------------------------------------------------------------------------------------------
// Geometry Pipeline Stages: meshio.Coords, Transform, Culling and Gathering
//------------------------------------------------------------------------------------------

fn prefixVisCounts(mesh_workspace: *MeshFrameWorkspace) void {
    var running_total: usize = 0;
    for (mesh_workspace.vis_counts_by_chunk, 0..) |vis_count, cc| {
        mesh_workspace.vis_offsets_by_chunk[cc] = running_total;
        running_total += vis_count;
    }
    mesh_workspace.elems_in_image = running_total;
}

fn getConnectNodesNum(connect: *const meshio.Connect) usize {
    var max_node_idx: usize = 0;
    for (connect.table_mem) |node_idx| {
        max_node_idx = @max(max_node_idx, node_idx);
    }
    return max_node_idx + 1;
}

//------------------------------------------------------------------------------------------
// Frame Mesh Pipeline: Implementation of the frame-by-frame geometry pipeline
//------------------------------------------------------------------------------------------

fn FrameMeshPipeline(comptime MT: geomkerns.MeshType) type {
    return struct {
        const FrameMeshPipelineType = @This();

        camera: *const cam.CameraPrepared,
        mesh_static: *const MeshStatic,
        frame_idx: usize,
        hull_mode: rastcfg.HullMode,
        multiroot_mode: rastcfg.MultirootSolverMode,
        multiroot_edge_fun_mode: rastcfg.EdgeFunMode,
        edge_spacing_px: F,
        scaling_params: ?imageops.ScalingParams,
        chunk_exec: *pce.ParaChunkExecutor,
        workers_num: usize,
        nodes_num: usize,
        elems_num: usize,
        node_chunk_size: usize,
        elem_chunk_size: usize,
        elem_chunks_num: usize,
        vis_chunk_size: usize,
        mesh_workspace: MeshFrameWorkspace,
        hit_geometry: meshhit.MeshHitGeomPrepared = .{},

        fn init(
            outer_alloc: std.mem.Allocator,
            camera: *const cam.CameraPrepared,
            mesh_static: *const MeshStatic,
            frame_idx: usize,
            hull_mode: rastcfg.HullMode,
            multiroot_mode: rastcfg.MultirootSolverMode,
            multiroot_edge_fun_mode: rastcfg.EdgeFunMode,
            edge_spacing_px: F,
            scaling_params: ?imageops.ScalingParams,
            chunk_exec: *pce.ParaChunkExecutor,
            workers_num: usize,
        ) !FrameMeshPipelineType {
            const nodes_num = mesh_static.coords_orig.mat.rows_num;
            const elems_num = mesh_static.connect.getElemsNum();
            const node_chunk_size = scalingpolicy.geometryNodeChunkSize(
                nodes_num,
                workers_num,
            );
            const elem_chunk_size = scalingpolicy.geometryElemChunkSize(
                elems_num,
                workers_num,
            );

            return .{
                .camera = camera,
                .mesh_static = mesh_static,
                .frame_idx = frame_idx,
                .hull_mode = hull_mode,
                .multiroot_mode = multiroot_mode,
                .multiroot_edge_fun_mode = multiroot_edge_fun_mode,
                .edge_spacing_px = edge_spacing_px,
                .scaling_params = scaling_params,
                .chunk_exec = chunk_exec,
                .workers_num = workers_num,
                .nodes_num = nodes_num,
                .elems_num = elems_num,
                .node_chunk_size = node_chunk_size,
                .elem_chunk_size = elem_chunk_size,
                .elem_chunks_num = pce.getStaticPartitionsNum(
                    chunk_exec,
                    elems_num,
                    elem_chunk_size,
                ),
                .vis_chunk_size = 1,
                .mesh_workspace = try initMeshFrameWorkspace(
                    outer_alloc,
                    mesh_static,
                    camera.render_format,
                ),
            };
        }

        fn run(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            timing: *GeomTimes,
        ) !MeshFrame {
            const time_start_coords = Timestamp.now(self.chunk_exec.io, .awake);
            self.displaceCoords();
            self.transformCoords();
            const time_end_coords = Timestamp.now(self.chunk_exec.io, .awake);
            timing.coord_ops += @intCast(time_start_coords.durationTo(
                time_end_coords,
            ).raw.nanoseconds);

            const time_start_cull = Timestamp.now(self.chunk_exec.io, .awake);
            try self.cullAndClassifyVisibleElems(outer_alloc);
            var mesh_prep = try self.gatherVisCoords(outer_alloc);
            const time_end_cull = Timestamp.now(self.chunk_exec.io, .awake);
            timing.cull_ops += @intCast(time_start_cull.durationTo(
                time_end_cull,
            ).raw.nanoseconds);

            const time_start_prep = Timestamp.now(self.chunk_exec.io, .awake);
            try self.prepareAdaptiveHulls(outer_alloc, &mesh_prep.coords);
            try self.prepareMultiRootElems(outer_alloc, &mesh_prep.coords);
            self.hit_geometry = try self.prepareHitGeometry(outer_alloc);
            mesh_prep.hit_geometry = self.hit_geometry;
            try self.prepareShader(outer_alloc, &mesh_prep);
            const time_end_prep = Timestamp.now(self.chunk_exec.io, .awake);
            timing.prep_hulls_shaders += @intCast(time_start_prep.durationTo(
                time_end_prep,
            ).raw.nanoseconds);

            const time_start_remap = Timestamp.now(self.chunk_exec.io, .awake);
            self.remapVisElemInds();
            const time_end_remap = Timestamp.now(self.chunk_exec.io, .awake);
            timing.remap_inds += @intCast(time_start_remap.durationTo(
                time_end_remap,
            ).raw.nanoseconds);

            return .{
                .mesh = mesh_prep,
                .elem_bboxes = self.mesh_workspace.elem_bboxes,
                .root_classes = self.mesh_workspace.root_classes,
                .elem_float_bboxes = self.mesh_workspace.elem_float_bboxes,
                .elems_in_image = self.mesh_workspace.elems_in_image,
                .total_elems_num = self.mesh_static.connect.getElemsNum(),
                .hull_adaptive = self.mesh_workspace.hull_adaptive,
                .hull_multiroot = self.mesh_workspace.hull_multiroot,
                .frame_workspace = self.mesh_workspace,
            };
        }

        const DisplaceCoordsStage = struct {
            frame_workspace: *MeshFrameWorkspace,
            mesh_static: *const MeshStatic,
            frame_idx: usize,
        };

        fn runDisplaceCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *DisplaceCoordsStage = @ptrCast(@alignCast(ctx_ptr));

            const actual_frame_idx = if (stage.mesh_static.disp) |disp|
                @min(stage.frame_idx, disp.array.dims[0] - 1)
            else
                0;

            for (range_start..range_end) |nn| {
                const coord_off = nn * 3;
                stage.frame_workspace.coords_nodes.mem[coord_off + 0] =
                    stage.mesh_static.coords_orig.mem[coord_off + 0];
                stage.frame_workspace.coords_nodes.mem[coord_off + 1] =
                    stage.mesh_static.coords_orig.mem[coord_off + 1];
                stage.frame_workspace.coords_nodes.mem[coord_off + 2] =
                    stage.mesh_static.coords_orig.mem[coord_off + 2];

                if (stage.mesh_static.disp) |disp| {
                    for (0..3) |cc| {
                        stage.frame_workspace.coords_nodes.mem[coord_off + cc] +=
                            disp.array.get(&[_]usize{ actual_frame_idx, nn, cc });
                    }
                }
            }
        }

        fn displaceCoords(self: *FrameMeshPipelineType) void {
            var displace_stage = DisplaceCoordsStage{
                .frame_workspace = &self.mesh_workspace,
                .mesh_static = self.mesh_static,
                .frame_idx = self.frame_idx,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &displace_stage,
                runDisplaceCoords,
                self.nodes_num,
                self.node_chunk_size,
            );
            if (self.mesh_workspace.coords_nodes_def_world) |*coords_def_world| {
                @memcpy(coords_def_world.mem, self.mesh_workspace.coords_nodes.mem);
            }
        }

        const TransformCoordsStage = struct {
            camera: *const cam.CameraPrepared,
            frame_workspace: *MeshFrameWorkspace,
        };

        fn runTransformCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *TransformCoordsStage = @ptrCast(@alignCast(ctx_ptr));

            if (MT == .tri3 or MT == .tri3opt) {
                frontend.nodesToRasterRangeInPlace(
                    stage.camera,
                    &stage.frame_workspace.coords_nodes,
                    range_start,
                    range_end,
                );
            } else {
                frontend.nodesToClipPxLengRangeInPlace(
                    stage.camera,
                    &stage.frame_workspace.coords_nodes,
                    range_start,
                    range_end,
                );
            }
        }

        fn transformCoords(self: *FrameMeshPipelineType) void {
            var transform_stage = TransformCoordsStage{
                .camera = self.camera,
                .frame_workspace = &self.mesh_workspace,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &transform_stage,
                runTransformCoords,
                self.nodes_num,
                self.node_chunk_size,
            );
        }

        const CullVisibleCountStage = struct {
            camera: *const cam.CameraPrepared,
            edge_spacing_px: F,
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            vis_counts_by_chunk: []usize,
            cached_distort_bboxes: ?[]?frontend.DistortElemBBox,
            cached_bboxes: ?[]?frontend.ElemBBox,
            cached_root_classes: []?frontend.ElemRootClass,
            hull_mode: rastcfg.HullMode,
        };

        fn runCullVisibleCount(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            const stage: *CullVisibleCountStage = @ptrCast(@alignCast(ctx_ptr));
            var vis_count: usize = 0;

            for (range_start..range_end) |ee| {
                const bbox: ?frontend.ElemBBox =
                    if (stage.camera.ideal_sensor_bounds) |ideal_sensor| blk: {
                        const distorted = frontend.calcVisibleDistortBBox(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.hull_mode,
                            stage.camera.prep_psf.halo_px,
                            ideal_sensor,
                            stage.edge_spacing_px,
                        );
                        if (stage.cached_distort_bboxes) |cached| cached[ee] = distorted;
                        break :blk if (distorted) |value| value.box_ints else null;
                    } else if (MT == .tri3 or MT == .tri3opt)
                        frontend.calcVisibleNodeBBoxTri3WithHalo(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.camera.prep_psf.halo_px,
                        )
                    else
                        frontend.calcVisibleNodeBBoxHighOrdWithHalo(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.hull_mode,
                            stage.camera.prep_psf.halo_px,
                        );

                if (bbox != null) {
                    if (comptime MT != .tri3 and MT != .tri3opt) {
                        stage.cached_root_classes[ee] = frontend.classifyElemFacing(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                        );
                    }
                    vis_count += 1;
                }
                if (stage.cached_bboxes) |cached| cached[ee] = bbox;
            }

            stage.vis_counts_by_chunk[chunk_idx] = vis_count;
        }

        fn cullAndClassifyVisibleElems(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
        ) !void {
            const has_distort = self.camera.ideal_sensor_bounds != null;

            var cached_distort_bboxes: ?[]?frontend.DistortElemBBox = null;
            if (has_distort) {
                cached_distort_bboxes = try outer_alloc.alloc(
                    ?frontend.DistortElemBBox,
                    self.elems_num,
                );
            }
            defer if (cached_distort_bboxes) |bboxes| outer_alloc.free(bboxes);
            const cached_bboxes = if (has_distort)
                null
            else
                try outer_alloc.alloc(?frontend.ElemBBox, self.elems_num);
            defer if (cached_bboxes) |bboxes| outer_alloc.free(bboxes);
            const cached_root_classes = if (MT == .tri3 or MT == .tri3opt)
                &.{}
            else
                try outer_alloc.alloc(?frontend.ElemRootClass, self.elems_num);
            defer if (cached_root_classes.len != 0)
                outer_alloc.free(cached_root_classes);

            self.mesh_workspace.vis_counts_by_chunk = try outer_alloc.alloc(
                usize,
                self.elem_chunks_num,
            );
            self.mesh_workspace.vis_offsets_by_chunk = try outer_alloc.alloc(
                usize,
                self.elem_chunks_num,
            );
            @memset(self.mesh_workspace.vis_counts_by_chunk, 0);
            @memset(self.mesh_workspace.vis_offsets_by_chunk, 0);

            var cull_count_stage = CullVisibleCountStage{
                .camera = self.camera,
                .edge_spacing_px = self.edge_spacing_px,
                .connect = &self.mesh_static.connect,
                .coords_nodes = &self.mesh_workspace.coords_nodes,
                .vis_counts_by_chunk = self.mesh_workspace.vis_counts_by_chunk,
                .cached_distort_bboxes = cached_distort_bboxes,
                .cached_bboxes = cached_bboxes,
                .cached_root_classes = cached_root_classes,
                .hull_mode = self.hull_mode,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &cull_count_stage,
                runCullVisibleCount,
                self.elems_num,
                self.elem_chunk_size,
            );

            prefixVisCounts(&self.mesh_workspace);

            self.mesh_workspace.vis_orig_elem_inds =
                try outer_alloc.alloc(usize, self.mesh_workspace.elems_in_image);
            self.mesh_workspace.elem_bboxes = try outer_alloc.alloc(
                frontend.ElemBBox,
                self.mesh_workspace.elems_in_image,
            );
            self.mesh_workspace.root_classes = if (MT == .tri3 or MT == .tri3opt)
                &.{}
            else
                try outer_alloc.alloc(
                    frontend.ElemRootClass,
                    self.mesh_workspace.elems_in_image,
                );
            self.mesh_workspace.elem_float_bboxes = if (has_distort)
                try outer_alloc.alloc(
                    distbounds.DistortBounds,
                    self.mesh_workspace.elems_in_image,
                )
            else
                null;

            var cull_fill_stage = CullVisibleFillStage{
                .camera = self.camera,
                .connect = &self.mesh_static.connect,
                .coords_nodes = &self.mesh_workspace.coords_nodes,
                .hull_mode = self.hull_mode,
                .cached_distort_bboxes = cached_distort_bboxes,
                .cached_bboxes = cached_bboxes,
                .cached_root_classes = cached_root_classes,
                .vis_orig_elem_inds = self.mesh_workspace.vis_orig_elem_inds,
                .elem_bboxes = self.mesh_workspace.elem_bboxes,
                .root_classes = self.mesh_workspace.root_classes,
                .elem_float_bboxes = self.mesh_workspace.elem_float_bboxes,
                .vis_offsets_by_chunk = self.mesh_workspace.vis_offsets_by_chunk,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &cull_fill_stage,
                runCullVisibleFill,
                self.elems_num,
                self.elem_chunk_size,
            );

            self.vis_chunk_size = scalingpolicy.geometryVisibleChunkSize(
                self.mesh_workspace.elems_in_image,
                self.workers_num,
            );
        }

        const CullVisibleFillStage = struct {
            camera: *const cam.CameraPrepared,
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            hull_mode: rastcfg.HullMode,
            cached_distort_bboxes: ?[]const ?frontend.DistortElemBBox,
            cached_bboxes: ?[]const ?frontend.ElemBBox,
            cached_root_classes: []const ?frontend.ElemRootClass,
            vis_orig_elem_inds: []usize,
            elem_bboxes: []frontend.ElemBBox,
            root_classes: []frontend.ElemRootClass,
            elem_float_bboxes: ?[]distbounds.DistortBounds,
            vis_offsets_by_chunk: []const usize,
        };

        fn runCullVisibleFill(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            const stage: *CullVisibleFillStage = @ptrCast(@alignCast(ctx_ptr));
            var write_idx = stage.vis_offsets_by_chunk[chunk_idx];

            for (range_start..range_end) |ee| {
                if (stage.cached_distort_bboxes) |cached| {
                    if (cached[ee]) |value| {
                        stage.vis_orig_elem_inds[write_idx] = ee;
                        stage.elem_bboxes[write_idx] = value.box_ints;
                        if (comptime MT != .tri3 and MT != .tri3opt) {
                            stage.root_classes[write_idx] =
                                stage.cached_root_classes[ee].?;
                        }
                        if (stage.elem_float_bboxes) |float_bboxes| {
                            float_bboxes[write_idx] = value.box_floats;
                        }
                        write_idx += 1;
                    }
                    continue;
                }

                const bbox = stage.cached_bboxes.?[ee];
                if (bbox) |b| {
                    stage.vis_orig_elem_inds[write_idx] = ee;
                    stage.elem_bboxes[write_idx] = b;
                    if (comptime MT != .tri3 and MT != .tri3opt) {
                        stage.root_classes[write_idx] =
                            stage.cached_root_classes[ee].?;
                    }
                    write_idx += 1;
                }
            }
        }

        const GatherVisibleCoordsStage = struct {
            connect: *const meshio.Connect,
            coords_nodes: *const meshio.Coords,
            vis_orig_elem_inds: []const usize,
            elem_coords: *ndarray.NDArray(F),
        };

        fn runGatherVisibleCoords(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleCoordsStage = @ptrCast(@alignCast(ctx_ptr));
            const N = comptime MT.getNodesNum();

            for (range_start..range_end) |pp| {
                const orig_ee = stage.vis_orig_elem_inds[pp];
                const coord_inds = stage.connect.getElem(orig_ee);
                for (0..N) |nn| {
                    const node_idx = coord_inds[nn];
                    stage.elem_coords.set(
                        &[_]usize{ pp, 0, nn },
                        stage.coords_nodes.x(node_idx),
                    );
                    stage.elem_coords.set(
                        &[_]usize{ pp, 1, nn },
                        stage.coords_nodes.y(node_idx),
                    );
                    stage.elem_coords.set(
                        &[_]usize{ pp, 2, nn },
                        stage.coords_nodes.z(node_idx),
                    );
                }
            }
        }

        fn gatherVisElemCoordsFromNodes(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            coords_nodes: *const meshio.Coords,
        ) !ndarray.NDArray(F) {
            const N = comptime MT.getNodesNum();
            var elem_coords = try ndarray.NDArray(F).initFlat(
                outer_alloc,
                &[_]usize{ self.mesh_workspace.elems_in_image, 3, N },
            );

            var gather_coords_stage = GatherVisibleCoordsStage{
                .connect = &self.mesh_static.connect,
                .coords_nodes = coords_nodes,
                .vis_orig_elem_inds = self.mesh_workspace.vis_orig_elem_inds,
                .elem_coords = &elem_coords,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &gather_coords_stage,
                runGatherVisibleCoords,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );

            return elem_coords;
        }

        fn gatherVisCoords(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
        ) !MeshPrepared {
            const elem_coords = try self.gatherVisElemCoordsFromNodes(
                outer_alloc,
                &self.mesh_workspace.coords_nodes,
            );

            return .{
                .scene_mesh_idx = self.mesh_static.scene_mesh_idx,
                .mesh_type = MT,
                .coords = elem_coords,
                .shaders = .{},
            };
        }

        const PrepareAdaptiveHullsStage = struct {
            camera: *const cam.CameraPrepared,
            elem_coords: *const ndarray.NDArray(F),
            hull_adaptive: *ndarray.NDArray(F),
            root_classes: []const frontend.ElemRootClass,
            hull_mode: rastcfg.HullMode,
        };

        fn runPrepareAdaptiveHulls(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *PrepareAdaptiveHullsStage = @ptrCast(@alignCast(ctx_ptr));
            frontend.prepareVisibleAdaptiveHullsRange(
                MT,
                stage.camera,
                stage.elem_coords,
                stage.hull_adaptive,
                stage.root_classes,
                stage.hull_mode,
                range_start,
                range_end,
            );
        }

        fn prepareAdaptiveHulls(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            elem_coords: *const ndarray.NDArray(F),
        ) !void {
            if (MT == .tri3 or MT == .tri3opt) {
                self.mesh_workspace.hull_adaptive = null;
                return;
            }

            const NH = comptime MT.getNumHullPoints();
            self.mesh_workspace.hull_adaptive = try ndarray.NDArray(F).initFlat(
                outer_alloc,
                &[_]usize{ self.mesh_workspace.elems_in_image, 2, NH },
            );

            var hulls_stage = PrepareAdaptiveHullsStage{
                .camera = self.camera,
                .elem_coords = elem_coords,
                .hull_adaptive = &self.mesh_workspace.hull_adaptive.?,
                .root_classes = self.mesh_workspace.root_classes,
                .hull_mode = self.hull_mode,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &hulls_stage,
                runPrepareAdaptiveHulls,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );
        }

        const PrepareMultiRootElemsStage = struct {
            camera: *const cam.CameraPrepared,
            elem_coords: *const ndarray.NDArray(F),
            hulls: *MultiRootHulls,
            multiroot_mode: rastcfg.MultirootSolverMode,
            edge_fun_mode: rastcfg.EdgeFunMode,
        };

        fn runPrepareMultiRootElems(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *PrepareMultiRootElemsStage = @ptrCast(@alignCast(ctx_ptr));
            const N = comptime MT.getNodesNum();
            const Seed = struct { z: F, index: u8 };

            for (range_start..range_end) |pp| {
                const slot = stage.hulls.slot_by_visible_elem.get(pp);
                if (slot == std.math.maxInt(u32)) continue;

                var coords: frontend.ElemCoords(N) = undefined;
                const xs = stage.elem_coords.getSlice(&.{ pp, 0, 0 }, 1);
                const ys = stage.elem_coords.getSlice(&.{ pp, 1, 0 }, 1);
                const zs = stage.elem_coords.getSlice(&.{ pp, 2, 0 }, 1);
                var seeds: [geomkerns.multiRootSeedCount(N)]Seed = undefined;
                var available: usize = 0;
                for (0..N) |nn| {
                    coords.x[nn] = xs[nn];
                    coords.y[nn] = ys[nn];
                    coords.z[nn] = zs[nn];
                    if (zs[nn] > 0) {
                        seeds[available] = .{
                            .z = zs[nn],
                            .index = @intCast(nn),
                        };
                        available += 1;
                    }
                }

                const leaf_offset = @as(usize, slot) * 4;
                if (stage.edge_fun_mode == .pre_calc) {
                    const leaf_slice =
                        stage.hulls.leaves_pre_calc[leaf_offset .. leaf_offset + 4];
                    HullMultiRoot.prepareFourBezierLeavesPreCalc(
                        N,
                        stage.camera,
                        coords,
                        leaf_slice[0..4],
                    );
                } else {
                    const leaf_slice =
                        stage.hulls.leaves_on_the_fly[leaf_offset .. leaf_offset + 4];
                    HullMultiRoot.prepareFourBezierLeavesOnTheFly(
                        N,
                        stage.camera,
                        coords,
                        leaf_slice[0..4],
                    );
                }

                for (N..geomkerns.multiRootSeedCount(N)) |seed_idx| {
                    const seed_uv = geomkerns.multiRootSeedCoords(
                        N,
                        @intCast(seed_idx),
                    );
                    var weights: [N]F = undefined;
                    var du: [N]F = undefined;
                    var dv: [N]F = undefined;
                    shapefun.shapeFunc(
                        N,
                        seed_uv[0],
                        seed_uv[1],
                        &weights,
                        &du,
                        &dv,
                    );
                    var seed_z: F = 0;
                    for (0..N) |nn| seed_z += weights[nn] * zs[nn];
                    if (seed_z > 0) {
                        seeds[available] = .{
                            .z = seed_z,
                            .index = @intCast(seed_idx),
                        };
                        available += 1;
                    }
                }
                for (1..available) |ii| {
                    const seed = seeds[ii];
                    var jj = ii;
                    while (jj > 0 and (seeds[jj - 1].z > seed.z or
                        (seeds[jj - 1].z == seed.z and
                            seeds[jj - 1].index > seed.index)))
                    {
                        seeds[jj] = seeds[jj - 1];
                        jj -= 1;
                    }
                    seeds[jj] = seed;
                }
                var ordered: [geomkerns.multiRootSeedCount(N)]Seed = undefined;
                var length: usize = 0;
                const nodes = frontend.Vec3Slices(F){
                    .x = &coords.x,
                    .y = &coords.y,
                    .z = &coords.z,
                };
                for (0..2) |tier_idx| {
                    var tier: [geomkerns.multiRootSeedCount(N)]Seed = undefined;
                    var tier_len: usize = 0;
                    for (seeds[0..available]) |seed| {
                        const uv = geomkerns.multiRootSeedCoords(
                            N,
                            seed.index,
                        );
                        const facing = frontend.projectedJacDetPhysical(
                            N,
                            nodes,
                            uv[0],
                            uv[1],
                        );
                        const front = std.math.isFinite(facing) and
                            facing < -buildconfig.config.tol.culling.projected_jacobian_abs;
                        if (front != (tier_idx == 0)) continue;
                        tier[tier_len] = seed;
                        tier_len += 1;
                    }
                    var used = [_]bool{false} ** geomkerns.multiRootSeedCount(N);
                    for (0..tier_len) |ii| {
                        const remaining = tier_len - ii;
                        const rank = switch (ii % 3) {
                            0 => @as(usize, 0),
                            1 => remaining / 2,
                            else => remaining - 1,
                        };
                        var seen: usize = 0;
                        for (0..tier_len) |jj| {
                            if (used[jj]) continue;
                            if (seen == rank) {
                                ordered[length] = tier[jj];
                                length += 1;
                                used[jj] = true;
                                break;
                            }
                            seen += 1;
                        }
                    }
                }
                std.debug.assert(length == available);
                @memcpy(seeds[0..available], ordered[0..available]);

                const count = @min(available, stage.hulls.indices.cols_num);
                const row = stage.hulls.indices.getSlice(slot);
                for (0..count) |ii| row[ii] = seeds[ii].index;
                stage.hulls.valid_depth.set(slot, @intCast(count));
            }
        }

        fn prepareMultiRootElems(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            elem_coords: *const ndarray.NDArray(F),
        ) !void {
            if (comptime MT == .tri3 or MT == .tri3opt) {
                self.mesh_workspace.hull_multiroot = null;
                return;
            }

            const visible_count = self.mesh_workspace.elems_in_image;
            var multi_count: usize = 0;
            for (self.mesh_workspace.root_classes) |root_class| {
                if (root_class == .multi_root) multi_count += 1;
            }
            if (multi_count == 0) {
                self.mesh_workspace.hull_multiroot = null;
                return;
            }
            if (multi_count >= std.math.maxInt(u32)) {
                return error.TooManyMultiRootElements;
            }

            const slot_mem = try outer_alloc.alloc(u32, visible_count);
            @memset(slot_mem, std.math.maxInt(u32));
            var next_slot: u32 = 0;
            for (self.mesh_workspace.root_classes, 0..) |root_class, pp| {
                if (root_class != .multi_root) continue;
                slot_mem[pp] = next_slot;
                next_slot += 1;
            }

            self.mesh_workspace.hull_multiroot = .{
                .indices = try matslice.MatSlice(u8).initAlloc(
                    outer_alloc,
                    multi_count,
                    3,
                ),
                .valid_depth = vecslice.VecSlice(u8).init(
                    try outer_alloc.alloc(u8, multi_count),
                ),
                .slot_by_visible_elem = vecslice.VecSlice(u32).init(slot_mem),
                .leaves_pre_calc = if (self.multiroot_edge_fun_mode == .pre_calc)
                    try outer_alloc.alloc(
                        HullMultiRoot.BezierLeafPreCalc,
                        multi_count * 4,
                    )
                else
                    &.{},
                .leaves_on_the_fly = if (self.multiroot_edge_fun_mode == .on_the_fly)
                    try outer_alloc.alloc(
                        HullMultiRoot.BezierLeafOnTheFly,
                        multi_count * 4,
                    )
                else
                    &.{},
            };

            var stage = PrepareMultiRootElemsStage{
                .camera = self.camera,
                .elem_coords = elem_coords,
                .hulls = &self.mesh_workspace.hull_multiroot.?,
                .multiroot_mode = self.multiroot_mode,
                .edge_fun_mode = self.multiroot_edge_fun_mode,
            };
            pce.runStaticRange(
                self.chunk_exec,
                &stage,
                runPrepareMultiRootElems,
                visible_count,
                self.vis_chunk_size,
            );
        }

        fn prepareHitGeometry(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
        ) !meshhit.MeshHitGeomPrepared {
            var selection = shaderSetHitSelection(
                self.mesh_static.shaders,
                self.camera.render_format,
                self.mesh_static.normal_type,
            );
            var hit_geometry = meshhit.MeshHitGeomPrepared{ .selection = selection };
            if (selection.contains(.coords_ref)) {
                hit_geometry.coords_ref = try self.gatherVisElemCoordsFromNodes(
                    outer_alloc,
                    &self.mesh_static.coords_orig,
                );
            }
            if (selection.contains(.coords_def)) {
                hit_geometry.coords_def = try self.gatherVisElemCoordsFromNodes(
                    outer_alloc,
                    &(self.mesh_workspace.coords_nodes_def_world orelse
                        return error.MissingWorldDeformedCoords),
                );
            }
            if (selection.contains(.surf_norm)) {
                hit_geometry.surf_norm = try self.prepVisNormals(
                    outer_alloc,
                    self.mesh_static.normal_type,
                );
            }
            return hit_geometry;
        }

        fn prepareShader(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            mesh_prep: *MeshPrepared,
        ) !void {
            const format = self.camera.render_format;
            const execution = switch (format) {
                .mono => self.mesh_static.shaders.mono,
                .rgb => self.mesh_static.shaders.rgb,
                .ir => self.mesh_static.shaders.ir,
                .multifield => self.mesh_static.shaders.multifield,
            } orelse return;
            const prepared: shaderops.ShaderExecutionPrepared = switch (execution) {
                .direct => |shader| .{ .direct = try self.prepareShaderDirect(
                    outer_alloc,
                    shader,
                    self.scaling_params,
                ) },
                .pipe => |pipe| .{ .pipe = try self.prepareShaderPipe(
                    outer_alloc,
                    pipe,
                    format.channels(),
                ) },
            };
            switch (format) {
                .mono => mesh_prep.shaders.mono = prepared,
                .rgb => mesh_prep.shaders.rgb = prepared,
                .ir => mesh_prep.shaders.ir = prepared,
                .multifield => mesh_prep.shaders.multifield = prepared,
            }
        }

        fn prepareShaderPipe(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            pipe: shaderops.ShaderPipeStatic,
            channels: u8,
        ) !shaderops.ShaderPipePrepared {
            const stages = try outer_alloc.alloc(
                shaderops.ShaderPipeStagePrepared,
                pipe.stages.len,
            );

            for (pipe.stages, 0..) |stage, si| {
                stages[si] = switch (stage) {
                    .source => |src| blk: {
                        var prepared_shader = try self.prepareShaderDirect(
                            outer_alloc,
                            src.shader,
                            if (src.shader == .nodal and src.global_scaling == null)
                                imageops.getScalingParamsNDArray(
                                    &src.shader.nodal.field.array,
                                    self.frame_idx,
                                    src.shader.nodal.scaling,
                                )
                            else
                                src.global_scaling,
                        );
                        switch (prepared_shader) {
                            .func, .func_rgb, .func_multi => |*shader| shader.hit_geometry = .{},
                            else => {},
                        }
                        break :blk .{ .source = .{
                            .shader = prepared_shader,
                            .destination = src.destination,
                        } };
                    },
                    .grey_to_emissivity => |m| .{ .grey_to_emissivity = m },
                    .clamp => |c| .{ .clamp = c },
                    .affine_map => |m| .{ .affine_map = m },
                    .lut_map => |m| .{ .lut_map = m },
                    .blend => |m| .{ .blend = m },
                    .normalise => |m| .{ .normalise = m },
                };
            }

            return .{
                .stages = stages,
                .resolver = pipe.resolver,
                .constants = pipe.constants,
                .channels = channels,
                .hit_geometry = self.hit_geometry,
            };
        }

        fn prepareShaderDirect(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            shader_static: shaderops.ShaderDirectStatic,
            scaling: ?imageops.ScalingParams,
        ) !shaderops.ShaderDirectPrepared {
            const previous_scaling = self.scaling_params;
            self.scaling_params = scaling;
            defer self.scaling_params = previous_scaling;
            switch (shader_static) {
                .nodal => |nodal_static| {
                    return try self.prepareNodalShader(
                        outer_alloc,
                        nodal_static,
                    );
                },
                .tex_multi_f => |tex_static| {
                    return try prepareTexShader(F, null, outer_alloc, self, tex_static);
                },
                .tex_u8 => |tex_static| {
                    return try prepareTexShader(
                        u8,
                        1,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .tex_u16 => |tex_static| {
                    return try prepareTexShader(
                        u16,
                        1,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .tex_f => |tex_static| {
                    return try prepareTexShader(
                        F,
                        1,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .tex_rgb_u8 => |tex_static| {
                    return try prepareTexShader(
                        u8,
                        3,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .tex_rgb_u16 => |tex_static| {
                    return try prepareTexShader(
                        u16,
                        3,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .tex_rgb_f => |tex_static| {
                    return try prepareTexShader(
                        F,
                        3,
                        outer_alloc,
                        self,
                        tex_static,
                    );
                },
                .func => |func_static| {
                    return try prepareFuncShader(
                        1,
                        outer_alloc,
                        self,
                        func_static,
                    );
                },
                .func_multi => |func_static| {
                    return try prepareFuncShader(
                        0,
                        outer_alloc,
                        self,
                        func_static,
                    );
                },
                .func_rgb => |func_static| {
                    return try prepareFuncShader(
                        3,
                        outer_alloc,
                        self,
                        func_static,
                    );
                },
            }
        }

        const GatherVisibleFieldStage = struct {
            connect: *const meshio.Connect,
            field: *const meshio.Field,
            frame_idx: usize,
            vis_orig_elem_inds: []const usize,
            elem_field: *ndarray.NDArray(F),
        };

        fn runGatherVisibleField(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleFieldStage = @ptrCast(@alignCast(ctx_ptr));
            const actual_frame_idx = @min(stage.frame_idx, stage.field.array.dims[0] - 1);
            const fields_num = stage.field.getFieldsN();
            const N = comptime MT.getNodesNum();

            for (range_start..range_end) |pp| {
                const orig_ee = stage.vis_orig_elem_inds[pp];
                const coord_inds = stage.connect.getElem(orig_ee);
                for (0..N) |nn| {
                    for (0..@as(usize, fields_num)) |ff| {
                        const field_val = stage.field.array.get(
                            &[_]usize{ actual_frame_idx, coord_inds[nn], ff },
                        );
                        stage.elem_field.set(&[_]usize{ pp, ff, nn }, field_val);
                    }
                }
            }
        }

        fn prepareNodalShader(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            nodal_static: shaderops.NodalStatic,
        ) !shaderops.ShaderDirectPrepared {
            const N = comptime MT.getNodesNum();
            var elem_field = try ndarray.NDArray(F).initFlat(
                outer_alloc,
                &[_]usize{
                    self.mesh_workspace.elems_in_image,
                    @as(usize, nodal_static.field.getFieldsN()),
                    N,
                },
            );

            var field_stage = GatherVisibleFieldStage{
                .connect = &self.mesh_static.connect,
                .field = &nodal_static.field,
                .frame_idx = self.frame_idx,
                .vis_orig_elem_inds = self.mesh_workspace.vis_orig_elem_inds,
                .elem_field = &elem_field,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &field_stage,
                runGatherVisibleField,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );

            const factors = if (self.scaling_params) |sp|
                imageops.getScaleFactors(nodal_static.scaling, null, sp)
            else
                imageops.ScaleFactors{ .mul = 1.0, .add = 0.0 };

            return .{ .nodal = .{
                .elem_field = elem_field,
                .output_gain = nodal_static.output_gain,
                .output_offset = nodal_static.output_offset,
                .scaling = nodal_static.scaling,
                .scale_over = nodal_static.scale_over,
                .scale_mul = factors.mul * nodal_static.output_gain,
                .scale_add = factors.add * nodal_static.output_gain + nodal_static.output_offset,
            } };
        }

        const GatherVisibleUVStage = struct {
            elem_uvs_full: ndarray.NDArray(F),
            vis_orig_elem_inds: []const usize,
            elem_uvs: *ndarray.NDArray(F),
        };

        fn runGatherVisibleUV(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *GatherVisibleUVStage = @ptrCast(@alignCast(ctx_ptr));
            const nodes_num = stage.elem_uvs_full.dims[2];

            for (range_start..range_end) |pp| {
                const orig_ee = stage.vis_orig_elem_inds[pp];
                const src_start = stage.elem_uvs_full.getFlatIdx(&[_]usize{ orig_ee, 0, 0 });
                const dst_start = stage.elem_uvs.getFlatIdx(&[_]usize{ pp, 0, 0 });
                @memcpy(
                    stage.elem_uvs.slice[dst_start .. dst_start + 2 * nodes_num],
                    stage.elem_uvs_full.slice[src_start .. src_start + 2 * nodes_num],
                );
            }
        }

        fn prepareTexShader(
            comptime T: type,
            comptime C: ?usize,
            outer_alloc: std.mem.Allocator,
            self: *FrameMeshPipelineType,
            tex_static: if (C) |channels| shaderops.TexStatic(T, channels) else shaderops.TexMultiStatic(T),
        ) !shaderops.ShaderDirectPrepared {
            const params = imageops.getScalingParamsTex(
                T,
                C,
                &tex_static.tex,
                tex_static.scaling,
            );
            const factors = imageops.getScaleFactors(
                tex_static.scaling,
                null,
                params,
            );

            var elem_uvs = try ndarray.NDArray(F).initFlat(
                outer_alloc,
                &[_]usize{
                    self.mesh_workspace.elems_in_image,
                    2,
                    tex_static.elem_uvs.dims[2],
                },
            );

            var uv_stage = GatherVisibleUVStage{
                .elem_uvs_full = tex_static.elem_uvs,
                .vis_orig_elem_inds = self.mesh_workspace.vis_orig_elem_inds,
                .elem_uvs = &elem_uvs,
            };

            pce.runStaticRange(
                self.chunk_exec,
                &uv_stage,
                runGatherVisibleUV,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );

            if (comptime C == null) {
                const prepared: shaderops.TexMultiPrepared(T) = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                };
                return .{ .tex_multi_f = prepared };
            } else if (comptime T == u8 and C == 1) {
                return .{ .tex_u8 = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            } else if (comptime T == u16 and C == 1) {
                return .{ .tex_u16 = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            } else if (comptime T == F and C == 1) {
                return .{ .tex_f = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            } else if (comptime T == u8 and C == 3) {
                return .{ .tex_rgb_u8 = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            } else if (comptime T == u16 and C == 3) {
                return .{ .tex_rgb_u16 = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            } else {
                return .{ .tex_rgb_f = .{
                    .elem_uvs = elem_uvs,
                    .tex = tex_static.tex,
                    .samp_cfg = tex_static.samp_cfg,
                    .output_gain = tex_static.output_gain,
                    .output_offset = tex_static.output_offset,
                    .scaling = tex_static.scaling,
                    .scale_mul = factors.mul * tex_static.output_gain,
                    .scale_add = factors.add * tex_static.output_gain + tex_static.output_offset,
                } };
            }
        }

        fn prepareFuncShader(
            comptime C: usize,
            outer_alloc: std.mem.Allocator,
            self: *FrameMeshPipelineType,
            func_static: shaderops.FuncStatic,
        ) !shaderops.ShaderDirectPrepared {
            const factors = imageops.getScaleFactors(
                func_static.scaling,
                null,
                .{ .min = 0.0, .range = 1.0 },
            );

            const elem_uvs = if (func_static.coord_mode == .uv) blk: {
                const elem_uvs_full = func_static.elem_uvs orelse
                    return error.MissingUVsForFuncShader;
                var elem_uvs = try ndarray.NDArray(F).initFlat(
                    outer_alloc,
                    &[_]usize{
                        self.mesh_workspace.elems_in_image,
                        2,
                        elem_uvs_full.dims[2],
                    },
                );

                var uv_stage = GatherVisibleUVStage{
                    .elem_uvs_full = elem_uvs_full,
                    .vis_orig_elem_inds = self.mesh_workspace.vis_orig_elem_inds,
                    .elem_uvs = &elem_uvs,
                };

                pce.runStaticRange(
                    self.chunk_exec,
                    &uv_stage,
                    runGatherVisibleUV,
                    self.mesh_workspace.elems_in_image,
                    self.vis_chunk_size,
                );
                break :blk elem_uvs;
            } else null;

            if (comptime C == 0) {
                const channels = try outer_alloc.alloc(
                    shaderops.FuncChannelPrepared,
                    func_static.channels.len,
                );
                var needs_normal = false;
                for (func_static.channels, channels) |channel, *prepared| {
                    const channel_factors = imageops.getScaleFactors(
                        channel.scaling,
                        null,
                        .{ .min = 0.0, .range = 1.0 },
                    );
                    prepared.* = .{
                        .builtin = channel.builtin,
                        .params = shaderops.normFuncShaderParams(channel.builtin, channel.params),
                        .scale_mul = channel_factors.mul * channel.output_gain,
                        .scale_add = channel_factors.add * channel.output_gain + channel.output_offset,
                    };
                    needs_normal = needs_normal or channel.builtin == .lambertian_normal_z;
                }
                return .{ .func_multi = .{
                    .elem_uvs = elem_uvs,
                    .hit_geometry = self.hit_geometry,
                    .coord_mode = func_static.coord_mode,
                    .channels = channels,
                    .needs_normal = needs_normal and self.mesh_static.normal_type != .none,
                } };
            } else if (comptime C == 1) {
                return .{ .func = .{
                    .elem_uvs = elem_uvs,
                    .hit_geometry = self.hit_geometry,
                    .coord_mode = func_static.coord_mode,
                    .builtin = func_static.builtin,
                    .params = shaderops.normFuncShaderParams(
                        func_static.builtin,
                        func_static.params,
                    ),
                    .output_gain = func_static.output_gain,
                    .output_offset = func_static.output_offset,
                    .scaling = func_static.scaling,
                    .scale_mul = factors.mul * func_static.output_gain,
                    .scale_add = factors.add * func_static.output_gain + func_static.output_offset,
                    .needs_normal = func_static.builtin == .lambertian_normal_z and
                        self.mesh_static.normal_type != .none,
                } };
            } else {
                return .{ .func_rgb = .{
                    .elem_uvs = elem_uvs,
                    .hit_geometry = self.hit_geometry,
                    .coord_mode = func_static.coord_mode,
                    .builtin = func_static.builtin,
                    .params = shaderops.normFuncShaderParams(
                        func_static.builtin,
                        func_static.params,
                    ),
                    .output_gain = func_static.output_gain,
                    .output_offset = func_static.output_offset,
                    .scaling = func_static.scaling,
                    .scale_mul = factors.mul * func_static.output_gain,
                    .scale_add = factors.add * func_static.output_gain + func_static.output_offset,
                    .needs_normal = func_static.builtin == .lambertian_normal_z and
                        self.mesh_static.normal_type != .none,
                } };
            }
        }

        fn prepVisNormals(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            normal_type: normals.NormalType,
        ) !?ndarray.MappedNDArray(F) {
            if (normal_type == .none) {
                return null;
            }

            return try normals.prepVisNormalsThreaded(
                MT,
                outer_alloc,
                &self.mesh_workspace.coords_nodes,
                &self.mesh_static.connect,
                self.mesh_workspace.vis_orig_elem_inds,
                normal_type,
                self.chunk_exec,
                self.elem_chunk_size,
                self.vis_chunk_size,
            );
        }

        fn remapVisElemInds(self: *FrameMeshPipelineType) void {
            for (self.mesh_workspace.elem_bboxes, 0..) |*elem_bbox, pp| {
                elem_bbox.elem_idx = pp;
            }
        }
    };
}
