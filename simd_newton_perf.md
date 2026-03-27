# Performance Comparison: Vectorized Newton Solver vs. Baseline

The following table compares the **Raster Loop Time** (median) between the baseline implementation in `src` and the new SIMD implementation in `src-simd`.

**Benchmark Settings:**
- **Resolution**: 800x500
- **Optimization**: `-O ReleaseFast`
- **CPU**: (Host Environment)
- **Runs per Case**: 5

| Mesh Type       | Shading Case         | Baseline (ms) | SIMD (ms) | **Speedup** |
| :-------------- | :------------------- | :-----------: | :-------: | :---------: |
| **Tri6**        | Flat (Grey)          |     59.64     |   24.30   |  **2.45x**  |
| **Tri6**        | Texture (Cubic LUT)  |    100.08     |   54.70   |  **1.83x**  |
| **Quad4Newton** | Flat (Grey)          |     40.11     |   19.58   |  **2.05x**  |
| **Quad4Newton** | Texture (Cubic LUT)  |     75.66     |   49.23   |  **1.54x**  |
| **Quad8**       | Flat (Grey)          |     69.34     |   27.38   |  **2.53x**  |
| **Quad8**       | Texture (Cubic LUT)  |    114.18     |   58.97   |  **1.94x**  |
| **Quad9**       | Flat (Grey)          |     69.13     |   28.66   |  **2.41x**  |
| **Quad9**       | Texture (Cubic LUT)  |    114.20     |   58.90   |  **1.94x**  |

### Analysis
The vectorized Newton solver pipeline provides a substantial performance boost for higher-order kernels. By solving for 8 pixels simultaneously and utilizing a three-pass system that filters out exterior pixels before the expensive Newton-Raphson iteration, we achieve between **1.5x and 2.5x** throughput improvement. The gains are most pronounced in "heavy" kernels like `Quad8` and `Tri6` where the shape function evaluations and Jacobian calculations are complex.
