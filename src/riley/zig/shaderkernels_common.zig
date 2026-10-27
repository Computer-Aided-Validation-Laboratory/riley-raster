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
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;
const eval_branch_quota = buildconfig.comptime_eval_branch_quota;
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const MatSlice = @import("matslice.zig").MatSlice;
const texops = @import("textureops.zig");
const TexSampConfig = texops.TexSampConfig;
const CoordSpace = @import("geometrykernels.zig").CoordSpace;

// --------------------------------------------------------------------------------------
// Nodal Interp Shader
// --------------------------------------------------------------------------------------

pub inline fn shadeNodalScalComm(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.NodalPrepared,
    ctx_report: anytype,
    spx_img_scratch: *MatSlice(F),
) void {
    _ = ctx_report;
    _ = ctx_report;

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillNodalClipScal(
            N,
            ctx_shade,
            interp,
            shader_buf,
            shader,
            spx_img_scratch,
        );
    } else {
        shaderops.fillNodalPerspScal(
            N,
            ctx_shade,
            interp,
            shader_buf,
            shader,
            spx_img_scratch,
        );
    }
}

// --------------------------------------------------------------------------------------
// Texture Shader
// --------------------------------------------------------------------------------------

pub inline fn shadeTexScalComm(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    ctx_report: anytype,
    spx_img_scratch: *MatSlice(F),
) void {
    _ = ctx_report;
    _ = ctx_report;

    shadeTexScalDispatchSample(
        N,
        T,
        C,
        coord_space,
        shader.samp_cfg,
        ctx_shade,
        interp,
        shader_buf,
        shader,
        spx_img_scratch,
    );
}

inline fn shadeTexScalDispatchSample(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    samp_cfg: TexSampConfig,
    ctx_shade: shaderops.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    spx_img_scratch: *MatSlice(F),
) void {
    @setEvalBranchQuota(eval_branch_quota);
    switch (samp_cfg.sample) {
        inline else => |samp_type| shadeTexScalDispatchMode(
            N,
            T,
            C,
            coord_space,
            samp_type,
            samp_cfg.mode,
            ctx_shade,
            interp,
            shader_buf,
            shader,
            spx_img_scratch,
        ),
    }
}

inline fn shadeTexScalDispatchMode(
    comptime N: usize,
    comptime T: type,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    comptime samp_type: texops.TexSamp,
    mode: texops.TexSampMode,
    ctx_shade: shaderops.ShadeContext,
    interp: meshhit.RasterHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.TexPrepared(T, C),
    spx_img_scratch: *MatSlice(F),
) void {
    switch (mode) {
        inline else => |mode_type| {
            const samp_cfg = comptime (TexSampConfig{
                .sample = samp_type,
                .mode = mode_type,
            }).sanitize();

            if (comptime coord_space == CoordSpace.clip_px_leng) {
                shaderops.fillTexClipScal(
                    N,
                    T,
                    C,
                    samp_cfg,
                    ctx_shade,
                    interp,
                    shader_buf,
                    shader,
                    spx_img_scratch,
                );
            } else {
                shaderops.fillTexPerspScal(
                    N,
                    T,
                    C,
                    samp_cfg,
                    ctx_shade,
                    interp,
                    shader_buf,
                    shader,
                    spx_img_scratch,
                );
            }
        },
    }
}

// --------------------------------------------------------------------------------------
// Function Shader
// --------------------------------------------------------------------------------------

pub inline fn completeFuncHit(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    base: meshhit.MeshHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.FuncPrepared,
) meshhit.MeshHit(N) {
    const selection = shader.hit_geometry.selection;
    if (selection.count() == 0) return base;
    var hit = base;
    if (selection.contains(.coords_ref)) {
        hit.coords_ref = meshhit.interpCoords(N, coord_space, &shader_buf.func_coords, base);
    }
    if (selection.contains(.coords_def)) {
        hit.coords_def = meshhit.interpCoords(N, coord_space, &shader_buf.func_coords, base);
    }
    if (selection.contains(.surf_norm)) {
        hit.surf_norm = meshhit.interpCoords(N, .clip_px_leng, &shader_buf.normals, base);
    }
    return hit;
}

pub inline fn completeFuncHitSIMD(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    mask: VecSB,
    weights: [N]VecSF,
    nodes_inv_z: [N]VecSF,
    subpx_z: VecSF,
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.FuncPrepared,
) meshhit.MeshHitGeomSIMD {
    const selection = shader.hit_geometry.selection;
    if (selection.count() == 0) return .{};
    var hit: meshhit.MeshHitGeomSIMD = .{};
    if (selection.contains(.coords_ref)) {
        hit.coords_ref = meshhit.interpCoordsSIMD(
            N,
            coord_space,
            &shader_buf.func_coords,
            mask,
            weights,
            nodes_inv_z,
            subpx_z,
        );
    }
    if (selection.contains(.coords_def)) {
        hit.coords_def = meshhit.interpCoordsSIMD(
            N,
            coord_space,
            &shader_buf.func_coords,
            mask,
            weights,
            nodes_inv_z,
            subpx_z,
        );
    }
    if (selection.contains(.surf_norm)) {
        hit.surf_norm = meshhit.interpCoordsSIMD(
            N,
            .clip_px_leng,
            &shader_buf.normals,
            mask,
            weights,
            nodes_inv_z,
            subpx_z,
        );
    }
    return hit;
}

pub inline fn shadeFuncScalComm(
    comptime N: usize,
    comptime C: usize,
    comptime coord_space: CoordSpace,
    ctx_shade: shaderops.ShadeContext,
    interp: meshhit.MeshHit(N),
    shader_buf: *const shaderops.LocalShaderBuff(N),
    shader: *const shaderops.FuncPrepared,
    ctx_report: anytype,
    spx_img_scratch: *MatSlice(F),
) void {
    _ = ctx_report;
    _ = ctx_report;

    if (comptime coord_space == CoordSpace.clip_px_leng) {
        shaderops.fillFuncClipScal(
            N,
            C,
            ctx_shade,
            interp,
            shader_buf,
            shader,
            spx_img_scratch,
        );
    } else {
        shaderops.fillFuncPerspScal(
            N,
            C,
            ctx_shade,
            interp,
            shader_buf,
            shader,
            spx_img_scratch,
        );
    }
}

test "direct function hit completion shares world coordinates and normals" {
    const N = 3;
    const tol: F = if (F == f32) 1e-5 else 1e-12;
    var buf: shaderops.LocalShaderBuff(N) = .{};
    buf.func_coords = .{ 1, 3, 5, 2, 4, 6, 7, 8, 9 };
    buf.normals = .{ 0, 0, 0, 0, 0, 0, 1, 0, 1 };
    var selection = meshhit.MeshHitSelection.initEmpty();
    selection.insert(.coords_ref);
    selection.insert(.surf_norm);
    const shader = shaderops.FuncPrepared{
        .elem_uvs = null,
        .hit_geometry = .{ .selection = selection },
        .coord_mode = .world_reference,
        .builtin = .lambertian_normal_z,
        .needs_normal = true,
    };
    const base: meshhit.MeshHit(N) = .{
        .weights = .{ 0.2, 0.3, 0.5 },
        .nodes_inv_z = .{ 1, 2, 4 },
        .sub_pixel_z = 0.5,
        .xi = 0.3,
        .eta = 0.5,
    };
    const scalar = completeFuncHit(N, .raster, base, &buf, &shader);
    try std.testing.expectApproxEqAbs(@as(F, 6), scalar.coords_ref.?[0], tol);
    try std.testing.expectApproxEqAbs(@as(F, 0.7), scalar.surf_norm.?[2], tol);
    try std.testing.expect(scalar.coords_def == null);

    const v_weights = [N]VecSF{ @splat(0.2), @splat(0.3), @splat(0.5) };
    const v_inv_z = [N]VecSF{ @splat(1), @splat(2), @splat(4) };
    const vector = completeFuncHitSIMD(
        N,
        .raster,
        @splat(true),
        v_weights,
        v_inv_z,
        @splat(0.5),
        &buf,
        &shader,
    );
    try std.testing.expectApproxEqAbs(@as(F, 6), vector.coords_ref.?[0][0], tol);
    try std.testing.expectApproxEqAbs(@as(F, 0.7), vector.surf_norm.?[2][0], tol);
    try std.testing.expect(vector.coords_def == null);
}
