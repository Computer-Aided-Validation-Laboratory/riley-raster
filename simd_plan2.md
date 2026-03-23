# SIMD Implementation Plan (Revised)

This plan outlines the architectural steps to integrate high-performance SIMD features into the `src-simd` workspace, moving from scalar processing to an 8-wide SIMD pipeline.

## Phase 1: Planar Memory Foundation
Currently, `ScratchBuffers` use an interleaved layout (RGBRGB). SIMD is most efficient with **Planar Layout** (RRR..., GGG..., BBB...).
*   **Action:** Update `rasterengine.zig` to swap `MatSlice` dimensions so rows represent fields and columns represent sub-pixels.
*   **Action:** Update `shaderops.zig` and `shaderkernels.zig` to use planar indexing (`field * total_pixels + pixel_idx`).
*   **Action:** Update `averageScratch` in `rasterengine.zig` to read from the planar layout.
*   **Benefit:** Enables **Contiguous SIMD Stores**, allowing the CPU to write 8 results for a field in a single instruction.

## Phase 2: Geometry Kernel SIMD Extensions
Extend `Tri3Kernel` and `Tri3OptKernel` in `geometrykernels.zig` to support vectorized setup.
*   **Action:** Implement `getSIMDConstants` to return `@Vector(8, f64)` splatted nodal values (inv_z, field terms).
*   **Action:** Implement `getSIMDSteps` to provide horizontal (`dw_dx`) and vertical (`dw_dy`) increments as vectors.
*   **Benefit:** Enables **Strength Reduction** and avoids repeated `@splat` operations in hot loops.

## Phase 3: The SIMD Rasterizer Loop
Implement a new `rasterSIMD` loop in `rasterengine.zig` processing 8 sub-pixels per iteration.
*   **Action:** Use incremental updates: `v_weights += v_dw_dx_step`.
*   **Action:** Implement **Early-Out Masking** using `if (@reduce(.Or, v_mask) == 0) continue;`.
*   **Action:** Use the **`@select`** intrinsic for branchless depth and color updates.
*   **Benefit:** Maximizes throughput by staying in vector registers and avoiding pipeline stalls from branching.

## Phase 4: Vectorized Shaders
Implement `shadeSIMD` for `Flat` shader kernels.
*   **Action:** Perform 8-wide perspective-correct field interpolation using vector math.
*   **Action:** Perform contiguous vectorized stores into the planar scratch buffer.

## Phase 5: Verification & Benchmarking
*   **Correctness:** Pass `src-simd/test_gold_all.zig`.
*   **Consistency:** Pass `src-simd/test_bench_fullscreen.zig`.
*   **Performance:** Compare MOps/s and MTri/s against the `src/` directory.
