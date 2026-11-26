# Procedural speckles

See the [usage guide](../docs/procedural.rst) for Zig and Python inputs,
examples of direct monochrome and shader-pipe sources, and output scaling.
Both APIs use `Disk2DParams`, `Gaussian2DParams`, and `Perlin2DParams`;
only `Disk2DParams` accepts edge softness. They share the same sampler and
reference-UV calibration. The fixed seed is repeatable within a build; results
need not be identical across f32 and f64. The flat C `CSpeckleInput` still has
an `edge_softness` field; it must be zero for Gaussian spots.

## Runnable procedural tutorials

Run from the repository root. The plane builds its own mesh; the sphere and
rabbit use the checked-in mesh and UV assets.

| Tutorial | Zig command | Python command | Default BMPs relative to the output root |
| --- | --- | --- | --- |
| [Plane](../src/demo00b_procedural_quickstart.zig) | `zig build demo00b-procedural-quickstart` | `python -m riley demo00b_procedural_quickstart` | `demo00b_procedural_quickstart/disk.bmp` (1024 × 1024) |
| [Deforming sphere](../src/demo01b_procedural_sphere.zig) | `zig build demo01b-procedural-sphere` | `python -m riley demo01b_procedural_sphere` | `demo01b_procedural_sphere/cam0_frame{0,1,2}_field0.bmp` (720 × 450; reference, stretch, twist) |
| [Shader-pipe rabbit](../src/demo02d_rabbit_procedural.zig) | `zig build demo02d-rabbit-procedural` | `python -m riley demo02d_rabbit_procedural` | `demo02d_rabbit_procedural/cam0_frame0_field0.bmp` (800 × 500) |

Zig writes below `out/`; Python writes below `out_riley_py/`.
Pass `--help` to a demo to list its options. In Zig, pass runtime options after
`--` to a single named demo target. The aggregate targets `demos` and
`run-all-demos` reject runtime options and run with defaults when none are
provided. For example, to switch from disks to Gaussian spots:

```shell
zig build demo00b-procedural-quickstart -- --pattern gaussian
python -m riley demo00b_procedural_quickstart --pattern gaussian
```

Both accept `--pattern perlin` for noise and `--output DIR` to change the
output directory. The plane also accepts
`--width PIXELS` and `--height PIXELS`; unequal dimensions give non-square
pixels, not a change to the 40 × 40 plane or pattern scale. Its image filename
is the selected pattern. Disk/Gaussian radius and Perlin cell size are 0.25
on the plane, 0.02 on the sphere, and 0.005 on the rabbit. Both dot patterns use
0.5 nominal coverage. To customise the seed, pass it when constructing the
pattern parameters in the tutorial; the CLI does not expose it.

## Physical calibration and nominal coverage

Use `C` for nominal coverage, `R` for physical radius, `p` for occupancy,
`J` for jitter, and `S` for edge softness. See the
[usage guide](../docs/procedural.rst) for units. Preparation checks the UV
domain once with a tolerance of `2e-5`; the sampler clamps to `[0, 1]`.
Calibration is shared over the mesh's reference faces, not repeated per frame
or camera. Sampler storage spans the square, so small UV islands can cost
more memory for the same physical pattern size. Where atlas placement is not
required, use more of the square while preserving atlas proportions.

[`specklegeom.zig`](../src/riley/zig/specklegeom.zig) integrates physical
and UV areas of the referenced faces. Before integration, it checks
nodal UV bounds for affine triangles and bilinear quads. For quadratic elements
it also bounds the interpolated UV patch with Bernstein control points, bisecting
uncertain patches up to 16 times along alternating axes. A patch that remains
uncertified is rejected.

```text
Aphys = sum over faces integral |dX/dxi cross dX/deta| dxi deta
Auv   = sum over faces integral |det(d(u,v)/d(xi,eta))| dxi deta
m     = integral ln(|X_u|/|X_v|) dAphys / Aphys
Lu    = sqrt(Aphys/Auv) * exp(m/2)
Lv    = sqrt(Aphys/Auv) * exp(-m/2); Lu*Lv = Aphys/Auv
```

`tri3`/`tri3opt` use exact constant-Jacobian one-point integration; `tri6` and
`quad4/8/9` use fixed 8×8 Gauss quadrature (Duffy mapping for triangles), assuming
usable FE geometry. All area and metric reductions accumulate in `f64`, including
f32 builds. The physical-area-weighted log-mean ratio varies continuously with
the mapping and recovers constant orthogonal planar scales. A UV sliver's ratio
influence grows logarithmically, weighted by its physical area fraction. Perlin
uses `cells_per_uv = (Lu / cell_size, Lv / cell_size)` with no coverage solve.
The product `Lu*Lv = Aphys/Auv` makes a nominal disk or Gaussian footprint
of radius `R` correspond to average physical area `pi*R*R`.

For disks and Gaussians, coverage is defined by the nominal disk support.
On an infinite square owner grid, each cell independently contains one uniformly
positioned centre with probability `p`. For normalized radius `r <= 1`, nine
owners suffice. Let `A_i(x,r)` be the intersection area of owner cell `i` and
the radius-`r` disk centred at query point `x`:

```text
F(p,r) = integral over unit query cell [1 - product_i(1 - p * A_i(x,r))] dx
       = sum from k=1 to 9 of M_k(r) * p^k
F(p,r) = C (solve for r); q = r / R
cells_per_uv = (Lu * q, Lv * q)
radius_mean = r; radius_jitter = r*(J/R); edge_softness = r*(S/R)
```

The signed coefficients integrate the expanded product; `M_1(r) = pi*r*r`.
This stratified Bernoulli model approximates the finite-precision hash sampler;
it is not the Poisson formula `1 - exp(-p*pi*r*r)`. Public jitter requires
`0 <= J <= R/2`. Full feasibility also requires `C <= F(p,1/(1+J/R+S/R))`;
validation checks this forward bound before geometry without an inverse solve.
Lowering inverts nominal coverage once, independently of jitter/softness, and
checks converted support `r + r*(J/R) + r*(S/R) <= 1` without clamping.
Nominal cap equality maps to `r = 1`.

Jitter changes expected union area without changing placement density. For
example, `p = 1`, `C = 0.5`, and `J = R/2` give about 0.525 expected hard-disk
coverage. In the dilute limit, uniform radius jitter multiplies expected area
by `1 + J*J/(3*R*R)`, about 1.083 at `J = R/2`. Overlap generally reduces the
increase, and the factor is not a bound for individual finite fields.

[`specklecoverage.zig`](../src/riley/zig/specklecoverage.zig) computes in `f64`
without allocation or I/O: an integrated analytic polynomial for `r <= 0.5`,
otherwise a generated table over `0.5 <= r <= 1` with signed `M_2..M_9`
coefficients. Horner evaluation gives `F(p,r)/p` at nodes;
monotone PCHIP interpolates those values, not coefficients. At most 64 bisections
invert the approximation. Builds import constants without regeneration.

Separate oracle tests use vertical-slice circle/rectangle areas and direct
noncoverage probabilities, with `1e-6` absolute coverage acceptance near geometry
breaks and the cap. This is empirical evidence, not a global error bound or
finite-image guarantee. The generator checks node monotonicity in both modes;
`--check` verifies the committed table's shape and compares coefficients in
fixed radius-node order without rewriting the table. These checks are separate
from the scalar/SIMD equality tests.

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
Query supported alternatives and combinations with
`zig build bench-speckle-evaluators -Denable-all-evaluators=true -- --list-evaluators`
(or pass `--list-evaluators` to an installed binary). Masks use nearest-grid
sampling; `mask-u8` also quantizes to bytes. `mock` provides a raw-arithmetic
ablation.

`-Dspeckle-mask-samples-per-cell=8|12|16` selects experimental mask and
`classified-indexed` resolution (default 12, `MaskResolution` in Zig). It does
not change `classified-binned`, which uses a fixed 8×4 grid. Classification resolution
changes acceleration, not analytic field fidelity; masks remain approximations.

`python3 scripts/bench_speckle.py --help` lists profile factors and case-file schemas.
The runner reads each binary's catalogue; omitted raw Perlin controls use binary
A's defaults for both binaries. Raw evaluation compares named evaluators or
`texture`; full-render accepts `auto` or `texture` without neighborhood overrides.
Python checks scalar inputs; native validation and preparation check feasibility.
Each run exclusively claims a new or empty output directory; a claimed directory
cannot be reused, even if the run fails.

The full-render profile records physical inputs and declared evaluator policy,
not observed dispatch. Its only metric,
`combined_ns`, times the in-memory render including preparation. Ordered image
hashes for output equality are untimed. Only raw evaluation supports split
metrics (`--metrics setup render`). Raw texture samples report zero setup time:
geometry and UV gathering are untimed, as is texture decoding. When both variants
are textures, `render` is the default; select either `render` or `combined`, not
both, because they measure the same interval.

`resource_bytes` in native JSON measures retained backing allocations for
`cell-binned`, `list-indexed`, `classified-indexed`, and `classified-binned`
evaluation-mode runs, not peak process memory. `duplicated_disk_records` counts
live binned record references, excluding fixed-layout padding. Classified bins
also report `record_capacity`, including unused slots. These diagnostics do not
measure preparation scratch or peak process RSS. Uncollected values are `null`,
including metrics for textures and full-render runs.

`python3 scripts/compile_benchmarks.py speckle_evaluators` installs a stripped
experimental `ReleaseFast` binary at the runner's default path,
`bin/bench_speckle_evaluators_f64_simd`.

For custom builds, use separate install prefixes: the standard and experimental
builds have the same executable name, so installing both to one prefix
overwrites the first.
These examples use the default f64/SIMD executable name (append `.exe` on Windows).
Build the experimental benchmark and compare two exact hard-disk evaluators:

```shell
zig build install-bench-speckle-evaluators -Doptimize=ReleaseFast -Dstrip=true -Denable-all-evaluators=true --prefix zig-out/speckle-experimental
python3 scripts/bench_speckle.py --binary zig-out/speckle-experimental/bin/bench_speckle_evaluators_f64_simd \
  --out out/classified_binned_tuning --profile tuning --a cell-binned --b classified-binned \
  --patterns hard --neighbors 9 --require-equal-output
```

`tuning` and `full` both use native `evaluation` mode: fixed geometry with
shading, depth testing, and accumulation through the shader pipe. `tuning`
defaults to `combined`; `full` defaults to `setup` and `render` separately.
The `full-render` profile instead runs the production raster pipeline.

| Runner profiles | Native mode | Required `workload_mode` |
| --- | --- | --- |
| `tuning`, `full` | `evaluation` | `static-geometry-depth-accumulator-shaderpipe` |
| `full-render` | `full-render` | `production-raster-advanced-memory-shaderpipe` |

These unversioned IDs are checked against each binary's catalogue and results
by [`scripts/bench_speckle.py`](../scripts/bench_speckle.py). Compare matching
workloads and build settings, retain results, and use a fresh output directory.
Use `--workers` for worker budgets. For raw `texture`/`texture`, the `render`
default applies to both evaluation profiles.

For a production repeatability smoke comparison (`0.25` is a coarse radius):

```shell
zig build install-bench-speckle-evaluators -Doptimize=ReleaseFast -Dstrip=true --prefix zig-out/speckle-default
python3 scripts/bench_speckle.py --binary zig-out/speckle-default/bin/bench_speckle_evaluators_f64_simd \
  --out out/speckle_production_repeatability --profile full-render --coverage 0.5 --radius 0.25 --a auto --b auto
```

For cross-build A/B measurements, select the two executables with `--binary-a`
and `--binary-b`, retaining `auto/auto` and matching other build settings.

## Implementation constraints

Before render allocations, fast validation checks metadata and `SpeckleParams`;
full validation also scans UVs and connectivity. Mesh preparation checks the
interpolated UV domain and calibrates the referenced faces. Physical resolution
precedes UV/resource allocation; `SpeckleStatic` owns the gathered UVs and
sampler `Resources`. The selected backing owns the sampling parameters; cell-hash
stores them inline without allocating. Per-frame `SpecklePrepared` borrows a
`*const Resources` without copying parameters or taking ownership.
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
including cell-binned, evaluate every lane; callers discard inactive lanes.

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
