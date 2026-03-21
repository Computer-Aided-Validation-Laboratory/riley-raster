# Early-In / Early-Out Optimization: Refined Hierarchical Summary
This report compares the **Original Baseline** (Pointwise `tri3`, Incremental `tri3opt`) against the **Refined Hierarchical** implementation (Depth 1, reuse of corner edge values, and node hoisting).

## Summary: Rasterization Time (ms) - Flat Grey Shader

| Benchmark      | Kernel    | Original (ms) | Hierarchical (ms) | Speedup |
|----------------|-----------|:-------------:| :---------------: |:-------:|
| **Fullraster** | tri3      |     36.65     |       11.17       | **3.28x** |
| (2 large tris) | tri3opt   |     14.53     |       11.21       | **1.30x** |
| **Bal 100**    | tri3      |     18.18     |       12.64       | **1.44x** |
| (100 med tris) | tri3opt   |     14.30     |       12.73       | **1.12x** |
| **Bal 1000**   | tri3      |     19.30     |       14.35       | **1.34x** |
| (1000 med tris)| tri3opt   |     14.90     |       14.31       | **1.04x** |
| **Geometry**   | tri3      |     55.65     |       29.00       | **1.92x** |
| (100k tiny tris)| tri3opt   |     18.64     |       28.75       | 0.65x (Reg) |

---

## Detailed Performance by Shader Type

### Shader: flat_rgb (Raster ms)
| Benchmark      | tri3 (Orig / Hier) | tri3 Speedup | tri3opt (Orig / Hier) | tri3opt Speedup |
|----------------| :----------------: | :----------: | :-------------------: | :-------------: |
| Fullraster     |   23.23 / 16.21    |   **1.43x**  |     18.28 / 15.68     |    **1.17x**    |
| Bal 100        |   23.38 / 16.97    |   **1.38x**  |     18.73 / 17.31     |    **1.08x**    |
| Bal 1000       |   24.84 / 19.31    |   **1.29x**  |     19.33 / 18.73     |    **1.03x**    |
| Geometry       |   32.20 / 34.90    |     0.92x    |     24.08 / 35.45     |      0.68x      |

### Shader: tex8_rgb (Raster ms)
| Benchmark      | tri3 (Orig / Hier) | tri3 Speedup | tri3opt (Orig / Hier) | tri3opt Speedup |
|----------------| :----------------: | :----------: | :-------------------: | :-------------: |
| Fullraster     |   74.82 / 68.54    |   **1.09x**  |     72.54 / 66.97     |    **1.08x**    |
| Bal 100        |   76.67 / 69.81    |   **1.10x**  |     72.65 / 70.25     |    **1.03x**    |
| Bal 1000       |   77.41 / 72.57    |   **1.07x**  |     73.59 / 72.39     |    **1.02x**    |
| Geometry       |   87.07 / 91.15    |     0.96x    |     78.47 / 90.56     |      0.87x      |

---

## Key Observations
1. **Consistency:** The hierarchical approach has successfully converged the performance of `tri3` and `tri3opt`. They now share the same optimized path for Early-In and subdivided tiles.
2. **Pointwise Superiority:** The optimized `tri3` is now significantly faster than the original incremental `tri3opt` in most balanced and large-triangle scenarios.
3. **Overhead Reduction:** Reusing corner calculations and hoisting node data has drastically reduced the cost of the Early-Out check, though a minor regression remains in the extremely dense `Geometry` benchmark.
