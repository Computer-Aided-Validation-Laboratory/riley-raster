const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const fixture = @import("../dev_support/fullfixtures.zig");
const geom = @import("../riley/zig/geometrykernels.zig");
const meshpipe = @import("../riley/zig/meshpipeline.zig");
const shaderops = @import("../riley/zig/shaderops.zig");
const shaderpipe = @import("../riley/zig/shaderpipe.zig");
const riley = @import("../riley/zig/riley.zig");
const tcfg = @import("../dev_support/testconfig.zig");
const F = buildconfig.F;
const policy = @import("../dev_support/testpolicy.zig");
const common = @import("../dev_support/tests.zig");
const imageio = @import("../riley/zig/imageio.zig");

pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
    try runCase(allocator, io, false);
}

pub fn generateGold(allocator: std.mem.Allocator, io: std.Io) !void {
    try runCase(allocator, io, true);
}

fn runCase(allocator: std.mem.Allocator, io: std.Io, generate_gold: bool) !void {
    const parity_tol: F = if (F == f32) 1e-5 else 1e-9;
    var textures = try fixture.FullTextures.init(allocator, io);
    defer textures.deinit(allocator);
    const mesh_types = [_]geom.MeshType{ .tri3, .tri6, .quad4, .quad8, .quad9 };
    for (mesh_types) |mesh_type| {
        var scene = try fixture.prepareScene0(allocator, io, mesh_type);
        defer scene.deinit(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const sphere_stages = [_]shaderops.ShaderPipeStageInput{
            .{ .source = .{ .shader = .{ .tex_u8 = .{
                .uvs = scene.sphere_uvs.array,
                .tex = textures.tex_u8_mono,
                .samp_cfg = .{ .sample = .linear, .mode = .direct },
                .bits = null,
            } }, .destination = .{ .kind = .channel, .index = 0 } } },
            .{ .source = .{ .shader = .{ .func = .{
                .builtin = .lambertian_normal_z,
                .params = .{
                    .settings = .{
                        .lambertian_normal_z = .{
                            .coeffs = .{ 0.7, 0.3 },
                        },
                    },
                },
                .bits = null,
            } }, .destination = .{ .kind = .parameter, .index = 0 } } },
        };
        const cylinder_stages = [_]shaderops.ShaderPipeStageInput{
            .{ .source = .{ .shader = .{ .tex_u8 = .{
                .uvs = scene.cylinder_uvs.array,
                .tex = textures.tex_u8_mono,
                .samp_cfg = .{ .sample = .linear, .mode = .direct },
                .bits = null,
            } }, .destination = .{ .kind = .channel, .index = 0 } } },
            .{ .source = .{ .shader = .{ .func = .{
                .builtin = .lambertian_normal_z,
                .params = .{
                    .settings = .{
                        .lambertian_normal_z = .{
                            .coeffs = .{ 0.7, 0.3 },
                        },
                    },
                },
                .bits = null,
            } }, .destination = .{ .kind = .parameter, .index = 0 } } },
        };
        const channel_slots = [_]shaderpipe.Slot{.{ .kind = .channel, .index = 0 }};
        const resolver: shaderpipe.Resolver = .{ .modulate = .{
            .sources = &channel_slots,
            .factor = .{ .kind = .parameter, .index = 0 },
        } };
        const sphere_pipes = [_]shaderops.ShaderPipeInput{.{
            .stages = &sphere_stages,
            .resolver = resolver,
        }};
        const cylinder_pipes = [_]shaderops.ShaderPipeInput{.{
            .stages = &cylinder_stages,
            .resolver = resolver,
        }};
        const meshes = [_]meshpipe.MeshInput{
            .{
                .mesh_type = mesh_type,
                .coords = scene.sphere_coords,
                .connect = scene.sphere_connect,
                .disp = scene.sphere_disp,
                .shaders = .{ .mono = sphere_pipes[0] },
            },
            .{
                .mesh_type = mesh_type,
                .coords = scene.cylinder_coords,
                .connect = scene.cylinder_connect,
                .disp = scene.cylinder_disp,
                .shaders = .{ .mono = cylinder_pipes[0] },
            },
        };
        var camera = scene.camera_input;
        camera.shader_selection = .mono;
        var config = tcfg.getRasterConfig(.testing);
        config.save_strategy = if (generate_gold) .both else .memory;
        if (generate_gold) config.output.image_save_opts = &.{
            imageio.ImageSaveOpts{ .format = .fimg, .bits = null, .scaling = .none },
            imageio.ImageSaveOpts{ .format = .bmp, .bits = 8, .scaling = .auto },
        };
        const gold_dir = try std.fmt.allocPrint(
            aa,
            "{s}/scene0_modulate_{s}",
            .{ policy.goldRoot(.full_shaderpipe), @tagName(mesh_type) },
        );
        const result = try riley.raster(
            aa,
            io,
            &.{camera},
            &meshes,
            config,
            if (generate_gold) gold_dir else null,
        );
        const image = result orelse return error.NoResult;
        defer aa.free(image.slice);
        var min: F = std.math.inf(F);
        var max: F = -std.math.inf(F);
        for (image.slice) |pixel| {
            min = @min(min, pixel);
            max = @max(max, pixel);
        }
        try std.testing.expect(max > min + 0.05);
        const rows = image.dims[3];
        const cols = image.dims[4];
        var frame_diff: F = 0;
        for (0..rows) |yy| {
            for (0..cols) |xx| {
                const diff = @abs(
                    image.get(&.{ 0, 0, 0, yy, xx }) -
                        image.get(&.{ 0, 1, 0, yy, xx }),
                );
                frame_diff = @max(frame_diff, diff);
            }
        }
        try std.testing.expect(frame_diff > 1e-3);
        if (!generate_gold) {
            for (0..image.dims[1]) |frame| {
                const gold = try common.findGoldPath(aa, io, gold_dir, 0, frame, 0, false);
                try common.compareNDArrayToGold(
                    aa,
                    io,
                    &image,
                    0,
                    frame,
                    0,
                    1,
                    gold,
                    tcfg.FULL_GOLD_REL_TOL,
                    tcfg.FULL_GOLD_ABS_TOL,
                );
            }
        }

        if (mesh_type == .quad4) {
            config.save_strategy = .memory;
            inline for (.{ .global_subpx_full, .global_subpx_stripe }) |mode| {
                config.advanced.raster.buffer_mode = mode;
                const other_result = try riley.raster(
                    aa,
                    io,
                    &.{camera},
                    &meshes,
                    config,
                    null,
                );
                const other = other_result orelse return error.NoResult;
                defer aa.free(other.slice);
                try std.testing.expectEqual(image.slice.len, other.slice.len);
                for (image.slice, other.slice) |a, b| {
                    try std.testing.expectApproxEqAbs(a, b, parity_tol);
                }
            }

            const operations = [_]shaderpipe.Op{
                .{ .load = .{ .kind = .channel, .index = 0 } },
                .{ .load = .{ .kind = .parameter, .index = 0 } },
                .multiply,
                .{ .store = 0 },
            };
            const expression_resolver: shaderpipe.Resolver = .{
                .expression = .{ .operations = &operations },
            };
            const sphere_expr = [_]shaderops.ShaderPipeInput{.{
                .stages = &sphere_stages,
                .resolver = expression_resolver,
            }};
            const cylinder_expr = [_]shaderops.ShaderPipeInput{.{
                .stages = &cylinder_stages,
                .resolver = expression_resolver,
            }};
            var expression_meshes = meshes;
            expression_meshes[0].shaders = .{ .mono = sphere_expr[0] };
            expression_meshes[1].shaders = .{ .mono = cylinder_expr[0] };
            config.advanced.raster.buffer_mode = .tile_local;
            const expression_result = try riley.raster(
                aa,
                io,
                &.{camera},
                &expression_meshes,
                config,
                null,
            );
            const expression_image = expression_result orelse return error.NoResult;
            defer aa.free(expression_image.slice);
            for (image.slice, expression_image.slice) |a, b| {
                try std.testing.expectApproxEqAbs(a, b, parity_tol);
            }
        }
    }
}
