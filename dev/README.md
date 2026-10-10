# Riley Developer Guide
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**

## Development Guides
The `dev/` directory provides comprehensive architectural, mathematical, testing, and conventions documentation for Riley developers:

- [**`dev/TESTING.md`**](file:///home/lloydf/riley-raster/dev/TESTING.md): Complete testing architecture, quickstart commands, descriptions of the 4 test scenes, detailed breakdown of all 8 test suites, gold reference generation, and automated regression diagnostics.
- [**`dev/THEORY.md`**](file:///home/lloydf/riley-raster/dev/THEORY.md): Mathematical foundations and engine design details, including polynomial camera distortion formulation, distortion-aware rasterisation frontend bounds, render thread budgets, and image save mode mechanics.
- [**`dev/ASSUMPTIONS.md`**](file:///home/lloydf/riley-raster/dev/ASSUMPTIONS.md): Supported engineering operating envelope, mesh validity contracts, conservative numerical margins, and reasoning guidelines for review.
- [**`dev/MESHCONVENTION.md`**](file:///home/lloydf/riley-raster/dev/MESHCONVENTION.md): Riley standard mesh representation, surface element definitions (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`), 3D continuum elements, node ordering, and connectivity conventions.
- [**`dev/FILESTRUCTURE.md`**](file:///home/lloydf/riley-raster/dev/FILESTRUCTURE.md): Repository layout, module naming rules (`io`, `ops`, `kernel`), scalar/SIMD file splitting, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](file:///home/lloydf/riley-raster/dev/ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.

## Testing Architecture & Core Packaged Suites
Riley provides a layered testing architecture designed for fast routine verification, rigorous mathematical validation, and exhaustive factorial test coverage:

### Quick Commands

For day-to-day development and routine checks, the **verification** and **basic**
suites (`test-verif`, `test-basic`, and `test-verif-basic`) should be run in
**Debug mode without optimization flags** (the default `zig build` mode), which compiles
much faster. The **full test suite** (`test-full`) tests multi-threaded execution
and factorial sweeps and should be run in **ReleaseSafe mode** (`-Doptimize=ReleaseSafe`)
for optimized execution with safety checks.

Suite targets use Zig's standard terminal test runner with inherited console streams. Status 
and suite/case timings are written to stdout using a buffered `std.Io` writer flushed after 
each message; failure diagnostics remain on stderr. The test runner reports test counts; use 
`--summary all` for build/run timings. Clearing `.zig-cache` is safe and only forces a rebuild.

```shell
# 1. Combined Verification and Basic Suites (preferred routine development in Debug)
zig build test-verif-basic

# 2. Analytic Verification Suite (Mathematical & Numerical Validation in Debug)
zig build test-verif

# 3. Basic Test Suite (Fast Core Feature Coverage in Debug)
zig build test-basic

# 4. Full Test Suite (Exhaustive Factorial System & Threading Coverage in ReleaseSafe)
zig build gen-gold-full -Doptimize=ReleaseSafe  # Generate Full gold (if needed)
zig build test-full -Doptimize=ReleaseSafe

# 5. Python Integration Suite
pytest --pyargs riley.pytests -vs
```

### Core Suites Summary

| Suite Name | Command | Primary Role | Reference Data |
| :--- | :--- | :--- | :--- |
| **Combined Core Suite** | `zig build test-verif-basic` | Fast routine development/verification in Debug mode (no optimization flags) | `gold/verif/`, `gold/basic/` |
| **Verification Suite** | `zig build test-verif` | Inverse solver recovery, silhouette area/centroid, depth ordering, and camera distortion oracles (Debug) | `gold/verif/` |
| **Basic Suite** | `zig build test-basic` | Fast coverage across 1-element, 2-shape FE interaction, and feature zoo cases (Debug) | `gold/basic/` |
| **Full Suite** | `zig build test-full -Doptimize=ReleaseSafe` | Exhaustive sweeps over shaders, textures, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs in ReleaseSafe | `gold/full_*/` |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |

> [!NOTE]
> For complete documentation of all 4 test scenes, 8 sub-suites, gold generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](file:///home/lloydf/riley-raster/dev/TESTING.md).

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

Suggested first-pass development checks on the main production path (Debug for verif/basic, ReleaseSafe for full):

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on
zig build test-basic -Dprecision=f64 -Dsimd=on
zig build test-full -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

For broader matrix checks across precisions and SIMD modes:

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on
zig build test-basic -Dprecision=f64 -Dsimd=on

zig build test-basic -Dprecision=f64 -Dsimd=off
zig build test-basic -Dprecision=f32 -Dsimd=on
zig build test-basic -Dprecision=f32 -Dsimd=off
```

## Benchmark Binaries
The benchmark entry points exposed through `zig build` are:

- `bench-dicuq`
- `bench-fullraster`
- `bench-tiltraster`
- `bench-geom`
- `bench-sphere2000`
- `bench-sphere2000zoom`
- `bench-thread-geom`

To install benchmark binaries into `./bin/`:

```shell
zig build install-bench-fullraster -Doptimize=ReleaseFast --prefix .
zig build install-bench-tiltraster -Doptimize=ReleaseFast --prefix .
zig build install-bench-geom -Doptimize=ReleaseFast --prefix .
zig build install-bench-sphere2000 -Doptimize=ReleaseFast --prefix .
zig build install-bench-sphere2000zoom -Doptimize=ReleaseFast --prefix .
zig build install-bench-dicuq -Doptimize=ReleaseFast --prefix .
zig build install-bench-bins -Doptimize=ReleaseFast --prefix .
```

The installed binaries land in `./bin/`.

## Performance Regression Scripts
The older performance regression workflow uses the scripts in `./scripts/` with reference data under `./perf/`.

Compile the standard SIMD benchmark binaries:

```shell
python ./scripts/compile_para_simd_benchmarks.py
```

Generate local gold performance statistics:

```shell
python ./scripts/gen_gold_perf_all.py
```

Run performance regression checks against those references:

```shell
python ./scripts/test_perf_all.py
```

You can also isolate a single case:

```shell
python ./scripts/test_perf_fullraster.py
python ./scripts/test_perf_geom.py
python ./scripts/test_perf_sphere2000.py
python ./scripts/test_perf_sphere2000zoom.py
```

These scripts support perf profiles such as `1thread` and `4thread` through their `--profile` flag.

## Benchmark Experiment Orchestration
For the newer raster-performance study workflow, use:

- `scripts/compile_perf_all.py`
- `scripts/bench_perf_raster.py`

First compile the benchmark binaries used by the experiment matrix:

```shell
python ./scripts/compile_perf_all.py
```

This builds the configured `bench_tiltraster` variants into `./bin/`.

Then run the raster benchmark experiments:

```shell
python ./scripts/bench_perf_raster.py
```

By default this uses the constants defined at the top of the script, including which experiments are enabled, the run count, the active SSAA levels, and the case matrix.

Typical useful commands are:

```shell
python ./scripts/bench_perf_raster.py --runs 5
python ./scripts/bench_perf_raster.py --dry-run
python ./scripts/bench_perf_raster.py --out-root out/bench_stats_perf_manual
python ./scripts/bench_perf_raster.py --image-out-dir out/bench_images_perf_manual
```

The script writes:

- per-run experiment output under `./out/bench_stats_perf/<timestamp>/`
- rendered images under `./out/bench_images_perf/`
- a timing summary CSV such as `./out/time_bench_perf_raster_<timestamp>.csv`

The current experiment groups are driven directly by constants in the script:

- `DEFAULT_EXPERIMENT1`
- `DEFAULT_EXPERIMENT2`
- `EXPERIMENT1_SUB_SAMPLES`
- `EXPERIMENT2_SUB_SAMPLES`
- `EXPERIMENT1_CASES_BASE`

If you want to change the study matrix, edit those constants first.

## Additional Notes

- Plain `zig run` and `zig test` under `./src/` use the default Riley path of `f64` with SIMD enabled. Run the suite drivers through `zig build` to select precision, SIMD, solver, or vector-width options.
- The public C ABI is fixed to that same production path.
- The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses floating-point struct arguments at the C boundary in camera helpers. Native demo/test backend selection is unchanged.
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](file:///home/lloydf/riley-raster/dev/THEORY.md).
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.

