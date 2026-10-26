// Sample-domain shader pipe. Source shaders reuse the existing FE, texture and
// function kernels; the tiny stage scratch stays on the worker stack.
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;
const cfg = buildconfig.config;
const shaderops = @import("shaderops.zig");
const meshhit = @import("meshhit.zig");
const shaderpipe = @import("shaderpipe.zig");
const shadekerns = @import("shaderkernels.zig");
const simdops = @import("simdops.zig");
const CoordSpace = @import("geometrykernels.zig").CoordSpace;
const MatSlice = @import("matslice.zig").MatSlice;

pub fn LocalPipeBuff(comptime N: usize) type {
    return struct {
        stages: [8]shaderops.LocalShaderBuff(N) = undefined,
        coords_ref: [3 * N]F = undefined,
        coords_def: [3 * N]F = undefined,
        surf_norm: [3 * N]F = undefined,

        pub fn load(
            self: *@This(),
            pipe: *const shaderops.ShaderPipePrepared,
            elem_idx: usize,
            frame_idx: usize,
        ) void {
            if (pipe.hit_geometry.coords_ref) |array| {
                const start = elem_idx * 3 * N;
                @memcpy(self.coords_ref[0 .. 3 * N], array.slice[start .. start + 3 * N]);
            }
            if (pipe.hit_geometry.coords_def) |array| {
                const start = elem_idx * 3 * N;
                @memcpy(self.coords_def[0 .. 3 * N], array.slice[start .. start + 3 * N]);
            }
            if (pipe.hit_geometry.surf_norm) |normals| {
                const start = normals.map[elem_idx] * 3 * N;
                @memcpy(self.surf_norm[0 .. 3 * N], normals.array.slice[start .. start + 3 * N]);
            }
            for (pipe.stages, 0..) |stage, si| switch (stage) {
                .source => |src| {
                    const buf = &self.stages[si];
                    switch (src.shader) {
                        .nodal => |shader| {
                            const count: u8 = if (shader.elem_field.dims.len == 3)
                                @intCast(shader.elem_field.dims[1])
                            else
                                @intCast(shader.elem_field.dims[2]);
                            const frame_dim = shader.elem_field.dims[0] - 1;
                            const idx = if (shader.elem_field.dims.len == 3)
                                shader.elem_field.getFlatIdx(&.{ elem_idx, 0, 0 })
                            else
                                shader.elem_field.getFlatIdx(&.{
                                    @min(frame_idx, frame_dim),
                                    elem_idx,
                                    0,
                                    0,
                                });
                            buf.load(shader.elem_field, idx, count);
                        },
                        inline .tex_u8,
                        .tex_u16,
                        .tex_f,
                        .tex_rgb_u8,
                        .tex_rgb_u16,
                        .tex_rgb_f,
                        .tex_multi_f,
                        => |shader| {
                            buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                        },
                        .func, .func_rgb, .func_multi => |shader| {
                            switch (shader.coord_mode) {
                                .uv => buf.loadFuncCoords(
                                    shader.elem_uvs.?,
                                    elem_idx * 2 * N,
                                    2,
                                ),
                                .world_reference, .world_deformed, .para => {},
                            }
                        },
                    }
                },
                else => {},
            };
        }

        pub inline fn completeHit(
            self: *const @This(),
            comptime coord_space: CoordSpace,
            base: meshhit.MeshHit(N),
            selection: meshhit.MeshHitSelection,
        ) meshhit.MeshHit(N) {
            if (selection.count() == 0) return base;
            var hit = base;
            if (selection.contains(.coords_ref)) {
                hit.coords_ref = meshhit.interpCoords(N, coord_space, &self.coords_ref, base);
            }
            if (selection.contains(.coords_def)) {
                hit.coords_def = meshhit.interpCoords(N, coord_space, &self.coords_def, base);
            }
            if (selection.contains(.surf_norm)) {
                hit.surf_norm = meshhit.interpCoords(N, .clip_px_leng, &self.surf_norm, base);
            }
            return hit;
        }

        pub inline fn completeHitSIMD(
            self: *const @This(),
            comptime coord_space: CoordSpace,
            mask: VecSB,
            weights: [N]VecSF,
            nodes_inv_z: [N]VecSF,
            subpx_z: VecSF,
            selection: meshhit.MeshHitSelection,
        ) meshhit.MeshHitGeomSIMD {
            if (selection.count() == 0) return .{};
            var hit: meshhit.MeshHitGeomSIMD = .{};
            if (selection.contains(.coords_ref)) {
                hit.coords_ref = meshhit.interpCoordsSIMD(
                    N,
                    coord_space,
                    &self.coords_ref,
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
                    &self.coords_def,
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
                    &self.surf_norm,
                    mask,
                    weights,
                    nodes_inv_z,
                    subpx_z,
                );
            }
            return hit;
        }
    };
}

pub fn PipeKernel(comptime N: usize) type {
    return struct {
        pub const LocalBuff = LocalPipeBuff(N);
        pub const Hit = meshhit.MeshHit(N);

        pub fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: meshhit.MeshHit(N),
            pipe_buf: *const LocalBuff,
            pipe: *const shaderops.ShaderPipePrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
            const hit = pipe_buf.completeHit(coord_space, interp, pipe.hit_geometry.selection);
            var outputs: shaderpipe.ScalarOutputs = .{};
            var temporary: [cfg.max_nodal_fields]F = @splat(0);
            var temp_mat = MatSlice(F).init(&temporary, cfg.max_nodal_fields, 1);
            var stage_ctx = ctx_shade;
            stage_ctx.scratch_idx = 0;
            stage_ctx.exclusive_subpx_target = true;

            for (pipe.stages, 0..) |*stage, si| switch (stage.*) {
                .source => |*src| {
                    const count = sourceChannels(src.shader);
                    stage_ctx.actual_fields = count;
                    shadeSource(
                        N,
                        coord_space,
                        stage_ctx,
                        hit,
                        &pipe_buf.stages[si],
                        &src.shader,
                        ctx_report,
                        &temp_mat,
                    );
                    for (0..count) |ch| {
                        var dest = src.destination;
                        dest.index += @intCast(ch);
                        outputs.set(dest, temporary[ch]);
                    }
                },
                .grey_to_emissivity => |m| {
                    const grey = std.math.clamp((outputs.get(m.source) - m.grey_black) /
                        (m.grey_white - m.grey_black), 0, 1);
                    outputs.set(m.destination, m.black + grey * (m.white - m.black));
                },
                .clamp => |c| {
                    const clamped = std.math.clamp(
                        outputs.get(c.source),
                        c.lower,
                        c.upper,
                    );
                    outputs.set(c.destination, clamped);
                },
                .affine_map => |m| m.apply(&outputs),
                .lut_map => |m| m.apply(&outputs, true),
                .blend => |m| m.apply(&outputs),
                .normalise => |m| m.apply(&outputs),
            };

            var resolved: [shaderpipe.max_channels]F = undefined;
            pipe.resolver.evaluate(&outputs, pipe.constants, pipe.channels, &resolved);
            for (0..pipe.channels) |ch| {
                const idx = ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx;
                spx_image_scratch.slice[idx] = resolved[ch];
            }
        }

        pub fn shadeSIMD(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            ctx_report: anytype,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            pipe_buf: *const LocalBuff,
            pipe: *const shaderops.ShaderPipePrepared,
            spx_image_scratch: *MatSlice(F),
        ) void {
            const hit = pipe_buf.completeHitSIMD(
                coord_space,
                v_mask_active,
                v_weights,
                v_nodes_inv_z,
                v_subpx_z,
                pipe.hit_geometry.selection,
            );
            var outputs: shaderpipe.VectorOutputs = .{};
            var stage_ctx = ctx_shade;

            for (pipe.stages, 0..) |*stage, si| switch (stage.*) {
                .source => |*src| {
                    const count = sourceChannels(src.shader);
                    stage_ctx.actual_fields = count;
                    var source_values: shaderops.VectorSink(cfg.max_nodal_fields) = .{};
                    shadeSourceSIMD(
                        N,
                        coord_space,
                        stage_ctx,
                        ctx_report,
                        v_mask_active,
                        v_weights,
                        v_xi,
                        v_eta,
                        v_nodes_inv_z,
                        v_subpx_z,
                        hit,
                        &pipe_buf.stages[si],
                        &src.shader,
                        &source_values,
                    );
                    for (0..count) |ch| {
                        var dest = src.destination;
                        dest.index += @intCast(ch);
                        outputs.set(dest, source_values.values[ch]);
                    }
                },
                .grey_to_emissivity => |m| {
                    const src_val = outputs.get(m.source);
                    const gb = @as(VecSF, @splat(m.grey_black));
                    const gw_gb = @as(VecSF, @splat(m.grey_white - m.grey_black));
                    const raw_grey = (src_val - gb) / gw_gb;
                    const one = @as(VecSF, @splat(1));
                    const zero = @as(VecSF, @splat(0));
                    const grey = @min(one, @max(zero, raw_grey));
                    const blk_splat = @as(VecSF, @splat(m.black));
                    const w_b = @as(VecSF, @splat(m.white - m.black));
                    outputs.set(m.destination, blk_splat + grey * w_b);
                },
                .clamp => |c| {
                    const upper = @as(VecSF, @splat(c.upper));
                    const lower = @as(VecSF, @splat(c.lower));
                    const clamped = @min(upper, @max(lower, outputs.get(c.source)));
                    outputs.set(c.destination, clamped);
                },
                .affine_map => |m| m.apply(&outputs),
                .lut_map => |m| m.apply(&outputs, v_mask_active),
                .blend => |m| m.apply(&outputs),
                .normalise => |m| m.apply(&outputs),
            };

            var resolved: [shaderpipe.max_channels]VecSF = undefined;
            pipe.resolver.evaluate(&outputs, pipe.constants, pipe.channels, &resolved);
            for (0..pipe.channels) |ch| {
                const idx = ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx;
                if (ctx_shade.exclusive_subpx_target) {
                    const lanes: [S]F = resolved[ch];
                    const mask: [S]bool = v_mask_active;
                    inline for (0..S) |lane| if (mask[lane]) {
                        spx_image_scratch.slice[idx + lane] = lanes[lane];
                    };
                } else {
                    simdops.storeMaskedVecSF(
                        spx_image_scratch.slice,
                        idx,
                        v_mask_active,
                        resolved[ch],
                    );
                }
            }
        }
    };
}

fn sourceChannels(source: shaderops.ShaderDirectPrepared) u8 {
    return switch (source) {
        .nodal => |n| if (n.elem_field.dims.len == 3)
            @intCast(n.elem_field.dims[1])
        else
            @intCast(n.elem_field.dims[2]),
        .tex_rgb_u8, .tex_rgb_u16, .tex_rgb_f, .func_rgb => 3,
        .tex_multi_f => |multi| @intCast(multi.tex.array.dims[0]),
        .func_multi => |multi| @intCast(multi.channels.len),
        else => 1,
    };
}

fn shadeSource(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    ctx: shaderops.ShadeContext,
    interp: meshhit.MeshHit(N),
    buf: *const shaderops.LocalShaderBuff(N),
    source: *const shaderops.ShaderDirectPrepared,
    ctx_report: anytype,
    scratch: *MatSlice(F),
) void {
    switch (source.*) {
        .nodal => |*s| {
            shadekerns.NodalKernel(N).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_multi_f => |*s| {
            shadekerns.TexMultiKernel(N, F).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_u8 => |*s| {
            shadekerns.TexKernel(N, u8, 1).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_u16 => |*s| {
            shadekerns.TexKernel(N, u16, 1).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_f => |*s| {
            shadekerns.TexKernel(N, F, 1).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_rgb_u8 => |*s| {
            shadekerns.TexKernel(N, u8, 3).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_rgb_u16 => |*s| {
            shadekerns.TexKernel(N, u16, 3).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .tex_rgb_f => |*s| {
            shadekerns.TexKernel(N, F, 3).shade(
                coord_space,
                ctx,
                interp.core(),
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .func => |*s| {
            shadekerns.FuncKernel(N, 1).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .func_multi => |*s| {
            shadekerns.FuncKernel(N, 0).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
        .func_rgb => |*s| {
            shadekerns.FuncKernel(N, 3).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                ctx_report,
                scratch,
            );
        },
    }
}

fn shadeSourceSIMD(
    comptime N: usize,
    comptime coord_space: CoordSpace,
    ctx: shaderops.ShadeContext,
    ctx_report: anytype,
    mask: VecSB,
    weights: [N]VecSF,
    xi: VecSF,
    eta: VecSF,
    inv_z: [N]VecSF,
    subpx_z: VecSF,
    hit: meshhit.MeshHitGeomSIMD,
    buf: *const shaderops.LocalShaderBuff(N),
    source: *const shaderops.ShaderDirectPrepared,
    sink: anytype,
) void {
    switch (source.*) {
        .nodal => |*s| {
            shadekerns.NodalKernel(N).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_multi_f => |*s| {
            shadekerns.TexMultiKernel(N, F).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_u8 => |*s| {
            shadekerns.TexKernel(N, u8, 1).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_u16 => |*s| {
            shadekerns.TexKernel(N, u16, 1).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_f => |*s| {
            shadekerns.TexKernel(N, F, 1).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_rgb_u8 => |*s| {
            shadekerns.TexKernel(N, u8, 3).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_rgb_u16 => |*s| {
            shadekerns.TexKernel(N, u16, 3).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .tex_rgb_f => |*s| {
            shadekerns.TexKernel(N, F, 3).shadeSIMDTo(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                buf,
                s,
                sink,
            );
        },
        .func => |*s| {
            shadekerns.FuncKernel(N, 1).shadeSIMDToHit(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                hit,
                buf,
                s,
                sink,
            );
        },
        .func_multi => |*s| {
            shadekerns.FuncKernel(N, 0).shadeSIMDToHit(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                hit,
                buf,
                s,
                sink,
            );
        },
        .func_rgb => |*s| {
            shadekerns.FuncKernel(N, 3).shadeSIMDToHit(
                coord_space,
                ctx,
                ctx_report,
                mask,
                weights,
                xi,
                eta,
                inv_z,
                subpx_z,
                hit,
                buf,
                s,
                sink,
            );
        },
    }
}

test "MeshHit shares selected geometry with scalar and SIMD stages" {
    const N = 3;
    const test_tol: F = if (F == f32) 1e-5 else 1e-12;
    var buff: LocalPipeBuff(N) = .{};
    buff.coords_ref = .{ 1, 3, 5, 2, 4, 6, 7, 8, 9 };
    buff.coords_def = .{ 2, 4, 6, 3, 5, 7, 8, 9, 10 };
    buff.surf_norm = .{ 0, 0, 0, 0, 0, 0, 1, 0, 1 };
    const base: meshhit.MeshHit(N) = .{
        .weights = .{ 0.2, 0.3, 0.5 },
        .nodes_inv_z = .{ 1, 2, 4 },
        .sub_pixel_z = 0.5,
        .xi = 0.3,
        .eta = 0.5,
    };
    var selection = meshhit.MeshHitSelection.initEmpty();
    const empty_hit = buff.completeHit(.raster, base, selection);
    try std.testing.expect(empty_hit.coords_ref == null);
    try std.testing.expect(empty_hit.coords_def == null);
    try std.testing.expect(empty_hit.surf_norm == null);

    selection.insert(.coords_ref);
    selection.insert(.coords_def);
    selection.insert(.surf_norm);
    const clip_hit = buff.completeHit(.clip_px_leng, base, selection);
    try std.testing.expectApproxEqAbs(@as(F, 3.6), clip_hit.coords_ref.?[0], test_tol);
    try std.testing.expectApproxEqAbs(@as(F, 4.6), clip_hit.coords_def.?[0], test_tol);
    try std.testing.expectApproxEqAbs(@as(F, 0.7), clip_hit.surf_norm.?[2], test_tol);
    const raster_hit = buff.completeHit(.raster, base, selection);
    try std.testing.expectApproxEqAbs(@as(F, 6.0), raster_hit.coords_ref.?[0], test_tol);
    try std.testing.expectApproxEqAbs(@as(F, 0.7), raster_hit.surf_norm.?[2], test_tol);

    const v_weights = [N]VecSF{ @splat(0.2), @splat(0.3), @splat(0.5) };
    const v_inv_z = [N]VecSF{ @splat(1), @splat(2), @splat(4) };
    const v_hit = buff.completeHitSIMD(
        .raster,
        @splat(true),
        v_weights,
        v_inv_z,
        @splat(0.5),
        selection,
    );
    try std.testing.expectApproxEqAbs(raster_hit.coords_ref.?[0], v_hit.coords_ref.?[0][0], test_tol);
    try std.testing.expectApproxEqAbs(raster_hit.coords_def.?[1], v_hit.coords_def.?[1][0], test_tol);
    try std.testing.expectApproxEqAbs(raster_hit.surf_norm.?[2], v_hit.surf_norm.?[2][0], test_tol);
}
