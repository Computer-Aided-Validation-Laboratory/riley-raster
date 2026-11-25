Examples
========

After :doc:`installation <../install/install>`, choose a demo below. Run
Zig commands from the repository root. Python demos run with the installed
package from a writable directory. Renders go under ``out/`` for Zig and
``out_riley_py/`` for Python.

.. list-table::
   :header-rows: 1

   * - Demo
     - Zig
     - Python
   * - Deforming textured sphere
     - ``zig build demo01-sphere -Doptimize=ReleaseFast``
     - ``python -m riley demo01_sphere``
   * - Monochrome rabbits with mixed element and shader types
     - ``zig build demo02a-rabbits-mono -Doptimize=ReleaseFast``
     - ``python -m riley demo02a_rabbits_mono``
   * - Stereo DIC UQ on a plate with a hole
     - ``zig build demo03-dicuq -Doptimize=ReleaseFast``
     - ``python -m riley demo03_dicuq``
   * - Stereo calibration target
     - ``zig build demo04-stereocal -Doptimize=ReleaseFast``
     - ``python -m riley demo04_stereocal``
   * - Camera models, distortion and point spread functions
     - ``zig build demo05-cameramodels -Doptimize=ReleaseFast``
     - ``python -m riley demo05_cameramodels``
   * - Feature zoo: multiple meshes, cameras and image formats
     - ``zig build demo06-featurezoo -Doptimize=ReleaseFast``
     - ``python -m riley demo06_featurezoo``
   * - Shader-pipe quickstart
     - ``zig build demo07-shaderpipe-quickstart -Doptimize=ReleaseFast``
     - ``python -m riley demo07_shaderpipe_quickstart``

For texture-free patterns on a plane, deforming sphere, or rabbit, see
:doc:`../procedural`. Use ``zig build --help`` or ``python -m riley`` to list
available targets or demo names, respectively.

Browse the `Zig <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src>`_
and `Python <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src/riley/pydemos>`_
demo sources for complete render setups.
