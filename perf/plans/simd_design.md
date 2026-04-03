# General Principles for High-Performance SIMD Code

This document outlines architectural principles for developing high-performance SIMD (Single Instruction, Multiple Data) code, moving from scalar-centric logic to a vectorized pipeline.

## 1. Data Layout: SoA over AoS
The "Structure of Arrays" (SoA) is the foundation of SIMD efficiency.
*   **Scalar Anti-pattern (AoS):** Storing data as an "Array of Structures" (e.g., `RGBRGB...`). Loading 8 "Red" values requires slow "Gather" instructions or shuffles.
*   **SIMD Principle (SoA):** Store data in independent planes or "Structures of Arrays" (e.g., `RRRR...`, `GGGG...`, `BBBB...`).
*   **Benefit:** Enables **Contiguous Loads/Stores**. The CPU can move an entire vector from memory to a register in a single instruction, maximizing memory bandwidth.

## 2. Branchless Logic via Masking
Standard `if/else` statements inside loops cause pipeline stalls and are incompatible with the uniform nature of SIMD.
*   **Scalar Anti-pattern:** `if (val > threshold) result = func(val)`. Since different lanes in a vector may take different paths, the CPU cannot branch efficiently.
*   **SIMD Principle:** Use **Masked Selects**. Calculate the results for *all* lanes and then use a boolean mask to choose the final value.
*   **Example:** `v_final = @select(f64, v_mask, v_calculated, v_original)`. This keeps the execution pipeline linear and predictable.

## 3. Hierarchical Early-Outs (Reductions)
SIMD throughput is high, but the fastest code is the code that isn't executed.
*   **SIMD Principle:** Use **Horizontal Reductions** to skip entire blocks of work. Before starting an expensive computation, check if any lanes in the current vector are actually active.
*   **Example:** `if (@reduce(.Or, v_mask) == false) continue;`. This allows the SIMD pipeline to "jump" over large inactive data regions as efficiently as scalar code.

## 4. Vector Strength Reduction
Simplify mathematical operations to additions within the hot loop.
*   **Scalar Anti-pattern:** Recalculating linear functions (e.g., `y = mx + b`) for every element using multiplication.
*   **SIMD Principle:** Calculate a "Step Vector" once outside the loop. If processing 8 elements at a time, the step is `scalar_delta * 8`.
*   **Example:** `v_state += v_step_8`. Replacing multiplications with additions inside the loop reduces the pressure on the CPU's execution units.

## 5. Amortize Scalar Costs (Splatting)
Moving data from scalar registers to vector registers (splatting) has a non-zero cost.
*   **SIMD Principle:** **Splat Once, Use Many.** Identify values that are constant for the duration of a loop and splat them into vector registers before entering the loop.
*   **Example:** Splatting transformation constants, light positions, or thresholds into `@Vector` variables before the main processing loop starts.

## 6. Buffer Alignment and Padding
SIMD instructions are most efficient when operating on memory aligned to the vector width (e.g., 64-byte alignment for AVX-512).
*   **SIMD Principle:** **Uniform Loop Processing via Padding.** Avoid complex "loop tails" (scalar loops that handle the remaining 1-7 elements) by padding your data buffers.
*   **Generic Example:** Pad arrays to be a multiple of the vector width. This allows the use of a single, high-speed SIMD loop for the entire dataset without fear of out-of-bounds access.

## 7. Register Residency
The "Memory Wall" is the primary bottleneck in modern computing.
*   **SIMD Principle:** Keep the "Active State" in vector registers for the entire duration of the pipeline.
*   **Benefit:** By passing data between functions as vector arguments rather than writing to and reading from memory, you avoid expensive cache hits and stay within the CPU's fastest storage layer.

## Summary Comparison

| Feature | Scalar Thinking | SIMD Thinking |
| :--- | :--- | :--- |
| **Logic** | Branching (`if/else`) | Masking (`@select`) |
| **Math** | Pointwise (`x * y`) | Incremental (`v + step`) |
| **Memory** | Interleaved (`AoS`) | Planar (`SoA`) |
| **End of Data** | Cleanup Loop | Padding + Masking |
| **Focus** | Reducing Instructions | Maximizing Throughput |
