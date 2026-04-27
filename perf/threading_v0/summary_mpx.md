# Performance Summary: Pixel Throughput (MPx/s)

## Benchmark: fullraster

### By Element Type (Median across interpolators)

| Element | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| quad4ibi | 5.67 (1.00x) | 10.59 (1.87x) | 19.96 (3.52x) | 31.91 (5.63x) |
| quad4newton | 6.16 (1.00x) | 11.46 (1.86x) | 21.16 (3.44x) | 32.79 (5.33x) |
| quad8 | 5.47 (1.00x) | 10.13 (1.85x) | 18.71 (3.42x) | 28.69 (5.24x) |
| quad9 | 5.43 (1.00x) | 10.07 (1.86x) | 18.63 (3.43x) | 27.35 (5.04x) |
| tri3 | 7.79 (1.00x) | 14.53 (1.86x) | 27.43 (3.52x) | 43.45 (5.58x) |
| tri6 | 5.45 (1.00x) | 10.16 (1.87x) | 18.28 (3.36x) | 27.53 (5.06x) |

### By Interpolator (Median across element types)

| Interpolator | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| cubic_bspline_lut_lerp | 5.58 (1.00x) | 10.50 (1.88x) | 19.75 (3.54x) | 30.90 (5.53x) |
| cubic_catmull_rom_direct | 5.27 (1.00x) | 9.96 (1.89x) | 18.40 (3.50x) | 29.09 (5.53x) |
| cubic_catmull_rom_lut_lerp | 5.57 (1.00x) | 10.38 (1.86x) | 19.26 (3.46x) | 31.11 (5.59x) |
| cubic_mitchell_netravali_lut_lerp | 5.62 (1.00x) | 10.38 (1.85x) | 19.49 (3.47x) | 30.34 (5.40x) |
| lanczos3_lut_lerp | 4.64 (1.00x) | 8.62 (1.86x) | 16.21 (3.49x) | 25.09 (5.41x) |
| linear_direct | 8.24 (1.00x) | 15.18 (1.84x) | 28.39 (3.44x) | 43.89 (5.33x) |
| nodal | 11.57 (1.00x) | 21.45 (1.85x) | 38.92 (3.36x) | 58.31 (5.04x) |
| quintic_bspline_direct | 3.53 (1.00x) | 6.72 (1.90x) | 12.67 (3.59x) | 20.39 (5.78x) |
| quintic_bspline_lut_lerp | 4.63 (1.00x) | 8.55 (1.85x) | 16.16 (3.49x) | 25.07 (5.41x) |

## Benchmark: sphere2000

### By Element Type (Median across interpolators)

| Element | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| quad4ibi | 7.37 (1.00x) | 13.62 (1.85x) | 25.43 (3.45x) | 41.70 (5.66x) |
| quad4newton | 9.33 (1.00x) | 16.92 (1.81x) | 31.77 (3.41x) | 50.11 (5.37x) |
| quad8 | 6.86 (1.00x) | 12.70 (1.85x) | 23.74 (3.46x) | 38.16 (5.56x) |
| quad9 | 6.70 (1.00x) | 12.50 (1.87x) | 23.34 (3.49x) | 36.64 (5.47x) |
| tri3 | 12.09 (1.00x) | 21.66 (1.79x) | 40.41 (3.34x) | 63.66 (5.27x) |
| tri6 | 4.52 (1.00x) | 8.54 (1.89x) | 15.99 (3.54x) | 25.23 (5.58x) |

### By Interpolator (Median across element types)

| Interpolator | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| cubic_bspline_lut_lerp | 7.12 (1.00x) | 13.18 (1.85x) | 24.52 (3.44x) | 39.55 (5.56x) |
| cubic_catmull_rom_lut_lerp | 7.14 (1.00x) | 13.11 (1.83x) | 24.68 (3.45x) | 39.86 (5.58x) |
| cubic_mitchell_netravali_lut_lerp | 7.12 (1.00x) | 13.18 (1.85x) | 24.58 (3.46x) | 40.19 (5.65x) |
| lanczos3_lut_lerp | 6.16 (1.00x) | 11.43 (1.85x) | 21.29 (3.46x) | 34.40 (5.58x) |
| linear_direct | 9.87 (1.00x) | 17.65 (1.79x) | 33.73 (3.42x) | 53.12 (5.38x) |
| nodal | 11.41 (1.00x) | 20.41 (1.79x) | 39.20 (3.43x) | 62.87 (5.51x) |
| quintic_bspline_lut_lerp | 6.15 (1.00x) | 11.39 (1.85x) | 21.14 (3.44x) | 33.36 (5.42x) |

