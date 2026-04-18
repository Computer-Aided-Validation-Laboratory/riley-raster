# Fullraster MPx/s Summary

## MPx/s

```text
| Mesh        | Shader     | Sample                       | Mode   |    0t |     2t |     4t |     8t |
|-------------|------------|------------------------------|--------|-------|--------|--------|--------|
| quad4ibi    | nodal_grey | -                            | -      | 21.34 |  39.17 |  72.23 | 117.92 |
| quad4ibi    | nodal_rgb  | -                            | -      | 14.09 |  25.45 |  45.73 |  73.26 |
| quad4ibi    | tex8_grey  | cubic_bspline_lut            | lerp   |  6.70 |  13.01 |  24.90 |  47.62 |
| quad4ibi    | tex8_grey  | cubic_catmull_rom            | direct |  6.61 |  12.97 |  24.88 |  44.85 |
| quad4ibi    | tex8_grey  | cubic_catmull_rom_lut        | lerp   |  6.66 |  13.08 |  25.01 |  47.75 |
| quad4ibi    | tex8_grey  | cubic_mitchell_netravali_lut | lerp   |  6.68 |  12.93 |  25.18 |  47.61 |
| quad4ibi    | tex8_grey  | lanczos3_lut                 | lerp   |  5.56 |  10.94 |  21.04 |  40.07 |
| quad4ibi    | tex8_grey  | linear                       | direct | 14.97 |  27.89 |  51.69 |  89.24 |
| quad4ibi    | tex8_grey  | quintic_bspline              | direct |  4.26 |   8.32 |  16.30 |  30.60 |
| quad4ibi    | tex8_grey  | quintic_bspline_lut          | lerp   |  5.56 |  10.78 |  20.91 |  39.79 |
| quad4ibi    | tex8_rgb   | cubic_bspline_lut            | lerp   |  5.50 |  10.70 |  19.90 |  35.41 |
| quad4ibi    | tex8_rgb   | cubic_catmull_rom            | direct |  5.37 |  10.24 |  19.34 |  34.20 |
| quad4ibi    | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  5.48 |  10.56 |  19.94 |  35.52 |
| quad4ibi    | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  5.49 |  10.53 |  19.69 |  35.86 |
| quad4ibi    | tex8_rgb   | lanczos3_lut                 | lerp   |  4.10 |   8.07 |  15.38 |  27.09 |
| quad4ibi    | tex8_rgb   | linear                       | direct | 10.62 |  19.76 |  35.48 |  59.05 |
| quad4ibi    | tex8_rgb   | quintic_bspline              | direct |  3.08 |   6.05 |  11.63 |  21.27 |
| quad4ibi    | tex8_rgb   | quintic_bspline_lut          | lerp   |  4.11 |   7.89 |  15.30 |  27.29 |
| quad4newton | nodal_grey | -                            | -      | 15.50 |  28.41 |  53.62 |  92.28 |
| quad4newton | nodal_rgb  | -                            | -      | 12.41 |  22.65 |  40.76 |  63.73 |
| quad4newton | tex8_grey  | cubic_bspline_lut            | lerp   |  7.59 |  14.54 |  27.89 |  52.23 |
| quad4newton | tex8_grey  | cubic_catmull_rom            | direct |  6.62 |  12.90 |  25.07 |  45.76 |
| quad4newton | tex8_grey  | cubic_catmull_rom_lut        | lerp   |  7.59 |  14.48 |  28.40 |  51.85 |
| quad4newton | tex8_grey  | cubic_mitchell_netravali_lut | lerp   |  7.57 |  14.48 |  28.04 |  51.87 |
| quad4newton | tex8_grey  | lanczos3_lut                 | lerp   |  6.13 |  11.81 |  22.87 |  43.16 |
| quad4newton | tex8_grey  | linear                       | direct | 11.96 |  22.37 |  42.83 |  75.14 |
| quad4newton | tex8_grey  | quintic_bspline              | direct |  4.36 |   8.41 |  16.46 |  31.09 |
| quad4newton | tex8_grey  | quintic_bspline_lut          | lerp   |  6.12 |  11.70 |  23.05 |  43.62 |
| quad4newton | tex8_rgb   | cubic_bspline_lut            | lerp   |  5.44 |  10.35 |  19.69 |  34.17 |
| quad4newton | tex8_rgb   | cubic_catmull_rom            | direct |  4.91 |   9.37 |  18.05 |  31.93 |
| quad4newton | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  5.42 |  10.36 |  19.58 |  34.15 |
| quad4newton | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  5.43 |  10.37 |  19.32 |  34.22 |
| quad4newton | tex8_rgb   | lanczos3_lut                 | lerp   |  4.41 |   8.52 |  15.56 |  28.77 |
| quad4newton | tex8_rgb   | linear                       | direct |  7.27 |  13.77 |  25.46 |  44.27 |
| quad4newton | tex8_rgb   | quintic_bspline              | direct |  3.36 |   6.51 |  12.47 |  22.97 |
| quad4newton | tex8_rgb   | quintic_bspline_lut          | lerp   |  4.41 |   8.57 |  15.53 |  28.87 |
| quad8       | nodal_grey | -                            | -      | 12.27 |  23.80 |  43.36 |  77.97 |
| quad8       | nodal_rgb  | -                            | -      | 10.13 |  19.34 |  33.77 |  54.34 |
| quad8       | tex8_grey  | cubic_bspline_lut            | lerp   |  6.61 |  12.80 |  24.57 |  46.08 |
| quad8       | tex8_grey  | cubic_catmull_rom            | direct |  5.90 |  11.29 |  22.17 |  41.42 |
| quad8       | tex8_grey  | cubic_catmull_rom_lut        | lerp   |  6.62 |  12.78 |  24.62 |  46.24 |
| quad8       | tex8_grey  | cubic_mitchell_netravali_lut | lerp   |  6.46 |  12.82 |  24.99 |  46.45 |
| quad8       | tex8_grey  | lanczos3_lut                 | lerp   |  5.47 |  10.63 |  20.95 |  38.55 |
| quad8       | tex8_grey  | linear                       | direct |  9.85 |  18.63 |  34.78 |  64.67 |
| quad8       | tex8_grey  | quintic_bspline              | direct |  4.01 |   7.85 |  15.15 |  28.73 |
| quad8       | tex8_grey  | quintic_bspline_lut          | lerp   |  5.47 |  10.58 |  20.62 |  39.31 |
| quad8       | tex8_rgb   | cubic_bspline_lut            | lerp   |  4.93 |   9.56 |  18.23 |  32.12 |
| quad8       | tex8_rgb   | cubic_catmull_rom            | direct |  4.51 |   8.81 |  16.60 |  29.67 |
| quad8       | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  4.93 |   9.37 |  18.17 |  31.79 |
| quad8       | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  4.92 |   9.35 |  18.09 |  32.35 |
| quad8       | tex8_rgb   | lanczos3_lut                 | lerp   |  4.08 |   7.84 |  14.57 |  27.32 |
| quad8       | tex8_rgb   | linear                       | direct |  6.54 |  12.81 |  22.88 |  40.30 |
| quad8       | tex8_rgb   | quintic_bspline              | direct |  3.15 |   6.09 |  11.80 |  21.62 |
| quad8       | tex8_rgb   | quintic_bspline_lut          | lerp   |  4.08 |   7.85 |  14.49 |  27.05 |
| quad9       | nodal_grey | -                            | -      | 12.04 |  22.72 |  42.57 |  75.89 |
| quad9       | nodal_rgb  | -                            | -      |  9.93 |  18.54 |  34.11 |  56.03 |
| quad9       | tex8_grey  | cubic_bspline_lut            | lerp   |  6.59 |  12.86 |  24.48 |  45.46 |
| quad9       | tex8_grey  | cubic_catmull_rom            | direct |  5.84 |  11.23 |  22.03 |  41.21 |
| quad9       | tex8_grey  | cubic_catmull_rom_lut        | lerp   |  6.59 |  12.79 |  24.59 |  45.83 |
| quad9       | tex8_grey  | cubic_mitchell_netravali_lut | lerp   |  6.59 |  12.57 |  24.66 |  44.27 |
| quad9       | tex8_grey  | lanczos3_lut                 | lerp   |  5.46 |  10.65 |  20.09 |  36.76 |
| quad9       | tex8_grey  | linear                       | direct |  9.71 |  18.39 |  34.63 |  63.32 |
| quad9       | tex8_grey  | quintic_bspline              | direct |  3.99 |   7.81 |  15.16 |  28.26 |
| quad9       | tex8_grey  | quintic_bspline_lut          | lerp   |  5.46 |  10.53 |  20.57 |  38.44 |
| quad9       | tex8_rgb   | cubic_bspline_lut            | lerp   |  4.91 |   9.54 |  17.79 |  31.57 |
| quad9       | tex8_rgb   | cubic_catmull_rom            | direct |  4.49 |   8.60 |  16.32 |  29.35 |
| quad9       | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  4.91 |   9.49 |  17.81 |  31.30 |
| quad9       | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  4.92 |   9.34 |  17.86 |  32.70 |
| quad9       | tex8_rgb   | lanczos3_lut                 | lerp   |  4.07 |   7.87 |  14.43 |  26.99 |
| quad9       | tex8_rgb   | linear                       | direct |  6.35 |  12.05 |  23.09 |  39.50 |
| quad9       | tex8_rgb   | quintic_bspline              | direct |  3.15 |   6.14 |  11.63 |  21.76 |
| quad9       | tex8_rgb   | quintic_bspline_lut          | lerp   |  4.07 |   7.79 |  14.53 |  26.71 |
| tri3        | nodal_grey | -                            | -      | 67.05 | 110.73 | 184.35 | 225.17 |
| tri3        | nodal_rgb  | -                            | -      | 32.94 |  54.23 |  84.57 | 116.73 |
| tri3        | tex8_grey  | cubic_bspline_lut            | lerp   | 11.23 |  21.80 |  41.34 |  75.73 |
| tri3        | tex8_grey  | cubic_catmull_rom            | direct |  8.52 |  16.68 |  31.79 |  60.10 |
| tri3        | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 11.34 |  21.74 |  42.35 |  75.76 |
| tri3        | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 11.21 |  21.45 |  41.03 |  75.96 |
| tri3        | tex8_grey  | lanczos3_lut                 | lerp   |  8.27 |  15.84 |  28.84 |  57.75 |
| tri3        | tex8_grey  | linear                       | direct | 21.69 |  40.31 |  73.74 | 119.70 |
| tri3        | tex8_grey  | quintic_bspline              | direct |  5.16 |   9.96 |  19.54 |  37.50 |
| tri3        | tex8_grey  | quintic_bspline_lut          | lerp   |  8.29 |  16.17 |  28.78 |  57.34 |
| tri3        | tex8_rgb   | cubic_bspline_lut            | lerp   |  6.95 |  13.27 |  24.19 |  42.66 |
| tri3        | tex8_rgb   | cubic_catmull_rom            | direct |  6.29 |  11.77 |  22.33 |  39.06 |
| tri3        | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  6.91 |  12.84 |  23.94 |  41.59 |
| tri3        | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  6.93 |  12.80 |  24.07 |  42.15 |
| tri3        | tex8_rgb   | lanczos3_lut                 | lerp   |  5.35 |  10.35 |  19.46 |  35.02 |
| tri3        | tex8_rgb   | linear                       | direct | 12.94 |  23.72 |  41.21 |  68.22 |
| tri3        | tex8_rgb   | quintic_bspline              | direct |  3.89 |   7.52 |  14.40 |  26.39 |
| tri3        | tex8_rgb   | quintic_bspline_lut          | lerp   |  5.35 |  10.31 |  19.25 |  34.77 |
| tri6        | nodal_grey | -                            | -      | 12.21 |  22.57 |  42.81 |  73.32 |
| tri6        | nodal_rgb  | -                            | -      | 10.09 |  18.38 |  33.78 |  55.79 |
| tri6        | tex8_grey  | cubic_bspline_lut            | lerp   |  6.65 |  12.90 |  24.91 |  46.38 |
| tri6        | tex8_grey  | cubic_catmull_rom            | direct |  5.87 |  11.54 |  21.97 |  41.47 |
| tri6        | tex8_grey  | cubic_catmull_rom_lut        | lerp   |  6.60 |  12.81 |  24.75 |  46.59 |
| tri6        | tex8_grey  | cubic_mitchell_netravali_lut | lerp   |  6.61 |  12.83 |  24.66 |  46.02 |
| tri6        | tex8_grey  | lanczos3_lut                 | lerp   |  5.48 |  10.63 |  20.36 |  38.67 |
| tri6        | tex8_grey  | linear                       | direct |  9.72 |  18.81 |  34.54 |  65.00 |
| tri6        | tex8_grey  | quintic_bspline              | direct |  4.03 |   7.88 |  15.26 |  28.91 |
| tri6        | tex8_grey  | quintic_bspline_lut          | lerp   |  5.52 |  10.56 |  20.52 |  39.06 |
| tri6        | tex8_rgb   | cubic_bspline_lut            | lerp   |  4.95 |   9.59 |  18.09 |  31.92 |
| tri6        | tex8_rgb   | cubic_catmull_rom            | direct |  4.51 |   8.65 |  16.54 |  29.56 |
| tri6        | tex8_rgb   | cubic_catmull_rom_lut        | lerp   |  4.93 |   9.44 |  18.10 |  31.89 |
| tri6        | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   |  4.96 |   9.43 |  17.86 |  32.71 |
| tri6        | tex8_rgb   | lanczos3_lut                 | lerp   |  4.08 |   7.93 |  14.47 |  27.31 |
| tri6        | tex8_rgb   | linear                       | direct |  6.49 |  12.22 |  22.91 |  41.03 |
| tri6        | tex8_rgb   | quintic_bspline              | direct |  3.15 |   6.13 |  11.76 |  21.83 |
| tri6        | tex8_rgb   | quintic_bspline_lut          | lerp   |  4.07 |   7.95 |  14.60 |  27.15 |
```

## Performance Multiplier

```text
| Mesh        | Shader     | Sample                       | Mode   |   x2 |   x4 |   x8 |
|-------------|------------|------------------------------|--------|------|------|------|
| quad4ibi    | nodal_grey | -                            | -      | 1.84 | 3.38 | 5.53 |
| quad4ibi    | nodal_rgb  | -                            | -      | 1.81 | 3.25 | 5.20 |
| quad4ibi    | tex8_grey  | cubic_bspline_lut            | lerp   | 1.94 | 3.72 | 7.11 |
| quad4ibi    | tex8_grey  | cubic_catmull_rom            | direct | 1.96 | 3.76 | 6.79 |
| quad4ibi    | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.96 | 3.76 | 7.17 |
| quad4ibi    | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.94 | 3.77 | 7.13 |
| quad4ibi    | tex8_grey  | lanczos3_lut                 | lerp   | 1.97 | 3.78 | 7.21 |
| quad4ibi    | tex8_grey  | linear                       | direct | 1.86 | 3.45 | 5.96 |
| quad4ibi    | tex8_grey  | quintic_bspline              | direct | 1.95 | 3.83 | 7.18 |
| quad4ibi    | tex8_grey  | quintic_bspline_lut          | lerp   | 1.94 | 3.76 | 7.16 |
| quad4ibi    | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.95 | 3.62 | 6.44 |
| quad4ibi    | tex8_rgb   | cubic_catmull_rom            | direct | 1.91 | 3.60 | 6.37 |
| quad4ibi    | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.93 | 3.64 | 6.48 |
| quad4ibi    | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.92 | 3.59 | 6.53 |
| quad4ibi    | tex8_rgb   | lanczos3_lut                 | lerp   | 1.97 | 3.75 | 6.61 |
| quad4ibi    | tex8_rgb   | linear                       | direct | 1.86 | 3.34 | 5.56 |
| quad4ibi    | tex8_rgb   | quintic_bspline              | direct | 1.96 | 3.78 | 6.91 |
| quad4ibi    | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.92 | 3.72 | 6.64 |
| quad4newton | nodal_grey | -                            | -      | 1.83 | 3.46 | 5.95 |
| quad4newton | nodal_rgb  | -                            | -      | 1.83 | 3.28 | 5.14 |
| quad4newton | tex8_grey  | cubic_bspline_lut            | lerp   | 1.92 | 3.67 | 6.88 |
| quad4newton | tex8_grey  | cubic_catmull_rom            | direct | 1.95 | 3.79 | 6.91 |
| quad4newton | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.91 | 3.74 | 6.83 |
| quad4newton | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.91 | 3.70 | 6.85 |
| quad4newton | tex8_grey  | lanczos3_lut                 | lerp   | 1.93 | 3.73 | 7.04 |
| quad4newton | tex8_grey  | linear                       | direct | 1.87 | 3.58 | 6.28 |
| quad4newton | tex8_grey  | quintic_bspline              | direct | 1.93 | 3.78 | 7.13 |
| quad4newton | tex8_grey  | quintic_bspline_lut          | lerp   | 1.91 | 3.77 | 7.13 |
| quad4newton | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.90 | 3.62 | 6.28 |
| quad4newton | tex8_rgb   | cubic_catmull_rom            | direct | 1.91 | 3.68 | 6.50 |
| quad4newton | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.91 | 3.61 | 6.30 |
| quad4newton | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.91 | 3.56 | 6.30 |
| quad4newton | tex8_rgb   | lanczos3_lut                 | lerp   | 1.93 | 3.53 | 6.52 |
| quad4newton | tex8_rgb   | linear                       | direct | 1.89 | 3.50 | 6.09 |
| quad4newton | tex8_rgb   | quintic_bspline              | direct | 1.94 | 3.71 | 6.84 |
| quad4newton | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.94 | 3.52 | 6.55 |
| quad8       | nodal_grey | -                            | -      | 1.94 | 3.53 | 6.35 |
| quad8       | nodal_rgb  | -                            | -      | 1.91 | 3.33 | 5.36 |
| quad8       | tex8_grey  | cubic_bspline_lut            | lerp   | 1.94 | 3.72 | 6.97 |
| quad8       | tex8_grey  | cubic_catmull_rom            | direct | 1.91 | 3.76 | 7.02 |
| quad8       | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.93 | 3.72 | 6.98 |
| quad8       | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.98 | 3.87 | 7.19 |
| quad8       | tex8_grey  | lanczos3_lut                 | lerp   | 1.94 | 3.83 | 7.05 |
| quad8       | tex8_grey  | linear                       | direct | 1.89 | 3.53 | 6.57 |
| quad8       | tex8_grey  | quintic_bspline              | direct | 1.96 | 3.78 | 7.16 |
| quad8       | tex8_grey  | quintic_bspline_lut          | lerp   | 1.93 | 3.77 | 7.19 |
| quad8       | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.94 | 3.70 | 6.52 |
| quad8       | tex8_rgb   | cubic_catmull_rom            | direct | 1.95 | 3.68 | 6.58 |
| quad8       | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.90 | 3.69 | 6.45 |
| quad8       | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.90 | 3.68 | 6.58 |
| quad8       | tex8_rgb   | lanczos3_lut                 | lerp   | 1.92 | 3.57 | 6.70 |
| quad8       | tex8_rgb   | linear                       | direct | 1.96 | 3.50 | 6.16 |
| quad8       | tex8_rgb   | quintic_bspline              | direct | 1.93 | 3.75 | 6.86 |
| quad8       | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.92 | 3.55 | 6.63 |
| quad9       | nodal_grey | -                            | -      | 1.89 | 3.54 | 6.30 |
| quad9       | nodal_rgb  | -                            | -      | 1.87 | 3.44 | 5.64 |
| quad9       | tex8_grey  | cubic_bspline_lut            | lerp   | 1.95 | 3.71 | 6.90 |
| quad9       | tex8_grey  | cubic_catmull_rom            | direct | 1.92 | 3.77 | 7.06 |
| quad9       | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.94 | 3.73 | 6.95 |
| quad9       | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.91 | 3.74 | 6.72 |
| quad9       | tex8_grey  | lanczos3_lut                 | lerp   | 1.95 | 3.68 | 6.73 |
| quad9       | tex8_grey  | linear                       | direct | 1.89 | 3.57 | 6.52 |
| quad9       | tex8_grey  | quintic_bspline              | direct | 1.96 | 3.80 | 7.08 |
| quad9       | tex8_grey  | quintic_bspline_lut          | lerp   | 1.93 | 3.77 | 7.04 |
| quad9       | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.94 | 3.62 | 6.43 |
| quad9       | tex8_rgb   | cubic_catmull_rom            | direct | 1.92 | 3.63 | 6.54 |
| quad9       | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.93 | 3.63 | 6.37 |
| quad9       | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.90 | 3.63 | 6.65 |
| quad9       | tex8_rgb   | lanczos3_lut                 | lerp   | 1.93 | 3.55 | 6.63 |
| quad9       | tex8_rgb   | linear                       | direct | 1.90 | 3.64 | 6.22 |
| quad9       | tex8_rgb   | quintic_bspline              | direct | 1.95 | 3.69 | 6.91 |
| quad9       | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.91 | 3.57 | 6.56 |
| tri3        | nodal_grey | -                            | -      | 1.65 | 2.75 | 3.36 |
| tri3        | nodal_rgb  | -                            | -      | 1.65 | 2.57 | 3.54 |
| tri3        | tex8_grey  | cubic_bspline_lut            | lerp   | 1.94 | 3.68 | 6.74 |
| tri3        | tex8_grey  | cubic_catmull_rom            | direct | 1.96 | 3.73 | 7.05 |
| tri3        | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.92 | 3.73 | 6.68 |
| tri3        | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.91 | 3.66 | 6.78 |
| tri3        | tex8_grey  | lanczos3_lut                 | lerp   | 1.92 | 3.49 | 6.98 |
| tri3        | tex8_grey  | linear                       | direct | 1.86 | 3.40 | 5.52 |
| tri3        | tex8_grey  | quintic_bspline              | direct | 1.93 | 3.79 | 7.27 |
| tri3        | tex8_grey  | quintic_bspline_lut          | lerp   | 1.95 | 3.47 | 6.92 |
| tri3        | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.91 | 3.48 | 6.14 |
| tri3        | tex8_rgb   | cubic_catmull_rom            | direct | 1.87 | 3.55 | 6.21 |
| tri3        | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.86 | 3.46 | 6.02 |
| tri3        | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.85 | 3.47 | 6.08 |
| tri3        | tex8_rgb   | lanczos3_lut                 | lerp   | 1.93 | 3.64 | 6.55 |
| tri3        | tex8_rgb   | linear                       | direct | 1.83 | 3.18 | 5.27 |
| tri3        | tex8_rgb   | quintic_bspline              | direct | 1.93 | 3.70 | 6.78 |
| tri3        | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.93 | 3.60 | 6.50 |
| tri6        | nodal_grey | -                            | -      | 1.85 | 3.51 | 6.00 |
| tri6        | nodal_rgb  | -                            | -      | 1.82 | 3.35 | 5.53 |
| tri6        | tex8_grey  | cubic_bspline_lut            | lerp   | 1.94 | 3.75 | 6.97 |
| tri6        | tex8_grey  | cubic_catmull_rom            | direct | 1.97 | 3.74 | 7.06 |
| tri6        | tex8_grey  | cubic_catmull_rom_lut        | lerp   | 1.94 | 3.75 | 7.06 |
| tri6        | tex8_grey  | cubic_mitchell_netravali_lut | lerp   | 1.94 | 3.73 | 6.96 |
| tri6        | tex8_grey  | lanczos3_lut                 | lerp   | 1.94 | 3.72 | 7.06 |
| tri6        | tex8_grey  | linear                       | direct | 1.94 | 3.55 | 6.69 |
| tri6        | tex8_grey  | quintic_bspline              | direct | 1.96 | 3.79 | 7.17 |
| tri6        | tex8_grey  | quintic_bspline_lut          | lerp   | 1.91 | 3.72 | 7.08 |
| tri6        | tex8_rgb   | cubic_bspline_lut            | lerp   | 1.94 | 3.65 | 6.45 |
| tri6        | tex8_rgb   | cubic_catmull_rom            | direct | 1.92 | 3.67 | 6.55 |
| tri6        | tex8_rgb   | cubic_catmull_rom_lut        | lerp   | 1.91 | 3.67 | 6.47 |
| tri6        | tex8_rgb   | cubic_mitchell_netravali_lut | lerp   | 1.90 | 3.60 | 6.59 |
| tri6        | tex8_rgb   | lanczos3_lut                 | lerp   | 1.94 | 3.55 | 6.69 |
| tri6        | tex8_rgb   | linear                       | direct | 1.88 | 3.53 | 6.32 |
| tri6        | tex8_rgb   | quintic_bspline              | direct | 1.95 | 3.73 | 6.93 |
| tri6        | tex8_rgb   | quintic_bspline_lut          | lerp   | 1.95 | 3.59 | 6.67 |
```
