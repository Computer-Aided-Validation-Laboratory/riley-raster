Procedural speckles
===================

Attach a :class:`riley.SpeckleShader` to a mesh with one UV pair per node to
produce grayscale disk, Gaussian, or Perlin patterns. Parameters are fixed per
mesh throughout a render; resources are prepared once and reused across frames.

.. code-block:: python

   import riley

   shader = riley.SpeckleShader(
       uvs=uvs,
       params=riley.Speckle2DParams(pattern=riley.SpecklePattern.disk, seed=42),
   )

The Python/C API selects analytic evaluators automatically:
``classified-binned`` for hard disks (nine neighbors), ``cell-binned`` for
soft disks and Gaussians (nine neighbors), and ``gradient-lattice`` for Perlin.
Hard disks use exact foreground/background certificates on a fixed 8×4
microcell grid per procedural bin, with exact disk fallback for ambiguous
samples. These certificates accelerate analytic evaluation without texture
sampling or coverage quantization; they do not imply a fastest evaluator for
every workload. Evaluator and neighborhood selection is not exposed to Python.

Storage is checked for representability, without fixed memory budgets.
Representable allocations can still fail with ``OutOfMemory``; see the parameter
reference for input restrictions and native error reporting.

.. autoclass:: riley.SpecklePattern
   :members:

.. autoclass:: riley.Speckle2DParams
   :members:

.. autoclass:: riley.SpeckleShader
   :members:
