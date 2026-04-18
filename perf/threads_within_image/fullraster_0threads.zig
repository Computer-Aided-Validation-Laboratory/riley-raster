# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  5.99   | 0.02 |  5.97  | 67.05 |  268.19  |   67.05   |    268.19    |   0.13   | 166.85 | 802.41 |
| tri6_nodal_grey                                         |  32.77  | 0.02 | 32.75  | 12.21 |  48.86   |   12.21   |    48.86     |   0.13   | 30.52 | 293.02 |
| quad4ibi_nodal_grey                                     |  18.76  | 0.01 | 18.74  | 21.34 |  85.36   |   21.34   |    85.36     |   0.07   | 53.30 | 341.22 |
| quad4newton_nodal_grey                                  |  25.83  | 0.01 | 25.81  | 15.50 |  61.99   |   15.50   |    61.99     |   0.09   | 38.72 | 247.86 |
| quad8_nodal_grey                                        |  32.61  | 0.01 | 32.59  | 12.27 |  49.09   |   12.27   |    49.09     |   0.08   | 30.66 | 392.56 |
| quad9_nodal_grey                                        |  33.23  | 0.01 | 33.21  | 12.04 |  48.18   |   12.04   |    48.18     |   0.08   | 30.09 | 433.40 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  12.16  | 0.01 | 12.14  | 32.94 |  131.75  |   32.94   |    131.75    |   0.15   | 82.20 | 394.81 |
| tri6_nodal_rgb                                          |  39.68  | 0.02 | 39.66  | 10.09 |  40.34   |   10.09   |    40.34     |   0.13   | 25.20 | 241.98 |
| quad4ibi_nodal_rgb                                      |  28.41  | 0.02 | 28.39  | 14.09 |  56.36   |   14.09   |    56.36     |   0.06   | 35.20 | 225.33 |
| quad4newton_nodal_rgb                                   |  32.25  | 0.01 | 32.22  | 12.41 |  49.65   |   12.41   |    49.65     |   0.07   | 31.01 | 198.50 |
| quad8_nodal_rgb                                         |  39.51  | 0.01 | 39.48  | 10.13 |  40.53   |   10.13   |    40.53     |   0.07   | 25.31 | 324.09 |
| quad9_nodal_rgb                                         |  40.29  | 0.01 | 40.26  | 9.93  |  39.74   |   9.93    |    39.74     |   0.08   | 24.82 | 357.49 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  18.46  | 0.02 | 18.44  | 21.69 |  86.77   |   21.69   |    86.77     |   0.13   | 54.17 | 260.11 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  46.94  | 0.01 | 46.92  | 8.52  |  34.10   |   8.52    |    34.10     |   0.15   | 21.30 | 102.27 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  35.29  | 0.02 | 35.27  | 11.34 |  45.36   |   11.34   |    45.36     |   0.13   | 28.34 | 136.03 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  35.70  | 0.01 | 35.68  | 11.21 |  44.85   |   11.21   |    44.85     |   0.15   | 28.01 | 134.49 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  48.41  | 0.01 | 48.39  | 8.27  |  33.07   |   8.27    |    33.07     |   0.14   | 20.66 | 99.17  |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  35.65  | 0.01 | 35.63  | 11.23 |  44.91   |   11.23   |    44.91     |   0.16   | 28.05 | 134.67 |
| tri3_tex8_grey_quintic_bspline_direct                   |  77.49  | 0.01 | 77.46  | 5.16  |  20.66   |   5.16    |    20.66     |   0.15   | 12.91 | 61.95  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  48.30  | 0.01 | 48.28  | 8.29  |  33.14   |   8.29    |    33.14     |   0.14   | 20.70 | 99.39  |
| tri6_tex8_grey_linear_direct                            |  41.18  | 0.01 | 41.15  | 9.72  |  38.88   |   9.72    |    38.88     |   0.14   | 24.29 | 233.18 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  68.13  | 0.02 | 68.10  | 5.87  |  23.49   |   5.87    |    23.49     |   0.12   | 14.68 | 140.92 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  60.63  | 0.02 | 60.60  | 6.60  |  26.40   |   6.60    |    26.40     |   0.11   | 16.49 | 158.37 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  60.51  | 0.01 | 60.49  | 6.61  |  26.45   |   6.61    |    26.45     |   0.13   | 16.53 | 158.67 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  73.01  | 0.02 | 72.99  | 5.48  |  21.92   |   5.48    |    21.92     |   0.11   | 13.70 | 131.50 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  60.13  | 0.02 | 60.11  | 6.65  |  26.62   |   6.65    |    26.62     |   0.12   | 16.63 | 159.67 |
| tri6_tex8_grey_quintic_bspline_direct                   |  99.38  | 0.02 | 99.36  | 4.03  |  16.10   |   4.03    |    16.10     |   0.12   | 10.06 | 96.60  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  72.51  | 0.02 | 72.48  | 5.52  |  22.07   |   5.52    |    22.07     |   0.13   | 13.79 | 132.42 |
| quad4ibi_tex8_grey_linear_direct                        |  26.74  | 0.01 | 26.71  | 14.97 |  59.89   |   14.97   |    59.89     |   0.09   | 37.40 | 239.45 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  60.53  | 0.01 | 60.51  | 6.61  |  26.44   |   6.61    |    26.44     |   0.08   | 16.52 | 105.74 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  60.04  | 0.01 | 60.02  | 6.66  |  26.66   |   6.66    |    26.66     |   0.08   | 16.65 | 106.60 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  59.94  | 0.01 | 59.92  | 6.68  |  26.70   |   6.68    |    26.70     |   0.08   | 16.68 | 106.79 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  72.03  | 0.01 | 72.00  | 5.56  |  22.22   |   5.56    |    22.22     |   0.08   | 13.88 | 88.86  |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  59.75  | 0.01 | 59.73  | 6.70  |  26.79   |   6.70    |    26.79     |   0.09   | 16.74 | 107.12 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  93.82  | 0.01 | 93.80  | 4.26  |  17.06   |   4.26    |    17.06     |   0.08   | 10.66 | 68.22  |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  71.94  | 0.02 | 71.91  | 5.56  |  22.25   |   5.56    |    22.25     |   0.06   | 13.90 | 88.97  |
| quad4newton_tex8_grey_linear_direct                     |  33.45  | 0.01 | 33.43  | 11.96 |  47.86   |   11.96   |    47.86     |   0.09   | 29.90 | 191.38 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  60.48  | 0.01 | 60.46  | 6.62  |  26.46   |   6.62    |    26.46     |   0.08   | 16.53 | 105.83 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  52.73  | 0.01 | 52.71  | 7.59  |  30.35   |   7.59    |    30.35     |   0.09   | 18.96 | 121.39 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  52.87  | 0.01 | 52.84  | 7.57  |  30.28   |   7.57    |    30.28     |   0.08   | 18.92 | 121.08 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  65.31  | 0.01 | 65.29  | 6.13  |  24.51   |   6.13    |    24.51     |   0.09   | 15.31 | 98.01  |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  52.73  | 0.01 | 52.71  | 7.59  |  30.36   |   7.59    |    30.36     |   0.08   | 18.97 | 121.40 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  91.73  | 0.01 | 91.70  | 4.36  |  17.45   |   4.36    |    17.45     |   0.08   | 10.90 | 69.78  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  65.37  | 0.01 | 65.35  | 6.12  |  24.48   |   6.12    |    24.48     |   0.09   | 15.30 | 97.92  |
| quad8_tex8_grey_linear_direct                           |  40.64  | 0.01 | 40.63  | 9.85  |  39.38   |   9.85    |    39.38     |   0.08   | 24.61 | 314.99 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  67.78  | 0.01 | 67.76  | 5.90  |  23.61   |   5.90    |    23.61     |   0.09   | 14.75 | 188.87 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  60.47  | 0.01 | 60.45  | 6.62  |  26.47   |   6.62    |    26.47     |   0.08   | 16.54 | 211.70 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  62.00  | 0.01 | 61.95  | 6.46  |  25.83   |   6.46    |    25.83     |   0.08   | 16.13 | 206.58 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  73.20  | 0.01 | 73.18  | 5.47  |  21.86   |   5.47    |    21.86     |   0.08   | 13.66 | 174.88 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  60.49  | 0.01 | 60.47  | 6.61  |  26.46   |   6.61    |    26.46     |   0.09   | 16.53 | 211.63 |
| quad8_tex8_grey_quintic_bspline_direct                  |  99.76  | 0.01 | 99.73  | 4.01  |  16.04   |   4.01    |    16.04     |   0.07   | 10.02 | 128.32 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  73.13  | 0.01 | 73.10  | 5.47  |  21.89   |   5.47    |    21.89     |   0.08   | 13.68 | 175.06 |
| quad9_tex8_grey_linear_direct                           |  41.20  | 0.01 | 41.18  | 9.71  |  38.85   |   9.71    |    38.85     |   0.08   | 24.27 | 349.57 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  68.54  | 0.01 | 68.52  | 5.84  |  23.35   |   5.84    |    23.35     |   0.08   | 14.59 | 210.12 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  60.71  | 0.01 | 60.69  | 6.59  |  26.36   |   6.59    |    26.36     |   0.08   | 16.47 | 237.21 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  60.70  | 0.01 | 60.68  | 6.59  |  26.37   |   6.59    |    26.37     |   0.08   | 16.47 | 237.26 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  73.33  | 0.01 | 73.31  | 5.46  |  21.83   |   5.46    |    21.83     |   0.07   | 13.64 | 196.39 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  60.68  | 0.01 | 60.66  | 6.59  |  26.38   |   6.59    |    26.38     |   0.07   | 16.48 | 237.35 |
| quad9_tex8_grey_quintic_bspline_direct                  | 100.25  | 0.01 | 100.23 | 3.99  |  15.96   |   3.99    |    15.96     |   0.09   | 9.98 | 143.65 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  73.33  | 0.01 | 73.30  | 5.46  |  21.83   |   5.46    |    21.83     |   0.08   | 13.64 | 196.39 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  30.94  | 0.02 | 30.92  | 12.94 |  51.75   |   12.94   |    51.75     |   0.11   | 32.32 | 155.18 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  63.64  | 0.01 | 63.61  | 6.29  |  25.15   |   6.29    |    25.15     |   0.15   | 15.71 | 75.44  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  57.87  | 0.02 | 57.85  | 6.91  |  27.66   |   6.91    |    27.66     |   0.13   | 17.28 | 82.96  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  57.75  | 0.01 | 57.72  | 6.93  |  27.72   |   6.93    |    27.72     |   0.14   | 17.32 | 83.13  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  74.73  | 0.01 | 74.71  | 5.35  |  21.42   |   5.35    |    21.42     |   0.14   | 13.38 | 64.24  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  57.59  | 0.01 | 57.56  | 6.95  |  27.80   |   6.95    |    27.80     |   0.14   | 17.36 | 83.36  |
| tri3_tex8_rgb_quintic_bspline_direct                    | 102.83  | 0.01 | 102.80 | 3.89  |  15.56   |   3.89    |    15.56     |   0.14   | 9.72 | 46.68  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  74.85  | 0.02 | 74.82  | 5.35  |  21.38   |   5.35    |    21.38     |   0.12   | 13.36 | 64.14  |
| tri6_tex8_rgb_linear_direct                             |  61.63  | 0.02 | 61.61  | 6.49  |  25.97   |   6.49    |    25.97     |   0.13   | 16.23 | 155.79 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  88.77  | 0.02 | 88.75  | 4.51  |  18.03   |   4.51    |    18.03     |   0.13   | 11.26 | 108.15 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  81.15  | 0.02 | 81.12  | 4.93  |  19.72   |   4.93    |    19.72     |   0.10   | 12.32 | 118.31 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  80.74  | 0.02 | 80.71  | 4.96  |  19.82   |   4.96    |    19.82     |   0.12   | 12.39 | 118.92 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  98.13  | 0.02 | 98.10  | 4.08  |  16.31   |   4.08    |    16.31     |   0.13   | 10.19 | 97.84  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  80.80  | 0.02 | 80.77  | 4.95  |  19.81   |   4.95    |    19.81     |   0.13   | 12.38 | 118.82 |
| tri6_tex8_rgb_quintic_bspline_direct                    | 126.84  | 0.02 | 126.81 | 3.15  |  12.62   |   3.15    |    12.62     |   0.12   | 7.88 | 75.69  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  98.21  | 0.02 | 98.18  | 4.07  |  16.30   |   4.07    |    16.30     |   0.13   | 10.18 | 97.76  |
| quad4ibi_tex8_rgb_linear_direct                         |  37.67  | 0.02 | 37.65  | 10.62 |  42.50   |   10.62   |    42.50     |   0.07   | 26.54 | 169.92 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  74.48  | 0.01 | 74.45  | 5.37  |  21.49   |   5.37    |    21.49     |   0.07   | 13.43 | 85.94  |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  73.05  | 0.02 | 73.02  | 5.48  |  21.91   |   5.48    |    21.91     |   0.06   | 13.69 | 87.63  |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  72.85  | 0.01 | 72.82  | 5.49  |  21.97   |   5.49    |    21.97     |   0.07   | 13.73 | 87.86  |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  97.50  | 0.02 | 97.48  | 4.10  |  16.41   |   4.10    |    16.41     |   0.06   | 10.26 | 65.65  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  72.69  | 0.01 | 72.67  | 5.50  |  22.02   |   5.50    |    22.02     |   0.07   | 13.76 | 88.06  |
| quad4ibi_tex8_rgb_quintic_bspline_direct                | 130.04  | 0.01 | 130.02 | 3.08  |  12.31   |   3.08    |    12.31     |   0.08   | 7.69 | 49.22  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  97.37  | 0.01 | 97.35  | 4.11  |  16.44   |   4.11    |    16.44     |   0.07   | 10.27 | 65.74  |
| quad4newton_tex8_rgb_linear_direct                      |  55.03  | 0.01 | 55.01  | 7.27  |  29.09   |   7.27    |    29.09     |   0.07   | 18.17 | 116.31 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  81.53  | 0.01 | 81.50  | 4.91  |  19.63   |   4.91    |    19.63     |   0.08   | 12.27 | 78.51  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  73.81  | 0.01 | 73.78  | 5.42  |  21.68   |   5.42    |    21.68     |   0.08   | 13.55 | 86.73  |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  73.71  | 0.01 | 73.68  | 5.43  |  21.72   |   5.43    |    21.72     |   0.07   | 13.57 | 86.85  |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  90.72  | 0.01 | 90.70  | 4.41  |  17.64   |   4.41    |    17.64     |   0.07   | 11.02 | 70.55  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  73.61  | 0.01 | 73.58  | 5.44  |  21.74   |   5.44    |    21.74     |   0.07   | 13.59 | 86.96  |
| quad4newton_tex8_rgb_quintic_bspline_direct             | 119.15  | 0.01 | 119.12 | 3.36  |  13.43   |   3.36    |    13.43     |   0.07   | 8.39 | 53.72  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  90.81  | 0.01 | 90.79  | 4.41  |  17.62   |   4.41    |    17.62     |   0.08   | 11.01 | 70.48  |
| quad8_tex8_rgb_linear_direct                            |  61.20  | 0.01 | 61.18  | 6.54  |  26.15   |   6.54    |    26.15     |   0.07   | 16.34 | 209.17 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  88.81  | 0.01 | 88.78  | 4.51  |  18.02   |   4.51    |    18.02     |   0.08   | 11.26 | 144.16 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  81.14  | 0.01 | 81.11  | 4.93  |  19.73   |   4.93    |    19.73     |   0.08   | 12.32 | 157.78 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  81.38  | 0.01 | 81.35  | 4.92  |  19.67   |   4.92    |    19.67     |   0.08   | 12.29 | 157.31 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  98.18  | 0.01 | 98.15  | 4.08  |  16.30   |   4.08    |    16.30     |   0.07   | 10.18 | 130.39 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  81.18  | 0.02 | 81.15  | 4.93  |  19.72   |   4.93    |    19.72     |   0.07   | 12.32 | 157.71 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 126.93  | 0.01 | 126.91 | 3.15  |  12.61   |   3.15    |    12.61     |   0.07   | 7.88 | 100.85 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  98.14  | 0.02 | 98.12  | 4.08  |  16.31   |   4.08    |    16.31     |   0.06   | 10.19 | 130.44 |
| quad9_tex8_rgb_linear_direct                            |  63.05  | 0.01 | 63.03  | 6.35  |  25.39   |   6.35    |    25.39     |   0.08   | 15.86 | 228.43 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  89.06  | 0.01 | 89.03  | 4.49  |  17.97   |   4.49    |    17.97     |   0.07   | 11.23 | 161.71 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  81.45  | 0.01 | 81.42  | 4.91  |  19.65   |   4.91    |    19.65     |   0.07   | 12.28 | 176.82 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  81.37  | 0.02 | 81.35  | 4.92  |  19.67   |   4.92    |    19.67     |   0.06   | 12.29 | 176.99 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  98.40  | 0.01 | 98.37  | 4.07  |  16.27   |   4.07    |    16.27     |   0.07   | 10.16 | 146.36 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  81.54  | 0.01 | 81.52  | 4.91  |  19.63   |   4.91    |    19.63     |   0.08   | 12.26 | 176.62 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 126.86  | 0.01 | 126.84 | 3.15  |  12.61   |   3.15    |    12.61     |   0.07   | 7.88 | 113.52 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  98.37  | 0.01 | 98.35  | 4.07  |  16.27   |   4.07    |    16.27     |   0.08   | 10.17 | 146.40 |

