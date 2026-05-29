# `std.Thread` Outer Parallelism Performs Better Than Outer `io`

This note compares the DIC UQ threading benchmark results from:

- old outer scheduling with `std.Thread`:
  `out/bench_stats_dicuq/20260521_152348/experiment_5_offline_sweet_spot`
- new outer scheduling with outer `io.async` / `await`:
  `out/bench_stats_dicuq/20260523_221924/experiment_5_offline_sweet_spot`

The new run is incomplete, so the comparison only uses like-for-like cases
present in both datasets.

## Scope

- Benchmark: `bench_dicuq`
- Experiment: `experiment_5_offline_sweet_spot`
- Compared save modes:
  - `disk`
  - `memory`
- Old `memory_direct_write` was normalized to new `memory`
- Only matched cases were compared

Matched cases:

- `29` `disk`
- `29` `memory`
- `58` total

## Main Result

The new outer `io` scheduling is only modestly worse for single render-group
cases, but it is substantially worse for multiple render-group cases.

Median new/old throughput ratio across matched cases:

| Save Mode | Case Type     | E2E TP Ratio | Raster TP Ratio |
|-----------|---------------|--------------|-----------------|
| disk      | single-group  | 0.864        | 0.892           |
| memory    | single-group  | 0.924        | 0.890           |
| disk      | multi-group   | 0.671        | 0.688           |
| memory    | multi-group   | 0.709        | 0.681           |

Interpretation:

- single-group regression is modest
- multi-group regression is large
- the regression appears in raster throughput too, not just end-to-end
  throughput

## Key Behaviour Change

In the old `std.Thread` dataset, splitting work across more render groups was
often beneficial.

In the new outer `io` dataset, splitting work across more render groups is
usually harmful.

### Best Multi-Group vs Best Single-Group Within Each Dataset

Old `std.Thread` dataset:

- `disk`, `4` threads: `1.23x`
- `disk`, `8` threads: `1.46x`
- `disk`, `16` threads: `2.03x`
- `disk`, `32` threads: `3.28x`
- `disk`, `64` threads: `4.02x`
- `memory`, `4` threads: `1.03x`
- `memory`, `8` threads: `1.03x`
- `memory`, `16` threads: `1.09x`
- `memory`, `32` threads: `1.18x`
- `memory`, `64` threads: `1.19x`

New outer `io` dataset:

- `disk`, `2` threads: `0.55x`
- `disk`, `4` threads: `0.89x`
- `memory`, `2` threads: `0.51x`
- `memory`, `4` threads: `0.76x`

Interpretation:

- old outer `std.Thread`: multiple render groups helped
- new outer `io`: multiple render groups hurt

## Representative Cases

### `4` Threads, `disk`

Old dataset:

- best `1x4`: `19.85 MPx/s`
- best multi-group: `24.47 MPx/s` at `4x1`

New dataset:

- best `1x4`: `17.14 MPx/s`
- best multi-group: `15.29 MPx/s` at `2x2`
- `4x1`: only `5.54 MPx/s`

### `4` Threads, `memory`

Old dataset:

- best `1x4`: `23.63 MPx/s`
- best multi-group: `24.33 MPx/s` at `4x1`

New dataset:

- best `1x4`: `22.56 MPx/s`
- best multi-group: `17.21 MPx/s` at `2x2`
- `4x1`: only `6.07 MPx/s`

### `2` Threads

Old dataset:

- `2x1` slightly better than `1x2`

New dataset:

- `2x1` about half the throughput of `1x2`

This is true for both `disk` and `memory`.

## Detailed Multi-Group Matched Cases

### `disk`

- `2` threads, `2x1`, batch `1`, geomjobs `1`:
  old E2E `12.54`, new E2E `5.65`, ratio `0.45`
- `2` threads, `2x1`, batch `2`, geomjobs `1`:
  old E2E `12.53`, new E2E `5.67`, ratio `0.45`
- `4` threads, `2x2`, batch `1`, geomjobs `1`:
  old E2E `22.50`, new E2E `15.23`, ratio `0.68`
- `4` threads, `2x2`, batch `1`, geomjobs `2`:
  old E2E `22.41`, new E2E `15.28`, ratio `0.68`
- `4` threads, `2x2`, batch `2`, geomjobs `1`:
  old E2E `22.41`, new E2E `15.02`, ratio `0.67`
- `4` threads, `2x2`, batch `2`, geomjobs `2`:
  old E2E `22.39`, new E2E `15.02`, ratio `0.67`
- `4` threads, `2x2`, batch `4`, geomjobs `1`:
  old E2E `21.07`, new E2E `15.20`, ratio `0.72`
- `4` threads, `2x2`, batch `4`, geomjobs `2`:
  old E2E `22.48`, new E2E `15.29`, ratio `0.68`
- `4` threads, `4x1`, batch `1`, geomjobs `1`:
  old E2E `24.47`, new E2E `5.54`, ratio `0.23`
- `4` threads, `4x1`, batch `2`, geomjobs `1`:
  old E2E `24.37`, new E2E `5.54`, ratio `0.23`

### `memory`

- `2` threads, `2x1`, batch `1`, geomjobs `1`:
  old E2E `13.02`, new E2E `6.06`, ratio `0.47`
- `2` threads, `2x1`, batch `2`, geomjobs `1`:
  old E2E `12.98`, new E2E `6.07`, ratio `0.47`
- `4` threads, `2x2`, batch `1`, geomjobs `1`:
  old E2E `23.86`, new E2E `17.08`, ratio `0.72`
- `4` threads, `2x2`, batch `1`, geomjobs `2`:
  old E2E `23.86`, new E2E `17.04`, ratio `0.71`
- `4` threads, `2x2`, batch `2`, geomjobs `1`:
  old E2E `23.52`, new E2E `16.96`, ratio `0.72`
- `4` threads, `2x2`, batch `2`, geomjobs `2`:
  old E2E `24.07`, new E2E `17.21`, ratio `0.71`
- `4` threads, `2x2`, batch `4`, geomjobs `1`:
  old E2E `23.79`, new E2E `16.96`, ratio `0.71`
- `4` threads, `2x2`, batch `4`, geomjobs `2`:
  old E2E `24.09`, new E2E `16.99`, ratio `0.71`
- `4` threads, `4x1`, batch `1`, geomjobs `1`:
  old E2E `24.29`, new E2E `6.07`, ratio `0.25`
- `4` threads, `4x1`, batch `2`, geomjobs `1`:
  old E2E `24.33`, new E2E `6.04`, ratio `0.25`

## Setup vs Dispatch

Representative `stdout.txt` comparisons show that the regression is not in
setup time. It is overwhelmingly in dispatch/runtime.

### `disk`, `4` threads, `4x1`

- old: total `27073.312 ms`, setup `0.275 ms`, dispatch `27073.037 ms`
- new: total `116757.749 ms`, setup `0.307 ms`, dispatch `116757.441 ms`

### `disk`, `4` threads, `2x2`

- old: total `28787.056 ms`, setup `0.322 ms`, dispatch `28786.734 ms`
- new: total `42447.897 ms`, setup `0.317 ms`, dispatch `42447.580 ms`

### `memory`, `4` threads, `4x1`

- old: total `26478.979 ms`, setup `1886.217 ms`, dispatch `24592.763 ms`
- new: total `106770.236 ms`, setup `0.347 ms`, dispatch `106769.889 ms`

### `memory`, `4` threads, `2x2`

- old: total `26963.128 ms`, setup `1894.810 ms`, dispatch `25068.318 ms`
- new: total `37799.078 ms`, setup `0.349 ms`, dispatch `37798.729 ms`

### `memory`, `4` threads, `1x4`

- old: total `27385.464 ms`, setup `1894.137 ms`, dispatch `25491.328 ms`
- new: total `28751.052 ms`, setup `0.351 ms`, dispatch `28750.700 ms`

Interpretation:

- the new outer `io` path is not losing because of setup
- the large losses are in dispatch/runtime
- the worst regressions are specifically the multi-render-group cases

## Conclusion

For the DIC UQ threading benchmark, the old outer `std.Thread` scheduling is
clearly better than the new outer `io` scheduling.

The evidence indicates:

- single render-group cases are only modestly worse with outer `io`
- multiple render-group cases are substantially worse with outer `io`
- the regression affects both `disk` and `memory`
- the regression appears in raster throughput as well as E2E throughput
- the regression is a dispatch/runtime problem, not a setup problem

For this workload, if the goal is strong multiple render-group parallelism,
the old `std.Thread` outer scheduling performs better.
