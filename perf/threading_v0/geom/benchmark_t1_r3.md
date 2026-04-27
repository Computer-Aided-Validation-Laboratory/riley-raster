# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  42.55  | 17.58 | 21.16  | 18.90 |  75.61   |   19.53   |    78.12     |   0.00   | 23.50 | 122.43 |
| tri6_nodal_grey                                         | 155.58  | 50.40 | 98.57  | 4.06  |  16.23   |   4.17    |    16.68     |   0.00   | 6.43 | 64.04  |
| quad4ibi_nodal_grey                                     |  38.77  | 7.26 | 28.34  | 14.11 |  56.45   |   14.45   |    57.81     |   0.00   | 25.80 | 173.90 |
| quad4newton_nodal_grey                                  |  57.74  | 6.96 | 48.03  | 8.33  |  33.31   |   8.55    |    34.22     |   0.00   | 17.32 | 114.62 |
| quad8_nodal_grey                                        | 114.28  | 31.75 | 76.55  | 5.23  |  20.90   |   5.36    |    21.44     |   0.00   | 8.75 | 116.79 |
| quad9_nodal_grey                                        | 114.50  | 34.06 | 74.55  | 5.37  |  21.46   |   5.51    |    22.04     |   0.00   | 8.73 | 131.28 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  50.33  | 18.23 | 28.07  | 14.25 |  57.01   |   14.72   |    58.90     |   0.00   | 19.87 | 101.96 |
| tri6_nodal_rgb                                          | 177.66  | 63.88 | 104.33 | 3.83  |  15.34   |   3.94    |    15.76     |   0.00   | 5.63 | 56.40  |
| quad4ibi_nodal_rgb                                      |  51.88  | 11.27 | 35.62  | 11.23 |  44.91   |   11.50   |    45.99     |   0.00   | 19.28 | 129.98 |
| quad4newton_nodal_rgb                                   |  71.08  | 11.51 | 54.70  | 7.31  |  29.25   |   7.51    |    30.05     |   0.00   | 14.07 | 93.82  |
| quad8_nodal_rgb                                         | 131.29  | 41.72 | 81.99  | 4.88  |  19.51   |   5.01    |    20.02     |   0.00   | 7.62 | 102.02 |
| quad9_nodal_rgb                                         | 131.42  | 44.49 | 78.98  | 5.06  |  20.26   |   5.20    |    20.81     |   0.00   | 7.61 | 114.90 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  64.56  | 18.32 | 39.58  | 10.11 |  40.42   |   10.44   |    41.76     |   0.00   | 15.49 | 82.42  |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  92.83  | 18.01 | 68.53  | 5.84  |  23.35   |   6.03    |    24.12     |   0.00   | 10.77 | 55.10  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  85.13  | 17.91 | 60.28  | 6.64  |  26.54   |   6.86    |    27.42     |   0.00   | 11.75 | 60.67  |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  84.19  | 17.65 | 59.53  | 6.72  |  26.88   |   6.94    |    27.77     |   0.00   | 11.88 | 61.37  |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  96.37  | 18.70 | 71.36  | 5.61  |  22.42   |   5.79    |    23.16     |   0.00   | 10.38 | 52.96  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  84.88  | 17.94 | 59.87  | 6.68  |  26.73   |   6.90    |    27.61     |   0.00   | 11.78 | 60.99  |
| tri3_tex8_grey_quintic_bspline_direct                   | 124.99  | 17.65 | 101.10 | 3.96  |  15.83   |   4.09    |    16.35     |   0.00   | 8.00 | 40.33  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  96.88  | 18.01 | 72.97  | 5.48  |  21.93   |   5.66    |    22.65     |   0.00   | 10.32 | 52.69  |
| tri6_tex8_grey_linear_direct                            | 184.35  | 52.03 | 109.93 | 3.64  |  14.56   |   3.74    |    14.96     |   0.00   | 5.42 | 57.99  |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 207.87  | 52.10 | 134.96 | 2.96  |  11.86   |   3.05    |    12.19     |   0.00   | 4.81 | 50.42  |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 200.06  | 52.02 | 128.90 | 3.10  |  12.41   |   3.19    |    12.76     |   0.00   | 5.00 | 52.59  |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 203.86  | 52.19 | 128.61 | 3.11  |  12.44   |   3.20    |    12.79     |   0.00   | 4.91 | 52.34  |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 212.85  | 52.04 | 141.44 | 2.83  |  11.31   |   2.91    |    11.63     |   0.00   | 4.70 | 49.04  |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 200.81  | 51.86 | 129.29 | 3.09  |  12.38   |   3.18    |    12.72     |   0.00   | 4.98 | 52.15  |
| tri6_tex8_grey_quintic_bspline_direct                   | 240.26  | 52.20 | 169.65 | 2.36  |   9.43   |   2.42    |     9.69     |   0.00   | 4.16 | 42.96  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 213.25  | 52.08 | 140.38 | 2.85  |  11.40   |   2.93    |    11.71     |   0.00   | 4.69 | 49.00  |
| quad4ibi_tex8_grey_linear_direct                        |  47.03  | 6.84 | 36.32  | 11.01 |  44.06   |   11.28   |    45.11     |   0.00   | 21.26 | 145.83 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  76.06  | 6.71 | 65.31  | 6.12  |  24.50   |   6.27    |    25.09     |   0.00   | 13.15 | 87.92  |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  80.55  | 6.79 | 68.73  | 5.82  |  23.28   |   5.96    |    23.84     |   0.00   | 12.42 | 82.80  |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  77.29  | 6.75 | 66.46  | 6.02  |  24.08   |   6.16    |    24.66     |   0.00   | 12.94 | 86.42  |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  94.74  | 6.80 | 83.35  | 4.80  |  19.20   |   4.91    |    19.66     |   0.00   | 10.56 | 69.96  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  77.52  | 6.69 | 66.75  | 5.99  |  23.97   |   6.14    |    24.55     |   0.00   | 12.90 | 86.18  |
| quad4ibi_tex8_grey_quintic_bspline_direct               | 111.10  | 6.77 | 98.99  | 4.04  |  16.16   |   4.14    |    16.55     |   0.00   | 9.00 | 59.31  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  94.25  | 6.71 | 82.79  | 4.83  |  19.33   |   4.95    |    19.79     |   0.00   | 10.61 | 70.32  |
| quad4newton_tex8_grey_linear_direct                     |  81.11  | 6.63 | 59.63  | 6.71  |  26.83   |   6.89    |    27.56     |   0.00   | 12.33 | 93.83  |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          | 110.61  | 6.94 | 88.94  | 4.50  |  17.99   |   4.62    |    18.48     |   0.00   | 9.04 | 65.79  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        | 104.13  | 6.86 | 82.88  | 4.83  |  19.30   |   4.96    |    19.83     |   0.00   | 9.60 | 70.51  |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp | 103.50  | 6.95 | 81.71  | 4.90  |  19.58   |   5.03    |    20.11     |   0.00   | 9.66 | 71.50  |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 | 116.14  | 7.05 | 95.16  | 4.20  |  16.81   |   4.32    |    17.27     |   0.00   | 8.61 | 61.99  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            | 103.52  | 6.96 | 82.60  | 4.84  |  19.37   |   4.97    |    19.90     |   0.00   | 9.66 | 70.67  |
| quad4newton_tex8_grey_quintic_bspline_direct            | 143.75  | 6.99 | 123.18 | 3.25  |  12.99   |   3.34    |    13.34     |   0.00   | 6.96 | 49.05  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          | 116.70  | 7.07 | 95.41  | 4.19  |  16.77   |   4.31    |    17.22     |   0.00   | 8.57 | 61.88  |
| quad8_tex8_grey_linear_direct                           | 133.03  | 32.53 | 86.81  | 4.61  |  18.43   |   4.73    |    18.91     |   0.00   | 7.52 | 106.42 |
| quad8_tex8_grey_cubic_catmull_rom_direct                | 162.67  | 32.91 | 114.39 | 3.50  |  13.99   |   3.59    |    14.35     |   0.00   | 6.15 | 85.42  |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              | 158.29  | 32.05 | 109.16 | 3.67  |  14.66   |   3.76    |    15.04     |   0.00   | 6.32 | 88.44  |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 152.97  | 32.02 | 107.37 | 3.73  |  14.90   |   3.82    |    15.29     |   0.00   | 6.54 | 90.94  |
| quad8_tex8_grey_lanczos3_lut_lerp                       | 164.18  | 32.18 | 117.94 | 3.39  |  13.57   |   3.48    |    13.92     |   0.00   | 6.09 | 84.42  |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  | 153.38  | 32.48 | 106.75 | 3.75  |  14.99   |   3.84    |    15.38     |   0.00   | 6.52 | 91.38  |
| quad8_tex8_grey_quintic_bspline_direct                  | 192.07  | 32.07 | 144.73 | 2.76  |  11.05   |   2.84    |    11.34     |   0.00   | 5.21 | 71.30  |
| quad8_tex8_grey_quintic_bspline_lut_lerp                | 167.34  | 31.76 | 122.33 | 3.27  |  13.08   |   3.35    |    13.42     |   0.00   | 5.98 | 82.73  |
| quad9_tex8_grey_linear_direct                           | 133.53  | 34.65 | 84.40  | 4.74  |  18.96   |   4.87    |    19.47     |   0.00   | 7.49 | 120.04 |
| quad9_tex8_grey_cubic_catmull_rom_direct                | 161.15  | 35.51 | 110.35 | 3.62  |  14.50   |   3.72    |    14.89     |   0.00   | 6.21 | 97.98  |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              | 156.55  | 35.35 | 106.34 | 3.76  |  15.05   |   3.86    |    15.45     |   0.00   | 6.39 | 101.02 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 157.59  | 35.40 | 105.50 | 3.79  |  15.17   |   3.89    |    15.58     |   0.00   | 6.35 | 100.86 |
| quad9_tex8_grey_lanczos3_lut_lerp                       | 175.38  | 37.95 | 123.54 | 3.24  |  12.95   |   3.33    |    13.30     |   0.00   | 5.70 | 89.02  |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  | 157.31  | 35.06 | 108.89 | 3.67  |  14.70   |   3.77    |    15.09     |   0.00   | 6.36 | 100.00 |
| quad9_tex8_grey_quintic_bspline_direct                  | 205.83  | 37.40 | 152.14 | 2.63  |  10.52   |   2.70    |    10.80     |   0.00   | 4.86 | 75.14  |
| quad9_tex8_grey_quintic_bspline_lut_lerp                | 178.65  | 38.21 | 125.29 | 3.19  |  12.77   |   3.28    |    13.12     |   0.00   | 5.60 | 87.38  |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  78.67  | 13.84 | 58.64  | 6.82  |  27.29   |   7.05    |    28.19     |   0.00   | 12.71 | 65.06  |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  | 108.20  | 13.97 | 88.06  | 4.54  |  18.17   |   4.69    |    18.77     |   0.00   | 9.24 | 46.48  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                | 106.64  | 14.09 | 86.11  | 4.65  |  18.58   |   4.80    |    19.20     |   0.00   | 9.38 | 47.32  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 104.92  | 13.52 | 83.46  | 4.79  |  19.17   |   4.95    |    19.81     |   0.00   | 9.53 | 48.22  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         | 122.00  | 13.38 | 101.01 | 3.96  |  15.84   |   4.09    |    16.36     |   0.00   | 8.20 | 41.12  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  98.47  | 12.77 | 77.42  | 5.17  |  20.67   |   5.34    |    21.35     |   0.00   | 10.16 | 51.32  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 142.85  | 12.87 | 122.29 | 3.27  |  13.08   |   3.38    |    13.52     |   0.00   | 7.00 | 34.78  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  | 118.96  | 12.79 | 96.88  | 4.13  |  16.52   |   4.27    |    17.06     |   0.00   | 8.41 | 42.42  |
| tri6_tex8_rgb_linear_direct                             | 210.28  | 56.40 | 135.35 | 2.96  |  11.82   |   3.04    |    12.15     |   0.00   | 4.76 | 49.76  |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 237.06  | 56.55 | 158.96 | 2.52  |  10.07   |   2.59    |    10.35     |   0.00   | 4.22 | 44.13  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 230.05  | 56.13 | 153.91 | 2.60  |  10.40   |   2.67    |    10.69     |   0.00   | 4.35 | 45.30  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 230.94  | 56.30 | 153.86 | 2.60  |  10.40   |   2.67    |    10.69     |   0.00   | 4.33 | 45.35  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 249.66  | 56.20 | 171.70 | 2.33  |   9.32   |   2.39    |     9.58     |   0.00   | 4.01 | 41.81  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 243.41  | 60.25 | 161.17 | 2.48  |   9.93   |   2.55    |    10.20     |   0.00   | 4.11 | 42.78  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 292.54  | 60.45 | 209.61 | 1.91  |   7.63   |   1.96    |     7.85     |   0.00   | 3.42 | 35.06  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 261.89  | 59.91 | 181.07 | 2.21  |   8.84   |   2.27    |     9.08     |   0.00   | 3.82 | 39.46  |
| quad4ibi_tex8_rgb_linear_direct                         |  58.84  | 8.79 | 44.37  | 9.02  |  36.06   |   9.23    |    36.93     |   0.00   | 17.00 | 116.25 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  95.85  | 8.80 | 80.77  | 4.95  |  19.81   |   5.07    |    20.29     |   0.00   | 10.43 | 69.55  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  98.94  | 8.84 | 83.83  | 4.77  |  19.09   |   4.89    |    19.55     |   0.00   | 10.11 | 67.29  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  99.03  | 8.86 | 83.41  | 4.80  |  19.18   |   4.91    |    19.64     |   0.00   | 10.10 | 67.27  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 122.73  | 8.86 | 106.65 | 3.75  |  15.00   |   3.84    |    15.36     |   0.00   | 8.15 | 54.12  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  98.64  | 8.85 | 82.51  | 4.85  |  19.39   |   4.96    |    19.86     |   0.00   | 10.14 | 67.60  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 148.94  | 9.02 | 133.94 | 2.99  |  11.95   |   3.06    |    12.23     |   0.00   | 6.71 | 44.14  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 121.01  | 8.88 | 105.76 | 3.78  |  15.13   |   3.87    |    15.49     |   0.00   | 8.26 | 54.67  |
| quad4newton_tex8_rgb_linear_direct                      | 111.27  | 9.43 | 86.39  | 4.63  |  18.52   |   4.76    |    19.02     |   0.00   | 8.99 | 65.39  |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           | 138.54  | 10.10 | 113.58 | 3.52  |  14.09   |   3.62    |    14.47     |   0.00   | 7.22 | 51.24  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         | 131.71  | 9.53 | 105.87 | 3.78  |  15.11   |   3.88    |    15.52     |   0.00   | 7.59 | 54.37  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  | 130.08  | 9.33 | 104.97 | 3.81  |  15.24   |   3.91    |    15.66     |   0.00   | 7.69 | 54.89  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  | 148.55  | 9.25 | 122.43 | 3.27  |  13.07   |   3.36    |    13.42     |   0.00   | 6.73 | 47.58  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             | 123.27  | 8.93 | 99.25  | 4.03  |  16.12   |   4.14    |    16.56     |   0.00   | 8.11 | 58.08  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 167.34  | 8.90 | 142.88 | 2.80  |  11.20   |   2.88    |    11.50     |   0.00   | 5.98 | 41.42  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           | 140.30  | 8.95 | 116.29 | 3.44  |  13.76   |   3.53    |    14.13     |   0.00   | 7.13 | 50.30  |
| quad8_tex8_rgb_linear_direct                            | 161.39  | 35.42 | 109.61 | 3.65  |  14.60   |   3.74    |    14.98     |   0.00   | 6.20 | 86.65  |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 189.65  | 35.43 | 134.31 | 2.98  |  11.91   |   3.06    |    12.22     |   0.00   | 5.27 | 73.10  |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               | 183.05  | 35.80 | 129.99 | 3.08  |  12.31   |   3.16    |    12.63     |   0.00   | 5.46 | 75.31  |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 179.27  | 35.05 | 126.87 | 3.15  |  12.61   |   3.23    |    12.94     |   0.00   | 5.58 | 77.32  |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 197.91  | 35.10 | 145.16 | 2.76  |  11.02   |   2.83    |    11.31     |   0.00   | 5.05 | 69.81  |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   | 180.99  | 35.66 | 129.80 | 3.08  |  12.33   |   3.16    |    12.65     |   0.00   | 5.53 | 76.17  |
| quad8_tex8_rgb_quintic_bspline_direct                   | 225.79  | 35.46 | 174.13 | 2.30  |   9.19   |   2.36    |     9.43     |   0.00   | 4.43 | 60.26  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 198.09  | 35.52 | 145.74 | 2.74  |  10.98   |   2.82    |    11.26     |   0.00   | 5.05 | 69.99  |
| quad9_tex8_rgb_linear_direct                            | 176.44  | 41.63 | 117.51 | 3.40  |  13.62   |   3.50    |    13.98     |   0.00   | 5.67 | 89.16  |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 202.34  | 41.66 | 143.17 | 2.79  |  11.18   |   2.87    |    11.48     |   0.00   | 4.94 | 77.44  |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               | 196.80  | 40.81 | 138.78 | 2.88  |  11.53   |   2.96    |    11.84     |   0.00   | 5.08 | 79.25  |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 194.54  | 41.16 | 135.56 | 2.95  |  11.80   |   3.03    |    12.12     |   0.00   | 5.14 | 80.41  |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 212.44  | 41.59 | 154.23 | 2.59  |  10.37   |   2.66    |    10.65     |   0.00   | 4.71 | 72.89  |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   | 195.96  | 41.62 | 135.53 | 2.95  |  11.81   |   3.03    |    12.13     |   0.00   | 5.10 | 80.27  |
| quad9_tex8_rgb_quintic_bspline_direct                   | 244.09  | 41.41 | 184.77 | 2.16  |   8.66   |   2.22    |     8.89     |   0.00   | 4.10 | 62.97  |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 212.78  | 40.93 | 154.10 | 2.60  |  10.38   |   2.67    |    10.66     |   0.00   | 4.70 | 73.04  |

