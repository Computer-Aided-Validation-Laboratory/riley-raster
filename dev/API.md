# Riley public API and language boundary

## Scene-building API

The Zig `riley` module exports scene inputs, camera configuration, shader inputs,
rendering, and data loading/saving. `riley.ops` contains scene/camera operations and
shader-input construction helpers. Engine preparation, normal generation, texture
sampling, scaling implementation, and worker scheduling remain internal.

All existing `riley.maths` types remain public. Shader input capacities are available
as `riley.max_channels` and `riley.max_slots` for callers constructing input arrays.

Render using `raster`, or use `calcAllFramesImageDims` and `rasterInto` when reusing
caller-owned image storage. Benchmark capture and externally managed render groups
are implementation interfaces, not exports of the user module.

`riley.dataio` exports simulation/UV owners and loaders, image load/save, numerical
FIMG loading, and camera/stereo save/load. Callers release the owning objects using
their documented allocator/deinitialisation methods.

Camera framing over meshes requires only records with a `coords: riley.Coords`
field. It accepts full `MeshInput` records and coordinate-only records, allowing
camera placement before materials, connectivity, and displacement are available.

## Python scene inputs

Public Python scene dataclasses and enums live in `riley/types.py` and are imported
from `riley`. Cython adapts these objects to the C ABI; it does not implement shader
preparation or rendering algorithms.

- Cameras select `RenderFormat.mono`, `.rgb`, `.ir`, or `.multifield`; a multifield
  camera also specifies `render_channels`.
- Each camera owns its `background_value` and `output_files` (`ImageSaveOpts`).
- `MeshShaderSet` defines explicit `mono`, `rgb`, `ir`, and `multifield` roles.
  Mono/IR accept a direct source or a `ShaderPipe`. RGB/multifield plain sources
  are normalised into identity pipes by the Python model before marshalling.
- `RasterConfig.report_perf` selects `ReportMode.off` or `.bench`;
  `report_console` independently controls console reporting. Both are off by default.
- Image format, file/ADC bits, scaling, and packing are specified in camera output
  options. There are no global image-save-mode or full-statistics options.
- Camera placement uses `pos_frame_coords`, `pos_frame_mesh`, and
  `pos_frame_meshes`, with optional `target` and a `FrameFitMode`.

Procedural sources use `FunctionShader` for scalar/RGB evaluation and
`FunctionMultiShader` with independent `FunctionChannel` objects for one to eight
scalar channels. Texture sources support one to eight channels in `u8`, `u16`, or
floating storage; the public Zig dynamic texture inputs handle non-mono/RGB sources.

## C ABI

`c-riley.zig` imports Riley only through `api.zig`. It converts C descriptors into
public Zig inputs and calls the public render, scene, camera, and data-I/O APIs.
The C ABI uses production `f64` storage. Boundary code validates pointers, descriptor
shapes, and enum representations; native preparation validates scene semantics.

Each exported call owns an arena for converted descriptors. Numeric input arrays
are borrowed for the synchronous call; callers keep them alive and unmodified until
it returns. Render allocations use the renderer's allocator, not the descriptor arena.

Cython keeps NumPy arrays alive for borrowed numeric buffers and aligned descriptor
blocks. Descriptor storage is released on normal return and exceptions. The output
image is caller-owned NumPy storage, sized through `rileyCalcOutputDimsScene` before
`rileyRaster` fills it. Camera loading copies coefficients into caller-owned buffers.

Shader input and execution descriptors use tagged unions. Only the active payload
is accessed. Function coefficients are fixed-size arrays instead of individual scalar
fields. The transport tags are:

| Shader tag | Payload |
| --- | --- |
| 0 | Mono texture |
| 1 | RGB texture |
| 2 | Nodal source |
| 3 | Scalar function |
| 4 | RGB function |
| 5 | RGB nodal source |
| 6 | Independent function channels |
| 7 | Dynamic multichannel texture |

Texture storage tags are `0 = u8`, `1 = u16`, and `2 = f64`. Shader format tags
are `0 = mono`, `1 = rgb`, `2 = ir`, and `3 = multifield`. Execution tags are
`0 = direct` and `1 = pipe`; RGB and multifield require pipe execution, matching
`MeshShaderSetInput` in Zig. Camera framing C calls take coordinate descriptors and
an optional target pointer, without requiring shader descriptors.

The obsolete `full_stats`, camera `shader_selection`, shader-set `direct` alias,
and deprecated fill-frame wrappers have been removed. This is an intentional ABI
and Python API change: rebuild C callers and the Cython extension together.

## Declarations and verification

The extern declarations in `c-riley.zig` are the source of truth for the generated
`cython/riley.h`, `cython/riley.pxd`, and independent C compiler layout fixture.
After changing an extern declaration, run:

```sh
python scripts/gen_c_abi.py
python scripts/gen_c_abi.py --check
zig build test-public-api
zig build test-c-abi
```

The layout test compares size, alignment, and every field offset between Zig and
the C compiler, including union payloads. Package builds reject stale generated
headers/declarations and rebuild the native library when any Zig source changes.

Build bindings before running Python tests:

```sh
.venv/bin/python setup.py build_ext --inplace --force
RILEY_FORCE_ZIG_RENDER=1 .venv/bin/python -m pytest src/riley/pytests/
```

Run verification/basic in Debug and the full suite in ReleaseSafe, as described
in `TESTING.md`. Existing render gold must not be regenerated for API changes.
