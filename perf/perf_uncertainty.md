# Performance Benchmark Uncertainty

This note tracks the observed run-to-run uncertainty of our benchmark suite and
gives working significance thresholds for `MPx/s` comparisons.

## Working Rule

For quick benchmark interpretation:

- treat differences within `+/-2%` as potentially explained by normal run-to-run
  variation
- do not claim a meaningful performance win or loss from a single run unless the
  change is clearly outside that band

This `+/-2%` rule is a practical screening threshold, not a statistical bound.

## Fullraster Variability Study

Configuration:

- benchmark: `zig run -O ReleaseFast ./src-simd2/bench_fullraster.zig`
- implementation: `src-simd2`
- runs: `10`
- execution mode: sequential, one benchmark process at a time
- archived outputs:
  - `perf/fullraster_variability_src-simd2/bench0.md`
  - `perf/fullraster_variability_src-simd2/bench1.md`
  - `perf/fullraster_variability_src-simd2/bench2.md`
  - `perf/fullraster_variability_src-simd2/bench3.md`
  - `perf/fullraster_variability_src-simd2/bench4.md`
  - `perf/fullraster_variability_src-simd2/bench5.md`
  - `perf/fullraster_variability_src-simd2/bench6.md`
  - `perf/fullraster_variability_src-simd2/bench7.md`
  - `perf/fullraster_variability_src-simd2/bench8.md`
  - `perf/fullraster_variability_src-simd2/bench9.md`

Method:

- metric used: `MPx/s`
- cases analyzed: `84`
- per case, compute:
  - minimum `MPx/s`
  - maximum `MPx/s`
  - median `MPx/s`
  - median absolute deviation (`MAD`)
- normalize `MAD`, min/max range, and max deviation from median into percent of
  median `MPx/s`

Aggregate results across all `84` cases:

- median relative `MAD`: `0.227%`
- 90th percentile relative `MAD`: `0.383%`
- 95th percentile relative `MAD`: `0.480%`
- worst relative `MAD`: `1.123%`

- median min/max range: `1.189%`
- 90th percentile min/max range: `2.937%`
- 95th percentile min/max range: `3.203%`
- worst min/max range: `5.669%`

- median max deviation from median: `0.761%`
- 90th percentile max deviation from median: `2.134%`
- 95th percentile max deviation from median: `2.543%`
- worst max deviation from median: `3.721%`

Highest-variability cases by relative `MAD`:

- `tri3opt_flat_rgb`: min `29.74`, median `30.27`, max `30.86`, `MAD 1.12%`
- `tri3_flat_rgb`: min `29.81`, median `30.37`, max `31.50`, `MAD 1.04%`
- `quad4newton_tex8_rgb_cubic_lut_lerp`: `MAD 0.61%`
- `quad4newton_flat_rgb`: `MAD 0.54%`

## Suggested Significance Thresholds

For `MPx/s` comparisons:

- reasonable threshold: `1%`
  - use this for day-to-day optimization work
  - changes at or above this level are probably real on this machine

- conservative threshold: `2.5%`
  - use this when deciding whether to accept or reject an optimization from a
    small number of runs
  - this is aligned with the observed 95th percentile worst-case deviation from
    median in the 10-run study

Recommended interpretation:

- `< 1%`: treat as noise
- `1%` to `2.5%`: likely real, but worth confirming with repeat runs if the
  decision matters
- `>= 2.5%`: strong evidence of a meaningful performance change

## Updated V3 Thresholds

After the `v3` 10-run variability studies in:

- `perf/v3_variability/`
- `perf/v3_variability_rerun/`

the old single conservative threshold of `2.5%` is no longer appropriate for all
cases.

What the two datasets showed:

- the first `v3` sweep had high overall spread
- the rerun sweep, after closing programs, had much lower typical variability
- however, a small number of outlier cases still showed large max deviations
- the repeated outliers cluster mainly around `quad9`

Recommended thresholds, rounded up to the nearest whole percent:

- all cases
  - reasonable: `3%`
  - conservative: `14%`

- non-`quad9` cases
  - reasonable: `2%`
  - conservative: `8%`

- `quad9` cases
  - reasonable: `5%`
  - conservative: `15%`

Recommended working rule:

- use the split rule above when looking at detailed per-case benchmark changes
- if only one repo-wide threshold is practical, use:
  - reasonable: `3%`
  - conservative: `14%`

Interpretation:

- most non-`quad9` cases are substantially more stable than the worst-case tail
- `quad9` should be treated as a special noisy family until the source of its
  variability is better understood

## Geometry Throughput Thresholds (`MElem/s`)

For geometry-pipeline work we should use a separate uncertainty model from the
raster-loop `MPx/s` thresholds above.

Source dataset:

- `perf/v3_variability_rerun/geom/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/sphere2000/bench0.md` to `bench9.md`

Method:

- metric used: `MElem/s`
- suites analyzed: `geom`, `sphere2000`
- cases analyzed: `112`
- per case, compute:
  - median `MElem/s`
  - relative median absolute deviation (`MAD`)
  - max deviation from median as a percent of median

Aggregate results:

- median relative `MAD`: `1.822%`
- 95th percentile relative `MAD`: `4.422%`
- median max deviation from median: `5.542%`
- 90th percentile max deviation from median: `10.209%`
- 95th percentile max deviation from median: `10.477%`
- worst max deviation from median: `14.831%`

Most unstable `MElem/s` cases in this rerun archive:

- `sphere2000:tri6_flat_grey`: max deviation `14.831%`
- `geom:quad4newton_flat_grey`: max deviation `12.408%`
- `sphere2000:tri6_tex8_grey`: max deviation `11.952%`
- `geom:quad4newton_tex8_grey_linear`: max deviation `10.917%`
- `geom:tri3opt_tex8_grey_linear`: max deviation `10.590%`

Recommended thresholds for `MElem/s` comparisons:

- reasonable threshold: `5%`
- conservative threshold: `11%`

Recommended interpretation:

- `< 5%`: treat as likely noise or too small to rely on from a single run
- `5%` to `11%`: likely real, but worth confirming if the decision matters
- `>= 11%`: strong evidence of a meaningful geometry-throughput change

Working note:

- unlike the earlier `MPx/s` studies, `quad9` is not the dominant `MElem/s`
  outlier in this rerun archive
- for now, use one geometry-throughput threshold set for all kernels rather than
  splitting out a separate `quad9` rule
