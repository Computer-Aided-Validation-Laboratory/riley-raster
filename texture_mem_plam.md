# Texture Memory Layout Overhaul Plan: Planar [C, Y, X]

This plan outlines the architectural shift from Interleaved (AoS) to Planar (SoA) texture memory storage to enable high-efficiency SIMD gathering and contiguous row-chunk loading.

## Phase 1: Redefine the Texture Core (`imageio.zig`)
*   **Backing Storage:** Replace the current interleaved slice with an `NDArray(f64)`.
*   **Axis Ordering:** Set dimensions to strictly `[channels, rows, cols]`.
*   **Loading Logic:** Update `loadImage` and `loadTexture` to perform planar de-interleaving during the loading phase (storing R, G, and B in separate memory planes).

## Phase 2: Vectorized Texel Fetching (`textureops.zig`)
*   **Unified SIMD Fetch:** Implement `v_getPxSIMD` that takes `@Vector(8, isize)` for both X and Y coordinates.
*   **Planar Indexing:** Offset calculation becomes `(channel * plane_size) + (v_yi * stride_y) + v_xi`.
*   **Row-Chunk Optimization:** Implement a fast-path that detects monotonic `v_xi` and identical `v_yi`. If detected, perform a single contiguous vector load (`v_res = ptr[base..][0..8].*`) instead of a gather loop.

## Phase 3: High-Order Interpolation Refactoring (`textureops.zig`)
*   **Plane-at-a-Time Shading:** refactor the SIMD loops for cubic and quintic kernels to process one color plane at a time across all 8 lanes.
*   **Register Residency:** Keep interpolation weights in registers and apply them to the fetched pixel planes without re-calculating for each channel.

## Phase 4: Integration and Regression
*   **Shaders:** Update `shaderops.zig` to interface with the new `NDArray`-backed texture.
*   **Mesh Prep:** Update `meshraster.zig` to ensure texture data is correctly prepared.
*   **Correctness:** Pass `test_gold_all.zig` (101 tests).
*   **Performance:** Run `bench_fullraster.zig` to quantify gains from planar fetches and row-chunking.

## Phase 5: Porting to src-simd2
*   Once verified in `src-simd`, port the changes to `src-simd2` to benefit the unrolled implementation (Option B).
