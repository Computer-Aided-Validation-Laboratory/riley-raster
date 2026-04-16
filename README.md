# zaster
`zraster` is a performant software rasteriser written in Zig specifically designed for digital image correlation (DIC) uncertainty quantification (UQ). `zraster` performs off-line rendering of deformed speckle pattern images from an input finite element simulation. `zraster` supports accurate rendering of higher order finite elements including tri3, tri6, quad4, quad8 and quad9 surface elements. Texture shading with higher order texture sampling is also supported for accurate speckle pattern rendering including: cubic sampling (Catmull-Rom, Mitchell-Netravali, BSpline), quintic sampling (BSpline) and Lancsoz (lancsoz3). Rendering multiple meshes with different element types and shading strategies in the same scene is supported. 

We specifically chose to implement `zraster` in Zig as it is a compiled language with manual memory management. It also allows for compile time code generation and has excellent support for SIMD vector types. We have used `comptime` to generate speciliased kernels for geometry and shader types removing run time dispatch overhead. 

## Getting Started
`zraster` has been built using a developement version of the Zig 0.16 compiler.  

The `zraster` repository contains a minimal set of regression tests (called the "min" test suite) which should be run before generating a wider set gold regression data and running performance benchmark suites. The min test suite can be run from the project root directory using:
```shell
zig test -lc -O ReleaseSafe ./src/test_min.zig
```
The min test suite contains two cases a render of the "multimesh" case which is two elements of each type in a single scene that are rendered with nodal interpolation shading or texture shading. The min test suite also contains a rendering of the "sphere200" case which is a sphere with 200 elements of a single type with every possible combination of nodal or texture shading. the sphere200 case is particularly sensitive to breaking changes due to the range of element orientations.

Once the min test suite passes the additional gold regression data can be generated for two suites the first is the "all" suite and the second is the "bench" suite. The "bench" suite is based on the benchmarks described in the "Benchmarks" section below. Before we can render the gold images we first need to generate the larger meshes for the "bench" cases using a python script that has numpy as a dependency, run this from the project root:
```shell
python ./data-bench/gen_bench_data.py
```

You should see a range of directories generated in the data-bench directory with different element types and case tags. Once that is done we can render the required gold output with:
```shell
zig run -lc -O ReleaseSafe ./src/gen_gold_all.zig
```

Now we can run the remaining "all" and "bench" test suites:
```shell
zig test -lc -O ReleaseSafe ./src/test_gold_all.zig
zig test -lc -O ReleaseSafe ./src/test_bench.zig
```

## Capability Demo


## Benchmarks
We used three cases to analyse the performance of `zraster`: 1) Minimum elements filling the screen (2 triangles or 1 quadrilateral), called "fullraster", 2) 1e5 elements filling screen, called "geom", 3) A sphere in the centre of the screen with 2000 elements, called sphere2000. Case 1 is intended to test the throughput of the raster hot loop. Case 2 is intended to test the throughput of the geometry pre-processing. Case 3 is a more realistic case with a balance of element orientations. These benchmark suites can be run using:

```shell
zig run -lc -O ReleaseFast ./src/bench_fullraster.zig
zig run -lc -O ReleaseFast ./src/bench_geom.zig
zig run -lc -O ReleaseFast ./src/bench_sphere2000.zig
``` 

## Contributors
- Lloyd Fletcher ([ScepticalRabbit](https://github.com/ScepticalRabbit)), UK Atomic Energy Authority
