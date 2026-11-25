Verification and regression tests
=================================

Zig
---

Run the Zig suites from the repository root. The verification suite requires
``f64`` precision and SIMD enabled, the default build settings. The
verification and basic regression references ship with the repository.

.. list-table::
   :header-rows: 1

   * - Command
     - Purpose
   * - ``zig build test-verif-basic``
     - Run verification and basic regression in one build.
   * - ``zig build test-verif``
     - Verify the solver, silhouettes, depth buffer, and camera distortion
       against analytic references.
   * - ``zig build test-basic``
     - Run the basic regression suite and shared unit tests.
   * - ``zig build test-full -Doptimize=ReleaseSafe``
     - Run the full regression suite. Its larger reference dataset must be
       prepared separately if missing; see the `Full suite reference setup
       <https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/blob/main/dev/TESTING.md#6-full-test-suite-test_full>`_.

Python
------

Run the packaged tests with ``python -m riley test``. This forwards extra
arguments to pytest; for example, ``python -m riley test -k speckle`` filters
by test name. To invoke pytest directly, use:

.. code-block:: shell

   python -m pytest --pyargs riley.pytests -s

Python-to-Zig demo comparisons require a source checkout with the repository
assets and the Zig compiler. Those comparisons skip when the prerequisites
are unavailable; the rest of the packaged suite still runs.
