Procedural speckles
===================

Procedural speckles generate a monochrome pattern from nodal UVs without an
image texture. Supply UVs of shape ``(nodes, 2)``. The entire interpolated map
must lie within the unit square, up to a small numerical tolerance, not just
at the nodes. Pattern sizes are in reference-mesh units, not pixels, and the
pattern follows the mesh as it deforms. On curved or distorted UV maps, spot
size and shape can vary locally. If a pattern is too dense for the sampler's
grid, increase the radius or cell size.

Python
------

For a direct monochrome shader, pass a ``SpeckleShader`` to the ``mono`` role
of a ``MeshShaderSet`` and use that set as the mesh's ``shaders``:

.. code-block:: python

   import riley

   speckle = riley.SpeckleShader(
       uvs=uvs,
       params=riley.Disk2DParams(coverage=0.5, radius=0.25),
   )
   shaders = riley.MeshShaderSet(mono=speckle)

To use the same shader as a source in a ``ShaderPipe``, write it to a channel
register and resolve that register. The identity resolver passes it through;
other stages and resolvers can combine it with other inputs.

.. code-block:: python

   channel = riley.Register(riley.RegisterKind.channel, 0)
   shaders = riley.MeshShaderSet(
       mono=riley.ShaderPipe(
           stages=(riley.ShaderSource(speckle, channel),),
           resolver=riley.ShaderResolver(
               riley.ResolverKind.identity, registers=(channel,),
           ),
       ),
   )

Select ``RenderFormat.mono`` on the camera for either example. Shader scaling
and file scaling are independent: the shader applies
``sample * output_gain + output_offset`` before ``scaling_type``. At the
shader stage, ``ScaleStrategy.auto`` uses the nominal range ``[0, 1]`` and
``bits`` to set the output range. To keep the shader samples in ``[0, 1]``
and map that range to an 8-bit BMP only when saving, leave the shader scaling
at ``ScaleStrategy.none`` and set the camera's ``output_files``:

.. code-block:: python

   camera.output_files = (
       riley.ImageSaveOpts(
           format=riley.ImageFormat.bmp,
           file_bits=8,
           scaling=riley.ScaleStrategy.fixed,
           scaling_min=0.0,
           scaling_max=1.0,
       ),
   )

Use ``SaveStrategy.disk`` or ``SaveStrategy.both`` in ``RasterConfig`` to
write files. The camera settings do not rescale the returned image buffer.

Python parameter reference
~~~~~~~~~~~~~~~~~~~~~~~~~~

.. autoclass:: riley.SpeckleShader

   With ``ScaleStrategy.frac``, ``scaling_min`` and ``scaling_max`` set the output
   interval as fractions of full scale. With ``ScaleStrategy.fixed``, they set
   the input bounds after gain and offset.

.. autoclass:: riley.Disk2DParams

.. autoclass:: riley.Gaussian2DParams

For disk and Gaussian spots, ``coverage`` must be in ``(0, 1)`` and
``occupancy`` (the probability that a grid cell contains a spot centre) must be
in ``(0, 1]``. Use a positive ``radius`` and nonnegative ``jitter`` no larger
than half the radius. Not every combination of coverage and support is feasible.
Disk ``edge_softness`` must be nonnegative.

.. autoclass:: riley.Perlin2DParams

   Use a positive ``cell_size`` and a nonnegative ``transition_width``.
   Perlin has no coverage control.

All patterns share Riley's deterministic default ``seed``. Set another
unsigned 32-bit integer seed for a different realization. The ``foreground``
and ``background`` must be distinct values in ``[0, 1]``. The shader background
is part of the pattern on the mesh; it is separate from the camera background
outside the mesh.

Zig
---

Set the ``shaders`` field of a ``riley.MeshInput`` for a mono camera:

.. code-block:: zig

   .shaders = .{ .mono_direct = .{ .speckle = .{
       .uvs = uvs.array,
       .params = .{ .disk = .{ .radius = 0.25, .coverage = 0.5 } },
   } } },

The ``riley.SpeckleParams`` union takes ``riley.Disk2DParams`` for ``.disk``,
``riley.Gaussian2DParams`` for ``.gaussian``, and ``riley.Perlin2DParams`` for
``.perlin``. Only ``Disk2DParams`` has an ``edge_softness`` field. The same
``SpeckleInput`` works as a ``.speckle`` source in a shader pipe. As in Python,
``output_gain`` and ``output_offset`` are applied before shader scaling;
``CameraInput.output_files`` controls file scaling separately.

Runnable demos
--------------

Run the plane quickstart, the deforming sphere, or the rabbit with a
monochrome shader pipe. Run Zig commands from the repository root; with the
Python package installed, run the Python demos from any writable directory:

.. code-block:: shell

   zig build demo00b-procedural-quickstart
   zig build demo01b-procedural-sphere
   zig build demo02d-rabbit-procedural

.. code-block:: shell

   python -m riley demo00b_procedural_quickstart
   python -m riley demo01b_procedural_sphere
   python -m riley demo02d_rabbit_procedural

Zig writes to ``out/`` and Python writes to ``out_riley_py/``. For other demo
options, reference-UV calibration, coverage constraints, and evaluator
implementation details, see the `developer guide to procedural speckles
<https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/blob/main/dev/PROCEDURAL.md>`_.
