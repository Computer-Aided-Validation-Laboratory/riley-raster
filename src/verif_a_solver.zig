// --------------------------------------------------------------------------
// zraster: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------
const std = @import("std");
const buildconfig = @import("zraster/zig/buildconfig.zig");
const cam = @import("zraster/zig/camera.zig");
const gk = @import("zraster/zig/geometrykernels.zig");
const verif = @import("common/verif.zig");
const vconst = @import("common/verifconstants.zig");

const structured_grid_quad_num: usize = 250;
const structured_grid_tri_num: usize = 250;
const random_samples_num: usize = 400;
const boundary_samples_num: usize = 192;
const corner_samples_num: usize = 48;

fn mapFileStem(
    buf: []u8,
    mesh_type: gk.MeshType,
    geom_case_name: []const u8,
    camera_case_name: []const u8,
) ![]const u8 {
    return std.fmt.bufPrint(
        buf,
        "{s}_{s}_{s}",
        .{ @tagName(mesh_type), geom_case_name, camera_case_name },
    );
}

fn evalSample(
    comptime mesh_type: gk.MeshType,
    camera: *const cam.CameraPrepared,
    node_x: []const f64,
    node_y: []const f64,
    node_z: []const f64,
    solver_nodes: *const verif.ElementNodes(mesh_type.getNodesNum()),
    sample: verif.SamplePoint,
) !verif.SampleRecord {
    const world_true = verif.forwardMapWorldForMeshType(
        mesh_type,
        sample.xi_true,
        sample.eta_true,
        node_x,
        node_y,
        node_z,
    );
    const ideal_target = verif.worldToIdealRaster(camera, world_true);
    const observed_target = try verif.idealToObservedRaster(camera, ideal_target);
    const ideal_solve_target = try verif.observedToIdealRaster(
        camera,
        observed_target,
    );
    const solve_result = verif.solveParentFromIdealRaster(
        mesh_type,
        camera,
        solver_nodes,
        ideal_solve_target[0],
        ideal_solve_target[1],
    );

    var xi_rec: f64 = 0.0;
    var eta_rec: f64 = 0.0;
    var observed_reproj = observed_target;

    if (solve_result.converged) {
        xi_rec = solve_result.xi_rec;
        eta_rec = solve_result.eta_rec;
        const world_rec = verif.forwardMapWorldForMeshType(
            mesh_type,
            xi_rec,
            eta_rec,
            node_x,
            node_y,
            node_z,
        );
        const ideal_reproj = verif.worldToIdealRaster(camera, world_rec);
        observed_reproj = try verif.idealToObservedRaster(camera, ideal_reproj);
    }

    const err_xi = xi_rec - sample.xi_true;
    const err_eta = eta_rec - sample.eta_true;
    const err_param = @sqrt(err_xi * err_xi + err_eta * err_eta);
    const dx_obs = observed_reproj[0] - observed_target[0];
    const dy_obs = observed_reproj[1] - observed_target[1];
    const reproj_err = @sqrt(dx_obs * dx_obs + dy_obs * dy_obs);

    return .{
        .sample_kind = sample.sample_kind,
        .xi_true = sample.xi_true,
        .eta_true = sample.eta_true,
        .xi_rec = xi_rec,
        .eta_rec = eta_rec,
        .err_xi = err_xi,
        .err_eta = err_eta,
        .err_param = err_param,
        .ideal_target_x = ideal_target[0],
        .ideal_target_y = ideal_target[1],
        .observed_target_x = observed_target[0],
        .observed_target_y = observed_target[1],
        .observed_reproj_x = observed_reproj[0],
        .observed_reproj_y = observed_reproj[1],
        .reproj_err = reproj_err,
        .iters = solve_result.iters,
        .converged = solve_result.converged,
        .in_domain = verif.isInParametricDomain(mesh_type, xi_rec, eta_rec),
        .row_idx = sample.row_idx,
        .col_idx = sample.col_idx,
    };
}

fn saveStructuredMaps(
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    file_stem: []const u8,
    rows_num: usize,
    cols_num: usize,
    reproj_map: []const f64,
    param_map: []const f64,
    nonconv_map: []const f64,
) !void {
    var file_name_buf: [256]u8 = undefined;

    const reproj_csv = try std.fmt.bufPrint(
        &file_name_buf,
        "{s}_reproj_map.csv",
        .{file_stem},
    );
    try verif.writeScalarMapCsv(
        io,
        out_dir,
        reproj_csv,
        rows_num,
        cols_num,
        reproj_map,
    );

    const reproj_bmp_stem = try std.fmt.bufPrint(
        &file_name_buf,
        "{s}_reproj_map",
        .{file_stem},
    );
    try verif.writeScalarMapBmp(
        allocator,
        io,
        out_dir,
        reproj_bmp_stem,
        rows_num,
        cols_num,
        reproj_map,
    );

    const param_bmp_stem = try std.fmt.bufPrint(
        &file_name_buf,
        "{s}_param_map",
        .{file_stem},
    );
    try verif.writeScalarMapBmp(
        allocator,
        io,
        out_dir,
        param_bmp_stem,
        rows_num,
        cols_num,
        param_map,
    );

    const nonconv_bmp_stem = try std.fmt.bufPrint(
        &file_name_buf,
        "{s}_nonconv_map",
        .{file_stem},
    );
    try verif.writeBinaryMaskBmp(
        allocator,
        io,
        out_dir,
        nonconv_bmp_stem,
        rows_num,
        cols_num,
        nonconv_map,
    );
}

fn runCase(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    summary_list: *std.ArrayList(verif.CaseSummary),
    global_reproj_errs: *std.ArrayList(f64),
    camera_case_name: []const u8,
    camera: *const cam.CameraPrepared,
    elem_case: anytype,
) !void {
    const solver_nodes = verif.worldNodesToSolverCoords(
        mesh_type,
        camera,
        elem_case.node_x[0..],
        elem_case.node_y[0..],
        elem_case.node_z[0..],
    );

    var sample_list: std.ArrayList(verif.SamplePoint) = .empty;
    defer sample_list.deinit(allocator);

    const structured_grid_num = if (mesh_type == .tri3 or mesh_type == .tri6)
        structured_grid_tri_num
    else
        structured_grid_quad_num;

    const map_dims = try verif.appendStructuredSamples(
        mesh_type,
        allocator,
        &sample_list,
        structured_grid_num,
    );

    const prng_seed: u64 = 0x5eed_1234 + @as(u64, @intFromEnum(mesh_type));
    var prng = std.Random.DefaultPrng.init(prng_seed);
    var rng = prng.random();
    try verif.appendRandomSamples(
        mesh_type,
        allocator,
        &sample_list,
        &rng,
        random_samples_num,
    );
    try verif.appendBoundarySamples(
        mesh_type,
        allocator,
        &sample_list,
        boundary_samples_num,
    );
    try verif.appendCornerSamples(
        mesh_type,
        allocator,
        &sample_list,
        corner_samples_num,
    );

    const map_len = map_dims.rows_num * map_dims.cols_num;
    var reproj_map = try allocator.alloc(f64, map_len);
    defer allocator.free(reproj_map);
    var param_map = try allocator.alloc(f64, map_len);
    defer allocator.free(param_map);
    var nonconv_map = try allocator.alloc(f64, map_len);
    defer allocator.free(nonconv_map);
    @memset(reproj_map, std.math.nan(f64));
    @memset(param_map, std.math.nan(f64));
    @memset(nonconv_map, 0.0);

    var sample_records: std.ArrayList(verif.SampleRecord) = .empty;
    defer sample_records.deinit(allocator);
    try sample_records.ensureTotalCapacity(allocator, sample_list.items.len);

    var reproj_vals: std.ArrayList(f64) = .empty;
    defer reproj_vals.deinit(allocator);
    var param_vals: std.ArrayList(f64) = .empty;
    defer param_vals.deinit(allocator);
    var iter_vals: std.ArrayList(f64) = .empty;
    defer iter_vals.deinit(allocator);

    var nonconverged_num: usize = 0;
    var out_of_domain_num: usize = 0;

    for (sample_list.items) |sample| {
        const record = try evalSample(
            mesh_type,
            camera,
            elem_case.node_x[0..],
            elem_case.node_y[0..],
            elem_case.node_z[0..],
            &solver_nodes,
            sample,
        );
        try sample_records.append(allocator, record);
        try reproj_vals.append(allocator, record.reproj_err);
        try param_vals.append(allocator, record.err_param);
        try iter_vals.append(allocator, @floatFromInt(record.iters));
        try global_reproj_errs.append(allocator, record.reproj_err);

        if (!record.converged) {
            nonconverged_num += 1;
        }
        if (!record.in_domain) {
            out_of_domain_num += 1;
        }
        if (record.row_idx != verif.invalid_grid_idx and
            record.col_idx != verif.invalid_grid_idx)
        {
            const map_idx = record.row_idx * map_dims.cols_num + record.col_idx;
            reproj_map[map_idx] = record.reproj_err;
            param_map[map_idx] = record.err_param;
            nonconv_map[map_idx] = if (record.converged) 0.0 else 1.0;
        }
    }

    const reproj_stats = try verif.calcScalarStats(allocator, reproj_vals.items);
    const param_stats = try verif.calcScalarStats(allocator, param_vals.items);
    const iter_stats = try verif.calcScalarStats(allocator, iter_vals.items);

    try summary_list.append(allocator, .{
        .mesh_type = mesh_type,
        .geom_case_name = elem_case.name,
        .camera_case_name = camera_case_name,
        .samples_num = sample_records.items.len,
        .nonconverged_num = nonconverged_num,
        .out_of_domain_num = out_of_domain_num,
        .reproj_stats = reproj_stats,
        .param_stats = param_stats,
        .iter_stats = iter_stats,
    });

    const newton_tol = buildconfig.config.tolerance.newton.residual;
    const tol_cmp = verif.compareTol(reproj_stats, newton_tol);
    std.debug.print(
        "{s}/{s}/{s}: reproj px min={e:.6} q1={e:.6} med={e:.6} " ++
            "q3={e:.6} max={e:.6}  max/newton_tol={e:.3}\n",
        .{
            @tagName(mesh_type),
            elem_case.name,
            camera_case_name,
            reproj_stats.min,
            reproj_stats.q1,
            reproj_stats.median,
            reproj_stats.q3,
            reproj_stats.max,
            tol_cmp.max_ratio,
        },
    );

    var file_stem_buf: [256]u8 = undefined;
    const file_stem = try mapFileStem(
        &file_stem_buf,
        mesh_type,
        elem_case.name,
        camera_case_name,
    );

    var samples_name_buf: [256]u8 = undefined;
    const samples_file = try std.fmt.bufPrint(
        &samples_name_buf,
        "{s}_samples.csv",
        .{file_stem},
    );
    try verif.writeSampleRecordsCsv(
        io,
        out_dir,
        samples_file,
        sample_records.items,
    );
    try saveStructuredMaps(
        allocator,
        io,
        out_dir,
        file_stem,
        map_dims.rows_num,
        map_dims.cols_num,
        reproj_map,
        param_map,
        nonconv_map,
    );
}

fn runMeshType(
    comptime mesh_type: gk.MeshType,
    allocator: std.mem.Allocator,
    io: std.Io,
    out_dir: std.Io.Dir,
    summary_list: *std.ArrayList(verif.CaseSummary),
    global_reproj_errs: *std.ArrayList(f64),
    cameras: []const cam.CameraPrepared,
) !void {
    const elem_cases = vconst.getCases(mesh_type);

    for (elem_cases) |elem_case| {
        for (vconst.camera_cases, cameras) |camera_case, camera| {
            try runCase(
                mesh_type,
                allocator,
                io,
                out_dir,
                summary_list,
                global_reproj_errs,
                camera_case.name,
                &camera,
                elem_case,
            );
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var out_dir = try verif.openOutputDir(io, vconst.output_dir_name);
    defer out_dir.close(io);

    var cameras = try allocator.alloc(cam.CameraPrepared, vconst.camera_cases.len);
    defer {
        for (cameras) |*camera| {
            camera.deinit(allocator);
        }
        allocator.free(cameras);
    }
    for (vconst.camera_cases, 0..) |camera_case, cc| {
        cameras[cc] = try cam.CameraPrepared.init(allocator, camera_case.input);
    }

    var summary_list: std.ArrayList(verif.CaseSummary) = .empty;
    defer summary_list.deinit(allocator);

    var global_reproj_errs: std.ArrayList(f64) = .empty;
    defer global_reproj_errs.deinit(allocator);

    inline for (std.enums.values(gk.MeshType)) |mesh_type| {
        try runMeshType(
            mesh_type,
            allocator,
            io,
            out_dir,
            &summary_list,
            &global_reproj_errs,
            cameras,
        );
    }

    try verif.writeSummaryCsv(
        io,
        out_dir,
        "summary.csv",
        summary_list.items,
    );

    const global_stats = try verif.calcScalarStats(
        allocator,
        global_reproj_errs.items,
    );
    const newton_tol = buildconfig.config.tolerance.newton.residual;
    const distortion_tol = buildconfig.config.tolerance.distortion.residual;

    std.debug.print(
        "\nGlobal reprojection error summary (px):\n" ++
            "  min={e:.6}\n  q1={e:.6}\n  median={e:.6}\n  q3={e:.6}\n" ++
            "  max={e:.6}\n  mean={e:.6}\n  rms={e:.6}\n",
        .{
            global_stats.min,
            global_stats.q1,
            global_stats.median,
            global_stats.q3,
            global_stats.max,
            global_stats.mean,
            global_stats.rms,
        },
    );
    std.debug.print(
        "Tolerance comparison:\n" ++
            "  newton residual tol = {e:.6}\n" ++
            "  distortion residual tol = {e:.6}\n" ++
            "  max / newton tol = {e:.3}\n" ++
            "  median / newton tol = {e:.3}\n",
        .{
            newton_tol,
            distortion_tol,
            global_stats.max / newton_tol,
            global_stats.median / newton_tol,
        },
    );
}
