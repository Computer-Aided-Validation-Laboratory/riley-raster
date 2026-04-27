# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  14.55  | 0.02 | 11.46  | 34.98 |  139.92  |   34.98   |    139.92    |   0.13   | 68.75 | 382.76 |
| tri6_nodal_grey                                         |  39.02  | 0.01 | 36.93  | 10.83 |  43.33   |   10.83   |    43.33     |   0.16   | 25.63 | 257.32 |
| quad4ibi_nodal_grey                                     |  25.62  | 0.01 | 23.23  | 17.22 |  68.87   |   17.22   |    68.87     |   0.10   | 39.03 | 270.32 |
| quad4newton_nodal_grey                                  |  31.61  | 0.01 | 28.56  | 14.00 |  56.01   |   14.00   |    56.01     |   0.07   | 31.64 | 216.63 |
| quad8_nodal_grey                                        |  38.80  | 0.01 | 36.15  | 11.06 |  44.25   |   11.06   |    44.25     |   0.07   | 25.77 | 345.32 |
| quad9_nodal_grey                                        |  38.60  | 0.01 | 36.55  | 10.94 |  43.77   |   10.94   |    43.77     |   0.10   | 25.91 | 389.80 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  18.46  | 0.01 | 15.29  | 26.16 |  104.66  |   26.16   |    104.66    |   0.18   | 54.18 | 289.87 |
| tri6_nodal_rgb                                          |  44.75  | 0.01 | 41.84  | 9.56  |  38.24   |   9.56    |    38.24     |   0.15   | 22.35 | 223.63 |
| quad4ibi_nodal_rgb                                      |  34.45  | 0.01 | 31.38  | 12.75 |  50.98   |   12.75   |    50.98     |   0.10   | 29.03 | 196.84 |
| quad4newton_nodal_rgb                                   |  36.87  | 0.01 | 33.25  | 12.03 |  48.12   |   12.03   |    48.12     |   0.10   | 27.13 | 182.27 |
| quad8_nodal_rgb                                         |  44.69  | 0.01 | 41.12  | 9.73  |  38.91   |   9.73    |    38.91     |   0.10   | 22.38 | 298.00 |
| quad9_nodal_rgb                                         |  45.97  | 0.01 | 43.22  | 9.26  |  37.02   |   9.26    |    37.02     |   0.10   | 21.75 | 324.97 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  26.24  | 0.01 | 24.23  | 16.51 |  66.05   |   16.51   |    66.05     |   0.19   | 38.11 | 195.27 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  53.06  | 0.01 | 50.73  | 7.88  |  31.54   |   7.88    |    31.54     |   0.19   | 18.85 | 93.76  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  45.50  | 0.01 | 43.37  | 9.22  |  36.89   |   9.22    |    36.89     |   0.19   | 21.98 | 109.71 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  45.03  | 0.01 | 42.89  | 9.33  |  37.30   |   9.33    |    37.30     |   0.19   | 22.21 | 111.02 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  56.38  | 0.01 | 54.09  | 7.40  |  29.58   |   7.40    |    29.58     |   0.19   | 17.74 | 87.96  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  45.98  | 0.01 | 43.79  | 9.13  |  36.54   |   9.13    |    36.54     |   0.19   | 21.75 | 108.64 |
| tri3_tex8_grey_quintic_bspline_direct                   |  85.15  | 0.01 | 81.99  | 4.88  |  19.51   |   4.88    |    19.51     |   0.19   | 11.74 | 57.56  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  56.54  | 0.01 | 54.33  | 7.36  |  29.45   |   7.36    |    29.45     |   0.19   | 17.69 | 87.77  |
| tri6_tex8_grey_linear_direct                            |  48.42  | 0.01 | 45.89  | 8.72  |  34.87   |   8.72    |    34.87     |   0.16   | 20.65 | 206.13 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  74.99  | 0.02 | 72.17  | 5.54  |  22.17   |   5.54    |    22.17     |   0.10   | 13.34 | 131.44 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  67.93  | 0.02 | 65.05  | 6.15  |  24.60   |   6.15    |    24.60     |   0.12   | 14.72 | 145.26 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  67.00  | 0.01 | 64.72  | 6.18  |  24.72   |   6.18    |    24.72     |   0.16   | 14.93 | 147.33 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  79.25  | 0.01 | 76.55  | 5.23  |  20.90   |   5.23    |    20.90     |   0.17   | 12.62 | 123.81 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  68.52  | 0.01 | 66.33  | 6.03  |  24.12   |   6.03    |    24.12     |   0.16   | 14.59 | 143.91 |
| tri6_tex8_grey_quintic_bspline_direct                   | 106.78  | 0.01 | 104.74 | 3.82  |  15.28   |   3.82    |    15.28     |   0.17   | 9.37 | 91.32  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  79.26  | 0.01 | 76.52  | 5.23  |  20.91   |   5.23    |    20.91     |   0.17   | 12.62 | 123.73 |
| quad4ibi_tex8_grey_linear_direct                        |  33.59  | 0.01 | 31.48  | 12.71 |  50.83   |   12.71   |    50.83     |   0.10   | 29.77 | 201.11 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  64.02  | 0.01 | 61.88  | 6.46  |  25.85   |   6.46    |    25.85     |   0.11   | 15.62 | 102.83 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  64.75  | 0.01 | 62.44  | 6.41  |  25.62   |   6.41    |    25.62     |   0.11   | 15.44 | 101.85 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  65.99  | 0.01 | 63.52  | 6.30  |  25.19   |   6.30    |    25.19     |   0.08   | 15.15 | 99.79  |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  81.81  | 0.01 | 78.63  | 5.09  |  20.35   |   5.09    |    20.35     |   0.07   | 12.22 | 80.11  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  67.24  | 0.01 | 64.31  | 6.22  |  24.88   |   6.22    |    24.88     |   0.07   | 14.87 | 98.58  |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  99.62  | 0.01 | 96.86  | 4.13  |  16.52   |   4.13    |    16.52     |   0.07   | 10.04 | 65.50  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  81.93  | 0.01 | 79.29  | 5.05  |  20.18   |   5.05    |    20.18     |   0.11   | 12.21 | 79.94  |
| quad4newton_tex8_grey_linear_direct                     |  41.33  | 0.01 | 38.47  | 10.40 |  41.59   |   10.40   |    41.59     |   0.07   | 24.20 | 161.72 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  66.39  | 0.01 | 63.97  | 6.25  |  25.01   |   6.25    |    25.01     |   0.07   | 15.06 | 98.98  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  59.75  | 0.01 | 57.06  | 7.01  |  28.04   |   7.01    |    28.04     |   0.07   | 16.74 | 110.49 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  60.25  | 0.01 | 56.94  | 7.03  |  28.10   |   7.03    |    28.10     |   0.10   | 16.60 | 110.42 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  71.53  | 0.01 | 68.45  | 5.84  |  23.37   |   5.84    |    23.37     |   0.07   | 13.98 | 92.09  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  59.88  | 0.01 | 57.28  | 6.98  |  27.93   |   6.98    |    27.93     |   0.07   | 16.70 | 110.09 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  97.97  | 0.01 | 95.29  | 4.20  |  16.79   |   4.20    |    16.79     |   0.07   | 10.21 | 66.50  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  71.25  | 0.01 | 68.56  | 5.83  |  23.34   |   5.83    |    23.34     |   0.07   | 14.04 | 92.27  |
| quad8_tex8_grey_linear_direct                           |  49.10  | 0.01 | 45.99  | 8.70  |  34.79   |   8.70    |    34.79     |   0.07   | 20.37 | 270.31 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  74.28  | 0.01 | 71.64  | 5.58  |  22.33   |   5.58    |    22.33     |   0.07   | 13.46 | 176.54 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  67.41  | 0.01 | 64.49  | 6.20  |  24.81   |   6.20    |    24.81     |   0.07   | 14.83 | 195.43 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  67.26  | 0.01 | 64.53  | 6.20  |  24.80   |   6.20    |    24.80     |   0.07   | 14.87 | 195.74 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  80.31  | 0.01 | 77.58  | 5.16  |  20.62   |   5.16    |    20.62     |   0.07   | 12.45 | 163.08 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  67.92  | 0.01 | 65.17  | 6.14  |  24.55   |   6.14    |    24.55     |   0.07   | 14.72 | 193.79 |
| quad8_tex8_grey_quintic_bspline_direct                  | 107.07  | 0.01 | 103.79 | 3.85  |  15.42   |   3.85    |    15.42     |   0.07   | 9.34 | 122.31 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  79.14  | 0.01 | 76.46  | 5.23  |  20.93   |   5.23    |    20.93     |   0.07   | 12.64 | 165.51 |
| quad9_tex8_grey_linear_direct                           |  48.07  | 0.01 | 45.94  | 8.71  |  34.82   |   8.71    |    34.82     |   0.10   | 20.80 | 310.90 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  74.46  | 0.01 | 72.14  | 5.54  |  22.18   |   5.54    |    22.18     |   0.10   | 13.43 | 198.40 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  66.76  | 0.01 | 64.69  | 6.18  |  24.73   |   6.18    |    24.73     |   0.10   | 14.98 | 221.19 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  68.20  | 0.01 | 65.40  | 6.12  |  24.47   |   6.12    |    24.47     |   0.10   | 14.66 | 216.61 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  80.18  | 0.01 | 77.36  | 5.17  |  20.69   |   5.17    |    20.69     |   0.10   | 12.47 | 185.19 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  67.21  | 0.01 | 65.12  | 6.14  |  24.57   |   6.14    |    24.57     |   0.10   | 14.88 | 219.73 |
| quad9_tex8_grey_quintic_bspline_direct                  | 107.09  | 0.01 | 104.75 | 3.82  |  15.27   |   3.82    |    15.27     |   0.08   | 9.34 | 136.63 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  79.95  | 0.01 | 76.71  | 5.21  |  20.86   |   5.21    |    20.86     |   0.07   | 12.51 | 184.22 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  35.82  | 0.01 | 33.14  | 12.07 |  48.29   |   12.07   |    48.29     |   0.19   | 27.91 | 140.50 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  69.27  | 0.01 | 66.48  | 6.02  |  24.07   |   6.02    |    24.07     |   0.18   | 14.44 | 71.08  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  63.41  | 0.01 | 60.59  | 6.60  |  26.41   |   6.60    |    26.41     |   0.18   | 15.77 | 77.80  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  63.38  | 0.01 | 60.42  | 6.62  |  26.48   |   6.62    |    26.48     |   0.18   | 15.78 | 77.97  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  80.30  | 0.01 | 77.48  | 5.16  |  20.65   |   5.16    |    20.65     |   0.19   | 12.45 | 61.14  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  63.51  | 0.01 | 60.72  | 6.59  |  26.35   |   6.59    |    26.35     |   0.19   | 15.74 | 77.65  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 108.33  | 0.01 | 104.85 | 3.81  |  15.26   |   3.81    |    15.26     |   0.18   | 9.23 | 45.05  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  81.94  | 0.01 | 79.01  | 5.06  |  20.25   |   5.06    |    20.25     |   0.19   | 12.20 | 59.82  |
| tri6_tex8_rgb_linear_direct                             |  66.79  | 0.01 | 63.95  | 6.25  |  25.02   |   6.25    |    25.02     |   0.17   | 14.97 | 147.53 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  93.52  | 0.01 | 90.79  | 4.41  |  17.62   |   4.41    |    17.62     |   0.17   | 10.69 | 104.55 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  87.76  | 0.01 | 85.07  | 4.70  |  18.81   |   4.70    |    18.81     |   0.17   | 11.39 | 111.49 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  87.20  | 0.01 | 84.47  | 4.74  |  18.94   |   4.74    |    18.94     |   0.16   | 11.47 | 112.23 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 104.11  | 0.01 | 101.42 | 3.94  |  15.78   |   3.94    |    15.78     |   0.16   | 9.61 | 93.70  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  87.12  | 0.01 | 84.30  | 4.75  |  18.98   |   4.75    |    18.98     |   0.16   | 11.48 | 112.47 |
| tri6_tex8_rgb_quintic_bspline_direct                    | 132.27  | 0.01 | 129.55 | 3.09  |  12.35   |   3.09    |    12.35     |   0.16   | 7.56 | 73.52  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 103.58  | 0.01 | 100.69 | 3.97  |  15.89   |   3.97    |    15.89     |   0.16   | 9.65 | 94.31  |
| quad4ibi_tex8_rgb_linear_direct                         |  45.12  | 0.01 | 40.81  | 9.80  |  39.21   |   9.80    |    39.21     |   0.11   | 22.16 | 147.49 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  80.48  | 0.01 | 76.93  | 5.20  |  20.80   |   5.20    |    20.80     |   0.11   | 12.43 | 81.29  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  84.03  | 0.01 | 80.29  | 4.98  |  19.93   |   4.98    |    19.93     |   0.11   | 11.90 | 77.92  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  82.93  | 0.01 | 79.41  | 5.04  |  20.15   |   5.04    |    20.15     |   0.11   | 12.06 | 78.79  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 107.30  | 0.01 | 103.80 | 3.85  |  15.42   |   3.85    |    15.42     |   0.11   | 9.32 | 60.62  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  84.53  | 0.01 | 80.95  | 4.94  |  19.77   |   4.94    |    19.77     |   0.11   | 11.83 | 77.44  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 135.34  | 0.01 | 131.31 | 3.05  |  12.19   |   3.05    |    12.19     |   0.11   | 7.39 | 47.89  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 108.59  | 0.01 | 104.94 | 3.81  |  15.25   |   3.81    |    15.25     |   0.10   | 9.21 | 60.25  |
| quad4newton_tex8_rgb_linear_direct                      |  58.62  | 0.01 | 54.85  | 7.29  |  29.17   |   7.29    |    29.17     |   0.11   | 17.06 | 113.08 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  86.40  | 0.01 | 82.32  | 4.86  |  19.44   |   4.86    |    19.44     |   0.11   | 11.57 | 75.64  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  78.88  | 0.01 | 74.51  | 5.37  |  21.47   |   5.37    |    21.47     |   0.11   | 12.68 | 82.97  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  79.01  | 0.01 | 75.06  | 5.33  |  21.32   |   5.33    |    21.32     |   0.10   | 12.66 | 82.83  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  96.48  | 0.01 | 92.09  | 4.34  |  17.37   |   4.34    |    17.37     |   0.11   | 10.37 | 67.73  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  79.33  | 0.01 | 75.58  | 5.29  |  21.17   |   5.29    |    21.17     |   0.10   | 12.61 | 82.52  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 124.05  | 0.01 | 120.40 | 3.32  |  13.29   |   3.32    |    13.29     |   0.11   | 8.06 | 52.37  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  96.38  | 0.01 | 92.65  | 4.32  |  17.27   |   4.32    |    17.27     |   0.11   | 10.38 | 67.61  |
| quad8_tex8_rgb_linear_direct                            |  66.62  | 0.01 | 62.82  | 6.37  |  25.47   |   6.37    |    25.47     |   0.10   | 15.01 | 197.71 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  94.18  | 0.01 | 89.72  | 4.46  |  17.83   |   4.46    |    17.83     |   0.10   | 10.62 | 138.50 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  85.83  | 0.01 | 82.28  | 4.86  |  19.45   |   4.86    |    19.45     |   0.10   | 11.65 | 152.22 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  85.85  | 0.01 | 82.24  | 4.86  |  19.46   |   4.86    |    19.46     |   0.11   | 11.65 | 152.18 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 104.03  | 0.01 | 100.25 | 3.99  |  15.96   |   3.99    |    15.96     |   0.10   | 9.61 | 125.24 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  87.62  | 0.01 | 83.03  | 4.82  |  19.27   |   4.82    |    19.27     |   0.10   | 11.41 | 149.01 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 130.90  | 0.01 | 127.47 | 3.14  |  12.55   |   3.14    |    12.55     |   0.09   | 7.64 | 99.25  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 103.03  | 0.01 | 100.13 | 3.99  |  15.98   |   3.99    |    15.98     |   0.10   | 9.71 | 126.51 |
| quad9_tex8_rgb_linear_direct                            |  67.27  | 0.01 | 63.95  | 6.26  |  25.02   |   6.26    |    25.02     |   0.10   | 14.87 | 219.66 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  94.62  | 0.01 | 90.41  | 4.42  |  17.70   |   4.42    |    17.70     |   0.09   | 10.57 | 155.28 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  86.32  | 0.01 | 83.55  | 4.79  |  19.15   |   4.79    |    19.15     |   0.10   | 11.59 | 170.18 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  86.61  | 0.01 | 83.70  | 4.78  |  19.12   |   4.78    |    19.12     |   0.10   | 11.55 | 169.98 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 103.87  | 0.01 | 100.16 | 3.99  |  15.97   |   3.99    |    15.97     |   0.10   | 9.63 | 141.49 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  87.09  | 0.01 | 84.19  | 4.75  |  19.00   |   4.75    |    19.00     |   0.10   | 11.48 | 168.90 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 132.13  | 0.01 | 129.08 | 3.10  |  12.40   |   3.10    |    12.40     |   0.09   | 7.57 | 110.67 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 104.48  | 0.01 | 101.33 | 3.95  |  15.79   |   3.95    |    15.79     |   0.10   | 9.57 | 140.36 |

