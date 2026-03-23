# SIMD Implementation Plan for Tri3/Tri3Opt Kernels

This plan outlines the steps to incorporate high-performance SIMD features (as defined in `simd_best.md`) into the `src-simd` directory, focusing on `tri3` and `tri3opt` kernels with `.flat` shaders.

## 1. Memory Foundation & Alignment (Features 3 & 4)
*   **Action:** Update `ScratchBuffers` in `rasterengine.zig` to a **Planar** layout.
*   **Planar Layout:** Store fields as `[fields_num][subpx_total]` instead of interleaved `[subpx_total][fields_num]`.

## 2. Geometry Kernel SIMD Extensions (Features 1 & 5)
*   **Action:** Enhance `Tri3Kernel` and `Tri3OptKernel` in `geometrykernels.zig` with SIMD-specific methods.
*   **Pre-Splatted Constants:** Implement `getSIMDConstants` to return `@Vector(8, f64)` splatted nodal values (depth and field terms).
*   **Incremental Steps:** Implement `getSIMDSteps` to return `v_dw_dx` and `v_dw_dy` vectors for 8-wide iteration.

## 3. Core SIMD Rasterizer Loop (Features 1, 2, & 6)
*   **Action:** Add `rasterSIMD` to `RasterPass` in `rasterengine.zig`.
*   **Vectorization:** Process 8 sub-pixels per iteration using `@Vector(8, f64)`.
*   **Incremental Updates:** Use SIMD addition for edge weight updates (`v_w += v_dw_dx_step`).
*   **Early-Out Masking:** Skip blocks using `if (@reduce(.Or, v_mask) == 0) continue;`.
*   **Branchless Depth Test:** Use `@select` for updating the depth buffer without branching.

## 4. Vectorized Shader Integration (Feature 2)
*   **Action:** Implement `shadeSIMD` in `FlatKernel` (`shaderkernels.zig` / `shaderops.zig`).
*   **SIMD Interpolation:** Perform perspective-correct field interpolation using vector math.
*   **Contiguous Stores:** Write results to the planar scratch buffer using vectorized stores.

## 5. Efficient Finalization
*   **Action:** Update `averageScratch` in `rasterengine.zig` to handle the transition from planar scratch to interleaved output.
*   **Optimization:** Interleaving happens once during final averaging, keeping the hot loops purely planar and vectorized.

## 6. Verification & Benchmarking
1.  **Correctness:** Pass `zig test -lc -O ReleaseSafe src-simd/test_gold_all.zig`.
2.  **Regression:** Pass `zig test -lc -O ReleaseSafe src-simd/test_bench_fullscreen.zig`.
3.  **Performance:** Run `bench_fullraster.zig` and `bench_geom.zig` in both `src` and `src-simd` and compare results (MOps/s, MTri/s).
