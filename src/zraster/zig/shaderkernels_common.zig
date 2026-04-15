const std = @import("std");
const buildconfig = @import("buildconfig.zig");
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
    spx_image_scratch: *MatSlice(f64),
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
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    interp: shaderops.InterpData(N),
    shader: *const shaderops.TexPrepared(channels),
    ctx_report: anytype,
    spx_image_scratch: *MatSlice(f64),
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

    const config = shader.sample_config;
    if (buildconfig.config.texture_sample_dispatch == .comp_time and
        buildconfig.config.texture_sample_mode_dispatch == .comp_time)
    {
        inline for (.{
            .nearest,
            .linear,
            .cubic_catmull_rom,
            .cubic_mitchell_netravali,
            .lanczos3,
            .cubic_bspline,
            .quintic_bspline,
        }) |sample_type| {
            if (config.sample == sample_type) {
                inline for (.{ .direct, .lut, .lut_lerp }) |mode_type| {
                    if (config.mode == mode_type) {
                        const comptime_config = texops.TextureSampleConfig{
                            .sample = sample_type,
                            .mode = mode_type,
                        };
                        if (comptime comptime_config.isValid()) {
                            if (comptime coord_space == CoordSpace.clip_px_leng) {
                                shaderops.fillTexClip(
                                    N,
                                    channels,
                                    comptime_config,
                                    ctx_shade,
                                    interp,
                                    shader,
                                    spx_image_scratch,
                                );
                            } else {
                                shaderops.fillTexPersp(
                                    N,
                                    channels,
                                    comptime_config,
                                    ctx_shade,
                                    interp,
                                    shader,
                                    spx_image_scratch,
                                );
                            }
                            return;
                        }
                    }
                }
            }
        }
    } else {
        if (comptime coord_space == CoordSpace.clip_px_leng) {
            shaderops.fillTexClipRuntime(
                N,
                channels,
                config,
                ctx_shade,
                interp,
                shader,
                spx_image_scratch,
            );
        } else {
            shaderops.fillTexPerspRuntime(
                N,
                channels,
                config,
                ctx_shade,
                interp,
                shader,
                spx_image_scratch,
            );
        }
    }
}
