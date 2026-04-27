# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  7.87   | 0.19 |  3.73  | 107.24 |  428.95  |  107.24   |    428.95    |   0.01   | 127.08 | 804.64 |
| tri6_nodal_grey                                         |  13.90  | 0.24 | 10.98  | 36.45 |  145.79  |   36.45   |    145.79    |   0.01   | 71.96 | 790.13 |
| quad4ibi_nodal_grey                                     |  10.36  | 0.26 |  7.52  | 53.16 |  212.64  |   53.16   |    212.64    |   0.00   | 96.54 | 741.86 |
| quad4newton_nodal_grey                                  |  11.72  | 0.21 |  8.71  | 45.90 |  183.61  |   45.90   |    183.61    |   0.00   | 85.47 | 660.63 |
| quad8_nodal_grey                                        |  13.68  | 0.25 | 10.89  | 36.73 |  146.91  |   36.73   |    146.91    |   0.00   | 73.09 | 1071.10 |
| quad9_nodal_grey                                        |  13.69  | 0.25 | 10.69  | 37.41 |  149.64  |   37.41   |    149.64    |   0.00   | 73.10 | 1241.10 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  10.15  | 0.23 |  5.00  | 79.99 |  319.95  |   79.99   |    319.95    |   0.01   | 98.71 | 572.11 |
| tri6_nodal_rgb                                          |  17.93  | 0.20 | 12.36  | 32.44 |  129.75  |   32.44   |    129.75    |   0.01   | 55.77 | 596.71 |
| quad4ibi_nodal_rgb                                      |  13.32  | 0.18 |  9.45  | 42.35 |  169.40  |   42.35   |    169.40    |   0.01   | 75.06 | 557.18 |
| quad4newton_nodal_rgb                                   |  13.96  | 0.21 |  9.73  | 41.12 |  164.48  |   41.12   |    164.48    |   0.00   | 71.63 | 535.25 |
| quad8_nodal_rgb                                         |  15.44  | 0.20 | 11.64  | 34.38 |  137.51  |   34.38   |    137.51    |   0.00   | 64.76 | 944.10 |
| quad9_nodal_rgb                                         |  16.00  | 0.22 | 12.31  | 32.50 |  130.01  |   32.50   |    130.01    |   0.00   | 62.51 | 1015.47 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  10.33  | 0.20 |  7.36  | 54.34 |  217.35  |   54.34   |    217.35    |   0.01   | 96.85 | 568.43 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  17.42  | 0.16 | 14.50  | 27.58 |  110.32  |   27.58   |    110.32    |   0.01   | 57.42 | 305.81 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  14.95  | 0.16 | 12.21  | 32.77 |  131.08  |   32.77   |    131.08    |   0.01   | 66.87 | 363.08 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  14.96  | 0.16 | 12.06  | 33.16 |  132.64  |   33.16   |    132.64    |   0.01   | 66.84 | 362.02 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  19.54  | 0.19 | 16.04  | 24.98 |  99.93   |   24.98   |    99.93     |   0.01   | 51.44 | 271.21 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  14.82  | 0.19 | 12.11  | 33.03 |  132.14  |   33.03   |    132.14    |   0.01   | 67.46 | 370.37 |
| tri3_tex8_grey_quintic_bspline_direct                   |  26.36  | 0.18 | 23.40  | 17.10 |  68.38   |   17.10   |    68.38     |   0.01   | 37.93 | 195.52 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  17.89  | 0.21 | 14.97  | 26.72 |  106.89  |   26.72   |    106.89    |   0.01   | 55.91 | 299.31 |
| tri6_tex8_grey_linear_direct                            |  16.20  | 0.19 | 13.53  | 29.57 |  118.28  |   29.57   |    118.28    |   0.01   | 61.71 | 666.93 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  23.90  | 0.26 | 20.72  | 19.31 |  77.23   |   19.31   |    77.23     |   0.01   | 41.84 | 434.30 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  22.15  | 0.21 | 18.55  | 21.56 |  86.24   |   21.56   |    86.24     |   0.01   | 45.15 | 474.69 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  21.36  | 0.21 | 18.48  | 21.65 |  86.60   |   21.65   |    86.60     |   0.01   | 46.82 | 489.94 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  25.40  | 0.27 | 22.75  | 17.61 |  70.43   |   17.61   |    70.43     |   0.01   | 39.38 | 405.32 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  21.55  | 0.23 | 18.70  | 21.39 |  85.56   |   21.39   |    85.56     |   0.01   | 46.42 | 484.29 |
| tri6_tex8_grey_quintic_bspline_direct                   |  31.68  | 0.23 | 28.58  | 14.00 |  55.99   |   14.00   |    55.99     |   0.01   | 31.57 | 322.13 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  24.91  | 0.23 | 21.85  | 18.31 |  73.23   |   18.31   |    73.23     |   0.01   | 40.14 | 417.84 |
| quad4ibi_tex8_grey_linear_direct                        |  12.34  | 0.33 |  9.35  | 42.80 |  171.20  |   42.80   |    171.20    |   0.00   | 81.03 | 602.47 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  22.53  | 0.22 | 18.82  | 21.27 |  85.07   |   21.27   |    85.07     |   0.00   | 44.39 | 308.49 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  20.47  | 0.24 | 17.58  | 22.76 |  91.03   |   22.76   |    91.03     |   0.00   | 48.86 | 341.71 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.33  | 0.24 | 17.42  | 22.96 |  91.83   |   22.96   |    91.83     |   0.00   | 49.20 | 345.25 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  25.19  | 0.26 | 22.45  | 17.82 |  71.27   |   17.82   |    71.27     |   0.00   | 39.70 | 272.38 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  20.60  | 0.21 | 17.67  | 22.64 |  90.56   |   22.64   |    90.56     |   0.00   | 48.54 | 339.34 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  29.25  | 0.26 | 26.56  | 15.06 |  60.25   |   15.06   |    60.25     |   0.00   | 34.19 | 232.60 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  25.34  | 0.23 | 22.47  | 17.80 |  71.21   |   17.80   |    71.21     |   0.00   | 39.47 | 270.87 |
| quad4newton_tex8_grey_linear_direct                     |  13.91  | 0.25 | 10.78  | 37.12 |  148.46  |   37.12   |    148.46    |   0.00   | 71.88 | 532.70 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  20.88  | 0.24 | 17.89  | 22.36 |  89.46   |   22.36   |    89.46     |   0.00   | 47.89 | 333.86 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  19.92  | 0.26 | 17.39  | 23.02 |  92.06   |   23.02   |    92.06     |   0.00   | 50.21 | 351.40 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  19.19  | 0.26 | 16.08  | 24.87 |  99.49   |   24.87   |    99.49     |   0.00   | 52.10 | 369.87 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  21.81  | 0.20 | 19.01  | 21.04 |  84.18   |   21.04   |    84.18     |   0.01   | 45.86 | 320.12 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  18.82  | 0.24 | 15.77  | 25.36 |  101.43  |   25.36   |    101.43    |   0.00   | 53.15 | 375.18 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  29.26  | 0.25 | 26.31  | 15.20 |  60.82   |   15.20   |    60.82     |   0.00   | 34.18 | 232.77 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  22.82  | 0.27 | 19.73  | 20.27 |  81.10   |   20.27   |    81.10     |   0.00   | 43.84 | 303.94 |
| quad8_tex8_grey_linear_direct                           |  18.53  | 0.24 | 14.31  | 28.06 |  112.24  |   28.06   |    112.24    |   0.00   | 54.07 | 773.36 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  23.93  | 0.30 | 20.31  | 19.70 |  78.79   |   19.70   |    78.79     |   0.00   | 41.81 | 577.83 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  21.46  | 0.27 | 18.85  | 21.22 |  84.90   |   21.22   |    84.90     |   0.00   | 46.60 | 648.69 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  22.11  | 0.27 | 18.61  | 21.49 |  85.96   |   21.49   |    85.96     |   0.00   | 45.24 | 631.71 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  24.76  | 0.28 | 21.68  | 18.45 |  73.81   |   18.45   |    73.81     |   0.00   | 40.40 | 558.18 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  21.00  | 0.24 | 18.23  | 21.94 |  87.77   |   21.94   |    87.77     |   0.00   | 47.63 | 664.72 |
| quad8_tex8_grey_quintic_bspline_direct                  |  32.00  | 0.25 | 28.98  | 13.80 |  55.21   |   13.80   |    55.21     |   0.00   | 31.25 | 424.10 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  25.37  | 0.30 | 21.86  | 18.30 |  73.20   |   18.30   |    73.20     |   0.00   | 39.43 | 544.85 |
| quad9_tex8_grey_linear_direct                           |  15.92  | 0.23 | 13.09  | 30.57 |  122.26  |   30.57   |    122.26    |   0.00   | 62.83 | 1012.31 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  24.30  | 0.32 | 20.63  | 19.39 |  77.56   |   19.39   |    77.56     |   0.00   | 41.19 | 638.71 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  22.82  | 0.25 | 19.08  | 20.96 |  83.85   |   20.96   |    83.85     |   0.00   | 43.85 | 686.75 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  21.36  | 0.27 | 18.60  | 21.51 |  86.03   |   21.51   |    86.03     |   0.00   | 46.82 | 739.06 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  25.50  | 0.27 | 22.49  | 17.79 |  71.14   |   17.79   |    71.14     |   0.00   | 39.22 | 609.46 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  21.12  | 0.33 | 18.19  | 21.99 |  87.95   |   21.99   |    87.95     |   0.00   | 47.34 | 741.92 |
| quad9_tex8_grey_quintic_bspline_direct                  |  31.97  | 0.25 | 29.12  | 13.74 |  54.94   |   13.74   |    54.94     |   0.00   | 31.27 | 475.90 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  25.21  | 0.30 | 22.27  | 17.96 |  71.85   |   17.96   |    71.85     |   0.00   | 39.67 | 615.04 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  13.61  | 0.15 |  9.38  | 42.66 |  170.64  |   42.66   |    170.64    |   0.01   | 73.55 | 408.37 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  22.50  | 0.16 | 18.52  | 21.60 |  86.39   |   21.60   |    86.39     |   0.01   | 44.44 | 232.11 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  20.25  | 0.14 | 16.50  | 24.25 |  96.99   |   24.25   |    96.99     |   0.01   | 49.39 | 261.18 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.84  | 0.16 | 16.94  | 23.61 |  94.44   |   23.61   |    94.44     |   0.01   | 47.99 | 252.23 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  26.05  | 0.16 | 21.50  | 18.61 |  74.44   |   18.61   |    74.44     |   0.01   | 38.39 | 198.22 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  20.47  | 0.15 | 16.74  | 23.89 |  95.58   |   23.89   |    95.58     |   0.01   | 48.86 | 256.13 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  33.40  | 0.18 | 28.63  | 13.97 |  55.88   |   13.97   |    55.88     |   0.01   | 29.95 | 151.61 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  25.95  | 0.14 | 21.91  | 18.25 |  73.01   |   18.25   |    73.01     |   0.01   | 38.54 | 199.66 |
| tri6_tex8_rgb_linear_direct                             |  23.61  | 0.25 | 18.77  | 21.31 |  85.22   |   21.31   |    85.22     |   0.01   | 42.35 | 439.99 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  31.02  | 0.16 | 27.49  | 14.55 |  58.21   |   14.55   |    58.21     |   0.01   | 32.24 | 327.67 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  28.29  | 0.22 | 23.69  | 16.88 |  67.53   |   16.88   |    67.53     |   0.01   | 35.38 | 361.63 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  27.27  | 0.17 | 23.23  | 17.22 |  68.88   |   17.22   |    68.88     |   0.01   | 36.67 | 375.64 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  32.79  | 0.19 | 28.79  | 13.90 |  55.58   |   13.90   |    55.58     |   0.01   | 30.50 | 310.34 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  27.73  | 0.19 | 23.55  | 16.98 |  67.93   |   16.98   |    67.93     |   0.01   | 36.06 | 369.40 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  39.77  | 0.17 | 36.09  | 11.08 |  44.33   |   11.08   |    44.33     |   0.01   | 25.15 | 252.63 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  32.01  | 0.17 | 28.23  | 14.17 |  56.69   |   14.17   |    56.69     |   0.01   | 31.24 | 316.81 |
| quad4ibi_tex8_rgb_linear_direct                         |  15.85  | 0.23 | 11.75  | 34.04 |  136.17  |   34.04   |    136.17    |   0.00   | 63.08 | 452.81 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  25.10  | 0.22 | 21.48  | 18.62 |  74.48   |   18.62   |    74.48     |   0.00   | 39.83 | 273.84 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  26.08  | 0.20 | 22.40  | 17.86 |  71.44   |   17.86   |    71.44     |   0.01   | 38.34 | 263.00 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  26.70  | 0.19 | 23.23  | 17.23 |  68.90   |   17.23   |    68.90     |   0.01   | 37.46 | 256.35 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  32.18  | 0.21 | 28.21  | 14.18 |  56.73   |   14.18   |    56.73     |   0.00   | 31.08 | 214.71 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  27.74  | 0.20 | 23.43  | 17.08 |  68.31   |   17.08   |    68.31     |   0.01   | 36.05 | 246.36 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  40.01  | 0.26 | 36.41  | 10.99 |  43.95   |   10.99   |    43.95     |   0.00   | 24.99 | 167.11 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  32.48  | 0.23 | 28.96  | 13.81 |  55.25   |   13.81   |    55.25     |   0.00   | 30.79 | 208.34 |
| quad4newton_tex8_rgb_linear_direct                      |  22.19  | 0.18 | 17.59  | 22.75 |  91.01   |   22.75   |    91.01     |   0.01   | 45.07 | 323.87 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  27.07  | 0.20 | 23.34  | 17.14 |  68.55   |   17.14   |    68.55     |   0.01   | 36.94 | 252.67 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  25.29  | 0.22 | 21.58  | 18.54 |  74.15   |   18.54   |    74.15     |   0.00   | 39.55 | 274.11 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  24.50  | 0.26 | 20.89  | 19.15 |  76.60   |   19.15   |    76.60     |   0.00   | 40.82 | 282.79 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  29.22  | 0.20 | 25.63  | 15.61 |  62.43   |   15.61   |    62.43     |   0.01   | 34.22 | 233.69 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  25.75  | 0.21 | 21.61  | 18.51 |  74.03   |   18.51   |    74.03     |   0.00   | 38.84 | 266.67 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  37.39  | 0.17 | 33.16  | 12.07 |  48.26   |   12.07   |    48.26     |   0.01   | 26.75 | 180.08 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  29.82  | 0.20 | 26.00  | 15.39 |  61.54   |   15.39   |    61.54     |   0.00   | 33.53 | 227.84 |
| quad8_tex8_rgb_linear_direct                            |  21.65  | 0.21 | 17.89  | 22.36 |  89.45   |   22.36   |    89.45     |   0.00   | 46.18 | 645.72 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  28.96  | 0.20 | 25.12  | 15.92 |  63.69   |   15.92   |    63.69     |   0.00   | 34.54 | 470.71 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  27.56  | 0.23 | 23.53  | 17.00 |  68.02   |   17.00   |    68.02     |   0.00   | 36.28 | 498.60 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  26.97  | 0.22 | 23.29  | 17.17 |  68.70   |   17.17   |    68.70     |   0.00   | 37.08 | 507.25 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  33.15  | 0.23 | 28.88  | 13.85 |  55.41   |   13.85   |    55.41     |   0.00   | 30.17 | 407.84 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  28.08  | 0.27 | 23.64  | 16.92 |  67.68   |   16.92   |    67.68     |   0.00   | 35.61 | 485.50 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  39.02  | 0.23 | 35.11  | 11.39 |  45.57   |   11.39   |    45.57     |   0.00   | 25.63 | 343.03 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  31.57  | 0.24 | 27.49  | 14.55 |  58.20   |   14.55   |    58.20     |   0.00   | 31.67 | 429.21 |
| quad9_tex8_rgb_linear_direct                            |  22.63  | 0.22 | 18.61  | 21.49 |  85.97   |   21.49   |    85.97     |   0.00   | 44.19 | 689.15 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  29.98  | 0.21 | 25.96  | 15.41 |  61.66   |   15.41   |    61.66     |   0.00   | 33.36 | 512.29 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  27.55  | 0.21 | 23.94  | 16.71 |  66.85   |   16.71   |    66.85     |   0.00   | 36.30 | 560.57 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  28.08  | 0.17 | 23.21  | 17.23 |  68.94   |   17.23   |    68.94     |   0.01   | 35.65 | 549.26 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  31.73  | 0.26 | 27.64  | 14.47 |  57.89   |   14.47   |    57.89     |   0.00   | 31.51 | 479.63 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  27.76  | 0.18 | 23.94  | 16.71 |  66.84   |   16.71   |    66.84     |   0.01   | 36.02 | 555.20 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  39.16  | 0.24 | 35.37  | 11.31 |  45.24   |   11.31   |    45.24     |   0.00   | 25.53 | 384.75 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  33.08  | 0.21 | 28.08  | 14.25 |  56.99   |   14.25   |    56.99     |   0.00   | 30.25 | 461.11 |

