# SIMD Unification Plan

## Goal

Refactor `src-simd` into a single canonical tree that supports both scalar and SIMD
backends via comptime-selected imports, across the whole pipeline:

- geometry prep
- overlap generation
- raster engine
- shader ops
- texture ops where needed
- supporting helpers where backend-specific code exists

The scalar `src` tree remains untouched as the external baseline until the unified
`src-simd` tree is stable.

## High-Level Design

Use a 3-layer structure per subsystem:

1. `*_common.zig`
   Shared types, helpers, orchestration pieces, common loops, common structs.

2. `*_scalar.zig`
   Scalar implementation details.

3. `*_simd.zig`
   SIMD implementation details.

Then expose one public subsystem file:

- `bbox.zig`
- `coordtransform.zig`
- `normals.zig`
- `overlap.zig`
- `rasterengine.zig`
- `shaderops.zig`
- `textureops.zig`

Each public file chooses scalar or SIMD backend at comptime using `buildconfig.zig`.

## Core Rule

Do not duplicate full top-level files unless unavoidable.

The desired split is:

- orchestration in `*_common.zig` or the public file
- hot backend-specific kernels in `*_scalar.zig` / `*_simd.zig`

## Build Configuration

Create `src-simd/zigraster/zig/buildconfig.zig`.

Suggested contents:

```zig
pub const SimdMode = enum {
    off,
    on,
};

pub const Config = struct {
    simd: SimdMode = .on,
    simd_vector_width: comptime_int = 8,
    precision: type = f64,
};

pub const config = Config{
    .simd = .on,
    .simd_vector_width = 8,
    .precision = f64,
};
```

## Dispatch Pattern

Each public subsystem file should dispatch once.

Example:

```zig
const cfg = @import("buildconfig.zig").config;

pub usingnamespace if (cfg.simd == .on)
    @import("bbox_simd.zig")
else
    @import("bbox_scalar.zig");
```

Prefer explicit symbol export over blanket `usingnamespace` once files get large.

## Target File Layout

### Configuration / backend

- `buildconfig.zig`
- `backend.zig` optional, only if it stays small

### Geometry prep

- `coordtransform.zig`
- `coordtransform_common.zig`
- `coordtransform_scalar.zig`
- `coordtransform_simd.zig`

- `bbox.zig`
- `bbox_common.zig`
- `bbox_scalar.zig`
- `bbox_simd.zig`

- `normals.zig`
- `normals_common.zig`
- `normals_scalar.zig`
- `normals_simd.zig`

- `overlap.zig`
- `overlap_common.zig`
- `overlap_scalar.zig`
- `overlap_simd.zig` optional stub or scalar alias initially

### Raster / shading

- `rasterengine.zig`
- `rasterengine_common.zig`
- `rasterengine_scalar.zig`
- `rasterengine_simd.zig`

- `shaderops.zig`
- `shaderops_common.zig`
- `shaderops_scalar.zig`
- `shaderops_simd.zig`

- `shaderkernels.zig`
- `shaderkernels_common.zig`
- `shaderkernels_scalar.zig`
- `shaderkernels_simd.zig`

- `textureops.zig`
- `textureops_common.zig`
- `textureops_scalar.zig`
- `textureops_simd.zig`

### Supporting math only if needed

- `vecsimd.zig` stays as-is
- `shapefun.zig` may stay unified unless scalar/SIMD divergence grows
- `newton.zig` probably stays unified for now
- `geometrykernels.zig` probably stays unified unless dispatch pressure grows

## What Goes Where

### `coordtransform_*`

Own:

- `worldToRasterCoords`
- `worldToRasterSIMD`
- `elemsToRasterSIMD`
- `elemsToClipPxLengSIMD`
- scalar equivalents if needed

### `bbox_*`

Own:

- `countElemsCalcBBoxes`
- `countElemsCalcBBoxesTri3`
- nodal derivative tables if only bbox/normals use them
- backface/orientation helpers
- hull bbox helpers

### `normals_*`

Own:

- `calculateMeshNormals`
- exact-normal helpers
- averaged-normal local accumulation helpers

### `overlap_*`

Own:

- `sceneTileElemOverlap`
- overlap structs
- active tile construction

This is likely scalar/common first. SIMD version can be absent or alias scalar.

### `rasterengine_*`

Own:

- tile raster loops
- scalar tile path
- SIMD tile path
- scratch handling
- subpixel loops
- per-kernel raster dispatch

### `shaderops_*`

Own:

- fill routines
- interpolation/store routines
- masked/full-lane SIMD paths
- scalar shading paths

### `shaderkernels_*`

Own:

- shader entry glue that differs between scalar and SIMD
- calls into `shaderops`

### `textureops_*`

Own:

- scalar samplers
- SIMD samplers
- cubic/quintic/LUT sampling helpers where backend differs

## Detailed Migration Plan

### Phase 0: Inventory

Before edits:

1. Inventory all current `src-simd/zigraster/zig/*.zig` modules.
2. Mark each as:
   - common
   - scalar-specific
   - simd-specific
   - mixed
3. Map imports so dispatch does not create cycles.

### Phase 1: Configuration Layer

1. Add `buildconfig.zig`
2. Add optional `backend.zig` only if it stays tiny
3. Do not change runtime behavior yet

### Phase 2: Geometry Subsystems

1. Extract `coordtransform_*`
2. Extract `bbox_*`
3. Extract `normals_*`
4. Extract `overlap_*`
5. Leave `prepareSceneGeometry` in `rasterops.zig`, but make it call the new subsystem
   modules

### Phase 3: `rasterops.zig` Slimming

After geometry extraction, `rasterops.zig` should become mostly orchestration:

- `prepareSceneGeometry`
- scene-level aggregation
- imports of coordtransform/bbox/normals/overlap

### Phase 4: Shader / Texture Split

1. Split `textureops_*`
2. Split `shaderops_*`
3. Split `shaderkernels_*`

### Phase 5: Raster Engine Split

1. Identify shared orchestration in current `rasterengine.zig`
2. Extract:
   - `rasterengine_common.zig`
   - `rasterengine_scalar.zig`
   - `rasterengine_simd.zig`
3. Keep public `rasterengine.zig` as dispatch layer

### Phase 6: Final Dispatch Cleanup

1. Ensure all subsystem public files dispatch from `buildconfig`
2. Remove stale direct imports of old backend-specific files
3. Keep import graph readable and acyclic

### Phase 7: Validation and Benchmark Pass

Correctness tests must pass in both configurations:

- `.simd = .on`
- `.simd = .off`

Required test commands:

- `zig test -lc -O ReleaseSafe ./src-simd/test_gold_all.zig`
- `zig test -lc -O ReleaseSafe ./src-simd/test_bench.zig`

Performance benchmarking is only required for:

- `.simd = .on`

Benchmark commands:

- `zig run -O ReleaseFast ./src-simd/bench_fullraster.zig`
- `zig run -O ReleaseFast ./src-simd/bench_geom.zig`
- `zig run -O ReleaseFast ./src-simd/bench_sphere2000.zig`

## How To Avoid Duplication

### Good candidates for `*_common`

- shared structs
- enums
- NDArray-facing helpers
- bound/clamp helpers
- derivative-table generation
- orchestration/control flow
- config-driven dispatch wrappers

### Good candidates for split backends

- vector math kernels
- masked vs full-lane raster paths
- shading fills
- sampler implementations
- bbox reduction
- nodal derivative accumulations
- backface/orientation kernels

## Testing Strategy

After each major subsystem extraction:

1. run both `ReleaseSafe` suites with `.simd = .on`
2. run both `ReleaseSafe` suites with `.simd = .off`
3. if geometry touched:
   - run `bench_geom` with `.simd = .on`
   - run `bench_sphere2000` with `.simd = .on`
4. if raster/shader touched:
   - run `bench_fullraster` with `.simd = .on`

## Acceptance Criteria

The refactor is successful if:

1. `src-simd` remains functionally equivalent to the current accepted implementation
2. backend choice is driven from `buildconfig.zig`
3. major subsystems expose one public import path each
4. duplication is reduced relative to separate `src` / `src-simd` trees
5. future scalar/SIMD experiments can be isolated to backend files without cloning
   whole modules
