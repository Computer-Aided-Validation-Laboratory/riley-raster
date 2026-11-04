// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const report = @import("report.zig");
const hullmultiroot = @import("hullmultiroot.zig");
const shaderfunc = @import("shaderfunc.zig");
const fieldtypes = @import("fieldtypes.zig");
const std = @import("std");
const shaderpipe = @import("shaderpipe.zig");

const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;

const ndarray = @import("ndarray.zig");
const matslice = @import("matslice.zig");
const vecslice = @import("vecslice.zig");
const shapefun = @import("shapefun.zig");

const meshio = @import("meshio.zig");
const meshtypes = @import("meshtypes.zig");
const uvio = @import("uvio.zig");
const imageio = @import("imageio.zig");

const rasterconfig = @import("rasterconfig.zig");
const cameratypes = @import("cameratypes.zig");
const shadertypes = @import("shadertypes.zig");
const texturetypes = @import("texturetypes.zig");

const imageops = @import("imageops.zig");
const cameraprojops = @import("cameraprojops.zig");
const parachunkexec = @import("parachunkexec.zig");
const scalingpolicy = @import("scalingpolicy.zig");
const rasterfrontend = @import("rasterfrontend.zig");
const sceneops = @import("sceneops.zig");
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const normals = @import("normals.zig");
const geometrykernels = @import("geometrykernels.zig");
const distortbounds = @import("distortbounds.zig");

// --------------------------------------------------------------------------------------
// Public Entry-Point Func
// --------------------------------------------------------------------------------------

pub fn countFrames(
    meshes: []const meshtypes.MeshInput,
    cameras: []const cameratypes.CameraInput,
) usize {
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
                shadertypes.ShaderMonoInput,
                shadertypes.ShaderPipeInput,
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

pub fn countOutputFields(
    meshes: []const meshtypes.MeshInput,
    cameras: []const cameratypes.CameraInput,
) u8 {
    var num_fields: u8 = 0;
    for (meshes) |mesh| {
        for (cameras) |camera| {
            const selected_shader = shaderops.selectShader(
                shadertypes.ShaderMonoInput,
                shadertypes.ShaderPipeInput,
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

pub fn countStaticMeshElems(mesh_static: []const meshtypes.MeshStatic) usize {
    var total: usize = 0;
    for (mesh_static) |mesh| {
        total += mesh.connect.table.rows_num;
    }
    return total;
}

pub fn countMeshInputElems(meshes: []const meshtypes.MeshInput) usize {
    var total: usize = 0;
    for (meshes) |mesh| {
        total += mesh.connect.table.rows_num;
    }
    return total;
}

pub fn countStaticMeshNodes(mesh_static: []const meshtypes.MeshStatic) usize {
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
    mesh_types: []const geometrykernels.MeshType,
    shader_mode: enum { nodal, tex },
    uv_paths: ?[]const []const u8,
    tex_path: ?[]const u8,
    uv_file: ?[]const u8,
) ![]meshtypes.MeshInput {
    var mesh_inputs = try outer_alloc.alloc(meshtypes.MeshInput, sim_datas.len);
    var initialized_count: usize = 0;
    errdefer {
        for (0..initialized_count) |ii| {
            switch (mesh_inputs[ii].shaders.mono_direct.?) {
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
                else => {},
            }
        }
        outer_alloc.free(mesh_inputs);
    }

    const uv_file_name = uv_file orelse "uvs.csv";

    for (sim_datas, 0..) |sim_data, ii| {
        mesh_inputs[ii] = meshtypes.MeshInput{
            .mesh_type = mesh_types[ii],
            .coords = sim_data.coords,
            .connect = sim_data.connect,
            .disp = sim_data.disp,
            .shaders = .{},
        };

        if (shader_mode == .nodal) {
            if (sim_data.field) |field| {
                mesh_inputs[ii].shaders.mono_direct = .{ .nodal = .{
                    .field = field,
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

            mesh_inputs[ii].shaders.mono_direct = .{ .tex_u8 = .{
                .uvs = uvmap.array,
                .tex = tex,
                .samp_cfg = .{ .sample = .cubic_catmull_rom, .mode = .direct },
            } };
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
    mesh_input: *const meshtypes.MeshInput,
    active_roles: [4]bool,
) !meshtypes.MeshStatic {
    const coords_orig = try sceneops.duplicateCoords(
        allocator,
        mesh_input.coords,
    );

    var shaders: shadertypes.MeshShaderSetStatic = .{};
    if (active_roles[0]) {
        if (mesh_input.shaders.mono_direct) |shader|
            shaders.mono = .{ .direct = try createShaderMonoStatic(allocator, shader, &mesh_input.connect) };
        if (mesh_input.shaders.mono_pipe) |pipe|
            shaders.mono = .{ .pipe = try createShaderPipeStatic(allocator, pipe, &mesh_input.connect) };
    }
    if (active_roles[1]) {
        if (mesh_input.shaders.rgb_pipe) |pipe|
            shaders.rgb = try createShaderPipeStatic(
                allocator,
                pipe,
                &mesh_input.connect,
            );
    }
    if (active_roles[2]) {
        if (mesh_input.shaders.ir_direct) |shader|
            shaders.ir = .{ .direct = try createShaderMonoStatic(allocator, shader, &mesh_input.connect) };
        if (mesh_input.shaders.ir_pipe) |pipe|
            shaders.ir = .{ .pipe = try createShaderPipeStatic(allocator, pipe, &mesh_input.connect) };
    }
    if (active_roles[3]) {
        if (mesh_input.shaders.multifield_pipe) |pipe|
            shaders.multifield = try createShaderPipeStatic(
                allocator,
                pipe,
                &mesh_input.connect,
            );
    }
    const roles = [_]shadertypes.RenderFormat{ .mono, .rgb, .ir, .{ .multifield = 1 } };
    var hit_selections: [4]meshhit.MeshHitSelection = undefined;
    var needs_normals = false;
    for (roles, 0..) |role, ii| {
        hit_selections[ii] = shaderSetHitSelection(shaders, role, mesh_input.normal_type);
        needs_normals = needs_normals or hit_selections[ii].contains(.surf_norm);
    }

    return .{
        .referenced_nodes_num = if (needs_normals and mesh_input.normal_type == .avg) normals.getConnectNodesNum(&mesh_input.connect) else 0,
        .hit_selections = hit_selections,
        .mesh_type = mesh_input.mesh_type,
        .normal_type = mesh_input.normal_type,
        .coords_orig = coords_orig,
        .connect = mesh_input.connect,
        .disp = mesh_input.disp,
        .shaders = shaders,
    };
}

fn createShaderPipeStatic(
    allocator: std.mem.Allocator,
    pipe: shadertypes.ShaderPipeInput,
    connect: *const meshtypes.Connect,
) !shadertypes.ShaderPipeStatic {
    const stages = try allocator.alloc(
        shadertypes.ShaderPipeStageStatic,
        pipe.stages.len,
    );

    for (pipe.stages, 0..) |stage, si| {
        stages[si] = switch (stage) {
            .source => |src| .{ .source = .{
                .shader = try createPipeSourceStatic(allocator, src.shader, connect),
                .destination = src.destination,
                .channels = switch (src.shader) {
                    .nodal => |n| @intCast(n.field.getFieldsN()),
                    .tex_rgb_u8, .tex_rgb_u16, .tex_rgb_f, .func_rgb => 3,
                    .tex_multi_u8 => |t| @intCast(t.tex.array.dims[0]),
                    .tex_multi_u16 => |t| @intCast(t.tex.array.dims[0]),
                    .tex_multi_f => |t| @intCast(t.tex.array.dims[0]),
                    .func_multi => |f| @intCast(f.channels.len),
                    else => 1,
                },
            } },
            .grey_to_emissivity => |m| .{ .grey_to_emissivity = shadertypes.GreyToEmissivityPrepared.init(m) },
            .clamp => |c| .{ .clamp = c },
            .affine_map => |m| .{ .affine_map = m },
            .lut_map => |m| .{ .lut_map = shadertypes.LUTMapPrepared.init(m) },
            .blend => |m| .{ .blend = shadertypes.BlendPrepared.init(m) },
            .normalise => |m| .{ .normalise = m },
        };
    }

    return .{
        .stages = stages,
        .resolver = shaderpipe.PreparedResolver.init(pipe.resolver),
        .constants = pipe.constants,
    };
}

fn createNodalStatic(input: shadertypes.NodalInput) shadertypes.NodalStatic {
    const bounds: imageops.ScalingParams = if (input.scale_over == .over_frames or input.scaling == .fixed)
        imageops.getScalingParamsNDArray(&input.field.array, null, input.scaling)
    else
        .{ .min = 0, .range = 1 };
    const factors = imageops.getScaleFactors(input.scaling, null, bounds);
    return .{
        .field = input.field,
        .output_gain = input.output_gain,
        .output_offset = input.output_offset,
        .scaling = input.scaling,
        .scale_over = input.scale_over,
        .scale_mul = factors.mul * input.output_gain,
        .scale_add = factors.add * input.output_gain + input.output_offset,
    };
}

fn createTextureStatic(
    comptime T: type,
    comptime C: usize,
    allocator: std.mem.Allocator,
    input: shadertypes.TexInput(texturetypes.TexDataFix(T, C)),
    connect: *const meshtypes.Connect,
) !shadertypes.TexStatic(T, C) {
    const factors = imageops.getScaleFactors(input.scaling, null, imageops.getScalingParamsTex(T, C, &input.tex, input.scaling));
    return .{
        .elem_uvs = try prepUVs(allocator, &input.uvs, connect),
        .tex = input.tex,
        .samp_cfg = input.samp_cfg,
        .output_gain = input.output_gain,
        .output_offset = input.output_offset,
        .scaling = input.scaling,
        .scale_mul = factors.mul * input.output_gain,
        .scale_add = factors.add * input.output_gain + input.output_offset,
    };
}

fn createShaderMonoStatic(
    allocator: std.mem.Allocator,
    input: shadertypes.ShaderMonoInput,
    connect: *const meshtypes.Connect,
) !shadertypes.ShaderMonoStatic {
    return switch (input) {
        .nodal => |n| .{ .nodal = createNodalStatic(n) },
        .tex_u8 => |t| .{ .tex_u8 = try createTextureStatic(u8, 1, allocator, t, connect) },
        .tex_u16 => |t| .{ .tex_u16 = try createTextureStatic(u16, 1, allocator, t, connect) },
        .tex_f => |t| .{ .tex_f = try createTextureStatic(F, 1, allocator, t, connect) },
        .func => |f| .{ .func = try funcStaticFromInput(allocator, f, connect) },
    };
}

fn funcStaticFromInput(
    allocator: std.mem.Allocator,
    input: shadertypes.FuncInput,
    connect: *const meshtypes.Connect,
) !shadertypes.FuncStatic {
    const factors = imageops.getScaleFactors(input.scaling, null, .{ .min = 0, .range = 1 });
    return .{
        .elem_uvs = if (input.coord_mode == .uv)
            try prepUVs(allocator, &(input.uvs orelse return error.MissingUVsForFuncShader), connect)
        else
            null,
        .scale_mul = factors.mul * input.output_gain,
        .scale_add = factors.add * input.output_gain + input.output_offset,
        .needs_normal = input.builtin == .lambertian_normal_z,
        .coord_mode = input.coord_mode,
        .builtin = input.builtin,
        .params = shaderfunc.normFuncShaderParams(
            input.builtin,
            input.params,
        ),
        .output_gain = input.output_gain,
        .output_offset = input.output_offset,
        .scaling = input.scaling,
    };
}

fn funcMultiStaticFromInput(
    allocator: std.mem.Allocator,
    input: shadertypes.FuncMultiInput,
    connect: *const meshtypes.Connect,
) !shadertypes.FuncStatic {
    const channels = try allocator.alloc(shadertypes.FuncChannelPrepared, input.channels.len);
    var needs_normal = false;
    for (input.channels, channels) |ch, *out| {
        const factors = imageops.getScaleFactors(ch.scaling, null, .{ .min = 0, .range = 1 });
        out.* = .{
            .builtin = ch.builtin,
            .params = shaderfunc.normFuncShaderParams(ch.builtin, ch.params),
            .scale_mul = factors.mul * ch.output_gain,
            .scale_add = factors.add * ch.output_gain + ch.output_offset,
        };
        needs_normal = needs_normal or ch.builtin == .lambertian_normal_z;
    }
    return .{ .elem_uvs = if (input.coord_mode == .uv)
        try prepUVs(allocator, &(input.uvs orelse return error.MissingUVsForFuncShader), connect)
    else
        null, .coord_mode = input.coord_mode, .channels = channels, .needs_normal = needs_normal };
}

fn createPipeSourceStatic(
    allocator: std.mem.Allocator,
    input: shadertypes.PipeSourceInput,
    connect: *const meshtypes.Connect,
) !shadertypes.PipeSourceStatic {
    return switch (input) {
        .nodal => |n| .{ .nodal = createNodalStatic(n) },
        .tex_u8 => |t| .{ .tex_u8 = try createTextureStatic(u8, 1, allocator, t, connect) },
        .tex_u16 => |t| .{ .tex_u16 = try createTextureStatic(u16, 1, allocator, t, connect) },
        .tex_f => |t| .{ .tex_f = try createTextureStatic(F, 1, allocator, t, connect) },
        .tex_rgb_u8 => |t| .{ .tex_rgb_u8 = try createTextureStatic(u8, 3, allocator, t, connect) },
        .tex_rgb_u16 => |t| .{ .tex_rgb_u16 = try createTextureStatic(u16, 3, allocator, t, connect) },
        .tex_rgb_f => |t| .{ .tex_rgb_f = try createTextureStatic(F, 3, allocator, t, connect) },
        .tex_multi_u8 => |t| .{ .tex_multi_f = try createTextureMultiStatic(u8, allocator, t, connect) },
        .tex_multi_u16 => |t| .{ .tex_multi_f = try createTextureMultiStatic(u16, allocator, t, connect) },
        .tex_multi_f => |t| .{ .tex_multi_f = try createTextureMultiStatic(F, allocator, t, connect) },
        .func => |f| .{ .func = try funcStaticFromInput(allocator, f, connect) },
        .func_rgb => |f| .{ .func_rgb = try funcStaticFromInput(allocator, f, connect) },
        .func_multi => |f| .{ .func_multi = try funcMultiStaticFromInput(allocator, f, connect) },
    };
}

fn createTextureMultiStatic(
    comptime T: type,
    allocator: std.mem.Allocator,
    input: shadertypes.TexInput(texturetypes.TexDataDyn(T)),
    connect: *const meshtypes.Connect,
) !shadertypes.TexMultiStatic(F) {
    const elem_uvs = try prepUVs(allocator, &input.uvs, connect);
    const float_tex: texturetypes.TexDataDyn(F) = if (comptime T == F) input.tex else blk: {
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
    const factors = imageops.getScaleFactors(input.scaling, null, imageops.getScalingParamsTex(F, null, &float_tex, input.scaling));
    return .{
        .elem_uvs = elem_uvs,
        .tex = float_tex,
        .samp_cfg = input.samp_cfg,
        .output_gain = input.output_gain,
        .output_offset = input.output_offset,
        .scaling = input.scaling,
        .scale_mul = factors.mul * input.output_gain,
        .scale_add = factors.add * input.output_gain + input.output_offset,
    };
}

// -----------------------------------------------------------------------------------------
// Mesh Pipeline: Main entry point into the mesh frame pipeline
// -----------------------------------------------------------------------------------------

pub fn prepMeshFrames(
    arena_alloc: std.mem.Allocator,
    chunk_exec: *parachunkexec.ParaChunkExecutor,
    workers_num: usize,
    camera: *const cameraprojops.CameraPrepared,
    config: rasterconfig.RasterConfig,
    frame_idx: usize,
    static_meshes: []const meshtypes.MeshStatic,
    frame_meshes: []meshtypes.MeshFrame,
    timing: *report.GeomTimes,
) !meshtypes.FrameGeomResult {
    var res = meshtypes.FrameGeomResult{
        .total_elems_num = 0,
        .total_elems_in_image = 0,
    };

    for (static_meshes, 0..) |*mesh_static, ii| {
        // Only needed for nodal interpolation shading and only if not .none. If .none we
        // directly render float fields unscaled.
        var nodal_frame_scaling: ?imageops.ScalingParams = null;
        const selected = shaderops.selectShader(
            shadertypes.ShaderMonoStatic,
            shadertypes.ShaderPipeStatic,
            &mesh_static.shaders,
            camera.render_format,
        );
        if (selected) |execution| switch (execution) {
            .direct => |shader| switch (shader.*) {
                .nodal => |s| {
                    if (s.scale_over == .within_frames and
                        (s.scaling == .auto or s.scaling == .frac))
                    {
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
    chunk_exec: *parachunkexec.ParaChunkExecutor,
    workers_num: usize,
    camera: *const cameraprojops.CameraPrepared,
    config: rasterconfig.RasterConfig,
    mesh_static: *const meshtypes.MeshStatic,
    frame_idx: usize,
    scaling_params: ?imageops.ScalingParams,
    timing: *report.GeomTimes,
) !meshtypes.MeshFrame {
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

// Outside of pipeline because these are static - we gather these into an NDarray once
// for all frames and cameras
fn prepUVs(
    outer_alloc: std.mem.Allocator,
    uvs: *const ndarray.NDArray(F),
    connect: *const meshtypes.Connect,
) !ndarray.NDArray(F) {
    const elems_num = connect.getElemsNum();
    const nodes_per_elem = connect.getNodesPerElem();
    var elem_uv_arr = try ndarray.NDArray(F).initFlat(
        outer_alloc,
        &[_]usize{ elems_num, 2, nodes_per_elem },
    );

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
    mesh_static: *const meshtypes.MeshStatic,
    selection: shadertypes.RenderFormat,
) !meshtypes.MeshFrameWorkspace {
    return .{
        .coords_nodes = try meshtypes.Coords.initAlloc(
            allocator,
            mesh_static.coords_orig.mat.rows_num,
        ),
        .coords_nodes_def_world = if (mesh_static.hit_selections[renderRoleIndex(selection)].contains(.coords_def))
            try meshtypes.Coords.initAlloc(
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

fn renderRoleIndex(role: shadertypes.RenderFormat) usize {
    return switch (role) {
        .mono => 0,
        .rgb => 1,
        .ir => 2,
        .multifield => 3,
    };
}

fn shaderMonoHitSelection(
    shader: shadertypes.ShaderMonoStatic,
    normal_type: normals.NormalType,
) meshhit.MeshHitSelection {
    var selection = meshhit.MeshHitSelection.initEmpty();
    switch (shader) {
        .func => |s| {
            switch (s.coord_mode) {
                .world_reference => selection.insert(.coords_ref),
                .world_deformed => selection.insert(.coords_def),
                else => {},
            }
            if (s.needs_normal and normal_type != .none) {
                selection.insert(.surf_norm);
            }
        },
        else => {},
    }
    return selection;
}

fn pipeSourceHitSelection(
    source: shadertypes.PipeSourceStatic,
    normal_type: normals.NormalType,
) meshhit.MeshHitSelection {
    var selection = meshhit.MeshHitSelection.initEmpty();
    switch (source) {
        .func, .func_rgb, .func_multi => |s| {
            switch (s.coord_mode) {
                .world_reference => selection.insert(.coords_ref),
                .world_deformed => selection.insert(.coords_def),
                else => {},
            }
            if (s.needs_normal and normal_type != .none) {
                selection.insert(.surf_norm);
            }
        },
        else => {},
    }
    return selection;
}

fn shaderSetHitSelection(
    shaders: shadertypes.MeshShaderSetStatic,
    role: shadertypes.RenderFormat,
    normal_type: normals.NormalType,
) meshhit.MeshHitSelection {
    var selection = meshhit.MeshHitSelection.initEmpty();
    const selected = shaderops.selectShader(
        shadertypes.ShaderMonoStatic,
        shadertypes.ShaderPipeStatic,
        &shaders,
        role,
    ) orelse return selection;
    switch (selected) {
        .direct => |shader| return shaderMonoHitSelection(shader.*, normal_type),
        .pipe => |pipe| {
            for (pipe.stages) |stage| switch (stage) {
                .source => |src| selection.setUnion(
                    pipeSourceHitSelection(src.shader, normal_type),
                ),
                else => {},
            };
        },
    }
    return selection;
}

//------------------------------------------------------------------------------------------
// Geometry Pipeline Stages: meshio.Coords, Transform, Culling and Gathering
//------------------------------------------------------------------------------------------

fn prefixVisCounts(mesh_workspace: *meshtypes.MeshFrameWorkspace) void {
    var running_total: usize = 0;
    for (mesh_workspace.vis_counts_by_chunk, 0..) |vis_count, cc| {
        mesh_workspace.vis_offsets_by_chunk[cc] = running_total;
        running_total += vis_count;
    }
    mesh_workspace.elems_in_image = running_total;
}

//------------------------------------------------------------------------------------------
// Frame Mesh Pipeline: Implementation of the frame-by-frame geometry pipeline
//------------------------------------------------------------------------------------------

fn FrameMeshPipeline(comptime MT: geometrykernels.MeshType) type {
    return struct {
        const FrameMeshPipelineType = @This();

        camera: *const cameraprojops.CameraPrepared,
        mesh_static: *const meshtypes.MeshStatic,
        frame_idx: usize,
        hull_mode: rasterconfig.HullMode,
        multiroot_mode: rasterconfig.MultirootSolverMode,
        multiroot_edge_fun_mode: rasterconfig.EdgeFunMode,
        edge_spacing_px: F,
        scaling_params: ?imageops.ScalingParams,
        chunk_exec: *parachunkexec.ParaChunkExecutor,
        workers_num: usize,
        nodes_num: usize,
        elems_num: usize,
        node_chunk_size: usize,
        elem_chunk_size: usize,
        elem_chunks_num: usize,
        vis_chunk_size: usize,
        mesh_workspace: meshtypes.MeshFrameWorkspace,
        hit_geometry: meshhit.MeshHitGeomPrepared = .{},

        fn init(
            outer_alloc: std.mem.Allocator,
            camera: *const cameraprojops.CameraPrepared,
            mesh_static: *const meshtypes.MeshStatic,
            frame_idx: usize,
            hull_mode: rasterconfig.HullMode,
            multiroot_mode: rasterconfig.MultirootSolverMode,
            multiroot_edge_fun_mode: rasterconfig.EdgeFunMode,
            edge_spacing_px: F,
            scaling_params: ?imageops.ScalingParams,
            chunk_exec: *parachunkexec.ParaChunkExecutor,
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
                .elem_chunks_num = parachunkexec.getStaticPartitionsNum(
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
            timing: *report.GeomTimes,
        ) !meshtypes.MeshFrame {
            const time_start_coords = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            self.displaceCoords();
            self.transformCoords();
            const time_end_coords = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            timing.coord_ops += @intCast(time_start_coords.durationTo(
                time_end_coords,
            ).raw.nanoseconds);

            const time_start_cull = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            try self.cullAndClassifyVisibleElems(outer_alloc);
            var mesh_prep = try self.gatherVisCoords(outer_alloc);
            const time_end_cull = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            timing.cull_ops += @intCast(time_start_cull.durationTo(
                time_end_cull,
            ).raw.nanoseconds);

            const time_start_prep = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            try self.prepareAdaptiveHulls(outer_alloc, &mesh_prep.coords);
            try self.prepareMultiRootElems(outer_alloc, &mesh_prep.coords);
            self.hit_geometry = try self.prepareHitGeometry(outer_alloc);
            mesh_prep.hit_geometry = self.hit_geometry;
            try self.prepareShader(outer_alloc, &mesh_prep);
            const time_end_prep = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            timing.prep_hulls_shaders += @intCast(time_start_prep.durationTo(
                time_end_prep,
            ).raw.nanoseconds);

            const time_start_remap = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
            self.remapVisElemInds();
            const time_end_remap = std.Io.Clock.Timestamp.now(self.chunk_exec.io, .awake);
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
            frame_workspace: *meshtypes.MeshFrameWorkspace,
            mesh_static: *const meshtypes.MeshStatic,
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
            parachunkexec.runStaticRange(
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
            camera: *const cameraprojops.CameraPrepared,
            frame_workspace: *meshtypes.MeshFrameWorkspace,
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
                rasterfrontend.nodesToRasterRangeInPlace(
                    stage.camera,
                    &stage.frame_workspace.coords_nodes,
                    range_start,
                    range_end,
                );
            } else {
                rasterfrontend.nodesToClipPxLengRangeInPlace(
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

            parachunkexec.runStaticRange(
                self.chunk_exec,
                &transform_stage,
                runTransformCoords,
                self.nodes_num,
                self.node_chunk_size,
            );
        }

        const CullVisibleCountStage = struct {
            camera: *const cameraprojops.CameraPrepared,
            edge_spacing_px: F,
            connect: *const meshtypes.Connect,
            coords_nodes: *const meshtypes.Coords,
            vis_counts_by_chunk: []usize,
            cached_distort_bboxes: ?[]?rasterfrontend.DistortElemBBox,
            cached_bboxes: ?[]?rasterfrontend.ElemBBox,
            cached_root_classes: []?rasterfrontend.ElemRootClass,
            hull_mode: rasterconfig.HullMode,
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
                const bbox: ?rasterfrontend.ElemBBox =
                    if (stage.camera.ideal_sensor_bounds) |ideal_sensor| blk: {
                        const distorted = rasterfrontend.calcVisibleDistortBBox(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.hull_mode,
                            stage.camera.prep_psf.halo_px,
                            ideal_sensor,
                            stage.edge_spacing_px,
                            if (comptime MT == .tri3 or MT == .tri3opt) null else &stage.cached_root_classes[ee],
                        );
                        if (stage.cached_distort_bboxes) |cached| cached[ee] = distorted;
                        break :blk if (distorted) |value| value.box_ints else null;
                    } else if (MT == .tri3 or MT == .tri3opt)
                        rasterfrontend.calcVisibleNodeBBoxTri3WithHalo(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.camera.prep_psf.halo_px,
                        )
                    else
                        rasterfrontend.calcVisibleNodeBBoxHighOrdWithHalo(
                            MT,
                            stage.camera,
                            stage.coords_nodes,
                            stage.connect,
                            ee,
                            stage.hull_mode,
                            stage.camera.prep_psf.halo_px,
                            &stage.cached_root_classes[ee],
                        );

                if (bbox != null) {
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

            var cached_distort_bboxes: ?[]?rasterfrontend.DistortElemBBox = null;
            if (has_distort) {
                cached_distort_bboxes = try outer_alloc.alloc(
                    ?rasterfrontend.DistortElemBBox,
                    self.elems_num,
                );
            }
            defer if (cached_distort_bboxes) |bboxes| outer_alloc.free(bboxes);
            const cached_bboxes = if (has_distort)
                null
            else
                try outer_alloc.alloc(?rasterfrontend.ElemBBox, self.elems_num);
            defer if (cached_bboxes) |bboxes| outer_alloc.free(bboxes);
            const cached_root_classes = if (MT == .tri3 or MT == .tri3opt)
                &.{}
            else
                try outer_alloc.alloc(?rasterfrontend.ElemRootClass, self.elems_num);
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

            parachunkexec.runStaticRange(
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
                rasterfrontend.ElemBBox,
                self.mesh_workspace.elems_in_image,
            );
            self.mesh_workspace.root_classes = if (MT == .tri3 or MT == .tri3opt)
                &.{}
            else
                try outer_alloc.alloc(
                    rasterfrontend.ElemRootClass,
                    self.mesh_workspace.elems_in_image,
                );
            self.mesh_workspace.elem_float_bboxes = if (has_distort)
                try outer_alloc.alloc(
                    distortbounds.DistortBounds,
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
            parachunkexec.runStaticRange(
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
            camera: *const cameraprojops.CameraPrepared,
            connect: *const meshtypes.Connect,
            coords_nodes: *const meshtypes.Coords,
            hull_mode: rasterconfig.HullMode,
            cached_distort_bboxes: ?[]const ?rasterfrontend.DistortElemBBox,
            cached_bboxes: ?[]const ?rasterfrontend.ElemBBox,
            cached_root_classes: []const ?rasterfrontend.ElemRootClass,
            vis_orig_elem_inds: []usize,
            elem_bboxes: []rasterfrontend.ElemBBox,
            root_classes: []rasterfrontend.ElemRootClass,
            elem_float_bboxes: ?[]distortbounds.DistortBounds,
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
            connect: *const meshtypes.Connect,
            coords_nodes: *const meshtypes.Coords,
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
            coords_nodes: *const meshtypes.Coords,
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

            parachunkexec.runStaticRange(
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
        ) !meshtypes.MeshPrepared {
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
            camera: *const cameraprojops.CameraPrepared,
            elem_coords: *const ndarray.NDArray(F),
            hull_adaptive: *ndarray.NDArray(F),
            root_classes: []const rasterfrontend.ElemRootClass,
            hull_mode: rasterconfig.HullMode,
        };

        fn runPrepareAdaptiveHulls(
            ctx_ptr: *anyopaque,
            chunk_idx: usize,
            range_start: usize,
            range_end: usize,
        ) void {
            _ = chunk_idx;
            const stage: *PrepareAdaptiveHullsStage = @ptrCast(@alignCast(ctx_ptr));
            rasterfrontend.prepareVisibleAdaptiveHullsRange(
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
            parachunkexec.runStaticRange(
                self.chunk_exec,
                &hulls_stage,
                runPrepareAdaptiveHulls,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );
        }

        const PrepareMultiRootElemsStage = struct {
            camera: *const cameraprojops.CameraPrepared,
            elem_coords: *const ndarray.NDArray(F),
            hulls: *meshtypes.MultiRootHulls,
            multiroot_mode: rasterconfig.MultirootSolverMode,
            edge_fun_mode: rasterconfig.EdgeFunMode,
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
            const Seed = struct { z: F, index: u8, front: bool = false };

            for (range_start..range_end) |pp| {
                const slot = stage.hulls.slot_by_visible_elem.get(pp);
                if (slot == std.math.maxInt(u32)) continue;

                var coords: rasterfrontend.ElemCoords(N) = undefined;
                const xs = stage.elem_coords.getSlice(&.{ pp, 0, 0 }, 1);
                const ys = stage.elem_coords.getSlice(&.{ pp, 1, 0 }, 1);
                const zs = stage.elem_coords.getSlice(&.{ pp, 2, 0 }, 1);
                var seeds: [geometrykernels.multiRootSeedCount(N)]Seed = undefined;
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
                    hullmultiroot.HullMultiRoot.prepareFourBezierLeavesPreCalc(
                        N,
                        stage.camera,
                        coords,
                        leaf_slice[0..4],
                    );
                } else {
                    const leaf_slice =
                        stage.hulls.leaves_on_the_fly[leaf_offset .. leaf_offset + 4];
                    hullmultiroot.HullMultiRoot.prepareFourBezierLeavesOnTheFly(
                        N,
                        stage.camera,
                        coords,
                        leaf_slice[0..4],
                    );
                }

                for (N..geometrykernels.multiRootSeedCount(N)) |seed_idx| {
                    const seed_uv = geometrykernels.multiRootSeedCoords(
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
                var ordered: [geometrykernels.multiRootSeedCount(N)]Seed = undefined;
                var length: usize = 0;
                const nodes = rasterfrontend.Vec3Slices(F){
                    .x = &coords.x,
                    .y = &coords.y,
                    .z = &coords.z,
                };
                for (seeds[0..available]) |*seed| {
                    const uv = geometrykernels.multiRootSeedCoords(
                        N,
                        seed.index,
                    );
                    const facing = rasterfrontend.projectedJacDetPhysical(
                        N,
                        nodes,
                        uv[0],
                        uv[1],
                    );
                    seed.front = std.math.isFinite(facing) and
                        facing < -buildconfig.config.tol.culling.projected_jacobian_abs;
                }
                for (0..2) |tier_idx| {
                    var tier: [geometrykernels.multiRootSeedCount(N)]Seed = undefined;
                    var tier_len: usize = 0;
                    for (seeds[0..available]) |seed| {
                        if (seed.front != (tier_idx == 0)) continue;
                        tier[tier_len] = seed;
                        tier_len += 1;
                    }
                    var used = [_]bool{false} ** geometrykernels.multiRootSeedCount(N);
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
                        hullmultiroot.HullMultiRoot.BezierLeafPreCalc,
                        multi_count * 4,
                    )
                else
                    &.{},
                .leaves_on_the_fly = if (self.multiroot_edge_fun_mode == .on_the_fly)
                    try outer_alloc.alloc(
                        hullmultiroot.HullMultiRoot.BezierLeafOnTheFly,
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
            parachunkexec.runStaticRange(
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
            const selection = self.mesh_static.hit_selections[renderRoleIndex(self.camera.render_format)];
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
            mesh_prep: *meshtypes.MeshPrepared,
        ) !void {
            const format = self.camera.render_format;
            switch (format) {
                .mono => {
                    const exec = self.mesh_static.shaders.mono orelse return;
                    mesh_prep.shaders.mono = switch (exec) {
                        .direct => |s| .{
                            .direct = try self.prepareShaderMonoFromStatic(
                                outer_alloc,
                                s,
                                self.scaling_params,
                            ),
                        },
                        .pipe => |p| .{
                            .pipe = try self.prepareShaderPipeFromStatic(outer_alloc, p, 1),
                        },
                    };
                },
                .ir => {
                    const exec = self.mesh_static.shaders.ir orelse return;
                    mesh_prep.shaders.ir = switch (exec) {
                        .direct => |s| .{
                            .direct = try self.prepareShaderMonoFromStatic(
                                outer_alloc,
                                s,
                                self.scaling_params,
                            ),
                        },
                        .pipe => |p| .{
                            .pipe = try self.prepareShaderPipeFromStatic(outer_alloc, p, 1),
                        },
                    };
                },
                .rgb => {
                    const pipe = self.mesh_static.shaders.rgb orelse return;
                    mesh_prep.shaders.rgb = try self.prepareShaderPipeFromStatic(
                        outer_alloc,
                        pipe,
                        3,
                    );
                },
                .multifield => {
                    const pipe = self.mesh_static.shaders.multifield orelse return;
                    mesh_prep.shaders.multifield = try self.prepareShaderPipeFromStatic(
                        outer_alloc,
                        pipe,
                        format.channels(),
                    );
                },
            }
        }

        fn prepareShaderPipeFromStatic(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            pipe: shadertypes.ShaderPipeStatic,
            channels: u8,
        ) !shadertypes.ShaderPipePrepared {
            const stages = try outer_alloc.alloc(
                shadertypes.ShaderPipeStagePrepared,
                pipe.stages.len,
            );

            for (pipe.stages, 0..) |stage, si| {
                stages[si] = switch (stage) {
                    .source => |src| blk: {
                        var prepared_source = try self.preparePipeSourceFromStatic(
                            outer_alloc,
                            src.shader,
                            if (src.shader == .nodal and src.shader.nodal.scale_over == .within_frames and
                                (src.shader.nodal.scaling == .auto or src.shader.nodal.scaling == .frac))
                                imageops.getScalingParamsNDArray(
                                    &src.shader.nodal.field.array,
                                    self.frame_idx,
                                    src.shader.nodal.scaling,
                                )
                            else
                                null,
                        );
                        switch (prepared_source) {
                            .func, .func_rgb, .func_multi => |*shader| shader.hit_geometry = .{},
                            else => {},
                        }
                        break :blk .{ .source = .{
                            .shader = prepared_source,
                            .destination = src.destination,
                            .channels = src.channels,
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

        fn prepareShaderMonoFromStatic(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            shader_static: shadertypes.ShaderMonoStatic,
            scaling: ?imageops.ScalingParams,
        ) !shadertypes.ShaderMonoPrepared {
            const previous_scaling = self.scaling_params;
            self.scaling_params = scaling;
            defer self.scaling_params = previous_scaling;
            return switch (shader_static) {
                .nodal => |s| .{
                    .nodal = try self.prepareNodalShaderFromStatic(outer_alloc, s),
                },
                .tex_u8 => |s| .{
                    .tex_u8 = try prepareTexShaderFromStatic(u8, 1, outer_alloc, self, s),
                },
                .tex_u16 => |s| .{
                    .tex_u16 = try prepareTexShaderFromStatic(u16, 1, outer_alloc, self, s),
                },
                .tex_f => |s| .{
                    .tex_f = try prepareTexShaderFromStatic(F, 1, outer_alloc, self, s),
                },
                .func => |s| .{
                    .func = try prepareFuncShaderFromStatic(1, outer_alloc, self, s),
                },
            };
        }

        fn preparePipeSourceFromStatic(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            source_static: shadertypes.PipeSourceStatic,
            scaling: ?imageops.ScalingParams,
        ) !shadertypes.PipeSourcePrepared {
            const previous_scaling = self.scaling_params;
            self.scaling_params = scaling;
            defer self.scaling_params = previous_scaling;
            return switch (source_static) {
                .nodal => |s| .{
                    .nodal = try self.prepareNodalShaderFromStatic(outer_alloc, s),
                },
                .tex_u8 => |s| .{
                    .tex_u8 = try prepareTexShaderFromStatic(u8, 1, outer_alloc, self, s),
                },
                .tex_u16 => |s| .{
                    .tex_u16 = try prepareTexShaderFromStatic(u16, 1, outer_alloc, self, s),
                },
                .tex_f => |s| .{
                    .tex_f = try prepareTexShaderFromStatic(F, 1, outer_alloc, self, s),
                },
                .tex_rgb_u8 => |s| .{
                    .tex_rgb_u8 = try prepareTexShaderFromStatic(u8, 3, outer_alloc, self, s),
                },
                .tex_rgb_u16 => |s| .{
                    .tex_rgb_u16 = try prepareTexShaderFromStatic(u16, 3, outer_alloc, self, s),
                },
                .tex_rgb_f => |s| .{
                    .tex_rgb_f = try prepareTexShaderFromStatic(F, 3, outer_alloc, self, s),
                },
                .tex_multi_f => |s| .{
                    .tex_multi_f = try prepareTexShaderFromStatic(F, null, outer_alloc, self, s),
                },
                .func => |s| .{
                    .func = try prepareFuncShaderFromStatic(1, outer_alloc, self, s),
                },
                .func_rgb => |s| .{
                    .func_rgb = try prepareFuncShaderFromStatic(3, outer_alloc, self, s),
                },
                .func_multi => |s| .{
                    .func_multi = try prepareFuncShaderFromStatic(0, outer_alloc, self, s),
                },
            };
        }

        const GatherVisibleFieldStage = struct {
            connect: *const meshtypes.Connect,
            field: *const fieldtypes.Field,
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

        fn prepareNodalShaderFromStatic(
            self: *FrameMeshPipelineType,
            outer_alloc: std.mem.Allocator,
            nodal_static: shadertypes.NodalStatic,
        ) !shadertypes.NodalPrepared {
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

            parachunkexec.runStaticRange(
                self.chunk_exec,
                &field_stage,
                runGatherVisibleField,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );

            const frame_scaling = nodal_static.scale_over == .within_frames and
                (nodal_static.scaling == .auto or nodal_static.scaling == .frac);
            const factors = if (frame_scaling)
                imageops.getScaleFactors(nodal_static.scaling, null, self.scaling_params.?)
            else
                imageops.ScaleFactors{ .mul = 1, .add = 0 };

            return .{
                .elem_field = elem_field,
                .output_gain = nodal_static.output_gain,
                .output_offset = nodal_static.output_offset,
                .scaling = nodal_static.scaling,
                .scale_over = nodal_static.scale_over,
                .scale_mul = if (frame_scaling)
                    factors.mul * nodal_static.output_gain
                else
                    nodal_static.scale_mul,
                .scale_add = if (frame_scaling)
                    factors.add * nodal_static.output_gain + nodal_static.output_offset
                else
                    nodal_static.scale_add,
            };
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

        fn prepareTexShaderFromStatic(
            comptime T: type,
            comptime C: ?usize,
            outer_alloc: std.mem.Allocator,
            self: *FrameMeshPipelineType,
            tex_static: if (C) |channels|
                shadertypes.TexStatic(T, channels)
            else
                shadertypes.TexMultiStatic(T),
        ) !if (C) |channels|
            shadertypes.TexPrepared(T, channels)
        else
            shadertypes.TexMultiPrepared(T) {
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

            parachunkexec.runStaticRange(
                self.chunk_exec,
                &uv_stage,
                runGatherVisibleUV,
                self.mesh_workspace.elems_in_image,
                self.vis_chunk_size,
            );

            return .{
                .elem_uvs = elem_uvs,
                .tex = tex_static.tex,
                .samp_cfg = tex_static.samp_cfg,
                .output_gain = tex_static.output_gain,
                .output_offset = tex_static.output_offset,
                .scaling = tex_static.scaling,
                .scale_mul = tex_static.scale_mul,
                .scale_add = tex_static.scale_add,
            };
        }

        fn prepareFuncShaderFromStatic(
            comptime C: usize,
            outer_alloc: std.mem.Allocator,
            self: *FrameMeshPipelineType,
            func_static: shadertypes.FuncStatic,
        ) !shadertypes.FuncPrepared {
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

                parachunkexec.runStaticRange(
                    self.chunk_exec,
                    &uv_stage,
                    runGatherVisibleUV,
                    self.mesh_workspace.elems_in_image,
                    self.vis_chunk_size,
                );
                break :blk elem_uvs;
            } else null;

            if (comptime C == 0) {
                return .{
                    .elem_uvs = elem_uvs,
                    .hit_geometry = self.hit_geometry,
                    .coord_mode = func_static.coord_mode,
                    .channels = func_static.channels,
                    .needs_normal = func_static.needs_normal and self.mesh_static.normal_type != .none,
                };
            } else {
                return .{
                    .elem_uvs = elem_uvs,
                    .hit_geometry = self.hit_geometry,
                    .coord_mode = func_static.coord_mode,
                    .builtin = func_static.builtin,
                    .params = func_static.params,
                    .output_gain = func_static.output_gain,
                    .output_offset = func_static.output_offset,
                    .scaling = func_static.scaling,
                    .scale_mul = func_static.scale_mul,
                    .scale_add = func_static.scale_add,
                    .needs_normal = func_static.needs_normal and
                        self.mesh_static.normal_type != .none,
                };
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
                self.mesh_static.referenced_nodes_num,
            );
        }

        fn remapVisElemInds(self: *FrameMeshPipelineType) void {
            for (self.mesh_workspace.elem_bboxes, 0..) |*elem_bbox, pp| {
                elem_bbox.elem_idx = pp;
            }
        }
    };
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

test "MeshHit requirements follow the selected camera role" {
    const stages = [_]shadertypes.ShaderPipeStageStatic{
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
                .needs_normal = true,
            } },
            .destination = .{ .kind = .channel, .index = 0 },
        } },
    };
    const shaders = shadertypes.MeshShaderSetStatic{
        .mono = .{ .direct = .{ .nodal = .{ .field = undefined } } },
        .ir = .{ .pipe = .{
            .stages = &stages,
            .resolver = undefined,
            .constants = &.{},
        } },
    };
    const direct = shaderSetHitSelection(shaders, .mono, .exact);
    try std.testing.expect(direct.count() == 0);
    try std.testing.expect(!shaderSetHitSelection(shaders, .mono, .exact).contains(.coords_def));

    const pipe = shaderSetHitSelection(shaders, .ir, .exact);
    try std.testing.expect(pipe.contains(.coords_ref));
    try std.testing.expect(pipe.contains(.coords_def));
    try std.testing.expect(pipe.contains(.surf_norm));
    try std.testing.expect(shaderSetHitSelection(shaders, .ir, .exact).contains(.coords_def));

    const no_norm = shaderSetHitSelection(shaders, .ir, .none);
    try std.testing.expect(!no_norm.contains(.surf_norm));
}

test "static preparation caches scaling and only prepares active roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var coord_mem = [_]F{ 0, 0, 0, 1, 0, 0, 0, 1, 0 };
    const coords = meshtypes.Coords.init(&coord_mem, 3);
    const connect = try meshtypes.Connect.initAlloc(alloc, 1, 3);
    @memcpy(connect.table_mem, &[_]usize{ 2, 0, 1 });
    var field_values = [_]F{ 2, 4, 6, 8, 10, 12 };
    const field_array = try ndarray.NDArray(F).init(alloc, &field_values, &.{ 2, 3, 1 });
    const field = fieldtypes.Field{ .array = field_array, .array_mem = &field_values };
    const channels = [_]shadertypes.FuncChannel{
        .{
            .builtin = .constant,
            .scaling = .{ .frac = .{ 0.2, 0.8 } },
            .output_gain = 2,
            .output_offset = 0.1,
            .params = .{ .settings = .{ .constant = .{ .value = 300 } } },
        },
        .{ .builtin = .lambertian_normal_z, .params = .{ .settings = .{ .lambertian_normal_z = .{} } } },
        .{ .builtin = .linear, .params = .{ .settings = .{ .linear = .{} } } },
    };
    const stages = [_]shadertypes.ShaderPipeStageInput{.{ .source = .{
        .shader = .{ .func_multi = .{ .coord_mode = .world_reference, .channels = &channels } },
        .destination = .{ .kind = .channel, .index = 0 },
    } }};
    const input = meshtypes.MeshInput{ .mesh_type = .tri3, .normal_type = .avg, .coords = coords, .connect = connect, .disp = null, .shaders = .{
        .mono_direct = .{ .nodal = .{ .field = field, .scaling = .auto, .output_gain = 2, .output_offset = 0.25 } },
        .rgb_pipe = .{ .stages = &stages, .resolver = .{ .identity = shaderpipe.identity_channels_3 } },
    } };
    const mono = try initMeshStatic(alloc, &input, .{ true, false, false, false });
    try std.testing.expect(mono.shaders.rgb == null);
    const nodal = mono.shaders.mono.?.direct.nodal;
    try std.testing.expectApproxEqAbs(@as(F, 0.2), nodal.scale_mul, 1e-15);
    try std.testing.expectApproxEqAbs(@as(F, -0.15), nodal.scale_add, 1e-15);
    const rgb = try initMeshStatic(alloc, &input, .{ false, true, false, false });
    try std.testing.expect(rgb.shaders.mono == null);
    try std.testing.expectEqual(@as(usize, 3), rgb.referenced_nodes_num);
    try std.testing.expect(rgb.hit_selections[1].contains(.coords_ref));
    try std.testing.expect(rgb.hit_selections[1].contains(.surf_norm));
    const source = rgb.shaders.rgb.?.stages[0].source;
    try std.testing.expectEqual(@as(u8, 3), source.channels);
    const func = source.shader.func_multi;
    try std.testing.expect(func.needs_normal);
    try std.testing.expectEqual(@as(usize, 3), func.channels.len);
    try std.testing.expectApproxEqAbs(@as(F, 1.2), func.channels[0].scale_mul, 1e-15);
    try std.testing.expectApproxEqAbs(@as(F, 0.5), func.channels[0].scale_add, 1e-15);
}

test "static texture scaling and UV gather match independent values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const connect = try meshtypes.Connect.initAlloc(alloc, 1, 3);
    @memcpy(connect.table_mem, &[_]usize{ 2, 0, 1 });
    var uv_mem = [_]F{ 0, 0.1, 0.2, 0.3, 0.4, 0.5 };
    const uv = try ndarray.NDArray(F).init(alloc, &uv_mem, &.{ 3, 2 });
    var tex_mem = [_]u8{ 10, 30, 50, 90 };
    const tex_array = try ndarray.NDArray(u8).init(alloc, &tex_mem, &.{ 1, 2, 2 });
    const prepared = try createTextureStatic(u8, 1, alloc, .{
        .uvs = uv,
        .tex = .{ .array = tex_array, .rows_num = 2, .cols_num = 2 },
        .scaling = .auto,
        .output_gain = 2,
        .output_offset = 0.25,
    }, &connect);
    try std.testing.expectApproxEqAbs(@as(F, 0.025), prepared.scale_mul, 1e-15);
    try std.testing.expectApproxEqAbs(@as(F, 0), prepared.scale_add, 1e-15);
    try std.testing.expectEqualSlices(F, &.{ 0.4, 0, 0.2, 0.5, 0.1, 0.3 }, prepared.elem_uvs.slice);
    const function = try funcStaticFromInput(alloc, .{ .uvs = uv, .coord_mode = .para, .builtin = .constant }, &connect);
    try std.testing.expect(function.elem_uvs == null);
}
