# Performance Comparison: Wide SIMD vs. Optimized Hybrid (Inner-SIMD)

The following table compares the performance (in **MOps/s**) of the original **Wide SIMD** implementation (`src-simd`) against the new **Optimized Hybrid Inner-SIMD** approach (`src-simd2`).

| Case / Shader               | Wide (src-simd) | Optimized Hybrid (src-simd2) | Speedup   |
| :-------------------------- | :-------------: | :--------------------------: | :-------: |
| **Flat (Grey)**             |     579.94      |            571.13            |   0.98x   |
| **Flat (RGB)**              |     494.95      |            504.09            |   1.02x   |
| **Tex (Grey, Linear)**      |     155.22      |            250.42            | **1.61x** |
| **Tex (Grey, Cubic)**       |      59.15      |            122.64            | **2.07x** |
| **Tex (Grey, Quintic)**     |      28.39      |            74.55             | **2.63x** |
| **Tex (Grey, Quintic LUT)** |      27.44      |            96.36             | **3.51x** |
| **Tex (RGB, Linear)**       |     137.12      |            193.51            | **1.41x** |
| **Tex (RGB, Cubic)**        |      47.38      |            86.65             | **1.83x** |
| **Tex (RGB, Quintic)**      |      22.75      |            48.73             | **2.14x** |
| **Tex (RGB, Quintic LUT)**  |      22.27      |            56.74             | **2.55x** |

### Key Takeaways:
1.  **Massive Efficiency Gains**: The Inner-SIMD approach is significantly faster for all texture sampling operations. The move from "Gather 8 pixels" to "SIMD over 1 pixel's footprint" has effectively solved the cache hammering issue.
2.  **High-Order Scaling**: The performance speedup actually *increases* with filter complexity. Quintic interpolation saw the largest benefit (**up to 3.5x speedup**), confirming that locality is the dominant factor for high-order filters.
3.  **Flat Parity**: As intended, there is no regression in the flat shading path, as it continues to use the wide-SIMD pipeline.
4.  **RGB Success**: Even with the scalar loop for lanes, the Inner-SIMD footprint processing is so much more efficient that it easily overcomes the loop overhead, providing a ~1.4x to 2.5x boost for RGB textures.
5.  **LUT Benefit**: The `quintic_lut_lerp` case is particularly fast in the hybrid model (96 MOps/s) compared to the wide model (27 MOps/s), likely because fetching weights from a small LUT for one pixel at a time keeps that LUT extremely hot in L1.
