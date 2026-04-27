# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  10.34  | 0.18 |  6.32  | 63.34 |  253.35  |   63.34   |    253.35    |   0.01   | 96.80 | 577.04 |
| tri6_nodal_grey                                         |  23.17  | 0.21 | 20.54  | 19.48 |  77.90   |   19.48   |    77.90     |   0.01   | 43.16 | 448.67 |
| quad4ibi_nodal_grey                                     |  16.25  | 0.24 | 13.52  | 29.58 |  118.33  |   29.58   |    118.33    |   0.00   | 61.54 | 441.26 |
| quad4newton_nodal_grey                                  |  19.31  | 0.21 | 15.73  | 25.44 |  101.75  |   25.44   |    101.75    |   0.00   | 51.78 | 377.25 |
| quad8_nodal_grey                                        |  23.20  | 0.20 | 19.70  | 20.31 |  81.23   |   20.31   |    81.23     |   0.01   | 43.11 | 609.32 |
| quad9_nodal_grey                                        |  23.01  | 0.15 | 20.40  | 19.60 |  78.41   |   19.60   |    78.41     |   0.01   | 43.45 | 680.07 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  15.21  | 0.23 |  9.14  | 43.80 |  175.20  |   43.80   |    175.20    |   0.01   | 65.75 | 360.25 |
| tri6_nodal_rgb                                          |  26.39  | 0.17 | 22.26  | 17.97 |  71.90   |   17.97   |    71.90     |   0.01   | 37.90 | 390.01 |
| quad4ibi_nodal_rgb                                      |  22.82  | 0.19 | 18.27  | 21.89 |  87.58   |   21.89   |    87.58     |   0.01   | 43.83 | 303.98 |
| quad4newton_nodal_rgb                                   |  22.87  | 0.19 | 18.93  | 21.13 |  84.54   |   21.13   |    84.54     |   0.01   | 43.73 | 302.84 |
| quad8_nodal_rgb                                         |  26.05  | 0.21 | 22.62  | 17.68 |  70.72   |   17.68   |    70.72     |   0.00   | 38.40 | 525.79 |
| quad9_nodal_rgb                                         |  26.31  | 0.13 | 22.68  | 17.64 |  70.55   |   17.64   |    70.55     |   0.01   | 38.01 | 587.29 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  16.48  | 0.22 | 13.49  | 29.65 |  118.62  |   29.65   |    118.62    |   0.01   | 60.70 | 329.30 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  30.33  | 0.20 | 27.50  | 14.55 |  58.19   |   14.55   |    58.19     |   0.01   | 32.97 | 167.78 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  26.32  | 0.19 | 23.60  | 16.95 |  67.81   |   16.95   |    67.81     |   0.01   | 37.99 | 194.98 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  26.23  | 0.17 | 23.64  | 16.92 |  67.68   |   16.92   |    67.68     |   0.01   | 38.12 | 198.14 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  32.20  | 0.16 | 29.53  | 13.54 |  54.18   |   13.54   |    54.18     |   0.01   | 31.06 | 158.13 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  26.49  | 0.20 | 23.32  | 17.16 |  68.62   |   17.16   |    68.62     |   0.01   | 37.76 | 197.00 |
| tri3_tex8_grey_quintic_bspline_direct                   |  46.79  | 0.20 | 43.89  | 9.11  |  36.46   |   9.11    |    36.46     |   0.01   | 21.37 | 106.73 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  32.58  | 0.14 | 29.35  | 13.63 |  54.53   |   13.63   |    54.53     |   0.01   | 30.69 | 156.15 |
| tri6_tex8_grey_linear_direct                            |  29.07  | 0.21 | 25.48  | 15.71 |  62.85   |   15.71   |    62.85     |   0.01   | 34.41 | 350.75 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  42.04  | 0.19 | 39.28  | 10.18 |  40.73   |   10.18   |    40.73     |   0.01   | 23.79 | 238.04 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  37.74  | 0.20 | 34.77  | 11.50 |  46.01   |   11.50   |    46.01     |   0.01   | 26.50 | 266.62 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  38.11  | 0.19 | 35.28  | 11.34 |  45.36   |   11.34   |    45.36     |   0.01   | 26.24 | 264.46 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  43.34  | 0.20 | 40.55  | 9.87  |  39.46   |   9.87    |    39.46     |   0.01   | 23.07 | 231.11 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  38.13  | 0.22 | 34.94  | 11.45 |  45.79   |   11.45   |    45.79     |   0.01   | 26.23 | 264.00 |
| tri6_tex8_grey_quintic_bspline_direct                   |  58.51  | 0.21 | 55.15  | 7.25  |  29.01   |   7.25    |    29.01     |   0.01   | 17.09 | 171.63 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  44.27  | 0.24 | 41.43  | 9.65  |  38.62   |   9.65    |    38.62     |   0.01   | 22.59 | 226.40 |
| quad4ibi_tex8_grey_linear_direct                        |  21.08  | 0.19 | 17.74  | 22.55 |  90.20   |   22.55   |    90.20     |   0.01   | 47.45 | 337.72 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  36.38  | 0.24 | 33.36  | 11.99 |  47.97   |   11.99   |    47.97     |   0.00   | 27.49 | 184.66 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  37.06  | 0.22 | 34.09  | 11.73 |  46.93   |   11.73   |    46.93     |   0.00   | 26.99 | 182.05 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  36.53  | 0.21 | 33.63  | 11.90 |  47.58   |   11.90   |    47.58     |   0.00   | 27.37 | 184.29 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  44.67  | 0.24 | 41.88  | 9.55  |  38.20   |   9.55    |    38.20     |   0.00   | 22.39 | 149.55 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  37.44  | 0.28 | 34.27  | 11.67 |  46.69   |   11.67   |    46.69     |   0.00   | 26.71 | 179.19 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  54.54  | 0.22 | 51.76  | 7.73  |  30.91   |   7.73    |    30.91     |   0.00   | 18.34 | 121.39 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  45.25  | 0.26 | 42.56  | 9.40  |  37.60   |   9.40    |    37.60     |   0.00   | 22.10 | 146.91 |
| quad4newton_tex8_grey_linear_direct                     |  24.44  | 0.24 | 21.36  | 18.73 |  74.91   |   18.73   |    74.91     |   0.00   | 40.92 | 286.65 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  37.05  | 0.21 | 34.34  | 11.65 |  46.59   |   11.65   |    46.59     |   0.00   | 26.99 | 181.40 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  33.16  | 0.23 | 30.23  | 13.23 |  52.93   |   13.23   |    52.93     |   0.00   | 30.15 | 204.17 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  33.98  | 0.23 | 31.06  | 12.88 |  51.52   |   12.88   |    51.52     |   0.00   | 29.43 | 198.49 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  39.87  | 0.24 | 37.20  | 10.75 |  43.01   |   10.75   |    43.01     |   0.00   | 25.08 | 168.39 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  34.81  | 0.23 | 32.27  | 12.39 |  49.58   |   12.39   |    49.58     |   0.00   | 28.73 | 193.41 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  54.11  | 0.24 | 50.32  | 7.95  |  31.79   |   7.95    |    31.79     |   0.00   | 18.48 | 123.15 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  40.05  | 0.27 | 37.32  | 10.72 |  42.87   |   10.72   |    42.87     |   0.00   | 24.97 | 166.98 |
| quad8_tex8_grey_linear_direct                           |  27.94  | 0.25 | 25.57  | 15.65 |  62.60   |   15.65   |    62.60     |   0.00   | 35.80 | 487.76 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  41.34  | 0.21 | 38.57  | 10.37 |  41.48   |   10.37   |    41.48     |   0.00   | 24.19 | 323.85 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  38.48  | 0.24 | 35.48  | 11.27 |  45.10   |   11.27   |    45.10     |   0.00   | 25.99 | 349.37 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  38.17  | 0.26 | 35.47  | 11.28 |  45.11   |   11.28   |    45.11     |   0.00   | 26.20 | 352.69 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  44.16  | 0.31 | 41.26  | 9.70  |  38.78   |   9.70    |    38.78     |   0.00   | 22.64 | 301.47 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  37.91  | 0.25 | 34.95  | 11.45 |  45.78   |   11.45   |    45.78     |   0.00   | 26.38 | 353.92 |
| quad8_tex8_grey_quintic_bspline_direct                  |  59.84  | 0.22 | 56.58  | 7.07  |  28.28   |   7.07    |    28.28     |   0.00   | 16.71 | 221.13 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  44.58  | 0.20 | 41.74  | 9.58  |  38.34   |   9.58    |    38.34     |   0.00   | 22.43 | 298.75 |
| quad9_tex8_grey_linear_direct                           |  28.33  | 0.14 | 25.73  | 15.54 |  62.17   |   15.54   |    62.17     |   0.01   | 35.30 | 541.85 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  42.02  | 0.13 | 39.26  | 10.19 |  40.76   |   10.19   |    40.76     |   0.01   | 23.80 | 359.19 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  39.04  | 0.16 | 36.22  | 11.04 |  44.18   |   11.04   |    44.18     |   0.01   | 25.62 | 386.38 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  38.42  | 0.12 | 35.96  | 11.12 |  44.50   |   11.12   |    44.50     |   0.01   | 26.03 | 393.25 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  45.21  | 0.15 | 42.58  | 9.40  |  37.58   |   9.40    |    37.58     |   0.01   | 22.12 | 331.97 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  38.42  | 0.16 | 35.52  | 11.26 |  45.05   |   11.26   |    45.05     |   0.01   | 26.03 | 395.54 |
| quad9_tex8_grey_quintic_bspline_direct                  |  59.71  | 0.14 | 56.82  | 7.04  |  28.16   |   7.04    |    28.16     |   0.01   | 16.75 | 248.51 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  44.82  | 0.15 | 42.08  | 9.51  |  38.02   |   9.51    |    38.02     |   0.01   | 22.31 | 335.41 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  22.82  | 0.16 | 17.94  | 22.30 |  89.19   |   22.30   |    89.19     |   0.01   | 43.83 | 227.42 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  40.85  | 0.18 | 35.33  | 11.32 |  45.29   |   11.32   |    45.29     |   0.01   | 24.48 | 122.78 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  36.97  | 0.16 | 33.10  | 12.09 |  48.34   |   12.09   |    48.34     |   0.01   | 27.05 | 136.25 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  37.07  | 0.17 | 33.14  | 12.07 |  48.28   |   12.07   |    48.28     |   0.01   | 26.97 | 135.71 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  45.07  | 0.16 | 41.37  | 9.67  |  38.68   |   9.67    |    38.68     |   0.01   | 22.19 | 110.74 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  35.41  | 0.17 | 31.96  | 12.52 |  50.06   |   12.52   |    50.06     |   0.01   | 28.24 | 143.44 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  59.10  | 0.15 | 55.51  | 7.21  |  28.83   |   7.21    |    28.83     |   0.01   | 16.92 | 83.65  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  45.50  | 0.16 | 41.37  | 9.67  |  38.68   |   9.67    |    38.68     |   0.01   | 21.98 | 110.37 |
| tri6_tex8_rgb_linear_direct                             |  37.10  | 0.17 | 34.00  | 11.77 |  47.06   |   11.77   |    47.06     |   0.01   | 26.95 | 271.41 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  52.49  | 0.17 | 48.85  | 8.19  |  32.75   |   8.19    |    32.75     |   0.01   | 19.05 | 189.06 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  48.48  | 0.18 | 45.01  | 8.89  |  35.55   |   8.89    |    35.55     |   0.01   | 20.63 | 205.78 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  48.25  | 0.14 | 44.54  | 8.98  |  35.92   |   8.98    |    35.92     |   0.01   | 20.72 | 206.40 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  56.53  | 0.19 | 53.11  | 7.53  |  30.13   |   7.53    |    30.13     |   0.01   | 17.69 | 175.11 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  49.02  | 0.16 | 45.46  | 8.80  |  35.20   |   8.80    |    35.20     |   0.01   | 20.40 | 203.08 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  73.67  | 0.21 | 69.27  | 5.77  |  23.10   |   5.77    |    23.10     |   0.01   | 13.57 | 133.47 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  57.39  | 0.18 | 52.88  | 7.56  |  30.26   |   7.56    |    30.26     |   0.01   | 17.43 | 173.88 |
| quad4ibi_tex8_rgb_linear_direct                         |  26.80  | 0.18 | 22.86  | 17.50 |  69.99   |   17.50   |    69.99     |   0.01   | 37.31 | 256.58 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  44.02  | 0.21 | 40.13  | 9.97  |  39.87   |   9.97    |    39.87     |   0.00   | 22.72 | 151.39 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  47.89  | 0.20 | 43.75  | 9.14  |  36.58   |   9.14    |    36.58     |   0.01   | 20.88 | 139.06 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  46.43  | 0.22 | 42.92  | 9.32  |  37.28   |   9.32    |    37.28     |   0.00   | 21.54 | 143.53 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  59.34  | 0.19 | 55.40  | 7.22  |  28.88   |   7.22    |    28.88     |   0.01   | 16.85 | 111.09 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  46.54  | 0.22 | 42.57  | 9.40  |  37.59   |   9.40    |    37.59     |   0.00   | 21.49 | 143.37 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  73.20  | 0.17 | 69.55  | 5.75  |  23.00   |   5.75    |    23.00     |   0.01   | 13.66 | 89.54  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  59.63  | 0.21 | 55.50  | 7.21  |  28.83   |   7.21    |    28.83     |   0.00   | 16.77 | 110.55 |
| quad4newton_tex8_rgb_linear_direct                      |  33.57  | 0.20 | 29.62  | 13.50 |  54.02   |   13.50   |    54.02     |   0.00   | 29.79 | 201.93 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  48.18  | 0.22 | 44.34  | 9.02  |  36.08   |   9.02    |    36.08     |   0.00   | 20.76 | 139.11 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  44.04  | 0.21 | 40.50  | 9.88  |  39.51   |   9.88    |    39.51     |   0.00   | 22.71 | 151.66 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  44.59  | 0.18 | 40.34  | 9.92  |  39.68   |   9.92    |    39.68     |   0.01   | 22.43 | 149.31 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  53.19  | 0.19 | 49.68  | 8.05  |  32.20   |   8.05    |    32.20     |   0.01   | 18.80 | 124.31 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  43.23  | 0.19 | 39.70  | 10.07 |  40.30   |   10.07   |    40.30     |   0.01   | 23.13 | 156.34 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  68.68  | 0.17 | 64.06  | 6.24  |  24.98   |   6.24    |    24.98     |   0.01   | 14.56 | 95.77  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  52.72  | 0.17 | 48.72  | 8.21  |  32.84   |   8.21    |    32.84     |   0.01   | 18.97 | 126.61 |
| quad8_tex8_rgb_linear_direct                            |  38.13  | 0.14 | 34.41  | 11.62 |  46.49   |   11.62   |    46.49     |   0.01   | 26.23 | 351.92 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  52.67  | 0.16 | 49.23  | 8.13  |  32.50   |   8.13    |    32.50     |   0.01   | 18.99 | 251.30 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  50.27  | 0.15 | 45.79  | 8.74  |  34.94   |   8.74    |    34.94     |   0.01   | 19.89 | 264.72 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  48.22  | 0.14 | 44.69  | 8.95  |  35.81   |   8.95    |    35.81     |   0.01   | 20.74 | 276.63 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  57.62  | 0.13 | 53.53  | 7.47  |  29.89   |   7.47    |    29.89     |   0.01   | 17.36 | 229.14 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  49.48  | 0.16 | 45.90  | 8.72  |  34.86   |   8.72    |    34.86     |   0.01   | 20.21 | 267.98 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  73.31  | 0.19 | 69.69  | 5.74  |  22.96   |   5.74    |    22.96     |   0.01   | 13.64 | 178.94 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  58.45  | 0.13 | 54.31  | 7.36  |  29.46   |   7.36    |    29.46     |   0.01   | 17.11 | 226.72 |
| quad9_tex8_rgb_linear_direct                            |  37.60  | 0.13 | 34.37  | 11.64 |  46.56   |   11.64   |    46.56     |   0.01   | 26.60 | 402.30 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  53.90  | 0.13 | 50.06  | 7.99  |  31.96   |   7.99    |    31.96     |   0.01   | 18.55 | 276.60 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  49.97  | 0.16 | 45.83  | 8.73  |  34.91   |   8.73    |    34.91     |   0.01   | 20.01 | 301.30 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  49.76  | 0.22 | 45.41  | 8.81  |  35.24   |   8.81    |    35.24     |   0.00   | 20.10 | 299.90 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  59.04  | 0.24 | 54.09  | 7.40  |  29.58   |   7.40    |    29.58     |   0.00   | 16.94 | 251.81 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  48.55  | 0.22 | 45.13  | 8.86  |  35.46   |   8.86    |    35.46     |   0.00   | 20.60 | 308.77 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  73.57  | 0.21 | 69.21  | 5.78  |  23.12   |   5.78    |    23.12     |   0.00   | 13.59 | 200.57 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  58.08  | 0.24 | 54.47  | 7.34  |  29.38   |   7.34    |    29.38     |   0.00   | 17.22 | 255.48 |

