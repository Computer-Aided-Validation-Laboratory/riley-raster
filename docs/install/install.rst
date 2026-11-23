Installing riley-raster
=======================

Quick start: Zig
----------------

Riley uses `Zig 0.16.0 <https://ziglang.org/download/>`_. Clone the
`repository <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster>`_,
then build and run the smallest demo from the repository root:

.. code-block:: bash

   zig build demo0-quickstart -Doptimize=ReleaseFast

Renders are written to ``out/``. See :doc:`../tests/tests` for test commands.

Quick start: Python
-------------------

With Python 3.11 or newer, install the published package and run the demo:

.. code-block:: bash

   python -m pip install riley-raster
   python -m riley demo0_quickstart

Python renders are written below ``out_riley_py/``.
For development from a checkout, install it in editable mode from the repository
root:

.. code-block:: bash

   python -m pip install -e .
