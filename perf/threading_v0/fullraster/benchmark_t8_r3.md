# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  6.78   | 0.19 |  3.01  | 132.69 |  530.75  |  132.69   |    530.75    |   0.01   | 147.58 | 946.91 |
| tri6_nodal_grey                                         |  10.60  | 0.23 |  7.81  | 51.22 |  204.87  |   51.22   |    204.87    |   0.01   | 94.37 | 1083.73 |
| quad4ibi_nodal_grey                                     |  8.01   | 0.21 |  5.09  | 78.73 |  314.91  |   78.73   |    314.91    |   0.00   | 124.99 | 1071.62 |
| quad4newton_nodal_grey                                  |  8.56   | 0.24 |  5.87  | 68.18 |  272.71  |   68.18   |    272.71    |   0.00   | 116.85 | 942.35 |
| quad8_nodal_grey                                        |  9.89   | 0.25 |  7.26  | 55.12 |  220.47  |   55.12   |    220.47    |   0.00   | 101.14 | 1570.27 |
| quad9_nodal_grey                                        |  10.14  | 0.22 |  7.58  | 52.78 |  211.12  |   52.78   |    211.12    |   0.00   | 98.64 | 1715.01 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  10.01  | 0.18 |  4.08  | 98.05 |  392.22  |   98.05   |    392.22    |   0.01   | 99.92 | 581.42 |
| tri6_nodal_rgb                                          |  11.91  | 0.18 |  8.26  | 48.45 |  193.81  |   48.45   |    193.81    |   0.01   | 83.97 | 943.97 |
| quad4ibi_nodal_rgb                                      |  10.19  | 0.25 |  6.57  | 60.87 |  243.49  |   60.87   |    243.49    |   0.00   | 98.12 | 768.34 |
| quad4newton_nodal_rgb                                   |  10.65  | 0.23 |  7.04  | 56.79 |  227.16  |   56.79   |    227.16    |   0.00   | 93.92 | 721.72 |
| quad8_nodal_rgb                                         |  11.63  | 0.21 |  8.04  | 49.77 |  199.07  |   49.77   |    199.07    |   0.00   | 85.98 | 1303.19 |
| quad9_nodal_rgb                                         |  12.91  | 0.24 |  9.25  | 43.23 |  172.90  |   43.23   |    172.90    |   0.00   | 77.45 | 1301.46 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  8.75   | 0.17 |  5.40  | 74.08 |  296.34  |   74.08   |    296.34    |   0.01   | 114.37 | 684.33 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  11.53  | 0.18 |  8.78  | 45.75 |  182.99  |   45.75   |    182.99    |   0.01   | 86.88 | 497.89 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  11.27  | 0.17 |  8.12  | 49.26 |  197.06  |   49.26   |    197.06    |   0.01   | 88.76 | 510.24 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  9.22   | 0.14 |  6.72  | 59.53 |  238.11  |   59.53   |    238.11    |   0.01   | 108.52 | 653.59 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  11.30  | 0.17 |  8.43  | 47.44 |  189.76  |   47.44   |    189.76    |   0.01   | 88.48 | 506.96 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  10.74  | 0.19 |  7.89  | 50.68 |  202.72  |   50.68   |    202.72    |   0.01   | 93.14 | 533.92 |
| tri3_tex8_grey_quintic_bspline_direct                   |  16.05  | 0.18 | 12.44  | 32.24 |  128.95  |   32.24   |    128.95    |   0.01   | 62.29 | 337.92 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  12.35  | 0.17 |  8.39  | 47.71 |  190.84  |   47.71   |    190.84    |   0.01   | 80.97 | 455.03 |
| tri6_tex8_grey_linear_direct                            |  11.73  | 0.23 |  8.85  | 45.18 |  180.72  |   45.18   |    180.72    |   0.01   | 85.28 | 960.40 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  17.01  | 0.23 | 14.16  | 28.24 |  112.96  |   28.24   |    112.96    |   0.01   | 58.78 | 629.20 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  14.90  | 0.19 | 11.95  | 33.47 |  133.87  |   33.47   |    133.87    |   0.01   | 67.13 | 729.22 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  15.05  | 0.22 | 11.94  | 33.50 |  134.00  |   33.50   |    134.00    |   0.01   | 66.46 | 727.32 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  17.76  | 0.25 | 13.95  | 28.67 |  114.66  |   28.67   |    114.66    |   0.01   | 56.55 | 617.08 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  14.23  | 0.26 | 11.22  | 35.65 |  142.60  |   35.65   |    142.60    |   0.01   | 70.26 | 772.15 |
| tri6_tex8_grey_quintic_bspline_direct                   |  22.44  | 0.22 | 18.87  | 21.20 |  84.79   |   21.20   |    84.79     |   0.01   | 44.57 | 468.95 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  17.63  | 0.26 | 14.86  | 26.94 |  107.75  |   26.94   |    107.75    |   0.01   | 56.79 | 610.18 |
| quad4ibi_tex8_grey_linear_direct                        |  9.44   | 0.32 |  6.72  | 59.49 |  237.96  |   59.49   |    237.96    |   0.00   | 105.98 | 836.90 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  14.46  | 0.32 | 11.41  | 35.07 |  140.30  |   35.07   |    140.30    |   0.00   | 69.20 | 506.81 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  14.19  | 0.20 | 11.35  | 35.25 |  141.01  |   35.25   |    141.01    |   0.00   | 70.49 | 514.43 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  13.88  | 0.22 | 11.13  | 35.95 |  143.79  |   35.95   |    143.79    |   0.00   | 72.04 | 529.62 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  16.36  | 0.29 | 12.92  | 31.01 |  124.03  |   31.01   |    124.03    |   0.00   | 61.12 | 441.43 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  13.43  | 0.19 | 10.75  | 37.22 |  148.89  |   37.22   |    148.89    |   0.01   | 74.44 | 554.14 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  21.27  | 0.31 | 18.05  | 22.16 |  88.63   |   22.16   |    88.63     |   0.00   | 47.02 | 327.54 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  16.83  | 0.31 | 14.21  | 28.14 |  112.56  |   28.14   |    112.56    |   0.00   | 59.43 | 423.56 |
| quad4newton_tex8_grey_linear_direct                     |  10.60  | 0.22 |  7.38  | 54.23 |  216.94  |   54.23   |    216.94    |   0.00   | 94.35 | 722.87 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  15.40  | 0.24 | 11.92  | 33.55 |  134.20  |   33.55   |    134.20    |   0.00   | 64.97 | 492.11 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  13.37  | 0.26 | 10.46  | 38.23 |  152.92  |   38.23   |    152.92    |   0.00   | 74.82 | 564.98 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  13.27  | 0.28 |  9.77  | 40.98 |  163.94  |   40.98   |    163.94    |   0.00   | 75.35 | 561.35 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  16.12  | 0.26 | 12.93  | 30.94 |  123.76  |   30.94   |    123.76    |   0.00   | 62.02 | 450.67 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  13.13  | 0.28 | 10.20  | 39.23 |  156.93  |   39.23   |    156.93    |   0.00   | 76.18 | 562.58 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  20.80  | 0.23 | 18.26  | 21.91 |  87.63   |   21.91   |    87.63     |   0.00   | 48.09 | 336.07 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  15.07  | 0.22 | 12.27  | 32.60 |  130.39  |   32.60   |    130.39    |   0.00   | 66.39 | 481.04 |
| quad8_tex8_grey_linear_direct                           |  12.19  | 0.24 |  9.34  | 42.81 |  171.25  |   42.81   |    171.25    |   0.00   | 82.05 | 1235.90 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  17.05  | 0.22 | 14.13  | 28.30 |  113.22  |   28.30   |    113.22    |   0.00   | 58.66 | 843.54 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  14.79  | 0.23 | 12.32  | 32.48 |  129.93  |   32.48   |    129.93    |   0.00   | 67.63 | 993.53 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  14.59  | 0.22 | 12.03  | 33.25 |  133.02  |   33.25   |    133.02    |   0.00   | 68.56 | 996.27 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  17.42  | 0.24 | 14.09  | 28.39 |  113.58  |   28.39   |    113.58    |   0.00   | 57.41 | 851.36 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  15.62  | 0.24 | 12.88  | 31.05 |  124.21  |   31.05   |    124.21    |   0.00   | 64.02 | 921.40 |
| quad8_tex8_grey_quintic_bspline_direct                  |  22.18  | 0.20 | 19.28  | 20.75 |  83.00   |   20.75   |    83.00     |   0.01   | 45.08 | 628.63 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  16.71  | 0.25 | 13.99  | 28.58 |  114.34  |   28.58   |    114.34    |   0.00   | 59.85 | 853.11 |
| quad9_tex8_grey_linear_direct                           |  12.14  | 0.21 |  9.46  | 42.28 |  169.13  |   42.28   |    169.13    |   0.00   | 82.36 | 1379.10 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  16.47  | 0.17 | 13.31  | 30.07 |  120.27  |   30.07   |    120.27    |   0.01   | 60.75 | 981.12 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  16.01  | 0.30 | 13.07  | 30.61 |  122.45  |   30.61   |    122.45    |   0.00   | 62.45 | 1018.62 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  14.87  | 0.22 | 11.53  | 34.70 |  138.78  |   34.70   |    138.78    |   0.00   | 67.24 | 1096.52 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  17.99  | 0.32 | 14.69  | 27.24 |  108.97  |   27.24   |    108.97    |   0.00   | 55.60 | 888.58 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  14.84  | 0.22 | 11.77  | 33.99 |  135.95  |   33.99   |    135.95    |   0.00   | 67.37 | 1124.57 |
| quad9_tex8_grey_quintic_bspline_direct                  |  22.14  | 0.24 | 19.40  | 20.62 |  82.48   |   20.62   |    82.48     |   0.00   | 45.16 | 705.48 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  18.89  | 0.28 | 15.53  | 25.75 |  103.01  |   25.75   |    103.01    |   0.00   | 52.94 | 838.93 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  10.75  | 0.19 |  6.89  | 58.05 |  232.22  |   58.05   |    232.22    |   0.01   | 92.99 | 534.21 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  14.50  | 0.17 | 10.67  | 37.48 |  149.93  |   37.48   |    149.93    |   0.01   | 68.96 | 376.34 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  16.15  | 0.19 | 10.63  | 37.63 |  150.53  |   37.63   |    150.53    |   0.01   | 61.93 | 336.01 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  16.38  | 0.17 | 11.95  | 33.49 |  133.94  |   33.49   |    133.94    |   0.01   | 61.09 | 327.61 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  18.40  | 0.15 | 14.69  | 27.23 |  108.93  |   27.23   |    108.93    |   0.01   | 54.41 | 290.88 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  16.05  | 0.16 | 11.92  | 33.57 |  134.26  |   33.57   |    134.26    |   0.01   | 62.34 | 335.81 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  23.76  | 0.17 | 19.70  | 20.30 |  81.21   |   20.30   |    81.21     |   0.01   | 42.09 | 219.15 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  19.79  | 0.21 | 15.15  | 26.41 |  105.66  |   26.41   |    105.66    |   0.01   | 50.54 | 268.14 |
| tri6_tex8_rgb_linear_direct                             |  16.11  | 0.19 | 11.59  | 34.52 |  138.08  |   34.52   |    138.08    |   0.01   | 62.06 | 666.62 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  21.09  | 0.19 | 17.25  | 23.19 |  92.77   |   23.19   |    92.77     |   0.01   | 47.43 | 500.36 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  20.70  | 0.16 | 16.60  | 24.10 |  96.41   |   24.10   |    96.41     |   0.01   | 48.31 | 506.30 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.67  | 0.18 | 17.25  | 23.19 |  92.76   |   23.19   |    92.76     |   0.01   | 48.38 | 507.00 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  21.81  | 0.18 | 17.16  | 23.33 |  93.31   |   23.33   |    93.31     |   0.01   | 45.85 | 500.19 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  19.84  | 0.18 | 15.10  | 26.51 |  106.05  |   26.51   |    106.05    |   0.01   | 50.40 | 533.44 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  27.42  | 0.18 | 22.88  | 17.48 |  69.93   |   17.48   |    69.93     |   0.01   | 36.47 | 377.88 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  22.48  | 0.18 | 19.31  | 20.71 |  82.84   |   20.71   |    82.84     |   0.01   | 44.50 | 462.30 |
| quad4ibi_tex8_rgb_linear_direct                         |  11.78  | 0.22 |  7.79  | 51.34 |  205.35  |   51.34   |    205.35    |   0.00   | 84.89 | 655.45 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  19.21  | 0.23 | 14.84  | 26.95 |  107.82  |   26.95   |    107.82    |   0.00   | 52.06 | 371.89 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  17.58  | 0.23 | 13.90  | 28.77 |  115.07  |   28.77   |    115.07    |   0.00   | 56.90 | 407.39 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  17.20  | 0.28 | 13.06  | 30.63 |  122.51  |   30.63   |    122.51    |   0.00   | 58.18 | 417.35 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  22.70  | 0.17 | 18.74  | 21.35 |  85.38   |   21.35   |    85.38     |   0.01   | 44.06 | 305.38 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  16.68  | 0.23 | 13.15  | 30.42 |  121.67  |   30.42   |    121.67    |   0.00   | 59.96 | 433.32 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  28.27  | 0.27 | 24.34  | 16.43 |  65.73   |   16.43   |    65.73     |   0.00   | 35.37 | 241.42 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  21.83  | 0.20 | 17.84  | 22.48 |  89.93   |   22.48   |    89.93     |   0.01   | 45.90 | 319.01 |
| quad4newton_tex8_rgb_linear_direct                      |  13.69  | 0.20 |  9.97  | 40.12 |  160.50  |   40.12   |    160.50    |   0.01   | 73.05 | 541.01 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  19.94  | 0.23 | 15.85  | 25.24 |  100.96  |   25.24   |    100.96    |   0.00   | 50.15 | 352.46 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  19.26  | 0.19 | 15.64  | 25.58 |  102.32  |   25.58   |    102.32    |   0.01   | 51.93 | 364.99 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  18.37  | 0.19 | 14.65  | 27.31 |  109.23  |   27.31   |    109.23    |   0.01   | 54.45 | 386.11 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  21.39  | 0.18 | 17.44  | 22.95 |  91.79   |   22.95   |    91.79     |   0.01   | 46.77 | 328.04 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  18.03  | 0.19 | 14.11  | 28.35 |  113.38  |   28.35   |    113.38    |   0.01   | 55.48 | 392.48 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  24.87  | 0.21 | 21.31  | 18.77 |  75.08   |   18.77   |    75.08     |   0.00   | 40.24 | 276.76 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  21.82  | 0.24 | 17.80  | 22.48 |  89.91   |   22.48   |    89.91     |   0.00   | 45.83 | 318.24 |
| quad8_tex8_rgb_linear_direct                            |  14.43  | 0.18 | 11.19  | 35.74 |  142.95  |   35.74   |    142.95    |   0.01   | 69.32 | 1009.05 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  21.67  | 0.22 | 17.96  | 22.27 |  89.06   |   22.27   |    89.06     |   0.00   | 46.14 | 642.55 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  19.76  | 0.21 | 16.16  | 24.75 |  99.00   |   24.75   |    99.00     |   0.00   | 50.63 | 712.98 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  21.56  | 0.20 | 17.32  | 23.11 |  92.43   |   23.11   |    92.43     |   0.00   | 46.39 | 645.92 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  22.39  | 0.19 | 18.64  | 21.46 |  85.86   |   21.46   |    85.86     |   0.01   | 44.67 | 623.57 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  19.01  | 0.21 | 14.92  | 26.82 |  107.27  |   26.82   |    107.27    |   0.00   | 52.60 | 752.97 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  26.57  | 0.24 | 22.83  | 17.52 |  70.09   |   17.52   |    70.09     |   0.00   | 37.64 | 518.84 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  22.63  | 0.23 | 18.92  | 21.15 |  84.59   |   21.15   |    84.59     |   0.00   | 44.22 | 617.98 |
| quad9_tex8_rgb_linear_direct                            |  15.68  | 0.15 | 11.72  | 34.14 |  136.56  |   34.14   |    136.56    |   0.01   | 63.79 | 1032.14 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  21.91  | 0.19 | 18.56  | 21.56 |  86.23   |   21.56   |    86.23     |   0.01   | 45.64 | 713.62 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  20.77  | 0.21 | 16.80  | 23.81 |  95.25   |   23.81   |    95.25     |   0.00   | 48.16 | 755.96 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  20.53  | 0.26 | 16.94  | 23.61 |  94.43   |   23.61   |    94.43     |   0.00   | 48.72 | 770.92 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  22.65  | 0.22 | 19.58  | 20.43 |  81.73   |   20.43   |    81.73     |   0.00   | 44.15 | 687.78 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  19.93  | 0.23 | 16.30  | 24.53 |  98.14   |   24.53   |    98.14     |   0.00   | 50.18 | 792.14 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  27.64  | 0.26 | 23.20  | 17.24 |  68.96   |   17.24   |    68.96     |   0.00   | 36.23 | 559.28 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  23.01  | 0.25 | 19.20  | 20.84 |  83.35   |   20.84   |    83.35     |   0.00   | 43.46 | 678.04 |

