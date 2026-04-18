# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  3.63   | 0.01 |  3.61  | 110.73 |  442.90  |  110.73   |    442.90    |   0.17   | 275.26 | 1324.55 |
| tri6_nodal_grey                                         |  17.75  | 0.02 | 17.73  | 22.57 |  90.26   |   22.57   |    90.26     |   0.12   | 56.34 | 541.07 |
| quad4ibi_nodal_grey                                     |  10.23  | 0.01 | 10.21  | 39.17 |  156.67  |   39.17   |    156.67    |   0.10   | 97.73 | 626.00 |
| quad4newton_nodal_grey                                  |  14.10  | 0.01 | 14.08  | 28.41 |  113.64  |   28.41   |    113.64    |   0.09   | 70.94 | 454.17 |
| quad8_nodal_grey                                        |  16.82  | 0.01 | 16.80  | 23.80 |  95.21   |   23.80   |    95.21     |   0.07   | 59.44 | 761.10 |
| quad9_nodal_grey                                        |  17.65  | 0.01 | 17.61  | 22.72 |  90.88   |   22.72   |    90.88     |   0.09   | 56.65 | 817.34 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  7.40   | 0.01 |  7.38  | 54.23 |  216.91  |   54.23   |    216.91    |   0.14   | 135.14 | 649.49 |
| tri6_nodal_rgb                                          |  21.79  | 0.02 | 21.76  | 18.38 |  73.53   |   18.38   |    73.53     |   0.13   | 45.90 | 440.86 |
| quad4ibi_nodal_rgb                                      |  15.75  | 0.01 | 15.72  | 25.45 |  101.81  |   25.45   |    101.81    |   0.08   | 63.51 | 406.85 |
| quad4newton_nodal_rgb                                   |  17.69  | 0.02 | 17.66  | 22.65 |  90.60   |   22.65   |    90.60     |   0.06   | 56.54 | 362.04 |
| quad8_nodal_rgb                                         |  20.70  | 0.02 | 20.68  | 19.34 |  77.37   |   19.34   |    77.37     |   0.06   | 48.30 | 618.57 |
| quad9_nodal_rgb                                         |  21.60  | 0.01 | 21.57  | 18.54 |  74.18   |   18.54   |    74.18     |   0.08   | 46.30 | 667.15 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  9.94   | 0.02 |  9.92  | 40.31 |  161.24  |   40.31   |    161.24    |   0.13   | 100.56 | 482.95 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  24.02  | 0.02 | 23.99  | 16.68 |  66.70   |   16.68   |    66.70     |   0.12   | 41.64 | 199.96 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  18.42  | 0.02 | 18.40  | 21.74 |  86.96   |   21.74   |    86.96     |   0.13   | 54.29 | 260.72 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  18.67  | 0.01 | 18.65  | 21.45 |  85.82   |   21.45   |    85.82     |   0.16   | 53.57 | 257.24 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  25.26  | 0.01 | 25.25  | 15.84 |  63.38   |   15.84   |    63.38     |   0.17   | 39.58 | 190.05 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  18.36  | 0.01 | 18.34  | 21.80 |  87.22   |   21.80   |    87.22     |   0.14   | 54.45 | 261.48 |
| tri3_tex8_grey_quintic_bspline_direct                   |  40.18  | 0.01 | 40.16  | 9.96  |  39.84   |   9.96    |    39.84     |   0.15   | 24.89 | 119.49 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  24.76  | 0.01 | 24.73  | 16.17 |  64.69   |   16.17   |    64.69     |   0.14   | 40.39 | 193.95 |
| tri6_tex8_grey_linear_direct                            |  21.29  | 0.02 | 21.27  | 18.81 |  75.24   |   18.81   |    75.24     |   0.13   | 46.97 | 451.10 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  34.69  | 0.02 | 34.67  | 11.54 |  46.15   |   11.54   |    46.15     |   0.13   | 28.82 | 276.77 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  31.25  | 0.01 | 31.22  | 12.81 |  51.25   |   12.81   |    51.25     |   0.13   | 32.00 | 307.32 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  31.20  | 0.02 | 31.17  | 12.83 |  51.33   |   12.83   |    51.33     |   0.11   | 32.05 | 307.82 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  37.67  | 0.02 | 37.64  | 10.63 |  42.51   |   10.63   |    42.51     |   0.13   | 26.55 | 254.89 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  31.04  | 0.01 | 31.02  | 12.90 |  51.58   |   12.90   |    51.58     |   0.14   | 32.22 | 309.35 |
| tri6_tex8_grey_quintic_bspline_direct                   |  50.76  | 0.02 | 50.73  | 7.88  |  31.54   |   7.88    |    31.54     |   0.12   | 19.70 | 189.16 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  37.90  | 0.02 | 37.87  | 10.56 |  42.25   |   10.56   |    42.25     |   0.12   | 26.39 | 253.39 |
| quad4ibi_tex8_grey_linear_direct                        |  14.37  | 0.01 | 14.34  | 27.89 |  111.55  |   27.89   |    111.55    |   0.08   | 69.60 | 445.70 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  30.86  | 0.01 | 30.84  | 12.97 |  51.87   |   12.97   |    51.87     |   0.09   | 32.40 | 207.41 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  30.61  | 0.01 | 30.59  | 13.08 |  52.31   |   13.08   |    52.31     |   0.09   | 32.67 | 209.16 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  30.96  | 0.01 | 30.94  | 12.93 |  51.72   |   12.93   |    51.72     |   0.09   | 32.30 | 206.81 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  36.59  | 0.01 | 36.57  | 10.94 |  43.75   |   10.94   |    43.75     |   0.08   | 27.33 | 174.96 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  30.76  | 0.01 | 30.74  | 13.01 |  52.05   |   13.01   |    52.05     |   0.09   | 32.51 | 208.14 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  48.10  | 0.01 | 48.07  | 8.32  |  33.29   |   8.32    |    33.29     |   0.08   | 20.79 | 133.09 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  37.12  | 0.01 | 37.10  | 10.78 |  43.13   |   10.78   |    43.13     |   0.09   | 26.94 | 172.44 |
| quad4newton_tex8_grey_linear_direct                     |  17.90  | 0.01 | 17.88  | 22.37 |  89.50   |   22.37   |    89.50     |   0.07   | 55.88 | 357.77 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  31.04  | 0.01 | 31.02  | 12.90 |  51.58   |   12.90   |    51.58     |   0.09   | 32.21 | 206.23 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  27.65  | 0.01 | 27.63  | 14.48 |  57.91   |   14.48   |    57.91     |   0.07   | 36.16 | 231.53 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  27.65  | 0.01 | 27.63  | 14.48 |  57.91   |   14.48   |    57.91     |   0.09   | 36.17 | 231.54 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  33.90  | 0.01 | 33.88  | 11.81 |  47.23   |   11.81   |    47.23     |   0.08   | 29.50 | 188.83 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  27.53  | 0.01 | 27.51  | 14.54 |  58.15   |   14.54   |    58.15     |   0.09   | 36.32 | 232.52 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  47.59  | 0.01 | 47.56  | 8.41  |  33.64   |   8.41    |    33.64     |   0.08   | 21.02 | 134.53 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  34.21  | 0.01 | 34.19  | 11.70 |  46.80   |   11.70   |    46.80     |   0.09   | 29.23 | 187.12 |
| quad8_tex8_grey_linear_direct                           |  21.50  | 0.01 | 21.48  | 18.63 |  74.50   |   18.63   |    74.50     |   0.07   | 46.51 | 595.61 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  35.45  | 0.01 | 35.43  | 11.29 |  45.17   |   11.29   |    45.17     |   0.09   | 28.21 | 361.20 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  31.34  | 0.01 | 31.31  | 12.78 |  51.10   |   12.78   |    51.10     |   0.08   | 31.91 | 408.61 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  31.22  | 0.01 | 31.20  | 12.82 |  51.28   |   12.82   |    51.28     |   0.09   | 32.03 | 410.03 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  37.65  | 0.01 | 37.62  | 10.63 |  42.53   |   10.63   |    42.53     |   0.07   | 26.56 | 340.08 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  31.28  | 0.01 | 31.26  | 12.80 |  51.19   |   12.80   |    51.19     |   0.08   | 31.97 | 409.36 |
| quad8_tex8_grey_quintic_bspline_direct                  |  50.97  | 0.01 | 50.95  | 7.85  |  31.40   |   7.85    |    31.40     |   0.08   | 19.62 | 251.15 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  37.84  | 0.01 | 37.81  | 10.58 |  42.31   |   10.58   |    42.31     |   0.07   | 26.43 | 338.37 |
| quad9_tex8_grey_linear_direct                           |  21.78  | 0.01 | 21.75  | 18.39 |  73.57   |   18.39   |    73.57     |   0.08   | 45.93 | 661.61 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  35.66  | 0.01 | 35.63  | 11.23 |  44.90   |   11.23   |    44.90     |   0.08   | 28.05 | 403.98 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  31.31  | 0.01 | 31.29  | 12.79 |  51.14   |   12.79   |    51.14     |   0.08   | 31.94 | 460.08 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  31.85  | 0.01 | 31.82  | 12.57 |  50.29   |   12.57   |    50.29     |   0.07   | 31.40 | 452.36 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  37.57  | 0.01 | 37.55  | 10.65 |  42.61   |   10.65   |    42.61     |   0.09   | 26.62 | 383.37 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  31.12  | 0.01 | 31.09  | 12.86 |  51.46   |   12.86   |    51.46     |   0.09   | 32.14 | 462.90 |
| quad9_tex8_grey_quintic_bspline_direct                  |  51.24  | 0.02 | 51.22  | 7.81  |  31.24   |   7.81    |    31.24     |   0.06   | 19.52 | 281.07 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  38.03  | 0.01 | 38.00  | 10.53 |  42.10   |   10.53   |    42.10     |   0.08   | 26.30 | 378.77 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  16.90  | 0.02 | 16.87  | 23.72 |  94.87   |   23.72   |    94.87     |   0.13   | 59.17 | 284.33 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  34.01  | 0.02 | 33.98  | 11.77 |  47.09   |   11.77   |    47.09     |   0.12   | 29.40 | 141.17 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  31.17  | 0.01 | 31.14  | 12.84 |  51.37   |   12.84   |    51.37     |   0.15   | 32.08 | 154.05 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  31.29  | 0.01 | 31.26  | 12.80 |  51.18   |   12.80   |    51.18     |   0.14   | 31.96 | 153.48 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  38.69  | 0.01 | 38.66  | 10.35 |  41.38   |   10.35   |    41.38     |   0.13   | 25.84 | 124.10 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  30.16  | 0.02 | 30.13  | 13.27 |  53.10   |   13.27   |    53.10     |   0.12   | 33.15 | 159.20 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  53.24  | 0.02 | 53.22  | 7.52  |  30.07   |   7.52    |    30.07     |   0.11   | 18.78 | 90.17  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  38.83  | 0.02 | 38.80  | 10.31 |  41.24   |   10.31   |    41.24     |   0.11   | 25.75 | 123.67 |
| tri6_tex8_rgb_linear_direct                             |  32.76  | 0.02 | 32.73  | 12.22 |  48.89   |   12.22   |    48.89     |   0.13   | 30.53 | 293.17 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  46.29  | 0.02 | 46.26  | 8.65  |  34.59   |   8.65    |    34.59     |   0.12   | 21.60 | 207.46 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  42.42  | 0.01 | 42.39  | 9.44  |  37.74   |   9.44    |    37.74     |   0.14   | 23.57 | 226.36 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  42.43  | 0.01 | 42.41  | 9.43  |  37.73   |   9.43    |    37.73     |   0.14   | 23.57 | 226.29 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  50.50  | 0.02 | 50.47  | 7.93  |  31.70   |   7.93    |    31.70     |   0.11   | 19.80 | 190.15 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  41.76  | 0.01 | 41.73  | 9.59  |  38.35   |   9.59    |    38.35     |   0.14   | 23.95 | 229.98 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  65.29  | 0.01 | 65.27  | 6.13  |  24.52   |   6.13    |    24.52     |   0.14   | 15.32 | 147.06 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  50.36  | 0.02 | 50.33  | 7.95  |  31.79   |   7.95    |    31.79     |   0.13   | 19.86 | 190.65 |
| quad4ibi_tex8_rgb_linear_direct                         |  20.27  | 0.02 | 20.25  | 19.76 |  79.03   |   19.76   |    79.03     |   0.07   | 49.34 | 315.95 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  39.10  | 0.01 | 39.08  | 10.24 |  40.95   |   10.24   |    40.95     |   0.08   | 25.58 | 163.73 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  37.92  | 0.01 | 37.89  | 10.56 |  42.22   |   10.56   |    42.22     |   0.08   | 26.37 | 168.82 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  38.00  | 0.01 | 37.97  | 10.53 |  42.14   |   10.53   |    42.14     |   0.07   | 26.31 | 168.47 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  49.58  | 0.02 | 49.55  | 8.07  |  32.29   |   8.07    |    32.29     |   0.06   | 20.17 | 129.12 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  37.41  | 0.02 | 37.38  | 10.70 |  42.80   |   10.70   |    42.80     |   0.06   | 26.73 | 171.12 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  66.18  | 0.01 | 66.15  | 6.05  |  24.19   |   6.05    |    24.19     |   0.08   | 15.11 | 96.73  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  50.74  | 0.02 | 50.70  | 7.89  |  31.56   |   7.89    |    31.56     |   0.06   | 19.71 | 126.18 |
| quad4newton_tex8_rgb_linear_direct                      |  29.09  | 0.01 | 29.06  | 13.77 |  55.06   |   13.77   |    55.06     |   0.07   | 34.38 | 220.11 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  42.75  | 0.02 | 42.71  | 9.37  |  37.46   |   9.37    |    37.46     |   0.07   | 23.39 | 149.77 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  38.62  | 0.02 | 38.59  | 10.36 |  41.46   |   10.36   |    41.46     |   0.06   | 25.89 | 165.77 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  38.61  | 0.01 | 38.57  | 10.37 |  41.48   |   10.37   |    41.48     |   0.08   | 25.90 | 165.86 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  46.97  | 0.02 | 46.94  | 8.52  |  34.08   |   8.52    |    34.08     |   0.06   | 21.29 | 136.29 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  38.68  | 0.02 | 38.65  | 10.35 |  41.40   |   10.35   |    41.40     |   0.06   | 25.85 | 165.52 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  61.45  | 0.01 | 61.43  | 6.51  |  26.05   |   6.51    |    26.05     |   0.08   | 16.27 | 104.16 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  46.72  | 0.01 | 46.69  | 8.57  |  34.27   |   8.57    |    34.27     |   0.07   | 21.40 | 137.02 |
| quad8_tex8_rgb_linear_direct                            |  31.25  | 0.01 | 31.22  | 12.81 |  51.24   |   12.81   |    51.24     |   0.08   | 32.00 | 409.79 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  45.42  | 0.01 | 45.39  | 8.81  |  35.25   |   8.81    |    35.25     |   0.09   | 22.02 | 281.94 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  42.70  | 0.01 | 42.67  | 9.37  |  37.50   |   9.37    |    37.50     |   0.07   | 23.42 | 299.89 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  42.81  | 0.02 | 42.77  | 9.35  |  37.41   |   9.35    |    37.41     |   0.06   | 23.36 | 299.17 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  51.06  | 0.01 | 51.03  | 7.84  |  31.36   |   7.84    |    31.36     |   0.08   | 19.59 | 250.76 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  41.87  | 0.01 | 41.84  | 9.56  |  38.24   |   9.56    |    38.24     |   0.07   | 23.88 | 305.83 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  65.71  | 0.01 | 65.68  | 6.09  |  24.36   |   6.09    |    24.36     |   0.08   | 15.22 | 194.86 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  50.98  | 0.01 | 50.95  | 7.85  |  31.40   |   7.85    |    31.40     |   0.08   | 19.62 | 251.17 |
| quad9_tex8_rgb_linear_direct                            |  33.21  | 0.01 | 33.18  | 12.05 |  48.22   |   12.05   |    48.22     |   0.09   | 30.11 | 433.81 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  46.53  | 0.01 | 46.50  | 8.60  |  34.41   |   8.60    |    34.41     |   0.07   | 21.49 | 309.60 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  42.17  | 0.01 | 42.14  | 9.49  |  37.97   |   9.49    |    37.97     |   0.09   | 23.71 | 341.57 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  42.86  | 0.01 | 42.83  | 9.34  |  37.36   |   9.34    |    37.36     |   0.08   | 23.33 | 336.09 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  50.82  | 0.01 | 50.80  | 7.87  |  31.50   |   7.87    |    31.50     |   0.08   | 19.68 | 283.41 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  41.93  | 0.01 | 41.91  | 9.54  |  38.18   |   9.54    |    38.18     |   0.08   | 23.85 | 343.49 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  65.19  | 0.01 | 65.17  | 6.14  |  24.55   |   6.14    |    24.55     |   0.08   | 15.34 | 220.92 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  51.40  | 0.02 | 51.37  | 7.79  |  31.15   |   7.79    |    31.15     |   0.06   | 19.45 | 280.24 |

