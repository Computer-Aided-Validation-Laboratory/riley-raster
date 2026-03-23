# SIMD Refactoring Plan for `src-simd`

## Overview
The current SIMD implementation in `src-simd` underperforms because it frequently falls back to scalar loops for depth testing, field updates, and vector initialization. This plan adopts the "True SIMD Pipeline" strategy from the successful `simdraster.zig` example.

## 1. Identification of Bottlenecks in `src-simd`
*   **Scalar Initialization:** `getWeightsAtSIMD` uses `inline for` loops instead of `v_offsets` patterns.
*   **Depth Buffer Serialization:** `rasterIncremental` uses scalar loops to load and compare depth values from the scratch buffer.
*   **Shader Scalar Branching:** `shadeSIMD` reverts to scalar loops when updating multiple fields, negating SIMD gains for non-flat shading.
*   **Alignment:** Scratch buffers lack strict 64-byte alignment, leading to suboptimal memory throughput.

## 2. Refactoring Strategy

### A. Core Engine (`rasterenginesimd.zig`)
*   **Vectorized Depth Test:** Replace scalar load/compare loops with direct vector loads and `@select` intrinsics.
*   **Incremental SIMD Updates:** Implement scanline-parallel updates using `v_weights += v_dwdx_step` (where `step = dwdx * L`).
*   **OOB Masking:** Use a single pre-calculated `mask_lane` only for the final partial block of a scanline.

### B. Geometry Kernels (`geomkernsimd.zig`)
*   **Native SIMD Initialization:** Replace scalar loops in `getWeightsAtSIMD` with `v_offsets` based calculations.
*   **Interface Hardening:** Ensure all kernels strictly adhere to the `IncrementalSIMD` interface without scalar fallbacks.

### C. Shader Kernels (`shaderkernsimd.zig`)
*   **Vectorized Multi-field Updates:** Rewrite field update logic to use `@select` across the entire lane for each field, eliminating `inline for (0..L)` loops.
*   **Memory Alignment:** Ensure `spx_image_scratch` and `inv_z` buffers are 64-byte aligned.

## 3. Implementation Phases

1.  **Phase 1: Foundation.** Update `rasterops.zig` to ensure 64-byte aligned scratch buffers.
2.  **Phase 2: Geometry.** Refactor `Tri3OptKernel` in `geomkernsimd.zig` for native vector initialization.
3.  **Phase 3: Core Loop.** Refactor `rasterIncremental` in `rasterenginesimd.zig` to implement the vectorized depth test and incremental updates.
4.  **Phase 4: Shaders.** Update `FlatKernelSIMD` and `NormalKernelSIMD` to use `@select` for all field updates.
5.  **Phase 5: Validation.** Run `test_gold_all.zig` and `test_bench_fullscreen.zig` to ensure bit-perfect output and verify performance improvements.
