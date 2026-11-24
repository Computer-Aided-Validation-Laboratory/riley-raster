# Riley Developer Guide
This document collects information for developers including style guides, testing architecture, benchmark executables, and performance regression workflows.

## Style Guide
This project follows the Computer Aided Validation Laboratory style guides for Python and Zig which can be found [here](https://github.com/Computer-Aided-Validation-Laboratory/styleguides). Riley is designed around three equally important principles:

1. **Make it correct.**
2. **Make it fast.**
3. **Make it simple for users.**

## Development Guides
The `dev/` directory provides comprehensive architectural, mathematical, testing, and conventions documentation for Riley developers:

- [**`dev/TESTING.md`**](TESTING.md): Complete testing architecture, quickstart commands, descriptions of the 4 test scenes, detailed breakdown of the 8 full-suite sub-suites, gold reference generation, and automated regression diagnostics.
- [**`dev/THEORY.md`**](THEORY.md): Mathematical foundations and engine design details, including polynomial camera distortion formulation, distortion-aware rasterisation frontend bounds, render thread budgets, and image save mode mechanics.
- [**`dev/ASSUMPTIONS.md`**](ASSUMPTIONS.md): Supported engineering operating envelope, mesh validity contracts, conservative numerical margins, and reasoning guidelines for review.
- [**`dev/MESHCONVENTION.md`**](MESHCONVENTION.md): Riley standard mesh representation, surface element definitions (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`), 3D continuum elements, node ordering, and connectivity conventions.
- [**`dev/FILESTRUCTURE.md`**](FILESTRUCTURE.md): Zig module naming and scalar/SIMD file splitting, naming for tutorials and development programs, and internal code organisation.
- [**`dev/ABBREVIATIONS.md`**](ABBREVIATIONS.md): Standardized abbreviations and naming conventions across Zig, C ABI, and Python codebases.
- [**`dev/DOCS.md`**](DOCS.md): Build and preview the combined Sphinx Python API and Zig API documentation.
- [**`dev/PROCEDURAL.md`**](PROCEDURAL.md): Procedural shader tutorials, evaluator benchmarking, and implementation constraints.

## Python development and distribution

Use `pip install -e ".[dev,docs]"` for pip-installable extras, or
`uv sync --group dev --group docs` for checkout dependency groups. Both carry
matching development/documentation tools; groups are not published extras.

Windows wheel publication targets AMD64. The source-build selector separately
matches the Python interpreter, retaining `win32` → `x86-windows-msvc` as well as
AMD64 and ARM64 mappings. A mapping does not promise a published wheel or CI
coverage: source installs also require compatible dependencies and a C compiler.

## Build and test configuration

See the [testing quickstart](TESTING.md#1-quickstart-guide) for suite commands,
optimisation modes, and CI policy. `zig build test-unit` runs the
[gold-independent native suite](../src/test_unit.zig).
Ubuntu CI checks formatting with `zig fmt --check build.zig build.zig.zon src scripts`.
`zig build --help` lists targets and options,
including precision, SIMD, Newton solver, vector width, and symbol stripping.
Plain `zig run` and `zig test` under `src/` use `f64` with SIMD enabled; use
`zig build` to select other settings.

The public C ABI uses f64/SIMD and the default evaluator policy. The shared C
library uses LLVM even in Debug: Zig 0.16's self-hosted Debug backend mispasses
floating-point struct arguments at the C boundary in camera helpers. Native
demos and tests select their backends independently.

## Benchmark Binaries
Use `-Doptimize=ReleaseFast` for performance measurements. Find `bench-*` and
`install-bench-*` targets with `zig build --help`. Binaries install to
`zig-out/bin/` by default; use `--prefix .` for workflows that expect `./bin/`:

```shell
zig build install-bench-bins -Doptimize=ReleaseFast --prefix .
```

See the [procedural guide](PROCEDURAL.md#internal-evaluator-experiments-and-benchmarking)
for speckle evaluator comparisons.

Where the runner supports them, pass installed paths via `--binary` or
`--binary-a`/`--binary-b`.

## Performance Regression Scripts
Compile the standard SIMD benchmarks, generate local references under `perf/`,
then run regression checks against those references:

```shell
python scripts/compile_para_benchmarks.py --simd-only
python scripts/gen_gold_perf_all.py
python scripts/test_perf_all.py
```

To isolate a case, run its `scripts/test_perf_<case>.py` directly. Use `--profile`
to select a profile such as `1thread` or `4thread`; see `--help` for choices.

## Benchmark Experiment Orchestration
Build the configured `bench_tiltraster` variants into `bin/`, then run the
raster experiment matrix:

```shell
python scripts/compile_perf_all.py
python scripts/bench_perf_raster.py
```

Use `python scripts/bench_perf_raster.py --help` for overrides and `--dry-run`
to preview commands. Change the case and SSAA matrix in the constants at the top
of `scripts/bench_perf_raster.py`. The runner writes per-run output under
`out/bench_stats_perf/<timestamp>/`, images under `out/bench_images_perf/`, and
summary timings to `out/time_bench_perf_raster_<timestamp>.csv`.

## Additional Notes

Benchmark helpers under `scripts/legacy/` are not part of the current
verification workflow.
