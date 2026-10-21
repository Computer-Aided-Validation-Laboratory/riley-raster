# Riley Testing Architecture & Test Suites

---

## Render reference data commit policy

For render test gold, commit only the smallest floating-point comparison data needed by the
Verification and Basic suites under `gold/verif/` and `gold/basic/`. Select
representative cases and frames; review numerical values and the corresponding
test before adding or changing a reference. Do not commit digitised gold images
(`.bmp` or other integer image formats), even when they are generated for
visual inspection. Do not commit any Full suite gold. Full suite references,
including shader-pipe references, are generated and kept locally for testing.
Generated previews and failure diagnostics are local artifacts as well.
The benchmark statistics in `gold/perf_stats_ref/` follow their separate
performance reference policy.

Never regenerate existing gold as a side effect of testing. A gold change
requires a targeted generator run and review of its numerical diff.

## 1. Quickstart Guide

The recommended testing workflow for Riley is:

```bash
# Step 1: Run the core test suites (fast, repository-packaged references)
zig build test-verif
zig build test-basic
.venv/bin/pytest src/riley/pytests/

# Step 2: Generate reference gold data for the Full suite
zig build gen-gold-full -Doptimize=ReleaseSafe

# Step 3: Run the exhaustive Full test suite
zig build test-full -Doptimize=ReleaseSafe
```

The basic and full gold suites continue after image-comparison failures:
each failed camera/frame/field writes actual, reference, and (when dimensions
match) difference images under `fails/`. All remaining cases and sub-suites
still run. The command exits unsuccessfully only after printing the total
comparison and other suite-failure counts. Gold files are never updated by a
test run. Rendering, setup, or artifact-write errors still abort the current
sub-suite, but the next sub-suite runs.
The focused verification suite likewise continues through its remaining
verification cases and reports failure at the end.

Shader-pipe coverage is registered in `src/tests/test_basic_shaderpipe.zig` and
`src/tests/test_full_shaderpipe.zig`; the public Cython boundary has focused
coverage in `src/riley/pytests/test_shaderpipe.py`. The basic suite renders
retained channels,
grey-to-emissivity mapping, IR band radiance, RGB/multichannel camera selection,
and a four-namespace resolver expression. The full suite renders Scene 0 with
texture plus Lambertian modulation across five element types and compares
tile-local, full global, and stripe buffers. Its references live only under
`gold/basic/shaderpipe_*` and `gold/full_shaderpipe/`. Only the selected Basic
FIMG comparison frames are committed; Full references and BMP previews remain
local. To regenerate only these new shader-pipe references during development,
run
`zig run src/gen_gold_shaderpipe.zig -lc`; ordinary tests never write gold.
The standard `gen-gold-full` command also generates the Full shader-pipe
references locally, without touching the committed Basic references.
Inspect both BMP previews and floating-point FIMG values before accepting
new references. Existing gold directories must not be regenerated for a
shader-pipe change.
The generated one-element bulge/tangent fixtures include deformation frames
whose in-plane Jacobian becomes zero or changes sign. Normal basic and full
comparisons cover only valid frames. Run `zig build test-full-badjac` to render
the excluded frames as warning-only diagnostics. It writes actual, reference,
and difference BMP/CSV files under `fails/*_full_badjac/`; changes in these
out-of-domain renders do not fail the test command.
After reviewing and approving distortion failures, run
`zig build gen-gold-failed-distortion -Doptimize=ReleaseSafe` to regenerate
only the distinct distortion/PSF and SSAA/pixel-map gold cases represented
in `fails/`. The generator writes both `.fimg` and `.bmp` references; it does
not select or modify unrelated full-suite cases.

> [!NOTE]
> Running `gen-gold-full` and `test-full` with `-Doptimize=ReleaseSafe` is strongly recommended for high throughput, generating and verifying thousands of cases in seconds while maintaining safety checks.

---

## 2. Core Repository Packaged Test Suites

Riley provides three core repository-packaged test suites intended for routine development, CI pipelines, and release verification:

| Suite Name | Execution Command | Source / Test Driver | Primary Role | Reference Data |
| :--- | :--- | :--- | :--- | :--- |
| **Verification Suite** | `zig build test-verif` | [`src/test_verif.zig`](file:///home/lloydf/riley-raster/src/test_verif.zig) | Mathematical validation against analytical Python oracles | `gold/verif/` |
| **Basic Test Suite** | `zig build test-basic` | [`src/test_basic.zig`](file:///home/lloydf/riley-raster/src/test_basic.zig) | Fast, comprehensive coverage of core rasteriser features | `gold/basic/` |
| **Bad-Jacobian Diagnostics** | `zig build test-full-badjac` | [`src/test_full_badjac.zig`](file:///home/lloydf/riley-raster/src/test_full_badjac.zig) | Warning-only renders and diffs for invalid one-element frames | Existing basic and full-hull gold |
| **Python Pytest Suite** | `.venv/bin/pytest src/riley/pytests/` | [`src/riley/pytests/`](file:///home/lloydf/riley-raster/src/riley/pytests) | Python/Cython API, mesh pipeline, Exodus conversion, demo parity | Integrated / `gold/` |

### Regenerating Reference Gold for Core Suites

```bash
# Regenerate reference data for the Basic test suite
zig build gen-gold-basic

# Regenerate reference data for the Analytic Verification suite
zig build gen-gold-verif-zig
python -m gengold.gengold_verif
```

---

## 3. Test Scenes Overview

The test suites leverage standardized benchmark scenes designed to exercise specific rasteriser subsystems:

### Scene 0: Multi-Body FE Interaction & Deformation
- **Geometry**: Two interacting FE surface meshes:
  - **Sphere**: $12\text{mm}$ diameter, positioned on the left in front ($Z = 0.0\text{ mm}$).
  - **Cylinder**: $10\text{mm}$ diameter, positioned on the right behind ($Z = -10.0\text{ mm}$).
  - **Arrangement**: $20\%$ horizontal overlap of the sphere diameter ($2.4\text{mm}$) along the $X$-axis.
- **Mesh Elements**: Full support across all 5 finite element formulations (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`).
- **Dynamics**: 2-frame sequence with simultaneous nonlinear spatial displacement and scalar temperature fields.
- **Camera View**: $160 \times 100\text{ px}$, $\text{SSAA} = 2$, oblique $+10^\circ$ yaw / $-10^\circ$ pitch orientation.
- **Primary Use**: [`test_full_shader.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_shader.zig) and [`test_full_texture.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_texture.zig).

### Scene 1: Single Cube Surface & Optical Models
- **Geometry**: Single undeformed cube surface mesh (`tri3`).
- **Shader**: Procedural sharp checkerboard shader (`.builtin = .checker`, $24 \times 24$ density) with uniform $50\%$ dynamic range grey background ($127.5$).
- **Camera View**: $128 \times 128\text{ px}$, $95\%$ sensor frame fill factor ($5\%$ border margin), viewed obliquely from above at $+5^\circ$ yaw / $-5^\circ$ pitch orientation to inspect front, top, and side faces simultaneously.
- **Primary Use**: [`test_full_dist_psf.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_dist_psf.zig) and [`test_full_ssaa_pxmap.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_ssaa_pxmap.zig).

### Scene 2: Multi-Sphere Cropping, Occlusion & Image Formats
- **Geometry**: Two interacting FE sphere surface meshes (`tri3`):
  - **Sphere 1 (Front Left)**: Positioned in the foreground at $X = -4.0\text{ mm}, Z = 0.0\text{ mm}$, cropped tightly by the left, top, and bottom edges of the camera sensor frame.
  - **Sphere 2 (Back Right)**: Positioned behind the foreground sphere ($X = +5.0\text{ mm}, Z = -1.02\text{ m}$ at nominal double camera distance), fully contained within the sensor frame with its top, right, and bottom edges visible while its inner edge is occluded by Sphere 1 ($25\%$ horizontal diameter overlap).
- **Background**: Uniform $50\%$ dynamic range grey ($127.5$).
- **Shaders & Modalities**:
  - **Monochrome Mode**: Sphere 1 with 5-transition checkerboard shader (`coord_scale = .{ 10.0, 10.0 }`); Sphere 2 with direct Catmull-Rom cubic texture map (`u8`/`u16`).
  - **RGB Mode**: Sphere 1 with blue/green checkerboard function shader; Sphere 2 with RGB texture map (`u8`/`u16`).
- **Primary Use**: [`test_full_tiling.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_tiling.zig) and [`test_full_image_output.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_image_output.zig).

### Scene 3: Multi-Shape FE Grid & Order Pairs
- **Geometry**: 16 finite element surface meshes arranged in 2 rows $\times$ 4 shape pairs:
  - **Shapes per Row**: 2x Cubes, 2x Spheres, 2x Cylinders, 2x Plate with hole (thickness $2.0\text{ mm}$).
  - **Pair Overlap**: Each pair overlaps $25\%$ row-wise (Y) and $75\%$ column-wise (X), with the front mesh positioned lower in front ($Z = 0.0\text{ mm}$) and the back mesh higher behind ($Z = -10.0\text{ mm}$). A thin $0.1\text{ mm}$ clearance separates adjacent pairs.
  - **Element Order Pairs**:
    - **Top Row**: Front mesh is low-order, back mesh is equivalent high-order (`tri3`/`tri6`, `quad4`/`quad8`).
    - **Bottom Row**: Front mesh is high-order, back mesh is equivalent low-order (`tri6`/`tri3`, `quad8`/`quad4`).
- **Dynamics**: 4 temporal frames (1 static baseline frame + 3 nonlinear deformation steps for all meshes).
- **Shaders**: 8 distinct 16-bit auto-scaled shaders cycled across the meshes:
  1. Nodal field interpolation (within-frame auto-scaling, u16)
  2. Procedural Checker function (u16)
  3. Direct Cubic Catmull-Rom texture sampling from u8 source (u16)
  4. Procedural Eggbox function (u16)
  5. Nodal field interpolation (over-frames auto-scaling, u16)
  6. Direct Linear texture sampling from u16 source (u16)
  7. Procedural Smooth Checker function on UV coordinates (u16)
  8. LUT-interpolated Catmull-Rom texture sampling from f64 source (u16)
- **Primary Use**: [`test_full_scene_camera_threads.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_scene_camera_threads.zig).

---

## 4. Verification Oracle Suite (`test_verif`)

- **Driver**: [`src/test_verif.zig`](file:///home/lloydf/riley-raster/src/test_verif.zig)
- **Generators**: [`src/gengold/gengold_verif.py`](file:///home/lloydf/riley-raster/src/gengold/gengold_verif.py) & [`src/gen_gold_verif.zig`](file:///home/lloydf/riley-raster/src/gen_gold_verif.zig)
- **Data Location**: `gold/verif/`

The **Verification Suite** checks independent analytic and numerical contracts rather than broad image-output stability:

1. **Newton-Raphson Shape Function Inversion**: Validates inverse element-solver recovery from known parent coordinates across linear and quadratic elements (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`) and verifies analytical Jacobian derivatives.
2. **Undistorted Silhouette Area and Centroid**: Compares projected silhouette area and centroid against Python-generated analytic references.
3. **Overlapping-Rabbit Depth Ordering**: Validates depth buffer ordering across four rear-surface separations:
   - One largest mesh-coordinate span,
   - $1/100$ span,
   - $1/1000$ span, and
   - Twice the active depth-buffer tolerance (constructed in inverse camera-depth space because Riley's depth-buffer comparison tolerance has inverse-depth units).
   Each case renders individual masks and both mesh submission orders, then verifies analytic front-over-rear composition pixel by pixel.
4. **Camera Distortion Oracles**: Validates camera-distortion round trips plus independent OpenCV/NumPy forward, inverse, stacked-model, SIMD, and Jacobian oracles.

### Execution and Precision Configuration

The suite is intentionally fixed to the production `f64` configuration with SIMD enabled (run in Debug mode without optimization flags):

```bash
zig build test-verif -Dprecision=f64 -Dsimd=on
```

The test command is Zig-only. It reads compact comparison data from `./gold/verif/`; it does not invoke Python or regenerate expected results during test runs.

### Regenerating Verification Comparison Data

Regenerate verification comparison data using the repository virtual environment:

```bash
zig build gen-gold-verif -Dprecision=f64 -Dsimd=on -Doptimize=ReleaseSafe
```

This runs the Zig input generator followed by `./src/gengold/gengold_verif.py`. The Python stage independently integrates the projected linear and quadratic element boundaries and writes compact analytic results beneath `./gold/verif/`.

> [!WARNING]
> Changes to verification comparison data should be reviewed together with the generator and numerical diff. Do not regenerate comparison data as part of `test-verif`.

---

## 5. Basic Test Suite (`test_basic`)

- **Driver**: [`src/test_basic.zig`](file:///home/lloydf/riley-raster/src/test_basic.zig)
- **Generator**: [`src/gen_gold_basic.zig`](file:///home/lloydf/riley-raster/src/gen_gold_basic.zig)
- **Data Location**: `gold/basic/`

The **Basic Suite** is the primary regression suite packaged with the repository, structured into three sub-suites:

### A. Single Element Deformation & Edge Curvature (`test_oneelem`)
- **Driver**: [`src/tests/test_basic_oneelem.zig`](file:///home/lloydf/riley-raster/src/tests/test_basic_oneelem.zig)
- **Coverage**: 10-frame continuous deformations (rotation, shear, stretch) and midside node bulging across `tri3`, `tri6`, `quad4`, `quad8`, and `quad9`, plus extreme inverted curvature edge cases.

### B. Multi-Mesh Occlusion & Shader Matrix (`test_twoshapes`)
- **Driver**: [`src/tests/test_basic_twoshapes.zig`](file:///home/lloydf/riley-raster/src/tests/test_basic_twoshapes.zig)
- **Coverage**: Multi-body occlusion between a sphere and a cube across 5 element types $\times$ 13 curated mono and RGB shaders.

### C. Complete Feature Zoo (`test_featurezoo`)
- **Driver**: [`src/tests/test_basic_featurezoo.zig`](file:///home/lloydf/riley-raster/src/tests/test_basic_featurezoo.zig)
- **Coverage**: 2 rows $\times$ 3 columns of FE simulation meshes rendered under 6 distinct camera/distortion/PSF configurations across 8 parallel thread and buffer architectures (`tile_local`, `global_subpx_full`, `global_subpx_stripe`, multi-group `in_order` and `offline`).

---

## 6. Full Test Suite (`test_full`)

- **Driver**: [`src/test_full.zig`](file:///home/lloydf/riley-raster/src/test_full.zig)
- **Generator**: [`src/gen_gold_full.zig`](file:///home/lloydf/riley-raster/src/gen_gold_full.zig)
- **Data Location**: `gold/full_*/` (generated locally; never committed)

The **Full Test Suite** is an exhaustive factorial regression suite replacing legacy benchmark and monolithic test runs. Gold reference images are generated locally on demand and verified across the Full sub-suites:

```bash
# Generate local references for all Full gold sub-suites
zig build gen-gold-full -Doptimize=ReleaseSafe

# Run the Full suite against generated gold
zig build test-full -Doptimize=ReleaseSafe
```

### Sub-Suite 1: Full Shader Suite (`test_full_shader`)
- **Driver**: [`src/tests/test_full_shader.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_shader.zig)
- **Scene**: Scene 0 (Sphere + Cylinder, 5 element types: `tri3`, `tri6`, `quad4`, `quad8`, `quad9`)
- **Coverage** (1,260 cases + 252 `tri3opt` parity checks):
  - **Nodal Shaders**: Mono & RGB scalar/vector fields and scaling strategies (`none`, `auto` within frames, `auto` over frames). Normal mode is configured on the mesh.
  - **Texture Shaders**: Mono & RGB texture sampling across `u8`, `u16`, and `f64` precisions. Normal mode is configured on the mesh.
  - **Procedural Function Shaders**: 9 built-in functions (`constant`, `linear`, `quadratic`, `sinusoidal`, `sinusoidal_approx`, `checker`, `checker_smooth`, `lambertian_normal_z`, `eggbox`) evaluated across 4 coordinate spaces (`parametric`, `uv`, `world_reference`, `world_deformed`). Lambertian lighting uses the mesh normal mode.
  - **`tri3opt` Parity**: Verifies that the fixed-point subpixel snapped fast triangle pipeline matches standard `tri3` floating-point reference renders within tight tolerances.

### Sub-Suite 2: Full Texture Sampling Suite (`test_full_texture`)
- **Driver**: [`src/tests/test_full_texture.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_texture.zig)
- **Scene**: Scene 0 (Sphere + Cylinder, 5 element types)
- **Coverage** (600 cases):
  - **Data Types & Channels**: `u8`, `u16`, `f64` in single-channel mono and 3-channel RGB.
  - **Filter Kernels**: Direct Bilinear, Direct Catmull-Rom Cubic, and LUT-Interpolated Catmull-Rom Cubic.
  - **Edge Addressing Modes**: `clamp`, `mirror`, `repeat`, and `border`.

### Sub-Suite 3: Full Distortion & PSF Suite (`test_full_dist_psf`)
- **Driver**: [`src/tests/test_full_dist_psf.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_dist_psf.zig)
- **Scene**: Scene 1 (Cube `tri3`, high-density checkerboard, grey background)
- **Coverage** (240 test cases):
  - **SSAA Levels**: $1$ (direct pixel centers) and $4$ ($16$ subpixel samples/pixel).
  - **Distortion Models (10)**: Baseline `none`, light barrel/pincushion ($k_1 = \pm 1000.0$), extreme barrel/pincushion ($k_1 = \pm 2500.0, k_2 = 1.0\times 10^7$) with Brown-Conrady and Brown-Conrady-Ext, and quadratic polynomial distortion combinations.

The focused verification suite keeps two distortion checks separate:
`distortion_roundtrip` checks Riley's internal forward/inverse consistency,
while `distortion_oracle` compares scalar and SIMD evaluation, inversion, and
analytic Jacobians with compact OpenCV/NumPy gold data in `gold/verif/`. Oracle
tolerances are centralized in `src/dev_support/testconfig.zig`; they do not
change the production Newton solver tolerances.
  - **Point Spread Functions (4)**: Baseline pixel box (`off`), separable Gaussian ($\sigma = 1.5\text{ px}$), non-separable Gaussian ($\sigma = 1.5\text{ px}$), and anisotropic Gaussian ($\sigma_x = 1.5\text{ px}, \sigma_y = 0.1\text{ px}$).
  - **Buffer Architectures (3)**: Verified for identical bit-accurate output across `tile_local`, `global_subpx_full`, and `global_subpx_stripe`.

### Sub-Suite 4: Full SSAA & Pixel Center Mapping Suite (`test_full_ssaa_pxmap`)
- **Driver**: [`src/tests/test_full_ssaa_pxmap.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_ssaa_pxmap.zig)
- **Scene**: Scene 1 (Cube `tri3`)
- **Coverage** (72 cases):
  - **SSAA Levels**: $1, 2, 3, 4$ ($1, 4, 9, 16$ subpixels per pixel).
  - **Subpixel Center Mapping Engines**: `full_in_mem` (precomputed global grid) and `per_tile` (on-the-fly tile evaluation).
  - **Distortion Models**: Brown-Conrady, Brown-Conrady-Ext, and Brown-Conrady-Polynomial.
  - **PSFs & Halos**: Pixel box and Gaussian halo filtering ($\sigma = 1.5\text{ px}$, $5\text{ px}$ halo margin).

### Sub-Suite 5: Full Hull Geometry Suite (`test_full_hull`)
- **Driver**: [`src/tests/test_full_hull.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_hull.zig)
- **Scenes**: Single element scenes and continuous deformation sequences across all 5 element types (`tri3`, `tri6`, `quad4`, `quad8`, `quad9`).
- **Coverage**:
  - $128 \times 128\text{ px}$, $\text{SSAA} = 2$, procedural checkerboard shader.
  - Exact bounding hull rasterisation compared against gold references and deformation delta non-zero assertions.

### Sub-Suite 6: Full Tiling, Buffers & Threading Suite (`test_full_tiling`)
- **Driver**: [`src/tests/test_full_tiling.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_tiling.zig)
- **Scene**: Scene 2 (Two overlapping/occluded spheres)
- **Coverage**:
  - **Resolutions (4)**: Non-power-of-two and prime dimensions ($31 \times 19$, $65 \times 47$, $161 \times 103$, $401 \times 251$).
  - **SSAA Levels**: $1$ and $4$.
  - **Tile Dimensions**: $16 \times 16$, $32 \times 32$, $64 \times 64$.
  - **Buffer Strategies**: `tile_local`, `global_subpx_full`, `global_subpx_stripe`.
  - **Thread Configurations**: $1$, $2$, and $4$ worker threads.
  - **Invariance Invariant**: Asserts bit-identical rendered images regardless of tile size, buffer mode, or worker count.

### Sub-Suite 7: Full Scene, Cameras & Threads Suite (`test_full_scene_camera_threads`)
- **Driver**: [`src/tests/test_full_scene_camera_threads.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_scene_camera_threads.zig)
- **Scene**: Scene 3 (16 FE meshes in 2 rows $\times$ 4 shape pairs, 4 deformation frames, 8 16-bit shaders)
- **Coverage**:
  - **Cameras (8)**:
    - `cam0`: Centered face-on ($256 \times 256$, $\text{SSAA} = 1$).
    - `cam1`: Centered face-on ($256 \times 256$, $\text{SSAA} = 2$).
    - `cam2`: Cropped ($128 \times 128$, $\text{SSAA} = 2$, Anisotropic Gaussian PSF $\sigma_x = 1.2, \sigma_y = 0.2$).
    - `cam3`: Cropped ($128 \times 128$, $\text{SSAA} = 2$, Brown-Conrady Extreme distortion).
    - `cam4`: Cropped ($128 \times 128$, $\text{SSAA} = 2$, Brown-Conrady Ext + Separable Gaussian PSF $\sigma = 1.5$).
    - `cam5`: Stereo Left $+30^\circ$ yaw ($256 \times 256$, $\text{SSAA} = 2$).
    - `cam6`: Stereo Right $-30^\circ$ yaw ($256 \times 256$, $\text{SSAA} = 2$).
    - `cam7`: Oblique $+20^\circ$ yaw / $+20^\circ$ pitch ($256 \times 256$, $\text{SSAA} = 2$).
  - **Execution Configurations**: Evaluated across tile sizes ($16 \times 16, 32 \times 32, 64 \times 64$), buffer modes (`tile_local`, `global_subpx_full`, `global_subpx_stripe`), and thread counts ($1, 2, 4$ threads).
  - **Invariance Invariant**: Asserts identical bit-accurate output matching single-threaded reference gold images across all configurations.

### Sub-Suite 8: Full Image Output & Factorial Export Suite (`test_full_image_output`)
- **Driver**: [`src/tests/test_full_image_output.zig`](file:///home/lloydf/riley-raster/src/tests/test_full_image_output.zig)
- **Scene**: Scene 2 (Mono/RGB, u8/u16, blue/green RGB checker shader on front sphere and colored texture map on back sphere, 1 undeformed frame).
- **Camera**: $160 \times 100\text{ px}$, face-on, $\text{SSAA} = 2$, auto-zoomed with $1\%$ border margin (`fill_fov = 0.99`).
- **Factorial Parameter Coverage**:
  - **Save Strategies (4)**: `.memory`, `.disk`, `.both`, `.none`.
  - **Output Modes (3)**: `.grey` (1 channel luminance/monochrome), `.rgb` (3 channel RGB), `.multifield` (raw pass-through).
  - **File Formats (4)**: `.fimg` (raw floating point), `.csv` (comma-delimited numerical matrices), `.bmp` (8-bit and 16-bit bitmaps), `.tiff` (8-bit and 16-bit tagged images).
  - **Dynamic Range Scaling**: `.none`, `.auto`, explicit fixed ranges (`.fixed = .{ 0.0, 255.0 }`), and fractional percentile boundaries (`.frac = .{ 0.05, 0.95 }`).
  - **Diagnostic Reporting Modes**: `.off`, `.bench` (timing breakdown metrics), `.full_stats` (per-stage hardware and pipeline statistics).
  - **Output Verification**: Asserts bit-level equivalence between memory buffer captures, reference gold data, and reloaded on-disk export images.

### Automated Failure Diagnostics
When any case in the Full Test Suite encounters a regression or discrepancy exceeding tolerance:
- Failure artifacts are saved to `./fails/TEST_SUITE/TEST_CASE/`.
- Saved artifacts include:
  1. `*_actual.bmp` & `*_actual.csv`: The current render output.
  2. `*_gold.bmp` & `*_gold.csv`: The reference gold image.
  3. `*_diff.bmp`: A high-contrast visual difference map highlighting failing pixel locations.

---

## 7. Python & Cython Test Suite (`pytest`)

- **Driver**: `.venv/bin/pytest src/riley/pytests/`
- **Location**: [`src/riley/pytests/`](file:///home/lloydf/riley-raster/src/riley/pytests)

The **Python Test Suite** provides 640+ automated test cases covering:
1. **Mesh Pipeline & Conversions**: Element connectivity verification, quadratic-to-linear order reduction, surface extraction, and polygon triangulation.
2. **File I/O & Exodus Pipeline**: Multi-block Exodus II `.e` and CSV file reading/writing.
3. **Texture & UV Tools**: Image loading/saving (BMP, TIFF) and centered planar UV projection.
4. **End-to-End Demo Parity**: Verification that Python demos produce identical pixel output to the corresponding Zig demo binaries.

### Running Pytests

Run the full packaged Python test suite with:

```bash
python -m pytest --pyargs riley.pytests -s
```

or via the CLI wrapper:

```bash
python -m riley test
```

### Python-to-Zig Demo Parity Checks

To compare Python bindings against Zig demo outputs specifically:

```bash
python -m pytest --pyargs riley.pytests.test_riley -s
```

To force a fresh Zig render instead of reusing cached demo BMPs:

```bash
RILEY_FORCE_ZIG_RENDER=1 python -m pytest --pyargs riley.pytests.test_riley -s
```

Individual packaged Python demos can also be run directly:

```bash
python -m riley demo0_quickstart
python -m riley demo1_sphere
python -m riley demo2a_rabbits_mono
python -m riley demo2b_rabbits_rgb
python -m riley demo2c_rabbits_fields
python -m riley demo3_dicuq
python -m riley demo3_dicuq_from_exodus
python -m riley demo4_stereocal
python -m riley demo5_cameramodels
python -m riley demo6_featurezoo
```

Python demo output is written to `Path.cwd() / "out_riley_py" / "<demo-name>"`.

The Zig demos use the same numbered names and ordering:
- The rabbit demos (`demo2a`, `demo2b`, `demo2c`) share mesh loading, shader setup, and layout in `src/demo_rabbits_common.zig`; the Python variants share `demo_rabbits_common.py`.
- Rabbit parity checks require greater than 10% foreground coverage in every render, ensuring blank or unrendered frames cannot pass verification.
- Demos that clear previous output share `src/demo_common.zig` (`demo_common.resetOutputDir`). This removes the named demo output directory and recreates it cleanly.
- `demo5_cameramodels` renders all 6 distortion families with pixel-box, Gaussian (separable/non-separable), aligned anisotropic Gaussian, and rotated anisotropic Gaussian PSFs across all 3 buffer modes (90 comparison images per run under `<distortion>/<psf>/<buffer-mode>/`). Parity checks require the entire matrix to match.
