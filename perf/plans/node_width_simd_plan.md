# Node-Width SIMD Plan

This plan extends the existing SIMD coordinate transform approach to the rest of the
geometry preprocessing pipeline while staying friendly to the current memory layout.

The guiding rule is:

- do SIMD where the data is already contiguous
- prefer node-width SIMD over forced full-lane occupancy
- do not repack memory just to fill wider vectors unless benchmarking proves it is
  worthwhile

In practice, this means SIMD over nodes within one element:

- `tri3` -> `@Vector(3, f64)`
- `quad4ibi` and `quad4newton` -> `@Vector(4, f64)`
- `tri6` -> `@Vector(6, f64)`
- `quad8` -> `@Vector(8, f64)`
- `quad9` -> test `@Vector(9, f64)` against `8 + 1`

This should not be treated as the only SIMD style in the geometry pipeline. After
reviewing the baseline scalar implementation in
[`src/zigraster/zig/rasterops.zig`](/home/lloydf/zigraster/src/zigraster/zig/rasterops.zig),
the pipeline splits naturally into three categories:

1. node-width SIMD
   - per-element nodal math over contiguous `[elem, field, node]` slices

2. chunk-width SIMD
   - fixed-width SIMD over contiguous arrays that are not naturally tied to
     `nodes_per_elem`, such as raster hull point lists

3. layout-driven scalar or batched code
   - scatter-heavy or overlap-emission stages where memory write pattern and control
     flow dominate more than arithmetic density

## Why This Fits The Current Layout

The existing SIMD transform functions already follow the right pattern:

- `worldToRasterSIMD(comptime N, ...)`
- `elemsToRasterSIMD(comptime N, ...)`
- `elemsToClipPxLengSIMD(comptime N, ...)`

These operate on one element at a time, using contiguous node slices and SIMD width
equal to `N = nodes_per_elem`. That preserves memory locality and avoids gather/scatter
over multiple unrelated elements.

## Scope

This plan applies node-width SIMD to geometry preprocessing and bbox checks only:

- projected node generation
- bbox min/max reduction
- nonlinear orientation and backface checks
- exact normal calculation
- partial SIMD for averaged normals where the local element work is vector-friendly

This plan also acknowledges that some parts of the pipeline should use a different
approach:

- chunk-width SIMD for hull reductions and other contiguous non-nodal arrays
- layout-driven scalar or batched paths for overlap generation and scatter-heavy stages

This plan does not yet apply SIMD to:

- overlap generation
- the raster loop
- the Newton solver itself

## Implementation Plan

1. Keep the existing transform stage as the architectural template.
   - Build the rest of geometry SIMD around `Vec3SIMD(N, T)` and per-element contiguous
     slices.

2. Introduce a node-width SIMD helper layer in
   [`src-simd2/zigraster/zig/rasterops.zig`](/home/lloydf/zigraster/src-simd2/zigraster/zig/rasterops.zig).
   - Add helpers such as:
     - `projectNodesSIMD(comptime N, ...)`
     - `bboxMinMaxSIMD(comptime N, ...)`
     - `orientationCheckSIMD(comptime N, ...)`
     - `normalsExactSIMD(comptime N, ...)`
     - `normalsAveragedAccumSIMD(comptime N, ...)` where practical

3. Replace the fixed `@Vector(8, f64)` geometry helpers with `@Vector(N, f64)` helpers.
   - Move away from padded 8-wide geometry SIMD for nodal data.
   - Keep the element loop scalar and SIMD only the node loop inside each element.

4. Apply node-width SIMD to projection first.
   - For nonlinear kernels:
     - load one element's `x`, `y`, `z` slices
     - compute `sx = x / z + x_off`
     - compute `sy = y / z + y_off`
   - Keep solver-facing clip-space coordinates unchanged.

5. Apply node-width SIMD to bbox reduction next.
   - Once `sx/sy` are available for an element:
     - reduce `min/max` with `@reduce(.Min, ...)` and `@reduce(.Max, ...)`

6. Apply node-width SIMD to nonlinear orientation and backface checks.
   - Reuse nodal derivative weights as `@Vector(N, f64)`
   - Compute:
     - `dx_dxi = @reduce(.Add, v_dnu * v_sx)`
     - `dx_deta = @reduce(.Add, v_dnv * v_sx)`
     - `dy_dxi = @reduce(.Add, v_dnu * v_sy)`
     - `dy_deta = @reduce(.Add, v_dnv * v_sy)`

7. Keep hull reduction as a separate chunked SIMD path.
   - Hulls are not naturally tied to `N`
   - Use chunked contiguous reduction, likely `@Vector(8, f64)`, over hull point slices
   - Do not force hulls into the node-width nodal path

8. Extend the same node-width pattern to exact normals.
   - The exact-normal path is another derivative-weighted nodal accumulation
   - Reuse the same SIMD accumulation structure where possible

9. Be selective with averaged normals.
   - SIMD the per-element local derivative and cross-product work
   - keep the shared-node accumulation scalar at first
   - avoid trying to SIMD the scatter-heavy global accumulation path immediately

10. Keep overlap generation scalar in the first node-width SIMD pass.
    - First prove wins in geometry prep and bbox checks using `MElem/s`
    - [`sceneTileElemOverlap`](/home/lloydf/zigraster/src/zigraster/zig/rasterops.zig#L667)
      is not a good match for node-width SIMD because it is dominated by tile-span
      loops, count accumulation, and scattered overlap writes

11. For overlap generation, prefer layout and batching work instead of node-width SIMD.
    - promising directions are:
      - compact arrays of overlap metadata such as `tx_min`, `tx_max`, `ty_min`,
        `ty_max`
      - grouping by common small span classes such as `1x1`, `2x1`, `1x2`, `2x2`
      - row-bucketed or tile-bucketed staging if later overlap locality work is needed

12. Treat averaged normals as a mixed path.
    - SIMD the local per-element derivative and cross-product work
    - keep the shared-node accumulation scalar until a better accumulation layout is
      designed

## Recommended Implementation Order

1. Add node-width helper functions using `@Vector(N, f64)`
2. Convert projection and bbox min/max
3. Convert nonlinear backface and orientation
4. Reuse helpers in exact normals
5. Try partial SIMD in averaged normals
6. Separately explore chunk-width SIMD for hull reduction
7. Leave overlap generation for a later layout-driven pass

## Benchmarking

Use:

- `zig run -O ReleaseFast ./src-simd2/bench_geom.zig`
- `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`

Primary figure of merit:

- `MElem/s`

## Expected Kernel Behavior

- `quad8`
  - strongest expected fit and likely best win

- `tri6`, `quad4newton`, `quad4ibi`
  - good next targets due to contiguous per-element node slices

- `tri3`
  - easy to express, but gains may be modest

- `quad9`
  - should be evaluated separately:
    - `@Vector(9, f64)`
    - versus `8 + 1`
  - choose whichever works better with the current memory layout and codegen

## Architectural Note

The main lesson from the existing transform path is that maximizing lane occupancy is
not the right objective by itself.

Using `N = nodes_per_elem` can outperform wider vectors because:

- slices are direct and contiguous from the current
  `[elems, fields, nodes_per_elem]`-style layout
- indexing stays simple
- memory fetches remain locality-friendly
- no repacking or cross-element gather pattern is introduced

So the right target is a node-parallel SIMD pipeline, not a full-width SIMD pipeline.

## Pipeline Split

Based on the baseline scalar implementation, the geometry side should be approached as
three different optimization problems:

1. Node-width SIMD
   - best for:
     - coordinate transforms
     - projected `sx/sy`
     - bbox min/max over nodes
     - nonlinear orientation and backface checks
     - exact normals

2. Chunk-width SIMD
   - best for:
     - raster hull min/max reduction
     - compact contiguous metadata scans that are not naturally tied to element node
       count

3. Layout-driven scalar or batched code
   - best for:
     - `sceneTileElemOverlap`
     - shared-node averaged-normal accumulation
     - other scatter-heavy or branch-dominated stages

This split should guide future geometry work so that each part of the pipeline uses the
SIMD or dataflow style that actually matches its memory behavior.
