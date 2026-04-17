# V3 Cycles/Pixel Stats

Estimated `cycles/pixel` from the latest archived `v3` 10-run rerun.

Source archive:

- `perf/v3_variability_rerun/fullraster/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/geom/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/sphere2000/bench0.md` to `bench9.md`

Assumption:

- sustained CPU clock under load is approximately `4.8 GHz`

Formula:

- `cycles/pixel = 4800 / MPx/s`

Each value below is estimated `cycles/pixel`, computed from the median `MPx/s`
for that case across the 10 runs using that `4.8 GHz` assumption.

## Fullraster

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|---------------|-----------:|----------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`        |      51.51 |    107.70 |       216.07 |         485.09 |             426.86 |            805.37 |                567.71 |
| `tri3opt`     |      51.96 |    106.76 |       216.26 |         485.34 |             425.34 |            806.72 |                567.38 |
| `tri6`        |     320.43 |    374.41 |       425.34 |         719.10 |             691.64 |           1126.76 |                898.88 |
| `quad4ibi`    |     228.90 |    334.84 |       374.27 |         725.08 |             747.66 |           1045.75 |                867.99 |
| `quad4newton` |     239.34 |    291.79 |       342.61 |         633.66 |             606.44 |           1043.48 |                808.08 |
| `quad8`       |     315.89 |    373.40 |       423.28 |         716.42 |             689.66 |           1124.12 |                898.04 |
| `quad9`       |     350.75 |    408.51 |       462.43 |         756.50 |             727.82 |           1162.23 |                933.85 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|---------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`        |      323.67 |        697.17 |            616.17 |         1064.30 |              814.94 |
| `tri3opt`     |      323.78 |        698.69 |            614.99 |         1064.30 |              815.63 |
| `tri6`        |      525.16 |        878.32 |            864.86 |         1467.89 |             1167.88 |
| `quad4ibi`    |      466.25 |        854.09 |            888.89 |         1504.70 |             1200.00 |
| `quad4newton` |      445.27 |        804.02 |            783.03 |         1387.28 |             1085.97 |
| `quad8`       |      522.31 |        880.73 |            863.31 |         1467.89 |             1160.82 |
| `quad9`       |      561.08 |        931.13 |            903.10 |         1504.70 |             1209.07 |

## Geom

### Nodal + Grey Texture

| Element       | nodal_grey | nodal_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|---------------|-----------:|----------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`        |     174.13 |    238.51 |       445.27 |         743.61 |             657.08 |           1052.63 |                804.69 |
| `tri3opt`     |     171.34 |    240.36 |       444.86 |         745.34 |             658.89 |           1053.79 |                806.72 |
| `tri6`        |    1121.50 |   1197.01 |      1254.90 |        1566.07 |            1558.44 |           1975.31 |               1758.24 |
| `quad4ibi`    |     348.46 |    462.65 |       489.05 |         845.07 |             869.57 |           1183.72 |               1004.18 |
| `quad4newton` |     577.97 |    639.15 |       609.14 |         914.29 |             896.36 |           1337.05 |               1100.92 |
| `quad8`       |     892.19 |    961.92 |      1024.55 |        1318.68 |            1300.81 |           1745.45 |               1511.81 |
| `quad9`       |     907.37 |    979.59 |      1046.89 |        1354.02 |            1346.42 |           1771.22 |               1573.77 |

### RGB Texture

| Element       | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|---------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`        |      572.45 |        971.66 |            893.02 |         1355.93 |             1103.45 |
| `tri3opt`     |      573.48 |        974.62 |            892.19 |         1355.93 |             1105.99 |
| `tri6`        |     1385.28 |       1751.82 |           1758.24 |         2352.94 |             2060.09 |
| `quad4ibi`    |      583.59 |        975.61 |           1023.45 |         1638.23 |             1329.64 |
| `quad4newton` |      722.35 |       1099.66 |           1097.14 |         1702.13 |             1397.38 |
| `quad8`       |     1122.81 |       1500.00 |           1533.55 |         2100.66 |             1791.04 |
| `quad9`       |     1188.12 |       1576.35 |           1592.04 |         2171.95 |             1882.35 |

## Sphere2000

| Element       | nodal_grey | nodal_rgb | tex_grey | tex_rgb |
|---------------|-----------:|----------:|---------:|--------:|
| `tri3`        |      72.03 |    118.45 |   189.42 |  268.16 |
| `tri3opt`     |      71.55 |    116.26 |   189.42 |  273.58 |
| `tri6`        |     573.48 |    622.57 |   676.06 |  757.10 |
| `quad4ibi`    |     304.47 |    390.40 |   395.22 |  461.98 |
| `quad4newton` |     234.55 |    279.39 |   282.44 |  354.37 |
| `quad8`       |     381.56 |    427.62 |   446.72 |  515.85 |
| `quad9`       |     407.99 |    454.12 |   475.48 |  542.37 |

## Read

- This is an estimated view, not a hardware-counter measurement.
- If sustained clock is lower or higher than `4.8 GHz`, these values scale linearly.
- Lower `cycles/pixel` is better.
