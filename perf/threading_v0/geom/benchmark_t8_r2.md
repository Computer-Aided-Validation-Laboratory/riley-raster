# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  15.28  | 4.25 |  4.81  | 83.09 |  332.38  |   85.99   |    343.98    |  48.23   | 65.45 | 434.34 |
| tri6_nodal_grey                                         |  34.56  | 8.83 | 18.08  | 22.12 |  88.49   |   22.73   |    90.94     |  23.19   | 28.93 | 344.02 |
| quad4ibi_nodal_grey                                     |  12.22  | 3.19 |  6.20  | 64.48 |  257.94  |   66.14   |    264.55    |  32.10   | 81.84 | 627.97 |
| quad4newton_nodal_grey                                  |  15.95  | 2.68 |  9.53  | 41.99 |  167.96  |   43.14   |    172.58    |  38.28   | 62.74 | 469.86 |
| quad8_nodal_grey                                        |  28.09  | 5.93 | 15.36  | 26.05 |  104.19  |   26.75   |    107.00    |  17.27   | 35.61 | 581.94 |
| quad9_nodal_grey                                        |  28.79  | 6.15 | 15.24  | 26.26 |  105.05  |   26.97   |    107.89    |  16.66   | 34.73 | 653.52 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  18.49  | 4.82 |  5.56  | 71.97 |  287.90  |   74.48   |    297.92    |  42.53   | 54.09 | 320.13 |
| tri6_nodal_rgb                                          |  41.51  | 10.15 | 19.64  | 20.37 |  81.50   |   20.94   |    83.75     |  20.18   | 24.09 | 296.52 |
| quad4ibi_nodal_rgb                                      |  17.08  | 3.67 |  7.91  | 50.56 |  202.26  |   51.87   |    207.46    |  27.89   | 58.61 | 476.99 |
| quad4newton_nodal_rgb                                   |  19.30  | 3.33 | 10.64  | 37.60 |  150.39  |   38.63   |    154.50    |  30.78   | 51.82 | 400.56 |
| quad8_nodal_rgb                                         |  31.63  | 7.27 | 15.56  | 25.74 |  102.95  |   26.43   |    105.74    |  14.09   | 31.63 | 517.82 |
| quad9_nodal_rgb                                         |  31.06  | 7.76 | 14.82  | 27.00 |  107.99  |   27.72   |    110.89    |  13.20   | 32.22 | 584.40 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  20.55  | 4.32 |  8.13  | 49.21 |  196.83  |   50.92   |    203.70    |  47.47   | 48.69 | 342.13 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  25.42  | 4.49 | 12.52  | 31.94 |  127.75  |   33.05   |    132.21    |  45.60   | 39.34 | 262.72 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  23.51  | 4.65 | 10.92  | 36.62 |  146.48  |   37.90   |    151.60    |  44.02   | 42.56 | 282.26 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  22.75  | 4.05 | 10.66  | 37.53 |  150.11  |   38.83   |    155.33    |  50.53   | 43.97 | 297.99 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  24.93  | 4.48 | 12.57  | 31.82 |  127.29  |   32.93   |    131.71    |  45.76   | 40.11 | 265.64 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  24.13  | 4.25 | 11.25  | 35.57 |  142.26  |   36.79   |    147.17    |  48.23   | 41.45 | 276.21 |
| tri3_tex8_grey_quintic_bspline_direct                   |  29.06  | 4.40 | 18.07  | 22.14 |  88.57   |   22.92   |    91.66     |  46.59   | 34.41 | 209.95 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  25.68  | 4.37 | 13.51  | 29.61 |  118.44  |   30.64   |    122.56    |  47.09   | 38.95 | 258.33 |
| tri6_tex8_grey_linear_direct                            |  52.23  | 8.97 | 21.30  | 18.78 |  75.12   |   19.30   |    77.19     |  22.83   | 19.15 | 306.92 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  55.61  | 8.97 | 24.61  | 16.26 |  65.03   |   16.71   |    66.84     |  22.82   | 17.99 | 277.98 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  52.80  | 9.54 | 22.17  | 18.04 |  72.16   |   18.54   |    74.16     |  21.48   | 18.94 | 294.48 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  52.76  | 9.02 | 22.52  | 17.77 |  71.07   |   18.26   |    73.03     |  22.72   | 18.96 | 293.82 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  55.04  | 8.93 | 24.53  | 16.31 |  65.26   |   16.77   |    67.06     |  22.93   | 18.17 | 278.41 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  53.48  | 9.16 | 24.09  | 16.64 |  66.57   |   17.11   |    68.42     |  22.37   | 18.70 | 277.44 |
| tri6_tex8_grey_quintic_bspline_direct                   |  61.85  | 8.88 | 28.60  | 13.99 |  55.97   |   14.38   |    57.52     |  23.06   | 16.17 | 241.95 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  58.16  | 8.98 | 27.61  | 14.49 |  57.97   |   14.89   |    59.57     |  22.80   | 17.19 | 254.84 |
| quad4ibi_tex8_grey_linear_direct                        |  16.16  | 3.40 |  8.09  | 49.48 |  197.92  |   50.74   |    202.97    |  30.16   | 61.92 | 514.86 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  19.98  | 2.94 | 12.94  | 30.93 |  123.74  |   31.73   |    126.92    |  34.87   | 50.05 | 386.40 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  19.23  | 3.01 | 11.93  | 33.52 |  134.09  |   34.39   |    137.54    |  34.00   | 52.00 | 405.90 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.70  | 3.23 | 13.05  | 30.65 |  122.59  |   31.43   |    125.73    |  31.75   | 48.32 | 372.54 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  21.54  | 2.93 | 14.12  | 28.55 |  114.18  |   29.28   |    117.12    |  34.90   | 46.44 | 359.39 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  21.41  | 3.20 | 12.46  | 32.11 |  128.45  |   32.94   |    131.76    |  31.99   | 46.74 | 397.74 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  26.82  | 2.99 | 18.24  | 21.93 |  87.71   |   22.49   |    89.97     |  34.26   | 37.29 | 286.68 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  23.72  | 2.78 | 14.90  | 26.85 |  107.40  |   27.54   |    110.16    |  36.89   | 42.15 | 332.05 |
| quad4newton_tex8_grey_linear_direct                     |  30.34  | 2.80 | 11.91  | 33.60 |  134.39  |   34.51   |    138.04    |  36.62   | 32.96 | 395.48 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  33.87  | 2.91 | 14.22  | 28.30 |  113.20  |   29.07   |    116.30    |  35.13   | 29.53 | 326.15 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  32.30  | 2.95 | 14.60  | 27.44 |  109.77  |   28.19   |    112.76    |  34.73   | 30.96 | 339.10 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  33.54  | 2.94 | 15.38  | 26.03 |  104.11  |   26.74   |    106.95    |  34.77   | 29.82 | 336.21 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  33.93  | 2.99 | 15.63  | 25.72 |  102.89  |   26.42   |    105.69    |  34.28   | 29.48 | 335.32 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  35.11  | 2.95 | 15.60  | 25.64 |  102.55  |   26.34   |    105.37    |  34.97   | 28.48 | 319.65 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  40.27  | 2.86 | 22.39  | 17.87 |  71.47   |   18.36   |    73.42     |  35.79   | 24.83 | 244.33 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  34.68  | 2.91 | 17.37  | 23.02 |  92.09   |   23.66   |    94.62     |  35.21   | 28.84 | 296.82 |
| quad8_tex8_grey_linear_direct                           |  38.78  | 6.65 | 16.82  | 23.78 |  95.12   |   24.42   |    97.68     |  15.40   | 25.79 | 528.53 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  43.32  | 6.30 | 21.69  | 18.44 |  73.77   |   18.94   |    75.76     |  16.25   | 23.08 | 438.25 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  42.87  | 6.16 | 21.16  | 18.91 |  75.63   |   19.42   |    77.68     |  16.64   | 23.33 | 454.81 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.08  | 6.44 | 19.97  | 20.04 |  80.14   |   20.58   |    82.30     |  15.91   | 23.21 | 450.87 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  46.27  | 6.24 | 23.26  | 17.20 |  68.82   |   17.67   |    70.67     |  16.41   | 21.61 | 413.72 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  41.68  | 6.22 | 19.79  | 20.21 |  80.83   |   20.75   |    83.01     |  16.45   | 24.02 | 472.28 |
| quad8_tex8_grey_quintic_bspline_direct                  |  46.55  | 6.92 | 23.43  | 17.09 |  68.36   |   17.55   |    70.21     |  14.82   | 21.49 | 411.12 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  45.97  | 6.67 | 22.30  | 17.95 |  71.80   |   18.43   |    73.73     |  15.39   | 21.76 | 409.80 |
| quad9_tex8_grey_linear_direct                           |  40.93  | 6.75 | 16.49  | 24.26 |  97.03   |   24.92   |    99.68     |  15.17   | 24.43 | 576.50 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  46.38  | 7.01 | 21.33  | 18.77 |  75.07   |   19.28   |    77.11     |  14.62   | 21.57 | 476.98 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  43.73  | 6.83 | 19.66  | 20.35 |  81.39   |   20.90   |    83.59     |  14.99   | 22.87 | 525.05 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.76  | 7.01 | 19.99  | 20.02 |  80.07   |   20.56   |    82.25     |  14.61   | 22.85 | 513.81 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  45.50  | 6.69 | 21.46  | 18.65 |  74.60   |   19.15   |    76.62     |  15.30   | 21.98 | 488.57 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  45.98  | 6.60 | 20.57  | 19.45 |  77.81   |   19.98   |    79.93     |  15.52   | 21.75 | 496.24 |
| quad9_tex8_grey_quintic_bspline_direct                  |  50.37  | 6.75 | 25.41  | 15.74 |  62.97   |   16.17   |    64.68     |  15.17   | 19.86 | 431.73 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  46.46  | 7.08 | 21.55  | 18.57 |  74.30   |   19.09   |    76.34     |  14.50   | 21.52 | 485.76 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  22.42  | 4.31 | 10.55  | 37.92 |  151.70  |   39.25   |    156.99    |  47.52   | 44.60 | 281.95 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  29.45  | 4.34 | 16.64  | 24.04 |  96.16   |   24.87   |    99.49     |  47.24   | 33.96 | 204.36 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  24.86  | 3.82 | 13.52  | 29.79 |  119.17  |   30.82   |    123.27    |  53.69   | 40.24 | 246.57 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  26.06  | 4.39 | 13.90  | 28.80 |  115.18  |   29.79   |    119.17    |  46.68   | 38.37 | 231.89 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  29.82  | 3.92 | 18.38  | 21.76 |  87.03   |   22.52   |    90.07     |  52.31   | 33.53 | 200.44 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  26.82  | 3.92 | 15.66  | 25.55 |  102.20  |   26.44   |    105.75    |  52.23   | 37.28 | 227.06 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  34.30  | 4.19 | 22.66  | 17.65 |  70.61   |   18.26   |    73.06     |  48.85   | 29.16 | 168.29 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  31.83  | 4.09 | 18.62  | 21.51 |  86.03   |   22.26   |    89.03     |  50.08   | 31.43 | 183.46 |
| tri6_tex8_rgb_linear_direct                             |  58.71  | 9.23 | 26.25  | 15.24 |  60.96   |   15.66   |    62.65     |  22.18   | 17.03 | 252.92 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  62.45  | 10.21 | 27.26  | 14.68 |  58.70   |   15.08   |    60.32     |  20.06   | 16.01 | 238.88 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  61.74  | 9.51 | 25.92  | 15.44 |  61.77   |   15.87   |    63.47     |  21.53   | 16.20 | 249.37 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  60.95  | 9.66 | 26.08  | 15.34 |  61.37   |   15.76   |    63.06     |  21.21   | 16.41 | 245.55 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  62.89  | 9.31 | 29.63  | 13.51 |  54.04   |   13.88   |    55.53     |  21.99   | 15.90 | 235.42 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  60.99  | 9.40 | 27.77  | 14.41 |  57.63   |   14.81   |    59.23     |  21.78   | 16.40 | 246.09 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  67.75  | 9.44 | 34.04  | 11.75 |  47.01   |   12.08   |    48.32     |  21.71   | 14.76 | 210.92 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  63.71  | 9.71 | 29.37  | 13.62 |  54.48   |   14.00   |    55.99     |  21.10   | 15.71 | 223.98 |
| quad4ibi_tex8_rgb_linear_direct                         |  18.22  | 3.12 |  9.21  | 43.52 |  174.09  |   44.64   |    178.56    |  32.85   | 54.89 | 447.13 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  23.72  | 3.42 | 13.71  | 29.37 |  117.47  |   30.12   |    120.47    |  29.97   | 42.21 | 335.21 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  23.00  | 3.09 | 14.39  | 27.89 |  111.57  |   28.61   |    114.45    |  33.17   | 43.50 | 339.56 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  25.63  | 3.16 | 16.12  | 24.82 |  99.29   |   25.45   |    101.81    |  32.41   | 39.01 | 302.48 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  28.82  | 3.46 | 18.62  | 21.50 |  85.99   |   22.04   |    88.17     |  29.62   | 34.70 | 258.66 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  24.69  | 3.10 | 15.03  | 26.62 |  106.50  |   27.29   |    109.15    |  33.08   | 40.50 | 325.60 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  33.56  | 3.27 | 23.19  | 17.26 |  69.04   |   17.70   |    70.81     |  31.31   | 29.80 | 217.15 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  29.07  | 3.34 | 19.60  | 20.41 |  81.63   |   20.93   |    83.74     |  30.63   | 34.40 | 257.28 |
| quad4newton_tex8_rgb_linear_direct                      |  34.34  | 3.13 | 14.52  | 27.56 |  110.23  |   28.31   |    113.25    |  32.68   | 29.14 | 323.25 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  40.20  | 3.15 | 20.03  | 19.97 |  79.87   |   20.52   |    82.07     |  32.55   | 24.88 | 257.85 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  38.38  | 3.09 | 19.29  | 20.74 |  82.96   |   21.31   |    85.22     |  33.11   | 26.06 | 266.48 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  38.64  | 3.11 | 19.03  | 21.02 |  84.09   |   21.60   |    86.41     |  32.92   | 25.88 | 264.86 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  41.34  | 3.00 | 21.47  | 18.63 |  74.52   |   19.14   |    76.56     |  34.09   | 24.19 | 239.71 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  38.83  | 3.08 | 19.35  | 20.67 |  82.67   |   21.23   |    84.93     |  33.24   | 25.76 | 263.14 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  44.79  | 3.07 | 24.87  | 16.09 |  64.35   |   16.53   |    66.11     |  33.30   | 22.33 | 210.08 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  41.43  | 3.31 | 21.38  | 18.72 |  74.87   |   19.23   |    76.92     |  30.94   | 24.14 | 238.81 |
| quad8_tex8_rgb_linear_direct                            |  43.67  | 6.26 | 21.10  | 18.96 |  75.84   |   19.47   |    77.88     |  16.35   | 22.91 | 440.52 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  49.44  | 7.23 | 24.56  | 16.29 |  65.16   |   16.73   |    66.90     |  14.16   | 20.23 | 372.00 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.42  | 6.69 | 24.88  | 16.08 |  64.34   |   16.52   |    66.07     |  15.30   | 20.65 | 370.97 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.44  | 6.24 | 22.13  | 18.08 |  72.30   |   18.56   |    74.25     |  16.40   | 21.08 | 403.83 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  49.89  | 6.35 | 25.24  | 15.90 |  63.59   |   16.32   |    65.29     |  16.12   | 20.05 | 359.64 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  47.93  | 6.56 | 22.40  | 17.86 |  71.44   |   18.34   |    73.35     |  15.60   | 20.87 | 402.13 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  51.77  | 6.16 | 29.49  | 13.56 |  54.26   |   13.93   |    55.72     |  16.61   | 19.32 | 343.52 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  50.86  | 6.20 | 26.91  | 14.86 |  59.46   |   15.26   |    61.05     |  16.51   | 19.66 | 350.33 |
| quad9_tex8_rgb_linear_direct                            |  46.64  | 6.89 | 20.72  | 19.31 |  77.23   |   19.83   |    79.34     |  14.87   | 21.45 | 469.53 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  49.64  | 6.34 | 24.71  | 16.19 |  64.74   |   16.63   |    66.50     |  16.17   | 20.18 | 435.83 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  45.82  | 6.50 | 22.13  | 18.07 |  72.29   |   18.57   |    74.27     |  15.75   | 21.83 | 469.36 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.79  | 6.92 | 22.57  | 17.73 |  70.90   |   18.21   |    72.83     |  14.80   | 20.93 | 456.76 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  49.45  | 6.74 | 25.62  | 15.62 |  62.46   |   16.03   |    64.14     |  15.22   | 20.22 | 408.68 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  48.60  | 6.68 | 24.20  | 16.53 |  66.12   |   16.98   |    67.93     |  15.33   | 20.58 | 439.91 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  56.71  | 6.87 | 31.86  | 12.56 |  50.23   |   12.90   |    51.59     |  14.91   | 17.64 | 357.62 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  50.46  | 6.44 | 27.29  | 14.66 |  58.63   |   15.06   |    60.24     |  15.90   | 19.82 | 403.81 |

