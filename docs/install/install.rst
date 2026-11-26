Installation and quick start
============================

Python
------

With Python 3.11 or newer, install ``riley-raster`` from PyPI and run the
packaged quickstart from a writable directory:

.. code-block:: shell

   python -m pip install riley-raster
   python -m riley demo00_quickstart

The demo writes to ``out_riley_py/demo00_quickstart/``. The package is imported
as ``riley``; see the :doc:`Python API <../python-api>` for the reference.

On macOS, building the Python package from source requires macOS 13 or newer
for the pinned ``ziglang`` build dependency. This does not change the target
of prebuilt Riley wheels.

Zig
---

Install `Zig 0.17.1 <https://ziglang.org/download/>`_ and clone the
`Riley repository <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster>`_.
From the repository root, run:

.. code-block:: shell

   zig build demo00-quickstart -Doptimize=ReleaseFast

The demo writes to ``out/demo00_quickstart/``.
