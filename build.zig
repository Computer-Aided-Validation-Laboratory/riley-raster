const std = @import("std");
const speckleconfig = @import("src/riley/zig/speckleconfig.zig");

const riley_version = std.SemanticVersion{
    .major = 2026,
    .minor = 9,
    .patch = 1,
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

const BuildOptions = struct {
    precision: []const u8,
    simd: []const u8,
    newton_solver: []const u8,
    simd_vector_width: u32,
    enable_all_evaluators: bool,
    speckle_mask_samples_per_cell: u8,
    strip: bool,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    var options: BuildOptions = undefined;
    options.strip = b.option(
        bool,
        "strip",
        "Omit debug information to reduce compile memory and binary size",
    ) orelse false;
    options.precision = b.option(
        []const u8,
        "precision",
        "Floating point precision: f64 or f32",
    ) orelse "f64";
    options.simd = b.option([]const u8, "simd", "SIMD mode: on or off") orelse "on";
    options.newton_solver = b.option(
        []const u8,
        "newton-solver",
        "Newton solver mode: fast or robust",
    ) orelse "fast";
    options.simd_vector_width = b.option(
        u32,
        "simd-vector-width",
        "SIMD vector width (0 to use default for precision)",
    ) orelse 0;
    options.enable_all_evaluators = b.option(
        bool,
        "enable-all-evaluators",
        "Enable experimental runtime evaluator and neighbor overrides (native Zig only)",
    ) orelse false;
    options.speckle_mask_samples_per_cell = b.option(
        u8,
        "speckle-mask-samples-per-cell",
        "Speckle mask/classification resolution per cell: 8, 12, or 16",
    ) orelse speckleconfig.default_mask_samples_per_cell;
    if (!speckleconfig.isValidMaskSamplesPerCell(options.speckle_mask_samples_per_cell)) {
        @panic("Supported -Dspeckle-mask-samples-per-cell values are 8, 12, and 16.");
    }
    validatePrecision(options.precision);
    validateSimd(options.simd);
    validateNewtonSolver(options.newton_solver);

    const build_options_module = createBuildOptionsModule(b, options);
    const shared_lib = addRileySharedLibrary(
        b,
        target,
        optimize,
        options.strip,
        build_options_module,
    );
    shared_lib.installHeader(
        b.path("src/riley/cython/riley.h"),
        "riley.h",
    );
    b.installArtifact(shared_lib);

    const tests = [_]TestEntry{
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
            .step_name = "test-procedural-speckles",
            .description = "Run runtime procedural speckle resource tests",
            .source_path = "src/testproceduralspeckles.zig",
        },
        .{
            .step_name = "test-speckle-mask",
            .description = "Run runtime speckle generation, sampling, and demo argument tests",
            .source_path = "src/testproceduralmasks.zig",
        },
    };

    for (tests) |entry| {
        const test_step = b.step(entry.step_name, entry.description);
        const test_run = addTestRunStep(b, .ReleaseSafe, entry, options);
        test_step.dependOn(&test_run.step);
    }

    const speckle_suites = [_]TestEntry{
        .{
            .step_name = "mask",
            .description = "Run runtime speckle generation and sampling tests",
            .source_path = "src/testproceduralmasks.zig",
        },
        .{
            .step_name = "resources",
            .description = "Run runtime speckle production resource tests",
            .source_path = "src/testproceduralspeckles.zig",
        },
    };
    const speckle_configs_step = b.step(
        "test-speckle-configs",
        "Run runtime speckle tests with default and experimental evaluator availability",
    );
    for ([_]bool{ false, true }) |experimental| {
        const step_name = if (experimental) "test-speckle-experimental" else "test-speckle-default";
        const test_step = b.step(step_name, "Run one runtime speckle evaluator availability mode");
        var test_options = options;
        test_options.enable_all_evaluators = experimental;
        for (speckle_suites) |suite| {
            var entry = suite;
            entry.step_name = b.fmt("{s}-{s}", .{ step_name, suite.step_name });
            const test_run = addTestRunStep(b, .ReleaseSafe, entry, test_options);
            test_step.dependOn(&test_run.step);
        }
        speckle_configs_step.dependOn(test_step);
    }

    const demos = [_]RunEntry{
        .{
            .step_name = "demo0-quickstart",
            .description = "Run the triangle quickstart demo",
            .source_path = "src/demo0_quickstart.zig",
        },
        .{
            .step_name = "demo1-sphere200",
            .description = "Run the sphere200 demo",
            .source_path = "src/demo1_sphere200.zig",
        },
        .{
            .step_name = "demo-procedural-sphere200",
            .description = "Run the procedural sphere200 comparison demo",
            .source_path = "src/demoproceduralsphere200.zig",
        },
        .{
            .step_name = "demo-procedural-rabbit",
            .description = "Run the procedural rabbit demo",
            .source_path = "src/demoproceduralrabbit.zig",
        },
        .{
            .step_name = "demo2-psf",
            .description = "Run the Gaussian PSF demo",
            .source_path = "src/demo2_psf.zig",
        },
        .{
            .step_name = "demo3-rabbits",
            .description = "Run the rabbits demo",
            .source_path = "src/demo3_rabbits.zig",
        },
        .{
            .step_name = "demo4-rabbits-rgb",
            .description = "Run the rabbits RGB demo",
            .source_path = "src/demo4_rabbits_rgb.zig",
        },
        .{
            .step_name = "demo5-rabbits-fields",
            .description = "Run the rabbits fields demo",
            .source_path = "src/demo5_rabbits_fields.zig",
        },
        .{
            .step_name = "demo6-dicuq",
            .description = "Run the DIC UQ demo",
            .source_path = "src/demo6_dicuq.zig",
        },
        .{
            .step_name = "demo8-stereocal",
            .description = "Run the stereo calibration demo",
            .source_path = "src/demo8_stereocal.zig",
        },
        .{
            .step_name = "demo9-feature-zoo",
            .description = "Run the complete feature-zoo demo",
            .source_path = "src/demo9_feature_zoo.zig",
        },
        .{
            .step_name = "demo-procedural-speckles",
            .description = "Run the procedural speckle prototype demo",
            .source_path = "src/demoproceduralspeckles.zig",
        },
    };

    const demos_step = b.step("demos", "Run all demo entrypoints");
    for (demos) |entry| {
        const run_step = b.step(entry.step_name, entry.description);
        const run_artifact = addRunStep(
            b,
            target,
            optimize,
            options.strip,
            build_options_module,
            entry,
        );
        run_step.dependOn(&run_artifact.step);
        demos_step.dependOn(&run_artifact.step);
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
            options.strip,
            build_options_module,
            entry,
        );
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
        options.strip,
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
            options.strip,
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
            .root_source_file = b.path("src/riley/zig/riley.zig"),
            .target = target,
            .optimize = optimize,
            .strip = options.strip,
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
) *std.Build.Step.Compile {
    const shared_lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "riley",
        .root_module = createRootModule(
            b,
            target,
            optimize,
            strip,
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
    optimize: std.builtin.OptimizeMode,
    entry: TestEntry,
    options: BuildOptions,
) *std.Build.Step.Run {
    const run_step = b.addSystemCommand(&.{
        "sh",
        "-c",
        \\set -eu
        \\step_name="$1"
        \\src="$2"
        \\precision="$3"
        \\simd="$4"
        \\newton_solver="$5"
        \\simd_vector_width="$6"
        \\enable_all_evaluators="$7"
        \\speckle_mask_samples_per_cell="$8"
        \\zigexe="$9"
        \\opt="${10}"
        \\strip_arg="${11}"
        \\cache_root=".zig-cache/riley-test"
        \\mkdir -p "$cache_root"
        \\src_hash="$(
        \\    find src -type f -print0 |
        \\    sort -z |
        \\    xargs -0 sha256sum |
        \\    sha256sum |
        \\    cut -d' ' -f1
        \\)"
        \\tree_dir="${cache_root}/${step_name}_${precision}_${simd}_${newton_solver}"
        \\tree_dir="${tree_dir}_${simd_vector_width}_${enable_all_evaluators}"
        \\tree_dir="${tree_dir}_${speckle_mask_samples_per_cell}_${opt}_${strip_arg}_${src_hash}"
        \\if [ ! -d "$tree_dir" ]; then
        \\    lock_dir="${tree_dir}.lock"
        \\    while ! mkdir "$lock_dir" 2>/dev/null; do
        \\        sleep 0.1
        \\    done
        \\    cleanup() {
        \\        rmdir "$lock_dir"
        \\    }
        \\    trap cleanup EXIT
        \\    if [ ! -d "$tree_dir" ]; then
        \\        mkdir -p "$tree_dir"
        \\        cp -a src "$tree_dir/src"
        \\        override_file="$tree_dir/src/riley/zig/buildconfig_override.zig"
        \\        {
        \\            printf 'pub const enabled = true;\n'
        \\            printf 'pub const precision = "%s";\n' "$precision"
        \\            printf 'pub const simd = "%s";\n' "$simd"
        \\            printf 'pub const newton_solver = "%s";\n' "$newton_solver"
        \\            printf 'pub const simd_vector_width: comptime_int = %s;\n' "$simd_vector_width"
        \\            printf 'pub const enable_all_evaluators = %s;\n' "$enable_all_evaluators"
        \\            printf 'pub const speckle_mask_samples_per_cell: comptime_int = %s;\n' \
        \\                "$speckle_mask_samples_per_cell"
        \\        } > "$override_file"
        \\        expected_config_file="$tree_dir/src/tests/expected_speckle_config.zig"
        \\        {
        \\            printf 'pub const enable_all_evaluators = %s;\n' "$enable_all_evaluators"
        \\            printf 'pub const speckle_mask_samples_per_cell: comptime_int = %s;\n' \
        \\                "$speckle_mask_samples_per_cell"
        \\        } > "$expected_config_file"
        \\    fi
        \\fi
        \\"$zigexe" test -lc -O "$opt" "$strip_arg" "$tree_dir/$src"
        ,
        "--",
        entry.step_name,
        entry.source_path,
        options.precision,
        options.simd,
        options.newton_solver,
        b.fmt("{d}", .{options.simd_vector_width}),
        if (options.enable_all_evaluators) "true" else "false",
        b.fmt("{d}", .{options.speckle_mask_samples_per_cell}),
        b.graph.zig_exe,
        @tagName(optimize),
        if (options.strip) "-fstrip" else "-fno-strip",
    });
    return run_step;
}

fn addRunStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
) *std.Build.Step.Run {
    const executable = b.addExecutable(.{
        .name = entry.step_name,
        .root_module = createRootModule(
            b,
            target,
            optimize,
            strip,
            build_options_module,
            entry.source_path,
            false,
            .executable,
        ),
    });
    const run_artifact = b.addRunArtifact(executable);
    if (b.args) |args| run_artifact.addArgs(args);
    return run_artifact;
}

fn addBenchInstallStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    build_options_module: *std.Build.Module,
    entry: RunEntry,
    options: BuildOptions,
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
            options.strip,
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

fn createBuildOptionsModule(b: *std.Build, build_options: BuildOptions) *std.Build.Module {
    const options = b.addOptions();
    options.addOption([]const u8, "precision", build_options.precision);
    options.addOption([]const u8, "simd", build_options.simd);
    options.addOption([]const u8, "newton_solver", build_options.newton_solver);
    options.addOption(u32, "simd_vector_width", build_options.simd_vector_width);
    options.addOption(bool, "enable_all_evaluators", build_options.enable_all_evaluators);
    options.addOption(u8, "speckle_mask_samples_per_cell", build_options.speckle_mask_samples_per_cell);
    return options.createModule();
}

fn createRootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    build_options_module: *std.Build.Module,
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
        build_options_module,
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
    build_options_module: *std.Build.Module,
    source_path: []const u8,
    link_libc: bool,
) []const std.Build.Module.Import {
    var imports: std.ArrayList(std.Build.Module.Import) = .empty;
    imports.append(b.allocator, .{
        .name = "build_options",
        .module = build_options_module,
    }) catch @panic("OOM building imports.");

    imports.append(b.allocator, .{
        .name = "entry_source",
        .module = b.createModule(.{
            .root_source_file = b.path(source_path),
            .target = target,
            .optimize = optimize,
            .link_libc = link_libc,
        }),
    }) catch @panic("OOM building entry source import.");
    return imports.items;
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

fn validateNewtonSolver(newton_solver: []const u8) void {
    if (std.mem.eql(u8, newton_solver, "fast") or
        std.mem.eql(u8, newton_solver, "robust"))
    {
        return;
    }
    @panic("Supported -Dnewton-solver values are fast and robust.");
}

fn benchmarkBinaryName(
    b: *std.Build,
    base_name: []const u8,
    options: BuildOptions,
) []const u8 {
    const simd_tag = if (std.mem.eql(u8, options.simd, "on")) "simd" else "scalar";
    const default_width: u32 = if (std.mem.eql(u8, options.precision, "f32")) 16 else 8;

    if (options.simd_vector_width == 0 or options.simd_vector_width == default_width) {
        return b.fmt(
            "{s}_{s}_{s}",
            .{ base_name, options.precision, simd_tag },
        );
    } else {
        return b.fmt(
            "{s}_{s}_{s}_v{d}",
            .{
                base_name,
                options.precision,
                simd_tag,
                options.simd_vector_width,
            },
        );
    }
}
