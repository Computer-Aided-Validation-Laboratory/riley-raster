## Cleanup Plan

Goal:
- keep the current unified backend-switching structure
- reduce duplication by extracting shared code into `*_common.zig`
- avoid changing behavior or performance

## Principles

1. Only extract code that is actually identical or very close.
2. Keep hot backend-specific inner loops in `*_scalar.zig` and `*_simd.zig`.
3. Prefer shared helpers and orchestration first, not heroic generic abstractions.
4. After each subsystem cleanup:
   - `.simd = .off` tests pass
   - `.simd = .on` tests pass
5. Perf checks only for `.simd = .on`, and only after meaningful cleanup batches.

## Target End State

For each major subsystem:
- `name.zig`
- `name_common.zig`
- `name_scalar.zig`
- `name_simd.zig`

Best candidates:
- [`rasterops.zig`](src-simd/zigraster/zig/rasterops.zig)
- [`rasterengine.zig`](src-simd/zigraster/zig/rasterengine.zig)
- [`shaderops.zig`](src-simd/zigraster/zig/shaderops.zig)
- [`shaderkernels.zig`](src-simd/zigraster/zig/shaderkernels.zig)
- [`hull.zig`](src-simd/zigraster/zig/hull.zig)

Lower priority:
- [`textureops.zig`](src-simd/zigraster/zig/textureops.zig)

## Recommended Order

### Phase 1: Inventory
1. Diff each scalar/SIMD pair and classify code into:
   - identical
   - trivially parameterizable
   - genuinely backend-specific
2. Start with the smallest/highest-confidence subsystem first.

### Phase 2: Hull
1. Create `hull_common.zig`.
2. Move shared types and tessellation helpers there.
3. Leave only backend-specific return-shape or SIMD-only helpers in:
   - `hull_scalar.zig`
   - `hull_simd.zig`

Why first:
- small surface area
- low risk
- good pattern setter

### Phase 3: Shader Kernels
1. Create `shaderkernels_common.zig`.
2. Move shared shader dispatch/orchestration there.
3. Keep only backend-specific kernel entry glue in:
   - `shaderkernels_scalar.zig`
   - `shaderkernels_simd.zig`

### Phase 4: Shader Ops
1. Create `shaderops_common.zig`.
2. Move shared:
   - prepared/input types
   - common interpolation setup
   - non-hot control flow
3. Keep only actual scalar vs SIMD fill/store kernels separate.

### Phase 5: Raster Ops
1. Create `rasterops_common.zig`.
2. Move shared:
   - structs
   - enum helpers
   - high-level geometry prep orchestration
   - common bbox/normal setup that does not differ
3. Keep backend-specific geometry kernels in the backend files.

### Phase 6: Raster Engine
1. Create `rasterengine_common.zig`.
2. Move shared:
   - scratch structs
   - resolve orchestration
   - top-level raster pass control flow
3. Keep backend-specific tile loops separate.

### Phase 7: Texture Ops
1. Revisit texture API mismatch.
2. Define one canonical shared texture API in `textureops_common.zig`.
3. Make scalar and SIMD backends conform to it.
4. Only then make `textureops.zig` a true backend switch.

This should be last because it is the messiest compatibility area.

## Extraction Rules

Good `_common` candidates:
- shared structs
- shared enums
- dispatch tables
- orchestration functions
- helper math that is byte-for-byte the same
- common file-local constants

Keep backend-specific:
- vector math kernels
- masked/full-lane store paths
- raster inner loops
- sampler fast paths
- any code whose shape differs materially between scalar and SIMD

## Validation Plan

After each phase:
1. `zig test -lc -O ReleaseSafe ./src-simd/test_gold_all.zig` with `.simd = .off`
2. `zig test -lc -O ReleaseSafe ./src-simd/test_bench.zig` with `.simd = .off`
3. `zig test -lc -O ReleaseSafe ./src-simd/test_gold_all.zig` with `.simd = .on`
4. `zig test -lc -O ReleaseSafe ./src-simd/test_bench.zig` with `.simd = .on`

After Phases 4-6:
- run `bench_fullraster`, `bench_geom`, `bench_sphere2000` with `.simd = .on`

## Acceptance Criteria

Cleanup is complete when:
- each major subsystem has a stable `*_common.zig` split where appropriate
- duplicate code is materially reduced
- `textureops` no longer needs the current compatibility shortcut
- tests pass in both modes
- `.simd = .on` performance remains within the existing uncertainty bounds

## Recommendation

Start with:
1. `hull`
2. `shaderkernels`
3. `shaderops`

Those should give the cleanest early wins with the least risk. After that, do
`rasterops`, then `rasterengine`, and leave `textureops` for last.
