# Full Raster Benchmark Results
Date: 17-03-2026 | Res: 800x500

## Shader Type: nodal_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_grey                                         |  1.79   | 0.01 |  1.78  | 225.17 |  900.69  |  225.17   |    900.69    |   0.16   | 557.32 | 2682.80 |
| tri6_nodal_grey                                         |  5.48   | 0.02 |  5.46  | 73.32 |  293.29  |   73.32   |    293.29    |   0.13   | 182.47 | 1754.65 |
| quad4ibi_nodal_grey                                     |  3.41   | 0.01 |  3.39  | 117.92 |  471.68  |  117.92   |    471.68    |   0.09   | 293.43 | 1880.66 |
| quad4newton_nodal_grey                                  |  4.36   | 0.02 |  4.33  | 92.28 |  369.11  |   92.28   |    369.11    |   0.06   | 229.46 | 1471.61 |
| quad8_nodal_grey                                        |  5.15   | 0.01 |  5.13  | 77.97 |  311.89  |   77.97   |    311.89    |   0.09   | 194.25 | 2489.81 |
| quad9_nodal_grey                                        |  5.31   | 0.02 |  5.27  | 75.89 |  303.57  |   75.89   |    303.57    |   0.06   | 188.35 | 2718.52 |

## Shader Type: nodal_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_nodal_rgb                                          |  3.46   | 0.01 |  3.43  | 116.73 |  466.91  |  116.73   |    466.91    |   0.14   | 289.24 | 1393.17 |
| tri6_nodal_rgb                                          |  7.20   | 0.02 |  7.17  | 55.79 |  223.17  |   55.79   |    223.17    |   0.13   | 138.85 | 1335.00 |
| quad4ibi_nodal_rgb                                      |  5.49   | 0.02 |  5.46  | 73.26 |  293.06  |   73.26   |    293.06    |   0.06   | 182.19 | 1168.88 |
| quad4newton_nodal_rgb                                   |  6.30   | 0.01 |  6.28  | 63.73 |  254.92  |   63.73   |    254.92    |   0.07   | 158.74 | 1017.63 |
| quad8_nodal_rgb                                         |  7.39   | 0.01 |  7.36  | 54.34 |  217.37  |   54.34   |    217.37    |   0.08   | 135.35 | 1735.99 |
| quad9_nodal_rgb                                         |  7.16   | 0.01 |  7.14  | 56.03 |  224.12  |   56.03   |    224.12    |   0.07   | 139.59 | 2013.00 |

## Shader Type: tex8_grey

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_grey_linear_direct                            |  3.37   | 0.01 |  3.34  | 119.70 |  478.81  |  119.70   |    478.81    |   0.16   | 297.09 | 1429.32 |
| tri3_tex8_grey_cubic_catmull_rom_direct                 |  6.68   | 0.01 |  6.66  | 60.10 |  240.40  |   60.10   |    240.40    |   0.16   | 149.80 | 719.79 |
| tri3_tex8_grey_cubic_catmull_rom_lut_lerp               |  5.30   | 0.01 |  5.28  | 75.76 |  303.03  |   75.76   |    303.03    |   0.15   | 188.57 | 906.41 |
| tri3_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  5.28   | 0.01 |  5.27  | 75.96 |  303.86  |   75.96   |    303.86    |   0.16   | 189.22 | 909.42 |
| tri3_tex8_grey_lanczos3_lut_lerp                        |  6.95   | 0.01 |  6.93  | 57.75 |  231.01  |   57.75   |    231.01    |   0.15   | 143.81 | 691.53 |
| tri3_tex8_grey_cubic_bspline_lut_lerp                   |  5.30   | 0.01 |  5.28  | 75.73 |  302.94  |   75.73   |    302.94    |   0.15   | 188.60 | 906.50 |
| tri3_tex8_grey_quintic_bspline_direct                   |  10.69  | 0.01 | 10.67  | 37.50 |  150.01  |   37.50   |    150.01    |   0.15   | 93.54 | 449.40 |
| tri3_tex8_grey_quintic_bspline_lut_lerp                 |  7.00   | 0.01 |  6.98  | 57.34 |  229.37  |   57.34   |    229.37    |   0.15   | 142.88 | 686.52 |
| tri6_tex8_grey_linear_direct                            |  6.18   | 0.02 |  6.15  | 65.00 |  260.01  |   65.00   |    260.01    |   0.11   | 161.87 | 1555.91 |
| tri6_tex8_grey_cubic_catmull_rom_direct                 |  9.68   | 0.01 |  9.65  | 41.47 |  165.86  |   41.47   |    165.86    |   0.13   | 103.34 | 993.39 |
| tri6_tex8_grey_cubic_catmull_rom_lut_lerp               |  8.61   | 0.01 |  8.58  | 46.59 |  186.37  |   46.59   |    186.37    |   0.14   | 116.14 | 1116.11 |
| tri6_tex8_grey_cubic_mitchell_netravali_lut_lerp        |  8.72   | 0.01 |  8.69  | 46.02 |  184.08  |   46.02   |    184.08    |   0.14   | 114.74 | 1102.68 |
| tri6_tex8_grey_lanczos3_lut_lerp                        |  10.37  | 0.01 | 10.34  | 38.67 |  154.68  |   38.67   |    154.68    |   0.14   | 96.44 | 926.57 |
| tri6_tex8_grey_cubic_bspline_lut_lerp                   |  8.65   | 0.02 |  8.63  | 46.38 |  185.50  |   46.38   |    185.50    |   0.12   | 115.55 | 1110.87 |
| tri6_tex8_grey_quintic_bspline_direct                   |  13.87  | 0.02 | 13.84  | 28.91 |  115.63  |   28.91   |    115.63    |   0.11   | 72.12 | 692.94 |
| tri6_tex8_grey_quintic_bspline_lut_lerp                 |  10.27  | 0.01 | 10.24  | 39.06 |  156.25  |   39.06   |    156.25    |   0.14   | 97.38 | 936.18 |
| quad4ibi_tex8_grey_linear_direct                        |  4.50   | 0.01 |  4.48  | 89.24 |  356.96  |   89.24   |    356.96    |   0.09   | 222.16 | 1424.08 |
| quad4ibi_tex8_grey_cubic_catmull_rom_direct             |  8.96   | 0.01 |  8.92  | 44.85 |  179.38  |   44.85   |    179.38    |   0.09   | 111.65 | 716.02 |
| quad4ibi_tex8_grey_cubic_catmull_rom_lut_lerp           |  8.40   | 0.02 |  8.38  | 47.75 |  190.99  |   47.75   |    190.99    |   0.06   | 119.02 | 762.44 |
| quad4ibi_tex8_grey_cubic_mitchell_netravali_lut_lerp    |  8.42   | 0.01 |  8.40  | 47.61 |  190.42  |   47.61   |    190.42    |   0.09   | 118.72 | 760.47 |
| quad4ibi_tex8_grey_lanczos3_lut_lerp                    |  10.00  | 0.01 |  9.98  | 40.07 |  160.28  |   40.07   |    160.28    |   0.08   | 99.96 | 640.32 |
| quad4ibi_tex8_grey_cubic_bspline_lut_lerp               |  8.42   | 0.01 |  8.40  | 47.62 |  190.47  |   47.62   |    190.47    |   0.09   | 118.78 | 760.87 |
| quad4ibi_tex8_grey_quintic_bspline_direct               |  13.09  | 0.01 | 13.07  | 30.60 |  122.40  |   30.60   |    122.40    |   0.09   | 76.38 | 489.08 |
| quad4ibi_tex8_grey_quintic_bspline_lut_lerp             |  10.09  | 0.01 | 10.05  | 39.79 |  159.15  |   39.79   |    159.15    |   0.07   | 99.08 | 635.54 |
| quad4newton_tex8_grey_linear_direct                     |  5.35   | 0.01 |  5.32  | 75.14 |  300.55  |   75.14   |    300.55    |   0.08   | 186.96 | 1198.52 |
| quad4newton_tex8_grey_cubic_catmull_rom_direct          |  8.76   | 0.01 |  8.74  | 45.76 |  183.03  |   45.76   |    183.03    |   0.08   | 114.11 | 731.01 |
| quad4newton_tex8_grey_cubic_catmull_rom_lut_lerp        |  7.74   | 0.01 |  7.72  | 51.85 |  207.40  |   51.85   |    207.40    |   0.09   | 129.25 | 828.09 |
| quad4newton_tex8_grey_cubic_mitchell_netravali_lut_lerp |  7.73   | 0.01 |  7.71  | 51.87 |  207.47  |   51.87   |    207.47    |   0.08   | 129.33 | 828.52 |
| quad4newton_tex8_grey_lanczos3_lut_lerp                 |  9.29   | 0.01 |  9.27  | 43.16 |  172.63  |   43.16   |    172.63    |   0.07   | 107.62 | 689.33 |
| quad4newton_tex8_grey_cubic_bspline_lut_lerp            |  7.68   | 0.01 |  7.66  | 52.23 |  208.91  |   52.23   |    208.91    |   0.08   | 130.17 | 834.12 |
| quad4newton_tex8_grey_quintic_bspline_direct            |  12.89  | 0.01 | 12.87  | 31.09 |  124.35  |   31.09   |    124.35    |   0.07   | 77.58 | 496.84 |
| quad4newton_tex8_grey_quintic_bspline_lut_lerp          |  9.19   | 0.01 |  9.17  | 43.62 |  174.46  |   43.62   |    174.46    |   0.07   | 108.78 | 696.79 |
| quad8_tex8_grey_linear_direct                           |  6.21   | 0.01 |  6.19  | 64.67 |  258.69  |   64.67   |    258.69    |   0.08   | 161.15 | 2065.57 |
| quad8_tex8_grey_cubic_catmull_rom_direct                |  9.68   | 0.01 |  9.66  | 41.42 |  165.68  |   41.42   |    165.68    |   0.09   | 103.32 | 1323.86 |
| quad8_tex8_grey_cubic_catmull_rom_lut_lerp              |  8.68   | 0.01 |  8.65  | 46.24 |  184.96  |   46.24   |    184.96    |   0.07   | 115.25 | 1477.29 |
| quad8_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  8.63   | 0.01 |  8.61  | 46.45 |  185.79  |   46.45   |    185.79    |   0.09   | 115.86 | 1484.30 |
| quad8_tex8_grey_lanczos3_lut_lerp                       |  10.40  | 0.01 | 10.38  | 38.55 |  154.20  |   38.55   |    154.20    |   0.08   | 96.15 | 1231.76 |
| quad8_tex8_grey_cubic_bspline_lut_lerp                  |  8.71   | 0.01 |  8.68  | 46.08 |  184.33  |   46.08   |    184.33    |   0.08   | 114.86 | 1472.18 |
| quad8_tex8_grey_quintic_bspline_direct                  |  13.96  | 0.02 | 13.92  | 28.73 |  114.91  |   28.73   |    114.91    |   0.06   | 71.65 | 918.25 |
| quad8_tex8_grey_quintic_bspline_lut_lerp                |  10.20  | 0.01 | 10.18  | 39.31 |  157.23  |   39.31   |    157.23    |   0.08   | 98.07 | 1256.42 |
| quad9_tex8_grey_linear_direct                           |  6.34   | 0.01 |  6.32  | 63.32 |  253.28  |   63.32   |    253.28    |   0.08   | 157.82 | 2275.29 |
| quad9_tex8_grey_cubic_catmull_rom_direct                |  9.73   | 0.01 |  9.71  | 41.21 |  164.84  |   41.21   |    164.84    |   0.07   | 102.79 | 1481.29 |
| quad9_tex8_grey_cubic_catmull_rom_lut_lerp              |  8.76   | 0.01 |  8.73  | 45.83 |  183.31  |   45.83   |    183.31    |   0.09   | 114.19 | 1647.55 |
| quad9_tex8_grey_cubic_mitchell_netravali_lut_lerp       |  9.06   | 0.01 |  9.04  | 44.27 |  177.08  |   44.27   |    177.08    |   0.07   | 110.32 | 1590.35 |
| quad9_tex8_grey_lanczos3_lut_lerp                       |  10.92  | 0.01 | 10.89  | 36.76 |  147.02  |   36.76   |    147.02    |   0.08   | 91.65 | 1321.67 |
| quad9_tex8_grey_cubic_bspline_lut_lerp                  |  8.82   | 0.01 |  8.80  | 45.46 |  181.83  |   45.46   |    181.83    |   0.08   | 113.35 | 1633.61 |
| quad9_tex8_grey_quintic_bspline_direct                  |  14.18  | 0.01 | 14.16  | 28.26 |  113.03  |   28.26   |    113.03    |   0.08   | 70.52 | 1016.19 |
| quad9_tex8_grey_quintic_bspline_lut_lerp                |  10.43  | 0.01 | 10.41  | 38.44 |  153.78  |   38.44   |    153.78    |   0.08   | 95.89 | 1381.93 |

## Shader Type: tex8_rgb

| Case                                                    | E2E Med | Geom | Raster | MPx/s | MsubPx/s | MShades/s | MsubShades/s | MElems/s | FPS | MOps/s |
|---------------------------------------------------------| :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| tri3_tex8_rgb_linear_direct                             |  5.89   | 0.01 |  5.86  | 68.22 |  272.88  |   68.22   |    272.88    |   0.14   | 169.79 | 816.66 |
| tri3_tex8_rgb_cubic_catmull_rom_direct                  |  10.27  | 0.02 | 10.24  | 39.06 |  156.25  |   39.06   |    156.25    |   0.12   | 97.38 | 467.96 |
| tri3_tex8_rgb_cubic_catmull_rom_lut_lerp                |  9.64   | 0.02 |  9.62  | 41.59 |  166.37  |   41.59   |    166.37    |   0.13   | 103.68 | 498.30 |
| tri3_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  9.52   | 0.02 |  9.49  | 42.15 |  168.60  |   42.15   |    168.60    |   0.12   | 105.03 | 504.75 |
| tri3_tex8_rgb_lanczos3_lut_lerp                         |  11.46  | 0.02 | 11.42  | 35.02 |  140.07  |   35.02   |    140.07    |   0.11   | 87.29 | 419.67 |
| tri3_tex8_rgb_cubic_bspline_lut_lerp                    |  9.40   | 0.01 |  9.38  | 42.66 |  170.65  |   42.66   |    170.65    |   0.13   | 106.35 | 511.18 |
| tri3_tex8_rgb_quintic_bspline_direct                    |  15.19  | 0.02 | 15.16  | 26.39 |  105.56  |   26.39   |    105.56    |   0.12   | 65.84 | 316.35 |
| tri3_tex8_rgb_quintic_bspline_lut_lerp                  |  11.53  | 0.01 | 11.51  | 34.77 |  139.07  |   34.77   |    139.07    |   0.14   | 86.72 | 416.68 |
| tri6_tex8_rgb_linear_direct                             |  9.78   | 0.02 |  9.75  | 41.03 |  164.11  |   41.03   |    164.11    |   0.12   | 102.21 | 982.77 |
| tri6_tex8_rgb_cubic_catmull_rom_direct                  |  13.56  | 0.02 | 13.53  | 29.56 |  118.24  |   29.56   |    118.24    |   0.13   | 73.75 | 708.67 |
| tri6_tex8_rgb_cubic_catmull_rom_lut_lerp                |  12.57  | 0.02 | 12.54  | 31.89 |  127.55  |   31.89   |    127.55    |   0.12   | 79.55 | 764.37 |
| tri6_tex8_rgb_cubic_mitchell_netravali_lut_lerp         |  12.26  | 0.01 | 12.23  | 32.71 |  130.85  |   32.71   |    130.85    |   0.14   | 81.57 | 784.20 |
| tri6_tex8_rgb_lanczos3_lut_lerp                         |  14.68  | 0.02 | 14.65  | 27.31 |  109.24  |   27.31   |    109.24    |   0.12   | 68.14 | 654.68 |
| tri6_tex8_rgb_cubic_bspline_lut_lerp                    |  12.56  | 0.01 | 12.53  | 31.92 |  127.69  |   31.92   |    127.69    |   0.14   | 79.64 | 765.28 |
| tri6_tex8_rgb_quintic_bspline_direct                    |  18.35  | 0.02 | 18.32  | 21.83 |  87.33   |   21.83   |    87.33     |   0.11   | 54.49 | 523.48 |
| tri6_tex8_rgb_quintic_bspline_lut_lerp                  |  14.76  | 0.02 | 14.73  | 27.15 |  108.60  |   27.15   |    108.60    |   0.11   | 67.73 | 650.79 |
| quad4ibi_tex8_rgb_linear_direct                         |  6.80   | 0.02 |  6.77  | 59.05 |  236.21  |   59.05   |    236.21    |   0.06   | 146.99 | 942.55 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_direct              |  11.73  | 0.01 | 11.70  | 34.20 |  136.81  |   34.20   |    136.81    |   0.07   | 85.30 | 546.52 |
| quad4ibi_tex8_rgb_cubic_catmull_rom_lut_lerp            |  11.29  | 0.02 | 11.26  | 35.52 |  142.07  |   35.52   |    142.07    |   0.06   | 88.58 | 567.51 |
| quad4ibi_tex8_rgb_cubic_mitchell_netravali_lut_lerp     |  11.18  | 0.02 | 11.16  | 35.86 |  143.42  |   35.86   |    143.42    |   0.07   | 89.43 | 573.04 |
| quad4ibi_tex8_rgb_lanczos3_lut_lerp                     |  14.80  | 0.02 | 14.77  | 27.09 |  108.36  |   27.09   |    108.36    |   0.07   | 67.59 | 433.02 |
| quad4ibi_tex8_rgb_cubic_bspline_lut_lerp                |  11.32  | 0.01 | 11.30  | 35.41 |  141.64  |   35.41   |    141.64    |   0.08   | 88.30 | 565.73 |
| quad4ibi_tex8_rgb_quintic_bspline_direct                |  18.84  | 0.02 | 18.81  | 21.27 |  85.08   |   21.27   |    85.08     |   0.06   | 53.07 | 340.00 |
| quad4ibi_tex8_rgb_quintic_bspline_lut_lerp              |  14.68  | 0.01 | 14.65  | 27.29 |  109.18  |   27.29   |    109.18    |   0.07   | 68.10 | 436.23 |
| quad4newton_tex8_rgb_linear_direct                      |  9.06   | 0.01 |  9.04  | 44.27 |  177.09  |   44.27   |    177.09    |   0.07   | 110.37 | 707.30 |
| quad4newton_tex8_rgb_cubic_catmull_rom_direct           |  12.55  | 0.01 | 12.53  | 31.93 |  127.73  |   31.93   |    127.73    |   0.07   | 79.65 | 510.29 |
| quad4newton_tex8_rgb_cubic_catmull_rom_lut_lerp         |  11.74  | 0.01 | 11.71  | 34.15 |  136.61  |   34.15   |    136.61    |   0.08   | 85.18 | 545.70 |
| quad4newton_tex8_rgb_cubic_mitchell_netravali_lut_lerp  |  11.72  | 0.01 | 11.69  | 34.22 |  136.89  |   34.22   |    136.89    |   0.07   | 85.34 | 546.95 |
| quad4newton_tex8_rgb_lanczos3_lut_lerp                  |  13.93  | 0.01 | 13.90  | 28.77 |  115.08  |   28.77   |    115.08    |   0.07   | 71.78 | 459.81 |
| quad4newton_tex8_rgb_cubic_bspline_lut_lerp             |  11.73  | 0.01 | 11.70  | 34.17 |  136.70  |   34.17   |    136.70    |   0.08   | 85.23 | 546.17 |
| quad4newton_tex8_rgb_quintic_bspline_direct             |  17.44  | 0.02 | 17.41  | 22.97 |  91.90   |   22.97   |    91.90     |   0.07   | 57.34 | 367.25 |
| quad4newton_tex8_rgb_quintic_bspline_lut_lerp           |  13.88  | 0.01 | 13.85  | 28.87 |  115.49  |   28.87   |    115.49    |   0.07   | 72.04 | 461.44 |
| quad8_tex8_rgb_linear_direct                            |  9.95   | 0.01 |  9.93  | 40.30 |  161.21  |   40.30   |    161.21    |   0.08   | 100.48 | 1287.69 |
| quad8_tex8_rgb_cubic_catmull_rom_direct                 |  13.51  | 0.01 | 13.48  | 29.67 |  118.69  |   29.67   |    118.69    |   0.07   | 74.04 | 948.63 |
| quad8_tex8_rgb_cubic_catmull_rom_lut_lerp               |  12.61  | 0.02 | 12.58  | 31.79 |  127.14  |   31.79   |    127.14    |   0.07   | 79.30 | 1016.06 |
| quad8_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  12.39  | 0.01 | 12.37  | 32.35 |  129.39  |   32.35   |    129.39    |   0.08   | 80.70 | 1034.07 |
| quad8_tex8_rgb_lanczos3_lut_lerp                        |  14.67  | 0.01 | 14.64  | 27.32 |  109.27  |   27.32   |    109.27    |   0.07   | 68.17 | 873.28 |
| quad8_tex8_rgb_cubic_bspline_lut_lerp                   |  12.48  | 0.01 | 12.46  | 32.12 |  128.49  |   32.12   |    128.49    |   0.08   | 80.12 | 1026.60 |
| quad8_tex8_rgb_quintic_bspline_direct                   |  18.53  | 0.01 | 18.50  | 21.62 |  86.48   |   21.62   |    86.48     |   0.07   | 53.95 | 691.12 |
| quad8_tex8_rgb_quintic_bspline_lut_lerp                 |  14.81  | 0.02 | 14.79  | 27.05 |  108.21  |   27.05   |    108.21    |   0.06   | 67.52 | 864.96 |
| quad9_tex8_rgb_linear_direct                            |  10.15  | 0.02 | 10.13  | 39.50 |  158.00  |   39.50   |    158.00    |   0.06   | 98.49 | 1419.90 |
| quad9_tex8_rgb_cubic_catmull_rom_direct                 |  13.65  | 0.01 | 13.63  | 29.35 |  117.39  |   29.35   |    117.39    |   0.08   | 73.24 | 1055.60 |
| quad9_tex8_rgb_cubic_catmull_rom_lut_lerp               |  12.81  | 0.01 | 12.78  | 31.30 |  125.18  |   31.30   |    125.18    |   0.08   | 78.08 | 1125.50 |
| quad9_tex8_rgb_cubic_mitchell_netravali_lut_lerp        |  12.26  | 0.01 | 12.23  | 32.70 |  130.79  |   32.70   |    130.79    |   0.08   | 81.59 | 1175.93 |
| quad9_tex8_rgb_lanczos3_lut_lerp                        |  14.84  | 0.01 | 14.82  | 26.99 |  107.97  |   26.99   |    107.97    |   0.07   | 67.37 | 970.88 |
| quad9_tex8_rgb_cubic_bspline_lut_lerp                   |  12.70  | 0.01 | 12.67  | 31.57 |  126.27  |   31.57   |    126.27    |   0.08   | 78.77 | 1135.26 |
| quad9_tex8_rgb_quintic_bspline_direct                   |  18.40  | 0.01 | 18.38  | 21.76 |  87.06   |   21.76   |    87.06     |   0.08   | 54.34 | 783.01 |
| quad9_tex8_rgb_quintic_bspline_lut_lerp                 |  15.00  | 0.02 | 14.98  | 26.71 |  106.83  |   26.71   |    106.83    |   0.06   | 66.65 | 960.47 |

