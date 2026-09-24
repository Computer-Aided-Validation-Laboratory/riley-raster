![Riley Logo](/images/riley_logo.png)

Riley is a high performance Zig software rasteriser for digital image correlation uncertainty quantification (DIC UQ). It synthesises deformed speckle images from finite element simulations, with higher order surface elements (`tri3`, `tri6`, `quad4`, `quad8`, and `quad9`), camera models and distortion, texture/nodal/analytic shaders, and mixed scenes.

Riley's Zig core uses `comptime` specialisation and SIMD with `@Vector` to keep its rendering path direct. It also uses hierarchical offline parallelisation allowing scaling over cameras and timesteps to be rendered. Riley is available as a Zig library and executable, a C compatible ABI, and the [`riley-raster`](https://pypi.org/project/riley-raster/) Python package.

## Quick start: Zig

Riley uses [Zig 0.16.0](https://ziglang.org/download/). Clone the repository, then build and run the smallest demo:

```shell
zig build demo0-quickstart -Doptimize=ReleaseFast
```

Renders are written to `out/`. Run the combined smoke suite with:

```shell
zig build test-verif-basic -Doptimize=ReleaseSafe
```

## Quick start: Python

Install the published package, the package builds Riley from Zig source locally, so installation can take a several minutes.:

```shell
python -m pip install riley-raster
python -m riley demo0_quickstart
```
Python renders are written below `out_riley_py/`. For development from a checkout, install it in editable mode:

```shell
python -m pip install -e .
```

## Verification and regression tests

The Zig test suites are intentionally separated by purpose. The focused verification suite requires the production `f64` and SIMD configuration; run `zig build --help` for the complete target list and configuration options.

| Command | Purpose |
| --- | --- |
| `zig build test-verif-basic -Doptimize=ReleaseSafe` | Fast combination of focused analytic verification and basic regression tests. |
| `zig build test-verif -Doptimize=ReleaseSafe` | Analytic verification of the solver, silhouettes, depth buffer, and camera distortion. |
| `zig build test-basic -Doptimize=ReleaseSafe` | Basic regression suite. |
| `zig build test-full -Doptimize=ReleaseSafe` | Full regression suite. |

Run the packaged Python test suite with:

```shell
python -m pytest --pyargs riley.pytests -s
```

or:

```shell
python -m riley test
```

The repository parity tests compare Python and Zig demo output when the repository assets and Zig compiler are available; they skip when installed from a clean PyPI package.

## Examples

Riley provides a series of capability demos in Zig and Python. For example, render the rabbits demo with:

```shell
zig build demo3-rabbits -Doptimize=ReleaseFast
```

The equivalent Python demo is:

```shell
python -m riley demo3_rabbits
```

Browse the complete [Zig demo directory](https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src) or [Python demo directory](https://github.com/Computer-Aided-Validation-Laboratory/riley-raster/tree/main/src/riley/pydemos). The image links below are absolute GitHub URLs so they render both on GitHub and on PyPI.

### Rabbits demo

The rabbit scene combines all supported element types and the principal shader families in a single render.

![Rendered rabbits](https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/demo_rabbitrender.png)

### Digital image correlation UQ demo

A representative stereo DIC UQ render of a plate with a hole in tension.

| Camera 0 | Camera 1 |
| :---: | :---: |
| <img src="https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/dicuq_cam0_frame0_field0.png" alt="DIC Camera 0" width="400"> | <img src="https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/dicuq_cam1_frame0_field0.png" alt="DIC Camera 1" width="400"> |

### Stereo calibration target demo

Stereo calibration target renders using the DIC UQ camera setup.

| Camera 0 | Camera 1 |
| :---: | :---: |
| <img src="https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/cal_cam0_frame0_field0.png" alt="Calibration camera 0" width="400"> | <img src="https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/cal_cam1_frame0_field0.png" alt="Calibration camera 1" width="400"> |

## Project Layout
The main Zig entry point for the rendering pipeline is the `raster(...)` family in `./src/riley/zig/riley.zig`.

Useful top-level locations:

- `src/`: Zig demos, tests, benchmarks and the core Riley source
- `src/riley/zig/`: core Zig implementation
- `src/riley/cython/`: Cython->Python bindings for Riley
- `src/riley/python/`: Python utilities for setup and mesh manipulation
- `src/riley/pydemos/`: packaged Python demos
- `src/riley/pytests/`: packaged Python tests
- `gold/`: gold reference renders for regression testing
- `out/`: Zig render and benchmark output
- `out_riley_py/`: Python render output
- `dev/README.md`: detailed developer testing and benchmark notes

For a mathematical and architectural overview, see the engrXiv preprint: [Riley: A computational framework for higher-order finite element image synthesis applied to digital image correlation uncertainty quantification](https://engrxiv.org/preprint/view/7300/version/9460).

## C Interface
`Riley` provides a C-compatible API for use from other languages. The Python bindings use this interface through Cython, but it can also be called from C or from any language with a C FFI.

The public C ABI is intentionally fixed to the production Riley build with: precision=`f64`, SIMD=`on`. The extern types and functions live in [`src/riley/zig/c-riley.zig`](./src/riley/zig/c-riley.zig).

## Citing Riley
If you have found `Riley` useful you can cite it using:

> Fletcher, L., Hirst, J., and Bielajewa, W. (2026).
> *Riley: A computational framework for higher-order finite element image synthesis applied to digital image correlation uncertainty quantification*.
> engrXiv preprint. https://engrxiv.org/preprint/view/7300

```bibtex
@article{fletcher2026riley,
  title   = {Riley: A computational framework for higher-order finite element image synthesis applied to digital image correlation uncertainty quantification},
  author  = {Fletcher, Lloyd and Hirst, Joel and Bielajewa, Wiera},
  year    = {2026},
  journal = {engrXiv},
  note    = {Preprint},
  url     = {https://engrxiv.org/preprint/view/7300}
}
```

## Contributors
- Lloyd Fletcher ([ScepticalRabbit](https://github.com/ScepticalRabbit)), UK Atomic Energy Authority
- Joel Hirst ([JoelPhys](https://github.com/JoelPhys)), UK Atomic Energy Authority
- Wiera Bielajewa ([WieraB](https://github.com/WieraB)), UK Atomic Energy Authority
- James Panayis ([james-panayis](https://github.com/james-panayis)), UK Atomic Energy Authority
- Megan Sampson ([meganasampson](https://github.com/meganasampson)), UK Atomic Energy Authority

## Dedication
Named in memory of Riley, and for Feebee, her sister and bondmate. Without your love and support, this project would never have happened.

![Riley](https://raw.githubusercontent.com/Computer-Aided-Validation-Laboratory/riley-raster/main/images/RileyHelping.jpg)
