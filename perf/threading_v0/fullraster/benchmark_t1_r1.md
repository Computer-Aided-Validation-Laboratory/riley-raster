# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  13.77  | 0.02 | 10.91  | 36.65 |  146.61  |   36.65   |    146.61    |   0.11   | 72.63 | 403.63 |
| tri6_nodal_grey                                         |  39.88  | 0.02 | 37.17  | 10.76 |  43.05   |   10.76   |    43.05     |   0.10   | 25.08 | 251.93 |
| quad4ibi_nodal_grey                                     |  25.73  | 0.01 | 23.65  | 16.91 |  67.65   |   16.91   |    67.65     |   0.10   | 38.87 | 266.50 |
| quad4newton_nodal_grey                                  |  31.89  | 0.02 | 29.05  | 13.77 |  55.07   |   13.77   |    55.07     |   0.07   | 31.36 | 213.23 |
| quad8_nodal_grey                                        |  38.26  | 0.01 | 36.20  | 11.05 |  44.20   |   11.05   |    44.20     |   0.10   | 26.13 | 349.78 |
| quad9_nodal_grey                                        |  38.92  | 0.01 | 36.87  | 10.85 |  43.40   |   10.85   |    43.40     |   0.10   | 25.70 | 386.77 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  19.14  | 0.01 | 15.37  | 26.03 |  104.10  |   26.03   |    104.10    |   0.18   | 52.27 | 276.89 |
| tri6_nodal_rgb                                          |  45.47  | 0.01 | 41.46  | 9.65  |  38.60   |   9.65    |    38.60     |   0.16   | 21.99 | 220.15 |
| quad4ibi_nodal_rgb                                      |  33.99  | 0.01 | 31.13  | 12.85 |  51.41   |   12.85   |    51.41     |   0.10   | 29.42 | 199.07 |
| quad4newton_nodal_rgb                                   |  36.57  | 0.01 | 33.06  | 12.10 |  48.40   |   12.10   |    48.40     |   0.10   | 27.35 | 184.78 |
| quad8_nodal_rgb                                         |  44.09  | 0.01 | 41.16  | 9.72  |  38.88   |   9.72    |    38.88     |   0.08   | 22.68 | 303.38 |
| quad9_nodal_rgb                                         |  44.61  | 0.01 | 41.82  | 9.56  |  38.26   |   9.56    |    38.26     |   0.09   | 22.41 | 335.90 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  28.37  | 0.02 | 25.64  | 15.60 |  62.41   |   15.60   |    62.41     |   0.11   | 35.25 | 180.29 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  55.76  | 0.02 | 52.87  | 7.57  |  30.26   |   7.57    |    30.26     |   0.12   | 17.93 | 88.83  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  47.45  | 0.02 | 44.68  | 8.95  |  35.82   |   8.95    |    35.82     |   0.11   | 21.07 | 105.18 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  47.35  | 0.02 | 44.00  | 9.09  |  36.37   |   9.09    |    36.37     |   0.11   | 21.12 | 105.20 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  57.81  | 0.02 | 54.40  | 7.35  |  29.41   |   7.35    |    29.41     |   0.11   | 17.30 | 86.54  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  47.51  | 0.02 | 44.53  | 8.98  |  35.93   |   8.98    |    35.93     |   0.11   | 21.05 | 104.79 |
| tri3_tex8_grey_quintic_bspline_direct                   |  86.73  | 0.02 | 84.08  | 4.76  |  19.03   |   4.76    |    19.03     |   0.11   | 11.53 | 56.48  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  57.42  | 0.02 | 54.87  | 7.29  |  29.16   |   7.29    |    29.16     |   0.12   | 17.42 | 86.56  |
| tri6_tex8_grey_linear_direct                            |  48.59  | 0.01 | 46.01  | 8.69  |  34.78   |   8.69    |    34.78     |   0.17   | 20.58 | 205.51 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  74.31  | 0.01 | 72.17  | 5.54  |  22.17   |   5.54    |    22.17     |   0.16   | 13.46 | 132.30 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  67.24  | 0.01 | 65.11  | 6.14  |  24.57   |   6.14    |    24.57     |   0.16   | 14.87 | 146.56 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  67.88  | 0.01 | 65.78  | 6.08  |  24.33   |   6.08    |    24.33     |   0.17   | 14.73 | 145.01 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  80.17  | 0.01 | 78.00  | 5.13  |  20.51   |   5.13    |    20.51     |   0.17   | 12.47 | 122.33 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  67.15  | 0.01 | 64.94  | 6.16  |  24.64   |   6.16    |    24.64     |   0.17   | 14.89 | 146.60 |
| tri6_tex8_grey_quintic_bspline_direct                   | 105.76  | 0.01 | 103.59 | 3.86  |  15.45   |   3.86    |    15.45     |   0.16   | 9.46 | 92.37  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  78.84  | 0.01 | 76.75  | 5.21  |  20.85   |   5.21    |    20.85     |   0.16   | 12.68 | 124.49 |
| quad4ibi_tex8_grey_linear_direct                        |  33.64  | 0.01 | 31.41  | 12.74 |  50.94   |   12.74   |    50.94     |   0.10   | 29.73 | 200.62 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  64.20  | 0.01 | 61.99  | 6.45  |  25.81   |   6.45    |    25.81     |   0.10   | 15.58 | 102.37 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  64.70  | 0.01 | 62.50  | 6.40  |  25.60   |   6.40    |    25.60     |   0.10   | 15.46 | 101.73 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  64.53  | 0.01 | 62.35  | 6.42  |  25.66   |   6.42    |    25.66     |   0.11   | 15.50 | 102.06 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  81.86  | 0.01 | 78.69  | 5.08  |  20.33   |   5.08    |    20.33     |   0.07   | 12.22 | 80.00  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  65.13  | 0.01 | 62.79  | 6.37  |  25.48   |   6.37    |    25.48     |   0.10   | 15.35 | 100.93 |
| quad4ibi_tex8_grey_quintic_bspline_direct               | 100.58  | 0.01 | 97.66  | 4.10  |  16.38   |   4.10    |    16.38     |   0.10   | 9.94 | 64.83  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  81.28  | 0.01 | 79.14  | 5.05  |  20.22   |   5.05    |    20.22     |   0.10   | 12.30 | 80.52  |
| quad4newton_tex8_grey_linear_direct                     |  40.78  | 0.01 | 38.12  | 10.49 |  41.97   |   10.49   |    41.97     |   0.07   | 24.52 | 163.70 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  66.72  | 0.01 | 64.03  | 6.25  |  24.99   |   6.25    |    24.99     |   0.07   | 14.99 | 98.47  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  60.01  | 0.01 | 57.28  | 6.98  |  27.93   |   6.98    |    27.93     |   0.07   | 16.66 | 110.09 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  59.78  | 0.01 | 57.19  | 6.99  |  27.98   |   6.99    |    27.98     |   0.07   | 16.73 | 110.24 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  71.66  | 0.01 | 69.46  | 5.76  |  23.03   |   5.76    |    23.03     |   0.07   | 13.96 | 91.52  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  59.57  | 0.01 | 56.89  | 7.03  |  28.13   |   7.03    |    28.13     |   0.07   | 16.79 | 110.82 |
| quad4newton_tex8_grey_quintic_bspline_direct            | 100.21  | 0.01 | 97.63  | 4.10  |  16.39   |   4.10    |    16.39     |   0.07   | 9.98 | 65.00  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  72.41  | 0.01 | 69.79  | 5.73  |  22.93   |   5.73    |    22.93     |   0.07   | 13.81 | 90.59  |
| quad8_tex8_grey_linear_direct                           |  48.24  | 0.01 | 45.80  | 8.73  |  34.93   |   8.73    |    34.93     |   0.10   | 20.73 | 275.83 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  74.87  | 0.01 | 72.84  | 5.49  |  21.97   |   5.49    |    21.97     |   0.10   | 13.36 | 174.81 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  67.62  | 0.01 | 64.99  | 6.15  |  24.62   |   6.15    |    24.62     |   0.10   | 14.79 | 194.07 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  66.70  | 0.01 | 64.62  | 6.19  |  24.76   |   6.19    |    24.76     |   0.10   | 14.99 | 197.01 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  79.27  | 0.01 | 76.62  | 5.22  |  20.88   |   5.22    |    20.88     |   0.07   | 12.62 | 165.15 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  67.45  | 0.01 | 64.62  | 6.19  |  24.76   |   6.19    |    24.76     |   0.07   | 14.82 | 195.17 |
| quad8_tex8_grey_quintic_bspline_direct                  | 107.04  | 0.01 | 104.03 | 3.84  |  15.38   |   3.84    |    15.38     |   0.07   | 9.34 | 121.58 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  80.55  | 0.01 | 76.93  | 5.20  |  20.80   |   5.20    |    20.80     |   0.07   | 12.41 | 163.00 |
| quad9_tex8_grey_linear_direct                           |  49.33  | 0.01 | 46.35  | 8.63  |  34.52   |   8.63    |    34.52     |   0.07   | 20.27 | 303.72 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  78.35  | 0.01 | 74.80  | 5.35  |  21.39   |   5.35    |    21.39     |   0.07   | 12.76 | 187.94 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  68.91  | 0.01 | 66.33  | 6.03  |  24.12   |   6.03    |    24.12     |   0.07   | 14.51 | 214.35 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  68.26  | 0.01 | 64.94  | 6.16  |  24.64   |   6.16    |    24.64     |   0.07   | 14.65 | 216.79 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  80.19  | 0.01 | 77.56  | 5.16  |  20.63   |   5.16    |    20.63     |   0.07   | 12.47 | 183.50 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  67.69  | 0.01 | 64.95  | 6.16  |  24.63   |   6.16    |    24.63     |   0.07   | 14.77 | 218.82 |
| quad9_tex8_grey_quintic_bspline_direct                  | 106.74  | 0.01 | 103.75 | 3.86  |  15.42   |   3.86    |    15.42     |   0.07   | 9.37 | 137.18 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  79.16  | 0.01 | 76.57  | 5.22  |  20.90   |   5.22    |    20.90     |   0.07   | 12.63 | 185.98 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  38.14  | 0.01 | 33.85  | 11.82 |  47.27   |   11.82   |    47.27     |   0.18   | 26.22 | 132.31 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  75.87  | 0.01 | 72.12  | 5.55  |  22.19   |   5.55    |    22.19     |   0.19   | 13.18 | 64.95  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  70.37  | 0.01 | 67.40  | 5.93  |  23.74   |   5.93    |    23.74     |   0.18   | 14.21 | 69.97  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  70.59  | 0.01 | 67.90  | 5.89  |  23.56   |   5.89    |    23.56     |   0.19   | 14.17 | 69.64  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  86.83  | 0.01 | 83.88  | 4.77  |  19.08   |   4.77    |    19.08     |   0.19   | 11.52 | 56.53  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  68.93  | 0.01 | 65.67  | 6.09  |  24.36   |   6.09    |    24.36     |   0.19   | 14.51 | 71.52  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 114.04  | 0.01 | 111.32 | 3.59  |  14.37   |   3.59    |    14.37     |   0.19   | 8.77 | 42.72  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  87.18  | 0.01 | 83.68  | 4.78  |  19.12   |   4.78    |    19.12     |   0.19   | 11.47 | 56.14  |
| tri6_tex8_rgb_linear_direct                             |  67.65  | 0.01 | 64.31  | 6.22  |  24.88   |   6.22    |    24.88     |   0.16   | 14.78 | 145.51 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  94.72  | 0.01 | 91.65  | 4.36  |  17.46   |   4.36    |    17.46     |   0.16   | 10.56 | 103.49 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  87.86  | 0.01 | 84.04  | 4.76  |  19.04   |   4.76    |    19.04     |   0.16   | 11.38 | 111.36 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  86.25  | 0.01 | 83.51  | 4.79  |  19.16   |   4.79    |    19.16     |   0.17   | 11.59 | 113.54 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 104.66  | 0.01 | 101.22 | 3.95  |  15.81   |   3.95    |    15.81     |   0.15   | 9.55 | 93.33  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  85.99  | 0.01 | 83.02  | 4.82  |  19.27   |   4.82    |    19.27     |   0.16   | 11.63 | 114.05 |
| tri6_tex8_rgb_quintic_bspline_direct                    | 132.93  | 0.01 | 129.97 | 3.08  |  12.31   |   3.08    |    12.31     |   0.16   | 7.52 | 73.22  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 104.81  | 0.01 | 102.00 | 3.92  |  15.69   |   3.92    |    15.69     |   0.16   | 9.54 | 93.10  |
| quad4ibi_tex8_rgb_linear_direct                         |  43.37  | 0.01 | 40.65  | 9.84  |  39.36   |   9.84    |    39.36     |   0.11   | 23.06 | 153.55 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  78.66  | 0.01 | 75.71  | 5.28  |  21.13   |   5.28    |    21.13     |   0.10   | 12.71 | 83.30  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  83.15  | 0.01 | 79.89  | 5.01  |  20.03   |   5.01    |    20.03     |   0.11   | 12.03 | 78.62  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  83.36  | 0.01 | 79.96  | 5.00  |  20.01   |   5.00    |    20.01     |   0.10   | 12.00 | 78.34  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 106.66  | 0.01 | 103.92 | 3.85  |  15.40   |   3.85    |    15.40     |   0.11   | 9.38 | 60.97  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  83.05  | 0.01 | 79.73  | 5.02  |  20.07   |   5.02    |    20.07     |   0.11   | 12.04 | 78.89  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 135.23  | 0.01 | 131.51 | 3.04  |  12.17   |   3.04    |    12.17     |   0.11   | 7.40 | 47.95  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 108.41  | 0.01 | 104.33 | 3.83  |  15.34   |   3.83    |    15.34     |   0.11   | 9.22 | 60.00  |
| quad4newton_tex8_rgb_linear_direct                      |  58.61  | 0.01 | 54.83  | 7.30  |  29.18   |   7.30    |    29.18     |   0.11   | 17.06 | 112.66 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  86.62  | 0.01 | 83.03  | 4.82  |  19.27   |   4.82    |    19.27     |   0.11   | 11.55 | 75.44  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  78.61  | 0.01 | 74.46  | 5.37  |  21.49   |   5.37    |    21.49     |   0.11   | 12.72 | 83.27  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  77.99  | 0.01 | 74.37  | 5.38  |  21.51   |   5.38    |    21.51     |   0.11   | 12.82 | 83.92  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  96.61  | 0.01 | 92.82  | 4.31  |  17.24   |   4.31    |    17.24     |   0.11   | 10.35 | 67.43  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  77.61  | 0.01 | 74.79  | 5.35  |  21.39   |   5.35    |    21.39     |   0.10   | 12.88 | 84.27  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 124.07  | 0.01 | 121.24 | 3.30  |  13.20   |   3.30    |    13.20     |   0.11   | 8.06 | 52.30  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  96.46  | 0.01 | 93.58  | 4.27  |  17.10   |   4.27    |    17.10     |   0.10   | 10.37 | 67.61  |
| quad8_tex8_rgb_linear_direct                            |  67.55  | 0.01 | 63.31  | 6.32  |  25.28   |   6.32    |    25.28     |   0.10   | 14.80 | 194.53 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  93.62  | 0.01 | 89.80  | 4.45  |  17.82   |   4.45    |    17.82     |   0.10   | 10.68 | 139.66 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  86.45  | 0.01 | 82.82  | 4.83  |  19.32   |   4.83    |    19.32     |   0.10   | 11.57 | 151.34 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  86.01  | 0.01 | 82.08  | 4.87  |  19.49   |   4.87    |    19.49     |   0.10   | 11.63 | 152.02 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 103.31  | 0.01 | 99.93  | 4.00  |  16.01   |   4.00    |    16.01     |   0.10   | 9.68 | 126.00 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  85.44  | 0.01 | 82.04  | 4.88  |  19.50   |   4.88    |    19.50     |   0.10   | 11.70 | 152.82 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 131.42  | 0.01 | 128.46 | 3.11  |  12.46   |   3.11    |    12.46     |   0.10   | 7.61 | 98.64  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 103.64  | 0.01 | 100.89 | 3.96  |  15.86   |   3.96    |    15.86     |   0.10   | 9.65 | 125.51 |
| quad9_tex8_rgb_linear_direct                            |  67.01  | 0.01 | 63.50  | 6.30  |  25.20   |   6.30    |    25.20     |   0.10   | 14.92 | 221.25 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  95.09  | 0.01 | 91.25  | 4.38  |  17.54   |   4.38    |    17.54     |   0.10   | 10.52 | 154.19 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  86.99  | 0.01 | 82.78  | 4.83  |  19.33   |   4.83    |    19.33     |   0.10   | 11.50 | 168.89 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  87.27  | 0.01 | 83.31  | 4.80  |  19.21   |   4.80    |    19.21     |   0.10   | 11.46 | 168.29 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 103.84  | 0.01 | 100.10 | 4.00  |  15.98   |   4.00    |    15.98     |   0.10   | 9.63 | 141.15 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  86.80  | 0.01 | 82.60  | 4.84  |  19.37   |   4.84    |    19.37     |   0.10   | 11.52 | 169.23 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 132.63  | 0.01 | 128.63 | 3.11  |  12.44   |   3.11    |    12.44     |   0.10   | 7.54 | 110.20 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 104.68  | 0.01 | 100.97 | 3.96  |  15.85   |   3.96    |    15.85     |   0.10   | 9.55 | 139.85 |

