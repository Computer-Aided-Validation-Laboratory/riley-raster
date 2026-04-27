# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  15.34  | 4.14 |  4.93  | 81.16 |  324.66  |   83.97   |    335.86    |  49.50   | 65.24 | 435.45 |
| tri6_nodal_grey                                         |  35.59  | 8.41 | 18.81  | 21.27 |  85.09   |   21.86   |    87.44     |  24.39   | 28.10 | 335.73 |
| quad4ibi_nodal_grey                                     |  11.61  | 3.06 |  5.84  | 68.58 |  274.33  |   70.35   |    281.39    |  33.43   | 86.16 | 670.54 |
| quad4newton_nodal_grey                                  |  18.90  | 3.19 |  9.14  | 43.76 |  175.03  |   44.96   |    179.83    |  32.11   | 55.37 | 493.97 |
| quad8_nodal_grey                                        |  29.20  | 5.98 | 15.33  | 26.11 |  104.45  |   26.82   |    107.27    |  17.13   | 34.25 | 560.88 |
| quad9_nodal_grey                                        |  30.34  | 6.99 | 14.43  | 27.72 |  110.89  |   28.48   |    113.92    |  14.67   | 32.96 | 613.59 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  19.27  | 4.88 |  6.07  | 65.87 |  263.48  |   68.16   |    272.63    |  41.95   | 51.90 | 302.34 |
| tri6_nodal_rgb                                          |  40.49  | 10.13 | 19.03  | 21.10 |  84.41   |   21.69   |    86.75     |  20.23   | 24.71 | 310.34 |
| quad4ibi_nodal_rgb                                      |  16.49  | 3.36 |  8.04  | 49.74 |  198.94  |   51.02   |    204.07    |  30.51   | 60.67 | 490.75 |
| quad4newton_nodal_rgb                                   |  20.19  | 3.52 | 11.09  | 36.07 |  144.29  |   37.05   |    148.19    |  29.08   | 49.55 | 381.40 |
| quad8_nodal_rgb                                         |  33.78  | 7.72 | 16.60  | 24.10 |  96.39   |   24.74   |    98.96     |  13.28   | 29.61 | 499.21 |
| quad9_nodal_rgb                                         |  30.74  | 7.17 | 15.86  | 25.22 |  100.89  |   25.91   |    103.62    |  14.28   | 32.54 | 587.40 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  22.53  | 4.50 |  8.37  | 47.78 |  191.13  |   49.45   |    197.80    |  45.56   | 44.40 | 310.96 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  25.18  | 4.27 | 11.95  | 33.47 |  133.90  |   34.64   |    138.55    |  47.96   | 39.71 | 271.02 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  23.11  | 4.14 | 10.88  | 36.78 |  147.13  |   38.07   |    152.27    |  49.51   | 43.26 | 300.56 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  22.79  | 4.32 | 10.46  | 38.23 |  152.91  |   39.55   |    158.19    |  47.42   | 43.90 | 302.00 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  24.23  | 4.11 | 11.77  | 34.10 |  136.41  |   35.29   |    141.14    |  49.87   | 41.28 | 270.50 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  23.18  | 4.53 | 10.69  | 37.45 |  149.78  |   38.75   |    155.01    |  45.23   | 43.15 | 292.93 |
| tri3_tex8_grey_quintic_bspline_direct                   |  29.95  | 4.39 | 17.93  | 22.30 |  89.22   |   23.08   |    92.33     |  46.62   | 33.39 | 207.38 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  26.39  | 4.18 | 13.68  | 29.25 |  116.99  |   30.26   |    121.05    |  48.94   | 37.90 | 244.85 |
| tri6_tex8_grey_linear_direct                            |  51.76  | 9.04 | 19.56  | 20.45 |  81.79   |   21.01   |    84.03     |  22.68   | 19.32 | 312.00 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  55.54  | 8.57 | 24.38  | 16.44 |  65.75   |   16.89   |    67.57     |  23.90   | 18.00 | 276.16 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  55.35  | 8.81 | 23.76  | 16.84 |  67.36   |   17.31   |    69.22     |  23.26   | 18.07 | 277.26 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  56.10  | 8.75 | 23.87  | 16.76 |  67.04   |   17.22   |    68.88     |  23.42   | 17.83 | 283.87 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  57.23  | 9.05 | 25.94  | 15.42 |  61.69   |   15.85   |    63.40     |  22.66   | 17.48 | 271.10 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  54.88  | 8.95 | 23.81  | 16.80 |  67.19   |   17.26   |    69.05     |  22.90   | 18.22 | 282.17 |
| tri6_tex8_grey_quintic_bspline_direct                   |  62.04  | 8.85 | 29.14  | 13.73 |  54.92   |   14.11   |    56.44     |  23.15   | 16.12 | 238.36 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  57.18  | 9.64 | 25.39  | 15.76 |  63.02   |   16.19   |    64.76     |  21.25   | 17.49 | 264.54 |
| quad4ibi_tex8_grey_linear_direct                        |  15.74  | 3.37 |  6.93  | 57.81 |  231.23  |   59.30   |    237.19    |  30.41   | 63.54 | 578.29 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  21.08  | 3.21 | 12.78  | 31.32 |  125.26  |   32.12   |    128.48    |  31.86   | 47.45 | 365.42 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  21.12  | 3.31 | 13.54  | 29.54 |  118.14  |   30.27   |    121.10    |  31.00   | 47.34 | 363.31 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  22.56  | 3.17 | 12.82  | 31.21 |  124.83  |   31.99   |    127.97    |  32.33   | 44.43 | 364.51 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  24.27  | 3.06 | 15.08  | 26.53 |  106.13  |   27.22   |    108.86    |  33.44   | 41.20 | 307.88 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  21.26  | 3.17 | 12.49  | 32.03 |  128.12  |   32.85   |    131.41    |  32.33   | 47.05 | 377.51 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  25.94  | 3.03 | 18.78  | 21.30 |  85.21   |   21.85   |    87.40     |  33.85   | 38.56 | 285.51 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  24.73  | 2.73 | 15.73  | 25.44 |  101.75  |   26.09   |    104.37    |  37.57   | 40.44 | 326.86 |
| quad4newton_tex8_grey_linear_direct                     |  30.48  | 3.47 | 10.74  | 37.36 |  149.44  |   38.38   |    153.51    |  29.53   | 32.81 | 397.07 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  37.18  | 2.91 | 16.35  | 24.47 |  97.88   |   25.14   |    100.54    |  35.31   | 26.91 | 310.75 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  34.42  | 3.41 | 16.00  | 25.01 |  100.05  |   25.70   |    102.80    |  30.08   | 29.05 | 318.55 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  34.04  | 2.96 | 15.35  | 26.07 |  104.27  |   26.77   |    107.10    |  34.68   | 29.37 | 337.11 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  35.44  | 3.06 | 17.67  | 22.64 |  90.54   |   23.26   |    93.02     |  33.45   | 28.22 | 297.89 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  34.67  | 2.87 | 15.21  | 26.30 |  105.21  |   27.02   |    108.09    |  35.76   | 28.91 | 329.28 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  39.08  | 2.85 | 21.32  | 18.77 |  75.06   |   19.28   |    77.11     |  35.95   | 25.59 | 254.95 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  36.32  | 3.53 | 14.72  | 27.21 |  108.84  |   27.95   |    111.81    |  29.02   | 27.56 | 328.21 |
| quad8_tex8_grey_linear_direct                           |  39.53  | 6.51 | 17.83  | 22.43 |  89.71   |   23.03   |    92.13     |  15.72   | 25.30 | 504.81 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  43.42  | 6.35 | 20.67  | 19.36 |  77.45   |   19.88   |    79.52     |  16.13   | 23.03 | 442.97 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  42.98  | 6.32 | 20.62  | 19.41 |  77.62   |   19.93   |    79.71     |  16.20   | 23.27 | 454.04 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.00  | 6.29 | 20.81  | 19.22 |  76.87   |   19.74   |    78.94     |  16.27   | 23.26 | 456.85 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  43.86  | 7.11 | 21.64  | 18.48 |  73.93   |   18.98   |    75.90     |  14.40   | 22.80 | 437.27 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  42.33  | 6.50 | 20.31  | 19.72 |  78.87   |   20.25   |    81.00     |  15.78   | 23.62 | 453.00 |
| quad8_tex8_grey_quintic_bspline_direct                  |  46.67  | 6.18 | 24.82  | 16.11 |  64.46   |   16.55   |    66.20     |  16.56   | 21.43 | 398.54 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  44.57  | 6.26 | 21.89  | 18.27 |  73.09   |   18.76   |    75.06     |  16.35   | 22.44 | 427.22 |
| quad9_tex8_grey_linear_direct                           |  41.47  | 6.85 | 17.27  | 23.16 |  92.64   |   23.79   |    95.16     |  14.94   | 24.12 | 576.68 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  44.81  | 6.74 | 20.25  | 19.75 |  79.01   |   20.29   |    81.16     |  15.20   | 22.32 | 513.69 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  43.22  | 6.52 | 19.67  | 20.34 |  81.35   |   20.89   |    83.57     |  15.69   | 23.15 | 528.20 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  45.38  | 7.33 | 19.35  | 20.68 |  82.72   |   21.24   |    84.96     |  13.98   | 22.04 | 511.07 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  43.03  | 7.13 | 20.77  | 19.26 |  77.04   |   19.78   |    79.13     |  14.36   | 23.25 | 506.93 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  43.76  | 6.44 | 19.25  | 20.80 |  83.18   |   21.36   |    85.44     |  15.89   | 22.85 | 530.30 |
| quad9_tex8_grey_quintic_bspline_direct                  |  49.45  | 6.78 | 26.22  | 15.27 |  61.06   |   15.68   |    62.72     |  15.12   | 20.23 | 429.14 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  44.88  | 6.94 | 22.03  | 18.16 |  72.64   |   18.65   |    74.61     |  14.76   | 22.28 | 490.04 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  22.97  | 4.30 | 10.41  | 38.45 |  153.78  |   39.79   |    159.15    |  47.64   | 43.53 | 277.20 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  28.95  | 4.51 | 15.81  | 25.29 |  101.18  |   26.18   |    104.71    |  45.46   | 34.55 | 209.34 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  27.71  | 4.36 | 15.21  | 26.31 |  105.22  |   27.22   |    108.88    |  46.96   | 36.09 | 215.93 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  27.77  | 4.13 | 15.06  | 26.56 |  106.26  |   27.49   |    109.97    |  49.68   | 36.02 | 226.24 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  30.46  | 4.10 | 17.91  | 22.33 |  89.33   |   23.11   |    92.43     |  49.96   | 32.83 | 191.43 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  28.81  | 4.14 | 15.69  | 25.49 |  101.96  |   26.38   |    105.51    |  49.46   | 34.71 | 214.35 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  34.50  | 4.13 | 22.23  | 18.00 |  72.01   |   18.63   |    74.51     |  49.60   | 28.99 | 164.95 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  29.53  | 3.82 | 18.53  | 21.59 |  86.37   |   22.35   |    89.38     |  53.68   | 33.86 | 200.22 |
| tri6_tex8_rgb_linear_direct                             |  59.46  | 10.18 | 23.69  | 16.88 |  67.53   |   17.35   |    69.39     |  20.12   | 16.82 | 266.96 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  62.23  | 10.20 | 26.90  | 14.87 |  59.48   |   15.28   |    61.14     |  20.10   | 16.07 | 242.84 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  62.85  | 9.72 | 28.76  | 13.91 |  55.64   |   14.29   |    57.18     |  21.08   | 15.91 | 234.16 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  62.74  | 9.58 | 27.59  | 14.50 |  58.00   |   14.90   |    59.61     |  21.38   | 15.94 | 242.23 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  63.97  | 9.41 | 30.13  | 13.28 |  53.13   |   13.65   |    54.61     |  21.77   | 15.63 | 228.80 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  59.59  | 10.15 | 27.53  | 14.53 |  58.13   |   14.93   |    59.73     |  20.19   | 16.78 | 246.86 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  71.13  | 9.35 | 37.60  | 10.64 |  42.56   |   10.93   |    43.73     |  21.91   | 14.06 | 195.58 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  64.93  | 9.65 | 31.22  | 12.81 |  51.26   |   13.17   |    52.66     |  21.22   | 15.40 | 215.98 |
| quad4ibi_tex8_rgb_linear_direct                         |  19.16  | 3.17 |  9.71  | 41.23 |  164.94  |   42.29   |    169.17    |  32.30   | 52.18 | 440.68 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  25.56  | 3.47 | 15.11  | 26.48 |  105.92  |   27.15   |    108.61    |  29.56   | 39.21 | 302.53 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  24.21  | 3.34 | 13.51  | 29.78 |  119.11  |   30.54   |    122.17    |  30.75   | 41.35 | 320.02 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  24.76  | 3.09 | 15.12  | 26.47 |  105.86  |   27.15   |    108.59    |  33.17   | 40.40 | 314.01 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  29.06  | 3.32 | 19.42  | 20.60 |  82.38   |   21.13   |    84.50     |  30.88   | 34.41 | 260.10 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  24.74  | 3.25 | 15.44  | 25.91 |  103.63  |   26.58   |    106.32    |  31.52   | 40.42 | 316.01 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  35.70  | 3.43 | 24.34  | 16.44 |  65.76   |   16.86   |    67.46     |  29.89   | 28.01 | 211.12 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  29.43  | 3.16 | 19.90  | 20.10 |  80.42   |   20.63   |    82.50     |  32.48   | 33.98 | 257.26 |
| quad4newton_tex8_rgb_linear_direct                      |  34.61  | 3.09 | 15.04  | 26.60 |  106.40  |   27.33   |    109.30    |  33.17   | 28.91 | 317.03 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  39.71  | 3.12 | 19.25  | 20.78 |  83.11   |   21.34   |    85.38     |  32.81   | 25.18 | 254.64 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  38.33  | 3.06 | 18.00  | 22.22 |  88.89   |   22.83   |    91.33     |  33.48   | 26.09 | 274.59 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  39.85  | 3.12 | 19.82  | 20.18 |  80.73   |   20.73   |    82.93     |  32.86   | 25.10 | 257.21 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  40.39  | 3.07 | 20.22  | 19.79 |  79.18   |   20.33   |    81.32     |  33.38   | 24.77 | 247.84 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  37.85  | 3.01 | 18.84  | 21.23 |  84.93   |   21.81   |    87.25     |  34.02   | 26.42 | 271.54 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  46.19  | 3.16 | 23.97  | 16.69 |  66.75   |   17.14   |    68.58     |  32.39   | 21.66 | 213.93 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  40.63  | 2.99 | 21.65  | 18.48 |  73.91   |   18.98   |    75.93     |  34.25   | 24.61 | 241.80 |
| quad8_tex8_rgb_linear_direct                            |  43.91  | 6.62 | 20.64  | 19.38 |  77.52   |   19.90   |    79.59     |  15.46   | 22.78 | 450.43 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  47.62  | 6.70 | 22.79  | 17.59 |  70.36   |   18.06   |    72.24     |  15.28   | 21.01 | 410.27 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  44.94  | 6.47 | 21.01  | 19.05 |  76.20   |   19.56   |    78.25     |  15.82   | 22.26 | 430.08 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  46.85  | 7.10 | 21.46  | 18.64 |  74.58   |   19.15   |    76.59     |  14.43   | 21.35 | 420.35 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  49.09  | 6.69 | 25.43  | 15.73 |  62.93   |   16.15   |    64.62     |  15.32   | 20.37 | 366.36 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  46.73  | 6.80 | 23.43  | 17.07 |  68.30   |   17.53   |    70.14     |  15.07   | 21.40 | 399.42 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  52.73  | 6.65 | 28.95  | 13.82 |  55.29   |   14.19   |    56.77     |  15.40   | 18.97 | 336.70 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  49.09  | 6.45 | 27.18  | 14.73 |  58.91   |   15.12   |    60.50     |  15.87   | 20.37 | 361.63 |
| quad9_tex8_rgb_linear_direct                            |  45.13  | 7.20 | 19.88  | 20.12 |  80.48   |   20.66   |    82.65     |  14.22   | 22.16 | 497.29 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  46.89  | 6.70 | 22.39  | 17.92 |  71.68   |   18.41   |    73.62     |  15.29   | 21.33 | 453.76 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.10  | 6.80 | 23.66  | 16.91 |  67.64   |   17.37   |    69.49     |  15.06   | 20.79 | 446.64 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  50.25  | 7.55 | 24.02  | 16.66 |  66.63   |   17.11   |    68.44     |  13.59   | 19.90 | 427.91 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  52.40  | 6.61 | 25.56  | 15.70 |  62.80   |   16.13   |    64.51     |  15.50   | 19.08 | 414.65 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  48.17  | 6.80 | 21.58  | 18.53 |  74.13   |   19.04   |    76.17     |  15.05   | 20.76 | 458.04 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  55.10  | 6.69 | 28.27  | 14.16 |  56.64   |   14.55   |    58.20     |  15.30   | 18.15 | 386.31 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  49.94  | 6.79 | 25.77  | 15.53 |  62.13   |   15.96   |    63.82     |  15.09   | 20.04 | 414.55 |

