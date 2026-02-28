# GEMINI.md - Project Mandates & Engineering Standards

This document defines the foundational mandates for this workspace. These instructions take absolute precedence over general tool defaults.

## 🔬 Scientific & Engineering Principles
- **Numerical Stability:** Prioritize algorithms that minimize floating-point errors. Prefer Kahan summation or similar techniques when accumulating large sums.
- **Unit Verification:** Explicitly document units (SI preferred) for all physical constants and variables in comments or type aliases.
- **Reproducibility:** All simulations or data-processing scripts must support a `--seed` flag for deterministic output.
- **Accuracy vs. Performance:** Scientific correctness is the primary constraint. Performance optimizations (e.g., fast-math, lower precision) must be validated against a high-precision reference model. Document the acceptable error tolerance (e.g., ε < 1e-9) for all optimized kernels.

## 🛠 Language-Specific Standards

### Python (Scientific Stack)
- **Typing:** Strict Type Annotations are mandatory. Use `numpy.typing.NDArray` for all array-like structures.
- **Conventions:** Follow PEP 8. Use `ruff` for linting and formatting.
- **Performance:** Use NumPy/SciPy vectorization for hot loops. Use the `multiprocessing` module for CPU-bound parallel tasks to bypass the GIL.

### Cython (Pure Python Syntax)
- **Syntax:** **Strictly use Pure Python syntax** (`.py` files with decorators and type hints). Do not use `.pyx` or C-style `cdef` syntax. This ensures IDE compatibility and allows the code to run as standard Python when not compiled.
- **Integration:** Use `.pxd` files only when necessary for external C/C++ declarations.
- **Optimization:** Use `@cython.boundscheck(False)` and `@cython.wraparound(False)` decorators only after verifying memory safety with tests.

### C (System/High-Performance)
- **Safety:** Use `static` analysis tools (e.g., `clang-tidy`). Avoid `malloc` in performance-critical loops; prefer pre-allocation.
- **Parallelism:** Use OpenMP or pthreads for multi-threading. Leverage SIMD intrinsics or ensure code is structured for auto-vectorization (e.g., `restrict` pointers, alignment).
- **Build:** Use `CMake` as the primary build system.

### Zig (Modern Systems)
- **Error Handling:** Explicitly handle all errors. Do not use `try` unless the error is truly unrecoverable.
- **Allocators:** Always pass an `Allocator` as a parameter. Do not use a global allocator.
- **Performance:** Use `comptime` for generic scientific types. Leverage Zig's SIMD vectors (`@Vector`) for explicit data parallelism.

## 🏎 Performance & Data-Oriented Design (DOD)
- **Data Layout:** Prioritize **Structure of Arrays (SoA)** over Array of Structures (AoS) to maximize cache-line utilization and enable SIMD vectorization.
- **Cache Friendliness:** Minimize pointer chasing and deep object hierarchies. Keep hot data contiguous in memory to ensure spatial and temporal locality.
- **Hot Path Analysis:** Identify performance bottlenecks using profiling tools (`cProfile`, `perf`, `Valgrind/Callgrind`). Document "hot paths" and focus optimization efforts where the most time is spent.
- **Branch Minimization:** In high-frequency loops, prefer branchless programming or sorting data to minimize branch mispredictions.

## 📂 Architecture
- **FFI Strategy:**
    - **Zig:** Use **Cython** for interfacing Zig with Python.
    - **C:** Use **nanobind** for interfacing C with Python.
    - **Design:** Keep the FFI layer thin. Isolate computational kernels from I/O and UI logic.
- **Documentation:** Use Doxygen-style comments for C/Zig and Docstrings for Python. All mathematical formulas must be expressed in LaTeX format.

## 🧪 Testing & Validation
- **Unit Tests:** Every mathematical function must have unit tests covering edge cases (NaN, Infinity, Zero, negative values).
- **Validation:** Compare Cython/C/Zig implementations against Python/NumPy reference models to ensure numerical parity.
- **Verification:** Run memory safety checks (ASan/Valgrind) on all compiled extensions.
