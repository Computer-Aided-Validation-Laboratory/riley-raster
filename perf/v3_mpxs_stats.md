# V3 MPx/s Stats

Median `MPx/s` from the latest archived `v3` 10-run rerun:

- `perf/v3_variability_rerun/fullraster/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/geom/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/sphere2000/bench0.md` to `bench9.md`

Each value below is the median `MPx/s` for that case across the 10 runs.

## Fullraster

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|---------------|-----------:|----------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`        |     93.185 |    44.570 |       22.215 |          9.895 |             11.245 |             5.960 |                 8.455 |
| `tri3opt`     |     92.380 |    44.960 |       22.195 |          9.890 |             11.285 |             5.950 |                 8.460 |
| `tri6`        |     14.980 |    12.820 |       11.285 |          6.675 |              6.940 |             4.260 |                 5.340 |
| `quad4ibi`    |     20.970 |    14.335 |       12.825 |          6.620 |              6.420 |             4.590 |                 5.530 |
| `quad4newton` |     20.055 |    16.450 |       14.010 |          7.575 |              7.915 |             4.600 |                 5.940 |
| `quad8`       |     15.195 |    12.855 |       11.340 |          6.700 |              6.960 |             4.270 |                 5.345 |
| `quad9`       |     13.685 |    11.750 |       10.380 |          6.345 |              6.595 |             4.130 |                 5.140 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|---------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`        |      14.830 |         6.885 |             7.790 |           4.510 |               5.890 |
| `tri3opt`     |      14.825 |         6.870 |             7.805 |           4.510 |               5.885 |
| `tri6`        |       9.140 |         5.465 |             5.550 |           3.270 |               4.110 |
| `quad4ibi`    |      10.295 |         5.620 |             5.400 |           3.190 |               4.000 |
| `quad4newton` |      10.780 |         5.970 |             6.130 |           3.460 |               4.420 |
| `quad8`       |       9.190 |         5.450 |             5.560 |           3.270 |               4.135 |
| `quad9`       |       8.555 |         5.155 |             5.315 |           3.190 |               3.970 |

## Geom

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|---------------|-----------:|----------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`        |     27.565 |    20.125 |       10.780 |          6.455 |              7.305 |             4.560 |                 5.965 |
| `tri3opt`     |     28.015 |    19.970 |       10.790 |          6.440 |              7.285 |             4.555 |                 5.950 |
| `tri6`        |      4.280 |     4.010 |        3.825 |          3.065 |              3.080 |             2.430 |                 2.730 |
| `quad4ibi`    |     13.775 |    10.375 |        9.815 |          5.680 |              5.520 |             4.055 |                 4.780 |
| `quad4newton` |      8.305 |     7.510 |        7.880 |          5.250 |              5.355 |             3.590 |                 4.360 |
| `quad8`       |      5.380 |     4.990 |        4.685 |          3.640 |              3.690 |             2.750 |                 3.175 |
| `quad9`       |      5.290 |     4.900 |        4.585 |          3.545 |              3.565 |             2.710 |                 3.050 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|---------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`        |       8.385 |         4.940 |             5.375 |           3.540 |               4.350 |
| `tri3opt`     |       8.370 |         4.925 |             5.380 |           3.540 |               4.340 |
| `tri6`        |       3.465 |         2.740 |             2.730 |           2.040 |               2.330 |
| `quad4ibi`    |       8.225 |         4.920 |             4.690 |           2.930 |               3.610 |
| `quad4newton` |       6.645 |         4.365 |             4.375 |           2.820 |               3.435 |
| `quad8`       |       4.275 |         3.200 |             3.130 |           2.285 |               2.680 |
| `quad9`       |       4.040 |         3.045 |             3.015 |           2.210 |               2.550 |

## Sphere2000

| Element       | nodal_grey | nodal_rgb | tex_grey | tex_rgb |
|---------------|-----------:|----------:|---------:|--------:|
| `tri3`        |     66.635 |    40.525 |   25.340 |  17.900 |
| `tri3opt`     |     67.090 |    41.285 |   25.340 |  17.545 |
| `tri6`        |      8.370 |     7.710 |    7.100 |   6.340 |
| `quad4ibi`    |     15.765 |    12.295 |   12.145 |  10.390 |
| `quad4newton` |     20.465 |    17.180 |   16.995 |  13.545 |
| `quad8`       |     12.580 |    11.225 |   10.745 |   9.305 |
| `quad9`       |     11.765 |    10.570 |   10.095 |   8.850 |

## Read

- `tri3` and `tri3opt` dominate raw raster throughput in all three suites.
- `quad4newton` is the strongest nonlinear kernel in the latest `v3` rerun.
- `quad9` remains the slowest family in `geom` and one of the noisier families in the
  variability studies, so its numbers should still be interpreted with the wider
  uncertainty bounds from `perf_uncertainty.md`.
