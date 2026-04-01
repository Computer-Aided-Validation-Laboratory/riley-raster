# V3 MElem/s Stats

Median `MElem/s` from the latest archived `v3` 10-run rerun:

- `perf/v3_variability_rerun/fullraster/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/geom/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/sphere2000/bench0.md` to `bench9.md`

Each value below is the median `MElem/s` for that case across the 10 runs.

## Fullraster

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic  | tex_grey_quintic_lut  |
|---------------|------------|-----------|--------------|----------------|--------------------|-------------------|-----------------------|
| `tri3`        |      0.165 |     0.145 |        0.170 |          0.175 |              0.170 |             0.165 |                 0.165 |
| `tri3opt`     |      0.160 |     0.140 |        0.160 |          0.175 |              0.160 |             0.170 |                 0.160 |
| `tri6`        |      0.160 |     0.120 |        0.155 |          0.170 |              0.150 |             0.165 |                 0.170 |
| `quad4ibi`    |      0.110 |     0.085 |        0.110 |          0.110 |              0.110 |             0.110 |                 0.105 |
| `quad4newton` |      0.110 |     0.075 |        0.110 |          0.115 |              0.110 |             0.110 |                 0.110 |
| `quad8`       |      0.105 |     0.080 |        0.100 |          0.105 |              0.105 |             0.100 |                 0.100 |
| `quad9`       |      0.110 |     0.070 |        0.110 |          0.110 |              0.110 |             0.100 |                 0.105 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic  | tex_rgb_cubic_lut  | tex_rgb_quintic   | tex_rgb_quintic_lut   |
|---------------|-------------|----------------|--------------------|-------------------|-----------------------|
| `tri3`        |       0.120 |          0.130 |              0.130 |             0.130 |                 0.130 |
| `tri3opt`     |       0.130 |          0.120 |              0.135 |             0.145 |                 0.130 |
| `tri6`        |       0.120 |          0.120 |              0.130 |             0.125 |                 0.130 |
| `quad4ibi`    |       0.070 |          0.075 |              0.075 |             0.080 |                 0.070 |
| `quad4newton` |       0.065 |          0.080 |              0.075 |             0.080 |                 0.070 |
| `quad8`       |       0.070 |          0.070 |              0.070 |             0.070 |                 0.070 |
| `quad9`       |       0.070 |          0.075 |              0.070 |             0.080 |                 0.070 |

## Geom

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic  | tex_grey_quintic_lut  |
|---------------|------------|-----------|--------------|----------------|--------------------|-------------------|-----------------------|
| `tri3`        |     30.430 |    30.455 |       30.475 |         30.660 |             30.445 |            30.600 |                30.550 |
| `tri3opt`     |     30.740 |    30.580 |       31.350 |         30.870 |             30.450 |            30.550 |                30.315 |
| `tri6`        |     10.525 |    10.515 |       10.455 |         10.615 |             10.375 |            10.345 |                10.725 |
| `quad4ibi`    |     31.175 |    31.060 |       30.810 |         30.440 |             30.880 |            31.420 |                29.835 |
| `quad4newton` |     15.595 |    14.915 |       15.480 |         14.970 |             15.000 |            15.080 |                15.035 |
| `quad8`       |      6.780 |     6.680 |        6.770 |          6.625 |              6.810 |             6.685 |                 6.780 |
| `quad9`       |      8.680 |     8.150 |        8.800 |          8.780 |              8.680 |             8.580 |                 8.740 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic  | tex_rgb_cubic_lut  | tex_rgb_quintic   | tex_rgb_quintic_lut   |
|---------------|-------------|----------------|--------------------|-------------------|-----------------------|
| `tri3`        |      30.330 |         30.820 |             30.600 |            31.005 |                31.125 |
| `tri3opt`     |      31.040 |         29.980 |             30.455 |            30.425 |                29.260 |
| `tri6`        |      10.545 |         10.650 |             10.455 |            10.465 |                10.460 |
| `quad4ibi`    |      31.120 |         31.245 |             30.675 |            29.670 |                31.650 |
| `quad4newton` |      14.745 |         15.040 |             14.845 |            14.955 |                15.020 |
| `quad8`       |       6.740 |          6.695 |              6.755 |             6.750 |                 6.830 |
| `quad9`       |       8.670 |          8.450 |              8.615 |             8.545 |                 8.650 |

## Sphere2000

| Element       | nodal_grey | nodal_rgb | tex_grey | tex_rgb |
|---------------|------------|-----------|----------|---------|
| `tri3`        |     36.490 |    34.425 |   36.440 |  34.685 |
| `tri3opt`     |     36.970 |    33.695 |   36.545 |  34.225 |
| `tri6`        |     12.575 |    11.705 |   11.755 |  12.150 |
| `quad4ibi`    |     31.215 |    28.790 |   31.180 |  29.555 |
| `quad4newton` |     16.940 |    15.435 |   16.390 |  15.690 |
| `quad8`       |      7.010 |     6.550 |    7.160 |   6.760 |
| `quad9`       |      8.475 |     7.955 |    8.520 |   7.950 |

## Read

- `tri3` and `tri3opt` have the highest geometry throughput in `geom` and `sphere2000`.
- `quad4newton` is the strongest nonlinear family in the latest `v3` rerun.
- `quad9` remains one of the slower and noisier families, so its `MElem/s` should be interpreted with wider uncertainty bounds.
