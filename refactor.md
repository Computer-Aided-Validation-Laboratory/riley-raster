# REFACTOR:

## General todo
- Remove unused imports
- Use in-built load bmp and save tiff to save texture as tiff in texture folder. Then refactor load tiff to not use libtiff

## Netwon Solver fixes for non-linear elements
- Add newton iteration limits and solver tolerances to RasterConfig
- Fix magic float tolerance numbers in non-linear elements and add tolerance struct/solver config 

## Performance / Functionality Updates
- For tessalated guess - fall back to nearest triangle edge as initial guess?

## meshio.zig
- Remove prints 

## textureio.zig
- Refactor load functions to have comptime parameters first in function signatures.
- Refactor the nonsense tiff texture load function with hard coded libtiff path
- Fix tests? The csv save one is nonsense
- Move Texture and Pixel to textureinterp.zig
- Move image load and save to imageops.zig

## imageops.zig - rename to imageio.zig
- Move all imageio to here
- Add tests to load / save in all formats and check all formats match

## uvio.zig
- TexMap: Add asserts to bounds check that can be compiled out later in setUV and getUV
- TexMap: Rename to UVTexMap
- Rename load_uvs to loadUVs
- loadTexMap should call loadUVs not the other way around

## textureinterp.zig
- Add sample RGB
- Rename getPx1 to just getPx
- GO THROUGH THIS IN DETAIL!
