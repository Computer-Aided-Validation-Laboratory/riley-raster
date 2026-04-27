# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  7.50   | 0.19 |  3.61  | 110.82 |  443.28  |  110.82   |    443.28    |   0.01   | 133.43 | 855.64 |
| tri6_nodal_grey                                         |  15.39  | 0.21 | 11.91  | 33.60 |  134.38  |   33.60   |    134.38    |   0.01   | 65.02 | 741.77 |
| quad4ibi_nodal_grey                                     |  10.47  | 0.31 |  7.54  | 53.11 |  212.43  |   53.11   |    212.43    |   0.00   | 95.50 | 740.97 |
| quad4newton_nodal_grey                                  |  11.31  | 0.26 |  8.55  | 46.80 |  187.20  |   46.80   |    187.20    |   0.00   | 88.45 | 668.66 |
| quad8_nodal_grey                                        |  14.44  | 0.25 | 11.44  | 35.00 |  140.01  |   35.00   |    140.01    |   0.00   | 69.25 | 1005.45 |
| quad9_nodal_grey                                        |  13.91  | 0.29 | 10.91  | 36.67 |  146.68  |   36.67   |    146.68    |   0.00   | 71.92 | 1193.28 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  12.85  | 0.17 |  5.50  | 72.73 |  290.91  |   72.73   |    290.91    |   0.01   | 77.84 | 442.15 |
| tri6_nodal_rgb                                          |  17.01  | 0.18 | 12.23  | 32.70 |  130.80  |   32.70   |    130.80    |   0.01   | 58.80 | 668.00 |
| quad4ibi_nodal_rgb                                      |  13.81  | 0.23 |  9.61  | 41.62 |  166.47  |   41.62   |    166.47    |   0.00   | 72.45 | 538.32 |
| quad4newton_nodal_rgb                                   |  14.05  | 0.20 |  9.98  | 40.11 |  160.42  |   40.11   |    160.42    |   0.00   | 71.16 | 531.16 |
| quad8_nodal_rgb                                         |  16.11  | 0.21 | 12.34  | 32.40 |  129.62  |   32.40   |    129.62    |   0.00   | 62.09 | 899.40 |
| quad9_nodal_rgb                                         |  16.42  | 0.23 | 13.29  | 30.15 |  120.59  |   30.15   |    120.59    |   0.00   | 60.96 | 982.34 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  11.12  | 0.15 |  7.88  | 50.74 |  202.98  |   50.74   |    202.98    |   0.01   | 90.28 | 521.05 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  17.96  | 0.16 | 14.76  | 27.10 |  108.39  |   27.10   |    108.39    |   0.01   | 55.68 | 296.20 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  15.57  | 0.18 | 12.65  | 31.63 |  126.50  |   31.63   |    126.50    |   0.01   | 64.22 | 348.70 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  15.06  | 0.19 | 12.31  | 32.49 |  129.98  |   32.49   |    129.98    |   0.01   | 66.39 | 360.67 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  18.25  | 0.17 | 15.29  | 26.16 |  104.65  |   26.16   |    104.65    |   0.01   | 54.81 | 295.45 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  15.35  | 0.16 | 12.12  | 33.01 |  132.04  |   33.01   |    132.04    |   0.01   | 65.15 | 355.64 |
| tri3_tex8_grey_quintic_bspline_direct                   |  25.43  | 0.19 | 22.33  | 17.92 |  71.66   |   17.92   |    71.66     |   0.01   | 39.32 | 205.85 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  18.72  | 0.18 | 15.84  | 25.25 |  101.01  |   25.25   |    101.01    |   0.01   | 53.42 | 283.77 |
| tri6_tex8_grey_linear_direct                            |  17.27  | 0.19 | 13.46  | 29.71 |  118.84  |   29.71   |    118.84    |   0.01   | 57.92 | 671.58 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  25.46  | 0.22 | 21.34  | 18.75 |  75.01   |   18.75   |    75.01     |   0.01   | 39.30 | 411.48 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  23.46  | 0.22 | 19.04  | 21.01 |  84.04   |   21.01   |    84.04     |   0.01   | 42.62 | 470.09 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  23.63  | 0.22 | 19.78  | 20.23 |  80.94   |   20.23   |    80.94     |   0.01   | 42.33 | 445.33 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  27.13  | 0.21 | 22.37  | 17.88 |  71.52   |   17.88   |    71.52     |   0.01   | 36.86 | 389.63 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  23.69  | 0.24 | 20.89  | 19.15 |  76.61   |   19.15   |    76.61     |   0.01   | 42.23 | 437.20 |
| tri6_tex8_grey_quintic_bspline_direct                   |  33.65  | 0.23 | 30.03  | 13.32 |  53.29   |   13.32   |    53.29     |   0.01   | 29.72 | 308.28 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  25.91  | 0.23 | 22.12  | 18.09 |  72.35   |   18.09   |    72.35     |   0.01   | 38.61 | 415.25 |
| quad4ibi_tex8_grey_linear_direct                        |  12.52  | 0.26 |  9.61  | 41.63 |  166.51  |   41.63   |    166.51    |   0.00   | 79.90 | 596.59 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  20.74  | 0.21 | 17.68  | 22.63 |  90.52   |   22.63   |    90.52     |   0.00   | 48.21 | 337.94 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  20.38  | 0.23 | 17.53  | 22.82 |  91.30   |   22.82   |    91.30     |   0.00   | 49.08 | 343.23 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.93  | 0.25 | 17.90  | 22.34 |  89.37   |   22.34   |    89.37     |   0.00   | 47.79 | 338.24 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  25.14  | 0.28 | 22.03  | 18.16 |  72.63   |   18.16   |    72.63     |   0.00   | 39.78 | 274.42 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  20.58  | 0.22 | 17.39  | 23.00 |  92.01   |   23.00   |    92.01     |   0.00   | 48.60 | 342.52 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  29.68  | 0.23 | 26.66  | 15.00 |  60.02   |   15.00   |    60.02     |   0.00   | 33.69 | 229.37 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  25.48  | 0.28 | 22.47  | 17.80 |  71.21   |   17.80   |    71.21     |   0.00   | 39.25 | 271.65 |
| quad4newton_tex8_grey_linear_direct                     |  14.09  | 0.19 | 10.78  | 37.10 |  148.41  |   37.10   |    148.41    |   0.01   | 70.96 | 527.94 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  21.36  | 0.19 | 18.38  | 21.76 |  87.04   |   21.76   |    87.04     |   0.01   | 46.83 | 327.69 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  18.71  | 0.21 | 16.04  | 24.93 |  99.74   |   24.93   |    99.74     |   0.00   | 53.45 | 376.84 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  19.24  | 0.34 | 16.27  | 24.58 |  98.33   |   24.58   |    98.33     |   0.00   | 51.97 | 365.30 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  22.08  | 0.22 | 19.38  | 20.64 |  82.55   |   20.64   |    82.55     |   0.00   | 45.28 | 314.90 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  20.09  | 0.25 | 16.23  | 24.64 |  98.58   |   24.64   |    98.58     |   0.00   | 49.89 | 369.12 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  29.58  | 0.19 | 26.45  | 15.12 |  60.50   |   15.12   |    60.50     |   0.01   | 33.81 | 231.38 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  21.83  | 0.25 | 19.08  | 20.97 |  83.87   |   20.97   |    83.87     |   0.00   | 45.80 | 319.63 |
| quad8_tex8_grey_linear_direct                           |  16.51  | 0.26 | 13.59  | 29.44 |  117.78  |   29.44   |    117.78    |   0.00   | 60.58 | 874.79 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  26.60  | 0.24 | 22.55  | 17.75 |  71.00   |   17.75   |    71.00     |   0.00   | 37.61 | 515.08 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  22.43  | 0.20 | 19.08  | 20.96 |  83.84   |   20.96   |    83.84     |   0.01   | 44.60 | 619.50 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  22.58  | 0.29 | 19.58  | 20.43 |  81.70   |   20.43   |    81.70     |   0.00   | 44.30 | 617.25 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  25.22  | 0.36 | 21.63  | 18.50 |  73.99   |   18.50   |    73.99     |   0.00   | 39.68 | 545.11 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  21.08  | 0.28 | 18.24  | 21.94 |  87.74   |   21.94   |    87.74     |   0.00   | 47.45 | 663.83 |
| quad8_tex8_grey_quintic_bspline_direct                  |  32.80  | 0.33 | 29.64  | 13.50 |  53.98   |   13.50   |    53.98     |   0.00   | 30.49 | 411.87 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  24.08  | 0.28 | 21.52  | 18.59 |  74.36   |   18.59   |    74.36     |   0.00   | 41.52 | 573.82 |
| quad9_tex8_grey_linear_direct                           |  16.34  | 0.25 | 13.54  | 29.53 |  118.13  |   29.53   |    118.13    |   0.00   | 61.21 | 986.32 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  26.28  | 0.23 | 23.21  | 17.23 |  68.94   |   17.23   |    68.94     |   0.00   | 38.06 | 586.37 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  21.39  | 0.29 | 18.37  | 21.77 |  87.08   |   21.77   |    87.08     |   0.00   | 46.74 | 732.11 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  23.33  | 0.26 | 19.96  | 20.04 |  80.15   |   20.04   |    80.15     |   0.00   | 42.88 | 677.99 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  24.92  | 0.28 | 22.01  | 18.17 |  72.69   |   18.17   |    72.69     |   0.00   | 40.12 | 624.10 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  21.44  | 0.24 | 18.65  | 21.45 |  85.81   |   21.45   |    85.81     |   0.00   | 46.65 | 734.94 |
| quad9_tex8_grey_quintic_bspline_direct                  |  31.79  | 0.31 | 28.76  | 13.91 |  55.64   |   13.91   |    55.64     |   0.00   | 31.46 | 479.44 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  24.74  | 0.30 | 21.54  | 18.57 |  74.29   |   18.57   |    74.29     |   0.00   | 40.43 | 632.34 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  15.18  | 0.17 | 10.01  | 40.00 |  160.00  |   40.00   |    160.00    |   0.01   | 65.88 | 371.44 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  22.56  | 0.20 | 18.40  | 21.74 |  86.98   |   21.74   |    86.98     |   0.01   | 44.32 | 233.73 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  20.96  | 0.15 | 17.24  | 23.21 |  92.82   |   23.21   |    92.82     |   0.01   | 47.71 | 251.70 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.31  | 0.18 | 16.77  | 23.85 |  95.41   |   23.85   |    95.41     |   0.01   | 49.24 | 258.58 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  26.03  | 0.17 | 21.79  | 18.36 |  73.43   |   18.36   |    73.43     |   0.01   | 38.42 | 198.98 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  21.09  | 0.18 | 16.79  | 23.82 |  95.27   |   23.82   |    95.27     |   0.01   | 47.42 | 250.17 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  34.00  | 0.15 | 29.98  | 13.34 |  53.36   |   13.34   |    53.36     |   0.01   | 29.41 | 148.79 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  27.24  | 0.16 | 23.11  | 17.31 |  69.23   |   17.31   |    69.23     |   0.01   | 36.71 | 188.39 |
| tri6_tex8_rgb_linear_direct                             |  25.52  | 0.25 | 19.45  | 20.57 |  82.27   |   20.57   |    82.27     |   0.01   | 39.19 | 405.69 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  31.19  | 0.24 | 26.62  | 15.03 |  60.12   |   15.03   |    60.12     |   0.01   | 32.06 | 328.11 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  29.58  | 0.24 | 24.05  | 16.64 |  66.54   |   16.64   |    66.54     |   0.01   | 33.85 | 367.17 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  29.03  | 0.23 | 23.91  | 16.74 |  66.94   |   16.74   |    66.94     |   0.01   | 34.48 | 354.89 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  33.70  | 0.18 | 29.03  | 13.78 |  55.12   |   13.78   |    55.12     |   0.01   | 29.68 | 301.91 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  27.25  | 0.17 | 23.05  | 17.35 |  69.41   |   17.35   |    69.41     |   0.01   | 36.71 | 378.50 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  40.42  | 0.20 | 36.40  | 10.99 |  43.97   |   10.99   |    43.97     |   0.01   | 24.74 | 248.31 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  31.90  | 0.20 | 28.27  | 14.15 |  56.59   |   14.15   |    56.59     |   0.01   | 31.35 | 318.19 |
| quad4ibi_tex8_rgb_linear_direct                         |  16.23  | 0.26 | 11.89  | 33.65 |  134.60  |   33.65   |    134.60    |   0.00   | 61.61 | 443.99 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  26.74  | 0.17 | 21.91  | 18.28 |  73.13   |   18.28   |    73.13     |   0.01   | 37.40 | 256.01 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  26.58  | 0.25 | 22.78  | 17.56 |  70.25   |   17.56   |    70.25     |   0.00   | 37.62 | 260.48 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  26.20  | 0.19 | 22.46  | 17.81 |  71.24   |   17.81   |    71.24     |   0.01   | 38.17 | 262.05 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  32.17  | 0.24 | 28.23  | 14.17 |  56.69   |   14.17   |    56.69     |   0.00   | 31.08 | 211.29 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  26.13  | 0.20 | 22.38  | 17.87 |  71.48   |   17.87   |    71.48     |   0.00   | 38.27 | 263.40 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  40.13  | 0.19 | 36.16  | 11.06 |  44.25   |   11.06   |    44.25     |   0.01   | 24.92 | 166.60 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  32.96  | 0.20 | 28.89  | 13.85 |  55.39   |   13.85   |    55.39     |   0.01   | 30.35 | 209.05 |
| quad4newton_tex8_rgb_linear_direct                      |  19.90  | 0.18 | 16.16  | 24.75 |  99.00   |   24.75   |    99.00     |   0.01   | 50.25 | 352.32 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  28.27  | 0.19 | 23.12  | 17.30 |  69.20   |   17.30   |    69.20     |   0.01   | 35.38 | 241.15 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  24.65  | 0.18 | 20.71  | 19.31 |  77.26   |   19.31   |    77.26     |   0.01   | 40.57 | 281.36 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  24.64  | 0.17 | 21.16  | 18.90 |  75.61   |   18.90   |    75.61     |   0.01   | 40.58 | 279.62 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  29.54  | 0.20 | 26.28  | 15.22 |  60.88   |   15.22   |    60.88     |   0.01   | 33.85 | 229.98 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  25.62  | 0.19 | 21.12  | 18.94 |  75.76   |   18.94   |    75.76     |   0.01   | 39.03 | 270.58 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  36.62  | 0.16 | 33.16  | 12.06 |  48.26   |   12.06   |    48.26     |   0.01   | 27.31 | 183.54 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  29.98  | 0.16 | 25.97  | 15.40 |  61.60   |   15.40   |    61.60     |   0.01   | 33.36 | 228.21 |
| quad8_tex8_rgb_linear_direct                            |  22.80  | 0.20 | 18.92  | 21.15 |  84.59   |   21.15   |    84.59     |   0.00   | 43.87 | 610.42 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  29.12  | 0.21 | 25.07  | 15.96 |  63.83   |   15.96   |    63.83     |   0.00   | 34.35 | 470.33 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  27.78  | 0.24 | 24.25  | 16.49 |  65.98   |   16.49   |    65.98     |   0.00   | 36.00 | 494.82 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  27.83  | 0.25 | 23.57  | 16.97 |  67.89   |   16.97   |    67.89     |   0.00   | 35.95 | 490.45 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  31.26  | 0.17 | 27.96  | 14.31 |  57.23   |   14.31   |    57.23     |   0.01   | 32.00 | 433.25 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  27.02  | 0.26 | 23.30  | 17.17 |  68.67   |   17.17   |    68.67     |   0.00   | 37.01 | 508.86 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  39.80  | 0.21 | 35.49  | 11.27 |  45.08   |   11.27   |    45.08     |   0.00   | 25.12 | 336.46 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  32.47  | 0.21 | 27.95  | 14.31 |  57.24   |   14.31   |    57.24     |   0.00   | 30.80 | 417.91 |
| quad9_tex8_rgb_linear_direct                            |  22.09  | 0.22 | 18.61  | 21.50 |  85.98   |   21.50   |    85.98     |   0.00   | 45.29 | 707.70 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  30.15  | 0.22 | 25.77  | 15.52 |  62.10   |   15.52   |    62.10     |   0.00   | 33.17 | 510.60 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  26.91  | 0.25 | 23.25  | 17.20 |  68.82   |   17.20   |    68.82     |   0.00   | 37.16 | 574.80 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  27.38  | 0.19 | 23.36  | 17.12 |  68.49   |   17.12   |    68.49     |   0.01   | 36.52 | 563.74 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  33.66  | 0.25 | 29.63  | 13.50 |  54.00   |   13.50   |    54.00     |   0.00   | 29.71 | 453.71 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  27.38  | 0.23 | 23.80  | 16.82 |  67.28   |   16.82   |    67.28     |   0.00   | 36.56 | 563.21 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  39.81  | 0.25 | 35.56  | 11.25 |  44.99   |   11.25   |    44.99     |   0.00   | 25.12 | 378.25 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  32.18  | 0.22 | 28.58  | 13.99 |  55.98   |   13.99   |    55.98     |   0.00   | 31.08 | 474.35 |

