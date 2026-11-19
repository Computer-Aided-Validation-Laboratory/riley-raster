.. image:: ./_static/riley_logo.png
   :alt: Riley Logo
   :align: center
   :width: 600px

riley-raster documentation
==========================

.. |pypi| image:: https://img.shields.io/pypi/v/riley-raster
   :target: https://pypi.org/project/riley-raster/
   :alt: PyPI version

.. |github| image:: https://img.shields.io/badge/github-repo-blue?logo=github
   :target: https://github.com/Computer-Aided-Validation-Laboratory/riley-raster
   :alt: GitHub repository

.. |issues| image:: https://img.shields.io/github/issues/Computer-Aided-Validation-Laboratory/riley-raster
   :target: https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/issues
   :alt: Open GitHub issues

.. |PR| image:: https://img.shields.io/github/issues-pr/Computer-Aided-Validation-Laboratory/riley-raster
   :target: https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/issues
   :alt: Open GitHub Pull Requests

.. |license| image:: https://img.shields.io/github/license/Computer-Aided-Validation-Laboratory/riley-raster
   :target: https://choosealicense.com/licenses/mit/
   :alt: MIT License

|pypi| |github| |issues| |PR| |license|

Riley is a high performance Zig software rasteriser for digital image correlation
uncertainty quantification (DIC UQ). It synthesises deformed speckle images from 
finite element simulations, with higher order surface elements 
(tri3, tri6, quad4, quad8, and quad9), camera models and distortion, 
texture/nodal/analytic shaders, and mixed scenes.

Riley's Zig core uses comptime specialisation and SIMD with @Vector to keep its 
rendering path fast and direct. It also uses hierarchical offline parallelisation 
allowing scaling over cameras and timesteps to be rendered. Riley is available as 
a Zig library and executable, a C compatible ABI, and the riley-raster Python package 
which provides python bindings to the compiled Zig library. 


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

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   install/install
   riley-examples/examples
   python-api
   tests/tests

