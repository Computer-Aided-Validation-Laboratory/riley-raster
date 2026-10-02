// --------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("../riley/zig/buildconfig.zig");
const camera = @import("../riley/zig/camera.zig");
const fullcase_dist_frontend = @import("../tests/fullcase_dist_frontend.zig");
const gk = @import("../riley/zig/geometrykernels.zig");
const iio = @import("../riley/zig/imageio.zig");
const mo = @import("../riley/zig/meshpipeline.zig");
const orch = @import("../dev_support/orchestration.zig");
const policy = @import("../dev_support/testpolicy.zig");
const rastcfg = @import("../riley/zig/rasterconfig.zig");
const riley = @import("../riley/zig/riley.zig");
const tcfg = @import("../dev_support/testconfig.zig");

const F = buildconfig.F;
const CameraInput = camera.CameraInput;
const MeshInput = mo.MeshInput;

pub fn generateCase(
    allocator: std.mem.Allocator,
    io: std.Io,
    prepared: *const orch.SingleMeshPrepared,
    mesh_type: gk.MeshType,
    dist_case: fullcase_dist_frontend.DistModelCase,
    case_name: []const u8,
    camera_shift_x: F,
    disp_active: bool,
    gold_dir_root: []const u8,
    config: rastcfg.RasterConfig,
) !void {
    const out_dir_path = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ gold_dir_root, case_name },
    );
    defer allocator.free(out_dir_path);

    var out_dir = try orch.openDirEnsured(io, out_dir_path);
    out_dir.close(io);

    var mesh = fullcase_dist_frontend.buildCheckerMeshInput(prepared, mesh_type);
    if (!disp_active) {
        mesh.disp = null;
    }
    const meshes = [_]MeshInput{mesh};

    var camera_input = fullcase_dist_frontend.buildCameraInput(
        prepared,
        dist_case.distort,
    );
    if (camera_shift_x != 0.0) {
        camera_input.pos_world.set(
            0,
            camera_input.pos_world.get(0) + camera_shift_x,
        );
    }

    const render_groups = [_]riley.RenderGroupSpec{
        .{ .io = io, .workers = @max(@as(u16, 1), config.total_threads) },
    };

    var case_config = config;
    case_config.background_value = fullcase_dist_frontend.default_bg_value;

    const images = try riley.raster(
        allocator,
        &render_groups,
        &[_]CameraInput{camera_input},
        &meshes,
        case_config,
        out_dir_path,
    );

    if (images) |img| {
        allocator.free(img.slice);
    }
}

pub fn generateAllFullDistFrontendCases(
    allocator: std.mem.Allocator,
    io: std.Io,
    gold_dir_root: []const u8,
    config: rastcfg.RasterConfig,
) !void {
    const data_dir_root = "data/edge";

    // Standard cases
    for (fullcase_dist_frontend.test_motions) |motion| {
        for (fullcase_dist_frontend.all_mesh_types) |mesh_type| {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const aa = arena.allocator();

            const prepared = try orch.prepareSingleMeshCase(
                aa,
                io,
                motion,
                mesh_type,
                fullcase_dist_frontend.pixel_num_dist_frontend,
                fullcase_dist_frontend.fov_scale_dist_frontend,
                data_dir_root,
            );

            for (fullcase_dist_frontend.dist_model_cases) |dist_case| {
                const case_name = try fullcase_dist_frontend.formatCaseName(
                    aa,
                    motion,
                    mesh_type,
                    dist_case.tag,
                );
                try generateCase(
                    aa,
                    io,
                    &prepared,
                    mesh_type,
                    dist_case,
                    case_name,
                    0.0,
                    true,
                    gold_dir_root,
                    config,
                );
            }
        }
    }

    // Half off-screen cases (exactly 50% split across sensor boundary)
    for (fullcase_dist_frontend.edge_mesh_types) |mesh_type| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const prepared = try orch.prepareSingleMeshCase(
            aa,
            io,
            "distort_rot",
            mesh_type,
            fullcase_dist_frontend.pixel_num_dist_frontend,
            fullcase_dist_frontend.fov_scale_dist_frontend,
            data_dir_root,
        );

        const roi_dist = prepared.camera.pos_world.get(2) -
            prepared.camera.roi_cent_world.get(2);
        const pixel_size = prepared.camera.pixels_size[0];
        const focal_len = prepared.camera.focal_length;
        const half_sensor_px = @as(
            F,
            @floatFromInt(fullcase_dist_frontend.pixel_num_dist_frontend[0] / 2),
        );
        const half_sensor_world = half_sensor_px * pixel_size * roi_dist / focal_len;
        const shift_x = -half_sensor_world;

        for (fullcase_dist_frontend.dist_model_cases) |dist_case| {
            const case_name = try fullcase_dist_frontend.formatHalfOffCaseName(
                aa,
                mesh_type,
                dist_case.tag,
            );
            try generateCase(
                aa,
                io,
                &prepared,
                mesh_type,
                dist_case,
                case_name,
                shift_x,
                true,
                gold_dir_root,
                config,
            );
        }
    }

    // Onto-screen cases (just off-screen in pinhole, pulled onto sensor by barrel distortion)
    for (fullcase_dist_frontend.edge_mesh_types) |mesh_type| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        const prepared = try orch.prepareSingleMeshCase(
            aa,
            io,
            "distort_rot",
            mesh_type,
            fullcase_dist_frontend.pixel_num_dist_frontend,
            fullcase_dist_frontend.fov_scale_dist_frontend,
            data_dir_root,
        );

        const roi_dist = prepared.camera.pos_world.get(2) -
            prepared.camera.roi_cent_world.get(2);
        const pixel_size = prepared.camera.pixels_size[0];
        const focal_len = prepared.camera.focal_length;
        const bounds = fullcase_dist_frontend.calcCoordsBounds(
            &prepared.sim_data.coords,
        );

        // Place mesh min_x at 128.5 px in pinhole space (strictly off screen)
        const target_cam_x = bounds.min_x - (64.5 * pixel_size * roi_dist / focal_len);
        const shift_x = target_cam_x - prepared.camera.pos_world.get(0);

        for (fullcase_dist_frontend.onto_screen_dist_cases) |dist_case| {
            const case_name = try fullcase_dist_frontend.formatOntoScreenCaseName(
                aa,
                mesh_type,
                dist_case.tag,
            );
            try generateCase(
                aa,
                io,
                &prepared,
                mesh_type,
                dist_case,
                case_name,
                shift_x,
                false,
                gold_dir_root,
                config,
            );
        }
    }
}
