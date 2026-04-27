# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  7.92   | 0.17 |  3.84  | 104.04 |  416.16  |  104.04   |    416.16    |   0.01   | 127.37 | 850.08 |
| tri6_nodal_grey                                         |  14.24  | 0.20 | 11.20  | 35.72 |  142.88  |   35.72   |    142.88    |   0.01   | 70.24 | 764.89 |
| quad4ibi_nodal_grey                                     |  10.72  | 0.27 |  7.88  | 50.76 |  203.02  |   50.76   |    203.02    |   0.00   | 93.33 | 712.60 |
| quad4newton_nodal_grey                                  |  12.28  | 0.25 |  8.99  | 44.49 |  177.95  |   44.49   |    177.95    |   0.00   | 81.46 | 604.75 |
| quad8_nodal_grey                                        |  14.03  | 0.26 | 10.84  | 36.89 |  147.56  |   36.89   |    147.56    |   0.00   | 71.30 | 1044.02 |
| quad9_nodal_grey                                        |  14.24  | 0.30 | 11.20  | 35.73 |  142.92  |   35.73   |    142.92    |   0.00   | 70.23 | 1154.22 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  11.93  | 0.19 |  5.55  | 72.10 |  288.38  |   72.10   |    288.38    |   0.01   | 83.82 | 483.08 |
| tri6_nodal_rgb                                          |  16.26  | 0.16 | 12.14  | 32.96 |  131.82  |   32.96   |    131.82    |   0.01   | 61.51 | 670.11 |
| quad4ibi_nodal_rgb                                      |  13.53  | 0.23 |  9.81  | 40.79 |  163.16  |   40.79   |    163.16    |   0.00   | 73.94 | 542.65 |
| quad4newton_nodal_rgb                                   |  14.15  | 0.18 | 10.65  | 37.56 |  150.23  |   37.56   |    150.23    |   0.01   | 70.71 | 517.45 |
| quad8_nodal_rgb                                         |  16.50  | 0.20 | 12.35  | 32.39 |  129.55  |   32.39   |    129.55    |   0.00   | 60.69 | 901.66 |
| quad9_nodal_rgb                                         |  15.94  | 0.20 | 12.26  | 32.64 |  130.55  |   32.64   |    130.55    |   0.01   | 62.72 | 1012.48 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  11.12  | 0.23 |  7.76  | 51.55 |  206.22  |   51.55   |    206.22    |   0.01   | 89.92 | 519.24 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  17.76  | 0.20 | 14.59  | 27.41 |  109.65  |   27.41   |    109.65    |   0.01   | 56.31 | 298.42 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  15.35  | 0.22 | 12.49  | 32.04 |  128.14  |   32.04   |    128.14    |   0.01   | 65.14 | 352.09 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  15.15  | 0.16 | 12.42  | 32.21 |  128.83  |   32.21   |    128.83    |   0.01   | 66.01 | 360.67 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  19.17  | 0.20 | 15.56  | 25.71 |  102.84  |   25.71   |    102.84    |   0.01   | 52.21 | 284.96 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  15.69  | 0.21 | 12.77  | 31.33 |  125.33  |   31.33   |    125.33    |   0.01   | 63.73 | 345.48 |
| tri3_tex8_grey_quintic_bspline_direct                   |  25.62  | 0.18 | 22.71  | 17.61 |  70.45   |   17.61   |    70.45     |   0.01   | 39.03 | 202.58 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  18.56  | 0.22 | 15.66  | 25.55 |  102.18  |   25.55   |    102.18    |   0.01   | 53.87 | 287.69 |
| tri6_tex8_grey_linear_direct                            |  16.76  | 0.22 | 13.51  | 29.62 |  118.48  |   29.62   |    118.48    |   0.01   | 59.68 | 643.63 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  23.16  | 0.25 | 20.44  | 19.57 |  78.27   |   19.57   |    78.27     |   0.01   | 43.19 | 447.88 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  21.62  | 0.23 | 18.57  | 21.54 |  86.15   |   21.54   |    86.15     |   0.01   | 46.26 | 484.65 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  21.28  | 0.25 | 18.51  | 21.61 |  86.42   |   21.61   |    86.42     |   0.01   | 46.99 | 495.26 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  24.65  | 0.23 | 21.89  | 18.27 |  73.09   |   18.27   |    73.09     |   0.01   | 40.56 | 418.81 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  21.63  | 0.29 | 18.75  | 21.34 |  85.34   |   21.34   |    85.34     |   0.01   | 46.25 | 485.53 |
| tri6_tex8_grey_quintic_bspline_direct                   |  31.19  | 0.26 | 28.31  | 14.13 |  56.52   |   14.13   |    56.52     |   0.01   | 32.06 | 326.14 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  24.84  | 0.24 | 21.79  | 18.36 |  73.43   |   18.36   |    73.43     |   0.01   | 40.28 | 415.86 |
| quad4ibi_tex8_grey_linear_direct                        |  12.90  | 0.31 |  9.82  | 40.75 |  163.01  |   40.75   |    163.01    |   0.00   | 77.51 | 579.91 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  21.22  | 0.30 | 18.13  | 22.06 |  88.24   |   22.06   |    88.24     |   0.00   | 47.12 | 329.62 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  20.69  | 0.23 | 17.91  | 22.33 |  89.33   |   22.33   |    89.33     |   0.00   | 48.33 | 337.76 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  20.82  | 0.21 | 18.05  | 22.17 |  88.68   |   22.17   |    88.68     |   0.00   | 48.03 | 339.29 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  25.03  | 0.19 | 22.03  | 18.16 |  72.64   |   18.16   |    72.64     |   0.01   | 39.95 | 275.72 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  20.99  | 0.27 | 17.93  | 22.31 |  89.25   |   22.31   |    89.25     |   0.00   | 47.65 | 331.77 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  30.36  | 0.36 | 27.09  | 14.76 |  59.05   |   14.76   |    59.05     |   0.00   | 32.94 | 225.10 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  24.80  | 0.25 | 22.25  | 17.98 |  71.92   |   17.98   |    71.92     |   0.00   | 40.32 | 278.40 |
| quad4newton_tex8_grey_linear_direct                     |  13.99  | 0.23 | 10.85  | 36.85 |  147.41  |   36.85   |    147.41    |   0.00   | 71.46 | 523.11 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  22.38  | 0.28 | 18.44  | 21.69 |  86.78   |   21.69   |    86.78     |   0.00   | 44.73 | 313.90 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  19.20  | 0.19 | 16.48  | 24.28 |  97.13   |   24.28   |    97.13     |   0.01   | 52.07 | 366.36 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  18.96  | 0.21 | 16.11  | 24.83 |  99.32   |   24.83   |    99.32     |   0.00   | 52.75 | 374.33 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  22.44  | 0.19 | 19.48  | 20.54 |  82.14   |   20.54   |    82.14     |   0.01   | 44.56 | 309.24 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  19.10  | 0.22 | 16.37  | 24.43 |  97.72   |   24.43   |    97.72     |   0.00   | 52.36 | 368.00 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  30.34  | 0.28 | 26.45  | 15.12 |  60.50   |   15.12   |    60.50     |   0.00   | 32.96 | 230.72 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  22.87  | 0.30 | 19.72  | 20.28 |  81.14   |   20.28   |    81.14     |   0.00   | 43.73 | 302.73 |
| quad8_tex8_grey_linear_direct                           |  16.63  | 0.31 | 13.12  | 30.49 |  121.95  |   30.49   |    121.95    |   0.00   | 60.41 | 862.97 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  23.66  | 0.32 | 20.84  | 19.20 |  76.79   |   19.20   |    76.79     |   0.00   | 42.26 | 588.53 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  23.59  | 0.22 | 20.06  | 19.94 |  79.78   |   19.94   |    79.78     |   0.00   | 42.39 | 586.25 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  21.23  | 0.27 | 18.22  | 21.96 |  87.83   |   21.96   |    87.83     |   0.00   | 47.11 | 657.60 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  24.14  | 0.23 | 21.50  | 18.60 |  74.41   |   18.60   |    74.41     |   0.00   | 41.43 | 575.10 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  22.16  | 0.34 | 18.73  | 21.37 |  85.46   |   21.37   |    85.46     |   0.00   | 45.14 | 631.65 |
| quad8_tex8_grey_quintic_bspline_direct                  |  32.33  | 0.20 | 29.67  | 13.48 |  53.93   |   13.48   |    53.93     |   0.00   | 30.93 | 418.20 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  26.10  | 0.21 | 22.64  | 17.67 |  70.68   |   17.67   |    70.68     |   0.00   | 38.34 | 526.19 |
| quad9_tex8_grey_linear_direct                           |  17.18  | 0.24 | 14.23  | 28.13 |  112.51  |   28.13   |    112.51    |   0.00   | 58.20 | 933.60 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  23.76  | 0.20 | 21.17  | 18.90 |  75.60   |   18.90   |    75.60     |   0.00   | 42.09 | 655.09 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  22.73  | 0.29 | 19.48  | 20.56 |  82.25   |   20.56   |    82.25     |   0.00   | 44.04 | 695.80 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  21.66  | 0.28 | 18.48  | 21.65 |  86.60   |   21.65   |    86.60     |   0.00   | 46.18 | 735.33 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  24.98  | 0.23 | 22.14  | 18.07 |  72.29   |   18.07   |    72.29     |   0.00   | 40.03 | 620.52 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  22.18  | 0.24 | 19.06  | 20.98 |  83.93   |   20.98   |    83.93     |   0.00   | 45.09 | 703.85 |
| quad9_tex8_grey_quintic_bspline_direct                  |  31.34  | 0.22 | 28.83  | 13.87 |  55.49   |   13.87   |    55.49     |   0.00   | 31.91 | 487.19 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  25.20  | 0.32 | 21.81  | 18.34 |  73.35   |   18.34   |    73.35     |   0.00   | 39.70 | 615.66 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  15.11  | 0.16 |  9.70  | 41.23 |  164.93  |   41.23   |    164.93    |   0.01   | 66.27 | 359.59 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  24.18  | 0.20 | 18.72  | 21.37 |  85.50   |   21.37   |    85.50     |   0.01   | 41.40 | 219.58 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  21.82  | 0.15 | 18.27  | 21.90 |  87.60   |   21.90   |    87.60     |   0.01   | 45.83 | 238.86 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  20.73  | 0.17 | 16.86  | 23.72 |  94.88   |   23.72   |    94.88     |   0.01   | 48.23 | 252.88 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  25.50  | 0.15 | 21.75  | 18.40 |  73.58   |   18.40   |    73.58     |   0.01   | 39.22 | 202.67 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  21.80  | 0.15 | 17.60  | 22.73 |  90.91   |   22.73   |    90.91     |   0.01   | 45.88 | 238.87 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  32.77  | 0.16 | 28.99  | 13.80 |  55.19   |   13.80   |    55.19     |   0.01   | 30.52 | 155.57 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  27.17  | 0.16 | 23.21  | 17.24 |  68.95   |   17.24   |    68.95     |   0.01   | 36.80 | 189.76 |
| tri6_tex8_rgb_linear_direct                             |  22.99  | 0.23 | 18.76  | 21.32 |  85.28   |   21.32   |    85.28     |   0.01   | 43.51 | 454.38 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  29.40  | 0.18 | 25.38  | 15.76 |  63.04   |   15.76   |    63.04     |   0.01   | 34.01 | 347.88 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  28.12  | 0.20 | 24.26  | 16.49 |  65.96   |   16.49   |    65.96     |   0.01   | 35.57 | 365.14 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  31.09  | 0.21 | 25.99  | 15.41 |  61.65   |   15.41   |    61.65     |   0.01   | 32.16 | 326.69 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  32.48  | 0.19 | 28.52  | 14.03 |  56.11   |   14.03   |    56.11     |   0.01   | 30.78 | 314.99 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  26.92  | 0.22 | 22.98  | 17.41 |  69.62   |   17.41   |    69.62     |   0.01   | 37.15 | 380.65 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  41.32  | 0.19 | 37.11  | 10.78 |  43.12   |   10.78   |    43.12     |   0.01   | 24.20 | 242.64 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  31.90  | 0.19 | 28.11  | 14.23 |  56.92   |   14.23   |    56.92     |   0.01   | 31.36 | 318.52 |
| quad4ibi_tex8_rgb_linear_direct                         |  16.36  | 0.20 | 12.46  | 32.11 |  128.45  |   32.11   |    128.45    |   0.01   | 61.13 | 437.98 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  26.18  | 0.19 | 21.45  | 18.65 |  74.58   |   18.65   |    74.58     |   0.01   | 38.20 | 262.02 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  26.79  | 0.21 | 22.64  | 17.67 |  70.67   |   17.67   |    70.67     |   0.00   | 37.34 | 255.43 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  25.99  | 0.24 | 22.22  | 18.00 |  72.02   |   18.00   |    72.02     |   0.00   | 38.49 | 264.25 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  32.22  | 0.18 | 28.38  | 14.10 |  56.39   |   14.10   |    56.39     |   0.01   | 31.04 | 211.70 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  26.22  | 0.20 | 22.07  | 18.13 |  72.50   |   18.13   |    72.50     |   0.01   | 38.13 | 263.07 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  40.67  | 0.22 | 37.03  | 10.80 |  43.22   |   10.80   |    43.22     |   0.00   | 24.60 | 164.44 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  33.32  | 0.22 | 29.52  | 13.55 |  54.21   |   13.55   |    54.21     |   0.00   | 30.01 | 203.95 |
| quad4newton_tex8_rgb_linear_direct                      |  20.13  | 0.22 | 16.68  | 23.98 |  95.91   |   23.98   |    95.91     |   0.00   | 49.69 | 347.34 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  26.26  | 0.23 | 22.98  | 17.41 |  69.62   |   17.41   |    69.62     |   0.00   | 38.09 | 261.40 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  24.43  | 0.18 | 20.82  | 19.22 |  76.87   |   19.22   |    76.87     |   0.01   | 40.93 | 282.67 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  24.46  | 0.22 | 20.89  | 19.15 |  76.60   |   19.15   |    76.60     |   0.00   | 40.88 | 282.42 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  29.64  | 0.21 | 26.14  | 15.31 |  61.24   |   15.31   |    61.24     |   0.00   | 33.75 | 230.55 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  24.37  | 0.17 | 21.20  | 18.87 |  75.48   |   18.87   |    75.48     |   0.01   | 41.04 | 284.31 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  37.30  | 0.16 | 33.14  | 12.07 |  48.29   |   12.07   |    48.29     |   0.01   | 26.81 | 182.98 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  29.58  | 0.17 | 26.08  | 15.34 |  61.36   |   15.34   |    61.36     |   0.01   | 33.80 | 231.30 |
| quad8_tex8_rgb_linear_direct                            |  22.19  | 0.20 | 17.91  | 22.33 |  89.31   |   22.33   |    89.31     |   0.01   | 45.08 | 637.96 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  28.98  | 0.23 | 24.97  | 16.02 |  64.09   |   16.02   |    64.09     |   0.00   | 34.51 | 469.69 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  26.51  | 0.20 | 22.88  | 17.48 |  69.94   |   17.48   |    69.94     |   0.00   | 37.73 | 517.37 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  28.69  | 0.20 | 24.22  | 16.52 |  66.07   |   16.52   |    66.07     |   0.01   | 34.85 | 474.51 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  34.15  | 0.21 | 27.74  | 14.42 |  57.68   |   14.42   |    57.68     |   0.00   | 29.41 | 396.52 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  28.42  | 0.21 | 24.26  | 16.49 |  65.97   |   16.49   |    65.97     |   0.00   | 35.20 | 479.79 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  40.23  | 0.22 | 35.47  | 11.28 |  45.10   |   11.28   |    45.10     |   0.00   | 24.85 | 337.04 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  31.42  | 0.25 | 28.05  | 14.26 |  57.04   |   14.26   |    57.04     |   0.00   | 31.83 | 431.08 |
| quad9_tex8_rgb_linear_direct                            |  23.71  | 0.22 | 19.79  | 20.22 |  80.87   |   20.22   |    80.87     |   0.00   | 42.19 | 655.83 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  30.36  | 0.18 | 26.22  | 15.26 |  61.03   |   15.26   |    61.03     |   0.01   | 32.94 | 506.12 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  28.73  | 0.22 | 25.31  | 15.80 |  63.21   |   15.80   |    63.21     |   0.00   | 34.83 | 533.35 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  28.60  | 0.23 | 24.27  | 16.48 |  65.93   |   16.48   |    65.93     |   0.00   | 34.97 | 536.06 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  31.76  | 0.23 | 28.08  | 14.24 |  56.98   |   14.24   |    56.98     |   0.00   | 31.49 | 479.40 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  28.65  | 0.23 | 25.29  | 15.82 |  63.27   |   15.82   |    63.27     |   0.00   | 34.91 | 534.51 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  39.81  | 0.19 | 35.94  | 11.13 |  44.52   |   11.13   |    44.52     |   0.01   | 25.12 | 378.39 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  32.03  | 0.19 | 27.67  | 14.46 |  57.83   |   14.46   |    57.83     |   0.01   | 31.22 | 482.33 |

