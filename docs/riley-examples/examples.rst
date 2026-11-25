Examples
========

After :doc:`installation <../install/install>`, run ``zig build --help`` from
the checkout or ``python -m riley --help`` to discover the available demos.

From the repository root, render the monochrome rabbits or a textured sphere:

.. code-block:: bash

   zig build demo2a-rabbits-mono -Doptimize=ReleaseFast
   zig build demo1a-texture-sphere -Doptimize=ReleaseFast

With the Python package installed, run the corresponding demos with:

.. code-block:: bash

   python -m riley demo2a_rabbits_mono
   python -m riley demo1a_texture_sphere

Outputs use the underscore-separated demo name under ``out/`` (Zig) or
``out_riley_py/`` (Python). The complete render setups live in the
`Zig <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src>`_
and `Python <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src/riley/pydemos>`_ sources.

Procedural speckles
-------------------

See the `procedural tutorials <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/blob/main/dev/PROCEDURAL.md#runnable-procedural-tutorials>`_
to render speckles on a plane, a deforming sphere, or a rabbit, and the
:doc:`Python speckle reference <../python-api/speckles>` for shader parameters.
