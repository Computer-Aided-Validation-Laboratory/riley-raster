// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const eval_branch_quota = buildconfig.comptime_eval_branch_quota;
const shaderops = @import("shaderops.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const TextureSampleConfig = texops.TextureSampleConfig;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub inline fn shadeNodalScalarCommon(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.NodalPrepared,
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(F),
) void {
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        ctx_report.recordDepth(
            ctx_shade.global_subx,
            ctx_shade.global_suby,
            1.0 / interp.sub_pixel_z,
        );
    }

    if (shader.elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
            ctx_report.recordNormal(
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillNodalClip(
            N,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    } else {
        shaderops.fillNodalPersp(
            N,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    }
}

pub inline fn shadeTexScalarCommon(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(T, channels),
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(F),
) void {
    shadeTexScalarCommonImpl(
        N,
        T,
        channels,
        coord_space,
        ctx_shade,
        interp,
        shader,
        ctx_report,
        spx_image_scratch,
    );
}

fn shadeTexScalarCommonImpl(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(T, channels),
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(F),
) void {
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        ctx_report.recordDepth(
            ctx_shade.global_subx,
            ctx_shade.global_suby,
            1.0 / interp.sub_pixel_z,
        );
    }

    if (shader.elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
            ctx_report.recordNormal(
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }

    shadeTexScalarDispatchImpl(
        N,
        T,
        channels,
        coord_space,
        shader.sample_config,
        ctx_shade,
        interp,
        shader,
        spx_image_scratch,
    );
}

inline fn shadeTexScalarDispatchImpl(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    config: TextureSampleConfig,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(T, channels),
    spx_image_scratch: *MatSlice(F),
) void {
    @setEvalBranchQuota(eval_branch_quota);
    switch (config.sample) {
        inline else => |sample_type| shadeTexScalarDispatchModeImpl(
            N,
            T,
            channels,
            coord_space,
            sample_type,
            config.mode,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        ),
    }
}

inline fn shadeTexScalarDispatchModeImpl(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    comptime sample_type: texops.TextureSample,
    mode: texops.TextureSampleMode,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(T, channels),
    spx_image_scratch: *MatSlice(F),
) void {
    switch (mode) {
        inline else => |mode_type| shadeTexScalarDispatchConfigImpl(
            N,
            T,
            channels,
            coord_space,
            .{
                .sample = sample_type,
                .mode = mode_type,
            },
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        ),
    }
}

inline fn shadeTexScalarDispatchConfigImpl(
    comptime N: usize,
    comptime T: type,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    comptime comptime_config: TextureSampleConfig,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(T, channels),
    spx_image_scratch: *MatSlice(F),
) void {
    const sanitized_config = comptime comptime_config.sanitize();

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillTexClip(
            N,
            T,
            channels,
            sanitized_config,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    } else {
        shaderops.fillTexPersp(
            N,
            T,
            channels,
            sanitized_config,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    }
}

pub inline fn shadeFuncScalarCommon(
    comptime N: usize,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.FuncPrepared(channels),
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(F),
) void {
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        ctx_report.recordDepth(
            ctx_shade.global_subx,
            ctx_shade.global_suby,
            1.0 / interp.sub_pixel_z,
        );
    }

    if (shader.elem_normals != null) {
        const normal = ctx_shade.shader_buf.interpolateNormal(interp.weights);
        if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
            ctx_report.recordNormal(
                ctx_shade.global_subx,
                ctx_shade.global_suby,
                normal[0],
                normal[1],
                normal[2],
            );
        }
    }

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillFuncClip(
            N,
            channels,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    } else {
        shaderops.fillFuncPersp(
            N,
            channels,
            ctx_shade,
            interp,
            shader,
            spx_image_scratch,
        );
    }
}
