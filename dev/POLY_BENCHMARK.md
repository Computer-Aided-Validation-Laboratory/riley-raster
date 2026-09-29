# Degree-7 polynomial kernel measurements

Date: 2026-09-29. Exploratory local measurements, not a cross-machine guarantee.

- Zig 0.16.0, ReleaseFast, f64, eight SIMD lanes.
- AMD Ryzen 7 8845HS, Linux x86_64.
- Baseline: camera-model sources from revision `042589d`, before this refactor.
- Workload: `src/benchpoly.zig`, 100,000 varying sample batches per trial,
  one warmup then four measured trials. Values and every Jacobian component
  contribute to printed checksums, preventing dead-result elimination.
- Inverse targets are prepared before timing. Inverse timing excludes forward
  target generation; successful solves are required.
- Median of four measured trials. Some measurements overlapped other development
  work; rerun on an otherwise idle machine before making deployment decisions.

## Descriptor sizes

The native f64 polynomial descriptor shrank from 168 to 24 bytes.
The distortion-model union shrank from 440 to 296 bytes (BCExt still determines
the largest variant). Coefficient storage is separate: 48 bytes for degree 1,
576 bytes for degree 7, owned by the caller and shared immutably.

## Old versus new displacement kernels

Nanoseconds per scalar call or eight-lane SIMD batch:

| Degree | Kernel | Old | New |
| --- | --- | ---: | ---: |
| 1 | scalar_ford | 6.19 | 3.03 |
| 1 | scalar_jac | 7.35 | 4.46 |
| 1 | scalar_inv | 16.23 | 12.97 |
| 1 | simd_ford | 5.18 | 5.03 |
| 1 | simd_jac | 8.71 | 8.66 |
| 1 | simd_inv | 25.83 | 25.79 |
| 3 | scalar_ford | 14.75 | 5.94 |
| 3 | scalar_jac | 27.89 | 14.29 |
| 3 | scalar_inv | 73.19 | 42.04 |
| 3 | simd_ford | 14.71 | 10.63 |
| 3 | simd_jac | 31.06 | 26.59 |
| 3 | simd_inv | 88.16 | 76.00 |

The baseline was compiled from temporary copies of the actual old common/SIMD
source, not a newly invented mathematical reference. A small adapter converted
paired setup coefficients into the old two-array layout before timing. Coordinate
mode was represented by subtracting identity coefficients before timing, because
the old API only exposed displacement. Temporary baseline sources were removed;
the baseline revision and the current benchmark define the reproduction inputs.

These results support retaining the straightforward runtime-degree implementation:
no low-degree kernel regression was observed in this experiment. They do not
establish a full-scene speedup, a cache-layout advantage over SoA, or a need for
degree-specialised code. No seven-way comptime degree dispatch was added.

## New higher-degree kernels

| Degree | Mode | Scalar ford | Scalar jac | Scalar inv | SIMD ford | SIMD jac | SIMD inv |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | displacement | 3.03 | 4.46 | 12.97 | 5.03 | 8.66 | 25.79 |
| 1 | coordinate | 3.06 | 4.40 | 12.04 | 4.80 | 8.22 | 24.62 |
| 3 | displacement | 5.94 | 14.29 | 42.04 | 10.63 | 26.59 | 76.00 |
| 3 | coordinate | 5.67 | 13.53 | 39.70 | 11.46 | 25.15 | 73.91 |
| 5 | displacement | 11.23 | 30.19 | 80.25 | 20.03 | 54.61 | 145.18 |
| 5 | coordinate | 11.50 | 29.71 | 76.87 | 19.68 | 55.64 | 147.43 |
| 7 | displacement | 20.38 | 50.44 | 129.78 | 32.22 | 95.56 | 246.75 |
| 7 | coordinate | 20.23 | 49.61 | 129.26 | 31.41 | 96.47 | 244.58 |

## Reproduction and scope

```sh
zig build bench-poly -Doptimize=ReleaseFast
zig build bench-poly -Doptimize=ReleaseFast -Dprecision=f32
```

Selection of degree, mode, operation and trial is runtime orchestration.
Only scalar/SIMD type and whether derivatives are requested are specialised.
Arrays of powers are stack-local and coefficient validation happens outside the
timed kernels. No heap coefficient allocation occurs during evaluation.

Use `zig build test-poly` for the precision/backend matrix and
`zig build test-verif` for independent numerical accuracy. Numerical correctness
is an acceptance gate, not a tunable tradeoff for these timings.

No adaptive-hull or curved-boundary raster changes are included. Existing gold
regressions and flat-plate integration exercise rendering, but do not prove
arbitrary distorted curved-element coverage. Thermal state, runtime-varying
coefficient working sets, detailed iteration distributions, whole-scene timing,
compile-time comparisons and alternatives such as Horner/specialised degrees
remain useful follow-up profiling rather than justification for extra code now.
