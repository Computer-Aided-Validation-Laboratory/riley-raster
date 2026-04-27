# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  13.80  | 0.02 | 10.79  | 37.08 |  148.30  |   37.08   |    148.30    |   0.11   | 72.46 | 397.74 |
| tri6_nodal_grey                                         |  39.36  | 0.01 | 37.29  | 10.73 |  42.91   |   10.73   |    42.91     |   0.16   | 25.41 | 254.99 |
| quad4ibi_nodal_grey                                     |  25.58  | 0.01 | 23.38  | 17.11 |  68.44   |   17.11   |    68.44     |   0.10   | 39.09 | 269.72 |
| quad4newton_nodal_grey                                  |  31.18  | 0.01 | 28.98  | 13.80 |  55.22   |   13.80   |    55.22     |   0.10   | 32.07 | 218.21 |
| quad8_nodal_grey                                        |  39.44  | 0.01 | 36.92  | 10.83 |  43.34   |   10.83   |    43.34     |   0.07   | 25.35 | 339.17 |
| quad9_nodal_grey                                        |  40.63  | 0.01 | 37.50  | 10.67 |  42.66   |   10.67   |    42.66     |   0.07   | 24.61 | 371.08 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  19.19  | 0.01 | 15.18  | 26.37 |  105.46  |   26.37   |    105.46    |   0.18   | 52.13 | 276.25 |
| tri6_nodal_rgb                                          |  44.63  | 0.01 | 41.93  | 9.54  |  38.16   |   9.54    |    38.16     |   0.16   | 22.41 | 223.48 |
| quad4ibi_nodal_rgb                                      |  34.20  | 0.01 | 31.12  | 12.86 |  51.42   |   12.86   |    51.42     |   0.09   | 29.24 | 197.75 |
| quad4newton_nodal_rgb                                   |  36.32  | 0.01 | 33.40  | 11.98 |  47.91   |   11.98   |    47.91     |   0.10   | 27.53 | 185.24 |
| quad8_nodal_rgb                                         |  44.57  | 0.01 | 40.93  | 9.77  |  39.09   |   9.77    |    39.09     |   0.09   | 22.44 | 300.72 |
| quad9_nodal_rgb                                         |  45.03  | 0.01 | 41.34  | 9.67  |  38.70   |   9.67    |    38.70     |   0.10   | 22.21 | 333.14 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  27.33  | 0.02 | 24.51  | 16.32 |  65.28   |   16.32   |    65.28     |   0.12   | 36.59 | 187.69 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  55.04  | 0.02 | 51.25  | 7.80  |  31.22   |   7.80    |    31.22     |   0.11   | 18.17 | 91.00  |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  46.22  | 0.02 | 43.61  | 9.17  |  36.69   |   9.17    |    36.69     |   0.11   | 21.64 | 108.32 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  47.28  | 0.02 | 44.56  | 8.98  |  35.91   |   8.98    |    35.91     |   0.11   | 21.15 | 105.41 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  57.23  | 0.02 | 54.69  | 7.31  |  29.26   |   7.31    |    29.26     |   0.11   | 17.47 | 86.46  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  46.03  | 0.02 | 43.35  | 9.23  |  36.91   |   9.23    |    36.91     |   0.11   | 21.73 | 108.48 |
| tri3_tex8_grey_quintic_bspline_direct                   |  85.29  | 0.02 | 82.30  | 4.86  |  19.44   |   4.86    |    19.44     |   0.11   | 11.72 | 57.44  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  57.17  | 0.02 | 54.38  | 7.36  |  29.42   |   7.36    |    29.42     |   0.11   | 17.49 | 86.92  |
| tri6_tex8_grey_linear_direct                            |  48.38  | 0.01 | 46.28  | 8.64  |  34.57   |   8.64    |    34.57     |   0.16   | 20.67 | 205.79 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  75.86  | 0.01 | 73.14  | 5.47  |  21.88   |   5.47    |    21.88     |   0.17   | 13.18 | 129.52 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  67.77  | 0.01 | 65.54  | 6.10  |  24.41   |   6.10    |    24.41     |   0.17   | 14.76 | 145.48 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  67.64  | 0.01 | 65.45  | 6.11  |  24.45   |   6.11    |    24.45     |   0.17   | 14.78 | 145.59 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  79.33  | 0.01 | 77.18  | 5.18  |  20.73   |   5.18    |    20.73     |   0.16   | 12.61 | 123.82 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  67.69  | 0.01 | 65.65  | 6.09  |  24.37   |   6.09    |    24.37     |   0.17   | 14.77 | 145.45 |
| tri6_tex8_grey_quintic_bspline_direct                   | 107.39  | 0.01 | 105.31 | 3.80  |  15.19   |   3.80    |    15.19     |   0.16   | 9.31 | 90.86  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  79.01  | 0.01 | 76.79  | 5.21  |  20.84   |   5.21    |    20.84     |   0.17   | 12.66 | 124.39 |
| quad4ibi_tex8_grey_linear_direct                        |  33.51  | 0.01 | 31.44  | 12.72 |  50.89   |   12.72   |    50.89     |   0.10   | 29.84 | 201.11 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  64.05  | 0.01 | 61.83  | 6.47  |  25.88   |   6.47    |    25.88     |   0.10   | 15.61 | 102.77 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  65.84  | 0.01 | 63.78  | 6.27  |  25.09   |   6.27    |    25.09     |   0.10   | 15.19 | 99.73  |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  64.63  | 0.01 | 62.43  | 6.41  |  25.63   |   6.41    |    25.63     |   0.10   | 15.47 | 101.84 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  80.26  | 0.01 | 78.11  | 5.12  |  20.48   |   5.12    |    20.48     |   0.11   | 12.46 | 81.56  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  65.61  | 0.01 | 62.77  | 6.37  |  25.49   |   6.37    |    25.49     |   0.07   | 15.24 | 100.26 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  98.86  | 0.01 | 96.32  | 4.15  |  16.61   |   4.15    |    16.61     |   0.07   | 10.11 | 65.89  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  82.03  | 0.01 | 79.99  | 5.00  |  20.00   |   5.00    |    20.00     |   0.10   | 12.19 | 79.62  |
| quad4newton_tex8_grey_linear_direct                     |  40.37  | 0.01 | 38.25  | 10.46 |  41.83   |   10.46   |    41.83     |   0.11   | 24.77 | 165.73 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  66.37  | 0.01 | 64.12  | 6.24  |  24.95   |   6.24    |    24.95     |   0.10   | 15.07 | 99.25  |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  60.28  | 0.01 | 57.62  | 6.94  |  27.77   |   6.94    |    27.77     |   0.11   | 16.59 | 109.40 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  59.41  | 0.01 | 57.31  | 6.98  |  27.92   |   6.98    |    27.92     |   0.11   | 16.83 | 111.00 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  72.39  | 0.01 | 70.21  | 5.70  |  22.79   |   5.70    |    22.79     |   0.10   | 13.82 | 90.50  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  59.69  | 0.01 | 57.35  | 6.97  |  27.90   |   6.97    |    27.90     |   0.11   | 16.75 | 110.63 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  97.84  | 0.01 | 95.57  | 4.19  |  16.74   |   4.19    |    16.74     |   0.11   | 10.22 | 66.70  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  71.45  | 0.01 | 68.72  | 5.82  |  23.28   |   5.82    |    23.28     |   0.07   | 13.99 | 91.76  |
| quad8_tex8_grey_linear_direct                           |  48.14  | 0.01 | 46.05  | 8.69  |  34.75   |   8.69    |    34.75     |   0.10   | 20.77 | 275.85 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  74.14  | 0.01 | 72.07  | 5.55  |  22.20   |   5.55    |    22.20     |   0.10   | 13.49 | 176.73 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  67.83  | 0.01 | 65.32  | 6.12  |  24.49   |   6.12    |    24.49     |   0.09   | 14.74 | 194.33 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  67.45  | 0.01 | 65.10  | 6.14  |  24.58   |   6.14    |    24.58     |   0.10   | 14.83 | 195.56 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  79.78  | 0.01 | 77.54  | 5.16  |  20.64   |   5.16    |    20.64     |   0.10   | 12.53 | 164.05 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  67.99  | 0.01 | 65.86  | 6.07  |  24.30   |   6.07    |    24.30     |   0.10   | 14.71 | 193.33 |
| quad8_tex8_grey_quintic_bspline_direct                  | 107.14  | 0.01 | 104.95 | 3.81  |  15.25   |   3.81    |    15.25     |   0.10   | 9.33 | 121.34 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  79.62  | 0.02 | 76.91  | 5.20  |  20.80   |   5.20    |    20.80     |   0.07   | 12.56 | 164.59 |
| quad9_tex8_grey_linear_direct                           |  49.13  | 0.01 | 46.46  | 8.61  |  34.44   |   8.61    |    34.44     |   0.07   | 20.36 | 304.24 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  76.69  | 0.01 | 72.43  | 5.52  |  22.09   |   5.52    |    22.09     |   0.07   | 13.04 | 194.49 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  68.12  | 0.01 | 65.51  | 6.11  |  24.42   |   6.11    |    24.42     |   0.07   | 14.68 | 216.94 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  68.26  | 0.01 | 65.41  | 6.11  |  24.46   |   6.11    |    24.46     |   0.07   | 14.65 | 216.85 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  79.75  | 0.01 | 77.06  | 5.19  |  20.76   |   5.19    |    20.76     |   0.07   | 12.54 | 184.73 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  69.58  | 0.01 | 67.00  | 5.97  |  23.88   |   5.97    |    23.88     |   0.07   | 14.37 | 212.18 |
| quad9_tex8_grey_quintic_bspline_direct                  | 107.15  | 0.01 | 104.49 | 3.83  |  15.31   |   3.83    |    15.31     |   0.07   | 9.33 | 136.88 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  81.37  | 0.01 | 78.66  | 5.09  |  20.34   |   5.09    |    20.34     |   0.07   | 12.29 | 180.85 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  37.45  | 0.01 | 33.10  | 12.08 |  48.34   |   12.08   |    48.34     |   0.19   | 26.71 | 134.42 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  70.39  | 0.01 | 66.22  | 6.04  |  24.16   |   6.04    |    24.16     |   0.19   | 14.21 | 70.36  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  65.18  | 0.01 | 60.31  | 6.63  |  26.53   |   6.63    |    26.53     |   0.19   | 15.34 | 76.70  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  63.67  | 0.01 | 59.93  | 6.67  |  26.70   |   6.67    |    26.70     |   0.19   | 15.71 | 77.68  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  80.58  | 0.01 | 76.82  | 5.21  |  20.83   |   5.21    |    20.83     |   0.19   | 12.41 | 60.88  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  63.07  | 0.01 | 59.65  | 6.71  |  26.82   |   6.71    |    26.82     |   0.19   | 15.86 | 78.32  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 108.99  | 0.01 | 105.47 | 3.79  |  15.17   |   3.79    |    15.17     |   0.19   | 9.18 | 44.72  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  81.65  | 0.01 | 78.24  | 5.11  |  20.45   |   5.11    |    20.45     |   0.18   | 12.25 | 60.15  |
| tri6_tex8_rgb_linear_direct                             |  67.43  | 0.01 | 64.49  | 6.20  |  24.81   |   6.20    |    24.81     |   0.17   | 14.83 | 146.11 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  93.84  | 0.01 | 90.30  | 4.43  |  17.72   |   4.43    |    17.72     |   0.17   | 10.66 | 104.22 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  88.18  | 0.01 | 84.10  | 4.76  |  19.03   |   4.76    |    19.03     |   0.17   | 11.34 | 111.04 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  87.35  | 0.01 | 83.70  | 4.78  |  19.12   |   4.78    |    19.12     |   0.17   | 11.45 | 112.23 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 103.73  | 0.01 | 100.16 | 3.99  |  15.97   |   3.99    |    15.97     |   0.16   | 9.64 | 94.14  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  87.20  | 0.01 | 83.89  | 4.77  |  19.07   |   4.77    |    19.07     |   0.16   | 11.47 | 112.25 |
| tri6_tex8_rgb_quintic_bspline_direct                    | 132.87  | 0.01 | 129.92 | 3.08  |  12.32   |   3.08    |    12.32     |   0.16   | 7.53 | 73.28  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 102.83  | 0.01 | 100.07 | 4.00  |  15.99   |   4.00    |    15.99     |   0.16   | 9.72 | 94.88  |
| quad4ibi_tex8_rgb_linear_direct                         |  43.41  | 0.01 | 40.68  | 9.83  |  39.33   |   9.83    |    39.33     |   0.11   | 23.04 | 153.31 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  78.80  | 0.01 | 75.94  | 5.27  |  21.07   |   5.27    |    21.07     |   0.10   | 12.69 | 83.12  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  81.84  | 0.01 | 79.16  | 5.05  |  20.21   |   5.05    |    20.21     |   0.10   | 12.22 | 79.81  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  82.67  | 0.01 | 79.34  | 5.04  |  20.17   |   5.04    |    20.17     |   0.11   | 12.10 | 79.34  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     | 106.27  | 0.01 | 103.17 | 3.88  |  15.51   |   3.88    |    15.51     |   0.10   | 9.41 | 61.25  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  82.30  | 0.01 | 78.80  | 5.08  |  20.31   |   5.08    |    20.31     |   0.10   | 12.15 | 80.17  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 134.28  | 0.01 | 131.53 | 3.04  |  12.16   |   3.04    |    12.16     |   0.10   | 7.45 | 48.26  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              | 107.91  | 0.01 | 105.05 | 3.81  |  15.23   |   3.81    |    15.23     |   0.10   | 9.27 | 60.30  |
| quad4newton_tex8_rgb_linear_direct                      |  59.20  | 0.01 | 55.03  | 7.27  |  29.07   |   7.27    |    29.07     |   0.11   | 16.89 | 112.67 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  86.05  | 0.01 | 82.30  | 4.86  |  19.44   |   4.86    |    19.44     |   0.11   | 11.62 | 75.90  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  78.65  | 0.01 | 74.86  | 5.34  |  21.37   |   5.34    |    21.37     |   0.10   | 12.71 | 83.32  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  78.95  | 0.01 | 74.69  | 5.36  |  21.42   |   5.36    |    21.42     |   0.10   | 12.67 | 82.90  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  97.22  | 0.01 | 93.01  | 4.30  |  17.20   |   4.30    |    17.20     |   0.11   | 10.29 | 67.02  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  78.45  | 0.01 | 74.83  | 5.35  |  21.38   |   5.35    |    21.38     |   0.11   | 12.75 | 83.48  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 123.68  | 0.01 | 120.93 | 3.31  |  13.23   |   3.31    |    13.23     |   0.10   | 8.09 | 52.47  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  95.85  | 0.01 | 92.80  | 4.31  |  17.24   |   4.31    |    17.24     |   0.10   | 10.43 | 67.96  |
| quad8_tex8_rgb_linear_direct                            |  65.56  | 0.01 | 62.08  | 6.44  |  25.77   |   6.44    |    25.77     |   0.09   | 15.25 | 200.75 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  93.46  | 0.01 | 89.82  | 4.45  |  17.81   |   4.45    |    17.81     |   0.10   | 10.70 | 139.75 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  87.34  | 0.01 | 82.19  | 4.87  |  19.47   |   4.87    |    19.47     |   0.10   | 11.45 | 151.77 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  86.11  | 0.01 | 82.34  | 4.86  |  19.43   |   4.86    |    19.43     |   0.11   | 11.61 | 152.10 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 104.11  | 0.01 | 100.17 | 3.99  |  15.97   |   3.99    |    15.97     |   0.10   | 9.61 | 125.21 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  85.63  | 0.01 | 82.06  | 4.87  |  19.50   |   4.87    |    19.50     |   0.11   | 11.68 | 153.10 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 131.23  | 0.01 | 128.53 | 3.11  |  12.45   |   3.11    |    12.45     |   0.10   | 7.62 | 98.79  |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 102.78  | 0.01 | 99.16  | 4.03  |  16.14   |   4.03    |    16.14     |   0.10   | 9.73 | 127.03 |
| quad9_tex8_rgb_linear_direct                            |  66.90  | 0.01 | 63.20  | 6.33  |  25.32   |   6.33    |    25.32     |   0.10   | 14.95 | 221.12 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  94.68  | 0.01 | 91.11  | 4.39  |  17.56   |   4.39    |    17.56     |   0.11   | 10.56 | 154.94 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  87.91  | 0.01 | 84.35  | 4.74  |  18.97   |   4.74    |    18.97     |   0.10   | 11.38 | 167.09 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  87.67  | 0.01 | 83.72  | 4.78  |  19.11   |   4.78    |    19.11     |   0.11   | 11.41 | 167.54 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 103.24  | 0.01 | 99.75  | 4.01  |  16.04   |   4.01    |    16.04     |   0.10   | 9.69 | 141.93 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  88.00  | 0.01 | 83.76  | 4.78  |  19.10   |   4.78    |    19.10     |   0.10   | 11.36 | 166.91 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 132.77  | 0.01 | 129.25 | 3.09  |  12.38   |   3.09    |    12.38     |   0.11   | 7.53 | 109.87 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 104.18  | 0.01 | 100.44 | 3.98  |  15.93   |   3.98    |    15.93     |   0.10   | 9.60 | 140.57 |

