# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  14.80  | 3.95 |  4.80  | 83.36 |  333.44  |   86.27   |    345.06    |  51.82   | 67.58 | 461.30 |
| tri6_nodal_grey                                         |  35.87  | 8.32 | 18.77  | 21.32 |  85.28   |   21.91   |    87.63     |  24.61   | 27.88 | 333.39 |
| quad4ibi_nodal_grey                                     |  12.70  | 3.35 |  5.85  | 68.41 |  273.64  |   70.16   |    280.63    |  30.54   | 78.72 | 610.54 |
| quad4newton_nodal_grey                                  |  15.37  | 2.78 |  9.79  | 40.87 |  163.47  |   41.98   |    167.94    |  36.85   | 65.08 | 482.90 |
| quad8_nodal_grey                                        |  28.68  | 7.27 | 15.08  | 26.54 |  106.15  |   27.25   |    108.99    |  14.09   | 34.87 | 549.39 |
| quad9_nodal_grey                                        |  28.21  | 6.48 | 14.28  | 28.01 |  112.05  |   28.78   |    115.11    |  15.81   | 35.45 | 643.10 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  20.24  | 4.80 |  6.01  | 66.52 |  266.07  |   68.84   |    275.35    |  42.69   | 49.42 | 296.31 |
| tri6_nodal_rgb                                          |  39.93  | 9.89 | 17.76  | 22.54 |  90.14   |   23.16   |    92.62     |  20.71   | 25.04 | 311.23 |
| quad4ibi_nodal_rgb                                      |  15.97  | 3.60 |  7.40  | 54.05 |  216.21  |   55.42   |    221.68    |  28.46   | 62.62 | 494.41 |
| quad4newton_nodal_rgb                                   |  20.68  | 3.83 | 10.83  | 36.95 |  147.80  |   37.96   |    151.84    |  26.75   | 48.35 | 368.33 |
| quad8_nodal_rgb                                         |  32.52  | 7.31 | 16.72  | 23.92 |  95.67   |   24.56   |    98.25     |  14.01   | 30.75 | 498.49 |
| quad9_nodal_rgb                                         |  31.33  | 7.45 | 15.77  | 25.36 |  101.44  |   26.05   |    104.19    |  13.75   | 31.93 | 572.17 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  21.65  | 4.31 |  8.25  | 48.48 |  193.94  |   50.17   |    200.68    |  47.53   | 46.22 | 323.87 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  26.17  | 4.30 | 13.04  | 30.68 |  122.73  |   31.75   |    127.01    |  47.61   | 38.21 | 247.68 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  23.74  | 4.30 | 11.06  | 36.18 |  144.72  |   37.44   |    149.77    |  47.59   | 42.12 | 277.03 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  23.32  | 4.41 | 10.57  | 37.83 |  151.34  |   39.16   |    156.62    |  46.44   | 42.89 | 288.40 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  24.89  | 4.03 | 13.50  | 29.63 |  118.54  |   30.66   |    122.65    |  50.84   | 40.18 | 263.89 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  24.17  | 4.43 | 11.71  | 34.15 |  136.62  |   35.35   |    141.39    |  46.30   | 41.37 | 282.92 |
| tri3_tex8_grey_quintic_bspline_direct                   |  29.83  | 4.17 | 17.62  | 22.71 |  90.84   |   23.49   |    93.97     |  49.10   | 33.53 | 207.89 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  24.56  | 4.17 | 12.97  | 30.84 |  123.36  |   31.91   |    127.63    |  49.09   | 40.74 | 262.38 |
| tri6_tex8_grey_linear_direct                            |  51.41  | 9.22 | 20.78  | 19.25 |  77.01   |   19.79   |    79.15     |  22.21   | 19.45 | 305.44 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  54.99  | 9.34 | 23.70  | 16.88 |  67.51   |   17.34   |    69.38     |  21.94   | 18.19 | 281.19 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  54.95  | 9.54 | 22.29  | 17.94 |  71.78   |   18.44   |    73.76     |  21.52   | 18.20 | 288.56 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  54.33  | 9.72 | 21.47  | 18.63 |  74.53   |   19.15   |    76.59     |  21.14   | 18.41 | 279.69 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  54.13  | 9.13 | 24.05  | 16.63 |  66.54   |   17.09   |    68.38     |  22.42   | 18.48 | 281.30 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  52.15  | 9.42 | 23.36  | 17.13 |  68.50   |   17.60   |    70.39     |  21.80   | 19.21 | 292.79 |
| tri6_tex8_grey_quintic_bspline_direct                   |  62.11  | 8.72 | 30.48  | 13.12 |  52.49   |   13.49   |    53.95     |  23.50   | 16.10 | 229.41 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  57.18  | 8.58 | 25.71  | 15.57 |  62.29   |   16.00   |    64.01     |  23.86   | 17.49 | 270.13 |
| quad4ibi_tex8_grey_linear_direct                        |  18.56  | 3.45 |  7.24  | 55.28 |  221.13  |   56.71   |    226.83    |  29.71   | 53.89 | 560.87 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  20.30  | 2.91 | 12.68  | 31.54 |  126.16  |   32.35   |    129.41    |  35.20   | 49.33 | 377.49 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  20.19  | 3.02 | 12.92  | 30.96 |  123.86  |   31.76   |    127.05    |  33.92   | 49.54 | 382.17 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.23  | 2.95 | 12.28  | 32.59 |  130.35  |   33.42   |    133.68    |  34.81   | 49.43 | 389.87 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  23.18  | 2.86 | 15.27  | 26.20 |  104.79  |   26.87   |    107.47    |  35.84   | 43.14 | 334.86 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  22.43  | 2.80 | 12.75  | 31.37 |  125.48  |   32.17   |    128.70    |  36.51   | 44.59 | 396.58 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  26.13  | 3.07 | 18.71  | 21.38 |  85.51   |   21.93   |    87.72     |  33.38   | 38.26 | 283.66 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  23.27  | 3.10 | 15.10  | 26.49 |  105.97  |   27.18   |    108.70    |  33.01   | 42.98 | 333.72 |
| quad4newton_tex8_grey_linear_direct                     |  29.05  | 3.11 | 12.23  | 32.71 |  130.85  |   33.61   |    134.46    |  32.93   | 34.42 | 404.47 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  33.98  | 3.07 | 16.26  | 24.60 |  98.39   |   25.27   |    101.08    |  33.41   | 29.43 | 314.98 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  33.00  | 2.83 | 14.62  | 27.35 |  109.41  |   28.10   |    112.41    |  36.15   | 30.32 | 341.88 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  33.02  | 2.76 | 15.38  | 26.02 |  104.06  |   26.73   |    106.91    |  37.12   | 30.29 | 328.54 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  35.10  | 2.87 | 17.96  | 22.28 |  89.11   |   22.89   |    91.54     |  35.67   | 28.49 | 294.38 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  33.25  | 2.91 | 13.81  | 29.16 |  116.63  |   29.96   |    119.84    |  35.23   | 30.08 | 338.10 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  39.66  | 3.12 | 21.85  | 18.31 |  73.24   |   18.81   |    75.24     |  32.92   | 25.23 | 250.25 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  35.12  | 3.17 | 16.27  | 24.63 |  98.54   |   25.31   |    101.22    |  32.25   | 28.47 | 315.67 |
| quad8_tex8_grey_linear_direct                           |  38.79  | 6.23 | 17.47  | 22.89 |  91.57   |   23.51   |    94.03     |  16.44   | 25.79 | 504.97 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  44.27  | 6.54 | 22.48  | 17.79 |  71.18   |   18.27   |    73.10     |  15.68   | 22.59 | 425.67 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  42.47  | 6.28 | 20.81  | 19.22 |  76.89   |   19.74   |    78.94     |  16.31   | 23.55 | 464.33 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.02  | 6.97 | 20.50  | 19.51 |  78.05   |   20.04   |    80.15     |  14.70   | 23.24 | 447.35 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  45.11  | 6.24 | 23.46  | 17.05 |  68.20   |   17.51   |    70.03     |  16.41   | 22.17 | 411.34 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  42.28  | 6.37 | 20.70  | 19.32 |  77.29   |   19.84   |    79.37     |  16.08   | 23.65 | 461.05 |
| quad8_tex8_grey_quintic_bspline_direct                  |  50.25  | 6.44 | 27.61  | 14.49 |  57.95   |   14.87   |    59.50     |  15.91   | 19.90 | 364.82 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  45.51  | 6.40 | 22.40  | 17.87 |  71.49   |   18.35   |    73.41     |  16.00   | 21.98 | 415.28 |
| quad9_tex8_grey_linear_direct                           |  39.62  | 7.00 | 15.69  | 25.50 |  102.01  |   26.19   |    104.77    |  14.63   | 25.24 | 604.93 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  44.18  | 6.47 | 20.45  | 19.56 |  78.25   |   20.10   |    80.40     |  15.82   | 22.64 | 514.42 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  43.53  | 6.70 | 18.80  | 21.28 |  85.13   |   21.86   |    87.44     |  15.31   | 22.97 | 524.06 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.32  | 7.33 | 19.21  | 20.82 |  83.28   |   21.38   |    85.53     |  13.97   | 23.08 | 521.63 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  44.35  | 6.69 | 21.09  | 18.97 |  75.88   |   19.49   |    77.94     |  15.32   | 22.57 | 496.38 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  45.47  | 6.67 | 20.70  | 19.33 |  77.31   |   19.85   |    79.41     |  15.36   | 21.99 | 503.09 |
| quad9_tex8_grey_quintic_bspline_direct                  |  49.47  | 6.59 | 25.29  | 15.83 |  63.32   |   16.26   |    65.03     |  15.54   | 20.22 | 433.30 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  45.55  | 7.05 | 21.99  | 18.19 |  72.75   |   18.68   |    74.73     |  14.56   | 21.96 | 489.76 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  22.72  | 4.26 | 10.88  | 36.79 |  147.16  |   38.07   |    152.28    |  48.21   | 44.02 | 278.34 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  27.59  | 3.98 | 16.58  | 24.14 |  96.56   |   24.97   |    99.90     |  51.48   | 36.25 | 215.99 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  27.81  | 4.36 | 15.79  | 25.33 |  101.33  |   26.21   |    104.84    |  47.01   | 35.96 | 220.03 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  26.45  | 3.68 | 15.24  | 26.24 |  104.97  |   27.15   |    108.60    |  55.71   | 37.81 | 228.42 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  30.49  | 4.11 | 18.55  | 21.58 |  86.30   |   22.33   |    89.31     |  50.00   | 32.80 | 192.50 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  26.64  | 3.70 | 15.36  | 26.05 |  104.19  |   26.95   |    107.81    |  55.32   | 37.55 | 226.05 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  34.64  | 4.06 | 23.05  | 17.35 |  69.40   |   17.95   |    71.80     |  50.43   | 28.87 | 162.81 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  30.32  | 3.71 | 18.95  | 21.11 |  84.43   |   21.84   |    87.37     |  55.21   | 32.99 | 191.45 |
| tri6_tex8_rgb_linear_direct                             |  55.81  | 9.47 | 24.66  | 16.22 |  64.90   |   16.67   |    66.68     |  21.62   | 17.92 | 267.12 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  62.54  | 9.43 | 27.64  | 14.48 |  57.92   |   14.88   |    59.52     |  21.73   | 15.99 | 233.08 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  61.71  | 9.76 | 28.88  | 13.86 |  55.46   |   14.25   |    56.99     |  21.03   | 16.21 | 239.39 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  59.29  | 9.97 | 26.08  | 15.34 |  61.35   |   15.76   |    63.04     |  20.53   | 16.87 | 246.92 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  62.26  | 9.39 | 29.66  | 13.49 |  53.95   |   13.86   |    55.45     |  21.81   | 16.07 | 229.09 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  61.28  | 10.46 | 28.67  | 13.95 |  55.81   |   14.34   |    57.35     |  19.58   | 16.32 | 243.89 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  68.09  | 9.31 | 34.68  | 11.53 |  46.14   |   11.85   |    47.42     |  21.99   | 14.69 | 204.91 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  64.17  | 9.83 | 29.89  | 13.38 |  53.54   |   13.75   |    55.02     |  20.83   | 15.59 | 238.56 |
| quad4ibi_tex8_rgb_linear_direct                         |  18.84  | 3.11 |  9.48  | 42.19 |  168.77  |   43.27   |    173.09    |  32.96   | 53.09 | 440.21 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  24.92  | 3.17 | 15.06  | 26.57 |  106.27  |   27.25   |    108.99    |  32.31   | 40.13 | 314.67 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  25.38  | 3.23 | 15.16  | 26.39 |  105.58  |   27.07   |    108.30    |  31.72   | 39.40 | 312.65 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  25.17  | 3.40 | 15.37  | 26.03 |  104.13  |   26.70   |    106.81    |  30.17   | 39.72 | 307.14 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  29.31  | 3.12 | 20.31  | 19.70 |  78.79   |   20.20   |    80.82     |  32.79   | 34.12 | 254.26 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  25.50  | 3.14 | 15.59  | 25.66 |  102.63  |   26.32   |    105.27    |  32.63   | 39.22 | 309.99 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  34.23  | 3.11 | 24.81  | 16.12 |  64.49   |   16.54   |    66.15     |  32.88   | 29.21 | 216.42 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  29.66  | 3.13 | 18.29  | 22.04 |  88.16   |   22.60   |    90.41     |  32.75   | 33.72 | 254.80 |
| quad4newton_tex8_rgb_linear_direct                      |  35.84  | 3.20 | 15.41  | 25.96 |  103.84  |   26.67   |    106.66    |  31.99   | 27.90 | 310.13 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  38.31  | 3.16 | 17.56  | 22.84 |  91.38   |   23.47   |    93.86     |  32.42   | 26.11 | 269.11 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  38.69  | 3.14 | 18.73  | 21.36 |  85.42   |   21.94   |    87.77     |  32.58   | 25.84 | 262.68 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  38.66  | 2.94 | 19.88  | 20.12 |  80.47   |   20.67   |    82.67     |  34.79   | 25.87 | 259.42 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  41.19  | 3.20 | 21.83  | 18.33 |  73.31   |   18.83   |    75.31     |  31.99   | 24.28 | 235.91 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  37.46  | 3.21 | 18.50  | 21.62 |  86.50   |   22.22   |    88.88     |  31.87   | 26.69 | 274.71 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  45.22  | 3.25 | 25.47  | 15.70 |  62.82   |   16.13   |    64.54     |  31.47   | 22.12 | 208.49 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  41.63  | 2.99 | 21.34  | 18.74 |  74.97   |   19.26   |    77.03     |  34.29   | 24.02 | 243.36 |
| quad8_tex8_rgb_linear_direct                            |  43.90  | 6.39 | 19.47  | 20.57 |  82.27   |   21.12   |    84.48     |  16.02   | 22.78 | 453.01 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  48.65  | 6.58 | 24.27  | 16.48 |  65.92   |   16.92   |    67.70     |  15.55   | 20.55 | 388.77 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.86  | 6.63 | 24.14  | 16.57 |  66.29   |   17.02   |    68.07     |  15.46   | 20.47 | 388.37 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  46.93  | 6.05 | 24.55  | 16.30 |  65.18   |   16.73   |    66.94     |  16.92   | 21.31 | 392.69 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  49.95  | 6.15 | 25.89  | 15.48 |  61.93   |   15.90   |    63.59     |  16.65   | 20.02 | 359.99 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  45.41  | 6.51 | 22.95  | 17.43 |  69.74   |   17.90   |    71.59     |  15.74   | 22.02 | 410.50 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  55.60  | 6.38 | 33.76  | 11.86 |  47.43   |   12.18   |    48.71     |  16.05   | 17.99 | 306.39 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  49.37  | 6.66 | 27.81  | 14.38 |  57.52   |   14.77   |    59.07     |  15.37   | 20.26 | 352.17 |
| quad9_tex8_rgb_linear_direct                            |  42.27  | 7.23 | 18.61  | 21.49 |  85.98   |   22.08   |    88.31     |  14.16   | 23.66 | 527.23 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  50.32  | 7.02 | 23.92  | 16.72 |  66.90   |   17.18   |    68.73     |  14.59   | 19.88 | 435.64 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  47.13  | 6.64 | 23.47  | 17.04 |  68.17   |   17.50   |    70.01     |  15.44   | 21.22 | 444.79 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.60  | 7.55 | 22.68  | 17.64 |  70.55   |   18.12   |    72.48     |  13.58   | 21.01 | 449.49 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  51.26  | 6.87 | 25.86  | 15.47 |  61.89   |   15.89   |    63.57     |  14.91   | 19.51 | 415.57 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  47.97  | 6.79 | 23.71  | 16.87 |  67.48   |   17.33   |    69.31     |  15.09   | 20.85 | 450.92 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  53.19  | 6.77 | 27.62  | 14.48 |  57.94   |   14.87   |    59.49     |  15.13   | 18.80 | 399.48 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  50.98  | 6.88 | 26.18  | 15.29 |  61.18   |   15.71   |    62.84     |  14.89   | 19.62 | 406.82 |

