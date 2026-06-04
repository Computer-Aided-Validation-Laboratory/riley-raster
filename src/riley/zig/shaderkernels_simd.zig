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
const S = buildconfig.SimdWidth;
const VecSB = buildconfig.VecSB;
const VecSF = buildconfig.VecSF;

const common = @import("shaderkernels_common.zig");
const shaderops = @import("shaderops.zig");
const texops = @import("textureops.zig");
const report = @import("report.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

pub fn NodalKernel(comptime N: usize) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.NodalPrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.shadeNodalScalarCommon(
                N,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader: *const shaderops.NodalPrepared,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            _ = v_xi;
            _ = v_eta;
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillNodalPerspSIMD(
                    N,
                    ctx_shade,
                    v_weights,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillNodalClipSIMD(
                    N,
                    ctx_shade,
                    v_weights,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}

pub fn TexKernel(
    comptime N: usize,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexPrepared(channels),
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.shadeTexScalarCommon(
                N,
                channels,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader: *const shaderops.TexPrepared(channels),
            spx_image_scratch: *MatSlice(f64),
        ) void {
            shadeTexSIMDImpl(
                N,
                channels,
                coord_space,
                ctx_shade,
                ctx_report,
                v_mask_active,
                v_weights,
                v_xi,
                v_eta,
                v_nodes_inv_z,
                v_subpx_z,
                shader,
                spx_image_scratch,
            );
        }
    };
}

fn shadeTexSIMDImpl(
    comptime N: usize,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext(N),
    ctx_report: anytype,
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_xi: VecSF,
    v_eta: VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader: *const shaderops.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    _ = v_xi;
    _ = v_eta;
    if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
        if (shader.elem_normals != null) {
            report.recordNormalSIMD(
                N,
                S,
                ctx_report,
                ctx_shade,
                v_mask_active,
                v_weights,
            );
        }
    }

    shadeTexSIMDDispatchImpl(
        N,
        channels,
        coord_space,
        shader.sample_config,
        ctx_shade,
        v_mask_active,
        v_weights,
        v_nodes_inv_z,
        v_subpx_z,
        shader,
        spx_image_scratch,
    );
}

fn shadeTexSIMDDispatchImpl(
    comptime N: usize,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    config: texops.TextureSampleConfig,
    ctx_shade: shaderops.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader: *const shaderops.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    switch (config.sample) {
        inline else => |sample_type| shadeTexSIMDDispatchModeImpl(
            N,
            channels,
            coord_space,
            sample_type,
            config.mode,
            ctx_shade,
            v_mask_active,
            v_weights,
            v_nodes_inv_z,
            v_subpx_z,
            shader,
            spx_image_scratch,
        ),
    }
}

fn shadeTexSIMDDispatchModeImpl(
    comptime N: usize,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    comptime sample_type: texops.TextureSample,
    mode: texops.TextureSampleMode,
    ctx_shade: shaderops.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader: *const shaderops.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    switch (mode) {
        inline else => |mode_type| shadeTexSIMDDispatchConfigImpl(
            N,
            channels,
            coord_space,
            .{
                .sample = sample_type,
                .mode = mode_type,
            },
            ctx_shade,
            v_mask_active,
            v_weights,
            v_nodes_inv_z,
            v_subpx_z,
            shader,
            spx_image_scratch,
        ),
    }
}

fn shadeTexSIMDDispatchConfigImpl(
    comptime N: usize,
    comptime channels: usize,
    comptime coord_space: CoordSpace,
    comptime comptime_config: texops.TextureSampleConfig,
    ctx_shade: shaderops.ShadeContext(N),
    v_mask_active: VecSB,
    v_weights: [N]VecSF,
    v_nodes_inv_z: [N]VecSF,
    v_subpx_z: VecSF,
    shader: *const shaderops.TexPrepared(channels),
    spx_image_scratch: *MatSlice(f64),
) void {
    if (!comptime comptime_config.isValid()) return;

    if (comptime coord_space == CoordSpace.raster) {
        shaderops.fillTexPerspSIMD(
            N,
            channels,
            comptime_config,
            ctx_shade,
            v_mask_active,
            v_weights,
            v_nodes_inv_z,
            v_subpx_z,
            shader,
            spx_image_scratch,
        );
    } else if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillTexClipSIMD(
            N,
            channels,
            comptime_config,
            ctx_shade,
            v_mask_active,
            v_weights,
            shader,
            spx_image_scratch,
        );
    } else {
        @panic("shadeSIMD not implemented for this coord_space");
    }
}

pub fn TexFuncKernel(
    comptime N: usize,
    comptime channels: usize,
) type {
    return struct {
        pub inline fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            interp: shaderops.InterpData(N),
            shader: *const shaderops.TexFuncPrepared(channels),
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(f64),
        ) void {
            common.shadeTexFuncScalarCommon(
                N,
                channels,
                coord_space,
                ctx_shade,
                interp,
                shader,
                ctx_report,
                spx_image_scratch,
            );
        }

        pub inline fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext(N),
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            shader: *const shaderops.TexFuncPrepared(channels),
            spx_image_scratch: *MatSlice(f64),
        ) void {
            if (comptime @TypeOf(ctx_report).mode_tag == .full_stats) {
                if (shader.elem_normals != null) {
                    report.recordNormalSIMD(
                        N,
                        S,
                        ctx_report,
                        ctx_shade,
                        v_mask_active,
                        v_weights,
                    );
                }
            }

            if (comptime coord_space == CoordSpace.raster) {
                shaderops.fillTexFuncPerspSIMD(
                    N,
                    channels,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_xi,
                    v_eta,
                    v_nodes_inv_z,
                    v_subpx_z,
                    shader,
                    spx_image_scratch,
                );
            } else if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTexFuncClipSIMD(
                    N,
                    channels,
                    ctx_shade,
                    v_mask_active,
                    v_weights,
                    v_xi,
                    v_eta,
                    shader,
                    spx_image_scratch,
                );
            } else {
                @panic("shadeSIMD not implemented for this coord_space");
            }
        }
    };
}
