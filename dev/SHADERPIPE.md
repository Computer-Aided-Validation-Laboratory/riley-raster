# Shader sets and shader pipes

A mesh owns one `MeshShaderSet` of optional, named alternatives: `direct`, `mono`, `rgb`, `ir`, and `multifield`. Each camera chooses one with `shader_selection` (default `direct`). A camera skips meshes without its selected role. Riley rejects a camera if no mesh in its scene supports that role; it never falls back to another shader. A single mesh can therefore serve optical and IR cameras using the same geometry and displacement frames.

`direct` holds one ordinary nodal, texture, or function shader and keeps the specialised direct raster kernel. The other roles hold a `ShaderPipe`. Mono and IR output one channel, RGB outputs three, and multifield requires an explicit `channels` count from 1 to 8. Camera batches return an array padded to the largest **selected** channel count; unused channels contain the background value. Unselected roles do not add frames or output channels. Selecting a pipe does not change image file format or ADC encoding.

A pipe evaluates source and transform stages in order at each covered surface sample. Sources write to `channel`, `field`, or `parameter` slots; subsequent stages may read earlier slots. `constant` slots belong to the resolver expression. `GreyToEmissivity` maps a sampled grey value to a spatial emissivity parameter. `ClampStage` bounds a value. The final `ShaderResolver` produces the sample's output channels before pixel integration. Available resolvers include `identity`, `sum`, `modulate`, `weighted_sum`, `greybody_bolometric`, `greybody_band`, `greybody_band_apparent_c`, and `expression`. The expression resolver uses bounded, validated stack operations for arithmetic, fourth power, clamps, and lookups. Configuration is validated before rasterisation; there are no Python callbacks per sample.

```python
import riley

ch0 = riley.Slot(riley.SlotKind.channel, 0)
ch1 = riley.Slot(riley.SlotKind.channel, 1)
pipe = riley.ShaderPipe(
    stages=(riley.ShaderSource(first_shader, ch0),
            riley.ShaderSource(second_shader, ch1)),
    resolver=riley.ShaderResolver(riley.ResolverKind.sum, slots=(ch0, ch1)),
)
mesh.shaders = riley.MeshShaderSet(direct=first_shader, mono=pipe)
mono_camera.shader_selection = riley.CameraShaderSelection.mono
```

A pipe source is an ordinary *direct* shader; pipes cannot recursively contain pipes. In Python, `riley.create_mesh(..., shaders=riley.MeshShaderSet(...))` also remaps nodal and UV data into Riley's mesh convention. The same concepts are exposed in Zig through `MeshShaderSetInput`, `ShaderPipeInput`, and `CameraShaderSelection`. The C ABI transport is documented by the tags in `src/riley/cython/riley.h`.

## IR apparent temperature

`greybody_band_apparent_c` consumes Kelvin temperature and unitless emissivity slots plus a monotonic band-integrated Planck radiance lookup. For ambient temperature `T_amb`, it computes `L = emissivity * L_bb(T) + (1-emissivity) * L_bb(T_amb)`, inverts the same lookup, and outputs blackbody-equivalent apparent temperature in °C. It is a simple opaque diffuse surface model with unit transmission and no atmosphere. It does **not** recover emissivity-corrected material temperature. Lookup interpolation and its inverse clamp at the calibrated endpoints. See demo9 for a flat 8–14 µm response and an explicit 0–250 °C output calibration.

## Per-camera TIFF encoding

`Camera.output_encoding` is independent of shader selection. `native` uses the existing image save scaling. `grid12_to_u16` maps a declared raw range to 12-bit codes 0–4095, then stores each as `16 * code` (0–65520) in a 16-bit TIFF. `linear_u16` maps a declared raw range linearly to 0–65535. Both encodings clamp outside the declared range, require 16-bit TIFF disk output, and leave returned floating-point memory images in physical/raw units. Demo9 uses 0–255 source intensity for DIC and 0–250 °C apparent temperature for IR. Decode IR TIFF codes as `C = code * 250 / 65535`.

## Examples and migration

`demo7_shaderpipe_quickstart` renders one checker mesh through a direct and a lit mono choice. `demo8_shaderpipe_gallery` has four self-contained pipe examples. `demo9_diciruq` uses one deforming FE mesh for two direct stereo DIC cameras and one IR camera. `demo10_sphere_lit` renders the sphere simulation under three conditions: direct speckle, direct Lambertian lighting, and their combined modulated shader pipe. Each has Zig and Python versions.

The previous mesh `.shader`/`PipelineShader` and camera `pipe_request`/`pipe_family` API was removed. Use mesh `.shaders = .{ .direct = shader }` and camera `.shader_selection`. Pipes no longer carry a family: the `ShaderSet` slot defines the role.
