# Riley Code File Structure

## Zig module file organisation

These rules apply to Zig implementation modules. Standalone entry points and
named test suites follow [Programs and tutorials](#programs-and-tutorials).

- Module file names should be lower case unless directly exposed as a struct
- Use io as a suffix for files that contain operations for reading and writing to disk e.g. imageio.zig
- Use ops as a suffix for collections of utility/data operation functions e.g. meshops.zig
- Mesh, camera, and shader input/static/prepared declarations live in
  `meshtypes.zig`, `cameratypes.zig`, and `shadertypes.zig`. Texture storage and
  sampling configuration declarations live in `texturetypes.zig`; sampling operations
  and coefficient LUTs live in `textureops*.zig`. Timing structs live in `report.zig`.
  Canonical mesh
  coordinate, connectivity, and field declarations live in `meshtypes.zig` and
  `fieldtypes.zig`. Internal code imports declarations from those owners.
- Internal implementation code imports modules and qualifies external types, functions,
  and shared constants through the owning module, for example `report.GeomTimes`
  and `std.Io.Clock.Timestamp`. Use a lowercase namespace matching the source
  filename, including scalar/SIMD suffixes. Do not introduce local declaration
  aliases or route internal imports through unrelated re-exports.
  `buildconfig.zig` is the shorthand exception: `F`, SIMD types, `cfg`, and
  configuration-derived constants may remain unqualified. Local types, generic
  parameters, and ordinary local values such as allocator handles are unaffected.
  Public API facades, thin implementation-selection wrappers, and associated types
  required by generic kernel interfaces may deliberately re-export declarations;
  qualify external declarations inside their implementation bodies.
- The public Zig API is assembled explicitly in `api/core.zig` and exposed
  through `api.zig`, the `riley` module root for external consumers. Repository
  demos import `riley/zig/api.zig` by relative path so standalone `zig run` works;
  build wrappers supply configuration without a named Riley dependency.
  Public load/save, numerical, and operation namespaces are assembled in `api/dataio.zig`,
  `api/maths.zig`, and `api/ops.zig`. Do not add `usingnamespace` or duplicate
  implementation types in the public API.
- Input-to-Static constructors use `create*StaticFromInput` names, including
  `createMeshStaticFromInput`; frame preparation uses `prepare*FromStatic`.
- Shader evaluation fill functions live in `shaderfill_scalar.zig` and
  `shaderfill_simd.zig`, exported by the thin `shaderfill.zig` facade.
  Shader selection, conversion, and construction helpers live in `shaderops.zig`.
- Shader-pipe register, operation, and resolver declarations live in
  `shaderpipe.zig`; raster shading kernels live in `shaderpipekernels.zig`.
  Shader-pipe intermediate addresses are `Register` values. Stage endpoints use
  `register_source` and `register_dest`; resolver expressions use `ResolverProgramInput`
  and `ResolverOp`. Register state is held by `RegistersWritten` and `RegistersOutput`.
  Stage, register, instruction, and stack capacities come from
  `buildconfig.config.shaderpipe`; output channels use `config.max_image_channels`.
- `ResolverInput` and `ResolverProgramInput` describe and validate resolver inputs.
  Only `ResolverPrepared` and `ResolverProgramPrepared` evaluate registers. Static
  construction prepares lookup metadata and ambient radiance once. Prepared
  resolvers are tagged unions with variant-specific payloads; expression lookup
  metadata belongs to the static arena, while table values remain borrowed.
- Shader-pipe stages use `.shader` for shader evaluation, alongside operation
  tags such as `.clamp`, `.blend`, and `.lut_map`.
- Shader roles derive from the tags of `shadertypes.RenderFormat`.
  `ActiveShaderRoles` is an enum set; per-role mesh hit selections use an enum
  array keyed by the same roles. Avoid positional role arrays and numeric indices.
- Mesh Static initialization prepares only shader roles used by the render cameras.
  It owns invariant scale factors, normalised function/channel records, pipe
  constants, and per-role geometry requirements. Frame Prepared records borrow
  immutable metadata from this storage; the static arena must outlive all frame
  workers. Frame-dependent nodal scaling and visible-element gathering remain in
  frame preparation. Geometry caches proportional to element count are not added
  merely to avoid arithmetic.
- Camera framing and placement helpers live in `cameraframeops.zig`; camera
  slice preparation is private render setup in `riley.zig`; projection lives in
  `cameraprojops*.zig`.
- Use the kernel suffix for files defining structs containing only comptime known constants and inline functions e.g. geometrykernels
- If a scalar/simd split is required the top level file name becomes a thin wrapper with no implementation details then all implementation and tests is moved into _common.zig, _simd.zig, _scalar.zig files.
- Zig module file names should not have underscores except for `_common`,
  `_simd`, `_scalar`, and the suffixes listed below.

## Exceptions
- ABI-facing files may retain established external naming
- Generated artefacts and non-Zig files are out of scope for the Zig module rules
- Thin wrapper files should contain no implementation logic and no tests
- Existing file names should only be changed when the rename improves clarity
- Global subpixel buffer implementation files use `_globbuff` before any
  `_common`, `_scalar`, or `_simd` suffix, to distinguish them from tile-local
  implementations. Function and type names retain Zig casing conventions.
- Single-root and multi-root Newton SIMD paths share the final contiguous, masked
  winner-shading pass in `rasterengine_simd.zig`. Solvers populate scratch masks
  and winning parameter coordinates before that shared pass performs depth tests
  and shader evaluation.
- Forward shader-pipe lookup tables use SIMD index/interpolation arithmetic with
  per-lane gathers. Inverse monotonic lookup remains a scalar search per lane.
- Raster execution files may use `_tileloc` for the tile-local buffer strategy.
  `rasterengine.zig` is the thin entry-point facade. `rasterengine_tileloc.zig`
  and `rasterengine_globbuff.zig` own their worker lifecycles and scratch
  binding; both call the shared subpixel core in `rasterengine_common.zig`.
  The scalar and SIMD raster kernels remain in `rasterengine_scalar.zig` and
  `rasterengine_simd.zig`.

## Programs and tutorials

- Reserve `demo` names for runnable, user-facing tutorials in Zig and Python.
  Show the full setup (inputs, camera, shader, and render/output configuration)
  through Riley's APIs. Repeat setup when it helps readers follow the example
  rather than hiding the setup behind shared tutorial wrappers. Keep small,
  purpose-specific helpers for mechanics such as CLI parsing or safe output
  directory cleanup; don't abstract away the Riley APIs the demo teaches.
- Use `test_<subject>` for new named test suites, `gen_gold_<suite>` for gold
  reference generators, `verif_<subject>` for standalone numerical verification
  drivers, and `bench_<workload>` for performance measurement tools.
- Keep shared internal tooling under `dev_support` where appropriate. Name
  standalone internal tools for their operation (for example, `run_all_demos.zig`),
  rather than naming them as tutorials.

Keep established names, including older forms such as `benchcam.py`; do not
rename existing files solely to match these conventions.

Use underscores in tutorial source names, hyphens in Zig build steps, and the
extensionless source name in the Python CLI. Use that same source name as the
default output directory under `out/` (Zig) or `out_riley_py/` (Python). For
example, `demo07_shaderpipe_quickstart` runs via
`zig build demo07-shaderpipe-quickstart` or
`python -m riley demo07_shaderpipe_quickstart`.

## Within file code organisation
1. Module header block / documentation / description
2. Imports
3. Module constants
4. Public entry-point functions
5. Public constants and public types
6. Main implementation stages, in pipeline order
   - organise code from public entry points down to deeper private internals
   - within each stage place functions in pipeline or call order
   - place stage-local types as close as practical above their first real use
   - if a struct owns methods, keep the struct and its methods together as one unit
   - stage entry function first, then deeper helpers below it
7. Generic low-level helpers
8. Tests

For files using the `ops` suffix:
- these files may not control the overall application pipeline themselves
- even so, functions should still be grouped in local pipeline or call order
- types should still be placed near where they are first used
- organise the file from higher-level public operations down to deeper private helpers

**Module Header Block**
```
// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher) and James Panayis
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher), James Panayis
// --------------------------------------------------------------------------------------
```
**Marking Code Blocks**
Each code block should be denoted by a 90 column comment -. As below
```
// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------
```

Not all sections may be needed depending on the file. The main rule is to keep the
reader moving from the public surface down through the implementation in call order,
with types placed close to where they are first needed.
