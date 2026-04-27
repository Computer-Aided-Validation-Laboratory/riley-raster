# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  6.42   | 0.22 |  2.79  | 143.59 |  574.34  |  143.59   |    574.34    |   0.01   | 155.80 | 1060.05 |
| tri6_nodal_grey                                         |  11.12  | 0.25 |  7.83  | 51.11 |  204.42  |   51.11   |    204.42    |   0.01   | 89.94 | 1020.27 |
| quad4ibi_nodal_grey                                     |  8.03   | 0.29 |  5.25  | 76.56 |  306.22  |   76.56   |    306.22    |   0.00   | 124.62 | 1022.01 |
| quad4newton_nodal_grey                                  |  8.70   | 0.23 |  6.05  | 66.17 |  264.68  |   66.17   |    264.68    |   0.00   | 114.91 | 914.08 |
| quad8_nodal_grey                                        |  10.35  | 0.28 |  7.34  | 54.51 |  218.04  |   54.51   |    218.04    |   0.00   | 96.58 | 1529.17 |
| quad9_nodal_grey                                        |  10.78  | 0.24 |  7.77  | 51.48 |  205.90  |   51.48   |    205.90    |   0.00   | 92.78 | 1585.94 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  10.39  | 0.19 |  3.75  | 106.70 |  426.81  |  106.70   |    426.81    |   0.01   | 96.34 | 554.31 |
| tri6_nodal_rgb                                          |  12.44  | 0.18 |  8.17  | 48.94 |  195.77  |   48.94   |    195.77    |   0.01   | 80.47 | 903.28 |
| quad4ibi_nodal_rgb                                      |  10.61  | 0.21 |  6.48  | 61.75 |  247.01  |   61.75   |    247.01    |   0.00   | 94.29 | 727.06 |
| quad4newton_nodal_rgb                                   |  10.47  | 0.22 |  6.92  | 57.79 |  231.17  |   57.79   |    231.17    |   0.00   | 95.51 | 754.03 |
| quad8_nodal_rgb                                         |  12.71  | 0.20 |  8.76  | 45.65 |  182.60  |   45.65   |    182.60    |   0.00   | 78.74 | 1165.00 |
| quad9_nodal_rgb                                         |  12.64  | 0.18 |  8.97  | 44.58 |  178.31  |   44.58   |    178.31    |   0.01   | 79.13 | 1328.00 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  8.46   | 0.20 |  5.47  | 73.22 |  292.90  |   73.22   |    292.90    |   0.01   | 118.27 | 734.86 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  11.35  | 0.20 |  8.17  | 49.08 |  196.32  |   49.08   |    196.32    |   0.01   | 88.09 | 496.51 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  10.58  | 0.19 |  7.63  | 52.42 |  209.70  |   52.42   |    209.70    |   0.01   | 94.56 | 541.57 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  10.45  | 0.18 |  7.69  | 52.03 |  208.11  |   52.03   |    208.11    |   0.01   | 95.67 | 548.55 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  13.75  | 0.19 | 10.74  | 37.24 |  148.98  |   37.24   |    148.98    |   0.01   | 72.76 | 414.29 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  10.02  | 0.21 |  7.23  | 55.34 |  221.35  |   55.34   |    221.35    |   0.01   | 99.84 | 576.12 |
| tri3_tex8_grey_quintic_bspline_direct                   |  17.24  | 0.17 | 14.96  | 26.74 |  106.98  |   26.74   |    106.98    |   0.01   | 58.04 | 309.88 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  13.23  | 0.22 | 10.09  | 39.64 |  158.57  |   39.64   |    158.57    |   0.01   | 75.62 | 422.16 |
| tri6_tex8_grey_linear_direct                            |  12.26  | 0.25 |  9.43  | 42.45 |  169.81  |   42.45   |    169.81    |   0.01   | 81.58 | 910.68 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  15.74  | 0.21 | 13.03  | 30.69 |  122.76  |   30.69   |    122.76    |   0.01   | 63.54 | 684.81 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  15.18  | 0.22 | 12.27  | 32.59 |  130.35  |   32.59   |    130.35    |   0.01   | 65.87 | 714.49 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  14.42  | 0.20 | 11.17  | 35.91 |  143.63  |   35.91   |    143.63    |   0.01   | 69.36 | 762.51 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  17.89  | 0.26 | 13.63  | 29.39 |  117.54  |   29.39   |    117.54    |   0.01   | 55.96 | 600.65 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  13.92  | 0.25 | 10.61  | 37.71 |  150.84  |   37.71   |    150.84    |   0.01   | 71.88 | 799.19 |
| tri6_tex8_grey_quintic_bspline_direct                   |  23.02  | 0.20 | 19.91  | 20.09 |  80.35   |   20.09   |    80.35     |   0.01   | 43.44 | 451.30 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  18.01  | 0.22 | 15.38  | 26.02 |  104.06  |   26.02   |    104.06    |   0.01   | 55.54 | 593.39 |
| quad4ibi_tex8_grey_linear_direct                        |  9.38   | 0.24 |  6.75  | 59.28 |  237.13  |   59.28   |    237.13    |   0.00   | 106.66 | 837.60 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  14.77  | 0.26 | 11.83  | 33.85 |  135.42  |   33.85   |    135.42    |   0.00   | 67.70 | 491.48 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  14.54  | 0.26 | 11.71  | 34.17 |  136.67  |   34.17   |    136.67    |   0.00   | 68.76 | 500.36 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  14.81  | 0.29 | 12.01  | 33.29 |  133.18  |   33.29   |    133.18    |   0.00   | 67.51 | 488.69 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  16.81  | 0.40 | 13.65  | 29.31 |  117.23  |   29.31   |    117.23    |   0.00   | 59.53 | 428.94 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  15.32  | 0.28 | 11.65  | 34.35 |  137.38  |   34.35   |    137.38    |   0.00   | 65.29 | 475.42 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  19.47  | 0.19 | 17.19  | 23.29 |  93.16   |   23.29   |    93.16     |   0.01   | 51.40 | 361.69 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  17.56  | 0.23 | 14.67  | 27.28 |  109.11  |   27.28   |    109.11    |   0.00   | 56.94 | 404.02 |
| quad4newton_tex8_grey_linear_direct                     |  10.07  | 0.23 |  7.21  | 55.45 |  221.79  |   55.45   |    221.79    |   0.00   | 99.29 | 783.30 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  15.16  | 0.24 | 12.20  | 32.79 |  131.16  |   32.79   |    131.16    |   0.00   | 65.98 | 480.39 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  12.26  | 0.27 |  9.76  | 41.00 |  163.99  |   41.00   |    163.99    |   0.00   | 81.55 | 607.09 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  12.74  | 0.26 | 10.13  | 39.49 |  157.96  |   39.49   |    157.96    |   0.00   | 78.50 | 581.97 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  15.07  | 0.22 | 11.48  | 35.00 |  140.00  |   35.00   |    140.00    |   0.00   | 66.39 | 480.61 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  13.48  | 0.24 | 10.51  | 38.04 |  152.17  |   38.04   |    152.17    |   0.00   | 74.20 | 550.36 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  20.96  | 0.22 | 17.84  | 22.42 |  89.68   |   22.42   |    89.68     |   0.00   | 47.71 | 336.51 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  16.69  | 0.24 | 13.62  | 29.38 |  117.50  |   29.38   |    117.50    |   0.00   | 59.91 | 429.19 |
| quad8_tex8_grey_linear_direct                           |  13.11  | 0.29 |  9.82  | 40.72 |  162.86  |   40.72   |    162.86    |   0.00   | 76.27 | 1154.63 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  16.78  | 0.28 | 13.80  | 28.99 |  115.97  |   28.99   |    115.97    |   0.00   | 59.61 | 850.77 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  15.07  | 0.24 | 12.07  | 33.14 |  132.57  |   33.14   |    132.57    |   0.00   | 66.37 | 973.50 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  14.39  | 0.32 | 11.62  | 34.44 |  137.76  |   34.44   |    137.76    |   0.00   | 69.47 | 1011.81 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  17.69  | 0.30 | 14.88  | 26.88 |  107.53  |   26.88   |    107.53    |   0.00   | 56.53 | 807.82 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  15.25  | 0.25 | 12.08  | 33.12 |  132.47  |   33.12   |    132.47    |   0.00   | 65.60 | 946.95 |
| quad8_tex8_grey_quintic_bspline_direct                  |  19.51  | 0.25 | 16.72  | 23.98 |  95.91   |   23.98   |    95.91     |   0.00   | 51.34 | 725.36 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  16.58  | 0.22 | 13.88  | 28.82 |  115.29  |   28.82   |    115.29    |   0.00   | 60.32 | 860.40 |
| quad9_tex8_grey_linear_direct                           |  13.06  | 0.23 |  9.75  | 41.02 |  164.07  |   41.02   |    164.07    |   0.00   | 76.57 | 1284.67 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  17.98  | 0.24 | 14.43  | 27.72 |  110.87  |   27.72   |    110.87    |   0.00   | 55.63 | 931.59 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  15.65  | 0.24 | 12.41  | 32.23 |  128.93  |   32.23   |    128.93    |   0.00   | 63.93 | 1082.94 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  15.82  | 0.30 | 12.70  | 31.50 |  125.99  |   31.50   |    125.99    |   0.00   | 63.20 | 1033.72 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  19.53  | 0.29 | 15.59  | 25.65 |  102.61  |   25.65   |    102.61    |   0.00   | 51.21 | 851.79 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  15.79  | 0.31 | 12.06  | 33.16 |  132.66  |   33.16   |    132.66    |   0.00   | 63.32 | 1068.24 |
| quad9_tex8_grey_quintic_bspline_direct                  |  24.28  | 0.25 | 21.22  | 18.85 |  75.41   |   18.85   |    75.41     |   0.00   | 41.19 | 642.36 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  18.15  | 0.26 | 14.51  | 27.58 |  110.31  |   27.58   |    110.31    |   0.00   | 55.09 | 913.16 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  11.19  | 0.17 |  7.29  | 54.89 |  219.57  |   54.89   |    219.57    |   0.01   | 89.41 | 511.04 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  17.94  | 0.14 | 13.86  | 28.87 |  115.48  |   28.87   |    115.48    |   0.01   | 55.75 | 301.84 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  15.92  | 0.16 | 11.84  | 33.82 |  135.27  |   33.82   |    135.27    |   0.01   | 62.82 | 343.97 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  15.50  | 0.17 | 11.88  | 33.68 |  134.72  |   33.68   |    134.72    |   0.01   | 64.52 | 350.89 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  19.19  | 0.16 | 15.05  | 26.58 |  106.34  |   26.58   |    106.34    |   0.01   | 52.27 | 280.59 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  15.48  | 0.19 | 11.61  | 34.48 |  137.93  |   34.48   |    137.93    |   0.01   | 64.61 | 349.42 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  22.39  | 0.16 | 19.08  | 20.97 |  83.86   |   20.97   |    83.86     |   0.01   | 44.67 | 232.42 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  18.35  | 0.16 | 12.87  | 31.63 |  126.52  |   31.63   |    126.52    |   0.01   | 54.58 | 310.42 |
| tri6_tex8_rgb_linear_direct                             |  16.71  | 0.19 | 11.95  | 33.46 |  133.86  |   33.46   |    133.86    |   0.01   | 59.98 | 642.12 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  21.09  | 0.18 | 17.32  | 23.10 |  92.41   |   23.10   |    92.41     |   0.01   | 47.42 | 496.25 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  20.96  | 0.20 | 16.22  | 24.71 |  98.84   |   24.71   |    98.84     |   0.01   | 47.72 | 501.60 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.22  | 0.17 | 16.56  | 24.15 |  96.60   |   24.15   |    96.60     |   0.01   | 49.45 | 522.48 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  25.08  | 0.19 | 20.36  | 19.65 |  78.60   |   19.65   |    78.60     |   0.01   | 39.87 | 411.61 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  20.45  | 0.18 | 16.33  | 24.49 |  97.97   |   24.49   |    97.97     |   0.01   | 48.92 | 517.16 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  27.79  | 0.16 | 24.27  | 16.49 |  65.96   |   16.49   |    65.96     |   0.01   | 35.99 | 372.00 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  23.11  | 0.18 | 19.48  | 20.54 |  82.16   |   20.54   |    82.16     |   0.01   | 43.28 | 448.67 |
| quad4ibi_tex8_rgb_linear_direct                         |  12.44  | 0.23 |  8.24  | 48.58 |  194.32  |   48.58   |    194.32    |   0.00   | 80.39 | 605.70 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  18.21  | 0.20 | 14.01  | 28.55 |  114.19  |   28.55   |    114.19    |   0.01   | 54.92 | 388.28 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  18.00  | 0.25 | 14.32  | 27.94 |  111.76  |   27.94   |    111.76    |   0.00   | 55.55 | 393.77 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  17.64  | 0.20 | 13.95  | 28.67 |  114.69  |   28.67   |    114.69    |   0.00   | 56.69 | 405.53 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  23.16  | 0.24 | 19.20  | 20.87 |  83.49   |   20.87   |    83.49     |   0.00   | 43.30 | 300.42 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  18.22  | 0.20 | 14.60  | 27.40 |  109.58  |   27.40   |    109.58    |   0.00   | 54.89 | 387.95 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  26.41  | 0.21 | 23.11  | 17.31 |  69.25   |   17.31   |    69.25     |   0.00   | 37.87 | 260.62 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  23.50  | 0.21 | 18.95  | 21.12 |  84.46   |   21.12   |    84.46     |   0.00   | 42.56 | 293.90 |
| quad4newton_tex8_rgb_linear_direct                      |  12.49  | 0.20 |  8.52  | 46.97 |  187.88  |   46.97   |    187.88    |   0.01   | 80.11 | 594.73 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  18.27  | 0.17 | 14.87  | 26.90 |  107.59  |   26.90   |    107.59    |   0.01   | 54.75 | 386.25 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  17.45  | 0.22 | 13.94  | 28.70 |  114.81  |   28.70   |    114.81    |   0.00   | 57.31 | 407.24 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  16.50  | 0.19 | 12.74  | 31.44 |  125.75  |   31.44   |    125.75    |   0.01   | 60.64 | 433.25 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  21.61  | 0.20 | 16.90  | 23.67 |  94.66   |   23.67   |    94.66     |   0.00   | 46.29 | 321.95 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  18.66  | 0.22 | 14.37  | 27.85 |  111.42  |   27.85   |    111.42    |   0.00   | 53.66 | 379.43 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  26.04  | 0.23 | 22.48  | 17.80 |  71.18   |   17.80   |    71.18     |   0.00   | 38.40 | 263.24 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  22.17  | 0.21 | 18.00  | 22.22 |  88.87   |   22.22   |    88.87     |   0.00   | 45.12 | 314.18 |
| quad8_tex8_rgb_linear_direct                            |  15.78  | 0.25 | 11.83  | 33.80 |  135.22  |   33.80   |    135.22    |   0.00   | 63.39 | 910.65 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  21.03  | 0.22 | 16.59  | 24.11 |  96.43   |   24.11   |    96.43     |   0.00   | 47.64 | 665.96 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  19.97  | 0.20 | 15.55  | 25.74 |  102.97  |   25.74   |    102.97    |   0.00   | 50.08 | 707.45 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  20.64  | 0.22 | 16.17  | 24.74 |  98.94   |   24.74   |    98.94     |   0.00   | 48.46 | 683.06 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  22.41  | 0.19 | 18.31  | 21.86 |  87.43   |   21.86   |    87.43     |   0.01   | 44.63 | 618.63 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  20.04  | 0.20 | 14.74  | 27.25 |  109.01  |   27.25   |    109.01    |   0.00   | 49.91 | 706.12 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  27.92  | 0.22 | 23.70  | 16.88 |  67.51   |   16.88   |    67.51     |   0.00   | 35.82 | 491.69 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  22.02  | 0.21 | 18.30  | 21.90 |  87.61   |   21.90   |    87.61     |   0.00   | 45.48 | 631.07 |
| quad9_tex8_rgb_linear_direct                            |  18.42  | 0.25 | 12.89  | 31.02 |  124.09  |   31.02   |    124.09    |   0.00   | 54.28 | 929.34 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  22.07  | 0.27 | 17.72  | 22.58 |  90.30   |   22.58   |    90.30     |   0.00   | 45.34 | 735.32 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  20.98  | 0.20 | 17.26  | 23.18 |  92.73   |   23.18   |    92.73     |   0.01   | 47.66 | 752.98 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  21.71  | 0.21 | 16.80  | 23.82 |  95.29   |   23.82   |    95.29     |   0.00   | 46.07 | 755.61 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  23.59  | 0.18 | 19.09  | 20.97 |  83.87   |   20.97   |    83.87     |   0.01   | 42.41 | 670.28 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  19.71  | 0.24 | 15.44  | 25.93 |  103.74  |   25.93   |    103.74    |   0.00   | 50.77 | 823.36 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  29.74  | 0.22 | 24.46  | 16.35 |  65.41   |   16.35   |    65.41     |   0.00   | 33.63 | 537.23 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  24.64  | 0.25 | 20.16  | 19.85 |  79.40   |   19.85   |    79.40     |   0.00   | 40.58 | 650.47 |

