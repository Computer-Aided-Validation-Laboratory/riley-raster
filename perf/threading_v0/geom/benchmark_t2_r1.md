# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  24.24  | 5.17 | 12.57  | 31.81 |  127.25  |   32.87   |    131.47    |  39.63   | 41.26 | 242.73 |
| tri6_nodal_grey                                         |  77.18  | 11.83 | 56.31  | 7.10  |  28.42   |   7.30    |    29.21     |  17.32   | 12.96 | 138.95 |
| quad4ibi_nodal_grey                                     |  23.54  | 3.71 | 16.33  | 24.49 |  97.98   |   25.08   |    100.33    |  27.61   | 42.49 | 298.75 |
| quad4newton_nodal_grey                                  |  37.03  | 3.35 | 27.42  | 14.59 |  58.36   |   14.99   |    59.94     |  30.56   | 27.07 | 195.99 |
| quad8_nodal_grey                                        |  59.22  | 8.18 | 43.82  | 9.13  |  36.51   |   9.36    |    37.46     |  12.51   | 16.89 | 239.54 |
| quad9_nodal_grey                                        |  57.63  | 8.55 | 41.86  | 9.56  |  38.22   |   9.81    |    39.26     |  11.97   | 17.35 | 280.96 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  26.92  | 5.43 | 15.33  | 26.10 |  104.39  |   26.96   |    107.85    |  37.71   | 37.16 | 207.93 |
| tri6_nodal_rgb                                          |  84.12  | 14.25 | 59.14  | 6.76  |  27.05   |   6.95    |    27.80     |  14.38   | 11.89 | 127.24 |
| quad4ibi_nodal_rgb                                      |  30.07  | 4.03 | 21.13  | 18.93 |  75.73   |   19.39   |    77.55     |  25.44   | 33.26 | 237.32 |
| quad4newton_nodal_rgb                                   |  39.40  | 4.03 | 30.32  | 13.19 |  52.77   |   13.55   |    54.20     |  25.43   | 25.39 | 178.09 |
| quad8_nodal_rgb                                         |  63.96  | 8.63 | 47.09  | 8.49  |  33.98   |   8.72    |    34.86     |  11.86   | 15.64 | 220.96 |
| quad9_nodal_rgb                                         |  63.35  | 9.31 | 46.20  | 8.66  |  34.63   |   8.89    |    35.57     |  11.00   | 15.79 | 251.83 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  34.58  | 5.28 | 21.16  | 18.90 |  75.61   |   19.53   |    78.11     |  38.76   | 28.92 | 173.61 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  48.73  | 4.68 | 36.65  | 10.91 |  43.65   |   11.28   |    45.10     |  43.78   | 20.52 | 113.47 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  44.26  | 4.55 | 32.09  | 12.46 |  49.86   |   12.88   |    51.51     |  45.06   | 22.59 | 126.51 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  44.60  | 5.03 | 32.24  | 12.41 |  49.63   |   12.82   |    51.27     |  40.72   | 22.42 | 126.20 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  50.73  | 4.82 | 39.10  | 10.23 |  40.92   |   10.57   |    42.28     |  42.47   | 19.71 | 107.24 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  44.45  | 4.95 | 32.22  | 12.41 |  49.65   |   12.82   |    51.30     |  41.34   | 22.50 | 125.80 |
| tri3_tex8_grey_quintic_bspline_direct                   |  67.19  | 4.89 | 54.20  | 7.38  |  29.53   |   7.63    |    30.50     |  41.87   | 14.88 | 78.95  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  52.29  | 4.99 | 38.88  | 10.29 |  41.16   |   10.63   |    42.53     |  41.06   | 19.12 | 105.15 |
| tri6_tex8_grey_linear_direct                            |  97.59  | 12.13 | 63.24  | 6.33  |  25.30   |   6.50    |    26.01     |  16.89   | 10.25 | 123.81 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 111.55  | 11.05 | 77.73  | 5.15  |  20.58   |   5.29    |    21.16     |  18.55   | 8.96 | 105.90 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 116.72  | 12.42 | 76.49  | 5.23  |  20.92   |   5.37    |    21.50     |  16.49   | 8.57 | 104.80 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 107.12  | 11.52 | 74.05  | 5.40  |  21.61   |   5.55    |    22.21     |  17.78   | 9.34 | 110.76 |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 115.34  | 11.79 | 81.09  | 4.93  |  19.73   |   5.07    |    20.28     |  17.38   | 8.67 | 102.05 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 107.28  | 11.95 | 73.53  | 5.44  |  21.76   |   5.59    |    22.36     |  17.16   | 9.32 | 111.07 |
| tri6_tex8_grey_quintic_bspline_direct                   | 127.34  | 11.74 | 94.08  | 4.25  |  17.01   |   4.37    |    17.48     |  17.45   | 7.85 | 89.84  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 112.12  | 11.67 | 78.63  | 5.09  |  20.35   |   5.23    |    20.91     |  17.55   | 8.92 | 104.58 |
| quad4ibi_tex8_grey_linear_direct                        |  29.26  | 3.48 | 21.36  | 18.73 |  74.92   |   19.18   |    76.72     |  29.41   | 34.17 | 251.45 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  44.47  | 3.21 | 36.88  | 10.85 |  43.39   |   11.11   |    44.43     |  31.96   | 22.49 | 155.75 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  46.72  | 3.06 | 37.65  | 10.63 |  42.50   |   10.88   |    43.52     |  33.45   | 21.40 | 152.64 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  46.22  | 3.09 | 37.97  | 10.54 |  42.14   |   10.79   |    43.15     |  33.10   | 21.64 | 151.38 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  53.74  | 3.08 | 46.05  | 8.69  |  34.75   |   8.90    |    35.58     |  33.27   | 18.61 | 126.82 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  46.40  | 3.33 | 38.02  | 10.52 |  42.09   |   10.77   |    43.10     |  30.78   | 21.55 | 149.89 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  65.06  | 4.21 | 55.65  | 7.19  |  28.75   |   7.36    |    29.44     |  24.39   | 15.37 | 105.82 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  55.35  | 2.93 | 46.31  | 8.64  |  34.55   |   8.85    |    35.38     |  34.92   | 18.07 | 125.20 |
| quad4newton_tex8_grey_linear_direct                     |  51.12  | 3.25 | 33.42  | 11.97 |  47.88   |   12.29   |    49.18     |  31.54   | 19.56 | 171.68 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  63.85  | 3.18 | 46.84  | 8.54  |  34.16   |   8.77    |    35.09     |  32.22   | 15.66 | 126.21 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  61.52  | 3.08 | 42.91  | 9.32  |  37.29   |   9.57    |    38.30     |  33.26   | 16.26 | 135.66 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  61.26  | 2.93 | 43.59  | 9.18  |  36.70   |   9.42    |    37.70     |  34.90   | 16.32 | 133.40 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  67.58  | 3.21 | 49.62  | 8.07  |  32.26   |   8.28    |    33.14     |  31.90   | 14.80 | 118.72 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  60.48  | 3.13 | 43.64  | 9.17  |  36.67   |   9.42    |    37.66     |  32.74   | 16.53 | 134.38 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  81.02  | 3.14 | 63.65  | 6.28  |  25.14   |   6.45    |    25.82     |  32.60   | 12.34 | 94.31  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  66.94  | 2.91 | 49.07  | 8.15  |  32.61   |   8.37    |    33.49     |  35.21   | 14.94 | 119.70 |
| quad8_tex8_grey_linear_direct                           |  74.45  | 7.93 | 50.50  | 7.92  |  31.68   |   8.13    |    32.51     |  12.93   | 13.43 | 213.94 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  87.93  | 8.27 | 64.37  | 6.21  |  24.86   |   6.38    |    25.50     |  12.38   | 11.37 | 174.69 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  85.28  | 7.74 | 61.58  | 6.50  |  25.98   |   6.66    |    26.66     |  13.23   | 11.73 | 181.82 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  86.23  | 8.01 | 61.97  | 6.46  |  25.82   |   6.62    |    26.49     |  12.79   | 11.60 | 180.17 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  90.49  | 7.56 | 67.41  | 5.93  |  23.73   |   6.09    |    24.35     |  13.54   | 11.05 | 168.86 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  85.82  | 8.20 | 61.93  | 6.46  |  25.84   |   6.63    |    26.51     |  12.49   | 11.65 | 179.75 |
| quad8_tex8_grey_quintic_bspline_direct                  | 105.83  | 8.32 | 82.26  | 4.86  |  19.45   |   4.99    |    19.96     |  12.30   | 9.45 | 140.27 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  92.71  | 8.48 | 67.51  | 5.92  |  23.70   |   6.08    |    24.32     |  12.08   | 10.79 | 166.88 |
| quad9_tex8_grey_linear_direct                           |  75.82  | 9.15 | 48.80  | 8.20  |  32.79   |   8.42    |    33.68     |  11.20   | 13.19 | 244.17 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  88.88  | 8.38 | 63.62  | 6.29  |  25.15   |   6.46    |    25.83     |  12.21   | 11.25 | 197.27 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  85.34  | 8.38 | 60.10  | 6.66  |  26.62   |   6.84    |    27.34     |  12.24   | 11.72 | 208.47 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  85.58  | 8.62 | 60.09  | 6.66  |  26.63   |   6.84    |    27.35     |  11.89   | 11.69 | 207.59 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  90.94  | 8.79 | 65.33  | 6.12  |  24.49   |   6.29    |    25.15     |  11.65   | 11.00 | 192.39 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  83.18  | 8.41 | 58.70  | 6.81  |  27.26   |   7.00    |    28.00     |  12.18   | 12.02 | 210.96 |
| quad9_tex8_grey_quintic_bspline_direct                  | 105.51  | 8.44 | 79.57  | 5.03  |  20.11   |   5.16    |    20.65     |  12.13   | 9.48 | 161.49 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  92.06  | 8.55 | 66.64  | 6.00  |  24.01   |   6.16    |    24.66     |  11.98   | 10.86 | 189.09 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  43.19  | 4.97 | 31.29  | 12.78 |  51.13   |   13.21   |    52.83     |  41.28   | 23.15 | 126.97 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  57.67  | 3.95 | 47.13  | 8.49  |  33.95   |   8.77    |    35.07     |  51.82   | 17.34 | 91.93  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  55.82  | 4.40 | 44.06  | 9.08  |  36.32   |   9.38    |    37.52     |  46.58   | 17.92 | 96.42  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  55.35  | 4.52 | 43.50  | 9.20  |  36.78   |   9.50    |    38.00     |  45.30   | 18.07 | 97.02  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  65.14  | 4.30 | 52.85  | 7.57  |  30.27   |   7.82    |    31.28     |  47.62   | 15.36 | 80.76  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  55.85  | 4.36 | 43.00  | 9.30  |  37.21   |   9.61    |    38.45     |  47.00   | 17.90 | 96.27  |
| tri3_tex8_rgb_quintic_bspline_direct                    |  80.36  | 4.32 | 68.33  | 5.85  |  23.42   |   6.05    |    24.19     |  47.40   | 12.44 | 64.16  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  67.89  | 4.57 | 55.39  | 7.22  |  28.89   |   7.46    |    29.84     |  44.95   | 14.73 | 77.20  |
| tri6_tex8_rgb_linear_direct                             | 112.91  | 11.69 | 78.16  | 5.12  |  20.47   |   5.26    |    21.04     |  17.52   | 8.86 | 104.94 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 127.15  | 12.46 | 90.86  | 4.40  |  17.61   |   4.52    |    18.10     |  16.44   | 7.86 | 90.80  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 124.25  | 13.08 | 87.34  | 4.58  |  18.32   |   4.71    |    18.83     |  15.65   | 8.05 | 93.24  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 123.84  | 12.76 | 86.82  | 4.61  |  18.43   |   4.74    |    18.94     |  16.06   | 8.08 | 93.93  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 133.10  | 12.61 | 97.40  | 4.11  |  16.43   |   4.22    |    16.88     |  16.24   | 7.51 | 84.90  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 122.97  | 12.50 | 86.97  | 4.60  |  18.40   |   4.73    |    18.91     |  16.39   | 8.13 | 94.21  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 147.65  | 11.97 | 111.66 | 3.58  |  14.33   |   3.68    |    14.73     |  17.11   | 6.77 | 76.49  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 133.85  | 11.32 | 98.23  | 4.07  |  16.29   |   4.19    |    16.74     |  18.09   | 7.47 | 86.58  |
| quad4ibi_tex8_rgb_linear_direct                         |  35.42  | 3.39 | 25.73  | 15.54 |  62.18   |   15.92   |    63.67     |  30.24   | 28.23 | 205.65 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  55.91  | 3.45 | 44.95  | 8.90  |  35.61   |   9.12    |    36.46     |  29.64   | 17.89 | 124.40 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  57.64  | 3.51 | 47.22  | 8.47  |  33.88   |   8.67    |    34.70     |  29.22   | 17.35 | 120.59 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  57.49  | 3.63 | 47.13  | 8.49  |  33.95   |   8.69    |    34.76     |  28.19   | 17.40 | 120.97 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  69.56  | 3.50 | 59.79  | 6.69  |  26.76   |   6.85    |    27.40     |  29.27   | 14.38 | 98.51  |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  57.00  | 3.42 | 47.07  | 8.50  |  33.99   |   8.70    |    34.81     |  29.94   | 17.55 | 121.45 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  83.69  | 3.44 | 73.78  | 5.42  |  21.69   |   5.55    |    22.21     |  29.75   | 11.95 | 81.04  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  68.86  | 3.75 | 58.81  | 6.80  |  27.21   |   6.97    |    27.86     |  27.30   | 14.52 | 99.37  |
| quad4newton_tex8_rgb_linear_direct                      |  65.18  | 3.49 | 46.00  | 8.70  |  34.79   |   8.93    |    35.73     |  29.35   | 15.34 | 123.51 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  78.14  | 3.66 | 58.61  | 6.83  |  27.30   |   7.01    |    28.04     |  27.99   | 12.80 | 100.30 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  73.35  | 3.34 | 54.39  | 7.35  |  29.42   |   7.55    |    30.21     |  30.66   | 13.63 | 106.66 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  76.46  | 3.60 | 54.86  | 7.29  |  29.16   |   7.49    |    29.96     |  28.42   | 13.08 | 105.54 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  83.56  | 3.46 | 64.70  | 6.18  |  24.73   |   6.35    |    25.40     |  29.62   | 11.97 | 91.71  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  75.14  | 3.58 | 54.72  | 7.31  |  29.24   |   7.51    |    30.04     |  28.62   | 13.31 | 105.11 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  99.08  | 3.48 | 79.41  | 5.04  |  20.15   |   5.17    |    20.69     |  29.46   | 10.09 | 75.11  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  82.36  | 3.31 | 63.67  | 6.28  |  25.13   |   6.45    |    25.81     |  31.01   | 12.14 | 92.96  |
| quad8_tex8_rgb_linear_direct                            |  87.76  | 8.76 | 62.11  | 6.44  |  25.76   |   6.61    |    26.43     |  11.68   | 11.39 | 177.88 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 100.61  | 8.77 | 75.81  | 5.28  |  21.11   |   5.41    |    21.65     |  11.67   | 9.94 | 149.74 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  99.05  | 8.26 | 72.83  | 5.49  |  21.97   |   5.64    |    22.54     |  12.40   | 10.10 | 154.95 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  96.93  | 8.84 | 72.40  | 5.52  |  22.10   |   5.67    |    22.67     |  11.62   | 10.32 | 154.88 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 107.24  | 7.41 | 82.83  | 4.83  |  19.32   |   4.96    |    19.82     |  13.83   | 9.33 | 139.36 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  96.26  | 8.32 | 71.62  | 5.59  |  22.34   |   5.73    |    22.92     |  12.32   | 10.39 | 156.94 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 121.04  | 7.27 | 97.43  | 4.11  |  16.42   |   4.21    |    16.85     |  14.10   | 8.26 | 120.22 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 108.26  | 8.06 | 83.08  | 4.81  |  19.26   |   4.94    |    19.76     |  12.70   | 9.24 | 138.17 |
| quad9_tex8_rgb_linear_direct                            |  87.52  | 8.53 | 59.60  | 6.71  |  26.85   |   6.89    |    27.57     |  12.01   | 11.43 | 204.57 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 | 103.28  | 9.00 | 74.02  | 5.40  |  21.62   |   5.55    |    22.20     |  11.38   | 9.68 | 169.10 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  94.41  | 7.47 | 70.56  | 5.67  |  22.68   |   5.82    |    23.29     |  13.71   | 10.59 | 179.31 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  98.31  | 8.79 | 69.71  | 5.74  |  22.95   |   5.89    |    23.57     |  11.67   | 10.17 | 177.10 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 106.84  | 7.99 | 81.00  | 4.94  |  19.75   |   5.07    |    20.29     |  12.83   | 9.36 | 158.27 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  98.30  | 8.47 | 70.68  | 5.66  |  22.64   |   5.81    |    23.25     |  12.09   | 10.17 | 177.47 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 119.17  | 8.14 | 93.91  | 4.26  |  17.04   |   4.37    |    17.50     |  12.58   | 8.39 | 138.26 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 104.90  | 7.86 | 81.41  | 4.91  |  19.65   |   5.05    |    20.19     |  13.03   | 9.53 | 158.91 |

