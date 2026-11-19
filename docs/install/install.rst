Installing riley-raster
==========================

Quick Start: Zig
==========================

Riley uses Zig 0.16.0. Clone the repository, then build and run the smallest demo:

      .. code-block:: bash

          zig build demo0-quickstart -Doptimize=ReleaseFast

Renders are written to out/. Run the combined test suite with:

      .. code-block:: bash

          zig build test-verif-basic

`Zig API documentation <zig-api/index.html>`_

Quick Start: Python
==========================

Install the published package:

      .. code-block:: bash

          python -m pip install riley-raster
          python -m riley demo0_quickstart

Python renders are written below out_riley_py/. 
For development from a checkout, install it in editable mode:

      .. code-block:: bash
         
          python -m pip install -e .