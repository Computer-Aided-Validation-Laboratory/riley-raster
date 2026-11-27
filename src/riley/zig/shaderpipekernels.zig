// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

const geometrykernels = @import("geometrykernels.zig");
const matslice = @import("matslice.zig");
const shadertypes = @import("shadertypes.zig");
const std = @import("std");
const buildconfig = @import("buildconfig.zig");
const F = buildconfig.F;
const pipe_cfg = buildconfig.config.shaderpipe;
const S = buildconfig.SimdWidth;
const VecSF = buildconfig.VecSF;
const VecSB = buildconfig.VecSB;
const shaderops = @import("shaderops.zig");
const shaderfill = @import("shaderfill.zig");
const meshhit = @import("meshhit.zig");
const shaderpipe = @import("shaderpipe.zig");
const shaderkernels = @import("shaderkernels.zig");
const simdops = @import("simdops.zig");
const shaderfill_scalar = @import("shaderfill_scalar.zig");
const shaderfill_simd = @import("shaderfill_simd.zig");
const speckleops = @import("speckleops.zig");
const speckleconfig = @import("speckleconfig.zig");

pub fn LocalPipeBuff(comptime N: usize) type {
    return struct {
        stages: [pipe_cfg.max_stages]shadertypes.LocalShaderBuff(N) = undefined,
        coords_ref: [3 * N]F = undefined,
        coords_def: [3 * N]F = undefined,
        surf_norm: [3 * N]F = undefined,

        pub fn load(
            self: *@This(),
            pipe: *const shadertypes.ShaderPipePrepared,
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

            for (pipe.stages, 0..) |stage, si| {
                const source = switch (stage) {
                    .shader => |source| source,
                    else => continue,
                };
                const buf = &self.stages[si];

                switch (source.shader) {
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
                    .tex_u8 => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_u16 => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_f => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_rgb_u8 => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_rgb_u16 => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_rgb_f => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .tex_multi_f => |shader| {
                        buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .speckle => |shader| {
                        buf.loadFuncCoords(shader.elem_uvs, elem_idx * 2 * N, 2);
                    },
                    .speckle3d => {},
                    .func, .func_rgb, .func_multi => |shader| {
                        if (shader.coord_mode == .uv) {
                            buf.loadFuncCoords(shader.elem_uvs.?, elem_idx * 2 * N, 2);
                        }
                    },
                }
            }
        }

        pub inline fn completeHit(
            self: *const @This(),
            comptime coord_space: geometrykernels.CoordSpace,
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
            comptime coord_space: geometrykernels.CoordSpace,
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
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            interp: meshhit.MeshHit(N),
            pipe_buf: *const LocalBuff,
            pipe: *const shadertypes.ShaderPipePrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            const hit = pipe_buf.completeHit(coord_space, interp, pipe.hit_geometry.selection);

            var registers_out: shaderpipe.RegistersOutputScalar = .{};

            var source_values: [buildconfig.config.max_image_channels]F = @splat(0);
            var source_output = matslice.MatSlice(F).init(
                &source_values,
                buildconfig.config.max_image_channels,
                1,
            );

            var stage_ctx = ctx_shade;
            stage_ctx.scratch_idx = 0;
            stage_ctx.simd_full_vector_store_safe = false;

            for (pipe.stages, 0..) |*stage, si| {
                switch (stage.*) {
                    .shader => |*src| {
                        const count = src.channels;

                        stage_ctx.actual_fields = count;

                        shadeSource(
                            N,
                            coord_space,
                            stage_ctx,
                            hit,
                            &pipe_buf.stages[si],
                            &src.shader,
                            &source_output,
                        );

                        for (0..count) |ch| {
                            var dest = src.register_dest;
                            dest.index += @intCast(ch);
                            registers_out.set(dest, source_values[ch]);
                        }
                    },
                    .grey_to_emissivity => |m| {
                        const grey = std.math.clamp((registers_out.get(m.register_source) - m.greylevel_at_black) /
                            m.greylevel_range, 0, 1);
                        registers_out.set(
                            m.register_dest,
                            m.emissivity_at_black + grey * m.emissivity_range,
                        );
                    },
                    .clamp => |c| {
                        const clamped = std.math.clamp(
                            registers_out.get(c.register_source),
                            c.lower,
                            c.upper,
                        );
                        registers_out.set(c.register_dest, clamped);
                    },
                    .affine_map => |m| m.apply(&registers_out),
                    .lut_map => |m| m.apply(&registers_out, true),
                    .blend => |m| m.apply(&registers_out),
                    .normalise => |m| m.apply(&registers_out),
                }
            }

            var resolved: [buildconfig.config.max_image_channels]F = undefined;
            pipe.resolver.evaluate(&registers_out, pipe.constants, pipe.channels, &resolved);

            for (0..pipe.channels) |ch| {
                const idx = ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx;
                spx_image_scratch.slice[idx] = resolved[ch];
            }
        }

        pub fn shadeSIMD(
            comptime coord_space: geometrykernels.CoordSpace,
            ctx_shade: shadertypes.ShadeContext,
            v_mask_active: VecSB,
            v_weights: [N]VecSF,
            v_xi: VecSF,
            v_eta: VecSF,
            v_nodes_inv_z: [N]VecSF,
            v_subpx_z: VecSF,
            pipe_buf: *const LocalBuff,
            pipe: *const shadertypes.ShaderPipePrepared,
            spx_image_scratch: *matslice.MatSlice(F),
        ) void {
            const hit = pipe_buf.completeHitSIMD(
                coord_space,
                v_mask_active,
                v_weights,
                v_nodes_inv_z,
                v_subpx_z,
                pipe.hit_geometry.selection,
            );

            var registers_out: shaderpipe.RegistersOutputSIMD = .{};
            var stage_ctx = ctx_shade;

            for (pipe.stages, 0..) |*stage, si| {
                switch (stage.*) {
                    .shader => |*src| {
                        const count = src.channels;
                        stage_ctx.actual_fields = count;
                        var source_values: shaderfill.VectorSink(buildconfig.config.max_image_channels) = .{};
                        shadeSourceSIMD(
                            N,
                            coord_space,
                            stage_ctx,
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
                            var dest = src.register_dest;
                            dest.index += @intCast(ch);
                            registers_out.set(dest, source_values.values[ch]);
                        }
                    },
                    .grey_to_emissivity => |m| {
                        const src_val = registers_out.get(m.register_source);
                        const gb = @as(VecSF, @splat(m.greylevel_at_black));
                        const gw_gb = @as(VecSF, @splat(m.greylevel_range));
                        const raw_grey = (src_val - gb) / gw_gb;
                        const one = @as(VecSF, @splat(1));
                        const zero = @as(VecSF, @splat(0));
                        const grey = @min(one, @max(zero, raw_grey));
                        const blk_splat = @as(VecSF, @splat(m.emissivity_at_black));
                        const w_b = @as(VecSF, @splat(m.emissivity_range));
                        registers_out.set(m.register_dest, blk_splat + grey * w_b);
                    },
                    .clamp => |c| {
                        const upper = @as(VecSF, @splat(c.upper));
                        const lower = @as(VecSF, @splat(c.lower));
                        const clamped = @min(upper, @max(lower, registers_out.get(c.register_source)));
                        registers_out.set(c.register_dest, clamped);
                    },
                    .affine_map => |m| m.apply(&registers_out),
                    .lut_map => |m| m.apply(&registers_out, v_mask_active),
                    .blend => |m| m.apply(&registers_out),
                    .normalise => |m| m.apply(&registers_out),
                }
            }

            var resolved: [buildconfig.config.max_image_channels]VecSF = undefined;
            pipe.resolver.evaluate(&registers_out, pipe.constants, pipe.channels, &resolved);
            for (0..pipe.channels) |ch| {
                const idx = ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx;
                if (!ctx_shade.simd_full_vector_store_safe) {
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

fn shadeSource(
    comptime N: usize,
    comptime coord_space: geometrykernels.CoordSpace,
    ctx: shadertypes.ShadeContext,
    interp: meshhit.MeshHit(N),
    buf: *const shadertypes.LocalShaderBuff(N),
    source: *const shadertypes.PipeSourcePrepared,
    scratch: *matslice.MatSlice(F),
) void {
    switch (source.*) {
        .speckle => |*s| {
            scratch.slice[ctx.scratch_idx] = shaderfill_scalar.evalSpeckleScal(
                N,
                coord_space,
                interp.getRasterHit(),
                buf,
                s,
                samplePipeSpeckleScal,
            );
        },
        .speckle3d => |*s| {
            scratch.slice[ctx.scratch_idx] = shaderfill_scalar.evalSpeckle3D(interp.coords_ref.?, s);
        },
        .nodal => |*s| {
            shaderkernels.NodalKernel(N).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_multi_f => |*s| {
            shaderkernels.TexMultiKernel(N, F).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_u8 => |*s| {
            shaderkernels.TexKernel(N, u8, 1).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_u16 => |*s| {
            shaderkernels.TexKernel(N, u16, 1).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_f => |*s| {
            shaderkernels.TexKernel(N, F, 1).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_rgb_u8 => |*s| {
            shaderkernels.TexKernel(N, u8, 3).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_rgb_u16 => |*s| {
            shaderkernels.TexKernel(N, u16, 3).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .tex_rgb_f => |*s| {
            shaderkernels.TexKernel(N, F, 3).shade(
                coord_space,
                ctx,
                interp.getRasterHit(),
                buf,
                s,
                scratch,
            );
        },
        .func => |*s| {
            shaderkernels.FuncKernel(N, 1).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                scratch,
            );
        },
        .func_rgb => |*s| {
            shaderkernels.FuncKernel(N, 3).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                scratch,
            );
        },
        .func_multi => |*s| {
            shaderkernels.FuncKernel(N, 0).shade(
                coord_space,
                ctx,
                interp,
                buf,
                s,
                scratch,
            );
        },
    }
}

fn shadeSourceSIMD(
    comptime N: usize,
    comptime coord_space: geometrykernels.CoordSpace,
    ctx: shadertypes.ShadeContext,
    mask: VecSB,
    weights: [N]VecSF,
    xi: VecSF,
    eta: VecSF,
    inv_z: [N]VecSF,
    subpx_z: VecSF,
    hit: meshhit.MeshHitGeomSIMD,
    buf: *const shadertypes.LocalShaderBuff(N),
    source: *const shadertypes.PipeSourcePrepared,
    sink: anytype,
) void {
    switch (source.*) {
        .speckle => |*s| {
            const value = shaderfill_simd.evalSpeckleSIMD(
                N,
                coord_space,
                mask,
                weights,
                inv_z,
                subpx_z,
                buf,
                s,
                samplePipeSpeckleSIMD,
            );
            sink.store(0, mask, value);
        },
        .speckle3d => |*s| {
            sink.store(0, mask, shaderfill_simd.evalSpeckle3DSIMD(hit.coords_ref.?, mask, s));
        },
        .nodal => |*s| {
            shaderkernels.NodalKernel(N).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexMultiKernel(N, F).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, u8, 1).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, u16, 1).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, F, 1).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, u8, 3).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, u16, 3).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.TexKernel(N, F, 3).shadeSIMDTo(
                coord_space,
                ctx,
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
            shaderkernels.FuncKernel(N, 1).shadeSIMDToHit(
                coord_space,
                ctx,
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
            shaderkernels.FuncKernel(N, 3).shadeSIMDToHit(
                coord_space,
                ctx,
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
            shaderkernels.FuncKernel(N, 0).shadeSIMDToHit(
                coord_space,
                ctx,
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

// Keep dispatch on the speckle path without adding state to other pipes. The index is
// immutable for the stage; SIMD dispatches the entire packet, not individual lanes.
fn samplePipeSpeckleScal(u: F, v: F, resources: *const speckleops.Resources) F {
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
    return switch (resources.kernel_index.?) {
        inline 0...speckleops.kernel_configs.len - 1 => |index| speckleops.Kernel(index).sampleScal(u, v, resources),
        else => unreachable,
    };
}

fn samplePipeSpeckleSIMD(u: VecSF, v: VecSF, active: VecSB, resources: *const speckleops.Resources) VecSF {
    @setEvalBranchQuota(buildconfig.comptime_eval_branch_quota);
    return switch (resources.kernel_index.?) {
        inline 0...speckleops.kernel_configs.len - 1 => |index| speckleops.Kernel(index).sampleSIMD(u, v, active, resources),
        else => unreachable,
    };
}

// --------------------------------------------------------------------------------------
// Tests
// --------------------------------------------------------------------------------------

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
    var selection = meshhit.MeshHitSelection.empty;
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

test "speckle pipe dispatch preserves hit geometry and exact unclamped source values" {
    const N = 3;
    const cameraprojops = @import("cameraprojops.zig");
    const cameratypes = @import("cameratypes.zig");
    const meshpipeline = @import("meshpipeline.zig");
    const meshtypes = @import("meshtypes.zig");
    const ndarray = @import("ndarray.zig");
    const parachunkexec = @import("parachunkexec.zig");
    const rasterconfig = @import("rasterconfig.zig");
    const rendergroups = @import("rendergroups.zig");
    const report = @import("report.zig");
    const rotation = @import("rotation.zig");
    const speckleparams = @import("speckleparams.zig");
    const validatearrays = @import("validatearrays.zig");
    const validateinput = @import("validateinput.zig");
    const vecstack = @import("vecstack.zig");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var uv_data = [_]F{ 0, 0, 1, 0, 0, 1 };
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_data, &.{ N, 2 });
    const registers = [_]shaderpipe.Register{
        .{ .kind = .channel, .index = 0 },
        .{ .kind = .channel, .index = 1 },
        .{ .kind = .channel, .index = 2 },
        .{ .kind = .constant, .index = 0 },
        .{ .kind = .constant, .index = 1 },
        .{ .kind = .constant, .index = 2 },
    };
    // Both hits stay near the UV origin, outside the hard disks and below the Perlin threshold.
    const params = [_]speckleparams.SpeckleParams{
        .{ .disk = .{ .coverage = 0.05, .radius = 8, .background = 0.25 } },
        .{ .perlin = .{ .cell_size = 64, .threshold = 0.5, .transition_width = 0, .background = 0.75 } },
    };
    var stages: [3]shadertypes.ShaderPipeStageInput = undefined;
    for (stages[0..2], registers[0..2], params) |*stage, dest, param| {
        stage.* = .{ .shader = .{
            .shader = .{ .speckle = .{
                .uvs = uvs,
                .params = param,
                .output_gain = 2,
                .output_offset = 0.5,
                .bits = null,
                .scaling = .{ .fixed = .{ -0.25, 0.25 } },
            } },
            .register_dest = dest,
        } };
    }
    stages[2] = .{ .shader = .{
        .shader = .{ .func = .{
            .coord_mode = .world_reference,
            .builtin = .linear,
            .params = .{ .settings = .{ .linear = .{ .coeffs = .{ 0, 2, 0 } } } },
        } },
        .register_dest = registers[2],
    } };
    // Distinct weights and source values make the result sensitive to destination swaps.
    const operations = [_]shaderpipe.ResolverOp{
        .{ .load = registers[0] },
        .{ .load = registers[1] },
        .{ .load = registers[4] },
        .multiply,
        .add,
        .{ .load = registers[2] },
        .{ .load = registers[5] },
        .multiply,
        .add,
        .{ .load = registers[3] },
        .add,
        .{ .store = 0 },
    };
    var coords = [_]F{ 2, 0, 0, 4, 0, 0, 6, 2, 0 };
    var connect = [_]usize{ 0, 1, 2 };
    const mesh: meshtypes.MeshInput = .{
        .mesh_type = .tri3,
        .coords = meshtypes.Coords.init(&coords, N),
        .connect = meshtypes.Connect.init(&connect, 1, N),
        .disp = null,
        .shaders = .{ .mono_pipe = .{
            .stages = &stages,
            .resolver = .{ .expression = .{ .operations = &operations, .constants = &.{ 0.125, 2, 4 } } },
        } },
    };
    const camera_input: cameratypes.CameraInput = .{
        .pixels_num = .{ 32, 32 },
        .pixels_size = .{ 0.25, 0.25 },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 4, 1, 4 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initSlice(&.{ 4, 1, 0 }),
        .focal_length = 4,
        .sub_sample = 1,
    };
    const config: rasterconfig.RasterConfig = .{};
    const groups = [_]rendergroups.RenderGroup{.{ .io = std.testing.io, .workers = 1 }};
    _ = try validateinput.checkRenderInps(&groups, &.{camera_input}, &.{mesh}, config, null, false, null);
    try validatearrays.checkRenderArrs(&.{mesh});
    const mesh_static = try meshpipeline.createMeshStaticFromInput(alloc, &mesh, .initOne(.mono));
    const camera = try cameraprojops.CameraPrepared.init(alloc, camera_input);
    var exec = parachunkexec.ParaChunkExecutor.init(std.testing.io, 1);
    var timing: report.GeomTimes = .{};
    const frame = try meshpipeline.prepMeshFrame(alloc, &exec, 1, &camera, config, &mesh_static, 0, &timing);
    try std.testing.expectEqual(@as(usize, 1), frame.elems_in_image);
    const pipe = frame.mesh.shaders.mono.?.pipe;
    try std.testing.expect(pipe.hit_geometry.selection.contains(.coords_ref));
    const K = PipeKernel(N);
    var buff: K.LocalBuff = .{};
    buff.load(&pipe, 0, 0);
    const ctx: shadertypes.ShadeContext = .{
        .frame_idx = 0,
        .elem_idx = 0,
        .fields_num = 1,
        .actual_fields = 1,
        .scratch_idx = 0,
        .global_subx = 0,
        .global_suby = 0,
        .simd_full_vector_store_safe = false,
    };
    const Direct = shaderkernels.SpeckleKernel(N, speckleconfig.sampleConfigIndex(
        buildconfig.enable_all_evaluators,
        .classified_binned,
    ));
    const direct = &pipe.stages[0].shader.shader.speckle;
    try std.testing.expect(direct.resources.kernel_index != pipe.stages[1].shader.shader.speckle.resources.kernel_index);
    const weighted_speckles: F = 2.5 + 2 * 4.5;
    var values: [S]F = @splat(-1);
    var output = matslice.MatSlice(F).init(&values, 1, S);
    const hit: K.Hit = .{
        .weights = .{ 0.5, 0.25, 0.25 },
        .nodes_inv_z = .{ 1, 1, 1 },
        .sub_pixel_z = 1,
        .xi = 0.25,
        .eta = 0.25,
    };
    Direct.shade(.clip_px_leng, ctx, hit.getRasterHit(), &buff.stages[0], direct, &output);
    try std.testing.expectEqual(@as(F, 2.5), values[0]);
    K.shade(.clip_px_leng, ctx, hit, &buff, &pipe, &output);
    try std.testing.expectEqual(weighted_speckles + 4 * (2 * 3.5) + 0.125, values[0]);

    if (comptime buildconfig.config.simd == .on) {
        @memset(&values, -1);
        var mask: [S]bool = undefined;
        for (&mask, 0..) |*lane, index| lane.* = index % 2 == 0;
        const weights = [N]VecSF{ @splat(0.5), @splat(0.25), @splat(0.25) };
        const inv_z = [N]VecSF{ @splat(1), @splat(2), @splat(4) };
        Direct.shadeSIMD(
            .raster,
            ctx,
            mask,
            weights,
            @splat(0.25),
            @splat(0.25),
            inv_z,
            @splat(0.5),
            &buff.stages[0],
            direct,
            &output,
        );
        for (values, mask) |value, active| {
            try std.testing.expectEqual(@as(F, if (active) 2.5 else -1), value);
        }
        @memset(&values, -1);
        K.shadeSIMD(
            .raster,
            ctx,
            mask,
            weights,
            @splat(0.25),
            @splat(0.25),
            inv_z,
            @splat(0.5),
            &buff,
            &pipe,
            &output,
        );
        for (values, mask) |value, active| {
            try std.testing.expectEqual(if (active) weighted_speckles + 4 * (2 * 4.5) + 0.125 else -1, value);
        }
    }
}
