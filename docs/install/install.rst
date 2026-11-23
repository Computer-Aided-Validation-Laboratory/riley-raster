Installing riley-raster
=======================

Quick start: Zig
----------------

Riley uses `Zig 0.16.0 <https://ziglang.org/download/>`_. Clone the
`repository <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster>`_,
then build and run the smallest demo from the repository root:

.. code-block:: bash

   zig build demo0a-quickstart -Doptimize=ReleaseFast

Renders are written to ``out/demo0a_quickstart/``.

Quick start: Python
-------------------

With Python 3.11 or newer, install the published package and run the demo:

.. code-block:: bash

   python -m pip install riley-raster
   python -m riley demo0a_quickstart

Python renders are written to ``out_riley_py/demo0a_quickstart/``.
For development from a checkout, run ``python -m pip install -e .`` from the
repository root.

See :doc:`../riley-examples/examples` for more demos or :doc:`../tests/tests`
for test commands.
