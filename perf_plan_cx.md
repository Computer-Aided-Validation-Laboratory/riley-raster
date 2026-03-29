# Performance Optimisation Plan for `src-simd2`

This plan is focused on squeezing out additional single-threaded performance from the
SIMD raster hot loop while preserving correctness for high-accuracy deformed speckle
pattern simulation from finite element data.

## Validation Rule for Every Optimisation

After implementing each optimisation:

1. `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig` must pass.
2. `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig` must pass.
3. Benchmarks must be run and compared against the `src-simd` baseline:
   - `zig run -O ReleaseFast ./src-simd2/bench_fullraster.zig`
   - `zig run -O ReleaseFast ./src-simd2/bench_geom.zig`
   - `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`
4. Keep the optimisation only if it passes both test suites and gives a performance
   improvement relative to `src-simd` for the targeted workload.
5. If an optimisation causes a regression, remove or revert it and continue to the next
   item in the list.

## Ranked Optimisation List

1. Rework the Newton raster path to eliminate full-tile solved-state scratch.
   - Replace the current `candidate_buffer -> subpx_xi/subpx_eta/subpx_mask -> reread`
     flow.
   - Keep coarse hull rejection if it is effective.
   - Store candidates in row-local or chunk-local AoSoA buffers of width 8.
   - Run `solveWeightsSIMD` on compacted candidate groups.
   - Shade immediately after solve, or append only solved groups to a row-local solved
     queue and shade once per row.

2. Change candidate storage from AoS to AoSoA.
   - Replace `Candidate` array storage with chunk-friendly arrays:
     `scratch_x[8]`, `scratch_y[8]`, `px[8]`, `py[8]`, `guess_xi[8]`,
     `guess_eta[8]`.
   - Append candidates in groups that map directly to SIMD solve inputs.

3. Add full-coverage and full-depth fast paths in the triangle SIMD loop.
   - If all 8 lanes pass coverage and depth, use plain vector stores.
   - Skip loading old color values in shader fill routines when all lanes update.
   - Keep masked read-modify-write only for partial-lane cases.

4. Add coarse accept paths for triangles.
   - Derive an 8-wide block accept test from edge values plus monotonic edge deltas.
   - If all lanes are guaranteed inside, skip repeated per-edge mask combines.

5. Track dirty regions in scratch and only clear touched rows or chunks.
   - Replace whole-tile `@memset` of `inv_z` and image scratch with per-overlap or
     per-row touched bounds.
   - Maintain min/max touched x per row, or dirty 8-wide chunk flags.

6. Resolve only dirty output pixels.
   - Feed `averageScratch` touched pixel bounds per row instead of the whole tile.
   - Specialize resolve kernels for `fields_num == 1` and `fields_num == 3`.
   - Add a bypass path when `sub_sample == 1`.

7. Bucket overlaps by kernel and shader variant before rasterization.
   - Prepartition overlaps into homogeneous batches such as `tri3-flat`,
     `tri3-texture`, `quad9-texture`.
   - Raster each batch in a dedicated loop.

8. Prepack per-element shader payloads into raster-ready layout.
   - Build compact raster payload arrays for visible elements:
     coords, inv-z terms, UVs, normals, scale params.
   - Avoid repeated `LocalNodeBuffer.load` copies where possible.

9. Improve hybrid texture locality without widening the cubic or quintic footprint.
   - Compact active lanes before calling the inner sampler.
   - Process active lanes in an order that preserves row or approximate footprint
     locality.
   - Optionally add small per-row footprint reuse for neighboring samples.

10. Cache per-element invariants across tiles.
    - Precompute and store triangle `inv_area`, edge step constants, `nodes_inv_z`,
      Newton params, and hull tessellation.
    - Reuse across every tile overlap for the same visible element.

## Execution Order

1. Newton path restructure: items 1 and 2.
2. Triangle and store fast paths: items 3 and 4.
3. Scratch bandwidth reduction: items 5 and 6.
4. Dispatch and payload layout: items 7 and 8.
5. Texture locality tuning: item 9.
6. Invariant caching: item 10.

## Benchmark Focus

- `bench_geom`
  - Prioritize items 1, 2, 7, 8, 10.
- `bench_sphere2000`
  - Prioritize items 1, 2, 5, 6, 9.
- `bench_fullraster`
  - Prioritize items 3, 4, 5, 6.

## First Milestone

1. Newton row-local solved candidate pipeline.
2. AoSoA candidate storage.
3. Full-mask and full-depth shader store fast paths.

## Results So Far

- Rejected:
  - The first Newton-path optimisation attempt, which removed the full-tile solved-state
    scratch and shaded immediately after `solveWeightsSIMD`, passed correctness tests but
    produced a substantial performance regression in the Newton kernels.
  - The measured regressions were commonly in the `-15%` to `-30%` range, with some
    Newton cases worse than that.
  - Conclusion: preserve the original three-pass Newton structure for now and only
    evaluate lower-risk data-layout changes on top of it.

- Accepted:
  - The second optimisation, changing Newton candidate storage from AoS to 8-lane AoSoA
    blocks while preserving the original three-pass Newton flow, passed both required
    test suites:
    `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig` and
    `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig`.
  - On `bench_fullraster`, the Newton kernels improved consistently.
  - The measured Newton-path gains were approximately `+2.5%` to `+18.7%`, depending on
    shader and interpolation order.
  - Representative gains:
    `quad4newton_flat_grey` about `+18.7%`,
    `quad4newton_flat_rgb` about `+18.5%`,
    `quad4newton_tex8_grey_linear` about `+16.6%`,
    `quad4newton_tex8_rgb_linear` about `+7.7%`,
    `quad4newton_tex8_grey_cubic` about `+8.1%`,
    `quad4newton_tex8_rgb_cubic` about `+5.5%`,
    `quad4newton_tex8_grey_quintic` about `+2.5%`,
    `quad4newton_tex8_rgb_quintic` about `+3.9%`.
  - It also improved several non-Newton higher-order paths, especially `quad8` and
    `quad9`, though some simpler `tri3` textured cases were slightly slower in the same
    run and should be treated cautiously until repeated A/B runs confirm that behavior.
