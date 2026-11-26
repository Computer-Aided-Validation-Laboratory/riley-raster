// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
const std = @import("std");
const buildoptions = @import("src/riley/zig/buildoptions.zig");
const speckleconfig = @import("src/riley/zig/speckleconfig.zig");

const riley_version = std.SemanticVersion{
    .major = 2026,
    .minor = 11,
    .patch = 2,
};

const RunEntry = struct {
    step_name: []const u8,
    description: []const u8,
    source_path: []const u8,
    forward_args: bool = false,
};

const TestEntry = struct {
    step_name: []const u8,
    description: []const u8,
    source_path: []const u8,
    filters: []const []const u8 = &.{},
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Omit debug information from built binaries") orelse false;
    const defaults: buildoptions.Options = .{};
    const mask_samples = b.option(
        u8,
        "speckle-mask-samples-per-cell",
        "Experimental mask/classified-indexed resolution per cell: 8, 12, or 16",
    ) orelse @intFromEnum(defaults.speckle_mask_resolution);
    const options: buildoptions.Options = .{
        .precision = b.option(
            buildoptions.Precision,
            "precision",
            "Floating point precision: f64 or f32",
        ) orelse defaults.precision,
        .simd = b.option(buildoptions.SimdMode, "simd", "SIMD mode: on or off") orelse defaults.simd,
        .newton_solver = b.option(
            buildoptions.NewtonSolverMode,
            "newton-solver",
            "Newton solver mode: fast or robust",
        ) orelse defaults.newton_solver,
        .simd_vector_width = b.option(
            u32,
            "simd-vector-width",
            "SIMD vector width (0 to use default for precision)",
        ) orelse defaults.simd_vector_width,
        .enable_all_evaluators = b.option(
            bool,
            "enable-all-evaluators",
            "Enable experimental native evaluator and neighbor overrides",
        ) orelse defaults.enable_all_evaluators,
        .speckle_mask_resolution = std.enums.fromInt(speckleconfig.MaskResolution, mask_samples) orelse
            @panic("Supported -Dspeckle-mask-samples-per-cell values are 8, 12, and 16."),
    };

    const build_options_module = createBuildOptionsModule(b, options);
    const riley_module = b.addModule("riley", .{
        .root_source_file = b.path("src/riley/zig/api.zig"),
        .target = target,
        .optimize = optimize,
    });
    const shared_lib = addRileySharedLibrary(
        b,
        target,
        optimize,
        strip,
        build_options_module,
        riley_module,
    );
    shared_lib.installHeader(
        b.path("src/riley/cython/riley.h"),
        "riley.h",
    );
    b.installArtifact(shared_lib);

    const abi_module = b.createModule(.{
        .root_source_file = b.path("src/test_c_abi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    abi_module.addIncludePath(b.path("src/riley/cython"));
    abi_module.addCSourceFile(.{
        .file = b.path("src/tests/c_abi_layout.c"),
        .flags = &.{"-std=c11"},
    });
    const abi_test = b.addTest(.{ .root_module = abi_module, .use_llvm = true });
    const abi_step = b.step("test-c-abi", "Check every public C descriptor against the C compiler layout");
    abi_step.dependOn(&b.addRunArtifact(abi_test).step);

    const tests = [_]TestEntry{
        .{
            .step_name = "test-unit",
            .description = "Run gold-independent native unit, integration, and tooling tests",
            .source_path = "src/test_unit.zig",
        },
        .{
            .step_name = "test-procedural-speckles",
            .description = "Run procedural speckle integration and unit tests",
            .source_path = "src/test_procedural_speckles.zig",
        },
        .{
            .step_name = "test-speckle-benchmark",
            .description = "Run focused native speckle benchmark tooling tests",
            .source_path = "src/bench_speckle_evaluators.zig",
            .filters = &.{"speckle benchmark"},
        },

        .{
            .step_name = "test-verif-basic",
            .description = "Run the verification and BASIC test suites in one build",
            .source_path = "src/test_verif_basic.zig",
        },
        .{
            .step_name = "test-basic",
            .description = "Run the BASIC test suite",
            .source_path = "src/test_basic.zig",
        },
        .{
            .step_name = "test-full",
            .description = "Run the FULL test suite",
            .source_path = "src/test_full.zig",
        },
        .{
            .step_name = "test-verif",
            .description = "Run the focused analytic verification suite",
            .source_path = "src/test_verif.zig",
        },
        .{
            .step_name = "test-public-api",
            .description = "Compile-check the public Riley Zig API",
            .source_path = "src/test_public_api.zig",
        },
    };

    for (tests) |entry| {
        const test_step = b.step(entry.step_name, entry.description);
        const test_run = addTestRunStep(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            riley_module,
            entry,
        );
        test_step.dependOn(&test_run.step);
    }

    const configs_step = b.step(
        "test-configs",
        "Run native tests across precision, SIMD, evaluator policy, and mask resolution",
    );
    for ([_]buildoptions.Precision{ .f64, .f32 }) |config_precision| {
        for ([_]buildoptions.SimdMode{ .on, .off }) |config_simd| {
            for ([_]bool{ false, true }) |experimental| {
                var config_options = options;
                config_options.precision = config_precision;
                config_options.simd = config_simd;
                config_options.enable_all_evaluators = experimental;
                config_options.speckle_mask_resolution = defaults.speckle_mask_resolution;
                if (experimental) {
                    if (config_precision == .f32 and config_simd == .on) config_options.speckle_mask_resolution = .sixteen;
                    if (config_precision == .f64 and config_simd == .off) config_options.speckle_mask_resolution = .eight;
                }
                const config_run = addTestRunStep(
                    b,
                    target,
                    optimize,
                    strip,
                    createBuildOptionsModule(b, config_options),
                    riley_module,
                    .{
                        .step_name = b.fmt("test-configs-{s}-{s}-{s}-mask-{d}", .{
                            @tagName(config_precision),
                            @tagName(config_simd),
                            if (experimental) "experimental" else "default",
                            @intFromEnum(config_options.speckle_mask_resolution),
                        }),
                        .description = "Run one native build configuration",
                        .source_path = "src/test_unit.zig",
                    },
                );
                configs_step.dependOn(&config_run.step);
            }
        }
    }

    const diag_badjac_step = b.step(
        "diag-badjac",
        "Run warning-only invalid-Jacobian render diagnostics",
    );
    const diag_badjac_run = addRunStep(
        b,
        target,
        optimize,
        strip,
        build_options_module,
        .{
            .step_name = "diag-badjac",
            .description = "Run warning-only invalid-Jacobian render diagnostics",
            .source_path = "src/diag_badjac.zig",
        },
    );
    diag_badjac_step.dependOn(&diag_badjac_run.step);

    const demos = [_]RunEntry{
        .{
            .step_name = "demo00-quickstart",
            .description = "Run the triangle quickstart demo",
            .source_path = "src/demo00_quickstart.zig",
        },
        .{
            .step_name = "demo01-sphere",
            .description = "Run the sphere demo",
            .source_path = "src/demo01_sphere.zig",
        },
        .{
            .step_name = "demo02a-rabbits-mono",
            .description = "Run the rabbits demo",
            .source_path = "src/demo02a_rabbits_mono.zig",
        },
        .{
            .step_name = "demo02b-rabbits-rgb",
            .description = "Run the rabbits RGB demo",
            .source_path = "src/demo02b_rabbits_rgb.zig",
        },
        .{
            .step_name = "demo02c-rabbits-fields",
            .description = "Run the rabbits fields demo",
            .source_path = "src/demo02c_rabbits_fields.zig",
        },
        .{
            .step_name = "demo03-dicuq",
            .description = "Run the DIC UQ demo",
            .source_path = "src/demo03_dicuq.zig",
        },
        .{
            .step_name = "demo04-stereocal",
            .description = "Run the stereo calibration demo",
            .source_path = "src/demo04_stereocal.zig",
        },
        .{
            .step_name = "demo05-cameramodels",
            .description = "Run all camera distortion and PSF models",
            .source_path = "src/demo05_cameramodels.zig",
        },
        .{
            .step_name = "demo06-featurezoo",
            .description = "Run the complete feature-zoo demo",
            .source_path = "src/demo06_featurezoo.zig",
        },
        .{
            .step_name = "demo00b-procedural-quickstart",
            .description = "Render a physical speckle pattern on a plane",
            .source_path = "src/demo00b_procedural_quickstart.zig",
            .forward_args = true,
        },
        .{
            .step_name = "demo01b-procedural-sphere",
            .description = "Render physical speckles on a deforming sphere",
            .source_path = "src/demo01b_procedural_sphere.zig",
            .forward_args = true,
        },
        .{
            .step_name = "demo02d-rabbit-procedural",
            .description = "Run the procedural rabbit demo",
            .source_path = "src/demo02d_rabbit_procedural.zig",
            .forward_args = true,
        },
        .{
            .step_name = "demo07-shaderpipe-quickstart",
            .description = "Run the ShaderSet quickstart demo",
            .source_path = "src/demo07_shaderpipe_quickstart.zig",
        },
        .{
            .step_name = "demo08-shaderpipe-gallery",
            .description = "Run the ShaderPipe gallery demo",
            .source_path = "src/demo08_shaderpipe_gallery.zig",
        },
        .{
            .step_name = "demo09-diciruq",
            .description = "Run the multimodal DIC and IR demo",
            .source_path = "src/demo09_diciruq.zig",
        },
        .{
            .step_name = "demo10-sphere-lit",
            .description = "Run the lit sphere shaderpipe demo",
            .source_path = "src/demo10_sphere_lit.zig",
        },
    };

    const demos_step = b.step("demos", "Run all demo entrypoints with default arguments");
    const has_demo_args = if (b.args) |args| args.len != 0 else false;
    if (has_demo_args) {
        const fail = b.addFail("'demos' does not accept arguments; use 'zig build <demo-target> -- <args>'.");
        demos_step.dependOn(&fail.step);
    }
    const demos_check = b.step("demos-check", "Compile all demo entrypoints without running them");
    const demo_cli_test = b.step("test-demo-cli", "Check help and invalid options for procedural demos");
    for (demos) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            entry,
        );
        run_step.dependOn(&run_artifact.step);
        if (!has_demo_args) demos_step.dependOn(&run_artifact.step);
        const executable = run_artifact.producer.?;
        executable.getEmittedBin().addStepDependencies(demos_check);

        if (entry.forward_args) {
            const help = b.addRunArtifact(executable);
            help.addArg("--help");
            help.expectStdOutMatch("Usage: ");
            demo_cli_test.dependOn(&help.step);

            const invalid = b.addRunArtifact(executable);
            invalid.addArgs(&.{ "--unknown-option", "0" });
            invalid.expectExitCode(1);
            invalid.expectStdErrMatch("--unknown-option");
            demo_cli_test.dependOn(&invalid.step);
        }
    }

    const run_all_demos_step = b.step(
        "run-all-demos",
        "Run all demos sequentially through the public API module",
    );
    if (has_demo_args) {
        const fail = b.addFail("'run-all-demos' does not accept arguments; use 'zig build <demo-target> -- <args>'.");
        run_all_demos_step.dependOn(&fail.step);
    } else {
        const run_all_demos_artifact = addRunStep(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            .{
                .step_name = "run-all-demos",
                .description = "Run all demos sequentially through the public API module",
                .source_path = "src/run_all_demos.zig",
            },
        );
        run_all_demos_step.dependOn(&run_all_demos_artifact.step);
    }

    const generators = [_]RunEntry{
        .{
            .step_name = "gen-gold-basic",
            .description = "Generate the BASIC gold datasets",
            .source_path = "src/gen_gold_basic.zig",
        },
        .{
            .step_name = "gen-gold-full",
            .description = "Generate the FULL gold datasets",
            .source_path = "src/gen_gold_full.zig",
        },
        .{
            .step_name = "gen-gold-failed-distortion",
            .description = "Regenerate only distortion gold cases listed in fails/",
            .source_path = "src/gen_gold_full.zig",
        },
        .{
            .step_name = "gen-gold-verif-zig",
            .description = "Generate the Zig verification oracle inputs",
            .source_path = "src/gen_gold_verif.zig",
        },
    };

    const gold_step = b.step("gen-gold", "Run all gold generation entrypoints");
    for (generators) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            entry,
        );
        if (std.mem.eql(u8, entry.step_name, "gen-gold-failed-distortion")) {
            run_artifact.addArg("--failed-distortion-only");
        }
        run_step.dependOn(&run_artifact.step);
        if (std.mem.eql(u8, entry.step_name, "gen-gold-full")) {
            gold_step.dependOn(&run_artifact.step);
        }
    }

    const gen_verif_python = b.addSystemCommand(&.{
        ".venv/bin/python",
        "src/gengold/gengold_verif.py",
    });
    const gen_verif_zig = addRunStep(
        b,
        target,
        optimize,
        strip,
        build_options_module,
        .{
            .step_name = "gen-gold-verif-zig-internal",
            .description = "Generate verification oracle inputs",
            .source_path = "src/gen_gold_verif.zig",
        },
    );
    gen_verif_python.step.dependOn(&gen_verif_zig.step);
    const gen_verif_step = b.step(
        "gen-gold-verif",
        "Generate focused analytic verification gold",
    );
    gen_verif_step.dependOn(&gen_verif_python.step);

    const benches = [_]RunEntry{
        .{
            .step_name = "bench-speckle-evaluators",
            .description = "Benchmark procedural speckle evaluators",
            .source_path = "src/bench_speckle_evaluators.zig",
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
            .step_name = "bench-tiltraster",
            .description = "Run the tiltraster benchmark",
            .source_path = "src/bench_tiltraster.zig",
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
            .step_name = "bench-dist-psf",
            .description = "Run the distortion and PSF benchmark",
            .source_path = "src/bench_dist_psf.zig",
        },
        .{
            .step_name = "bench-multiroot",
            .description = "Benchmark multi-root hierarchy policies",
            .source_path = "src/bench_multiroot.zig",
        },
        .{
            .step_name = "bench-buffer-psf",
            .description = "Benchmark buffer modes against PSFs and scene densities",
            .source_path = "src/bench_buffer_psf.zig",
        },
    };

    const bench_runs_step = b.step("benches", "Run all benchmark entrypoints with default arguments");
    const bench_args = b.args orelse &.{};
    if (bench_args.len != 0) {
        const fail = b.addFail("'benches' does not accept arguments; use 'zig build bench-<name> -- <args>'.");
        bench_runs_step.dependOn(&fail.step);
    }
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
            strip,
            build_options_module,
            entry,
        );
        run_artifact.addArgs(bench_args);
        run_step.dependOn(&run_artifact.step);
        if (bench_args.len == 0) bench_runs_step.dependOn(&run_artifact.step);

        const install_step = b.step(
            b.fmt("install-{s}", .{entry.step_name}),
            b.fmt("Install the {s} benchmark executable", .{entry.step_name}),
        );
        const install_artifact = addBenchInstallStep(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            entry,
            options,
        );
        install_step.dependOn(&install_artifact.step);
        bench_bins_step.dependOn(&install_artifact.step);
    }

    // Rooted at the public API module, not shared_lib, whose generated wrapper
    // root keeps its entry source private where autodoc cannot follow. A
    // separate object also keeps doc generation out of normal builds. No
    // build_options is injected here, so the -D config options have no effect:
    // docs always describe the f64 / SIMD-on / fast-Newton build.
    const docs_obj = b.addObject(.{
        .name = "riley",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/riley/zig/api.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const docs_install = b.addInstallDirectory(.{
        .source_dir = docs_obj.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Generate API documentation");
    docs_step.dependOn(&docs_install.step);
}

fn addRileySharedLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    riley_module: *std.Build.Module,
) *std.Build.Step.Compile {
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "riley",
        // Zig 0.16's self-hosted Debug backend mispasses floating-point C
        // struct arguments in the camera helpers. Keep the C ABI on LLVM;
        // native demos/tests still use the default backend and optimization.
        .use_llvm = true,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            riley_module,
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
    strip: bool,
    build_options_module: *std.Build.Module,
    riley_module: *std.Build.Module,
    entry: TestEntry,
) *std.Build.Step.Run {
    const test_module = b.createModule(.{
        .root_source_file = b.path(entry.source_path),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .link_libc = true,
    });
    test_module.addImport("build_options", build_options_module);
    test_module.addImport("riley", riley_module);

    const default_runner_path = b.graph.zig_lib_directory.join(
        b.allocator,
        &.{ "compiler", "test_runner.zig" },
    ) catch @panic("OOM locating the Zig test runner.");
    test_module.addImport("default_test_runner", b.createModule(.{
        .root_source_file = .{ .cwd_relative = default_runner_path },
        .target = target,
        .optimize = optimize,
        .strip = strip,
    }));
    const tests = b.addTest(.{
        .name = entry.step_name,
        .root_module = test_module,
        .filters = entry.filters,

        .test_runner = .{
            .path = b.path("src/dev_support/testrunner.zig"),
            .mode = .simple,
        },
    });
    const run_tests = b.addRunArtifact(tests);
    // Use the stock terminal runner rather than its stdout server protocol.
    // Inherit both streams so progress is live and stderr is not mislabelled
    // as a failed command on successful runs. Nonzero exits still fail the build.
    run_tests.stdio = .inherit;
    // Suites read gold and runtime assets and may write failure diagnostics.
    // Cache compilation, but execute the tests on every invocation.
    run_tests.has_side_effects = true;
    return run_tests;
}

fn addRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
) *std.Build.Step.Run {
    // Linking libc selects the C-backed process allocator in optimized builds.
    const executable = b.addExecutable(.{
        .name = entry.step_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            null,
            entry.source_path,
            true,
            .executable,
        ),
    });
    const run_artifact = b.addRunArtifact(executable);
    if (entry.forward_args) {
        if (b.args) |args| run_artifact.addArgs(args);
    }
    return run_artifact;
}

fn addBenchInstallStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
    options: buildoptions.Options,
) *std.Build.Step.InstallArtifact {
    const basename = std.fs.path.basename(entry.source_path);
    const binary_name = benchmarkBinaryName(
        b,
        basename[0 .. basename.len - ".zig".len],
        options,
    );
    const executable = b.addExecutable(.{
        .name = binary_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            null,
            entry.source_path,
            true,
            .executable,
        ),
    });
    return b.addInstallArtifact(executable, .{});
}

fn createBuildOptionsModule(
    b: *std.Build,
    values: buildoptions.Options,
) *std.Build.Module {
    const options = b.addOptions();
    options.addOption(buildoptions.Options, "values", values);
    return options.createModule();
}

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    riley_module: ?*std.Build.Module,
    source_path: []const u8,
    link_libc: bool,
    wrapper_kind: WrapperKind,
) *std.Build.Module {
    const wrapper_text = wrapperSourceText(wrapper_kind);
    const wrapper_files = b.addWriteFiles();
    const wrapper_source = wrapper_files.add(
        b.fmt("{s}.wrapper.zig", .{source_path}),
        wrapper_text,
    );
    const imports = buildWrapperImports(
        b,
        target,
        optimize,
        strip,
        build_options_module,
        riley_module,
        source_path,
        link_libc,
    );
    return b.createModule(.{
        .root_source_file = wrapper_source,
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .link_libc = link_libc,
        .imports = imports,
    });
}

const WrapperKind = enum {
    executable,
    library,
};

fn wrapperSourceText(
    wrapper_kind: WrapperKind,
) []const u8 {
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
        .library =>
        \\const entry_source = @import("entry_source");
        \\pub const build_options = @import("build_options");
        \\comptime {
        \\    _ = entry_source;
        \\}
        \\
        ,
    };
}

fn buildWrapperImports(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    riley_module: ?*std.Build.Module,
    source_path: []const u8,
    link_libc: bool,
) []const std.Build.Module.Import {
    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    imports.append(b.allocator, .{
        .name = "build_options",
        .module = build_options_module,
    }) catch @panic("OOM building imports.");

    const entry_source = b.createModule(.{
        .root_source_file = b.path(source_path),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .link_libc = link_libc,
    });
    if (riley_module) |module| entry_source.addImport("riley", module);
    imports.append(b.allocator, .{
        .name = "entry_source",
        .module = entry_source,
    }) catch @panic("OOM building entry source import.");
    return imports.items;
}

fn benchmarkBinaryName(
    b: *std.Build,
    base_name: []const u8,
    options: buildoptions.Options,
) []const u8 {
    const precision = @tagName(options.precision);
    const simd_tag = if (options.simd == .on) "simd" else "scalar";
    const default_width = options.precision.defaultSimdVectorWidth();

    if (options.simd_vector_width == 0 or options.simd_vector_width == default_width) {
        return b.fmt(
            "{s}_{s}_{s}",
            .{ base_name, precision, simd_tag },
        );
    } else {
        return b.fmt(
            "{s}_{s}_{s}_v{d}",
            .{
                base_name,
                precision,
                simd_tag,
                options.simd_vector_width,
            },
        );
    }
}
