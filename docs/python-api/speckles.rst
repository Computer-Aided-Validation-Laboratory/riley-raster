Procedural speckles
===================

Set a mesh's ``shader`` to :class:`riley.SpeckleShader` for monochrome disk,
Gaussian, or Perlin patterns. Pass the mesh's nodal UVs as an array of shape
``(nodes, 2)`` and supply pattern parameters:

.. code-block:: python

   import riley

   shader = riley.SpeckleShader(
       uvs=uvs,
       params=riley.Speckle2DParams(coverage=0.5, radius=0.25, seed=42),
   )

Disk is the default. For Gaussian spots, set ``pattern=riley.SpecklePattern.gaussian``
on :class:`riley.Speckle2DParams`. For Perlin noise, pass :class:`riley.Perlin2DParams`
instead.

.. _speckle-calibration:

Physical calibration and coverage
---------------------------------

Disk/Gaussian ``radius`` and Perlin ``cell_size`` use reference-mesh coordinate
units: 0.25 means 0.25 mm if coordinates are in mm, not pixels or a bounding-box
fraction. Perlin uses the same geometry calibration but has no coverage parameter.
Its threshold and transition width are in noise units.

Calibration is shared by all parts of one ``Mesh`` and uses the reference
geometry actually rendered, including higher-order geometry unless mesh conversion
has reduced its order. Uniform orthogonal planar maps preserve physical circles
and square Perlin cells; curved or distorted maps do not guarantee equal local
sizes or geodesic circles. Seams and poles may share physical positions across
nodes if the face interiors and UV metric remain usable. The pattern follows mesh
deformation without recalibrating for each frame or camera.

Coverage is the nominal expected union-area fraction at the specified radius,
not a finite-image guarantee or mean opacity. Jitter and softness do not change
placement density but can change realised coverage and intensity. Soft disk
edges and Gaussian profiles vary the intensity within their supports.

Patterns use automatic analytic evaluators, not quantized textures. A fixed seed
is repeatable within a build, not necessarily identical across f32/f64 builds;
Python uses f64.

.. _speckle-uv-domain:

UV domain and memory
--------------------

The entire interpolated UV map of every referenced face must lie in the unit
square, with a ``2e-5`` allowance at each boundary. Preparation checks this once;
the sampler clamps to the unit square. For quadratic elements, in-range nodal
UVs are not enough: preparation may reject a near-boundary map it cannot certify.

Sampler storage spans the unit square, not just the occupied UV islands. Small
islands can therefore increase memory without increasing physical pattern density.
When atlas placement is not needed, rescale the UV layout to use more of the
square, preserving its proportions where practical.

.. _speckle-preparation:

Preparation and errors
----------------------

Construction stores parameters; render validation checks scalar controls before
calibration. With ``ValidateInput.off``, scalar inputs and mesh metadata are
assumed valid and mesh arrays are not scanned, but preparation still checks the
UV domain, calibration, and resource limits.

When rendering, Python raises ``TypeError`` if ``params`` is not a
:class:`riley.Speckle2DParams` or :class:`riley.Perlin2DParams` instance, and
``ValueError`` if ``Speckle2DParams.pattern`` is not a valid
:class:`riley.SpecklePattern` value. Seeds use Python's integer protocol (including
NumPy integers, but not Python or NumPy booleans). Invalid seed types raise
``TypeError``; integers outside ``[0, 2**32 - 1]`` raise ``ValueError``.

Native errors reach Python as ``RuntimeError``:

- ``UnattainableSpeckleCoverage``: a target strictly inside ``(0, 1)`` exceeds
  the maximum attainable at this occupancy; lower coverage or raise occupancy.
- ``InvalidSpeckleCoverage``, ``InvalidSpeckleRadius``, ``InvalidSpeckleJitter``,
  ``InvalidSpeckleOccupancy``, or ``InvalidSpeckleEdgeSoftness``: correct the named
  control using the bounds in :class:`riley.Speckle2DParams`.
  ``SpeckleEdgeSoftnessRequiresDisk`` means use zero softness for Gaussian patterns.
- ``UnsupportedSpeckleSupport``: reduce jitter, softness, or coverage, or raise
  occupancy up to 1. Combined support must fit the sampler even when each control
  is individually valid, and a request at the limit can round over it after
  conversion. Preparation does not change density or select a fallback.
- ``InvalidSpeckleCellSize``: supply a positive finite Perlin cell size.
- ``SpeckleDensityOutOfRange``: the derived grid exceeds coordinate precision or
  representable storage. Increase radius or cell size, or adjust the UV mapping
  as described in :ref:`speckle-uv-domain`.
- ``InvalidSpeckleUvDomain``: the interpolated UV map is outside the allowed domain
  or could not be certified.
- ``InvalidSpeckleReferenceGeometry`` or ``InvalidSpeckleUvGeometry``: supply usable
  reference faces and UV mappings. A zero UV Jacobian at an integration point
  rejects the mesh: that face has no usable metric and is not silently skipped.

``InvalidSpeckleForeground``, ``InvalidSpeckleBackground``, and
``SpeckleColorsMustDiffer`` identify intensity errors; use a uniform texture for
a constant field. Nonfinite shader output transforms return
``InvalidSpeckleOutputTransform``. Perlin noise controls report
``InvalidSpecklePerlinThreshold`` or
``InvalidSpecklePerlinTransitionWidth``.
Even a representable grid can exhaust memory; allocation failure is reported as
``OutOfMemory``.

The shader applies ``sample * output_scale + output_offset``, then maps the
result using the image scaling strategy (``scaling_type`` and ``bits`` in Python).
Python defaults to ``auto`` scaling with 8-bit output, while Zig defaults to
``.none`` scaling.

For complete Zig render setups and CLI options, see the
`runnable procedural tutorials <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/blob/main/dev/README.md#runnable-procedural-tutorials>`_.

API reference
-------------

.. autoclass:: riley.SpecklePattern
   :members:

.. autoclass:: riley.Speckle2DParams
   :members:

.. autoclass:: riley.Perlin2DParams
   :members:

.. autoclass:: riley.SpeckleShader
   :members:
