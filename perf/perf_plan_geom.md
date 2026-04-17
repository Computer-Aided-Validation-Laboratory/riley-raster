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

### Suggested Grouping

These scalar and structural items should not all be attacked one by one. Several of
them group naturally and are better implemented together to avoid reshaping the same
data flow repeatedly.

1. Group 1: BBox Prep Data Model
   - remove repeated projection work
   - store tile-span metadata
   - split hull and non-hull bbox paths
   - specialize bbox generation by kernel
   - This group defines what a prepared visible element looks like and should be done as
     one coordinated refactor.

2. Group 2: Overlap Emission
   - precompute clipped overlap metadata
   - specialize 1-tile, 2-tile, and 4-tile overlap paths
   - optionally sort or bucket visible elements for locality
   - only consider replacing the two-pass overlap generation after the earlier overlap
     fast paths are understood
   - This group should be built on top of the output shape from Group 1.

3. Group 3: Orientation And Culling Refinement
   - kernel-specific orientation tests
   - cheaper conservative tests before full nonlinear checks
   - derivative and invariant caching
   - This group is best done after the bbox structure is stable, and preferably one
     kernel family at a time so wins and regressions are easy to attribute.

4. Group 4: Visible-Element Packing
   - prepack visible-element geometry after culling
   - compact arrays for later overlap and raster setup
   - This can either be folded into Group 1 if the visible-element representation is
     being redesigned anyway, or done immediately after Group 1 once the data shape is
     clear.

Recommended sequencing:

1. Group 1
2. Group 2
3. Group 3
4. Group 4 if it did not already land as part of Group 1

### Group 1 Result

Rejected in the first full refactor attempt.

What was implemented:

- split projected-nodal and hull bbox paths
- added projected screen-space scratch for bbox prep while keeping Newton solver data
  in clip space
- stored tile-span metadata in `ElemBBox`
- updated overlap generation to consume stored tile spans

Outcome:

- correctness was restored and both `ReleaseSafe` suites passed
- geometry throughput regressed heavily versus `v3` when measured with `MElem/s`

Measured impact versus `v3`:

- `bench_geom`: about `-29.1%` average
- `bench_sphere2000`: about `-25.0%` average

The worst regressions were concentrated in the nonlinear and quad kernels:

- `quad4ibi`: about `-52%`
- `quad4newton`: about `-36%` to `-37%`
- `tri6`: about `-34%` to `-36%`
- `quad9`: about `-37%` to `-44%`

Likely reason:

- the added screen-space scratch build and broader data-model indirection cost more than
  the saved divide and tile-span recomputation work
- for these scenes, the extra geometry-prep passes outweighed the simplified overlap math

Decision:

- revert to `v3`
- do not continue this Group 1 design in its current form
- future geometry work should focus on smaller, more targeted changes rather than a
  broad bbox-prep data-model refactor

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

### SIMD Experiment Result

Rejected overall in the first two SIMD geometry-prep experiments.

What was tried:

1. `src-simd2`: a generic SIMD path across all geometry kernels
   - padded or generic 8-wide SIMD used for projected node generation, bbox min/max,
     hull min/max, and nonlinear backface/orientation accumulation

2. `src-simd3`: a hybrid specialized SIMD path across all geometry kernels
   - exact-width SIMD for kernels with `N <= 8`
   - `8 + 1` split path for `quad9`

Measured impact versus `v3` baseline in `MElem/s`:

- generic `src-simd2`:
  - `bench_geom`: about `-7.4%`
  - `bench_sphere2000`: about `-14.6%`

- hybrid `src-simd3`:
  - `bench_geom`: about `+1.0%`
  - `bench_sphere2000`: about `-1.6%`

Kernel-level read:

- `quad8` responded well to SIMD
- `tri3` and `tri3opt` were near flat in the hybrid version
- `quad4newton` was close to flat in the hybrid version
- `tri6` was mildly negative
- `quad4ibi` and `quad9` regressed enough to make the overall result not worth keeping

Decision:

- reject both versions as full geometry-pipeline replacements
- keep `v3` as the accepted baseline
- revisit geometry SIMD with a better memory layout and dataflow design

### Node-Width SIMD Result

Rejected as a broad all-kernel geometry replacement.

What was implemented:

- node-width SIMD for nodal per-element geometry work using `N = nodes_per_elem`
- applied to:
  - projected node generation
  - nodal bbox min/max reduction
  - nonlinear backface and orientation accumulation
  - local exact-normal and averaged-normal derivative accumulation
- overlap generation remained scalar

Measured impact versus `v3` baseline in `MElem/s`:

- `bench_geom`: about `+2.9%`
- `bench_sphere2000`: about `-3.9%`

Kernel-level read:

- strong positive:
  - `quad8`
    - about `+32.3%` on `geom`
    - about `+14.0%` on `sphere2000`

- near flat:
  - `tri3`
    - about `+0.1%` on `geom`
    - about `-4.0%` on `sphere2000`
  - `tri3opt`
    - about `+0.6%` on `geom`
    - about `+0.6%` on `sphere2000`
  - `quad4newton`
    - about `-0.9%` on `geom`
    - about `-5.6%` on `sphere2000`

- negative:
  - `tri6`
    - about `-3.0%` on `geom`
    - about `-6.1%` on `sphere2000`
  - `quad4ibi`
    - about `-5.4%` on `geom`
    - about `-6.5%` on `sphere2000`
  - `quad9`
    - about `-3.2%` on `geom`
    - about `-19.7%` on `sphere2000`

Representative outliers:

- best `geom` case: `quad8_flat_grey +38.46%`
- best `sphere2000` case: `quad8_tex8_rgb +15.26%`
- worst `geom` case: `quad4ibi_tex8_rgb_quintic_lut_lerp -15.19%`
- worst `sphere2000` case: `quad9_tex8_grey -23.02%`

Decision:

- reject this as a full-kernel default path
- keep `v3` as the accepted baseline
- carry forward the architectural lesson that node-width SIMD is promising for
  contiguous nodal work, but should likely be applied selectively rather than forced
  across every geometry kernel

Important architectural note for future SIMD work:

- a full-vector-width approach is not automatically best for this pipeline
- for the coordinate transform, using `N = nodes_per_elem` to slice directly from the
  `[elems, fields, nodes_per_elem]` layout was previously found to be more efficient
  than forcing full-width vectors
- even though that leaves vector lanes unused for smaller kernels, it preserves a much
  better memory access pattern
- the likely direction for future geometry SIMD is therefore a hybrid memory layout
  that balances fetch locality and slicing cost against SIMD width, rather than
  maximizing SIMD lane occupancy at all costs
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
