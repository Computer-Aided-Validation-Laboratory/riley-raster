# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  10.09  | 0.16 |  6.28  | 63.69 |  254.75  |   63.69   |    254.75    |   0.01   | 99.16 | 573.04 |
| tri6_nodal_grey                                         |  22.99  | 0.17 | 19.81  | 20.19 |  80.76   |   20.19   |    80.76     |   0.01   | 43.50 | 451.59 |
| quad4ibi_nodal_grey                                     |  15.68  | 0.29 | 13.05  | 30.66 |  122.63  |   30.66   |    122.63    |   0.00   | 63.79 | 460.11 |
| quad4newton_nodal_grey                                  |  19.55  | 0.23 | 16.40  | 24.39 |  97.58   |   24.39   |    97.58     |   0.00   | 51.15 | 362.23 |
| quad8_nodal_grey                                        |  23.14  | 0.27 | 20.36  | 19.65 |  78.62   |   19.65   |    78.62     |   0.00   | 43.22 | 599.82 |
| quad9_nodal_grey                                        |  23.81  | 0.26 | 20.92  | 19.13 |  76.51   |   19.13   |    76.51     |   0.00   | 42.00 | 651.61 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  14.60  | 0.15 |  8.86  | 45.14 |  180.57  |   45.14   |    180.57    |   0.01   | 68.57 | 372.26 |
| tri6_nodal_rgb                                          |  26.30  | 0.14 | 22.86  | 17.50 |  70.01   |   17.50   |    70.01     |   0.01   | 38.03 | 394.62 |
| quad4ibi_nodal_rgb                                      |  21.37  | 0.22 | 17.33  | 23.08 |  92.33   |   23.08   |    92.33     |   0.00   | 46.80 | 327.76 |
| quad4newton_nodal_rgb                                   |  22.57  | 0.26 | 18.37  | 21.77 |  87.10   |   21.77   |    87.10     |   0.00   | 44.31 | 308.54 |
| quad8_nodal_rgb                                         |  26.59  | 0.24 | 22.63  | 17.67 |  70.70   |   17.67   |    70.70     |   0.00   | 37.61 | 518.12 |
| quad9_nodal_rgb                                         |  26.12  | 0.20 | 22.49  | 17.78 |  71.13   |   17.78   |    71.13     |   0.01   | 38.28 | 593.64 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  16.48  | 0.18 | 13.79  | 29.01 |  116.02  |   29.01   |    116.02    |   0.01   | 60.69 | 328.58 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  30.47  | 0.21 | 27.43  | 14.58 |  58.33   |   14.58   |    58.33     |   0.01   | 32.82 | 168.91 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  26.01  | 0.15 | 23.49  | 17.03 |  68.11   |   17.03   |    68.11     |   0.01   | 38.45 | 197.70 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  26.39  | 0.16 | 23.59  | 16.96 |  67.83   |   16.96   |    67.83     |   0.01   | 37.90 | 195.53 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  31.52  | 0.19 | 28.65  | 13.96 |  55.85   |   13.96   |    55.85     |   0.01   | 31.73 | 161.01 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  26.78  | 0.15 | 23.89  | 16.74 |  66.98   |   16.74   |    66.98     |   0.01   | 37.33 | 192.29 |
| tri3_tex8_grey_quintic_bspline_direct                   |  46.60  | 0.16 | 43.76  | 9.14  |  36.56   |   9.14    |    36.56     |   0.01   | 21.46 | 107.67 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  32.62  | 0.17 | 29.83  | 13.41 |  53.63   |   13.41   |    53.63     |   0.01   | 30.66 | 155.33 |
| tri6_tex8_grey_linear_direct                            |  27.31  | 0.15 | 24.48  | 16.34 |  65.37   |   16.34   |    65.37     |   0.01   | 36.62 | 376.80 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  41.05  | 0.16 | 38.02  | 10.52 |  42.08   |   10.52   |    42.08     |   0.01   | 24.36 | 245.26 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  37.52  | 0.14 | 35.18  | 11.37 |  45.48   |   11.37   |    45.48     |   0.01   | 26.65 | 267.75 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  38.93  | 0.21 | 35.81  | 11.17 |  44.68   |   11.17   |    44.68     |   0.01   | 25.69 | 258.49 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  44.52  | 0.21 | 41.84  | 9.56  |  38.24   |   9.56    |    38.24     |   0.01   | 22.46 | 224.28 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  37.69  | 0.21 | 34.95  | 11.45 |  45.78   |   11.45   |    45.78     |   0.01   | 26.53 | 267.65 |
| tri6_tex8_grey_quintic_bspline_direct                   |  58.77  | 0.21 | 55.34  | 7.23  |  28.91   |   7.23    |    28.91     |   0.01   | 17.02 | 168.76 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  43.63  | 0.20 | 40.29  | 9.93  |  39.72   |   9.93    |    39.72     |   0.01   | 22.92 | 229.07 |
| quad4ibi_tex8_grey_linear_direct                        |  20.56  | 0.29 | 17.81  | 22.47 |  89.87   |   22.47   |    89.87     |   0.00   | 48.63 | 340.70 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  36.52  | 0.27 | 33.47  | 11.95 |  47.81   |   11.95   |    47.81     |   0.00   | 27.38 | 184.01 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  37.06  | 0.34 | 34.13  | 11.72 |  46.88   |   11.72   |    46.88     |   0.00   | 26.98 | 181.15 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  37.37  | 0.20 | 34.31  | 11.66 |  46.64   |   11.66   |    46.64     |   0.00   | 26.76 | 179.58 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  45.73  | 0.24 | 42.60  | 9.39  |  37.56   |   9.39    |    37.56     |   0.00   | 21.87 | 145.68 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  36.80  | 0.19 | 34.06  | 11.74 |  46.98   |   11.74   |    46.98     |   0.01   | 27.17 | 182.93 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  55.02  | 0.21 | 52.14  | 7.67  |  30.69   |   7.67    |    30.69     |   0.00   | 18.17 | 120.07 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  45.15  | 0.25 | 42.19  | 9.48  |  37.92   |   9.48    |    37.92     |   0.00   | 22.15 | 147.62 |
| quad4newton_tex8_grey_linear_direct                     |  23.35  | 0.25 | 20.59  | 19.43 |  77.72   |   19.43   |    77.72     |   0.00   | 42.83 | 295.95 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  37.37  | 0.22 | 34.62  | 11.56 |  46.22   |   11.56   |    46.22     |   0.00   | 26.76 | 179.58 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  33.45  | 0.23 | 30.66  | 13.04 |  52.18   |   13.04   |    52.18     |   0.00   | 29.90 | 202.89 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  33.67  | 0.29 | 30.63  | 13.06 |  52.24   |   13.06   |    52.24     |   0.00   | 29.70 | 200.24 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  40.26  | 0.25 | 37.24  | 10.74 |  42.97   |   10.74   |    42.97     |   0.00   | 24.84 | 166.53 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  33.00  | 0.22 | 30.33  | 13.19 |  52.75   |   13.19   |    52.75     |   0.00   | 30.30 | 205.39 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  54.22  | 0.23 | 51.26  | 7.80  |  31.21   |   7.80    |    31.21     |   0.00   | 18.44 | 121.88 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  39.17  | 0.28 | 36.31  | 11.02 |  44.07   |   11.02   |    44.07     |   0.00   | 25.53 | 171.36 |
| quad8_tex8_grey_linear_direct                           |  27.94  | 0.21 | 25.12  | 15.93 |  63.71   |   15.93   |    63.71     |   0.00   | 35.79 | 488.17 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  42.59  | 0.22 | 39.28  | 10.18 |  40.74   |   10.18   |    40.74     |   0.00   | 23.48 | 314.16 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  38.49  | 0.33 | 35.42  | 11.29 |  45.17   |   11.29   |    45.17     |   0.00   | 25.98 | 349.41 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  37.70  | 0.18 | 34.75  | 11.51 |  46.04   |   11.51   |    46.04     |   0.01   | 26.52 | 355.83 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  43.13  | 0.23 | 40.23  | 9.94  |  39.77   |   9.94    |    39.77     |   0.00   | 23.18 | 310.60 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  38.63  | 0.25 | 35.76  | 11.19 |  44.75   |   11.19   |    44.75     |   0.00   | 25.89 | 346.94 |
| quad8_tex8_grey_quintic_bspline_direct                  |  57.80  | 0.24 | 54.82  | 7.30  |  29.19   |   7.30    |    29.19     |   0.00   | 17.30 | 228.37 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  45.16  | 0.24 | 42.32  | 9.45  |  37.81   |   9.45    |    37.81     |   0.00   | 22.15 | 294.87 |
| quad9_tex8_grey_linear_direct                           |  28.12  | 0.25 | 25.40  | 15.75 |  62.99   |   15.75   |    62.99     |   0.00   | 35.56 | 548.05 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  42.26  | 0.24 | 39.49  | 10.13 |  40.52   |   10.13   |    40.52     |   0.00   | 23.66 | 355.37 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  37.61  | 0.21 | 34.82  | 11.49 |  45.94   |   11.49   |    45.94     |   0.00   | 26.59 | 403.35 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  37.78  | 0.31 | 35.06  | 11.41 |  45.64   |   11.41   |    45.64     |   0.00   | 26.47 | 399.35 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  45.01  | 0.24 | 41.56  | 9.62  |  38.50   |   9.62    |    38.50     |   0.00   | 22.22 | 335.69 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  37.94  | 0.29 | 35.00  | 11.43 |  45.72   |   11.43   |    45.72     |   0.00   | 26.36 | 397.55 |
| quad9_tex8_grey_quintic_bspline_direct                  |  57.90  | 0.21 | 55.02  | 7.27  |  29.08   |   7.27    |    29.08     |   0.00   | 17.27 | 256.21 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  45.58  | 0.25 | 42.80  | 9.35  |  37.38   |   9.35    |    37.38     |   0.00   | 21.94 | 329.03 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  21.73  | 0.16 | 18.08  | 22.12 |  88.50   |   22.12   |    88.50     |   0.01   | 46.03 | 241.54 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  40.00  | 0.13 | 36.10  | 11.08 |  44.32   |   11.08   |    44.32     |   0.02   | 25.00 | 125.45 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  36.75  | 0.13 | 32.92  | 12.15 |  48.60   |   12.15   |    48.60     |   0.02   | 27.22 | 137.16 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  36.29  | 0.16 | 32.49  | 12.31 |  49.25   |   12.31   |    49.25     |   0.01   | 27.56 | 139.87 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  45.32  | 0.15 | 41.06  | 9.74  |  38.98   |   9.74    |    38.98     |   0.01   | 22.06 | 110.12 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  36.25  | 0.18 | 32.22  | 12.42 |  49.67   |   12.42   |    49.67     |   0.01   | 27.59 | 139.04 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  58.52  | 0.14 | 55.55  | 7.20  |  28.80   |   7.20    |    28.80     |   0.01   | 17.09 | 84.54  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  44.99  | 0.13 | 41.29  | 9.69  |  38.75   |   9.69    |    38.75     |   0.02   | 22.23 | 110.98 |
| tri6_tex8_rgb_linear_direct                             |  37.75  | 0.18 | 33.61  | 11.90 |  47.60   |   11.90   |    47.60     |   0.01   | 26.49 | 266.34 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  51.99  | 0.17 | 48.26  | 8.29  |  33.15   |   8.29    |    33.15     |   0.01   | 19.23 | 190.89 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  47.82  | 0.16 | 44.29  | 9.03  |  36.13   |   9.03    |    36.13     |   0.01   | 20.91 | 208.33 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  48.82  | 0.16 | 45.27  | 8.84  |  35.34   |   8.84    |    35.34     |   0.01   | 20.49 | 204.41 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  57.07  | 0.17 | 53.46  | 7.48  |  29.93   |   7.48    |    29.93     |   0.01   | 17.52 | 173.45 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  48.53  | 0.16 | 45.03  | 8.88  |  35.53   |   8.88    |    35.53     |   0.01   | 20.61 | 205.01 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  72.06  | 0.17 | 68.47  | 5.84  |  23.37   |   5.84    |    23.37     |   0.01   | 13.88 | 136.83 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  57.64  | 0.15 | 53.18  | 7.52  |  30.09   |   7.52    |    30.09     |   0.01   | 17.35 | 171.82 |
| quad4ibi_tex8_rgb_linear_direct                         |  27.08  | 0.22 | 22.75  | 17.58 |  70.33   |   17.58   |    70.33     |   0.00   | 36.93 | 252.45 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  44.95  | 0.16 | 40.78  | 9.81  |  39.24   |   9.81    |    39.24     |   0.01   | 22.25 | 149.40 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  46.53  | 0.21 | 42.51  | 9.41  |  37.64   |   9.41    |    37.64     |   0.00   | 21.49 | 143.95 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  46.03  | 0.18 | 42.65  | 9.38  |  37.52   |   9.38    |    37.52     |   0.01   | 21.73 | 144.43 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  58.20  | 0.20 | 54.43  | 7.35  |  29.40   |   7.35    |    29.40     |   0.00   | 17.18 | 113.58 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  46.61  | 0.22 | 43.26  | 9.25  |  36.98   |   9.25    |    36.98     |   0.00   | 21.45 | 142.97 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  72.76  | 0.22 | 68.79  | 5.81  |  23.26   |   5.81    |    23.26     |   0.00   | 13.74 | 90.11  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  59.53  | 0.20 | 55.61  | 7.19  |  28.77   |   7.19    |    28.77     |   0.00   | 16.80 | 110.76 |
| quad4newton_tex8_rgb_linear_direct                      |  33.54  | 0.19 | 30.21  | 13.24 |  52.96   |   13.24   |    52.96     |   0.01   | 29.82 | 201.77 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  49.45  | 0.20 | 45.18  | 8.86  |  35.42   |   8.86    |    35.42     |   0.00   | 20.22 | 134.15 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  44.15  | 0.21 | 40.39  | 9.90  |  39.61   |   9.90    |    39.61     |   0.00   | 22.65 | 150.97 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  44.31  | 0.18 | 40.70  | 9.83  |  39.32   |   9.83    |    39.32     |   0.01   | 22.57 | 150.27 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  53.23  | 0.22 | 49.47  | 8.09  |  32.35   |   8.09    |    32.35     |   0.00   | 18.79 | 124.24 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  43.97  | 0.24 | 40.16  | 9.96  |  39.84   |   9.96    |    39.84     |   0.00   | 22.74 | 151.56 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  68.34  | 0.26 | 64.17  | 6.23  |  24.94   |   6.23    |    24.94     |   0.00   | 14.63 | 96.25  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  53.16  | 0.18 | 49.27  | 8.12  |  32.47   |   8.12    |    32.47     |   0.01   | 18.81 | 124.46 |
| quad8_tex8_rgb_linear_direct                            |  37.92  | 0.23 | 33.88  | 11.81 |  47.23   |   11.81   |    47.23     |   0.00   | 26.37 | 353.79 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  52.11  | 0.17 | 47.88  | 8.35  |  33.42   |   8.35    |    33.42     |   0.01   | 19.19 | 254.98 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.70  | 0.24 | 44.70  | 8.95  |  35.79   |   8.95    |    35.79     |   0.00   | 20.53 | 273.61 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  48.30  | 0.21 | 44.71  | 8.95  |  35.79   |   8.95    |    35.79     |   0.00   | 20.70 | 274.69 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  56.74  | 0.21 | 53.10  | 7.53  |  30.13   |   7.53    |    30.13     |   0.00   | 17.63 | 233.20 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  48.20  | 0.20 | 44.05  | 9.08  |  36.32   |   9.08    |    36.32     |   0.01   | 20.75 | 275.34 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  71.92  | 0.20 | 68.37  | 5.85  |  23.40   |   5.85    |    23.40     |   0.01   | 13.90 | 182.30 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  56.27  | 0.23 | 52.83  | 7.57  |  30.29   |   7.57    |    30.29     |   0.00   | 17.77 | 235.16 |
| quad9_tex8_rgb_linear_direct                            |  38.93  | 0.24 | 34.68  | 11.53 |  46.13   |   11.53   |    46.13     |   0.00   | 25.69 | 387.00 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  51.65  | 0.22 | 48.55  | 8.24  |  32.96   |   8.24    |    32.96     |   0.00   | 19.36 | 288.49 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.84  | 0.19 | 44.90  | 8.91  |  35.64   |   8.91    |    35.64     |   0.01   | 20.48 | 306.64 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  48.89  | 0.22 | 44.58  | 8.97  |  35.89   |   8.97    |    35.89     |   0.00   | 20.45 | 307.90 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  56.67  | 0.20 | 53.04  | 7.54  |  30.16   |   7.54    |    30.16     |   0.00   | 17.65 | 261.96 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  48.28  | 0.24 | 44.67  | 8.96  |  35.82   |   8.96    |    35.82     |   0.00   | 20.71 | 309.50 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  71.87  | 0.21 | 68.25  | 5.86  |  23.44   |   5.86    |    23.44     |   0.00   | 13.91 | 205.31 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  57.50  | 0.25 | 53.36  | 7.50  |  29.98   |   7.50    |    29.98     |   0.00   | 17.39 | 258.17 |

