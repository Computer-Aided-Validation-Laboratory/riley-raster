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

## Procedural generation

Speckles use a dedicated grayscale shader with required UV coordinates:

```zig
.shader = .{ .speckle = .{ .uvs = uvs, .params = .{ .seed = 42 } } }
```

The Python equivalent is `SpeckleShader(uvs=uvs, params=Speckle2DParams(seed=42))`.
RGB, normals, and coordinate-mode controls are not supported. Output transforms
apply in the order `(sample * output_scale + output_offset) * scale_mul + scale_add`.

### Configuration

`Speckle2DParams` resolves to a tagged `Config` that encodes valid evaluator,
pattern, neighborhood, and edge combinations. Compatibility rules live in
[speckleconfig.zig](../src/riley/zig/speckleconfig.zig).
`-Denable-all-evaluators=true` enables native Zig evaluator and neighborhood
overrides; default builds reject explicit overrides. Python/C use defaults only.
Neighborhoods use `.one`, `.four`, or `.nine` in Zig and numeric 1/4/9 in the CLI.
Non-mock Perlin rejects neighborhood overrides; hard/soft edges apply only to disks.

| Pattern | Default evaluator | Native alternatives |
| --- | --- | --- |
| Hard disk | `classified-indexed` (9 neighbors) | `cell-hash`, `list-indexed`, `list-naive`, `cell-binned`, `direct-fixed`, masks |
| Soft disk | `cell-binned` (9 neighbors) | `cell-hash`, `list-indexed`, `list-naive`, `mask-u8` |
| Gaussian | `cell-binned` (9 neighbors) | `cell-hash`, `list-indexed`, `list-naive`, `mask-u8` |
| Perlin | `gradient-lattice` | `cell-hash`, `mask-u8` |

Native one/four-neighbour modes default to `list-indexed` for disks and Gaussians.
All defaults preserve analytic coverage. Masks use nearest-grid sampling;
`mask-u8` also quantizes coverage to bytes. `mock` provides raw-arithmetic ablation.
Defaults favor evaluation throughput with reused resources; `list-indexed` can be
preferable for short runs or lower preparation/storage costs.

`-Dspeckle-mask-samples-per-cell=8|12|16` selects mask/classification resolution
(default 12), represented by `MaskResolution` in Zig. Classification resolution
affects acceleration, not analytic field fidelity; masks remain approximations.
A fixed seed does not guarantee identical f32/f64 results.

### Benchmarking

`scripts/bench_speckle.py` reads the native evaluator catalogue and supports
`--patterns hard soft gaussian perlin`. Use `--perlin-threshold` and
`--perlin-transition` to select hard/smooth Perlin cases.

For explicit non-Cartesian benchmark matrices, pass `--case-file cases.json`.
It replaces profile cases (not repeats/statistics) and rejects explicit factor
overrides, including `--radius` and `--softness` even when explicitly set to their
usual defaults. Without a case file, omitted radius/softness remain 0.35/0.04.
Each JSON-list entry has exactly `threads`, `scene`, `pattern`, `radius`, `jitter`,
`occupancy`, `neighbors`, and `softness`; workers can be integers or
`"available-cpus"`. Duplicate resolved cases collapse, including one-CPU hosts.
Per-case radii are passed to and validated against native metadata. For example:

```json
[{"threads":1,"scene":"plate","pattern":"gaussian","radius":0.4,"jitter":0,"occupancy":1,"neighbors":9,"softness":0}]
```

### Implementation constraints

Generation and sampling live in [speckleops.zig](../src/riley/zig/speckleops.zig).
Mesh setup turns `SpeckleInput` into `SpeckleStatic`, which owns gathered UVs and
resources initialized by `Resources.init(allocator, params)`. Per-frame
`SpecklePrepared` borrows resources through a stable `*const Resources`; frames
and workers do not deinitialize them. Parameters reside in the shader, not in
`Resources`. `Resources.deinit(allocator)` frees the active tagged backing and
resets it; the resource does not retain an allocator.

Fast input validation checks metadata, shapes, and parameters before render
allocations. Full validation also scans UVs and connectivity payloads.
`Resources.init` is a checked preparation boundary for low-level callers.
Finite UVs clamp to `[0,1]` before procedural scaling.

- **`classified-indexed`:** procedural-aligned microcells store nine candidate
  bits and a foreground flag. Certified cells avoid disk tests; other samples
  test only candidate owners. The 256 MiB state limit returns
  `SpeckleClassificationTooLarge` on excess or checked size overflow.
- **`cell-binned`:** setup bins touching support into procedural cells. Fixed
  radii use nine-slot X/Y planes and byte counts; variable radii use CSR records.
  Fixed Gaussians reduce paired squared distances before one exponential;
  variable Gaussians cache rounded support-squared and sigma-squared coefficients.
  Layout dispatch precedes the SIMD lane adapter. The 256 MiB preparation budget
  includes temporary storage, and the owner-cell limit is ten million.
  Excess or checked overflow returns `SpeckleCellBinsTooLarge`, without fallback.
- **`gradient-lattice`:** shared byte gradient IDs include outer corners at UV 1.
  A cache exceeding 256 MiB, or checked size overflow, selects exact on-demand
  hashing. Perlin mask setup samples this evaluator with unit colors, then
  quantizes coverage.

In-budget allocation failures propagate. Exactness means bitwise agreement with
independent references at the same precision/build under strict round-to-nearest
with gradual underflow. Preserve gradient expressions, interpolation order,
transition division, and color arithmetic: algebraically equivalent rewrites can
change rounding or signed zero. Cell-binned finite inactive SIMD lanes retain
analytic-list behavior; nonfinite lanes return background. Empty-cell coverage
uses the arithmetic color mapping rather than returning the stored background.

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
Performance regression scripts in `./scripts/` compare against reference data under `./perf/`.

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
For raster-performance experiments, use:

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
python3 scripts/bench_speckle.py --out out/texture_vs_gaussian --profile full-render --a texture --b cell-binned --texture texture/speckle_mono.bmp --patterns gaussian --neighbors 9
```

Use `--profile full` for static-geometry evaluation instead of production rendering.
The integrated multiroot pipeline reports workload IDs
`static-geometry-depth-accumulator-v2` and `production-raster-advanced-memory-v2`.
Compare timings only between matching workload IDs and configurations.
Each comparison needs a fresh output directory. The texture is frozen, not regenerated
to match procedural factors, so cross-variant output differences are expected;
do not use `--require-equal-output` for these comparisons.

## Additional Notes

- Plain `zig run` and `zig test` under `./src/` use the default Riley path of `f64` with SIMD enabled. Run the suite drivers through `zig build` to select precision, SIMD, solver, or vector-width options.
- The public C ABI is fixed to that same production path.
- The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses floating-point struct arguments at the C boundary in camera helpers. Native demo/test backend selection is unchanged.
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](./dev/THEORY.md).
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.
