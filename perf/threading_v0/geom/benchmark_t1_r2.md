# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  43.74  | 17.42 | 21.84  | 18.32 |  73.27   |   18.92   |    75.70     |   0.00   | 22.86 | 119.92 |
| tri6_nodal_grey                                         | 154.25  | 50.55 | 96.45  | 4.15  |  16.59   |   4.26    |    17.05     |   0.00   | 6.48 | 64.69  |
| quad4ibi_nodal_grey                                     |  36.50  | 6.97 | 26.84  | 14.90 |  59.61   |   15.26   |    61.04     |   0.00   | 27.40 | 184.82 |
| quad4newton_nodal_grey                                  |  57.74  | 7.05 | 47.59  | 8.40  |  33.62   |   8.63    |    34.53     |   0.00   | 17.32 | 114.65 |
| quad8_nodal_grey                                        | 114.56  | 31.11 | 76.99  | 5.20  |  20.78   |   5.33    |    21.32     |   0.00   | 8.73 | 116.84 |
| quad9_nodal_grey                                        | 118.53  | 33.78 | 77.87  | 5.14  |  20.55   |   5.28    |    21.10     |   0.00   | 8.44 | 127.48 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  50.64  | 17.79 | 27.68  | 14.45 |  57.81   |   14.93   |    59.73     |   0.00   | 19.75 | 100.98 |
| tri6_nodal_rgb                                          | 178.12  | 64.58 | 103.99 | 3.85  |  15.39   |   3.95    |    15.81     |   0.00   | 5.61 | 56.51  |
| quad4ibi_nodal_rgb                                      |  51.77  | 11.32 | 35.41  | 11.30 |  45.18   |   11.57   |    46.27     |   0.00   | 19.32 | 130.27 |
| quad4newton_nodal_rgb                                   |  70.69  | 11.34 | 53.63  | 7.46  |  29.84   |   7.66    |    30.65     |   0.00   | 14.15 | 94.25  |
| quad8_nodal_rgb                                         | 134.54  | 42.18 | 82.92  | 4.82  |  19.30   |   4.95    |    19.80     |   0.00   | 7.43 | 100.78 |
| quad9_nodal_rgb                                         | 135.58  | 43.30 | 84.08  | 4.76  |  19.03   |   4.89    |    19.55     |   0.00   | 7.38 | 111.66 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  65.00  | 18.78 | 39.39  | 10.16 |  40.62   |   10.49   |    41.97     |   0.00   | 15.38 | 80.97  |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  93.04  | 18.51 | 67.87  | 5.89  |  23.57   |   6.09    |    24.36     |   0.00   | 10.75 | 55.03  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  86.04  | 18.03 | 61.24  | 6.53  |  26.13   |   6.75    |    26.99     |   0.00   | 11.62 | 60.10  |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  80.68  | 17.02 | 57.37  | 6.97  |  27.89   |   7.20    |    28.82     |   0.00   | 12.40 | 63.85  |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  92.88  | 17.22 | 68.78  | 5.82  |  23.26   |   6.01    |    24.03     |   0.00   | 10.77 | 55.09  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  80.15  | 17.03 | 56.41  | 7.09  |  28.37   |   7.33    |    29.31     |   0.00   | 12.48 | 64.55  |
| tri3_tex8_grey_quintic_bspline_direct                   | 119.62  | 16.89 | 94.35  | 4.24  |  16.96   |   4.38    |    17.52     |   0.00   | 8.36 | 42.14  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  92.28  | 16.95 | 67.58  | 5.92  |  23.67   |   6.11    |    24.46     |   0.00   | 10.84 | 55.35  |
| tri6_tex8_grey_linear_direct                            | 184.73  | 52.45 | 113.46 | 3.53  |  14.10   |   3.62    |    14.49     |   0.00   | 5.41 | 57.37  |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 211.24  | 52.51 | 138.42 | 2.89  |  11.56   |   2.97    |    11.88     |   0.00   | 4.73 | 49.85  |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 201.11  | 52.05 | 129.59 | 3.09  |  12.35   |   3.17    |    12.69     |   0.00   | 4.97 | 52.21  |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 202.69  | 51.77 | 129.95 | 3.08  |  12.31   |   3.16    |    12.65     |   0.00   | 4.93 | 52.71  |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 215.73  | 51.50 | 143.11 | 2.80  |  11.18   |   2.87    |    11.49     |   0.00   | 4.64 | 48.32  |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 201.17  | 51.72 | 130.93 | 3.06  |  12.22   |   3.14    |    12.56     |   0.00   | 4.97 | 52.38  |
| tri6_tex8_grey_quintic_bspline_direct                   | 238.81  | 51.78 | 167.20 | 2.39  |   9.57   |   2.46    |     9.84     |   0.00   | 4.19 | 43.37  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 214.23  | 51.68 | 142.51 | 2.81  |  11.23   |   2.89    |    11.54     |   0.00   | 4.67 | 48.75  |
| quad4ibi_tex8_grey_linear_direct                        |  47.64  | 6.55 | 36.44  | 10.98 |  43.91   |   11.24   |    44.96     |   0.00   | 21.00 | 143.98 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  77.42  | 6.53 | 65.57  | 6.10  |  24.40   |   6.25    |    24.99     |   0.00   | 12.92 | 86.23  |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  77.81  | 6.74 | 66.20  | 6.04  |  24.17   |   6.19    |    24.75     |   0.00   | 12.85 | 85.85  |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  77.60  | 6.72 | 66.72  | 6.00  |  23.98   |   6.14    |    24.56     |   0.00   | 12.89 | 85.98  |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  92.31  | 6.78 | 81.54  | 4.91  |  19.62   |   5.02    |    20.09     |   0.00   | 10.83 | 71.79  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  76.53  | 6.73 | 65.74  | 6.08  |  24.34   |   6.23    |    24.92     |   0.00   | 13.07 | 87.28  |
| quad4ibi_tex8_grey_quintic_bspline_direct               | 110.74  | 6.65 | 99.26  | 4.03  |  16.12   |   4.13    |    16.51     |   0.00   | 9.03 | 59.48  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  92.53  | 6.49 | 81.67  | 4.90  |  19.59   |   5.02    |    20.06     |   0.00   | 10.81 | 71.64  |
| quad4newton_tex8_grey_linear_direct                     |  80.95  | 6.69 | 59.61  | 6.71  |  26.84   |   6.89    |    27.57     |   0.00   | 12.35 | 94.03  |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          | 103.04  | 6.54 | 83.33  | 4.80  |  19.20   |   4.93    |    19.72     |   0.00   | 9.70 | 70.47  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  98.85  | 6.62 | 78.57  | 5.09  |  20.36   |   5.23    |    20.92     |   0.00   | 10.12 | 73.90  |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  98.73  | 6.61 | 78.56  | 5.09  |  20.37   |   5.23    |    20.92     |   0.00   | 10.13 | 74.14  |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 | 111.35  | 6.54 | 89.61  | 4.46  |  17.86   |   4.59    |    18.34     |   0.00   | 8.98 | 64.96  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  96.92  | 6.71 | 76.90  | 5.20  |  20.81   |   5.34    |    21.37     |   0.00   | 10.32 | 75.56  |
| quad4newton_tex8_grey_quintic_bspline_direct            | 136.29  | 6.79 | 115.57 | 3.46  |  13.85   |   3.56    |    14.22     |   0.00   | 7.34 | 51.87  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          | 109.83  | 6.75 | 89.62  | 4.46  |  17.85   |   4.58    |    18.34     |   0.00   | 9.11 | 65.68  |
| quad8_tex8_grey_linear_direct                           | 135.49  | 32.66 | 87.82  | 4.55  |  18.22   |   4.67    |    18.69     |   0.00   | 7.38 | 104.90 |
| quad8_tex8_grey_cubic_catmull_rom_direct                | 161.93  | 32.00 | 113.79 | 3.52  |  14.06   |   3.61    |    14.43     |   0.00   | 6.18 | 86.24  |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              | 156.97  | 32.10 | 108.16 | 3.70  |  14.79   |   3.79    |    15.18     |   0.00   | 6.37 | 89.60  |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 156.04  | 31.88 | 110.07 | 3.63  |  14.54   |   3.73    |    14.91     |   0.00   | 6.41 | 89.04  |
| quad8_tex8_grey_lanczos3_lut_lerp                       | 166.98  | 32.28 | 121.23 | 3.30  |  13.20   |   3.39    |    13.54     |   0.00   | 5.99 | 82.89  |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  | 158.09  | 31.69 | 108.32 | 3.69  |  14.77   |   3.79    |    15.15     |   0.00   | 6.33 | 89.29  |
| quad8_tex8_grey_quintic_bspline_direct                  | 191.67  | 32.23 | 146.20 | 2.74  |  10.94   |   2.81    |    11.23     |   0.00   | 5.22 | 71.56  |
| quad8_tex8_grey_quintic_bspline_lut_lerp                | 170.42  | 32.04 | 123.37 | 3.24  |  12.97   |   3.33    |    13.31     |   0.00   | 5.87 | 81.70  |
| quad9_tex8_grey_linear_direct                           | 144.56  | 36.89 | 90.40  | 4.42  |  17.70   |   4.54    |    18.18     |   0.00   | 6.92 | 111.88 |
| quad9_tex8_grey_cubic_catmull_rom_direct                | 169.69  | 35.34 | 118.64 | 3.37  |  13.49   |   3.46    |    13.85     |   0.00   | 5.89 | 92.74  |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              | 168.99  | 36.46 | 115.55 | 3.46  |  13.85   |   3.56    |    14.22     |   0.00   | 5.92 | 93.10  |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 162.45  | 34.68 | 112.46 | 3.56  |  14.23   |   3.65    |    14.61     |   0.00   | 6.16 | 96.99  |
| quad9_tex8_grey_lanczos3_lut_lerp                       | 176.06  | 35.13 | 124.57 | 3.21  |  12.84   |   3.30    |    13.19     |   0.00   | 5.68 | 89.34  |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  | 168.06  | 37.31 | 113.82 | 3.51  |  14.06   |   3.61    |    14.44     |   0.00   | 5.95 | 94.72  |
| quad9_tex8_grey_quintic_bspline_direct                  | 205.71  | 36.06 | 153.59 | 2.60  |  10.42   |   2.67    |    10.70     |   0.00   | 4.86 | 75.43  |
| quad9_tex8_grey_quintic_bspline_lut_lerp                | 181.21  | 36.77 | 126.91 | 3.15  |  12.61   |   3.24    |    12.95     |   0.00   | 5.52 | 87.00  |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  74.50  | 12.79 | 54.38  | 7.36  |  29.42   |   7.60    |    30.40     |   0.00   | 13.42 | 69.00  |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  | 103.78  | 12.70 | 82.17  | 4.87  |  19.47   |   5.03    |    20.12     |   0.00   | 9.64 | 49.20  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                | 100.10  | 12.83 | 79.99  | 5.00  |  20.00   |   5.17    |    20.67     |   0.00   | 9.99 | 50.46  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  98.13  | 12.78 | 77.92  | 5.13  |  20.53   |   5.30    |    21.21     |   0.00   | 10.19 | 51.43  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         | 113.74  | 12.77 | 94.22  | 4.25  |  16.98   |   4.39    |    17.54     |   0.00   | 8.79 | 44.08  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  96.23  | 12.94 | 76.83  | 5.21  |  20.82   |   5.38    |    21.52     |   0.00   | 10.39 | 52.53  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 141.81  | 12.80 | 121.15 | 3.30  |  13.21   |   3.41    |    13.64     |   0.00   | 7.05 | 35.07  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  | 118.38  | 12.79 | 98.07  | 4.08  |  16.31   |   4.21    |    16.85     |   0.00   | 8.45 | 42.34  |
| tri6_tex8_rgb_linear_direct                             | 212.64  | 56.10 | 134.90 | 2.97  |  11.86   |   3.05    |    12.19     |   0.00   | 4.70 | 49.77  |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 237.96  | 55.79 | 159.39 | 2.51  |  10.04   |   2.58    |    10.32     |   0.00   | 4.20 | 43.76  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 228.96  | 55.73 | 152.25 | 2.63  |  10.51   |   2.70    |    10.80     |   0.00   | 4.37 | 45.70  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 232.07  | 56.00 | 153.66 | 2.60  |  10.41   |   2.68    |    10.70     |   0.00   | 4.31 | 45.00  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 249.31  | 55.90 | 169.93 | 2.35  |   9.42   |   2.42    |     9.68     |   0.00   | 4.01 | 41.61  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 232.36  | 55.81 | 152.80 | 2.62  |  10.47   |   2.69    |    10.76     |   0.00   | 4.30 | 44.96  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 275.33  | 55.77 | 198.48 | 2.02  |   8.06   |   2.07    |     8.29     |   0.00   | 3.63 | 37.34  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 250.11  | 55.92 | 172.36 | 2.32  |   9.28   |   2.39    |     9.54     |   0.00   | 4.00 | 41.61  |
| quad4ibi_tex8_rgb_linear_direct                         |  58.89  | 8.80 | 44.69  | 8.95  |  35.80   |   9.17    |    36.66     |   0.00   | 16.98 | 116.20 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  93.61  | 8.77 | 79.02  | 5.06  |  20.25   |   5.18    |    20.73     |   0.00   | 10.68 | 71.28  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  99.46  | 8.76 | 84.12  | 4.76  |  19.02   |   4.87    |    19.48     |   0.00   | 10.05 | 66.93  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  97.92  | 8.80 | 83.64  | 4.78  |  19.13   |   4.90    |    19.59     |   0.00   | 10.21 | 68.00  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 120.92  | 8.81 | 105.75 | 3.78  |  15.13   |   3.87    |    15.49     |   0.00   | 8.27 | 54.68  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  98.27  | 8.81 | 82.45  | 4.85  |  19.41   |   4.97    |    19.87     |   0.00   | 10.18 | 67.81  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 147.78  | 8.85 | 132.48 | 3.02  |  12.08   |   3.09    |    12.37     |   0.00   | 6.77 | 44.45  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 122.10  | 8.79 | 106.16 | 3.77  |  15.07   |   3.86    |    15.44     |   0.00   | 8.19 | 54.70  |
| quad4newton_tex8_rgb_linear_direct                      | 104.55  | 8.90 | 79.14  | 5.05  |  20.22   |   5.19    |    20.77     |   0.00   | 9.57 | 69.86  |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           | 128.33  | 8.96 | 104.43 | 3.83  |  15.32   |   3.93    |    15.74     |   0.00   | 7.79 | 55.49  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         | 121.96  | 8.91 | 98.52  | 4.06  |  16.24   |   4.17    |    16.69     |   0.00   | 8.20 | 58.66  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  | 124.28  | 8.89 | 99.06  | 4.04  |  16.15   |   4.15    |    16.59     |   0.00   | 8.05 | 57.48  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  | 139.07  | 8.88 | 114.31 | 3.50  |  14.00   |   3.59    |    14.38     |   0.00   | 7.19 | 50.71  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             | 124.16  | 8.88 | 97.84  | 4.09  |  16.35   |   4.20    |    16.80     |   0.00   | 8.05 | 58.27  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 169.62  | 8.92 | 144.07 | 2.78  |  11.11   |   2.85    |    11.41     |   0.00   | 5.90 | 41.02  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           | 142.03  | 8.99 | 115.22 | 3.47  |  13.89   |   3.57    |    14.26     |   0.00   | 7.04 | 50.34  |
| quad8_tex8_rgb_linear_direct                            | 162.97  | 36.86 | 110.17 | 3.63  |  14.52   |   3.73    |    14.90     |   0.00   | 6.14 | 86.25  |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 191.56  | 36.32 | 136.12 | 2.94  |  11.76   |   3.02    |    12.06     |   0.00   | 5.22 | 72.34  |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               | 185.27  | 36.69 | 134.06 | 2.98  |  11.93   |   3.06    |    12.24     |   0.00   | 5.40 | 74.80  |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 192.95  | 36.82 | 136.18 | 2.94  |  11.75   |   3.01    |    12.05     |   0.00   | 5.18 | 72.36  |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 204.79  | 36.27 | 153.00 | 2.61  |  10.46   |   2.68    |    10.73     |   0.00   | 4.88 | 66.96  |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   | 179.18  | 35.50 | 127.40 | 3.14  |  12.56   |   3.22    |    12.89     |   0.00   | 5.58 | 77.45  |
| quad8_tex8_rgb_quintic_bspline_direct                   | 236.05  | 36.82 | 180.62 | 2.21  |   8.86   |   2.27    |     9.09     |   0.00   | 4.24 | 58.02  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 206.43  | 37.15 | 152.87 | 2.62  |  10.47   |   2.68    |    10.74     |   0.00   | 4.84 | 66.85  |
| quad9_tex8_rgb_linear_direct                            | 176.92  | 40.49 | 119.16 | 3.36  |  13.43   |   3.45    |    13.79     |   0.00   | 5.65 | 89.17  |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 202.42  | 40.79 | 145.86 | 2.74  |  10.97   |   2.82    |    11.27     |   0.00   | 4.94 | 76.76  |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               | 197.74  | 40.92 | 139.31 | 2.87  |  11.48   |   2.95    |    11.80     |   0.00   | 5.06 | 79.36  |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 197.04  | 40.88 | 138.59 | 2.89  |  11.55   |   2.96    |    11.86     |   0.00   | 5.08 | 79.52  |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 210.61  | 39.83 | 155.06 | 2.58  |  10.32   |   2.65    |    10.60     |   0.00   | 4.75 | 73.37  |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   | 192.88  | 38.78 | 135.45 | 2.95  |  11.81   |   3.03    |    12.13     |   0.00   | 5.18 | 81.41  |
| quad9_tex8_rgb_quintic_bspline_direct                   | 228.03  | 36.95 | 171.86 | 2.33  |   9.31   |   2.39    |     9.56     |   0.00   | 4.39 | 67.60  |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 212.59  | 39.02 | 153.06 | 2.61  |  10.45   |   2.68    |    10.74     |   0.00   | 4.70 | 73.93  |

