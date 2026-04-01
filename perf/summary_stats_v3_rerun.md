# V3 Summary Stats Rerun

This note summarizes `MPx/s` variability for the second archived 10-run `v3`
benchmark sweep after closing other programs:

- `perf/v3_variability_rerun/fullraster/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/geom/bench0.md` to `bench9.md`
- `perf/v3_variability_rerun/sphere2000/bench0.md` to `bench9.md`

## Overall Uncertainty Check

- cases analyzed: `196`
- median relative `MAD`: `0.290%`
- 95th percentile relative `MAD`: `1.047%`
- median max deviation from median: `1.949%`
- 95th percentile max deviation from median: `13.459%`
- worst max deviation from median: `25.589%`

Read:

- typical variability is much lower than in the first `v3` sweep
- the tail is still bad, so `2.5%` is still not a safe conservative threshold
- the instability is now concentrated in a small number of outlier cases rather than
  spread broadly across the benchmark set

## Fullraster

- cases analyzed: `84`
- median relative `MAD`: `0.259%`
- 95th percentile max deviation from median: `15.505%`

Most unstable cases:

- `quad4newton_tex8_grey_quintic_lut_lerp`: max deviation `25.589%`
- `quad8_tex8_grey_quintic_lut_lerp`: max deviation `23.293%`
- `tri6_tex8_grey_quintic_lut_lerp`: max deviation `23.034%`
- `quad9_tex8_grey_quintic_lut_lerp`: max deviation `22.374%`
- `quad4ibi_tex8_grey_quintic_lut_lerp`: max deviation `16.094%`

## Geom

- cases analyzed: `84`
- median relative `MAD`: `0.279%`
- 95th percentile max deviation from median: `13.491%`

Most unstable cases:

- `quad4newton_tex8_grey_quintic_lut_lerp`: max deviation `20.872%`
- `quad8_tex8_grey_quintic_lut_lerp`: max deviation `14.961%`
- `quad4ibi_tex8_grey_quintic_lut_lerp`: max deviation `14.854%`
- `quad9_tex8_grey_quintic_lut_lerp`: max deviation `14.098%`
- `tri3_tex8_rgb_cubic_lut_lerp`: max deviation `13.674%`
- `tri3opt_tex8_rgb_cubic_lut_lerp`: max deviation `12.454%`

## Sphere2000

- cases analyzed: `28`
- median relative `MAD`: `0.463%`
- 95th percentile max deviation from median: `12.083%`

Most unstable cases:

- `quad9_flat_grey`: max deviation `13.387%`
- `quad9_flat_rgb`: max deviation `12.961%`
- `quad9_tex8_grey`: max deviation `10.451%`
- `quad9_tex8_rgb`: max deviation `9.605%`

## Geometry Families Across The Rerun Dataset

Across the full rerun archive, the geometry families ranked by mean max deviation were:

- `quad9`: mean relative `MAD` `0.427%`, mean max deviation `8.858%`
- `quad4newton`: mean relative `MAD` `0.419%`, mean max deviation `3.708%`
- `tri3`: mean relative `MAD` `0.586%`, mean max deviation `3.588%`
- `tri6`: mean relative `MAD` `0.323%`, mean max deviation `3.200%`
- `tri3opt`: mean relative `MAD` `0.608%`, mean max deviation `3.160%`
- `quad8`: mean relative `MAD` `0.217%`, mean max deviation `3.004%`
- `quad4ibi`: mean relative `MAD` `0.190%`, mean max deviation `2.704%`

This is the key reason the split threshold recommendation now treats `quad9`
separately from the rest of the suite.

## Repeated Outlier Pattern

Comparing the first and second `v3` sweeps, the repeated outliers above `10%`
max deviation in both datasets were:

- `fullraster:quad9_flat_grey`
- `geom:quad9_flat_grey`
- `sphere2000:quad9_flat_grey`
- `fullraster:quad9_flat_rgb`
- `geom:quad9_tex8_grey_linear`
- `sphere2000:quad9_tex8_grey`

This makes `quad9` the clearest repeated source of benchmark instability.

## Takeaway

- closing background programs improved typical variability a lot
- most geometry families now look reasonably stable
- `quad9` remains the main noisy family
- a few LUT-heavy shader cases also show large outliers, but the strongest repeated
  signal is still `quad9`
