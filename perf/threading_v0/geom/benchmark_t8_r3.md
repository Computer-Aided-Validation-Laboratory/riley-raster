# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  16.08  | 4.14 |  4.89  | 81.78 |  327.11  |   84.63   |    338.52    |  49.52   | 62.18 | 425.35 |
| tri6_nodal_grey                                         |  36.34  | 8.56 | 19.77  | 20.23 |  80.94   |   20.79   |    83.17     |  23.92   | 27.52 | 331.42 |
| quad4ibi_nodal_grey                                     |  12.01  | 3.07 |  5.98  | 66.90 |  267.61  |   68.61   |    274.44    |  33.33   | 83.27 | 640.87 |
| quad4newton_nodal_grey                                  |  23.94  | 3.16 | 10.18  | 39.30 |  157.18  |   40.37   |    161.47    |  32.64   | 41.81 | 448.71 |
| quad8_nodal_grey                                        |  28.67  | 5.91 | 15.29  | 26.17 |  104.67  |   26.87   |    107.49    |  17.34   | 34.89 | 574.52 |
| quad9_nodal_grey                                        |  28.87  | 6.76 | 14.96  | 26.74 |  106.95  |   27.47   |    109.87    |  15.14   | 34.64 | 637.74 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  19.92  | 4.90 |  5.73  | 69.78 |  279.12  |   72.22   |    288.87    |  41.76   | 50.24 | 296.33 |
| tri6_nodal_rgb                                          |  42.33  | 10.74 | 20.32  | 19.69 |  78.76   |   20.23   |    80.94     |  19.07   | 23.63 | 293.67 |
| quad4ibi_nodal_rgb                                      |  15.79  | 3.64 |  7.56  | 52.94 |  211.77  |   54.30   |    217.18    |  28.16   | 63.33 | 503.81 |
| quad4newton_nodal_rgb                                   |  19.48  | 3.23 | 10.66  | 37.52 |  150.08  |   38.55   |    154.18    |  31.71   | 51.33 | 391.44 |
| quad8_nodal_rgb                                         |  31.64  | 7.12 | 16.28  | 24.56 |  98.26   |   25.23   |    100.90    |  14.39   | 31.62 | 508.50 |
| quad9_nodal_rgb                                         |  32.46  | 7.69 | 15.58  | 25.69 |  102.77  |   26.39   |    105.57    |  13.31   | 30.83 | 576.09 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  19.86  | 4.34 |  7.12  | 56.29 |  225.16  |   58.24   |    232.95    |  47.23   | 50.37 | 368.13 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  24.88  | 4.34 | 12.26  | 32.62 |  130.47  |   33.76   |    135.03    |  47.21   | 40.20 | 265.74 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  23.79  | 4.37 | 10.95  | 36.54 |  146.15  |   37.81   |    151.25    |  46.87   | 42.03 | 278.64 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  22.85  | 4.49 | 10.20  | 39.20 |  156.82  |   40.55   |    162.20    |  45.62   | 43.76 | 294.30 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  25.57  | 4.61 | 12.35  | 32.38 |  129.51  |   33.51   |    134.03    |  44.49   | 39.15 | 250.93 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  23.04  | 4.43 | 11.20  | 35.70 |  142.82  |   36.95   |    147.81    |  46.23   | 43.42 | 288.23 |
| tri3_tex8_grey_quintic_bspline_direct                   |  28.87  | 4.42 | 15.11  | 26.48 |  105.93  |   27.41   |    109.62    |  46.38   | 34.67 | 215.59 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  25.10  | 4.09 | 13.83  | 28.93 |  115.71  |   29.94   |    119.75    |  50.10   | 39.83 | 256.61 |
| tri6_tex8_grey_linear_direct                            |  51.40  | 9.61 | 21.08  | 18.97 |  75.90   |   19.50   |    78.00     |  21.30   | 19.45 | 301.11 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  54.93  | 10.44 | 23.19  | 17.27 |  69.09   |   17.75   |    71.00     |  19.71   | 18.21 | 276.59 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  57.00  | 9.08 | 25.34  | 15.78 |  63.14   |   16.22   |    64.88     |  22.55   | 17.55 | 261.16 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  54.44  | 8.94 | 23.69  | 16.88 |  67.54   |   17.35   |    69.41     |  22.91   | 18.37 | 281.35 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  58.18  | 8.88 | 26.96  | 14.84 |  59.36   |   15.25   |    61.00     |  23.07   | 17.19 | 260.09 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  56.35  | 10.18 | 24.08  | 16.62 |  66.46   |   17.07   |    68.30     |  20.17   | 17.75 | 268.45 |
| tri6_tex8_grey_quintic_bspline_direct                   |  58.82  | 9.98 | 28.09  | 14.28 |  57.10   |   14.67   |    58.69     |  20.52   | 17.00 | 244.43 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  57.24  | 9.47 | 26.29  | 15.23 |  60.91   |   15.65   |    62.59     |  21.64   | 17.47 | 258.63 |
| quad4ibi_tex8_grey_linear_direct                        |  15.25  | 3.12 |  7.66  | 52.26 |  209.03  |   53.60   |    214.39    |  32.88   | 65.56 | 540.40 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  20.56  | 3.14 | 12.68  | 31.55 |  126.19  |   32.34   |    129.35    |  32.60   | 48.63 | 381.01 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  19.30  | 2.90 | 12.36  | 32.37 |  129.48  |   33.19   |    132.77    |  35.27   | 51.82 | 398.84 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.17  | 3.30 | 12.39  | 32.30 |  129.21  |   33.12   |    132.50    |  31.06   | 49.58 | 389.70 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  27.65  | 2.97 | 15.94  | 25.10 |  100.39  |   25.75   |    102.99    |  34.43   | 36.18 | 322.31 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  22.14  | 2.82 | 13.34  | 29.98 |  119.92  |   30.75   |    123.00    |  36.37   | 45.27 | 376.64 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  26.29  | 2.81 | 18.97  | 21.09 |  84.35   |   21.63   |    86.52     |  36.46   | 38.04 | 278.09 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  26.60  | 2.88 | 15.91  | 25.15 |  100.59  |   25.80   |    103.18    |  35.65   | 37.59 | 318.36 |
| quad4newton_tex8_grey_linear_direct                     |  32.96  | 3.61 | 12.46  | 32.10 |  128.39  |   32.98   |    131.90    |  28.39   | 30.36 | 376.25 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  33.33  | 2.87 | 15.44  | 25.93 |  103.74  |   26.64   |    106.57    |  35.74   | 30.00 | 318.25 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  32.70  | 3.02 | 14.35  | 27.91 |  111.64  |   28.67   |    114.69    |  33.89   | 30.59 | 347.82 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  35.10  | 3.36 | 15.68  | 25.51 |  102.03  |   26.20   |    104.82    |  30.57   | 28.49 | 316.13 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  37.73  | 3.12 | 17.52  | 22.83 |  91.31   |   23.45   |    93.78     |  33.06   | 26.59 | 297.69 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  33.06  | 2.93 | 14.64  | 27.34 |  109.35  |   28.09   |    112.34    |  34.95   | 30.25 | 343.53 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  38.24  | 2.79 | 21.50  | 18.61 |  74.42   |   19.11   |    76.46     |  36.68   | 26.15 | 255.94 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  36.33  | 3.13 | 17.36  | 23.07 |  92.30   |   23.71   |    94.83     |  32.92   | 27.53 | 292.77 |
| quad8_tex8_grey_linear_direct                           |  40.88  | 6.11 | 17.73  | 22.56 |  90.25   |   23.17   |    92.68     |  16.75   | 24.46 | 494.39 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  44.29  | 6.34 | 21.56  | 18.56 |  74.24   |   19.06   |    76.22     |  16.15   | 22.58 | 436.66 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  41.55  | 6.90 | 17.48  | 22.89 |  91.54   |   23.50   |    94.00     |  14.84   | 24.07 | 503.52 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  42.86  | 6.64 | 20.93  | 19.11 |  76.46   |   19.63   |    78.51     |  15.45   | 23.34 | 455.30 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  44.09  | 6.36 | 21.03  | 19.02 |  76.09   |   19.53   |    78.14     |  16.10   | 22.68 | 441.95 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  43.08  | 6.47 | 20.33  | 19.68 |  78.72   |   20.21   |    80.84     |  15.84   | 23.21 | 460.18 |
| quad8_tex8_grey_quintic_bspline_direct                  |  46.54  | 6.75 | 24.34  | 16.44 |  65.77   |   16.88   |    67.54     |  15.19   | 21.50 | 398.99 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  44.16  | 6.55 | 21.53  | 18.58 |  74.31   |   19.08   |    76.32     |  15.65   | 22.65 | 425.15 |
| quad9_tex8_grey_linear_direct                           |  41.42  | 6.62 | 17.80  | 22.48 |  89.90   |   23.08   |    92.32     |  15.48   | 24.15 | 567.14 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  43.88  | 6.70 | 20.57  | 19.45 |  77.79   |   19.97   |    79.89     |  15.29   | 22.79 | 508.04 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  44.04  | 7.62 | 19.29  | 20.78 |  83.13   |   21.36   |    85.43     |  13.44   | 22.71 | 512.68 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  43.43  | 6.57 | 19.49  | 20.52 |  82.08   |   21.08   |    84.31     |  15.58   | 23.03 | 516.81 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  43.25  | 6.61 | 20.05  | 19.95 |  79.79   |   20.49   |    81.95     |  15.48   | 23.12 | 530.93 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  43.62  | 6.77 | 19.66  | 20.36 |  81.42   |   20.90   |    83.61     |  15.13   | 22.92 | 519.35 |
| quad9_tex8_grey_quintic_bspline_direct                  |  51.18  | 6.54 | 26.12  | 15.32 |  61.27   |   15.73   |    62.93     |  15.65   | 19.54 | 427.24 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  45.79  | 6.74 | 22.31  | 17.93 |  71.71   |   18.42   |    73.66     |  15.20   | 21.84 | 482.93 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  21.45  | 3.94 | 10.08  | 39.71 |  158.83  |   41.09   |    164.37    |  52.01   | 46.63 | 300.70 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  27.71  | 4.21 | 15.82  | 25.30 |  101.20  |   26.18   |    104.71    |  48.68   | 36.09 | 220.00 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  27.92  | 4.35 | 15.92  | 25.13 |  100.52  |   26.00   |    104.00    |  47.03   | 35.81 | 215.16 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  25.85  | 4.07 | 14.57  | 27.46 |  109.85  |   28.42   |    113.68    |  50.37   | 38.68 | 232.25 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  29.19  | 4.13 | 18.01  | 22.21 |  88.85   |   22.98   |    91.93     |  49.54   | 34.26 | 203.56 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  28.00  | 4.17 | 15.06  | 26.56 |  106.22  |   27.48   |    109.92    |  49.17   | 35.72 | 225.11 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  33.55  | 3.84 | 21.27  | 18.90 |  75.60   |   19.55   |    78.21     |  53.32   | 29.81 | 168.42 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  30.41  | 3.81 | 18.35  | 21.80 |  87.18   |   22.56   |    90.23     |  53.73   | 32.88 | 199.46 |
| tri6_tex8_rgb_linear_direct                             |  58.18  | 9.20 | 25.91  | 15.44 |  61.76   |   15.87   |    63.47     |  22.26   | 17.19 | 262.85 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  59.79  | 9.57 | 27.52  | 14.54 |  58.14   |   14.93   |    59.74     |  21.39   | 16.73 | 247.10 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  60.07  | 9.08 | 28.38  | 14.15 |  56.59   |   14.54   |    58.15     |  22.56   | 16.65 | 244.74 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  62.36  | 9.29 | 28.21  | 14.18 |  56.74   |   14.58   |    58.31     |  22.05   | 16.04 | 235.65 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  67.92  | 10.43 | 31.67  | 12.63 |  50.52   |   12.98   |    51.92     |  19.64   | 14.73 | 207.98 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  61.07  | 9.42 | 27.13  | 14.75 |  58.98   |   15.16   |    60.62     |  21.74   | 16.37 | 253.05 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  69.35  | 9.91 | 34.98  | 11.44 |  45.75   |   11.75   |    47.01     |  20.70   | 14.43 | 207.25 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  66.76  | 9.75 | 31.63  | 12.65 |  50.58   |   13.00   |    51.99     |  21.01   | 14.99 | 220.09 |
| quad4ibi_tex8_rgb_linear_direct                         |  19.19  | 3.27 |  9.30  | 43.05 |  172.20  |   44.16   |    176.64    |  31.34   | 52.15 | 450.71 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  25.12  | 3.20 | 15.62  | 25.61 |  102.45  |   26.26   |    105.05    |  31.97   | 39.82 | 307.40 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  25.13  | 3.24 | 15.96  | 25.06 |  100.25  |   25.71   |    102.82    |  31.61   | 39.79 | 307.40 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  24.91  | 3.10 | 15.46  | 25.88 |  103.50  |   26.53   |    106.13    |  33.14   | 40.15 | 317.59 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  28.50  | 3.30 | 18.70  | 21.42 |  85.67   |   21.96   |    87.82     |  30.99   | 35.16 | 262.79 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  25.25  | 3.11 | 14.40  | 27.80 |  111.20  |   28.51   |    114.05    |  32.91   | 39.61 | 314.00 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  33.61  | 3.18 | 24.24  | 16.50 |  66.02   |   16.93   |    67.72     |  32.20   | 29.77 | 219.54 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  29.97  | 3.12 | 20.08  | 19.92 |  79.68   |   20.43   |    81.71     |  32.82   | 33.37 | 252.42 |
| quad4newton_tex8_rgb_linear_direct                      |  34.05  | 3.41 | 14.05  | 28.47 |  113.88  |   29.25   |    116.99    |  30.02   | 29.37 | 330.60 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  40.28  | 3.05 | 19.41  | 20.61 |  82.43   |   21.17   |    84.69     |  33.57   | 24.83 | 247.68 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  37.10  | 3.12 | 18.35  | 21.80 |  87.20   |   22.40   |    89.59     |  32.85   | 26.95 | 280.57 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  37.76  | 3.11 | 17.52  | 22.84 |  91.38   |   23.47   |    93.88     |  32.89   | 26.48 | 282.27 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  41.30  | 3.12 | 21.10  | 18.98 |  75.91   |   19.49   |    77.96     |  32.86   | 24.21 | 242.41 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  36.59  | 3.08 | 17.11  | 23.42 |  93.66   |   24.06   |    96.22     |  33.26   | 27.33 | 290.53 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  46.78  | 3.54 | 26.00  | 15.39 |  61.55   |   15.81   |    63.22     |  28.92   | 21.38 | 209.40 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  42.89  | 3.20 | 21.90  | 18.27 |  73.07   |   18.77   |    75.06     |  31.97   | 23.31 | 230.40 |
| quad8_tex8_rgb_linear_direct                            |  43.95  | 6.60 | 20.07  | 19.94 |  79.76   |   20.48   |    81.90     |  15.52   | 22.77 | 446.35 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  48.92  | 6.45 | 25.20  | 15.87 |  63.50   |   16.30   |    65.21     |  15.90   | 20.44 | 372.73 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  43.76  | 6.95 | 20.93  | 19.11 |  76.44   |   19.62   |    78.47     |  14.73   | 22.86 | 433.03 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.40  | 6.85 | 23.48  | 17.04 |  68.17   |   17.50   |    70.00     |  14.96   | 21.10 | 398.37 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  50.76  | 6.49 | 27.48  | 14.56 |  58.24   |   14.95   |    59.81     |  15.79   | 19.70 | 345.47 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  46.96  | 6.25 | 23.13  | 17.30 |  69.18   |   17.76   |    71.04     |  16.38   | 21.29 | 385.87 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  56.08  | 6.38 | 34.26  | 11.68 |  46.70   |   11.99   |    47.96     |  16.06   | 17.83 | 301.08 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  51.00  | 6.68 | 27.32  | 14.66 |  58.64   |   15.05   |    60.21     |  15.34   | 19.61 | 349.63 |
| quad9_tex8_rgb_linear_direct                            |  44.79  | 7.50 | 19.53  | 20.48 |  81.93   |   21.04   |    84.17     |  13.66   | 22.33 | 502.54 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  50.36  | 6.87 | 24.23  | 16.51 |  66.04   |   16.96   |    67.83     |  14.91   | 19.86 | 438.41 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  48.94  | 6.96 | 22.79  | 17.56 |  70.24   |   18.04   |    72.15     |  14.71   | 20.46 | 440.95 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  47.54  | 6.89 | 23.43  | 17.07 |  68.28   |   17.54   |    70.14     |  14.85   | 21.04 | 451.21 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  47.95  | 6.72 | 24.46  | 16.36 |  65.43   |   16.80   |    67.21     |  15.25   | 20.86 | 432.78 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  45.39  | 6.47 | 22.87  | 17.49 |  69.95   |   17.97   |    71.89     |  15.83   | 22.03 | 456.09 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  53.45  | 7.08 | 28.00  | 14.29 |  57.14   |   14.67   |    58.70     |  14.46   | 18.71 | 388.80 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  50.49  | 6.96 | 25.11  | 15.95 |  63.79   |   16.38   |    65.53     |  14.71   | 19.81 | 414.30 |

