# SIMD Naming Fix Plan

1. Keep `v_` as the marker for actual SIMD vectors.
2. Use `v_splat_` for vectors created with `@splat(...)`.
3. Use `v_mask_` for SIMD boolean masks.
4. Use `lane_` for scalar lane arrays like `[S]f64` or `[S]bool`.
5. Replace opaque lane-index names like `v_07` and `x07` with
   semantic names such as `v_lane_idx` and `v_dx_lane_offset`.
6. Update `TriWeightStepSIMD` and `Tri3Kernel.getSIMDSteps()` first, since
   these names are currently the most misleading.
7. Rename SIMD locals in the main SIMD-heavy files:
   - `src/zraster/zig/geometrykernels.zig`
   - `src/zraster/zig/rasterengine_simd.zig`
   - `src/zraster/zig/newton.zig`
   - `src/zraster/zig/hull_simd.zig`
   - `src/zraster/zig/rasterops.zig`
   - `src/zraster/zig/shapefun.zig`
   - `src/zraster/zig/shaderops_simd.zig`
   - `src/zraster/zig/textureops_simd.zig`
   - `src/zraster/zig/report.zig`
8. Remove misleading scalar names that use `v_` but are not SIMD values.
9. Run `zig fmt` on touched files.
10. Run:
    - `zig test -lc -O ReleaseSafe ./src/test_gold_all.zig`
    - `zig test -lc -O ReleaseSafe ./src/test_bench.zig`
    and fix any fallout.
