# Performance Summary: Element Throughput (MElems/s)

## Benchmark: geom

### By Element Type (Median across interpolators)

| Element | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| quad4ibi | 13.07 (1.00x) | 29.41 (2.25x) | 35.62 (2.72x) | 32.45 (2.48x) |
| quad4newton | 13.10 (1.00x) | 30.33 (2.31x) | 35.98 (2.75x) | 33.30 (2.54x) |
| quad8 | 2.97 (1.00x) | 12.53 (4.21x) | 15.46 (5.20x) | 15.79 (5.31x) |
| quad9 | 2.69 (1.00x) | 12.04 (4.48x) | 14.66 (5.46x) | 15.15 (5.64x) |
| tri3 | 13.28 (1.00x) | 42.59 (3.21x) | 50.37 (3.79x) | 48.55 (3.66x) |
| tri6 | 3.74 (1.00x) | 16.71 (4.47x) | 21.16 (5.66x) | 21.76 (5.83x) |

## Benchmark: sphere2000

### By Element Type (Median across interpolators)

| Element | 1 Thread | 2 Threads | 4 Threads | 8 Threads |
| :--- | :--- | :--- | :--- | :--- |
| quad4ibi | 17.12 (1.00x) | 7.26 (0.42x) | 3.77 (0.22x) | 1.94 (0.11x) |
| quad4newton | 17.19 (1.00x) | 7.48 (0.44x) | 3.75 (0.22x) | 1.97 (0.11x) |
| quad8 | 6.16 (1.00x) | 4.87 (0.79x) | 3.40 (0.55x) | 1.87 (0.30x) |
| quad9 | 5.96 (1.00x) | 4.88 (0.82x) | 3.45 (0.58x) | 1.83 (0.31x) |
| tri3 | 23.66 (1.00x) | 13.79 (0.58x) | 7.80 (0.33x) | 4.14 (0.18x) |
| tri6 | 8.95 (1.00x) | 9.39 (1.05x) | 8.41 (0.94x) | 5.14 (0.58x) |

