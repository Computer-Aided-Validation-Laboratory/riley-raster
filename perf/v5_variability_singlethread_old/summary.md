# V5 Variability Summary

Benchmark runs saved in this directory:
- `fullraster_run1.md` .. `fullraster_run10.md`
- `geom_run1.md` .. `geom_run10.md`
- `sphere2000_run1.md` .. `sphere2000_run10.md`

Overview of the requested stability metrics across 10 runs:

| Benchmark | Metric | Runs | Cases | Mean CV | Median CV | Worst Case | Worst CV | Best Case | Best CV |
|-----------|--------|-----:|------:|--------:|----------:|------------|---------:|-----------|--------:|
| `fullraster` | `MPx/s` | 10 | 72 | 3.70% | 3.19% | `quad9_tex8_grey_cubic_lut_lerp` | 9.22% | `quad8_tex8_grey_quintic` | 2.44% |
| `geom` | `MElems/s` | 10 | 72 | 4.62% | 4.41% | `quad4ibi_tex8_rgb_linear` | 7.54% | `quad4ibi_flat_rgb` | 2.44% |
| `sphere2000` | `MPx/s` | 10 | 24 | 2.71% | 2.53% | `tri3_tex8_rgb` | 3.93% | `quad9_tex8_grey` | 1.99% |
| `sphere2000` | `MElems/s` | 10 | 24 | 3.66% | 3.67% | `quad9_tex8_rgb` | 6.36% | `quad4newton_flat_rgb` | 2.02% |

Detailed top-10 highest-variability cases for each requested benchmark/metric:

## fullraster MPx/s

| Case | Median | Mean | Std Dev | CV | Min | Max | Range |
|------|-------:|-----:|--------:|---:|----:|----:|------:|
| `quad9_tex8_grey_cubic_lut_lerp` | 6.40 | 6.33 | 0.58 | 9.22% | 4.84 | 6.80 | 1.96 |
| `quad4newton_tex8_grey_cubic_lut_lerp` | 7.62 | 7.53 | 0.67 | 8.96% | 5.73 | 8.11 | 2.38 |
| `quad8_tex8_grey_cubic_lut_lerp` | 6.76 | 6.68 | 0.53 | 7.99% | 5.25 | 7.17 | 1.92 |
| `tri6_tex8_grey_cubic_lut_lerp` | 6.72 | 6.70 | 0.46 | 6.91% | 5.50 | 7.14 | 1.64 |
| `tri3_flat_rgb` | 44.09 | 45.21 | 2.87 | 6.34% | 42.02 | 49.97 | 7.95 |
| `quad9_flat_grey` | 13.34 | 13.26 | 0.81 | 6.08% | 11.79 | 14.25 | 2.46 |
| `quad9_tex8_rgb_linear` | 8.62 | 8.52 | 0.51 | 6.01% | 7.70 | 9.01 | 1.31 |
| `quad9_flat_rgb` | 11.52 | 11.56 | 0.69 | 6.00% | 10.41 | 12.29 | 1.88 |
| `quad4ibi_tex8_grey_cubic_lut_lerp` | 7.05 | 7.03 | 0.41 | 5.83% | 6.02 | 7.46 | 1.44 |
| `quad9_tex8_grey_linear` | 10.16 | 10.23 | 0.56 | 5.51% | 9.31 | 10.82 | 1.51 |
## geom MElems/s

| Case | Median | Mean | Std Dev | CV | Min | Max | Range |
|------|-------:|-----:|--------:|---:|----:|----:|------:|
| `quad4ibi_tex8_rgb_linear` | 16.60 | 16.12 | 1.22 | 7.54% | 13.06 | 17.00 | 3.94 |
| `tri6_tex8_grey_cubic` | 12.25 | 11.92 | 0.89 | 7.43% | 10.39 | 12.75 | 2.36 |
| `quad9_flat_rgb` | 9.12 | 8.83 | 0.61 | 6.92% | 7.80 | 9.42 | 1.62 |
| `quad4newton_tex8_grey_quintic` | 16.27 | 15.95 | 1.07 | 6.73% | 13.50 | 16.88 | 3.38 |
| `quad4ibi_tex8_rgb_quintic_lut_lerp` | 16.49 | 16.07 | 1.06 | 6.61% | 14.15 | 16.97 | 2.82 |
| `quad4newton_flat_grey` | 16.44 | 16.06 | 1.05 | 6.54% | 14.01 | 16.84 | 2.83 |
| `tri6_tex8_grey_quintic` | 12.04 | 11.67 | 0.75 | 6.42% | 10.44 | 12.58 | 2.14 |
| `tri6_tex8_grey_cubic_lut_lerp` | 11.95 | 11.74 | 0.74 | 6.35% | 10.26 | 12.70 | 2.44 |
| `quad9_tex8_rgb_cubic` | 9.20 | 9.16 | 0.57 | 6.20% | 8.25 | 9.77 | 1.52 |
| `tri3_flat_rgb` | 32.59 | 32.04 | 1.98 | 6.17% | 28.30 | 33.68 | 5.38 |
## sphere2000 MPx/s

| Case | Median | Mean | Std Dev | CV | Min | Max | Range |
|------|-------:|-----:|--------:|---:|----:|----:|------:|
| `tri3_tex8_rgb` | 18.90 | 18.91 | 0.74 | 3.93% | 17.75 | 19.69 | 1.94 |
| `quad4newton_tex8_rgb` | 14.29 | 14.06 | 0.53 | 3.74% | 13.06 | 14.49 | 1.43 |
| `quad4newton_flat_rgb` | 18.34 | 18.30 | 0.64 | 3.47% | 17.25 | 18.97 | 1.72 |
| `quad4newton_tex8_grey` | 17.48 | 17.32 | 0.56 | 3.23% | 16.60 | 17.90 | 1.30 |
| `quad4ibi_tex8_rgb` | 11.05 | 11.15 | 0.34 | 3.05% | 10.59 | 11.54 | 0.95 |
| `tri3_flat_grey` | 68.66 | 68.78 | 2.09 | 3.04% | 64.69 | 71.37 | 6.68 |
| `tri3_tex8_grey` | 25.98 | 26.01 | 0.76 | 2.93% | 24.86 | 27.33 | 2.47 |
| `quad8_tex8_grey` | 10.82 | 10.93 | 0.32 | 2.89% | 10.53 | 11.35 | 0.82 |
| `quad4ibi_tex8_grey` | 13.46 | 13.40 | 0.39 | 2.89% | 12.88 | 13.80 | 0.92 |
| `quad4ibi_flat_grey` | 15.46 | 15.38 | 0.41 | 2.66% | 14.81 | 15.83 | 1.02 |
## sphere2000 MElems/s

| Case | Median | Mean | Std Dev | CV | Min | Max | Range |
|------|-------:|-----:|--------:|---:|----:|----:|------:|
| `quad9_tex8_rgb` | 8.75 | 8.54 | 0.54 | 6.36% | 7.43 | 8.97 | 1.54 |
| `tri3_tex8_rgb` | 37.02 | 36.81 | 1.95 | 5.30% | 33.32 | 39.15 | 5.83 |
| `tri3_flat_grey` | 39.59 | 39.48 | 2.00 | 5.07% | 35.35 | 41.80 | 6.45 |
| `tri6_flat_rgb` | 13.49 | 13.28 | 0.66 | 4.94% | 11.45 | 13.64 | 2.19 |
| `quad4newton_flat_grey` | 18.38 | 18.18 | 0.76 | 4.16% | 16.63 | 19.18 | 2.55 |
| `quad4ibi_tex8_grey` | 17.71 | 17.69 | 0.73 | 4.14% | 16.54 | 18.56 | 2.02 |
| `quad8_flat_rgb` | 7.24 | 7.12 | 0.29 | 4.06% | 6.47 | 7.35 | 0.88 |
| `quad4ibi_flat_grey` | 17.94 | 18.20 | 0.74 | 4.05% | 17.18 | 19.21 | 2.03 |
| `quad8_tex8_grey` | 7.51 | 7.47 | 0.30 | 4.01% | 6.72 | 7.78 | 1.06 |
| `quad4newton_tex8_grey` | 17.65 | 17.58 | 0.69 | 3.93% | 16.54 | 18.42 | 1.88 |
