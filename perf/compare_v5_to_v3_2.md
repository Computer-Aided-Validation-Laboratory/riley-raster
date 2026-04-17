# V5 vs V3.2 Performance Comparison

This compares `v5_variability` against `v3_2_variability`.

- Metric focus:
  - `MPx/s` for `fullraster` and `sphere2000`
  - `MElems/s` for `geom` and `sphere2000`
- Method:
  - use the median of the 10 saved runs for each case
  - compare only cases common to both versions
  - exclude the removed `tri3opt` rows
- Interpretation:
  - positive `% diff` means `v5` is faster
  - negative `% diff` means `v5` is slower

## Summary

The main outlier is `quad4ibi`.

That regression is expected:
- we added a hull to `quad4ibi`
- the hull must now be built during geometry preprocessing
- the inverse bilinear solver now has additional valid code paths
- the raster path now also pays for the coarse hull in/out checks

If `quad4ibi` is ignored, the rest of the codebase is broadly flat against
`v3.2`, which is acceptable for this refactor stage.

The most important benchmark is `sphere2000`, and in `MPx/s` that case is
effectively flat overall.

## Fullraster `MPx/s` Flat

| Element        | flat<br>grey | flat<br>rgb |
|----------------|-------------:|------------:|
| `tri3`         |       `-6.2` |      `-3.1` |
| `tri6`         |       `-4.9` |      `-4.4` |
| `quad4ibi`     |       `+4.6` |      `+7.0` |
| `quad4newton`  |       `-3.7` |      `-2.3` |
| `quad8`        |       `-3.8` |      `-3.0` |
| `quad9`        |       `-2.7` |      `-1.5` |

## Fullraster `MPx/s` Tex Grey

| Element        | lin | cubic | cubic<br>lut | quint | quint<br>lut |
|----------------|----:|------:|-------------:|------:|-------------:|
| `tri3`         | `-2.0` | `-1.1` | `-0.6` | `-0.6` | `-1.2` |
| `tri6`         | `-3.1` | `-1.8` | `-2.8` | `-1.2` | `-0.8` |
| `quad4ibi`     | `+5.7` | `+10.8` | `+10.2` | `+3.1` | `+4.4` |
| `quad4newton`  | `-4.0` | `-2.9` | `-3.2` | `-1.7` | `-2.1` |
| `quad8`        | `-2.4` | `-0.9` | `-2.5` | `-1.2` | `-0.8` |
| `quad9`        | `-2.3` | `-2.0` | `-2.7` | `-1.3` | `-2.7` |

## Fullraster `MPx/s` Tex RGB

| Element        | lin | cubic | cubic<br>lut | quint | quint<br>lut |
|----------------|----:|------:|-------------:|------:|-------------:|
| `tri3`         | `-0.4` | `-1.4` | `-1.5` | `-0.8` | `-1.1` |
| `tri6`         | `-5.8` | `-4.7` | `-4.5` | `-2.3` | `-3.1` |
| `quad4ibi`     | `+3.2` | `+6.8` | `+5.6` | `+4.5` | `+4.9` |
| `quad4newton`  | `-2.9` | `-2.1` | `-3.4` | `-1.7` | `-2.6` |
| `quad8`        | `-5.9` | `-4.0` | `-5.0` | `-2.1` | `-4.2` |
| `quad9`        | `+1.1` | `-0.4` | `-2.7` | `-0.9` | `-1.3` |

## Geom `MElems/s` Flat

| Element        | flat<br>grey | flat<br>rgb |
|----------------|-------------:|------------:|
| `tri3`         |       `+1.5` |      `+4.5` |
| `tri6`         |       `+4.5` |      `+2.2` |
| `quad4ibi`     |      `-48.0` |     `-48.1` |
| `quad4newton`  |       `+6.7` |      `+5.2` |
| `quad8`        |       `+2.6` |      `+3.8` |
| `quad9`        |       `-2.0` |      `+2.1` |

## Geom `MElems/s` Tex Grey

| Element        | lin | cubic | cubic<br>lut | quint | quint<br>lut |
|----------------|----:|------:|-------------:|------:|-------------:|
| `tri3`         | `+3.5` | `+0.7` | `+2.9` | `+1.4` | `+2.8` |
| `tri6`         | `+5.0` | `+5.6` | `+3.2` | `+3.9` | `+4.4` |
| `quad4ibi`     | `-47.6` | `-47.8` | `-47.0` | `-48.3` | `-47.0` |
| `quad4newton`  | `+5.3` | `+6.7` | `+6.7` | `+7.2` | `+5.2` |
| `quad8`        | `+4.3` | `+2.9` | `+5.2` | `+3.5` | `+3.2` |
| `quad9`        | `+4.2` | `-1.1` | `+0.1` | `+0.8` | `+1.1` |

## Geom `MElems/s` Tex RGB

| Element        | lin | cubic | cubic<br>lut | quint | quint<br>lut |
|----------------|----:|------:|-------------:|------:|-------------:|
| `tri3`         | `+4.1` | `+3.6` | `+2.1` | `+3.1` | `+6.2` |
| `tri6`         | `+3.8` | `+3.9` | `+4.0` | `+7.5` | `+5.7` |
| `quad4ibi`     | `-46.9` | `-47.1` | `-48.1` | `-47.4` | `-47.4` |
| `quad4newton`  | `+8.0` | `+6.2` | `+4.8` | `+3.7` | `+4.3` |
| `quad8`        | `-1.6` | `-1.9` | `+0.9` | `+3.4` | `+1.1` |
| `quad9`        | `+0.3` | `+2.1` | `+1.2` | `+0.6` | `+1.0` |

## Sphere2000 `MPx/s`

| Element        | flat<br>grey | flat<br>rgb | tex8<br>grey | tex8<br>rgb |
|----------------|-------------:|------------:|-------------:|------------:|
| `tri3`         |       `+0.9` |      `+3.5` |       `-0.5` |      `+0.2` |
| `tri6`         |       `-4.4` |      `-5.0` |       `-1.2` |      `-0.9` |
| `quad4ibi`     |       `-3.0` |      `-1.3` |       `+9.0` |      `+3.7` |
| `quad4newton`  |       `+4.6` |      `+2.8` |       `+0.1` |      `+1.1` |
| `quad8`        |       `+1.6` |      `-0.2` |       `-0.9` |      `-1.6` |
| `quad9`        |       `-1.3` |      `+1.4` |       `-1.5` |      `-1.9` |

## Sphere2000 `MElems/s`

| Element        | flat<br>grey | flat<br>rgb | tex8<br>grey | tex8<br>rgb |
|----------------|-------------:|------------:|-------------:|------------:|
| `tri3`         |       `+3.4` |      `+3.3` |       `+2.2` |      `+4.3` |
| `tri6`         |       `+6.6` |      `+5.5` |       `+9.5` |      `+4.5` |
| `quad4ibi`     |      `-46.9` |     `-45.9` |      `-45.6` |     `-44.1` |
| `quad4newton`  |       `+4.8` |      `+3.0` |       `+0.4` |      `+1.3` |
| `quad8`        |       `+2.9` |      `+2.2` |       `+1.6` |      `+3.6` |
| `quad9`        |       `-1.0` |      `+3.0` |       `+0.1` |      `+3.8` |
