Procedural speckles
===================

Attach a :class:`riley.SpeckleShader` to a mesh with one UV pair per node for
monochrome disk, Gaussian, or Perlin patterns. Both ``uvs`` and ``params`` are
required.

.. code-block:: python

   import riley

   shader = riley.SpeckleShader(
       uvs=uvs,
       params=riley.Speckle2DParams(coverage=0.5, radius=0.25, seed=42),
   )

.. _speckle-calibration:

Physical calibration and coverage
---------------------------------

Disk/Gaussian ``radius`` and Perlin ``cell_size`` use reference-mesh coordinate
units: 0.25 means 0.25 mm if coordinates are in mm, not pixels or a bounding-box
fraction. Perlin requires a single positive finite ``cell_size`` and uses the
same geometry calibration as disks and Gaussians, but does not solve for
coverage. Its threshold and transition width are in noise units.

Calibration integrates referenced physical and UV face areas once per mesh,
including higher-order geometry present in the rendered reference mesh.
It uses a physical-area-weighted log-mean axis ratio, normalized so the product
of axis lengths equals physical area divided by UV area. For disks and Gaussians
this preserves nominal average footprint area ``pi * R * R``. Uniform orthogonal
planar maps preserve physical circles and square Perlin cells. Curved/distorted
maps do not promise equal local sizes, exact per-speckle areas, or geodesic
circles. At seams or poles, distinct node IDs may share a physical position;
physical edge collapse alone does not invalidate calibration if the interior
reference geometry and UV metric are usable. All parts of one ``Mesh`` share
this global calibration. Mesh conversion happens first: reducing element order
calibrates against the resulting lower-order geometry, not the discarded curved
surface. Displacement stretches the frozen reference field; frames and cameras
do not recalibrate it.

Coverage is nominal, not a finite-image guarantee or mean opacity. Jitter and
softness do not change density, but can change realized coverage and intensity.
For example, at occupancy 1, nominal coverage 0.5 with jitter ``J = 0.5R`` gives
about 0.525 hard-disk coverage in the statistical model, not exactly 0.5 for each
seed. In the dilute expected limit, the relative area factor is
``1 + J*J/(3*R*R)``, about an 8.3% increase at ``J = R/2``; overlap generally
reduces this increase. This is not a strict bound for an individual finite field.
Soft boundaries and Gaussian profiles weight intensity within their supports
rather than making every covered point opaque.

Patterns use automatic analytic evaluators, not quantized textures. A fixed seed
is repeatable within a build, not necessarily identical across f32/f64 builds;
Python uses f64.

.. _speckle-uv-domain:

UV domain and memory
--------------------

The entire interpolated UV map of every referenced face must lie in the unit
square, with a ``2e-5`` allowance at each boundary. Preparation checks this once;
the sampler clamps to the unit square. For quadratic elements, in-range nodal
UVs are not enough: preparation uses conservative subdivided Bernstein bounds
and may reject a near-boundary map it cannot certify.

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
  is individually valid;
  a request at the limit can round over it after conversion. Preparation does not
  change density or select a fallback to make it fit.
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

For the Zig shader example and runnable procedural tutorials, see the
`developer guide <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/blob/2d_procedural_speckle_generation/dev/README.md#procedural-generation>`_.

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
