# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  2.19   | 0.01 |  2.17  | 184.35 |  737.40  |  184.35   |    737.40    |   0.15   | 456.89 | 2197.25 |
| tri6_nodal_grey                                         |  9.37   | 0.02 |  9.34  | 42.81 |  171.24  |   42.81   |    171.24    |   0.13   | 106.78 | 1025.96 |
| quad4ibi_nodal_grey                                     |  5.57   | 0.01 |  5.54  | 72.23 |  288.94  |   72.23   |    288.94    |   0.08   | 179.39 | 1152.85 |
| quad4newton_nodal_grey                                  |  7.48   | 0.01 |  7.46  | 53.62 |  214.46  |   53.62   |    214.46    |   0.09   | 133.74 | 856.60 |
| quad8_nodal_grey                                        |  9.24   | 0.01 |  9.22  | 43.36 |  173.45  |   43.36   |    173.45    |   0.08   | 108.18 | 1385.53 |
| quad9_nodal_grey                                        |  9.42   | 0.01 |  9.40  | 42.57 |  170.29  |   42.57   |    170.29    |   0.08   | 106.16 | 1529.89 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  4.75   | 0.02 |  4.73  | 84.57 |  338.30  |   84.57   |    338.30    |   0.12   | 210.47 | 1012.04 |
| tri6_nodal_rgb                                          |  11.86  | 0.01 | 11.84  | 33.78 |  135.12  |   33.78   |    135.12    |   0.14   | 84.29 | 809.79 |
| quad4ibi_nodal_rgb                                      |  8.77   | 0.01 |  8.75  | 45.73 |  182.91  |   45.73   |    182.91    |   0.08   | 114.03 | 730.56 |
| quad4newton_nodal_rgb                                   |  9.83   | 0.01 |  9.81  | 40.76 |  163.04  |   40.76   |    163.04    |   0.07   | 101.69 | 651.31 |
| quad8_nodal_rgb                                         |  11.87  | 0.01 | 11.84  | 33.77 |  135.09  |   33.77   |    135.09    |   0.08   | 84.27 | 1079.39 |
| quad9_nodal_rgb                                         |  11.75  | 0.01 | 11.73  | 34.11 |  136.42  |   34.11   |    136.42    |   0.07   | 85.09 | 1226.32 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  5.44   | 0.01 |  5.42  | 73.74 |  294.94  |   73.74   |    294.94    |   0.16   | 183.70 | 882.68 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  12.60  | 0.01 | 12.58  | 31.79 |  127.16  |   31.79   |    127.16    |   0.16   | 79.34 | 381.02 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  9.47   | 0.02 |  9.45  | 42.35 |  169.38  |   42.35   |    169.38    |   0.13   | 105.64 | 507.36 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  9.77   | 0.01 |  9.75  | 41.03 |  164.11  |   41.03   |    164.11    |   0.16   | 102.33 | 491.48 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  13.89  | 0.01 | 13.87  | 28.84 |  115.36  |   28.84   |    115.36    |   0.16   | 71.99 | 345.74 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  9.70   | 0.01 |  9.68  | 41.34 |  165.38  |   41.34   |    165.38    |   0.14   | 103.07 | 495.04 |
| tri3_tex8_grey_quintic_bspline_direct                   |  20.49  | 0.01 | 20.47  | 19.54 |  78.17   |   19.54   |    78.17     |   0.15   | 48.80 | 234.34 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  13.92  | 0.01 | 13.90  | 28.78 |  115.11  |   28.78   |    115.11    |   0.16   | 71.84 | 344.98 |
| tri6_tex8_grey_linear_direct                            |  11.60  | 0.02 | 11.58  | 34.54 |  138.17  |   34.54   |    138.17    |   0.11   | 86.18 | 827.76 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  18.23  | 0.01 | 18.21  | 21.97 |  87.87   |   21.97   |    87.87     |   0.14   | 54.86 | 526.84 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  16.18  | 0.01 | 16.16  | 24.75 |  99.02   |   24.75   |    99.02     |   0.14   | 61.79 | 593.47 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  16.25  | 0.01 | 16.22  | 24.66 |  98.63   |   24.66   |    98.63     |   0.14   | 61.54 | 591.09 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  19.67  | 0.01 | 19.65  | 20.36 |  81.43   |   20.36   |    81.43     |   0.14   | 50.83 | 488.17 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  16.09  | 0.02 | 16.06  | 24.91 |  99.66   |   24.91   |    99.66     |   0.12   | 62.17 | 597.10 |
| tri6_tex8_grey_quintic_bspline_direct                   |  26.24  | 0.02 | 26.21  | 15.26 |  61.04   |   15.26   |    61.04     |   0.13   | 38.11 | 366.04 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  19.52  | 0.01 | 19.50  | 20.52 |  82.07   |   20.52   |    82.07     |   0.14   | 51.24 | 492.08 |
| quad4ibi_tex8_grey_linear_direct                        |  7.76   | 0.01 |  7.74  | 51.69 |  206.77  |   51.69   |    206.77    |   0.09   | 128.83 | 825.49 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  16.10  | 0.01 | 16.08  | 24.88 |  99.51   |   24.88   |    99.51     |   0.08   | 62.12 | 397.70 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  16.02  | 0.01 | 15.99  | 25.01 |  100.04  |   25.01   |    100.04    |   0.09   | 62.44 | 399.79 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  15.90  | 0.01 | 15.88  | 25.18 |  100.74  |   25.18   |    100.74    |   0.08   | 62.89 | 402.68 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  19.03  | 0.01 | 19.01  | 21.04 |  84.15   |   21.04   |    84.15     |   0.08   | 52.54 | 336.40 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  16.09  | 0.01 | 16.06  | 24.90 |  99.60   |   24.90   |    99.60     |   0.08   | 62.17 | 398.06 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  24.57  | 0.01 | 24.55  | 16.30 |  65.19   |   16.30   |    65.19     |   0.08   | 40.69 | 260.52 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  19.15  | 0.01 | 19.13  | 20.91 |  83.65   |   20.91   |    83.65     |   0.09   | 52.22 | 334.39 |
| quad4newton_tex8_grey_linear_direct                     |  9.36   | 0.01 |  9.34  | 42.83 |  171.31  |   42.83   |    171.31    |   0.08   | 106.86 | 684.34 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  15.98  | 0.01 | 15.95  | 25.07 |  100.29  |   25.07   |    100.29    |   0.09   | 62.59 | 400.81 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  14.11  | 0.01 | 14.09  | 28.40 |  113.59  |   28.40   |    113.59    |   0.09   | 70.86 | 453.89 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  14.28  | 0.01 | 14.26  | 28.04 |  112.17  |   28.04   |    112.17    |   0.09   | 70.01 | 448.31 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  17.52  | 0.01 | 17.49  | 22.87 |  91.47   |   22.87   |    91.47     |   0.09   | 57.09 | 365.57 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  14.37  | 0.01 | 14.34  | 27.89 |  111.55  |   27.89   |    111.55    |   0.08   | 69.60 | 445.69 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  24.33  | 0.01 | 24.31  | 16.46 |  65.83   |   16.46   |    65.83     |   0.09   | 41.11 | 263.19 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  17.37  | 0.01 | 17.35  | 23.05 |  92.20   |   23.05   |    92.20     |   0.08   | 57.56 | 368.51 |
| quad8_tex8_grey_linear_direct                           |  11.52  | 0.01 | 11.50  | 34.78 |  139.12  |   34.78   |    139.12    |   0.09   | 86.77 | 1111.59 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  18.07  | 0.01 | 18.05  | 22.17 |  88.66   |   22.17   |    88.66     |   0.09   | 55.34 | 708.82 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  16.27  | 0.01 | 16.25  | 24.62 |  98.47   |   24.62   |    98.47     |   0.09   | 61.47 | 787.22 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  16.02  | 0.01 | 16.01  | 24.99 |  99.96   |   24.99   |    99.96     |   0.09   | 62.40 | 799.06 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  19.11  | 0.01 | 19.09  | 20.95 |  83.81   |   20.95   |    83.81     |   0.08   | 52.33 | 670.11 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  16.31  | 0.01 | 16.28  | 24.57 |  98.26   |   24.57   |    98.26     |   0.08   | 61.32 | 785.42 |
| quad8_tex8_grey_quintic_bspline_direct                  |  26.43  | 0.01 | 26.41  | 15.15 |  60.59   |   15.15   |    60.59     |   0.09   | 37.84 | 484.50 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  19.42  | 0.01 | 19.40  | 20.62 |  82.48   |   20.62   |    82.48     |   0.08   | 51.49 | 659.42 |
| quad9_tex8_grey_linear_direct                           |  11.58  | 0.01 | 11.55  | 34.63 |  138.50  |   34.63   |    138.50    |   0.08   | 86.38 | 1244.74 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  18.18  | 0.01 | 18.16  | 22.03 |  88.10   |   22.03   |    88.10     |   0.08   | 55.01 | 792.45 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  16.29  | 0.01 | 16.27  | 24.59 |  98.36   |   24.59   |    98.36     |   0.08   | 61.39 | 884.38 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  16.24  | 0.01 | 16.22  | 24.66 |  98.65   |   24.66   |    98.65     |   0.08   | 61.59 | 887.23 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  19.93  | 0.01 | 19.91  | 20.09 |  80.37   |   20.09   |    80.37     |   0.08   | 50.17 | 722.76 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  16.36  | 0.01 | 16.34  | 24.48 |  97.93   |   24.48   |    97.93     |   0.08   | 61.13 | 880.75 |
| quad9_tex8_grey_quintic_bspline_direct                  |  26.41  | 0.01 | 26.39  | 15.16 |  60.63   |   15.16   |    60.63     |   0.07   | 37.86 | 545.35 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  19.47  | 0.01 | 19.45  | 20.57 |  82.27   |   20.57   |    82.27     |   0.09   | 51.37 | 740.01 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  9.74   | 0.01 |  9.71  | 41.21 |  164.83  |   41.21   |    164.83    |   0.15   | 102.71 | 493.50 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  17.95  | 0.01 | 17.92  | 22.33 |  89.31   |   22.33   |    89.31     |   0.14   | 55.71 | 267.63 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  16.74  | 0.02 | 16.71  | 23.94 |  95.76   |   23.94   |    95.76     |   0.12   | 59.73 | 286.94 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  16.65  | 0.02 | 16.62  | 24.07 |  96.26   |   24.07   |    96.26     |   0.11   | 60.08 | 288.54 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  20.59  | 0.02 | 20.56  | 19.46 |  77.84   |   19.46   |    77.84     |   0.12   | 48.58 | 233.34 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  16.56  | 0.02 | 16.53  | 24.19 |  96.77   |   24.19   |    96.77     |   0.12   | 60.38 | 290.06 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  27.79  | 0.01 | 27.77  | 14.40 |  57.62   |   14.40   |    57.62     |   0.14   | 35.98 | 172.77 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  20.80  | 0.02 | 20.78  | 19.25 |  77.01   |   19.25   |    77.01     |   0.11   | 48.07 | 230.87 |
| tri6_tex8_rgb_linear_direct                             |  17.49  | 0.02 | 17.46  | 22.91 |  91.63   |   22.91   |    91.63     |   0.12   | 57.16 | 549.29 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  24.21  | 0.02 | 24.18  | 16.54 |  66.17   |   16.54   |    66.17     |   0.11   | 41.30 | 396.68 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  22.13  | 0.01 | 22.10  | 18.10 |  72.40   |   18.10   |    72.40     |   0.14   | 45.19 | 434.07 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  22.42  | 0.01 | 22.39  | 17.86 |  71.45   |   17.86   |    71.45     |   0.14   | 44.60 | 428.35 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  27.67  | 0.02 | 27.64  | 14.47 |  57.89   |   14.47   |    57.89     |   0.11   | 36.14 | 347.14 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  22.14  | 0.01 | 22.11  | 18.09 |  72.36   |   18.09   |    72.36     |   0.14   | 45.17 | 433.87 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  34.04  | 0.02 | 34.01  | 11.76 |  47.04   |   11.76   |    47.04     |   0.13   | 29.38 | 282.11 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  27.43  | 0.01 | 27.40  | 14.60 |  58.39   |   14.60   |    58.39     |   0.14   | 36.46 | 350.14 |
| quad4ibi_tex8_rgb_linear_direct                         |  11.31  | 0.02 | 11.28  | 35.48 |  141.90  |   35.48   |    141.90    |   0.06   | 88.42 | 566.85 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  20.70  | 0.01 | 20.68  | 19.34 |  77.37   |   19.34   |    77.37     |   0.08   | 48.30 | 309.30 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  20.08  | 0.01 | 20.06  | 19.94 |  79.77   |   19.94   |    79.77     |   0.08   | 49.79 | 318.86 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  20.34  | 0.01 | 20.31  | 19.69 |  78.76   |   19.69   |    78.76     |   0.08   | 49.16 | 314.85 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  26.04  | 0.02 | 26.01  | 15.38 |  61.51   |   15.38   |    61.51     |   0.06   | 38.40 | 245.89 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  20.13  | 0.01 | 20.10  | 19.90 |  79.60   |   19.90   |    79.60     |   0.07   | 49.68 | 318.20 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  34.42  | 0.02 | 34.39  | 11.63 |  46.53   |   11.63   |    46.53     |   0.07   | 29.05 | 186.01 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  26.17  | 0.02 | 26.14  | 15.30 |  61.20   |   15.30   |    61.20     |   0.06   | 38.21 | 244.64 |
| quad4newton_tex8_rgb_linear_direct                      |  15.74  | 0.01 | 15.71  | 25.46 |  101.83  |   25.46   |    101.83    |   0.08   | 63.54 | 406.98 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  22.18  | 0.02 | 22.16  | 18.05 |  72.21   |   18.05   |    72.21     |   0.06   | 45.08 | 288.62 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  20.46  | 0.01 | 20.43  | 19.58 |  78.32   |   19.58   |    78.32     |   0.07   | 48.89 | 313.03 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  20.73  | 0.01 | 20.71  | 19.32 |  77.27   |   19.32   |    77.27     |   0.08   | 48.24 | 308.90 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  25.72  | 0.01 | 25.70  | 15.56 |  62.26   |   15.56   |    62.26     |   0.07   | 38.87 | 248.89 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  20.34  | 0.01 | 20.32  | 19.69 |  78.75   |   19.69   |    78.75     |   0.08   | 49.16 | 314.80 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  32.10  | 0.01 | 32.07  | 12.47 |  49.88   |   12.47   |    49.88     |   0.08   | 31.15 | 199.46 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  25.79  | 0.01 | 25.76  | 15.53 |  62.10   |   15.53   |    62.10     |   0.07   | 38.77 | 248.24 |
| quad8_tex8_rgb_linear_direct                            |  17.50  | 0.01 | 17.48  | 22.88 |  91.53   |   22.88   |    91.53     |   0.09   | 57.13 | 731.76 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  24.12  | 0.02 | 24.09  | 16.60 |  66.40   |   16.60   |    66.40     |   0.06   | 41.45 | 530.87 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  22.04  | 0.01 | 22.01  | 18.17 |  72.70   |   18.17   |    72.70     |   0.07   | 45.38 | 581.16 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  22.14  | 0.01 | 22.11  | 18.09 |  72.35   |   18.09   |    72.35     |   0.08   | 45.16 | 578.52 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  27.47  | 0.01 | 27.45  | 14.57 |  58.28   |   14.57   |    58.28     |   0.08   | 36.40 | 466.04 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  21.97  | 0.01 | 21.95  | 18.23 |  72.90   |   18.23   |    72.90     |   0.09   | 45.52 | 582.91 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  33.93  | 0.02 | 33.90  | 11.80 |  47.19   |   11.80   |    47.19     |   0.07   | 29.47 | 377.34 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  27.64  | 0.01 | 27.61  | 14.49 |  57.96   |   14.49   |    57.96     |   0.08   | 36.18 | 463.47 |
| quad9_tex8_rgb_linear_direct                            |  17.35  | 0.01 | 17.32  | 23.09 |  92.36   |   23.09   |    92.36     |   0.08   | 57.64 | 830.61 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  24.53  | 0.01 | 24.51  | 16.32 |  65.28   |   16.32   |    65.28     |   0.07   | 40.76 | 587.23 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  22.50  | 0.02 | 22.46  | 17.81 |  71.22   |   17.81   |    71.22     |   0.06   | 44.45 | 640.51 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  22.42  | 0.01 | 22.39  | 17.86 |  71.45   |   17.86   |    71.45     |   0.08   | 44.61 | 642.64 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  27.75  | 0.01 | 27.72  | 14.43 |  57.72   |   14.43   |    57.72     |   0.08   | 36.04 | 519.29 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  22.51  | 0.01 | 22.48  | 17.79 |  71.17   |   17.79   |    71.17     |   0.08   | 44.43 | 640.15 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  34.41  | 0.01 | 34.38  | 11.63 |  46.53   |   11.63   |    46.53     |   0.08   | 29.06 | 418.60 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  27.56  | 0.01 | 27.53  | 14.53 |  58.13   |   14.53   |    58.13     |   0.07   | 36.28 | 522.80 |

