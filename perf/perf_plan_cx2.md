# Follow-On Performance Review Plan for `src-simd2`

This document captures the main findings from a deep review of the `src-simd2`
software rasteriser, with emphasis on:

- accurate higher-order finite element rendering for DIC speckle simulation
- maximum single-threaded performance before adding threading
- consistency with the SIMD principles in `simd_design.md`

The suggestions below assume the currently accepted optimisations from
`perf_plan_cx.md` remain in place unless replaced by a measured improvement.

## Validation Rule for Every Change

After each optimisation:

1. `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig` must pass.
2. `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig` must pass.
3. Benchmarks must be compared against the current `src-simd2` baseline and the
   original `src-simd` baseline where relevant:
   - `zig run -O ReleaseFast ./src-simd2/bench_fullraster.zig`
   - `zig run -O ReleaseFast ./src-simd2/bench_geom.zig`
   - `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`
4. Keep the optimisation only if correctness is preserved and the targeted
   workload improves.

## Main Review Findings

### 1. Full-tile scratch clear and full-tile resolve still waste bandwidth

Current behavior:

- Entire tile `inv_z` scratch is cleared every tile.
- Entire tile image scratch is cleared every tile.
- Entire tile is resolved in `averageScratch`, even if only a small subset of
  rows or 8-wide chunks were touched.

Why this matters:

- This is a direct bandwidth cost in the hottest part of the pipeline.
- It is especially expensive for sparse overlap patterns and higher-order
  elements whose actual covered area can be much smaller than the overlap bbox.

Priority:

- Very high.

Recommended action:

- Track dirty bounds per row or dirty 8-wide chunks.
- Clear only touched scratch regions.
- Resolve only touched output pixels.
- Add specialized resolve paths for:
  - `sub_sample == 1`
  - `fields_num == 1`
  - `fields_num == 3`

### 2. SIMD store fast paths are still missing

Current behavior:

- The triangle SIMD path still performs masked read-modify-write stores even
  when all 8 lanes pass coverage and depth.
- Flat and perspective-flat shader fills always load old output values before
  `@select`.

Why this matters:

- This adds avoidable loads and register pressure in the common case for large
  fully covered blocks.
- It contradicts item 3 in `perf_plan_cx.md`.

Priority:

- Very high.

Recommended action:

- Add an all-lanes-covered/all-lanes-depth-pass fast path.
- Use plain vector stores in that path.
- Avoid loading prior scratch color values when the full vector is overwritten.
- Keep masked read-modify-write only for partial-lane cases.

### 3. The Newton path still spills too much state to scratch

Current behavior:

- Pass 1 builds candidate blocks.
- Pass 2 solves Newton and writes solved `xi`, `eta`, and `mask` back to
  full-tile scratch arrays.
- Pass 3 rereads those arrays and recomputes shape functions before shading.

Why this matters:

- This is a clear violation of the register-residency principle in
  `simd_design.md`.
- Even though the first attempt at immediate shading regressed, the current
  design is still paying substantial scratch bandwidth and reload cost.

Priority:

- Very high.

Recommended action:

- Keep the accepted AoSoA candidate storage.
- Do not revert to the original AoS layout.
- Revisit the Newton flow with lower-risk steps:
  - preserve row-local ordering
  - keep compact solved queues instead of full-tile solved-state arrays
  - avoid rereading solved parametric coordinates from tile-sized scratch when
    possible

### 4. Hull-generated Newton guesses are not being used effectively

Current behavior:

- Hull tessellation computes `guess_xi` and `guess_eta`.
- These guesses are then overwritten by the default guess or previous solved
  seed before the Newton solve.

Why this matters:

- Work is being done in the hull pass without delivering its intended benefit.
- Better initial guesses are one of the most plausible ways to reduce Newton
  iterations and failed lanes without changing numerical correctness.

Priority:

- Very high.

Recommended action:

- Preserve hull-provided guesses where they are better than the generic default.
- Evaluate seeding policy carefully:
  - hull guess only
  - previous solved seed only
  - hybrid policy based on spatial continuity or residual quality
- Benchmark Newton iteration counts and convergence rates, not just frame time.

### 5. The expensive texture paths are still largely scalar-per-lane

Current behavior:

- `fillTexPerspectiveSIMD` computes interpolated UVs in SIMD.
- `sampleGenericHybrid` then processes active lanes one-by-one for the actual
  sampling work.
- Cubic and quintic filtering paths remain dominated by scattered footprint
  fetches and repeated weight setup.

Why this matters:

- Bench behavior shows that textured cubic and quintic paths dominate runtime.
- The bottleneck is not just arithmetic, but memory locality and repeated
  scalarized sampling work.

Priority:

- Very high.

Recommended action:

- Continue lane compaction and locality-aware ordering.
- Extend locality work beyond the current `Tri3`-local path.
- Add a tiny footprint reuse cache for neighboring samples within a row or chunk.
- Focus on reducing footprint fetch redundancy before attempting more elaborate
  math rewrites.

### 6. Pass 3 of the Newton path computes derivatives it does not use

Current behavior:

- `shapeFunctionsSIMD` computes weights plus derivatives.
- Pass 3 shading only uses the weights.

Why this matters:

- This is wasted arithmetic and register pressure in a hot loop.

Priority:

- High.

Recommended action:

- Add a weights-only SIMD shape-function entry point for pass 3 shading.
- Keep the full weights-plus-derivatives version only where the Newton solver
  actually needs it.

### 7. SIMD width is fixed at 8 lanes of `f64`

Current behavior:

- Hot paths are built around `@Vector(8, f64)`.

Why this matters:

- This may be optimal on some CPUs, but it should not be assumed.
- Industrial software rasterisers such as LLVMpipe expose vector-width tuning
  because narrower vectors can outperform wider ones when register pressure,
  gathers, or cache behavior dominate.

Priority:

- High.

Recommended action:

- Make SIMD width configurable for benchmarking.
- Test at least:
  - 2 lanes
  - 4 lanes
  - 8 lanes
- Measure on the real target CPU rather than deciding from theory alone.

### 8. Dispatch is still per-overlap rather than batched by kernel variant

Current behavior:

- Rasterisation dispatch still switches by mesh type and shader variant within
  the overlap loop.
- Local node payloads are loaded overlap-by-overlap.

Why this matters:

- This hurts i-cache locality and front-end efficiency.
- It also makes it harder to build highly specialized hot loops.

Priority:

- High.

Recommended action:

- Prebucket overlaps by homogeneous raster variant, for example:
  - `tri3-flat`
  - `tri3-texture-linear`
  - `quad9-texture-quintic`
- Prepack visible-element payloads into raster-ready SoA/AoSoA storage.
- Raster each homogeneous batch in a dedicated loop.

## Review Against `simd_design.md`

### Data Layout: SoA over AoS

Status:

- Improved in Newton candidate storage due to accepted AoSoA work.
- Still incomplete in per-overlap payload preparation and some texture access
  patterns.

Action:

- Continue moving visible-element payloads toward raster-ready SoA/AoSoA layout.

### Branchless Logic via Masking

Status:

- Generally good in core SIMD loops.
- Still paying masked-store cost even in full-mask cases.

Action:

- Keep masking for correctness.
- Add full-mask specialization to avoid unnecessary read-modify-write.

### Hierarchical Early-Outs

Status:

- Present in several SIMD loops via `@reduce(.Or, mask)`.
- Still missing stronger coarse accept/reject in triangle blocks and resolve.

Action:

- Add block-level full-accept tests for triangles.
- Use dirty tracking to early-out clears and resolve.

### Vector Strength Reduction

Status:

- Good in the triangle incremental edge/weight stepping path.
- Less effective in Newton and texture sampling paths.

Action:

- Preserve incremental stepping where already working.
- Reduce recomputation in Newton shading and texture setup.

### Amortize Scalar Costs

Status:

- Constants are often splatted once per loop.
- Some scalar setup is still repeated unnecessarily in texture and Newton code.

Action:

- Hoist invariant setup aggressively.
- Precompute more per-element constants across tiles.

### Buffer Alignment and Padding

Status:

- Good scratch alignment and padded subpixel storage.

Action:

- Preserve this.
- Extend the same thinking to packed variant-specific payload buffers.

### Register Residency

Status:

- Good in parts of the triangle SIMD path.
- Poor in the three-pass Newton path and in hybrid texture sampling.

Action:

- Treat register residency as a main design goal for all future Newton-path work.

## Industrial Rasteriser Lessons to Apply

### LLVMpipe

Useful ideas:

- Vector width is a tuning knob, not a fixed truth.
- Variant-specialized generated code matters.
- JIT disassembly and perf-guided inspection are valuable.

Possible application here:

- Benchmark multiple SIMD widths.
- Consider more variant-specific hot loops even without full JIT infrastructure.

### SwiftShader

Useful ideas:

- Specialize processing routines for the exact draw state.
- Keep setup and pixel work closely coupled for the active variant.
- Cache specialized routines and avoid generic dispatch inside hot loops.

Possible application here:

- Prebucket overlaps and execute dedicated loops for homogeneous variants.
- Reduce dynamic branching inside the overlap hot path.

### OpenSWR

Useful ideas:

- Tile-based immediate rendering with strong front-end/back-end separation.
- Heavy use of AoS-to-SoA conversion before hot loops.
- Designed for geometry-heavy visualization workloads, which is relevant to FE
  rendering.

Possible application here:

- Prepack visible-element payloads before rasterization.
- Keep the raster core operating on tight, homogeneous, cache-friendly data.

### WARP

Useful ideas:

- High-performance software rasterization benefits from state-specialized
  vectorized command streams and JIT-like specialization.

Possible application here:

- Reduce “one generic path handles everything” structure in hot loops.

## Literature/Technique Ideas Worth Trying

### 1. Coarse accept/reject for 8-wide triangle blocks

Why:

- Pineda-style half-space rasterisation benefits from block-level monotonic edge
  tests.

Action:

- Derive full-accept and full-reject tests from edge values and edge deltas.
- Skip per-edge lane combines for fully inside blocks.

### 2. Compact solved queues rather than full solved scratch

Why:

- Compact queues preserve locality while reducing full-tile scratch traffic.

Action:

- Revisit row-local solved queues after fixing seed policy and removing unused
  derivative work.

### 3. Footprint-local texture sampling reuse

Why:

- Neighboring samples often hit overlapping cubic/quintic footprints.

Action:

- Add a tiny row/chunk-local cache keyed by footprint origin.
- Especially target higher-order textured kernels.

### 4. Output layout and swizzle experiments

Why:

- Texture and scratch access patterns may benefit from cache-friendlier layouts.

Action:

- Consider experiments with tile- or row-swizzled texture storage if locality
  remains limiting after simpler changes.
- Treat this as later-stage work, not the first optimisation.

### 5. Per-element invariant caching across tiles

Why:

- Some setup repeats for every tile overlap.

Action:

- Cache:
  - Newton parameters
  - inverse depth terms
  - triangle edge constants
  - hull tessellation data
  - prepacked shader payloads

## Recommended Execution Order

1. Dirty tracking and touched-only resolve.
2. Full-mask/full-depth fast paths for stores.
3. Fix Newton seed handling so hull guesses are actually usable.
4. Add weights-only pass-3 shape function path.
5. Revisit Newton solved-state handling with compact row-local queues.
6. Batch overlaps by raster/shader/interpolation variant.
7. Prepack visible-element payloads.
8. Improve texture locality and footprint reuse.
9. Benchmark configurable SIMD widths.
10. Add further invariant caching across tiles.

## First Concrete Milestone

1. Implement dirty row or dirty chunk tracking.
2. Add touched-only `averageScratch` resolve.
3. Add full-mask store fast paths for flat and textured SIMD fills.
4. Fix Newton seed overwrite behavior.
5. Add weights-only SIMD shape-function evaluation for Newton pass 3.

## Notes

- Do not sacrifice numerical correctness for higher-order FE rendering just to
  gain speed in the short term.
- Prioritize bandwidth and redundant-work reductions before risky numerical
  changes such as mixed precision.
- The current profile shape strongly suggests the textured cubic/quintic kernels
  and Newton scratch traffic remain the highest-value optimisation targets.
