# High-Performance SIMD Rasterizer Features

Based on the comparison of the SIMD implementations in `examples-simd/`, the following features provide the maximum performance boost and should be integrated into the main rasterizer.

### 1. Incremental Edge Updates (Strength Reduction)
Instead of recalculating the edge functions for every SIMD block, use the **stepping approach**.
*   **The Feature:** Pre-calculate `dw_dx` and `dw_dy` for each triangle.
*   **Performance Gain:** Replaces expensive multiplications and subtractions inside the hot loop with a single SIMD addition (`v_w0 += v_dw0_step`).

### 2. Pure SIMD Control Flow (Branchless)
The basic version drops back to scalar code for depth testing and field updates. The optimized version stays in "vector-land" for the entire pixel pipe.
*   **The Feature:** Use SIMD comparison masks and the **`@select`** intrinsic.
*   **Performance Gain:** Allows the CPU to process 8 pixels at once without the pipeline stalls caused by branching (`if` statements) or the overhead of switching between vector and scalar registers.

### 3. Planar Memory Layout (SIMD-Friendly Data)
The way data is arranged in scratch memory is critical.
*   **The Feature:** Use **Planar Layout** (storing all Red values, then all Green, etc.) rather than Interleaved (RGB, RGB).
*   **Performance Gain:** Enables **Contiguous SIMD Stores**. The CPU can write 8 "Red" values to memory in a single instruction. Interleaved data would require complex "shuffle" or "scatter" instructions, which are significantly slower.

### 4. 64-Byte Memory Alignment
SIMD hardware is most efficient when data starts at specific memory boundaries.
*   **The Feature:** Use **`allocator.alignedAlloc`** with a 64-byte alignment for all scratch buffers.
*   **Performance Gain:** Prevents "Cache Line Splits" where a single 8-wide vector load spans two cache lines, which would otherwise double the memory traffic for that operation.

### 5. Pre-Splatted Constants
Repeatedly "splatting" a scalar value into a vector inside a loop is a hidden performance killer.
*   **The Feature:** Move `@splat` operations for nodal values (like `inv_z` and field terms) outside the pixel loops.
*   **Performance Gain:** Reduces the total instruction count in the innermost loop.

### 6. Early-Out SIMD Masking
Even though the code is branchless, it still uses a "smart" early-out.
*   **The Feature:** Use `if (@reduce(.Or, mask))` before performing heavy calculations like division or field interpolation.
*   **Performance Gain:** If all 8 pixels in a SIMD block fail the edge or depth test, the entire block is skipped instantly, saving significant cycles on empty areas of the tile.

---

### Recommended "Best of" Architecture:

| Phase | Best Feature to Use |
| :--- | :--- |
| **Allocation** | `alignedAlloc(64)` for all tile scratch buffers. |
| **Setup** | Pre-calculate `dw_dx/dy` and `@splat` nodal field terms. |
| **Outer Loop** | 32x32 Tiling to keep data in L1/L2 cache. |
| **Inner Loop** | Incremental `v_w` updates + `@select` for depth/color updates. |
| **Finalize** | Planar-to-Interleaved conversion only during the final `averageScratch` pass. |
