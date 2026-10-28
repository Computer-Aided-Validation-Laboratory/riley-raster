# Harmonised Shader Sets and Shader Pipes

## Overview

A mesh owns format-aligned shader definitions. Zig's `MeshShaderSetInput` exposes the supported combinations as flat fields: `mono_direct`, `mono_pipe`, `ir_direct`, `ir_pipe`, `rgb_pipe`, and `multifield_pipe`. Python's `MeshShaderSet` accepts shader objects under `mono`, `rgb`, `ir`, and `multifield` and infers direct versus pipe from the object type. Each camera defines its required `render_format` (`.mono`, `.rgb`, `.ir`, or `.{ .multifield = count }` in Zig; `RenderFormat` in Python).

Input validation rejects setting both direct and pipe for one format. Static and Prepared Zig shader sets retain a tagged `direct | pipe` union for mono and IR after input preparation.

```text
Camera.render_format  ───►  Selects mesh shader role: .mono / .rgb / .ir / .multifield
                            ├── Mono/IR direct shader: specialised kernel dispatch
                            └── ShaderPipe: multi-stage composition with resolver
```

A camera only rasterises meshes that provide a shader matching its `render_format`. If any camera in the scene has no compatible mesh, initialization fails early with `NoCompatibleShader`. Multiple cameras (e.g. stereo visible cameras and an IR camera) can view shared geometry while selecting appropriate shaders.

## Format Roles and Arity

| Role | Intrinsic channels | Execution options | Use case |
| --- | --- | --- | --- |
| `mono` | 1 | Direct or Pipe | Greyscale imaging, single-channel DIC |
| `rgb` | 3 | Pipe | Color imaging, multi-channel DIC |
| `ir` | 1 | Direct or Pipe | Thermal and infrared imaging, apparent radiance |
| `multifield` | 1–8 (explicit) | Pipe | Multi-field nodal data, physical diagnostics |

Direct shaders retain specialised, zero-overhead raster kernels. Direct shaders and pipe sources share unified source parameter contracts (`output_gain: F = 1.0`, `output_offset: F = 0.0`, `scaling: ScaleStrategy = .none`).

### Zig texture inputs

Texture storage uses `TexDataFix(T, C)` when the channel count is fixed and
`TexDataDyn(T)` when the count is chosen at runtime. The shader union tag
selects the input type, so callers do not need to spell out `TexInput(...)`:

```zig
const mono_tex = try texops.TexDataFix(u8, 1).init(allocator, rows, cols);
const mono_shader: shaderops.ShaderDirectInput = .{ .tex_u8 = .{
    .uvs = uvs,
    .tex = mono_tex,
} };

const fields_tex = try texops.TexDataDyn(F).init(allocator, 4, rows, cols);
const fields_shader: shaderops.ShaderDirectInput = .{ .tex_multi_f = .{
    .uvs = uvs,
    .tex = fields_tex,
} };
```

The dynamic texture stores its actual channel count in `array.dims[0]`.
Preparation validates the supported 2–8 channel range and converts integer
multifield textures to floating-point storage once before rendering.

## Shader Pipes and Resolvers

A `ShaderPipe` evaluates ordered source and transform stages at each covered surface sample:

1. **Sources:** Write directly to `channel`, `field`, or `parameter` slots.
2. **Transforms:** Dedicated, per-sample operators:
   - `AffineMap`: `dest = gain * src + offset`.
   - `LUTMap`: Uniformly spaced 1D lookup table with endpoint clamping.
   - `Blend`: `dest = (1 - alpha) * a + alpha * b`.
   - `Normalise`: Normalises 2 or 3 vector components into destination slots.
   - `GreyToEmissivity`: Maps sampled greyscale value to spatial emissivity.
   - `ClampStage`: Bounds a value to `[min, max]`.
3. **Resolver:** Synthesizes final sample channels before pixel integration:
   - `identity`: Single slot pass-through.
   - `sum`: Sum of multiple input slots.
   - `modulate`: Multiplies slots by a scalar factor slot.
   - `weighted_sum`: Linear combination with fixed weights.
   - `greybody_bolometric`: Total thermal emissive power.
   - `greybody_band`: Monotonic band-integrated Planck radiance.
   - `greybody_band_apparent_c`: Band radiance inversion returning apparent temperature in °C.
   - `expression`: Bounded stack-based calculator for non-linear models.

Pipes are validated prior to rendering. There are no Python callbacks or dynamic allocations during rasterisation.

## Camera Output and Digitisation

Each camera owns `output_files: []const ImageSaveOpts`. Every file has its own:
- `format`: `.bmp`, `.tiff`, `.ppm`, `.fimg`, `.csv`.
- `file_bits`: 8 or 16 for integer files; `null` for floating CSV/FIMG.
- `adc_bits`: optional integer precision; `null` means use `file_bits`. Both widths `null` means no quantisation.
- `scaling`: `.none` treats scene values as ADC codes; `.auto`, `.fixed`, and `.frac` map scene values into the ADC range.
- `packing`: `.spread` (default) expands ADC codes across the file range; `.lower` stores codes in the low bits; `.upper` shifts them into the high bits. With equal widths these produce identical codes.

For a 12-bit DIC camera saved as 16-bit TIFF, use `file_bits = 16`, `adc_bits = 12`, `scaling = .{ .fixed = .{ 0, 255 } }`, and `packing = .upper`. For full 16-bit range mapping, use `file_bits = 16`, `adc_bits = null`, and `.fixed` scaling. A camera may save a floating CSV and a digitised TIFF in the same render.

Returned in-memory arrays always preserve physical floating-point scene values.

## Python Example

```python
import numpy as np
import riley

coords = np.array([[-0.5, -0.5, 0], [0.5, -0.5, 0], [0, 0.5, 0]], dtype=np.float64)
connect = np.array([[0, 1, 2]], dtype=np.int64)
conv = riley.ConnectConvention(
    riley.EElemType.TRI3, riley.EConnectAxis.ROW, 0, riley.ENodeOrder.RILEY,
)

checker = riley.FunctionShader(
    builtin=riley.FuncShaderBuiltin.checker,
    coord_mode=riley.FuncCoordMode.world_reference,
    params=riley.FuncShaderParams(coord_scale=(4.0, 4.0)),
)

ch0 = riley.Slot(riley.SlotKind.channel, 0)
param = riley.Slot(riley.SlotKind.parameter, 0)
lit_pipe = riley.ShaderPipe(
    stages=(
        riley.ShaderSource(checker, ch0),
        riley.ShaderSource(
            riley.FunctionShader(builtin=riley.FuncShaderBuiltin.constant), param,
        ),
    ),
    resolver=riley.ShaderResolver(
        riley.ResolverKind.modulate, slots=(ch0,), factor=param,
    ),
)

mesh = riley.create_mesh(
    conv, riley.MeshType.tri3opt, coords, connect,
    riley.MeshShaderSet(mono=lit_pipe),
)

camera = riley.Camera(
    pixels_num=(512, 512), pixels_size=(0.02, 0.02),
    pos_world=(0, 0, 1), rot_world=(0, 0, 0), roi_cent_world=(0, 0, 0),
    focal_length=1.0, sub_sample=4,
    render_format=riley.RenderFormat.mono,
    output_files=[
        riley.ImageSaveOpts(
            format=riley.ImageFormat.bmp, file_bits=8, scaling=riley.ScaleStrategy.auto,
        )
    ],
)

config = riley.RasterConfig(parallel=1, save_strategy=riley.SaveStrategy.memory)
images = riley.raster(mesh, camera, config)
```
