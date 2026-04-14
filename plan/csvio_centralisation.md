## Plan

1. Add `csvio.zig` for shared CSV primitives.
   This module should own:
   - reading trimmed non-empty CSV lines
   - counting comma-separated columns
   - detecting colon-packed channel cells
   - loading scalar 2D CSV arrays
   - loading packed-channel 2D CSV arrays
   - generic scalar and packed CSV grid writers

2. Move `meshio.readCsvToList(...)` into `csvio.zig`.
   Keep `meshio.readCsvToList(...)` as a thin wrapper for compatibility.

3. Centralize the generic CSV writers.
   Convert:
   - `MatSlice.saveCSV(...)`
   - `Texture.saveCSV(...)`
   - `imageio.saveCSV(...)`
   - debug NDArray CSV writers

   into thin wrappers around `csvio.zig`.

4. Centralize the generic CSV readers.
   Convert:
   - `imageio.loadCSV(...)`
   - `uvio.loadUVs(...)`
   - `common/benchcommon.loadNDArrayFromCSV(...)`
   - `common/tests.loadImageFromCSV(...)`
   - `debug/main_diff_images.loadNDArrayFromCSVRGB(...)`

   to reuse `csvio.zig`.

5. Keep domain-specific parsing in the owning modules.
   `meshio.parseCoords(...)`, `parseConnect(...)`, and `parseField(...)`
   should stay in `meshio.zig`, but rely on `csvio` for file reading.

6. Keep existing public CSV methods/functions as thin wrappers.
   This preserves the current API surface while removing duplicated logic.

7. Validate with both SIMD modes:
   - `.simd = .on`
   - `.simd = .off`

   In each mode, run:
   - `zig test -lc -O ReleaseSafe ./src/test_gold_all.zig`
   - `zig test -lc -O ReleaseSafe ./src/test_bench.zig`

8. Restore the default config:
   - `.simd = .on`
   - `.simd_texture_interp = .inner`
