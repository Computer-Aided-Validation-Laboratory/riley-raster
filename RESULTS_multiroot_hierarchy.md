# Bézier multi-root hierarchy: initial implementation results

The production implementation retains the three-seed front-facing legacy
policy as its default. Runtime alternatives are the original depth-ordered
bank, fixed four or sixteen children, and a bounded adaptive hierarchy.
The child modes can also use a front-facing child seed, a single frozen-Jacobian
predictor, or a legacy-bank fallback. Scalar and SIMD raster paths are both
implemented. Child subdivision is exact FE restriction in parent space before
projection; no raster-time subdivision or allocation is used.

## Analytic verification

The independent offline oracle subdivides each element into 64 subpatches,
finer than the fixed four and sixteen production candidates. Across the
outward cylinder, outward sphere, inward cylinder, and saddle fixtures, no
oracle-visible ray was falsely rejected by the child hulls.
The final `zig build test-verif -Doptimize=Debug` passes all 202 tests;
`zig build -Doptimize=Debug` also succeeds. The complete small-scene
scalar/SIMD benchmark matrix passes shaded-sample and Newton-call parity.

| Fixture / policy | Nearest front hits | Accuracy | Newton starts on hits |
| --- | ---: | ---: | ---: |
| Outward 3D cylinder, fixed 4, centre | 4664 / 4704 | 99.15% | 7248 |
| Outward 3D cylinder, fixed 16, centre | 4550 / 4704 | 96.73% | 7688 |
| Outward 3D cylinder, fixed 16, front-near | 4686 / 4704 | 99.62% | 7688 |
| Outward 3D cylinder, adaptive, front-near | 4688 / 4704 | 99.66% | 7614 |
| Outward 3D cylinder, fixed 4 + legacy fallback | 4704 / 4704 | 100% | 7288 |
| Outward sphere, fixed 4, centre | 4282 / 4408 | 97.14% | 6968 |
| Outward sphere, fixed 16, centre | 4260 / 4408 | 96.64% | 7652 |
| Outward sphere, fixed 16, front-near | 4388 / 4408 | 99.55% | 7652 |
| Outward sphere, adaptive, front-near | 4398 / 4408 | 99.77% | 7618 |
| Outward sphere, fixed 16 + legacy fallback | 4400 / 4408 | 99.82% | 7816 |
| Quadratic saddle, fixed 4, centre | 1298 / 1484 | 87.47% | 2792 |
| Quadratic saddle, fixed 16, centre | 1328 / 1484 | 89.49% | 3240 |
| Quadratic saddle, adaptive, centre | 1422 / 1484 | 95.82% | 3436 |

The hierarchy's main gain is rejecting true misses inside the loose
whole-element hull. The 64-subpatch oracle confirmed 3992 such cylinder misses
and 5352 sphere misses. Fixed four children rejected 3238 (81.11%) and 4272
(79.82%) before Newton; fixed sixteen rejected 3868 (96.89%) and 5064
(94.62%). The legacy three-seed policy would start Newton three times for
each of these misses; fixed sixteen required only 128 and 346 starts,
respectively. These are oracle diagnostic counts, not full-frame timings.
The cost shifts toward child AABB checks: fixed four uses four per broad-phase
survivor, fixed sixteen uses sixteen. In the outward cylinder/sphere fixtures,
roughly 1.6–1.7 child hull polygon tests per survivor remain after the AABB
filter in the fixed-sixteen mode (14,988/8,696 and 15,400/9,760). The
candidate-count distributions are written to the verification log and the
runner's accuracy CSV.

The remaining visible-ray misses are Newton basin failures, **not** false hull
rejections. In particular, neither fixed subdivision with its current single
child seed nor the legacy fallback reaches 100% on the outward sphere cases.
On the quadratic saddle, fixed four finds 1318 front roots but only 1298
nearest roots (20 wrong-nearest outcomes); fixed sixteen has 1332 front and
1328 nearest (four wrong-nearest outcomes). Adaptive centre seeds find 1422
front roots, all nearest. The constructed three-root quad8 fixture gives
36/72 nearest roots for fixed four and 60/72 for fixed sixteen; fixed sixteen
plus the frozen predictor reaches 72/72, at appreciably greater solve cost.
One frozen-Jacobian step adds work and gives little outward-geometry accuracy
benefit. It is therefore experimental, not the default.

## Render regression status

The debug verification portion passes with no gold mismatch. The basic gold
suite reports 249 image comparisons differing, concentrated in `twoshapes`
and `featurezoo`; explicitly restoring the original depth-ordered policy in
the gold test configuration does **not** remove them. A cached test binary
built before this hierarchy work also reports exactly 249 basic gold
differences when run in an isolated directory. Thus the basic mismatches
predate this implementation. Gold was not regenerated.
The shallow-bank quad8 counterexample remains in verification as a diagnostic,
not as an unconditional hard failure.
The full debug suite runs through every case and reports 4,350 gold-image
differences, with zero non-gold suite failures. Most are in `full_shader` and
`full_texture`; there are also differences in `full_scene_camera_threads` and
`full_hull`. The generated images and diffs remain under `fails/` for review.
No ReleaseSafe full-suite run was attempted because the debug run already
produced extensive unapproved gold differences and free disk space was about
2.5 GB after this run.

## Initial ReleaseSafe render benchmark

This is a 48-element mixed tri6/quad4/quad8/quad9 stress scene, 256×256 pixels,
one raster thread, one warmup and three measured runs. Times are medians in
milliseconds. All scalar/SIMD pairs gave exactly matching shaded-sample and
Newton-call counts. This is a scene-level comparison, not an accuracy oracle;
the analytic figures above provide the correctness context.

| Policy | Shaded samples | Newton calls | Newton iterations | Scalar E2E | SIMD E2E | SIMD raster |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Legacy front-three (default) | 11,968 | 93,090 | 697,073 | 13.04 | 5.59 | 5.13 |
| Legacy depth-three | 9,825 | 93,162 | 671,210 | 13.07 | 5.36 | 4.96 |
| Fixed four, centre | 11,563 | 28,820 | 170,502 | 5.38 | 3.44 | 2.92 |
| Fixed sixteen, centre | 11,776 | 25,095 | 123,706 | 5.65 | 4.28 | 3.48 |
| Adaptive, centre | 11,875 | 24,791 | 112,059 | 7.69 | 6.77 | 5.33 |
| Fixed four + legacy fallback | 11,980 | 62,186 | 411,612 | 9.54 | 4.93 | 4.41 |
| Fixed sixteen + legacy fallback | 11,980 | 50,352 | 297,381 | 8.67 | 5.43 | 4.59 |
| Adaptive + legacy fallback | 11,980 | 49,061 | 277,986 | 10.61 | 7.89 | 6.41 |

The fixed-four pure path is the fastest here but is not accurate enough to
replace the default. Fixed-four plus fallback is faster than legacy front-three
in this scene while recovering its missed samples. Adaptive reduces Newton
starts further but its preparation and child-search overhead dominate at this
scale. These timings precede a final fixed-mode preprocessing cleanup (avoiding
an unnecessary internal-leaf hull build), so fixed-mode geometry-preparation
time is a conservative upper bound; raster timings are unaffected. The scalar
binary was also built before an extra fixed-mode leaf-count pass was removed,
whereas the SIMD binary includes that first cleanup. Compare methods within a
backend or compare raster times across backends; do not read the scalar/SIMD
end-to-end difference as a final backend speedup. Raw and summary CSVs are in
`out/bench_stats_multiroot_release_quick/`.

## Reproduce

`python3 scripts/bench_multiroot.py` builds scalar and SIMD ReleaseSafe
executables, runs repeated full renders, writes raw and summary timing CSVs,
and runs the independent verification oracle to write accuracy CSV. Use
`--quick` for the main eight method configurations and `--skip-verif` to avoid
rerunning analytic verification.
