# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  17.52  | 4.36 |  6.79  | 58.93 |  235.70  |   60.98   |    243.93    |  47.04   | 57.07 | 355.77 |
| tri6_nodal_grey                                         |  48.25  | 9.13 | 30.19  | 13.25 |  53.01   |   13.62   |    54.47     |  22.44   | 20.73 | 238.24 |
| quad4ibi_nodal_grey                                     |  15.12  | 2.93 |  9.10  | 43.95 |  175.79  |   45.08   |    180.32    |  35.01   | 66.23 | 490.55 |
| quad4newton_nodal_grey                                  |  20.37  | 2.47 | 14.23  | 28.11 |  112.45  |   28.88   |    115.52    |  41.45   | 49.11 | 362.46 |
| quad8_nodal_grey                                        |  36.91  | 6.19 | 22.91  | 17.46 |  69.85   |   17.93   |    71.73     |  16.63   | 27.10 | 428.05 |
| quad9_nodal_grey                                        |  36.49  | 6.14 | 21.93  | 18.24 |  72.96   |   18.73   |    74.94     |  16.68   | 27.41 | 483.84 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  20.60  | 4.70 |  8.72  | 45.92 |  183.69  |   47.52   |    190.10    |  43.60   | 48.55 | 285.98 |
| tri6_nodal_rgb                                          |  53.70  | 11.79 | 30.45  | 13.14 |  52.55   |   13.50   |    54.00     |  17.50   | 18.62 | 213.50 |
| quad4ibi_nodal_rgb                                      |  18.68  | 3.22 | 10.54  | 37.95 |  151.82  |   38.93   |    155.73    |  31.81   | 53.53 | 404.01 |
| quad4newton_nodal_rgb                                   |  25.18  | 3.13 | 16.57  | 24.15 |  96.59   |   24.81   |    99.23     |  32.75   | 39.76 | 296.09 |
| quad8_nodal_rgb                                         |  42.65  | 7.55 | 24.73  | 16.17 |  64.70   |   16.61   |    66.44     |  13.56   | 23.45 | 366.84 |
| quad9_nodal_rgb                                         |  41.90  | 7.35 | 23.88  | 16.75 |  67.01   |   17.21   |    68.83     |  13.96   | 23.87 | 413.72 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  24.15  | 4.19 | 12.45  | 32.16 |  128.62  |   33.28   |    133.11    |  48.91   | 41.41 | 267.16 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  31.91  | 3.95 | 19.07  | 20.98 |  83.90   |   21.71   |    86.83     |  51.82   | 31.35 | 190.27 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  29.01  | 4.14 | 16.69  | 23.97 |  95.86   |   24.80   |    99.21     |  49.45   | 34.48 | 218.22 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  29.56  | 4.03 | 16.31  | 24.52 |  98.10   |   25.38   |    101.52    |  50.87   | 33.83 | 218.16 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  33.08  | 4.27 | 20.96  | 19.08 |  76.33   |   19.75   |    78.99     |  47.95   | 30.23 | 182.33 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  29.69  | 4.25 | 17.04  | 23.48 |  93.91   |   24.30   |    97.19     |  48.29   | 33.71 | 207.72 |
| tri3_tex8_grey_quintic_bspline_direct                   |  40.07  | 3.98 | 27.72  | 14.43 |  57.71   |   14.93   |    59.73     |  51.52   | 24.96 | 146.56 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  31.52  | 4.05 | 20.03  | 19.97 |  79.88   |   20.67   |    82.67     |  50.56   | 31.72 | 191.37 |
| tri6_tex8_grey_linear_direct                            |  64.20  | 9.88 | 32.87  | 12.17 |  48.67   |   12.50   |    50.02     |  20.75   | 15.58 | 215.83 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  71.58  | 9.26 | 40.73  | 9.82  |  39.29   |   10.09   |    40.37     |  22.12   | 13.98 | 184.72 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  70.79  | 9.47 | 39.65  | 10.09 |  40.35   |   10.37   |    41.47     |  21.68   | 14.13 | 188.16 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  69.49  | 9.39 | 38.49  | 10.39 |  41.57   |   10.68   |    42.72     |  21.82   | 14.39 | 193.98 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  72.66  | 9.20 | 41.72  | 9.59  |  38.35   |   9.85    |    39.41     |  22.27   | 13.77 | 185.21 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  71.55  | 10.44 | 37.93  | 10.55 |  42.19   |   10.84   |    43.35     |  19.61   | 13.98 | 197.19 |
| tri6_tex8_grey_quintic_bspline_direct                   |  78.80  | 8.89 | 47.98  | 8.34  |  33.35   |   8.57    |    34.27     |  23.03   | 12.69 | 165.73 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  73.67  | 10.55 | 41.46  | 9.65  |  38.59   |   9.91    |    39.65     |  19.42   | 13.57 | 180.56 |
| quad4ibi_tex8_grey_linear_direct                        |  20.45  | 3.52 | 11.20  | 35.73 |  142.92  |   36.65   |    146.60    |  29.07   | 48.94 | 418.79 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  27.78  | 3.14 | 19.34  | 20.69 |  82.74   |   21.22   |    84.87     |  32.71   | 36.02 | 273.81 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  26.63  | 3.02 | 19.00  | 21.06 |  84.23   |   21.60   |    86.40     |  34.00   | 37.56 | 279.50 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  27.61  | 2.82 | 19.37  | 20.65 |  82.59   |   21.18   |    84.72     |  36.27   | 36.23 | 263.63 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  31.65  | 3.00 | 24.16  | 16.55 |  66.21   |   16.98   |    67.92     |  34.14   | 31.60 | 228.68 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  26.57  | 2.86 | 19.37  | 20.65 |  82.58   |   21.18   |    84.71     |  35.77   | 37.64 | 277.58 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  37.11  | 3.23 | 28.38  | 14.10 |  56.38   |   14.46   |    57.83     |  31.70   | 26.95 | 196.20 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  31.47  | 2.58 | 23.96  | 16.70 |  66.79   |   17.13   |    68.51     |  39.62   | 31.78 | 228.48 |
| quad4newton_tex8_grey_linear_direct                     |  37.83  | 3.47 | 18.03  | 22.19 |  88.74   |   22.79   |    91.17     |  29.47   | 26.45 | 282.36 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  43.52  | 3.08 | 24.21  | 16.52 |  66.09   |   16.98   |    67.90     |  33.32   | 23.00 | 223.63 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  43.15  | 3.55 | 23.08  | 17.33 |  69.33   |   17.81   |    71.23     |  28.86   | 23.18 | 233.80 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  42.08  | 2.63 | 23.27  | 17.20 |  68.78   |   17.67   |    70.66     |  39.03   | 23.76 | 230.93 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  46.06  | 2.86 | 25.89  | 15.45 |  61.80   |   15.87   |    63.48     |  36.11   | 21.71 | 213.83 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  41.79  | 2.81 | 23.11  | 17.31 |  69.25   |   17.78   |    71.14     |  36.54   | 23.93 | 232.83 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  53.13  | 3.22 | 33.04  | 12.11 |  48.43   |   12.44   |    49.76     |  32.36   | 18.83 | 170.09 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  44.79  | 2.62 | 26.28  | 15.23 |  60.90   |   15.64   |    62.57     |  39.11   | 22.33 | 212.30 |
| quad8_tex8_grey_linear_direct                           |  48.07  | 6.94 | 25.57  | 15.64 |  62.57   |   16.06   |    64.25     |  14.76   | 20.81 | 377.57 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  55.31  | 6.61 | 33.16  | 12.06 |  48.26   |   12.39   |    49.56     |  15.50   | 18.08 | 314.81 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  54.54  | 7.07 | 31.31  | 12.78 |  51.10   |   13.12   |    52.48     |  14.50   | 18.34 | 329.04 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.86  | 6.67 | 31.82  | 12.57 |  50.29   |   12.91   |    51.64     |  15.46   | 18.23 | 324.14 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  57.64  | 6.61 | 35.16  | 11.38 |  45.50   |   11.68   |    46.73     |  15.51   | 17.35 | 299.90 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  54.21  | 6.78 | 31.77  | 12.59 |  50.35   |   12.93   |    51.71     |  15.11   | 18.45 | 324.97 |
| quad8_tex8_grey_quintic_bspline_direct                  |  65.21  | 6.62 | 41.81  | 9.57  |  38.28   |   9.83    |    39.31     |  15.48   | 15.34 | 257.63 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  58.13  | 6.60 | 35.66  | 11.22 |  44.88   |   11.52   |    46.08     |  15.52   | 17.20 | 296.98 |
| quad9_tex8_grey_linear_direct                           |  49.58  | 6.49 | 25.92  | 15.44 |  61.76   |   15.86   |    63.43     |  15.77   | 20.17 | 430.03 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  57.01  | 7.13 | 33.47  | 11.95 |  47.81   |   12.28   |    49.11     |  14.37   | 17.54 | 343.77 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  55.24  | 6.57 | 31.55  | 12.68 |  50.73   |   13.03   |    52.11     |  15.60   | 18.11 | 371.41 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.41  | 7.18 | 31.24  | 12.81 |  51.22   |   13.15   |    52.61     |  14.26   | 18.38 | 369.62 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  57.85  | 6.94 | 34.56  | 11.58 |  46.30   |   11.89   |    47.56     |  14.76   | 17.29 | 343.25 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  56.38  | 6.88 | 31.37  | 12.75 |  51.01   |   13.10   |    52.39     |  14.90   | 17.74 | 354.62 |
| quad9_tex8_grey_quintic_bspline_direct                  |  64.57  | 6.63 | 41.40  | 9.66  |  38.65   |   9.92    |    39.70     |  15.46   | 15.49 | 295.89 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  59.15  | 6.99 | 34.18  | 11.70 |  46.81   |   12.02   |    48.08     |  14.65   | 16.91 | 332.60 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  28.04  | 3.60 | 16.09  | 24.87 |  99.48   |   25.74   |    102.95    |  56.89   | 35.67 | 214.76 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  36.80  | 4.03 | 23.87  | 16.76 |  67.03   |   17.34   |    69.37     |  50.83   | 27.19 | 156.07 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  34.25  | 4.14 | 22.40  | 17.86 |  71.44   |   18.48   |    73.93     |  49.47   | 29.20 | 166.83 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  35.07  | 4.03 | 23.22  | 17.23 |  68.92   |   17.83   |    71.33     |  51.03   | 28.52 | 162.27 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  39.78  | 3.93 | 27.46  | 14.57 |  58.27   |   15.07   |    60.29     |  52.21   | 25.14 | 140.69 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  35.02  | 3.83 | 22.50  | 17.78 |  71.11   |   18.40   |    73.59     |  53.57   | 28.58 | 168.96 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  46.45  | 4.01 | 34.50  | 11.59 |  46.38   |   12.00   |    47.99     |  51.14   | 21.53 | 118.30 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  38.56  | 3.62 | 27.03  | 14.80 |  59.19   |   15.31   |    61.26     |  56.71   | 25.93 | 147.54 |
| tri6_tex8_rgb_linear_direct                             |  72.68  | 10.54 | 39.95  | 10.01 |  40.05   |   10.29   |    41.15     |  19.47   | 13.76 | 184.03 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  81.29  | 9.52 | 47.23  | 8.47  |  33.88   |   8.70    |    34.81     |  21.51   | 12.30 | 160.95 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  80.29  | 11.08 | 45.37  | 8.82  |  35.27   |   9.06    |    36.25     |  18.55   | 12.46 | 162.11 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  80.98  | 10.01 | 46.31  | 8.64  |  34.56   |   8.88    |    35.51     |  20.46   | 12.35 | 161.78 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  84.20  | 10.25 | 50.36  | 7.94  |  31.77   |   8.16    |    32.65     |  19.99   | 11.88 | 151.42 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  78.50  | 10.72 | 44.77  | 8.94  |  35.74   |   9.18    |    36.73     |  19.11   | 12.74 | 170.24 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  93.00  | 9.87 | 58.60  | 6.83  |  27.30   |   7.01    |    28.06     |  20.75   | 10.75 | 136.15 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  84.08  | 9.73 | 49.81  | 8.03  |  32.12   |   8.25    |    33.01     |  21.05   | 11.90 | 153.48 |
| quad4ibi_tex8_rgb_linear_direct                         |  22.56  | 3.07 | 13.95  | 28.67 |  114.69  |   29.41   |    117.63    |  33.40   | 44.33 | 344.77 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  33.23  | 2.95 | 24.33  | 16.44 |  65.76   |   16.86   |    67.45     |  34.69   | 30.09 | 220.76 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  33.74  | 3.15 | 24.24  | 16.50 |  66.01   |   16.93   |    67.71     |  32.55   | 29.64 | 219.07 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  33.54  | 3.01 | 24.58  | 16.27 |  65.09   |   16.69   |    66.77     |  34.04   | 29.82 | 218.75 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  40.24  | 3.49 | 30.56  | 13.09 |  52.35   |   13.43   |    53.70     |  29.33   | 24.85 | 178.81 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  34.02  | 3.05 | 23.93  | 16.71 |  66.86   |   17.14   |    68.58     |  33.60   | 29.39 | 215.64 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  47.74  | 2.90 | 37.95  | 10.54 |  42.17   |   10.81   |    43.25     |  35.37   | 20.95 | 148.13 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  39.95  | 3.02 | 30.51  | 13.11 |  52.44   |   13.45   |    53.80     |  33.91   | 25.03 | 180.29 |
| quad4newton_tex8_rgb_linear_direct                      |  42.84  | 2.86 | 23.60  | 16.95 |  67.81   |   17.42   |    69.66     |  35.78   | 23.35 | 223.78 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  50.27  | 2.95 | 30.59  | 13.08 |  52.31   |   13.43   |    53.74     |  34.74   | 19.90 | 180.96 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  49.92  | 2.88 | 30.41  | 13.16 |  52.62   |   13.52   |    54.06     |  35.61   | 20.03 | 181.11 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  48.97  | 3.02 | 29.40  | 13.61 |  54.42   |   13.98   |    55.91     |  33.91   | 20.43 | 185.62 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  53.04  | 2.91 | 33.82  | 11.83 |  47.31   |   12.15   |    48.60     |  35.17   | 18.85 | 165.96 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  48.70  | 3.06 | 28.92  | 13.83 |  55.32   |   14.21   |    56.83     |  33.50   | 20.53 | 190.68 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  60.23  | 2.93 | 41.44  | 9.65  |  38.61   |   9.92    |    39.66     |  34.90   | 16.60 | 138.16 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  53.42  | 2.80 | 34.25  | 11.68 |  46.73   |   12.00   |    48.01     |  36.54   | 18.72 | 162.40 |
| quad8_tex8_rgb_linear_direct                            |  57.32  | 6.91 | 32.60  | 12.27 |  49.08   |   12.60   |    50.40     |  14.82   | 17.45 | 308.56 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  63.02  | 6.73 | 38.86  | 10.29 |  41.17   |   10.57   |    42.28     |  15.22   | 15.87 | 269.43 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  61.60  | 6.37 | 38.09  | 10.50 |  42.00   |   10.78   |    43.13     |  16.08   | 16.23 | 276.77 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  62.51  | 6.30 | 38.99  | 10.26 |  41.03   |   10.53   |    42.14     |  16.25   | 16.00 | 266.78 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  66.72  | 6.87 | 44.20  | 9.05  |  36.20   |   9.29    |    37.18     |  14.90   | 14.99 | 242.69 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  62.81  | 6.61 | 38.97  | 10.26 |  41.06   |   10.54   |    42.16     |  15.49   | 15.92 | 271.79 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  73.69  | 7.03 | 49.94  | 8.01  |  32.04   |   8.23    |    32.91     |  14.57   | 13.57 | 215.47 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  64.66  | 6.92 | 41.75  | 9.58  |  38.32   |   9.84    |    39.35     |  14.82   | 15.47 | 251.29 |
| quad9_tex8_rgb_linear_direct                            |  59.14  | 7.67 | 30.75  | 13.01 |  52.04   |   13.36   |    53.45     |  13.37   | 16.91 | 356.31 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  65.57  | 7.38 | 37.98  | 10.53 |  42.13   |   10.82   |    43.27     |  13.87   | 15.25 | 304.05 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  62.03  | 6.86 | 36.46  | 10.97 |  43.88   |   11.27   |    45.07     |  14.93   | 16.12 | 314.97 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  60.91  | 6.55 | 37.41  | 10.69 |  42.78   |   10.98   |    43.94     |  15.63   | 16.42 | 312.85 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  68.46  | 6.45 | 43.15  | 9.27  |  37.08   |   9.52    |    38.09     |  15.88   | 14.61 | 279.46 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  65.41  | 8.48 | 36.25  | 11.03 |  44.14   |   11.33   |    45.33     |  12.08   | 15.29 | 309.02 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  72.15  | 6.73 | 48.27  | 8.29  |  33.15   |   8.51    |    34.04     |  15.21   | 13.86 | 252.54 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  66.80  | 7.25 | 42.73  | 9.36  |  37.44   |   9.61    |    38.46     |  14.15   | 14.97 | 280.06 |

