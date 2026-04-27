# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  9.88   | 0.21 |  6.12  | 65.36 |  261.44  |   65.36   |    261.44    |   0.01   | 101.26 | 608.51 |
| tri6_nodal_grey                                         |  22.23  | 0.25 | 19.13  | 20.91 |  83.65   |   20.91   |    83.65     |   0.01   | 45.00 | 475.60 |
| quad4ibi_nodal_grey                                     |  15.84  | 0.25 | 12.83  | 31.19 |  124.74  |   31.19   |    124.74    |   0.00   | 63.14 | 451.61 |
| quad4newton_nodal_grey                                  |  17.75  | 0.26 | 15.19  | 26.33 |  105.34  |   26.33   |    105.34    |   0.00   | 56.36 | 398.17 |
| quad8_nodal_grey                                        |  22.30  | 0.21 | 19.49  | 20.53 |  82.10   |   20.53   |    82.10     |   0.00   | 44.84 | 619.75 |
| quad9_nodal_grey                                        |  23.30  | 0.28 | 20.08  | 19.92 |  79.68   |   19.92   |    79.68     |   0.00   | 42.92 | 670.49 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  14.13  | 0.18 |  8.31  | 48.16 |  192.63  |   48.16   |    192.63    |   0.01   | 70.79 | 385.68 |
| tri6_nodal_rgb                                          |  24.94  | 0.19 | 21.64  | 18.49 |  73.95   |   18.49   |    73.95     |   0.01   | 40.10 | 412.38 |
| quad4ibi_nodal_rgb                                      |  20.35  | 0.19 | 16.87  | 23.72 |  94.88   |   23.72   |    94.88     |   0.01   | 49.16 | 342.35 |
| quad4newton_nodal_rgb                                   |  20.67  | 0.20 | 17.08  | 23.42 |  93.68   |   23.42   |    93.68     |   0.01   | 48.38 | 338.20 |
| quad8_nodal_rgb                                         |  25.83  | 0.20 | 21.82  | 18.33 |  73.34   |   18.33   |    73.34     |   0.01   | 38.74 | 545.64 |
| quad9_nodal_rgb                                         |  26.42  | 0.19 | 22.69  | 17.63 |  70.52   |   17.63   |    70.52     |   0.01   | 37.85 | 583.63 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  15.81  | 0.13 | 13.43  | 29.79 |  119.18  |   29.79   |    119.18    |   0.02   | 63.27 | 340.73 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  29.02  | 0.15 | 26.24  | 15.25 |  61.00   |   15.25   |    61.00     |   0.01   | 34.46 | 175.38 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  26.07  | 0.15 | 23.15  | 17.28 |  69.13   |   17.28   |    69.13     |   0.01   | 38.35 | 197.12 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  26.21  | 0.16 | 23.33  | 17.15 |  68.58   |   17.15   |    68.58     |   0.01   | 38.15 | 196.01 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  34.00  | 0.12 | 30.79  | 12.99 |  51.97   |   12.99   |    51.97     |   0.02   | 29.41 | 152.50 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  25.41  | 0.16 | 22.70  | 17.62 |  70.48   |   17.62   |    70.48     |   0.01   | 39.36 | 202.67 |
| tri3_tex8_grey_quintic_bspline_direct                   |  43.79  | 0.19 | 41.43  | 9.65  |  38.62   |   9.65    |    38.62     |   0.01   | 22.84 | 113.91 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  30.88  | 0.15 | 28.23  | 14.17 |  56.69   |   14.17   |    56.69     |   0.01   | 32.39 | 165.03 |
| tri6_tex8_grey_linear_direct                            |  26.85  | 0.21 | 24.25  | 16.50 |  65.99   |   16.50   |    65.99     |   0.01   | 37.25 | 381.40 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  41.17  | 0.20 | 37.91  | 10.55 |  42.20   |   10.55   |    42.20     |   0.01   | 24.29 | 244.00 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  37.99  | 0.20 | 34.58  | 11.57 |  46.27   |   11.57   |    46.27     |   0.01   | 26.32 | 267.09 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  37.49  | 0.19 | 34.91  | 11.46 |  45.84   |   11.46   |    45.84     |   0.01   | 26.67 | 268.36 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  43.36  | 0.17 | 40.83  | 9.80  |  39.19   |   9.80    |    39.19     |   0.01   | 23.07 | 230.57 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  37.54  | 0.20 | 34.41  | 11.63 |  46.50   |   11.63   |    46.50     |   0.01   | 26.64 | 267.62 |
| tri6_tex8_grey_quintic_bspline_direct                   |  56.65  | 0.22 | 53.60  | 7.46  |  29.85   |   7.46    |    29.85     |   0.01   | 17.65 | 175.32 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  42.47  | 0.23 | 39.56  | 10.11 |  40.45   |   10.11   |    40.45     |   0.01   | 23.55 | 235.12 |
| quad4ibi_tex8_grey_linear_direct                        |  19.54  | 0.21 | 16.51  | 24.23 |  96.92   |   24.23   |    96.92     |   0.00   | 51.18 | 358.18 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  35.43  | 0.20 | 32.90  | 12.16 |  48.63   |   12.16   |    48.63     |   0.00   | 28.22 | 189.67 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  36.37  | 0.21 | 33.93  | 11.79 |  47.16   |   11.79   |    47.16     |   0.00   | 27.50 | 184.51 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  35.37  | 0.22 | 32.00  | 12.50 |  50.00   |   12.50   |    50.00     |   0.00   | 28.28 | 189.71 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  42.38  | 0.21 | 39.77  | 10.06 |  40.24   |   10.06   |    40.24     |   0.00   | 23.60 | 157.15 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  36.34  | 0.27 | 33.26  | 12.03 |  48.11   |   12.03   |    48.11     |   0.00   | 27.52 | 186.78 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  53.02  | 0.20 | 50.12  | 7.98  |  31.93   |   7.98    |    31.93     |   0.00   | 18.86 | 124.74 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  44.85  | 0.26 | 41.37  | 9.67  |  38.68   |   9.67    |    38.68     |   0.00   | 22.30 | 148.58 |
| quad4newton_tex8_grey_linear_direct                     |  23.34  | 0.16 | 20.56  | 19.46 |  77.84   |   19.46   |    77.84     |   0.01   | 42.84 | 295.46 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  35.09  | 0.29 | 32.59  | 12.27 |  49.10   |   12.27   |    49.10     |   0.00   | 28.50 | 191.44 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  32.30  | 0.30 | 29.38  | 13.62 |  54.46   |   13.62   |    54.46     |   0.00   | 30.96 | 208.83 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  32.10  | 0.24 | 29.22  | 13.69 |  54.76   |   13.69   |    54.76     |   0.00   | 31.15 | 210.12 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  37.71  | 0.32 | 34.90  | 11.46 |  45.84   |   11.46   |    45.84     |   0.00   | 26.52 | 177.41 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  31.98  | 0.24 | 29.18  | 13.71 |  54.84   |   13.71   |    54.84     |   0.00   | 31.27 | 210.93 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  51.81  | 0.22 | 49.29  | 8.12  |  32.47   |   8.12    |    32.47     |   0.00   | 19.30 | 127.76 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  37.78  | 0.30 | 35.03  | 11.42 |  45.67   |   11.42   |    45.67     |   0.00   | 26.47 | 177.05 |
| quad8_tex8_grey_linear_direct                           |  27.86  | 0.20 | 24.60  | 16.26 |  65.05   |   16.26   |    65.05     |   0.01   | 35.89 | 499.38 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  40.27  | 0.25 | 37.14  | 10.77 |  43.08   |   10.77   |    43.08     |   0.00   | 24.83 | 333.25 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  37.78  | 0.35 | 34.89  | 11.46 |  45.86   |   11.46   |    45.86     |   0.00   | 26.47 | 358.30 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  35.83  | 0.31 | 33.12  | 12.08 |  48.30   |   12.08   |    48.30     |   0.00   | 27.91 | 374.44 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  41.57  | 0.34 | 39.00  | 10.26 |  41.03   |   10.26   |    41.03     |   0.00   | 24.06 | 320.67 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  36.62  | 0.26 | 34.05  | 11.75 |  46.99   |   11.75   |    46.99     |   0.00   | 27.31 | 366.40 |
| quad8_tex8_grey_quintic_bspline_direct                  |  58.06  | 0.18 | 55.19  | 7.25  |  28.99   |   7.25    |    28.99     |   0.01   | 17.23 | 227.40 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  45.40  | 0.20 | 42.73  | 9.36  |  37.44   |   9.36    |    37.44     |   0.01   | 22.02 | 293.35 |
| quad9_tex8_grey_linear_direct                           |  27.86  | 0.21 | 25.10  | 15.94 |  63.75   |   15.94   |    63.75     |   0.00   | 35.89 | 556.62 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  41.68  | 0.27 | 38.49  | 10.39 |  41.57   |   10.39   |    41.57     |   0.00   | 23.99 | 363.07 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  37.74  | 0.26 | 35.05  | 11.41 |  45.65   |   11.41   |    45.65     |   0.00   | 26.49 | 400.27 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  37.85  | 0.19 | 34.89  | 11.46 |  45.86   |   11.46   |    45.86     |   0.01   | 26.42 | 401.11 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  43.64  | 0.22 | 40.41  | 9.90  |  39.59   |   9.90    |    39.59     |   0.00   | 22.91 | 347.23 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  38.41  | 0.24 | 35.35  | 11.32 |  45.26   |   11.32   |    45.26     |   0.00   | 26.03 | 392.51 |
| quad9_tex8_grey_quintic_bspline_direct                  |  57.76  | 0.25 | 54.54  | 7.33  |  29.34   |   7.33    |    29.34     |   0.00   | 17.31 | 257.02 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  45.05  | 0.22 | 41.76  | 9.58  |  38.31   |   9.58    |    38.31     |   0.00   | 22.20 | 334.60 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  22.73  | 0.16 | 17.77  | 22.52 |  90.06   |   22.52   |    90.06     |   0.01   | 44.05 | 228.84 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  38.73  | 0.18 | 34.83  | 11.49 |  45.94   |   11.49   |    45.94     |   0.01   | 25.83 | 129.72 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  35.88  | 0.16 | 32.53  | 12.30 |  49.19   |   12.30   |    49.19     |   0.01   | 27.88 | 140.70 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  33.90  | 0.21 | 30.73  | 13.02 |  52.06   |   13.02   |    52.06     |   0.01   | 29.50 | 148.85 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  42.54  | 0.14 | 38.41  | 10.41 |  41.65   |   10.41   |    41.65     |   0.01   | 23.51 | 117.42 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  33.90  | 0.16 | 30.73  | 13.02 |  52.07   |   13.02   |    52.07     |   0.01   | 29.50 | 148.86 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  56.34  | 0.14 | 52.61  | 7.60  |  30.41   |   7.60    |    30.41     |   0.01   | 17.75 | 87.77  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  42.96  | 0.13 | 39.71  | 10.07 |  40.29   |   10.07   |    40.29     |   0.01   | 23.28 | 116.32 |
| tri6_tex8_rgb_linear_direct                             |  36.52  | 0.20 | 32.69  | 12.24 |  48.96   |   12.24   |    48.96     |   0.01   | 27.39 | 275.59 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  50.28  | 0.16 | 46.72  | 8.56  |  34.25   |   8.56    |    34.25     |   0.01   | 19.89 | 197.63 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  48.76  | 0.16 | 44.78  | 8.93  |  35.73   |   8.93    |    35.73     |   0.01   | 20.51 | 204.32 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  47.00  | 0.16 | 43.63  | 9.17  |  36.67   |   9.17    |    36.67     |   0.01   | 21.28 | 212.22 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  56.26  | 0.15 | 52.12  | 7.68  |  30.70   |   7.68    |    30.70     |   0.01   | 17.78 | 175.97 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  49.50  | 0.16 | 45.80  | 8.73  |  34.93   |   8.73    |    34.93     |   0.01   | 20.20 | 200.75 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  72.43  | 0.18 | 68.22  | 5.86  |  23.45   |   5.86    |    23.45     |   0.01   | 13.81 | 135.80 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  57.47  | 0.17 | 53.74  | 7.44  |  29.77   |   7.44    |    29.77     |   0.01   | 17.40 | 172.08 |
| quad4ibi_tex8_rgb_linear_direct                         |  25.32  | 0.21 | 22.01  | 18.18 |  72.71   |   18.18   |    72.71     |   0.00   | 39.49 | 271.27 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  43.21  | 0.23 | 39.10  | 10.23 |  40.92   |   10.23   |    40.92     |   0.00   | 23.15 | 154.54 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  47.81  | 0.19 | 43.18  | 9.27  |  37.07   |   9.27    |    37.07     |   0.01   | 20.92 | 141.40 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  46.79  | 0.16 | 42.07  | 9.51  |  38.04   |   9.51    |    38.04     |   0.01   | 21.39 | 141.91 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  56.65  | 0.16 | 53.16  | 7.52  |  30.10   |   7.52    |    30.10     |   0.01   | 17.66 | 116.40 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  44.22  | 0.21 | 40.27  | 9.93  |  39.73   |   9.93    |    39.73     |   0.00   | 22.62 | 150.42 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  68.65  | 0.20 | 65.41  | 6.11  |  24.46   |   6.11    |    24.46     |   0.00   | 14.57 | 95.49  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  56.24  | 0.21 | 52.40  | 7.63  |  30.54   |   7.63    |    30.54     |   0.00   | 17.78 | 117.24 |
| quad4newton_tex8_rgb_linear_direct                      |  31.83  | 0.21 | 28.49  | 14.04 |  56.16   |   14.04   |    56.16     |   0.00   | 31.42 | 212.15 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  45.82  | 0.22 | 41.90  | 9.55  |  38.19   |   9.55    |    38.19     |   0.00   | 21.82 | 144.95 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  41.44  | 0.19 | 38.20  | 10.47 |  41.88   |   10.47   |    41.88     |   0.01   | 24.13 | 160.84 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  41.18  | 0.20 | 37.84  | 10.57 |  42.29   |   10.57   |    42.29     |   0.00   | 24.29 | 161.85 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  50.52  | 0.17 | 46.83  | 8.54  |  34.17   |   8.54    |    34.17     |   0.01   | 19.79 | 131.08 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  41.45  | 0.25 | 37.95  | 10.54 |  42.16   |   10.54   |    42.16     |   0.00   | 24.13 | 160.75 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  64.03  | 0.20 | 60.69  | 6.59  |  26.36   |   6.59    |    26.36     |   0.00   | 15.62 | 102.57 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  50.28  | 0.23 | 46.50  | 8.60  |  34.41   |   8.60    |    34.41     |   0.00   | 19.89 | 131.57 |
| quad8_tex8_rgb_linear_direct                            |  37.35  | 0.18 | 33.67  | 11.88 |  47.52   |   11.88   |    47.52     |   0.01   | 26.77 | 361.99 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  53.20  | 0.21 | 48.60  | 8.23  |  32.93   |   8.23    |    32.93     |   0.00   | 18.80 | 248.62 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  47.76  | 0.17 | 44.46  | 9.00  |  35.99   |   9.00    |    35.99     |   0.01   | 20.94 | 278.09 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.69  | 0.21 | 44.29  | 9.03  |  36.13   |   9.03    |    36.13     |   0.00   | 20.97 | 278.29 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  56.60  | 0.17 | 52.94  | 7.56  |  30.22   |   7.56    |    30.22     |   0.01   | 17.67 | 233.92 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  48.16  | 0.21 | 44.92  | 8.91  |  35.62   |   8.91    |    35.62     |   0.00   | 20.76 | 275.74 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  71.49  | 0.22 | 67.17  | 5.95  |  23.82   |   5.95    |    23.82     |   0.00   | 13.99 | 183.40 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  56.14  | 0.20 | 52.49  | 7.62  |  30.48   |   7.62    |    30.48     |   0.01   | 17.81 | 235.96 |
| quad9_tex8_rgb_linear_direct                            |  38.56  | 0.23 | 34.05  | 11.75 |  46.99   |   11.75   |    46.99     |   0.00   | 25.94 | 396.98 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  52.12  | 0.21 | 48.23  | 8.29  |  33.17   |   8.29    |    33.17     |   0.00   | 19.19 | 288.11 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.79  | 0.21 | 45.60  | 8.77  |  35.09   |   8.77    |    35.09     |   0.00   | 20.50 | 306.84 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.49  | 0.19 | 44.04  | 9.08  |  36.33   |   9.08    |    36.33     |   0.01   | 21.06 | 315.54 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  57.62  | 0.22 | 53.29  | 7.51  |  30.02   |   7.51    |    30.02     |   0.00   | 17.36 | 257.57 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  47.42  | 0.21 | 43.66  | 9.16  |  36.65   |   9.16    |    36.65     |   0.00   | 21.09 | 316.05 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  71.76  | 0.21 | 67.73  | 5.91  |  23.62   |   5.91    |    23.62     |   0.00   | 13.93 | 206.67 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  57.58  | 0.23 | 53.97  | 7.41  |  29.65   |   7.41    |    29.65     |   0.00   | 17.37 | 257.75 |

