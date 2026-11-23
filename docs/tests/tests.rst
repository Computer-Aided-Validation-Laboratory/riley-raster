Verification and regression tests
=================================

Zig tests
---------

Run the Zig tests from the repository root. The focused verification suite
requires ``f64`` and SIMD enabled, which are the default build settings. Run
``zig build --help`` for the complete target list and configuration options.

.. list-table::
   :header-rows: 1

   * - Command
     - Purpose
   * - ``zig build test-verif``
     - Analytic verification of the solver, silhouettes, depth buffer, and camera distortion.
   * - ``zig build test-basic``
     - Basic regression suite, including the shared unit tests.
   * - ``zig build test-verif-basic -Doptimize=ReleaseSafe``
     - Combined verification and basic suites, as run in CI.
   * - ``zig build test-full -Doptimize=ReleaseSafe``
     - Full regression suite. If its reference data is missing, first run
       ``zig build gen-gold-full -Doptimize=ReleaseSafe``.

Python tests
------------

Run the packaged Python test suite with:

.. code-block:: bash

   python -m pytest --pyargs riley.pytests -s

or:

.. code-block:: bash

   python -m riley test

Python-to-Zig demo parity checks require a source checkout with repository
assets and the Zig compiler. They are skipped in a standalone package install.
