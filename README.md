# zaster
`zraster` is a performant software rasteriser written in Zig specifically designed for digital image correlation (DIC) uncertainty quantification (UQ). `zraster` performs off-line rendering of deformed speckle pattern images from an input finite element simulation. `zraster` supports accurate rendering of higher order finite elements including tri3, tri6, quad4, quad8 and quad9 surface elements. Texture shading with higher order texture sampling is also supported for accurate speckle pattern rendering including: cubic sampling (Catmull-Rom, Mitchell-Netravali, BSpline), quintic sampling (BSpline) and Lancsoz (lancsoz3). Rendering multiple meshes with different element types and shading strategies in the same scene is supported.

We specifically chose to implement `zraster` in Zig as it is a compiled language with manual memory management. It also allows for compile time code generation and has excellent support for SIMD vector types. We have used `comptime` to generate speciliased kernels for geometry and shader types removing run time dispatch overhead. We have also leveraged Zig's `io` interface to implement hierarchical parallelisation...

## Getting Started
`zraster` uses the Zig 0.16.0 compiler release which can be downloaded from [here](https://ziglang.org/download/). The `zraster` repository contains a minimal set of regression tests (called the "min" test suite) which should be run before generating a wider set gold regression data and running performance benchmark suites. The min test suite can be run from the project root directory using:
```shell
zig test -lc -O ReleaseSafe ./src/test_min.zig
```
The min test suite contains two cases a render of the "multimesh" case which is two elements of each type in a single scene that are rendered with nodal interpolation shading or texture shading. The min test suite also contains a rendering of the "sphere200" case which is a sphere with 200 elements of a single type with every possible combination of nodal or texture shading. the sphere200 case is particularly sensitive to breaking changes due to the range of element orientations.

Once the min test suite passes the additional gold regression data can be generated for two suites the first is the "all" suite and the second is the "bench" suite. The "bench" suite is based on the benchmarks described in the "Benchmarks" section below. Before we can render the gold images we first need to generate the larger meshes for the "bench" cases using a python script that has numpy as a dependency, run this from the project root:
```shell
python ./data/bench/gen_bench_data.py
```

You should see a range of directories generated in the data/bench directory with different element types and case tags. Once that is done we can render the required gold output with:
```shell
zig run -lc -O ReleaseSafe ./src/gen_gold_all.
```

Now we can run the remaining "all" and "bench" test suites:
```shell
zig test -lc -O ReleaseSafe ./src/test_gold_all.zig
zig test -lc -O ReleaseSafe ./src/test_bench.zig
```

## Capability Demonstration
We have included a series of capability demonstrations scripts in the /src/ directory.... These can be run using
```shell
zig run -lc -O ReleaseFast ./src/demo_CASE.zig
```
where CASE is the name of the demonstration case you want to run. The output renders will be saved to ./out/demo-CASE/.

### Speckle Sphere

### Rendering Rabbits
In this demonstration we render a series of rabbit meshes that are composed of all supported element types: `tri3`, `tri6`, `quad4`, `quad8` and `quad9`. We also demonstrate the usage of all support shader types in the same scene rotating between a texture shader with cubic LUT-lerp sampling, a nodal interpolation shader interpolating the uv coordinates and an analytic function shader producing a sin wave pattern across the rabbit mesh based on the input uvs. The output render is shown below, the top row are the triangular meshes and the bottom row are the quadrilateral meshes:

![fig_rabbit_render](/images/demo_rabbitrender.bmp)

### Digital Image Correlation Uncertainty Quantification
For this case we demonstrate a representative DIC UQ rendering using an input finite element model of a plate with a hole loaded in tension imaged by a stereo DIC system consisting of two 5MPx cameras. The simulation mesh was generated with Gmsh and solved using the MOOSE solid mechanics module. The gmsh .geo and MOOSE .i input file can be found in the /data/FE/ directory.

| Camera 0 | Camera 1 |
|:---:|:---:|
| ![DIC Camera 0](./images/dicuq_cam0_frame0_field0.bmp) | ![DIC Camera 1](./images/dicuq_cam1_frame0_field0.bmp) |


### Stereo Calibration
We now use the camera setup from the previous DIC UQ demo, import it and then render a series of stereo calibration target images with the same camera setup. A representative render is shown below:

| Camera 0 | Camera 1 |
|:---:|:---:|
| ![Cal Camera 0](./images/cal_cam0_frame0_field0.bmp) | ![ Cal Camera 1](./images/cal_cam1_frame0_field0.bmp) |


## Performance Benchmarks
We used four cases to analyse the performance of `zraster`: 1) Minimum elements filling the screen (2 triangles or 1 quadrilateral), called "fullraster", 2) 1e5 elements filling screen, called "geom", 3) A sphere in the centre of the screen with 2000 elements, called sphere2000. Case 1 is intended to test the throughput of the raster hot loop. Case 2 is intended to test the throughput of the geometry pre-processing. Case 3 is a more realistic case with a balance of element orientations. Case 4 tests thread scaling on the same case as the DIC UQ demonstration. These benchmark suites can be run using:

```shell
zig run -lc -O ReleaseFast ./src/bench_fullraster.zig
zig run -lc -O ReleaseFast ./src/bench_geom.zig
zig run -lc -O ReleaseFast ./src/bench_sphere2000.zig
zig run -lc -O ReleaseFast ./src/bench_dicuq.zig
```
You will find the rendered output for these benchmarks in ./out/bench-CASE where CASE is fullraster, geom, sphere2000 or dicuq.

## Navigating the Codebase
The main entry point for the `zraster` rendering pipeline is the `rasterAllFrames` function in ./src/zraster/zig/zraster.zig.

## Contributors
- Lloyd Fletcher ([ScepticalRabbit](https://github.com/ScepticalRabbit)), UK Atomic Energy Authority
- Joel Hirst ([]()), UK Atomic Energy Authority
- Wiera Bielajewa ([]()), UK Atomic Energy Authority
