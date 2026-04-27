# Geom Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  16.10  | 3.77 |  5.89  | 68.05 |  272.18  |   70.42   |    281.68    |  54.32   | 62.11 | 396.92 |
| tri6_nodal_grey                                         |  48.28  | 9.98 | 29.79  | 13.43 |  53.70   |   13.80   |    55.19     |  20.53   | 20.72 | 237.91 |
| quad4ibi_nodal_grey                                     |  12.92  | 2.72 |  7.62  | 52.47 |  209.89  |   53.82   |    215.30    |  37.64   | 77.43 | 579.38 |
| quad4newton_nodal_grey                                  |  22.78  | 2.36 | 13.43  | 29.80 |  119.21  |   30.62   |    122.47    |  43.38   | 44.60 | 380.28 |
| quad8_nodal_grey                                        |  33.19  | 5.75 | 21.52  | 18.59 |  74.35   |   19.09   |    76.35     |  17.81   | 30.13 | 460.16 |
| quad9_nodal_grey                                        |  35.82  | 6.66 | 21.52  | 18.59 |  74.36   |   19.09   |    76.38     |  15.37   | 27.92 | 483.50 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  17.43  | 3.95 |  7.82  | 51.19 |  204.76  |   52.98   |    211.91    |  51.94   | 57.41 | 336.75 |
| tri6_nodal_rgb                                          |  56.72  | 11.74 | 31.58  | 12.67 |  50.67   |   13.02   |    52.07     |  17.45   | 17.63 | 212.91 |
| quad4ibi_nodal_rgb                                      |  18.14  | 3.10 |  9.64  | 41.52 |  166.08  |   42.59   |    170.36    |  32.99   | 55.17 | 430.11 |
| quad4newton_nodal_rgb                                   |  22.68  | 2.95 | 15.18  | 26.35 |  105.42  |   27.07   |    108.30    |  34.76   | 44.09 | 325.39 |
| quad8_nodal_rgb                                         |  38.36  | 6.76 | 22.79  | 17.55 |  70.19   |   18.02   |    72.08     |  15.16   | 26.07 | 413.74 |
| quad9_nodal_rgb                                         |  39.78  | 7.45 | 23.39  | 17.11 |  68.44   |   17.57   |    70.30     |  13.75   | 25.14 | 433.64 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  23.36  | 4.11 | 10.81  | 37.02 |  148.07  |   38.31   |    153.24    |  49.85   | 42.81 | 286.86 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  28.70  | 3.71 | 17.80  | 22.47 |  89.87   |   23.25   |    93.00     |  55.23   | 34.85 | 214.92 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  27.60  | 4.22 | 15.69  | 25.49 |  101.95  |   26.38   |    105.51    |  48.52   | 36.23 | 228.35 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  27.69  | 4.01 | 15.80  | 25.32 |  101.30  |   26.21   |    104.83    |  51.04   | 36.11 | 220.92 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  29.48  | 3.77 | 18.60  | 21.50 |  86.02   |   22.26   |    89.02     |  54.32   | 33.92 | 206.75 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  28.77  | 3.85 | 16.22  | 24.66 |  98.65   |   25.52   |    102.10    |  53.17   | 34.82 | 228.85 |
| tri3_tex8_grey_quintic_bspline_direct                   |  41.45  | 4.36 | 27.75  | 14.42 |  57.66   |   14.92   |    59.68     |  46.98   | 24.13 | 140.13 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  33.68  | 5.17 | 20.41  | 19.59 |  78.38   |   20.28   |    81.11     |  39.66   | 29.69 | 185.34 |
| tri6_tex8_grey_linear_direct                            |  68.53  | 9.79 | 33.16  | 12.06 |  48.26   |   12.40   |    49.59     |  20.92   | 14.59 | 209.07 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  71.83  | 9.23 | 39.29  | 10.18 |  40.73   |   10.46   |    41.85     |  22.19   | 13.92 | 191.24 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  65.37  | 9.14 | 35.73  | 11.19 |  44.78   |   11.50   |    46.01     |  22.41   | 15.30 | 206.12 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  65.29  | 8.75 | 35.83  | 11.17 |  44.66   |   11.47   |    45.90     |  23.41   | 15.32 | 208.68 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  68.99  | 8.75 | 38.41  | 10.41 |  41.66   |   10.70   |    42.81     |  23.41   | 14.51 | 191.25 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  66.59  | 8.89 | 35.51  | 11.26 |  45.06   |   11.58   |    46.30     |  23.04   | 15.02 | 205.60 |
| tri6_tex8_grey_quintic_bspline_direct                   |  75.66  | 8.52 | 46.03  | 8.69  |  34.76   |   8.93    |    35.72     |  24.05   | 13.22 | 171.69 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  73.03  | 9.44 | 40.50  | 9.88  |  39.51   |   10.15   |    40.60     |  21.71   | 13.69 | 183.08 |
| quad4ibi_tex8_grey_linear_direct                        |  17.65  | 2.81 | 10.03  | 39.90 |  159.60  |   40.93   |    163.71    |  36.44   | 56.68 | 453.93 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  26.69  | 2.76 | 18.16  | 22.02 |  88.09   |   22.59   |    90.36     |  37.18   | 37.46 | 291.87 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  25.97  | 2.57 | 18.63  | 21.47 |  85.87   |   22.02   |    88.08     |  39.90   | 38.52 | 286.02 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  26.05  | 2.63 | 18.82  | 21.26 |  85.03   |   21.80   |    87.22     |  39.01   | 38.38 | 287.37 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  30.65  | 2.54 | 23.12  | 17.30 |  69.21   |   17.75   |    70.99     |  40.25   | 32.64 | 235.13 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  26.11  | 2.53 | 18.32  | 21.84 |  87.35   |   22.40   |    89.60     |  40.42   | 38.34 | 289.00 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  35.37  | 2.55 | 27.28  | 14.67 |  58.67   |   15.04   |    60.18     |  40.08   | 28.27 | 204.57 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  30.83  | 2.68 | 22.88  | 17.49 |  69.96   |   17.94   |    71.76     |  38.19   | 32.44 | 235.48 |
| quad4newton_tex8_grey_linear_direct                     |  32.85  | 2.63 | 16.59  | 24.11 |  96.44   |   24.77   |    99.08     |  38.87   | 30.44 | 320.09 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  41.47  | 2.83 | 23.13  | 17.30 |  69.19   |   17.77   |    71.08     |  36.43   | 24.11 | 236.96 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  37.31  | 2.58 | 21.51  | 18.60 |  74.38   |   19.10   |    76.42     |  39.67   | 26.80 | 255.58 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  40.67  | 2.78 | 22.02  | 18.17 |  72.67   |   18.66   |    74.66     |  37.09   | 24.59 | 252.47 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  42.59  | 2.91 | 24.38  | 16.41 |  65.63   |   16.86   |    67.43     |  35.33   | 23.49 | 226.77 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  37.36  | 2.49 | 21.49  | 18.61 |  74.44   |   19.12   |    76.48     |  41.18   | 26.77 | 257.67 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  49.00  | 2.53 | 31.26  | 12.80 |  51.18   |   13.14   |    52.58     |  40.51   | 20.43 | 184.72 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  40.50  | 2.52 | 24.33  | 16.44 |  65.77   |   16.89   |    67.56     |  40.63   | 24.69 | 229.85 |
| quad8_tex8_grey_linear_direct                           |  47.62  | 6.05 | 24.55  | 16.29 |  65.17   |   16.73   |    66.93     |  16.93   | 21.00 | 395.86 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  55.07  | 6.81 | 33.11  | 12.08 |  48.32   |   12.41   |    49.62     |  15.11   | 18.16 | 311.99 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  55.20  | 6.57 | 32.11  | 12.46 |  49.83   |   12.79   |    51.17     |  15.60   | 18.12 | 318.12 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.85  | 6.99 | 31.79  | 12.58 |  50.33   |   12.92   |    51.68     |  14.66   | 18.23 | 319.19 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  57.56  | 6.69 | 35.31  | 11.33 |  45.33   |   11.64   |    46.55     |  15.30   | 17.37 | 293.34 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  54.05  | 6.21 | 32.10  | 12.46 |  49.86   |   12.80   |    51.20     |  16.48   | 18.50 | 320.91 |
| quad8_tex8_grey_quintic_bspline_direct                  |  64.77  | 6.55 | 42.44  | 9.42  |  37.70   |   9.68    |    38.71     |  15.69   | 15.44 | 255.76 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  57.48  | 6.32 | 34.97  | 11.44 |  45.76   |   11.75   |    46.99     |  16.21   | 17.40 | 299.73 |
| quad9_tex8_grey_linear_direct                           |  50.18  | 7.55 | 25.21  | 15.87 |  63.48   |   16.30   |    65.20     |  13.58   | 19.93 | 423.65 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  55.57  | 7.18 | 32.65  | 12.25 |  49.01   |   12.58   |    50.34     |  14.27   | 18.00 | 354.73 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  57.46  | 7.18 | 30.72  | 13.02 |  52.09   |   13.38   |    53.50     |  14.26   | 17.40 | 357.17 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  54.77  | 6.50 | 31.44  | 12.73 |  50.90   |   13.07   |    52.28     |  15.79   | 18.26 | 365.40 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  58.03  | 6.92 | 34.20  | 11.70 |  46.79   |   12.01   |    48.06     |  14.80   | 17.23 | 340.22 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  54.39  | 6.91 | 30.67  | 13.04 |  52.18   |   13.40   |    53.59     |  14.93   | 18.39 | 372.79 |
| quad9_tex8_grey_quintic_bspline_direct                  |  65.93  | 6.58 | 41.05  | 9.74  |  38.97   |   10.01   |    40.03     |  15.56   | 15.17 | 285.67 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  58.62  | 7.52 | 34.02  | 11.76 |  47.04   |   12.08   |    48.31     |  13.63   | 17.06 | 341.89 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  30.59  | 4.94 | 17.07  | 23.44 |  93.75   |   24.26   |    97.02     |  41.46   | 32.69 | 193.66 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  36.67  | 3.68 | 24.82  | 16.13 |  64.50   |   16.69   |    66.76     |  55.66   | 27.27 | 155.61 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  34.02  | 3.80 | 22.41  | 17.85 |  71.39   |   18.47   |    73.88     |  53.95   | 29.39 | 168.69 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  36.86  | 4.28 | 22.61  | 17.69 |  70.77   |   18.31   |    73.24     |  47.91   | 27.13 | 163.42 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  40.46  | 3.65 | 27.91  | 14.34 |  57.35   |   14.84   |    59.35     |  56.08   | 24.72 | 140.66 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  35.97  | 3.97 | 22.64  | 17.67 |  70.68   |   18.29   |    73.15     |  51.62   | 27.80 | 164.62 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  46.40  | 3.49 | 35.06  | 11.41 |  45.63   |   11.81   |    47.23     |  58.70   | 21.55 | 116.41 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  39.57  | 3.94 | 27.63  | 14.48 |  57.91   |   14.98   |    59.93     |  51.98   | 25.27 | 145.05 |
| tri6_tex8_rgb_linear_direct                             |  69.07  | 9.27 | 37.00  | 10.81 |  43.25   |   11.11   |    44.44     |  22.10   | 14.48 | 199.47 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  77.21  | 9.78 | 44.01  | 9.09  |  36.36   |   9.34    |    37.36     |  20.93   | 12.95 | 171.93 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  72.66  | 9.30 | 41.76  | 9.58  |  38.31   |   9.84    |    39.37     |  22.03   | 13.76 | 182.56 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  75.06  | 9.59 | 43.50  | 9.20  |  36.78   |   9.45    |    37.80     |  21.37   | 13.32 | 174.98 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  80.20  | 9.72 | 47.59  | 8.41  |  33.63   |   8.64    |    34.56     |  21.06   | 12.47 | 161.51 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  74.14  | 9.20 | 42.91  | 9.32  |  37.29   |   9.58    |    38.32     |  22.26   | 13.49 | 179.28 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  86.35  | 9.62 | 53.95  | 7.41  |  29.65   |   7.62    |    30.47     |  21.29   | 11.58 | 144.30 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  79.44  | 9.43 | 47.37  | 8.44  |  33.78   |   8.68    |    34.71     |  21.72   | 12.59 | 163.60 |
| quad4ibi_tex8_rgb_linear_direct                         |  22.20  | 2.64 | 12.94  | 30.97 |  123.86  |   31.76   |    127.05    |  38.80   | 45.04 | 354.00 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  31.49  | 2.73 | 21.57  | 18.54 |  74.18   |   19.02   |    76.09     |  37.55   | 31.80 | 235.87 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  31.37  | 2.72 | 22.74  | 17.59 |  70.37   |   18.05   |    72.18     |  37.69   | 31.88 | 234.77 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  33.25  | 2.84 | 23.08  | 17.33 |  69.33   |   17.78   |    71.11     |  36.06   | 30.11 | 221.75 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  37.65  | 2.77 | 28.42  | 14.08 |  56.30   |   14.44   |    57.75     |  36.91   | 26.56 | 191.92 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  32.04  | 2.73 | 23.23  | 17.22 |  68.88   |   17.66   |    70.65     |  37.45   | 31.21 | 228.06 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  44.12  | 2.88 | 35.56  | 11.25 |  44.99   |   11.54   |    46.15     |  35.54   | 22.67 | 159.14 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  37.97  | 2.81 | 29.18  | 13.71 |  54.84   |   14.06   |    56.25     |  36.38   | 26.34 | 188.36 |
| quad4newton_tex8_rgb_linear_direct                      |  40.88  | 2.78 | 22.78  | 17.56 |  70.24   |   18.04   |    72.16     |  36.77   | 24.46 | 230.06 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  45.87  | 2.80 | 28.61  | 13.98 |  55.93   |   14.36   |    57.46     |  36.53   | 21.80 | 193.82 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  43.81  | 2.74 | 26.59  | 15.04 |  60.17   |   15.45   |    61.81     |  37.32   | 22.83 | 205.34 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  44.06  | 2.82 | 26.81  | 14.92 |  59.67   |   15.33   |    61.30     |  36.32   | 22.70 | 206.88 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  49.79  | 2.83 | 31.88  | 12.55 |  50.19   |   12.89   |    51.56     |  36.24   | 20.09 | 174.56 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  44.74  | 2.84 | 27.32  | 14.64 |  58.57   |   15.04   |    60.17     |  36.03   | 22.35 | 199.14 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  56.74  | 2.64 | 38.78  | 10.31 |  41.26   |   10.60   |    42.38     |  38.84   | 17.63 | 147.29 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  49.73  | 2.81 | 31.84  | 12.56 |  50.25   |   12.91   |    51.62     |  36.46   | 20.11 | 174.31 |
| quad8_tex8_rgb_linear_direct                            |  55.12  | 6.96 | 32.18  | 12.43 |  49.72   |   12.76   |    51.06     |  14.73   | 18.14 | 315.43 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  61.62  | 7.16 | 38.47  | 10.40 |  41.60   |   10.68   |    42.71     |  14.35   | 16.23 | 272.33 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  60.30  | 6.66 | 36.92  | 10.83 |  43.34   |   11.13   |    44.50     |  15.39   | 16.58 | 278.93 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  60.48  | 7.18 | 36.98  | 10.82 |  43.27   |   11.11   |    44.43     |  14.40   | 16.54 | 276.57 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  65.22  | 6.94 | 41.77  | 9.58  |  38.31   |   9.83    |    39.34     |  14.77   | 15.33 | 250.39 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  58.62  | 6.14 | 36.88  | 10.85 |  43.38   |   11.14   |    44.55     |  16.67   | 17.06 | 282.54 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  72.27  | 6.02 | 50.52  | 7.92  |  31.67   |   8.13    |    32.53     |  17.02   | 13.84 | 216.28 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  64.82  | 7.07 | 42.80  | 9.35  |  37.39   |   9.60    |    38.39     |  14.49   | 15.43 | 248.19 |
| quad9_tex8_rgb_linear_direct                            |  57.73  | 7.22 | 30.58  | 13.08 |  52.32   |   13.43   |    53.74     |  14.18   | 17.33 | 355.45 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  63.82  | 7.02 | 38.99  | 10.26 |  41.04   |   10.54   |    42.15     |  14.60   | 15.67 | 303.92 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  63.31  | 8.42 | 36.01  | 11.11 |  44.44   |   11.41   |    45.65     |  12.16   | 15.80 | 311.32 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  60.39  | 7.06 | 35.88  | 11.15 |  44.60   |   11.45   |    45.81     |  14.53   | 16.56 | 320.31 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  65.86  | 6.27 | 42.12  | 9.50  |  37.99   |   9.75    |    39.02     |  16.32   | 15.18 | 284.79 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  60.28  | 6.83 | 36.03  | 11.10 |  44.40   |   11.40   |    45.61     |  14.99   | 16.59 | 319.11 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  77.35  | 6.67 | 48.89  | 8.18  |  32.73   |   8.40    |    33.62     |  15.37   | 12.93 | 246.11 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  69.30  | 7.36 | 42.23  | 9.47  |  37.89   |   9.73    |    38.92     |  13.91   | 14.43 | 274.90 |

