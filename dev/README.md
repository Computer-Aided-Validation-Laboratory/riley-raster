# Riley Developer Notes
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**

## Testing Architecture & Core Packaged Suites
Riley provides a layered testing architecture designed for fast routine verification, rigorous mathematical validation, and exhaustive factorial test coverage:

### Quick Commands

All test targets default to Debug and honor `-Doptimize`. Select
`-Doptimize=ReleaseSafe` explicitly for optimized runs with safety checks.
The four suite targets use native Zig test build steps with the original source
files. Zig tracks imported source dependencies and build options; unrelated
demo or Python edits do not invalidate their test binaries. Test execution still
runs on each invocation so changes to gold data and runtime assets are checked.
`src/dev_support/testrunner.zig` exposes the generated options at the test
runner root used by `buildconfig.zig` and delegates execution to Zig's standard
test runner. This keeps precision, SIMD, solver, and vector-width options active
without modifying or copying suite source files.
Suite targets use Zig's standard terminal test runner with inherited console
streams. Status and suite/case timings are written to stdout using a buffered
`std.Io` writer flushed after each message; failure diagnostics remain on stderr.
The test runner reports test counts; use `--summary all` for build/run timings.
Clearing `.zig-cache` is safe and only forces a rebuild.

```shell
# 1. Combined Verification and Basic Suites (preferred routine/CI command)
zig build test-verif-basic -Doptimize=ReleaseSafe

# 2. Analytic Verification Suite (Mathematical & Numerical Validation)
zig build test-verif -Doptimize=ReleaseSafe

# 3. Basic Test Suite (Fast Core Feature Coverage)
zig build test-basic -Doptimize=ReleaseSafe

# 4. Full Test Suite (Exhaustive Factorial System Coverage)
zig build gen-gold-full -Doptimize=ReleaseSafe  # Generate Full gold (if needed)
zig build test-full -Doptimize=ReleaseSafe

# 5. Python Integration Suite
.venv/bin/pytest src/riley/pytests/
```

### Core Suites Summary

| Suite Name | Command | Primary Role | Reference Data |
| :--- | :--- | :--- | :--- |
| **Combined Core Suite** | `zig build test-verif-basic` | Compiles and runs Verification and Basic together to avoid duplicate CI compile work | `gold/verif/`, `gold/basic/` |
| **Verification Suite** | `zig build test-verif` | Inverse solver recovery, silhouette area/centroid, depth ordering, and camera distortion oracles | `gold/verif/` |
| **Basic Suite** | `zig build test-basic` | Fast coverage across 1-element, 2-shape FE interaction, and feature zoo cases | `gold/basic/` |
| **Full Suite** | `zig build test-full` | Exhaustive sweeps over shaders, textures, PSF/distortion, SSAA, hulls, tiling, scenes, threads, and outputs | `gold/full_*/` |
| **Python Pytests** | `.venv/bin/pytest src/riley/pytests/` | Python/Cython API, mesh pipeline, Exodus conversion, and demo parity | Integrated / `gold/` |

> [!NOTE]
> For complete documentation of all 4 test scenes, 8 sub-suites, gold generation, tolerances, and design contracts, see [**`dev/TESTING.md`**](file:///home/lloydf/riley-raster/dev/TESTING.md).

## Precision and SIMD Build Matrix
The `zig build` workflow supports direct control over precision, SIMD mode, Newton solver mode, and SIMD vector width:

```shell
zig build <STEP> -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
zig build <STEP> -Dprecision=f64 -Dsimd=off -Doptimize=ReleaseSafe
zig build <STEP> -Dprecision=f32 -Dsimd=on -Doptimize=ReleaseSafe
zig build <STEP> -Dprecision=f32 -Dsimd=off -Doptimize=ReleaseSafe
zig build <STEP> -Dnewton-solver=robust -Doptimize=ReleaseSafe
zig build <STEP> -Dsimd-vector-width=8 -Doptimize=ReleaseSafe
```

Suggested first-pass development checks on the main production path:

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
zig build test-basic -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
zig build test-full -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

For broader matrix checks across precisions and SIMD modes:

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
zig build test-basic -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe

zig build test-basic -Dprecision=f64 -Dsimd=off -Doptimize=ReleaseSafe
zig build test-basic -Dprecision=f32 -Dsimd=on -Doptimize=ReleaseSafe
zig build test-basic -Dprecision=f32 -Dsimd=off -Doptimize=ReleaseSafe
```

## Focused Verification Suite

The focused verification suite checks independent analytic and numerical contracts rather than broad image-output stability. It currently covers:

- inverse element-solver recovery from known parent coordinates;
- undistorted silhouette area and centroid against Python-generated analytic references;
- overlapping-rabbit depth ordering at four rear-surface separations;
- camera-distortion round trips plus independent OpenCV/NumPy forward, inverse,
  stacked-model, SIMD, and Jacobian oracles.

The suite is intentionally fixed to the production `f64` configuration with SIMD enabled:

```shell
zig build test-verif -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

The ordinary test command is Zig-only. It reads compact comparison data from
`./gold/verif/`; it does not run Python or regenerate expected results.

The depth cases place the rear rabbit at separations of one largest mesh-coordinate span,
`1/100` span, `1/1000` span, and twice the active depth-buffer tolerance. The final case is
constructed in inverse camera-depth space because Riley's depth-buffer comparison tolerance
has inverse-depth units. Each case renders the individual masks and both mesh submission
orders, then verifies the analytic front-over-rear composition pixel by pixel.

Regenerate the verification comparison data with the repository virtual environment:

```shell
zig build gen-gold-verif -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

This first runs the Zig input generator and then
`./src/gengold/gengold_verif.py`. The Python stage independently integrates the projected
linear and quadratic element boundaries and writes only the compact analytic results beneath
`./gold/verif/`. These files remain ignored for now. If they are committed later, only the
`f64`, SIMD-enabled dataset should be added.

Changes to verification comparison data should be reviewed together with the generator and
the numerical diff. Do not regenerate comparison data as part of `test-verif`.

## Benchmark Binaries
The benchmark entry points exposed through `zig build` are:

- `bench-dicuq`
- `bench-fullraster`
- `bench-tiltraster`
- `bench-geom`
- `bench-sphere2000`
- `bench-sphere2000zoom`
- `bench-thread-geom`
- `benches`

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

## Python Parity Check
The packaged Python tests live in `src/riley/pytests/`.

Run the full packaged Python test suite with:

```shell
python -m pytest --pyargs riley.pytests -s
```

or:

```shell
python -m riley test
```

To compare the Python bindings against the Zig demo outputs specifically:

```shell
python -m pytest --pyargs riley.pytests.test_riley -s
```

To force a fresh Zig render instead of reusing cached demo BMPs:

```shell
RILEY_FORCE_ZIG_RENDER=1 python -m pytest --pyargs riley.pytests.test_riley -s
```

Run a packaged Python demo directly with:

```shell
python -m riley demo0_quickstart
python -m riley demo1_sphere
python -m riley demo2a_rabbits_mono
python -m riley demo2b_rabbits_rgb
python -m riley demo2c_rabbits_fields
python -m riley demo3_dicuq
python -m riley demo3_dicuq_from_exodus
python -m riley demo4_stereocal
python -m riley demo5_cameramodels
python -m riley demo6_featurezoo
```

Python demo output is written to `Path.cwd() / "out_riley_py" / "<demo-name>"`.

The Zig demos use the same numbered names and ordering. The three rabbit demos
share mesh loading, shader setup, and layout in `src/demo_rabbits_common.zig`;
the Python variants share `demo_rabbits_common.py`. Camera inputs are constructed
directly; Riley prepares them internally.

Rabbit parity checks also require more than 10% foreground coverage in every
render, so matching blank images cannot pass verification.

Demos that clear previous output share `src/demo_common.zig`:

```zig
var out_dir = try demo_common.resetOutputDir(io, out_dir_root);
defer out_dir.close(io);
```

This removes the named demo output directory, recreates it (including missing
parents), and returns an open handle for metadata exports. It does not clear the
parent output directory. Absolute paths, parent traversal, and empty/current
directory paths are rejected. Helper regression tests run with `test-basic`.

`demo5_cameramodels` renders all six distortion families with pixel-box,
separable/non-separable Gaussian, aligned separable anisotropic Gaussian, and
rotated non-separable anisotropic Gaussian PSFs. Each of the 30 combinations is
rendered through all three buffer modes, producing 90 comparison images under
`<distortion>/<psf>/<buffer-mode>/`. Demo parity checks require the full matrix.

## Notes

### Polynomial camera distortion

Polynomial maps support total degrees 1 through 7. Supply one forward map in
dimensionless normalized camera coordinates, in the same direction as
Brown–Conrady. Inversion numerically solves that same map; there are no supplied
inverse coefficients or direction flags.

Coefficients are a row-major paired buffer with logical shape
`[term_count, 2]`, where `term_count = (degree + 1) * (degree + 2) / 2`.
Terms are ordered by increasing total degree, then descending x exponent:
`1, x, y, x², xy, y², ...`. Each term stores its x-output and y-output
coefficient next to each other. Degrees 1–7 use 3, 6, 10, 15, 21, 28, 36 pairs.

Choose `PolyMode.coordinate` for `(P(x,y), Q(x,y))` or
`PolyMode.displacement` for `(x + P(x,y), y + Q(x,y))`.
Coordinate identity needs x/y linear coefficients of one; zero coordinate
coefficients describe a zero map. Zero displacement coefficients describe identity.

```zig
const coeffs = [_]F{ 0, 0, 0.01, 0, 0, -0.01 };
const poly = try cam.PolyMap.init(1, .displacement, &coeffs);
const distort = try cam.DistortModel.init(.{ .poly = poly });
```

Native maps borrow `[]const F`: construction validates but does not allocate.
Keep coefficient storage alive and unchanged until preparation/rendering and
all workers complete. Struct copies and `paramsFromModel()` do not extend its
lifetime. Native empty map defaults retain displacement identity semantics.

Evaluation methods are `ford`, `fordWithJac`, and `inv`. Forward-only does
not compute derivatives. Inversion reports singularity, nonfinite arithmetic,
or nonconvergence, and only residual convergence is success. Arbitrary maps
need not be invertible; root uniqueness and convergence are not guaranteed.
BC/BCExt composition applies Brown–Conrady first, then the polynomial.
Inversion reverses that order.

CSV loading returns an owner rather than a self-contained camera input:

```zig
const loaded = try cameraio.LoadedCamera.init(outer_alloc, io, dir, "camera.csv");
defer loaded.deinit(outer_alloc);
// Render loaded.camera_input before deinitializing the owner.
```

Stereo loading uses `LoadedStereoPair.init/deinit` and `.stereo_pair`.
Neither owner stores an allocator; callers pass the same allocator to deinit.
CSV metadata is `poly_degree`, `poly_mode`, and
`poly_coeff_<term>_x` / `poly_coeff_<term>_y`. Coefficients are written with
roundtrip-safe scientific precision. Conventional model tags are unchanged.

Python cameras use `distort_poly=riley.PolyMap(degree, mode, coeffs)`, with
`mode=riley.EPolyMode.coordinate` or `.displacement`. Coefficients have
shape `(term_count, 2)`. The binding takes a contiguous owned f64 snapshot for
each native call, accepts strided/real numeric arrays, and never silently
reshapes, truncates or pads wrong-shaped data. Python-loaded maps own their arrays.

The C ABI exposes `distort_poly_degree`, `distort_poly_mode` (0 coordinate,
1 displacement), `distort_poly_coeffs` and `distort_poly_coeffs_len`.
Render/save calls borrow the caller's buffers through worker completion.
`rileyLoadCamera` accepts caller storage/capacity; null storage with zero
capacity queries metadata and required count, returning a null coefficient
pointer. Load again with sufficient caller-owned storage. Capacity is checked
on the final load even if the file changes between calls. Stereo loading
accepts independent buffers for each camera. No returned pointer references
the loader's temporary arena.

This is a breaking ABI/API/schema change: rebuild the native library, Cython
extension and C clients together. To migrate old degree-1–3 displacement data,
interleave only the active u/v coefficients and explicitly select displacement.
No automatic padding or compatibility shim is provided.

Adaptive hulls and conservative distorted curved-boundary bounds are outside
this update. Flat/low-curvature plate rendering is the intended immediate use;
pointwise polynomial correctness does not establish conservative raster bounds.
See `plans/bug_distorted_curved_hull.md` for the existing limitation.

### Managed render groups

Use the public owner to create render groups from a render-thread budget:

```zig
var groups = try riley.ManagedRenderGroups.init(init.gpa, init.minimal, .{
    .thread_budget = 8,
});
defer groups.deinit(init.gpa);
// Pass groups.specs to riley.raster(...).
```

By default this creates eight caller-only groups. Set `.max_groups = 1` for a
single-frame demo with four raster workers (`.thread_budget = 4`), or cap groups
to limit simultaneous frame memory or match available jobs. Remaining workers
are distributed evenly: budget 12 capped to five groups gives `3, 3, 2, 2, 2`.
`RasterConfig.max_raster_workers_per_job` must also allow the desired worker
count. The helper does not change raster settings.

Budgets include group callers, exclude disk-save overlap threads, and must be
positive (as must an explicit group cap). Use a thread-safe backing allocator,
not a shared arena. The owner, allocator and process metadata must outlive all
uses of `groups.specs`; finish rendering before `deinit`, and do not copy the
owning value. Pass `null` instead of process metadata when embedding Riley.
Pass the same allocator to `init` and `deinit`; the owner does not store it.

Python keeps `create_raster_config`, with optional `num_cameras` for camera/frame
job budgeting. The C runtime uses the same managed-group owner and balanced
remainder policy, without changing the C ABI. The sphere, rabbit, and camera-model demos use four
raster workers; quickstart uses one. Multi-frame demos prefer independent jobs.
The shared C library explicitly uses LLVM even in Debug: Zig 0.16's self-hosted
Debug backend mispasses floating-point struct arguments at the C boundary in
camera helpers. Native demo/test backend selection is unchanged.

- Plain `zig run` and `zig test` under `./src/` use the default Riley path of `f64` with SIMD enabled. Run the four suite drivers through `zig build` to select precision, SIMD, solver, or vector-width options.
- The public C ABI is fixed to that same production path.
- Some older benchmark helper scripts remain in `./scripts/` for historical studies. Prefer the current commands above unless you specifically need an archived workflow.
