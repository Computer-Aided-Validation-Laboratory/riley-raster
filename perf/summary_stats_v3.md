# V3 Summary Stats

This note summarizes `MPx/s` variability for the archived 10-run `v3` benchmark sweep:

- `perf/v3_variability/fullraster/bench0.md` to `bench9.md`
- `perf/v3_variability/geom/bench0.md` to `bench9.md`
- `perf/v3_variability/sphere2000/bench0.md` to `bench9.md`

Per case, the statistics below use minimum, maximum, median, and `MAD` of `MPx/s`.

## Overall Uncertainty Check

- cases analyzed: `196`
- median relative `MAD`: `1.467%`
- 90th percentile relative `MAD`: `3.199%`
- 95th percentile relative `MAD`: `3.741%`
- worst relative `MAD`: `5.920%`
- median min/max range: `10.104%`
- 90th percentile min/max range: `17.740%`
- 95th percentile min/max range: `19.938%`
- worst min/max range: `31.132%`
- median max deviation from median: `6.002%`
- 90th percentile max deviation from median: `10.627%`
- 95th percentile max deviation from median: `13.276%`
- worst max deviation from median: `18.357%`

Conservative threshold check: `2.5%` no longer covers the 95th percentile max deviation (`13.276%`).

## Fullraster

- cases analyzed: `84`
- median relative `MAD`: `0.710%`
- 95th percentile relative `MAD`: `2.603%`
- 95th percentile max deviation from median: `15.227%`
- worst max deviation from median: `18.357%`

Geometry families:
- `quad4ibi`: mean median `MPx/s` `8.32`, mean relative `MAD` `0.308%`, mean max deviation `6.059%`
- `quad4newton`: mean median `MPx/s` `8.94`, mean relative `MAD` `0.487%`, mean max deviation `6.035%`
- `quad8`: mean median `MPx/s` `7.51`, mean relative `MAD` `0.757%`, mean max deviation `6.412%`
- `quad9`: mean median `MPx/s` `6.96`, mean relative `MAD` `2.000%`, mean max deviation `7.687%`
- `tri3`: mean median `MPx/s` `19.64`, mean relative `MAD` `1.443%`, mean max deviation `8.001%`
- `tri3opt`: mean median `MPx/s` `19.65`, mean relative `MAD` `1.323%`, mean max deviation `7.334%`
- `tri6`: mean median `MPx/s` `7.48`, mean relative `MAD` `0.574%`, mean max deviation `6.665%`

Shader families:
- `flat_grey`: mean median `MPx/s` `38.62`, mean relative `MAD` `1.006%`, mean max deviation `6.833%`
- `flat_rgb`: mean median `MPx/s` `22.70`, mean relative `MAD` `1.816%`, mean max deviation `7.865%`
- `tex8_grey_linear`: mean median `MPx/s` `14.88`, mean relative `MAD` `0.685%`, mean max deviation `5.904%`
- `tex8_rgb_linear`: mean median `MPx/s` `11.08`, mean relative `MAD` `1.205%`, mean max deviation `7.016%`
- `tex8_grey_cubic_lut_lerp`: mean median `MPx/s` `8.18`, mean relative `MAD` `1.352%`, mean max deviation `6.507%`
- `tex8_grey_cubic`: mean median `MPx/s` `7.65`, mean relative `MAD` `0.734%`, mean max deviation `5.306%`
- `tex8_grey_quintic_lut_lerp`: mean median `MPx/s` `6.32`, mean relative `MAD` `0.779%`, mean max deviation `5.601%`
- `tex8_rgb_cubic_lut_lerp`: mean median `MPx/s` `6.19`, mean relative `MAD` `1.147%`, mean max deviation `16.211%`
- `tex8_rgb_cubic`: mean median `MPx/s` `5.92`, mean relative `MAD` `0.931%`, mean max deviation `5.791%`
- `tex8_grey_quintic`: mean median `MPx/s` `4.81`, mean relative `MAD` `0.660%`, mean max deviation `5.502%`
- `tex8_rgb_quintic_lut_lerp`: mean median `MPx/s` `4.62`, mean relative `MAD` `0.719%`, mean max deviation `5.720%`
- `tex8_rgb_quintic`: mean median `MPx/s` `3.61`, mean relative `MAD` `0.780%`, mean max deviation `4.362%`

Highest-variability cases:
- `tri3_tex8_rgb_cubic_lut_lerp`: min `6.36`, median `7.79`, max `8.34`, `MAD 1.861%`, max deviation `18.357%`
- `quad4ibi_tex8_rgb_cubic_lut_lerp`: min `4.41`, median `5.38`, max `5.72`, `MAD 0.464%`, max deviation `18.106%`
- `quad8_tex8_rgb_cubic_lut_lerp`: min `4.55`, median `5.54`, max `5.90`, `MAD 1.354%`, max deviation `17.870%`
- `quad4newton_tex8_rgb_cubic_lut_lerp`: min `5.10`, median `6.12`, max `6.50`, `MAD 0.491%`, max deviation `16.599%`
- `tri3opt_tex8_rgb_cubic_lut_lerp`: min `6.58`, median `7.77`, max `8.32`, `MAD 1.030%`, max deviation `15.315%`
- `tri6_tex8_rgb_cubic_lut_lerp`: min `4.69`, median `5.50`, max `5.85`, `MAD 1.000%`, max deviation `14.727%`
- `tri3opt_flat_rgb`: min `40.35`, median `45.41`, max `51.41`, `MAD 3.160%`, max deviation `13.213%`
- `quad9_tex8_rgb_cubic_lut_lerp`: min `4.55`, median `5.20`, max `5.31`, `MAD 1.827%`, max deviation `12.500%`

## Geom

- cases analyzed: `84`
- median relative `MAD`: `2.291%`
- 95th percentile relative `MAD`: `4.387%`
- 95th percentile max deviation from median: `12.078%`
- worst max deviation from median: `16.004%`

Geometry families:
- `quad4ibi`: mean median `MPx/s` `6.69`, mean relative `MAD` `2.396%`, mean max deviation `4.498%`
- `quad4newton`: mean median `MPx/s` `5.50`, mean relative `MAD` `2.617%`, mean max deviation `8.123%`
- `quad8`: mean median `MPx/s` `3.77`, mean relative `MAD` `1.957%`, mean max deviation `6.221%`
- `quad9`: mean median `MPx/s` `3.65`, mean relative `MAD` `3.737%`, mean max deviation `9.353%`
- `tri3`: mean median `MPx/s` `9.66`, mean relative `MAD` `1.835%`, mean max deviation `8.619%`
- `tri3opt`: mean median `MPx/s` `9.65`, mean relative `MAD` `2.019%`, mean max deviation `6.539%`
- `tri6`: mean median `MPx/s` `3.16`, mean relative `MAD` `2.493%`, mean max deviation `6.420%`

Shader families:
- `flat_grey`: mean median `MPx/s` `13.93`, mean relative `MAD` `2.966%`, mean max deviation `8.561%`
- `flat_rgb`: mean median `MPx/s` `10.83`, mean relative `MAD` `2.802%`, mean max deviation `7.547%`
- `tex8_grey_linear`: mean median `MPx/s` `7.80`, mean relative `MAD` `2.615%`, mean max deviation `8.592%`
- `tex8_rgb_linear`: mean median `MPx/s` `6.47`, mean relative `MAD` `2.201%`, mean max deviation `8.412%`
- `tex8_grey_cubic_lut_lerp`: mean median `MPx/s` `5.28`, mean relative `MAD` `2.371%`, mean max deviation `7.322%`
- `tex8_grey_cubic`: mean median `MPx/s` `5.02`, mean relative `MAD` `2.263%`, mean max deviation `6.925%`
- `tex8_grey_quintic_lut_lerp`: mean median `MPx/s` `4.44`, mean relative `MAD` `2.515%`, mean max deviation `6.693%`
- `tex8_rgb_cubic_lut_lerp`: mean median `MPx/s` `4.27`, mean relative `MAD` `2.518%`, mean max deviation `7.228%`
- `tex8_rgb_cubic`: mean median `MPx/s` `4.17`, mean relative `MAD` `2.253%`, mean max deviation `6.837%`
- `tex8_grey_quintic`: mean median `MPx/s` `3.65`, mean relative `MAD` `2.259%`, mean max deviation `6.366%`
- `tex8_rgb_quintic_lut_lerp`: mean median `MPx/s` `3.42`, mean relative `MAD` `2.349%`, mean max deviation `5.099%`
- `tex8_rgb_quintic`: mean median `MPx/s` `2.86`, mean relative `MAD` `2.124%`, mean max deviation `5.743%`

Highest-variability cases:
- `quad9_flat_grey`: min `4.54`, median `5.41`, max `5.75`, `MAD 5.920%`, max deviation `16.004%`
- `tri3_tex8_rgb_linear`: min `7.53`, median `8.88`, max `9.00`, `MAD 1.239%`, max deviation `15.203%`
- `quad4newton_tex8_grey_linear`: min `7.13`, median `8.31`, max `8.47`, `MAD 1.925%`, max deviation `14.200%`
- `quad8_tex8_rgb_cubic_lut_lerp`: min `2.86`, median `3.30`, max `3.37`, `MAD 1.815%`, max deviation `13.464%`
- `quad4newton_flat_rgb`: min `6.80`, median `7.73`, max `8.00`, `MAD 2.973%`, max deviation `12.088%`
- `tri3_flat_grey`: min `26.13`, median `29.70`, max `31.02`, `MAD 3.906%`, max deviation `12.020%`
- `tri3_tex8_grey_cubic_lut_lerp`: min `6.86`, median `7.70`, max `7.78`, `MAD 1.105%`, max deviation `10.851%`
- `tri6_flat_grey`: min `4.05`, median `4.54`, max `4.70`, `MAD 2.426%`, max deviation `10.695%`

## Sphere2000

- cases analyzed: `28`
- median relative `MAD`: `1.279%`
- 95th percentile relative `MAD`: `3.815%`
- 95th percentile max deviation from median: `10.270%`
- worst max deviation from median: `11.008%`

Geometry families:
- `quad4ibi`: mean median `MPx/s` `12.68`, mean relative `MAD` `1.088%`, mean max deviation `5.524%`
- `quad4newton`: mean median `MPx/s` `17.15`, mean relative `MAD` `1.337%`, mean max deviation `6.296%`
- `quad8`: mean median `MPx/s` `10.98`, mean relative `MAD` `0.891%`, mean max deviation `5.919%`
- `quad9`: mean median `MPx/s` `10.32`, mean relative `MAD` `1.202%`, mean max deviation `9.632%`
- `tri3`: mean median `MPx/s` `38.06`, mean relative `MAD` `2.102%`, mean max deviation `8.262%`
- `tri3opt`: mean median `MPx/s` `38.12`, mean relative `MAD` `2.675%`, mean max deviation `8.414%`
- `tri6`: mean median `MPx/s` `7.38`, mean relative `MAD` `1.034%`, mean max deviation `5.821%`

Shader families:
- `flat_grey`: mean median `MPx/s` `28.95`, mean relative `MAD` `0.896%`, mean max deviation `6.605%`
- `flat_rgb`: mean median `MPx/s` `20.46`, mean relative `MAD` `1.626%`, mean max deviation `7.616%`
- `tex8_grey`: mean median `MPx/s` `15.47`, mean relative `MAD` `1.292%`, mean max deviation `6.586%`
- `tex8_rgb`: mean median `MPx/s` `12.09`, mean relative `MAD` `2.089%`, mean max deviation `7.689%`

Highest-variability cases:
- `quad9_flat_grey`: min `10.51`, median `11.81`, max `12.44`, `MAD 1.143%`, max deviation `11.008%`
- `tri3opt_tex8_rgb`: min `16.82`, median `17.87`, max `19.71`, `MAD 3.694%`, max deviation `10.327%`
- `quad9_tex8_grey`: min `9.06`, median `10.09`, max `10.75`, `MAD 1.091%`, max deviation `10.164%`
- `tri3_flat_rgb`: min `39.99`, median `42.02`, max `46.28`, `MAD 1.618%`, max deviation `10.151%`
- `tri3opt_flat_rgb`: min `38.77`, median `42.01`, max `46.20`, `MAD 3.880%`, max deviation `9.974%`
- `quad9_flat_rgb`: min `9.66`, median `10.59`, max `11.25`, `MAD 1.038%`, max deviation `8.825%`
- `quad9_tex8_rgb`: min `8.04`, median `8.79`, max `9.43`, `MAD 1.536%`, max deviation `8.532%`
- `tri3_tex8_rgb`: min `17.19`, median `18.24`, max `19.77`, `MAD 4.359%`, max deviation `8.388%`

