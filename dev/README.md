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
- [**`dev/FILESTRUCTURE.md`**](FILESTRUCTURE.md): Zig module naming and scalar/SIMD file splitting, naming for tutorials and development programs, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.
- [**`dev/DOCS.md`**](DOCS.md): Build and preview the combined Sphinx Python API and Zig API documentation.

## Python development and distribution

Use `pip install -e ".[dev,docs]"` for pip-installable extras, or
`uv sync --group dev --group docs` for checkout dependency groups. Both carry
matching development/documentation tools; groups are not published extras.

Windows wheel publication targets AMD64. The source-build selector separately
matches the Python interpreter, retaining `win32` → `x86-windows-msvc` as well as
AMD64 and ARM64 mappings. A mapping does not promise a published wheel or CI
coverage: source installs also require compatible dependencies and a C compiler.

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

# Python Integration Suite (see Python development setup above)
.venv/bin/pytest src/riley/pytests/ -vs

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
| **Whole-project Unit Suite** | `zig build test-unit` | Gold-independent numerical, camera/frontend, procedural-speckle, and native tooling/harness correctness tests | In-memory references |
| **Configuration Matrix** | `zig build test-configs` | Runs the shared unit root across f64/f32, SIMD on/off, and default/experimental evaluator policy | In-memory references |
| **Full Suite** | `zig build test-full -Doptimize=ReleaseSafe` | Exhaustive sweeps over shaders, textures, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs in ReleaseSafe | `gold/full_*/` |
| **Bad-Jacobian Diagnostics** | `zig build test-full-badjac` | Warning-only renders of intentionally folded one-element frames, with actual/reference/diff artifacts under `fails/*_full_badjac/` | Existing basic and full-hull gold |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |
| **Procedural Speckles** | Included in `zig build test-basic` and `zig build test-unit`; focused checks use `zig build test-procedural-speckles` | Default integration plus gold-independent generation, sampling, and preparation checks | In-memory references |
| **C API** | `zig build test-c-api` | C interface tests under the fixed public f64/SIMD/default policy | In-memory references |
| **Native Benchmark Tooling** | Included in `zig build test-unit`; focused checks use `zig build test-speckle-benchmark` | Native benchmark tooling and harness correctness (not performance profiles) | In-memory references |

> [!NOTE]
> For complete documentation of all 4 test scenes, 8 sub-suites, gold generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](TESTING.md).

See the [native unit/configuration testing policy](TESTING.md#native-unit-and-configuration-testing)
for CI coverage and portable smoke-test commands.

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

Speckles use a dedicated grayscale shader with required nodal UV coordinates
and explicit parameters. Native `SpeckleParams` is a tagged union:

```zig
.shader = .{ .speckle = .{
    .uvs = uvs,
    .params = .{ .disk = .{ .coverage = 0.5, .radius = 0.25 } },
} }
```

Use the `.gaussian` branch for Gaussian blobs or
`.{ .perlin = .{ .cell_size = 0.25 } }` for Perlin noise.
The public root exports `Speckle2DParams`, `Perlin2DParams`, and
`SpeckleParams`; evaluator and grid controls are internal.

The [parameter reference source](../docs/python-api/speckles.rst) is the shared public
contract for units, calibration, coverage, defaults, and errors, with a Python
example. See [documentation build instructions](DOCS.md) for the rendered API,
and [Theory](THEORY.md#6-physical-speckle-calibration-and-nominal-coverage) for
the internal calibration and coverage model.

### Runnable procedural tutorials

Each tutorial shows the complete public-shader render setup. Run these from the
repository root with Zig 0.16.0:

```shell
zig build demo-procedural-pattern -Doptimize=ReleaseFast
zig build demo-procedural-sphere200 -Doptimize=ReleaseFast -- --pattern gaussian
zig build demo-procedural-rabbit -Doptimize=ReleaseFast -- --pattern perlin
zig build demo-procedural-speckles -Doptimize=ReleaseFast
```

Pass tutorial options after `--`. All four default to `disk` and accept
`--pattern disk|gaussian|perlin`, `--output DIR`, and `-h` or `--help`.
Only the pattern plane accepts `--width` and `--height`: these change the
resolution without changing the 40 × 40 plane. Unequal dimensions give
non-square pixels.

| Tutorial | Image size | Default output |
| --- | --- | --- |
| [Pattern plane](../src/demoproceduralpattern.zig) | 1024 × 1024 | `out/procedural_pattern/disk.bmp` (`gaussian.bmp` or `perlin.bmp` when selected) |
| [Sphere](../src/demoproceduralsphere200.zig) | 800 × 500 | `out/demo-procedural-sphere200/cam0_frame0_field0.bmp` |
| [Rabbit](../src/demoproceduralrabbit.zig) | 800 × 500 | `out/demo-procedural-rabbit/cam0_frame0_field0.bmp` |
| [Deformation](../src/demoproceduralspeckles.zig) | 720 × 450 | Under `out/demo-procedural-speckles/`: `cam0_frame0_field0.bmp` (reference), `cam0_frame1_field0.bmp` (stretch), `cam0_frame2_field0.bmp` (twist) |

Edit `seed`, `radius`, `coverage`, and `cell_size` in the tutorial source, not on
the command line. The disk/Gaussian radius and Perlin cell size default to 0.25
on the plane, 0.005 on the rabbit, and 0.02 on the sphere and deformation mesh,
all in reference geometry units, not pixels. Nominal disk/Gaussian coverage
defaults to 0.5.

### Internal evaluator experiments and benchmarking

Developer-only [`speckleops.GridParams`](../src/riley/zig/speckleops.zig)
provides cell-space controls for unit cases and raw evaluation benchmarks;
its radii, jitter, and softness are in cell units.

Internal `GridParams.resolve()` returns a tagged `Config`; compatibility rules
live in [speckleconfig.zig](../src/riley/zig/speckleconfig.zig).
`-Denable-all-evaluators=true` enables experimental internal overrides.
Neighborhoods are `.one`, `.four`, or `.nine` internally (numeric 1/4/9 in raw
benchmark options). Non-mock Perlin rejects neighborhood overrides; hard/soft
edges apply only to disks.

| Pattern | Automatic evaluator | Internal alternatives |
| --- | --- | --- |
| Hard disk | `classified-binned` (9 neighbors) | `cell-binned`, `cell-hash`, `list-indexed`, `list-naive`, `classified-indexed`, `direct-fixed`, masks |
| Soft disk | `cell-binned` (9 neighbors) | `cell-hash`, `list-indexed`, `list-naive`, `mask-u8` |
| Gaussian | `cell-binned` (9 neighbors) | `cell-hash`, `list-indexed`, `list-naive`, `mask-u8` |
| Perlin | `gradient-lattice` | `cell-hash`, `mask-u8` |

Internal one/four-neighbor modes default to `list-indexed` for disks and Gaussians.
`classified-binned` uses exact foreground/background certificates on a fixed
8×4 microcell grid per bin and exact disk tests for ambiguous samples.
`cell-binned` uses spatial bins without classification. Automatic evaluators
sample analytic fields without texture quantization, but are not guaranteed to
be fastest for every workload. Masks use nearest-grid sampling; `mask-u8` also
quantizes to bytes. `mock` provides a raw-arithmetic ablation. Explicit internal
selection, including `classified-binned`, requires the experimental build.

`-Dspeckle-mask-samples-per-cell=8|12|16` selects experimental mask and
`classified-indexed` resolution (default 12, `MaskResolution` in Zig). It does
not change the default `classified-binned` 8×4 grid. Classification resolution
changes acceleration, not analytic field fidelity; masks remain approximations.

`scripts/bench_speckle.py` reads the native evaluator catalogue. Raw runner
comparisons require explicit evaluator names (or `texture`); omitted raw Perlin
controls use binary A's defaults for both binaries. Full-render accepts only
`auto` or `texture`, without neighborhood overrides. Python checks scalar inputs;
native validation and preparation check feasibility.

Full-render workload `production-raster-advanced-memory-v5` records physical
inputs and declared evaluator policy, not observed dispatch. It defaults to
`combined_ns`: `resource_ns` includes UV gathering and reference calibration
for procedural inputs, and `render_ns` excludes that work. Do not compare
individual timing buckets against baselines with different boundaries. Output
equality uses ordered image hashes computed outside the timed render. Use
`--help` for profile-specific factors and `--case-file` schemas.

`resource_bytes` in native JSON measures retained backing allocations for
`cell-binned`, `list-indexed`, `classified-indexed`, and `classified-binned`
evaluation-mode runs, not peak process memory. `duplicated_disk_records` counts
live binned record references, excluding fixed-layout padding. Classified bins
also report `record_capacity`, including unused slots. These diagnostics do not
measure preparation scratch or peak process RSS. Uncollected values are `null`,
including metrics for textures and full-render runs.

Use separate install prefixes: the default and experimental builds have the
same executable name, so installing both to one prefix overwrites the first.
These examples use the default f64/SIMD executable name (append `.exe` on Windows).
Build the experimental benchmark and compare two exact hard-disk evaluators:

```shell
zig build install-bench-speckle-evaluators -Doptimize=ReleaseFast -Dstrip=true -Denable-all-evaluators=true --prefix zig-out/speckle-experimental
python3 scripts/bench_speckle.py --binary zig-out/speckle-experimental/bin/bench_speckle_evaluators_f64_simd \
  --out out/classified_binned_tuning --profile tuning --a cell-binned --b classified-binned \
  --patterns hard --neighbors 9 --require-equal-output
```

`--profile tuning` measures combined preparation/evaluation time;
`--profile full` measures static-geometry evaluation.
Compare matching workload IDs and build settings, retain results, and use a
fresh output directory. Use `--workers` for worker budgets.

For a production repeatability smoke comparison (`0.25` is a coarse radius):

```shell
zig build install-bench-speckle-evaluators -Doptimize=ReleaseFast -Dstrip=true --prefix zig-out/speckle-default
python3 scripts/bench_speckle.py --binary zig-out/speckle-default/bin/bench_speckle_evaluators_f64_simd \
  --out out/speckle_production_repeatability --profile full-render --coverage 0.5 --radius 0.25 --a auto --b auto
```

For cross-build A/B measurements, use `--binary-a` and `--binary-b` to select
executables from the prefixes above, retaining `auto/auto` and matching other build
settings. This compares production builds, not selectable public shader evaluators.

### Implementation constraints

Physical resolution lives in [speckleparams.zig](../src/riley/zig/speckleparams.zig),
reference calibration in [specklegeom.zig](../src/riley/zig/specklegeom.zig), and
nominal coverage inversion in [specklecoverage.zig](../src/riley/zig/specklecoverage.zig).
Generation and sampling use internal `GridParams` in
[speckleops.zig](../src/riley/zig/speckleops.zig).
Scalar and SIMD samplers agree exactly, except that zero signs may differ.

Before render allocations, fast validation checks metadata and `SpeckleParams`;
full validation also scans UVs and connectivity. Mesh preparation checks the
interpolated UV domain and calibrates the referenced faces. Physical resolution
precedes UV/resource allocation; `SpeckleStatic` owns the resolved `GridParams`,
gathered UVs, and sampler resources. Per-frame `SpecklePrepared` borrows resources
through a stable `*const Resources`; frames and workers do not deinitialize them.
`Resources.deinit(allocator)` frees and resets the active tagged backing;
resources do not retain an allocator.

Unlike the public contract, low-level `GridParams.resolve()` and `Resources.init()`
allow equal colors and zero occupancy for reference tests. Internal mock ignores
colors and evaluates a raw UV gradient.

Preparation checks dimension casts, element/byte counts, and index representability
before using unchecked computational stages. There are no fixed memory or owner-cell
budgets. Internal unrepresentable storage returns the evaluator-specific size
error; public preparation maps it to `SpeckleDensityOutOfRange` and leaves
`OutOfMemory` unchanged. Packed-mask preparation also checks the signed SIMD
index range on 32-bit targets. Samplers do not revalidate the UV domain.

Prepared Perlin (`gradient-lattice` or `cell-hash`) and classified/direct/mask
samplers return background for inactive SIMD lanes. Other prepared samplers,
including cell-binned, and unprepared convenience calls evaluate every lane.
Callers discard inactive lanes.

- **`classified-indexed`:** procedural-aligned microcells store nine candidate
  bits and a foreground flag. Certified cells avoid disk tests; other samples
  test only candidate owners. State storage is checked before owner generation;
  unrepresentable grids return `SpeckleClassificationTooLarge`.
  Its candidates reference owner-indexed strips, not procedural-cell bins.
- **`classified-binned`:** default nine-neighbor hard-disk evaluator with procedural-cell
  bins and local 8×4 classification, independent of the build-wide mask resolution.
  Preparation classifies bins with reachable-domain-clipped FG32/AMB32 certificates:
  certified foreground/background microcells skip disk tests; ambiguous samples
  use exact disk fallback with variable-radius lanes grouped by bin.
  Fixed radii retain nine-slot X/Y planes; variable radii retain CSR X/Y/radius²
  planes. Preparation checks storage and index representability, with no fixed
  memory budget; unrepresentable classification returns
  `SpeckleClassificationTooLarge`, while representable allocation failures
  propagate `OutOfMemory`. This is distinct from the owner-strip
  `classified-indexed` algorithm.
- **`cell-binned`:** setup bins touching support into procedural cells. Fixed
  radii use nine-slot X/Y planes and byte counts; variable radii use CSR records.
  Fixed Gaussians reduce paired squared distances before one exponential;
  variable Gaussians cache rounded support-squared and sigma-squared coefficients.
  Layout dispatch precedes the SIMD lane adapter. Counts, offsets, and each
  allocation's byte size are checked for representability, returning
  `SpeckleCellBinsTooLarge` on overflow. CSR record counts are determined before
  the final record allocation; temporary indices are cleaned up on failure.
- **`gradient-lattice`:** shared byte gradient IDs include outer corners at UV 1.
  An unrepresentable cache returns `SpecklePerlinLatticeTooLarge`.
  Perlin mask setup samples this evaluator with unit colors, then quantizes
  coverage. `cell-hash` is an explicit native alternative.

Exactness means numerical equality with independent references at the same
precision/build under strict round-to-nearest with gradual underflow. Positive
and negative zero are interchangeable; nonzero results must agree without a
tolerance. Preserve gradient expressions, interpolation order, transition division,
and color arithmetic where rewriting them changes nonzero results through rounding.
Gaussian reductions that select the smallest distance term before calling
`@exp` assume that `@exp` is monotone nondecreasing over the supported arguments;
this applies to scalar and SIMD implementations.

## Benchmark Binaries
The benchmark entry points exposed through `zig build` are:

- `bench-dicuq`
- `bench-fullraster`
- `bench-tiltraster`
- `bench-geom`
- `bench-sphere2000`
- `bench-sphere2000zoom`
- `bench-thread-geom`
- `bench-dist-psf`
- `bench-multiroot`
- `bench-buffer-psf`
- `bench-speckle-evaluators`

The normal install prefix puts binaries in `zig-out/bin/`. Use `--prefix .`
for workflows that expect `./bin/`:

```shell
zig build install-bench-fullraster -Doptimize=ReleaseFast --prefix .
zig build install-bench-tiltraster -Doptimize=ReleaseFast --prefix .
zig build install-bench-geom -Doptimize=ReleaseFast --prefix .
zig build install-bench-sphere2000 -Doptimize=ReleaseFast --prefix .
zig build install-bench-sphere2000zoom -Doptimize=ReleaseFast --prefix .
zig build install-bench-dicuq -Doptimize=ReleaseFast --prefix .
zig build install-bench-bins -Doptimize=ReleaseFast --prefix .
```

Where the runner supports them, pass installed paths via `--binary` or
`--binary-a`/`--binary-b`.

## Performance Regression Scripts
Performance regression scripts in `./scripts/` compare against reference data under `./perf/`.

Compile the standard SIMD benchmark binaries:

```shell
python ./scripts/compile_para_benchmarks.py --simd-only
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

For a production texture/procedural smoke comparison, use the default binary
from the [separate-prefix install above](#internal-evaluator-experiments-and-benchmarking):

```shell
python3 scripts/bench_speckle.py --binary zig-out/speckle-default/bin/bench_speckle_evaluators_f64_simd \
  --out out/texture_vs_disk --profile full-render --coverage 0.5 --radius 0.25 \
  --a texture --b auto --texture texture/speckle_mono.bmp --patterns hard
```

The texture is frozen, not regenerated to match procedural factors, so do not
use `--require-equal-output` for these comparisons.

## Additional Notes

- Some benchmark helper scripts remain in `./scripts/`, including `./scripts/legacy/`. Their presence does not make them part of the current verification workflow; use the packaged test suites above for correctness and `scripts/bench_speckle.py` for speckle evaluator comparisons.

- Plain `zig run` and `zig test` under `./src/` use the default Riley path of `f64` with SIMD enabled. Run the suite drivers through `zig build` to select precision, SIMD, solver, or vector-width options.
- The public C ABI is fixed to that same production path.
- The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses floating-point struct arguments at the C boundary in camera helpers. Native demos and tests select their backends independently.
- For detailed camera model mathematics, thread budgeting, distortion-aware hulls, and image save mode mechanics, see [**`dev/THEORY.md`**](THEORY.md).
