# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  6.43   | 0.21 |  2.79  | 143.33 |  573.33  |  143.33   |    573.33    |   0.01   | 155.43 | 1020.16 |
| tri6_nodal_grey                                         |  10.46  | 0.26 |  7.60  | 52.65 |  210.58  |   52.65   |    210.58    |   0.01   | 95.57 | 1099.76 |
| quad4ibi_nodal_grey                                     |  8.73   | 0.25 |  5.67  | 70.55 |  282.18  |   70.55   |    282.18    |   0.00   | 114.52 | 920.28 |
| quad4newton_nodal_grey                                  |  8.72   | 0.23 |  5.86  | 68.22 |  272.87  |   68.22   |    272.87    |   0.00   | 114.74 | 939.11 |
| quad8_nodal_grey                                        |  10.68  | 0.22 |  7.35  | 54.60 |  218.39  |   54.60   |    218.39    |   0.00   | 93.66 | 1445.96 |
| quad9_nodal_grey                                        |  10.85  | 0.24 |  7.78  | 51.44 |  205.74  |   51.44   |    205.74    |   0.00   | 92.13 | 1591.00 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  8.01   | 0.18 |  3.34  | 119.81 |  479.24  |  119.81   |    479.24    |   0.01   | 125.17 | 770.90 |
| tri6_nodal_rgb                                          |  12.15  | 0.17 |  7.67  | 52.19 |  208.74  |   52.19   |    208.74    |   0.01   | 82.29 | 919.83 |
| quad4ibi_nodal_rgb                                      |  10.27  | 0.21 |  6.68  | 59.91 |  239.63  |   59.91   |    239.63    |   0.00   | 97.36 | 749.52 |
| quad4newton_nodal_rgb                                   |  10.83  | 0.21 |  6.87  | 58.34 |  233.35  |   58.34   |    233.35    |   0.00   | 92.36 | 709.64 |
| quad8_nodal_rgb                                         |  12.45  | 0.23 |  7.99  | 50.06 |  200.25  |   50.06   |    200.25    |   0.00   | 80.31 | 1269.89 |
| quad9_nodal_rgb                                         |  13.26  | 0.20 |  9.41  | 42.51 |  170.05  |   42.51   |    170.05    |   0.00   | 75.41 | 1268.57 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  7.29   | 0.18 |  4.62  | 86.52 |  346.09  |   86.52   |    346.09    |   0.01   | 137.14 | 873.86 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  11.80  | 0.17 |  8.66  | 46.40 |  185.60  |   46.40   |    185.60    |   0.01   | 84.77 | 483.38 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  9.54   | 0.16 |  6.96  | 57.51 |  230.03  |   57.51   |    230.03    |   0.01   | 104.90 | 615.85 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  10.65  | 0.18 |  7.99  | 50.09 |  200.34  |   50.09   |    200.34    |   0.01   | 93.93 | 538.23 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  13.31  | 0.20 | 10.62  | 37.67 |  150.67  |   37.67   |    150.67    |   0.01   | 75.15 | 417.01 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  10.93  | 0.21 |  8.06  | 49.63 |  198.52  |   49.63   |    198.52    |   0.01   | 91.53 | 523.37 |
| tri3_tex8_grey_quintic_bspline_direct                   |  16.82  | 0.23 | 12.79  | 31.27 |  125.10  |   31.27   |    125.10    |   0.01   | 59.72 | 319.78 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  13.95  | 0.17 | 10.82  | 36.97 |  147.89  |   36.97   |    147.89    |   0.01   | 71.70 | 398.16 |
| tri6_tex8_grey_linear_direct                            |  12.64  | 0.21 |  9.85  | 40.60 |  162.40  |   40.60   |    162.40    |   0.01   | 79.17 | 883.24 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  16.37  | 0.21 | 13.37  | 29.91 |  119.66  |   29.91   |    119.66    |   0.01   | 61.10 | 665.36 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  15.44  | 0.23 | 12.47  | 32.08 |  128.33  |   32.08   |    128.33    |   0.01   | 64.77 | 712.83 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  15.73  | 0.19 | 12.94  | 30.91 |  123.66  |   30.91   |    123.66    |   0.01   | 63.59 | 688.46 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  16.67  | 0.22 | 14.02  | 28.56 |  114.22  |   28.56   |    114.22    |   0.01   | 59.98 | 644.10 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  14.39  | 0.22 | 11.64  | 34.35 |  137.41  |   34.35   |    137.41    |   0.01   | 69.50 | 758.06 |
| tri6_tex8_grey_quintic_bspline_direct                   |  22.71  | 0.20 | 19.09  | 20.98 |  83.91   |   20.98   |    83.91     |   0.01   | 44.04 | 458.23 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  17.59  | 0.24 | 14.50  | 27.58 |  110.31  |   27.58   |    110.31    |   0.01   | 56.86 | 606.71 |
| quad4ibi_tex8_grey_linear_direct                        |  8.60   | 0.24 |  5.50  | 72.82 |  291.27  |   72.82   |    291.27    |   0.00   | 116.40 | 953.95 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  14.26  | 0.25 | 11.42  | 35.03 |  140.11  |   35.03   |    140.11    |   0.00   | 70.11 | 513.58 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  14.53  | 0.24 | 11.51  | 34.76 |  139.03  |   34.76   |    139.03    |   0.00   | 68.85 | 499.58 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  14.15  | 0.21 | 11.14  | 35.92 |  143.68  |   35.92   |    143.68    |   0.00   | 70.74 | 517.67 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  17.68  | 0.29 | 14.47  | 27.65 |  110.59  |   27.65   |    110.59    |   0.00   | 56.56 | 404.63 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  14.97  | 0.31 | 11.98  | 33.40 |  133.60  |   33.40   |    133.60    |   0.00   | 66.82 | 484.48 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  20.70  | 0.24 | 18.00  | 22.24 |  88.97   |   22.24   |    88.97     |   0.00   | 48.36 | 341.18 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  16.69  | 0.25 | 13.93  | 28.73 |  114.94  |   28.73   |    114.94    |   0.00   | 59.93 | 429.43 |
| quad4newton_tex8_grey_linear_direct                     |  10.06  | 0.24 |  6.92  | 57.82 |  231.28  |   57.82   |    231.28    |   0.00   | 99.58 | 769.66 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  14.19  | 0.25 | 11.18  | 35.78 |  143.12  |   35.78   |    143.12    |   0.00   | 70.47 | 518.95 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  13.67  | 0.24 | 10.59  | 37.79 |  151.15  |   37.79   |    151.15    |   0.00   | 73.18 | 536.37 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  13.01  | 0.23 | 10.37  | 38.56 |  154.22  |   38.56   |    154.22    |   0.00   | 76.89 | 567.40 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  15.15  | 0.25 | 11.43  | 35.16 |  140.66  |   35.16   |    140.66    |   0.00   | 66.01 | 485.71 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  13.48  | 0.28 | 10.41  | 38.43 |  153.72  |   38.43   |    153.72    |   0.00   | 74.20 | 570.59 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  21.02  | 0.22 | 17.84  | 22.42 |  89.69   |   22.42   |    89.69     |   0.00   | 47.59 | 331.94 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  15.59  | 0.27 | 11.87  | 33.71 |  134.84  |   33.71   |    134.84    |   0.00   | 64.14 | 467.48 |
| quad8_tex8_grey_linear_direct                           |  11.39  | 0.23 |  8.73  | 45.83 |  183.31  |   45.83   |    183.31    |   0.00   | 87.77 | 1338.31 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  16.85  | 0.26 | 13.78  | 29.03 |  116.13  |   29.03   |    116.13    |   0.00   | 59.35 | 855.49 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  14.74  | 0.25 | 11.58  | 34.57 |  138.29  |   34.57   |    138.29    |   0.00   | 67.93 | 988.82 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  15.15  | 0.27 | 12.28  | 32.57 |  130.29  |   32.57   |    130.29    |   0.00   | 66.03 | 954.71 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  17.20  | 0.21 | 14.70  | 27.21 |  108.83  |   27.21   |    108.83    |   0.00   | 58.13 | 827.69 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  15.86  | 0.32 | 11.66  | 34.31 |  137.25  |   34.31   |    137.25    |   0.00   | 63.04 | 934.26 |
| quad8_tex8_grey_quintic_bspline_direct                  |  22.14  | 0.30 | 19.22  | 20.82 |  83.27   |   20.82   |    83.27     |   0.00   | 45.17 | 630.39 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  16.63  | 0.23 | 14.16  | 28.24 |  112.96  |   28.24   |    112.96    |   0.00   | 60.13 | 863.93 |
| quad9_tex8_grey_linear_direct                           |  11.76  | 0.21 |  8.78  | 45.56 |  182.24  |   45.56   |    182.24    |   0.00   | 85.04 | 1449.30 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  17.43  | 0.22 | 14.66  | 27.29 |  109.18  |   27.29   |    109.18    |   0.00   | 57.37 | 918.49 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  14.90  | 0.22 | 12.40  | 32.25 |  129.01  |   32.25   |    129.01    |   0.00   | 67.10 | 1091.23 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  15.94  | 0.26 | 12.53  | 31.95 |  127.81  |   31.95   |    127.81    |   0.00   | 62.72 | 1018.16 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  17.97  | 0.25 | 14.61  | 27.39 |  109.57  |   27.39   |    109.57    |   0.00   | 55.65 | 922.29 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  15.89  | 0.21 | 12.61  | 31.73 |  126.94  |   31.73   |    126.94    |   0.00   | 62.92 | 1039.79 |
| quad9_tex8_grey_quintic_bspline_direct                  |  24.06  | 0.25 | 21.27  | 18.81 |  75.23   |   18.81   |    75.23     |   0.00   | 41.57 | 645.44 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  17.91  | 0.27 | 14.44  | 27.71 |  110.84  |   27.71   |    110.84    |   0.00   | 55.86 | 897.04 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  11.26  | 0.17 |  6.08  | 65.84 |  263.34  |   65.84   |    263.34    |   0.01   | 89.06 | 515.08 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  15.89  | 0.21 | 10.78  | 37.48 |  149.92  |   37.48   |    149.92    |   0.01   | 63.07 | 339.08 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  17.03  | 0.18 | 12.05  | 33.22 |  132.87  |   33.22   |    132.87    |   0.01   | 58.74 | 326.46 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  16.07  | 0.16 | 12.51  | 31.97 |  127.86  |   31.97   |    127.86    |   0.01   | 62.23 | 334.45 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  18.54  | 0.17 | 13.83  | 28.92 |  115.67  |   28.92   |    115.67    |   0.01   | 53.97 | 287.97 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  13.90  | 0.14 |  9.93  | 40.34 |  161.37  |   40.34   |    161.37    |   0.01   | 71.94 | 399.16 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  24.47  | 0.14 | 19.16  | 20.95 |  83.79   |   20.95   |    83.79     |   0.01   | 40.88 | 211.38 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  16.47  | 0.14 | 12.30  | 32.53 |  130.12  |   32.53   |    130.12    |   0.01   | 60.76 | 326.07 |
| tri6_tex8_rgb_linear_direct                             |  16.09  | 0.21 | 11.49  | 34.81 |  139.26  |   34.81   |    139.26    |   0.01   | 62.27 | 670.04 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  21.87  | 0.18 | 18.17  | 22.02 |  88.08   |   22.02   |    88.08     |   0.01   | 45.72 | 480.10 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  21.29  | 0.18 | 16.53  | 24.21 |  96.83   |   24.21   |    96.83     |   0.01   | 46.97 | 495.34 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.73  | 0.23 | 16.68  | 23.99 |  95.97   |   23.99   |    95.97     |   0.01   | 48.25 | 510.27 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  22.72  | 0.19 | 19.03  | 21.02 |  84.08   |   21.02   |    84.08     |   0.01   | 44.01 | 460.80 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  20.29  | 0.19 | 16.52  | 24.22 |  96.88   |   24.22   |    96.88     |   0.01   | 49.31 | 517.77 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  26.57  | 0.19 | 23.01  | 17.41 |  69.66   |   17.41   |    69.66     |   0.01   | 37.72 | 387.99 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  23.37  | 0.19 | 18.98  | 21.08 |  84.34   |   21.08   |    84.34     |   0.01   | 42.79 | 443.73 |
| quad4ibi_tex8_rgb_linear_direct                         |  12.39  | 0.22 |  8.58  | 46.61 |  186.43  |   46.61   |    186.43    |   0.00   | 80.73 | 611.10 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  18.81  | 0.23 | 14.74  | 27.15 |  108.58  |   27.15   |    108.58    |   0.00   | 53.17 | 375.19 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  17.37  | 0.21 | 13.07  | 30.61 |  122.45  |   30.61   |    122.45    |   0.00   | 57.65 | 409.75 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  19.22  | 0.22 | 14.81  | 27.01 |  108.04  |   27.01   |    108.04    |   0.00   | 52.05 | 366.35 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  22.92  | 0.21 | 19.55  | 20.46 |  81.86   |   20.46   |    81.86     |   0.00   | 43.64 | 302.19 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  18.01  | 0.19 | 14.60  | 27.41 |  109.63  |   27.41   |    109.63    |   0.01   | 55.59 | 393.57 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  27.75  | 0.23 | 24.36  | 16.42 |  65.68   |   16.42   |    65.68     |   0.00   | 36.03 | 246.09 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  22.88  | 0.20 | 19.00  | 21.05 |  84.21   |   21.05   |    84.21     |   0.00   | 43.76 | 303.02 |
| quad4newton_tex8_rgb_linear_direct                      |  13.86  | 0.27 | 10.24  | 39.06 |  156.25  |   39.06   |    156.25    |   0.00   | 72.19 | 535.07 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  19.02  | 0.20 | 15.16  | 26.38 |  105.52  |   26.38   |    105.52    |   0.00   | 52.58 | 370.38 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  18.61  | 0.23 | 14.69  | 27.24 |  108.98  |   27.24   |    108.98    |   0.00   | 53.73 | 380.16 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  18.51  | 0.22 | 14.33  | 27.91 |  111.65  |   27.91   |    111.65    |   0.00   | 54.01 | 381.41 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  18.04  | 0.20 | 13.70  | 29.20 |  116.81  |   29.20   |    116.81    |   0.00   | 55.42 | 399.38 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  19.57  | 0.24 | 15.48  | 25.83 |  103.34  |   25.83   |    103.34    |   0.00   | 51.10 | 358.55 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  26.42  | 0.24 | 22.42  | 17.84 |  71.36   |   17.84   |    71.36     |   0.00   | 37.86 | 259.45 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  20.97  | 0.21 | 17.67  | 22.64 |  90.56   |   22.64   |    90.56     |   0.00   | 47.70 | 336.04 |
| quad8_tex8_rgb_linear_direct                            |  15.84  | 0.21 | 11.03  | 36.28 |  145.11  |   36.28   |    145.11    |   0.00   | 63.14 | 915.97 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  21.45  | 0.19 | 17.10  | 23.40 |  93.59   |   23.40   |    93.59     |   0.01   | 46.63 | 649.99 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  20.44  | 0.22 | 16.26  | 24.61 |  98.44   |   24.61   |    98.44     |   0.00   | 48.93 | 687.55 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  19.76  | 0.20 | 16.13  | 24.80 |  99.19   |   24.80   |    99.19     |   0.01   | 50.60 | 715.36 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  24.58  | 0.17 | 20.36  | 19.65 |  78.60   |   19.65   |    78.60     |   0.01   | 40.69 | 559.64 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  20.85  | 0.20 | 17.35  | 23.05 |  92.21   |   23.05   |    92.21     |   0.00   | 47.95 | 670.22 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  28.90  | 0.20 | 24.63  | 16.25 |  65.00   |   16.25   |    65.00     |   0.00   | 34.60 | 471.26 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  22.81  | 0.21 | 18.97  | 21.09 |  84.36   |   21.09   |    84.36     |   0.00   | 43.84 | 610.60 |
| quad9_tex8_rgb_linear_direct                            |  16.35  | 0.17 | 12.24  | 32.68 |  130.71  |   32.68   |    130.71    |   0.01   | 61.16 | 1008.43 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  21.92  | 0.23 | 18.79  | 21.29 |  85.17   |   21.29   |    85.17     |   0.00   | 45.63 | 712.38 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  20.44  | 0.18 | 16.61  | 24.09 |  96.34   |   24.09   |    96.34     |   0.01   | 48.92 | 769.05 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  20.09  | 0.22 | 16.63  | 24.05 |  96.19   |   24.05   |    96.19     |   0.00   | 49.79 | 791.25 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  22.59  | 0.22 | 19.11  | 20.94 |  83.75   |   20.94   |    83.75     |   0.00   | 44.27 | 691.22 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  20.00  | 0.23 | 16.24  | 24.63 |  98.53   |   24.63   |    98.53     |   0.00   | 50.03 | 793.15 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  26.47  | 0.18 | 23.50  | 17.02 |  68.09   |   17.02   |    68.09     |   0.01   | 37.79 | 583.19 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  23.49  | 0.17 | 19.57  | 20.45 |  81.79   |   20.45   |    81.79     |   0.01   | 42.57 | 662.09 |

