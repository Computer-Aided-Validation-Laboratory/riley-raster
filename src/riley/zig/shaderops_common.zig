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
const cfg = @import("buildconfig.zig").config;
const F = buildconfig.F;

const ndarray = @import("ndarray.zig");

const imageops = @import("imageops.zig");
const texops = @import("textureops.zig");
const meshio = @import("meshio.zig");
const speckle = @import("speckleops.zig");

// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

pub const ScaleOver = enum { within_frames, over_frames };
pub const NormalType = enum { none, exact, avg };

pub fn LocalShaderBuff(comptime N: usize) type {
    return struct {
        data: [cfg.max_nodal_fields * N]F = undefined,
        func_coords: [3 * N]F = undefined,
        normals: [3 * N]F = undefined,
        actual_fields: u8 = 0,
        actual_func_coords: u8 = 0,

        const Self = @This();

        pub inline fn load(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
            fields_num: u8,
        ) void {
            std.debug.assert(fields_num <= cfg.max_nodal_fields);
            self.actual_fields = fields_num;
            const count = @as(usize, fields_num) * N;
            @memcpy(self.data[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn loadNormals(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
        ) void {
            const count = 3 * N;
            @memcpy(self.normals[0..count], array.slice[start_idx .. start_idx + count]);
        }

        pub inline fn loadFuncCoords(
            self: *Self,
            array: ndarray.NDArray(F),
            start_idx: usize,
            coords_num: u8,
        ) void {
            std.debug.assert(coords_num <= 3);
            self.actual_func_coords = coords_num;
            const count = @as(usize, coords_num) * N;
            @memcpy(
                self.func_coords[0..count],
                array.slice[start_idx .. start_idx + count],
            );
        }

        pub inline fn interp(
            self: *const Self,
            field_idx: usize,
            weights: [N]F,
        ) F {
            const base = field_idx * N;
            var sum: F = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.data[base + nn];
            }
            return sum;
        }

        pub inline fn interpNormal(
            self: *const Self,
            weights: [N]F,
        ) [3]F {
            var norm = [3]F{ 0.0, 0.0, 0.0 };
            inline for (0..N) |nn| {
                norm[0] += weights[nn] * self.normals[0 * N + nn];
                norm[1] += weights[nn] * self.normals[1 * N + nn];
                norm[2] += weights[nn] * self.normals[2 * N + nn];
            }
            return norm;
        }

        pub inline fn interpFuncCoord(
            self: *const Self,
            coord_idx: usize,
            weights: [N]F,
        ) F {
            const base = coord_idx * N;
            var sum: F = 0.0;
            inline for (0..N) |nn| {
                sum += weights[nn] * self.func_coords[base + nn];
            }
            return sum;
        }
    };
}

// Input: Raw user shader data for all frames.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Node-order [total_nodes, 2]
pub const NodalInput = struct {
    field: meshio.Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub fn TexInput(comptime T: type, comptime C: usize) type {
    return struct {
        uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const FuncInput = struct {
    uvs: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    normal_type: NormalType = .none,
};

pub const ShaderInput = union(enum) {
    nodal: NodalInput,
    tex_u8: TexInput(u8, 1),
    tex_u16: TexInput(u16, 1),
    tex_f: TexInput(F, 1),
    tex_rgb_u8: TexInput(u8, 3),
    tex_rgb_u16: TexInput(u16, 3),
    tex_rgb_f: TexInput(F, 3),
    func: FuncInput,
    func_rgb: FuncInput,
};

pub const FuncCoordMode = enum {
    uv,
    para,
    world_reference,
    world_deformed,
};

pub const FuncShaderBuiltin = enum {
    constant,
    linear,
    quadratic,
    sinusoidal,
    sinusoidal_approx,
    checker,
    checker_smooth,
    lambertian_normal_z,
    eggbox,
    speckle,
};

pub const ConstantParams = struct {
    value: F = 0.5,
    value_rgb: [3]F = .{ 0.2, 0.5, 0.8 },
};

pub const LinearParams = struct {
    coeffs: [3]F = .{ 0.5, 0.25, 0.2 },
    coeffs_rgb: [3][3]F = .{
        .{ 0.5, 0.25, 0.0 },
        .{ 0.5, 0.0, 0.25 },
        .{ 0.5, 0.15, -0.15 },
    },
};

pub const QuadraticParams = struct {
    coeffs: [6]F = .{ 0.35, 0.2, 0.15, 0.1, -0.08, 0.06 },
    coeffs_rgb: [3][6]F = .{
        .{ 0.3, 0.0, 0.0, 0.2, 0.0, 0.0 },
        .{ 0.3, 0.0, 0.0, 0.0, 0.0, 0.2 },
        .{ 0.3, 0.0, 0.0, 0.0, 0.12, 0.0 },
    },
};

pub const SinusoidalParams = struct {
    wave_num_scalar: [2]F = .{ 6.0, 5.0 },
    wave_num_rgb: [3]F = .{ 6.0, 6.0, 4.0 },
    bias: F = 0.5,
    amplitudes: [2]F = .{ 0.25, 0.2 },
    bias_rgb: [3]F = .{ 0.5, 0.5, 0.5 },
    amplitudes_rgb: [3]F = .{ 0.25, 0.25, 0.2 },
};

pub const CheckerParams = struct {
    levels: [2]F = .{ 0.0, 1.0 },
    levels_rgb: [2][3]F = .{
        .{ 0.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 1.0 },
    },
};

pub const CheckerSmoothParams = struct {
    frequency: F = 8.0,
};

pub const LambertianParams = struct {
    coeffs: [2]F = .{ 0.5, 0.5 },
    coeffs_rgb: [3][2]F = .{
        .{ 0.5, 0.5 },
        .{ 0.375, 0.375 },
        .{ 0.25, 0.25 },
    },
};

pub const EggboxParams = struct {
    mean: F = 0.5,
    contrast: F = 0.4,
    pitch: [2]F = .{ 1.0, 1.0 },
    phase: [2]F = .{ 0.0, 0.0 },
};

pub const FuncShaderParams = struct {
    coord_scale: [2]F = .{ 1.0, 1.0 },
    coord_offset: [2]F = .{ 0.0, 0.0 },
    output_scale: F = 1.0,
    output_offset: F = 0.0,
    settings: union(FuncShaderBuiltin) {
        constant: ConstantParams,
        linear: LinearParams,
        quadratic: QuadraticParams,
        sinusoidal: SinusoidalParams,
        sinusoidal_approx: SinusoidalParams,
        checker: CheckerParams,
        checker_smooth: CheckerSmoothParams,
        lambertian_normal_z: LambertianParams,
        eggbox: EggboxParams,
        speckle: speckle.Speckle2DParams,
    } = .{ .constant = .{} },
};

// Static: Persistent multi-frame shader resources in engine memory.
// Nodal Fields: Node-order [num_frames, total_nodes, num_fields]
// UVs: Elem-order [total_elems, 2, nodes_per_elem]
pub const NodalStatic = struct {
    field: meshio.Field,
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    normal_type: NormalType = .none,
};

pub fn TexStatic(comptime T: type, comptime C: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        normal_type: NormalType = .none,
    };
}

pub const FuncStatic = struct {
    elem_uvs: ?ndarray.NDArray(F),
    speckle_resources: speckle.Resources = .{},
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    normal_type: NormalType = .none,
};

pub const ShaderStatic = union(enum) {
    nodal: NodalStatic,
    tex_u8: TexStatic(u8, 1),
    tex_u16: TexStatic(u16, 1),
    tex_f: TexStatic(F, 1),
    tex_rgb_u8: TexStatic(u8, 3),
    tex_rgb_u16: TexStatic(u16, 3),
    tex_rgb_f: TexStatic(F, 3),
    func: FuncStatic,
    func_rgb: FuncStatic,
};

// Prep: Culled and expanded shader data for a SINGLE frame.
// Prep means culled elem-order ndarray.NDArray data ready for the raster loop.
// Nodal Fields: Elem-order [vis_elems, num_fields, nodes_per_elem]
// UVs: Elem-order [vis_elems, 2, nodes_per_elem]
pub const NodalPrepared = struct {
    elem_field: ndarray.NDArray(F),
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_over: ScaleOver = .over_frames,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?ndarray.MappedNDArray(F) = null,
};

pub fn TexPrepared(comptime T: type, comptime C: usize) type {
    return struct {
        elem_uvs: ndarray.NDArray(F),
        tex: texops.Tex(T, C),
        samp_cfg: texops.TexSampConfig = .{
            .sample = .cubic_catmull_rom,
            .mode = .lut_lerp,
        },
        bits: ?u8 = 8,
        scaling: imageops.ScaleStrategy = .none,
        scale_mul: F = 1.0,
        scale_add: F = 0.0,
        normal_type: NormalType = .none,
        elem_normals: ?ndarray.MappedNDArray(F) = null,
    };
}

pub const FuncPrepared = struct {
    elem_uvs: ?ndarray.NDArray(F),
    speckle_resources: speckle.Resources = .{},
    elem_world_ref: ?ndarray.NDArray(F) = null,
    elem_world_def: ?ndarray.NDArray(F) = null,
    coord_mode: FuncCoordMode = .para,
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams = .{},
    bits: ?u8 = 8,
    scaling: imageops.ScaleStrategy = .none,
    scale_mul: F = 1.0,
    scale_add: F = 0.0,
    normal_type: NormalType = .none,
    elem_normals: ?ndarray.MappedNDArray(F) = null,
};

pub const ShaderPrepared = union(enum) {
    nodal: NodalPrepared,
    tex_u8: TexPrepared(u8, 1),
    tex_u16: TexPrepared(u16, 1),
    tex_f: TexPrepared(F, 1),
    tex_rgb_u8: TexPrepared(u8, 3),
    tex_rgb_u16: TexPrepared(u16, 3),
    tex_rgb_f: TexPrepared(F, 3),
    func: FuncPrepared,
    func_rgb: FuncPrepared,
};

pub const ShadeContext = struct {
    frame_idx: usize,
    elem_idx: usize,
    fields_num: u8,
    actual_fields: u8,
    scratch_idx: usize,
    global_subx: usize,
    global_suby: usize,
    v_mask_active: ?buildconfig.VecSB = null,
    // Global sub-pixel tiles own disjoint target samples. Their final SIMD
    // vector may straddle a tile edge, so inactive lanes must not perform a
    // read-modify-write against the neighbouring tile's target samples.
    exclusive_subpx_target: bool = false,
};

pub fn InterpData(comptime N: usize) type {
    return struct {
        weights: [N]F,
        nodes_inv_z: [N]F,
        sub_pixel_z: F,
        xi: F,
        eta: F,
    };
}

pub inline fn normFuncShaderParams(
    builtin: FuncShaderBuiltin,
    params: FuncShaderParams,
) FuncShaderParams {
    if (std.meta.activeTag(params.settings) == builtin) return params;

    var out = params;
    out.settings = switch (builtin) {
        .constant => .{ .constant = .{} },
        .linear => .{ .linear = .{} },
        .quadratic => .{ .quadratic = .{} },
        .sinusoidal => .{ .sinusoidal = .{} },
        .sinusoidal_approx => .{ .sinusoidal_approx = .{} },
        .checker => .{ .checker = .{} },
        .checker_smooth => .{ .checker_smooth = .{} },
        .lambertian_normal_z => .{ .lambertian_normal_z = .{} },
        .eggbox => .{ .eggbox = .{} },
        .speckle => .{ .speckle = .{} },
    };
    return out;
}

pub fn validateSpeckleInput(
    input: FuncInput,
    is_rgb: bool,
    connect: *const meshio.Connect,
) !void {
    if (input.builtin != .speckle) return;
    if (is_rgb) return error.SpeckleRequiresGrayscale;
    if (input.coord_mode != .uv) return error.SpeckleRequiresUVCoordinates;
    const uvs = input.uvs orelse return error.MissingUVsForSpeckleShader;
    if (input.normal_type != .none) return error.SpeckleRequiresNoNormals;
    if (uvs.dims.len != 2 or uvs.dims[1] != 2) {
        return error.InvalidSpeckleUVShape;
    }
    for (connect.table_mem) |node_idx| {
        if (node_idx >= uvs.dims[0]) return error.InvalidSpeckleUVNodeIndex;
    }
    for (uvs.slice) |value| {
        if (!std.math.isFinite(value)) return error.InvalidSpeckleUVValue;
    }
    if (input.params.coord_scale[0] != 1.0 or
        input.params.coord_scale[1] != 1.0 or
        input.params.coord_offset[0] != 0.0 or
        input.params.coord_offset[1] != 0.0)
    {
        return error.SpeckleUsesTypedCoordinateParams;
    }

    const params = normFuncShaderParams(.speckle, input.params);
    try params.settings.speckle.validate();
}
