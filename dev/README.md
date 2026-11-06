# Riley Developer Guide
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**

## Development Guides
The `dev/` directory provides comprehensive architectural, mathematical, testing, and conventions documentation for Riley developers:

- [**`dev/TESTING.md`**](TESTING.md): Complete testing architecture, quickstart commands, descriptions of the 4 test scenes, detailed breakdown of all 8 test suites, gold reference generation, and automated regression diagnostics.
- [**`dev/THEORY.md`**](THEORY.md): Mathematical foundations and engine design details, including polynomial camera distortion formulation, distortion-aware rasterisation frontend bounds, render thread budgets, and image save mode mechanics.
- [**`dev/ASSUMPTIONS.md`**](ASSUMPTIONS.md): Supported engineering operating envelope, mesh validity contracts, conservative numerical margins, and reasoning guidelines for review.
- [**`dev/MESHCONVENTION.md`**](MESHCONVENTION.md): Riley standard mesh representation, surface element definitions (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`), 3D continuum elements, node ordering, and connectivity conventions.
- [**`dev/FILESTRUCTURE.md`**](FILESTRUCTURE.md): Repository layout, module naming rules (`io`, `ops`, `kernel`), scalar/SIMD file splitting, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.

## Testing Architecture & Core Packaged Suites
Riley provides a layered testing architecture designed for fast routine verification, rigorous mathematical validation, and exhaustive factorial test coverage:

### Optimization Modes & Execution Policy

Riley strictly separates optimization modes by task type:
- **Local Verification and Basic suites (`test-verif`, `test-basic`)**: Run in **Debug mode without optimisation flags** for fast developer feedback; CI runs the combined core suite in **ReleaseSafe**.
- **Full test suite (`test-full`)**: Run in **ReleaseSafe mode** (`-Doptimize=ReleaseSafe`), enabling optimized factorial sweeps with safety assertions active.
- **Benchmarks and Performance profiling (`bench-*`, `./scripts/bench_*.py`, `./scripts/perf_*.py`)**: Run in **ReleaseFast mode** (`-Doptimize=ReleaseFast`), ensuring maximum compiler vectorization and realistic production throughput.

> [!IMPORTANT]
> The combined target `zig build test-verif-basic` is intended **primarily for CI pipelines**. For **local development**, prefer running `zig build test-verif` and `zig build test-basic` as two separate terminal processes in parallel to cut turnaround time in half.

### Quick Commands

```shell
# Local Development: Run verif and basic in parallel across two terminal tabs/jobs (Debug)
zig build test-verif & zig build test-basic & wait

# CI Combined Verification & Basic Suite (ReleaseSafe)
zig build test-verif-basic -Doptimize=ReleaseSafe

# Gold-independent whole-project unit coverage (Debug)
zig build test-unit

# Gold-independent precision/SIMD/policy configuration matrix (CI)
zig build test-configs

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
| **Combined Core Suite** | `zig build test-verif-basic` (local Debug); CI uses `-Doptimize=ReleaseSafe` | Verification and gold-backed basic comparisons, including the gold-independent unit root | `gold/verif/`, `gold/basic/` |
| **Whole-project Unit Suite** | `zig build test-unit` | Gold-independent numerical, camera/frontend, speckle/CLI, and native tool/harness correctness tests | In-memory references |
| **Configuration Matrix** | `zig build test-configs` | Runs the shared unit root across f64/f32, SIMD on/off, and default/experimental evaluator policy | In-memory references |
| **Full Suite** | `zig build test-full -Doptimize=ReleaseSafe` | Exhaustive sweeps over shaders, textures, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs in ReleaseSafe | `gold/full_*/` |
| **Bad-Jacobian Diagnostics** | `zig build test-full-badjac` | Warning-only renders of intentionally folded one-element frames, with actual/reference/diff artifacts under `fails/*_full_badjac/` | Existing basic and full-hull gold |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |
| **Procedural Speckles** | Included in `zig build test-basic` and `zig build test-unit`; focused checks use `zig build test-procedural-speckles` | Default integration plus gold-independent generation, sampling, and preparation checks; focused target remains a local convenience | Basic gold / in-memory references |
| **C API** | `zig build test-c-api` | C interface tests under the fixed public f64/SIMD/default policy | In-memory references |
| **Native Benchmark Tooling** | Included in `zig build test-unit`; focused checks use `zig build test-speckle-benchmark` | Native benchmark tooling and harness correctness (not performance profiles) | In-memory references |

> [!NOTE]
> For complete documentation of all 4 test scenes, 8 sub-suites, gold generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](TESTING.md).

The whole-project `test-unit` suite and configuration matrix are gold-independent; focused procedural-speckle and native-tool checks remain local conveniences. See [the native unit/configuration testing policy](./TESTING.md#native-unit-and-configuration-testing) for coverage and commands.

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

`resource_bytes` in native JSON measures backing allocations for evaluation-mode
cell-binned and list-indexed runs, not peak process memory. `duplicated_disk_records`
counts stored cell-binned record references in evaluation mode. Uncollected values
are `null`, including both metrics for other backings, textures, and full-render runs.

### Implementation constraints

Generation and sampling live in [speckleops.zig](../src/riley/zig/speckleops.zig).
`fillImage(image, params, resources)` samples pixel centers, with row zero at the
top, without supersampling or output scaling. SIMD and scalar results agree
exactly, except that zero signs may differ. The [direct pattern demo](../README.md#procedural-speckles)
writes the field to a BMP and accepts native evaluator overrides.

Mesh setup turns `SpeckleInput` into `SpeckleStatic`, which owns gathered UVs and
resources initialized by `Resources.init(allocator, params)`. Per-frame
`SpecklePrepared` borrows resources through a stable `*const Resources`; frames
and workers do not deinitialize them. `Resources.deinit(allocator)` frees the
active tagged backing and resets it; resources do not retain an allocator.

Fast input validation checks metadata, shapes, and parameters before render
allocations. Full validation also scans UVs and connectivity payloads.
`Speckle2DParams.validate()` rejects equal foreground/background values and zero
disk/Gaussian occupancy at user-input boundaries; use a uniform texture for a
constant field. Perlin and mock ignore occupancy. Low-level `resolve()` and
`Resources.init()` allow equal colors and zero occupancy for reference calculations
and tests. Mock ignores colors and retains its raw UV-gradient behavior.

Preparation checks dimension casts, element/byte counts, and index representability
before using unchecked computational stages. There are no fixed memory or owner-cell
budgets. Unrepresentable storage returns the evaluator-specific size error;
representable allocation failures propagate `OutOfMemory`. Packed-mask preparation
also checks the signed SIMD index range on 32-bit targets. Coordinate-precision
limits still apply. Samplers do not recheck UV finiteness: clamping maps NaN and
positive infinity to 1 and negative infinity to 0 before grid indexing.

Prepared Perlin (`gradient-lattice` or `cell-hash`) and classified/direct/mask
samplers return background for inactive SIMD lanes. Other prepared samplers,
including cell-binned, and unprepared convenience calls evaluate every lane.
Callers discard inactive lanes.

- **`classified-indexed`:** procedural-aligned microcells store nine candidate
  bits and a foreground flag. Certified cells avoid disk tests; other samples
  test only candidate owners. State storage is checked before owner generation;
  unrepresentable grids return `SpeckleClassificationTooLarge`.
- **`cell-binned`:** setup bins touching support into procedural cells. Fixed
  radii use nine-slot X/Y planes and byte counts; variable radii use CSR records.
  Fixed Gaussians reduce paired squared distances before one exponential;
  variable Gaussians cache rounded support-squared and sigma-squared coefficients.
  Layout dispatch precedes the SIMD lane adapter. Counts, offsets, and each
  allocation's byte size are checked for representability, returning
  `SpeckleCellBinsTooLarge` on overflow. CSR record counts are determined before
  the final record allocation; temporary indices are cleaned up on failure.
- **`gradient-lattice`:** shared byte gradient IDs include outer corners at UV 1.
  An unrepresentable cache returns `SpecklePerlinLatticeTooLarge`; there is no
  automatic hashing fallback. Perlin mask setup samples this evaluator with unit
  colors, then quantizes coverage. Explicit `cell-hash` remains a native alternative.

Exactness means numerical equality with independent references at the same
precision/build under strict round-to-nearest with gradual underflow. Positive
and negative zero are interchangeable; nonzero results must agree without a
tolerance. Preserve gradient expressions, interpolation order, transition division,
and color arithmetic where rewriting them changes nonzero results through rounding.

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
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](THEORY.md).
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.
