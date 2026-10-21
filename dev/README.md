# Riley Developer Guide
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**

## Development Guides
The `dev/` directory provides comprehensive architectural, mathematical, testing, and conventions documentation for Riley developers:

- [**`dev/TESTING.md`**](./dev/TESTING.md): Complete testing architecture, quickstart commands, descriptions of the 4 test scenes, detailed breakdown of all 8 test suites, gold reference generation, and automated regression diagnostics.
- [**`dev/THEORY.md`**](./dev/THEORY.md): Mathematical foundations and engine design details, including polynomial camera distortion formulation, distortion-aware rasterisation frontend bounds, render thread budgets, and image save mode mechanics.
- [**`dev/ASSUMPTIONS.md`**](./dev/ASSUMPTIONS.md): Supported engineering operating envelope, mesh validity contracts, conservative numerical margins, and reasoning guidelines for review.
- [**`dev/MESHCONVENTION.md`**](./dev/MESHCONVENTION.md): Riley standard mesh representation, surface element definitions (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`), 3D continuum elements, node ordering, and connectivity conventions.
- [**`dev/FILESTRUCTURE.md`**](./dev/FILESTRUCTURE.md): Repository layout, module naming rules (`io`, `ops`, `kernel`), scalar/SIMD file splitting, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](./dev/ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.

## Testing Architecture & Core Packaged Suites
Riley provides a layered testing architecture designed for fast routine verification, rigorous mathematical validation, and exhaustive factorial test coverage:

### Optimization Modes & Execution Policy

Riley strictly separates optimization modes by task type:
- **Verification and Basic test suites (`test-verif`, `test-basic`)**: Run in **Debug mode without optimisation flags** (default `zig build`), ensuring fastest compilation and developer feedback.
- **Full test suite (`test-full`)**: Run in **ReleaseSafe mode** (`-Doptimize=ReleaseSafe`), enabling optimized factorial sweeps with safety assertions active.
- **Benchmarks and Performance profiling (`bench-*`, `./scripts/bench_*.py`, `./scripts/perf_*.py`)**: Run in **ReleaseFast mode** (`-Doptimize=ReleaseFast`), ensuring maximum compiler vectorization and realistic production throughput.

> [!IMPORTANT]
> The combined target `zig build test-verif-basic` is intended **primarily for CI pipelines**. For **local development**, prefer running `zig build test-verif` and `zig build test-basic` as two separate terminal processes in parallel to cut turnaround time in half.

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
zig build test-full-badjac

# Python Integration Suite
pytest --pyargs riley.pytests -vs

# Benchmarks & Performance Runs (Always ReleaseFast)
zig build install-bench-multiroot -Doptimize=ReleaseFast -Dsimd=on
zig build install-bench-buffer-psf -Doptimize=ReleaseFast -Dsimd=on
```

### Core Suites Summary

| Suite Name | Command | Primary Role | Reference Data |
| :--- | :--- | :--- | :--- |
| **Verification Suite** | `zig build test-verif` | Inverse solver recovery, silhouette area/centroid, depth ordering, and camera distortion oracles (Debug) | `gold/verif/` |
| **Basic Suite** | `zig build test-basic` | Fast coverage across 1-element, 2-shape FE interaction, and feature zoo cases (Debug) | `gold/basic/` |
| **Combined Core Suite** | `zig build test-verif-basic` | Primarily for CI: runs verif and basic sequentially in Debug mode | `gold/verif/`, `gold/basic/` |
| **Full Suite** | `zig build test-full -Doptimize=ReleaseSafe` | Exhaustive sweeps over shaders, textures, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs in ReleaseSafe | `gold/full_*/` |
| **Bad-Jacobian Diagnostics** | `zig build test-full-badjac` | Warning-only renders of intentionally folded one-element frames, with actual/reference/diff artifacts under `fails/*_full_badjac/` | Existing basic and full-hull gold |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |
| **Procedural Speckles** | `zig build test-speckle-configs` | Default/experimental evaluator policy, generation, sampling, and mesh preparation | In-memory references |

> [!NOTE]
> For complete documentation of all 4 test scenes, 8 sub-suites, gold generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](./dev/TESTING.md).

## Precision and SIMD Build Matrix
The `zig build` workflow supports direct control over precision, SIMD mode, Newton solver mode, and SIMD vector width:

```shell
zig build <STEP> -Dprecision=f64 -Dsimd=on
zig build <STEP> -Dprecision=f64 -Dsimd=off
zig build <STEP> -Dprecision=f32 -Dsimd=on
zig build <STEP> -Dprecision=f32 -Dsimd=off
zig build <STEP> -Dnewton-solver=robust
zig build <STEP> -Dsimd-vector-width=8
zig build <STEP> -Dstrip=true  # Omit debug information
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

### Procedural generation options

Speckles are a dedicated grayscale shader, not a function-shader builtin:

```zig
.shader = .{ .speckle = .{ .uvs = uvs, .params = .{ .seed = 42 } } }
```

Python uses `SpeckleShader(uvs=uvs, params=Speckle2DParams(seed=42))`.
UVs are required; RGB, normals, and coordinate-mode controls are not exposed.
`SpeckleInput` becomes `SpeckleStatic` at mesh setup (gathered UVs and generated
resources), then `SpecklePrepared` per frame (visible UVs and borrowed resources).
Parameter/shape checks run at the input boundary; UV payload scans require full
validation. Output transforms retain the arithmetic order
`(sample * output_scale + output_offset) * scale_mul + scale_add`.

This replaces `FunctionShader` with the speckle builtin and
`Speckle2DParams.to_func_shader_params()`; migrate callers rather than retaining
that route. The C ABI uses shader tag 6 and dedicated speckle fields; rebuild
native/Cython clients against the updated header. Other shader/builtin IDs are unchanged.

Native Zig `Speckle2DParams.neighbor_count` uses `Neighborhood` (`.one`, `.four`,
`.nine`); build settings use `MaskResolution` (`.eight`, `.twelve`, `.sixteen`).
Resolved `Config` is a tagged evaluator union encoding valid combinations. `-Denable-all-evaluators=true` enables native evaluator and
neighborhood overrides; default builds reject explicit overrides. Hard/soft edges
apply only to disks. Perlin has no dummy neighborhood, and mock resolution erases
ignored controls after external validation. CLI neighborhoods remain numeric
1/4/9; `-Dspeckle-mask-samples-per-cell` remains 8/12/16.

| Pattern | Default evaluator | Native alternatives |
| --- | --- | --- |
| Hard disk | `classified-indexed` (9 neighbors) | Hash/list evaluators, `direct-fixed`, masks |
| Soft disk | `list-indexed` | `cell-hash`, `list-naive`, `mask-u8` |
| Gaussian | `list-indexed` | `cell-hash`, `list-naive`, `mask-u8` |
| Perlin | `gradient-lattice` | `cell-hash`, `mask-u8` |

All defaults preserve analytic coverage. Masks use nearest-grid sampling;
`mask-u8` additionally quantizes coverage to bytes. `mock` is a raw arithmetic
ablation for every pattern. Python/C expose only the defaults.
Compatibility rules are defined in [speckleconfig.zig](../src/riley/zig/speckleconfig.zig).

The native catalogue has 45 distinct generators (12 equivalent mock
configurations collapse to one); experimental sampling remains 28 configurations.
Default generation and sampling each have four configurations.
Perlin records have null neighborhood, and irrelevant pattern/neighborhood/edge
metadata may be null. The benchmark request still carries the requested pattern
and echoes explicit mock neighborhoods for driver validation. Python and C retain
flat parameters and default-only policy; their representations do not change.
`-Dspeckle-mask-samples-per-cell=8|12|16` selects mask resolution (default 12),
affecting explicit masks but not analytic field fidelity. Precision affects
generation: a fixed seed does not guarantee identical f32/f64 results.

The benchmark runner reads the native catalogue; use `--a classified-indexed`
or `--b classified-indexed`, not historical numbered selectors. It supports
`--patterns hard soft gaussian perlin`; `--perlin-threshold` and
`--perlin-transition` select hard/smooth Perlin cases without a neighborhood override.

#### Implementation constraints

Generation and sampling live in [speckleops.zig](../src/riley/zig/speckleops.zig).
`Resources.init(allocator, params)` replaces `generateResources`; its `.data`
tagged union has exactly one active backing variant: `none`, `list`,
`strip_list`, `classified`, `direct_fixed`, `mask`, or `perlin`. `deinit(allocator)`
releases the active allocation and resets the value. Resources own no allocator;
the static shader owns the resource value, and `Prepared.resources: *const Resources`
is borrowed from that stable static shader for frame/worker use. Frames do not
deinitialize it. Speckle parameters remain in the shader input/static shader,
not in `Resources`. Finite UVs clamp to `[0,1]` before procedural scaling.

Input validation happens before render allocations: fast validation checks
metadata, shapes, and parameters; full validation additionally scans array
payloads, including UV finiteness and connectivity indices. Resource initialization
is itself a checked preparation boundary for direct low-level callers.

- `classified-indexed` stores nine candidate bits and a foreground flag per
  procedural-aligned microcell. Its 256 MiB state limit returns
  `SpeckleClassificationTooLarge` on excess or checked size overflow.
- `gradient-lattice` stores shared byte gradient IDs, including outer corners at
  UV 1. Above its 256 MiB budget, or on checked size overflow, it uses exact
  on-demand hashing. In-budget allocation failures propagate. Perlin mask setup
  reuses this evaluator with unit colors before quantizing coverage.
- Exactness is bitwise agreement with the independent reference at the same
  precision/build, under strict round-to-nearest with gradual underflow. Preserve
  gradient expressions, interpolation order, transition division, and color
  arithmetic; algebraically equivalent rewrites can change rounding or signed zero.


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

### Texture versus procedural speckles

`scripts/bench_speckle.py` compares native evaluators with an 8-bit monochrome
BMP texture. The texture default matches the production shader:
`--texture-filter cubic_catmull_rom` with `lut_lerp` weights. `nearest` and
`linear` remain available and use direct sampling. Interpolation LUTs are
compile-time constants; setup timing includes texture UV preparation or
procedural resource generation, not image loading/decoding.

Using the experimental benchmark binary (`-Denable-all-evaluators=true`):

```shell
python3 scripts/bench_speckle.py --out out/texture_vs_disk --profile full-render --a texture --b classified-indexed --texture texture/speckle_mono.bmp --patterns hard --neighbors 9
python3 scripts/bench_speckle.py --out out/texture_vs_gaussian --profile full-render --a texture --b list-indexed --texture texture/speckle_mono.bmp --patterns gaussian --neighbors 9
```

Use `--profile full` for static-geometry evaluation instead of production rendering.
The integrated multiroot pipeline reports workload IDs
`static-geometry-depth-accumulator-v2` and `production-raster-advanced-memory-v2`;
rerun baselines rather than comparing their timings directly with historical v1 runs.
Each comparison needs a fresh output directory. The texture is frozen, not regenerated
to match procedural factors, so cross-variant output differences are expected;
do not use `--require-equal-output` for these comparisons.

## Additional Notes

- Plain `zig run` and `zig test` under `./src/` use the default Riley path of `f64` with SIMD enabled. Run the suite drivers through `zig build` to select precision, SIMD, solver, or vector-width options.
- The public C ABI is fixed to that same production path.
- The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses floating-point struct arguments at the C boundary in camera helpers. Native demo/test backend selection is unchanged.
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](./dev/THEORY.md).
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.
