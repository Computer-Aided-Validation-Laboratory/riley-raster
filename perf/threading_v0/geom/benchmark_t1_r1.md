# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  40.69  | 16.65 | 19.69  | 20.31 |  81.24   |   20.98   |    83.93     |   0.00   | 24.58 | 128.51 |
| tri6_nodal_grey                                         | 153.01  | 47.85 | 97.24  | 4.11  |  16.46   |   4.23    |    16.91     |   0.00   | 6.54 | 65.23  |
| quad4ibi_nodal_grey                                     |  37.13  | 7.21 | 26.89  | 14.87 |  59.49   |   15.23   |    60.92     |   0.00   | 26.93 | 181.80 |
| quad4newton_nodal_grey                                  |  57.26  | 6.73 | 48.06  | 8.32  |  33.29   |   8.55    |    34.19     |   0.00   | 17.46 | 115.98 |
| quad8_nodal_grey                                        | 115.83  | 31.11 | 78.10  | 5.12  |  20.49   |   5.25    |    21.02     |   0.00   | 8.63 | 115.31 |
| quad9_nodal_grey                                        | 115.09  | 32.74 | 74.92  | 5.34  |  21.36   |   5.48    |    21.93     |   0.00   | 8.69 | 131.05 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  47.65  | 16.74 | 26.05  | 15.36 |  61.43   |   15.87   |    63.46     |   0.00   | 20.99 | 107.60 |
| tri6_nodal_rgb                                          | 178.45  | 62.46 | 104.53 | 3.83  |  15.31   |   3.93    |    15.73     |   0.00   | 5.60 | 56.16  |
| quad4ibi_nodal_rgb                                      |  52.56  | 11.31 | 35.28  | 11.34 |  45.36   |   11.61   |    46.44     |   0.00   | 19.03 | 130.40 |
| quad4newton_nodal_rgb                                   |  68.76  | 11.39 | 53.52  | 7.47  |  29.90   |   7.68    |    30.71     |   0.00   | 14.54 | 96.84  |
| quad8_nodal_rgb                                         | 132.87  | 40.59 | 84.78  | 4.72  |  18.87   |   4.84    |    19.36     |   0.00   | 7.53 | 100.90 |
| quad9_nodal_rgb                                         | 132.20  | 42.68 | 81.20  | 4.93  |  19.71   |   5.06    |    20.25     |   0.00   | 7.56 | 114.13 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  60.63  | 17.51 | 36.65  | 10.92 |  43.66   |   11.28   |    45.11     |   0.00   | 16.49 | 87.22  |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  88.36  | 17.60 | 63.93  | 6.26  |  25.03   |   6.47    |    25.86     |   0.00   | 11.32 | 58.06  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  80.75  | 17.38 | 56.03  | 7.14  |  28.56   |   7.38    |    29.50     |   0.00   | 12.38 | 63.94  |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  81.34  | 17.50 | 56.02  | 7.14  |  28.56   |   7.38    |    29.51     |   0.00   | 12.30 | 63.49  |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  92.35  | 17.32 | 67.48  | 5.93  |  23.71   |   6.12    |    24.50     |   0.00   | 10.83 | 56.30  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  82.00  | 17.23 | 56.43  | 7.09  |  28.35   |   7.32    |    29.29     |   0.00   | 12.20 | 62.95  |
| tri3_tex8_grey_quintic_bspline_direct                   | 119.21  | 17.35 | 94.46  | 4.23  |  16.94   |   4.38    |    17.50     |   0.00   | 8.39 | 42.24  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  91.91  | 17.52 | 67.59  | 5.92  |  23.67   |   6.11    |    24.46     |   0.00   | 10.88 | 55.62  |
| tri6_tex8_grey_linear_direct                            | 181.45  | 49.78 | 111.19 | 3.60  |  14.39   |   3.70    |    14.79     |   0.00   | 5.51 | 58.88  |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 206.33  | 49.50 | 136.71 | 2.93  |  11.70   |   3.01    |    12.03     |   0.00   | 4.85 | 50.82  |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 202.00  | 49.31 | 130.99 | 3.05  |  12.22   |   3.14    |    12.55     |   0.00   | 4.95 | 52.47  |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 199.67  | 49.22 | 130.06 | 3.08  |  12.30   |   3.16    |    12.64     |   0.00   | 5.01 | 52.76  |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 212.38  | 49.60 | 142.37 | 2.81  |  11.24   |   2.89    |    11.55     |   0.00   | 4.71 | 49.28  |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 199.95  | 49.88 | 130.08 | 3.07  |  12.30   |   3.16    |    12.64     |   0.00   | 5.00 | 52.78  |
| tri6_tex8_grey_quintic_bspline_direct                   | 236.04  | 49.85 | 166.18 | 2.41  |   9.63   |   2.47    |     9.90     |   0.00   | 4.24 | 43.96  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 208.73  | 49.40 | 139.72 | 2.86  |  11.45   |   2.94    |    11.77     |   0.00   | 4.79 | 50.31  |
| quad4ibi_tex8_grey_linear_direct                        |  47.56  | 6.75 | 36.18  | 11.06 |  44.22   |   11.32   |    45.28     |   0.00   | 21.03 | 144.39 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  76.75  | 6.69 | 65.89  | 6.07  |  24.28   |   6.22    |    24.87     |   0.00   | 13.03 | 87.02  |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  76.49  | 6.41 | 65.69  | 6.09  |  24.36   |   6.24    |    24.94     |   0.00   | 13.07 | 87.30  |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  77.18  | 6.43 | 65.74  | 6.08  |  24.34   |   6.23    |    24.92     |   0.00   | 12.96 | 86.49  |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  91.45  | 6.35 | 81.58  | 4.90  |  19.61   |   5.02    |    20.08     |   0.00   | 10.93 | 72.48  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  76.48  | 6.41 | 66.42  | 6.02  |  24.09   |   6.17    |    24.67     |   0.00   | 13.08 | 87.32  |
| quad4ibi_tex8_grey_quintic_bspline_direct               | 107.70  | 6.42 | 97.86  | 4.09  |  16.35   |   4.19    |    16.74     |   0.00   | 9.28 | 61.19  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  93.72  | 6.40 | 83.43  | 4.80  |  19.18   |   4.91    |    19.64     |   0.00   | 10.67 | 70.72  |
| quad4newton_tex8_grey_linear_direct                     |  78.19  | 6.42 | 58.91  | 6.79  |  27.16   |   6.97    |    27.90     |   0.00   | 12.79 | 97.18  |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          | 105.06  | 6.44 | 83.89  | 4.77  |  19.07   |   4.90    |    19.59     |   0.00   | 9.52 | 69.33  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  96.58  | 6.44 | 77.50  | 5.16  |  20.64   |   5.30    |    21.20     |   0.00   | 10.35 | 75.97  |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  97.72  | 6.45 | 77.45  | 5.16  |  20.66   |   5.30    |    21.22     |   0.00   | 10.23 | 75.09  |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 | 108.05  | 6.46 | 89.15  | 4.49  |  17.95   |   4.61    |    18.43     |   0.00   | 9.25 | 66.70  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  97.90  | 6.48 | 78.71  | 5.08  |  20.33   |   5.22    |    20.88     |   0.00   | 10.22 | 74.78  |
| quad4newton_tex8_grey_quintic_bspline_direct            | 135.87  | 6.45 | 115.79 | 3.45  |  13.82   |   3.55    |    14.19     |   0.00   | 7.36 | 51.78  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          | 109.61  | 6.47 | 90.09  | 4.44  |  17.76   |   4.56    |    18.24     |   0.00   | 9.12 | 65.92  |
| quad8_tex8_grey_linear_direct                           | 135.49  | 31.70 | 90.53  | 4.42  |  17.68   |   4.53    |    18.13     |   0.00   | 7.38 | 104.19 |
| quad8_tex8_grey_cubic_catmull_rom_direct                | 159.53  | 31.85 | 113.47 | 3.53  |  14.10   |   3.62    |    14.47     |   0.00   | 6.27 | 87.29  |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              | 158.51  | 31.55 | 108.30 | 3.69  |  14.78   |   3.79    |    15.16     |   0.00   | 6.31 | 88.48  |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 151.56  | 31.33 | 107.13 | 3.73  |  14.93   |   3.83    |    15.32     |   0.00   | 6.60 | 91.91  |
| quad8_tex8_grey_lanczos3_lut_lerp                       | 165.11  | 32.06 | 118.81 | 3.37  |  13.47   |   3.45    |    13.82     |   0.00   | 6.06 | 84.17  |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  | 153.30  | 31.85 | 106.44 | 3.76  |  15.03   |   3.86    |    15.42     |   0.00   | 6.52 | 91.02  |
| quad8_tex8_grey_quintic_bspline_direct                  | 192.15  | 31.81 | 145.56 | 2.75  |  10.99   |   2.82    |    11.28     |   0.00   | 5.20 | 71.66  |
| quad8_tex8_grey_quintic_bspline_lut_lerp                | 164.99  | 31.30 | 118.33 | 3.38  |  13.52   |   3.47    |    13.87     |   0.00   | 6.06 | 84.52  |
| quad9_tex8_grey_linear_direct                           | 136.93  | 34.25 | 87.92  | 4.55  |  18.20   |   4.67    |    18.69     |   0.00   | 7.30 | 116.52 |
| quad9_tex8_grey_cubic_catmull_rom_direct                | 160.21  | 33.86 | 111.54 | 3.59  |  14.34   |   3.68    |    14.73     |   0.00   | 6.24 | 98.46  |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              | 156.80  | 33.17 | 104.34 | 3.83  |  15.33   |   3.94    |    15.75     |   0.00   | 6.38 | 102.01 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 163.39  | 36.48 | 112.17 | 3.57  |  14.26   |   3.66    |    14.65     |   0.00   | 6.12 | 96.40  |
| quad9_tex8_grey_lanczos3_lut_lerp                       | 177.43  | 36.88 | 125.06 | 3.20  |  12.79   |   3.28    |    13.14     |   0.00   | 5.64 | 88.68  |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  | 165.56  | 35.89 | 113.32 | 3.53  |  14.12   |   3.63    |    14.50     |   0.00   | 6.04 | 95.66  |
| quad9_tex8_grey_quintic_bspline_direct                  | 204.00  | 35.79 | 153.28 | 2.61  |  10.44   |   2.68    |    10.72     |   0.00   | 4.90 | 75.95  |
| quad9_tex8_grey_quintic_bspline_lut_lerp                | 175.32  | 35.43 | 125.57 | 3.19  |  12.74   |   3.27    |    13.09     |   0.00   | 5.70 | 89.40  |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  77.20  | 13.08 | 57.08  | 7.01  |  28.03   |   7.24    |    28.96     |   0.00   | 12.95 | 66.32  |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  | 121.89  | 13.11 | 101.93 | 3.92  |  15.70   |   4.05    |    16.22     |   0.00   | 8.21 | 41.02  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                | 120.46  | 13.28 | 99.69  | 4.01  |  16.05   |   4.15    |    16.58     |   0.00   | 8.30 | 41.51  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 106.07  | 13.30 | 82.97  | 4.82  |  19.29   |   4.98    |    19.93     |   0.00   | 9.43 | 47.77  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         | 137.29  | 13.28 | 116.88 | 3.42  |  13.69   |   3.54    |    14.14     |   0.00   | 7.28 | 36.28  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    | 117.81  | 13.39 | 96.98  | 4.12  |  16.50   |   4.26    |    17.05     |   0.00   | 8.49 | 42.50  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 162.87  | 13.52 | 142.41 | 2.81  |  11.24   |   2.90    |    11.61     |   0.00   | 6.14 | 30.38  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  | 125.86  | 13.04 | 104.20 | 3.84  |  15.36   |   3.97    |    15.86     |   0.00   | 7.95 | 39.97  |
| tri6_tex8_rgb_linear_direct                             | 211.49  | 53.35 | 135.68 | 2.95  |  11.79   |   3.03    |    12.12     |   0.00   | 4.73 | 49.93  |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 233.27  | 54.29 | 158.81 | 2.52  |  10.08   |   2.59    |    10.36     |   0.00   | 4.29 | 44.62  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 228.24  | 53.95 | 154.60 | 2.59  |  10.35   |   2.66    |    10.64     |   0.00   | 4.38 | 45.54  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 226.93  | 53.93 | 153.48 | 2.61  |  10.43   |   2.68    |    10.72     |   0.00   | 4.41 | 45.90  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 249.01  | 54.10 | 170.09 | 2.35  |   9.41   |   2.42    |     9.67     |   0.00   | 4.02 | 42.29  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 229.61  | 53.93 | 152.80 | 2.62  |  10.47   |   2.69    |    10.76     |   0.00   | 4.36 | 45.56  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 275.68  | 53.63 | 198.96 | 2.01  |   8.04   |   2.07    |     8.27     |   0.00   | 3.63 | 37.47  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 249.94  | 53.80 | 175.38 | 2.28  |   9.12   |   2.34    |     9.38     |   0.00   | 4.00 | 41.66  |
| quad4ibi_tex8_rgb_linear_direct                         |  58.81  | 8.86 | 44.24  | 9.04  |  36.17   |   9.26    |    37.04     |   0.00   | 17.00 | 116.50 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  93.60  | 8.83 | 78.93  | 5.07  |  20.27   |   5.19    |    20.76     |   0.00   | 10.68 | 71.33  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            | 100.17  | 8.86 | 83.73  | 4.78  |  19.12   |   4.89    |    19.57     |   0.00   | 9.98 | 67.81  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  97.74  | 8.85 | 82.10  | 4.87  |  19.49   |   4.99    |    19.96     |   0.00   | 10.23 | 68.18  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 118.54  | 8.92 | 104.31 | 3.83  |  15.34   |   3.93    |    15.71     |   0.00   | 8.44 | 55.76  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  96.80  | 8.93 | 82.88  | 4.83  |  19.31   |   4.94    |    19.77     |   0.00   | 10.33 | 68.98  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 147.97  | 8.89 | 132.93 | 3.01  |  12.04   |   3.08    |    12.33     |   0.00   | 6.76 | 44.37  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 120.90  | 8.88 | 107.11 | 3.73  |  14.94   |   3.82    |    15.30     |   0.00   | 8.27 | 54.63  |
| quad4newton_tex8_rgb_linear_direct                      | 102.83  | 8.92 | 80.00  | 5.00  |  20.00   |   5.14    |    20.54     |   0.00   | 9.72 | 71.07  |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           | 129.18  | 8.92 | 106.15 | 3.77  |  15.07   |   3.87    |    15.48     |   0.00   | 7.74 | 55.02  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         | 120.93  | 8.91 | 98.15  | 4.08  |  16.30   |   4.19    |    16.74     |   0.00   | 8.27 | 59.15  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  | 121.46  | 8.95 | 98.21  | 4.07  |  16.29   |   4.18    |    16.73     |   0.00   | 8.23 | 59.08  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  | 141.44  | 8.90 | 118.21 | 3.38  |  13.54   |   3.48    |    13.90     |   0.00   | 7.07 | 49.89  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             | 121.57  | 8.88 | 98.14  | 4.08  |  16.30   |   4.19    |    16.75     |   0.00   | 8.23 | 58.79  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 168.54  | 8.86 | 143.84 | 2.78  |  11.12   |   2.86    |    11.42     |   0.00   | 5.93 | 41.07  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           | 141.46  | 8.99 | 116.52 | 3.43  |  13.73   |   3.53    |    14.10     |   0.00   | 7.07 | 49.84  |
| quad8_tex8_rgb_linear_direct                            | 158.87  | 35.01 | 108.10 | 3.70  |  14.80   |   3.80    |    15.19     |   0.00   | 6.29 | 87.98  |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 186.92  | 34.93 | 135.80 | 2.95  |  11.78   |   3.02    |    12.09     |   0.00   | 5.35 | 73.98  |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               | 179.29  | 34.91 | 128.76 | 3.11  |  12.43   |   3.19    |    12.75     |   0.00   | 5.58 | 77.07  |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 181.45  | 34.89 | 129.82 | 3.08  |  12.33   |   3.16    |    12.65     |   0.00   | 5.51 | 75.97  |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 197.39  | 35.32 | 144.46 | 2.77  |  11.08   |   2.84    |    11.36     |   0.00   | 5.07 | 69.66  |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   | 178.44  | 34.92 | 127.59 | 3.14  |  12.54   |   3.22    |    12.87     |   0.00   | 5.60 | 77.57  |
| quad8_tex8_rgb_quintic_bspline_direct                   | 224.89  | 34.93 | 173.80 | 2.30  |   9.21   |   2.36    |     9.45     |   0.00   | 4.45 | 60.46  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 196.54  | 34.94 | 146.11 | 2.74  |  10.95   |   2.81    |    11.24     |   0.00   | 5.09 | 69.85  |
| quad9_tex8_rgb_linear_direct                            | 174.62  | 39.43 | 118.53 | 3.37  |  13.50   |   3.47    |    13.86     |   0.00   | 5.73 | 90.26  |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 200.74  | 39.55 | 144.62 | 2.77  |  11.06   |   2.84    |    11.36     |   0.00   | 4.98 | 77.59  |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               | 192.99  | 40.70 | 137.62 | 2.91  |  11.63   |   2.99    |    11.94     |   0.00   | 5.18 | 80.39  |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 191.12  | 38.98 | 136.30 | 2.93  |  11.74   |   3.01    |    12.06     |   0.00   | 5.23 | 81.70  |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 210.09  | 39.39 | 155.27 | 2.58  |  10.30   |   2.65    |    10.58     |   0.00   | 4.76 | 73.54  |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   | 192.12  | 38.99 | 137.23 | 2.91  |  11.66   |   2.99    |    11.97     |   0.00   | 5.21 | 80.93  |
| quad9_tex8_rgb_quintic_bspline_direct                   | 238.93  | 39.27 | 184.12 | 2.17  |   8.69   |   2.23    |     8.92     |   0.00   | 4.19 | 64.10  |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 212.02  | 39.44 | 156.40 | 2.56  |  10.23   |   2.63    |    10.51     |   0.00   | 4.72 | 72.93  |

