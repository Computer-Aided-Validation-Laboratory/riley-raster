# Shader pipes

A camera selects a pipe family: `mono`, `rgb`, `ir`, or `multichannel` with an
explicit channel count. A mesh can provide several pipes in a `PipelineShader`.
During rendering, Riley prepares only meshes with a pipe matching that camera.

Each `ShaderSource` writes its sample value to a `Slot`. Source shaders can be
existing texture, nodal, or function shaders. A later stage can read an earlier
slot. `GreyToEmissivity` maps a greyscale channel to a spatially varying
emissivity parameter, and `ClampStage` bounds a value. A `ShaderResolver`
combines the retained slots into the camera's output channels at each surface
sample, before pixel integration and digitisation.

```python
import riley

ch0 = riley.Slot(riley.SlotKind.channel, 0)
ch1 = riley.Slot(riley.SlotKind.channel, 1)
pipe = riley.ShaderPipe(
    family=riley.PipeFamily.mono,
    stages=(
        riley.ShaderSource(first_shader, ch0),
        riley.ShaderSource(second_shader, ch1),
    ),
    resolver=riley.ShaderResolver(
        riley.ResolverKind.sum, slots=(ch0, ch1),
    ),
)
mesh.shader = riley.PipelineShader((pipe,))
camera.pipe_family = riley.PipeFamily.mono
```

`first_shader` and `second_shader` are ordinary Riley shader objects. A
`PipelineShader` can also be passed to `create_mesh`; source nodal data and UVs
then follow the usual mesh conversion. The full working examples are in
`src/riley/pytests/test_shaderpipe.py`.

The resolver choices are `identity`, `sum`, `modulate`, `weighted_sum`,
`greybody_bolometric`, `greybody_band`, and `expression`. An expression is a
bounded stack program of `Operation` records. It can load `channel`, `field`,
`parameter`, and `constant` slots, perform arithmetic, fourth power, clamp,
and a prepared one-dimensional LUT lookup, then store each output channel.
For example, `constant[0] * parameter[0] * field[0]^4` can represent
bolometric greybody exitance. The `greybody_band` resolver accepts a sampled
camera response lookup through `lookup_first`, `lookup_step`, and
`lookup_values`. Values between samples are linearly interpolated.

The public C ABI uses the same records in `src/riley/cython/riley.h`. Its tag
values are documented beside the structs. Riley validates the configuration
during preparation and executes the pipe in Zig; Python callbacks are not
called for surface samples.

For mixed camera families, the returned memory array uses the largest channel
count across the scene. Channels unused by a camera contain the configured
background value. Select the camera's `pipe_family` and `pipe_channels` when
interpreting those channels.
