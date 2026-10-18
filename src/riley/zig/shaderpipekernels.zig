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
const shaderpipe = @import("shaderpipe.zig");
const shadekerns = @import("shaderkernels.zig");
const simdops = @import("simdops.zig");
const CoordSpace = @import("geometrykernels.zig").CoordSpace;
const MatSlice = @import("matslice.zig").MatSlice;

pub fn LocalPipeBuff(comptime N: usize) type {
    return struct {
        stages: [8]shaderops.LocalShaderBuff(N) = undefined,

        pub fn load(self: *@This(), pipe: *const shaderops.PipePrepared, elem_idx: usize, frame_idx: usize) void {
            for (pipe.stages, 0..) |stage, si| switch (stage) {
                .source => |src| {
                    const buf = &self.stages[si];
                    switch (src.shader) {
                        .nodal => |shader| {
                            const count: u8 = if (shader.elem_field.dims.len == 3)
                                @intCast(shader.elem_field.dims[1])
                            else
                                @intCast(shader.elem_field.dims[2]);
                            const idx = if (shader.elem_field.dims.len == 3)
                                shader.elem_field.getFlatIdx(&.{ elem_idx, 0, 0 })
                            else
                                shader.elem_field.getFlatIdx(&.{ @min(frame_idx, shader.elem_field.dims[0] - 1), elem_idx, 0, 0 });
                            buf.load(shader.elem_field, idx, count);
                            if (shader.elem_normals) |normals| buf.loadNormals(normals.array, normals.map[elem_idx] * 3 * N);
                        },
                        inline .tex_u8, .tex_u16, .tex_f, .tex_rgb_u8, .tex_rgb_u16, .tex_rgb_f => |shader| {
                            buf.load(shader.elem_uvs, elem_idx * 2 * N, 2);
                            if (shader.elem_normals) |normals| buf.loadNormals(normals.array, normals.map[elem_idx] * 3 * N);
                        },
                        .func, .func_rgb => |shader| {
                            switch (shader.coord_mode) {
                                .uv => buf.loadFuncCoords(shader.elem_uvs.?, elem_idx * 2 * N, 2),
                                .world_reference => buf.loadFuncCoords(shader.elem_world_ref.?, elem_idx * 3 * N, 3),
                                .world_deformed => buf.loadFuncCoords(shader.elem_world_def.?, elem_idx * 3 * N, 3),
                                .para => {},
                            }
                            if (shader.elem_normals) |normals| buf.loadNormals(normals.array, normals.map[elem_idx] * 3 * N);
                        },
                    }
                },
                else => {},
            };
        }
    };
}

pub fn PipeKernel(comptime N: usize) type {
    return struct {
        pub const LocalBuff = LocalPipeBuff(N);

        pub fn shade(
            comptime coord_space: CoordSpace,
            ctx_shade: shaderops.ShadeContext,
            interp: shaderops.InterpData(N),
            pipe_buf: *const LocalBuff,
            pipe: *const shaderops.PipePrepared,
            ctx_report: anytype,
            spx_image_scratch: *MatSlice(F),
        ) void {
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
                    shadeSource(N, coord_space, stage_ctx, interp, &pipe_buf.stages[si], &src.shader, ctx_report, &temp_mat);
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
                .clamp => |c| outputs.set(c.destination, std.math.clamp(outputs.get(c.source), c.lower, c.upper)),
            };

            var resolved: [shaderpipe.max_channels]F = undefined;
            pipe.resolver.evaluate(&outputs, pipe.constants, pipe.channels, &resolved);
            for (0..pipe.channels) |ch| {
                spx_image_scratch.slice[ch * spx_image_scratch.cols_num + ctx_shade.scratch_idx] = resolved[ch];
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
            pipe: *const shaderops.PipePrepared,
            spx_image_scratch: *MatSlice(F),
        ) void {
            var outputs: shaderpipe.VectorOutputs = .{};
            var temporary: [cfg.max_nodal_fields * S]F = @splat(0);
            var temp_mat = MatSlice(F).init(&temporary, cfg.max_nodal_fields, S);
            var stage_ctx = ctx_shade;
            stage_ctx.scratch_idx = 0;
            stage_ctx.exclusive_subpx_target = true;

            for (pipe.stages, 0..) |*stage, si| switch (stage.*) {
                .source => |*src| {
                    const count = sourceChannels(src.shader);
                    stage_ctx.actual_fields = count;
                    shadeSourceSIMD(N, coord_space, stage_ctx, ctx_report, v_mask_active, v_weights, v_xi, v_eta, v_nodes_inv_z, v_subpx_z, &pipe_buf.stages[si], &src.shader, &temp_mat);
                    for (0..count) |ch| {
                        var lanes: [S]F = undefined;
                        @memcpy(&lanes, temporary[ch * S ..][0..S]);
                        var dest = src.destination;
                        dest.index += @intCast(ch);
                        outputs.set(dest, @bitCast(lanes));
                    }
                },
                .grey_to_emissivity => |m| {
                    const grey = @min(@as(VecSF, @splat(1)), @max(@as(VecSF, @splat(0)), (outputs.get(m.source) - @as(VecSF, @splat(m.grey_black))) /
                        @as(VecSF, @splat(m.grey_white - m.grey_black))));
                    outputs.set(m.destination, @as(VecSF, @splat(m.black)) +
                        grey * @as(VecSF, @splat(m.white - m.black)));
                },
                .clamp => |c| outputs.set(c.destination, @min(@as(VecSF, @splat(c.upper)), @max(@as(VecSF, @splat(c.lower)), outputs.get(c.source)))),
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
                    simdops.storeMaskedVecSF(spx_image_scratch.slice, idx, v_mask_active, resolved[ch]);
                }
            }
        }
    };
}

fn sourceChannels(source: shaderops.ShaderPrepared) u8 {
    return switch (source) {
        .nodal => |n| if (n.elem_field.dims.len == 3) @intCast(n.elem_field.dims[1]) else @intCast(n.elem_field.dims[2]),
        .tex_rgb_u8, .tex_rgb_u16, .tex_rgb_f, .func_rgb => 3,
        else => 1,
    };
}

fn shadeSource(comptime N: usize, comptime coord_space: CoordSpace, ctx: shaderops.ShadeContext, interp: shaderops.InterpData(N), buf: *const shaderops.LocalShaderBuff(N), source: *const shaderops.ShaderPrepared, ctx_report: anytype, scratch: *MatSlice(F)) void {
    switch (source.*) {
        .nodal => |*s| shadekerns.NodalKernel(N).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_u8 => |*s| shadekerns.TexKernel(N, u8, 1).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_u16 => |*s| shadekerns.TexKernel(N, u16, 1).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_f => |*s| shadekerns.TexKernel(N, F, 1).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_rgb_u8 => |*s| shadekerns.TexKernel(N, u8, 3).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_rgb_u16 => |*s| shadekerns.TexKernel(N, u16, 3).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .tex_rgb_f => |*s| shadekerns.TexKernel(N, F, 3).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .func => |*s| shadekerns.FuncKernel(N, 1).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
        .func_rgb => |*s| shadekerns.FuncKernel(N, 3).shade(coord_space, ctx, interp, buf, s, ctx_report, scratch),
    }
}

fn shadeSourceSIMD(comptime N: usize, comptime coord_space: CoordSpace, ctx: shaderops.ShadeContext, ctx_report: anytype, mask: VecSB, weights: [N]VecSF, xi: VecSF, eta: VecSF, inv_z: [N]VecSF, subpx_z: VecSF, buf: *const shaderops.LocalShaderBuff(N), source: *const shaderops.ShaderPrepared, scratch: *MatSlice(F)) void {
    switch (source.*) {
        .nodal => |*s| shadekerns.NodalKernel(N).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_u8 => |*s| shadekerns.TexKernel(N, u8, 1).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_u16 => |*s| shadekerns.TexKernel(N, u16, 1).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_f => |*s| shadekerns.TexKernel(N, F, 1).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_rgb_u8 => |*s| shadekerns.TexKernel(N, u8, 3).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_rgb_u16 => |*s| shadekerns.TexKernel(N, u16, 3).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .tex_rgb_f => |*s| shadekerns.TexKernel(N, F, 3).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .func => |*s| shadekerns.FuncKernel(N, 1).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
        .func_rgb => |*s| shadekerns.FuncKernel(N, 3).shadeSIMD(coord_space, ctx, ctx_report, mask, weights, xi, eta, inv_z, subpx_z, buf, s, scratch),
    }
}
