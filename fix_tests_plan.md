# Plan for Fixing Tests and Benchmarks

## 1. Core Configuration & Defaults
*   **`zraster.zig`**: Update `RasterConfig` to set the default `tile_size` to `32`.
*   **`camera.zig`**: Update `Camera.init` to default `sub_sample` to `2` if `0` is passed.
*   **Explicit Cleanup**: Remove all manual overrides of `tile_size` and `sub_sample` in tests and benchmarks.

## 2. Performance Reporting (`perf.zig` & `zraster.zig`)
*   **Metric Definitions**:
    *   Add **`MPx/second`** to performance blocks.
    *   Reorder reports: **Elements** before **Pixels**.
    *   Add **`Visible %`** (Visible/Total Elems) and **`Shaded %`** (Shaded/Total SubPx).
*   **Reporting Logic**:
    *   Update `standardReport` and `writeReport` to calculate `MOps/s` using `nodes_per_elem`.
    *   Split `.bench` mode report into **Counts/Coverage** and **Throughput** blocks.
    *   Integrate `.bench` mode into `rasterAllFrames` for minimal `Perf` initialization.

## 3. Benchmark Infrastructure & Compile-Time Optimization
*   **`meshraster.zig`**: Add `MeshType.getNodesNum()`.
*   **`bench_common.zig`**: 
    *   Change `shouldRun` to take `BenchConfig` as a regular runtime parameter.
*   **`test_bench.zig`**:
    *   Refactor triple-nested `inline for` loops into standard runtime `for` loops.
*   **`tests.zig`**:
    *   Delete hardcoded pixel unit tests (e.g., Scaling Options) in favor of gold-image comparison.

## 4. Import & Path Corrections
*   Standardize imports to use direct file paths.
*   Fix missing `.zig` extensions in imports.

## 5. Execution Order
1.  Apply changes to `src-simd/zigraster/zig/`.
2.  Refactor `src-simd/common/` and `src-simd/bench_common.zig`.
3.  Update `src-simd/test_bench.zig`.
4.  Run tests for `src-simd` (some failures expected in sphere/multimesh RGB).
5.  Repeat steps 1-3 for `src-simd2/`.
6.  Run tests for `src-simd2` (all should pass).
