# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  25.06  | 5.55 | 11.73  | 34.12 |  136.47  |   35.25   |    140.99    |  36.91   | 39.90 | 239.68 |
| tri6_nodal_grey                                         |  75.51  | 11.95 | 55.84  | 7.16  |  28.65   |   7.36    |    29.45     |  17.16   | 13.24 | 140.58 |
| quad4ibi_nodal_grey                                     |  23.21  | 3.75 | 16.22  | 24.67 |  98.67   |   25.26   |    101.04    |  27.31   | 43.08 | 307.46 |
| quad4newton_nodal_grey                                  |  32.90  | 3.12 | 26.66  | 15.00 |  60.01   |   15.41   |    61.63     |  32.81   | 30.40 | 209.86 |
| quad8_nodal_grey                                        |  59.76  | 8.16 | 44.35  | 9.02  |  36.07   |   9.25    |    37.01     |  12.55   | 16.74 | 238.65 |
| quad9_nodal_grey                                        |  56.32  | 8.56 | 41.06  | 9.74  |  38.97   |   10.01   |    40.02     |  11.96   | 17.76 | 284.54 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  28.15  | 6.26 | 15.46  | 25.87 |  103.50  |   26.73   |    106.93    |  32.78   | 35.53 | 196.85 |
| tri6_nodal_rgb                                          |  84.12  | 14.42 | 59.05  | 6.77  |  27.10   |   6.96    |    27.85     |  14.21   | 11.89 | 126.94 |
| quad4ibi_nodal_rgb                                      |  29.92  | 4.06 | 20.08  | 19.92 |  79.66   |   20.39   |    81.58     |  25.20   | 33.42 | 242.13 |
| quad4newton_nodal_rgb                                   |  38.56  | 3.86 | 30.04  | 13.32 |  53.27   |   13.68   |    54.71     |  26.53   | 25.94 | 181.22 |
| quad8_nodal_rgb                                         |  62.96  | 8.32 | 47.58  | 8.41  |  33.63   |   8.63    |    34.50     |  12.34   | 15.88 | 220.96 |
| quad9_nodal_rgb                                         |  64.50  | 10.13 | 45.27  | 8.84  |  35.35   |   9.08    |    36.30     |  10.11   | 15.50 | 252.09 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  34.79  | 5.34 | 21.53  | 18.57 |  74.30   |   19.19   |    76.76     |  38.42   | 28.77 | 170.76 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  48.63  | 5.11 | 35.75  | 11.19 |  44.75   |   11.56   |    46.23     |  40.05   | 20.56 | 114.20 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  44.44  | 4.91 | 32.19  | 12.42 |  49.70   |   12.84   |    51.35     |  41.72   | 22.50 | 127.35 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  45.38  | 5.34 | 32.21  | 12.42 |  49.68   |   12.83   |    51.33     |  38.36   | 22.03 | 124.37 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  51.78  | 5.09 | 38.87  | 10.29 |  41.16   |   10.63   |    42.53     |  40.25   | 19.31 | 106.45 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  44.31  | 4.90 | 31.65  | 12.64 |  50.55   |   13.06   |    52.23     |  41.84   | 22.57 | 126.97 |
| tri3_tex8_grey_quintic_bspline_direct                   |  65.25  | 4.94 | 53.75  | 7.44  |  29.77   |   7.69    |    30.76     |  41.50   | 15.33 | 81.47  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  51.27  | 5.22 | 38.26  | 10.45 |  41.82   |   10.80   |    43.20     |  39.22   | 19.51 | 107.63 |
| tri6_tex8_grey_linear_direct                            |  97.28  | 11.52 | 63.43  | 6.31  |  25.22   |   6.48    |    25.93     |  17.79   | 10.28 | 125.81 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 110.15  | 11.85 | 77.15  | 5.19  |  20.74   |   5.33    |    21.32     |  17.30   | 9.08 | 106.58 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 107.63  | 12.05 | 72.80  | 5.49  |  21.98   |   5.65    |    22.59     |  16.99   | 9.29 | 110.77 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 108.39  | 12.84 | 74.06  | 5.40  |  21.61   |   5.55    |    22.21     |  15.95   | 9.23 | 109.30 |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 112.41  | 11.72 | 79.45  | 5.03  |  20.14   |   5.17    |    20.70     |  17.48   | 8.90 | 104.26 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 107.52  | 12.03 | 74.88  | 5.34  |  21.37   |   5.49    |    21.96     |  17.03   | 9.30 | 109.05 |
| tri6_tex8_grey_quintic_bspline_direct                   | 127.65  | 12.24 | 93.13  | 4.30  |  17.18   |   4.41    |    17.66     |  16.74   | 7.83 | 90.47  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 111.60  | 11.21 | 79.43  | 5.04  |  20.14   |   5.18    |    20.70     |  18.27   | 8.96 | 105.18 |
| quad4ibi_tex8_grey_linear_direct                        |  29.73  | 3.61 | 21.37  | 18.71 |  74.86   |   19.16   |    76.66     |  28.46   | 33.63 | 249.43 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  45.39  | 3.51 | 36.75  | 10.88 |  43.53   |   11.14   |    44.58     |  29.21   | 22.03 | 153.97 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  45.18  | 3.42 | 36.95  | 10.82 |  43.30   |   11.08   |    44.34     |  30.05   | 22.13 | 153.75 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  47.13  | 3.32 | 38.46  | 10.40 |  41.61   |   10.65   |    42.61     |  30.88   | 21.22 | 148.07 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  55.07  | 3.34 | 46.35  | 8.63  |  34.52   |   8.84    |    35.35     |  30.62   | 18.16 | 125.89 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  46.76  | 3.31 | 37.50  | 10.67 |  42.67   |   10.92   |    43.70     |  30.91   | 21.39 | 150.34 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  63.41  | 3.22 | 55.62  | 7.19  |  28.77   |   7.37    |    29.46     |  31.83   | 15.77 | 106.59 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  53.83  | 3.42 | 45.47  | 8.80  |  35.19   |   9.01    |    36.04     |  29.93   | 18.58 | 127.63 |
| quad4newton_tex8_grey_linear_direct                     |  51.16  | 3.43 | 32.77  | 12.21 |  48.82   |   12.54   |    50.15     |  29.92   | 19.55 | 172.90 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  63.58  | 3.35 | 45.65  | 8.76  |  35.05   |   9.00    |    36.00     |  30.58   | 15.73 | 127.03 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  59.85  | 3.36 | 42.84  | 9.34  |  37.35   |   9.59    |    38.36     |  30.45   | 16.71 | 135.14 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  60.66  | 3.15 | 43.38  | 9.22  |  36.88   |   9.47    |    37.88     |  32.51   | 16.48 | 135.10 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  66.88  | 3.30 | 49.86  | 8.02  |  32.09   |   8.24    |    32.96     |  30.99   | 14.95 | 118.61 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  60.70  | 3.34 | 42.94  | 9.32  |  37.26   |   9.57    |    38.27     |  30.73   | 16.47 | 135.04 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  80.45  | 3.22 | 63.33  | 6.32  |  25.26   |   6.49    |    25.95     |  31.77   | 12.43 | 95.51  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  67.14  | 3.32 | 49.47  | 8.09  |  32.35   |   8.31    |    33.22     |  30.89   | 14.90 | 118.95 |
| quad8_tex8_grey_linear_direct                           |  72.17  | 7.31 | 49.35  | 8.11  |  32.42   |   8.32    |    33.27     |  14.02   | 13.86 | 220.45 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  87.87  | 8.00 | 64.15  | 6.24  |  24.94   |   6.40    |    25.59     |  12.80   | 11.38 | 174.88 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  85.03  | 8.21 | 60.62  | 6.60  |  26.39   |   6.77    |    27.08     |  12.48   | 11.76 | 183.78 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  82.76  | 7.85 | 60.69  | 6.59  |  26.37   |   6.76    |    27.05     |  13.05   | 12.08 | 185.59 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  91.71  | 8.09 | 68.12  | 5.87  |  23.49   |   6.02    |    24.10     |  12.65   | 10.90 | 165.44 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  84.55  | 8.37 | 60.58  | 6.60  |  26.41   |   6.77    |    27.10     |  12.24   | 11.83 | 183.17 |
| quad8_tex8_grey_quintic_bspline_direct                  | 105.44  | 8.26 | 81.12  | 4.93  |  19.72   |   5.06    |    20.24     |  12.40   | 9.48 | 141.44 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  91.95  | 8.48 | 66.84  | 5.98  |  23.94   |   6.14    |    24.56     |  12.07   | 10.88 | 165.80 |
| quad9_tex8_grey_linear_direct                           |  74.88  | 9.16 | 48.85  | 8.19  |  32.76   |   8.41    |    33.64     |  11.18   | 13.35 | 243.16 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  89.02  | 9.05 | 62.27  | 6.42  |  25.69   |   6.60    |    26.39     |  11.31   | 11.23 | 201.00 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  84.60  | 8.51 | 59.49  | 6.72  |  26.90   |   6.91    |    27.62     |  12.03   | 11.82 | 208.29 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  84.98  | 8.14 | 60.26  | 6.64  |  26.55   |   6.82    |    27.27     |  12.58   | 11.77 | 207.20 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  90.78  | 8.49 | 64.92  | 6.16  |  24.65   |   6.33    |    25.31     |  12.06   | 11.02 | 192.75 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  87.12  | 8.65 | 60.27  | 6.64  |  26.55   |   6.82    |    27.26     |  11.84   | 11.48 | 204.99 |
| quad9_tex8_grey_quintic_bspline_direct                  | 104.09  | 8.44 | 79.95  | 5.00  |  20.01   |   5.14    |    20.55     |  12.13   | 9.61 | 161.69 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  93.02  | 8.57 | 65.97  | 6.06  |  24.25   |   6.23    |    24.91     |  11.95   | 10.75 | 189.20 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  43.23  | 5.19 | 30.45  | 13.14 |  52.55   |   13.57   |    54.30     |  39.44   | 23.13 | 127.30 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  58.77  | 4.64 | 46.19  | 8.66  |  34.64   |   8.95    |    35.79     |  44.16   | 17.02 | 89.95  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  55.65  | 4.83 | 42.75  | 9.36  |  37.43   |   9.67    |    38.67     |  42.38   | 17.97 | 96.71  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  57.24  | 5.01 | 44.51  | 8.99  |  35.94   |   9.28    |    37.14     |  40.86   | 17.47 | 93.89  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  65.24  | 4.39 | 53.16  | 7.52  |  30.10   |   7.77    |    31.10     |  46.64   | 15.33 | 80.28  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  55.79  | 4.13 | 43.16  | 9.27  |  37.07   |   9.58    |    38.30     |  49.61   | 17.93 | 95.11  |
| tri3_tex8_rgb_quintic_bspline_direct                    |  77.99  | 4.37 | 66.77  | 5.99  |  23.96   |   6.19    |    24.76     |  46.87   | 12.82 | 66.20  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  65.13  | 4.53 | 53.60  | 7.46  |  29.85   |   7.71    |    30.84     |  45.23   | 15.35 | 80.83  |
| tri6_tex8_rgb_linear_direct                             | 112.55  | 12.60 | 77.05  | 5.19  |  20.77   |   5.34    |    21.34     |  16.26   | 8.88 | 105.36 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 125.75  | 13.19 | 89.78  | 4.46  |  17.82   |   4.58    |    18.32     |  15.54   | 7.95 | 91.50  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 123.01  | 12.96 | 88.33  | 4.53  |  18.11   |   4.65    |    18.62     |  15.81   | 8.13 | 93.86  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 123.43  | 12.45 | 86.24  | 4.64  |  18.55   |   4.77    |    19.07     |  16.45   | 8.10 | 94.99  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 132.50  | 13.07 | 96.05  | 4.16  |  16.66   |   4.28    |    17.12     |  15.68   | 7.55 | 85.96  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 124.00  | 12.64 | 86.48  | 4.63  |  18.50   |   4.75    |    19.02     |  16.21   | 8.06 | 94.55  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 148.75  | 12.89 | 111.39 | 3.59  |  14.36   |   3.69    |    14.76     |  15.89   | 6.72 | 76.26  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 133.06  | 12.46 | 96.57  | 4.14  |  16.57   |   4.26    |    17.03     |  16.43   | 7.52 | 86.88  |
| quad4ibi_tex8_rgb_linear_direct                         |  36.03  | 3.62 | 26.23  | 15.25 |  61.00   |   15.62   |    62.47     |  28.25   | 27.75 | 202.83 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  55.24  | 3.80 | 44.89  | 8.91  |  35.64   |   9.12    |    36.50     |  26.93   | 18.10 | 125.81 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  57.10  | 3.69 | 45.85  | 8.72  |  34.90   |   8.93    |    35.74     |  27.76   | 17.51 | 123.05 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  57.19  | 3.64 | 46.47  | 8.61  |  34.43   |   8.82    |    35.26     |  28.12   | 17.49 | 121.26 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  69.91  | 3.72 | 59.66  | 6.70  |  26.82   |   6.87    |    27.46     |  27.51   | 14.30 | 98.19  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  56.09  | 3.77 | 46.32  | 8.63  |  34.54   |   8.84    |    35.37     |  27.18   | 17.83 | 123.45 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  83.60  | 3.57 | 73.46  | 5.45  |  21.78   |   5.58    |    22.30     |  28.68   | 11.96 | 80.99  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  69.01  | 3.75 | 58.87  | 6.79  |  27.18   |   6.96    |    27.83     |  27.32   | 14.49 | 99.41  |
| quad4newton_tex8_rgb_linear_direct                      |  66.28  | 3.55 | 46.70  | 8.57  |  34.26   |   8.80    |    35.19     |  28.82   | 15.09 | 122.22 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  76.73  | 3.39 | 58.14  | 6.88  |  27.52   |   7.07    |    28.27     |  30.18   | 13.03 | 101.15 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  73.30  | 3.63 | 54.87  | 7.29  |  29.16   |   7.49    |    29.95     |  28.25   | 13.64 | 106.09 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  73.80  | 3.62 | 54.00  | 7.41  |  29.63   |   7.61    |    30.44     |  28.32   | 13.55 | 107.58 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  83.48  | 3.50 | 64.65  | 6.19  |  24.75   |   6.36    |    25.42     |  29.23   | 11.98 | 91.83  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  73.37  | 3.52 | 54.46  | 7.34  |  29.38   |   7.54    |    30.17     |  29.09   | 13.63 | 107.67 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  97.60  | 3.75 | 78.15  | 5.12  |  20.47   |   5.26    |    21.03     |  27.32   | 10.25 | 76.31  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  84.21  | 3.50 | 64.81  | 6.17  |  24.69   |   6.34    |    25.36     |  29.24   | 11.87 | 90.97  |
| quad8_tex8_rgb_linear_direct                            |  87.73  | 8.84 | 61.70  | 6.48  |  25.93   |   6.65    |    26.61     |  11.59   | 11.40 | 176.28 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  99.93  | 8.47 | 75.81  | 5.28  |  21.11   |   5.41    |    21.66     |  12.09   | 10.01 | 148.02 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  97.71  | 7.91 | 73.62  | 5.43  |  21.73   |   5.57    |    22.30     |  12.97   | 10.23 | 153.10 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  95.71  | 8.31 | 71.73  | 5.58  |  22.30   |   5.72    |    22.88     |  12.40   | 10.45 | 155.75 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 108.02  | 8.43 | 82.30  | 4.86  |  19.44   |   4.99    |    19.95     |  12.15   | 9.26 | 137.56 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  96.48  | 7.19 | 72.42  | 5.52  |  22.09   |   5.67    |    22.67     |  14.28   | 10.37 | 156.67 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 120.21  | 7.12 | 97.28  | 4.11  |  16.45   |   4.22    |    16.88     |  14.39   | 8.32 | 119.53 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 104.61  | 7.18 | 82.22  | 4.86  |  19.46   |   4.99    |    19.96     |  14.27   | 9.56 | 139.98 |
| quad9_tex8_rgb_linear_direct                            |  87.18  | 9.15 | 60.42  | 6.62  |  26.48   |   6.80    |    27.20     |  11.19   | 11.47 | 200.94 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 102.05  | 9.55 | 74.36  | 5.38  |  21.52   |   5.53    |    22.10     |  10.73   | 9.80 | 167.75 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  97.32  | 8.31 | 70.60  | 5.67  |  22.66   |   5.82    |    23.28     |  12.32   | 10.28 | 176.10 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  97.98  | 8.15 | 70.33  | 5.69  |  22.75   |   5.84    |    23.37     |  12.57   | 10.21 | 177.24 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 106.21  | 8.49 | 80.42  | 4.97  |  19.90   |   5.11    |    20.43     |  12.06   | 9.42 | 158.89 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  93.93  | 7.64 | 70.19  | 5.70  |  22.80   |   5.85    |    23.41     |  13.40   | 10.65 | 180.21 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 118.91  | 7.86 | 93.65  | 4.27  |  17.08   |   4.39    |    17.55     |  13.04   | 8.41 | 138.57 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 106.65  | 7.82 | 80.14  | 4.99  |  19.97   |   5.13    |    20.51     |  13.09   | 9.38 | 156.70 |

