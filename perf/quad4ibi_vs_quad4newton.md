# Quad4IBI vs Quad4Newton

Comparison of rendered `MPx/s` for `quad4ibi` against `quad4newton` using:

- [fullraster_simd_on.md](/home/lloydf/zigraster/perf/quad4ibi_simd/fullraster_simd_on.md)
- [fullraster_simd_off.md](/home/lloydf/zigraster/perf/quad4ibi_simd/fullraster_simd_off.md)
- [sphere2000_simd_on.md](/home/lloydf/zigraster/perf/quad4ibi_simd/sphere2000_simd_on.md)
- [sphere2000_simd_off.md](/home/lloydf/zigraster/perf/quad4ibi_simd/sphere2000_simd_off.md)

`Diff` is `(quad4ibi - quad4newton) / quad4newton`.

## Fullraster SIMD On

| Case                    | `quad4ibi` MPx/s | `quad4newton`<br>`MPx/s` | Diff vs<br>`quad4newton` |
|-------------------------|-----------------:|-------------------------:|-------------------------:|
| `flat_grey`             |            23.96 |                    18.89 |                   +26.8% |
| `flat_rgb`              |            19.68 |                    15.95 |                   +23.4% |
| `tex8_grey_linear`      |            15.70 |                    13.45 |                   +16.7% |
| `tex8_grey_cubic`       |             7.99 |                     7.34 |                    +8.9% |
| `tex8_grey_cubic_lut`   |             8.30 |                     7.62 |                    +8.9% |
| `tex8_grey_quintic`     |             4.73 |                     4.51 |                    +4.9% |
| `tex8_grey_quintic_lut` |             6.17 |                     5.79 |                    +6.6% |
| `tex8_rgb_linear`       |            11.47 |                    10.54 |                    +8.8% |
| `tex8_rgb_cubic`        |             6.21 |                     5.87 |                    +5.8% |
| `tex8_rgb_cubic_lut`    |             6.33 |                     5.95 |                    +6.4% |
| `tex8_rgb_quintic`      |             3.53 |                     3.41 |                    +3.5% |
| `tex8_rgb_quintic_lut`  |             4.55 |                     4.32 |                    +5.3% |

## Fullraster SIMD Off

| Case                    | `quad4ibi` MPx/s | `quad4newton`<br>`MPx/s` | Diff vs<br>`quad4newton` |
|-------------------------|-----------------:|-------------------------:|-------------------------:|
| `flat_grey`             |            21.72 |                    10.56 |                  +105.7% |
| `flat_rgb`              |            15.59 |                     9.09 |                   +71.5% |
| `tex8_grey_linear`      |            13.58 |                     9.88 |                   +37.4% |
| `tex8_grey_cubic`       |             7.19 |                     5.98 |                   +20.2% |
| `tex8_grey_cubic_lut`   |             7.00 |                     5.86 |                   +19.5% |
| `tex8_grey_quintic`     |             4.71 |                     4.13 |                   +14.0% |
| `tex8_grey_quintic_lut` |             5.77 |                     4.68 |                   +23.3% |
| `tex8_rgb_linear`       |            10.78 |                     8.25 |                   +30.7% |
| `tex8_rgb_cubic`        |             6.05 |                     5.14 |                   +17.7% |
| `tex8_rgb_cubic_lut`    |             5.73 |                     4.94 |                   +16.0% |
| `tex8_rgb_quintic`      |             3.37 |                     3.08 |                    +9.4% |
| `tex8_rgb_quintic_lut`  |             4.27 |                     3.80 |                   +12.4% |

## Sphere2000 SIMD On

| Case         | `quad4ibi` MPx/s | `quad4newton`<br>`MPx/s` | Diff vs<br>`quad4newton` |
|--------------|-----------------:|-------------------------:|-------------------------:|
| `flat_grey`  |            16.26 |                    20.86 |                   -22.1% |
| `flat_rgb`   |            14.32 |                    18.20 |                   -21.3% |
| `tex8_grey`  |            13.37 |                    16.71 |                   -20.0% |
| `tex8_rgb`   |            11.29 |                    13.33 |                   -15.3% |

## Sphere2000 SIMD Off

| Case         | `quad4ibi` MPx/s | `quad4newton`<br>`MPx/s` | Diff vs<br>`quad4newton` |
|--------------|-----------------:|-------------------------:|-------------------------:|
| `flat_grey`  |            15.60 |                    12.19 |                   +28.0% |
| `flat_rgb`   |            12.72 |                    10.85 |                   +17.2% |
| `tex8_grey`  |            14.01 |                    12.04 |                   +16.4% |
| `tex8_rgb`   |            11.64 |                    10.18 |                   +14.3% |

## Read

`quad4ibi` is faster than `quad4newton` in `fullraster` with both SIMD modes,
and also faster in `sphere2000` with `.simd = .off`.

With `.simd = .on`, `sphere2000` flips and `quad4ibi` is slower across all four
cases. The likely reason is that the analytic inverse-bilinear path is not
particularly SIMD-friendly: it has substantial per-lane branching, which causes
lane divergence and reduces SIMD efficiency on the more realistic sphere
workload.
