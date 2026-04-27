# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  8.01   | 0.20 |  3.89  | 102.76 |  411.02  |  102.76   |    411.02    |   0.01   | 125.03 | 830.42 |
| tri6_nodal_grey                                         |  13.74  | 0.25 | 10.76  | 37.19 |  148.75  |   37.19   |    148.75    |   0.01   | 72.77 | 804.78 |
| quad4ibi_nodal_grey                                     |  9.89   | 0.20 |  7.01  | 57.09 |  228.34  |   57.09   |    228.34    |   0.00   | 101.10 | 791.05 |
| quad4newton_nodal_grey                                  |  12.14  | 0.20 |  8.88  | 45.03 |  180.11  |   45.03   |    180.11    |   0.01   | 82.38 | 625.57 |
| quad8_nodal_grey                                        |  13.66  | 0.29 | 10.66  | 37.53 |  150.11  |   37.53   |    150.11    |   0.00   | 73.23 | 1095.72 |
| quad9_nodal_grey                                        |  13.70  | 0.20 | 10.85  | 36.87 |  147.49  |   36.87   |    147.49    |   0.01   | 73.00 | 1207.64 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  9.77   | 0.19 |  4.92  | 81.35 |  325.42  |   81.35   |    325.42    |   0.01   | 104.03 | 607.65 |
| tri6_nodal_rgb                                          |  20.20  | 0.18 | 14.35  | 27.87 |  111.50  |   27.87   |    111.50    |   0.01   | 49.52 | 524.90 |
| quad4ibi_nodal_rgb                                      |  13.33  | 0.21 |  9.53  | 41.99 |  167.97  |   41.99   |    167.97    |   0.00   | 75.04 | 562.13 |
| quad4newton_nodal_rgb                                   |  13.43  | 0.23 |  9.57  | 41.81 |  167.25  |   41.81   |    167.25    |   0.00   | 74.48 | 551.79 |
| quad8_nodal_rgb                                         |  16.61  | 0.20 | 12.57  | 31.82 |  127.29  |   31.82   |    127.29    |   0.01   | 60.22 | 860.71 |
| quad9_nodal_rgb                                         |  16.44  | 0.20 | 12.57  | 31.84 |  127.35  |   31.84   |    127.35    |   0.00   | 60.86 | 979.82 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  12.21  | 0.18 |  8.23  | 48.58 |  194.32  |   48.58   |    194.32    |   0.01   | 81.89 | 509.60 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  17.11  | 0.20 | 14.52  | 27.55 |  110.22  |   27.55   |    110.22    |   0.01   | 58.45 | 312.11 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  15.19  | 0.19 | 12.18  | 32.84 |  131.37  |   32.84   |    131.37    |   0.01   | 65.86 | 361.31 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  16.23  | 0.21 | 12.90  | 31.01 |  124.04  |   31.01   |    124.04    |   0.01   | 61.72 | 331.95 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  17.95  | 0.17 | 15.34  | 26.07 |  104.28  |   26.07   |    104.28    |   0.01   | 55.71 | 295.52 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  15.78  | 0.19 | 12.67  | 31.57 |  126.30  |   31.57   |    126.30    |   0.01   | 63.39 | 351.50 |
| tri3_tex8_grey_quintic_bspline_direct                   |  25.81  | 0.18 | 22.91  | 17.46 |  69.85   |   17.46   |    69.85     |   0.01   | 38.75 | 200.54 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  18.38  | 0.17 | 15.46  | 25.88 |  103.53  |   25.88   |    103.53    |   0.01   | 54.40 | 287.89 |
| tri6_tex8_grey_linear_direct                            |  16.15  | 0.21 | 13.19  | 30.32 |  121.27  |   30.32   |    121.27    |   0.01   | 61.92 | 671.08 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  23.99  | 0.23 | 20.64  | 19.38 |  77.51   |   19.38   |    77.51     |   0.01   | 41.68 | 430.94 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  22.52  | 0.24 | 19.61  | 20.40 |  81.60   |   20.40   |    81.60     |   0.01   | 44.41 | 461.93 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  21.71  | 0.20 | 18.43  | 21.71 |  86.82   |   21.71   |    86.82     |   0.01   | 46.07 | 486.09 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  25.06  | 0.19 | 22.06  | 18.14 |  72.56   |   18.14   |    72.56     |   0.01   | 39.91 | 411.07 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  21.84  | 0.21 | 18.56  | 21.55 |  86.22   |   21.55   |    86.22     |   0.01   | 45.81 | 489.99 |
| tri6_tex8_grey_quintic_bspline_direct                   |  32.82  | 0.27 | 29.48  | 13.57 |  54.30   |   13.57   |    54.30     |   0.01   | 30.47 | 310.48 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  25.38  | 0.21 | 22.66  | 17.67 |  70.67   |   17.67   |    70.67     |   0.01   | 39.44 | 406.29 |
| quad4ibi_tex8_grey_linear_direct                        |  12.41  | 0.20 |  9.53  | 41.99 |  167.97  |   41.99   |    167.97    |   0.00   | 80.56 | 612.58 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  20.29  | 0.20 | 17.14  | 23.34 |  93.37   |   23.34   |    93.37     |   0.00   | 49.30 | 346.89 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  21.74  | 0.19 | 18.68  | 21.42 |  85.68   |   21.42   |    85.68     |   0.01   | 46.00 | 324.64 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.65  | 0.24 | 17.75  | 22.54 |  90.14   |   22.54   |    90.14     |   0.00   | 48.43 | 339.19 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  24.59  | 0.22 | 21.78  | 18.36 |  73.45   |   18.36   |    73.45     |   0.00   | 40.66 | 279.94 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  20.73  | 0.21 | 17.48  | 22.88 |  91.54   |   22.88   |    91.54     |   0.00   | 48.25 | 339.70 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  29.83  | 0.30 | 26.37  | 15.17 |  60.67   |   15.17   |    60.67     |   0.00   | 33.53 | 230.25 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  24.68  | 0.22 | 21.77  | 18.38 |  73.51   |   18.38   |    73.51     |   0.00   | 40.52 | 281.19 |
| quad4newton_tex8_grey_linear_direct                     |  14.02  | 0.21 | 10.86  | 36.85 |  147.38  |   36.85   |    147.38    |   0.00   | 71.42 | 542.34 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  20.94  | 0.27 | 18.09  | 22.11 |  88.43   |   22.11   |    88.43     |   0.00   | 47.75 | 333.27 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  18.84  | 0.24 | 16.12  | 24.82 |  99.27   |   24.82   |    99.27     |   0.00   | 53.10 | 377.71 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  18.67  | 0.20 | 15.87  | 25.21 |  100.86  |   25.21   |    100.86    |   0.01   | 53.56 | 378.70 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  22.33  | 0.29 | 19.37  | 20.65 |  82.60   |   20.65   |    82.60     |   0.00   | 44.79 | 310.65 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  19.66  | 0.24 | 16.52  | 24.22 |  96.86   |   24.22   |    96.86     |   0.00   | 50.87 | 361.78 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  29.26  | 0.24 | 26.28  | 15.22 |  60.87   |   15.22   |    60.87     |   0.00   | 34.18 | 232.28 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  22.36  | 0.23 | 19.06  | 20.98 |  83.94   |   20.98   |    83.94     |   0.00   | 44.72 | 311.84 |
| quad8_tex8_grey_linear_direct                           |  15.86  | 0.27 | 12.96  | 30.86 |  123.44  |   30.86   |    123.44    |   0.00   | 63.06 | 905.99 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  23.20  | 0.23 | 20.15  | 19.85 |  79.41   |   19.85   |    79.41     |   0.00   | 43.10 | 595.95 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  22.33  | 0.28 | 19.23  | 20.81 |  83.22   |   20.81   |    83.22     |   0.00   | 44.82 | 626.39 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  23.74  | 0.23 | 19.30  | 20.73 |  82.90   |   20.73   |    82.90     |   0.00   | 42.13 | 613.16 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  24.31  | 0.28 | 21.79  | 18.36 |  73.43   |   18.36   |    73.43     |   0.00   | 41.13 | 567.16 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  21.47  | 0.31 | 18.70  | 21.39 |  85.55   |   21.39   |    85.55     |   0.00   | 46.58 | 649.33 |
| quad8_tex8_grey_quintic_bspline_direct                  |  32.02  | 0.23 | 29.11  | 13.74 |  54.96   |   13.74   |    54.96     |   0.00   | 31.23 | 424.11 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  24.80  | 0.28 | 21.94  | 18.24 |  72.95   |   18.24   |    72.95     |   0.00   | 40.33 | 555.15 |
| quad9_tex8_grey_linear_direct                           |  17.69  | 0.21 | 15.11  | 26.48 |  105.91  |   26.48   |    105.91    |   0.00   | 56.52 | 914.05 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  23.64  | 0.29 | 20.53  | 19.48 |  77.93   |   19.48   |    77.93     |   0.00   | 42.30 | 659.32 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  21.82  | 0.26 | 18.95  | 21.10 |  84.42   |   21.10   |    84.42     |   0.00   | 45.82 | 716.76 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  21.91  | 0.25 | 18.79  | 21.28 |  85.14   |   21.28   |    85.14     |   0.00   | 45.66 | 719.63 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  26.02  | 0.22 | 22.77  | 17.57 |  70.28   |   17.57   |    70.28     |   0.00   | 38.43 | 593.58 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  22.55  | 0.20 | 19.68  | 20.33 |  81.32   |   20.33   |    81.32     |   0.01   | 44.36 | 693.70 |
| quad9_tex8_grey_quintic_bspline_direct                  |  32.76  | 0.27 | 29.98  | 13.34 |  53.36   |   13.34   |    53.36     |   0.00   | 30.53 | 464.67 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  25.14  | 0.21 | 21.88  | 18.28 |  73.14   |   18.28   |    73.14     |   0.00   | 39.78 | 618.12 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  14.54  | 0.16 |  9.72  | 41.17 |  164.70  |   41.17   |    164.70    |   0.01   | 68.78 | 381.08 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  23.38  | 0.14 | 19.02  | 21.03 |  84.13   |   21.03   |    84.13     |   0.01   | 42.79 | 221.78 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  21.69  | 0.15 | 17.44  | 22.94 |  91.74   |   22.94   |    91.74     |   0.01   | 46.12 | 241.95 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  21.86  | 0.19 | 17.29  | 23.14 |  92.55   |   23.14   |    92.55     |   0.01   | 45.76 | 239.00 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  25.78  | 0.17 | 21.70  | 18.43 |  73.73   |   18.43   |    73.73     |   0.01   | 38.80 | 203.08 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  20.98  | 0.14 | 17.33  | 23.08 |  92.32   |   23.08   |    92.32     |   0.01   | 47.66 | 249.25 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  33.86  | 0.14 | 29.84  | 13.40 |  53.62   |   13.40   |    53.62     |   0.01   | 29.54 | 149.49 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  25.63  | 0.15 | 21.97  | 18.21 |  72.83   |   18.21   |    72.83     |   0.01   | 39.01 | 200.76 |
| tri6_tex8_rgb_linear_direct                             |  23.36  | 0.19 | 18.40  | 21.74 |  86.94   |   21.74   |    86.94     |   0.01   | 42.81 | 447.80 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  30.08  | 0.19 | 25.59  | 15.63 |  62.52   |   15.63   |    62.52     |   0.01   | 33.28 | 339.48 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  27.14  | 0.19 | 23.29  | 17.18 |  68.70   |   17.18   |    68.70     |   0.01   | 36.85 | 377.59 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  27.82  | 0.18 | 23.45  | 17.06 |  68.24   |   17.06   |    68.24     |   0.01   | 35.94 | 370.04 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  31.39  | 0.19 | 27.69  | 14.45 |  57.78   |   14.45   |    57.78     |   0.01   | 31.86 | 324.56 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  27.68  | 0.19 | 23.95  | 16.70 |  66.81   |   16.70   |    66.81     |   0.01   | 36.13 | 369.58 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  39.86  | 0.20 | 35.63  | 11.23 |  44.91   |   11.23   |    44.91     |   0.01   | 25.09 | 252.66 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  32.30  | 0.18 | 28.25  | 14.16 |  56.63   |   14.16   |    56.63     |   0.01   | 30.96 | 314.20 |
| quad4ibi_tex8_rgb_linear_direct                         |  16.00  | 0.30 | 11.92  | 33.55 |  134.20  |   33.55   |    134.20    |   0.00   | 62.49 | 448.35 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  25.38  | 0.16 | 21.65  | 18.47 |  73.90   |   18.47   |    73.90     |   0.01   | 39.41 | 273.54 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  26.44  | 0.20 | 22.94  | 17.44 |  69.74   |   17.44   |    69.74     |   0.00   | 37.82 | 261.47 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  26.17  | 0.17 | 22.22  | 18.00 |  72.00   |   18.00   |    72.00     |   0.01   | 38.21 | 264.85 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  33.04  | 0.17 | 29.23  | 13.69 |  54.76   |   13.69   |    54.76     |   0.01   | 30.27 | 204.29 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  25.66  | 0.16 | 22.28  | 17.95 |  71.81   |   17.95   |    71.81     |   0.01   | 38.97 | 269.18 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  40.31  | 0.19 | 36.79  | 10.87 |  43.49   |   10.87   |    43.49     |   0.01   | 24.81 | 165.91 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  34.03  | 0.17 | 30.02  | 13.33 |  53.31   |   13.33   |    53.31     |   0.01   | 29.40 | 198.53 |
| quad4newton_tex8_rgb_linear_direct                      |  19.43  | 0.20 | 15.75  | 25.40 |  101.59  |   25.40   |    101.59    |   0.01   | 51.46 | 364.45 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  26.63  | 0.18 | 23.05  | 17.36 |  69.43   |   17.36   |    69.43     |   0.01   | 37.55 | 258.07 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  24.68  | 0.16 | 21.24  | 18.84 |  75.36   |   18.84   |    75.36     |   0.01   | 40.53 | 279.32 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  24.67  | 0.22 | 21.08  | 18.97 |  75.90   |   18.97   |    75.90     |   0.00   | 40.53 | 281.28 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  29.91  | 0.19 | 25.94  | 15.42 |  61.67   |   15.42   |    61.67     |   0.01   | 33.44 | 229.07 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  25.21  | 0.22 | 21.31  | 18.77 |  75.07   |   18.77   |    75.07     |   0.00   | 39.66 | 273.92 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  37.81  | 0.19 | 32.87  | 12.17 |  48.67   |   12.17   |    48.67     |   0.01   | 26.45 | 177.39 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  29.85  | 0.18 | 25.70  | 15.56 |  62.25   |   15.56   |    62.25     |   0.01   | 33.50 | 227.63 |
| quad8_tex8_rgb_linear_direct                            |  22.58  | 0.19 | 18.84  | 21.24 |  84.96   |   21.24   |    84.96     |   0.01   | 44.29 | 614.15 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  29.11  | 0.23 | 24.97  | 16.02 |  64.07   |   16.02   |    64.07     |   0.00   | 34.36 | 467.57 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  27.55  | 0.22 | 23.78  | 16.82 |  67.29   |   16.82   |    67.29     |   0.00   | 36.31 | 498.50 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  27.04  | 0.23 | 23.03  | 17.37 |  69.49   |   17.37   |    69.49     |   0.00   | 36.99 | 508.19 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  31.89  | 0.20 | 27.91  | 14.33 |  57.33   |   14.33   |    57.33     |   0.01   | 31.37 | 430.02 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  27.85  | 0.23 | 23.55  | 16.99 |  67.96   |   16.99   |    67.96     |   0.00   | 35.91 | 490.68 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  40.45  | 0.25 | 35.80  | 11.18 |  44.72   |   11.18   |    44.72     |   0.00   | 24.72 | 330.77 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  31.73  | 0.18 | 27.65  | 14.47 |  57.86   |   14.47   |    57.86     |   0.01   | 31.51 | 432.03 |
| quad9_tex8_rgb_linear_direct                            |  22.57  | 0.24 | 18.36  | 21.78 |  87.12   |   21.78   |    87.12     |   0.00   | 44.32 | 690.35 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  29.99  | 0.21 | 25.81  | 15.50 |  61.99   |   15.50   |    61.99     |   0.00   | 33.34 | 510.00 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  27.25  | 0.22 | 23.77  | 16.83 |  67.32   |   16.83   |    67.32     |   0.00   | 36.69 | 564.53 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  27.64  | 0.22 | 23.63  | 16.93 |  67.72   |   16.93   |    67.72     |   0.00   | 36.17 | 558.10 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  32.99  | 0.21 | 29.57  | 13.53 |  54.13   |   13.53   |    54.13     |   0.00   | 30.32 | 461.10 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  27.65  | 0.21 | 23.48  | 17.03 |  68.13   |   17.03   |    68.13     |   0.00   | 36.17 | 557.30 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  41.37  | 0.22 | 37.25  | 10.74 |  42.96   |   10.74   |    42.96     |   0.00   | 24.17 | 363.16 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  31.63  | 0.20 | 28.12  | 14.23 |  56.91   |   14.23   |    56.91     |   0.00   | 31.61 | 481.71 |

