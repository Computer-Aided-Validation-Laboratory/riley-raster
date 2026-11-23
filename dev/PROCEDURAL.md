# Procedural speckles

The native `.speckle` shader takes nodal UVs and a `SpeckleParams` tagged union
(`.disk`, `.gaussian`, or `.perlin`), with public `Dot2DParams` and `Perlin2DParams`
payload types. Evaluator and grid controls are internal. See the
[Python speckle reference](../docs/python-api/speckles.rst) for the public contract
and [API documentation build instructions](DOCS.md) for local API docs.

## Runnable procedural tutorials

Run Zig tutorials from the repository root or Python tutorials with the package
installed (see [installation](../docs/install/install.rst)). The plane builds
its own mesh; the sphere and rabbit use mesh and UV assets.

| Tutorial | Zig command | Python command |
| --- | --- | --- |
| Plane quickstart ([Zig](../src/demo0b_procedural_quickstart.zig), [Python](../src/riley/pydemos/demo0b_procedural_quickstart.py)) | `zig build demo0b-procedural-quickstart -Doptimize=ReleaseFast` | `python -m riley demo0b_procedural_quickstart` |
| Deforming sphere ([Zig](../src/demo1b_procedural_sphere.zig), [Python](../src/riley/pydemos/demo1b_procedural_sphere.py)) | `zig build demo1b-procedural-sphere -Doptimize=ReleaseFast` | `python -m riley demo1b_procedural_sphere` |
| Rabbit ([Zig](../src/demo2d_rabbit_procedural.zig), [Python](../src/riley/pydemos/demo2d_rabbit_procedural.py)) | `zig build demo2d-rabbit-procedural -Doptimize=ReleaseFast` | `python -m riley demo2d_rabbit_procedural` |

Zig writes to `out/<name>/` and Python writes to `out_riley_py/<name>/`, where
`<name>` is the underscore-separated tutorial name. Default images:

- `demo0b_procedural_quickstart`: `disk.bmp` (1024 × 1024).
- `demo1b_procedural_sphere`: three images (720 × 450), `cam0_frame0_field0.bmp`
  (reference), `cam0_frame1_field0.bmp` (stretch), and `cam0_frame2_field0.bmp`
  (twist). The same pattern follows the surface through all three frames.
- `demo2d_rabbit_procedural`: `cam0_frame0_field0.bmp` (800 × 500).

Append `--help` to a Python demo command or `-- --help` to a Zig build command
for pattern and output options. For example, select Gaussian spots with
`--pattern gaussian` in Python or `-- --pattern gaussian` in Zig.

Only the Zig plane demo accepts `--width PIXELS` and `--height PIXELS`. These
change the image size, not the 40 × 40 plane or the physical pattern scale;
unequal dimensions give non-square pixels. The plane names its output after
the selected pattern (`disk.bmp`, `gaussian.bmp`, or `perlin.bmp`).

The tutorials set the seed and physical pattern parameters in source, not
on the command line. Disk/Gaussian radius and Perlin cell size are 0.25 on the
plane, 0.02 on the sphere, and 0.005 on the rabbit. Disk and Gaussian patterns
use 0.5 nominal coverage.

## Internal evaluator experiments and benchmarking

Developer-only [`speckleops.GridParams`](../src/riley/zig/speckleops.zig)
provides cell-space controls for unit cases and raw evaluation benchmarks;
its radii, jitter, and softness are in cell units.

Internal `GridParams.resolve()` returns a tagged `Config`; compatibility rules
live in [speckleconfig.zig](../src/riley/zig/speckleconfig.zig).
`-Denable-all-evaluators=true` enables experimental internal overrides.
Neighborhoods are `.one`, `.four`, or `.nine` internally (numeric 1/4/9 in raw
benchmark options). Non-mock Perlin rejects neighborhood overrides; hard/soft
edges apply only to disks.

Automatic policy uses `classified-binned` for nine-neighbor hard disks,
`cell-binned` for nine-neighbor soft disks and Gaussians, and `gradient-lattice`
for Perlin. One/four-neighbor disks and Gaussians default to `list-indexed`.
Query the native benchmark binary with `--list-evaluators` for its supported
alternatives and combinations. Masks use nearest-grid sampling; `mask-u8` also
quantizes to bytes. `mock` provides a raw-arithmetic ablation.

`-Dspeckle-mask-samples-per-cell=8|12|16` selects experimental mask and
`classified-indexed` resolution (default 12, `MaskResolution` in Zig). It does
not change the default `classified-binned` 8×4 grid. Classification resolution
changes acceleration, not analytic field fidelity; masks remain approximations.

`python3 scripts/bench_speckle.py --help` lists profile factors and case-file schemas.
The runner reads each binary's catalogue; omitted raw Perlin controls use binary
A's defaults for both binaries. Raw evaluation compares named evaluators or
`texture`; full-render accepts `auto` or `texture` without neighborhood overrides.
Python checks scalar inputs; native validation and preparation check feasibility.

Full-render workload `production-raster-advanced-memory-v6` records physical
inputs and declared evaluator policy, not observed dispatch. Its only metric,
`combined_ns`, times the in-memory render including preparation. Ordered image
hashes for output equality are untimed. Only raw evaluation supports split
metrics (`--metrics setup render`).

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

For cross-build A/B measurements, select the two executables with `--binary-a`
and `--binary-b`, retaining `auto/auto` and matching other build settings.

## Implementation constraints

See [Theory](THEORY.md#6-physical-speckle-calibration-and-nominal-coverage) for
reference UV calibration and the nominal coverage model, and
[Testing](TESTING.md#physical-speckle-verification) for their verification.

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
- **`classified-binned`:** procedural-cell bins use reachable-domain-clipped
  FG32/AMB32 certificates on a local 8×4 grid. Certified foreground/background
  microcells skip disk tests; ambiguous samples use exact fallback with
  variable-radius lanes grouped by bin. Fixed radii retain nine-slot X/Y planes;
  variable radii retain CSR X/Y/radius² planes. Unrepresentable classification
  returns `SpeckleClassificationTooLarge`.
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

Scalar and SIMD samplers must agree with each other and independent references
at the same precision/build under strict round-to-nearest with gradual underflow.
Positive and negative zero are interchangeable; nonzero results must agree
without a tolerance. Preserve gradient expressions, interpolation order, transition division,
and color arithmetic where rewriting them changes nonzero results through rounding.
Gaussian reductions that select the smallest distance term before calling
`@exp` assume that `@exp` is monotone nondecreasing over the supported arguments;
this applies to scalar and SIMD implementations.

## Texture versus procedural speckles

`scripts/bench_speckle.py` compares native evaluators with an 8-bit monochrome
BMP texture. The texture default matches the production shader:
`--texture-filter cubic_catmull_rom` with `lut_lerp` weights. `nearest` and
`linear` remain available and use direct sampling. Interpolation LUTs are
compile-time constants; texture loading and decoding are untimed.

For a texture/procedural smoke comparison, use the full-render command above
with a fresh output directory and replace `--a auto --b auto` with
`--a texture --b auto --texture texture/speckle_mono.bmp --patterns hard`.
The texture is frozen, not regenerated to match procedural factors, so do not
use `--require-equal-output` for these comparisons.
