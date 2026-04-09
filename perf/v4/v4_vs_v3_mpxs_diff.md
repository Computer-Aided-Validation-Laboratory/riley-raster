# V4 vs V3 MPx/s Diff

Percent difference in median `MPx/s`, computed as:

`(v4 - v3) / v3`

Positive values are faster in `v4`.

`tri3` is compared against the `v3` `tri3` row. `tri3opt` was removed in `v4`.

## Read

- `sphere2000` is the most realistic case and is effectively flat overall.
- `fullraster` is mostly slightly down versus `v3`.
- `geom` is mixed, with the largest `tri3` regressions concentrated in RGB
  texture cases.

## Fullraster

| Element     | flat_grey | flat_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|-------------|----------:|---------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`      |    -13.8% |    +5.3% |        -3.2% |          -2.0% |              -1.7% |             -0.7% |                 -1.5% |
| `tri6`      |     -3.8% |    -2.3% |        -2.3% |          -1.4% |              -2.2% |             -1.4% |                 -1.3% |
| `quad4ibi`  |     +1.2% |    +2.3% |        -0.0% |          -0.3% |              -0.2% |             -0.7% |                 +0.7% |
| `quad4newton` |   -5.8% |    -2.2% |        -4.6% |          -3.2% |              -3.6% |             -1.5% |                 -2.7% |
| `quad8`     |     -4.8% |    -2.5% |        -3.7% |          -1.9% |              -2.4% |             -1.2% |                 -1.2% |
| `quad9`     |     -4.4% |    -1.0% |        -2.9% |          -2.3% |              -2.7% |             -1.2% |                 -1.8% |

| Element     | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|-------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`      |       +1.8% |         -0.1% |             +0.1% |           +0.0% |               +0.0% |
| `tri6`      |       -2.4% |         -1.6% |             -1.3% |           -0.6% |               -0.7% |
| `quad4ibi`  |       +3.7% |         +0.5% |             -0.7% |           +0.6% |               +0.5% |
| `quad4newton` |    -3.4% |         -2.3% |             -3.8% |           -1.7% |               -1.8% |
| `quad8`     |       -1.7% |         -0.7% |             -1.6% |           -0.6% |               -1.1% |
| `quad9`     |       -1.7% |         -0.5% |             -2.4% |           -0.9% |               -1.3% |

## Geom

| Element       | flat_grey | flat_rgb | tex_grey_lin | tex_grey_cubic | tex_grey_cubic_lut | tex_grey_quintic | tex_grey_quintic_lut |
|---------------|----------:|---------:|-------------:|---------------:|-------------------:|------------------:|----------------------:|
| `tri3`        |     -2.7% |    -1.9% |        -2.8% |          -1.8% |              -2.0% |             -0.9% |                 -2.1% |
| `tri6`        |     -5.6% |    -5.7% |        -3.5% |          -2.8% |              -2.6% |             -2.1% |                 -1.8% |
| `quad4ibi`    |     -8.1% |    -4.5% |        -1.8% |          -0.9% |              -0.7% |             -0.6% |                 -0.4% |
| `quad4newton` |    +11.9% |   +11.1% |        -9.9% |          -7.4% |              -7.6% |             -5.3% |                 -6.2% |
| `quad8`       |     -2.4% |    -0.8% |        -0.7% |          -1.4% |              -1.4% |             +0.0% |                 -0.5% |
| `quad9`       |     +0.0% |    -1.8% |        -3.4% |          -3.0% |              -2.4% |             -2.2% |                 -1.3% |

| Element       | tex_rgb_lin | tex_rgb_cubic | tex_rgb_cubic_lut | tex_rgb_quintic | tex_rgb_quintic_lut |
|---------------|------------:|--------------:|------------------:|----------------:|--------------------:|
| `tri3`        |      -18.7% |        -12.1% |            -12.4% |           -8.5% |              -10.3% |
| `tri6`        |       -7.9% |         -6.6% |             -6.6% |           -5.4% |               -5.2% |
| `quad4ibi`    |       -1.2% |         -0.8% |             -0.6% |           +0.0% |               +0.0% |
| `quad4newton` |       -1.9% |         -0.8% |             -2.4% |           -1.4% |               -0.4% |
| `quad8`       |       -0.8% |         -1.3% |             +1.0% |           -1.1% |               -1.5% |
| `quad9`       |       -4.2% |         -3.1% |             -1.8% |           -2.3% |               -1.6% |

## Sphere2000

| Element       | flat_grey | flat_rgb | tex_grey | tex_rgb |
|---------------|----------:|---------:|---------:|--------:|
| `tri3`        |     -3.2% |    +2.9% |    +0.8% |   +1.8% |
| `tri6`        |     -2.6% |    -2.1% |    -1.4% |   -2.2% |
| `quad4ibi`    |     -0.4% |    +0.4% |    +0.2% |   +1.1% |
| `quad4newton` |     +3.1% |    +3.1% |    -2.6% |   -1.1% |
| `quad8`       |     -2.7% |    -1.1% |    -1.5% |   +0.1% |
| `quad9`       |     -2.0% |    -1.3% |    -1.3% |   -0.6% |
