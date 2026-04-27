# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  6.70   | 0.23 |  2.79  | 143.59 |  574.38  |  143.59   |    574.38    |   0.01   | 149.30 | 992.43 |
| tri6_nodal_grey                                         |  10.20  | 0.22 |  7.26  | 55.07 |  220.29  |   55.07   |    220.29    |   0.01   | 98.01 | 1161.58 |
| quad4ibi_nodal_grey                                     |  8.31   | 0.26 |  5.31  | 75.26 |  301.04  |   75.26   |    301.04    |   0.00   | 120.36 | 981.33 |
| quad4newton_nodal_grey                                  |  8.74   | 0.23 |  5.77  | 69.27 |  277.08  |   69.27   |    277.08    |   0.00   | 114.48 | 967.90 |
| quad8_nodal_grey                                        |  10.42  | 0.24 |  7.37  | 54.29 |  217.15  |   54.29   |    217.15    |   0.00   | 95.98 | 1472.65 |
| quad9_nodal_grey                                        |  10.78  | 0.29 |  7.68  | 52.05 |  208.21  |   52.05   |    208.21    |   0.00   | 92.82 | 1657.37 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  10.35  | 0.21 |  3.95  | 101.32 |  405.29  |  101.32   |    405.29    |   0.01   | 96.72 | 560.21 |
| tri6_nodal_rgb                                          |  11.98  | 0.18 |  8.74  | 45.80 |  183.20  |   45.80   |    183.20    |   0.01   | 83.44 | 949.64 |
| quad4ibi_nodal_rgb                                      |  11.23  | 0.24 |  6.86  | 58.41 |  233.64  |   58.41   |    233.64    |   0.00   | 89.04 | 683.32 |
| quad4newton_nodal_rgb                                   |  10.66  | 0.22 |  6.38  | 62.72 |  250.88  |   62.72   |    250.88    |   0.00   | 93.80 | 714.84 |
| quad8_nodal_rgb                                         |  13.37  | 0.22 |  8.09  | 49.47 |  197.90  |   49.47   |    197.90    |   0.00   | 74.82 | 1118.72 |
| quad9_nodal_rgb                                         |  12.20  | 0.23 |  8.26  | 48.44 |  193.77  |   48.44   |    193.77    |   0.00   | 81.95 | 1372.91 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  8.56   | 0.22 |  5.66  | 70.63 |  282.51  |   70.63   |    282.51    |   0.01   | 116.87 | 720.46 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  12.89  | 0.17 |  9.98  | 40.07 |  160.28  |   40.07   |    160.28    |   0.01   | 77.59 | 432.37 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  10.01  | 0.20 |  7.20  | 55.68 |  222.73  |   55.68   |    222.73    |   0.01   | 99.88 | 586.83 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  10.36  | 0.16 |  7.35  | 54.42 |  217.69  |   54.42   |    217.69    |   0.01   | 96.88 | 570.20 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  11.70  | 0.18 |  8.46  | 47.34 |  189.35  |   47.34   |    189.35    |   0.01   | 85.52 | 496.75 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  11.44  | 0.22 |  8.42  | 47.55 |  190.19  |   47.55   |    190.19    |   0.01   | 87.50 | 498.08 |
| tri3_tex8_grey_quintic_bspline_direct                   |  19.81  | 0.21 | 16.19  | 24.71 |  98.82   |   24.71   |    98.82     |   0.01   | 50.50 | 280.08 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  13.29  | 0.19 | 10.33  | 38.73 |  154.94  |   38.73   |    154.94    |   0.01   | 75.28 | 417.65 |
| tri6_tex8_grey_linear_direct                            |  12.88  | 0.23 |  9.54  | 41.95 |  167.80  |   41.95   |    167.80    |   0.01   | 77.64 | 861.47 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  16.95  | 0.22 | 13.97  | 28.64 |  114.55  |   28.64   |    114.55    |   0.01   | 58.98 | 638.54 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  16.06  | 0.24 | 12.59  | 31.78 |  127.13  |   31.78   |    127.13    |   0.01   | 62.29 | 677.81 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  15.50  | 0.26 | 11.21  | 35.93 |  143.71  |   35.93   |    143.71    |   0.01   | 64.51 | 697.25 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  17.23  | 0.24 | 14.28  | 28.01 |  112.03  |   28.01   |    112.03    |   0.01   | 58.03 | 625.55 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  15.25  | 0.22 | 12.03  | 33.25 |  133.02  |   33.25   |    133.02    |   0.01   | 65.56 | 715.15 |
| tri6_tex8_grey_quintic_bspline_direct                   |  22.43  | 0.19 | 19.77  | 20.23 |  80.93   |   20.23   |    80.93     |   0.01   | 44.59 | 463.61 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  17.38  | 0.25 | 13.94  | 28.72 |  114.86  |   28.72   |    114.86    |   0.01   | 57.56 | 613.92 |
| quad4ibi_tex8_grey_linear_direct                        |  9.47   | 0.27 |  6.42  | 62.27 |  249.07  |   62.27   |    249.07    |   0.00   | 105.54 | 836.34 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  14.66  | 0.29 | 11.97  | 33.41 |  133.65  |   33.41   |    133.65    |   0.00   | 68.23 | 494.90 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  14.11  | 0.23 | 10.58  | 37.80 |  151.20  |   37.80   |    151.20    |   0.00   | 71.00 | 519.30 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  14.66  | 0.25 | 11.65  | 34.36 |  137.43  |   34.36   |    137.43    |   0.00   | 68.20 | 495.05 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  17.41  | 0.29 | 13.98  | 28.64 |  114.55  |   28.64   |    114.55    |   0.00   | 57.45 | 409.67 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  14.45  | 0.26 | 11.55  | 34.62 |  138.49  |   34.62   |    138.49    |   0.00   | 69.20 | 503.46 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  21.76  | 0.29 | 18.78  | 21.31 |  85.24   |   21.31   |    85.24     |   0.00   | 45.95 | 320.42 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  15.00  | 0.22 | 12.38  | 32.31 |  129.23  |   32.31   |    129.23    |   0.00   | 66.70 | 483.27 |
| quad4newton_tex8_grey_linear_direct                     |  10.51  | 0.19 |  7.75  | 51.60 |  206.40  |   51.60   |    206.40    |   0.01   | 95.16 | 737.49 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  14.96  | 0.25 | 12.14  | 32.99 |  131.98  |   32.99   |    131.98    |   0.00   | 66.93 | 489.18 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  13.55  | 0.21 | 10.86  | 36.88 |  147.54  |   36.88   |    147.54    |   0.00   | 73.91 | 543.02 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  13.64  | 0.25 | 10.57  | 37.86 |  151.43  |   37.86   |    151.43    |   0.00   | 73.30 | 538.13 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  14.96  | 0.28 | 11.55  | 34.72 |  138.86  |   34.72   |    138.86    |   0.00   | 66.86 | 484.38 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  13.35  | 0.24 | 10.43  | 38.35 |  153.41  |   38.35   |    153.41    |   0.00   | 74.93 | 554.52 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  20.65  | 0.31 | 17.97  | 22.26 |  89.02   |   22.26   |    89.02     |   0.00   | 48.42 | 337.72 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  15.84  | 0.22 | 12.96  | 30.88 |  123.50  |   30.88   |    123.50    |   0.00   | 63.15 | 453.10 |
| quad8_tex8_grey_linear_direct                           |  12.75  | 0.25 |  9.78  | 40.93 |  163.73  |   40.93   |    163.73    |   0.00   | 78.52 | 1176.44 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  15.23  | 0.24 | 12.21  | 32.76 |  131.04  |   32.76   |    131.04    |   0.00   | 65.68 | 952.25 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  14.42  | 0.27 | 11.31  | 35.47 |  141.87  |   35.47   |    141.87    |   0.00   | 69.36 | 1010.76 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  14.93  | 0.25 | 12.04  | 33.21 |  132.85  |   33.21   |    132.85    |   0.00   | 66.99 | 969.07 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  17.66  | 0.30 | 14.03  | 28.52 |  114.07  |   28.52   |    114.07    |   0.00   | 56.65 | 804.28 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  15.27  | 0.27 | 12.14  | 32.95 |  131.80  |   32.95   |    131.80    |   0.00   | 65.56 | 946.34 |
| quad8_tex8_grey_quintic_bspline_direct                  |  21.91  | 0.24 | 18.98  | 21.07 |  84.30   |   21.07   |    84.30     |   0.00   | 45.65 | 638.88 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  17.50  | 0.22 | 14.64  | 27.33 |  109.31  |   27.33   |    109.31    |   0.00   | 57.15 | 813.40 |
| quad9_tex8_grey_linear_direct                           |  12.23  | 0.27 |  9.23  | 43.32 |  173.29  |   43.32   |    173.29    |   0.00   | 81.77 | 1381.63 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  17.51  | 0.22 | 14.41  | 27.76 |  111.04  |   27.76   |    111.04    |   0.00   | 57.12 | 914.68 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  15.45  | 0.24 | 12.79  | 31.27 |  125.07  |   31.27   |    125.07    |   0.00   | 64.73 | 1050.18 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  15.00  | 0.23 | 11.72  | 34.12 |  136.50  |   34.12   |    136.50    |   0.00   | 66.68 | 1096.10 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  17.56  | 0.25 | 14.56  | 27.47 |  109.89  |   27.47   |    109.89    |   0.00   | 56.96 | 909.57 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  15.77  | 0.31 | 12.87  | 31.08 |  124.31  |   31.08   |    124.31    |   0.00   | 63.40 | 1042.23 |
| quad9_tex8_grey_quintic_bspline_direct                  |  22.52  | 0.27 | 19.46  | 20.58 |  82.31   |   20.58   |    82.31     |   0.00   | 44.41 | 717.85 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  17.85  | 0.27 | 15.18  | 26.43 |  105.71  |   26.43   |    105.71    |   0.00   | 56.09 | 893.94 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  12.85  | 0.20 |  7.84  | 51.02 |  204.07  |   51.02   |    204.07    |   0.01   | 77.92 | 441.92 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  17.06  | 0.17 | 13.06  | 30.64 |  122.55  |   30.64   |    122.55    |   0.01   | 58.67 | 313.73 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  16.33  | 0.16 | 11.89  | 33.68 |  134.71  |   33.68   |    134.71    |   0.01   | 61.25 | 329.11 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  15.45  | 0.19 | 10.37  | 38.59 |  154.35  |   38.59   |    154.35    |   0.01   | 64.80 | 355.54 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  20.93  | 0.15 | 16.40  | 24.41 |  97.65   |   24.41   |    97.65     |   0.01   | 47.80 | 250.12 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  16.45  | 0.16 | 12.33  | 32.47 |  129.87  |   32.47   |    129.87    |   0.01   | 60.82 | 326.58 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  24.04  | 0.16 | 19.29  | 20.74 |  82.96   |   20.74   |    82.96     |   0.01   | 41.59 | 215.03 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  20.25  | 0.17 | 15.96  | 25.07 |  100.27  |   25.07   |    100.27    |   0.01   | 49.38 | 259.45 |
| tri6_tex8_rgb_linear_direct                             |  15.70  | 0.19 | 11.93  | 33.53 |  134.11  |   33.53   |    134.11    |   0.01   | 63.73 | 687.11 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  20.60  | 0.18 | 16.66  | 24.01 |  96.06   |   24.01   |    96.06     |   0.01   | 48.55 | 509.12 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  20.53  | 0.18 | 16.96  | 23.59 |  94.37   |   23.59   |    94.37     |   0.01   | 48.71 | 511.98 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.65  | 0.17 | 16.59  | 24.12 |  96.47   |   24.12   |    96.47     |   0.01   | 48.42 | 507.52 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  24.76  | 0.18 | 20.12  | 19.88 |  79.54   |   19.88   |    79.54     |   0.01   | 40.45 | 418.39 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  20.50  | 0.19 | 16.52  | 24.22 |  96.88   |   24.22   |    96.88     |   0.01   | 48.78 | 516.93 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  28.72  | 0.17 | 24.46  | 16.35 |  65.41   |   16.35   |    65.41     |   0.01   | 34.82 | 355.95 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  20.00  | 0.20 | 16.35  | 24.50 |  98.00   |   24.50   |    98.00     |   0.01   | 50.20 | 531.22 |
| quad4ibi_tex8_rgb_linear_direct                         |  12.20  | 0.20 |  7.57  | 52.85 |  211.39  |   52.85   |    211.39    |   0.00   | 82.14 | 621.43 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  18.19  | 0.22 | 13.85  | 28.89 |  115.55  |   28.89   |    115.55    |   0.00   | 55.09 | 392.68 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  17.36  | 0.21 | 13.08  | 30.63 |  122.52  |   30.63   |    122.52    |   0.00   | 57.61 | 415.06 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  16.87  | 0.22 | 13.04  | 30.70 |  122.79  |   30.70   |    122.79    |   0.00   | 59.28 | 424.60 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  23.15  | 0.24 | 19.20  | 20.83 |  83.34   |   20.83   |    83.34     |   0.00   | 43.19 | 298.99 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  18.22  | 0.19 | 14.03  | 28.53 |  114.11  |   28.53   |    114.11    |   0.01   | 54.88 | 390.24 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  25.96  | 0.20 | 21.47  | 18.68 |  74.72   |   18.68   |    74.72     |   0.01   | 38.53 | 264.23 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  23.25  | 0.20 | 19.30  | 20.73 |  82.91   |   20.73   |    82.91     |   0.00   | 43.01 | 297.53 |
| quad4newton_tex8_rgb_linear_direct                      |  13.95  | 0.24 | 10.15  | 39.41 |  157.62  |   39.41   |    157.62    |   0.00   | 71.71 | 530.17 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  20.27  | 0.20 | 16.05  | 24.94 |  99.77   |   24.94   |    99.77     |   0.00   | 49.33 | 346.17 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  18.95  | 0.21 | 15.00  | 26.67 |  106.68  |   26.67   |    106.68    |   0.00   | 52.80 | 372.36 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  18.84  | 0.21 | 14.45  | 27.69 |  110.74  |   27.69   |    110.74    |   0.00   | 53.07 | 394.83 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  22.17  | 0.19 | 18.28  | 21.88 |  87.53   |   21.88   |    87.53     |   0.01   | 45.11 | 312.79 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  16.96  | 0.20 | 13.49  | 29.65 |  118.60  |   29.65   |    118.60    |   0.01   | 58.97 | 425.26 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  23.39  | 0.19 | 19.35  | 20.67 |  82.70   |   20.67   |    82.70     |   0.01   | 42.77 | 296.95 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  19.65  | 0.19 | 15.67  | 25.77 |  103.07  |   25.77   |    103.07    |   0.01   | 51.11 | 365.64 |
| quad8_tex8_rgb_linear_direct                            |  15.01  | 0.23 | 11.46  | 34.92 |  139.67  |   34.92   |    139.67    |   0.00   | 66.66 | 964.94 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  17.74  | 0.23 | 14.09  | 28.38 |  113.52  |   28.38   |    113.52    |   0.00   | 56.38 | 799.33 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  18.45  | 0.18 | 14.72  | 27.17 |  108.67  |   27.17   |    108.67    |   0.01   | 54.22 | 766.62 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  20.94  | 0.20 | 16.72  | 23.93 |  95.71   |   23.93   |    95.71     |   0.00   | 47.76 | 682.24 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  22.41  | 0.19 | 18.57  | 21.54 |  86.15   |   21.54   |    86.15     |   0.01   | 44.61 | 619.32 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  20.69  | 0.22 | 16.42  | 24.37 |  97.47   |   24.37   |    97.47     |   0.00   | 48.34 | 675.18 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  24.95  | 0.18 | 19.19  | 20.85 |  83.40   |   20.85   |    83.40     |   0.01   | 40.31 | 556.22 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  23.53  | 0.22 | 19.80  | 20.21 |  80.82   |   20.21   |    80.82     |   0.00   | 42.50 | 587.55 |
| quad9_tex8_rgb_linear_direct                            |  16.16  | 0.24 | 12.28  | 32.58 |  130.33  |   32.58   |    130.33    |   0.00   | 61.87 | 999.78 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  21.51  | 0.19 | 17.57  | 22.77 |  91.09   |   22.77   |    91.09     |   0.01   | 46.51 | 727.27 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  20.81  | 0.21 | 16.63  | 24.06 |  96.23   |   24.06   |    96.23     |   0.00   | 48.05 | 764.19 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  19.76  | 0.20 | 15.65  | 25.57 |  102.27  |   25.57   |    102.27    |   0.01   | 50.61 | 819.50 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  22.86  | 0.19 | 19.61  | 20.39 |  81.58   |   20.39   |    81.58     |   0.01   | 43.74 | 685.22 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  20.48  | 0.17 | 16.65  | 24.02 |  96.09   |   24.02   |    96.09     |   0.01   | 48.83 | 775.86 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  25.93  | 0.20 | 21.90  | 18.49 |  73.97   |   18.49   |    73.97     |   0.00   | 38.97 | 607.93 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  23.95  | 0.19 | 20.16  | 19.84 |  79.35   |   19.84   |    79.35     |   0.01   | 41.76 | 649.64 |

