# Riley Developer Guide
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**


> [!IMPORTANT]
> **AI AGENTS — REQUIRED TEST CONFIGURATION: `f64` WITH SIMD ON.**
> Run tests only with `-Dprecision=f64 -Dsimd=on` unless the user explicitly
> instructs you to run another combination. Do not run `f32`, scalar
> (`-Dsimd=off`), or precision/SIMD matrix sweeps on your own. A general request
> to implement, test, verify, or complete a plan does not authorize extra
> precision/SIMD combinations. This rule avoids unnecessary
> compilation, runtime, and token costs.


## Development Guides
The `dev/` directory provides comprehensive architectural, mathematical, testing, and conventions documentation for Riley developers:

- [**`dev/TESTING.md`**](./TESTING.md): Testing architecture, quickstart commands, scene descriptions, suite coverage, reference generation and automated regression diagnostics.
- [**`dev/THEORY.md`**](./THEORY.md): Mathematical foundations and engine design details, including polynomial camera distortion formulation, distortion-aware rasterisation frontend bounds, render thread budgets, and image save mode mechanics.
- [**`dev/ASSUMPTIONS.md`**](./ASSUMPTIONS.md): Supported engineering operating envelope, mesh validity contracts, conservative numerical margins, and reasoning guidelines for review.
- [**`dev/MESHCONVENTION.md`**](./MESHCONVENTION.md): Riley standard mesh representation, surface element definitions (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`), 3D continuum elements, node ordering, and connectivity conventions.
- [**`dev/FILESTRUCTURE.md`**](./FILESTRUCTURE.md): Repository layout, module naming rules (`io`, `ops`, `kernel`), scalar/SIMD file splitting, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](./ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.

## API and Render Data Flow

The main user-facing Zig API is [api.zig](../src/riley/zig/api.zig). It explicitly
exports the declarations assembled in [api/core.zig](../src/riley/zig/api/core.zig),
plus the `dataio`, `maths`, and `ops` namespaces. Render functions and input types
such as `MeshInput`, `CameraInput`, `RasterConfig`, and `ResolverInput` are exposed
at the top level. `dataio` contains public load/save functions; `maths` contains
numerical types; `ops` contains scene arrangement, camera framing, and shader-input
construction helpers. Internal modules import their declaration owners directly.

The render entry functions `raster` and `rasterInto` are defined in
[riley.zig](../src/riley/zig/riley.zig), which is the starting point for tracing
render execution. Its flow is:

1. Resolve render parallelism and validate/summarise the inputs according to
   `RasterConfig.validation`.
2. Prepare cameras and create mesh Static data for the shader roles in use.
3. Dispatch camera/frame jobs; use `meshpipeline.zig` to prepare frame geometry,
   culling/hulls, and shader data from Static inputs, then bin elements into tiles.
4. Call `rasterengine.zig` for rasterisation and shading, then resolve/filter image
   buffers and save and/or return images according to the output configuration.

Mesh Static data is shared across frame jobs and owned by the render's static arena;
frame preparation borrows it. Public inputs are validated upstream according to
the selected validation mode, rather than repeatedly in raster and shader kernels.

Repository demos import `riley/zig/api.zig` by relative path. External consumers
register `api.zig` as their named `riley` module. The C implementation is in
[c-riley.zig](../src/riley/zig/c-riley.zig), with declarations in
[riley.h](../src/riley/cython/riley.h). Python exports are assembled in
[__init__.py](../src/riley/__init__.py), with input types in
[types.py](../src/riley/types.py) and calls into the C ABI through Cython.

## Testing Architecture & Core Packaged Suites
Riley provides a layered testing architecture designed for fast routine verification, rigorous mathematical validation, and exhaustive factorial test coverage:

### Optimization Modes & Execution Policy

Riley strictly separates optimization modes by task type:
- **Verification and Basic test suites (`test-verif`, `test-basic`)**: Run in **Debug mode without optimisation flags** (default `zig build`), ensuring fastest compilation and developer feedback.
- **Full test suite (`test-full`)**: Run in **ReleaseSafe mode** (`-Doptimize=ReleaseSafe`), enabling optimized factorial sweeps with safety assertions active.
- **Benchmarks and Performance profiling (`bench-*`, `./scripts/bench_*.py`, `./scripts/perf_*.py`)**: Run in **ReleaseFast mode** (`-Doptimize=ReleaseFast`), ensuring maximum compiler vectorization and realistic production throughput.

> [!IMPORTANT]
> The combined target `zig build test-verif-basic` is intended **primarily for CI pipelines**. For **local development**, prefer running `zig build test-verif` and `zig build test-basic` as separate terminal processes in parallel when resources permit.

### Quick Commands

```shell
# Local Development: Run verif and basic in parallel across two terminal tabs/jobs (Debug)
zig build test-verif & zig build test-basic & wait

# CI Combined Verification & Basic Suite (Debug)
zig build test-verif-basic

# Analytic Verification Suite (Mathematical & Numerical Validation in Debug)
zig build test-verif

# Basic Test Suite (Fast Core Feature Coverage in Debug)
zig build test-basic

# Full Test Suite (Exhaustive Factorial System & Threading Coverage in ReleaseSafe)
zig build gen-gold-full -Doptimize=ReleaseSafe  # Generate Full gold (if needed)
zig build test-full -Doptimize=ReleaseSafe

# Warning-only diagnostics for invalid-Jacobian element frames
zig build diag-badjac

# Python Integration Suite
pytest --pyargs riley.pytests -vs

# Compile all native benchmarks (ReleaseFast, f64, SIMD on)
python scripts/compile_benchmarks.py

# Minimal execution check for every native benchmark
python scripts/run_all_bench.py --profile smoke
```

### Core Suites Summary

| Suite Name | Command | Primary Role | Reference Data |
| :--- | :--- | :--- | :--- |
| **Verification Suite** | `zig build test-verif` | Inverse solver recovery, silhouette area/centroid, depth ordering, and camera distortion oracles (Debug) | `gold/verif/` |
| **Basic Suite** | `zig build test-basic` | Fast coverage across 1-element, 2-shape FE interaction, and feature zoo cases (Debug) | `gold/basic/` |
| **Combined Core Suite** | `zig build test-verif-basic` | Primarily for CI: runs verif and basic in one Debug test executable | `gold/verif/`, `gold/basic/` |
| **Full Suite** | `zig build test-full -Doptimize=ReleaseSafe` | Exhaustive sweeps over shaders, textures, camera I/O, maths SIMD, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs in ReleaseSafe | `gold/full_*/` |
| **Bad-Jacobian Diagnostics** | `zig build diag-badjac` | Diagnostic utility (`dev_support/diag_badjac.zig`) for warning-only renders of intentionally folded one-element frames under `fails/*_full_badjac/` | Existing basic and full-hull gold |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |

> [!NOTE]
> For scene descriptions, suite coverage, reference generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](./TESTING.md).

## Precision and SIMD Build Matrix
The `zig build` workflow supports direct control over precision, SIMD mode, Newton solver mode, and SIMD vector width:

```shell
zig build <STEP> -Dprecision=f64 -Dsimd=on
zig build <STEP> -Dprecision=f64 -Dsimd=off
zig build <STEP> -Dprecision=f32 -Dsimd=on
zig build <STEP> -Dprecision=f32 -Dsimd=off
zig build <STEP> -Dnewton-solver=robust
zig build <STEP> -Dsimd-vector-width=8
```

Default development checks and the required AI-agent configuration (Debug for verif/basic, ReleaseSafe for full):

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on
zig build test-basic -Dprecision=f64 -Dsimd=on
zig build test-full -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

**Alternative configurations — AI agents must run these only when the user explicitly requests the corresponding combinations.** These are opt-in examples, not a routine verification checklist:

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on
zig build test-basic -Dprecision=f64 -Dsimd=on

zig build test-basic -Dprecision=f64 -Dsimd=off
zig build test-basic -Dprecision=f32 -Dsimd=on
zig build test-basic -Dprecision=f32 -Dsimd=off
```

## Benchmarks

All native benchmarks use the same Python compiler and execution harness.
The benchmark catalogue in `scripts/benchmark_catalog.py` defines their names,
Zig install targets, binary names, and supported experiment matrices.

| Name | Python entry point | Shared experiment | Specialised study |
| --- | --- | --- | --- |
| `dicuq` | `scripts/bench_dicuq.py` | `hulls` | DIC UQ |
| `fullraster` | `scripts/bench_fullraster.py` | `hulls` | — |
| `tiltraster` | `scripts/bench_tiltraster.py` | `hulls` | Raster/shader experiments 1–5 |
| `geom` | `scripts/bench_geom.py` | `hulls` | — |
| `sphere2000` | `scripts/bench_sphere2000.py` | `hulls` | — |
| `sphere2000zoom` | `scripts/bench_sphere2000zoom.py` | `hulls` | — |
| `thread_geom` | `scripts/bench_thread_geom.py` | `hulls` | — |
| `dist_psf` | `scripts/bench_dist_psf.py` | `distortion` | Distortion/PSF experiments |
| `multiroot` | `scripts/bench_multiroot.py` | `solver`, `shaders` | Root policies, shading, and edge preparation |
| `buffer_psf` | `scripts/bench_buffer_psf.py` | `buffers` | Buffer/PSF/density/SSAA experiments |

### Compilation and naming

```shell
# All benchmarks, or selected benchmarks
python scripts/compile_benchmarks.py
python scripts/compile_benchmarks.py geom multiroot

# Explicit alternative configuration when needed
python scripts/compile_benchmarks.py tiltraster --precision f64 --simd on --lanes 4
```

Compilation always uses ReleaseFast. Use `--jobs N` to set concurrent builds
(default: two). The default is f64 with SIMD on; alternative
precision/SIMD configurations require explicit options. Binaries install into
`bin/`, with names such as `bench_geom_f64_simd`, `bench_geom_f64_scalar`, and
`bench_tiltraster_f64_simd_v4`. Default vector widths omit the `_vN` suffix.
No shorthand binary copies are produced.

Every benchmark also has native Zig run and install hooks. Convert underscores
in catalogue names to hyphens in build targets:

```shell
zig build install-bench-thread-geom --prefix . -Doptimize=ReleaseFast -Dprecision=f64 -Dsimd=on
zig build install-bench-bins --prefix . -Doptimize=ReleaseFast -Dprecision=f64 -Dsimd=on
```

### Shared execution harness

Every `bench_<name>.py` supports the same options. Compilation is separate unless
`--build` is supplied. Smoke profiles use one repeat, small images, and a reduced
case selection; they check execution, not representative performance. The DIC
UQ smoke profile uses the bundled `platehole3d_2mr_7f` dataset; its default
large study requires `data/FE/platehole3d_6mr_63f/`. Override the input using
`-- --data-dir PATH/` (including the trailing slash).

```shell
python scripts/bench_geom.py --profile smoke --build
python scripts/run_all_bench.py --profile smoke
python scripts/bench_geom.py --runs 5
python scripts/bench_geom.py --experiment hulls --runs 5
python scripts/bench_buffer_psf.py --experiment buffers --profile smoke
python scripts/bench_multiroot.py --dry-run
```

Shared options include `--profile`, `--runs`, `--precision`, `--simd`, `--lanes`,
`--binary`, `--out-root`, `--build`, `--dry-run`, and `--experiment`.
Pass driver-specific arguments after `--`. Defaults use one thread and memory
output. Each invocation writes its native CSVs, exact command, configuration
metadata, execution status/duration, stdout, and stderr under `out/benchmarks/<name>/<timestamp>/`.
A failed build or benchmark exits unsuccessfully; inspect that run's stderr.
Specialised CSV schemas and counters remain native to each benchmark. Threaded
geometry reports the mean over `--runs` repeats for each scheduling configuration;
its smoke profile uses one frame and one mesh copy.

Check the Python harness contract without compiling or rendering:

```shell
python -m unittest discover -s scripts/tests -v
```

### Specialised experiments

Preserved experiment matrices live in `scripts/study_*.py`; select them through
the corresponding entry point with `--study`. Arguments after `--` belong to the
study, whose own CLI controls its matrix, output locations, and build behaviour.
Use `--study -- --help` to inspect those options. Shared `--runs` is forwarded;
`--dry-run` prints the study invocation without executing it.

```shell
python scripts/bench_tiltraster.py --study -- --no-experiment1 --no-experiment2 --experiment3
python scripts/bench_multiroot.py --study -- --quick --skip-build
python scripts/bench_buffer_psf.py --study -- --quick --skip-build
```

Studies also use the shared command/logging/failure-handling runner.
Study build adapters use the canonical targets and `bin/` installation location.

The multiroot shading study compares checker, nodal, direct Catmull–Rom texture,
and a five-stage pipe (texture, checker, nodal, blend, affine map, then modulation
resolution). It contains no lookup-table stages or lookup-table resolvers. It
covers multi-root fast/robust solving and one-root controls in all three buffer
modes. Each scene contains quad4, tri6, quad8, and quad9 elements.

```shell
python scripts/compile_benchmarks.py multiroot
python scripts/bench_multiroot.py --study -- --shading-study --typical --runs 15 --warmup 3 --skip-build
python scripts/bench_multiroot.py --study -- --shading-study --typical --runs 15 --warmup 3 --binary out/baseline/bench_multiroot_f64_simd
```

The typical profile uses 1,000 elements, 1024×1024 pixels, SSAA=2, and one thread.
The study writes per-case raw runs and consolidated median/MAD summaries. Preserve
baseline binaries and keep CPU affinity and system load consistent for comparisons.

### Geometry-heavy static preparation experiment

The tilt-raster `static_preparation` profile uses the `geom_1e5` datasets
(99,856 quad or 100,352 triangle elements), 1600×1000 pixels, SSAA=1, and one
thread. Its 120 direct/stress-pipe cases exercise all six element modes and
nodal, texture, function, and composed shader preparation.

```shell
python scripts/bench_tiltraster.py --profile static_preparation --runs 5 --build
python scripts/bench_tiltraster.py --profile static_preparation --runs 5 --binary out/baseline/bench_tiltraster_f64_simd
```

Preserve baseline binaries before rebuilding. Use the same CPU affinity and
avoid concurrent compiler/test jobs when measuring. Compare geometry and
end-to-end timings: geometry excludes static setup, while end-to-end includes it.
Retain raw samples and compare matching datasets, configurations, and case matrices.

### Performance regression checks

The reference-based workflow remains separate from experiment orchestration.
It uses the canonical f64/SIMD binary names. `test_perf_all.py` compares new
runs against local timing gold in `gold/perf_<case>_<profile>/`. Committed timing
references live in `gold/perf_stats_ref/` and are compared separately by
`test_perf_ref_to_gold.py`. Reports live under `perf/dev_single_threaded/` or
`perf/dev_4_threaded/`, according to the selected profile:

```shell
python scripts/compile_benchmarks.py fullraster geom sphere2000 sphere2000zoom
python scripts/gen_gold_perf_all.py
python scripts/test_perf_all.py
```

Generate references deliberately; do not regenerate them during ordinary checks.
The individual `test_perf_<name>.py` scripts support profiles such as `1thread`
and `4thread`. Paper studies retain their separate `paper_bench*.py` workflow;
`scripts/legacy/` contains archived scripts outside the supported native harness.

## Additional Notes

- Demos import the public API through `riley/zig/api.zig`, so plain
  `zig run ./src/demo00_quickstart.zig` works from the repository root without
  `-lc` or named-module flags. Direct demo runs use f64 with SIMD enabled;
  optionally add `-O ReleaseFast` for larger scenes. Run all demos with
  `zig run ./src/run_all_demos.zig -O ReleaseFast`.
- Native executable build targets (including demos and benchmarks) link libc.
  Optimized builds therefore use the C-backed process allocator; Debug retains
  Zig's debug allocator. Standalone `zig run` can still run without libc; add
  `-lc` to match the linkage and allocator selection of the build targets.
  Demo build targets retain the build-options wrapper without a redundant named
  `riley` dependency. Use `zig build demo00-quickstart` or the
  suite drivers to select precision, SIMD, solver, or vector-width options.
  Tests such as `test-public-api` that import the named module use `zig build`.
- Native TIFF loading and saving do not require libc or libtiff. The optional
  `imageio.CLoadTIFF` helper dynamically loads libtiff; demos use the native path.
- The public C ABI uses f64 with SIMD enabled; native Zig configuration options
  do not extend the supported C/Python ABI configurations.
- The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses floating-point struct arguments at the C boundary in camera helpers. Native demo/test backend selection is unchanged.
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](./THEORY.md).
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.

