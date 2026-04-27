# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  44.10  | 17.16 | 21.80  | 18.35 |  73.40   |   18.96   |    75.83     |   0.00   | 22.68 | 120.24 |
| tri6_nodal_grey                                         | 165.45  | 53.39 | 104.71 | 3.82  |  15.28   |   3.93    |    15.71     |   0.00   | 6.04 | 60.14  |
| quad4ibi_nodal_grey                                     |  39.85  | 7.76 | 29.20  | 13.70 |  54.80   |   14.03   |    56.11     |   0.00   | 25.10 | 168.70 |
| quad4newton_nodal_grey                                  |  61.38  | 7.33 | 51.13  | 7.82  |  31.29   |   8.04    |    32.14     |   0.00   | 16.29 | 108.00 |
| quad8_nodal_grey                                        | 121.39  | 32.60 | 82.83  | 4.83  |  19.32   |   4.95    |    19.82     |   0.00   | 8.24 | 110.58 |
| quad9_nodal_grey                                        | 120.58  | 34.41 | 80.16  | 4.99  |  19.96   |   5.13    |    20.50     |   0.00   | 8.29 | 124.45 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  51.83  | 18.29 | 27.95  | 14.31 |  57.24   |   14.79   |    59.14     |   0.00   | 19.30 | 98.59  |
| tri6_nodal_rgb                                          | 193.06  | 68.10 | 114.52 | 3.49  |  13.97   |   3.59    |    14.36     |   0.00   | 5.18 | 52.15  |
| quad4ibi_nodal_rgb                                      |  54.70  | 11.82 | 37.76  | 10.59 |  42.38   |   10.85   |    43.39     |   0.00   | 18.28 | 123.68 |
| quad4newton_nodal_rgb                                   |  74.07  | 11.96 | 56.83  | 7.04  |  28.15   |   7.23    |    28.92     |   0.00   | 13.50 | 90.57  |
| quad8_nodal_rgb                                         | 139.12  | 43.59 | 88.29  | 4.53  |  18.12   |   4.65    |    18.59     |   0.00   | 7.19 | 96.00  |
| quad9_nodal_rgb                                         | 141.63  | 46.98 | 85.81  | 4.66  |  18.65   |   4.79    |    19.15     |   0.00   | 7.06 | 106.78 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  65.30  | 18.82 | 38.75  | 10.32 |  41.29   |   10.67   |    42.66     |   0.00   | 15.31 | 80.90  |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  93.01  | 18.67 | 67.34  | 5.94  |  23.76   |   6.14    |    24.55     |   0.00   | 10.75 | 55.13  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  86.08  | 18.51 | 59.76  | 6.69  |  26.77   |   6.92    |    27.66     |   0.00   | 11.62 | 60.25  |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  86.31  | 18.51 | 60.76  | 6.58  |  26.33   |   6.80    |    27.21     |   0.00   | 11.59 | 59.91  |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  98.33  | 18.73 | 72.67  | 5.50  |  22.02   |   5.69    |    22.75     |   0.00   | 10.17 | 51.87  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  85.44  | 18.38 | 59.56  | 6.72  |  26.86   |   6.94    |    27.75     |   0.00   | 11.70 | 60.60  |
| tri3_tex8_grey_quintic_bspline_direct                   | 124.61  | 19.10 | 99.65  | 4.01  |  16.06   |   4.15    |    16.59     |   0.00   | 8.03 | 40.46  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  97.16  | 18.07 | 71.89  | 5.56  |  22.26   |   5.75    |    23.00     |   0.00   | 10.29 | 52.70  |
| tri6_tex8_grey_linear_direct                            | 195.87  | 55.91 | 120.32 | 3.32  |  13.30   |   3.42    |    13.67     |   0.00   | 5.11 | 54.27  |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 222.31  | 56.21 | 146.34 | 2.73  |  10.93   |   2.81    |    11.24     |   0.00   | 4.50 | 46.90  |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 215.57  | 55.91 | 140.37 | 2.85  |  11.40   |   2.93    |    11.72     |   0.00   | 4.64 | 48.70  |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 216.66  | 55.65 | 142.04 | 2.82  |  11.26   |   2.89    |    11.58     |   0.00   | 4.62 | 48.49  |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 230.86  | 56.42 | 153.10 | 2.61  |  10.45   |   2.69    |    10.74     |   0.00   | 4.33 | 45.64  |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 215.24  | 56.08 | 140.91 | 2.84  |  11.35   |   2.92    |    11.67     |   0.00   | 4.65 | 48.60  |
| tri6_tex8_grey_quintic_bspline_direct                   | 254.44  | 55.66 | 179.25 | 2.23  |   8.93   |   2.29    |     9.17     |   0.00   | 3.93 | 40.47  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 227.21  | 55.34 | 151.74 | 2.64  |  10.54   |   2.71    |    10.84     |   0.00   | 4.40 | 46.03  |
| quad4ibi_tex8_grey_linear_direct                        |  50.80  | 7.04 | 38.84  | 10.30 |  41.19   |   10.55   |    42.18     |   0.00   | 19.68 | 135.34 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  81.17  | 7.08 | 69.22  | 5.78  |  23.12   |   5.92    |    23.67     |   0.00   | 12.32 | 82.44  |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  82.59  | 7.03 | 70.86  | 5.65  |  22.58   |   5.78    |    23.12     |   0.00   | 12.11 | 81.13  |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  82.71  | 7.06 | 70.08  | 5.71  |  22.83   |   5.84    |    23.38     |   0.00   | 12.09 | 80.94  |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    | 100.74  | 7.21 | 87.88  | 4.55  |  18.21   |   4.66    |    18.64     |   0.00   | 9.93 | 66.19  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  82.47  | 7.02 | 71.00  | 5.63  |  22.54   |   5.77    |    23.08     |   0.00   | 12.13 | 81.05  |
| quad4ibi_tex8_grey_quintic_bspline_direct               | 118.37  | 7.01 | 106.71 | 3.75  |  14.99   |   3.84    |    15.35     |   0.00   | 8.45 | 55.62  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  99.41  | 7.09 | 87.73  | 4.56  |  18.24   |   4.67    |    18.68     |   0.00   | 10.06 | 66.77  |
| quad4newton_tex8_grey_linear_direct                     |  84.57  | 6.78 | 64.32  | 6.22  |  24.88   |   6.39    |    25.55     |   0.00   | 11.82 | 89.50  |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          | 110.32  | 6.75 | 89.69  | 4.46  |  17.84   |   4.58    |    18.32     |   0.00   | 9.06 | 65.79  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        | 104.49  | 7.01 | 82.91  | 4.82  |  19.30   |   4.96    |    19.82     |   0.00   | 9.57 | 70.22  |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp | 104.22  | 6.93 | 82.69  | 4.84  |  19.35   |   4.97    |    19.87     |   0.00   | 9.60 | 70.47  |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 | 116.06  | 6.95 | 94.89  | 4.22  |  16.86   |   4.33    |    17.32     |   0.00   | 8.62 | 62.53  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            | 104.13  | 6.75 | 83.98  | 4.76  |  19.05   |   4.89    |    19.57     |   0.00   | 9.60 | 70.17  |
| quad4newton_tex8_grey_quintic_bspline_direct            | 143.59  | 6.88 | 121.84 | 3.28  |  13.13   |   3.37    |    13.49     |   0.00   | 6.96 | 49.40  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          | 116.31  | 6.73 | 95.89  | 4.17  |  16.69   |   4.28    |    17.14     |   0.00   | 8.60 | 61.88  |
| quad8_tex8_grey_linear_direct                           | 141.83  | 33.90 | 94.00  | 4.26  |  17.02   |   4.37    |    17.46     |   0.00   | 7.05 | 99.54  |
| quad8_tex8_grey_cubic_catmull_rom_direct                | 169.87  | 33.51 | 120.75 | 3.31  |  13.25   |   3.40    |    13.59     |   0.00   | 5.89 | 81.89  |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              | 165.72  | 34.73 | 115.55 | 3.46  |  13.85   |   3.55    |    14.21     |   0.00   | 6.03 | 84.77  |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 164.82  | 33.74 | 115.51 | 3.46  |  13.85   |   3.55    |    14.21     |   0.00   | 6.07 | 85.31  |
| quad8_tex8_grey_lanczos3_lut_lerp                       | 175.27  | 33.77 | 127.07 | 3.15  |  12.59   |   3.23    |    12.92     |   0.00   | 5.71 | 79.34  |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  | 163.93  | 33.96 | 114.47 | 3.49  |  13.98   |   3.59    |    14.34     |   0.00   | 6.10 | 85.80  |
| quad8_tex8_grey_quintic_bspline_direct                  | 201.98  | 33.86 | 153.54 | 2.61  |  10.42   |   2.67    |    10.69     |   0.00   | 4.95 | 67.97  |
| quad8_tex8_grey_quintic_bspline_lut_lerp                | 174.75  | 33.71 | 127.12 | 3.15  |  12.59   |   3.23    |    12.91     |   0.00   | 5.72 | 79.22  |
| quad9_tex8_grey_linear_direct                           | 145.51  | 36.25 | 92.17  | 4.34  |  17.36   |   4.46    |    17.83     |   0.00   | 6.87 | 112.19 |
| quad9_tex8_grey_cubic_catmull_rom_direct                | 170.80  | 36.20 | 119.57 | 3.35  |  13.38   |   3.44    |    13.74     |   0.00   | 5.85 | 92.18  |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              | 166.97  | 36.31 | 112.99 | 3.54  |  14.16   |   3.64    |    14.54     |   0.00   | 5.99 | 95.10  |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       | 166.51  | 36.72 | 113.38 | 3.53  |  14.11   |   3.62    |    14.49     |   0.00   | 6.01 | 95.06  |
| quad9_tex8_grey_lanczos3_lut_lerp                       | 177.03  | 36.46 | 125.50 | 3.19  |  12.75   |   3.27    |    13.09     |   0.00   | 5.65 | 88.31  |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  | 167.99  | 37.29 | 114.55 | 3.49  |  13.97   |   3.59    |    14.34     |   0.00   | 5.95 | 93.36  |
| quad9_tex8_grey_quintic_bspline_direct                  | 206.26  | 36.64 | 152.47 | 2.62  |  10.49   |   2.69    |    10.78     |   0.00   | 4.85 | 75.67  |
| quad9_tex8_grey_quintic_bspline_lut_lerp                | 177.87  | 37.05 | 125.50 | 3.19  |  12.75   |   3.27    |    13.09     |   0.00   | 5.62 | 88.28  |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  80.45  | 13.76 | 59.07  | 6.77  |  27.09   |   7.00    |    27.99     |   0.00   | 12.43 | 63.71  |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  | 108.67  | 13.48 | 87.94  | 4.55  |  18.19   |   4.70    |    18.80     |   0.00   | 9.20 | 46.45  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                | 105.52  | 13.88 | 84.31  | 4.74  |  18.98   |   4.90    |    19.61     |   0.00   | 9.48 | 47.87  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 104.57  | 13.74 | 83.39  | 4.80  |  19.19   |   4.96    |    19.82     |   0.00   | 9.56 | 48.63  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         | 123.69  | 13.85 | 101.71 | 3.93  |  15.73   |   4.06    |    16.25     |   0.00   | 8.08 | 40.54  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    | 103.64  | 14.09 | 82.33  | 4.86  |  19.43   |   5.02    |    20.08     |   0.00   | 9.65 | 48.65  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 151.15  | 13.44 | 131.12 | 3.05  |  12.20   |   3.15    |    12.61     |   0.00   | 6.62 | 32.85  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  | 124.38  | 13.61 | 103.96 | 3.85  |  15.39   |   3.98    |    15.90     |   0.00   | 8.04 | 40.33  |
| tri6_tex8_rgb_linear_direct                             | 231.08  | 60.62 | 147.72 | 2.71  |  10.83   |   2.78    |    11.13     |   0.00   | 4.33 | 45.52  |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 255.10  | 61.38 | 172.82 | 2.31  |   9.26   |   2.38    |     9.52     |   0.00   | 3.92 | 40.75  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 250.06  | 60.74 | 168.04 | 2.38  |   9.52   |   2.45    |     9.79     |   0.00   | 4.00 | 41.64  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 249.92  | 61.34 | 167.97 | 2.38  |   9.53   |   2.45    |     9.79     |   0.00   | 4.00 | 41.71  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 269.50  | 60.65 | 187.05 | 2.14  |   8.55   |   2.20    |     8.79     |   0.00   | 3.71 | 38.38  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 250.07  | 60.57 | 168.48 | 2.37  |   9.50   |   2.44    |     9.76     |   0.00   | 4.00 | 41.55  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 296.89  | 60.69 | 214.72 | 1.86  |   7.45   |   1.91    |     7.66     |   0.00   | 3.37 | 34.70  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 266.95  | 59.95 | 186.22 | 2.15  |   8.59   |   2.21    |     8.83     |   0.00   | 3.75 | 38.70  |
| quad4ibi_tex8_rgb_linear_direct                         |  64.00  | 9.50 | 48.30  | 8.28  |  33.13   |   8.48    |    33.92     |   0.00   | 15.63 | 106.77 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  99.45  | 9.33 | 84.62  | 4.73  |  18.91   |   4.84    |    19.36     |   0.00   | 10.06 | 67.17  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            | 103.34  | 9.33 | 87.90  | 4.55  |  18.20   |   4.66    |    18.64     |   0.00   | 9.68 | 64.81  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     | 103.94  | 9.51 | 89.25  | 4.48  |  17.93   |   4.59    |    18.36     |   0.00   | 9.62 | 64.15  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 126.62  | 9.34 | 111.93 | 3.57  |  14.29   |   3.66    |    14.64     |   0.00   | 7.90 | 52.28  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                | 102.78  | 10.22 | 87.50  | 4.57  |  18.29   |   4.68    |    18.73     |   0.00   | 9.73 | 64.69  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 154.84  | 9.50 | 140.24 | 2.85  |  11.41   |   2.92    |    11.68     |   0.00   | 6.46 | 42.45  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 127.46  | 9.31 | 112.54 | 3.55  |  14.22   |   3.64    |    14.56     |   0.00   | 7.85 | 51.77  |
| quad4newton_tex8_rgb_linear_direct                      | 110.05  | 9.41 | 85.58  | 4.67  |  18.70   |   4.80    |    19.20     |   0.00   | 9.09 | 66.06  |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           | 136.61  | 9.42 | 110.77 | 3.61  |  14.44   |   3.71    |    14.84     |   0.00   | 7.32 | 52.06  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         | 130.02  | 9.52 | 103.64 | 3.86  |  15.44   |   3.96    |    15.86     |   0.00   | 7.69 | 55.30  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  | 128.88  | 9.52 | 103.96 | 3.85  |  15.39   |   3.95    |    15.81     |   0.00   | 7.76 | 55.43  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  | 150.90  | 9.70 | 124.76 | 3.21  |  12.82   |   3.29    |    13.17     |   0.00   | 6.63 | 46.88  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             | 132.59  | 9.59 | 105.01 | 3.81  |  15.24   |   3.91    |    15.65     |   0.00   | 7.54 | 54.11  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 176.08  | 9.22 | 151.23 | 2.65  |  10.58   |   2.72    |    10.87     |   0.00   | 5.68 | 39.42  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           | 148.39  | 9.26 | 123.17 | 3.25  |  12.99   |   3.34    |    13.34     |   0.00   | 6.74 | 47.60  |
| quad8_tex8_rgb_linear_direct                            | 170.93  | 38.60 | 117.30 | 3.41  |  13.64   |   3.50    |    13.99     |   0.00   | 5.85 | 81.38  |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 201.70  | 39.48 | 146.35 | 2.73  |  10.93   |   2.80    |    11.22     |   0.00   | 4.96 | 68.36  |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               | 191.10  | 37.89 | 138.39 | 2.89  |  11.56   |   2.97    |    11.86     |   0.00   | 5.23 | 72.10  |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 191.64  | 38.23 | 138.43 | 2.89  |  11.56   |   2.96    |    11.86     |   0.00   | 5.22 | 71.84  |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 210.67  | 37.14 | 156.79 | 2.55  |  10.21   |   2.62    |    10.47     |   0.00   | 4.75 | 65.27  |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   | 190.77  | 37.89 | 138.86 | 2.88  |  11.52   |   2.96    |    11.82     |   0.00   | 5.24 | 72.02  |
| quad8_tex8_rgb_quintic_bspline_direct                   | 239.16  | 38.31 | 185.49 | 2.16  |   8.63   |   2.21    |     8.85     |   0.00   | 4.18 | 57.05  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 210.68  | 37.99 | 157.25 | 2.54  |  10.17   |   2.61    |    10.44     |   0.00   | 4.75 | 65.05  |
| quad9_tex8_rgb_linear_direct                            | 176.92  | 40.51 | 119.18 | 3.36  |  13.43   |   3.45    |    13.79     |   0.00   | 5.65 | 89.24  |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 203.58  | 40.10 | 145.15 | 2.76  |  11.02   |   2.83    |    11.32     |   0.00   | 4.91 | 76.74  |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               | 196.04  | 40.55 | 137.48 | 2.91  |  11.64   |   2.99    |    11.95     |   0.00   | 5.10 | 80.21  |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        | 195.29  | 39.88 | 137.82 | 2.90  |  11.61   |   2.98    |    11.92     |   0.00   | 5.12 | 80.20  |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 211.98  | 40.24 | 156.08 | 2.56  |  10.25   |   2.63    |    10.53     |   0.00   | 4.72 | 73.04  |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   | 196.56  | 40.29 | 137.60 | 2.91  |  11.63   |   2.99    |    11.94     |   0.00   | 5.09 | 79.74  |
| quad9_tex8_rgb_quintic_bspline_direct                   | 243.32  | 40.01 | 184.74 | 2.17  |   8.66   |   2.22    |     8.90     |   0.00   | 4.11 | 63.72  |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 216.23  | 40.62 | 157.36 | 2.54  |  10.17   |   2.61    |    10.44     |   0.00   | 4.62 | 72.23  |

