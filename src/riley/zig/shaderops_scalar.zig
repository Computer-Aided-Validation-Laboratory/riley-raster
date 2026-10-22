// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const matslice = @import("matslice.zig");
const texops = @import("textureops.zig");
const comm = @import("shaderops_common.zig");
const meshhit = @import("meshhit.zig");

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub inline fn fillNodalClipScal(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.NodalPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const value = shader_buf.interp(ff, interp.weights);
        const idx = ff * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = value * shader.scale_mul + shader.scale_add;
    }
}

pub inline fn fillNodalPerspScal(
    comptime N: usize,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.NodalPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    for (0..@as(usize, ctx_shade.actual_fields)) |ff| {
        const base = ff * N;

        var value: F = 0.0;
        inline for (0..N) |nn| {
            const inv_z = interp.nodes_inv_z[nn];
            value += interp.weights[nn] * shader_buf.data[base + nn] * inv_z;
        }

        const final_val = value * interp.sub_pixel_z;
        const idx = ff * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = final_val * shader.scale_mul + shader.scale_add;
    }
}

// --------------------------------------------------------------------------------------
// Texture Shader
// --------------------------------------------------------------------------------------

pub inline fn fillTexClipScal(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: texops.TexSampConfig,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        tex_u += interp.weights[nn] * shader_buf.data[nn];
        tex_v += interp.weights[nn] * shader_buf.data[N + nn];
    }

    const sampled = texops.sampScal(
        C,
        samp_cfg,
        shader.tex,
        tex_u,
        tex_v,
    );

    inline for (0..C) |ch| {
        const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = sampled[ch] * shader.scale_mul + shader.scale_add;
    }
}

pub inline fn fillTexPerspScal(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime samp_cfg: texops.TexSampConfig,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.TexPrepared(T, C),
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var tex_u: F = 0.0;
    var tex_v: F = 0.0;
    inline for (0..N) |nn| {
        const inv_z = interp.nodes_inv_z[nn];
        tex_u += interp.weights[nn] * shader_buf.data[nn] * inv_z;
        tex_v += interp.weights[nn] * shader_buf.data[N + nn] * inv_z;
    }

    const sampled = texops.sampScal(
        C,
        samp_cfg,
        shader.tex,
        tex_u * interp.sub_pixel_z,
        tex_v * interp.sub_pixel_z,
    );

    inline for (0..C) |ch| {
        const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
        spx_img_scratch.slice[idx] = sampled[ch] * shader.scale_mul + shader.scale_add;
    }
}

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

inline fn getFuncCoord(
    comptime N: usize,
    interp: meshhit.MeshHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    needs_normal: bool,
) comm.FuncCoord {
    if (needs_normal) {
        const normal = interp.surf_norm orelse shader_buf.interpNormal(interp.weights);
        return .{
            .coord_0 = 0.0,
            .coord_1 = 0.0,
            .normal_x = normal[0],
            .normal_y = normal[1],
            .normal_z = normal[2],
        };
    }

    return .{
        .coord_0 = 0.0,
        .coord_1 = 0.0,
        .normal_x = 0.0,
        .normal_y = 0.0,
        .normal_z = 1.0,
    };
}

inline fn setCoordValues(
    coord: *comm.FuncCoord,
    coord_0: F,
    coord_1: F,
) void {
    coord.coord_0 = coord_0;
    coord.coord_1 = coord_1;
}

inline fn resolveFuncCoordsClip(
    comptime N: usize,
    interp: meshhit.MeshHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
) struct { coord_0: F, coord_1: F } {
    return switch (shader.coord_mode) {
        .uv => .{
            .coord_0 = shader_buf.interpFuncCoord(0, interp.weights),
            .coord_1 = shader_buf.interpFuncCoord(1, interp.weights),
        },
        .para => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
        .world_reference => blk: {
            const coords = interp.coords_ref orelse break :blk .{
                .coord_0 = shader_buf.interpFuncCoord(0, interp.weights),
                .coord_1 = shader_buf.interpFuncCoord(1, interp.weights),
            };
            break :blk .{ .coord_0 = coords[0], .coord_1 = coords[1] };
        },
        .world_deformed => blk: {
            const coords = interp.coords_def orelse break :blk .{
                .coord_0 = shader_buf.interpFuncCoord(0, interp.weights),
                .coord_1 = shader_buf.interpFuncCoord(1, interp.weights),
            };
            break :blk .{ .coord_0 = coords[0], .coord_1 = coords[1] };
        },
    };
}

inline fn resolveFuncCoordsPersp(
    comptime N: usize,
    interp: meshhit.MeshHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
) struct { coord_0: F, coord_1: F } {
    const shared_coords = switch (shader.coord_mode) {
        .world_reference => interp.coords_ref,
        .world_deformed => interp.coords_def,
        else => null,
    };
    if (shared_coords) |coords| {
        return .{ .coord_0 = coords[0], .coord_1 = coords[1] };
    }
    return switch (shader.coord_mode) {
        .uv, .world_reference, .world_deformed => blk: {
            var coord_0: F = 0.0;
            var coord_1: F = 0.0;

            inline for (0..N) |nn| {
                const inv_z = interp.nodes_inv_z[nn];
                coord_0 += interp.weights[nn] * shader_buf.func_coords[nn] * inv_z;
                coord_1 += interp.weights[nn] * shader_buf.func_coords[N + nn] * inv_z;
            }

            break :blk .{
                .coord_0 = coord_0 * interp.sub_pixel_z,
                .coord_1 = coord_1 * interp.sub_pixel_z,
            };
        },
        .para => .{
            .coord_0 = interp.xi,
            .coord_1 = interp.eta,
        },
    };
}

pub inline fn fillFuncClipScal(
    comptime N: usize,
    comptime C: usize,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.MeshHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var coord = getFuncCoord(N, interp, shader_buf, shader.needs_normal);
    const coords = resolveFuncCoordsClip(N, interp, shader_buf, shader);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);
    const params = shader.params;

    if (comptime C == 1) {
        const value = comm.evalFuncShaderBuiltinGreyNorm(
            shader.builtin,
            coord,
            params,
        );

        spx_img_scratch.slice[ctx_shade.scratch_idx] =
            value * shader.scale_mul + shader.scale_add;
    } else {
        const vals = comm.evalFuncShaderBuiltinRGBNorm(
            shader.builtin,
            coord,
            params,
        );

        inline for (0..C) |ch| {
            const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
            spx_img_scratch.slice[idx] = vals[ch] * shader.scale_mul + shader.scale_add;
        }
    }
}

pub inline fn fillFuncPerspScal(
    comptime N: usize,
    comptime C: usize,
    ctx_shade: comm.ShadeContext,
    interp: meshhit.MeshHit(N),
    shader_buf: *const comm.LocalShaderBuff(N),
    shader: *const comm.FuncPrepared,
    spx_img_scratch: *matslice.MatSlice(F),
) void {
    var coord = getFuncCoord(N, interp, shader_buf, shader.needs_normal);
    const coords = resolveFuncCoordsPersp(N, interp, shader_buf, shader);
    setCoordValues(&coord, coords.coord_0, coords.coord_1);
    const params = shader.params;

    if (comptime C == 1) {
        const value = comm.evalFuncShaderBuiltinGreyNorm(
            shader.builtin,
            coord,
            params,
        );

        spx_img_scratch.slice[ctx_shade.scratch_idx] =
            value * shader.scale_mul + shader.scale_add;
    } else {
        const vals = comm.evalFuncShaderBuiltinRGBNorm(
            shader.builtin,
            coord,
            params,
        );

        inline for (0..C) |ch| {
            const idx = ch * spx_img_scratch.cols_num + ctx_shade.scratch_idx;
            spx_img_scratch.slice[idx] = vals[ch] * shader.scale_mul + shader.scale_add;
        }
    }
}
