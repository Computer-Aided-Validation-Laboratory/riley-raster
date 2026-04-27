# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  10.56  | 0.23 |  6.60  | 60.58 |  242.33  |   60.58   |    242.33    |   0.01   | 94.68 | 553.24 |
| tri6_nodal_grey                                         |  23.20  | 0.20 | 20.23  | 19.77 |  79.08   |   19.77   |    79.08     |   0.01   | 43.10 | 449.36 |
| quad4ibi_nodal_grey                                     |  16.17  | 0.21 | 13.48  | 29.67 |  118.67  |   29.67   |    118.67    |   0.00   | 61.84 | 443.41 |
| quad4newton_nodal_grey                                  |  18.82  | 0.24 | 15.97  | 25.04 |  100.16  |   25.04   |    100.16    |   0.00   | 53.14 | 376.56 |
| quad8_nodal_grey                                        |  22.55  | 0.22 | 19.69  | 20.32 |  81.29   |   20.32   |    81.29     |   0.00   | 44.34 | 614.39 |
| quad9_nodal_grey                                        |  23.91  | 0.24 | 20.85  | 19.18 |  76.73   |   19.18   |    76.73     |   0.00   | 41.82 | 649.61 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  15.34  | 0.18 |  8.81  | 45.41 |  181.64  |   45.41   |    181.64    |   0.01   | 65.26 | 355.48 |
| tri6_nodal_rgb                                          |  26.85  | 0.16 | 23.00  | 17.39 |  69.57   |   17.39   |    69.57     |   0.01   | 37.25 | 389.48 |
| quad4ibi_nodal_rgb                                      |  21.22  | 0.22 | 17.71  | 22.59 |  90.35   |   22.59   |    90.35     |   0.00   | 47.12 | 331.82 |
| quad4newton_nodal_rgb                                   |  22.13  | 0.23 | 18.21  | 21.97 |  87.88   |   21.97   |    87.88     |   0.00   | 45.18 | 314.22 |
| quad8_nodal_rgb                                         |  26.34  | 0.22 | 22.86  | 17.50 |  70.00   |   17.50   |    70.00     |   0.00   | 37.98 | 520.84 |
| quad9_nodal_rgb                                         |  26.90  | 0.22 | 22.74  | 17.59 |  70.35   |   17.59   |    70.35     |   0.00   | 37.18 | 572.57 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  16.81  | 0.23 | 13.89  | 28.81 |  115.22  |   28.81   |    115.22    |   0.01   | 59.50 | 318.75 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  30.59  | 0.20 | 27.71  | 14.43 |  57.74   |   14.43   |    57.74     |   0.01   | 32.69 | 167.33 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  26.51  | 0.16 | 23.94  | 16.71 |  66.86   |   16.71   |    66.86     |   0.01   | 37.74 | 193.95 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  26.77  | 0.19 | 23.84  | 16.78 |  67.11   |   16.78   |    67.11     |   0.01   | 37.35 | 192.64 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  32.27  | 0.17 | 28.95  | 13.82 |  55.27   |   13.82   |    55.27     |   0.01   | 30.99 | 158.70 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  25.75  | 0.18 | 23.12  | 17.30 |  69.20   |   17.30   |    69.20     |   0.01   | 38.83 | 200.34 |
| tri3_tex8_grey_quintic_bspline_direct                   |  47.09  | 0.18 | 44.40  | 9.01  |  36.04   |   9.01    |    36.04     |   0.01   | 21.24 | 105.73 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  32.04  | 0.20 | 28.82  | 13.88 |  55.51   |   13.88   |    55.51     |   0.01   | 31.22 | 158.44 |
| tri6_tex8_grey_linear_direct                            |  27.88  | 0.22 | 25.13  | 15.92 |  63.68   |   15.92   |    63.68     |   0.01   | 35.87 | 368.53 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  41.70  | 0.21 | 38.60  | 10.36 |  41.45   |   10.36   |    41.45     |   0.01   | 23.98 | 242.21 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  37.89  | 0.17 | 35.18  | 11.37 |  45.48   |   11.37   |    45.48     |   0.01   | 26.39 | 266.05 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  37.99  | 0.21 | 35.41  | 11.30 |  45.18   |   11.30   |    45.18     |   0.01   | 26.32 | 264.72 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  43.36  | 0.17 | 40.74  | 9.82  |  39.27   |   9.82    |    39.27     |   0.01   | 23.06 | 230.60 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  38.33  | 0.20 | 35.48  | 11.27 |  45.09   |   11.27   |    45.09     |   0.01   | 26.09 | 263.94 |
| tri6_tex8_grey_quintic_bspline_direct                   |  56.92  | 0.20 | 54.17  | 7.38  |  29.54   |   7.38    |    29.54     |   0.01   | 17.57 | 173.89 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  44.52  | 0.19 | 41.14  | 9.72  |  38.89   |   9.72    |    38.89     |   0.01   | 22.46 | 227.88 |
| quad4ibi_tex8_grey_linear_direct                        |  21.42  | 0.27 | 18.09  | 22.11 |  88.44   |   22.11   |    88.44     |   0.00   | 46.69 | 325.93 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  37.03  | 0.23 | 33.94  | 11.78 |  47.14   |   11.78   |    47.14     |   0.00   | 27.00 | 181.16 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  36.92  | 0.23 | 33.81  | 11.83 |  47.33   |   11.83   |    47.33     |   0.00   | 27.08 | 182.69 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  36.37  | 0.22 | 33.55  | 11.92 |  47.69   |   11.92   |    47.69     |   0.00   | 27.49 | 184.80 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  45.35  | 0.29 | 42.62  | 9.39  |  37.54   |   9.39    |    37.54     |   0.00   | 22.05 | 146.60 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  37.41  | 0.21 | 34.35  | 11.64 |  46.58   |   11.64   |    46.58     |   0.00   | 26.73 | 179.90 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  53.81  | 0.25 | 51.05  | 7.84  |  31.34   |   7.84    |    31.34     |   0.00   | 18.58 | 123.10 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  46.37  | 0.19 | 43.36  | 9.23  |  36.90   |   9.23    |    36.90     |   0.01   | 21.57 | 144.55 |
| quad4newton_tex8_grey_linear_direct                     |  23.04  | 0.20 | 20.18  | 19.82 |  79.27   |   19.82   |    79.27     |   0.01   | 43.41 | 301.48 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  37.18  | 0.20 | 34.57  | 11.57 |  46.28   |   11.57   |    46.28     |   0.01   | 26.90 | 180.52 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  34.00  | 0.23 | 31.23  | 12.81 |  51.24   |   12.81   |    51.24     |   0.00   | 29.41 | 198.30 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  33.39  | 0.17 | 30.51  | 13.11 |  52.45   |   13.11   |    52.45     |   0.01   | 29.95 | 202.83 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  39.91  | 0.25 | 37.22  | 10.75 |  42.99   |   10.75   |    42.99     |   0.00   | 25.06 | 167.62 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  33.51  | 0.25 | 30.82  | 12.98 |  51.92   |   12.98   |    51.92     |   0.00   | 29.84 | 201.77 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  54.08  | 0.22 | 51.42  | 7.78  |  31.11   |   7.78    |    31.11     |   0.00   | 18.49 | 122.61 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  39.95  | 0.25 | 37.29  | 10.73 |  42.91   |   10.73   |    42.91     |   0.00   | 25.03 | 167.26 |
| quad8_tex8_grey_linear_direct                           |  27.50  | 0.19 | 24.82  | 16.12 |  64.47   |   16.12   |    64.47     |   0.01   | 36.36 | 499.07 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  41.28  | 0.22 | 38.72  | 10.33 |  41.32   |   10.33   |    41.32     |   0.00   | 24.23 | 324.94 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  38.28  | 0.24 | 35.09  | 11.40 |  45.60   |   11.40   |    45.60     |   0.00   | 26.13 | 350.14 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  37.33  | 0.20 | 34.80  | 11.49 |  45.97   |   11.49   |    45.97     |   0.01   | 26.79 | 359.67 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  44.38  | 0.26 | 41.37  | 9.67  |  38.68   |   9.67    |    38.68     |   0.00   | 22.54 | 300.17 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  38.62  | 0.25 | 35.71  | 11.20 |  44.81   |   11.20   |    44.81     |   0.00   | 25.90 | 346.93 |
| quad8_tex8_grey_quintic_bspline_direct                  |  57.87  | 0.22 | 54.96  | 7.28  |  29.11   |   7.28    |    29.11     |   0.00   | 17.28 | 228.68 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  44.85  | 0.23 | 41.45  | 9.65  |  38.60   |   9.65    |    38.60     |   0.00   | 22.29 | 297.64 |
| quad9_tex8_grey_linear_direct                           |  28.13  | 0.26 | 25.38  | 15.76 |  63.05   |   15.76   |    63.05     |   0.00   | 35.55 | 547.43 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  41.13  | 0.24 | 38.40  | 10.42 |  41.67   |   10.42   |    41.67     |   0.00   | 24.31 | 365.31 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  37.69  | 0.25 | 34.60  | 11.56 |  46.24   |   11.56   |    46.24     |   0.00   | 26.53 | 402.82 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  39.05  | 0.30 | 35.44  | 11.29 |  45.15   |   11.29   |    45.15     |   0.00   | 25.61 | 385.79 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  44.05  | 0.29 | 41.10  | 9.73  |  38.93   |   9.73    |    38.93     |   0.00   | 22.70 | 340.83 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  38.63  | 0.20 | 35.50  | 11.27 |  45.08   |   11.27   |    45.08     |   0.00   | 25.89 | 391.36 |
| quad9_tex8_grey_quintic_bspline_direct                  |  58.92  | 0.27 | 55.99  | 7.14  |  28.58   |   7.14    |    28.58     |   0.00   | 16.97 | 251.81 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  45.68  | 0.31 | 42.25  | 9.47  |  37.87   |   9.47    |    37.87     |   0.00   | 21.89 | 327.75 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  21.57  | 0.16 | 17.78  | 22.50 |  90.01   |   22.50   |    90.01     |   0.01   | 46.37 | 242.56 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  39.53  | 0.17 | 35.52  | 11.26 |  45.04   |   11.26   |    45.04     |   0.01   | 25.30 | 127.89 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  35.83  | 0.17 | 32.41  | 12.34 |  49.36   |   12.34   |    49.36     |   0.01   | 27.91 | 140.81 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  36.52  | 0.18 | 32.91  | 12.15 |  48.62   |   12.15   |    48.62     |   0.01   | 27.38 | 137.88 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  45.18  | 0.17 | 41.69  | 9.60  |  38.38   |   9.60    |    38.38     |   0.01   | 22.13 | 110.77 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  36.27  | 0.18 | 32.90  | 12.16 |  48.64   |   12.16   |    48.64     |   0.01   | 27.57 | 138.97 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  59.88  | 0.19 | 56.31  | 7.10  |  28.41   |   7.10    |    28.41     |   0.01   | 16.70 | 82.74  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  45.72  | 0.17 | 41.72  | 9.59  |  38.36   |   9.59    |    38.36     |   0.01   | 21.87 | 110.30 |
| tri6_tex8_rgb_linear_direct                             |  37.58  | 0.17 | 33.84  | 11.82 |  47.28   |   11.82   |    47.28     |   0.01   | 26.61 | 269.09 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  52.81  | 0.17 | 48.65  | 8.22  |  32.89   |   8.22    |    32.89     |   0.01   | 18.94 | 188.31 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  49.25  | 0.17 | 45.54  | 8.78  |  35.14   |   8.78    |    35.14     |   0.01   | 20.30 | 201.92 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  48.30  | 0.17 | 44.03  | 9.08  |  36.34   |   9.08    |    36.34     |   0.01   | 20.70 | 206.82 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  57.56  | 0.17 | 53.60  | 7.46  |  29.85   |   7.46    |    29.85     |   0.01   | 17.38 | 172.03 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  47.71  | 0.18 | 44.18  | 9.05  |  36.21   |   9.05    |    36.21     |   0.01   | 20.96 | 209.12 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  72.11  | 0.17 | 68.49  | 5.84  |  23.36   |   5.84    |    23.36     |   0.01   | 13.87 | 136.59 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  56.82  | 0.19 | 53.16  | 7.52  |  30.10   |   7.52    |    30.10     |   0.01   | 17.60 | 174.30 |
| quad4ibi_tex8_rgb_linear_direct                         |  26.69  | 0.21 | 22.94  | 17.44 |  69.75   |   17.44   |    69.75     |   0.00   | 37.47 | 256.56 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  44.92  | 0.20 | 41.06  | 9.74  |  38.97   |   9.74    |    38.97     |   0.01   | 22.26 | 148.40 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  46.85  | 0.19 | 43.15  | 9.27  |  37.08   |   9.27    |    37.08     |   0.01   | 21.35 | 141.83 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  46.29  | 0.21 | 42.98  | 9.31  |  37.23   |   9.31    |    37.23     |   0.00   | 21.60 | 143.91 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  59.38  | 0.25 | 54.95  | 7.28  |  29.12   |   7.28    |    29.12     |   0.00   | 16.85 | 111.22 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  45.93  | 0.25 | 42.14  | 9.49  |  37.97   |   9.49    |    37.97     |   0.00   | 21.77 | 144.83 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  72.96  | 0.20 | 69.66  | 5.74  |  22.97   |   5.74    |    22.97     |   0.00   | 13.71 | 89.83  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  59.52  | 0.21 | 55.89  | 7.16  |  28.63   |   7.16    |    28.63     |   0.00   | 16.80 | 110.87 |
| quad4newton_tex8_rgb_linear_direct                      |  33.46  | 0.21 | 29.40  | 13.61 |  54.43   |   13.61   |    54.43     |   0.00   | 29.88 | 201.71 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  48.80  | 0.17 | 44.62  | 8.97  |  35.86   |   8.97    |    35.86     |   0.01   | 20.49 | 135.94 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  44.41  | 0.22 | 39.86  | 10.03 |  40.14   |   10.03   |    40.14     |   0.00   | 22.52 | 150.39 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  44.53  | 0.20 | 40.57  | 9.86  |  39.44   |   9.86    |    39.44     |   0.01   | 22.46 | 150.89 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  53.56  | 0.23 | 49.35  | 8.11  |  32.42   |   8.11    |    32.42     |   0.00   | 18.67 | 123.46 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  44.45  | 0.17 | 40.55  | 9.86  |  39.46   |   9.86    |    39.46     |   0.01   | 22.50 | 149.86 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  67.50  | 0.24 | 64.20  | 6.23  |  24.92   |   6.23    |    24.92     |   0.00   | 14.82 | 97.34  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  52.78  | 0.19 | 49.25  | 8.12  |  32.49   |   8.12    |    32.49     |   0.01   | 18.95 | 125.37 |
| quad8_tex8_rgb_linear_direct                            |  38.17  | 0.19 | 34.27  | 11.67 |  46.70   |   11.67   |    46.70     |   0.01   | 26.20 | 351.31 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  51.91  | 0.20 | 47.91  | 8.35  |  33.39   |   8.35    |    33.39     |   0.01   | 19.26 | 255.00 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.31  | 0.23 | 44.30  | 9.03  |  36.12   |   9.03    |    36.12     |   0.00   | 20.70 | 274.52 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.81  | 0.24 | 44.13  | 9.06  |  36.25   |   9.06    |    36.25     |   0.00   | 20.92 | 277.77 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  57.24  | 0.22 | 53.11  | 7.53  |  30.13   |   7.53    |    30.13     |   0.00   | 17.47 | 230.64 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  48.83  | 0.27 | 44.51  | 8.99  |  35.95   |   8.99    |    35.95     |   0.00   | 20.48 | 271.81 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  72.67  | 0.26 | 68.53  | 5.84  |  23.35   |   5.84    |    23.35     |   0.00   | 13.76 | 180.39 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  57.12  | 0.26 | 52.91  | 7.56  |  30.24   |   7.56    |    30.24     |   0.00   | 17.51 | 232.41 |
| quad9_tex8_rgb_linear_direct                            |  38.57  | 0.22 | 35.27  | 11.34 |  45.36   |   11.34   |    45.36     |   0.00   | 25.93 | 391.74 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  52.62  | 0.20 | 48.56  | 8.24  |  32.95   |   8.24    |    32.95     |   0.00   | 19.00 | 282.88 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  47.69  | 0.23 | 43.90  | 9.11  |  36.45   |   9.11    |    36.45     |   0.00   | 20.97 | 314.62 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  49.66  | 0.24 | 45.27  | 8.84  |  35.35   |   8.84    |    35.35     |   0.00   | 20.14 | 300.61 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  57.41  | 0.24 | 53.90  | 7.42  |  29.69   |   7.42    |    29.69     |   0.00   | 17.42 | 258.56 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  48.57  | 0.21 | 44.79  | 8.93  |  35.72   |   8.93    |    35.72     |   0.00   | 20.59 | 308.32 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  72.75  | 0.23 | 68.40  | 5.85  |  23.39   |   5.85    |    23.39     |   0.00   | 13.75 | 203.88 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  56.88  | 0.20 | 52.91  | 7.56  |  30.24   |   7.56    |    30.24     |   0.00   | 17.58 | 260.98 |

