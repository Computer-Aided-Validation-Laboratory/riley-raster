# Benchmark Suite Overview

The benchmarking suite consists of a set of Zig programs in `./src/` that perform the actual rendering and timing, and Python scripts in `./scripts/` that orchestrate high-level experiments by running these binaries with various configurations.

## 1. General Benchmarks
Most benchmarks use a standard experiment matrix defined in `scripts/bench_common.py`. They are:
*   **`bench_fullraster`**: Renders a large mesh that fills the entire viewport. It is designed to maximize pixel load, testing the throughput of the rasterization and shading stages.
*   **`bench_geom`**: Renders a mesh with high geometric complexity but lower pixel coverage. It focuses on the geometry processing pipeline, vertex shading, and tile-based culling.
*   **`bench_sphere2000`**: A standard balanced workload rendering a sphere with ~2,000 elements.
*   **`bench_sphere2000zoom`**: The same sphere model but with a 0.5x FOV (zoomed in). This shifts the bottleneck toward rasterization by increasing the pixel area covered by the mesh.

**Experiments covered (General):**
*   **Experiment 1 (SIMD vs Scalar)**: Compares the `simd` and `scalar` binaries (built via `compile_benchmarks.sh`) across `disk` and `memory` save strategies to measure the raw benefit of SIMD optimizations.
*   **Experiment 2 (Hull Mode)**: Evaluates the performance impact of the "Hull Mode" optimization (`on_no_fallback` vs `off`).

## 2. Specialized DIC UQ Benchmark
The **`bench_dicuq`** (`scripts/bench_dicuq.py` and `src/bench_dicuq.zig`) benchmark is more sophisticated. It simulates a real-world Digital Image Correlation (DIC) Uncertainty Quantification (UQ) workload, which involves rendering multiple camera positions (frames) for a single mesh.

**Experiments covered (DIC UQ):**
*   **Experiment 1 (Thread Scaling)**: Tests scaling from 1 to 8 total threads, with balanced geometry and rasterization thread allocation.
*   **Experiment 2 (Geometry Bottleneck)**: Fixes geometry processing to a single thread while scaling rasterization threads to identify if geometry processing is a limiting factor.
*   **Experiment 3 (Frames in Flight)**: Measures the impact of concurrent frame rendering (1, 2, or 4 frames at a time).
*   **Experiment 4 (Render Mode)**: Compares `offline` (batch) rendering against `in_order` (sequential) rendering.

## 3. Supporting Infrastructure
*   **`scripts/compile_benchmarks.sh`**: A utility script that builds both `scalar` and `simd` versions of all benchmarks by temporarily modifying `src/zraster/zig/buildconfig.zig`.
*   **`src/common/benchcommon.zig`**: The shared Zig library that handles the benchmark loop, data loading, case name generation, and result reporting.
*   **`scripts/bench_common.py`**: The Python module containing the logic for the general experiment matrix and subprocess management.
