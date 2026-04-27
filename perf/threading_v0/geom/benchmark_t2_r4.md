# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  23.40  | 5.12 | 11.49  | 34.81 |  139.23  |   35.96   |    143.84    |  40.00   | 42.74 | 256.16 |
| tri6_nodal_grey                                         |  73.83  | 10.69 | 55.36  | 7.23  |  28.90   |   7.43    |    29.71     |  19.16   | 13.55 | 144.12 |
| quad4ibi_nodal_grey                                     |  22.81  | 3.39 | 15.66  | 25.54 |  102.18  |   26.16   |    104.63    |  30.19   | 43.89 | 311.58 |
| quad4newton_nodal_grey                                  |  33.89  | 3.08 | 27.72  | 14.43 |  57.71   |   14.82   |    59.28     |  33.24   | 29.51 | 200.43 |
| quad8_nodal_grey                                        |  59.60  | 8.63 | 43.88  | 9.12  |  36.46   |   9.35    |    37.41     |  11.88   | 16.78 | 241.61 |
| quad9_nodal_grey                                        |  57.96  | 7.79 | 41.84  | 9.56  |  38.25   |   9.82    |    39.28     |  13.14   | 17.25 | 281.09 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  29.23  | 6.04 | 15.90  | 25.16 |  100.64  |   25.99   |    103.98    |  34.01   | 34.22 | 185.47 |
| tri6_nodal_rgb                                          |  85.11  | 14.61 | 58.37  | 6.85  |  27.41   |   7.04    |    28.18     |  14.02   | 11.75 | 128.31 |
| quad4ibi_nodal_rgb                                      |  30.27  | 3.92 | 20.80  | 19.23 |  76.92   |   19.69   |    78.77     |  26.13   | 33.04 | 239.57 |
| quad4newton_nodal_rgb                                   |  38.85  | 4.03 | 30.33  | 13.19 |  52.76   |   13.55   |    54.19     |  25.41   | 25.74 | 178.30 |
| quad8_nodal_rgb                                         |  66.95  | 9.98 | 48.35  | 8.27  |  33.09   |   8.49    |    33.95     |  10.26   | 14.94 | 214.52 |
| quad9_nodal_rgb                                         |  64.22  | 9.66 | 44.75  | 8.94  |  35.76   |   9.18    |    36.72     |  10.60   | 15.58 | 254.92 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  36.50  | 5.34 | 21.72  | 18.42 |  73.66   |   19.03   |    76.10     |  38.37   | 27.40 | 160.29 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  47.96  | 4.84 | 35.64  | 11.22 |  44.89   |   11.59   |    46.38     |  42.29   | 20.85 | 116.45 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  44.48  | 4.97 | 32.27  | 12.40 |  49.59   |   12.81   |    51.23     |  41.23   | 22.48 | 127.70 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  44.62  | 4.80 | 32.27  | 12.40 |  49.58   |   12.81   |    51.23     |  42.70   | 22.41 | 126.78 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  50.43  | 4.83 | 38.34  | 10.43 |  41.74   |   10.78   |    43.12     |  42.38   | 19.83 | 109.33 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  45.36  | 5.37 | 32.03  | 12.49 |  49.96   |   12.90   |    51.61     |  38.14   | 22.04 | 124.98 |
| tri3_tex8_grey_quintic_bspline_direct                   |  65.46  | 4.84 | 52.89  | 7.56  |  30.25   |   7.81    |    31.26     |  42.33   | 15.28 | 81.42  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  50.64  | 4.56 | 38.71  | 10.33 |  41.33   |   10.68   |    42.70     |  44.95   | 19.75 | 108.22 |
| tri6_tex8_grey_linear_direct                            |  96.28  | 11.82 | 62.99  | 6.35  |  25.40   |   6.53    |    26.11     |  17.33   | 10.39 | 127.14 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 109.67  | 11.41 | 76.68  | 5.22  |  20.86   |   5.36    |    21.44     |  17.95   | 9.12 | 107.79 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 107.40  | 11.72 | 73.31  | 5.46  |  21.82   |   5.61    |    22.43     |  17.49   | 9.31 | 111.43 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 107.86  | 12.15 | 73.77  | 5.42  |  21.69   |   5.57    |    22.29     |  16.85   | 9.27 | 109.26 |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 114.59  | 11.75 | 80.18  | 4.99  |  19.96   |   5.13    |    20.51     |  17.43   | 8.73 | 102.31 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 107.78  | 11.93 | 73.82  | 5.42  |  21.68   |   5.57    |    22.28     |  17.16   | 9.28 | 110.38 |
| tri6_tex8_grey_quintic_bspline_direct                   | 128.82  | 12.28 | 94.16  | 4.25  |  16.99   |   4.37    |    17.47     |  16.68   | 7.76 | 89.49  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 110.61  | 12.15 | 78.74  | 5.08  |  20.32   |   5.22    |    20.89     |  16.86   | 9.04 | 104.48 |
| quad4ibi_tex8_grey_linear_direct                        |  29.12  | 3.50 | 21.32  | 18.77 |  75.08   |   19.22   |    76.89     |  29.27   | 34.35 | 248.29 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  47.22  | 4.19 | 36.62  | 10.92 |  43.69   |   11.18   |    44.74     |  24.45   | 21.18 | 154.11 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  46.30  | 2.85 | 37.58  | 10.64 |  42.58   |   10.90   |    43.60     |  35.99   | 21.60 | 152.52 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  45.55  | 3.22 | 38.42  | 10.41 |  41.65   |   10.66   |    42.65     |  31.84   | 21.95 | 151.86 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  53.99  | 3.10 | 46.31  | 8.64  |  34.55   |   8.85    |    35.38     |  33.10   | 18.52 | 126.84 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  46.12  | 3.36 | 37.80  | 10.58 |  42.33   |   10.84   |    43.35     |  30.49   | 21.68 | 150.82 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  64.02  | 3.19 | 56.40  | 7.09  |  28.37   |   7.26    |    29.05     |  32.09   | 15.62 | 105.37 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  54.92  | 3.36 | 46.48  | 8.61  |  34.42   |   8.81    |    35.25     |  30.45   | 18.21 | 124.31 |
| quad4newton_tex8_grey_linear_direct                     |  52.37  | 3.42 | 34.21  | 11.69 |  46.77   |   12.01   |    48.04     |  29.93   | 19.09 | 164.83 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  64.33  | 3.24 | 45.89  | 8.72  |  34.86   |   8.95    |    35.81     |  31.64   | 15.54 | 127.30 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  60.15  | 3.12 | 42.50  | 9.41  |  37.65   |   9.67    |    38.67     |  32.86   | 16.62 | 137.01 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  62.17  | 3.00 | 43.31  | 9.24  |  36.95   |   9.49    |    37.95     |  34.12   | 16.09 | 133.46 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  66.02  | 3.06 | 49.19  | 8.13  |  32.53   |   8.35    |    33.41     |  33.45   | 15.15 | 119.59 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  60.42  | 2.98 | 42.59  | 9.39  |  37.57   |   9.65    |    38.58     |  34.41   | 16.55 | 134.16 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  81.21  | 3.16 | 63.79  | 6.27  |  25.08   |   6.44    |    25.76     |  32.50   | 12.31 | 94.19  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  68.23  | 3.58 | 48.75  | 8.20  |  32.82   |   8.43    |    33.71     |  28.68   | 14.66 | 120.84 |
| quad8_tex8_grey_linear_direct                           |  75.66  | 8.22 | 50.81  | 7.87  |  31.49   |   8.08    |    32.31     |  12.47   | 13.22 | 212.47 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  88.65  | 8.55 | 65.28  | 6.13  |  24.51   |   6.29    |    25.15     |  11.99   | 11.28 | 172.60 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  87.13  | 8.18 | 61.68  | 6.49  |  25.94   |   6.65    |    26.62     |  12.52   | 11.48 | 178.01 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  85.60  | 7.66 | 61.20  | 6.54  |  26.14   |   6.71    |    26.82     |  13.37   | 11.68 | 182.51 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  90.98  | 7.97 | 67.63  | 5.91  |  23.66   |   6.07    |    24.27     |  12.84   | 10.99 | 167.29 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  84.99  | 8.30 | 61.34  | 6.52  |  26.08   |   6.69    |    26.76     |  12.34   | 11.77 | 181.45 |
| quad8_tex8_grey_quintic_bspline_direct                  | 105.59  | 8.57 | 81.83  | 4.89  |  19.55   |   5.02    |    20.06     |  11.95   | 9.47 | 140.54 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  92.06  | 8.23 | 67.07  | 5.96  |  23.85   |   6.12    |    24.47     |  12.45   | 10.86 | 166.77 |
| quad9_tex8_grey_linear_direct                           |  74.72  | 8.19 | 48.39  | 8.27  |  33.06   |   8.49    |    33.96     |  12.51   | 13.38 | 249.12 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  88.97  | 7.89 | 62.29  | 6.42  |  25.69   |   6.60    |    26.38     |  12.98   | 11.24 | 198.52 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  85.69  | 8.90 | 59.43  | 6.73  |  26.92   |   6.91    |    27.65     |  11.52   | 11.67 | 206.43 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  85.99  | 8.55 | 59.75  | 6.69  |  26.78   |   6.88    |    27.50     |  11.97   | 11.63 | 207.54 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  91.96  | 8.76 | 65.96  | 6.06  |  24.26   |   6.23    |    24.91     |  11.69   | 10.87 | 190.28 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  85.12  | 8.81 | 59.81  | 6.69  |  26.75   |   6.87    |    27.47     |  11.62   | 11.75 | 206.61 |
| quad9_tex8_grey_quintic_bspline_direct                  | 103.45  | 8.18 | 79.56  | 5.03  |  20.11   |   5.16    |    20.66     |  12.52   | 9.67 | 163.48 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  92.65  | 8.73 | 66.83  | 5.99  |  23.94   |   6.15    |    24.59     |  11.73   | 10.79 | 188.95 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  43.95  | 4.88 | 30.81  | 12.99 |  51.94   |   13.42   |    53.66     |  41.98   | 22.75 | 126.46 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  60.63  | 4.74 | 46.05  | 8.69  |  34.75   |   8.97    |    35.90     |  43.25   | 16.49 | 90.24  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  58.71  | 4.68 | 44.05  | 9.08  |  36.32   |   9.38    |    37.53     |  43.76   | 17.03 | 95.14  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  57.17  | 4.70 | 43.15  | 9.27  |  37.08   |   9.58    |    38.31     |  43.60   | 17.50 | 95.80  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  65.83  | 4.36 | 52.84  | 7.57  |  30.28   |   7.82    |    31.28     |  46.99   | 15.19 | 81.46  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  57.61  | 4.83 | 42.58  | 9.39  |  37.58   |   9.71    |    38.82     |  42.40   | 17.36 | 95.37  |
| tri3_tex8_rgb_quintic_bspline_direct                    |  81.93  | 4.72 | 69.08  | 5.79  |  23.16   |   5.98    |    23.93     |  43.35   | 12.21 | 63.67  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  67.10  | 4.39 | 53.21  | 7.52  |  30.07   |   7.77    |    31.07     |  46.66   | 14.90 | 79.44  |
| tri6_tex8_rgb_linear_direct                             | 114.63  | 12.99 | 77.97  | 5.13  |  20.52   |   5.27    |    21.09     |  15.77   | 8.72 | 104.16 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 128.09  | 12.89 | 90.01  | 4.44  |  17.78   |   4.57    |    18.27     |  15.90   | 7.81 | 91.25  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 123.58  | 12.93 | 86.50  | 4.62  |  18.50   |   4.75    |    19.01     |  15.84   | 8.09 | 94.91  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 123.35  | 12.58 | 86.66  | 4.62  |  18.46   |   4.74    |    18.98     |  16.28   | 8.11 | 95.04  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 134.95  | 12.30 | 98.01  | 4.08  |  16.33   |   4.20    |    16.78     |  16.65   | 7.41 | 84.33  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 123.49  | 12.79 | 86.12  | 4.64  |  18.58   |   4.77    |    19.09     |  16.01   | 8.10 | 95.35  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 147.37  | 12.20 | 110.88 | 3.61  |  14.43   |   3.71    |    14.83     |  16.80   | 6.79 | 76.25  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 131.54  | 11.88 | 97.01  | 4.12  |  16.49   |   4.24    |    16.95     |  17.24   | 7.60 | 86.81  |
| quad4ibi_tex8_rgb_linear_direct                         |  36.67  | 3.54 | 26.14  | 15.30 |  61.20   |   15.67   |    62.67     |  28.92   | 27.27 | 201.52 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  55.06  | 3.41 | 45.01  | 8.89  |  35.55   |   9.10    |    36.40     |  30.07   | 18.16 | 127.25 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  57.28  | 3.65 | 46.86  | 8.54  |  34.15   |   8.74    |    34.97     |  28.07   | 17.46 | 121.34 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  57.29  | 3.58 | 47.74  | 8.38  |  33.52   |   8.58    |    34.32     |  28.61   | 17.46 | 120.78 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  68.67  | 3.65 | 59.01  | 6.78  |  27.12   |   6.94    |    27.77     |  28.06   | 14.56 | 99.65  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  57.69  | 3.76 | 46.87  | 8.53  |  34.14   |   8.74    |    34.96     |  27.27   | 17.33 | 120.75 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  84.57  | 3.64 | 74.35  | 5.38  |  21.52   |   5.51    |    22.04     |  28.14   | 11.83 | 79.82  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  69.22  | 3.52 | 59.56  | 6.72  |  26.86   |   6.88    |    27.51     |  29.09   | 14.45 | 98.62  |
| quad4newton_tex8_rgb_linear_direct                      |  64.34  | 3.39 | 44.79  | 8.93  |  35.72   |   9.17    |    36.69     |  30.23   | 15.54 | 127.02 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  79.10  | 3.67 | 59.36  | 6.74  |  26.96   |   6.92    |    27.69     |  27.88   | 12.64 | 98.43  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  74.42  | 3.45 | 54.15  | 7.39  |  29.55   |   7.59    |    30.35     |  29.69   | 13.44 | 106.54 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  75.75  | 3.67 | 55.16  | 7.25  |  29.00   |   7.45    |    29.79     |  27.90   | 13.20 | 105.83 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  83.81  | 3.43 | 63.66  | 6.28  |  25.13   |   6.45    |    25.81     |  29.86   | 11.93 | 92.39  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  74.36  | 3.37 | 55.29  | 7.24  |  28.94   |   7.43    |    29.73     |  30.43   | 13.45 | 106.12 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  97.89  | 3.57 | 79.60  | 5.03  |  20.10   |   5.16    |    20.65     |  28.66   | 10.22 | 75.77  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  85.12  | 3.53 | 64.71  | 6.18  |  24.73   |   6.35    |    25.40     |  29.05   | 11.75 | 89.76  |
| quad8_tex8_rgb_linear_direct                            |  88.41  | 8.89 | 61.56  | 6.50  |  25.99   |   6.67    |    26.67     |  11.52   | 11.31 | 174.03 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 101.49  | 7.98 | 75.78  | 5.28  |  21.11   |   5.42    |    21.66     |  12.85   | 9.85 | 150.08 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  94.09  | 7.44 | 71.97  | 5.56  |  22.23   |   5.70    |    22.81     |  13.80   | 10.63 | 157.41 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  98.95  | 7.47 | 72.50  | 5.52  |  22.07   |   5.66    |    22.64     |  13.71   | 10.11 | 155.79 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 108.47  | 8.70 | 82.33  | 4.86  |  19.43   |   4.98    |    19.94     |  11.77   | 9.22 | 136.36 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  96.72  | 7.76 | 73.47  | 5.44  |  21.78   |   5.59    |    22.34     |  13.20   | 10.34 | 154.89 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 120.42  | 7.20 | 98.20  | 4.07  |  16.29   |   4.18    |    16.72     |  14.23   | 8.30 | 119.33 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 106.27  | 7.92 | 82.69  | 4.84  |  19.35   |   4.96    |    19.85     |  12.93   | 9.41 | 138.69 |
| quad9_tex8_rgb_linear_direct                            |  88.41  | 8.42 | 60.94  | 6.56  |  26.26   |   6.74    |    26.97     |  12.16   | 11.31 | 199.00 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 102.12  | 8.64 | 74.95  | 5.34  |  21.35   |   5.48    |    21.93     |  11.85   | 9.79 | 169.68 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  94.55  | 7.74 | 70.17  | 5.70  |  22.80   |   5.85    |    23.42     |  13.23   | 10.58 | 179.97 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  96.03  | 7.80 | 71.22  | 5.62  |  22.46   |   5.77    |    23.07     |  13.16   | 10.41 | 179.79 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 106.92  | 8.12 | 82.87  | 4.83  |  19.31   |   4.96    |    19.83     |  12.61   | 9.35 | 154.77 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  94.26  | 7.39 | 69.85  | 5.73  |  22.91   |   5.88    |    23.53     |  13.86   | 10.61 | 180.40 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 120.75  | 7.85 | 94.78  | 4.22  |  16.88   |   4.33    |    17.34     |  13.06   | 8.28 | 136.94 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 106.27  | 8.15 | 80.91  | 4.94  |  19.78   |   5.08    |    20.31     |  12.57   | 9.41 | 159.00 |

