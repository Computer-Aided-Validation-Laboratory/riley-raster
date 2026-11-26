// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");

const buildconfig = @import("../riley/zig/buildconfig.zig");
const specklefixture = @import("specklefixture.zig");
const expected_config = @import("expected_speckle_config.zig");
const geometrykernels = @import("../riley/zig/geometrykernels.zig");
const imageio = @import("../riley/zig/imageio.zig");
const matslice = @import("../riley/zig/matslice.zig");
const riley = @import("../riley/zig/api.zig");
const render = @import("../riley/zig/riley.zig");
const speckleconfig = @import("../riley/zig/speckleconfig.zig");
const speckleops = @import("../riley/zig/speckleops.zig");
const speckleparams = @import("../riley/zig/speckleparams.zig");
const ndarray = @import("../riley/zig/ndarray.zig");
const rotation = @import("../riley/zig/rotation.zig");
const vecstack = @import("../riley/zig/vecstack.zig");

const F = buildconfig.F;

const Params = riley.SpeckleParams;
const Pattern = speckleconfig.Pattern;

const fixture_params = specklefixture.disk_params;

test "speckle BMP matches an independently calculated mock gradient" {
    if (comptime !buildconfig.enable_all_evaluators) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const params: speckleops.GridParams = .{ .evaluator = .mock };
    const K = speckleops.Kernel(speckleconfig.sampleConfigIndex(buildconfig.enable_all_evaluators, .mock));
    var resources = try speckleops.Resources.init(std.testing.allocator, params);
    defer resources.deinit(std.testing.allocator);
    const rows = 7;
    const cols = 13;
    var pixels: [rows * cols]F = undefined;
    const image = matslice.MatSlice(F).init(&pixels, rows, cols);
    for (0..rows) |rr| {
        const v = (@as(F, @floatFromInt(rr)) + 0.5) / rows;
        for (0..cols) |cc| {
            const u = (@as(F, @floatFromInt(cc)) + 0.5) / cols;
            pixels[rr * cols + cc] = K.sampleScal(u, v, &resources);
        }
    }
    try imageio.saveMatAsImage(std.testing.io, tmp.dir, "mock", &image, .{
        .format = .bmp,
        .file_bits = 8,
        .scaling = .{ .fixed = .{ 0, 1 } },
    });

    const stride = (cols * 3 + 3) & ~@as(usize, 3);
    const file_size = 54 + rows * stride;
    var buffer: [file_size + 1]u8 = undefined;
    const bmp = try tmp.dir.readFile(std.testing.io, "mock.bmp", &buffer);
    try std.testing.expectEqual(file_size, bmp.len);
    try std.testing.expectEqualStrings("BM", bmp[0..2]);
    try std.testing.expectEqual(file_size, std.mem.readInt(u32, bmp[2..6], .little));
    try std.testing.expectEqual(54, std.mem.readInt(u32, bmp[10..14], .little));
    try std.testing.expectEqual(cols, std.mem.readInt(i32, bmp[18..22], .little));
    try std.testing.expectEqual(rows, std.mem.readInt(i32, bmp[22..26], .little));
    try std.testing.expectEqual(24, std.mem.readInt(u16, bmp[28..30], .little));
    for (0..rows) |rr| {
        // Positive BMP heights store the bottom row first.
        const row = bmp[54 + (rows - 1 - rr) * stride ..][0..stride];
        for (0..cols) |cc| {
            const u = (@as(f64, @floatFromInt(cc)) + 0.5) / cols;
            const v = (@as(f64, @floatFromInt(rr)) + 0.5) / rows;
            const expected: u8 = @intFromFloat(@round(255.0 * 0.5 * (u + v)));
            try std.testing.expectEqualSlices(u8, &.{ expected, expected, expected }, row[cc * 3 ..][0..3]);
        }
        for (row[cols * 3 ..]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "speckle build options reach the runtime configuration" {
    try std.testing.expectEqual(
        expected_config.enable_all_evaluators,
        buildconfig.enable_all_evaluators,
    );
    try std.testing.expectEqual(
        expected_config.speckle_mask_samples_per_cell,
        buildconfig.speckle_mask_samples_per_cell,
    );
}

test "physical default speckles produce nontrivial two-frame images and preserve unit rescaling" {
    // Here the public entry point lowers hard/soft disks, Gaussian and Perlin inputs.
    const Case = struct {
        pattern: Pattern,
        jitter: F = 0,
        curved: bool = false,
        coverage: F = fixture_params.coverage,
        occupancy: F = fixture_params.occupancy,
        softness: F = 0,
    };
    const cases = [_]Case{
        .{ .pattern = .disk, .coverage = 0.5, .occupancy = 1 },
        .{ .pattern = .disk, .curved = true, .coverage = 0.5, .occupancy = 1 },
        .{ .pattern = .disk, .jitter = 0.02, .softness = 0.015 },
        .{ .pattern = .gaussian, .curved = true, .jitter = 0.02 },
        .{ .pattern = .perlin, .curved = true },
    };

    for (cases, 0..) |case, case_idx| {
        var physical = fixture_params;
        physical.coverage = case.coverage;
        physical.occupancy = case.occupancy;
        physical.jitter = case.jitter;
        physical.edge_softness = case.softness;
        const params: Params = switch (case.pattern) {
            .disk => .{ .disk = physical },
            .gaussian => .{ .gaussian = .{
                .coverage = case.coverage,
                .radius = fixture_params.radius,
                .occupancy = case.occupancy,
                .jitter = case.jitter,
                .seed = fixture_params.seed,
            } },
            .perlin => .{ .perlin = .{
                .cell_size = 0.3,
                .seed = fixture_params.seed,
            } },
        };
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const scene = try specklefixture.initScene(&arena, params, case.curved, 1);

        errdefer std.debug.print("physical render case {d}: {s}, curved={}\n", .{
            case_idx, @tagName(case.pattern), case.curved,
        });
        const alloc = arena.allocator();
        const expected = try renderSpeckleMesh(alloc, scene.camera_input, scene.mesh_input, .tile_local, 1);
        // This is a two-frame smoke check, not a reference for the deformation mapping.
        try specklefixture.expectDeformedImages(expected);

        // An identity pipe must preserve the public direct shader's samples.
        var stages: [1]riley.ShaderPipeStageInput = undefined;
        var piped = scene.mesh_input;
        piped.shaders = .{ .mono_pipe = riley.ops.identityMulti(
            1,
            riley.ops.monoToPipeSource(scene.mesh_input.shaders.mono_direct.?),
            &stages,
        ) };
        const pipe_images = try renderSpeckleMesh(alloc, scene.camera_input, piped, .tile_local, 1);
        try specklefixture.expectImagesWithin(expected, pipe_images, 0);

        // A unit change must preserve the jittered spots and the physical Perlin period.
        if (case.jitter > 0 or case.pattern == .perlin) {
            const scaled = try specklefixture.initScene(&arena, params, case.curved, 8);
            const actual = try renderSpeckleMesh(alloc, scaled.camera_input, scaled.mesh_input, .tile_local, 1);
            try specklefixture.expectImagesWithin(expected, actual, 0);
        }
    }
}

test "direct and pipe speckles validate strided UVs without scanning padding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var scene = try specklefixture.initScene(&arena, .{ .disk = fixture_params }, false, 1);
    // Keep all six logical nodes in the view, but reference only the three corners.
    var corners = [_]usize{ 0, 1, 2 };
    scene.mesh_input.mesh_type = .tri3;
    scene.mesh_input.connect = riley.Connect.init(&corners, 1, 3);
    const direct = scene.mesh_input.shaders.mono_direct.?;
    const uvs = direct.speckle.uvs;
    const expected = try renderSpeckleMesh(alloc, scene.camera_input, scene.mesh_input, .tile_local, 1);

    // Padded component planes: the last usable V is exactly at the end of the view.
    var padded = [_]F{std.math.nan(F)} ** 23;
    var strides = [_]usize{ 2, 12 };
    var strided: ndarray.NDArray(F) = .{ .slice = &padded, .dims = uvs.dims, .strides = &strides };
    for (0..uvs.dims[0]) |node| {
        for (0..2) |axis| strided.set(&.{ node, axis }, uvs.get(&.{ node, axis }));
    }
    var extra_stride = [_]usize{ 2, 12, 1 };
    var mul_overflow = [_]usize{ std.math.maxInt(usize), 1 };
    var add_overflow = [_]usize{ 2, std.math.maxInt(usize) };
    const malformed = [_]ndarray.NDArray(F){
        .{ .slice = &padded, .dims = uvs.dims, .strides = strides[0..1] },
        .{ .slice = &padded, .dims = uvs.dims, .strides = &extra_stride },
        .{ .slice = padded[0 .. padded.len - 1], .dims = uvs.dims, .strides = &strides },
        .{ .slice = &padded, .dims = uvs.dims, .strides = &mul_overflow },
        .{ .slice = &padded, .dims = uvs.dims, .strides = &add_overflow },
    };

    var nonfinite_values = padded;
    var nonfinite = strided;
    nonfinite.slice = &nonfinite_values;
    nonfinite.set(&.{ corners[2], 1 }, std.math.nan(F));
    var unreferenced_values = padded;
    var unreferenced = strided;
    unreferenced.slice = &unreferenced_values;
    unreferenced.set(&.{ uvs.dims[0] - 1, 1 }, std.math.nan(F));
    const inputs = malformed ++ [_]ndarray.NDArray(F){ strided, nonfinite, unreferenced };

    const Role = enum { mono_direct, mono_pipe, multifield_used, multifield_unused };
    var config = specklefixture.rasterConfig(.tile_local);
    for ([_]@TypeOf(config.validation){ .off, .fast, .full }) |validation| {
        config.validation = validation;
        for (std.enums.values(Role)) |role| {
            for (inputs, 0..) |input, ii| {
                var shader = direct;
                shader.speckle.uvs = input;
                var stages: [1]riley.ShaderPipeStageInput = undefined;
                var mesh = scene.mesh_input;
                var camera = scene.camera_input;
                camera.background_value = -1;
                switch (role) {
                    .mono_direct => mesh.shaders = .{ .mono_direct = shader },
                    .mono_pipe => mesh.shaders = .{
                        .mono_pipe = riley.ops.identityMulti(1, riley.ops.monoToPipeSource(shader), &stages),
                    },
                    .multifield_used => {
                        camera.render_format = .{ .multifield = 1 };
                        mesh.shaders = .{
                            .multifield_pipe = riley.ops.identityMulti(1, riley.ops.monoToPipeSource(shader), &stages),
                        };
                    },
                    .multifield_unused => {
                        var pipe = riley.ops.identityMulti(1, riley.ops.monoToPipeSource(shader), &stages);
                        // The unused resolver has two outputs even though the active camera is mono.
                        const ch0 = riley.Register{ .kind = .channel, .index = 0 };
                        pipe.resolver = .{ .identity = &.{ ch0, ch0 } };
                        mesh.shaders.multifield_pipe = pipe;
                    },
                }
                const rendered = render.rasterAdvanced(
                    alloc,
                    std.testing.io,
                    &.{camera},
                    &.{mesh},
                    config,
                    null,
                    .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = 1 }} } },
                );
                const unused = role == .multifield_unused;
                if (ii < malformed.len and (!unused or validation != .off)) {
                    try std.testing.expectError(error.InvalidUvDimensions, rendered);
                } else if (validation == .full and ii > malformed.len) {
                    try std.testing.expectError(error.NonFiniteUvs, rendered);
                } else if (ii == malformed.len + 1 and !unused) {
                    try std.testing.expectError(error.InvalidSpeckleUvDomain, rendered);
                } else {
                    try specklefixture.expectImagesWithin(expected, (try rendered) orelse return error.NoResult, 0);
                }
            }
        }
    }
}

test "planar speckle fields agree across surface element types" {
    const cols = 35;
    const rows = 20;
    // Crop strictly inside the plate so silhouette coverage does not affect the comparison.
    const cam_input: riley.CameraInput = .{
        .pixels_num = .{ cols, rows },
        .pixels_size = .{ 1.0 / 32.0, 1.0 / 32.0 },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 2,
        .sub_sample = 2,
    };
    const plate_size = [2]F{ 1.25, 0.75 };
    var uv_values = [_]F{ 0, 0, 1, 0, 1, 1, 0, 1, 0.5, 0, 1, 0.5, 0.5, 1, 0, 0.5, 0.5, 0.5 };
    var coords: [9 * 3]F = undefined;
    for (0..9) |nn| {
        const u = uv_values[2 * nn];
        const v = uv_values[2 * nn + 1];
        coords[3 * nn ..][0..3].* = .{ (u - 0.5) * plate_size[0], (v - 0.5) * plate_size[1], 0 };
    }
    var quad_nodes = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8 };
    var tri3_nodes = [_]usize{ 0, 1, 2, 0, 2, 3 };
    var tri6_nodes = [_]usize{ 0, 1, 2, 4, 5, 8, 0, 2, 3, 8, 6, 7 };
    const meshes = [_]struct { mesh_type: geometrykernels.MeshType, nodes: []usize }{
        .{ .mesh_type = .quad4, .nodes = quad_nodes[0..4] },
        .{ .mesh_type = .tri3, .nodes = &tri3_nodes },
        .{ .mesh_type = .tri3opt, .nodes = &tri3_nodes },
        .{ .mesh_type = .tri6, .nodes = &tri6_nodes },
        .{ .mesh_type = .quad8, .nodes = quad_nodes[0..8] },
        .{ .mesh_type = .quad9, .nodes = &quad_nodes },
    };
    const patterns = [_]Params{
        .{ .disk = fixture_params },
        .{ .gaussian = .{
            .coverage = fixture_params.coverage,
            .radius = fixture_params.radius,
            .occupancy = fixture_params.occupancy,
            .seed = fixture_params.seed,
        } },
        .{ .perlin = .{ .cell_size = 0.15, .seed = fixture_params.seed } },
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_values, &.{ 9, 2 });
    for (patterns) |params| {
        var reference: ndarray.NDArray(F) = undefined;
        for (meshes, 0..) |mesh, index| {
            errdefer std.debug.print("planar speckle parity: {s} on {s}\n", .{
                @tagName(params), @tagName(mesh.mesh_type),
            });
            const nodes_per_elem = mesh.mesh_type.getNodesNum();
            const mesh_input: riley.MeshInput = .{
                .mesh_type = mesh.mesh_type,
                .coords = riley.Coords.init(&coords, 9),
                .connect = riley.Connect.init(mesh.nodes, mesh.nodes.len / nodes_per_elem, nodes_per_elem),
                .disp = null,
                .shaders = .{ .mono_direct = .{ .speckle = .{ .uvs = uvs, .params = params } } },
            };
            const image = try renderSpeckleMesh(alloc, cam_input, mesh_input, .tile_local, 1);
            try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1, rows, cols }, image.dims);
            if (index == 0) {
                reference = image;
                try std.testing.expect(std.mem.min(F, image.slice) < 0.4);
                try std.testing.expect(std.mem.max(F, image.slice) > 0.6);
                for (image.slice) |value| try std.testing.expect(value >= 0 and value <= 1);
                try expectPlanarExecutionParity(alloc, cam_input, mesh_input, plate_size, image);
                continue;
            }
            const tol: F = if (F == f32) 2e-4 else 1e-10;
            for (reference.slice, image.slice, 0..) |expected, actual, pixel| {
                errdefer std.debug.print("pixel ({d}, {d})\n", .{ pixel % cols, pixel / cols });
                try std.testing.expectApproxEqAbs(expected, actual, tol);
            }
            if (mesh.mesh_type == .tri3) {
                // The 35-pixel crop leaves three columns in the final 8-pixel tile:
                // six subpixels at 2x SSAA, a partial packet at the default SIMD widths.
                var stages: [1]riley.ShaderPipeStageInput = undefined;
                var piped = mesh_input;
                const source = riley.ops.monoToPipeSource(mesh_input.shaders.mono_direct.?);
                piped.shaders = .{ .mono_pipe = riley.ops.identityMulti(1, source, &stages) };
                const pipe_image = try renderSpeckleMesh(alloc, cam_input, piped, .tile_local, 1);
                try specklefixture.expectImagesWithin(image, pipe_image, 0);

                if (params == .perlin) {
                    var distorted = cam_input;
                    distorted.distort = .{ .brown_con = .{ .k1 = 0.2 } };
                    const distorted_direct = try renderSpeckleMesh(alloc, distorted, mesh_input, .tile_local, 1);
                    const distorted_pipe = try renderSpeckleMesh(alloc, distorted, piped, .tile_local, 1);
                    try specklefixture.expectImagesWithin(distorted_direct, distorted_pipe, 0);
                    for (distorted_direct.slice) |value| try std.testing.expect(value >= 0 and value <= 1);
                    try std.testing.expect(!std.mem.eql(F, image.slice, distorted_direct.slice));
                }
            }
        }
    }
}

test "tilted triangle speckles use perspective-correct UVs" {
    const side = 32;
    const cam_input: riley.CameraInput = .{
        .pixels_num = .{ side, side },
        .pixels_size = .{ 1.0 / 16.0, 1.0 / 16.0 },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 2,
        .sub_sample = 1,
    };
    var coords = [_]F{ -1, -1, 0, 0.5, -0.5, 1, -1, 1, 0 };
    var nodes = [_]usize{ 0, 1, 2 };
    var uv_values = [_]F{ 0, 0, 1, 0, 0, 1 };
    const params: Params = .{ .perlin = .{ .cell_size = 0.45, .transition_width = 0.6, .seed = fixture_params.seed } };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_values, &.{ 3, 2 });
    var mesh: riley.MeshInput = .{
        .mesh_type = .tri3,
        .coords = riley.Coords.init(&coords, 3),
        .connect = riley.Connect.init(&nodes, 1, 3),
        .disp = null,
        .shaders = .{ .mono_direct = .{ .speckle = .{ .uvs = uvs, .params = params } } },
    };
    const direct = try renderSpeckleMesh(alloc, cam_input, mesh, .tile_local, 1);
    var stages: [1]riley.ShaderPipeStageInput = undefined;
    mesh.shaders = .{ .mono_pipe = riley.ops.identityMulti(1, riley.ops.monoToPipeSource(mesh.shaders.mono_direct.?), &stages) };
    const pipe = try renderSpeckleMesh(alloc, cam_input, mesh, .tile_local, 1);

    // Reuse material calibration and sampling, but no projection or interpolation code.
    const grid = try speckleparams.resolveForMesh(params, mesh.mesh_type, &mesh.coords, &mesh.connect, &uvs);
    var resources = try speckleops.Resources.init(alloc, grid);
    defer resources.deinit(alloc);
    const index = comptime speckleconfig.sampleConfigIndex(buildconfig.enable_all_evaluators, .gradient_lattice);
    const K = speckleops.Kernel(index);
    const tol: F = if (F == f32) 2e-4 else 1e-10;
    var max_affine_difference: F = 0;
    for ([_][2]usize{ .{ 8, 23 }, .{ 12, 26 }, .{ 6, 13 } }) |probe| {
        const col, const row = probe;
        errdefer std.debug.print("tilted triangle pixel ({d}, {d})\n", .{ col, row });
        const x = (@as(f64, @floatFromInt(col)) + 0.5 - side / 2) / 16;
        const y = (side / 2 - @as(f64, @floatFromInt(row)) - 0.5) / 16;
        // Intersect (t*x, t*y, 2-2*t) with A + u*(B-A) + v*(C-A).
        const t = 2 / (3 + x);
        const u = 2 - 2 * t;
        const v = (t * y + 1 - 0.5 * u) / 2;
        try std.testing.expect(@min(u, v, 1 - u - v) > 0.1);
        const expected = K.sampleScal(@floatCast(u), @floatCast(v), &resources);
        try std.testing.expectApproxEqAbs(expected, direct.slice[row * side + col], tol);
        try std.testing.expectApproxEqAbs(expected, pipe.slice[row * side + col], tol);

        // The projected vertices at z=0 are (-1,-1), (1,-1), (-1,1).
        const affine = K.sampleScal(@floatCast((x + 1) / 2), @floatCast((y + 1) / 2), &resources);
        max_affine_difference = @max(max_affine_difference, @abs(expected - affine));
    }
    try std.testing.expect(max_affine_difference > 0.05);
}

test "folded projection speckles shade the nearest front-facing root" {
    const side = 33;
    const cam_input: riley.CameraInput = .{
        .pixels_num = .{ side, side },
        .pixels_size = .{ 1.0 / 32.0, 1.0 / 32.0 },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 1 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 1,
        .sub_sample = 1,
    };
    var coords: [8 * 3]F = undefined;
    var uv_values: [8 * 2]F = undefined;
    var nodes = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (geometrykernels.parentNodeCoords(8), 0..) |parent, nn| {
        const xi, const eta = parent;
        const z = -0.25 * (xi + xi * xi * eta - 0.25 * xi);
        // Only the projection folds: x and y+z recover both parent coordinates.
        coords[3 * nn ..][0..3].* = .{ 0.25 * (xi - eta), -z - 0.25 * eta, z };
        uv_values[2 * nn ..][0..2].* = .{ 0.5 * (1 + xi), 0.5 * (1 + eta) };
    }

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_values, &.{ 8, 2 });
    const params: Params = .{ .perlin = .{ .cell_size = 0.45, .transition_width = 0.6, .seed = fixture_params.seed } };
    var stages: [1]riley.ShaderPipeStageInput = undefined;
    const source = riley.ops.monoToPipeSource(.{ .speckle = .{ .uvs = uvs, .params = params } });
    const mesh: riley.MeshInput = .{
        .mesh_type = .quad8,
        .coords = riley.Coords.init(&coords, 8),
        .connect = riley.Connect.init(&nodes, 1, 8),
        .disp = null,
        .shaders = .{ .mono_pipe = riley.ops.identityMulti(1, source, &stages) },
    };
    const image = try renderSpeckleMesh(alloc, cam_input, mesh, .tile_local, 1);

    // On the centre ray, x=y=0 gives xi=eta and xi*(xi^2-1/4)=0.
    // The projected Jacobian is negative at both outer roots (front-facing).
    // There, depth is 1+xi/4, so xi=-1/2 wins over xi=+1/2.
    const grid = try speckleparams.resolveForMesh(params, mesh.mesh_type, &mesh.coords, &mesh.connect, &uvs);
    var resources = try speckleops.Resources.init(alloc, grid);
    defer resources.deinit(alloc);
    const index = comptime speckleconfig.sampleConfigIndex(buildconfig.enable_all_evaluators, .gradient_lattice);
    const K = speckleops.Kernel(index);
    const nearest = K.sampleScal(0.25, 0.25, &resources);
    const farther = K.sampleScal(0.75, 0.75, &resources);
    const back_facing = K.sampleScal(0.5, 0.5, &resources);
    try std.testing.expect(@min(@abs(nearest - farther), @abs(nearest - back_facing)) > 0.05);
    const tol: F = if (F == f32) 2e-3 else 1e-9;
    try std.testing.expectApproxEqAbs(nearest, image.slice[(side / 2) * side + side / 2], tol);
}

test "public physical disk render recovers nominal coverage and reference scale" {
    const cols = 768;
    const rows = 512;
    const pixel_size = 1.0 / 128.0;
    const radius: F = 1.0 / 64.0;
    // Front-facing 6 by 4 view inside a larger orthogonal plate: no silhouette or UV
    // boundary pixels contribute. At z = 0, focal length equals camera distance.
    const cam_input: riley.CameraInput = .{
        .pixels_num = .{ cols, rows },
        .pixels_size = .{ pixel_size, pixel_size },
        .pos_world = vecstack.Vec3F.initSlice(&.{ 0, 0, 2 }),
        .rot_world = rotation.Rotation.init(0, 0, 0),
        .roi_cent_world = vecstack.Vec3F.initZeros(),
        .focal_length = 2,
        .sub_sample = 1,
    };
    var coords = [_]F{ -3.25, -2.25, 0, 3.25, -2.25, 0, 3.25, 2.25, 0, -3.25, 2.25, 0 };
    var connect = [_]usize{ 0, 1, 2, 3 };
    var uv_values = [_]F{ 0, 0, 1, 0, 1, 1, 0, 1 };
    const alloc = std.testing.allocator;
    const uvs = try ndarray.NDArray(F).init(alloc, &uv_values, &.{ 4, 2 });
    defer uvs.deinit(alloc);

    const cases = [_]struct { occupancy: F, coverage: F, jitter: F = 0, expected: f64, tol: f64 }{
        .{ .occupancy = 0.3, .coverage = 0.1, .expected = 0.1, .tol = 0.005 },
        // dev/THEORY.md §6 gives about 0.525 for the stratified owner-cell model:
        // calibrate at C = 0.5 without jitter, then give each owner a uniform radius
        // in [R/2, 3R/2]. The tolerance allows for a finite field and pixel sampling.
        .{ .occupancy = 1, .coverage = 0.5, .jitter = radius / 2, .expected = 0.525, .tol = 0.01 },
    };
    for (cases) |case| {
        errdefer std.debug.print("disk coverage {d}, occupancy {d}, jitter {d}\n", .{
            case.coverage, case.occupancy, case.jitter,
        });
        var arena = std.heap.ArenaAllocator.init(alloc);
        defer arena.deinit();
        const image = try renderSpeckleMesh(arena.allocator(), cam_input, .{
            .mesh_type = .quad4,
            .coords = riley.Coords.init(&coords, 4),
            .connect = riley.Connect.init(&connect, 1, 4),
            .disp = null,
            .shaders = .{ .mono_direct = .{ .speckle = .{ .uvs = uvs, .params = .{ .disk = .{
                .seed = fixture_params.seed,
                .radius = radius,
                .occupancy = case.occupancy,
                .coverage = case.coverage,
                .jitter = case.jitter,
            } }, .bits = null } } },
        }, .tile_local, 1);
        try std.testing.expectEqualSlices(usize, &.{ 1, 1, 1, rows, cols }, image.dims);
        var covered: usize = 0;
        var row_transitions: usize = 0;
        var col_transitions: usize = 0;
        for (image.slice, 0..) |value, index| {
            if (value == 0) covered += 1 else try std.testing.expectEqual(@as(F, 1), value);
            if (index % cols != 0 and value != image.slice[index - 1]) row_transitions += 1;
            if (index >= cols and value != image.slice[index - cols]) col_transitions += 1;
        }
        const fraction = @as(f64, @floatFromInt(covered)) / (rows * cols);
        // Resolution, centre quantization, and correlated finite-area sampling all matter.
        try std.testing.expectApproxEqAbs(case.expected, fraction, case.tol);
        if (case.coverage < 0.2) {
            // Isolated circles have 4/(pi*R) crossings per scanline length per unit
            // coverage. Overlap and pixel sampling reduce that ratio in this scene.
            const isolated = 4 * fraction / (std.math.pi * @as(f64, radius));
            for ([_]usize{ row_transitions, col_transitions }, [_]f64{ rows * (cols - 1), cols * (rows - 1) }) |transitions, pixel_intervals| {
                const crossings_per_length = @as(f64, @floatFromInt(transitions)) /
                    (pixel_intervals * pixel_size);
                try std.testing.expectApproxEqAbs(@as(f64, 0.95), crossings_per_length / isolated, 0.057);
            }
        }
    }
}

fn expectPlanarExecutionParity(
    alloc: std.mem.Allocator,
    camera: riley.CameraInput,
    mesh: riley.MeshInput,
    plate_size: [2]F,
    tile_reference: ndarray.NDArray(F),
) !void {
    const direct = mesh.shaders.mono_direct.?;
    const params = direct.speckle.params;
    // Cover all buffer backends without crossing every material with every mode.
    const mode: riley.BufferMode = switch (params) {
        .disk => .global_subpx_full,
        .gaussian => .global_subpx_stripe,
        .perlin => .tile_local,
    };
    errdefer std.debug.print("planar execution parity: {s}, {s}\n", .{ @tagName(params), @tagName(mode) });
    const serial = if (mode == .tile_local) tile_reference else try renderSpeckleMesh(alloc, camera, mesh, mode, 1);
    // The tile-local and global buffers can reduce SSAA samples in different orders.
    try specklefixture.expectImagesWithin(tile_reference, serial, 8 * std.math.floatEps(F));
    try specklefixture.expectImagesWithin(serial, try renderSpeckleMesh(alloc, camera, mesh, mode, 4), 0);

    var stages: [1]riley.ShaderPipeStageInput = undefined;
    var piped = mesh;
    piped.shaders = .{ .mono_pipe = riley.ops.identityMulti(1, riley.ops.monoToPipeSource(direct), &stages) };
    const pipe_images = try renderSpeckleMesh(alloc, camera, piped, mode, 4);
    try specklefixture.expectImagesWithin(serial, pipe_images, 0);

    if (comptime buildconfig.enable_all_evaluators) {
        // Use the same calibrated field, but sample it independently of rasterisation and
        // with a different analytic evaluator: exhaustive dots or uncached Perlin.
        var grid = try speckleparams.resolveForMesh(params, mesh.mesh_type, &mesh.coords, &mesh.connect, &direct.speckle.uvs);
        grid.evaluator = if (params == .perlin) .cell_hash else .list_naive;
        var resources = try speckleops.Resources.init(alloc, grid);
        defer resources.deinit(alloc);
        const index = resources.kernel_index.?;
        switch (index) {
            inline 0...speckleops.kernel_configs.len - 1 => |ii| {
                const K = speckleops.Kernel(ii);
                const cols = camera.pixels_num[0];
                const rows = camera.pixels_num[1];
                const ssaa = camera.sub_sample;
                const ssaa_f: F = @floatFromInt(ssaa);
                const centre = [2]F{ @as(F, @floatFromInt(cols)) / 2, @as(F, @floatFromInt(rows)) / 2 };
                const tolerance: F = if (F == f32) 2e-4 else 1e-12;
                for (0..rows) |rr| for (0..cols) |cc| {
                    var sum: F = 0;
                    for (0..ssaa) |sy| for (0..ssaa) |sx| {
                        // Focal length equals camera distance, and raster Y points down.
                        const x = @as(F, @floatFromInt(cc)) + (@as(F, @floatFromInt(sx)) + 0.5) / ssaa_f;
                        const y = @as(F, @floatFromInt(rr)) + (@as(F, @floatFromInt(sy)) + 0.5) / ssaa_f;
                        const u = 0.5 + (x - centre[0]) * camera.pixels_size[0] / plate_size[0];
                        const v = 0.5 - (y - centre[1]) * camera.pixels_size[1] / plate_size[1];
                        sum += K.sampleScal(u, v, &resources);
                    };
                    errdefer std.debug.print("analytic reference mismatch at ({d}, {d})\n", .{ cc, rr });
                    try std.testing.expectApproxEqAbs(sum / (ssaa_f * ssaa_f), pipe_images.slice[rr * cols + cc], tolerance);
                };
            },
            else => unreachable,
        }
    }
}

fn renderSpeckleMesh(
    outer_alloc: std.mem.Allocator,
    camera_input: riley.CameraInput,
    mesh_input: riley.MeshInput,
    mode: riley.BufferMode,
    workers: u16,
) !ndarray.NDArray(F) {
    var camera = camera_input;
    camera.background_value = -1;
    return (try render.rasterAdvanced(
        outer_alloc,
        std.testing.io,
        &.{camera},
        &.{mesh_input},
        specklefixture.rasterConfig(mode),
        null,
        .{ .render_groups = .{ .supplied = &.{.{ .io = std.testing.io, .workers = workers }} } },
    )) orelse error.NoResult;
}
