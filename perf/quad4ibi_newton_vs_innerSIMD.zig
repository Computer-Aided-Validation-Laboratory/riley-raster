// Quad4IBI Inner-SIMD vs Quad4Newton
//
// This file stores the MPx/s comparison extracted from:
// - perf/quad4ibi_innersimd/fullraster.md
// - perf/quad4ibi_innersimd/geom.md
// - perf/quad4ibi_innersimd/sphere2000.md
//
// Diff is (quad4ibi - quad4newton) / quad4newton.
//
// Fullraster
//
// | Case                    | quad4ibi MPx/s | quad4newton MPx/s | Diff vs quad4newton |
// |-------------------------|---------------:|------------------:|--------------------:|
// | flat_grey               |          21.55 |             19.15 |              +12.5% |
// | flat_rgb                |          15.21 |             16.03 |               -5.1% |
// | tex8_grey_linear        |          13.70 |             13.28 |               +3.2% |
// | tex8_grey_cubic         |           7.16 |              7.29 |               -1.8% |
// | tex8_grey_cubic_lut     |           7.20 |              7.62 |               -5.5% |
// | tex8_grey_quintic       |           4.75 |              4.49 |               +5.8% |
// | tex8_grey_quintic_lut   |           5.74 |              5.77 |               -0.5% |
// | tex8_rgb_linear         |          10.74 |             10.52 |               +2.1% |
// | tex8_rgb_cubic          |           5.95 |              5.85 |               +1.7% |
// | tex8_rgb_cubic_lut      |           5.71 |              5.96 |               -4.2% |
// | tex8_rgb_quintic        |           3.35 |              3.42 |               -2.0% |
// | tex8_rgb_quintic_lut    |           4.22 |              4.34 |               -2.8% |
//
// Geom
//
// | Case                    | quad4ibi MPx/s | quad4newton MPx/s | Diff vs quad4newton |
// |-------------------------|---------------:|------------------:|--------------------:|
// | flat_grey               |          14.43 |              8.71 |              +65.7% |
// | flat_rgb                |          11.46 |              7.74 |              +48.1% |
// | tex8_grey_linear        |          10.68 |              7.59 |              +40.7% |
// | tex8_grey_cubic         |           6.19 |              5.10 |              +21.4% |
// | tex8_grey_cubic_lut     |           6.22 |              5.22 |              +19.2% |
// | tex8_grey_quintic       |           4.20 |              3.51 |              +19.7% |
// | tex8_grey_quintic_lut   |           4.98 |              4.25 |              +17.2% |
// | tex8_rgb_linear         |           8.85 |              6.67 |              +32.7% |
// | tex8_rgb_cubic          |           5.22 |              4.38 |              +19.2% |
// | tex8_rgb_cubic_lut      |           5.03 |              4.38 |              +14.8% |
// | tex8_rgb_quintic        |           3.08 |              2.81 |               +9.6% |
// | tex8_rgb_quintic_lut    |           3.84 |              3.43 |              +12.0% |
//
// Sphere2000
//
// | Case                    | quad4ibi MPx/s | quad4newton MPx/s | Diff vs quad4newton |
// |-------------------------|---------------:|------------------:|--------------------:|
// | flat_grey               |          12.11 |             21.12 |              -42.7% |
// | flat_rgb                |          10.24 |             18.17 |              -43.6% |
// | tex8_grey               |          10.73 |             16.44 |              -34.7% |
// | tex8_rgb                |           9.29 |             13.62 |              -31.8% |
//
// Read
//
// - fullraster: mixed result, no clear win for inner-SIMD quad4ibi
// - geom: quad4ibi remains substantially faster than quad4newton
// - sphere2000: inner-SIMD quad4ibi is much slower than quad4newton
//
// Conclusion:
// This inner-SIMD experiment did not improve the realistic sphere case.
// It made quad4ibi vs quad4newton materially worse there.
