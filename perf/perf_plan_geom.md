# Geometry Performance Optimisation Plan for `src-simd2`

This plan focuses on the geometry side of the pipeline rather than the raster loop.

Primary hotspots:

- [`prepareSceneGeometry`](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterops.zig#L565)
- [`sceneTileElemOverlap`](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterops.zig#L677)

Primary benchmarks and figure of merit:

- `zig run -O ReleaseFast ./src-simd2/bench_geom.zig`
- `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`
- focus on `MElem/s`

## Validation Rule

After implementing each optimisation:

1. `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig` must pass.
2. `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig` must pass.
3. Benchmarks must be run sequentially:
   - `zig run -O ReleaseFast ./src-simd2/bench_geom.zig`
   - `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`
4. Keep the optimisation only if it improves `MElem/s` for the targeted workload.

## Scalar And Structural Plan

1. Specialize bbox generation by kernel family.
   - Keep the dedicated `tri3` path.
   - Add dedicated paths for:
     - `quad4ibi`
     - `quad4newton`
     - `tri6`
     - `quad8`
     - `quad9`
   - Avoid routing all nonlinear kernels through one generic bbox routine.

2. Remove repeated divide-heavy screen projection in bbox counting.
   - Avoid recomputing `x / z` and `y / z` inside bbox generation when geometry has
     already been transformed earlier in the prep stage.
   - Prefer storing projected screen coordinates directly or storing `inv_z` once and
     multiplying.

3. Split hull and non-hull bbox paths early.
   - Use a hull-specific bbox routine when raster hulls exist.
   - Use a nodal bbox routine otherwise.
   - Avoid per-element branchy dispatch inside the hot loop.

4. Add kernel-specific orientation and backface screening.
   - Replace the current generic nonlinear nodal-derivative sweep with cheaper
     conservative tests where possible.
   - Only fall back to the full nodal check when the cheaper test is ambiguous.

5. Store tile span metadata during bbox preparation.
   - Precompute:
     - `tile_ind_min_x`
     - `tile_ind_max_x`
     - `tile_ind_min_y`
     - `tile_ind_max_y`
   - Avoid repeated divides by `tile_size` in overlap generation.

6. Precompute clipped overlap metadata for visible elements.
   - Store compact overlap-ready information once per visible element.
   - Reduce repeated min/max clipping inside the overlap pass.

7. Specialize overlap emission for common tile-span cases.
   - Add fast paths for elements touching:
     - 1 tile
     - 2 tiles horizontally
     - 2 tiles vertically
     - 4 tiles
   - Fall back to the generic nested loop only for larger spans.

8. Consider a chunked single-pass or semi-single-pass overlap binning path.
   - The current implementation counts, scans, then fills.
   - That is simple and robust, but walks all visible elements twice.
   - Explore whether a chunked append path can reduce total work without adding too much
     bookkeeping complexity.

9. Prepack visible-element geometry after culling.
   - Build compact visible-element-only arrays for:
     - projected coords
     - bbox integers
     - tile spans
     - optional hull references
     - optional normal mappings
   - Improve memory locality in later overlap and raster setup stages.

10. Sort or bucket visible elements for overlap locality.
    - Explore ordering visible elements by tile row or Morton-like screen key before
      overlap emission.
    - Prioritize `sphere2000`, where overlap throughput likely matters most.

11. Cache derivative constants and kernel invariants more aggressively.
    - Use per-kernel specialized derivative tables and invariant constants rather than a
      generic indexing-heavy path.
    - Especially relevant for:
      - `quad4newton`
      - `tri6`
      - `quad8`
      - `quad9`

## Extended SIMD Plan

This SIMD exploration is for geometry processing, not the raster loop. It is intended
to improve `MElem/s` in `bench_geom` and `bench_sphere2000`.

Element fit with 8-wide SIMD:

- natural or near-natural fits:
  - `tri3`
  - `quad4ibi`
  - `quad4newton`
  - `tri6`
  - `quad8`
- awkward case:
  - `quad9`

### SIMD Options For All Element Types

1. SIMD per-element node loads for all kernels.
   - Load projected node data into 8-wide vectors:
     - `tri3` as `3 + pad`
     - `quad4ibi` and `quad4newton` as `4 + pad`
     - `tri6` as `6 + pad`
     - `quad8` as exact `8`
     - `quad9` as `8 + 1` split or padded mixed path

2. SIMD bbox min/max reduction for all kernels.
   - Use vector min/max over node `x` and `y`.
   - Use padding lanes initialized to:
     - `+inf` for mins
     - `-inf` for maxes

3. SIMD orientation and backface screening.
   - Compute derivative contributions over node index in vector form.
   - Most promising for:
     - `quad4newton`
     - `tri6`
     - `quad8`
     - `quad9`

4. SIMD hull-point bbox reduction.
   - When raster hulls exist, reduce hull extents with vector min/max instead of scalar
     loops.

5. SIMD projection and transform in visible-element blocks.
   - Replace element-by-element transform loops with AoSoA or blockwise transforms.
   - Project multiple elements at once and write results back contiguously.

6. AoSoA staging buffers by kernel.
   - Build kernel-specific packed arrays such as:
     - `[elem_block][node][lane]`
     - or `[node][lane]`
   - Use them for projection, bbox reduction, orientation tests, and overlap-span work.

7. SIMD tile-span computation.
   - Compute tile min/max x/y from vectorized bbox results.
   - Clamp and convert to integers in vector-friendly batches.

8. SIMD overlap classification for common small-span cases.
   - Quickly classify one-tile, two-tile, and four-tile spans before generic emission.

9. Dedicated `quad9` SIMD strategies.
   - `8 + 1` split evaluation
   - SIMD first 8 nodes plus scalar tail node
   - two-vector padded path
   - reduced-order coarse SIMD screen followed by scalar refinement if needed

10. Keep SIMD specialized by kernel rather than one generic implementation.
    - Prefer separate SIMD prep kernels for:
      - `tri3`
      - `quad4`
      - `tri6`
      - `quad8`
      - `quad9`

### SIMD Priority Order

1. `quad8`
   - exact 8-node fit
2. `tri6`
   - good fit with small padding
3. `quad4ibi` and `quad4newton`
   - cheap padded SIMD
4. `tri3`
   - easy to implement, though scalar may already be strong
5. `quad9`
   - explore separately with custom awkward-width strategies

## Recommended Execution Order

1. Remove repeated projection work in bbox prep.
2. Store tile-span metadata during geometry prep.
3. Specialize overlap emission for 1-tile, 2-tile, and 4-tile cases.
4. Add dedicated bbox paths for `quad4ibi` and `quad4newton`.
5. Add visible-element packing for later stages.
6. Explore SIMD bbox and projection for `quad8`, then `tri6`, then `quad4*`.
7. Explore `quad9` only with a dedicated strategy rather than a generic SIMD path.

## Benchmark Focus

- `bench_geom`
  - best for:
    - bbox generation
    - projection/prep cost
    - visible-element packing
    - overlap generation

- `bench_sphere2000`
  - best for:
    - overlap scalability
    - small-footprint element throughput
    - tile-span classification
    - locality-sensitive overlap generation

## First Geometry Milestone

1. Stop recomputing projected screen coordinates in bbox generation.
2. Add stored tile-span metadata for visible elements.
3. Specialize overlap generation for 1-tile and 2-tile spans.
4. Measure `MElem/s` on `geom` and `sphere2000`.

## Initial Hypothesis

The highest-probability early wins are:

- avoid repeated `x / z`, `y / z` work in bbox counting
- store tile-span metadata once
- specialize overlap generation for common small tile-span cases

These attack both hot geometry stages with lower risk than starting immediately with a
large SIMD refactor.
