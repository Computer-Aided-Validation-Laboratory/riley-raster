# SIMD Performance Comparison

This document provides a comparative analysis of the scalar implementation (`src`) versus the two SIMD implementations (`src-simd` and `src-simd2`). Benchmarks were performed on an 800x500 frame with `sub_sample = 2` and `tile_size = 32`.

---

## 1. Triangle 3 (tri3)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  19.48   | 20.57 | 246.74 |  1.00x  |
|                                | src-simd       |  10.03   | 40.01 | 479.52 |  1.94x  |
|                                | src-simd2      |   9.55   | 42.01 | 503.34 |  2.04x  |
| **flat_rgb**                   | src            |  26.41   | 15.16 | 181.88 |  1.00x  |
|                                | src-simd       |  16.30   | 24.60 | 294.91 |  1.62x  |
|                                | src-simd2      |  12.95   | 30.98 | 371.26 |  2.04x  |
| **tex8_grey_linear**           | src            |  31.19   | 12.84 | 153.97 |  1.00x  |
|                                | src-simd       |  19.96   | 20.14 | 241.49 |  1.56x  |
|                                | src-simd2      |  18.04   | 22.21 | 266.30 |  1.73x  |
| **tex8_grey_quintic_lut_lerp** | src            |  78.24   |  5.12 |  61.37 |  1.00x  |
|                                | src-simd       |  49.71   |  8.05 |  96.61 |  1.57x  |
|                                | src-simd2      |  48.09   |  8.32 |  99.85 |  1.63x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 112.18   |  3.57 |  42.80 |  1.00x  |
|                                | src-simd       |  72.10   |  5.55 |  66.60 |  1.55x  |
|                                | src-simd2      |  68.93   |  5.81 |  69.67 |  1.63x  |

---

## 2. Triangle 3 Optimized (tri3opt)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  14.60   | 27.48 | 329.37 |  1.00x  |
|                                | src-simd       |   9.89   | 40.62 | 486.75 |  1.48x  |
|                                | src-simd2      |   9.68   | 41.48 | 497.08 |  1.51x  |
| **flat_rgb**                   | src            |  19.57   | 20.48 | 245.54 |  1.00x  |
|                                | src-simd       |  12.96   | 30.99 | 371.18 |  1.51x  |
|                                | src-simd2      |  13.18   | 30.45 | 364.91 |  1.48x  |
| **tex8_grey_linear**           | src            |  25.42   | 15.76 | 188.97 |  1.00x  |
|                                | src-simd       |  18.71   | 21.42 | 256.83 |  1.36x  |
|                                | src-simd2      |  18.22   | 22.01 | 263.89 |  1.41x  |
| **tex8_grey_quintic_lut_lerp** | src            |  74.15   |  5.40 |  64.75 |  1.00x  |
|                                | src-simd       |  51.86   |  7.74 |  92.85 |  1.43x  |
|                                | src-simd2      |  48.52   |  8.25 |  98.97 |  1.53x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 110.06   |  3.64 |  43.62 |  1.00x  |
|                                | src-simd       |  72.02   |  5.56 |  66.67 |  1.53x  |
|                                | src-simd2      |  69.09   |  5.79 |  69.50 |  1.59x  |

---

## 3. Triangle 6 (tri6)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  60.47   |  6.62 | 158.81 |  1.00x  |
|                                | src-simd       |  26.75   | 14.98 | 359.42 |  2.26x  |
|                                | src-simd2      |  29.07   | 13.77 | 330.44 |  2.08x  |
| **flat_rgb**                   | src            |  67.51   |  5.93 | 142.27 |  1.00x  |
|                                | src-simd       |  30.10   | 13.31 | 319.20 |  2.24x  |
|                                | src-simd2      |  34.27   | 11.69 | 280.41 |  1.97x  |
| **tex8_grey_linear**           | src            |  70.69   |  5.66 | 135.84 |  1.00x  |
|                                | src-simd       |  44.99   |  8.91 | 213.62 |  1.57x  |
|                                | src-simd2      |  38.31   | 10.46 | 250.85 |  1.85x  |
| **tex8_grey_quintic_lut_lerp** | src            | 127.97   |  3.13 |  75.04 |  1.00x  |
|                                | src-simd       |  77.54   |  5.16 | 123.84 |  1.65x  |
|                                | src-simd2      |  79.02   |  5.06 | 121.52 |  1.62x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 150.25   |  2.66 |  63.90 |  1.00x  |
|                                | src-simd       | 100.39   |  3.99 |  95.68 |  1.50x  |
|                                | src-simd2      |  99.98   |  4.00 |  96.04 |  1.50x  |

---

## 4. Quadrilateral 4 IBI (quad4ibi)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  24.98   | 16.03 | 256.42 |  1.00x  |
|                                | src-simd       |  26.69   | 15.01 | 240.11 |  0.94x  |
|                                | src-simd2      |  24.79   | 16.16 | 258.39 |  1.01x  |
| **flat_rgb**                   | src            |  33.42   | 11.98 | 191.60 |  1.00x  |
|                                | src-simd       |  34.08   | 11.75 | 187.90 |  0.98x  |
|                                | src-simd2      |  34.54   | 11.59 | 185.45 |  0.97x  |
| **tex8_grey_linear**           | src            |  38.59   | 10.38 | 165.97 |  1.00x  |
|                                | src-simd       |  39.67   | 10.09 | 161.42 |  0.97x  |
|                                | src-simd2      |  37.34   | 10.72 | 171.49 |  1.03x  |
| **tex8_grey_quintic_lut_lerp** | src            |  88.68   |  4.51 |  72.18 |  1.00x  |
|                                | src-simd       |  80.55   |  4.97 |  79.48 |  1.10x  |
|                                | src-simd2      |  80.15   |  4.99 |  79.88 |  1.11x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 124.29   |  3.22 | 115.87 |  1.00x  |
|                                | src-simd       | 106.42   |  3.76 |  60.15 |  1.17x  |
|                                | src-simd2      | 106.71   |  3.75 |  59.99 |  1.16x  |

---

## 5. Quadrilateral 4 Newton (quad4newton)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  40.60   |  9.86 | 157.72 |  1.00x  |
|                                | src-simd       |  20.36   | 19.68 | 314.69 |  1.99x  |
|                                | src-simd2      |  23.57   | 16.99 | 271.79 |  1.72x  |
| **flat_rgb**                   | src            |  46.29   |  8.65 | 138.38 |  1.00x  |
|                                | src-simd       |  23.45   | 17.08 | 273.21 |  1.97x  |
|                                | src-simd2      |  26.16   | 15.31 | 244.88 |  1.77x  |
| **tex8_grey_linear**           | src            |  48.38   |  8.27 | 132.35 |  1.00x  |
|                                | src-simd       |  29.87   | 13.41 | 214.44 |  1.62x  |
|                                | src-simd2      |  32.02   | 12.50 | 199.98 |  1.51x  |
| **tex8_grey_quintic_lut_lerp** | src            | 103.48   |  3.87 |  61.86 |  1.00x  |
|                                | src-simd       |  70.62   |  5.67 |  90.67 |  1.47x  |
|                                | src-simd2      |  71.60   |  5.59 |  89.42 |  1.45x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 129.53   |  3.09 |  49.42 |  1.00x  |
|                                | src-simd       |  95.21   |  4.20 |  67.24 |  1.36x  |
|                                | src-simd2      |  94.79   |  4.22 |  67.54 |  1.37x  |

---

## 6. Quadrilateral 8 (quad8)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  72.21   |  5.54 | 177.31 |  1.00x  |
|                                | src-simd       |  25.40   | 15.77 | 504.49 |  2.84x  |
|                                | src-simd2      |  29.79   | 13.44 | 430.01 |  2.42x  |
| **flat_rgb**                   | src            |  80.14   |  4.99 | 159.77 |  1.00x  |
|                                | src-simd       |  28.77   | 13.92 | 445.28 |  2.79x  |
|                                | src-simd2      |  35.14   | 11.40 | 364.52 |  2.28x  |
| **tex8_grey_linear**           | src            |  83.21   |  4.81 | 153.86 |  1.00x  |
|                                | src-simd       |  35.12   | 11.40 | 364.68 |  2.37x  |
|                                | src-simd2      |  39.34   | 10.18 | 325.57 |  2.12x  |
| **tex8_grey_quintic_lut_lerp** | src            | 140.74   |  2.84 |  90.96 |  1.00x  |
|                                | src-simd       |  75.04   |  5.33 | 170.62 |  1.88x  |
|                                | src-simd2      |  79.65   |  5.02 | 160.76 |  1.77x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 160.64   |  2.49 |  79.69 |  1.00x  |
|                                | src-simd       |  93.89   |  4.26 | 136.36 |  1.71x  |
|                                | src-simd2      | 100.33   |  3.99 | 127.61 |  1.60x  |

---

## 7. Quadrilateral 9 (quad9)

| Shader                         | Implementation | E2E (ms) | MPx/s | MOps/s | Speedup |
| :----------------------------- | :------------- | :------: | :---: | :----: | :-----: |
| **flat_grey**                  | src            |  71.06   |  5.63 | 202.74 |  1.00x  |
|                                | src-simd       |  26.86   | 14.91 | 536.45 |  2.65x  |
|                                | src-simd2      |  31.53   | 12.70 | 456.95 |  2.25x  |
| **flat_rgb**                   | src            |  79.03   |  5.06 | 182.25 |  1.00x  |
|                                | src-simd       |  30.74   | 13.03 | 468.82 |  2.57x  |
|                                | src-simd2      |  38.21   | 10.48 | 377.11 |  2.07x  |
| **tex8_grey_linear**           | src            |  84.13   |  4.76 | 171.20 |  1.00x  |
|                                | src-simd       |  35.92   | 11.15 | 401.11 |  2.34x  |
|                                | src-simd2      |  43.13   |  9.28 | 334.05 |  1.95x  |
| **tex8_grey_quintic_lut_lerp** | src            | 141.57   |  2.83 | 101.73 |  1.00x  |
|                                | src-simd       |  76.95   |  5.20 | 187.20 |  1.84x  |
|                                | src-simd2      |  83.92   |  4.77 | 171.64 |  1.69x  |
| **tex8_rgb_quintic_lut_lerp**  | src            | 161.46   |  2.48 |  89.20 |  1.00x  |
|                                | src-simd       |  98.30   |  4.07 | 146.53 |  1.64x  |
|                                | src-simd2      | 105.12   |  3.81 | 137.03 |  1.54x  |
