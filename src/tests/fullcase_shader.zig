// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const meshtypes = @import("../riley/zig/meshtypes.zig");
const cameratypes = @import("../riley/zig/cameratypes.zig");
const shadertypes = @import("../riley/zig/shadertypes.zig");
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/cameraprojops.zig");
const common_full = @import("../dev_support/fullfixtures.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const imageops = @import("../riley/zig/imageops.zig");
const mo = @import("../riley/zig/meshpipeline.zig");
const shaderops = @import("../riley/zig/shaderops.zig");
const shaderpipe = @import("../riley/zig/shaderpipe.zig");
const normals = @import("../riley/zig/normals.zig");
const texops = @import("../riley/zig/textureops.zig");

const F = buildconfig.F;
const CameraInput = cameratypes.CameraInput;
const MeshInput = meshtypes.MeshInput;

pub const FullNodalCase = struct {
    is_rgb: bool,
    scaling: imageops.ScaleStrategy,
    scale_over: shadertypes.ScaleOver,
    normal_type: normals.NormalType = .none,
};

pub const FullTexCase = struct {
    is_rgb: bool,
    dtype: enum { u8, u16, f64 },
    normal_type: normals.NormalType = .none,
};

pub const FullFuncCase = struct {
    is_rgb: bool,
    builtin: shadertypes.FuncShaderBuiltin,
    coord: shadertypes.FuncCoordMode,
    normal_type: normals.NormalType = .none,
};

pub const FullShaderCase = union(enum) {
    nodal: FullNodalCase,
    tex: FullTexCase,
    func: FullFuncCase,

    pub fn isRgb(self: FullShaderCase) bool {
        return switch (self) {
            .nodal => |n| n.is_rgb,
            .tex => |t| t.is_rgb,
            .func => |f| f.is_rgb,
        };
    }

    pub fn formatDirName(
        self: FullShaderCase,
        allocator: std.mem.Allocator,
        elem: gk.MeshType,
    ) ![]const u8 {
        const elem_str = switch (elem) {
            .tri3opt => "tri3",
            else => @tagName(elem),
        };
        switch (self) {
            .nodal => |n| {
                const colour_str = if (n.is_rgb) "rgb" else "mono";
                const scale_str = switch (n.scaling) {
                    .none => "scalenone",
                    .auto => switch (n.scale_over) {
                        .within_frames => "scalewithin",
                        .over_frames => "scaleover",
                    },
                    else => "scalenone",
                };
                const norm_str = switch (n.normal_type) {
                    .none => "normnone",
                    .avg => "normavg",
                    .exact => "normexact",
                };
                return std.fmt.allocPrint(
                    allocator,
                    "scene0_{s}_nodal_{s}_{s}_{s}",
                    .{ elem_str, colour_str, scale_str, norm_str },
                );
            },
            .tex => |t| {
                const colour_str = if (t.is_rgb) "rgb" else "mono";
                const dtype_str = @tagName(t.dtype);
                const norm_str = switch (t.normal_type) {
                    .none => "normnone",
                    .avg => "normavg",
                    .exact => "normexact",
                };
                return std.fmt.allocPrint(
                    allocator,
                    "scene0_{s}_tex_{s}_{s}_catmull_rom_direct_{s}",
                    .{ elem_str, colour_str, dtype_str, norm_str },
                );
            },
            .func => |f| {
                const colour_str = if (f.is_rgb) "rgb" else "mono";
                const builtin_str = @tagName(f.builtin);
                const coord_str = switch (f.coord) {
                    .para => "para",
                    .uv => "uv",
                    .world_reference => "world_ref",
                    .world_deformed => "world_def",
                };
                const norm_str = switch (f.normal_type) {
                    .none => "normnone",
                    .avg => "normavg",
                    .exact => "normexact",
                };
                return std.fmt.allocPrint(
                    allocator,
                    "scene0_{s}_func_{s}_{s}_{s}_{s}",
                    .{ elem_str, colour_str, builtin_str, coord_str, norm_str },
                );
            },
        }
    }
};

fn createShaders(
    allocator: std.mem.Allocator,
    is_rgb: bool,
    sphere_source: shadertypes.PipeSourceInput,
    cyl_source: shadertypes.PipeSourceInput,
    sphere_mono: shadertypes.ShaderMonoInput,
    cyl_mono: shadertypes.ShaderMonoInput,
) !struct { shadertypes.MeshShaderSetInput, shadertypes.MeshShaderSetInput } {
    if (is_rgb) {
        const s1_stages = try allocator.alloc(shadertypes.ShaderPipeStageInput, 1);
        s1_stages[0] = shaderops.stageSource(sphere_source);
        const s2_stages = try allocator.alloc(shadertypes.ShaderPipeStageInput, 1);
        s2_stages[0] = shaderops.stageSource(cyl_source);
        return .{
            .{ .rgb_pipe = .{
                .stages = s1_stages,
                .resolver = .{ .identity = shaderpipe.identity_channels_3[0..3] },
            } },
            .{ .rgb_pipe = .{
                .stages = s2_stages,
                .resolver = .{ .identity = shaderpipe.identity_channels_3[0..3] },
            } },
        };
    } else {
        return .{
            .{ .mono_direct = sphere_mono },
            .{ .mono_direct = cyl_mono },
        };
    }
}

pub fn buildShaderCaseMeshes(
    allocator: std.mem.Allocator,
    mesh_type: gk.MeshType,
    prep: *const common_full.Scene0Prepared,
    textures: *const common_full.FullTextures,
    case: FullShaderCase,
) ![2]MeshInput {
    switch (case) {
        .nodal => |n| {
            const sphere_field = if (n.is_rgb)
                prep.sphere_rgb
            else
                prep.sphere_temp;
            const cyl_field = if (n.is_rgb)
                prep.cylinder_rgb
            else
                prep.cylinder_temp;

            const sphere_input = shadertypes.NodalInput{
                .field = sphere_field,
                .output_gain = if (n.scaling == .none) 1.0 else 255.0,
                .scaling = n.scaling,
                .scale_over = n.scale_over,
            };
            const cyl_input = shadertypes.NodalInput{
                .field = cyl_field,
                .output_gain = if (n.scaling == .none) 1.0 else 255.0,
                .scaling = n.scaling,
                .scale_over = n.scale_over,
            };

            const sphere_source: shadertypes.PipeSourceInput = .{ .nodal = sphere_input };
            const cyl_source: shadertypes.PipeSourceInput = .{ .nodal = cyl_input };
            const sphere_mono: shadertypes.ShaderMonoInput = .{ .nodal = sphere_input };
            const cyl_mono: shadertypes.ShaderMonoInput = .{ .nodal = cyl_input };

            const shaders = try createShaders(
                allocator,
                n.is_rgb,
                sphere_source,
                cyl_source,
                sphere_mono,
                cyl_mono,
            );

            return [_]MeshInput{
                .{
                    .mesh_type = mesh_type,
                    .normal_type = n.normal_type,
                    .coords = prep.sphere_coords,
                    .connect = prep.sphere_connect,
                    .disp = prep.sphere_disp,
                    .shaders = shaders[0],
                },
                .{
                    .mesh_type = mesh_type,
                    .normal_type = n.normal_type,
                    .coords = prep.cylinder_coords,
                    .connect = prep.cylinder_connect,
                    .disp = prep.cylinder_disp,
                    .shaders = shaders[1],
                },
            };
        },
        .tex => |t| {
            const samp_cfg = texops.TexSampConfig{
                .sample = .cubic_catmull_rom,
                .mode = .direct,
            };

            const sphere_source: shadertypes.PipeSourceInput = switch (t.dtype) {
                .u8 => .{ .tex_rgb_u8 = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_u8_rgb,
                    .samp_cfg = samp_cfg,
                } },
                .u16 => .{ .tex_rgb_u16 = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_u16_rgb,
                    .samp_cfg = samp_cfg,
                } },
                .f64 => .{ .tex_rgb_f = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_f64_rgb,
                    .samp_cfg = samp_cfg,
                } },
            };
            const cyl_source: shadertypes.PipeSourceInput = switch (t.dtype) {
                .u8 => .{ .tex_rgb_u8 = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_u8_rgb,
                    .samp_cfg = samp_cfg,
                } },
                .u16 => .{ .tex_rgb_u16 = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_u16_rgb,
                    .samp_cfg = samp_cfg,
                } },
                .f64 => .{ .tex_rgb_f = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_f64_rgb,
                    .samp_cfg = samp_cfg,
                } },
            };

            const sphere_mono: shadertypes.ShaderMonoInput = switch (t.dtype) {
                .u8 => .{ .tex_u8 = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_u8_mono,
                    .samp_cfg = samp_cfg,
                } },
                .u16 => .{ .tex_u16 = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_u16_mono,
                    .samp_cfg = samp_cfg,
                } },
                .f64 => .{ .tex_f = .{
                    .uvs = prep.sphere_uvs.array,
                    .tex = textures.tex_f64_mono,
                    .samp_cfg = samp_cfg,
                } },
            };
            const cyl_mono: shadertypes.ShaderMonoInput = switch (t.dtype) {
                .u8 => .{ .tex_u8 = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_u8_mono,
                    .samp_cfg = samp_cfg,
                } },
                .u16 => .{ .tex_u16 = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_u16_mono,
                    .samp_cfg = samp_cfg,
                } },
                .f64 => .{ .tex_f = .{
                    .uvs = prep.cylinder_uvs.array,
                    .tex = textures.tex_f64_mono,
                    .samp_cfg = samp_cfg,
                } },
            };

            const shaders = try createShaders(
                allocator,
                t.is_rgb,
                sphere_source,
                cyl_source,
                sphere_mono,
                cyl_mono,
            );

            return [_]MeshInput{
                .{
                    .mesh_type = mesh_type,
                    .normal_type = t.normal_type,
                    .coords = prep.sphere_coords,
                    .connect = prep.sphere_connect,
                    .disp = prep.sphere_disp,
                    .shaders = shaders[0],
                },
                .{
                    .mesh_type = mesh_type,
                    .normal_type = t.normal_type,
                    .coords = prep.cylinder_coords,
                    .connect = prep.cylinder_connect,
                    .disp = prep.cylinder_disp,
                    .shaders = shaders[1],
                },
            };
        },
        .func => |f| {
            const params = shadertypes.FuncShaderParams{
                .settings = switch (f.builtin) {
                    .constant => .{ .constant = .{} },
                    .linear => .{ .linear = .{} },
                    .quadratic => .{ .quadratic = .{} },
                    .sinusoidal => .{ .sinusoidal = .{} },
                    .sinusoidal_approx => .{ .sinusoidal_approx = .{} },
                    .checker => .{ .checker = .{} },
                    .checker_smooth => .{ .checker_smooth = .{} },
                    .lambertian_normal_z => .{ .lambertian_normal_z = .{} },
                    .eggbox => .{ .eggbox = .{} },
                },
            };

            const sphere_uvs = if (f.coord == .uv)
                prep.sphere_uvs.array
            else
                null;
            const sphere_func_input = shadertypes.FuncInput{
                .uvs = sphere_uvs,
                .coord_mode = f.coord,
                .builtin = f.builtin,
                .params = params,
            };
            const cyl_uvs = if (f.coord == .uv)
                prep.cylinder_uvs.array
            else
                null;
            const cyl_func_input = shadertypes.FuncInput{
                .uvs = cyl_uvs,
                .coord_mode = f.coord,
                .builtin = f.builtin,
                .params = params,
            };

            const sphere_source: shadertypes.PipeSourceInput = .{
                .func = .{ .rgb = sphere_func_input },
            };
            const cyl_source: shadertypes.PipeSourceInput = .{
                .func = .{ .rgb = cyl_func_input },
            };
            const sphere_mono: shadertypes.ShaderMonoInput = .{
                .func = sphere_func_input,
            };
            const cyl_mono: shadertypes.ShaderMonoInput = .{
                .func = cyl_func_input,
            };

            const shaders = try createShaders(
                allocator,
                f.is_rgb,
                sphere_source,
                cyl_source,
                sphere_mono,
                cyl_mono,
            );

            return [_]MeshInput{
                .{
                    .mesh_type = mesh_type,
                    .normal_type = f.normal_type,
                    .coords = prep.sphere_coords,
                    .connect = prep.sphere_connect,
                    .disp = prep.sphere_disp,
                    .shaders = shaders[0],
                },
                .{
                    .mesh_type = mesh_type,
                    .normal_type = f.normal_type,
                    .coords = prep.cylinder_coords,
                    .connect = prep.cylinder_connect,
                    .disp = prep.cylinder_disp,
                    .shaders = shaders[1],
                },
            };
        },
    }
}
