const std = @import("std");

const riley_version = std.SemanticVersion{
    .major = 2026,
    .minor = 5,
    .patch = 0,
};

const RunEntry = struct {
    step_name: []const u8,
    description: []const u8,
    source_path: []const u8,
};

const TestEntry = struct {
    step_name: []const u8,
    description: []const u8,
    source_path: []const u8,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const precision = b.option([]const u8, "precision", "Floating point precision: f64 or f32") orelse
        "f64";
    const simd = b.option([]const u8, "simd", "SIMD mode: on or off") orelse "on";

    validatePrecision(precision);
    validateSimd(simd);

    const build_options_module = createBuildOptionsModule(
        b,
        precision,
        simd,
    );
    const shared_lib = addRileySharedLibrary(
        b,
        target,
        optimize,
        build_options_module,
    );
    b.installArtifact(shared_lib);
    _ = b.addInstallHeaderFile(
        b.path("src/riley/cyth/riley.h"),
        "riley.h",
    );

    const tests = [_]TestEntry{
        .{
            .step_name = "test-min",
            .description = "Run the MIN test suite",
            .source_path = "src/test_min.zig",
        },
        .{
            .step_name = "test-gold-all",
            .description = "Run the ALL gold regression test suite",
            .source_path = "src/test_gold_all.zig",
        },
        .{
            .step_name = "test-bench",
            .description = "Run the benchmark regression test suite",
            .source_path = "src/test_bench.zig",
        },
        .{
            .step_name = "test-gold-edge",
            .description = "Run the edge gold regression test suite",
            .source_path = "src/test_gold_edge.zig",
        },
        .{
            .step_name = "test-gold-multicamera",
            .description = "Run the multicamera gold regression test suite",
            .source_path = "src/test_gold_multicamera.zig",
        },
        .{
            .step_name = "test-gold-multimesh",
            .description = "Run the multimesh gold regression test suite",
            .source_path = "src/test_gold_multimesh.zig",
        },
        .{
            .step_name = "test-gold-psf",
            .description = "Run the PSF gold regression test suite",
            .source_path = "src/test_gold_psf.zig",
        },
        .{
            .step_name = "test-gold-simple",
            .description = "Run the simple gold regression test suite",
            .source_path = "src/test_gold_simple.zig",
        },
        .{
            .step_name = "test-gold-small",
            .description = "Run the small gold regression test suite",
            .source_path = "src/test_gold_small.zig",
        },
        .{
            .step_name = "test-gold-sphere",
            .description = "Run the sphere gold regression test suite",
            .source_path = "src/test_gold_sphere.zig",
        },
        .{
            .step_name = "test-gold-ssaa",
            .description = "Run the SSAA gold regression test suite",
            .source_path = "src/test_gold_ssaa.zig",
        },
        .{
            .step_name = "test-hull",
            .description = "Run the hull gold regression test suite",
            .source_path = "src/test_hull.zig",
        },
        .{
            .step_name = "test-nodal-normals",
            .description = "Run the nodal normals test suite",
            .source_path = "src/test_nodal_normals.zig",
        },
        .{
            .step_name = "test-texfunc",
            .description = "Run the texfunc gold regression test suite",
            .source_path = "src/test_texfunc.zig",
        },
    };

    const test_all_step = b.step("tests", "Run all configured test suites");
    for (tests) |entry| {
        const test_step = b.step(entry.step_name, entry.description);
        const test_run = addTestRunStep(
            b,
            target,
            optimize,
            build_options_module,
            entry,
        );
        test_step.dependOn(&test_run.step);
        test_all_step.dependOn(&test_run.step);
    }

    const demos = [_]RunEntry{
        .{
            .step_name = "demo-sphere200",
            .description = "Run the sphere200 demo",
            .source_path = "src/demo_sphere200.zig",
        },
        .{
            .step_name = "demo-rabbits",
            .description = "Run the rabbits demo",
            .source_path = "src/demo_rabbits.zig",
        },
        .{
            .step_name = "demo-rabbits-rgb",
            .description = "Run the rabbits RGB demo",
            .source_path = "src/demo_rabbits_rgb.zig",
        },
        .{
            .step_name = "demo-rabbits-fields",
            .description = "Run the rabbits fields demo",
            .source_path = "src/demo_rabbits_fields.zig",
        },
        .{
            .step_name = "demo-dicuq",
            .description = "Run the DIC UQ demo",
            .source_path = "src/demo_dicuq.zig",
        },
        .{
            .step_name = "demo-stereocal",
            .description = "Run the stereo calibration demo",
            .source_path = "src/demo_stereocal.zig",
        },
    };

    const demos_step = b.step("demos", "Run all demo entrypoints");
    for (demos) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            build_options_module,
            entry,
        );
        run_step.dependOn(&run_artifact.step);
        demos_step.dependOn(&run_artifact.step);
    }

    const generators = [_]RunEntry{
        .{
            .step_name = "gen-gold-all",
            .description = "Generate the ALL gold datasets",
            .source_path = "src/gen_gold_all.zig",
        },
        .{
            .step_name = "gen-gold-min",
            .description = "Generate the MIN gold datasets",
            .source_path = "src/gen_gold_min.zig",
        },
        .{
            .step_name = "gen-gold-small",
            .description = "Generate the small gold datasets",
            .source_path = "src/gen_gold_small.zig",
        },
        .{
            .step_name = "gen-gold-simple",
            .description = "Generate the simple gold datasets",
            .source_path = "src/gen_gold_simple.zig",
        },
        .{
            .step_name = "gen-gold-edge",
            .description = "Generate the edge gold datasets",
            .source_path = "src/gen_gold_edge.zig",
        },
        .{
            .step_name = "gen-gold-multimesh",
            .description = "Generate the multimesh gold datasets",
            .source_path = "src/gen_gold_multimesh.zig",
        },
        .{
            .step_name = "gen-gold-multicamera",
            .description = "Generate the multicamera gold datasets",
            .source_path = "src/gen_gold_multicamera.zig",
        },
        .{
            .step_name = "gen-gold-hull",
            .description = "Generate the hull gold datasets",
            .source_path = "src/gen_gold_hull.zig",
        },
        .{
            .step_name = "gen-gold-fullscreen",
            .description = "Generate the fullscreen gold datasets",
            .source_path = "src/gen_gold_fullscreen.zig",
        },
        .{
            .step_name = "gen-gold-sphere",
            .description = "Generate the sphere gold datasets",
            .source_path = "src/gen_gold_sphere.zig",
        },
        .{
            .step_name = "gen-gold-texfunc",
            .description = "Generate the texfunc gold datasets",
            .source_path = "src/gen_gold_texfunc.zig",
        },
        .{
            .step_name = "gen-gold-ssaa",
            .description = "Generate the SSAA gold datasets",
            .source_path = "src/gen_gold_ssaa.zig",
        },
        .{
            .step_name = "gen-gold-psf",
            .description = "Generate the PSF gold datasets",
            .source_path = "src/gen_gold_psf.zig",
        },
    };

    const gold_step = b.step("gen-gold", "Run all gold generation entrypoints");
    for (generators) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            build_options_module,
            entry,
        );
        run_step.dependOn(&run_artifact.step);
        if (std.mem.eql(u8, entry.step_name, "gen-gold-all")) {
            gold_step.dependOn(&run_artifact.step);
        }
    }

    const benches = [_]RunEntry{
        .{
            .step_name = "bench-cam",
            .description = "Run the camera benchmark",
            .source_path = "src/bench_cam.zig",
        },
        .{
            .step_name = "bench-dicuq",
            .description = "Run the DIC UQ benchmark",
            .source_path = "src/bench_dicuq.zig",
        },
        .{
            .step_name = "bench-fullraster",
            .description = "Run the fullraster benchmark",
            .source_path = "src/bench_fullraster.zig",
        },
        .{
            .step_name = "bench-geom",
            .description = "Run the geom benchmark",
            .source_path = "src/bench_geom.zig",
        },
        .{
            .step_name = "bench-sphere2000",
            .description = "Run the sphere2000 benchmark",
            .source_path = "src/bench_sphere2000.zig",
        },
        .{
            .step_name = "bench-sphere2000zoom",
            .description = "Run the sphere2000zoom benchmark",
            .source_path = "src/bench_sphere2000zoom.zig",
        },
        .{
            .step_name = "bench-thread-geom",
            .description = "Run the threaded geom benchmark",
            .source_path = "src/bench_thread_geom.zig",
        },
        .{
            .step_name = "bench-mem-dicuq",
            .description = "Run the memory DIC UQ benchmark",
            .source_path = "src/bench_mem_dicuq.zig",
        },
    };

    const bench_runs_step = b.step("benches", "Run all benchmark entrypoints");
    const bench_bins_step = b.step(
        "install-bench-bins",
        "Install benchmark binaries under the selected prefix bin directory",
    );
    for (benches) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            build_options_module,
            entry,
        );
        run_step.dependOn(&run_artifact.step);
        bench_runs_step.dependOn(&run_artifact.step);

        const install_step = b.step(
            b.fmt("install-{s}", .{entry.step_name}),
            b.fmt("Install the {s} benchmark executable", .{entry.step_name}),
        );
        const install_artifact = addBenchInstallStep(
            b,
            target,
            optimize,
            build_options_module,
            entry,
            precision,
            simd,
        );
        install_step.dependOn(&install_artifact.step);
        bench_bins_step.dependOn(&install_artifact.step);
    }
}

fn addRileySharedLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
) *std.Build.Step.Compile {
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "riley",
        .root_module = createRootModule(
            b,
            target,
            optimize,
            build_options_module,
            "src/riley/zig/c-riley.zig",
            true,
            .library,
        ),
        .version = riley_version,
    });
    return shared_lib;
}

fn addTestRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
    entry: TestEntry,
) *std.Build.Step.Run {
    const test_compile = b.addTest(.{
        .name = entry.step_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            build_options_module,
            entry.source_path,
            true,
            .test_module,
        ),
    });
    return b.addRunArtifact(test_compile);
}

fn addRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
) *std.Build.Step.Run {
    const executable = b.addExecutable(.{
        .name = entry.step_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            build_options_module,
            entry.source_path,
            false,
            .executable,
        ),
    });
    return b.addRunArtifact(executable);
}

fn addBenchInstallStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
    precision: []const u8,
    simd: []const u8,
) *std.Build.Step.InstallArtifact {
    const binary_name = benchmarkBinaryName(
        b,
        entry.source_path["src/".len .. entry.source_path.len - ".zig".len],
        precision,
        simd,
    );
    const executable = b.addExecutable(.{
        .name = binary_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            build_options_module,
            entry.source_path,
            false,
            .executable,
        ),
    });
    return b.addInstallArtifact(executable, .{
        .dest_sub_path = binary_name,
    });
}

fn createBuildOptionsModule(
    b: *std.Build,
    precision: []const u8,
    simd: []const u8,
) *std.Build.Module {
    const options = b.addOptions();
    options.addOption([]const u8, "precision", precision);
    options.addOption([]const u8, "simd", simd);
    return options.createModule();
}

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
    source_path: []const u8,
    link_libc: bool,
    wrapper_kind: WrapperKind,
) *std.Build.Module {
    const wrapper_files = b.addWriteFiles();
    const wrapper_source = wrapper_files.add(
        b.fmt("{s}.wrapper.zig", .{source_path}),
        wrapperSourceText(wrapper_kind),
    );
    return b.createModule(.{
        .root_source_file = wrapper_source,
        .target = target,
        .optimize = optimize,
        .link_libc = link_libc,
        .imports = &.{
            .{
                .name = "build_options",
                .module = build_options_module,
            },
            .{
                .name = "entry_source",
                .module = b.createModule(.{
                    .root_source_file = b.path(source_path),
                    .target = target,
                    .optimize = optimize,
                    .link_libc = link_libc,
                }),
            },
        },
    });
}

const WrapperKind = enum {
    executable,
    test_module,
    library,
};

fn wrapperSourceText(wrapper_kind: WrapperKind) []const u8 {
    return switch (wrapper_kind) {
        .executable =>
        \\const entry_source = @import("entry_source");
        \\pub const build_options = @import("build_options");
        \\pub const main = entry_source.main;
        \\comptime {
        \\    _ = entry_source;
        \\}
        \\
        ,
        .test_module, .library =>
        \\const entry_source = @import("entry_source");
        \\pub const build_options = @import("build_options");
        \\comptime {
        \\    _ = entry_source;
        \\}
        \\
        ,
    };
}

fn validatePrecision(precision: []const u8) void {
    if (std.mem.eql(u8, precision, "f32") or
        std.mem.eql(u8, precision, "f64"))
    {
        return;
    }
    @panic("Supported -Dprecision values are f32 and f64.");
}

fn validateSimd(simd: []const u8) void {
    if (std.mem.eql(u8, simd, "on") or
        std.mem.eql(u8, simd, "off"))
    {
        return;
    }
    @panic("Supported -Dsimd values are on and off.");
}

fn benchmarkBinaryName(
    b: *std.Build,
    base_name: []const u8,
    precision: []const u8,
    simd: []const u8,
) []const u8 {
    const simd_tag = if (std.mem.eql(u8, simd, "on")) "simd" else "scalar";
    if (std.mem.eql(u8, precision, "f64")) {
        return b.fmt("{s}_{s}", .{ base_name, simd_tag });
    }
    return b.fmt("{s}_{s}_{s}", .{ base_name, precision, simd_tag });
}
