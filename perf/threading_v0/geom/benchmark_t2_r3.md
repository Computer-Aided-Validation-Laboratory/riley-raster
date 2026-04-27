# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  24.67  | 5.79 | 11.91  | 33.59 |  134.36  |   34.70   |    138.81    |  35.37   | 40.54 | 245.68 |
| tri6_nodal_grey                                         |  74.98  | 11.15 | 55.12  | 7.26  |  29.03   |   7.46    |    29.84     |  18.38   | 13.34 | 143.00 |
| quad4ibi_nodal_grey                                     |  21.81  | 3.87 | 15.64  | 25.58 |  102.34  |   26.20   |    104.80    |  26.48   | 45.84 | 321.92 |
| quad4newton_nodal_grey                                  |  33.65  | 3.19 | 26.77  | 14.94 |  59.77   |   15.35   |    61.39     |  32.12   | 29.72 | 206.11 |
| quad8_nodal_grey                                        |  58.89  | 7.71 | 43.82  | 9.13  |  36.51   |   9.37    |    37.46     |  13.29   | 16.98 | 241.16 |
| quad9_nodal_grey                                        |  57.57  | 8.47 | 41.99  | 9.53  |  38.11   |   9.78    |    39.14     |  12.10   | 17.37 | 276.53 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  29.04  | 5.81 | 15.42  | 25.94 |  103.76  |   26.80   |    107.20    |  35.26   | 34.45 | 192.64 |
| tri6_nodal_rgb                                          |  84.39  | 14.06 | 58.21  | 6.87  |  27.49   |   7.06    |    28.25     |  14.57   | 11.85 | 129.01 |
| quad4ibi_nodal_rgb                                      |  29.94  | 4.28 | 20.23  | 19.77 |  79.09   |   20.25   |    80.99     |  23.91   | 33.40 | 242.21 |
| quad4newton_nodal_rgb                                   |  39.41  | 3.90 | 30.31  | 13.20 |  52.79   |   13.55   |    54.22     |  26.23   | 25.38 | 176.34 |
| quad8_nodal_rgb                                         |  64.50  | 8.90 | 47.84  | 8.36  |  33.44   |   8.58    |    34.31     |  11.51   | 15.50 | 217.44 |
| quad9_nodal_rgb                                         |  64.09  | 9.77 | 44.90  | 8.91  |  35.63   |   9.15    |    36.60     |  10.49   | 15.60 | 252.45 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  33.97  | 5.07 | 21.38  | 18.71 |  74.84   |   19.33   |    77.32     |  40.42   | 29.44 | 174.75 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  49.29  | 5.27 | 36.12  | 11.07 |  44.30   |   11.44   |    45.76     |  38.83   | 20.29 | 112.46 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  44.79  | 5.05 | 32.00  | 12.50 |  50.00   |   12.91   |    51.66     |  40.56   | 22.33 | 126.25 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  45.44  | 5.21 | 32.28  | 12.39 |  49.56   |   12.80   |    51.20     |  39.33   | 22.01 | 124.83 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  50.95  | 5.07 | 38.27  | 10.45 |  41.81   |   10.80   |    43.19     |  40.36   | 19.63 | 108.10 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  46.13  | 5.58 | 31.46  | 12.72 |  50.86   |   13.14   |    52.55     |  36.68   | 21.68 | 127.78 |
| tri3_tex8_grey_quintic_bspline_direct                   |  65.71  | 5.27 | 52.24  | 7.66  |  30.63   |   7.91    |    31.64     |  38.85   | 15.22 | 82.46  |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  51.53  | 5.14 | 39.36  | 10.16 |  40.65   |   10.50   |    41.99     |  39.85   | 19.40 | 106.28 |
| tri6_tex8_grey_linear_direct                            |  96.57  | 11.58 | 62.34  | 6.42  |  25.67   |   6.59    |    26.38     |  17.68   | 10.36 | 128.20 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 | 110.06  | 11.63 | 76.45  | 5.23  |  20.93   |   5.38    |    21.51     |  17.61   | 9.09 | 107.89 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               | 106.57  | 12.75 | 73.00  | 5.48  |  21.92   |   5.63    |    22.53     |  16.06   | 9.38 | 111.32 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        | 108.33  | 11.97 | 73.56  | 5.44  |  21.75   |   5.59    |    22.36     |  17.11   | 9.23 | 110.93 |
| tri6_tex8_grey_lanczos3_lut_lerp                        | 114.08  | 12.68 | 80.23  | 4.99  |  19.94   |   5.12    |    20.50     |  16.15   | 8.77 | 102.41 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   | 107.26  | 11.96 | 73.69  | 5.43  |  21.71   |   5.58    |    22.32     |  17.12   | 9.32 | 110.80 |
| tri6_tex8_grey_quintic_bspline_direct                   | 126.36  | 11.53 | 93.51  | 4.28  |  17.11   |   4.40    |    17.59     |  17.76   | 7.91 | 90.63  |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 | 112.84  | 12.55 | 79.98  | 5.00  |  20.00   |   5.14    |    20.56     |  16.32   | 8.86 | 103.22 |
| quad4ibi_tex8_grey_linear_direct                        |  29.05  | 3.75 | 20.56  | 19.45 |  77.82   |   19.92   |    79.69     |  27.30   | 34.42 | 250.16 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  44.22  | 3.31 | 36.45  | 10.97 |  43.90   |   11.24   |    44.95     |  30.94   | 22.61 | 157.22 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  45.83  | 3.38 | 37.43  | 10.69 |  42.75   |   10.94   |    43.78     |  30.27   | 21.82 | 153.41 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  47.04  | 3.96 | 37.76  | 10.59 |  42.38   |   10.85   |    43.40     |  26.36   | 21.26 | 151.44 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  55.31  | 3.31 | 46.67  | 8.57  |  34.29   |   8.78    |    35.11     |  30.91   | 18.08 | 125.44 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  45.30  | 3.11 | 37.03  | 10.81 |  43.22   |   11.06   |    44.26     |  32.95   | 22.08 | 153.41 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  63.20  | 3.52 | 54.68  | 7.31  |  29.26   |   7.49    |    29.96     |  29.11   | 15.82 | 107.65 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  55.60  | 3.45 | 46.37  | 8.63  |  34.51   |   8.83    |    35.33     |  29.73   | 17.99 | 123.61 |
| quad4newton_tex8_grey_linear_direct                     |  50.94  | 3.24 | 33.20  | 12.05 |  48.19   |   12.37   |    49.50     |  31.60   | 19.63 | 170.87 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  63.94  | 3.27 | 46.28  | 8.64  |  34.58   |   8.88    |    35.52     |  31.30   | 15.64 | 125.73 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  60.78  | 3.23 | 42.76  | 9.35  |  37.42   |   9.61    |    38.43     |  31.74   | 16.45 | 135.99 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  60.29  | 3.29 | 43.06  | 9.29  |  37.16   |   9.54    |    38.17     |  31.11   | 16.59 | 134.47 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  67.98  | 3.29 | 49.26  | 8.12  |  32.48   |   8.34    |    33.36     |  31.12   | 14.71 | 118.75 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  61.68  | 3.37 | 43.30  | 9.24  |  36.96   |   9.49    |    37.96     |  30.40   | 16.21 | 132.53 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  81.45  | 3.28 | 64.07  | 6.24  |  24.97   |   6.41    |    25.65     |  31.19   | 12.28 | 93.56  |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  65.58  | 3.07 | 48.35  | 8.27  |  33.09   |   8.50    |    33.99     |  33.35   | 15.25 | 121.93 |
| quad8_tex8_grey_linear_direct                           |  74.13  | 8.18 | 50.31  | 7.95  |  31.80   |   8.16    |    32.63     |  12.51   | 13.49 | 214.15 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  88.03  | 8.24 | 63.65  | 6.28  |  25.14   |   6.45    |    25.79     |  12.43   | 11.36 | 174.87 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  84.58  | 8.21 | 60.88  | 6.57  |  26.28   |   6.74    |    26.96     |  12.48   | 11.82 | 182.58 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  86.26  | 8.62 | 61.94  | 6.46  |  25.83   |   6.63    |    26.50     |  11.88   | 11.59 | 178.21 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  92.78  | 8.25 | 68.65  | 5.83  |  23.31   |   5.98    |    23.91     |  12.41   | 10.78 | 163.98 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  85.41  | 7.83 | 60.97  | 6.56  |  26.24   |   6.73    |    26.93     |  13.07   | 11.71 | 183.38 |
| quad8_tex8_grey_quintic_bspline_direct                  | 105.08  | 8.34 | 81.28  | 4.92  |  19.68   |   5.05    |    20.20     |  12.28   | 9.52 | 141.96 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  92.92  | 8.11 | 68.28  | 5.86  |  23.43   |   6.01    |    24.04     |  12.63   | 10.76 | 165.46 |
| quad9_tex8_grey_linear_direct                           |  73.79  | 8.53 | 47.74  | 8.38  |  33.52   |   8.61    |    34.42     |  12.00   | 13.55 | 249.35 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  88.12  | 8.58 | 63.04  | 6.35  |  25.39   |   6.52    |    26.07     |  11.94   | 11.35 | 196.87 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  85.64  | 8.39 | 60.22  | 6.64  |  26.57   |   6.82    |    27.29     |  12.21   | 11.68 | 204.89 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  84.99  | 8.53 | 59.55  | 6.72  |  26.87   |   6.90    |    27.59     |  12.01   | 11.77 | 208.35 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  91.12  | 9.10 | 65.32  | 6.12  |  24.50   |   6.29    |    25.16     |  11.25   | 10.97 | 190.70 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  85.86  | 8.55 | 60.45  | 6.62  |  26.47   |   6.80    |    27.18     |  11.98   | 11.65 | 205.38 |
| quad9_tex8_grey_quintic_bspline_direct                  | 105.60  | 8.96 | 80.05  | 5.00  |  19.99   |   5.13    |    20.53     |  11.44   | 9.47 | 159.03 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  92.41  | 9.01 | 65.88  | 6.07  |  24.29   |   6.24    |    24.94     |  11.36   | 10.82 | 190.23 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  42.62  | 4.84 | 30.61  | 13.07 |  52.28   |   13.50   |    54.01     |  42.30   | 23.46 | 128.02 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  58.36  | 4.71 | 45.33  | 8.82  |  35.30   |   9.12    |    36.47     |  43.47   | 17.13 | 91.05  |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  56.76  | 4.78 | 43.74  | 9.14  |  36.58   |   9.45    |    37.79     |  42.81   | 17.62 | 95.39  |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  55.20  | 4.49 | 42.43  | 9.43  |  37.71   |   9.74    |    38.96     |  45.67   | 18.12 | 97.77  |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  64.51  | 4.57 | 52.73  | 7.59  |  30.35   |   7.84    |    31.35     |  44.84   | 15.50 | 81.39  |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  54.71  | 4.31 | 43.28  | 9.24  |  36.97   |   9.55    |    38.19     |  47.58   | 18.28 | 97.25  |
| tri3_tex8_rgb_quintic_bspline_direct                    |  78.91  | 4.45 | 66.93  | 5.98  |  23.91   |   6.17    |    24.70     |  46.02   | 12.67 | 65.38  |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  65.32  | 4.88 | 52.85  | 7.57  |  30.28   |   7.82    |    31.28     |  41.98   | 15.31 | 80.56  |
| tri6_tex8_rgb_linear_direct                             | 114.08  | 13.48 | 77.40  | 5.17  |  20.67   |   5.31    |    21.25     |  15.21   | 8.77 | 103.92 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  | 128.42  | 12.97 | 89.71  | 4.46  |  17.84   |   4.58    |    18.33     |  15.80   | 7.79 | 91.39  |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                | 122.44  | 12.66 | 86.07  | 4.65  |  18.59   |   4.78    |    19.11     |  16.17   | 8.17 | 95.44  |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         | 122.93  | 12.50 | 86.48  | 4.63  |  18.50   |   4.75    |    19.02     |  16.38   | 8.14 | 94.63  |
| tri6_tex8_rgb_lanczos3_lut_lerp                         | 134.20  | 13.56 | 96.99  | 4.12  |  16.50   |   4.24    |    16.96     |  15.11   | 7.45 | 84.60  |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    | 122.48  | 14.00 | 85.45  | 4.68  |  18.73   |   4.81    |    19.25     |  14.63   | 8.16 | 95.15  |
| tri6_tex8_rgb_quintic_bspline_direct                    | 148.79  | 13.15 | 112.48 | 3.56  |  14.23   |   3.66    |    14.62     |  15.58   | 6.72 | 74.86  |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  | 134.21  | 13.17 | 97.17  | 4.12  |  16.47   |   4.23    |    16.92     |  15.55   | 7.45 | 85.07  |
| quad4ibi_tex8_rgb_linear_direct                         |  35.82  | 3.62 | 25.62  | 15.61 |  62.44   |   15.98   |    63.94     |  28.30   | 27.92 | 206.80 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  55.28  | 3.62 | 44.63  | 8.96  |  35.85   |   9.18    |    36.71     |  28.26   | 18.09 | 125.88 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  56.66  | 3.73 | 46.67  | 8.57  |  34.29   |   8.78    |    35.11     |  27.43   | 17.65 | 122.23 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  56.15  | 3.85 | 46.02  | 8.69  |  34.77   |   8.90    |    35.60     |  26.59   | 17.81 | 123.89 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  67.77  | 3.63 | 58.32  | 6.86  |  27.44   |   7.02    |    28.10     |  28.24   | 14.76 | 100.77 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  56.79  | 3.82 | 45.96  | 8.70  |  34.82   |   8.91    |    35.65     |  26.79   | 17.61 | 122.01 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  83.01  | 3.60 | 73.68  | 5.43  |  21.72   |   5.56    |    22.24     |  28.46   | 12.05 | 81.33  |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  68.89  | 3.54 | 59.05  | 6.77  |  27.09   |   6.94    |    27.75     |  28.93   | 14.52 | 98.73  |
| quad4newton_tex8_rgb_linear_direct                      |  65.41  | 3.99 | 44.56  | 8.98  |  35.91   |   9.22    |    36.88     |  25.64   | 15.29 | 127.73 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  78.86  | 3.64 | 59.26  | 6.75  |  27.00   |   6.93    |    27.73     |  28.16   | 12.68 | 98.97  |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  74.67  | 3.55 | 55.56  | 7.20  |  28.80   |   7.39    |    29.58     |  28.88   | 13.39 | 105.32 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  75.33  | 3.64 | 55.42  | 7.22  |  28.87   |   7.41    |    29.65     |  28.10   | 13.28 | 104.68 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  83.96  | 3.62 | 65.19  | 6.14  |  24.54   |   6.30    |    25.21     |  28.32   | 11.91 | 91.25  |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  73.99  | 3.46 | 54.45  | 7.35  |  29.39   |   7.55    |    30.18     |  29.61   | 13.51 | 106.74 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  97.78  | 3.61 | 77.90  | 5.14  |  20.54   |   5.27    |    21.10     |  28.37   | 10.23 | 77.42  |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  83.39  | 3.69 | 63.94  | 6.26  |  25.02   |   6.42    |    25.70     |  27.75   | 11.99 | 91.85  |
| quad8_tex8_rgb_linear_direct                            |  89.12  | 9.08 | 61.83  | 6.47  |  25.88   |   6.64    |    26.55     |  11.28   | 11.22 | 176.32 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 | 102.69  | 8.65 | 75.46  | 5.30  |  21.20   |   5.44    |    21.76     |  11.85   | 9.74 | 147.44 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  97.21  | 8.33 | 71.97  | 5.56  |  22.23   |   5.70    |    22.81     |  12.32   | 10.29 | 155.19 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  98.49  | 8.63 | 72.26  | 5.54  |  22.14   |   5.68    |    22.72     |  11.88   | 10.15 | 154.15 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        | 108.15  | 8.69 | 82.04  | 4.88  |  19.50   |   5.00    |    20.01     |  11.79   | 9.25 | 137.25 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  97.10  | 7.81 | 71.94  | 5.56  |  22.24   |   5.70    |    22.82     |  13.11   | 10.30 | 154.37 |
| quad8_tex8_rgb_quintic_bspline_direct                   | 121.81  | 8.01 | 97.27  | 4.11  |  16.45   |   4.22    |    16.88     |  12.79   | 8.21 | 118.88 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 | 105.97  | 7.72 | 81.48  | 4.91  |  19.64   |   5.04    |    20.15     |  13.26   | 9.44 | 140.38 |
| quad9_tex8_rgb_linear_direct                            |  87.80  | 8.97 | 60.56  | 6.61  |  26.42   |   6.78    |    27.14     |  11.42   | 11.39 | 203.03 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  98.86  | 8.27 | 74.83  | 5.35  |  21.38   |   5.49    |    21.96     |  12.40   | 10.12 | 170.35 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  98.47  | 8.83 | 70.89  | 5.64  |  22.57   |   5.80    |    23.18     |  11.62   | 10.16 | 174.94 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  98.99  | 9.15 | 70.33  | 5.69  |  22.75   |   5.84    |    23.37     |  11.19   | 10.10 | 175.38 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        | 105.24  | 8.32 | 80.38  | 4.98  |  19.91   |   5.11    |    20.44     |  12.32   | 9.50 | 159.68 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  97.02  | 9.09 | 70.16  | 5.70  |  22.81   |   5.86    |    23.42     |  11.27   | 10.31 | 178.02 |
| quad9_tex8_rgb_quintic_bspline_direct                   | 120.66  | 8.88 | 93.79  | 4.26  |  17.06   |   4.38    |    17.52     |  11.53   | 8.29 | 137.33 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 | 106.83  | 8.38 | 81.53  | 4.91  |  19.63   |   5.04    |    20.16     |  12.22   | 9.36 | 157.04 |

