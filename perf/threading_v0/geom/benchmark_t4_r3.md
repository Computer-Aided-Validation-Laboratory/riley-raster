# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  16.92  | 3.98 |  6.44  | 62.32 |  249.27  |   64.49   |    257.97    |  51.51   | 59.13 | 377.35 |
| tri6_nodal_grey                                         |  46.54  | 8.44 | 28.90  | 13.84 |  55.35   |   14.22   |    56.88     |  24.27   | 21.49 | 249.85 |
| quad4ibi_nodal_grey                                     |  14.20  | 2.70 |  8.48  | 47.15 |  188.61  |   48.37   |    193.47    |  37.88   | 70.43 | 521.90 |
| quad4newton_nodal_grey                                  |  24.77  | 2.82 | 14.69  | 27.22 |  108.90  |   27.97   |    111.87    |  36.36   | 40.72 | 334.35 |
| quad8_nodal_grey                                        |  37.25  | 6.02 | 23.30  | 17.17 |  68.67   |   17.63   |    70.52     |  17.02   | 26.85 | 410.71 |
| quad9_nodal_grey                                        |  36.82  | 6.35 | 22.94  | 17.45 |  69.80   |   17.92   |    71.69     |  16.14   | 27.16 | 470.14 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  21.18  | 4.67 |  8.17  | 48.98 |  195.92  |   50.69   |    202.76    |  43.83   | 47.23 | 282.14 |
| tri6_nodal_rgb                                          |  54.58  | 12.44 | 30.76  | 13.00 |  52.02   |   13.36   |    53.45     |  16.46   | 18.32 | 213.20 |
| quad4ibi_nodal_rgb                                      |  18.75  | 3.19 | 10.59  | 37.79 |  151.17  |   38.77   |    155.07    |  32.14   | 53.34 | 412.64 |
| quad4newton_nodal_rgb                                   |  25.93  | 3.11 | 16.98  | 23.58 |  94.30   |   24.22   |    96.88     |  32.97   | 38.57 | 283.70 |
| quad8_nodal_rgb                                         |  39.60  | 6.48 | 24.68  | 16.21 |  64.82   |   16.64   |    66.57     |  15.80   | 25.26 | 386.02 |
| quad9_nodal_rgb                                         |  42.97  | 8.61 | 23.72  | 16.87 |  67.48   |   17.33   |    69.32     |  11.90   | 23.28 | 411.80 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  24.43  | 4.35 | 10.83  | 36.95 |  147.81  |   38.24   |    152.97    |  47.15   | 40.94 | 270.08 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  31.12  | 4.37 | 18.57  | 21.54 |  86.15   |   22.29   |    89.16     |  46.93   | 32.14 | 196.80 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  29.70  | 5.09 | 16.95  | 23.60 |  94.41   |   24.43   |    97.71     |  40.25   | 33.67 | 214.63 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  29.39  | 4.43 | 16.51  | 24.24 |  96.94   |   25.08   |    100.33    |  46.38   | 34.02 | 213.59 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  32.63  | 4.66 | 20.39  | 19.63 |  78.51   |   20.31   |    81.25     |  43.96   | 30.65 | 182.09 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  29.15  | 4.19 | 16.61  | 24.09 |  96.36   |   24.93   |    99.72     |  48.90   | 34.31 | 212.24 |
| tri3_tex8_grey_quintic_bspline_direct                   |  39.67  | 4.30 | 27.16  | 14.73 |  58.90   |   15.24   |    60.96     |  47.69   | 25.21 | 145.17 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  31.87  | 4.10 | 19.63  | 20.37 |  81.49   |   21.08   |    84.34     |  49.98   | 31.37 | 193.18 |
| tri6_tex8_grey_linear_direct                            |  63.94  | 9.08 | 34.36  | 11.64 |  46.56   |   11.96   |    47.85     |  22.56   | 15.64 | 216.56 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  71.76  | 9.60 | 39.70  | 10.07 |  40.30   |   10.35   |    41.41     |  21.40   | 13.94 | 190.32 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  69.95  | 9.54 | 37.91  | 10.55 |  42.21   |   10.84   |    43.37     |  21.46   | 14.30 | 192.14 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  71.30  | 9.78 | 39.03  | 10.25 |  41.00   |   10.53   |    42.13     |  20.95   | 14.03 | 194.46 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  72.26  | 8.36 | 42.22  | 9.48  |  37.90   |   9.74    |    38.95     |  24.49   | 13.84 | 184.94 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  70.81  | 10.80 | 38.02  | 10.52 |  42.08   |   10.81   |    43.24     |  18.97   | 14.12 | 191.18 |
| tri6_tex8_grey_quintic_bspline_direct                   |  80.04  | 9.28 | 49.24  | 8.12  |  32.50   |   8.35    |    33.40     |  22.08   | 12.49 | 160.98 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  72.43  | 9.33 | 42.22  | 9.47  |  37.90   |   9.74    |    38.94     |  21.95   | 13.81 | 183.11 |
| quad4ibi_tex8_grey_linear_direct                        |  18.50  | 3.07 | 11.06  | 36.17 |  144.70  |   37.11   |    148.42    |  33.33   | 54.06 | 426.87 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  27.13  | 2.65 | 19.82  | 20.18 |  80.73   |   20.70   |    82.81     |  38.70   | 36.87 | 273.18 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  26.79  | 2.81 | 19.62  | 20.38 |  81.54   |   20.91   |    83.64     |  36.49   | 37.34 | 272.15 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  27.51  | 2.68 | 20.27  | 19.73 |  78.94   |   20.24   |    80.97     |  38.22   | 36.36 | 270.08 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  32.88  | 2.65 | 24.10  | 16.60 |  66.41   |   17.03   |    68.12     |  38.67   | 30.41 | 223.25 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  27.68  | 2.58 | 19.56  | 20.45 |  81.81   |   20.98   |    83.91     |  39.75   | 36.12 | 273.29 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  37.48  | 3.27 | 28.32  | 14.12 |  56.50   |   14.49   |    57.95     |  31.36   | 26.68 | 198.18 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  30.89  | 2.57 | 23.71  | 16.87 |  67.48   |   17.30   |    69.22     |  39.80   | 32.38 | 235.90 |
| quad4newton_tex8_grey_linear_direct                     |  36.42  | 2.99 | 17.11  | 23.38 |  93.52   |   24.02   |    96.07     |  34.62   | 27.46 | 303.25 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  41.79  | 2.61 | 24.43  | 16.38 |  65.51   |   16.83   |    67.30     |  39.17   | 23.93 | 226.69 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  40.24  | 2.91 | 22.60  | 17.70 |  70.78   |   18.18   |    72.72     |  35.28   | 24.86 | 241.64 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  42.42  | 3.20 | 23.17  | 17.27 |  69.07   |   17.74   |    70.96     |  32.13   | 23.59 | 232.79 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  43.86  | 2.65 | 25.65  | 15.59 |  62.37   |   16.02   |    64.08     |  38.64   | 22.80 | 214.33 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  39.51  | 2.70 | 22.97  | 17.42 |  69.66   |   17.89   |    71.57     |  37.89   | 25.31 | 237.97 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  49.62  | 2.58 | 33.23  | 12.04 |  48.15   |   12.37   |    49.47     |  39.64   | 20.15 | 174.96 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  44.02  | 2.61 | 26.91  | 14.86 |  59.45   |   15.27   |    61.07     |  39.24   | 22.72 | 206.43 |
| quad8_tex8_grey_linear_direct                           |  48.82  | 6.46 | 25.91  | 15.44 |  61.75   |   15.85   |    63.41     |  15.89   | 20.48 | 373.90 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  56.71  | 7.89 | 33.01  | 12.12 |  48.47   |   12.44   |    49.78     |  12.98   | 17.63 | 307.06 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  56.14  | 7.47 | 31.53  | 12.69 |  50.75   |   13.03   |    52.12     |  13.73   | 17.82 | 312.21 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  55.18  | 6.31 | 31.52  | 12.69 |  50.77   |   13.03   |    52.14     |  16.24   | 18.12 | 321.89 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  57.93  | 6.62 | 35.30  | 11.33 |  45.32   |   11.64   |    46.54     |  15.51   | 17.26 | 296.33 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  55.04  | 6.97 | 31.86  | 12.56 |  50.23   |   12.89   |    51.58     |  14.71   | 18.17 | 315.32 |
| quad8_tex8_grey_quintic_bspline_direct                  |  65.05  | 6.66 | 41.31  | 9.68  |  38.73   |   9.94    |    39.78     |  15.37   | 15.37 | 253.07 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  57.92  | 6.99 | 34.51  | 11.59 |  46.36   |   11.90   |    47.61     |  14.65   | 17.27 | 296.22 |
| quad9_tex8_grey_linear_direct                           |  48.72  | 6.92 | 25.09  | 15.94 |  63.78   |   16.38   |    65.51     |  14.84   | 20.53 | 433.62 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  56.63  | 7.52 | 32.16  | 12.44 |  49.75   |   12.78   |    51.10     |  13.63   | 17.66 | 349.29 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  55.84  | 7.38 | 31.32  | 12.77 |  51.08   |   13.12   |    52.47     |  13.88   | 17.91 | 363.93 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.68  | 7.04 | 30.85  | 12.97 |  51.87   |   13.32   |    53.28     |  14.57   | 18.29 | 369.13 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  59.29  | 6.97 | 34.43  | 11.62 |  46.47   |   11.93   |    47.74     |  14.70   | 16.87 | 331.40 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  55.85  | 7.83 | 30.51  | 13.11 |  52.44   |   13.47   |    53.87     |  13.07   | 17.90 | 364.78 |
| quad9_tex8_grey_quintic_bspline_direct                  |  64.65  | 6.74 | 41.39  | 9.66  |  38.66   |   9.93    |    39.71     |  15.18   | 15.47 | 294.48 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  58.50  | 7.10 | 34.10  | 11.73 |  46.92   |   12.05   |    48.20     |  14.45   | 17.09 | 341.49 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  29.12  | 4.18 | 16.44  | 24.34 |  97.36   |   25.19   |    100.76    |  48.97   | 34.34 | 203.51 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  35.79  | 3.71 | 23.78  | 16.82 |  67.27   |   17.40   |    69.62     |  55.26   | 27.94 | 157.49 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  35.44  | 3.95 | 22.82  | 17.53 |  70.12   |   18.14   |    72.57     |  51.87   | 28.23 | 166.94 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  33.85  | 3.67 | 22.59  | 17.70 |  70.82   |   18.32   |    73.29     |  55.74   | 29.54 | 170.10 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  40.29  | 3.77 | 27.35  | 14.63 |  58.51   |   15.14   |    60.55     |  54.27   | 24.83 | 145.09 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  37.36  | 4.10 | 23.31  | 17.16 |  68.65   |   17.76   |    71.05     |  49.95   | 26.77 | 167.59 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  49.54  | 3.87 | 35.66  | 11.22 |  44.87   |   11.61   |    46.43     |  52.91   | 20.19 | 116.01 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  40.49  | 3.62 | 28.17  | 14.20 |  56.80   |   14.70   |    58.78     |  56.53   | 24.70 | 141.55 |
| tri6_tex8_rgb_linear_direct                             |  75.90  | 10.54 | 40.84  | 9.80  |  39.18   |   10.07   |    40.26     |  19.42   | 13.18 | 178.61 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  79.60  | 9.53 | 46.10  | 8.68  |  34.71   |   8.92    |    35.67     |  21.49   | 12.56 | 163.20 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  78.58  | 9.99 | 45.04  | 8.88  |  35.53   |   9.13    |    36.51     |  20.52   | 12.73 | 167.87 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  78.95  | 10.40 | 44.54  | 8.98  |  35.92   |   9.23    |    36.91     |  19.69   | 12.67 | 165.52 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  84.87  | 10.18 | 50.43  | 7.93  |  31.73   |   8.15    |    32.61     |  20.12   | 11.78 | 152.52 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  79.72  | 10.71 | 45.52  | 8.79  |  35.15   |   9.03    |    36.12     |  19.14   | 12.54 | 165.34 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  90.15  | 9.62 | 56.74  | 7.05  |  28.20   |   7.24    |    28.98     |  21.30   | 11.09 | 138.13 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  85.14  | 10.23 | 50.26  | 7.96  |  31.84   |   8.18    |    32.72     |  20.02   | 11.75 | 151.76 |
| quad4ibi_tex8_rgb_linear_direct                         |  22.26  | 3.08 | 13.17  | 30.37 |  121.47  |   31.15   |    124.60    |  33.25   | 44.96 | 353.15 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  32.88  | 3.20 | 23.02  | 17.37 |  69.49   |   17.82   |    71.28     |  31.98   | 30.41 | 225.35 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  33.36  | 3.04 | 24.51  | 16.32 |  65.29   |   16.74   |    66.97     |  33.70   | 29.97 | 219.45 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  32.66  | 2.95 | 23.79  | 16.82 |  67.26   |   17.25   |    68.99     |  34.69   | 30.62 | 225.60 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  38.93  | 2.94 | 29.75  | 13.45 |  53.79   |   13.79   |    55.17     |  34.80   | 25.68 | 185.56 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  33.08  | 3.26 | 23.57  | 16.97 |  67.89   |   17.41   |    69.64     |  31.44   | 30.23 | 223.17 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  48.35  | 3.44 | 37.47  | 10.68 |  42.70   |   10.95   |    43.80     |  29.80   | 20.68 | 147.75 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  41.07  | 2.98 | 31.45  | 12.72 |  50.88   |   13.05   |    52.19     |  34.32   | 24.35 | 175.41 |
| quad4newton_tex8_rgb_linear_direct                      |  43.22  | 3.19 | 23.62  | 16.93 |  67.73   |   17.39   |    69.58     |  32.17   | 23.14 | 222.39 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  49.62  | 2.90 | 30.88  | 12.95 |  51.82   |   13.31   |    53.23     |  35.27   | 20.16 | 179.71 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  46.94  | 2.80 | 28.53  | 14.02 |  56.08   |   14.40   |    57.62     |  36.54   | 21.30 | 193.67 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  47.23  | 3.04 | 28.44  | 14.07 |  56.27   |   14.45   |    57.80     |  33.72   | 21.18 | 194.31 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  53.44  | 3.01 | 34.03  | 11.76 |  47.02   |   12.08   |    48.31     |  34.10   | 18.71 | 160.91 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  47.88  | 2.97 | 29.14  | 13.73 |  54.92   |   14.10   |    56.42     |  34.48   | 20.89 | 189.66 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  59.90  | 2.96 | 40.90  | 9.78  |  39.12   |   10.05   |    40.19     |  34.59   | 16.69 | 138.69 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  52.64  | 2.95 | 33.90  | 11.80 |  47.19   |   12.12   |    48.48     |  34.74   | 19.00 | 165.25 |
| quad8_tex8_rgb_linear_direct                            |  56.18  | 6.81 | 31.71  | 12.61 |  50.45   |   12.95   |    51.81     |  15.03   | 17.80 | 317.44 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  63.74  | 6.58 | 38.72  | 10.33 |  41.32   |   10.61   |    42.44     |  15.58   | 15.70 | 270.41 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  61.85  | 6.51 | 37.48  | 10.67 |  42.69   |   10.96   |    43.84     |  15.74   | 16.17 | 278.02 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  62.82  | 6.53 | 36.91  | 10.84 |  43.35   |   11.13   |    44.52     |  15.67   | 15.92 | 276.56 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  68.99  | 7.46 | 42.50  | 9.41  |  37.65   |   9.66    |    38.66     |  13.74   | 14.49 | 246.47 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  60.97  | 6.53 | 37.17  | 10.76 |  43.05   |   11.05   |    44.21     |  15.68   | 16.40 | 280.04 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  73.17  | 7.17 | 49.16  | 8.14  |  32.54   |   8.36    |    33.42     |  14.27   | 13.67 | 220.64 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  65.33  | 7.23 | 41.17  | 9.71  |  38.86   |   9.98    |    39.91     |  14.17   | 15.31 | 251.59 |
| quad9_tex8_rgb_linear_direct                            |  57.52  | 7.70 | 31.22  | 12.81 |  51.26   |   13.16   |    52.65     |  13.29   | 17.39 | 352.67 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  66.81  | 7.97 | 38.52  | 10.39 |  41.54   |   10.67   |    42.67     |  12.97   | 14.97 | 295.20 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  63.00  | 6.84 | 36.98  | 10.82 |  43.27   |   11.11   |    44.45     |  14.99   | 15.87 | 313.12 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  62.54  | 7.34 | 37.12  | 10.78 |  43.10   |   11.07   |    44.28     |  13.95   | 15.99 | 309.98 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  68.05  | 6.82 | 42.52  | 9.41  |  37.63   |   9.66    |    38.65     |  15.02   | 14.70 | 276.22 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  61.57  | 6.74 | 35.68  | 11.21 |  44.85   |   11.52   |    46.07     |  15.20   | 16.24 | 317.73 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  73.73  | 6.81 | 48.92  | 8.18  |  32.71   |   8.40    |    33.59     |  15.03   | 13.56 | 250.88 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  65.99  | 7.44 | 41.14  | 9.72  |  38.89   |   9.99    |    39.95     |  13.76   | 15.16 | 285.32 |

