# Convex Hull Newton Plan

This plan is for `src-simd2` only.

Goal:
- Replace the current adaptive-hull coarse in/out path for Newton kernels with a convex
  hull.
- Use the Bezier-derived point when an edge bulges outward.
- Skip the midside node entirely and keep the straight corner-to-corner edge when an edge
  bulges inward.
- Keep fixed-capacity storage, but use length-tracked slices for the actual hull points.

## Design

1. Keep fixed-capacity backing storage per element.
   - `quad4`: capacity `4`
   - `tri6`: capacity `6`
   - `quad8` and `quad9`: capacity `8`

2. Add a per-element `hull_count`.
   - The backing arrays still use full capacity.
   - The actual hull is represented by `hull_x[0..hull_count]` and
     `hull_y[0..hull_count]`.
   - This avoids `NaN` sentinels and avoids extra checks in the hot loop.

3. Build a convex hull boundary in order.
   - Always append each corner node.
   - For each edge:
     - if the midside node bulges outward, append the Bezier point
       `2 * mid - 0.5 * (corner_a + corner_b)`
     - if the midside node bulges inward, append nothing for that edge
   - This produces:
     - `tri6`: 3 to 6 hull points
     - `quad8/quad9`: 4 to 8 hull points

4. Build parametric boundary coordinates alongside the raster hull.
   - Store fixed-capacity backing arrays for `x`, `y`, `xi`, and `eta`.
   - Corners use their standard `(xi, eta)` values.
   - Outward-bulging edges use the midside parametric coordinates.
   - Inward-bulging edges contribute no midside boundary sample.
   - The runtime hull is represented by slices
     `hull_x[0..hull_count]`, `hull_y[0..hull_count]`,
     `hull_xi[0..hull_count]`, and `hull_eta[0..hull_count]`.

5. Replace the compile-time-sized hull tessellation with a runtime-count polygon fan.
   - Keep a fixed-capacity triangle array with max size `8`.
   - Store `tri_count` at runtime.
   - Build the fan from the centroid of the retained hull boundary points.
   - Loop over `0..tri_count` in `isIn` and `isInSIMD`.

6. Thread hull counts through the geometry setup.
   - Expand raster-hull storage to hold `x`, `y`, `xi`, and `eta`.
   - Add a second per-mesh NDArray for hull counts.
   - Update the hull builder to write both the fixed-capacity backing arrays and the
     per-element count.

7. Update bbox and Newton coarse-in/out code to use slices.
   - In bbox code, use `hull_x[0..hull_count]` and `hull_y[0..hull_count]`.
   - In Newton raster code, load `hull_count` for the element and pass the shortened
     `x`, `y`, `xi`, and `eta` slices to the tessellation builder.

8. Keep the accepted AoSoA Newton candidate path unchanged.
   - This experiment should only change hull generation and coarse in/out logic.

## Validation

After implementation:

1. `zig test -lc -O ReleaseSafe ./src-simd2/test_gold_all.zig`
2. `zig test -lc -O ReleaseSafe ./src-simd2/test_bench.zig`
3. `zig run -O ReleaseFast ./src-simd2/bench_fullraster.zig`
4. `zig run -O ReleaseFast ./src-simd2/bench_sphere2000.zig`

## Expected Outcome

- `bench_fullraster`:
  likely faster for Newton kernels if the reduced hull edge count cuts coarse in/out cost
  enough.
- `bench_sphere2000`:
  uncertain, because a looser convex hull may admit more pixels to the Newton solver.
