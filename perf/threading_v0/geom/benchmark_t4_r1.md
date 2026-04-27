# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  17.32  | 4.49 |  6.22  | 64.29 |  257.15  |   66.53   |    266.12    |  45.57   | 57.74 | 374.80 |
| tri6_nodal_grey                                         |  47.17  | 9.38 | 29.20  | 13.70 |  54.80   |   14.08   |    56.31     |  21.83   | 21.20 | 241.28 |
| quad4ibi_nodal_grey                                     |  14.36  | 2.88 |  8.67  | 46.18 |  184.70  |   47.36   |    189.46    |  35.56   | 69.65 | 516.28 |
| quad4newton_nodal_grey                                  |  26.18  | 2.56 | 14.93  | 26.79 |  107.16  |   27.52   |    110.09    |  40.03   | 38.27 | 335.54 |
| quad8_nodal_grey                                        |  38.02  | 6.06 | 23.52  | 17.01 |  68.04   |   17.47   |    69.87     |  16.92   | 26.30 | 408.59 |
| quad9_nodal_grey                                        |  36.06  | 6.66 | 21.94  | 18.23 |  72.91   |   18.72   |    74.89     |  15.38   | 27.73 | 483.40 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  23.35  | 4.61 |  8.44  | 47.44 |  189.76  |   49.10   |    196.39    |  44.47   | 42.95 | 266.04 |
| tri6_nodal_rgb                                          |  52.70  | 11.13 | 29.87  | 13.39 |  53.57   |   13.76   |    55.05     |  18.40   | 18.98 | 223.14 |
| quad4ibi_nodal_rgb                                      |  20.82  | 3.25 | 11.33  | 35.30 |  141.21  |   36.21   |    144.85    |  31.51   | 48.06 | 361.92 |
| quad4newton_nodal_rgb                                   |  24.56  | 3.18 | 16.32  | 24.52 |  98.07   |   25.19   |    100.75    |  32.18   | 40.72 | 299.67 |
| quad8_nodal_rgb                                         |  41.55  | 7.75 | 24.88  | 16.08 |  64.32   |   16.51   |    66.05     |  13.21   | 24.07 | 371.88 |
| quad9_nodal_rgb                                         |  40.57  | 7.75 | 23.51  | 17.01 |  68.05   |   17.47   |    69.90     |  13.21   | 24.65 | 419.30 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  24.06  | 4.09 | 11.31  | 35.39 |  141.54  |   36.62   |    146.49    |  50.07   | 41.62 | 273.58 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  30.91  | 3.90 | 18.41  | 21.73 |  86.91   |   22.49   |    89.95     |  52.53   | 32.36 | 200.15 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  29.42  | 4.19 | 16.33  | 24.49 |  97.98   |   25.35   |    101.40    |  48.84   | 34.00 | 212.80 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  28.48  | 4.11 | 16.65  | 24.02 |  96.09   |   24.86   |    99.45     |  49.87   | 35.11 | 220.34 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  31.79  | 4.02 | 20.27  | 19.74 |  78.95   |   20.43   |    81.70     |  50.95   | 31.46 | 191.19 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  28.37  | 4.09 | 16.56  | 24.15 |  96.61   |   24.99   |    99.95     |  50.06   | 35.25 | 218.36 |
| tri3_tex8_grey_quintic_bspline_direct                   |  40.23  | 4.05 | 27.81  | 14.39 |  57.55   |   14.89   |    59.56     |  50.62   | 24.86 | 144.20 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  32.06  | 4.24 | 19.88  | 20.13 |  80.50   |   20.83   |    83.31     |  48.27   | 31.20 | 189.60 |
| tri6_tex8_grey_linear_direct                            |  62.68  | 8.78 | 33.40  | 11.97 |  47.90   |   12.31   |    49.22     |  23.33   | 15.96 | 221.48 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  69.97  | 10.14 | 39.38  | 10.16 |  40.63   |   10.44   |    41.75     |  20.22   | 14.29 | 190.54 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  69.18  | 9.74 | 38.26  | 10.46 |  41.82   |   10.74   |    42.98     |  21.04   | 14.46 | 194.88 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  67.60  | 9.42 | 38.22  | 10.46 |  41.86   |   10.75   |    43.02     |  21.77   | 14.79 | 197.37 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  72.88  | 9.91 | 41.99  | 9.53  |  38.10   |   9.79    |    39.16     |  20.66   | 13.72 | 182.60 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  70.11  | 10.21 | 38.89  | 10.29 |  41.15   |   10.57   |    42.28     |  20.05   | 14.26 | 192.64 |
| tri6_tex8_grey_quintic_bspline_direct                   |  78.84  | 9.53 | 48.25  | 8.29  |  33.16   |   8.52    |    34.08     |  21.49   | 12.68 | 162.94 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  73.76  | 9.40 | 42.52  | 9.41  |  37.63   |   9.67    |    38.67     |  21.80   | 13.56 | 181.12 |
| quad4ibi_tex8_grey_linear_direct                        |  19.39  | 3.06 | 10.86  | 36.83 |  147.33  |   37.78   |    151.12    |  33.48   | 51.57 | 420.21 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  25.97  | 2.81 | 19.21  | 20.82 |  83.29   |   21.36   |    85.43     |  36.51   | 38.51 | 281.88 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  26.89  | 2.68 | 19.26  | 20.77 |  83.08   |   21.31   |    85.22     |  38.17   | 37.19 | 277.37 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  26.90  | 2.87 | 19.41  | 20.61 |  82.45   |   21.14   |    84.57     |  35.69   | 37.18 | 274.68 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  31.76  | 2.69 | 23.77  | 16.83 |  67.32   |   17.26   |    69.05     |  38.10   | 31.49 | 230.53 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  27.08  | 2.59 | 19.28  | 20.75 |  82.99   |   21.28   |    85.12     |  39.55   | 36.94 | 274.38 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  36.00  | 3.18 | 28.14  | 14.21 |  56.86   |   14.58   |    58.32     |  32.18   | 27.78 | 199.24 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  32.86  | 2.93 | 24.19  | 16.54 |  66.14   |   16.96   |    67.85     |  35.01   | 30.44 | 221.80 |
| quad4newton_tex8_grey_linear_direct                     |  36.64  | 2.74 | 18.01  | 22.21 |  88.85   |   22.82   |    91.28     |  37.39   | 27.29 | 289.17 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  41.23  | 2.80 | 24.25  | 16.50 |  65.98   |   16.95   |    67.79     |  36.69   | 24.25 | 230.20 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  41.25  | 2.62 | 22.93  | 17.45 |  69.79   |   17.92   |    71.70     |  39.03   | 24.24 | 239.79 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  41.77  | 2.66 | 23.36  | 17.12 |  68.50   |   17.59   |    70.37     |  38.47   | 23.94 | 236.86 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  45.23  | 2.72 | 26.02  | 15.37 |  61.48   |   15.79   |    63.16     |  37.65   | 22.11 | 209.53 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  40.26  | 2.77 | 22.88  | 17.49 |  69.96   |   17.97   |    71.87     |  37.01   | 24.84 | 240.94 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  50.18  | 2.67 | 33.12  | 12.08 |  48.31   |   12.41   |    49.63     |  38.37   | 19.93 | 172.58 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  44.60  | 3.05 | 25.68  | 15.58 |  62.30   |   16.00   |    64.00     |  33.68   | 22.42 | 213.68 |
| quad8_tex8_grey_linear_direct                           |  48.28  | 6.37 | 26.15  | 15.30 |  61.19   |   15.71   |    62.84     |  16.07   | 20.71 | 369.59 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  56.32  | 6.41 | 33.17  | 12.06 |  48.24   |   12.38   |    49.54     |  16.00   | 17.76 | 311.58 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  55.06  | 6.67 | 31.84  | 12.56 |  50.25   |   12.90   |    51.61     |  15.36   | 18.16 | 321.82 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.43  | 6.62 | 31.94  | 12.52 |  50.09   |   12.86   |    51.43     |  15.49   | 18.37 | 327.19 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  59.11  | 6.83 | 35.52  | 11.26 |  45.04   |   11.56   |    46.25     |  15.03   | 16.92 | 294.98 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  52.79  | 6.61 | 31.54  | 12.68 |  50.74   |   13.03   |    52.10     |  15.50   | 18.94 | 323.76 |
| quad8_tex8_grey_quintic_bspline_direct                  |  65.76  | 6.80 | 41.85  | 9.56  |  38.23   |   9.81    |    39.26     |  15.06   | 15.21 | 251.01 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  59.13  | 6.65 | 34.77  | 11.50 |  46.02   |   11.81   |    47.26     |  15.39   | 16.91 | 293.37 |
| quad9_tex8_grey_linear_direct                           |  50.30  | 7.36 | 25.35  | 15.78 |  63.12   |   16.21   |    64.83     |  13.91   | 19.88 | 424.15 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  56.24  | 6.65 | 32.49  | 12.31 |  49.24   |   12.65   |    50.58     |  15.41   | 17.78 | 353.80 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  55.24  | 6.95 | 31.03  | 12.89 |  51.56   |   13.24   |    52.96     |  14.73   | 18.10 | 366.09 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.94  | 7.19 | 30.34  | 13.19 |  52.74   |   13.54   |    54.17     |  14.26   | 18.21 | 371.69 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  59.94  | 7.63 | 34.32  | 11.66 |  46.62   |   11.97   |    47.89     |  13.43   | 16.68 | 334.54 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  55.65  | 6.98 | 31.32  | 12.77 |  51.09   |   13.12   |    52.48     |  14.67   | 17.97 | 367.97 |
| quad9_tex8_grey_quintic_bspline_direct                  |  68.03  | 7.56 | 41.05  | 9.74  |  38.98   |   10.01   |    40.04     |  13.54   | 14.70 | 289.51 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  58.73  | 7.06 | 34.33  | 11.65 |  46.60   |   11.97   |    47.87     |  14.50   | 17.03 | 339.80 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  30.03  | 4.32 | 16.28  | 24.57 |  98.29   |   25.43   |    101.72    |  47.42   | 33.34 | 206.20 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  35.79  | 3.96 | 23.85  | 16.77 |  67.09   |   17.36   |    69.43     |  51.72   | 27.94 | 161.24 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  34.07  | 3.48 | 22.39  | 17.87 |  71.47   |   18.49   |    73.97     |  58.90   | 29.35 | 171.08 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  35.31  | 4.27 | 22.10  | 18.10 |  72.40   |   18.73   |    74.93     |  47.95   | 28.39 | 169.98 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  40.74  | 4.07 | 27.55  | 14.52 |  58.07   |   15.03   |    60.10     |  50.62   | 24.54 | 137.35 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  36.27  | 4.23 | 22.25  | 17.98 |  71.91   |   18.61   |    74.42     |  48.43   | 27.57 | 165.27 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  48.10  | 3.92 | 34.45  | 11.61 |  46.44   |   12.02   |    48.06     |  52.37   | 20.79 | 116.14 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  41.71  | 3.64 | 27.83  | 14.37 |  57.49   |   14.87   |    59.50     |  56.25   | 23.98 | 144.45 |
| tri6_tex8_rgb_linear_direct                             |  74.48  | 10.18 | 40.69  | 9.83  |  39.33   |   10.10   |    40.41     |  20.12   | 13.43 | 181.13 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  80.24  | 10.02 | 47.43  | 8.43  |  33.73   |   8.67    |    34.66     |  20.44   | 12.46 | 161.89 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  79.53  | 10.86 | 44.86  | 8.92  |  35.67   |   9.16    |    36.65     |  18.87   | 12.58 | 164.97 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  80.14  | 10.88 | 44.50  | 8.99  |  35.95   |   9.24    |    36.94     |  18.83   | 12.48 | 167.83 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  84.91  | 10.56 | 50.30  | 7.95  |  31.81   |   8.17    |    32.69     |  19.39   | 11.78 | 152.65 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  80.31  | 10.34 | 45.36  | 8.82  |  35.28   |   9.06    |    36.25     |  19.80   | 12.45 | 167.86 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  92.67  | 10.15 | 58.00  | 6.90  |  27.59   |   7.09    |    28.35     |  20.23   | 10.79 | 135.49 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  84.13  | 9.94 | 50.57  | 7.91  |  31.64   |   8.13    |    32.52     |  20.63   | 11.89 | 153.85 |
| quad4ibi_tex8_rgb_linear_direct                         |  23.38  | 2.92 | 13.65  | 29.30 |  117.19  |   30.05   |    120.21    |  35.10   | 42.80 | 340.73 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  32.86  | 2.98 | 22.87  | 17.49 |  69.96   |   17.94   |    71.76     |  34.39   | 30.44 | 229.01 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  32.77  | 2.95 | 23.93  | 16.72 |  66.87   |   17.15   |    68.59     |  34.74   | 30.52 | 224.49 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  33.51  | 3.06 | 24.66  | 16.22 |  64.89   |   16.64   |    66.56     |  33.44   | 29.84 | 218.39 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  39.37  | 2.88 | 31.13  | 12.85 |  51.40   |   13.18   |    52.73     |  35.61   | 25.40 | 181.80 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  33.03  | 2.99 | 23.71  | 16.87 |  67.49   |   17.31   |    69.23     |  34.26   | 30.27 | 224.35 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  48.04  | 3.50 | 37.69  | 10.61 |  42.46   |   10.89   |    43.55     |  29.22   | 20.82 | 149.14 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  39.56  | 2.92 | 30.36  | 13.17 |  52.70   |   13.51   |    54.06     |  35.04   | 25.28 | 182.81 |
| quad4newton_tex8_rgb_linear_direct                      |  42.32  | 2.86 | 23.59  | 16.96 |  67.82   |   17.42   |    69.67     |  35.76   | 23.63 | 229.98 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  50.67  | 2.97 | 30.52  | 13.10 |  52.42   |   13.46   |    53.85     |  34.51   | 19.74 | 180.81 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  47.41  | 2.95 | 28.68  | 13.95 |  55.79   |   14.33   |    57.31     |  34.72   | 21.09 | 188.64 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  47.12  | 2.87 | 28.72  | 13.93 |  55.70   |   14.31   |    57.22     |  35.64   | 21.22 | 190.31 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  52.90  | 2.92 | 33.89  | 11.81 |  47.22   |   12.13   |    48.51     |  35.05   | 18.91 | 162.23 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  48.19  | 2.98 | 29.13  | 13.73 |  54.92   |   14.11   |    56.42     |  34.31   | 20.75 | 187.55 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  60.33  | 3.20 | 40.97  | 9.76  |  39.05   |   10.03   |    40.12     |  32.01   | 16.58 | 137.70 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  53.13  | 3.07 | 33.57  | 11.91 |  47.66   |   12.24   |    48.96     |  33.32   | 18.82 | 166.23 |
| quad8_tex8_rgb_linear_direct                            |  57.04  | 6.42 | 33.07  | 12.10 |  48.38   |   12.42   |    49.69     |  15.95   | 17.53 | 306.99 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  63.18  | 7.30 | 39.30  | 10.18 |  40.71   |   10.45   |    41.80     |  14.03   | 15.83 | 265.75 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  61.66  | 6.50 | 38.45  | 10.40 |  41.61   |   10.68   |    42.73     |  15.75   | 16.22 | 273.46 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  61.77  | 6.68 | 37.96  | 10.54 |  42.17   |   10.83   |    43.30     |  15.33   | 16.19 | 277.09 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  67.17  | 6.59 | 42.84  | 9.34  |  37.34   |   9.59    |    38.35     |  15.56   | 14.89 | 248.26 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  59.22  | 6.50 | 36.97  | 10.82 |  43.28   |   11.11   |    44.44     |  15.77   | 16.89 | 283.49 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  74.20  | 6.69 | 49.84  | 8.03  |  32.10   |   8.24    |    32.97     |  15.31   | 13.48 | 216.16 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  65.02  | 6.77 | 42.21  | 9.48  |  37.90   |   9.73    |    38.92     |  15.17   | 15.39 | 252.26 |
| quad9_tex8_rgb_linear_direct                            |  56.68  | 6.55 | 31.03  | 12.89 |  51.56   |   13.24   |    52.96     |  15.63   | 17.65 | 348.81 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  62.89  | 7.24 | 38.14  | 10.49 |  41.96   |   10.77   |    43.10     |  14.14   | 15.90 | 306.08 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  62.04  | 6.85 | 37.20  | 10.75 |  43.01   |   11.04   |    44.18     |  14.96   | 16.12 | 309.47 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  63.90  | 7.03 | 38.26  | 10.46 |  41.84   |   10.74   |    42.98     |  14.56   | 15.65 | 302.22 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  63.72  | 6.82 | 41.91  | 9.54  |  38.18   |   9.80    |    39.21     |  15.04   | 15.69 | 285.84 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  66.67  | 6.65 | 42.72  | 9.36  |  37.45   |   9.62    |    38.47     |  15.40   | 15.01 | 277.32 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  73.96  | 6.51 | 50.95  | 7.85  |  31.40   |   8.06    |    32.26     |  15.74   | 13.52 | 243.62 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  63.18  | 6.64 | 40.22  | 9.95  |  39.78   |   10.22   |    40.86     |  15.42   | 15.83 | 295.29 |

