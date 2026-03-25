# Tri3 Performance Summary (Refined SIMD)

The table below shows the performance in **MOps/s** (Million Operations per Second) for the `Tri3` and `Tri3Opt` kernels across different shaders and interpolants, as measured on the current system using the refined SIMD implementation.

| Case / Shader               | Flat (Grey) | Flat (RGB) | Tex (Grey) | Tex (RGB) |
| :-------------------------- | :---------: | :--------: | :--------: | :-------: |
| **Tri3 (Linear)**           | **569.73**  |   498.13   |   162.55   |   136.17  |
| **Tri3Opt (Linear)**        | **575.73**  |   498.19   |   162.23   |   134.88  |
| **Tri3 (Cubic)**            |      -      |      -     |    58.84   |    48.08  |
| **Tri3 (Cubic LUT Lerp)**   |      -      |      -     |    55.00   |    46.03  |
| **Tri3 (Quintic)**          |      -      |      -     |    28.25   |    22.61  |
| **Tri3 (Quintic LUT Lerp)** |      -      |      -     |    27.36   |    22.14  |

### Observations:
1.  **Peak Performance**: The implementation reaches a peak of **~575 MOps/s** with flat shading. The overhead of RGB processing reduces this by about 12-13%.
2.  **Texturing Cost**: Moving from flat shading to linear texturing results in a ~3.5x drop in throughput (from ~570 to ~162 MOps/s) due to the complexity of UV interpolation and texture sampling.
3.  **Interpolant Complexity**: There is a steep performance cliff as interpolation quality increases:
    *   **Linear**: ~162 MOps/s (Reference)
    *   **Cubic**: ~59 MOps/s (~2.7x slower than Linear)
    *   **Quintic**: ~28 MOps/s (~5.8x slower than Linear)
4.  **Tri3 vs Tri3Opt**: In the SIMD implementation, the difference between the standard and "optimized" kernels is negligible (<1%). This suggests that the SIMD pipeline is the primary driver of performance, and the incremental weight calculation in `Tri3Opt` offers little additional benefit when processing 8 pixels at once.
