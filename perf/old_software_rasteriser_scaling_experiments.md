# Software Rasteriser Scaling Experiment Plan

This document summarises the scaling experiments to run for the Zig software rasteriser. The goal is to understand CPU scaling, cache effects, tile-size effects, anti-aliasing effects, nested parallelism, and optional I/O behaviour without exploding into a full factorial benchmark matrix.

## 1. Core principles

### Measure different benchmark scopes separately

Do not try to produce one global Amdahl number for the whole renderer. The apparent serial fraction depends on what is being measured:

- Single-frame latency
- Batch throughput
- Geometry-only scaling
- Tile-raster scaling
- End-to-end export including optional I/O

Amdahl's law applies to the measured workload, so each benchmark scope can have a different apparent serial fraction.

### Treat physical cores as the main scaling variable

For the main scaling plots, use physical cores:

- Ryzen 7 laptop: `1, 2, 4, 8`
- 64-core Threadripper: `1, 2, 4, 8, 16, 32, 64`

SMT / hyperthreads can be tested separately, but should not be included in the main Amdahl fit for a strongly CPU-bound rasteriser.

Optional SMT checks:

- Ryzen 7 laptop: `16`
- Threadripper: `128`

### Keep I/O separate

For CPU and memory scaling experiments, use:

- Disk I/O disabled
- Encoding disabled
- Preallocated output buffers
- Frames returned or written in memory only

Then run a separate end-to-end benchmark for saving frames to disk.

---

## 2. Metrics to collect

For every run, collect:

```text
benchmark_name
scene_name
resolution
output_pixels
anti_aliasing_mode
subpixel_samples_per_pixel
tile_size_pixels
tile_size_subpixels
thread_count
physical_core_count_used
frames_rendered
cameras_rendered
io_mode
total_time_ms
ms_per_frame
ns_per_output_pixel
ns_per_subpixel_sample
```

For scaling runs, also compute:

```text
speedup = T_1 / T_N
parallel_efficiency = speedup / N
```

For Amdahl-style reporting:

```text
apparent_serial_fraction(N) =
    ((1 / speedup) - (1 / N)) / (1 - (1 / N))
```

This is an apparent fraction, not a pure structural serial fraction. It includes real overheads such as synchronization, cache misses, load imbalance, and memory bandwidth pressure.

---

## 3. Phase instrumentation

Add timing for at least these phases:

```text
frame_total
scene_update
camera_setup
geometry_transform
triangle_setup
binning
tile_raster
resolve
output_copy
encode
disk_write
```

For CPU-only scaling, `encode` and `disk_write` should be disabled or reported separately.

### Per-worker counters

For each worker thread, collect:

```text
worker_id
active_time_ns
idle_or_wait_time_ns
tiles_processed
triangles_processed
output_pixels_processed
subpixel_samples_processed
```

### Optional per-tile diagnostics

For deeper diagnosis, temporarily collect:

```text
tile_id
triangles_in_tile
covered_output_pixels
covered_subpixel_samples
raster_time_ns
```

This helps distinguish load imbalance from memory/cache bandwidth problems.

---

## 4. Anti-aliasing and tile-size definitions

The default tile size is:

```text
32 x 32 output pixels
```

The default anti-aliasing is:

```text
2 x 2 subpixel samples per output pixel
```

Therefore the default tile contains:

```text
32 x 32 x 2 x 2 = 4096 subpixel samples
```

When comparing anti-aliasing modes, always report both:

```text
ns / output pixel
ns / subpixel sample
```

This avoids confusing true performance changes with simply doing more subpixel work.

A useful hypothesis to test later is to keep the subpixel tile edge roughly constant:

```text
target_subpixel_tile_edge ~= 64
tile_px = target_subpixel_tile_edge / aa_factor
```

Example:

```text
AA 1x1 -> 64 px tile gives 64 x 64 samples
AA 2x2 -> 32 px tile gives 64 x 64 samples
AA 4x4 -> 16 px tile gives 64 x 64 samples
```

Do not adopt this automatically. Treat it as a benchmark hypothesis.

---

# Step-by-step experiment suite

## Step 0: Verify benchmark hygiene

Before collecting scaling data, make sure the benchmark environment is stable.

### Requirements

- Use ReleaseFast for performance measurements.
- Run warmup frames before timing.
- Run enough frames to reduce noise.
- Disable debug logging.
- Disable file output unless the benchmark is specifically about I/O.
- Preallocate buffers where possible.
- Avoid allocator noise inside inner loops.
- Record CPU model, core count, memory configuration, and OS.
- Record whether threads are pinned.
- Record whether SMT is enabled.

### Suggested repeated-run policy

For each configuration:

```text
warmup: 5 to 20 frames
timed: 30 to 300 frames, depending on cost
repeats: at least 3
reported value: median, optionally also min
```

---

## Step 1: Single-thread sensor-size sweep

### Purpose

Find where single-thread performance stops scaling cleanly with sensor size. This reveals cache, TLB, and memory-footprint knees without threading noise.

### Fixed settings

```text
threads: 1
tile size: 32 px
AA: 2x2
I/O: off
output: preallocated memory buffer
```

### Scenes

Use two scenes initially:

```text
A. Fill-rate scene
   - Simple geometry
   - Large triangles
   - Lots of covered pixels

B. Geometry/binning scene
   - Many triangles
   - Realistic mesh
   - Moderate coverage
```

### Resolutions

Use a square sweep initially:

```text
512 x 512
1024 x 1024
2048 x 2048
4096 x 4096
8192 x 8192
16384 x 16384, if realistic
```

### Report

For each run:

```text
ms/frame
ns/output pixel
ns/subpixel sample
geometry %
binning %
tile_raster %
resolve/copy %
```

### What to look for

Expected regimes:

```text
small image:
    fixed overhead dominates

medium image:
    best ns/sample

huge image:
    cache, TLB, or memory-bandwidth penalty appears
```

Choose three representative resolutions from this sweep:

```text
small: below the knee
medium: near best efficiency
large: beyond the knee
```

These will be used in later experiments.

---

## Step 2: Thread scaling at three resolutions

### Purpose

Measure how sensor size interacts with thread scaling.

### Fixed settings

```text
tile size: 32 px
AA: 2x2
I/O: off
output: preallocated memory buffer
```

### Resolutions

Use the three resolutions selected from Step 1:

```text
small
medium
large
```

### Scenes

Use the same two scenes from Step 1:

```text
fill-rate scene
geometry/binning scene
```

### Thread counts

Ryzen 7 laptop:

```text
1, 2, 4, 8
```

Threadripper workstation:

```text
1, 2, 4, 8, 16, 32, 64
```

Optional SMT footnote:

```text
Ryzen 7: 16
Threadripper: 128
```

### Report

For each resolution and scene:

```text
ms/frame
speedup vs 1 thread at same resolution
parallel efficiency
apparent serial fraction
phase breakdown
worker active/idle spread
```

### Plots

Create:

```text
x-axis: physical cores
y-axis: speedup
series: small, medium, large resolution
```

Also useful:

```text
x-axis: physical cores
y-axis: parallel efficiency
series: small, medium, large resolution
```

### What to look for

Likely patterns:

```text
small sensor:
    poor scaling because there is not enough tile work

medium sensor:
    best scaling because there is enough work and locality is good

large sensor:
    enough work, but possible loss of efficiency due to memory/cache pressure
```

If workers have similar active time but scaling is poor, suspect memory bandwidth or shared cache pressure.

If some workers finish much earlier than others, suspect tile load imbalance.

---

## Step 3: Tile-size and anti-aliasing sensitivity

### Purpose

Determine whether the fixed 32 px tile size is a good default, and whether tile size should vary with AA level or workload.

### Use a cross-shaped subset, not a full matrix

Do not test all tile sizes against all AA modes initially.

Use these five configurations:

```text
16 px tile, AA 2x2
32 px tile, AA 1x1
32 px tile, AA 2x2
32 px tile, AA 4x4
64 px tile, AA 2x2
```

### Resolutions

Use:

```text
medium resolution from Step 1
large resolution from Step 1
```

### Scenes

Use one representative realistic scene initially. Add the fill-rate and geometry-heavy scenes later only if the results are ambiguous.

### Thread counts

Run at:

```text
1 physical core
all physical cores
```

For the laptop:

```text
1 and 8
```

For the Threadripper:

```text
1 and 64
```

### Report

For each run:

```text
ms/frame
ns/output pixel
ns/subpixel sample
speedup, for all-core runs
parallel efficiency, for all-core runs
tile_raster time
binning time
worker imbalance
```

### What to look for

Possible conclusions:

```text
16 px tiles beat 32 px at high AA:
    subpixel tile working set is probably too large

64 px tiles beat 32 px at low AA:
    scheduling or binning overhead may dominate

32 px tiles remain best:
    current default is reasonable

best tile size changes with thread count:
    dynamic tile sizing may need to consider thread count or workload
```

---

## Step 4: Outer vs inner parallelism

### Purpose

Determine whether coarse outer parallelism over cameras and frames is better than deeply threaded single-frame rendering for production workloads.

### Workload shapes

Use four shapes:

```text
1 camera x 1 frame
1 camera x many frames
many cameras x 1 frame
many cameras x many frames
```

### Parallelism modes

Compare:

```text
A. Inner only
   - One camera/frame at a time
   - Geometry and tile rendering use all cores

B. Outer only
   - Many camera/frame jobs in parallel
   - Each individual frame mostly single-threaded

C. Hybrid
   - Prefer outer camera/frame jobs
   - Use inner geometry/tile threading only when outer work is insufficient

D. Current/default scheduler
   - Whatever the current implementation does
```

If the current scheduler is already hybrid, compare only:

```text
inner only
outer only
current hybrid
```

### Fixed settings

```text
realistic scene
AA: 2x2
tile size: 32 px or best candidate from Step 3
I/O: off
output: preallocated memory buffer
```

### Thread counts

Minimal:

```text
1 physical core
all physical cores
```

Optional extra:

```text
half physical cores
```

For Threadripper, that means:

```text
1, 32, 64
```

### Report

For each mode and workload shape:

```text
total time
frames per second
camera-frames per second
speedup
parallel efficiency
phase breakdown
worker utilisation
```

### What to look for

Expected behaviour:

```text
1 camera x 1 frame:
    inner geometry/tile threading is necessary

many cameras x many frames:
    outer parallelism may be better because it is coarse grained

small number of camera/frame jobs with huge meshes:
    hybrid scheduling may be best
```

The goal is to determine when inner threading should be enabled and when outer jobs alone are enough to fill the CPU.

---

## Step 5: Geometry-only benchmark

### Purpose

Measure threaded geometry scaling independently from tile rasterisation.

### Setup

Disable or mock tile rasterisation if possible.

Use:

```text
small mesh
medium mesh
huge mesh
```

### Thread counts

Laptop:

```text
1, 2, 4, 8
```

Threadripper:

```text
1, 2, 4, 8, 16, 32, 64
```

### Report

```text
geometry time
triangle setup time
transform time
binning time, if included
speedup
parallel efficiency
apparent serial fraction
```

### What to look for

This tells you whether the geometry stage has enough work to justify inner threading.

If geometry scaling collapses early, inspect:

```text
memory access pattern
allocator use
shared output structures
atomic contention
work chunk size
```

---

## Step 6: Tile-raster-only benchmark

### Purpose

Measure tile rendering independently from geometry setup.

### Setup

Use precomputed or cached binned geometry if possible.

Use cases:

```text
few triangles, many pixels
many small triangles
heavy overdraw
high depth-test pressure
cheap shading
expensive shading, if applicable
```

### Thread counts

Laptop:

```text
1, 2, 4, 8
```

Threadripper:

```text
1, 2, 4, 8, 16, 32, 64
```

### Report

```text
tile raster time
ns/output pixel
ns/subpixel sample
tiles processed
samples processed
worker imbalance
speedup
parallel efficiency
apparent serial fraction
```

### What to look for

If tile-raster scaling is poor despite enough tiles, likely causes include:

```text
memory bandwidth saturation
shared cache pressure
depth/color buffer traffic
false sharing
tile load imbalance
task scheduling overhead
```

---

## Step 7: Optional I/O and end-to-end export benchmark

### Purpose

Measure user-facing export performance separately from CPU render scaling.

### Modes

Compare:

```text
render only
render + return frames in memory
render + encode
render + encode + save to disk
```

### Workloads

Use a small number of representative cases:

```text
single camera x single frame
single camera x many frames
many cameras x many frames
```

### Record I/O details

For each run, record:

```text
image format
compression settings
disk type
filesystem
local disk vs network storage
synchronous vs asynchronous write policy
OS page cache behaviour, if known
```

### Report separately

Main CPU scaling report should say:

```text
CPU render benchmark, no disk I/O
```

End-to-end report should say:

```text
Export benchmark, including encoding and disk I/O
```

Do not combine these into one Amdahl number.

---

# Minimal first-pass suite

If time is limited, run this first.

## A. Single-thread resolution sweep

```text
threads: 1
tile: 32 px
AA: 2x2
I/O: off
scenes: fill-rate, geometry-heavy
resolutions: 512², 1024², 2048², 4096², 8192²
```

Approximate runs:

```text
2 scenes x 5 resolutions = 10 runs
```

## B. Thread scaling at three resolutions

Pick:

```text
small, medium, large
```

from the resolution sweep.

Laptop:

```text
2 scenes x 3 resolutions x 4 thread counts = 24 runs
```

Threadripper:

```text
2 scenes x 3 resolutions x 7 thread counts = 42 runs
```

## C. Tile / AA sensitivity

Use one realistic scene.

```text
resolutions: medium, large
threads: 1 and all physical cores
configs:
    16 tile, 2x2 AA
    32 tile, 1x1 AA
    32 tile, 2x2 AA
    32 tile, 4x4 AA
    64 tile, 2x2 AA
```

Approximate runs:

```text
2 resolutions x 2 thread counts x 5 configs = 20 runs
```

## D. Outer vs inner scheduling

Use one realistic batch scene.

```text
workloads:
    1 camera x 1 frame
    1 camera x many frames
    many cameras x 1 frame
    many cameras x many frames

modes:
    inner only
    outer only
    current/hybrid

threads:
    1 and all physical cores
```

Approximate runs:

```text
4 workloads x 3 modes x 2 thread counts = 24 runs
```

Total first-pass size:

```text
Laptop:        about 78 runs
Threadripper:  about 96 runs
```

An even smaller smoke test would be:

```text
1. Single-thread resolution sweep
2. Thread scaling at three resolutions
3. Tile/AA sensitivity at one large resolution
4. One outer-vs-inner batch benchmark
```

---

# Diagnostic interpretation guide

Use this table to interpret the first-pass results.

```text
Observation:
    small images scale badly

Likely cause:
    scheduling overhead or not enough tile work
```

```text
Observation:
    medium images scale well

Likely cause:
    enough work and good cache locality
```

```text
Observation:
    huge images scale badly

Likely cause:
    memory bandwidth, TLB pressure, framebuffer traffic, or shared cache pressure
```

```text
Observation:
    16 px tiles beat 32 px at high AA

Likely cause:
    subpixel tile working set is too large
```

```text
Observation:
    64 px tiles beat 32 px at low AA

Likely cause:
    scheduling or binning overhead dominates
```

```text
Observation:
    all workers have similar active time but speedup is poor

Likely cause:
    memory bandwidth or shared cache limit
```

```text
Observation:
    some workers finish much earlier than others

Likely cause:
    tile load imbalance
```

```text
Observation:
    outer-only beats inner-only for many frames/cameras

Likely cause:
    coarse-grained parallelism has lower overhead and better locality
```

```text
Observation:
    inner-only beats outer-only for 1 camera x 1 frame

Likely cause:
    no outer work is available, so tile/geometry threading is required
```

---

# Recommended plots

Generate these plots after the first-pass suite.

## Plot 1: Single-thread sensor scaling

```text
x-axis: output pixels or megapixels
y-axis: ns/subpixel sample
series: scene
```

Purpose:

```text
Find cache, TLB, or memory-footprint knees.
```

## Plot 2: Thread scaling by resolution

```text
x-axis: physical cores
y-axis: speedup
series: small, medium, large resolution
```

Purpose:

```text
Show how sensor size affects scaling.
```

## Plot 3: Parallel efficiency by resolution

```text
x-axis: physical cores
y-axis: parallel efficiency
series: small, medium, large resolution
```

Purpose:

```text
Show where extra cores stop being worthwhile.
```

## Plot 4: Efficiency heatmap

```text
x-axis: thread count
y-axis: resolution
cell value: parallel efficiency
```

Purpose:

```text
Find the good operating region.
```

## Plot 5: Tile / AA sensitivity

```text
x-axis: tile / AA configuration
y-axis: ns/subpixel sample
series: 1 core and all cores
```

Purpose:

```text
Determine whether dynamic tile sizing is useful.
```

## Plot 6: Outer vs inner scheduling

```text
x-axis: workload shape
y-axis: camera-frames per second
series: inner only, outer only, hybrid/current
```

Purpose:

```text
Determine which scheduling strategy works best for each workload type.
```

---

# Suggested headline reporting

For public or project-level reporting, separate results into four headline sections.

## 1. Single-frame latency, no disk I/O

Measures:

```text
How quickly can one camera/frame be rendered?
```

## 2. Batch throughput, no disk I/O

Measures:

```text
How many camera-frames per second can the renderer produce?
```

## 3. Batch throughput, frames returned in memory

Measures:

```text
User-facing in-memory processing throughput.
```

## 4. End-to-end export, including optional I/O

Measures:

```text
Full application performance when saving frames.
```

Make the distinction explicit:

```text
CPU scaling numbers exclude disk I/O unless stated otherwise.
Disk-output benchmarks are end-to-end application/export benchmarks.
```

---

# Final recommendations

Start with the minimal first-pass suite. It should reveal whether the main bottleneck is:

```text
not enough work
thread scheduling overhead
tile load imbalance
geometry stage scaling
tile raster scaling
cache / TLB pressure
memory bandwidth
nested parallelism policy
I/O or encoding
```

Do not optimise dynamic tile sizing until the first-pass suite shows which regime matters most.

A plausible tile policy to test later is:

```text
AA 1x1: 32 or 64 px tiles
AA 2x2: 32 px tiles
AA 4x4: 16 px tiles
```

But the data should decide.

The most important split is:

```text
single camera x single frame:
    inner geometry/tile scaling

many cameras x many frames:
    outer/hybrid batch throughput

I/O disabled:
    renderer scaling

I/O enabled:
    application/export scaling
```
