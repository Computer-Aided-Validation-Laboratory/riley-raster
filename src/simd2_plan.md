# SIMD Option 2: SIMD Gather + Vectorized Interpolation

This plan outlines the implementation of Option 2 in `src-simd2`, focusing on vectorizing the internal logic of texture sampling.

## Core Strategy: Vectorized Sampling Loop
Instead of deferring shading, we perform vectorized texture lookups directly within the main 8-wide SIMD loop.

### 1. Vectorized UV Calculation
*   Interpolate UV coordinates for all 8 pixels simultaneously using `@Vector(8, f64)` math.
*   `v_u = sum(v_weights[i] * u_i)`
*   `v_v = sum(v_weights[i] * v_i)`

### 2. SIMD Coordinate Transformation
*   Convert 8 normalized (u,v) coordinates to 8 texture pixel coordinates (x_f, y_f) in parallel.
*   Perform 8-wide `floor()` and `subtraction` to get integer indices (x_i, y_i) and fractional offsets (tx, ty).

### 3. Optimized Texture Fetching (Gather-like)
*   For each active pixel in the 8-wide vector, fetch the required 4 (linear) or 16 (cubic) raw texels.
*   Since Zig/Hardware might not support true 8-wide gather for generic structs, we will implement a tight fetch loop that loads raw data into vector registers.

### 4. Vectorized Interpolation Math
*   Perform the interpolation math (e.g., bilinear lerp) entirely in vector registers using the gathered data and the fractional offsets (tx, ty).
*   Example: `res = (1-tx)*(1-ty)*p00 + tx*(1-ty)*p10 + ...`

### 5. Masked Planar Stores
*   Apply the final results to the planar scratch buffer using the mask and contiguous stores where possible (using unaligned pointer casts as verified in Phase 1).

## Verification
*   Pass all gold tests in `src-simd2/test_gold_all.zig`.
*   Maintain the Planar Memory layout established in Phase 1.
