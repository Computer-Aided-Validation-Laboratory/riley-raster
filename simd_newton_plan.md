# Plan: Vectorized Newton Solver for High-Order Kernels

The goal is to implement a high-performance, three-pass vectorized pipeline for geometry kernels that require non-linear weight solving (Newton-Raphson). This includes `Tri6`, `Quad4Newton`, `Quad8`, and `Quad9`.

## 1. Vectorized Shape Functions (`shapefun.zig`)
*   Implement `shapeFunctionsSIMD` for all target element types.
*   Use `@Vector(8, f64)` to compute shape values ($N_i$) and their derivatives ($dN/d\xi, dN/d\eta$) for 8 pixels simultaneously.

## 2. Vectorized Newton Solver (`newton.zig`)
*   Implement `solveInverseSIMD` to process 8 pixels in parallel.
*   Use a bit-mask (`@Vector(8, bool)`) to track convergence across lanes.
*   Vectorize the $2 \times 2$ Jacobian inversion and residual calculations.
*   Continue iterations until all active lanes have converged or reached `iter_max`.

## 3. Vectorized Coarse Check (`hull.zig` and `rasterops.zig`)
*   Implement `edgeFun3SIMD` in `rasterops.zig` to test 8 pixels against an edge simultaneously.
*   Implement `Tessellation.isInSIMD` in `hull.zig` to perform the coarse sub-tessellation check 8-wide.
*   Return both a mask and the initial $(\xi, \eta)$ guesses from the sub-triangle that matched the pixel.

## 4. Three-Pass Rasterizer Implementation (`rasterengine.zig`)
Implement a specialized `rasterSIMDNewton` function:

### Pass 1: Coarse Filtering & Candidate Generation
*   Iterate through the tile 8 pixels at a time.
*   Run the vectorized coarse check.
*   Store passing sub-pixels into a pre-allocated `CandidateBuffer` (scratch memory), including their coordinates and sub-tessellation initial guesses.

### Pass 2: Vectorized Weight Solving
*   Process the `CandidateBuffer` in chunks of 8.
*   Call `solveWeightsSIMD` (which uses `solveInverseSIMD`).
*   Store the converged parametric coordinates $(\xi, \eta)$ and a boolean success mask into tile-sized scratch buffers (`subpx_xi`, `subpx_eta`, `subpx_mask`).

### Pass 3: Spatially Grouped Shading
*   Iterate through the tile spatially in blocks of 8 (contiguous in memory).
*   Check the `subpx_mask` for the block.
*   If any pixels are active, re-calculate weights using `shapeFunctionsSIMD` and perform depth testing.
*   Call `shadeSIMD` for the block to perform either wide-flat shading or hybrid inner-SIMD texture shading.

## 5. Kernel Integration (`geometrykernels.zig`)
*   Add `solveWeightsSIMD` to `Tri6Kernel`, `Quad4NewtonKernel`, and `Quad89Kernel`.
*   Update these kernels to use the new `strategy = .newton_simd`.
*   Implement `getNewtonParams` (or `getInvElemArea`) to provide necessary constants to the solver.

## 6. Verification and Validation
*   **Correctness**: Verify using `test_gold_all.zig` to ensure results match the scalar reference (within epsilon).
*   **Integration**: Run `test_bench_fullscreen.zig` to confirm the new path works correctly across all unified tests.
*   **Performance**: Compare against the `src/` scalar baseline using `bench_fullraster.zig`.
