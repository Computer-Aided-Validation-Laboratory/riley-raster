# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  13.45  | 0.02 | 10.66  | 37.52 |  150.10  |   37.52   |    150.10    |   0.11   | 74.35 | 413.22 |
| tri6_nodal_grey                                         |  43.02  | 0.02 | 40.40  | 9.90  |  39.61   |   9.90    |    39.61     |   0.11   | 23.24 | 232.79 |
| quad4ibi_nodal_grey                                     |  26.59  | 0.01 | 24.24  | 16.50 |  65.99   |   16.50   |    65.99     |   0.10   | 37.61 | 260.14 |
| quad4newton_nodal_grey                                  |  32.45  | 0.01 | 29.78  | 13.43 |  53.72   |   13.43   |    53.72     |   0.07   | 30.82 | 211.31 |
| quad8_nodal_grey                                        |  39.46  | 0.01 | 35.82  | 11.17 |  44.66   |   11.17   |    44.66     |   0.07   | 25.36 | 340.17 |
| quad9_nodal_grey                                        |  41.37  | 0.01 | 38.02  | 10.53 |  42.13   |   10.53   |    42.13     |   0.10   | 24.17 | 362.86 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  18.52  | 0.01 | 15.28  | 26.19 |  104.75  |   26.19   |    104.75    |   0.17   | 53.98 | 290.85 |
| tri6_nodal_rgb                                          |  53.14  | 0.02 | 49.52  | 8.08  |  32.31   |   8.08    |    32.31     |   0.11   | 18.82 | 188.00 |
| quad4ibi_nodal_rgb                                      |  34.52  | 0.01 | 31.70  | 12.62 |  50.48   |   12.62   |    50.48     |   0.10   | 28.97 | 195.19 |
| quad4newton_nodal_rgb                                   |  37.42  | 0.01 | 34.14  | 11.72 |  46.88   |   11.72   |    46.88     |   0.10   | 26.72 | 179.15 |
| quad8_nodal_rgb                                         |  44.01  | 0.01 | 40.23  | 9.94  |  39.77   |   9.94    |    39.77     |   0.10   | 22.72 | 302.52 |
| quad9_nodal_rgb                                         |  46.75  | 0.01 | 43.38  | 9.22  |  36.88   |   9.22    |    36.88     |   0.09   | 21.39 | 319.63 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  27.07  | 0.02 | 24.53  | 16.30 |  65.22   |   16.30   |    65.22     |   0.11   | 36.94 | 189.82 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  54.05  | 0.02 | 51.32  | 7.79  |  31.18   |   7.79    |    31.18     |   0.11   | 18.50 | 91.98  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  46.68  | 0.02 | 44.01  | 9.09  |  36.35   |   9.09    |    36.35     |   0.11   | 21.42 | 106.73 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  46.28  | 0.02 | 43.61  | 9.17  |  36.69   |   9.17    |    36.69     |   0.11   | 21.61 | 107.81 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  59.55  | 0.02 | 56.65  | 7.06  |  28.25   |   7.06    |    28.25     |   0.11   | 16.79 | 83.53  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  47.77  | 0.02 | 44.82  | 8.93  |  35.70   |   8.93    |    35.70     |   0.13   | 20.93 | 104.50 |
| tri3_tex8_grey_quintic_bspline_direct                   |  87.85  | 0.01 | 83.62  | 4.78  |  19.14   |   4.78    |    19.14     |   0.15   | 11.38 | 56.15  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  58.74  | 0.01 | 56.66  | 7.06  |  28.24   |   7.06    |    28.24     |   0.17   | 17.02 | 84.20  |
| tri6_tex8_grey_linear_direct                            |  55.94  | 0.01 | 53.58  | 7.47  |  29.86   |   7.47    |    29.86     |   0.14   | 17.88 | 177.38 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  77.99  | 0.02 | 75.85  | 5.27  |  21.09   |   5.27    |    21.09     |   0.13   | 12.82 | 125.83 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  67.08  | 0.01 | 64.91  | 6.16  |  24.65   |   6.16    |    24.65     |   0.14   | 14.91 | 146.76 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  70.36  | 0.01 | 67.52  | 5.92  |  23.70   |   5.92    |    23.70     |   0.16   | 14.21 | 139.94 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  83.98  | 0.01 | 80.50  | 4.97  |  19.88   |   4.97    |    19.88     |   0.15   | 11.91 | 116.77 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  70.22  | 0.01 | 67.36  | 5.94  |  23.75   |   5.94    |    23.75     |   0.14   | 14.24 | 140.72 |
| tri6_tex8_grey_quintic_bspline_direct                   | 111.42  | 0.02 | 108.19 | 3.70  |  14.79   |   3.70    |    14.79     |   0.13   | 8.97 | 88.04  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  83.68  | 0.01 | 80.31  | 4.98  |  19.92   |   4.98    |    19.92     |   0.15   | 11.95 | 117.89 |
| quad4ibi_tex8_grey_linear_direct                        |  34.29  | 0.01 | 30.93  | 12.93 |  51.73   |   12.93   |    51.73     |   0.07   | 29.17 | 200.54 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  64.89  | 0.01 | 62.49  | 6.40  |  25.61   |   6.40    |    25.61     |   0.08   | 15.41 | 101.26 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  62.80  | 0.01 | 60.24  | 6.64  |  26.56   |   6.64    |    26.56     |   0.11   | 15.92 | 104.61 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  61.18  | 0.01 | 59.26  | 6.75  |  27.00   |   6.75    |    27.00     |   0.11   | 16.34 | 107.40 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  76.14  | 0.01 | 74.21  | 5.39  |  21.56   |   5.39    |    21.56     |   0.11   | 13.13 | 85.85  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  61.17  | 0.01 | 59.24  | 6.75  |  27.01   |   6.75    |    27.01     |   0.11   | 16.35 | 107.41 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  94.03  | 0.01 | 91.52  | 4.37  |  17.48   |   4.37    |    17.48     |   0.11   | 10.63 | 69.29  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  77.14  | 0.01 | 74.66  | 5.36  |  21.43   |   5.36    |    21.43     |   0.07   | 12.96 | 84.78  |
| quad4newton_tex8_grey_linear_direct                     |  40.23  | 0.01 | 37.81  | 10.58 |  42.31   |   10.58   |    42.31     |   0.10   | 24.85 | 166.10 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  67.80  | 0.01 | 64.35  | 6.22  |  24.87   |   6.22    |    24.87     |   0.11   | 14.75 | 96.87  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  57.91  | 0.01 | 55.91  | 7.15  |  28.62   |   7.15    |    28.62     |   0.11   | 17.27 | 113.76 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  59.13  | 0.01 | 55.98  | 7.15  |  28.58   |   7.15    |    28.58     |   0.09   | 16.91 | 111.47 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  67.40  | 0.01 | 64.82  | 6.17  |  24.68   |   6.17    |    24.68     |   0.07   | 14.84 | 97.36  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  56.65  | 0.01 | 54.06  | 7.40  |  29.60   |   7.40    |    29.60     |   0.07   | 17.65 | 116.41 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  94.54  | 0.01 | 90.98  | 4.40  |  17.59   |   4.40    |    17.59     |   0.07   | 10.58 | 69.11  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  73.09  | 0.01 | 70.14  | 5.70  |  22.81   |   5.70    |    22.81     |   0.07   | 13.68 | 89.70  |
| quad8_tex8_grey_linear_direct                           |  48.02  | 0.01 | 45.48  | 8.79  |  35.18   |   8.79    |    35.18     |   0.07   | 20.82 | 276.32 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  71.78  | 0.01 | 69.26  | 5.78  |  23.10   |   5.78    |    23.10     |   0.07   | 13.93 | 182.64 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  68.52  | 0.01 | 65.65  | 6.09  |  24.37   |   6.09    |    24.37     |   0.07   | 14.60 | 191.74 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  68.30  | 0.01 | 64.79  | 6.17  |  24.70   |   6.17    |    24.70     |   0.07   | 14.64 | 192.99 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  79.02  | 0.01 | 75.95  | 5.27  |  21.07   |   5.27    |    21.07     |   0.09   | 12.66 | 167.73 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  65.58  | 0.01 | 63.58  | 6.29  |  25.17   |   6.29    |    25.17     |   0.10   | 15.25 | 200.24 |
| quad8_tex8_grey_quintic_bspline_direct                  | 104.25  | 0.01 | 102.29 | 3.91  |  15.64   |   3.91    |    15.64     |   0.10   | 9.59 | 124.72 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  75.16  | 0.01 | 73.19  | 5.47  |  21.86   |   5.47    |    21.86     |   0.10   | 13.31 | 174.11 |
| quad9_tex8_grey_linear_direct                           |  48.50  | 0.01 | 46.45  | 8.61  |  34.45   |   8.61    |    34.45     |   0.10   | 20.62 | 307.70 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  76.41  | 0.01 | 74.15  | 5.39  |  21.58   |   5.39    |    21.58     |   0.10   | 13.09 | 193.26 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  71.51  | 0.01 | 68.78  | 5.82  |  23.26   |   5.82    |    23.26     |   0.09   | 13.98 | 207.22 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  68.03  | 0.01 | 65.99  | 6.06  |  24.25   |   6.06    |    24.25     |   0.10   | 14.70 | 217.07 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  74.70  | 0.01 | 72.73  | 5.50  |  22.00   |   5.50    |    22.00     |   0.10   | 13.39 | 197.01 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  65.40  | 0.01 | 63.39  | 6.31  |  25.24   |   6.31    |    25.24     |   0.10   | 15.29 | 225.93 |
| quad9_tex8_grey_quintic_bspline_direct                  | 100.17  | 0.01 | 98.22  | 4.07  |  16.29   |   4.07    |    16.29     |   0.10   | 9.98 | 146.09 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  76.22  | 0.01 | 72.70  | 5.50  |  22.01   |   5.50    |    22.01     |   0.11   | 13.13 | 193.06 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  38.29  | 0.01 | 35.22  | 11.36 |  45.43   |   11.36   |    45.43     |   0.18   | 26.11 | 132.30 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  69.98  | 0.01 | 67.16  | 5.96  |  23.83   |   5.96    |    23.83     |   0.19   | 14.29 | 70.42  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  67.86  | 0.01 | 64.49  | 6.20  |  24.81   |   6.20    |    24.81     |   0.18   | 14.74 | 72.70  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  65.68  | 0.01 | 61.93  | 6.46  |  25.84   |   6.46    |    25.84     |   0.18   | 15.23 | 75.33  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  83.57  | 0.01 | 80.44  | 4.97  |  19.89   |   4.97    |    19.89     |   0.19   | 11.97 | 58.82  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  65.88  | 0.01 | 62.99  | 6.35  |  25.40   |   6.35    |    25.40     |   0.17   | 15.18 | 74.82  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 114.39  | 0.01 | 111.16 | 3.60  |  14.39   |   3.60    |    14.39     |   0.17   | 8.74 | 42.62  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  86.63  | 0.01 | 82.16  | 4.87  |  19.47   |   4.87    |    19.47     |   0.18   | 11.54 | 56.54  |
| tri6_tex8_rgb_linear_direct                             |  68.74  | 0.01 | 65.45  | 6.11  |  24.45   |   6.11    |    24.45     |   0.16   | 14.55 | 143.34 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  96.60  | 0.01 | 90.84  | 4.40  |  17.61   |   4.40    |    17.61     |   0.14   | 10.35 | 101.96 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  84.91  | 0.01 | 82.29  | 4.86  |  19.44   |   4.86    |    19.44     |   0.16   | 11.78 | 115.26 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  85.63  | 0.01 | 80.46  | 4.97  |  19.89   |   4.97    |    19.89     |   0.17   | 11.68 | 115.52 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  97.72  | 0.01 | 95.15  | 4.20  |  16.82   |   4.20    |    16.82     |   0.16   | 10.23 | 99.86  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  81.62  | 0.01 | 79.04  | 5.06  |  20.24   |   5.06    |    20.24     |   0.16   | 12.25 | 119.95 |
| tri6_tex8_rgb_quintic_bspline_direct                    | 125.19  | 0.01 | 122.60 | 3.26  |  13.05   |   3.26    |    13.05     |   0.17   | 7.99 | 77.68  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  98.23  | 0.01 | 95.61  | 4.18  |  16.73   |   4.18    |    16.73     |   0.17   | 10.18 | 99.33  |
| quad4ibi_tex8_rgb_linear_direct                         |  42.22  | 0.01 | 38.47  | 10.40 |  41.59   |   10.40   |    41.59     |   0.11   | 23.69 | 157.75 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  76.78  | 0.01 | 73.05  | 5.48  |  21.90   |   5.48    |    21.90     |   0.11   | 13.02 | 85.19  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  86.12  | 0.01 | 82.34  | 4.86  |  19.43   |   4.86    |    19.43     |   0.10   | 11.61 | 75.86  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  83.80  | 0.01 | 80.98  | 4.94  |  19.76   |   4.94    |    19.76     |   0.10   | 11.93 | 77.95  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 110.40  | 0.01 | 107.09 | 3.74  |  14.94   |   3.74    |    14.94     |   0.09   | 9.06 | 58.89  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  82.73  | 0.01 | 78.09  | 5.12  |  20.49   |   5.12    |    20.49     |   0.11   | 12.09 | 79.03  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 135.13  | 0.01 | 131.56 | 3.04  |  12.16   |   3.04    |    12.16     |   0.10   | 7.40 | 47.94  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 110.23  | 0.01 | 105.29 | 3.80  |  15.20   |   3.80    |    15.20     |   0.11   | 9.07 | 59.41  |
| quad4newton_tex8_rgb_linear_direct                      |  58.16  | 0.01 | 55.14  | 7.25  |  29.02   |   7.25    |    29.02     |   0.10   | 17.20 | 113.37 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  86.54  | 0.01 | 82.37  | 4.86  |  19.42   |   4.86    |    19.42     |   0.10   | 11.56 | 76.00  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  78.81  | 0.01 | 74.91  | 5.34  |  21.36   |   5.34    |    21.36     |   0.10   | 12.69 | 83.51  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  76.84  | 0.01 | 73.37  | 5.45  |  21.81   |   5.45    |    21.81     |   0.11   | 13.01 | 85.18  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  92.95  | 0.01 | 90.21  | 4.43  |  17.74   |   4.43    |    17.74     |   0.11   | 10.76 | 70.13  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  75.92  | 0.01 | 72.94  | 5.48  |  21.94   |   5.48    |    21.94     |   0.11   | 13.17 | 86.25  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 119.72  | 0.01 | 115.52 | 3.46  |  13.85   |   3.46    |    13.85     |   0.11   | 8.35 | 54.22  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  95.23  | 0.01 | 91.07  | 4.39  |  17.57   |   4.39    |    17.57     |   0.11   | 10.50 | 68.60  |
| quad8_tex8_rgb_linear_direct                            |  65.66  | 0.01 | 62.70  | 6.38  |  25.52   |   6.38    |    25.52     |   0.10   | 15.23 | 199.93 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  93.80  | 0.01 | 90.62  | 4.41  |  17.66   |   4.41    |    17.66     |   0.10   | 10.66 | 138.92 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  85.79  | 0.01 | 83.01  | 4.82  |  19.28   |   4.82    |    19.28     |   0.10   | 11.66 | 152.07 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  84.55  | 0.01 | 80.44  | 4.97  |  19.90   |   4.97    |    19.90     |   0.10   | 11.83 | 154.54 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 102.45  | 0.01 | 99.18  | 4.03  |  16.13   |   4.03    |    16.13     |   0.10   | 9.76 | 126.97 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  85.62  | 0.01 | 82.24  | 4.86  |  19.46   |   4.86    |    19.46     |   0.10   | 11.68 | 152.45 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 131.16  | 0.01 | 127.51 | 3.14  |  12.55   |   3.14    |    12.55     |   0.10   | 7.62 | 98.82  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  98.97  | 0.01 | 95.92  | 4.17  |  16.68   |   4.17    |    16.68     |   0.10   | 10.11 | 131.58 |
| quad9_tex8_rgb_linear_direct                            |  62.62  | 0.01 | 60.02  | 6.66  |  26.66   |   6.66    |    26.66     |   0.10   | 15.97 | 236.04 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  89.37  | 0.01 | 86.42  | 4.63  |  18.51   |   4.63    |    18.51     |   0.10   | 11.19 | 164.01 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  82.00  | 0.01 | 79.43  | 5.04  |  20.14   |   5.04    |    20.14     |   0.10   | 12.19 | 179.08 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  81.55  | 0.01 | 78.97  | 5.06  |  20.26   |   5.06    |    20.26     |   0.10   | 12.26 | 180.09 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  97.74  | 0.01 | 95.07  | 4.21  |  16.83   |   4.21    |    16.83     |   0.10   | 10.23 | 149.74 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  84.11  | 0.01 | 81.43  | 4.91  |  19.65   |   4.91    |    19.65     |   0.10   | 11.89 | 174.69 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 133.55  | 0.01 | 129.14 | 3.10  |  12.39   |   3.10    |    12.39     |   0.10   | 7.49 | 109.43 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 103.73  | 0.01 | 99.47  | 4.02  |  16.09   |   4.02    |    16.09     |   0.11   | 9.64 | 141.16 |

