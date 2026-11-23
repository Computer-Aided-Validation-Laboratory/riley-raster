# Riley Code File Structure

## Zig module file organisation

These rules apply to Zig implementation modules. Standalone entry points and
named test suites follow [Programs and tutorials](#programs-and-tutorials).

- Module file names should be lower case unless directly exposed as a struct
- Use io as a suffix for files that contain operations for reading and writing to disk e.g. imageio.zig
- Use ops as a suffix for collections of utility/data operation functions e.g. meshops.zig
- Use the kernel suffix for files defining structs containing only comptime known constants and inline functions e.g. geometrykernels
- If a scalar/simd split is required the top level file name becomes a thin wrapper with no implementation details then all implementation and tests is moved into _common.zig, _simd.zig, _scalar.zig files.
- Zig module file names should not have underscores except in the suffixes below and `_common`, `_simd`, or `_scalar`.

## Exceptions
- ABI-facing files may retain established external naming
- Generated artefacts and non-Zig files are out of scope for the Zig module rules
- Thin wrapper files should contain no implementation logic and no tests
- Global subpixel buffer implementation files use `_globbuff` before any
  `_common`, `_scalar`, or `_simd` suffix, to distinguish them from tile-local
  implementations. Function and type names retain Zig casing conventions.
- Raster execution files may use `_tileloc` for the tile-local buffer strategy.
  `rasterengine.zig` is the thin entry-point facade. `rasterengine_tileloc.zig`
  and `rasterengine_globbuff.zig` own their worker lifecycles and scratch
  binding; both call the shared subpixel core in `rasterengine_common.zig`.
  The scalar and SIMD raster kernels remain in `rasterengine_scalar.zig` and
  `rasterengine_simd.zig`.

## Programs and tutorials

- Reserve `demo` names for runnable, user-facing tutorials in Zig and Python.
  Each tutorial shows its complete setup, including inputs, camera, shader, and
  render/output configuration. Repeat setup where it helps readers follow the
  example; use Riley's APIs directly instead of hiding setup behind shared
  tutorial wrappers.
- For new test suite files, use `test_<subject>`; for gold reference generators,
  use `gen_gold_<suite>`. Use `verif_<subject>` for standalone numerical
  verification drivers and `bench_<workload>` for performance measurement tools.
- Keep shared internal tooling under `dev_support` where appropriate. Give
  standalone internal tools names that describe the operation, such as
  `run_all_demos.zig`, rather than naming them as tutorials.

Keep established source and program names, including older forms such as
`demoprocedural*.zig`, `testunit.zig`, and `benchcam.py`. Apply the conventions
when adding new files; do not rename existing ones just to match the convention.
Output directories such as `out/procedural_pattern/` are artifact locations, not
program names, and do not follow these rules.

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
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
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
