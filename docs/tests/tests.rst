Verification and regression tests
==========

The Zig test suites are intentionally separated by purpose. The focused 
verification suite requires the production f64 and SIMD configuration; run zig build --help 
for the complete target list and configuration options.

============================================ ========================================================================================
Command                                       Purpose
============================================ ========================================================================================
zig build test-verif-basic                    Fast combination of focused analytic verification and basic regression tests.
zig build test-verif                          Analytic verification of the solver, silhouettes, depth buffer, and camera distortion.
zig build test-basic                          Basic regression suite.
zig build test-full -Doptimize=ReleaseSafe    Full regression suite.
============================================ ========================================================================================

Run the packaged Python test suite with:

      .. code-block:: bash

          python -m pytest --pyargs riley.pytests -s

or:

      .. code-block:: bash

          python -m riley test
