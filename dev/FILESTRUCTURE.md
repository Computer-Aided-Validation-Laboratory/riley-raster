# Riley Code File Structure

## File organisation
- All file names should be lower case unless directly exposed as a struct
- Use io as a suffix for files that contain operations for reading and writing to disk e.g. imageio.zig
- Use ops as a suffix for collections of utility/data operation functions e.g. meshops.zig
- Use the kernel suffix for files defining structs containing only comptime known constants and inline functions e.g. geometrykernels 
- If a scalar/simd split is required the top level file name becomes a thin wrapper with no implementation details then all implementation and tests is moved into _common.zig, _simd.zig, _scalar.zig files.
- File names should not have underscores unless using _common, _simd or _scalar 

## Within file code organisation
1. Module header block / documentation / description
2. Imports
3. Public constants and public types
4. Public entry-point functions
5. Major internal types shared across the file
6. Main implementation stages, in pipeline order
   - each stage begins with its stage-specific types
   - stage entry function first
   - deeper helpers below it
7. Generic low-level helpers
8. Tests

**Module Header Block**
// --------------------------------------------------------------------------------------
// Riley: A High Performance Rasteriser for DIC UQ
//
// Copyright (c) 2025-2026 scepticalrabbit (Lloyd Fletcher)
// Licensed under the MIT License (see LICENSE file for details)
//
// Authors: scepticalrabbit (Lloyd Fletcher)
// --------------------------------------------------------------------------------------

**Marking Code Blocks**
Each code block should be denoted by a 90 column comment -. As below
// --------------------------------------------------------------------------------------
// Public Constants & Public Types
// --------------------------------------------------------------------------------------

Not all sections may be needed depending on the file. For section 6 we will want the pipeline sections to appear in call order. 

